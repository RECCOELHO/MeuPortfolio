-- ============================================================
-- FAZENDINHA — Fase 123 (a loja de raros sem o limite por semana e com o preço 3x), só o que mudou.
-- Para o banco que já está no ar (com a fase 122): Supabase > SQL Editor > colar este arquivo > Run.
-- Rode ANTES do merge do PR (o jogo novo mostra o preço com o "mult" que vem daqui).
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- ------------------------------------------------------------
-- Fase 123: a loja de materiais raros (diamantes) sem o limite de 2 por semana, e cada raro custa 3x
-- (1 diamante a cada 10 mil do valor, vezes 3: pérola negra 15, madeira nobre 30, âncora 90).
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------

-- as funções que mudaram

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
           "raros": {"por": 10000, "mult": 3,
                     "itens": ["madeira_nobre", "corda_naval", "pedra_cantaria", "ferro_forjado", "ancora", "leme_dourado", "perola_negra", "luva_perks"]}}'::jsonb;   -- fase 84: a loja de raros (fase 123: sem limite por semana, 3x o preço)   -- fase 79: 10 diamantes = 2.000 moedas por nível
$$;


-- fase 84 (D9): compra 1 material raro com diamantes (1 💎 a cada 10 mil do preço de venda), até 2 por semana
create or replace function public.fazenda_comprar_raro(p_token text, p_item text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_l     jsonb := fazenda_loja_diamantes()->'raros';
  v_preco int;
begin
  if v_l is null or not (v_l->'itens' ? p_item) then raise exception 'item_invalido'; end if;
  perform 1 from fazenda_jogadores where id = v_id for update;   -- (dois toques juntos: um só passa)
  select ceil(venda / (v_l->>'por')::numeric)::int * coalesce((v_l->>'mult')::int, 1) into v_preco from fazenda_culturas where id = p_item;   -- fase 123: 3x, sem limite
  if v_preco is null then raise exception 'item_invalido'; end if;
  if (select diamantes from fazenda_jogadores where id = v_id) < v_preco then raise exception 'diamantes_insuficientes'; end if;
  update fazenda_jogadores set diamantes = diamantes - v_preco where id = v_id;
  insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, p_item, 1)
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
  insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, 'raro:' || p_item, v_preco);
  return jsonb_build_object('item', p_item, 'diamantes', v_preco, 'estado', fazenda_estado(v_id));
end;
$$;


-- conferência: tem que aparecer "fase 123 ok" e os preços novos
select case when (public.fazenda_loja_diamantes()->'raros'->>'mult') = '3'
             and (select prosrc from pg_proc where proname = 'fazenda_comprar_raro') not like '%limite_semana%'
            then 'fase 123 ok' else 'não aplicou' end as resultado,
       (select string_agg(nome || ' ' || ceil(venda / 10000.0)::int * 3, ', ' order by venda)
          from public.fazenda_culturas where id in (select jsonb_array_elements_text(public.fazenda_loja_diamantes()->'raros'->'itens'))) as precos;
