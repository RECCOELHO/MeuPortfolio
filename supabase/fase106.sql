-- ============================================================
-- FAZENDINHA — Fase 106 (zarpar no 46: o nível vai até o 60 e a Ilha da Caveira Dourada), só o que mudou.
-- Para o banco que já está no ar (com a fase 105): Supabase > SQL Editor > colar este arquivo > Run.
-- Rode ANTES do merge do PR.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 105 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (public.fazenda_mar_regras() ? 'jogo_ms') then
    raise exception 'Rode o fase105.sql antes deste. Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 106: zarpar no 46. Do nível 45 ao 60, a Ilha da Caveira Dourada.
-- • O último nível passa do 45 para o 60 (fazenda_nivel, fazenda_nivel_de, a trava, o XP por diamante, o
--   calendário e o bônus das metas). Quem já tinha XP de sobra no 45 fica no começo do 46 (uma vez só).
-- • Com o nível 46 e o kit de expedição (que pede o navio oceânico), o navio zarpa para a ilha.
-- • As 15 obras da ilha, uma por nível do 46 ao 60, na ordem (fazenda_ilha_obras): cada uma pede moedas,
--   tábuas, cravos, velas, cartas náuticas e alguns raros, e dá 8% do XP do nível dela. A última dá a
--   conquista "Ilha da Caveira Dourada".
-- • O baú enterrado: com o cais pronto, 1 por dia na praia da ilha (moedas; às vezes diamantes ou um raro).
-- • Conquistas dos níveis 50, 55 e 60.
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists ilha_obras smallint not null default 0;
alter table public.fazenda_jogadores add column if not exists ilha_bau_dia date;

create or replace function public.fazenda_ilha_obras()
returns jsonb language sql immutable as $$
  select '[
    {"n": 1,  "id": "cais",       "nivel": 46, "nome": "Cais de madeira",      "moedas": 400000,  "itens": {"tora": 12, "madeira_nobre": 1},       "descricao": "Onde o navio atraca. Com ele pronto, dá para cavar o baú da praia."},
    {"n": 2,  "id": "trapiche",   "nivel": 47, "nome": "Trapiche",             "moedas": 500000,  "itens": {"tabua_naval": 20},                    "descricao": "A passarela do cais até a areia."},
    {"n": 3,  "id": "armazem",    "nivel": 48, "nome": "Armazém do porto",     "moedas": 600000,  "itens": {"tabua_naval": 30, "tora": 10},         "descricao": "Para guardar a carga do navio."},
    {"n": 4,  "id": "muralha",    "nivel": 49, "nome": "Muralha de pedra",     "moedas": 700000,  "itens": {"tabua_naval": 20, "pedra_cantaria": 1}, "descricao": "Segura o mar nos dias de ressaca."},
    {"n": 5,  "id": "taverna",    "nivel": 50, "nome": "Taverna",              "moedas": 800000,  "itens": {"tabua_naval": 30, "cravo": 20},        "descricao": "Onde os marujos contam as histórias da ilha."},
    {"n": 6,  "id": "portao",     "nivel": 51, "nome": "Portão de ferro",      "moedas": 900000,  "itens": {"cravo": 20, "ferro_forjado": 1},      "descricao": "A entrada do porto."},
    {"n": 7,  "id": "farol",      "nivel": 52, "nome": "Farol",                "moedas": 1000000, "itens": {"leme_dourado": 1, "tabua_naval": 15},  "descricao": "Com o espelho dourado que guia os navios de noite."},
    {"n": 8,  "id": "vigia",      "nivel": 53, "nome": "Cabana do vigia",      "moedas": 1100000, "itens": {"tora": 20, "cravo": 20},               "descricao": "Lá de cima dá para ver o mar todo."},
    {"n": 9,  "id": "mercado",    "nivel": 54, "nome": "Mercado pirata",       "moedas": 1200000, "itens": {"corda_naval": 2, "vela": 2},          "descricao": "As barracas de lona da praça."},
    {"n": 10, "id": "toldo",      "nivel": 55, "nome": "Toldo da praça",       "moedas": 1400000, "itens": {"vela": 6},                            "descricao": "Sombra feita de velas velhas."},
    {"n": 11, "id": "ancora",     "nivel": 56, "nome": "Âncora gigante",       "moedas": 1600000, "itens": {"ancora": 1, "cravo": 30},             "descricao": "O enfeite da praça, de um navio afundado."},
    {"n": 12, "id": "canhoes",    "nivel": 57, "nome": "Canhões de festa",     "moedas": 1800000, "itens": {"cravo": 40, "carta_nautica": 1},      "descricao": "Três canhões que só soltam confete."},
    {"n": 13, "id": "sereia",     "nivel": 58, "nome": "Estátua da sereia",    "moedas": 2000000, "itens": {"perola_negra": 1, "tabua_naval": 20}, "descricao": "Dourada, com olhos de pérola."},
    {"n": 14, "id": "cartografo", "nivel": 59, "nome": "Casa do cartógrafo",   "moedas": 2200000, "itens": {"carta_nautica": 5, "tabua_naval": 20},"descricao": "Com os mapas das próximas ilhas."},
    {"n": 15, "id": "bandeira",   "nivel": 60, "nome": "Bandeira no morro",    "moedas": 2500000, "itens": {"carta_nautica": 4, "vela": 4},        "descricao": "A ilha é sua: a bandeira no alto do morro."}
  ]'::jsonb;
$$;

-- pode zarpar: nível 46 e o kit de expedição
create or replace function public.fazenda_ilha_pode(p_jogador uuid, p_nivel int)
returns boolean language sql stable security definer set search_path = public as $$
  select p_nivel >= 46 and coalesce((select nivel from fazenda_melhorias where jogador_id = p_jogador and id = 'expedicao'), 0) >= 1;
$$;

-- constrói a próxima obra (p_obra é o id dela: tocar duas vezes não constrói duas)
create or replace function public.fazenda_ilha_construir(p_token text, p_obra text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  j       record;
  c       record;
  v_p     jsonb;
  k       text;
  v_n     int;
  v_nivel int;
  v_xp    int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  v_nivel := fazenda_nivel_de(j.xp, j.nivel_trava);
  if not fazenda_ilha_pode(v_id, v_nivel) then raise exception 'ilha_fechada'; end if;
  v_n := coalesce(j.ilha_obras, 0) + 1;
  select p into v_p from jsonb_array_elements(fazenda_ilha_obras()) p where (p->>'n')::int = v_n;
  if v_p is null then raise exception 'ilha_pronta'; end if;
  if v_p->>'id' is distinct from p_obra then raise exception 'ilha_ordem'; end if;
  if v_nivel < (v_p->>'nivel')::int then raise exception 'nivel_insuficiente'; end if;
  if j.moedas < (v_p->>'moedas')::int then raise exception 'moedas_insuficientes'; end if;
  for k in select jsonb_object_keys(v_p->'itens') loop   -- só o que está livre (a reserva fica)
    if coalesce((select quantidade from fazenda_celeiro where jogador_id = v_id and item = k), 0)
       - coalesce((select quantidade from fazenda_reservas where jogador_id = v_id and item = k), 0) < (v_p->'itens'->>k)::int then
      raise exception 'faltam_materiais';
    end if;
  end loop;
  for k in select jsonb_object_keys(v_p->'itens') loop
    update fazenda_celeiro set quantidade = quantidade - (v_p->'itens'->>k)::int,
                               da_feira = least(da_feira, quantidade - (v_p->'itens'->>k)::int)
     where jogador_id = v_id and item = k;
  end loop;
  v_xp := round((fazenda_xp_nivel((v_p->>'nivel')::int + 1) - fazenda_xp_nivel((v_p->>'nivel')::int)) * 0.08)::int;
  perform set_config('fazenda.xp_puro', '1', true);
  update fazenda_jogadores set moedas = moedas - (v_p->>'moedas')::int, ilha_obras = v_n, xp = xp + v_xp where id = v_id;
  perform set_config('fazenda.xp_puro', '', true);
  if v_n = jsonb_array_length(fazenda_ilha_obras()) then
    select * into c from fazenda_conquistas_tipos where id = 'ilha_pronta';
    insert into fazenda_conquistas (jogador_id, conquista) values (v_id, 'ilha_pronta') on conflict do nothing;
    if found and c.id is not null then
      update fazenda_jogadores set moedas = least(2147483647, moedas::bigint + c.recompensa)::int, diamantes = diamantes + c.diamantes
       where id = v_id;
    end if;
  end if;
  return jsonb_build_object('obra', v_p, 'xp', v_xp, 'estado', fazenda_estado(v_id));
end;
$$;

-- o baú enterrado da praia: 1 por dia, com o cais pronto. Moedas (de 41 a 95 mil no 46; de 108 a 252 mil no 60);
-- 1 em 4 vem com diamantes (5 a 15); 1 em 12 com um raro do píer
create or replace function public.fazenda_ilha_bau(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  j       record;
  v_nivel int;
  v_moeda int;
  v_diam  int := 0;
  v_raro  text;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  v_nivel := fazenda_nivel_de(j.xp, j.nivel_trava);
  if not fazenda_ilha_pode(v_id, v_nivel) then raise exception 'ilha_fechada'; end if;
  if coalesce(j.ilha_obras, 0) < 1 then raise exception 'ilha_sem_cais'; end if;
  if j.ilha_bau_dia = fazenda_hoje() then raise exception 'ilha_bau_hoje'; end if;
  v_moeda := round((60000 + (v_nivel - 45) * 8000) * (0.6 + random() * 0.8))::int;
  if random() < 0.25 then v_diam := 5 + floor(random() * 11)::int; end if;
  if random() < 1.0 / 12 then
    v_raro := (array['madeira_nobre', 'corda_naval', 'pedra_cantaria', 'ferro_forjado', 'perola_negra'])[1 + floor(random() * 5)::int];
    insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, v_raro, 1)
    on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
  end if;
  update fazenda_jogadores set moedas = least(2147483647, moedas::bigint + v_moeda)::int, diamantes = diamantes + v_diam,
         moedas_ganhas = moedas_ganhas - v_moeda,   -- (o baú não conta no evento das moedas)
         ilha_bau_dia = fazenda_hoje()
   where id = v_id;
  return jsonb_build_object('moedas', v_moeda, 'diamantes', v_diam, 'raro', v_raro, 'estado', fazenda_estado(v_id));
end;
$$;

insert into public.fazenda_conquistas_tipos (id, nome, descricao, medida, meta, recompensa, ordem) values
  ('nivel_50',    'Mestre do mar',               'Chegue ao nível 50',                         'nivel', 50, 150000, 35),
  ('nivel_55',    'Pirata de respeito',          'Chegue ao nível 55',                         'nivel', 55, 200000, 36),
  ('nivel_60',    'Lenda dos sete mares',        'Chegue ao nível 60',                         'nivel', 60, 300000, 37),
  ('ilha_pronta', 'Ilha da Caveira Dourada',     'Termine as 15 obras da ilha',                'ilha',  15, 250000, 38)
on conflict (id) do update set nome = excluded.nome, descricao = excluded.descricao, medida = excluded.medida,
  meta = excluded.meta, recompensa = excluded.recompensa, ordem = excluded.ordem;
update public.fazenda_conquistas_tipos t set diamantes = v.d
  from (values ('nivel_50', 50), ('nivel_55', 75), ('nivel_60', 150), ('ilha_pronta', 100)) v(id, d)
 where t.id = v.id;

-- as funções que mudaram (o teto do 60, o kit de expedição e a ilha no estado)

-- Nível a partir do XP (o inverso de fazenda_xp_nivel)
create or replace function public.fazenda_nivel(p_xp int)
returns int language plpgsql immutable as $$
declare
  n int;
begin
  if p_xp < 2025 then
    return 1 + (select count(*)::int from unnest(array[10, 35, 85, 175, 315, 525, 825, 1325]) t where t <= p_xp);
  end if;
  n := 10 + floor(ln(1 + (p_xp - 2025) * 0.22 / 700) / ln(1.22))::int;
  while fazenda_xp_nivel(n + 1) <= p_xp loop n := n + 1; end loop;    -- acerta o arredondamento
  while n > 10 and fazenda_xp_nivel(n) > p_xp loop n := n - 1; end loop;
  return least(n, 60);   -- fase 106: o 60 é o último (fase 70: era o 45; passava para 46, 47... e o presente continuava)
end;
$$;


-- fase 90: o nível de verdade: o do XP, mas só passa do nível N quem tem tudo o que conta dos níveis até N
create or replace function public.fazenda_nivel_de(p_xp int, p_trava int)
returns int language sql immutable as $$
  select least(fazenda_nivel(p_xp), coalesce(p_trava, 60));   -- fase 106: até o 60
$$;


-- o menor nível que tem algo que conta e que o jogador não tem na fazenda (45: não falta nada)
create or replace function public.fazenda_nivel_trava(p_jogador uuid)
returns int language plpgsql stable security definer set search_path = public as $$
begin
  return coalesce((select min(i.nivel_min) from fazenda_itens i
                    where fazenda_conta_nivel(i.categoria, i.id) and i.nivel_min < 60   -- fase 106: até o 60
                      and not exists (select 1 from fazenda_construcoes c where c.jogador_id = p_jogador and c.tipo = i.id)), 60);
end;
$$;


create or replace function public.fazenda_usar_diamantes(p_token text, p_item text, p_x int default null, p_y int default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_loja  jsonb := fazenda_loja_diamantes() -> p_item;
  j       record;
  o       record;
  v_preco int;
  v_nivel int;
  v_xp    int := 0;
  v_e     real;
  v_cap   int;
begin
  if v_loja is null then raise exception 'item_invalido'; end if;
  perform fazenda_tick(v_id);
  select * into j from fazenda_jogadores where id = v_id for update;

  if p_item = 'xp2' then
    v_preco := (v_loja->>'preco')::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    -- comprar de novo com ele valendo soma mais 1 hora
    update fazenda_jogadores
       set diamantes = diamantes - v_preco,
           xp2_ate = greatest(coalesce(xp2_ate, now()), now()) + make_interval(hours => (v_loja->>'horas')::int)
     where id = v_id;

  elsif p_item = 'xp' then
    v_preco := (v_loja->>'preco')::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    if fazenda_diamantes_hoje(v_id, 'xp') >= (v_loja->>'por_dia')::int then raise exception 'limite_diario'; end if;
    v_nivel := fazenda_nivel_de(j.xp, j.nivel_trava);
    if v_nivel >= 60 then raise exception 'xp_maximo'; end if;   -- fase 106: o último nível agora é o 60 (fase 62: 45)
    v_xp := ceil((fazenda_xp_nivel(v_nivel + 1) - fazenda_xp_nivel(v_nivel)) * (v_loja->>'pct')::int / 100.0)::int;
    perform set_config('fazenda.xp_puro', '1', true);
    perform set_config('fazenda.xp_pago', '1', true);   -- fase 70: não conta no evento
    update fazenda_jogadores set diamantes = diamantes - v_preco, xp = xp + v_xp where id = v_id;
    perform set_config('fazenda.xp_puro', '', true);
    perform set_config('fazenda.xp_pago', '', true);

  elsif p_item = 'cafe' then
    v_preco := (v_loja->>'preco')::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    if not exists (select 1 from fazenda_ajudantes where jogador_id = v_id) then raise exception 'sem_ajudantes'; end if;
    perform fazenda_trabalhar(v_id);   -- fecha o trabalho de antes no ritmo de antes
    perform fazenda_ajudantes_fechar(v_id, null);   -- (fase 46: quem não trabalhou também)
    update fazenda_jogadores
       set diamantes = diamantes - v_preco,
           cafe_de = case when cafe_ate > now() then cafe_de else now() end,
           cafe_ate = greatest(coalesce(cafe_ate, now()), now()) + make_interval(hours => (v_loja->>'horas')::int)
     where id = v_id;

  elsif p_item = 'energia' then
    if not exists (select 1 from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
                    where c.jogador_id = v_id and i.categoria = 'energia') then
      raise exception 'sem_maquinas';
    end if;
    v_e := fazenda_energia_atualizar(v_id);
    v_cap := fazenda_capacidade(v_id);
    if v_cap - v_e < 1 then raise exception 'energia_cheia'; end if;
    v_preco := greatest(1, ceil((v_cap - v_e) / (v_loja->>'por')::real))::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    update fazenda_jogadores set diamantes = diamantes - v_preco, energia = v_cap, energia_em = now() where id = v_id;

  elsif p_item = 'murchas' then
    -- fase 48: o diamante salva todas as plantas murchas (voltam maduras, sem problemas); fase 72: 1 a
    -- cada 25 plantas (era 1 para todas)
    select count(*) into v_cap from fazenda_canteiros c join fazenda_culturas k on k.id = c.cultura
     where c.jogador_id = v_id and c.estado = 'plantado'
       and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600));
    if v_cap = 0 then raise exception 'nada_a_fazer'; end if;
    v_preco := (v_loja->>'preco')::int * ceil(v_cap / coalesce((v_loja->>'por')::numeric, v_cap))::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    update fazenda_canteiros c
       set plantado_em = now() - make_interval(secs => k.tempo_seg), erva = false, praga = false, seco = false, prox_evento = null
      from fazenda_culturas k
     where c.jogador_id = v_id and c.estado = 'plantado' and k.id = c.cultura
       and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600));
    update fazenda_jogadores set diamantes = diamantes - v_preco where id = v_id;

  elsif p_item = 'oficina' then
    perform fazenda_oficinas_andar(v_id);
    select c.iniciado_em, ceil(i.produz_seg * (1 - fazenda_oficina_rapidez(v_id, c.tipo)))::int as produz_seg, i.entradas into o
      from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
     where c.jogador_id = v_id and c.x = p_x and c.y = p_y
       for update of c;
    if not found or o.entradas is null then raise exception 'item_invalido'; end if;
    if o.iniciado_em is null then raise exception 'oficina_parada'; end if;
    v_preco := greatest(1, ceil(extract(epoch from o.iniciado_em + make_interval(secs => o.produz_seg) - now()) / 3600
                                * (v_loja->>'por_hora')::int))::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    update fazenda_jogadores set diamantes = diamantes - v_preco where id = v_id;
    update fazenda_construcoes set iniciado_em = now() - make_interval(secs => o.produz_seg)
     where jogador_id = v_id and x = p_x and y = p_y;
    perform fazenda_oficinas_andar(v_id);   -- termina agora: o produto sai e a próxima começa

  elsif p_item = 'moedas' then   -- fase 79: diamantes viram moedas (o pacote cresce com o nível)
    v_preco := (v_loja->>'preco')::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    v_nivel := fazenda_nivel_de(j.xp, j.nivel_trava);
    -- moeda comprada não conta no evento (o gatilho soma o que entra; aqui já desconta)
    update fazenda_jogadores
       set diamantes = diamantes - v_preco, moedas = moedas + v_nivel * (v_loja->>'por_nivel')::int,
           moedas_ganhas = moedas_ganhas - v_nivel * (v_loja->>'por_nivel')::int
     where id = v_id;
  end if;

  insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, p_item, v_preco);
  return jsonb_build_object('item', p_item, 'diamantes', v_preco, 'xp', v_xp, 'estado', fazenda_estado(v_id));
end;
$$;


-- Entrega um prêmio e devolve o que foi dado de fato (com as moedas já vezes o nível)
-- Fase 70: cada moeda da tabela vale um décimo do presente do nível (no 30: 300; antes era só o nível,
-- 30, e o prêmio não fazia diferença); o XP da trilha dourada ({"pago": true}) não conta no evento.
create or replace function public.fazenda_calendario_dar(p_jogador uuid, p jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_nivel int;
  v_tipo  text := p->>'tipo';
  v_qtd   int := coalesce((p->>'qtd')::int, 1);
  v_xp    int;
begin
  select fazenda_nivel_de(xp, nivel_trava) into v_nivel from fazenda_jogadores where id = p_jogador;
  if v_tipo in ('xp', 'xp2') and v_nivel >= 60 then v_tipo := 'moedas'; v_qtd := 50; end if;   -- no último nível (fase 106: o 60), XP não serve
  if v_tipo = 'cafe' and not exists (select 1 from fazenda_ajudantes where jogador_id = p_jogador) then v_tipo := 'moedas'; v_qtd := 20; end if;
  -- fase 84: o café e o XP em dobro viram vale (o jogador liga quando quiser); {"usar": true} liga na hora
  if v_tipo in ('cafe', 'xp2') and not coalesce((p->>'usar')::boolean, false) then
    insert into fazenda_vales (jogador_id, tipo, minutos) values (p_jogador, v_tipo, v_qtd);
    return jsonb_build_object('tipo', 'vale', 'vale', v_tipo, 'qtd', v_qtd);
  end if;
  if v_tipo = 'moedas' then
    v_qtd := v_qtd * greatest(fazenda_presente_nivel(v_nivel) / 10, 1);
    update fazenda_jogadores set moedas = moedas + v_qtd where id = p_jogador;
    return jsonb_build_object('tipo', 'moedas', 'qtd', v_qtd);
  elsif v_tipo = 'diamantes' then
    update fazenda_jogadores set diamantes = diamantes + v_qtd where id = p_jogador;
    return jsonb_build_object('tipo', 'diamantes', 'qtd', v_qtd);
  elsif v_tipo = 'xp' then
    v_xp := ceil((fazenda_xp_nivel(v_nivel + 1) - fazenda_xp_nivel(v_nivel)) * v_qtd / 100.0)::int;
    perform set_config('fazenda.xp_puro', '1', true);
    if (p->>'pago')::boolean then perform set_config('fazenda.xp_pago', '1', true); end if;
    update fazenda_jogadores set xp = xp + v_xp where id = p_jogador;
    perform set_config('fazenda.xp_puro', '', true);
    perform set_config('fazenda.xp_pago', '', true);
    return jsonb_build_object('tipo', 'xp', 'qtd', v_xp, 'pct', v_qtd);
  elsif v_tipo = 'xp2' then
    update fazenda_jogadores set xp2_ate = greatest(coalesce(xp2_ate, now()), now()) + make_interval(mins => v_qtd) where id = p_jogador;
    return jsonb_build_object('tipo', 'xp2', 'qtd', v_qtd);
  elsif v_tipo = 'cafe' then
    perform fazenda_trabalhar(p_jogador);   -- fecha o trabalho de antes no ritmo de antes (igual ao café da loja)
    perform fazenda_ajudantes_fechar(p_jogador, null);
    update fazenda_jogadores
       set cafe_de = case when cafe_ate > now() then cafe_de else now() end,
           cafe_ate = greatest(coalesce(cafe_ate, now()), now()) + make_interval(mins => v_qtd)
     where id = p_jogador;
    return jsonb_build_object('tipo', 'cafe', 'qtd', v_qtd);
  elsif v_tipo = 'item' then
    insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, p->>'item', v_qtd)
    on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
    return jsonb_build_object('tipo', 'item', 'item', p->>'item', 'qtd', v_qtd);
  elsif v_tipo = 'avatar' then
    update fazenda_jogadores set avatares = array_append(coalesce(avatares, '{}'), p->>'avatar')
     where id = p_jogador and not (p->>'avatar' = any(coalesce(avatares, '{}')));
    return jsonb_build_object('tipo', 'avatar', 'avatar', p->>'avatar');
  end if;
  return null;
end;
$$;


-- o catálogo (o jogo mostra o que vem daqui). valor: adubo e pomar = fração adiantada; pes = pés a mais
-- fase 62: barco, vara e marinheiro são do alto-mar (mar = só com o píer; aparecem na tela do barco, não
-- na loja). base = o que vem com o píer; intervalo/max = o cardume do barco (ou o cesto do marinheiro),
-- em segundos e peixes; janela = o tempo de fisgar da vara, em milésimos de segundo
-- fase 65: a tunagem do barco (peca = true): motor, sonar, porão, rede e o kit de expedição. Cada nível
-- pede moedas e materiais raros (itens); o efeito entra em fazenda_mar_item, na pescaria e no marinheiro
create or replace function public.fazenda_melhorias_tipos()
returns jsonb language sql immutable as $$
  -- fase 72: tudo 2x mais caro (o dinheiro do nível 20 em diante estava sobrando)
  select '[{"id":"adubo","nome":"Adubo premium","descricao":"As plantas nascem adiantadas: crescem 10%, 20%, 30% e 40% mais rápido (soma com o girassol e a estufa).",
            "niveis":[{"nivel":23,"custo":100000,"valor":0.1},{"nivel":26,"custo":300000,"valor":0.2},{"nivel":29,"custo":600000,"valor":0.3},{"nivel":36,"custo":1200000,"valor":0.4}]},
           {"id":"pomar","nome":"Pomar fértil","descricao":"As árvores do pomar dão frutas 15%, 30% e 45% mais rápido.",
            "niveis":[{"nivel":24,"custo":160000,"valor":0.15},{"nivel":28,"custo":400000,"valor":0.3},{"nivel":39,"custo":1000000,"valor":0.45}]},
           {"id":"pes","nome":"Mais pés de fruta","descricao":"Mais 1, 2 e 3 pés de cada fruta no pomar, além dos 4 que os terrenos dão.",
            "niveis":[{"nivel":25,"custo":120000,"valor":1},{"nivel":30,"custo":240000,"valor":2},{"nivel":41,"custo":600000,"valor":3}]},
           {"id":"barco","nome":"Barco","mar":true,"descricao":"Barco maior vai mais longe: o cardume é maior, enche mais rápido e tem peixe que o bote não alcança.",
            "base":{"nome":"Bote","valor":1,"intervalo":900,"max":16},
            "niveis":[{"nivel":34,"custo":800000,"valor":2,"nome":"Traineira","intervalo":720,"max":24,"itens":{"tabua_naval":10,"tora":10}},
                      {"nivel":37,"custo":1800000,"valor":3,"nome":"Barco de pesca","intervalo":600,"max":32,"itens":{"tabua_naval":20,"cravo":10}},
                      {"nivel":40,"custo":3600000,"valor":4,"nome":"Pesqueiro","intervalo":480,"max":40,"itens":{"tabua_naval":30,"cravo":20,"vela":2}},
                      {"nivel":43,"custo":7000000,"valor":5,"nome":"Navio oceânico","intervalo":360,"max":48,"itens":{"tabua_naval":40,"cravo":30,"vela":4,"carta_nautica":2}}]},
           {"id":"vara","nome":"Vara","mar":true,"descricao":"Vara melhor dá mais tempo para fisgar e puxa peixe maior.",
            "base":{"nome":"Vara de bambu","valor":1,"janela":900},
            "niveis":[{"nivel":32,"custo":300000,"valor":2,"nome":"Vara de fibra","janela":1100},
                      {"nivel":35,"custo":800000,"valor":3,"nome":"Molinete","janela":1300},
                      {"nivel":38,"custo":1800000,"valor":4,"nome":"Carretilha","janela":1500},
                      {"nivel":41,"custo":4000000,"valor":5,"nome":"Vara profissional","janela":1800}]},
           {"id":"marinheiro","nome":"Marinheiro","mar":true,"descricao":"O Seu Nonato pesca sozinho enquanto você cuida da fazenda: o cesto dele enche por até 8 horas. Cada nível pesca mais rápido.",
            "niveis":[{"nivel":33,"custo":500000,"valor":1,"nome":"Seu Nonato","intervalo":1800,"max":16},
                      {"nivel":36,"custo":1400000,"valor":2,"nome":"Seu Nonato com rede","intervalo":1200,"max":24},
                      {"nivel":39,"custo":3600000,"valor":3,"nome":"Seu Nonato com barco de apoio","intervalo":720,"max":40}]},
           {"id":"motor","nome":"Motor","mar":true,"peca":true,"descricao":"Motor mais forte vai e volta mais rápido: o cardume enche mais rápido.",
            "niveis":[{"nivel":33,"custo":400000,"valor":0.1,"nome":"Motor de popa","itens":{"ferro_forjado":1,"tabua_naval":5}},
                      {"nivel":39,"custo":1200000,"valor":0.2,"nome":"Motor a diesel","itens":{"ferro_forjado":2,"ancora":1,"cravo":10}},
                      {"nivel":44,"custo":3000000,"valor":0.3,"nome":"Motor turbo","itens":{"ferro_forjado":3,"ancora":2,"perola_negra":1,"cravo":20}}]},
           {"id":"sonar","nome":"Sonar","mar":true,"peca":true,"descricao":"Acha os cardumes de peixe grande e as ostras: mais peixe grande e mais pérola negra.",
            "niveis":[{"nivel":35,"custo":500000,"valor":1,"perola":150,"nome":"Sonar simples","itens":{"corda_naval":2}},
                      {"nivel":41,"custo":1600000,"valor":2,"perola":100,"nome":"Sonar colorido","itens":{"corda_naval":2,"perola_negra":1}},
                      {"nivel":45,"custo":4000000,"valor":3,"perola":70,"nome":"Sonar de varredura","itens":{"perola_negra":2,"marlim":1,"carta_nautica":2}}]},
           {"id":"porao","nome":"Porão","mar":true,"peca":true,"descricao":"Guarda o peixe no gelo: às vezes uma fisgada traz 2 peixes.",
            "niveis":[{"nivel":36,"custo":600000,"valor":0.15,"nome":"Caixa de gelo","itens":{"madeira_nobre":2,"tabua_naval":10}},
                      {"nivel":42,"custo":2000000,"valor":0.3,"nome":"Porão refrigerado","itens":{"madeira_nobre":3,"pedra_cantaria":2,"cravo":10}},
                      {"nivel":45,"custo":5000000,"valor":0.45,"nome":"Câmara fria","itens":{"pedra_cantaria":2,"ferro_forjado":2,"perola_negra":1,"cravo":15}}]},
           {"id":"rede","nome":"Rede de arrasto","mar":true,"peca":true,"descricao":"Para o marinheiro: ele pesca mais rápido (e o cesto continua guardando 8 horas).",
            "niveis":[{"nivel":37,"custo":600000,"valor":0.15,"nome":"Rede de arrasto","itens":{"corda_naval":2,"tabua_naval":5}},
                      {"nivel":43,"custo":2400000,"valor":0.3,"nome":"Rede dupla","itens":{"corda_naval":3,"ancora":1,"vela":1}}]},
           {"id":"expedicao","nome":"Kit de expedição","mar":true,"peca":true,"descricao":"Bússola, cartas náuticas e tanque extra: deixa o navio oceânico pronto para zarpar para a Ilha da Caveira Dourada (nível 46).",
            "niveis":[{"nivel":45,"custo":6000000,"valor":1,"nome":"Kit de expedição","itens":{"perola_negra":3,"marlim":2,"ancora":2,"carta_nautica":4,"vela":2}}]},
           {"id":"turno","nome":"Turno de 12 horas","diamante":true,"descricao":"Os ajudantes trabalham 12 horas com a barra de energia cheia (eram 8) e guardam até 12 horas de trabalho com a fazenda fechada.",
            "niveis":[{"nivel":5,"custo":0,"diamantes":150,"valor":12,"texto":"12 h de trabalho"}]},
           {"id":"cesto_bira","nome":"Cesto grande do Bira","diamante":true,"descricao":"O cesto do Bira no lago guarda 50% mais peixe: 24 em vez de 16 (enche por 12 horas).",
            "niveis":[{"nivel":1,"custo":0,"diamantes":80,"valor":0.5,"texto":"24 peixes"}]},
           {"id":"cesto_nonato","nome":"Cesto grande do Seu Nonato","diamante":true,"descricao":"O cesto do marinheiro no alto-mar guarda 50% mais peixe.",
            "niveis":[{"nivel":33,"custo":0,"diamantes":80,"valor":0.5,"texto":"+50% no cesto"}]},
           {"id":"fila","nome":"Fila de 15 receitas","diamante":true,"descricao":"Cada oficina guarda até 15 receitas no estoque (eram 10): trabalha mais tempo sozinha.",
            "niveis":[{"nivel":3,"custo":0,"diamantes":100,"valor":15,"texto":"15 receitas"}]},
           {"id":"barraca","nome":"Mais barracas na feira","diamante":true,"descricao":"Depois das 4 barracas compradas com moedas, a 5ª e a 6ª: cada uma dá mais 2 anúncios na feira.",
            "niveis":[{"nivel":5,"custo":0,"diamantes":100,"valor":5,"texto":"5ª barraca"},{"nivel":5,"custo":0,"diamantes":150,"valor":6,"texto":"6ª barraca"}]}]'::jsonb;
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
           nivel_premiado = v_nivel
     where id = p_jogador and nivel_premiado is not distinct from j.nivel_premiado;   -- fase 70: paga uma vez só
    select * into j from fazenda_jogadores where id = p_jogador;
  end if;
  v_omite := v_leve and fazenda_catalogos_ver(v_nivel) = current_setting('fazenda.cat_ver', true);   -- fase 89
  -- canteiros não aparecem mais sozinhos: o jogador coloca no modo construir até este limite
  v_max := fazenda_limite_canteiros(v_nivel, fazenda_terrenos(j.zonas, j.direita));
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
      'max_construcoes', fazenda_max_construcoes(fazenda_terrenos(j.zonas, j.direita)),
      'zonas', j.zonas,
      'direita', j.direita,   -- fase 78: os terrenos da direita
      'beleza', fazenda_beleza(p_jogador),
      'bonus_venda', fazenda_bonus_venda(p_jogador),
      -- fase 106: a ilha (pode zarpar? quantas obras; do 45 em diante, a lista; o baú de hoje já foi aberto?)
      'ilha', jsonb_build_object('obras', coalesce(j.ilha_obras, 0), 'pode_ir', fazenda_ilha_pode(p_jogador, v_nivel),
                                 'bau_hoje', j.ilha_bau_dia = fazenda_hoje(),
                                 'partes', case when v_nivel >= 45 then fazenda_ilha_obras() end)
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
  return v_json || jsonb_build_object('cat_ver', v_ver);
end;
$$;


-- fase 106: quem já tinha XP de sobra no 45 fica no começo do 46 (só quem ainda não ganhou o presente de
-- nenhum nível depois do 45: rodar de novo não mexe em quem já passou do 46)
select set_config('fazenda.xp_puro', '1', false);
update public.fazenda_jogadores set xp = public.fazenda_xp_nivel(46)::int
 where xp > public.fazenda_xp_nivel(46) and coalesce(nivel_premiado, 1) <= 45;
select set_config('fazenda.xp_puro', '', false);
update public.fazenda_jogadores set nivel_trava = greatest(public.fazenda_nivel_trava(id), coalesce(nivel_base, 1))
 where nivel_trava is distinct from greatest(public.fazenda_nivel_trava(id), coalesce(nivel_base, 1));

select public.fazenda_cache_montar();

revoke execute on function public.fazenda_ilha_obras(), public.fazenda_ilha_pode(uuid, int) from public, anon, authenticated;
grant execute on function public.fazenda_ilha_construir(text, text), public.fazenda_ilha_bau(text) to anon, authenticated;

-- conferência: tem que aparecer "fase 106 ok", o nível máximo 60 e as 15 obras
select case when exists (select 1 from pg_proc where proname = 'fazenda_ilha_construir') then 'fase 106 ok' else 'não aplicou' end as resultado,
       public.fazenda_nivel(2000000000) as nivel_maximo,
       jsonb_array_length(public.fazenda_ilha_obras()) as obras;
