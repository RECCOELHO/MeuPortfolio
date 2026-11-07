-- ============================================================
-- FAZENDINHA — Fase 122 (o XP em porcentagem do nível mais equilibrado: ajuda, pacote de XP e calendário),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 121): Supabase > SQL Editor > colar este arquivo > Run.
-- Pode rodar antes do merge do PR (o jogo mostra os números que vêm do servidor).
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 121 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not exists (select 1 from pg_proc where proname = 'fazenda_murcha_seg') then
    raise exception 'Rode o fase121.sql antes deste. Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 122: o XP que vem em porcentagem do nível estava forte demais (quanto mais alto o nível, mais ele dava).
-- • Ajudar vizinho: cada ajuda vale 0,15% do nível (era 0,3%) e o teto do dia é 1/4 de nível (era 1 nível
--   inteiro); passou do teto, a ajuda só dá as moedas (antes ainda dava 1/4 do XP, sem limite).
-- • Pacote de XP (diamantes): 5% do nível (era 10%), até 3 por dia.
-- • Calendário dourado: o XP de 10% do nível vira 5%.
-- Continuam: as missões (1,5% cada), as obras da ilha (8% cada, uma por nível) e o XP das colheitas.
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------

-- as funções que mudaram

-- Tira os problemas de um canteiro do vizinho. Retorna quantos problemas resolveu.
-- Fase 48: quanto XP vale cada ajuda a um vizinho: 0,25% do nível de quem ajuda (pelo menos 2)
-- fase 83: 0,30% (e sem o limite de 30 por dia)
create or replace function public.fazenda_premio_ajuda(p_ator uuid)
returns int language sql stable security definer set search_path = public as $$
  select greatest(2, round((fazenda_xp_nivel(n + 1) - fazenda_xp_nivel(n)) * 0.0015))::int   -- fase 122: 0,15% (era 0,3%)
    from (select fazenda_nivel_de(xp, nivel_trava) as n from fazenda_jogadores where id = p_ator) x;
$$;


-- fase 85: quantas ajudas (unidades) o ator já fez hoje na fazenda desse dono
create or replace function public.fazenda_ajudas_hoje(p_ator uuid, p_dono uuid)
returns int language plpgsql stable security definer set search_path = public as $$
begin   -- (plpgsql: fazenda_hoje vem mais adiante no arquivo)
  return (select coalesce(sum(qtd + case when tipo = 'plantar' then 1 else 0 end), 0)::int from fazenda_visitas   -- (plantar vale 2)
           where ator_id = p_ator and dono_id = p_dono and tipo <> 'roubo'
             and criado_em >= (fazenda_hoje()::timestamp at time zone 'America/Sao_Paulo'));
end;
$$;
-- fase 85: o teto do dia (o XP de 1 nível inteiro do ator)
create or replace function public.fazenda_ajuda_teto(p_ator uuid)
returns int language sql stable security definer set search_path = public as $$
  select round((fazenda_xp_nivel(n + 1) - fazenda_xp_nivel(n)) * 0.25)::int from   -- fase 122: 1/4 de nível (era 1 inteiro)
  (select fazenda_nivel_de(xp, nivel_trava) as n from fazenda_jogadores where id = p_ator) x;
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
  -- (fase 93: em if separado. Dentro do Ajudar tudo o j não é lido do banco, e citar j.ajuda_dia na mesma
  -- expressão, mesmo no ramo que não roda, dava "record j is not assigned yet" em todo canteiro)
  if v_lote is not null then
    v_dia := (v_lote->>'dia')::int;
  else
    v_dia := case when j.ajuda_dia = fazenda_hoje() then coalesce(j.ajuda_xp_dia, 0) else 0 end;
  end if;
  v_cheio := greatest(0, coalesce((v_lote->>'teto')::int, fazenda_ajuda_teto(p_ator)) - v_dia);
  v_xp := least(v_base, v_cheio);   -- fase 122: passou do teto do dia, a ajuda não dá mais XP (era 1/4, sem fim)
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


create or replace function public.fazenda_loja_diamantes()
returns jsonb language sql immutable as $$
  -- fase 72: o café dura 4 h; 1 diamante enche 150 ⚡; salvar murchas, 1 a cada 25 plantas; colher
  -- agora, 1 a cada 4 h que faltam
  select '{"xp2": {"preco": 15, "horas": 1},
           "xp": {"preco": 10, "pct": 5, "por_dia": 3},
           "cafe": {"preco": 10, "horas": 4},
           "energia": {"por": 150},
           "oficina": {"por_hora": 1},
           "murchas": {"preco": 1, "por": 25},
           "agora": {"horas": 4},
           "moedas": {"preco": 10, "por_nivel": 2000},
           "raros": {"por": 10000, "por_semana": 2,
                     "itens": ["madeira_nobre", "corda_naval", "pedra_cantaria", "ferro_forjado", "ancora", "leme_dourado", "perola_negra", "luva_perks"]}}'::jsonb;   -- fase 84: a loja de raros   -- fase 79: 10 diamantes = 2.000 moedas por nível
$$;


-- os prêmios de cada dia: g = grátis, d = dourada. moedas: vezes o nível; xp: % do nível; xp2 e cafe: minutos
create or replace function public.fazenda_calendario_premios()
returns jsonb language sql immutable as $$
  select '[
    {"g": [{"tipo": "moedas", "qtd": 15}],    "d": [{"tipo": "moedas", "qtd": 50}]},
    {"g": [{"tipo": "xp", "qtd": 3}],         "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "moedas", "qtd": 20}],    "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "cafe", "qtd": 30}],      "d": [{"tipo": "xp", "qtd": 5}]},
    {"g": [{"tipo": "moedas", "qtd": 25}],    "d": [{"tipo": "moedas", "qtd": 60}]},
    {"g": [{"tipo": "xp2", "qtd": 30}],       "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "diamantes", "qtd": 3}],  "d": [{"tipo": "diamantes", "qtd": 10}, {"tipo": "item", "item": "madeira_nobre", "qtd": 1}]},
    {"g": [{"tipo": "moedas", "qtd": 20}],    "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "xp", "qtd": 4}],         "d": [{"tipo": "moedas", "qtd": 70}]},
    {"g": [{"tipo": "moedas", "qtd": 25}],    "d": [{"tipo": "xp", "qtd": 5}]},
    {"g": [{"tipo": "cafe", "qtd": 30}],      "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "moedas", "qtd": 30}],    "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "xp2", "qtd": 30}],       "d": [{"tipo": "moedas", "qtd": 80}]},
    {"g": [{"tipo": "diamantes", "qtd": 5}],  "d": [{"tipo": "diamantes", "qtd": 10}, {"tipo": "item", "item": "perola_negra", "qtd": 1}]},
    {"g": [{"tipo": "moedas", "qtd": 25}],    "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "xp", "qtd": 5}],         "d": [{"tipo": "xp", "qtd": 5}]},
    {"g": [{"tipo": "moedas", "qtd": 30}],    "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "cafe", "qtd": 45}],      "d": [{"tipo": "moedas", "qtd": 90}]},
    {"g": [{"tipo": "moedas", "qtd": 35}],    "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "xp2", "qtd": 45}],       "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "diamantes", "qtd": 5}],  "d": [{"tipo": "diamantes", "qtd": 10}, {"tipo": "item", "item": "corda_naval", "qtd": 1}, {"tipo": "item", "item": "pedra_cantaria", "qtd": 1}]},
    {"g": [{"tipo": "moedas", "qtd": 30}],    "d": [{"tipo": "xp", "qtd": 5}]},
    {"g": [{"tipo": "xp", "qtd": 5}],         "d": [{"tipo": "moedas", "qtd": 100}]},
    {"g": [{"tipo": "moedas", "qtd": 40}],    "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "cafe", "qtd": 60}],      "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "moedas", "qtd": 45}],    "d": [{"tipo": "xp", "qtd": 5}]},
    {"g": [{"tipo": "xp2", "qtd": 60}],       "d": [{"tipo": "moedas", "qtd": 120}]},
    {"g": [{"tipo": "diamantes", "qtd": 10}], "d": [{"tipo": "avatar", "avatar": "fazendeiro_ouro"}, {"tipo": "diamantes", "qtd": 20}]}
  ]'::jsonb;
$$;


-- conferência: tem que aparecer "fase 122 ok"
select case when (select prosrc from pg_proc where proname = 'fazenda_premio_ajuda') like '%0.0015%'
             and (select prosrc from pg_proc where proname = 'fazenda_ajuda_teto') like '%0.25%'
             and (select prosrc from pg_proc where proname = 'fazenda_loja_diamantes') like '%"pct": 5%'
            then 'fase 122 ok' else 'não aplicou' end as resultado;
