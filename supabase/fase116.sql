-- ============================================================
-- FAZENDINHA — Fase 116 (os bichos da ilha: a tartaruga e o papagaio, com cercado), só o que mudou.
-- Para o banco que já está no ar (com a fase 115): Supabase > SQL Editor > colar este arquivo > Run.
-- Rode ANTES do merge do PR.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 115 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not exists (select 1 from pg_proc where proname = 'fazenda_flor_vender') then
    raise exception 'Rode o fase115.sql antes deste. Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 116: os bichos da ilha (desenhos do Jessé), com cercado só na ilha (so_ilha) e sem travar o nível.
-- • Tartaruga (47): mora no tanque (com laguinho), come 2 abacaxis e traz 1 concha da praia a cada 6 h.
-- • Papagaio (52): mora no viveiro (com poleiro), come 2 bananas e solta 1 pena de arara a cada 8 h.
-- Até 5 de cada, como os outros bichos. Pode rodar este arquivo de novo.
-- ------------------------------------------------------------
insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('concha',     'Concha',        '🐚', 1, 0,  1500, 1, 150, 47, 117, 'produto'),
  ('pena_arara', 'Pena de arara', '🪶', 1, 0,  2600, 1, 260, 52, 118, 'produto')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, venda = excluded.venda, xp = excluded.xp,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;
insert into public.fazenda_animais_tipos (id, nome, custo, nivel_min, maximo, produto, tempo_seg, racao, racao_qtd, ordem) values
  ('tartaruga', 'Tartaruga', 15000, 47, 5, 'concha',     21600, 'abacaxi', 2, 9),
  ('papagaio',  'Papagaio',  25000, 52, 5, 'pena_arara', 28800, 'banana',  2, 10)
on conflict (id) do update set
  nome = excluded.nome, custo = excluded.custo, nivel_min = excluded.nivel_min, maximo = excluded.maximo,
  produto = excluded.produto, tempo_seg = excluded.tempo_seg, racao = excluded.racao,
  racao_qtd = excluded.racao_qtd, ordem = excluded.ordem;
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, largura, altura, efeito, limite, beleza, descricao, so_ilha) values
  ('cercado_tartaruga', 'Tanque das tartarugas', 'bichos', 60000, 47, 108, 6, 4, 'cercado', 1, 4, 'Com laguinho: precisa dele para comprar tartarugas, e elas moram aqui. Só na ilha.', true),
  ('cercado_papagaio',  'Viveiro dos papagaios', 'bichos', 90000, 52, 109, 6, 4, 'cercado', 1, 4, 'Com poleiro: precisa dele para comprar papagaios, e eles moram aqui. Só na ilha.', true)
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, largura = excluded.largura, altura = excluded.altura, efeito = excluded.efeito,
  limite = excluded.limite, beleza = excluded.beleza, descricao = excluded.descricao, so_ilha = excluded.so_ilha;

-- a função que mudou

-- ------------------------------------------------------------
-- Fase 90: só passa de nível quem tem tudo dos seus níveis (a regra votada: vale daqui para frente). O XP não
-- é mais a única coisa: para passar do nível N, o jogador precisa ter na fazenda tudo o que conta dos níveis
-- 1 a N (oficinas, cercados, máquinas, energia sem o cano e pomar; enfeites, caminhos, objetos, casas e praia
-- não contam). Ninguém caiu: o nível de cada um no dia da regra fica guardado (nivel_base) e não baixa; daí
-- para cima, só sobe quem completar o que falta. Nenhum XP sai.
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists nivel_trava int not null default 2;
alter table public.fazenda_jogadores add column if not exists nivel_base int;   -- fase 90: o nível no dia da regra (não baixa)
create or replace function public.fazenda_conta_nivel(p_categoria text, p_id text)
returns boolean language sql immutable as $$
  select p_categoria in ('oficina', 'bichos', 'maquina', 'energia', 'pomar') and p_id <> 'cano'
     and p_id not in ('bananeira', 'engenho_pirata', 'casa_especiarias', 'forno_bordo', 'despensa_navio',
                      'cercado_tartaruga', 'cercado_papagaio');   -- fase 108: as da ilha não travam (fase 116: os cercados também)
$$;


select public.fazenda_cache_montar();

-- conferência: tem que aparecer "fase 116 ok", os 2 bichos e os 2 cercados da ilha
select case when not public.fazenda_conta_nivel('bichos', 'cercado_tartaruga') then 'fase 116 ok' else 'não aplicou' end as resultado,
       (select string_agg(nome || ' (' || nivel_min || ')', ', ' order by nivel_min) from public.fazenda_animais_tipos where id in ('tartaruga', 'papagaio')) as bichos,
       (select string_agg(nome, ', ' order by nivel_min) from public.fazenda_itens where id in ('cercado_tartaruga', 'cercado_papagaio') and so_ilha) as cercados;
