-- ============================================================
-- FAZENDINHA — Fase 73 (árvores, oficinas e sementes do 31 ao 45, a praia e o baú da sorte),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 72): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- ------------------------------------------------------------
-- Fase 73: o que liberar do nível 31 ao 45 (parte 1) e o baú da sorte.
-- • Pomar: coqueiro (31), cajueiro (34), açaizeiro (37), cupuaçuzeiro (40) e castanheira (43), cada um
--   com a sua oficina no nível seguinte (o produto vale ~1,7x os ingredientes, como nas fases 38 e 58).
-- • Sementes de estação do 31 em diante: maracujá (verão, 33), mexerica (inverno, 36), caqui (outono, 39)
--   e lichia (primavera, 42); fora da estação, só na estufa, como as outras.
-- • Praia (categoria nova): guarda-sol, cadeira, castelo de areia, barraca de coco e coqueiro, só na
--   areia do Litoral (y 32 a 36; fazenda_construir e fazenda_mover). Só enfeitam (beleza).
-- • Baú da sorte (fazenda_abrir_bau_sorte): comprado com moedas, sem limite, para gastar o que sobra.
--   Madeira 50 mil, prata 250 mil, ouro 1 milhão; vem de tudo, mas o que é bom vem pouco: na média
--   volta menos da metade. O que vem não conta no evento (moedas) nem dá XP na venda (da_feira).
-- ------------------------------------------------------------
alter table public.fazenda_itens drop constraint if exists fazenda_itens_categoria_check;
alter table public.fazenda_itens add constraint fazenda_itens_categoria_check
  check (categoria in ('caminho', 'natureza', 'objeto', 'construcao', 'maquina', 'oficina', 'energia', 'bichos', 'pomar', 'praia'));

insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('coco',          'Coco',               '🥥', 1, 0,   70, 1,   9, 31, 57, 'produto'),
  ('caju',          'Caju',               '🍊', 1, 0,   80, 1,  10, 34, 58, 'produto'),
  ('acai',          'Açaí',               '🫐', 1, 0,   90, 1,  11, 37, 59, 'produto'),
  ('cupuacu',       'Cupuaçu',            '🍊', 1, 0,  220, 1,  26, 40, 105, 'produto'),
  ('castanha',      'Castanha-do-pará',   '🌰', 1, 0,  260, 1,  30, 43, 106, 'produto'),
  ('cocada',        'Cocada',             '🍬', 1, 0,  700, 1,  70, 32, 107, 'produto'),
  ('cajuina',       'Cajuína',            '🧃', 1, 0,  545, 1,  54, 35, 108, 'produto'),
  ('acai_tigela',   'Açaí na tigela',     '🍧', 1, 0,  580, 1,  58, 38, 109, 'produto'),
  ('creme_cupuacu', 'Creme de cupuaçu',   '🍮', 1, 0, 1215, 1, 120, 41, 110, 'produto'),
  ('pacoca',        'Paçoca',             '🍪', 1, 0, 1675, 1, 165, 44, 111, 'produto')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, venda = excluded.venda, xp = excluded.xp,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;
insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo, estacao) values
  ('maracuja', 'Maracujá', '🍈', 21600, 200, 45,  9,  60, 33, 19, 'cultura', 'verao'),
  ('mexerica', 'Mexerica', '🍊', 28800, 260, 55, 10,  80, 36, 20, 'cultura', 'inverno'),
  ('caqui',    'Caqui',    '🍅', 36000, 320, 70,  9, 100, 39, 21, 'cultura', 'outono'),
  ('lichia',   'Lichia',   '🍒', 43200, 400, 85,  9, 120, 42, 22, 'cultura', 'primavera')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, tempo_seg = excluded.tempo_seg, custo = excluded.custo, venda = excluded.venda,
  rendimento = excluded.rendimento, xp = excluded.xp, nivel_min = excluded.nivel_min, ordem = excluded.ordem,
  tipo = excluded.tipo, estacao = excluded.estacao;

insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, beleza, produz, produz_seg, produz_qtd, por_terreno, grupo, descricao) values
  ('coqueiro',     'Coqueiro',     'pomar', 20000, 31, 117, 3, 'coco',     32400,  6, 1, null, 'Dá 6 cocos a cada 9 horas: toque nele para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).'),
  ('cajueiro',     'Cajueiro',     'pomar', 25000, 34, 118, 3, 'caju',     36000,  8, 1, null, 'Dá 8 cajus a cada 10 horas: toque nele para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).'),
  ('acaizeiro',    'Açaizeiro',    'pomar', 30000, 37, 119, 3, 'acai',     39600, 10, 1, null, 'Dá 10 açaís a cada 11 horas: toque nele para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).'),
  ('cupuacuzeiro', 'Cupuaçuzeiro', 'pomar', 40000, 40, 120, 3, 'cupuacu',  43200,  5, 1, null, 'Dá 5 cupuaçus a cada 12 horas: toque nele para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).'),
  ('castanheira',  'Castanheira',  'pomar', 50000, 43, 121, 3, 'castanha', 50400,  6, 1, null, 'Dá 6 castanhas a cada 14 horas: toque nela para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min, ordem = excluded.ordem,
  beleza = excluded.beleza, produz = excluded.produz, produz_seg = excluded.produz_seg, produz_qtd = excluded.produz_qtd,
  por_terreno = excluded.por_terreno, grupo = excluded.grupo, descricao = excluded.descricao;
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, largura, altura,
                                  produz, produz_seg, produz_qtd, entradas, limite, beleza, descricao) values
  ('doceria_coco',     'Doceria de coco',    'oficina', 120000, 32, 99, 2, 3, 'cocada',        5400, 1, '{"coco": 3, "acucar": 1}', 2, 5, '3 cocos + 1 açúcar → cocada.'),
  ('cajuinaria',       'Cajuína',            'oficina', 150000, 35, 99, 2, 3, 'cajuina',       7200, 1, '{"caju": 4}', 2, 5, '4 cajus → cajuína.'),
  ('acaiteria',        'Açaiteria',          'oficina', 180000, 38, 99, 2, 3, 'acai_tigela',   5400, 1, '{"acai": 3, "leite": 1}', 2, 5, '3 açaís + 1 leite → açaí na tigela.'),
  ('cremeria',         'Creme de cupuaçu',   'oficina', 220000, 41, 99, 2, 3, 'creme_cupuacu', 7200, 1, '{"cupuacu": 2, "leite": 1, "acucar": 1}', 2, 5, '2 cupuaçus + 1 leite + 1 açúcar → creme de cupuaçu.'),
  ('pacocaria',        'Paçocaria',          'oficina', 250000, 44, 99, 2, 3, 'pacoca',        7200, 1, '{"castanha": 3, "acucar": 1}', 2, 5, '3 castanhas + 1 açúcar → paçoca.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, largura = excluded.largura, altura = excluded.altura, produz = excluded.produz,
  produz_seg = excluded.produz_seg, produz_qtd = excluded.produz_qtd, entradas = excluded.entradas,
  limite = excluded.limite, beleza = excluded.beleza, descricao = excluded.descricao;
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, beleza, descricao) values
  ('cadeira_praia', 'Cadeira de praia', 'praia',  6000, 31, 130, 2, 'Para ver o mar. Só na areia do Litoral.'),
  ('guarda_sol',    'Guarda-sol',       'praia',  8000, 31, 131, 3, 'Sombra na areia. Só na areia do Litoral.'),
  ('coqueiro_praia','Coqueiro da praia','praia', 12000, 31, 132, 4, 'Só enfeita: o coco é do coqueiro do pomar. Só na areia do Litoral.'),
  ('castelo_areia', 'Castelo de areia', 'praia', 15000, 31, 133, 4, 'Com bandeirinha e tudo. Só na areia do Litoral.'),
  ('barraca_coco',  'Barraca de coco',  'praia', 25000, 31, 134, 5, 'Água de coco gelada na beira do mar. Só na areia do Litoral.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, beleza = excluded.beleza, descricao = excluded.descricao;

-- os baús da sorte: preço, nível e as chances (raro, o prêmio grande, diamantes, itens; o resto é moeda)
create or replace function public.fazenda_baus_sorte()
returns jsonb language sql immutable as $$
  select '{"madeira": {"nome": "Baú de madeira", "preco": 50000,   "nivel": 20, "raro": 0.004, "grande": 0.02, "diamantes": [5, 10],  "chance_diamantes": 0.08, "chance_itens": 0.35},
           "prata":   {"nome": "Baú de prata",   "preco": 250000,  "nivel": 25, "raro": 0.015, "grande": 0.02, "diamantes": [15, 30], "chance_diamantes": 0.08, "chance_itens": 0.35},
           "ouro":    {"nome": "Baú de ouro",    "preco": 1000000, "nivel": 30, "raro": 0.05,  "grande": 0.02, "diamantes": [40, 80], "chance_diamantes": 0.08, "chance_itens": 0.35}}'::jsonb;
$$;

-- abre um baú da sorte: paga, sorteia e entrega. Os prêmios:
--   raro (o mais caro, mais difícil: peso 1 / preço) · o prêmio grande (2x o preço em moedas) · diamantes
--   · itens que o seu nível já tem (de 30% a 90% do preço, pelo preço do celeiro) · moedas (15% a 45%)
create or replace function public.fazenda_abrir_bau_sorte(p_token text, p_tipo text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_b     jsonb := fazenda_baus_sorte() -> p_tipo;
  j       record;
  k       record;
  v_preco int;
  v_r     double precision := random();
  v_lim   double precision;
  v_moeda int := 0;
  v_diam  int := 0;
  v_item  text;
  v_qtd   int := 0;
  v_tipo  text;
begin
  if v_b is null then raise exception 'item_invalido'; end if;
  select * into j from fazenda_jogadores where id = v_id for update;
  if fazenda_nivel(j.xp) < (v_b->>'nivel')::int then raise exception 'nivel_insuficiente'; end if;
  v_preco := (v_b->>'preco')::int;
  if j.moedas < v_preco then raise exception 'moedas_insuficientes'; end if;

  -- as faixas do sorteio, uma depois da outra (raro, grande, diamantes, itens; o resto é moeda)
  v_lim := (v_b->>'raro')::float8;
  if v_r < v_lim then
    v_tipo := 'raro';
    select c.id into v_item from fazenda_culturas c
     where c.tipo = 'raro' and c.venda > 0
     order by -ln(greatest(random(), 1e-12)) * c.venda limit 1;   -- sorteio com peso 1 / preço
    v_qtd := 1;
  elsif v_r < v_lim + (v_b->>'grande')::float8 then
    v_tipo := 'grande';
    v_moeda := v_preco * 2;
  elsif v_r < v_lim + (v_b->>'grande')::float8 + (v_b->>'chance_diamantes')::float8 then
    v_tipo := 'diamantes';
    v_diam := (v_b->'diamantes'->>0)::int + floor(random() * ((v_b->'diamantes'->>1)::int - (v_b->'diamantes'->>0)::int + 1))::int;
  elsif v_r < v_lim + (v_b->>'grande')::float8 + (v_b->>'chance_diamantes')::float8 + (v_b->>'chance_itens')::float8 then
    v_tipo := 'itens';
    select c.* into k from fazenda_culturas c
     where c.tipo in ('cultura', 'produto') and c.venda > 0 and c.nivel_min <= fazenda_nivel(j.xp)
     order by random() limit 1;
    v_item := k.id;
    v_qtd := greatest(1, round(v_preco * (0.3 + random() * 0.6) / k.venda))::int;
  else
    v_tipo := 'moedas';
    v_moeda := round(v_preco * (0.15 + random() * 0.3))::int;
  end if;

  -- o que veio do baú não conta como moeda ganha no evento (o gatilho soma o que entra)
  update fazenda_jogadores
     set moedas = moedas - v_preco + v_moeda, diamantes = diamantes + v_diam,
         moedas_ganhas = moedas_ganhas - greatest(v_moeda - v_preco, 0)
   where id = v_id;
  if v_item is not null then   -- e vendido no celeiro dá as moedas, mas não o XP (como o da feira)
    insert into fazenda_celeiro (jogador_id, item, quantidade, da_feira) values (v_id, v_item, v_qtd, v_qtd)
    on conflict (jogador_id, item) do update
      set quantidade = fazenda_celeiro.quantidade + excluded.quantidade, da_feira = fazenda_celeiro.da_feira + excluded.da_feira;
  end if;
  insert into fazenda_baus_abertos (jogador_id, tipo, preco, premio, item, qtd, moedas, diamantes)
  values (v_id, p_tipo, v_preco, v_tipo, v_item, v_qtd, v_moeda, v_diam);
  return jsonb_build_object('premio', jsonb_build_object('tipo', v_tipo, 'item', v_item, 'qtd', v_qtd, 'moedas', v_moeda, 'diamantes', v_diam),
                            'preco', v_preco, 'estado', fazenda_estado(v_id));
end;
$$;

-- o que saiu de cada baú (para conferir as chances depois)
create table if not exists public.fazenda_baus_abertos (
  id         bigserial primary key,
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  tipo       text not null,
  preco      int  not null,
  premio     text not null,
  item       text,
  qtd        int  not null default 0,
  moedas     int  not null default 0,
  diamantes  int  not null default 0,
  em         timestamptz not null default now()
);
create index if not exists fazenda_baus_abertos_jogador on public.fazenda_baus_abertos (jogador_id, em);
alter table public.fazenda_baus_abertos enable row level security;
revoke all on public.fazenda_baus_abertos from anon, authenticated;
revoke all on sequence public.fazenda_baus_abertos_id_seq from anon, authenticated;

select public.fazenda_cache_montar();

-- as funções que já existiam e mudaram

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
begin
  perform fazenda_checar_conquistas(p_jogador);
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
  v_nivel := fazenda_nivel(j.xp);
  -- subiu de nível: presente de moedas e 5 diamantes por cada nível novo
  if v_nivel > coalesce(j.nivel_premiado, 1) then
    update fazenda_jogadores
       set moedas = moedas + (select sum(fazenda_presente_nivel(n)) from generate_series(coalesce(j.nivel_premiado, 1) + 1, v_nivel) n),
           diamantes = diamantes + 5 * (v_nivel - coalesce(j.nivel_premiado, 1)),
           nivel_premiado = v_nivel
     where id = p_jogador and nivel_premiado is not distinct from j.nivel_premiado;   -- fase 70: paga uma vez só
    select * into j from fazenda_jogadores where id = p_jogador;
  end if;
  -- canteiros não aparecem mais sozinhos: o jogador coloca no modo construir até este limite
  v_max := fazenda_limite_canteiros(v_nivel, j.zonas);
  -- fase 49: as metas de nível; com todas em dia, o bônus de XP vale neste nível (só grava se mudou)
  v_metas := fazenda_metas(p_jogador, v_nivel);
  -- (fase 62: até o 44; era até o 29, quando o 30 era o último nível)
  v_bonus := case when v_nivel < 45 and not exists (select 1 from jsonb_array_elements(v_metas) m where not (m->>'feito')::boolean)
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
      'xp_compras_hoje', fazenda_diamantes_hoje(p_jogador, 'xp'),
      -- conta Google ligada (só aparece para o dono; null = não ligada)
      'google', case when j.google_sub is not null then coalesce(j.google_email, 'sua conta Google') end,
      'admin', j.admin,   -- fase 53: 'dono', 'admin' ou null
      'xp', j.xp,
      'nivel', v_nivel,
      'xp_nivel', fazenda_xp_nivel(v_nivel),
      'xp_proximo', fazenda_xp_nivel(v_nivel + 1),
      'bonus_nivel', v_bonus,   -- fase 49: +50% de XP neste nível (metas em dia)
      'max_canteiros', v_max,
      'max_construcoes', fazenda_max_construcoes(j.zonas),
      'zonas', j.zonas,
      'beleza', fazenda_beleza(p_jogador),
      'bonus_venda', fazenda_bonus_venda(p_jogador)
    ),
    'zonas_venda', fazenda_zonas(),
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
      'desde', j.lago_em, 'intervalo', 1800, 'max', 16,
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
    'culturas', fazenda_cache_ler('culturas'),   -- fase 71: os catálogos vêm prontos (fazenda_cache)
    'animais', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'alimentado_em', alimentado_em,
               'radioativo_ate', case when radioativo_ate > now() then radioativo_ate end) order by id)   -- fase 68
        from fazenda_animais where jogador_id = p_jogador), '[]'::jsonb),
    'animais_tipos', fazenda_cache_ler('animais_tipos'),
    'construcoes', coalesce((
      select jsonb_agg(jsonb_build_object('x', x, 'y', y, 'tipo', tipo, 'colhido_em', colhido_em, 'iniciado_em', iniciado_em,
                                          'estoque', estoque, 'prontos', prontos, 'pago', pago))   -- fase 72: pago
        from fazenda_construcoes where jogador_id = p_jogador), '[]'::jsonb),
    'estoque_max', fazenda_estoque_max(),
    'itens', fazenda_cache_itens(v_nivel),   -- fase 57: o limite que vale para o nível de agora (fase 71: pronto, um por nível)
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
    -- fase 63: o evento da semana (até quando vai, os prêmios ainda não vistos e os troféus)
    'evento', jsonb_build_object(
      'fim', fazenda_semana_inicio(now()) + interval '7 days',
      'novos', coalesce((select jsonb_agg(jsonb_build_object('semana', semana, 'categoria', categoria, 'posicao', posicao,
                                   'valor', valor, 'diamantes', diamantes, 'item', item) order by categoria, posicao)
                           from fazenda_semana_premios where jogador_id = p_jogador and not visto), '[]'::jsonb),
      'trofeus', fazenda_trofeus(p_jogador),
      'regras', fazenda_evento_regras()),
    'melhorias_tipos', fazenda_cache_ler('melhorias_tipos'),
    'estatisticas', (select to_jsonb(e) - 'jogador_id' || jsonb_build_object('energia', e.energia + floor(j.energia_gasta)::int)
                       from fazenda_estatisticas e where e.jogador_id = p_jogador),
    'conquistas', coalesce((
      select jsonb_agg(jsonb_build_object('id', conquista, 'em', obtida_em) order by obtida_em)
        from fazenda_conquistas where jogador_id = p_jogador), '[]'::jsonb),
    'conquistas_tipos', fazenda_cache_ler('conquistas_tipos'),
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
    'ajudantes_tipos', fazenda_cache_ler('ajudantes_tipos')
  );
  -- o relatório (o que fizeram enquanto você estava fora) aparece uma vez só
  update fazenda_ajudantes set relatorio = 0 where jogador_id = p_jogador and relatorio > 0;
  update fazenda_convites set visto = true where dono_id = p_jogador and not visto;   -- idem os amigos novos
  update fazenda_feira set visto = true where vendedor_id = p_jogador and vendido_em is not null and not visto;   -- e as vendas da feira
  update fazenda_semana_premios set visto = true where jogador_id = p_jogador and not visto;   -- e os prêmios do evento (fase 63)
  update fazenda_murchas set visto = true where jogador_id = p_jogador and not visto;   -- e o relatório das murchas (fase 66)
  update fazenda_feira set reserva_vista = true where reservado_para = p_jogador and not reserva_vista;   -- e o que separaram no chat (fase 67)
  update fazenda_radiacao set visto = true where jogador_id = p_jogador and not visto;   -- e a radiação do reator (fase 68)
  return v_json;
end;
$$;

-- Compra um item e coloca no quadrado (x, y)
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
begin
  select * into j from fazenda_jogadores where id = v_id for update;

  -- canteiro: não é item da loja, é um lugar de plantar (limite pelo nível e terrenos)
  if p_tipo = 'canteiro' then
    if (select count(*) from fazenda_canteiros where jogador_id = v_id)
       >= fazenda_limite_canteiros(fazenda_nivel(j.xp), j.zonas) then
      raise exception 'limite_canteiros';
    end if;
    perform fazenda_checar_lugar(v_id, j.zonas, p_x, p_y, 1, 1);
    select min(g) into v_pos from generate_series(0, 299) g   -- fase 56: eram 0..99
     where not exists (select 1 from fazenda_canteiros where jogador_id = v_id and posicao = g);
    if v_pos is null then raise exception 'limite_canteiros'; end if;
    -- fase 70: canteiro novo espera os 8 min para dar XP de colheita (desmanchar e fazer de novo zerava)
    insert into fazenda_canteiros (jogador_id, posicao, estado, x, y, xp_em) values (v_id, v_pos, 'vazio', p_x, p_y, now());
    return jsonb_build_object('estado', fazenda_estado(v_id), 'posicao', v_pos);
  end if;

  select * into i from fazenda_itens where id = p_tipo;
  if not found then raise exception 'item_invalido'; end if;
  if fazenda_nivel(j.xp) < i.nivel_min then raise exception 'nivel_insuficiente'; end if;
  perform fazenda_checar_lugar(v_id, j.zonas, p_x, p_y, i.largura, i.altura);
  -- fase 73: o que é da praia só vai na areia do Litoral (y 32 a 36)
  if i.categoria = 'praia' and not (p_y >= 32 and p_y + i.altura - 1 <= 36) then raise exception 'so_na_areia'; end if;
  if i.limite is not null   -- fase 57: painel solar e turbina sobem com o nível
     and (select count(*) from fazenda_construcoes where jogador_id = v_id and tipo = i.id)
         >= fazenda_limite_maquina(i.id, i.limite, fazenda_nivel(j.xp)) then
    raise exception 'limite_maquina';
  end if;
  -- itens por terreno (amoreira): mais terreno, mais pés (igual a maxItem em fazenda.js); fase 47: no
  -- pomar, cada fruta tem 1 pé e +1 a cada 2 terrenos (até 4); quem já passou fica com as que tem
  if i.por_terreno is not null
     and (select count(*) from fazenda_construcoes c join fazenda_itens k on k.id = c.tipo
           where c.jogador_id = v_id and (c.tipo = i.id or (i.grupo is not null and k.grupo = i.grupo)))
         >= (case when i.categoria = 'pomar'   -- fase 57: + os pés da melhoria "Mais pés de fruta"
                  then i.por_terreno * (1 + j.zonas / 2) + fazenda_melhoria(v_id, 'pes')::int
                  else i.por_terreno * (1 + j.zonas) end) then
    raise exception 'limite_terreno';
  end if;
  if (select count(*) from fazenda_construcoes where jogador_id = v_id) >= fazenda_max_construcoes(j.zonas) then
    raise exception 'limite_construcoes';
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

-- Leva uma construção de (x, y) para (nx, ny)
create or replace function public.fazenda_mover(p_token text, p_x int, p_y int, p_nx int, p_ny int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id  uuid := fazenda_auth(p_token);
  j     record;
  i     record;
  v_pos int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  -- canteiro (mesmo plantado: a planta vai junto)
  select posicao into v_pos from fazenda_canteiros where jogador_id = v_id and x = p_x and y = p_y;
  if v_pos is not null then
    perform fazenda_checar_lugar(v_id, j.zonas, p_nx, p_ny, 1, 1, null, null, v_pos);
    update fazenda_canteiros set x = p_nx, y = p_ny where jogador_id = v_id and posicao = v_pos;
    return jsonb_build_object('estado', fazenda_estado(v_id));
  end if;

  select k.* into i from fazenda_construcoes c join fazenda_itens k on k.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y;
  if not found then raise exception 'item_invalido'; end if;
  perform fazenda_checar_lugar(v_id, j.zonas, p_nx, p_ny, i.largura, i.altura, p_x, p_y);
  if i.categoria = 'praia' and not (p_ny >= 32 and p_ny + i.altura - 1 <= 36) then raise exception 'so_na_areia'; end if;   -- fase 73
  update fazenda_construcoes set x = p_nx, y = p_ny
   where jogador_id = v_id and x = p_x and y = p_y;
  if not found then raise exception 'item_invalido'; end if;
  -- o que está guardado no baú e o que já chegou pelo cano na oficina vão junto (fase 39)
  update fazenda_bau_itens set x = p_nx, y = p_ny where jogador_id = v_id and x = p_x and y = p_y;
  update fazenda_oficina_itens set x = p_nx, y = p_ny where jogador_id = v_id and x = p_x and y = p_y;
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- permissões
revoke execute on function
  public.fazenda_baus_sorte()
from public, anon, authenticated;

grant execute on function
  public.fazenda_abrir_bau_sorte(text, text)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();


-- conferência: deve aparecer "Fase 73: 5 árvores, 5 oficinas, 4 sementes e 5 coisas da praia novas; 3 baús da sorte"
select 'Fase 73: ' || (select count(*) from public.fazenda_itens where id in ('coqueiro','cajueiro','acaizeiro','cupuacuzeiro','castanheira')) || ' árvores, '
       || (select count(*) from public.fazenda_itens where id in ('doceria_coco','cajuinaria','acaiteria','cremeria','pacocaria')) || ' oficinas, '
       || (select count(*) from public.fazenda_culturas where id in ('maracuja','mexerica','caqui','lichia')) || ' sementes e '
       || (select count(*) from public.fazenda_itens where categoria = 'praia') || ' coisas da praia novas; '
       || (select count(*) from jsonb_object_keys(public.fazenda_baus_sorte())) || ' baús da sorte' as ok;
