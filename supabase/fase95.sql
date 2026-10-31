-- ============================================================
-- FAZENDINHA — Fase 95 (o depósito do Construir e a troca de nome por diamantes), só o que mudou.
-- Para o banco que já está no ar (com a fase 94): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 94 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_invasao_lote')) then
    raise exception 'Rode o fase94.sql antes deste (a fase 94 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 95: o depósito (ideia do Francisco). No Construir, o "Guardar" de antes na verdade vendia: tirava o
-- item e devolvia metade do que foi pago. Agora são dois botões:
--   Guardar: o item sai da fazenda inteiro e vai para o depósito (o estoque da oficina e o que tinha no
--   baú voltam para o celeiro, como antes). Na barra do Construir aparece quantos você tem guardados.
--   Colocar um item que tem no depósito usa o guardado, de graça (os limites de sempre continuam valendo).
--   Vender: o de sempre (fazenda_demolir), metade do que você pagou.
-- Para reorganizar a fazenda: guarde tudo o que quer mudar de lugar e vá colocando com calma.
-- Junto, a troca de nome: no perfil, por 30 diamantes (as regras do apelido de sempre, de 2 a 20 letras e
-- sem palavrão).
-- ------------------------------------------------------------
create table if not exists public.fazenda_deposito (
  id          bigserial primary key,
  jogador_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  tipo        text not null references public.fazenda_itens(id),
  pago        int not null default 0,
  guardado_em timestamptz not null default now()
);
create index if not exists fazenda_deposito_jogador on public.fazenda_deposito (jogador_id, tipo);
alter table public.fazenda_deposito enable row level security;
revoke all on public.fazenda_deposito from anon, authenticated;

-- quantos de cada item estão no depósito: {"painel_solar": 3, "lampiao": 1}
create or replace function public.fazenda_deposito_mapa(p_jogador uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(tipo, n), '{}'::jsonb) from (
    select tipo, count(*) as n from fazenda_deposito where jogador_id = p_jogador group by tipo) x;
$$;

-- o depósito (o jogo pede ao abrir o Construir)
create or replace function public.fazenda_deposito(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  return jsonb_build_object('deposito', fazenda_deposito_mapa(fazenda_auth_ler(p_token)));
end;
$$;

-- Guardar: tira o item da fazenda e leva para o depósito, sem perder nada (o canteiro só sai, como antes)
create or replace function public.fazenda_guardar(p_token text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_tipo text;
  v_pago int;
  c      record;
begin
  -- canteiro: só sai vazio ou arado (planta crescendo, colha ou limpe antes)
  select * into c from fazenda_canteiros where jogador_id = v_id and x = p_x and y = p_y for update;
  if found then
    if c.estado = 'plantado' then raise exception 'canteiro_ocupado'; end if;
    delete from fazenda_canteiros where jogador_id = v_id and posicao = c.posicao;
    return jsonb_build_object('ok', true, 'canteiro', true, 'deposito', fazenda_deposito_mapa(v_id));
  end if;

  -- fase 45: cercado com bicho dentro não sai (o bicho não tem mais para onde ir)
  if exists (select 1 from fazenda_construcoes k join fazenda_animais a on a.jogador_id = k.jogador_id and 'cercado_' || a.tipo = k.tipo
              where k.jogador_id = v_id and k.x = p_x and k.y = p_y) then   -- (k: c é o registro do canteiro)
    raise exception 'cercado_com_bichos';
  end if;

  -- oficina: o estoque (ingredientes) e os produtos prontos voltam para o celeiro
  perform fazenda_oficinas_andar(v_id);
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  select v_id, x.item, sum(x.qtd)::int from (
    select e.key as item, e.value::int * (oc.estoque + case when oc.iniciado_em is null then 0 else 1 end) as qtd
      from fazenda_construcoes oc join fazenda_itens oi on oi.id = oc.tipo, jsonb_each_text(oi.entradas) e
     where oc.jogador_id = v_id and oc.x = p_x and oc.y = p_y and oi.entradas is not null
    union all
    select oi.produz, oc.prontos
      from fazenda_construcoes oc join fazenda_itens oi on oi.id = oc.tipo
     where oc.jogador_id = v_id and oc.x = p_x and oc.y = p_y and oi.entradas is not null and oc.prontos > 0
  ) x where x.qtd > 0 group by x.item
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  -- fase 39: o que estava guardado no baú ou já tinha chegado na oficina volta para o celeiro
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  select v_id, x.item, sum(x.quantidade)::int from (
    select item, quantidade from fazenda_bau_itens where jogador_id = v_id and x = p_x and y = p_y
    union all
    select item, quantidade from fazenda_oficina_itens where jogador_id = v_id and x = p_x and y = p_y
  ) x where x.quantidade > 0 group by x.item
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  delete from fazenda_bau_itens where jogador_id = v_id and x = p_x and y = p_y;
  delete from fazenda_oficina_itens where jogador_id = v_id and x = p_x and y = p_y;

  delete from fazenda_construcoes where jogador_id = v_id and x = p_x and y = p_y
  returning tipo, pago into v_tipo, v_pago;
  if v_tipo is null then raise exception 'item_invalido'; end if;
  -- vai inteiro para o depósito (com o que foi pago, para o Vender de depois devolver a metade disso)
  insert into fazenda_deposito (jogador_id, tipo, pago)
  values (v_id, v_tipo, coalesce(v_pago, (select custo from fazenda_itens where id = v_tipo)));
  return jsonb_build_object('ok', true, 'tipo', v_tipo, 'deposito', fazenda_deposito_mapa(v_id));
end;
$$;

-- Colocar: igual a antes, mas o que tem guardado no depósito sai primeiro, de graça
create or replace function public.fazenda_construir(p_token text, p_tipo text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id  uuid := fazenda_auth(p_token);
  j     record;
  i     record;
  v_pos int;
  v_custo int;
  v_dep record;   -- fase 95
begin
  select * into j from fazenda_jogadores where id = v_id for update;

  -- canteiro: não é item da loja, é um lugar de plantar (limite pelo nível e terrenos)
  if p_tipo = 'canteiro' then
    if (select count(*) from fazenda_canteiros where jogador_id = v_id)
       >= fazenda_limite_canteiros(fazenda_nivel_de(j.xp, j.nivel_trava), fazenda_terrenos(j.zonas, j.direita)) then
      raise exception 'limite_canteiros';
    end if;
    perform fazenda_checar_lugar(v_id, fazenda_terrenos(j.zonas, j.direita), p_x, p_y, 1, 1);
    select min(g) into v_pos from generate_series(0, 299) g   -- fase 56: eram 0..99
     where not exists (select 1 from fazenda_canteiros where jogador_id = v_id and posicao = g);
    if v_pos is null then raise exception 'limite_canteiros'; end if;
    -- fase 70: canteiro novo espera os 8 min para dar XP de colheita (desmanchar e fazer de novo zerava)
    insert into fazenda_canteiros (jogador_id, posicao, estado, x, y, xp_em) values (v_id, v_pos, 'vazio', p_x, p_y, now());
    return jsonb_build_object('estado', fazenda_estado(v_id), 'posicao', v_pos);
  end if;

  select * into i from fazenda_itens where id = p_tipo;
  if not found then raise exception 'item_invalido'; end if;
  if fazenda_nivel_de(j.xp, j.nivel_trava) < i.nivel_min then raise exception 'nivel_insuficiente'; end if;
  perform fazenda_checar_lugar(v_id, fazenda_terrenos(j.zonas, j.direita), p_x, p_y, i.largura, i.altura);
  -- fase 73: o que é da praia só vai na areia do Litoral (y 32 a 36)
  if i.categoria = 'praia' and not (p_y >= 32 and p_y + i.altura - 1 <= 36) then raise exception 'so_na_areia'; end if;
  if i.limite is not null   -- fase 57: painel solar e turbina sobem com o nível
     and (select count(*) from fazenda_construcoes where jogador_id = v_id and tipo = i.id)
         >= fazenda_limite_maquina(i.id, i.limite, fazenda_nivel_de(j.xp, j.nivel_trava)) then
    raise exception 'limite_maquina';
  end if;
  -- itens por terreno (amoreira): mais terreno, mais pés (igual a maxItem em fazenda.js); fase 47: no
  -- pomar, cada fruta tem 1 pé e +1 a cada 2 terrenos (até 4); quem já passou fica com as que tem
  if i.por_terreno is not null
     and (select count(*) from fazenda_construcoes c join fazenda_itens k on k.id = c.tipo
           where c.jogador_id = v_id and (c.tipo = i.id or (i.grupo is not null and k.grupo = i.grupo)))
         >= (case when i.categoria = 'pomar'   -- fase 57: + os pés da melhoria "Mais pés de fruta"
                  then i.por_terreno * (1 + (j.zonas + j.direita) / 2) + fazenda_melhoria(v_id, 'pes')::int   -- (fase 78: + os da direita)
                  else i.por_terreno * (1 + j.zonas + j.direita) end) then
    raise exception 'limite_terreno';
  end if;
  if (select count(*) from fazenda_construcoes where jogador_id = v_id) >= fazenda_max_construcoes(fazenda_terrenos(j.zonas, j.direita)) then
    raise exception 'limite_construcoes';
  end if;
  -- fase 95: tem um igual guardado no depósito? sai dele, de graça (e guarda o que foi pago na época)
  select id, pago into v_dep from fazenda_deposito where jogador_id = v_id and tipo = i.id order by id limit 1 for update;
  if v_dep.id is not null then
    delete from fazenda_deposito where id = v_dep.id;
    if i.categoria = 'energia' then
      perform fazenda_energia_atualizar(v_id);
      update fazenda_jogadores set energia_em = now() where id = v_id;
    end if;
    insert into fazenda_construcoes (jogador_id, x, y, tipo, colhido_em, pago) values (v_id, p_x, p_y, i.id, now(), v_dep.pago);
    return jsonb_build_object('estado', fazenda_estado(v_id), 'do_deposito', true, 'deposito', fazenda_deposito_mapa(v_id));
  end if;
  -- fase 45: quem já tinha o bicho antes do cercado obrigatório ganha o primeiro cercado dele
  v_custo := case when i.efeito = 'cercado' and substr(i.id, 9) = any(coalesce(j.cercado_gratis, '{}')) then 0 else i.custo end;
  if j.moedas < v_custo then raise exception 'moedas_insuficientes'; end if;
  -- máquina elétrica nova: fecha a conta da energia antes (ela não gera pelo tempo de antes)
  if i.categoria = 'energia' then
    perform fazenda_energia_atualizar(v_id);
    update fazenda_jogadores set energia_em = now() where id = v_id;   -- (fase 46: a conta começa agora)
  end if;
  update fazenda_jogadores
     set moedas = moedas - v_custo,
         cercado_gratis = case when i.efeito = 'cercado' then array_remove(cercado_gratis, substr(i.id, 9)) else cercado_gratis end
   where id = v_id;
  -- fase 72: guarda o que pagou (desmanchar devolve a metade disso, não do preço de hoje)
  insert into fazenda_construcoes (jogador_id, x, y, tipo, colhido_em, pago) values (v_id, p_x, p_y, i.id, now(), v_custo);
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- a troca de nome: quanto custa (em diamantes)
create or replace function public.fazenda_apelido_preco()
returns int language sql immutable as $$ select 30 $$;

create or replace function public.fazenda_trocar_apelido(p_token text, p_apelido text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_preco int := fazenda_apelido_preco();
  v_novo  text := btrim(regexp_replace(coalesce(p_apelido, ''), '\s+', ' ', 'g'));
  j       record;
begin
  if char_length(v_novo) not between 2 and 20 then raise exception 'apelido_invalido'; end if;
  if fazenda_chat_palavrao(v_novo) then raise exception 'apelido_palavrao'; end if;
  select * into j from fazenda_jogadores where id = v_id for update;
  if j.apelido = v_novo then raise exception 'apelido_igual'; end if;
  if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
  update fazenda_jogadores set apelido = v_novo, diamantes = diamantes - v_preco where id = v_id;
  return jsonb_build_object('apelido', v_novo, 'pagou', v_preco, 'diamantes', j.diamantes - v_preco);
end;
$$;

-- permissões
revoke execute on function
  public.fazenda_deposito_mapa(uuid),
  public.fazenda_apelido_preco()
from public, anon, authenticated;

grant execute on function
  public.fazenda_deposito(text),
  public.fazenda_guardar(text, int, int),
  public.fazenda_construir(text, text, int, int),
  public.fazenda_trocar_apelido(text, text)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache)
select public.fazenda_cache_montar();

-- conferência: a tabela, as 3 funções novas e o Construir que usa o depósito
select (select count(*) from information_schema.tables where table_schema = 'public' and table_name = 'fazenda_deposito') as tabela_deposito,
       (select count(*) from pg_proc where proname in ('fazenda_deposito', 'fazenda_guardar', 'fazenda_trocar_apelido')) as funcoes_novas,
       (select prosrc like '%fazenda_deposito%' from pg_proc where proname = 'fazenda_construir') as construir_usa_deposito,
       public.fazenda_apelido_preco() as preco_do_nome_em_diamantes;
