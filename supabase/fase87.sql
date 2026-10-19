-- ============================================================
-- FAZENDINHA — Fase 87 (o Ajudar tudo gravando menos),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 86): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 86 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_ajudar_tudo')) then
    raise exception 'Rode o fase86.sql antes deste (a fase 86 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 87: o banco travou sem memória (1 GB, swap cheio, o disco não dava conta). O Ajudar tudo gravava
-- a linha inteira de quem ajuda (e a missão) a cada item: 100 itens, umas 200 gravações. Agora o XP, as
-- moedas, a semente paga e a missão somam num lote (fazenda.ajuda_lote) e gravam uma vez só no fim.
-- A conta é a mesma (teto do dia, 1/4 depois, sequência, abandonada, regra por canteiro).
-- ------------------------------------------------------------

-- as funções que já existiam e mudaram

-- fase 87: a missão "ajudar" de cada item; no lote do Ajudar tudo, soma e conta uma vez só no fim
create or replace function public.fazenda_missao_ajuda(p_ator uuid, p_n int)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_lote jsonb := nullif(current_setting('fazenda.ajuda_lote', true), '')::jsonb;
begin
  if v_lote is null then perform fazenda_missao(p_ator, 'ajudar', p_n); return; end if;
  perform set_config('fazenda.ajuda_lote', (v_lote || jsonb_build_object('missao', (v_lote->>'missao')::int + p_n))::text, true);
end;
$$;

-- fase 87: quem ajuda paga a semente (plantar na abandonada); no lote, o gasto sai no fim
create or replace function public.fazenda_lote_gastar(p_ator uuid, p_custo int)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_lote jsonb := nullif(current_setting('fazenda.ajuda_lote', true), '')::jsonb;
begin
  if v_lote is null then
    if (select moedas from fazenda_jogadores where id = p_ator) < p_custo then raise exception 'moedas_insuficientes'; end if;
    update fazenda_jogadores set moedas = moedas - p_custo where id = p_ator;
    return;
  end if;
  if (select moedas from fazenda_jogadores where id = p_ator) + (v_lote->>'moedas')::int - (v_lote->>'gasto')::int < p_custo then
    raise exception 'moedas_insuficientes';
  end if;
  perform set_config('fazenda.ajuda_lote', (v_lote || jsonb_build_object('gasto', (v_lote->>'gasto')::int + p_custo))::text, true);
end;
$$;

-- Dá o prêmio de p_unidades ajudas; devolve o XP. Fase 83: sem o limite de 30 por dia, e com a
-- sequência de vizinhos: cada vizinho diferente ajudado em até 10 min do anterior dá +10% (até +100%);
-- 10 min sem ajudar, ela zera. O XP em dobro e os bônus de nível somam por cima (gatilho do XP).
create or replace function public.fazenda_premiar_ajuda(p_ator uuid, p_unidades int, p_dono uuid)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  j      record;
  v_seq  uuid[];
  v_xp   int;
  v_base int;
  v_un   int;
  v_cheio int;
  v_dia  int;
  v_lote jsonb;
begin
  if coalesce(p_unidades, 0) <= 0 then return 0; end if;
  -- fase 87: dentro do Ajudar tudo (fazenda_ajudar_tudo) a conta é a mesma, mas o XP e as moedas somam no
  -- lote e gravam uma vez só no fim (antes, cada item regravava a linha inteira do jogador)
  v_lote := nullif(current_setting('fazenda.ajuda_lote', true), '')::jsonb;
  if v_lote is not null then
    v_seq := array(select jsonb_array_elements_text(v_lote->'seq'))::uuid[];
  else
    select seq_donos, seq_em, xp, ajuda_dia, ajuda_xp_dia into j from fazenda_jogadores where id = p_ator for update;
    v_seq := case when j.seq_em is null or j.seq_em < now() - interval '10 minutes' then '{}'::uuid[] else coalesce(j.seq_donos, '{}') end;
  end if;
  if p_dono is not null and not (p_dono = any(v_seq)) then v_seq := v_seq || p_dono; end if;
  -- fase 86: sem o limite de 30 por vizinho (fase 85); quem segura é o canteiro (fazenda_roca_um) e o teto do dia
  v_un := p_unidades;
  v_base := round(v_un * fazenda_premio_ajuda(p_ator) * (1 + fazenda_sequencia_bonus(cardinality(v_seq)))
                  * case when fazenda_abandonada(p_dono) then 1.25 else 1 end)::int;   -- fazenda abandonada: +25% (fase 85; era +50%)
  -- fase 85: até 1 nível de XP de ajuda por dia vale cheio; o que passar disso vale 1/4
  v_dia := case when v_lote is not null then (v_lote->>'dia')::int
                when j.ajuda_dia = fazenda_hoje() then coalesce(j.ajuda_xp_dia, 0) else 0 end;
  v_cheio := greatest(0, coalesce((v_lote->>'teto')::int, fazenda_ajuda_teto(p_ator)) - v_dia);
  v_xp := least(v_base, v_cheio) + (v_base - least(v_base, v_cheio)) / 4;
  if v_lote is not null then
    perform set_config('fazenda.ajuda_lote', (v_lote || jsonb_build_object('seq', to_jsonb(v_seq), 'dia', v_dia + v_xp,
      'xp', (v_lote->>'xp')::int + v_xp, 'moedas', (v_lote->>'moedas')::int + p_unidades))::text, true);
    return v_xp;
  end if;
  update fazenda_jogadores set xp = xp + v_xp, moedas = moedas + p_unidades, seq_donos = v_seq, seq_em = now(),
         ajuda_dia = fazenda_hoje(), ajuda_xp_dia = v_dia + v_xp
   where id = p_ator;
  return v_xp;
end;
$$;

-- Fase 48: o vizinho salva uma planta murcha (1 por dia em cada fazenda): ela volta madura, sem
-- problemas, com o tempo todo para colher. Vale 3 ajudas. Devolve o XP.
create or replace function public.fazenda_salvar_um(p_ator uuid, p_dono uuid, p_posicao int)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  c   record;
  k   record;
  v_xp int;
begin
  select * into c from fazenda_canteiros where jogador_id = p_dono and posicao = p_posicao for update;
  if not found or c.estado <> 'plantado' then raise exception 'nada_a_fazer'; end if;
  select * into k from fazenda_culturas where id = c.cultura;
  if now() < c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) then
    raise exception 'nada_a_fazer';   -- não está murcha
  end if;
  if (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'salvar'
        and criado_em > now() - interval '1 day') >= 2 then
    raise exception 'ja_salvou';
  end if;
  update fazenda_canteiros
     set plantado_em = now() - make_interval(secs => k.tempo_seg), erva = false, praga = false, seco = false, prox_evento = null
   where jogador_id = p_dono and posicao = p_posicao;
  v_xp := fazenda_premiar_ajuda(p_ator, 3, p_dono);
  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd, xp)
  values (p_ator, p_dono, 'salvar', p_posicao, now() - make_interval(secs => k.tempo_seg), k.id, 3, v_xp);
  perform fazenda_missao_ajuda(p_ator, 3);
  return v_xp;
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
    if fazenda_nivel((select xp from fazenda_jogadores where id = p_ator)) < k.nivel_min then raise exception 'nivel_insuficiente'; end if;
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

create or replace function public.fazenda_ajudar_um(p_ator uuid, p_dono uuid, p_posicao int)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  c         record;
  k         record;
  v_n       int;
  v_hoje    int;
  v_premio  int;
begin
  select * into c from fazenda_canteiros
   where jogador_id = p_dono and posicao = p_posicao
     for update;
  if not found or c.estado <> 'plantado' then
    raise exception 'nada_a_fazer';
  end if;
  select * into k from fazenda_culturas where id = c.cultura;
  if now() >= c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) then
    raise exception 'nada_a_fazer';
  end if;
  v_n := c.erva::int + c.praga::int + c.seco::int;
  if v_n = 0 then
    raise exception 'nada_a_fazer';
  end if;

  update fazenda_canteiros set erva = false, praga = false, seco = false
   where jogador_id = p_dono and posicao = p_posicao;

  -- fase 48: o XP de cada uma cresce com o nível de quem ajuda (fazenda_premio_ajuda); fase 83: sem limite
  v_premio := fazenda_premiar_ajuda(p_ator, v_n, p_dono);

  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd, xp)
  values (p_ator, p_dono, 'ajuda', p_posicao, c.plantado_em, k.id, v_n, v_premio);
  perform fazenda_missao_ajuda(p_ator, v_n);

  return v_premio;   -- (fase 48: o XP ganho; antes, os problemas)
end;
$$;

-- Fase 86: o "Ajudar tudo" numa chamada só. Eram até 8 (ajudar, colher, salvar, limpar, arar, plantar,
-- ração e coleta) e cada uma devolvia o estado inteiro de quem ajuda, o que mais pesa no servidor: com
-- muita gente ajudando, o banco ficou lento para todo mundo. p_lista:
--   {"ajudar":[pos], "colher":[pos], "salvar":[pos], "limpar":[pos], "arar":[pos], "plantar":[pos],
--    "semente":"<id>", "bicho":[animal], "coleta":[animal]}
-- Faz na ordem do jogo; o que der erro é pulado (como em lote). Devolve, por ação, quantos fez, o XP
-- e o XP de cada canteiro (ou bicho).
create or replace function public.fazenda_ajudar_tudo(p_token text, p_vizinho uuid, p_lista jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id     uuid := fazenda_auth(p_token);
  v_acao   text;
  v_item   bigint;
  v_xp     int;
  v_um     jsonb;
  v_n      int;
  v_soma   int;
  v_bichos int := 0;
  v_feitos jsonb := '{}'::jsonb;
  v_total  jsonb := '{}'::jsonb;
  v_result jsonb := '{}'::jsonb;
  v_lote   jsonb;
  j        record;
begin
  if p_vizinho is null or p_vizinho = v_id then raise exception 'propria_fazenda'; end if;
  if not exists (select 1 from fazenda_jogadores where id = p_vizinho and banido_em is null) then raise exception 'vizinho_invalido'; end if;
  if p_lista is null or jsonb_typeof(p_lista) <> 'object' then raise exception 'nada_a_fazer'; end if;
  if (select coalesce(sum(jsonb_array_length(v)), 0) from jsonb_each(p_lista) e(k, v) where jsonb_typeof(v) = 'array') > 400 then
    raise exception 'acao_invalida';
  end if;

  perform fazenda_tick(p_vizinho);

  -- fase 87: o lote (o XP, as moedas e a missão somam aqui e gravam uma vez só no fim)
  select seq_donos, seq_em, ajuda_dia, ajuda_xp_dia into j from fazenda_jogadores where id = v_id for update;
  perform set_config('fazenda.ajuda_lote', jsonb_build_object(
    'seq', case when j.seq_em is null or j.seq_em < now() - interval '10 minutes' then '[]'::jsonb else to_jsonb(coalesce(j.seq_donos, '{}')) end,
    'dia', case when j.ajuda_dia = fazenda_hoje() then coalesce(j.ajuda_xp_dia, 0) else 0 end,
    'teto', fazenda_ajuda_teto(v_id), 'xp', 0, 'moedas', 0, 'gasto', 0, 'missao', 0)::text, true);

  foreach v_acao in array array['ajudar', 'colher', 'salvar', 'limpar', 'arar', 'plantar', 'bicho', 'coleta'] loop
    continue when jsonb_typeof(p_lista->v_acao) is distinct from 'array';
    v_um := '{}'::jsonb; v_n := 0; v_soma := 0;
    for v_item in select (x #>> '{}')::bigint from jsonb_array_elements(p_lista->v_acao) x loop
      begin
        v_xp := case v_acao
          when 'ajudar'  then fazenda_ajudar_um(v_id, p_vizinho, v_item::int)
          when 'salvar'  then fazenda_salvar_um(v_id, p_vizinho, v_item::int)
          when 'plantar' then fazenda_roca_um(v_id, p_vizinho, v_item::int, 'plantar:' || coalesce(p_lista->>'semente', ''))
          when 'bicho'   then fazenda_vizinho_bicho_um(v_id, p_vizinho, v_item)
          when 'coleta'  then fazenda_vizinho_coletar_um(v_id, p_vizinho, v_item)
          else fazenda_roca_um(v_id, p_vizinho, v_item::int, v_acao) end;   -- colher, limpar, arar
        v_um := v_um || jsonb_build_object(v_item::text, v_xp);
        v_n := v_n + 1;
        v_soma := v_soma + v_xp;
      exception when others then
        null;   -- pula o que não deu (já feito, sem ração, sem moedas...)
      end;
    end loop;
    if v_n > 0 then
      v_feitos := v_feitos || jsonb_build_object(v_acao, v_n);
      v_total := v_total || jsonb_build_object(v_acao, v_soma);
      v_result := v_result || jsonb_build_object(v_acao, v_um);
      if v_acao in ('bicho', 'coleta') then v_bichos := v_bichos + v_n; end if;
    end if;
  end loop;

  v_lote := current_setting('fazenda.ajuda_lote')::jsonb;
  perform set_config('fazenda.ajuda_lote', '', true);
  if (v_lote->>'moedas')::int > 0 or (v_lote->>'gasto')::int > 0 then
    update fazenda_jogadores
       set xp = xp + (v_lote->>'xp')::int, moedas = moedas + (v_lote->>'moedas')::int - (v_lote->>'gasto')::int,
           seq_donos = array(select jsonb_array_elements_text(v_lote->'seq'))::uuid[], seq_em = now(),
           ajuda_dia = fazenda_hoje(), ajuda_xp_dia = (v_lote->>'dia')::int
     where id = v_id;
  end if;
  if (v_lote->>'missao')::int + v_bichos > 0 then perform fazenda_missao(v_id, 'ajudar', (v_lote->>'missao')::int + v_bichos); end if;
  perform fazenda_bot_xp_gravar();   -- a metade do XP da colheita que vai para o dono
  return jsonb_build_object('feitos', v_feitos, 'xp', v_total, 'resultado', v_result,
                            'vizinho', fazenda_vizinho(p_vizinho, v_id), 'estado', fazenda_estado(v_id));
end;
$$;

-- permissões
revoke execute on function
  public.fazenda_missao_ajuda(uuid, int),
  public.fazenda_lote_gastar(uuid, int),
  public.fazenda_premiar_ajuda(uuid, int, uuid),
  public.fazenda_salvar_um(uuid, uuid, int),
  public.fazenda_roca_um(uuid, uuid, int, text),
  public.fazenda_ajudar_um(uuid, uuid, int)
from public, anon, authenticated;

grant execute on function
  public.fazenda_ajudar_tudo(text, uuid, jsonb)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- a média dos geradores já pronta (as chamadas do jogo não montam mais na hora)
select public.fazenda_energia_medias_refazer() is not null as energia_medias_pronta;

-- conferência: deve aparecer "Fase 87: Ajudar tudo gravando uma vez só"
select 'Fase 87: Ajudar tudo gravando uma vez só' as ok where exists (select 1 from pg_proc where proname = 'fazenda_missao_ajuda');
