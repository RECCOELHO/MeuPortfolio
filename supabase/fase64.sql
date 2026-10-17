-- ============================================================
-- FAZENDINHA — Fase 64 (o bug do gerador a biomassa e os prêmios do evento), só o que mudou.
-- Para o banco que já está no ar (com a fase 63): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- O gerador a biomassa: ligar queima o primeiro milho na hora só uma vez a cada 30 min (ligar e
-- desligar seguido virava 25 ⚡ a cada toque). O milho queimado na hora paga a primeira meia hora.
create or replace function public.fazenda_gerador(p_token text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  r    record;
begin
  select c.iniciado_em, c.colhido_em, i.efeito into r
    from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y
     for update of c;
  if not found or r.efeito is distinct from 'biomassa' then raise exception 'item_invalido'; end if;
  perform fazenda_energia_atualizar(v_id);   -- fecha a conta do que já passou
  if r.iniciado_em is not null then
    update fazenda_construcoes set iniciado_em = null where jogador_id = v_id and x = p_x and y = p_y;
    return jsonb_build_object('ligado', false, 'estado', fazenda_estado(v_id));
  end if;
  if coalesce((select quantidade from fazenda_celeiro where jogador_id = v_id and item = 'milho'), 0)
     - coalesce((select quantidade from fazenda_reservas where jogador_id = v_id and item = 'milho'), 0) < 1 then
    raise exception 'sem_milho';
  end if;
  if r.colhido_em is null or r.colhido_em <= now() - interval '30 minutes' then
    update fazenda_celeiro set quantidade = quantidade - 1 where jogador_id = v_id and item = 'milho';
    update fazenda_jogadores set energia = least(energia + 25, fazenda_capacidade(v_id)) where id = v_id;
    update fazenda_construcoes set iniciado_em = now() + interval '30 minutes', colhido_em = now()
     where jogador_id = v_id and x = p_x and y = p_y;
  else
    -- (queimou na hora há menos de 30 min: liga sem queimar; o primeiro milho sai daqui a 30 min)
    update fazenda_construcoes set iniciado_em = now() where jogador_id = v_id and x = p_x and y = p_y;
  end if;
  return jsonb_build_object('ligado', true, 'estado', fazenda_estado(v_id));
end;
$$;

-- O evento da semana: diamantes pela metade (30, 18 e 10) e o item com 50% de chance para cada lugar
-- do pódio (o 1º, o item da categoria; o 2º e o 3º fora do ranking, um material do píer sorteado).
create or replace function public.fazenda_evento_regras()
returns jsonb language sql immutable as $$
  select '{"fecha": "sexta às 22h", "diamantes": [30, 18, 10], "chance_item": 50, "convite_nivel": 5,
           "categorias": [
             {"id": "ranking",  "nome": "Ranking da semana",  "conta": "XP ganho na semana",            "itens": ["trofeu_ouro", "trofeu_prata", "trofeu_bronze"]},
             {"id": "niveis",   "nome": "Mais níveis",        "conta": "níveis subidos na semana",      "itens": ["ampulheta_dourada"]},
             {"id": "moedas",   "nome": "Mais moedas",        "conta": "moedas ganhas na semana",       "itens": ["cofrinho_ouro"]},
             {"id": "vendeu",   "nome": "Vendeu na barraca",  "conta": "moedas em vendas na feira",     "itens": ["balanca_ouro"]},
             {"id": "comprou",  "nome": "Comprou na barraca", "conta": "moedas em compras na feira",    "itens": ["sacola_ouro"]},
             {"id": "convites", "nome": "Mais convites",      "conta": "amigos convidados que chegaram ao nível 5", "itens": ["leme_dourado"]}]}'::jsonb;
$$;

create or replace function public.fazenda_semana_fechar()
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_ini  timestamptz := fazenda_semana_inicio(now());
  v_reg  jsonb := fazenda_evento_regras();
  s      record;
  r      record;
  v_dia  int;
  v_item text;
  v_sorte int;   -- fase 64
begin
  if exists (select 1 from fazenda_semanas where inicio = v_ini) then return; end if;
  perform pg_advisory_xact_lock(hashtext('fazenda_semana'));
  if exists (select 1 from fazenda_semanas where inicio = v_ini) then return; end if;   -- outra chamada fechou antes
  -- a última semana aberta (normalmente a que acabou agora)
  select * into s from fazenda_semanas where fechada_em is null order by inicio desc limit 1;
  if found then
    for r in select * from fazenda_semana_posicoes(s.inicio, s.aberta_em, now()) p where p.posicao <= 3 loop
      v_dia := (v_reg->'diamantes'->>(r.posicao::int - 1))::int;
      select c->'itens'->>(r.posicao::int - 1) into v_item from jsonb_array_elements(v_reg->'categorias') c where c->>'id' = r.categoria;
      -- fase 64: o item vem com 50% de chance; sem item próprio do lugar, um material do píer (pesos do mercador)
      if random() * 100 >= coalesce((v_reg->>'chance_item')::int, 100) then
        v_item := null;
      elsif v_item is null then
        v_sorte := floor(random() * 100)::int;   -- (um sorteio só: random() no where sorteava de novo a cada linha)
        select y.r->>'id' into v_item
          from (select x.r, sum((x.r->>'peso')::int) over (order by x.ord) as acum
                  from jsonb_array_elements(fazenda_raros()) with ordinality as x(r, ord)) y
         where y.acum > v_sorte
         order by y.acum limit 1;
      end if;
      insert into fazenda_semana_premios (semana, categoria, posicao, jogador_id, valor, diamantes, item)
      values (s.inicio, r.categoria, r.posicao, r.jogador_id, r.valor, v_dia, v_item);
      update fazenda_jogadores set diamantes = diamantes + v_dia where id = r.jogador_id;
      if v_item is not null then
        insert into fazenda_celeiro (jogador_id, item, quantidade) values (r.jogador_id, v_item, 1)
        on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
      end if;
    end loop;
    update fazenda_semanas set fechada_em = now() where fechada_em is null;
  end if;
  -- a foto do começo da semana nova
  insert into fazenda_semana_base (jogador_id, semana, xp, moedas_ganhas)
  select id, v_ini, xp, moedas_ganhas from fazenda_jogadores
  on conflict (jogador_id) do update set semana = excluded.semana, xp = excluded.xp, moedas_ganhas = excluded.moedas_ganhas;
  insert into fazenda_semanas (inicio) values (v_ini);
end;
$$;

-- conferência: deve aparecer "Evento: 30/18/10 diamantes, item com 50% de chance; gerador corrigido"
select 'Evento: ' || (r->'diamantes'->>0) || '/' || (r->'diamantes'->>1) || '/' || (r->'diamantes'->>2)
    || ' diamantes, item com ' || (r->>'chance_item') || '% de chance; gerador '
    || case when pg_get_functiondef('public.fazenda_gerador(text, int, int)'::regprocedure) like '%30 minutes%' then 'corrigido' else 'ANTIGO' end as ok
  from (select public.fazenda_evento_regras() as r) x;
