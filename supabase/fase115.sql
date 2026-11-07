-- ============================================================
-- FAZENDINHA — Fase 115 (o Dia dos Namorados da Fazendinha, todo 11/11: a flor Viih, o recado do ano e os
-- enfeites do dia), só o que mudou.
-- Para o banco que já está no ar (com a fase 114): Supabase > SQL Editor > colar este arquivo > Run.
-- Rode ANTES do merge do PR.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 114 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not exists (select 1 from pg_proc where proname = 'fazenda_recado_lido') then
    raise exception 'Rode o fase114.sql antes deste. Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 115: o Dia dos Namorados da Fazendinha (11/11, todo ano).
-- • A flor Viih (desenhos do Jessé): planta só no dia 11/11 (horário de Brasília), até 11 por jogador por
--   ano; cresce em 1h11; cada canteiro dá 1 flor (sem bônus). No celeiro, cada Viih que você colheu vira
--   1 diamante (fazenda_flor_vender); a que veio da feira não vira. Na feira, vende por ouro. O "Vender
--   tudo" não leva, ninguém pega do vizinho e os ajudantes só plantam no dia.
-- • O estado avisa quando é o dia (dia_especial) e quantas ainda dá para plantar (viih_restam); o jogo faz
--   o resto: pétalas caindo na fazenda, o coração do farol no mar e a constelação no céu do alto-mar.
-- • Recados que chegam todo ano no mesmo dia (fazenda_recados_anuais, mandados pelo SQL Editor): no dia, o
--   recado entra na caixa do jogador (fase 114), com os diamantes.
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------
-- fase 115: a flor de um dia só (so_dia = 'MM-DD'): a Viih planta só no 11/11, 11 por jogador por ano
alter table public.fazenda_culturas add column if not exists so_dia text;
create table if not exists public.fazenda_viih_plantio (
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  ano        int not null,
  plantadas  int not null default 0,
  primary key (jogador_id, ano)
);
alter table public.fazenda_viih_plantio enable row level security;
revoke all on public.fazenda_viih_plantio from anon, authenticated;
-- fase 115: recados que chegam todo ano no mesmo dia (mes_dia = 'MM-DD'), para um jogador só
create table if not exists public.fazenda_recados_anuais (
  id         bigint generated always as identity primary key,
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  mes_dia    text not null,
  titulo     text not null,
  texto      text not null,
  de         text,
  diamantes  int not null default 0,
  ultimo_ano int not null default 0
);
alter table public.fazenda_recados_anuais enable row level security;
revoke all on public.fazenda_recados_anuais from anon, authenticated;

insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo, so_dia) values
  ('viih', 'Viih', '🌸', 4260, 1111, 11111, 1, 11, 1, 1, 'cultura', '11-11')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, tempo_seg = excluded.tempo_seg, custo = excluded.custo, venda = excluded.venda,
  rendimento = excluded.rendimento, xp = excluded.xp, nivel_min = excluded.nivel_min, ordem = excluded.ordem,
  tipo = excluded.tipo, so_dia = excluded.so_dia;

-- plantar a flor de um dia só: só no dia; a Viih, até 11 por ano
create or replace function public.fazenda_so_dia_plantar(p_jogador uuid, p_dia text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_n int;
begin
  if to_char(fazenda_hoje(), 'MM-DD') <> p_dia then raise exception 'so_no_dia'; end if;
  insert into fazenda_viih_plantio (jogador_id, ano, plantadas) values (p_jogador, extract(year from fazenda_hoje())::int, 1)
  on conflict (jogador_id, ano) do update set plantadas = fazenda_viih_plantio.plantadas + 1
  returning plantadas into v_n;
  if v_n > 11 then raise exception 'viih_limite'; end if;
end;
$$;

-- vender a flor do dia no celeiro: 1 diamante cada (só a que você colheu; a da feira e a guardada ficam)
create or replace function public.fazenda_flor_vender(p_token text, p_item text, p_quantidade int default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_livre int;
  v_qtd  int;
begin
  if not exists (select 1 from fazenda_culturas where id = p_item and so_dia is not null) then raise exception 'item_invalido'; end if;
  select ce.quantidade - ce.da_feira - coalesce((select r.quantidade from fazenda_reservas r where r.jogador_id = v_id and r.item = p_item), 0)
    into v_livre from fazenda_celeiro ce where ce.jogador_id = v_id and ce.item = p_item for update;
  v_qtd := least(coalesce(p_quantidade, v_livre), coalesce(v_livre, 0));
  if v_qtd is null or v_qtd <= 0 then raise exception 'flor_da_feira'; end if;
  update fazenda_celeiro set quantidade = quantidade - v_qtd where jogador_id = v_id and item = p_item;
  update fazenda_jogadores set diamantes = diamantes + v_qtd where id = v_id;
  return jsonb_build_object('diamantes', v_qtd, 'estado', fazenda_estado(v_id));
end;
$$;

-- os recados do ano: no dia, entram na caixa do jogador (uma vez por ano), com os diamantes
create or replace function public.fazenda_recados_anuais_entregar(p_jogador uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_ano int := extract(year from fazenda_hoje())::int;
begin
  for r in select * from fazenda_recados_anuais
            where jogador_id = p_jogador and mes_dia = to_char(fazenda_hoje(), 'MM-DD') and ultimo_ano < v_ano for update loop
    insert into fazenda_recados (jogador_id, titulo, texto, de, diamantes) values (p_jogador, r.titulo, r.texto, r.de, r.diamantes);
    if r.diamantes > 0 then update fazenda_jogadores set diamantes = diamantes + r.diamantes where id = p_jogador; end if;
    update fazenda_recados_anuais set ultimo_ano = v_ano where id = r.id;
  end loop;
end;
$$;

revoke execute on function public.fazenda_so_dia_plantar(uuid, text), public.fazenda_recados_anuais_entregar(uuid) from public, anon, authenticated;
grant execute on function public.fazenda_flor_vender(text, text, int) to anon, authenticated;

-- as funções que mudaram

-- o valor de um catálogo, montado na hora
create or replace function public.fazenda_cache_valor(p_chave text)
returns jsonb language sql stable security definer set search_path = public as $$
  select case p_chave
    when 'culturas' then (
      select jsonb_agg(jsonb_build_object(
               'id', id, 'nome', nome, 'emoji', emoji, 'tempo_seg', tempo_seg,
               'custo', custo, 'venda', venda, 'rendimento', rendimento,
               'xp', xp, 'nivel_min', nivel_min, 'tipo', tipo, 'estacao', estacao, 'so_ilha', so_ilha, 'so_dia', so_dia)   -- (fase 108; fase 115)
             order by ordem)
        from fazenda_culturas)
    when 'animais_tipos' then (select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_animais_tipos t)
    when 'conquistas_tipos' then (select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_conquistas_tipos t)
    when 'ajudantes_tipos' then (select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_ajudantes_tipos t)
    when 'melhorias_tipos' then fazenda_melhorias_tipos()
    when 'melhorias' then (select jsonb_object_agg(m->>'id', m) from jsonb_array_elements(fazenda_melhorias_tipos()) m)
  end;
$$;


create or replace function public.fazenda_aplicar(p_jogador uuid, p_acao text, p_posicao int, p_cultura text, p_bot boolean default false)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  c        record;
  k        record;
  j        record;
  v_maduro timestamptz;
  v_murcho timestamptz;
  v_qtd    int := 0;
  v_fora   boolean;
  v_estufa boolean;
  v_xp_colheita boolean;
  v_tarde  boolean := false;
  v_preco  int;   -- fase 72
begin
  select * into j from fazenda_jogadores where id = p_jogador for update;

  select * into c from fazenda_canteiros
   where jogador_id = p_jogador and posicao = p_posicao
     for update;
  if not found then
    raise exception 'canteiro_bloqueado';
  end if;

  if c.cultura is not null then
    select * into k from fazenda_culturas where id = c.cultura;
    v_maduro := c.plantado_em + make_interval(secs => k.tempo_seg);
    v_murcho := v_maduro + make_interval(secs => greatest(k.tempo_seg * 2, 3600));
  end if;

  -- fase 48: o ajudante que colhe trabalha "atrasado" quando a fazenda estava fechada: o que murchou
  -- depois da última olhada dele, ele teria colhido a tempo (só para ajudante)
  if p_acao = 'colher_tarde' then
    if not p_bot then raise exception 'acao_invalida'; end if;
    v_tarde := true;
    p_acao := 'colher';
  end if;

  -- colher agora (fase 31): diamante deixa pronto na hora o que está crescendo, sem os
  -- problemas, e já colhe. Maduro não precisa de diamante: só colhe.
  -- fase 72: 1 diamante a cada 4 h que faltam (era 1 por planta: caro na alface, barato na baunilha)
  if p_acao = 'agora' then
    if p_bot then raise exception 'acao_invalida'; end if;
    if c.estado <> 'plantado' or now() >= v_murcho then raise exception 'nada_a_fazer'; end if;
    if now() < v_maduro then
      v_preco := greatest(1, ceil(extract(epoch from v_maduro - now())
                                  / (3600 * (fazenda_loja_diamantes()->'agora'->>'horas')::numeric)))::int;
      if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
      update fazenda_jogadores set diamantes = diamantes - v_preco where id = p_jogador;
      c.erva := false; c.praga := false; c.seco := false;
      v_maduro := now();
      v_murcho := now() + make_interval(secs => greatest(k.tempo_seg * 2, 3600));
    end if;
    p_acao := 'colher';
  end if;

  if p_acao = 'arar' then
    if c.estado = 'arado' then
      raise exception 'ja_arado';
    end if;
    if c.estado = 'plantado' and now() < v_murcho then
      raise exception 'canteiro_ocupado';
    end if;
    update fazenda_canteiros
       set estado = 'arado', cultura = null, plantado_em = null,
           erva = false, praga = false, seco = false, roubado = 0, prox_evento = null, adubado = false
     where jogador_id = p_jogador and posicao = p_posicao;
    -- arar só dá XP para quem está começando (até o nível 5): senão alface de 2 min vira fábrica de XP
    -- (fase 70: o XP de arar e plantar da fazenda completa vem na colheita: arar, desmanchar e fazer o
    -- canteiro de novo virava XP sem fim)
    if not p_bot and fazenda_nivel_de(j.xp, j.nivel_trava) <= 5 then update fazenda_jogadores set xp = xp + 1 where id = p_jogador; end if;

  elsif p_acao = 'arrancar' then   -- o jogador tira o que está plantado (perde a planta) para plantar outra coisa
    if p_bot then raise exception 'acao_invalida'; end if;
    if c.estado <> 'plantado' then raise exception 'nada_a_fazer'; end if;
    update fazenda_canteiros
       set estado = 'arado', cultura = null, plantado_em = null,
           erva = false, praga = false, seco = false, roubado = 0, prox_evento = null, adubado = false
     where jogador_id = p_jogador and posicao = p_posicao;

  elsif p_acao = 'adubar' then   -- só o Seu Zé (ajudante): +1 item na colheita desse plantio
    if not p_bot then raise exception 'acao_invalida'; end if;
    if c.estado <> 'plantado' or now() >= v_maduro or c.adubado then
      raise exception 'nada_a_fazer';
    end if;
    update fazenda_canteiros set adubado = true where jogador_id = p_jogador and posicao = p_posicao;

  elsif p_acao = 'plantar' then
    if c.estado <> 'arado' then
      raise exception 'precisa_arar';
    end if;
    select * into k from fazenda_culturas where id = p_cultura;
    if not found or k.tipo <> 'cultura' then
      raise exception 'cultura_invalida';
    end if;
    if k.so_ilha and c.y < 45 then raise exception 'so_na_ilha'; end if;   -- fase 108
    if k.so_dia is not null then perform fazenda_so_dia_plantar(p_jogador, k.so_dia); end if;   -- fase 115: a Viih
    -- semente de outra estação só cresce no alcance de uma estufa elétrica
    v_fora := k.estacao is not null and k.estacao <> fazenda_estacao_em(now());
    v_estufa := fazenda_protegido(p_jogador, 'estufa', c.x, c.y);
    if v_fora and not v_estufa then
      raise exception 'fora_de_estacao';
    end if;
    if fazenda_nivel_de(j.xp, j.nivel_trava) < k.nivel_min then
      raise exception 'nivel_insuficiente';
    end if;
    if j.moedas < k.custo then
      raise exception 'moedas_insuficientes';
    end if;
    if v_estufa then
      v_estufa := fazenda_gastar_energia(p_jogador, 5);   -- sem energia, a estufa não ajuda
    end if;
    if v_fora and not v_estufa then
      raise exception 'sem_energia';
    end if;
    update fazenda_jogadores set moedas = moedas - k.custo where id = p_jogador;
    update fazenda_canteiros
       -- pé de girassol, tora, árvore de outono por perto: começa 10% adiantada; estufa: 25%
       set estado = 'plantado', cultura = k.id,
           plantado_em = now() - make_interval(secs => k.tempo_seg * fazenda_adiantar(
                           0.1 * fazenda_protegido(p_jogador, 'crescer', c.x, c.y)::int + 0.25 * v_estufa::int
                            + fazenda_melhoria(p_jogador, 'adubo'), j.crescer_ate)),   -- fase 57: adubo premium; fase 93: ampulheta
           erva = false, praga = false, seco = false, roubado = 0, adubado = false,
           prox_evento = now() + make_interval(secs => k.tempo_seg * (0.15 + random() * 0.35))
     where jogador_id = p_jogador and posicao = p_posicao;
    if not p_bot then
      perform fazenda_missao(p_jogador, 'plantar', 1);
      -- fase 57: fazenda completa: plantar também dá XP (fase 70: ele vem na colheita; plantar e arrancar
      -- em seguida virava XP sem fim)
      if k.so_dia is null then update fazenda_jogadores set semente = k.id where id = p_jogador; end if;   -- (fase 115: a Viih não)
    end if;

  elsif p_acao in ('erva', 'praga', 'seco') then
    if c.estado <> 'plantado' or now() >= v_murcho
       or (p_acao = 'erva'  and not c.erva)
       or (p_acao = 'praga' and not c.praga)
       or (p_acao = 'seco'  and not c.seco) then
      raise exception 'nada_a_fazer';
    end if;
    update fazenda_canteiros
       set erva  = case when p_acao = 'erva'  then false else erva  end,
           praga = case when p_acao = 'praga' then false else praga end,
           seco  = case when p_acao = 'seco'  then false else seco  end
     where jogador_id = p_jogador and posicao = p_posicao;
    if not p_bot then
      update fazenda_jogadores set xp = xp + 1, moedas = moedas + 1 where id = p_jogador;
      perform fazenda_missao(p_jogador, 'cuidar', 1);
    end if;

  elsif p_acao = 'colher' then
    if c.estado <> 'plantado' or now() < v_maduro then
      raise exception 'nao_maduro';
    end if;
    if now() >= v_murcho and not v_tarde then
      raise exception 'murchou';
    end if;
    -- cada problema não resolvido custa 1 unidade; o que os vizinhos pegaram também sai
    v_qtd := greatest(k.rendimento - (c.erva::int + c.praga::int + c.seco::int) - c.roubado, 1)
             + fazenda_tem_efeito(p_jogador, 'colheita')::int          -- colheitadeira
             + (fazenda_clima_agora() = 'sol')::int                      -- colheita no sol (fase 71: uma conta por chamada)
             + fazenda_protegido(p_jogador, 'adubo', c.x, c.y)::int     -- cogumelos, barril, colmeia
             + c.adubado::int                                           -- adubo do Seu Zé
             + (c.y >= 45 and j.cachorro_raca is not null)::int;        -- fase 111: o cachorro da ilha
    if fazenda_protegido(p_jogador, 'sorte', c.x, c.y) and random() < 0.15 then
      v_qtd := v_qtd * 2;                                               -- alvo
    end if;
    if j.colheita50_ate > now() then
      v_qtd := v_qtd + ceil(v_qtd / 2.0)::int;                          -- fase 93: balança de ouro (+50%)
    end if;
    if k.so_dia is not null then v_qtd := k.rendimento; end if;        -- fase 115: a Viih, sem bônus
    insert into fazenda_celeiro (jogador_id, item, quantidade)
    values (p_jogador, k.id, v_qtd)
    on conflict (jogador_id, item)
    do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
    -- XP cheio da planta, mas o mesmo canteiro dá XP no máximo 1 vez a cada 8 min (fase 41)
    -- fase 72: o que ajudante, robô ou baú colhe dá metade do XP (antes, nada), somado e gravado uma
    -- vez só no fim da rodada deles (fazenda_bot_xp)
    v_xp_colheita := c.xp_em is null or c.xp_em <= now() - interval '8 minutes';
    if v_xp_colheita and p_bot then
      perform fazenda_bot_xp(p_jogador, k.xp / 2);
    elsif v_xp_colheita then
      -- fase 70: fazenda completa: + 2 (o XP de arar e plantar, que antes vinha na hora)
      update fazenda_jogadores set xp = xp + k.xp + fazenda_protegido(p_jogador, 'xp', c.x, c.y)::int + 2 * fazenda_completa(p_jogador)::int
       where id = p_jogador;
    end if;
    update fazenda_canteiros   -- com trator, o canteiro já fica arado
       set estado = case when fazenda_tem_efeito(p_jogador, 'arar') then 'arado' else 'vazio' end,
           cultura = null, plantado_em = null,
           erva = false, praga = false, seco = false, roubado = 0, prox_evento = null, adubado = false,
           xp_em = case when v_xp_colheita then now() else xp_em end
     where jogador_id = p_jogador and posicao = p_posicao;
    if not p_bot then perform fazenda_missao(p_jogador, 'colher', v_qtd); end if;

  else
    raise exception 'acao_invalida';
  end if;

  return v_qtd;
end;
$$;


-- Fase 83: cuidar da roça do vizinho (o que mais tem nas fazendas abandonadas). Devolve o XP.
--   limpar: tira 1 planta murcha (o canteiro fica arado); até 2 por dia em cada fazenda, como salvar. 1 ajuda.
--   arar: canteiro vazio vira arado. 1 ajuda.
--   colher: a planta madura vai para o celeiro do dono (ele ganha metade do XP, como com o ajudante). 1 ajuda.
--   plantar:<semente>: só na fazenda abandonada, com a semente paga por quem ajuda (o nível e a estação
--     valem os de quem ajuda e de agora). 5 ajudas.
create or replace function public.fazenda_roca_um(p_ator uuid, p_dono uuid, p_posicao int, p_acao text)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  c    record;
  k    record;
  v_murcha boolean;
  v_un int;
  v_tipo text;
  v_cult text;
  v_xp int;
begin
  select * into c from fazenda_canteiros where jogador_id = p_dono and posicao = p_posicao for update;
  if not found then raise exception 'nada_a_fazer'; end if;
  v_murcha := false;
  if c.cultura is not null then
    select * into k from fazenda_culturas where id = c.cultura;
    v_murcha := c.estado = 'plantado' and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600));
  end if;
  if p_acao = 'limpar' then
    if not v_murcha then raise exception 'nada_a_fazer'; end if;
    if (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'limpar'
          and criado_em > now() - interval '1 day') >= 2 then
      raise exception 'ja_limpou';
    end if;
    perform fazenda_aplicar(p_dono, 'arar', p_posicao, null, true);
    v_un := 1; v_tipo := 'limpar'; v_cult := c.cultura;
  elsif p_acao = 'arar' then
    if c.estado <> 'vazio' then raise exception 'nada_a_fazer'; end if;
    perform fazenda_aplicar(p_dono, 'arar', p_posicao, null, true);
    v_un := 1; v_tipo := 'arar'; v_cult := null;   -- (canteiro vazio: sem planta)
  elsif p_acao = 'colher' then
    if c.estado <> 'plantado' or v_murcha or now() < c.plantado_em + make_interval(secs => k.tempo_seg) then raise exception 'nao_maduro'; end if;
    perform fazenda_aplicar(p_dono, 'colher', p_posicao, null, true);
    v_un := 1; v_tipo := 'colher'; v_cult := c.cultura;
  else   -- plantar:<semente>
    if not fazenda_abandonada(p_dono) then raise exception 'nao_abandonada'; end if;
    if c.estado <> 'arado' then raise exception 'precisa_arar'; end if;
    select * into k from fazenda_culturas where id = split_part(p_acao, ':', 2) and tipo = 'cultura';
    if not found then raise exception 'cultura_invalida'; end if;
    if k.estacao is not null and k.estacao <> fazenda_estacao_em(now()) then raise exception 'fora_de_estacao'; end if;
    if k.so_ilha and c.y < 45 then raise exception 'so_na_ilha'; end if;   -- fase 108
    if k.so_dia is not null then raise exception 'cultura_invalida'; end if;   -- fase 115: a Viih só na sua fazenda
    if (select fazenda_nivel_de(xp, nivel_trava) from fazenda_jogadores where id = p_ator) < k.nivel_min then raise exception 'nivel_insuficiente'; end if;
    perform fazenda_lote_gastar(p_ator, k.custo);   -- (fase 87: no Ajudar tudo, sai no fim, numa gravação só)
    update fazenda_canteiros
       set estado = 'plantado', cultura = k.id, plantado_em = now(),
           erva = false, praga = false, seco = false, roubado = 0, adubado = false,
           prox_evento = now() + make_interval(secs => k.tempo_seg * (0.15 + random() * 0.35))
     where jogador_id = p_dono and posicao = p_posicao;
    v_un := 2; v_tipo := 'plantar'; v_cult := k.id;   -- (fase 85: 2 ajudas; eram 5)
  end if;
  -- fase 86: colher, arar e plantar dão XP 1 vez por dia em cada canteiro (para quem ajuda); de novo no
  -- mesmo canteiro, a ajuda vale para o dono mas não dá XP (o vai e volta de plantar e colher não sobe nível)
  if v_tipo in ('colher', 'arar', 'plantar') and exists (
       select 1 from fazenda_visitas
        where ator_id = p_ator and tipo = v_tipo and dono_id = p_dono and posicao = p_posicao
          and criado_em >= (fazenda_hoje()::timestamp at time zone 'America/Sao_Paulo')) then
    v_un := 0;
  end if;
  v_xp := fazenda_premiar_ajuda(p_ator, v_un, p_dono);
  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd, xp)
  values (p_ator, p_dono, v_tipo, p_posicao, now(), v_cult, 1, v_xp);   -- (fase 85: e o XP dado)
  if v_un > 0 then perform fazenda_missao_ajuda(p_ator, 1); end if;
  return v_xp;
end;
$$;


-- Pega colheita de um canteiro do vizinho. Retorna a quantidade pega.
-- fase 66: p_luva = pode gastar 1 luva do Perks para passar pelo alarme (só gasta no canteiro protegido)
-- fase 103: com a luva, leva a muda inteira (o que o dono colheria) e o canteiro do vizinho fica arado
drop function if exists public.fazenda_pegar_um(uuid, uuid, int);
create or replace function public.fazenda_pegar_um(p_ator uuid, p_dono uuid, p_posicao int, p_luva boolean default false)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  c        record;
  k        record;
  v_maduro timestamptz;
  v_qtd    int;
  v_luva   boolean := false;
begin
  select * into c from fazenda_canteiros
   where jogador_id = p_dono and posicao = p_posicao
     for update;
  if not found or c.estado <> 'plantado' then
    raise exception 'nao_maduro';
  end if;
  select * into k from fazenda_culturas where id = c.cultura;
  if k.so_dia is not null then raise exception 'nada_pra_pegar'; end if;   -- fase 115: a Viih ninguém pega
  v_maduro := c.plantado_em + make_interval(secs => k.tempo_seg);
  if now() < v_maduro then
    raise exception 'nao_maduro';
  end if;
  if now() >= v_maduro + make_interval(secs => greatest(k.tempo_seg * 2, 3600)) then
    raise exception 'murchou';
  end if;
  if fazenda_protegido(p_dono, 'alarme', c.x, c.y) and fazenda_alarme_ligado(p_dono) then
    if not coalesce(p_luva, false) then raise exception 'alarme'; end if;
    v_luva := true;   -- fase 66: passa com a luva do Perks (gasta lá embaixo, se der para pegar)
  end if;
  if exists (select 1 from fazenda_visitas
              where tipo = 'roubo' and ator_id = p_ator and dono_id = p_dono
                and posicao = p_posicao and plantado_em = c.plantado_em) then
    raise exception 'ja_pegou';
  end if;
  if c.roubado >= (case when v_luva then k.rendimento else fazenda_limite_roubo(k.rendimento) end) then
    raise exception 'nada_pra_pegar';
  end if;
  if (select count(*) from fazenda_visitas
       where ator_id = p_ator and tipo = 'roubo' and criado_em > now() - interval '1 day') >= 40 then
    raise exception 'limite_pegadas';
  end if;

  if v_luva then
    update fazenda_celeiro set quantidade = quantidade - 1
     where jogador_id = p_ator and item = 'luva_perks'
       and quantidade - coalesce((select quantidade from fazenda_reservas where jogador_id = p_ator and item = 'luva_perks'), 0) >= 1;
    if not found then raise exception 'sem_luva'; end if;
  end if;

  if v_luva then
    -- fase 103: a muda inteira, o mesmo que o dono colheria agora (a cerca não segura a luva)
    v_qtd := greatest(k.rendimento - (c.erva::int + c.praga::int + c.seco::int) - c.roubado, 1) + c.adubado::int;
    update fazenda_canteiros set estado = 'arado', cultura = null, plantado_em = null,
           erva = false, praga = false, seco = false, roubado = 0, prox_evento = null, adubado = false
     where jogador_id = p_dono and posicao = p_posicao;
  else
    v_qtd := least(2 + (random() < 0.4)::int, fazenda_limite_roubo(k.rendimento) - c.roubado);
    if fazenda_protegido(p_dono, 'cerca', c.x, c.y) then
      v_qtd := least(v_qtd, 1);   -- cerca ou placa por perto
    end if;
    update fazenda_canteiros set roubado = roubado + v_qtd
     where jogador_id = p_dono and posicao = p_posicao;
  end if;
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  values (p_ator, k.id, v_qtd)
  on conflict (jogador_id, item)
  do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd, luva)
  values (p_ator, p_dono, 'roubo', p_posicao, c.plantado_em, k.id, v_qtd, v_luva);
  perform fazenda_missao(p_ator, 'pegar', v_qtd);

  return v_qtd;
end;
$$;


-- p_quantidade null = vende tudo daquele item. p_item null = vende o celeiro todo.
-- fase 74b: p_itens vende vários de uma vez (o "vender produtos" chamava uma vez por produto, cada uma
-- com a fazenda inteira de volta: 15 produtos travavam o jogo uns 5 s)
create or replace function public.fazenda_vender(p_token text, p_item text default null, p_quantidade int default null,
                                                 p_itens text[] default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  r       record;
  v_qtd   int;
  v_ganho int := 0;
  v_valor numeric := 0;   -- valor que conta para o XP (sem o bônus de beleza)
  v_xp    int;
  v_feira int;
  v_sem_xp int := 0;      -- fase 56: quantos itens comprados na feira foram vendidos (sem XP)
  v_cofre boolean;        -- fase 93: cofrinho de ouro ligado (+50%, menos no que veio da feira)
  v_extra int := 0;
  v_nivel int := (select fazenda_nivel_de(xp, nivel_trava) from fazenda_jogadores where id = v_id);   -- fase 107: o preço do Velho Chico
begin
  if p_quantidade is not null and p_quantidade <= 0 then
    raise exception 'quantidade_invalida';
  end if;

  -- o que está reservado para os animais fica no celeiro
  for r in
    select ce.item, ce.quantidade - coalesce(rs.quantidade, 0) as livre, ce.da_feira,
           case when k.id = 'velho_chico' then fazenda_preco_chico(v_nivel) else k.venda end as venda,   -- fase 107
           k.tipo, k.nivel_min
      from fazenda_celeiro ce
      join fazenda_culturas k on k.id = ce.item
      left join fazenda_reservas rs on rs.jogador_id = ce.jogador_id and rs.item = ce.item
     where ce.jogador_id = v_id
       and ce.quantidade > coalesce(rs.quantidade, 0)
       and (p_item is null or ce.item = p_item)
       and (p_itens is null or ce.item = any(p_itens))   -- fase 74b
       and k.tipo <> 'raro'   -- fase 60: material raro só vende na feira
       and k.so_dia is null   -- fase 115: a Viih vira diamante (fazenda_flor_vender)
       for update of ce
  loop
    v_qtd := least(coalesce(p_quantidade, r.livre), r.livre);
    -- fase 56: o que veio da feira sai primeiro e não dá XP (comprar na feira para revender ao
    -- jogo virava XP comprado com moedas); as moedas da venda são as de sempre
    v_feira := least(v_qtd, r.da_feira);
    update fazenda_celeiro set quantidade = quantidade - v_qtd, da_feira = da_feira - v_feira
     where jogador_id = v_id and item = r.item;
    v_ganho := v_ganho + v_qtd * r.venda;
    -- XP da venda: só os produtos (oficinas, bichos, lago, pomar); a planta já deu XP na colheita (fase 41)
    v_valor := v_valor + case when r.tipo <> 'cultura' then (v_qtd - v_feira) * r.venda else 0 end;
    v_sem_xp := v_sem_xp + case when r.tipo <> 'cultura' then v_feira else 0 end;
    v_extra := v_extra + (v_qtd - v_feira) * r.venda;
  end loop;

  v_ganho := (v_ganho * (100 + fazenda_bonus_venda(v_id))) / 100;   -- beleza e caixote
  -- fase 93: cofrinho de ouro: +50% do preço de venda, só no que não veio da feira (comprar barato
  -- de outro jogador e revender ao jogo não rende o bônus)
  select venda50_ate > now() into v_cofre from fazenda_jogadores where id = v_id;
  v_extra := case when v_cofre then v_extra / 2 else 0 end;
  v_ganho := v_ganho + v_extra;
  -- 1 XP a cada 25 moedas do valor; o que sobra fica para a próxima venda
  select floor((venda_resto + v_valor) / 25)::int into v_xp from fazenda_jogadores where id = v_id;
  update fazenda_jogadores
     set moedas = moedas + v_ganho, xp = xp + v_xp, venda_resto = venda_resto + v_valor - v_xp * 25
   where id = v_id;
  if v_ganho > 0 then
    perform fazenda_missao(v_id, 'vender', v_ganho);
  end if;

  return jsonb_build_object('ganho', v_ganho, 'xp', v_xp, 'sem_xp', v_sem_xp, 'cofrinho', v_extra, 'estado', fazenda_estado(v_id));
end;
$$;


-- o robô consegue plantar essa semente nesse canteiro? (as checagens de fazenda_aplicar: arado,
-- nível, moedas e a estação ou uma estufa por perto)
create or replace function public.fazenda_bot_pode_plantar(p_jogador uuid, p_cultura text, p_posicao int)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select c.estado = 'arado' and k.tipo = 'cultura' and fazenda_nivel_de(j.xp, j.nivel_trava) >= k.nivel_min and j.moedas >= k.custo
           and (k.estacao is null or k.estacao = fazenda_estacao_em(now()) or fazenda_protegido(p_jogador, 'estufa', c.x, c.y))
           and (k.so_dia is null or (to_char(fazenda_hoje(), 'MM-DD') = k.so_dia   -- fase 115: a Viih só no dia, até 11
                and coalesce((select v.plantadas from fazenda_viih_plantio v where v.jogador_id = p_jogador
                               and v.ano = extract(year from fazenda_hoje())::int), 0) < 11))
      from fazenda_canteiros c, fazenda_culturas k, fazenda_jogadores j
     where c.jogador_id = p_jogador and c.posicao = p_posicao and k.id = p_cultura and j.id = p_jogador), false);
$$;


create or replace function public.fazenda_estado(p_jogador uuid)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  j       record;
  v_nivel int;
  v_max   int;
  v_json  jsonb;
  v_ener  real;
  v_prev  jsonb := fazenda_previsao_agora();   -- fase 71: a previsão do clima e do vento, pronta (uma por minuto)
  v_clima jsonb := v_prev->'clima';
  v_metas jsonb;
  v_bonus int;
  -- fase 89: sessão do jogo novo, que já tem os catálogos: manda só o que muda
  v_leve  boolean := coalesce(current_setting('fazenda.leve', true), '') = '1'
                     and current_setting('fazenda.eu', true) = p_jogador::text;
  v_omite boolean := false;
  v_ver   text;
begin
  -- fase 89: na sessão leve, as conquistas ficam para o carregar (de minuto em minuto)
  if not v_leve or coalesce(current_setting('fazenda.carregar', true), '') = '1' then
    perform fazenda_checar_conquistas(p_jogador);
  end if;
  select * into j from fazenda_jogadores where id = p_jogador;
  if j.convite is null then   -- (quem nasceu entre o SQL e o deploy)
    update fazenda_jogadores set convite = fazenda_novo_convite() where id = p_jogador;
    select * into j from fazenda_jogadores where id = p_jogador;
  end if;
  if j.zonas >= 3 and j.lago_em is null then   -- comprou o Vale do sudeste: o Bira começa a pescar
    update fazenda_jogadores set lago_em = now() where id = p_jogador;
    select * into j from fazenda_jogadores where id = p_jogador;
  end if;
  -- fase 62: com o píer pronto, o cardume do alto-mar começa cheio; o marinheiro, ao ser contratado
  if (j.pier_em is not null and j.mar_em is null)
     or (j.marinheiro_em is null and exists (select 1 from fazenda_melhorias where jogador_id = p_jogador and id = 'marinheiro')) then
    update fazenda_jogadores
       set mar_em = coalesce(mar_em, now() - make_interval(secs => (fazenda_mar_item(p_jogador, 'barco')->>'max')::int
                                                              * (fazenda_mar_item(p_jogador, 'barco')->>'intervalo')::int)),
           marinheiro_em = case when exists (select 1 from fazenda_melhorias where jogador_id = p_jogador and id = 'marinheiro')
                                then coalesce(marinheiro_em, now()) end
     where id = p_jogador;
    select * into j from fazenda_jogadores where id = p_jogador;
  end if;
  v_nivel := fazenda_nivel_de(j.xp, j.nivel_trava);
  -- subiu de nível: presente de moedas e 5 diamantes por cada nível novo
  if v_nivel > coalesce(j.nivel_premiado, 1) then
    update fazenda_jogadores
       set moedas = moedas + (select sum(fazenda_presente_nivel(n)) from generate_series(coalesce(j.nivel_premiado, 1) + 1, v_nivel) n),
           diamantes = diamantes + 5 * (v_nivel - coalesce(j.nivel_premiado, 1)),
           nivel_premiado = v_nivel,
           nivel_base = greatest(coalesce(nivel_base, 1), v_nivel)   -- fase 112: o nível que você alcançou não cai mais
     where id = p_jogador and nivel_premiado is not distinct from j.nivel_premiado;   -- fase 70: paga uma vez só
    select * into j from fazenda_jogadores where id = p_jogador;
  end if;
  v_omite := v_leve and fazenda_catalogos_ver(v_nivel) = current_setting('fazenda.cat_ver', true);   -- fase 89
  -- canteiros não aparecem mais sozinhos: o jogador coloca no modo construir até este limite
  v_max := fazenda_limite_canteiros(v_nivel, fazenda_terrenos(j.zonas, j.direita) + 100 * j.ilha_terrenos);
  -- fase 49: as metas de nível; com todas em dia, o bônus de XP vale neste nível (só grava se mudou)
  v_metas := fazenda_metas(p_jogador, v_nivel);
  -- (fase 62: até o 44; era até o 29, quando o 30 era o último nível)
  v_bonus := case when v_nivel < 60 and not exists (select 1 from jsonb_array_elements(v_metas) m where not (m->>'feito')::boolean)
                  then v_nivel end;
  if v_bonus is distinct from j.bonus_nivel then
    update fazenda_jogadores set bonus_nivel = v_bonus where id = p_jogador;
  end if;
  v_ener := fazenda_energia_atualizar(p_jogador);

  perform fazenda_gerar_missoes(p_jogador);

  v_json := jsonb_build_object(
    'agora', now(),
    'jogador', jsonb_build_object(
      'id', j.id,
      'apelido', j.apelido,
      'avatar', j.avatar,
      'avatares', j.avatares,
      'avatar_precos', fazenda_avatar_precos(),
      'avatar_diamantes', fazenda_avatar_diamantes(),
      'avatar_exclusivos', fazenda_avatar_exclusivos(),   -- fase 69
      'cercado_gratis', coalesce(j.cercado_gratis, '{}'),   -- fase 45: espécies com o primeiro cercado de graça
      'moedas', j.moedas,
      'diamantes', j.diamantes,
      -- fase 43: o que os diamantes ligaram (até quando) e quantos pacotes de XP saíram hoje
      'xp2_ate', case when j.xp2_ate > now() then j.xp2_ate end,
      'cafe_ate', case when j.cafe_ate > now() then j.cafe_ate end,
      -- fase 93: os bônus dos prêmios do evento (plantas 2x mais rápidas, +50% na venda, +50% na colheita) e
      -- quanto de cada item do celeiro veio da feira (sem o +50% do cofrinho). Num objeto só: o estado
      -- está no limite de 100 argumentos do jsonb_build_object
      'premios', jsonb_build_object(
        'crescer_ate', case when j.crescer_ate > now() then j.crescer_ate end,
        'venda50_ate', case when j.venda50_ate > now() then j.venda50_ate end,
        'colheita50_ate', case when j.colheita50_ate > now() then j.colheita50_ate end,
        'da_feira', coalesce((select jsonb_object_agg(item, least(da_feira, quantidade))
                                from fazenda_celeiro where jogador_id = p_jogador and quantidade > 0 and da_feira > 0), '{}'::jsonb)),
      'xp_compras_hoje', fazenda_diamantes_hoje(p_jogador, 'xp'),
      -- conta Google ligada (só aparece para o dono; null = não ligada)
      'google', case when j.google_sub is not null then coalesce(j.google_email, 'sua conta Google') end,
      'admin', j.admin,   -- fase 53: 'dono', 'admin' ou null
      'xp', j.xp,
      'nivel', v_nivel,
      -- fase 90: com XP para mais e travado por faltar algo do nível: o que falta comprar
      'trava', case when fazenda_nivel(j.xp) > v_nivel then
                 jsonb_build_object('nivel', v_nivel, 'faltam', fazenda_nivel_faltam(p_jogador, v_nivel)) end,
      'xp_nivel', fazenda_xp_nivel(v_nivel),
      'xp_proximo', fazenda_xp_nivel(v_nivel + 1),
      'bonus_nivel', v_bonus,   -- fase 49: +50% de XP neste nível (metas em dia)
      'max_canteiros', v_max,
      'max_construcoes', fazenda_max_construcoes(fazenda_terrenos(j.zonas, j.direita) + 100 * j.ilha_terrenos),
      'zonas', j.zonas,
      'direita', j.direita,   -- fase 78: os terrenos da direita
      'ilha_terrenos', j.ilha_terrenos,   -- fase 106: os da ilha
      'preco_chico', fazenda_preco_chico(v_nivel),   -- fase 107: o Peixe do Velho Chico vale mais a cada nível
      'beleza', fazenda_beleza(p_jogador),
      'bonus_venda', fazenda_bonus_venda(p_jogador),
      -- fase 106: a ilha (pode zarpar? quantas obras; do 45 em diante, a lista; o baú de hoje já foi aberto?)
      'ilha', jsonb_build_object('obras', coalesce(j.ilha_obras, 0), 'pode_ir', fazenda_ilha_pode(p_jogador, v_nivel),
                                 'bau_hoje', j.ilha_bau_dia = fazenda_hoje(), 'x', fazenda_ilha_x(p_jogador),
                                 'partes', case when v_nivel >= 45 then fazenda_ilha_obras() end),
      -- fase 111: o cachorro da ilha (null: ainda não escolheu)
      'cachorro', case when j.cachorro_raca is not null then jsonb_build_object('raca', j.cachorro_raca, 'nome', j.cachorro_nome) end
    ),
    'zonas_venda', case when not v_omite then fazenda_zonas() end,
    'pacotes_diamantes', fazenda_pacotes_diamantes(),
    'loja_diamantes', fazenda_loja_diamantes(),
    'baus_sorte', fazenda_baus_sorte(),   -- fase 73
    -- fase 50: a feira (os seus anúncios abertos e o que vendeu desde a última olhada)
    'feira', jsonb_build_object(
      'regras', fazenda_feira_regras(),
      'limite', fazenda_feira_limite(p_jogador),   -- fase 51: 2 por barraca
      'barracas', (select barracas from fazenda_jogadores where id = p_jogador),
      'vendidos', coalesce((select jsonb_agg(v order by (v->>'em') desc) from (
                    select jsonb_build_object('item', f.item, 'qtd', f.qtd, 'total', f.qtd * f.preco,
                             'comprador', c.apelido, 'em', f.vendido_em) as v
                      from fazenda_feira f left join fazenda_jogadores c on c.id = f.comprador_id
                     where f.vendedor_id = p_jogador and f.vendido_em > now() - interval '7 days'
                     order by f.vendido_em desc limit 10) x), '[]'::jsonb),
      'meus', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'item', f.item, 'qtd', f.qtd, 'preco', f.preco,
                          'ate', f.criado_em + make_interval(hours => (fazenda_feira_regras()->>'horas')::int),
                          -- fase 67: separado para quem pediu no chat
                          'para', case when f.reservado_ate > now() then r.apelido end,
                          'reservado_ate', case when f.reservado_ate > now() then f.reservado_ate end) order by f.id)
                          from fazenda_feira f left join fazenda_jogadores r on r.id = f.reservado_para
                         where f.vendedor_id = p_jogador and f.vendido_em is null), '[]'::jsonb),
      'vendas_novas', coalesce((select jsonb_agg(jsonb_build_object('item', f.item, 'qtd', f.qtd, 'total', f.qtd * f.preco,
                          'recebeu', f.qtd * f.preco - ceil(f.qtd * f.preco * (fazenda_feira_regras()->>'taxa')::int / 100.0)::int,
                          'comprador', c.apelido) order by f.vendido_em)
                          from fazenda_feira f left join fazenda_jogadores c on c.id = f.comprador_id
                         where f.vendedor_id = p_jogador and f.vendido_em is not null and not f.visto), '[]'::jsonb)),
    'metas', v_metas,
    -- fase 39: o que está em cada baú, o que já chegou pelo cano em cada oficina e as viagens
    -- dos últimos 2 minutos (o jogo desenha o item andando só enquanto ela acontece)
    'baus', coalesce((select jsonb_object_agg(b.x || ',' || b.y, b.itens) from (
        select x, y, jsonb_object_agg(item, quantidade) as itens from fazenda_bau_itens
         where jogador_id = p_jogador and quantidade > 0 group by x, y) b), '{}'::jsonb),
    'oficina_itens', coalesce((select jsonb_object_agg(o.x || ',' || o.y, o.itens) from (
        select x, y, jsonb_object_agg(item, quantidade) as itens from fazenda_oficina_itens
         where jogador_id = p_jogador and quantidade > 0 group by x, y) o), '{}'::jsonb),
    'viagens', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'item', v.item, 'qtd', v.qtd,
        'de', case when v.de_x is null then null else jsonb_build_array(v.de_x, v.de_y) end,
        'para', case when v.para_x is null then null else jsonb_build_array(v.para_x, v.para_y) end,
        'direto', v.direto, 'em', v.em) order by v.em)
        -- fase 44: as criadas nos últimos 2 minutos (o jogo anima cada uma quando recebe, item por
        -- item; antes eram as com hora marcada nos últimos 2 min, e a entrega de uma receita que
        -- terminou antes ficava de fora)
        from (select * from fazenda_viagens where jogador_id = p_jogador and criada_em > now() - interval '2 minutes'
               order by criada_em desc, id desc limit 300) v), '[]'::jsonb),
    'galinheiro', jsonb_build_object('linhas', fazenda_galinheiro_linhas(p_jogador), 'quer', fazenda_galinheiro_quer(p_jogador),
                                     'pasto', fazenda_pasto(p_jogador)),   -- fase 45: o pasto do começo ainda existe?
    'visitante', fazenda_visitante(p_jogador),
    -- o lago (só com o terreno 3): desde quando o cesto enche, o ritmo, o máximo e as chances
    'lago', case when j.zonas >= 3 then jsonb_build_object(
      'desde', j.lago_em, 'intervalo', 1800, 'max', fazenda_cesto_max(p_jogador),
      'estatua', fazenda_tem_efeito(p_jogador, 'chico'),
      'peixes', (select jsonb_agg(jsonb_build_object('id', peixe, 'chance', chance))
                   from fazenda_peixes(fazenda_tem_efeito(p_jogador, 'chico')))) end,
    'convites', jsonb_build_object(
      'codigo', j.convite,
      'premio', fazenda_premio_convite(),
      'total', (select count(*) from fazenda_convites where dono_id = p_jogador),
      'novos', coalesce((
        select jsonb_agg(jsonb_build_object('apelido', a.apelido, 'premiado', c.premiado) order by c.criado_em)
          from fazenda_convites c join fazenda_jogadores a on a.id = c.convidado_id
         where c.dono_id = p_jogador and not c.visto), '[]'::jsonb)),
    -- energia agora, quanto cabe e quanto entra por hora (sol/vento/reator + biomassa ligada)
    'energia', jsonb_build_object(
      'carga', round(v_ener::numeric, 1),
      'calmo', fazenda_vento_calmo(now()),   -- fase 48: sem vento agora (a turbina quase para)
      'vento', v_prev->'vento',
      'capacidade', fazenda_capacidade(p_jogador),
      'conta', fazenda_energia_conta(p_jogador),   -- fase 75: quanto gera e quanto gasta, por hora
      'por_hora', fazenda_energia_taxa(p_jogador, now()) + 50 * (
        select count(*) from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
         where c.jogador_id = p_jogador and i.efeito = 'biomassa' and c.iniciado_em is not null)),
    'estacao', fazenda_estacao_em(now()),
    'estacao_fim', fazenda_estacao_fim(now()),
    'estacao_proxima', fazenda_estacao_em(fazenda_estacao_fim(now())),
    -- agora / até quando / o próximo (hoje e amanha: nomes da versão anterior do jogo)
    'clima', v_clima || jsonb_build_object('hoje', v_clima->>'agora', 'amanha', v_clima->>'proximo'),
    'canteiros', coalesce((
      select jsonb_agg(jsonb_build_object(
               'posicao', posicao, 'x', x, 'y', y, 'estado', estado, 'cultura', cultura,
               'plantado_em', plantado_em, 'erva', erva, 'praga', praga, 'seco', seco,
               'roubado', roubado, 'adubado', adubado, 'xp_em', xp_em)
             order by posicao)
        from fazenda_canteiros where jogador_id = p_jogador), '[]'::jsonb),
    'diario', coalesce((
      select jsonb_agg(jsonb_build_object(
               'tipo', d.tipo, 'id', d.ator_id, 'apelido', d.apelido,
               'cultura', d.cultura, 'qtd', d.qtd, 'em', d.criado_em, 'luva', d.luva)   -- fase 66: passou pelo alarme
             order by d.criado_em desc)
        from (
          select v.tipo, v.ator_id, a.apelido, v.cultura, v.qtd, v.criado_em, v.luva
            from fazenda_visitas v
            join fazenda_jogadores a on a.id = v.ator_id
           where v.dono_id = p_jogador
           order by v.criado_em desc
           limit 20
        ) d), '[]'::jsonb),
    'celeiro', coalesce((
      select jsonb_object_agg(item, quantidade)
        from fazenda_celeiro where jogador_id = p_jogador and quantidade > 0), '{}'::jsonb),
    'reservas', coalesce((
      select jsonb_object_agg(item, quantidade)
        from fazenda_reservas where jogador_id = p_jogador), '{}'::jsonb),
    'culturas', case when not v_omite then fazenda_cache_ler('culturas') end,   -- fase 71: os catálogos vêm prontos (fazenda_cache)
    'animais', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'alimentado_em', alimentado_em,
               'radioativo_ate', case when radioativo_ate > now() then radioativo_ate end) order by id)   -- fase 68
        from fazenda_animais where jogador_id = p_jogador), '[]'::jsonb),
    'animais_tipos', case when not v_omite then fazenda_cache_ler('animais_tipos') end,
    'construcoes', coalesce((
      select jsonb_agg(jsonb_build_object('x', x, 'y', y, 'tipo', tipo, 'colhido_em', colhido_em, 'iniciado_em', iniciado_em,
                                          'estoque', estoque, 'prontos', prontos, 'pago', pago,   -- fase 72: pago
                                          'sobrecarga_em', sobrecarga_em))   -- fase 77: parado até o conserto
        from fazenda_construcoes where jogador_id = p_jogador), '[]'::jsonb),
    'estoque_max', fazenda_estoque_max_de(p_jogador),   -- fase 82: 15 com a fila de diamante
    -- fase 83: o alarme sem energia (o total de segundos desligado) e o resumo dos últimos 7 dias do
    -- que os vizinhos fizeram aqui (o jogo mostra o que é novo desde a última vez)
    'social', jsonb_build_object(   -- (fase 83: num objeto só: o estado chegou no limite de 100 argumentos)
      'alarme_off', jsonb_build_object('seg', j.alarme_off_seg, 'em', j.alarme_off_em),
      'raros_semana', fazenda_raros_semana(p_jogador),   -- fase 84
      -- fase 91: quantas vezes cada ajudante foi demitido (contratar e evoluir ficam 50% mais caros a cada uma)
      'demitidos', coalesce((select jsonb_object_agg(d.tipo, d.vezes) from fazenda_ajudantes_demitidos d where d.jogador_id = p_jogador), '{}'::jsonb),
      -- fase 85: o XP de ajuda de hoje e o teto (passou dele, cada ajuda vale 1/4)
      'ajuda_hoje', jsonb_build_object('xp', case when j.ajuda_dia = fazenda_hoje() then coalesce(j.ajuda_xp_dia, 0) else 0 end,
                                       'teto', fazenda_ajuda_teto(p_jogador)),
      'vizinhos_resumo', coalesce((select jsonb_agg(jsonb_build_object('apelido', x.apelido, 'tipo', x.tipo, 'qtd', x.qtd, 'em', x.em) order by x.em desc)
        from (select a.apelido, v.tipo, sum(v.qtd)::int as qtd, max(v.criado_em) as em
                from fazenda_visitas v join fazenda_jogadores a on a.id = v.ator_id
               where v.dono_id = p_jogador and v.criado_em > now() - interval '7 days'
               group by a.apelido, v.tipo order by max(v.criado_em) desc limit 30) x), '[]'::jsonb),
      -- fase 83: a sequência de vizinhos ajudados (zera 10 min depois da última ajuda)
      'sequencia', case when j.seq_em > now() - interval '10 minutes' then jsonb_build_object(
                   'n', cardinality(j.seq_donos), 'bonus', fazenda_sequencia_bonus(cardinality(j.seq_donos)),
                   'ate', j.seq_em + interval '10 minutes') end),
    'oficina_niveis', jsonb_build_object('regras', fazenda_oficina_niveis(),
                        'tem', coalesce((select jsonb_object_agg(tipo, nivel) from fazenda_oficina_nivel where jogador_id = p_jogador), '{}'::jsonb)),
    'itens', case when not v_omite then fazenda_cache_itens(v_nivel) end,   -- fase 57: o limite que vale para o nível de agora (fase 71: pronto, um por nível)
    'melhorias', coalesce((select jsonb_object_agg(id, nivel) from fazenda_melhorias where jogador_id = p_jogador), '{}'::jsonb),
    'camas', jsonb_build_object('total', fazenda_camas(p_jogador), 'ocupadas', fazenda_camas_ocupadas(p_jogador)),   -- fase 59
    'pier', jsonb_build_object('pronto', j.pier_em is not null, 'receita', fazenda_pier_receita()),   -- fase 61
    'mar', fazenda_mar_estado(p_jogador),   -- fase 62: o alto-mar (null sem o píer)
    -- fase 66: por que murchou (cada canteiro murcho de agora), o resumo das novas e as das últimas 24 h
    'murchas', jsonb_build_object(
      'canteiros', coalesce((
        select jsonb_object_agg(m.posicao::text, jsonb_build_object('motivo', m.motivo, 'detalhe', m.detalhe, 'em', m.murchou_em))
          from fazenda_murchas m join fazenda_canteiros c on c.jogador_id = m.jogador_id and c.posicao = m.posicao and c.plantado_em = m.plantado_em
         where m.jogador_id = p_jogador and c.estado = 'plantado'), '{}'::jsonb),
      'novas', coalesce((
        select jsonb_agg(jsonb_build_object('motivo', x.motivo, 'qtd', x.n, 'detalhe', x.d) order by x.n desc)
          from (select motivo, count(*) as n, (array_agg(detalhe order by murchou_em desc))[1] as d
                  from fazenda_murchas where jogador_id = p_jogador and not visto group by motivo) x), '[]'::jsonb),
      'dia', coalesce((
        select jsonb_object_agg(x.motivo, x.n)
          from (select motivo, count(*) as n from fazenda_murchas
                 where jogador_id = p_jogador and murchou_em > now() - interval '24 hours' group by motivo) x), '{}'::jsonb)),
    -- fase 67: o chat (o id mais novo, para a bolinha) e o que separaram para você na feira
    'chat', jsonb_build_object(
      'ultimo', (select max(c.id) from fazenda_chat c join fazenda_jogadores p on p.id = c.jogador_id
                  where c.criado_em >= now() - make_interval(mins => (fazenda_chat_regras()->>'minutos')::int)
                    and c.apagado_em is null and p.banido_em is null),
      'reservas', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'item', f.item, 'qtd', f.qtd, 'preco', f.preco,
                             'vendedor', v.apelido, 'ate', f.reservado_ate, 'nova', not f.reserva_vista) order by f.id)
                             from fazenda_feira f join fazenda_jogadores v on v.id = f.vendedor_id
                            where f.reservado_para = p_jogador and f.vendido_em is null and f.reservado_ate > now()), '[]'::jsonb)),
    'calendario', fazenda_calendario_estado(p_jogador),   -- fase 69: o calendário de resgate diário
    -- fase 68: o que a radiação do reator fez nos bichos (ainda não visto)
    'radiacao', coalesce((select jsonb_agg(jsonb_build_object('evento', r.evento, 'animal', r.animal, 'produto', r.produto, 'qtd', r.qtd, 'em', r.em) order by r.id)
                            from fazenda_radiacao r where r.jogador_id = p_jogador and not r.visto), '[]'::jsonb),
    -- fase 77: o que a tempestade e o furacão fizeram (e o que o eletricista consertou), ainda não visto
    'clima_eventos', coalesce((select jsonb_agg(jsonb_build_object('evento', e.evento, 'clima', e.clima, 'item', e.item, 'x', e.x, 'y', e.y, 'em', e.em) order by e.id)
                                 from fazenda_clima_eventos e where e.jogador_id = p_jogador and not e.visto), '[]'::jsonb),
    -- fase 63: o evento da semana (até quando vai, os prêmios ainda não vistos e os troféus)
    'evento', jsonb_build_object(
      'fim', fazenda_semana_inicio(now()) + interval '7 days',
      'novos', coalesce((select jsonb_agg(jsonb_build_object('semana', semana, 'categoria', categoria, 'posicao', posicao,
                                   'valor', valor, 'diamantes', diamantes, 'item', item) order by categoria, posicao)
                           from fazenda_semana_premios where jogador_id = p_jogador and not visto), '[]'::jsonb),
      'trofeus', fazenda_trofeus(p_jogador),
      'regras', fazenda_evento_regras()),
    'melhorias_tipos', case when not v_omite then fazenda_cache_ler('melhorias_tipos') end,
    'estatisticas', (select to_jsonb(e) - 'jogador_id' || jsonb_build_object('energia', e.energia + floor(j.energia_gasta)::int)
                       from fazenda_estatisticas e where e.jogador_id = p_jogador),
    'conquistas', coalesce((
      select jsonb_agg(jsonb_build_object('id', conquista, 'em', obtida_em) order by obtida_em)
        from fazenda_conquistas where jogador_id = p_jogador), '[]'::jsonb),
    'conquistas_tipos', case when not v_omite then fazenda_cache_ler('conquistas_tipos') end,
    'criado_em', j.criado_em,
    'missoes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'slot', slot, 'tipo', tipo, 'alvo', alvo, 'progresso', progresso,
               'moedas', moedas, 'xp', xp, 'resgatada', resgatada) order by slot)
        from fazenda_missoes where jogador_id = p_jogador and dia = fazenda_hoje()), '[]'::jsonb),
    'ajudantes', coalesce((
      select jsonb_agg(jsonb_build_object('tipo', h.tipo, 'nivel', h.nivel, 'relatorio', h.relatorio,
               -- fase 59: a barra de energia, o descanso e o que fez hoje e ontem
               'energia', round(h.energia::numeric, 1), 'custo', round((100 / (fazenda_ritmo(h.nivel) * 8))::numeric, 3),
               'descanso_ate', h.descanso_ate, 'descanso_motivo', h.descanso_motivo, 'descanso_casa', h.descanso_casa,
               'hoje', coalesce((select f.feito from fazenda_ajudantes_feito f where f.jogador_id = p_jogador and f.tipo = h.tipo and f.dia = fazenda_hoje()), '{}'::jsonb),
               'ontem', coalesce((select f.feito from fazenda_ajudantes_feito f where f.jogador_id = p_jogador and f.tipo = h.tipo and f.dia = fazenda_hoje() - 1), '{}'::jsonb)))
        from fazenda_ajudantes h where h.jogador_id = p_jogador), '[]'::jsonb),
    'ajudantes_tipos', case when not v_omite then fazenda_cache_ler('ajudantes_tipos') end
  );
  -- o relatório (o que fizeram enquanto você estava fora) aparece uma vez só
  update fazenda_ajudantes set relatorio = 0 where jogador_id = p_jogador and relatorio > 0;
  update fazenda_convites set visto = true where dono_id = p_jogador and not visto;   -- idem os amigos novos
  update fazenda_feira set visto = true where vendedor_id = p_jogador and vendido_em is not null and not visto;   -- e as vendas da feira
  update fazenda_semana_premios set visto = true where jogador_id = p_jogador and not visto;   -- e os prêmios do evento (fase 63)
  update fazenda_murchas set visto = true where jogador_id = p_jogador and not visto;   -- e o relatório das murchas (fase 66)
  update fazenda_feira set reserva_vista = true where reservado_para = p_jogador and not reserva_vista;   -- e o que separaram no chat (fase 67)
  update fazenda_radiacao set visto = true where jogador_id = p_jogador and not visto;   -- e a radiação do reator (fase 68)
  update fazenda_clima_eventos set visto = true where jogador_id = p_jogador and not visto;   -- e o raio e o furacão (fase 77)
  -- fase 89: sem os catálogos que o jogo já tem; mandou tudo para a sessão leve: guarda a versão que ela tem agora
  if v_omite then
    v_json := v_json - array['zonas_venda', 'culturas', 'animais_tipos', 'itens', 'melhorias_tipos', 'conquistas_tipos', 'ajudantes_tipos'];
    v_ver := current_setting('fazenda.cat_ver', true);
  else
    v_ver := fazenda_catalogos_ver(v_nivel);
    if v_leve then
      update fazenda_sessoes set cat_ver = v_ver where token_hash = current_setting('fazenda.sessao', true) and cat_ver is distinct from v_ver;
      perform set_config('fazenda.cat_ver', v_ver, true);
    end if;
  end if;
  perform fazenda_recados_anuais_entregar(p_jogador);   -- fase 115: o recado do dia (todo ano)
  return v_json || jsonb_build_object('cat_ver', v_ver,
    -- fase 115: hoje é o Dia dos Namorados da Fazendinha (11/11)? e quantas Viih ainda dá para plantar
    'dia_especial', case when to_char(fazenda_hoje(), 'MM-DD') = '11-11' then 'namorados' end,
    'viih_restam', greatest(0, 11 - coalesce((select v.plantadas from fazenda_viih_plantio v where v.jogador_id = p_jogador
                                                and v.ano = extract(year from fazenda_hoje())::int), 0)),
    -- fase 114: os recados particulares ainda não lidos (só os seus: o estado é sempre o do próprio jogador)
    'recados', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'titulo', r.titulo, 'texto', r.texto, 'de', r.de,
                                                             'diamantes', r.diamantes, 'em', r.criado_em) order by r.id)
                           from fazenda_recados r where r.jogador_id = p_jogador and r.visto_em is null), '[]'::jsonb));
end;
$$;


select public.fazenda_cache_montar();

-- conferência: tem que aparecer "fase 115 ok" e a Viih
select case when exists (select 1 from pg_proc where proname = 'fazenda_flor_vender')
             and (select prosrc from pg_proc where proname = 'fazenda_aplicar') like '%fazenda_so_dia_plantar%'
            then 'fase 115 ok' else 'não aplicou' end as resultado,
       (select nome || ' (só no ' || so_dia || ')' from public.fazenda_culturas where id = 'viih') as flor;
