-- ============================================================
-- FAZENDINHA — Fase 110 (bandeiras novas e velas coloridas na pintura do barco), só o que mudou.
-- Para o banco que já está no ar (com a fase 109): Supabase > SQL Editor > colar este arquivo > Run.
-- Rode ANTES do merge do PR.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 109 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not exists (select 1 from pg_proc where proname = 'fazenda_reserva_gastar') then
    raise exception 'Rode o fase109.sql antes deste. Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 110: bandeiras novas e velas coloridas. A pintura do barco (fazenda_barco_pintar) ganha a cor das
-- velas (as mesmas cores do casco; a dourada pede 1 pérola negra, como as outras) e 9 bandeiras: âncora,
-- lua, peixe, caveira dourada, arco-íris, listrada, fazendinha, coroa e raio (fazenda_barco_cores). Cada
-- mudança continua custando 20 mil. Quem já pintou fica com o que tem (sem vela = a de lona).
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------

-- as funções que mudaram

-- ------------------------------------------------------------
-- Fase 65: a tunagem do barco (até o nível 45, para as ilhas do 46).
-- • Peças (melhorias do mar com peca = true, em fazenda_melhorias_tipos): motor (o cardume enche mais
--   rápido), sonar (mais peixe grande e mais pérola), porão (às vezes 2 peixes numa fisgada), rede de
--   arrasto (o marinheiro pesca mais rápido) e o kit de expedição (deixa o barco oceânico pronto para as
--   ilhas). Cada nível pede moedas e materiais raros (do mercador, a pérola negra e o marlim-azul) e
--   aparece no desenho do barco. A compra é a de sempre: fazenda_comprar(…, 'melhoria', …).
-- • A pintura: a cor do casco e da faixa e a bandeira (barco_visual). 20 mil moedas por mudança; o
--   dourado pede 1 pérola negra.
-- ------------------------------------------------------------
create or replace function public.fazenda_barco_cores()
returns jsonb language sql immutable as $$
  select '{"preco": 20000, "dourado": "perola_negra",
           "cores": ["padrao", "branco", "azul", "vermelho", "verde", "amarelo", "preto", "roxo", "rosa", "dourado"],
           "bandeiras": ["padrao", "brasil", "pirata", "xadrez", "coracao", "estrela", "sertao",
                         "ancora", "lua", "peixe", "caveira_dourada", "arco_iris", "listrada", "fazendinha", "coroa", "raio"]}'::jsonb;   -- fase 110: + 9
$$;


create or replace function public.fazenda_barco_pintar(p_token text, p_visual jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id      uuid := fazenda_auth(p_token);
  v_cat     jsonb := fazenda_barco_cores();
  j         record;
  v_atual   jsonb;
  v_novo    jsonb;
  v_mud     int := 0;
  v_perolas int := 0;
  k         text;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  if j.pier_em is null then raise exception 'sem_pier'; end if;
  v_atual := coalesce(j.barco_visual, '{}'::jsonb);
  v_novo := jsonb_build_object('casco', coalesce(p_visual->>'casco', 'padrao'), 'faixa', coalesce(p_visual->>'faixa', 'padrao'),
                               'vela', coalesce(p_visual->>'vela', 'padrao'),   -- fase 110: a cor das velas
                               'bandeira', coalesce(p_visual->>'bandeira', 'padrao'));
  if not (v_cat->'cores' ? (v_novo->>'casco')) or not (v_cat->'cores' ? (v_novo->>'faixa'))
     or not (v_cat->'cores' ? (v_novo->>'vela')) or not (v_cat->'bandeiras' ? (v_novo->>'bandeira')) then
    raise exception 'cor_invalida';
  end if;
  foreach k in array array['casco', 'faixa', 'vela', 'bandeira'] loop
    if v_novo->>k is distinct from coalesce(v_atual->>k, 'padrao') then
      v_mud := v_mud + 1;
      if v_novo->>k = 'dourado' then v_perolas := v_perolas + 1; end if;
    end if;
  end loop;
  if v_mud = 0 then raise exception 'nada_mudou'; end if;
  if j.moedas < v_mud * (v_cat->>'preco')::int then raise exception 'moedas_insuficientes'; end if;
  if v_perolas > 0 and coalesce((select quantidade from fazenda_celeiro where jogador_id = v_id and item = v_cat->>'dourado'), 0)
                       - coalesce((select quantidade from fazenda_reservas where jogador_id = v_id and item = v_cat->>'dourado'), 0) < v_perolas then
    raise exception 'faltam_materiais';
  end if;
  update fazenda_celeiro set quantidade = quantidade - v_perolas where v_perolas > 0 and jogador_id = v_id and item = v_cat->>'dourado';
  update fazenda_jogadores set moedas = moedas - v_mud * (v_cat->>'preco')::int, barco_visual = v_novo where id = v_id;
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;


-- conferência: tem que aparecer "fase 110 ok" e 16 bandeiras
select case when (select prosrc from pg_proc where proname = 'fazenda_barco_pintar') like '%''vela''%'
            then 'fase 110 ok' else 'não aplicou' end as resultado,
       jsonb_array_length(public.fazenda_barco_cores()->'bandeiras') as bandeiras;
