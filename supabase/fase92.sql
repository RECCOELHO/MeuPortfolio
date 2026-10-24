-- ============================================================
-- FAZENDINHA — Fase 92 (o motivo das ações em massa que não deram),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 91): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 91 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_tables where tablename = 'fazenda_ajudantes_demitidos')) then
    raise exception 'Rode o fase91.sql antes deste (a fase 91 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 92: o erro que sumia. Nas ações em massa (plantar tudo, arar tudo, ajudar tudo no vizinho), cada
-- canteiro que não dava era pulado em silêncio e a resposta vinha só com "feitos: 0": no jogo, os
-- canteiros piscavam e nada acontecia, sem aviso nenhum. Agora a resposta traz "erros" com o motivo de
-- cada um ({"precisa_arar": 12, "moedas_insuficientes": 3}) e o jogo mostra o motivo mais comum.
-- ------------------------------------------------------------
-- soma +1 no motivo (o código do erro; um erro de verdade do banco entra com o começo da mensagem)
create or replace function public.fazenda_contar_erro(p_erros jsonb, p_msg text)
returns jsonb language sql immutable as $$
  select coalesce(p_erros, '{}'::jsonb)
         || jsonb_build_object(left(coalesce(p_msg, 'erro'), 80), coalesce((p_erros->>left(coalesce(p_msg, 'erro'), 80))::int, 0) + 1);
$$;

-- as funções que já existiam e mudaram

-- p_acao: arar | plantar | erva | praga | seco | colher
-- p_posicoes: um ou vários canteiros. Com um só, erros são devolvidos;
-- com vários (ações "em todos"), canteiros que não se aplicam são ignorados.
create or replace function public.fazenda_acao(p_token text, p_acao text, p_posicoes int[], p_cultura text default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id      uuid := fazenda_auth(p_token);
  v_pos     int;
  v_qtd     int;
  v_colhido jsonb := '{}'::jsonb;
  v_feitos  int := 0;
  v_erros   jsonb := '{}'::jsonb;   -- fase 92: o motivo de cada canteiro que não deu (antes sumia)
begin
  if p_posicoes is null or array_length(p_posicoes, 1) is null then
    raise exception 'nada_a_fazer';
  end if;
  if array_length(p_posicoes, 1) > 100 then
    raise exception 'acao_invalida';
  end if;

  perform fazenda_tick(v_id);

  foreach v_pos in array p_posicoes loop
    if array_length(p_posicoes, 1) = 1 then
      v_qtd := fazenda_aplicar(v_id, p_acao, v_pos, p_cultura);
      v_feitos := v_feitos + 1;
    else
      begin
        v_qtd := fazenda_aplicar(v_id, p_acao, v_pos, p_cultura);
        v_feitos := v_feitos + 1;
      exception when others then
        v_qtd := 0;
        v_erros := fazenda_contar_erro(v_erros, sqlerrm);
      end;
    end if;
    if v_qtd > 0 then
      v_colhido := v_colhido || jsonb_build_object(v_pos::text, v_qtd);
    end if;
  end loop;

  return jsonb_build_object(
    'feitos', v_feitos,
    'colhido', v_colhido,
    'erros', v_erros,
    'estado', fazenda_estado(v_id)
  );
end;
$$;

-- p_acao: pegar | ajudar. Mesmo esquema de lote do fazenda_acao.
create or replace function public.fazenda_acao_vizinho(p_token text, p_vizinho uuid, p_acao text, p_posicoes int[])
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id     uuid := fazenda_auth(p_token);
  v_pos    int;
  v_qtd    int;
  v_result jsonb := '{}'::jsonb;
  v_feitos int := 0;
  v_erros  jsonb := '{}'::jsonb;   -- fase 92
begin
  if p_vizinho is null or p_vizinho = v_id then
    raise exception 'propria_fazenda';
  end if;
  if not exists (select 1 from fazenda_jogadores where id = p_vizinho and banido_em is null) then
    raise exception 'vizinho_invalido';
  end if;
  -- fase 66: pegar_luva (a luva do Perks); fase 83: limpar (murcha), arar (vazio), colher (para o dono) e plantar:<semente>
  if p_acao not in ('pegar', 'pegar_luva', 'ajudar', 'salvar', 'limpar', 'arar', 'colher') and p_acao not like 'plantar:%' then
    raise exception 'acao_invalida';
  end if;
  if p_posicoes is null or array_length(p_posicoes, 1) is null then
    raise exception 'nada_a_fazer';
  end if;
  if array_length(p_posicoes, 1) > 100 then
    raise exception 'acao_invalida';
  end if;

  perform fazenda_tick(p_vizinho);

  foreach v_pos in array p_posicoes loop
    begin
      if p_acao in ('pegar', 'pegar_luva') then
        v_qtd := fazenda_pegar_um(v_id, p_vizinho, v_pos, p_acao = 'pegar_luva');
      elsif p_acao = 'salvar' then
        v_qtd := fazenda_salvar_um(v_id, p_vizinho, v_pos);
      elsif p_acao in ('limpar', 'arar', 'colher') or p_acao like 'plantar:%' then
        v_qtd := fazenda_roca_um(v_id, p_vizinho, v_pos, p_acao);   -- fase 83
      else
        v_qtd := fazenda_ajudar_um(v_id, p_vizinho, v_pos);
      end if;
      v_feitos := v_feitos + 1;
      v_result := v_result || jsonb_build_object(v_pos::text, v_qtd);
    exception when others then
      -- com um canteiro só, o erro volta para a tela; em lote, pula o canteiro
      if array_length(p_posicoes, 1) = 1 then
        raise;
      end if;
      v_erros := fazenda_contar_erro(v_erros, sqlerrm);
    end;
  end loop;

  perform fazenda_bot_xp_gravar();   -- fase 83: a metade do XP da colheita que vai para o dono
  return jsonb_build_object(
    'feitos', v_feitos,
    'resultado', v_result,
    'erros', v_erros,
    'vizinho', fazenda_vizinho(p_vizinho, v_id),
    'estado', fazenda_estado(v_id)
  );
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
  v_erros  jsonb := '{}'::jsonb;   -- fase 92
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
        v_erros := fazenda_contar_erro(v_erros, sqlerrm);   -- pula o que não deu (já feito, sem ração, sem moedas...)
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
  return jsonb_build_object('feitos', v_feitos, 'xp', v_total, 'resultado', v_result, 'erros', v_erros,
                            'vizinho', fazenda_vizinho(p_vizinho, v_id), 'estado', fazenda_estado(v_id));
end;
$$;

-- permissões
revoke execute on function
  public.fazenda_contar_erro(jsonb, text)
from public, anon, authenticated;

grant execute on function
  public.fazenda_acao(text, text, int[], text),
  public.fazenda_acao_vizinho(text, uuid, text, int[]),
  public.fazenda_ajudar_tudo(text, uuid, jsonb)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- a média dos geradores já pronta (as chamadas do jogo não montam mais na hora)
select public.fazenda_energia_medias_refazer() is not null as energia_medias_pronta;

-- conferência: as três respostas agora trazem 'erros'
select count(*) filter (where prosrc like '%''erros'', v_erros%') as funcoes_com_erros from pg_proc where proname in ('fazenda_acao', 'fazenda_acao_vizinho', 'fazenda_ajudar_tudo');
