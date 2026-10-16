-- ============================================================
-- FAZENDINHA — Fase 58 (etapa 2B: sementes e oficinas do nível 20 ao 30), só o que mudou.
-- Para o banco que já está no ar (com a fase 57): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================
-- ------------------------------------------------------------
-- Fase 58: sementes e oficinas em cadeia do nível 20 ao 30 (ideias de 15/10, etapa 2B).
-- A última semente da loja era a amora (nível 9); do 20 ao 25 não liberava nada. Seis sementes
-- novas (o ano todo) e oito oficinas, umas usando o produto das outras: o açúcar do engenho entra
-- no cappuccino e no bombom; o fio da fiação, na roupa (com o tecido da tecelagem); o chocolate da
-- chocolateria, no bombom. Produto vale ~1,7x os ingredientes, como nas oficinas da fase 38.
-- A arte fica em fazenda-arte.js (CULTURAS e PROPRIA 65..84; as oficinas, no pacote town).
-- ------------------------------------------------------------
insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem) values
  ('cana',     'Cana-de-açúcar', '🎋', 21600, 150,  30, 10,  45, 20, 13),
  ('cafe',     'Café',           '☕', 28800, 200,  40,  9,  55, 22, 14),
  ('algodao',  'Algodão',        '☁️', 36000, 240,  45,  9,  65, 23, 15),
  ('uva',      'Uva',            '🍇', 43200, 300,  55, 10,  80, 25, 16),
  ('pimenta',  'Pimenta',        '🌶️', 14400, 180,  35,  8,  40, 27, 17),
  ('baunilha', 'Baunilha',       '🌼', 57600, 500, 120,  6, 120, 30, 18)
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, tempo_seg = excluded.tempo_seg,
  custo = excluded.custo, venda = excluded.venda, rendimento = excluded.rendimento,
  xp = excluded.xp, nivel_min = excluded.nivel_min, ordem = excluded.ordem;

insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('acucar',        'Açúcar',         '🧂', 1, 0,  205, 1,  20, 21, 74, 'produto'),
  ('cafe_torrado',  'Café torrado',   '☕', 1, 0,  205, 1,  20, 22, 75, 'produto'),
  ('fio',           'Fio de algodão', '🧵', 1, 0,  305, 1,  30, 23, 76, 'produto'),
  ('cappuccino',    'Cappuccino',     '☕', 1, 0,  815, 1,  80, 24, 77, 'produto'),
  ('roupa',         'Roupa',          '👕', 1, 0, 1890, 1, 180, 25, 78, 'produto'),
  ('vinho',         'Vinho',          '🍷', 1, 0,  470, 1,  46, 26, 79, 'produto'),
  ('molho_picante', 'Molho picante',  '🌶️', 1, 0,  365, 1,  36, 28, 80, 'produto'),
  ('bombom',        'Bombom',         '🍬', 1, 0, 1480, 1, 145, 30, 81, 'produto')
on conflict (id) do update set
  nome = excluded.nome, venda = excluded.venda, xp = excluded.xp, nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;

insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, largura, altura,
                                  produz, produz_seg, produz_qtd, entradas, limite, beleza, descricao) values
  ('engenho',     'Engenho',     'oficina', 32000, 21, 91, 2, 3, 'acucar',         3600, 1, '{"cana": 4}', 2, 5, '4 canas → açúcar (vai no cappuccino e no bombom).'),
  ('torrefacao',  'Torrefação',  'oficina', 34000, 22, 92, 2, 3, 'cafe_torrado',   5400, 1, '{"cafe": 3}', 2, 5, '3 cafés → café torrado (vai no cappuccino).'),
  ('fiacao',      'Fiação',      'oficina', 36000, 23, 93, 2, 3, 'fio',            5400, 1, '{"algodao": 4}', 2, 5, '4 algodões → fio de algodão (vai na roupa).'),
  ('cafeteria',   'Cafeteria',   'oficina', 40000, 24, 94, 2, 3, 'cappuccino',     7200, 1, '{"cafe_torrado": 1, "acucar": 1, "leite": 1}', 2, 5, '1 café torrado + 1 açúcar + 1 leite → cappuccino.'),
  ('alfaiataria', 'Alfaiataria', 'oficina', 45000, 25, 95, 2, 3, 'roupa',         10800, 1, '{"fio": 2, "tecido": 1}', 2, 5, '2 fios de algodão + 1 tecido (da tecelagem) → roupa.'),
  ('vinicola',    'Vinícola',    'oficina', 48000, 26, 96, 2, 3, 'vinho',         14400, 1, '{"uva": 5}', 2, 5, '5 uvas → vinho.'),
  ('pimentaria',  'Pimentaria',  'oficina', 50000, 28, 97, 2, 3, 'molho_picante',  5400, 1, '{"pimenta": 3, "molho": 1}', 2, 5, '3 pimentas + 1 molho de tomate → molho picante.'),
  ('bombonaria',  'Bombonaria',  'oficina', 60000, 30, 98, 2, 3, 'bombom',        10800, 1, '{"chocolate": 1, "acucar": 1, "baunilha": 2}', 2, 5, '1 chocolate + 1 açúcar + 2 baunilhas → bombom.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, largura = excluded.largura, altura = excluded.altura, produz = excluded.produz,
  produz_seg = excluded.produz_seg, produz_qtd = excluded.produz_qtd, entradas = excluded.entradas,
  limite = excluded.limite, beleza = excluded.beleza, descricao = excluded.descricao;

-- conferência: deve aparecer "6 sementes novas, 8 oficinas novas"
select (select count(*) from public.fazenda_culturas where id in ('cana','cafe','algodao','uva','pimenta','baunilha')) || ' sementes novas, '
    || (select count(*) from public.fazenda_itens where id in ('engenho','torrefacao','fiacao','cafeteria','alfaiataria','vinicola','pimentaria','bombonaria')) || ' oficinas novas' as ok;
