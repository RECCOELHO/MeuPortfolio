-- ============================================================
-- FAZENDINHA — Fase 130 (cada obra da ilha faz alguma coisa), só o que mudou.
-- Para o banco que já está no ar (com a fase 129): Supabase > SQL Editor > colar este arquivo > Run.
-- Rodar ANTES do merge do PR (o jogo novo chama fazenda_ilha_canhoes).
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

alter table public.fazenda_jogadores add column if not exists canhoes_dia date;

-- fase 130: o número da obra da ilha (1 a 15, na ordem de fazenda_ilha_obras) e se o jogador já tem ela.
-- (Aqui em cima porque as funções em sql que usam isto precisam dela pronta.)
create or replace function public.fazenda_obra_n(p_id text)
returns int language sql immutable as $$
  select case p_id when 'cais' then 1 when 'trapiche' then 2 when 'armazem' then 3 when 'muralha' then 4 when 'taverna' then 5
                   when 'portao' then 6 when 'farol' then 7 when 'vigia' then 8 when 'mercado' then 9 when 'toldo' then 10
                   when 'ancora' then 11 when 'canhoes' then 12 when 'sereia' then 13 when 'cartografo' then 14 when 'bandeira' then 15 end;
$$;
create or replace function public.fazenda_obra_tem(p_jogador uuid, p_id text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select ilha_obras from fazenda_jogadores where id = p_jogador), 0) >= fazenda_obra_n(p_id);
$$;

-- ------------------------------------------------------------
-- Fase 130: cada obra da ilha faz alguma coisa (o efeito vai escrito no cartão dela, em fazenda_ilha_obras):
-- trapiche (Capitão +20%), armazém e mercado (produtos da ilha +10% cada), muralha (o furacão não arranca a
-- plantação da ilha), taverna (ajudantes 25% mais rápidos), portão (ninguém pega da ilha), farol (+50% de peixe
-- raro), vigia (metade das pragas na ilha), toldo (a planta da ilha demora o dobro para murchar), âncora (+1
-- diamante no baú do X), canhões (presente 1 vez por dia), sereia (+1 na colheita da ilha) e cartógrafo (seta
-- na próxima pista e o dobro de moedas nelas). O cais e a bandeira já tinham o deles.
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------


-- as funções que mudaram

create or replace function public.fazenda_ilha_obras()
returns jsonb language sql immutable as $$
  select '[
    {"n": 1,  "id": "cais",       "nivel": 46, "nome": "Cais de madeira",      "moedas": 400000,  "itens": {"tora": 12, "madeira_nobre": 1},       "descricao": "Onde o navio atraca. Com ele pronto, dá para cavar o baú da praia.", "efeito": "Libera o baú do X e a caça ao tesouro."},
    {"n": 2,  "id": "trapiche",   "nivel": 47, "nome": "Trapiche",             "moedas": 500000,  "itens": {"tabua_naval": 20},                    "descricao": "A passarela do cais até a areia.", "efeito": "O Capitão paga +20% nas entregas."},
    {"n": 3,  "id": "armazem",    "nivel": 48, "nome": "Armazém do porto",     "moedas": 600000,  "itens": {"tabua_naval": 30, "tora": 10},         "descricao": "Para guardar a carga do navio.", "efeito": "Os produtos da ilha vendem +10% no celeiro."},
    {"n": 4,  "id": "muralha",    "nivel": 49, "nome": "Muralha de pedra",     "moedas": 700000,  "itens": {"tabua_naval": 20, "pedra_cantaria": 1}, "descricao": "Segura o mar nos dias de ressaca.", "efeito": "O furacão não arranca a plantação da ilha."},
    {"n": 5,  "id": "taverna",    "nivel": 50, "nome": "Taverna",              "moedas": 800000,  "itens": {"tabua_naval": 30, "cravo": 20},        "descricao": "Onde os marujos contam as histórias da ilha.", "efeito": "Os ajudantes trabalham 25% mais rápido (na fazenda e na ilha)."},
    {"n": 6,  "id": "portao",     "nivel": 51, "nome": "Portão de ferro",      "moedas": 900000,  "itens": {"cravo": 20, "ferro_forjado": 1},      "descricao": "A entrada do porto.", "efeito": "Ninguém pega dos canteiros da ilha, nem com a luva do Perks."},
    {"n": 7,  "id": "farol",      "nivel": 52, "nome": "Farol",                "moedas": 1000000, "itens": {"leme_dourado": 1, "tabua_naval": 15},  "descricao": "Com o espelho dourado que guia os navios de noite.", "efeito": "+50% de chance de peixe raro no alto-mar."},
    {"n": 8,  "id": "vigia",      "nivel": 53, "nome": "Cabana do vigia",      "moedas": 1100000, "itens": {"tora": 20, "cravo": 20},               "descricao": "Lá de cima dá para ver o mar todo.", "efeito": "Metade das pragas nos canteiros da ilha."},
    {"n": 9,  "id": "mercado",    "nivel": 54, "nome": "Mercado pirata",       "moedas": 1200000, "itens": {"corda_naval": 2, "vela": 2},          "descricao": "As barracas de lona da praça.", "efeito": "Os produtos da ilha vendem mais +10% (com o armazém, +20%)."},
    {"n": 10, "id": "toldo",      "nivel": 55, "nome": "Toldo da praça",       "moedas": 1400000, "itens": {"vela": 6},                            "descricao": "Sombra feita de velas velhas.", "efeito": "A planta da ilha demora o dobro para murchar."},
    {"n": 11, "id": "ancora",     "nivel": 56, "nome": "Âncora gigante",       "moedas": 1600000, "itens": {"ancora": 1, "cravo": 30},             "descricao": "O enfeite da praça, de um navio afundado.", "efeito": "+1 diamante no baú do X, todo dia."},
    {"n": 12, "id": "canhoes",    "nivel": 57, "nome": "Canhões de festa",     "moedas": 1800000, "itens": {"cravo": 40, "carta_nautica": 1},      "descricao": "Três canhões que só soltam confete.", "efeito": "1 vez por dia, toque neles: confete e um presente."},
    {"n": 13, "id": "sereia",     "nivel": 58, "nome": "Estátua da sereia",    "moedas": 2000000, "itens": {"perola_negra": 1, "tabua_naval": 20}, "descricao": "Dourada, com olhos de pérola.", "efeito": "+1 na colheita de cada canteiro da ilha."},
    {"n": 14, "id": "cartografo", "nivel": 59, "nome": "Casa do cartógrafo",   "moedas": 2200000, "itens": {"carta_nautica": 5, "tabua_naval": 20},"descricao": "Com os mapas das próximas ilhas.", "efeito": "Uma seta mostra a próxima pista, e as pistas dão o dobro de moedas."},
    {"n": 15, "id": "bandeira",   "nivel": 60, "nome": "Bandeira no morro",    "moedas": 2500000, "itens": {"carta_nautica": 4, "vela": 4},        "descricao": "A ilha é sua: a bandeira no alto do morro.", "efeito": "Abre a caverna da Caveira Dourada."}
  ]'::jsonb;
$$;


-- o toldo da praça: na ilha (y >= 45), a planta demora o dobro para murchar (só olha a obra quando o canteiro é da ilha)
create or replace function public.fazenda_murcha_seg(p_tempo int, p_seco boolean, p_y int, p_dono uuid)
returns int language sql stable set search_path = public as $$
  select fazenda_murcha_seg(p_tempo, p_seco) * case when p_y >= 45 and fazenda_obra_tem(p_dono, 'toldo') then 2 else 1 end;
$$;

-- os canhões de festa: 1 vez por dia, um presente (moedas, ou diamantes 3 em cada 10 vezes)
create or replace function public.fazenda_ilha_canhoes(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  j       record;
  v_nivel int;
  v_moeda int := 0;
  v_diam  int := 0;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  if coalesce(j.ilha_obras, 0) < fazenda_obra_n('canhoes') then raise exception 'canhoes_fechado'; end if;
  if j.canhoes_dia = fazenda_hoje() then raise exception 'canhoes_hoje'; end if;
  v_nivel := fazenda_nivel_de(j.xp, j.nivel_trava);
  if random() < 0.3 then v_diam := 3 + floor(random() * 5)::int;
  else v_moeda := round((30000 + greatest(v_nivel - 45, 0) * 4000) * (0.7 + random() * 0.6))::int;
  end if;
  update fazenda_jogadores set canhoes_dia = fazenda_hoje(), diamantes = diamantes + v_diam,
         moedas = least(2147483647, moedas::bigint + v_moeda)::int,
         moedas_ganhas = moedas_ganhas - v_moeda   -- (como o baú, não conta no evento das moedas)
   where id = v_id;
  return jsonb_build_object('moedas', v_moeda, 'diamantes', v_diam, 'estado', fazenda_estado(v_id));
end;
$$;

-- o painel do Capitão: os pedidos de hoje, o que você tem de cada um e o baú
create or replace function public.fazenda_capitao(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id    uuid := fazenda_auth_ler(p_token);
  j       record;
  v_nivel int;
  v_mult  numeric;
begin
  select * into j from fazenda_jogadores where id = v_id;
  v_nivel := fazenda_nivel_de(j.xp, j.nivel_trava);
  v_mult := case when coalesce(j.ilha_obras, 0) >= fazenda_obra_n('trapiche') then 1.2 else 1 end;   -- fase 130: o trapiche
  if not fazenda_ilha_pode(v_id, v_nivel) then raise exception 'ilha_fechada'; end if;
  perform fazenda_capitao_gerar(v_id, v_nivel);
  return jsonb_build_object(
    'pedidos', coalesce((select jsonb_agg(jsonb_build_object('slot', c.slot, 'item', c.item, 'qtd', c.qtd, 'moedas', round(c.moedas * v_mult)::int, 'xp', c.xp,
                                                             'diamantes', c.diamantes, 'feito', c.feito_em is not null,
                                                             'tem', greatest(0, coalesce(ce.quantidade, 0) - coalesce(rs.quantidade, 0))) order by c.slot)
                           from fazenda_capitao c
                           left join fazenda_celeiro ce on ce.jogador_id = c.jogador_id and ce.item = c.item
                           left join fazenda_reservas rs on rs.jogador_id = c.jogador_id and rs.item = c.item
                          where c.jogador_id = v_id and c.dia = fazenda_hoje()), '[]'::jsonb),
    'bau', (select jsonb_build_object('diamantes', b.diamantes, 'raro', b.raro) from fazenda_capitao_bau b where b.jogador_id = v_id and b.dia = fazenda_hoje()));
end;
$$;


-- entregar um pedido (o que está guardado para os bichos ou o navio fica)
create or replace function public.fazenda_capitao_entregar(p_token text, p_slot int)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  c       record;
  v_livre int;
  v_bau   jsonb;
  v_raro  text;
  v_moedas int;
begin
  select * into c from fazenda_capitao where jogador_id = v_id and dia = fazenda_hoje() and slot = p_slot for update;
  if not found then raise exception 'capitao_sem_pedido'; end if;
  if c.feito_em is not null then raise exception 'capitao_ja_entregue'; end if;
  v_moedas := round(c.moedas * case when fazenda_obra_tem(v_id, 'trapiche') then 1.2 else 1 end)::int;   -- fase 130: o trapiche
  select ce.quantidade - coalesce((select r.quantidade from fazenda_reservas r where r.jogador_id = v_id and r.item = c.item), 0)
    into v_livre from fazenda_celeiro ce where ce.jogador_id = v_id and ce.item = c.item for update;
  if coalesce(v_livre, 0) < c.qtd then raise exception 'capitao_falta'; end if;
  update fazenda_celeiro set quantidade = quantidade - c.qtd, da_feira = greatest(0, least(da_feira, quantidade - c.qtd))
   where jogador_id = v_id and item = c.item;
  update fazenda_capitao set feito_em = now() where jogador_id = v_id and dia = c.dia and slot = c.slot;
  update fazenda_jogadores set moedas = least(2147483647, moedas::bigint + v_moedas)::int, xp = xp + c.xp, diamantes = diamantes + c.diamantes
   where id = v_id;
  -- os 3 entregues: o baú do Capitão (10 diamantes e um raro do píer, sorteado como no mercador)
  if not exists (select 1 from fazenda_capitao where jogador_id = v_id and dia = c.dia and feito_em is null)
     and not exists (select 1 from fazenda_capitao_bau where jogador_id = v_id and dia = c.dia) then
    v_raro := (array['madeira_nobre', 'corda_naval', 'pedra_cantaria', 'ferro_forjado', 'ancora', 'perola_negra'])[1 + floor(random() * 6)::int];
    insert into fazenda_capitao_bau (jogador_id, dia, diamantes, raro) values (v_id, c.dia, 10, v_raro);
    update fazenda_jogadores set diamantes = diamantes + 10 where id = v_id;
    insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, v_raro, 1)
    on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
    v_bau := jsonb_build_object('diamantes', 10, 'raro', v_raro);
  end if;
  return jsonb_build_object('item', c.item, 'qtd', c.qtd, 'moedas', v_moedas, 'xp', c.xp, 'diamantes', c.diamantes, 'bau', v_bau,
                            'estado', fazenda_estado(v_id));
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
  v_ilha  int;   -- fase 130
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

  -- fase 130: o armazém do porto e o mercado pirata: os produtos da ilha vendem +10% cada
  v_ilha := 10 * fazenda_obra_tem(v_id, 'armazem')::int + 10 * fazenda_obra_tem(v_id, 'mercado')::int;
  -- o que está reservado para os animais fica no celeiro
  for r in
    select ce.item, ce.quantidade - coalesce(rs.quantidade, 0) as livre, ce.da_feira,
           case when k.id = 'velho_chico' then fazenda_preco_chico(v_nivel) else k.venda end as venda,   -- fase 107
           k.tipo, k.nivel_min, (k.so_ilha or fazenda_capitao_itens() ? ce.item) as da_ilha   -- fase 130
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
    v_ganho := v_ganho + v_qtd * r.venda + case when r.da_ilha and v_ilha > 0 then (v_qtd * r.venda * v_ilha) / 100 else 0 end;   -- fase 130
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


-- Sorteia os pedaços de 36 min que passaram (no máximo os das últimas 48 h) e aplica o raio e o furacão.
-- Depois, o eletricista conserta o que já esperou o tempo dele.
create or replace function public.fazenda_tempestade(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_r     jsonb := fazenda_extremo_regras();
  v_cur   bigint := floor(extract(epoch from now()) / 2160);
  v_chance real := 1.0 / (fazenda_extremo_regras()->>'chance')::int;
  v_desde timestamptz;
  v_nivel int;
  v_t     timestamptz;
  v_e     text;
  v_min   int;
  v_ult   bigint;
  a       record;
begin
  select tempestade_em, fazenda_nivel_de(xp, nivel_trava) into v_desde, v_nivel from fazenda_jogadores where id = p_jogador;
  if v_desde is null then   -- conta daqui para a frente (ninguém leva raio de antes da fase 77)
    update fazenda_jogadores set tempestade_em = to_timestamp(v_cur * 2160) where id = p_jogador;
    return;
  end if;
  v_ult := floor(extract(epoch from v_desde) / 2160);
  if v_ult < v_cur then
    update fazenda_jogadores set tempestade_em = to_timestamp(v_cur * 2160) where id = p_jogador;
    if v_nivel >= (v_r->>'nivel')::int then
      for s in greatest(v_ult + 1, v_cur - (v_r->>'fatias_max')::int + 1)..v_cur loop
        v_t := to_timestamp(s::bigint * 2160);
        v_e := fazenda_extremo_em(v_t + interval '1 minute');
        continue when v_e is null;
        perform fazenda_energia_atualizar(p_jogador);   -- até aqui, os geradores contam ligados
        -- o raio (ou o vento do furacão) num painel solar ou numa turbina: sobrecarga
        for a in update fazenda_construcoes c
                    set sobrecarga_em = least(now(), v_t + make_interval(secs => floor(random() * 2160)::int))
                   from fazenda_itens i
                  where i.id = c.tipo and c.jogador_id = p_jogador and i.efeito in ('solar', 'eolica')
                    and c.sobrecarga_em is null and random() < v_chance
                 returning c.tipo, c.x, c.y, c.sobrecarga_em loop
          insert into fazenda_clima_eventos (jogador_id, evento, clima, item, x, y, em)
          values (p_jogador, 'sobrecarga', v_e, a.tipo, a.x, a.y, a.sobrecarga_em);
        end loop;
        if v_e = 'furacao' then   -- o furacão arranca a plantação (a estufa protege em volta dela)
          with alvo as (
            select cc.posicao, cc.cultura, cc.x, cc.y from fazenda_canteiros cc
             where cc.jogador_id = p_jogador and cc.estado = 'plantado' and cc.plantado_em < v_t + interval '36 minutes'
               and random() < v_chance and not fazenda_protegido(p_jogador, 'estufa', cc.x, cc.y)
               and not (cc.y >= 45 and fazenda_obra_tem(p_jogador, 'muralha'))   -- fase 130: a muralha segura a ilha
               for update),
          feito as (
            update fazenda_canteiros cc
               set estado = 'arado', cultura = null, plantado_em = null,
                   erva = false, praga = false, seco = false, roubado = 0, prox_evento = null, adubado = false
              from alvo where cc.jogador_id = p_jogador and cc.posicao = alvo.posicao)
          insert into fazenda_clima_eventos (jogador_id, evento, clima, item, x, y, em)
          select p_jogador, 'arrancou', 'furacao', alvo.cultura, alvo.x, alvo.y, least(now(), v_t + interval '18 minutes') from alvo;
        end if;
      end loop;
    end if;
    delete from fazenda_clima_eventos where jogador_id = p_jogador and em < now() - interval '7 days';
  end if;
  -- o eletricista conserta sozinho
  if exists (select 1 from fazenda_construcoes where jogador_id = p_jogador and sobrecarga_em is not null) then
    select (v_r->'eletricista_min'->>(least(h.nivel, 5) - 1))::int into v_min
      from fazenda_ajudantes h where h.jogador_id = p_jogador and h.tipo = 'eletricista';
    if v_min is not null and exists (select 1 from fazenda_construcoes where jogador_id = p_jogador
                                        and sobrecarga_em <= now() - make_interval(mins => v_min)) then
      perform fazenda_energia_atualizar(p_jogador);   -- até aqui, eles estavam parados
      for a in update fazenda_construcoes set sobrecarga_em = null
                where jogador_id = p_jogador and sobrecarga_em <= now() - make_interval(mins => v_min)
               returning tipo, x, y loop
        insert into fazenda_clima_eventos (jogador_id, evento, item, x, y) values (p_jogador, 'consertou', a.tipo, a.x, a.y);
      end loop;
    end if;
  end if;
end;
$$;


-- Os ajudantes fazem o trabalho acumulado desde a última vez (até 8 horas).
-- Roda quando a fazenda carrega (abrir a página e a cada 30 s com ela aberta).
-- Fase 71: cada ajudante trabalha num lote só. Primeiro no modo rápido: cada tarefa direto, sem o
-- "exception" em volta de cada uma (cada um abria uma sub-transação; com centenas delas numa chamada o
-- banco ficava lento para todo mundo e a volta depois de horas fora passava dos 3 s). Se alguma tarefa
-- der erro, o lote daquele ajudante volta e é refeito no modo seguro, cada tarefa protegida como antes.
-- O resultado é o mesmo. A estação sai uma vez só e a semeadora conta as sementes plantadas uma vez só.
create or replace function public.fazenda_trabalhar(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  a       record;
  c       record;
  m       record;
  v_cred  real;
  v_n     int;
  v_feito int;
  v_sem   text;
  v_nivel int;
  v_ok    boolean;
  v_cafe_de  timestamptz;
  v_cafe_ate timestamptz;
  v_seg   real;
  v_custo real;              -- fase 59: energia que cada tarefa gasta (a barra cheia dura 8 h de trabalho)
  v_energia real;
  v_cama  boolean;           -- fase 59: cansou e tem cama livre numa casinha
  v_log   jsonb;             -- fase 59: o que ele fez nesta rodada ({"colheu": 3, ...})
  v_reg   boolean := false;  -- fase 66: as murchas já foram registradas nesta rodada?
  v_seguro boolean;          -- fase 71: refazendo o lote no modo seguro?
  v_est   text := fazenda_estacao_em(now());   -- fase 71: a estação de agora (uma vez só)
  v_cont  jsonb;             -- fase 71: quantos canteiros de cada semente (o rodízio da semeadora)
  v_moedas int;
begin
  select cafe_de, cafe_ate into v_cafe_de, v_cafe_ate from fazenda_jogadores where id = p_jogador;
  for a in
    select h.tipo, h.nivel, h.credito, h.atualizado_em, h.energia, h.descanso_ate, t.funcao, t.alvo
      from fazenda_ajudantes h join fazenda_ajudantes_tipos t on t.id = h.tipo
     where h.jogador_id = p_jogador
     order by (t.funcao = 'colher') desc, t.ordem   -- fase 48: quem colhe vem antes de quem ara as murchas
       for update of h
  loop
    -- fase 66: o colhedor já passou; antes de o lavrador arar as murchas, cada uma ganha o seu motivo
    if not v_reg and a.funcao <> 'colher' then perform fazenda_murchas_registrar(p_jogador); v_reg := true; end if;
    -- o eletricista não faz tarefas: ele baixa o gasto de energia (fazenda_energia_preco)
    continue when a.funcao = 'energia';
    -- fase 59: descansando não trabalha (nem junta crédito); acabou o descanso, volta com a energia cheia
    if a.descanso_ate is not null then
      continue when a.descanso_ate > now();
      update fazenda_ajudantes set energia = 100, descanso_ate = null, descanso_motivo = null, descanso_casa = null, credito = 0, atualizado_em = a.descanso_ate
       where jogador_id = p_jogador and tipo = a.tipo;
      a.energia := 100; a.credito := 0; a.atualizado_em := a.descanso_ate;
    end if;
    -- com o jogador na fazenda a semeadora descansa (o tempo online não conta para ela)
    if a.funcao = 'plantar' and coalesce((select carregado_antes > now() - interval '4 minutes' from fazenda_jogadores where id = p_jogador), false) then
      update fazenda_ajudantes set atualizado_em = now() where jogador_id = p_jogador and tipo = a.tipo;
      continue;
    end if;
    v_custo := 100 / (fazenda_ritmo(a.nivel) * fazenda_turno(p_jogador));   -- fase 82: 12 h com o turno de diamante
    -- fase 43: com o café (diamantes) o tempo dentro dele vale em dobro
    v_seg := extract(epoch from now() - a.atualizado_em)::real
           + case when v_cafe_ate is null then 0
                  else greatest(extract(epoch from least(now(), v_cafe_ate) - greatest(a.atualizado_em, v_cafe_de))::real, 0) end;
    if fazenda_obra_tem(p_jogador, 'taverna') then v_seg := v_seg * 1.25; end if;   -- fase 130: a taverna
    v_cred := least(a.credito + v_seg / 3600 * fazenda_ritmo(a.nivel), fazenda_ritmo(a.nivel) * fazenda_turno(p_jogador));
    v_n := least(floor(v_cred), floor(a.energia / v_custo + 0.001))::int;   -- fase 59: e o que a energia deixa

    for v_tent in 1..2 loop   -- fase 71: 1 = modo rápido; 2 = deu erro, refaz no modo seguro
      v_seguro := v_tent = 2;
      v_feito := 0;
      v_log := '{}'::jsonb;
      begin
        if v_n > 0 and a.funcao = 'colher' then
          -- fase 48: também o que murchou depois da última olhada dele (até 8 h): com a fazenda fechada ele
          -- teria colhido a tempo; o que murcha primeiro vai primeiro
          for c in
            select cc.posicao, now() >= cc.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, cc.seco, cc.y, cc.jogador_id)) as murcha
              from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
             where cc.jogador_id = p_jogador and cc.estado = 'plantado'
               and now() >= cc.plantado_em + make_interval(secs => k.tempo_seg)
               and cc.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, cc.seco, cc.y, cc.jogador_id))
                   > greatest(a.atualizado_em, now() - make_interval(hours => fazenda_turno(p_jogador)::int))
             order by cc.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, cc.seco, cc.y, cc.jogador_id)) limit v_n
          loop
            if fazenda_bot_aplicar(p_jogador, case when c.murcha then 'colher_tarde' else 'colher' end, c.posicao, null, v_seguro) is not null then
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'colheu');
            end if;
          end loop;
          -- fase 43: com o tempo que sobra, colhe as frutas do pomar (para o celeiro); a árvore encostada
          -- num baú fica para o baú (é ela que alimenta a rede de canos)
          if v_feito < v_n then
            for c in
              select k.x, k.y, k.tipo, i.produz, i.produz_qtd from fazenda_construcoes k join fazenda_itens i on i.id = k.tipo
               where k.jogador_id = p_jogador and i.categoria = 'pomar' and i.produz is not null
                 and (k.colhido_em is null or now() >= k.colhido_em + make_interval(secs => i.produz_seg))
                 and not exists (select 1 from fazenda_construcoes b
                                  where b.jogador_id = p_jogador and b.tipo = 'bau' and abs(b.x - k.x) + abs(b.y - k.y) = 1)
               order by k.colhido_em nulls first, k.x, k.y limit v_n - v_feito
            loop
              update fazenda_construcoes set colhido_em = fazenda_colhido_agora(p_jogador, c.tipo) where jogador_id = p_jogador and x = c.x and y = c.y;
              insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, c.produz, c.produz_qtd)
              on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'frutas');
            end loop;
          end if;

        elsif v_n > 0 and a.funcao = 'oficina' then
          -- fase 43, a operária: a rede anda primeiro (ela só faz o que a rede não fez)...
          perform fazenda_oficinas_andar(p_jogador);
          -- ...leva para o celeiro o que ficou pronto esperando...
          for c in
            select k.x, k.y, k.prontos, i.produz from fazenda_construcoes k join fazenda_itens i on i.id = k.tipo
             where k.jogador_id = p_jogador and i.entradas is not null and k.prontos > 0
             order by i.ordem, k.x, k.y
          loop
            exit when v_feito >= v_n;
            insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, c.produz, c.prontos)
            on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
            update fazenda_construcoes set prontos = 0 where jogador_id = p_jogador and x = c.x and y = c.y;
            v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'levou', c.prontos);
          end loop;
          -- ...e enche o estoque com o que tem no celeiro, uma receita por vez em rodízio (a parada já começa)
          v_ok := true;
          while v_ok and v_feito < v_n loop
            v_ok := false;
            for c in
              select k.x, k.y, i.entradas from fazenda_construcoes k join fazenda_itens i on i.id = k.tipo
               where k.jogador_id = p_jogador and i.entradas is not null
                 and k.estoque + (k.iniciado_em is not null)::int < fazenda_estoque_max_de(p_jogador)
               order by i.ordem, k.x, k.y
            loop
              exit when v_feito >= v_n;
              if fazenda_abastecer(p_jogador, c.entradas, 1) = 1 then
                update fazenda_construcoes
                   set iniciado_em = coalesce(iniciado_em, now()),
                       estoque = estoque + case when iniciado_em is null then 0 else 1 end
                 where jogador_id = p_jogador and x = c.x and y = c.y;
                v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'encheu');
                v_ok := true;
              end if;
            end loop;
          end loop;

        elsif v_n > 0 and a.funcao = 'arar' then
          for c in
            select cc.posicao from fazenda_canteiros cc left join fazenda_culturas k on k.id = cc.cultura
             where cc.jogador_id = p_jogador
               and (cc.estado = 'vazio'
                    or (cc.estado = 'plantado' and now() >= cc.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, cc.seco, cc.y, cc.jogador_id))))
             order by cc.posicao limit v_n
          loop
            if fazenda_bot_aplicar(p_jogador, 'arar', c.posicao, null, v_seguro) is not null then
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'arou');
            end if;
          end loop;
          -- sobrou tempo: aduba os canteiros que estão crescendo (+1 item na colheita de cada um)
          if v_feito < v_n then
            for c in
              select cc.posicao from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
               where cc.jogador_id = p_jogador and cc.estado = 'plantado' and not cc.adubado
                 and now() < cc.plantado_em + make_interval(secs => k.tempo_seg)
               order by cc.plantado_em limit v_n - v_feito
            loop
              if fazenda_bot_aplicar(p_jogador, 'adubar', c.posicao, null, v_seguro) is not null then
                v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'adubou');
              end if;
            end loop;
          end if;

        elsif v_n > 0 and a.funcao = 'plantar' then
          v_nivel := (select fazenda_nivel_de(xp, nivel_trava) from fazenda_jogadores where id = p_jogador);
          -- (fase 71: a conta de cada semente sai uma vez e anda junto com o que ela planta)
          select coalesce(jsonb_object_agg(x.cultura, x.n), '{}'::jsonb) into v_cont
            from (select cultura, count(*) as n from fazenda_canteiros
                   where jogador_id = p_jogador and estado = 'plantado' group by cultura) x;
          for c in
            select posicao from fazenda_canteiros
             where jogador_id = p_jogador and estado = 'arado' order by posicao limit v_n
          loop
            -- rodízio com todas as sementes da estação que o nível libera: a menos plantada primeiro,
            -- pulando as que o dinheiro não paga
            v_ok := false;
            select moedas into v_moedas from fazenda_jogadores where id = p_jogador;
            for v_sem in
              select k.id from fazenda_culturas k
               where k.tipo = 'cultura' and k.nivel_min <= v_nivel
                 and (k.estacao is null or k.estacao = v_est)
                 and k.custo <= v_moedas
               order by coalesce((v_cont->>k.id)::int, 0), k.ordem
            loop
              if fazenda_bot_aplicar(p_jogador, 'plantar', c.posicao, v_sem, v_seguro) is not null then
                v_feito := v_feito + 1; v_ok := true; v_log := fazenda_conta(v_log, 'plantou');
                v_cont := v_cont || jsonb_build_object(v_sem, coalesce((v_cont->>v_sem)::int, 0) + 1);
                exit;
              end if;
            end loop;
            exit when not v_ok;   -- nenhuma semente que o dinheiro pague: para
          end loop;

        elsif v_n > 0 and a.funcao = 'cuidar' then
          for c in
            select cc.posicao, cc.erva, cc.praga, cc.seco from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
             where cc.jogador_id = p_jogador and cc.estado = 'plantado' and (cc.erva or cc.praga or cc.seco)
               and now() < cc.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, cc.seco, cc.y, cc.jogador_id))
             order by cc.plantado_em
          loop
            exit when v_feito >= v_n;
            if c.erva and v_feito < v_n and fazenda_bot_aplicar(p_jogador, 'erva', c.posicao, null, v_seguro) is not null then
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'erva');
            end if;
            if c.praga and v_feito < v_n and fazenda_bot_aplicar(p_jogador, 'praga', c.posicao, null, v_seguro) is not null then
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'praga');
            end if;
            if c.seco and v_feito < v_n and fazenda_bot_aplicar(p_jogador, 'seco', c.posicao, null, v_seguro) is not null then
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'seco');
            end if;
          end loop;

        elsif v_n > 0 and a.funcao = 'animal' then
          for m in
            select an.id, an.alimentado_em, t.tempo_seg, t.racao, fazenda_racao_qtd(t.racao_qtd) as racao_qtd from fazenda_animais an join fazenda_animais_tipos t on t.id = an.tipo
             where an.jogador_id = p_jogador and an.tipo = a.alvo order by an.id
          loop
            exit when v_feito >= v_n;
            -- coletar e dar ração separados: faltar ração não desfaz a coleta
            if m.alimentado_em is not null and now() >= m.alimentado_em + make_interval(secs => m.tempo_seg) then
              if fazenda_bot_animal(p_jogador, m.id, 'coletar', v_seguro) then
                v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'coletou');
                m.alimentado_em := null;
              end if;
            end if;
            -- sem ração no celeiro: pula (fase 71: confere antes de tentar)
            if m.alimentado_em is null and v_feito < v_n
               and coalesce((select quantidade from fazenda_celeiro where jogador_id = p_jogador and item = m.racao), 0) >= m.racao_qtd then
              if fazenda_bot_animal(p_jogador, m.id, 'alimentar', v_seguro) then
                v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'alimentou');
              end if;
            end if;
          end loop;
        end if;

        -- fase 46: quem não fez nada não é regravado: o crédito continua saindo do tempo desde
        -- atualizado_em (até 8 h), igual; contratar/evoluir e o café fecham a conta antes (fazenda_ajudantes_fechar)
        if v_feito > 0 then
          -- fase 59: gasta a energia; sem energia para mais uma tarefa, descansa sozinho: 2 h numa cama
          -- livre das casinhas, 4 h na sombra se todas estiverem ocupadas
          v_energia := greatest(a.energia - v_feito * v_custo, 0);
          v_cama := v_energia < v_custo and fazenda_camas_ocupadas(p_jogador) < fazenda_camas(p_jogador);
          update fazenda_ajudantes
             set credito = v_cred - v_feito, atualizado_em = now(), relatorio = relatorio + v_feito,
                 energia = v_energia,
                 descanso_ate = case when v_energia < v_custo then now() + case when v_cama then interval '2 hours' else interval '4 hours' end end,
                 descanso_motivo = case when v_energia < v_custo then 'cansou' end,
                 descanso_casa = case when v_energia < v_custo then v_cama end,
                 -- fase 66: a janela do último descanso fica guardada (para o relatório da planta murcha)
                 ultimo_descanso_de = case when v_energia < v_custo then now() else ultimo_descanso_de end,
                 ultimo_descanso_ate = case when v_energia < v_custo then now() + case when v_cama then interval '2 hours' else interval '4 hours' end else ultimo_descanso_ate end,
                 ultimo_descanso_motivo = case when v_energia < v_custo then case when v_cama then 'cama' else 'sombra' end else ultimo_descanso_motivo end
           where jogador_id = p_jogador and tipo = a.tipo;
          perform fazenda_ajudante_registrar(p_jogador, a.tipo, v_log);
        end if;
        exit;   -- deu certo: o próximo ajudante
      exception when others then
        if v_seguro then raise; end if;   -- (no modo seguro cada tarefa já se protege: este erro é de verdade)
      end;
    end loop;
  end loop;
  if not v_reg then perform fazenda_murchas_registrar(p_jogador); end if;   -- fase 66
  perform fazenda_bot_xp_gravar();   -- fase 72: o XP do que colheram, uma vez só
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
  if c.y >= 45 and fazenda_obra_tem(p_dono, 'portao') then raise exception 'portao_ilha'; end if;   -- fase 130: o portão de ferro
  if k.so_dia is not null then raise exception 'nada_pra_pegar'; end if;   -- fase 115: a Viih ninguém pega
  v_maduro := c.plantado_em + make_interval(secs => k.tempo_seg);
  if now() < v_maduro then
    raise exception 'nao_maduro';
  end if;
  if now() >= v_maduro + make_interval(secs => fazenda_murcha_seg(k.tempo_seg, c.seco, c.y, c.jogador_id)) then
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


-- o alto-mar no estado do jogo (null sem o píer)
create or replace function public.fazenda_mar_estado(p_jogador uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when j.pier_em is not null then jsonb_build_object(
           'barco', b.i, 'vara', v.i, 'marinheiro', m.i,
           'cardume', jsonb_build_object('desde', j.mar_em, 'intervalo', (b.i->>'intervalo')::int, 'max', (b.i->>'max')::int),
           'cesto', case when m.i is not null then
                      jsonb_build_object('desde', j.marinheiro_em, 'intervalo', (m.i->>'intervalo')::int, 'max', (m.i->>'max')::int) end,
           'peixes', (select jsonb_agg(jsonb_build_object('id', t.peixe, 'chance', t.chance))
                        from fazenda_mar_peixes((b.i->>'valor')::int, (v.i->>'valor')::int + fazenda_melhoria(p_jogador, 'sonar')::int + fazenda_obra_tem(p_jogador, 'farol')::int) t),
           'regras', fazenda_mar_regras(),
           'perola', fazenda_mar_perola(p_jogador),                  -- fase 65: o sonar acha mais pérola
           'visual', coalesce(j.barco_visual, '{}'::jsonb)) end
    from fazenda_jogadores j
    cross join lateral (select fazenda_mar_item(p_jogador, 'barco') as i) b
    cross join lateral (select fazenda_mar_item(p_jogador, 'vara') as i) v
    cross join lateral (select fazenda_mar_item(p_jogador, 'marinheiro') as i) m
   where j.id = p_jogador;
$$;


-- Lança a linha: tira 1 peixe do cardume, sorteia qual é e quando ele morde. Volta rápido (sem o
-- estado inteiro): quanto esperar, a janela de fisgar, o tamanho do peixe (a boia puxa mais) e o mar.
create or replace function public.fazenda_mar_lancar(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id     uuid := fazenda_auth(p_token);
  j        record;
  v_b      jsonb := fazenda_mar_item(v_id, 'barco');
  v_v      jsonb := fazenda_mar_item(v_id, 'vara');
  v_g      jsonb := fazenda_mar_regras();
  v_cheio  interval;
  v_peixe  text;
  v_espera int;
  v_tam    int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  if j.pier_em is null then raise exception 'sem_pier'; end if;
  if fazenda_mar_contar(v_id, 'barco') < 1 then raise exception 'cardume_vazio'; end if;
  -- tira 1 do cardume (o que passou do máximo já não contava)
  v_cheio := make_interval(secs => (v_b->>'max')::int * (v_b->>'intervalo')::int);
  update fazenda_jogadores
     set mar_em = greatest(coalesce(mar_em, now() - v_cheio), now() - v_cheio) + make_interval(secs => (v_b->>'intervalo')::int)
   where id = v_id;
  v_peixe := fazenda_mar_sortear((v_b->>'valor')::int, (v_v->>'valor')::int + fazenda_melhoria(v_id, 'sonar')::int + fazenda_obra_tem(v_id, 'farol')::int);   -- fase 65: o sonar
  v_espera := (v_g->>'mordida_min')::int + floor(random() * ((v_g->>'mordida_max')::int - (v_g->>'mordida_min')::int))::int;
  select x.o into v_tam from jsonb_array_elements(fazenda_mar_tabela()) with ordinality as x(p, o) where x.p->>'id' = v_peixe;
  insert into fazenda_mar_lances (jogador_id, peixe, perola, mordida_em, janela_ms)
  values (v_id, v_peixe, random() < 1.0 / fazenda_mar_perola(v_id), now() + make_interval(secs => v_espera / 1000.0), (v_v->>'janela')::int)
  on conflict (jogador_id) do update set
    peixe = excluded.peixe, perola = excluded.perola, mordida_em = excluded.mordida_em,
    janela_ms = excluded.janela_ms, criado_em = now();
  return jsonb_build_object('espera_ms', v_espera, 'janela_ms', (v_v->>'janela')::int, 'tamanho', v_tam,
                            'agora', now(), 'mar', fazenda_mar_estado(v_id));
end;
$$;


-- Recolhe o cesto do marinheiro (igual ao do Bira no lago): cada peixe sorteado com o seu barco e a
-- sua vara; o que passou do máximo (8 h) se perdeu
create or replace function public.fazenda_mar_recolher(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id      uuid := fazenda_auth(p_token);
  j         record;
  v_m       jsonb := fazenda_mar_item(v_id, 'marinheiro');
  v_b       jsonb := fazenda_mar_item(v_id, 'barco');
  v_v       jsonb := fazenda_mar_item(v_id, 'vara');
  v_g       jsonb := fazenda_mar_regras();
  v_n       int;
  v_k       int;
  v_p       text;
  v_peixes  jsonb := '{}'::jsonb;
  v_perolas int := 0;
  v_xp      int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  if j.pier_em is null then raise exception 'sem_pier'; end if;
  if v_m is null then raise exception 'sem_marinheiro'; end if;
  v_n := fazenda_mar_contar(v_id, 'marinheiro');
  if v_n <= 0 then raise exception 'cesto_mar_vazio'; end if;
  for v_k in 1..v_n loop
    v_p := fazenda_mar_sortear((v_b->>'valor')::int, (v_v->>'valor')::int + fazenda_melhoria(v_id, 'sonar')::int + fazenda_obra_tem(v_id, 'farol')::int);   -- fase 65: o sonar
    v_peixes := jsonb_set(v_peixes, array[v_p], to_jsonb(coalesce((v_peixes->>v_p)::int, 0) + 1));
    if random() < 1.0 / fazenda_mar_perola(v_id) then v_perolas := v_perolas + 1; end if;
  end loop;
  update fazenda_jogadores
     set marinheiro_em = greatest(coalesce(marinheiro_em, now()),
                                  now() - make_interval(secs => (v_m->>'max')::int * (v_m->>'intervalo')::int))
                         + make_interval(secs => v_n * (v_m->>'intervalo')::int)
   where id = v_id;
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  select v_id, e.key, e.value::int from jsonb_each_text(v_peixes) e
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  if v_perolas > 0 then
    insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, 'perola_negra', v_perolas)
    on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  end if;
  select coalesce(sum(k.xp * e.value::int), 0)::int into v_xp
    from jsonb_each_text(v_peixes) e join fazenda_culturas k on k.id = e.key;
  update fazenda_jogadores set xp = xp + v_xp where id = v_id;
  insert into fazenda_estatisticas (jogador_id) values (v_id) on conflict do nothing;
  update fazenda_estatisticas set peixes_mar = peixes_mar + v_n, marlins = marlins + coalesce((v_peixes->>'marlim')::int, 0)
   where jogador_id = v_id;
  perform fazenda_missao(v_id, 'colher', v_n);
  return jsonb_build_object('peixes', v_peixes, 'qtd', v_n, 'xp', v_xp, 'perolas', v_perolas, 'estado', fazenda_estado(v_id));
end;
$$;


-- Materializa os problemas (erva, praga, seca) que "aconteceram" enquanto a
-- planta crescia. Só ocorrem antes de a planta amadurecer.
create or replace function public.fazenda_tick(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  r        record;
  v_maduro timestamptz;
  v_evt    timestamptz;
  v_erva   boolean;
  v_praga  boolean;
  v_seco   boolean;
  v_tipo   int;
  i        int;
  v_ce     text;
  v_vigia  boolean;
begin
  v_vigia := fazenda_obra_tem(p_jogador, 'vigia');   -- fase 130: a cabana do vigia
  -- chovendo agora: a chuva rega tudo (some a seca dos canteiros)
  if fazenda_clima_agora() = 'chuva' then   -- (fase 71: uma conta por chamada)
    update fazenda_canteiros c set seco = false from fazenda_culturas k   -- (fase 121: só o que ainda cresce)
     where c.jogador_id = p_jogador and c.estado = 'plantado' and c.seco and k.id = c.cultura
       and now() < c.plantado_em + make_interval(secs => k.tempo_seg);
  end if;
  for r in
    select c.posicao, c.x, c.y, c.plantado_em, c.prox_evento, c.erva, c.praga, c.seco, k.tempo_seg
      from fazenda_canteiros c
      join fazenda_culturas k on k.id = c.cultura
     where c.jogador_id = p_jogador
       and c.estado = 'plantado'
       and c.prox_evento is not null
       and c.prox_evento <= now()
       for update of c
  loop
    v_maduro := r.plantado_em + make_interval(secs => r.tempo_seg);
    v_evt := r.prox_evento;
    v_erva := r.erva; v_praga := r.praga; v_seco := r.seco;
    i := 0;
    while v_evt <= now() and v_evt < v_maduro and i < 3 loop
      v_tipo := floor(random() * 3)::int;
      v_ce := fazenda_clima_em(v_evt);                                     -- o clima na hora do problema
      if v_ce = 'calor' and random() < 0.5 then v_tipo := 2; end if;       -- onda de calor: mais seca
      if v_ce = 'vento' and random() < 0.5 then v_tipo := 1; end if;       -- ventania espalha pragas
      if v_ce = 'chuva' and v_tipo = 2 then v_tipo := -1; end if;          -- com chuva não seca
      if v_ce = 'nublado' then v_tipo := -1; end if;                       -- nublado: nada de novo
      -- máquina por perto evita o problema (robô capinador, pulverizador, irrigador);
      -- o aspersor elétrico evita qualquer um, gastando 2 ⚡
      if v_tipo = 0 and not v_erva and not fazenda_protegido(p_jogador, 'erva', r.x, r.y) then
        if not fazenda_aspersor(p_jogador, r.x, r.y) then v_erva := true; end if;
      elsif v_tipo = 1 and not v_praga and not fazenda_protegido(p_jogador, 'praga', r.x, r.y)
            and not (r.y >= 45 and v_vigia and random() < 0.5) then   -- fase 130: o vigia espanta metade
        if not fazenda_aspersor(p_jogador, r.x, r.y) then v_praga := true; end if;
      elsif v_tipo = 2 and not v_seco and not fazenda_protegido(p_jogador, 'seco', r.x, r.y) then
        if not fazenda_aspersor(p_jogador, r.x, r.y) then v_seco := true; end if;
      end if;
      v_evt := v_evt + make_interval(secs => r.tempo_seg * (0.25 + random() * 0.35));
      i := i + 1;
    end loop;
    if v_evt >= v_maduro then
      v_evt := null;
    end if;
    update fazenda_canteiros
       set erva = v_erva, praga = v_praga, seco = v_seco, prox_evento = v_evt
     where jogador_id = p_jogador and posicao = r.posicao;
  end loop;
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
  if j.caca_dia is distinct from fazenda_hoje() or j.caca_passo < 3 then raise exception 'ilha_pistas'; end if;   -- fase 118
  v_moeda := round((60000 + (v_nivel - 45) * 8000) * (0.6 + random() * 0.8)
                   * case when j.cachorro_raca is not null then 1.5 else 1 end)::int;   -- fase 111: o cachorro fareja
  if random() < (case when j.cachorro_raca is not null then 1.0 / 3 else 0.25 end) then v_diam := 5 + floor(random() * 11)::int; end if;
  v_diam := v_diam + fazenda_obra_tem(v_id, 'ancora')::int;   -- fase 130: a âncora gigante
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
      'selos', fazenda_selos(j.id),   -- fase 127
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
      'ilha', jsonb_build_object('obras', coalesce(j.ilha_obras, 0), 'canhoes_hoje', coalesce(j.canhoes_dia = fazenda_hoje(), false), 'pode_ir', fazenda_ilha_pode(p_jogador, v_nivel),
                                 'bau_hoje', j.ilha_bau_dia = fazenda_hoje(), 'x', fazenda_ilha_x(p_jogador),
                                 -- fase 118: a caça ao tesouro (quantas pistas já achou hoje e onde está a próxima)
                                 'caca', fazenda_ilha_caca(p_jogador),
                                 -- fase 118: a caverna (abre com a 15ª obra): já explorou hoje? e a coleção dos tesouros
                                 'caverna', case when coalesce(j.ilha_obras, 0) >= 15 then jsonb_build_object(
                                     'hoje', coalesce(j.caverna_dia = fazenda_hoje(), false),
                                     -- fase 124: as explorações extras de hoje (com diamantes) e quanto custa
                                     'extras', case when j.caverna_extra_dia = fazenda_hoje() then j.caverna_extra else 0 end,
                                     'extras_max', 2, 'extra_preco', 10,
                                     'colecao', coalesce((select jsonb_object_agg(cv.item, cv.vezes) from fazenda_caverna cv where cv.jogador_id = p_jogador), '{}'::jsonb)) end,
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
                    and c.apagado_em is null and p.banido_em is null and (not p.teste or p.id = p_jogador)),   -- (fase 119)
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
    -- fase 117: quantos pedidos do Capitão ainda faltam hoje (3 se ele ainda não pediu; null fora da ilha)
    'capitao_faltam', case when fazenda_ilha_pode(p_jogador, v_nivel) then
        coalesce((select count(*) filter (where c.feito_em is null) from fazenda_capitao c where c.jogador_id = p_jogador and c.dia = fazenda_hoje()
                   having count(*) > 0), 3) end,
    -- fase 120: a conta de teste ligada a você (o botão no menu) e se esta é uma conta de teste
    'conta_teste', (select t.apelido from fazenda_jogadores t where t.teste_dono = p_jogador and t.teste order by t.criado_em limit 1),
    'sou_teste', (select j2.teste from fazenda_jogadores j2 where j2.id = p_jogador),
    'viih_restam', greatest(0, 11 - coalesce((select v.plantadas from fazenda_viih_plantio v where v.jogador_id = p_jogador
                                                and v.ano = extract(year from fazenda_hoje())::int), 0)),
    -- fase 114: os recados particulares ainda não lidos (só os seus: o estado é sempre o do próprio jogador)
    'recados', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'titulo', r.titulo, 'texto', r.texto, 'de', r.de,
                                                             'diamantes', r.diamantes, 'em', r.criado_em) order by r.id)
                           from fazenda_recados r where r.jogador_id = p_jogador and r.visto_em is null), '[]'::jsonb));
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
    v_murcho := v_maduro + make_interval(secs => fazenda_murcha_seg(k.tempo_seg, c.seco, c.y, c.jogador_id));
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
      v_murcho := now() + make_interval(secs => fazenda_murcha_seg(k.tempo_seg, c.seco, c.y, c.jogador_id));
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
             + (c.y >= 45 and j.cachorro_raca is not null)::int         -- fase 111: o cachorro da ilha
             + (c.y >= 45 and coalesce(j.ilha_obras, 0) >= fazenda_obra_n('sereia'))::int   -- fase 130: a estátua da sereia
             + fazenda_bonus_estacao(k.estacao_boa, k.rendimento);     -- fase 121: na estação dela, rende mais
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


-- cavar a pista p_n (a próxima): um pedaço do mapa, moedas (de 9,6 a 14,4 mil no 46; de 31 a 47 mil no 60) e,
-- 1 em 5, de 1 a 3 diamantes. Com a 3ª, o X aparece.
create or replace function public.fazenda_ilha_pista(p_token text, p_n int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  j       record;
  v_nivel int;
  v_passo int;
  v_moeda int;
  v_diam  int := 0;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  v_nivel := fazenda_nivel_de(j.xp, j.nivel_trava);
  if not fazenda_ilha_pode(v_id, v_nivel) then raise exception 'ilha_fechada'; end if;
  if coalesce(j.ilha_obras, 0) < 1 then raise exception 'ilha_sem_cais'; end if;
  if j.ilha_bau_dia = fazenda_hoje() then raise exception 'ilha_bau_hoje'; end if;
  v_passo := case when j.caca_dia = fazenda_hoje() then j.caca_passo else 0 end;
  if p_n is distinct from v_passo + 1 or p_n > 3 then raise exception 'pista_ordem'; end if;
  v_moeda := round((12000 + greatest(v_nivel - 45, 0) * 1500) * (0.8 + random() * 0.4))::int;
  if fazenda_obra_tem(v_id, 'cartografo') then v_moeda := v_moeda * 2; end if;   -- fase 130: a casa do cartógrafo
  if random() < 0.2 then v_diam := 1 + floor(random() * 3)::int; end if;
  update fazenda_jogadores set moedas = least(2147483647, moedas::bigint + v_moeda)::int, diamantes = diamantes + v_diam,
         moedas_ganhas = moedas_ganhas - v_moeda,   -- (como o baú, não conta no evento das moedas)
         caca_dia = fazenda_hoje(), caca_passo = p_n
   where id = v_id;
  return jsonb_build_object('n', p_n, 'moedas', v_moeda, 'diamantes', v_diam, 'estado', fazenda_estado(v_id));
end;
$$;


-- Fase 29: baú coletor (precisa de energia). Encostado num bloco de canteiros (os canteiros
-- encostados uns nos outros), colhe sozinho o que amadurece; encostado num cercado, coleta o
-- produto e alimenta os bichos daquela espécie. 2 ⚡ por colheita, coleta ou ração (fase 43; era 1).
create or replace function public.fazenda_baus(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  b       record;
  k       record;
  m       record;
  arv     record;
  e       record;
  v_qtd   int;
  v_livre int;
  v_peixes jsonb;
  v_seguro boolean;   -- fase 71
begin
  for b in select x, y from fazenda_construcoes where jogador_id = p_jogador and tipo = 'bau' loop
   -- fase 71: cada baú num lote só (modo rápido); deu erro, o lote volta e é refeito no modo seguro
   for v_tent in 1..2 loop
    v_seguro := v_tent = 2;
    begin
    v_livre := fazenda_bau_livre(p_jogador, b.x, b.y);
    -- canteiros: o bloco encostado no baú (canteiros encostados uns nos outros)
    for k in
      with recursive bloco(posicao, x, y) as (
        select c.posicao, c.x, c.y from fazenda_canteiros c
         where c.jogador_id = p_jogador and abs(c.x - b.x) + abs(c.y - b.y) = 1
        union
        select c.posicao, c.x, c.y from fazenda_canteiros c join bloco o on abs(c.x - o.x) + abs(c.y - o.y) = 1
         where c.jogador_id = p_jogador)
      select c.posicao, c.cultura, c.x, c.y from bloco o
        join fazenda_canteiros c on c.jogador_id = p_jogador and c.posicao = o.posicao
        join fazenda_culturas u on u.id = c.cultura
       where c.estado = 'plantado'
         and now() >= c.plantado_em + make_interval(secs => u.tempo_seg)
         and now() < c.plantado_em + make_interval(secs => u.tempo_seg + fazenda_murcha_seg(u.tempo_seg, c.seco, c.y, c.jogador_id))
    loop
      exit when v_livre <= 0 or not fazenda_gastar_energia(p_jogador, 2);
      if v_seguro then
        begin
          v_qtd := fazenda_aplicar(p_jogador, 'colher', k.posicao, null, true);   -- cai no celeiro...
          perform fazenda_bau_guardar(p_jogador, b.x, b.y, k.cultura, v_qtd, k.x, k.y);   -- ...e passa para o baú
          v_livre := v_livre - v_qtd;
        exception when others then null; end;
      else
        v_qtd := fazenda_aplicar(p_jogador, 'colher', k.posicao, null, true);
        perform fazenda_bau_guardar(p_jogador, b.x, b.y, k.cultura, v_qtd, k.x, k.y);
        v_livre := v_livre - v_qtd;
      end if;
    end loop;

    -- cercados encostados: coleta o produto (para o baú) e dá ração (do baú, se ele tiver; senão do celeiro)
    for m in
      select a.id, a.alimentado_em, t.tempo_seg, t.produto, t.racao, fazenda_racao_qtd(t.racao_qtd) as racao_qtd, p.x as px, p.y as py
        from fazenda_animais a
        join fazenda_animais_tipos t on t.id = a.tipo
        join fazenda_construcoes p on p.jogador_id = p_jogador and p.tipo = 'cercado_' || a.tipo
        join fazenda_itens i on i.id = p.tipo
       where a.jogador_id = p_jogador
         and (((b.x = p.x - 1 or b.x = p.x + i.largura) and b.y between p.y and p.y + i.altura - 1)
           or ((b.y = p.y - 1 or b.y = p.y + i.altura) and b.x between p.x and p.x + i.largura - 1))
    loop
      if v_seguro then
        begin
          if m.alimentado_em is not null and now() >= m.alimentado_em + make_interval(secs => m.tempo_seg)
             and v_livre > 0 and fazenda_gastar_energia(p_jogador, 2) then
            perform fazenda_animal_um(p_jogador, m.id, 'coletar', true);
            perform fazenda_bau_guardar(p_jogador, b.x, b.y, m.produto, 1, m.px, m.py);
            v_livre := v_livre - 1;
            m.alimentado_em := null;
          end if;
        exception when others then null;
        end;
        begin
          if m.alimentado_em is null and fazenda_energia_atualizar(p_jogador) >= fazenda_energia_preco(p_jogador, 2) then
            if coalesce((select quantidade from fazenda_bau_itens where jogador_id = p_jogador and x = b.x and y = b.y and item = m.racao), 0) >= m.racao_qtd then
              update fazenda_bau_itens set quantidade = quantidade - m.racao_qtd where jogador_id = p_jogador and x = b.x and y = b.y and item = m.racao;
              insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, m.racao, m.racao_qtd)   -- passa pelo celeiro
              on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
              perform fazenda_viagem(p_jogador, m.racao, m.racao_qtd, b.x, b.y, m.px, m.py, true, now());
              v_livre := v_livre + m.racao_qtd;
            end if;
            perform fazenda_animal_um(p_jogador, m.id, 'alimentar', true);   -- sem ração: pula (e desfaz o de cima)
            perform fazenda_gastar_energia(p_jogador, 2);
          end if;
        exception when others then null;
        end;
      else
        if m.alimentado_em is not null and now() >= m.alimentado_em + make_interval(secs => m.tempo_seg)
           and v_livre > 0 and fazenda_gastar_energia(p_jogador, 2) then
          perform fazenda_animal_um(p_jogador, m.id, 'coletar', true);
          perform fazenda_bau_guardar(p_jogador, b.x, b.y, m.produto, 1, m.px, m.py);
          v_livre := v_livre - 1;
          m.alimentado_em := null;
        end if;
        -- (no modo rápido, só tenta a ração que existe: no baú ou no celeiro)
        if coalesce((select quantidade from fazenda_bau_itens where jogador_id = p_jogador and x = b.x and y = b.y and item = m.racao), 0) >= m.racao_qtd
           or coalesce((select quantidade from fazenda_celeiro where jogador_id = p_jogador and item = m.racao), 0) >= m.racao_qtd then
          if m.alimentado_em is null and fazenda_energia_atualizar(p_jogador) >= fazenda_energia_preco(p_jogador, 2) then
            if coalesce((select quantidade from fazenda_bau_itens where jogador_id = p_jogador and x = b.x and y = b.y and item = m.racao), 0) >= m.racao_qtd then
              update fazenda_bau_itens set quantidade = quantidade - m.racao_qtd where jogador_id = p_jogador and x = b.x and y = b.y and item = m.racao;
              insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, m.racao, m.racao_qtd)   -- passa pelo celeiro
              on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
              perform fazenda_viagem(p_jogador, m.racao, m.racao_qtd, b.x, b.y, m.px, m.py, true, now());
              v_livre := v_livre + m.racao_qtd;
            end if;
            perform fazenda_animal_um(p_jogador, m.id, 'alimentar', true);   -- sem ração: pula (e desfaz o de cima)
            perform fazenda_gastar_energia(p_jogador, 2);
          end if;
        end if;
      end if;
    end loop;

    -- árvores do pomar (e a amoreira) encostadas: colhe as frutas prontas
    for arv in
      select c.x, c.y, c.tipo, i.produz, i.produz_qtd from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
       where c.jogador_id = p_jogador and i.produz is not null and i.entradas is null
         and abs(c.x - b.x) + abs(c.y - b.y) = 1
         and (c.colhido_em is null or now() >= c.colhido_em + make_interval(secs => i.produz_seg))
    loop
      exit when v_livre <= 0 or not fazenda_gastar_energia(p_jogador, 2);
      update fazenda_construcoes set colhido_em = fazenda_colhido_agora(p_jogador, arv.tipo) where jogador_id = p_jogador and x = arv.x and y = arv.y;
      insert into fazenda_bau_itens (jogador_id, x, y, item, quantidade) values (p_jogador, b.x, b.y, arv.produz, arv.produz_qtd)
      on conflict (jogador_id, x, y, item) do update set quantidade = fazenda_bau_itens.quantidade + excluded.quantidade;
      perform fazenda_viagem(p_jogador, arv.produz, arv.produz_qtd, arv.x, arv.y, b.x, b.y, true, now());
      v_livre := v_livre - arv.produz_qtd;
    end loop;

    -- encostado no lago (x 24..29, y 14..18): pega o cesto do Bira
    if ((b.x in (23, 30) and b.y between 14 and 18) or (b.y in (13, 19) and b.x between 24 and 29))
       and v_livre > 0 and fazenda_energia_atualizar(p_jogador) >= fazenda_energia_preco(p_jogador, 2) then
      v_peixes := fazenda_cesto(p_jogador, v_livre);
      if v_peixes <> '{}'::jsonb then
        perform fazenda_gastar_energia(p_jogador, 2);
        for e in select key as item, value::int as qtd from jsonb_each_text(v_peixes) loop
          insert into fazenda_bau_itens (jogador_id, x, y, item, quantidade) values (p_jogador, b.x, b.y, e.item, e.qtd)
          on conflict (jogador_id, x, y, item) do update set quantidade = fazenda_bau_itens.quantidade + excluded.quantidade;
          perform fazenda_viagem(p_jogador, e.item, e.qtd, least(greatest(b.x, 24), 29), least(greatest(b.y, 14), 18), b.x, b.y, true, now());
          v_livre := v_livre - e.qtd;
        end loop;
      end if;
    end if;
    exit;   -- deu certo: o próximo baú
    exception when others then
      if v_seguro then raise; end if;
    end;
   end loop;
  end loop;
  perform fazenda_bot_xp_gravar();   -- fase 72: o XP do que colheram, uma vez só
end;
$$;


-- As máquinas elétricas trabalham sozinhas (roda ao carregar a fazenda, como os ajudantes):
-- as oficinas andam (fábrica automática incluída); os robôs colhem e replantam.
create or replace function public.fazenda_industria(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  r     record;
  cc    record;
  m     record;
  v_sem text;
  v_seguro boolean;   -- fase 71
begin
  perform fazenda_energia_atualizar(p_jogador);
  delete from fazenda_viagens where jogador_id = p_jogador and criada_em < now() - interval '10 minutes';
  delete from fazenda_bau_itens where jogador_id = p_jogador and quantidade = 0;
  delete from fazenda_oficina_itens where jogador_id = p_jogador and quantidade = 0;
  perform fazenda_baus(p_jogador);   -- baús: colhem os canteiros e cuidam dos cercados encostados (antes das oficinas)
  perform fazenda_oficinas_andar(p_jogador);   -- oficinas: estoque, prontos e a fábrica automática

  select semente into v_sem from fazenda_jogadores where id = p_jogador;
  for r in
    select c.x, c.y, i.raio from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
     where c.jogador_id = p_jogador and i.efeito = 'robo'
  loop
   -- fase 71: cada robô num lote só (modo rápido); deu erro, volta e refaz no modo seguro
   for v_tent in 1..2 loop
    v_seguro := v_tent = 2;
    begin
    for cc in
      select x.posicao, x.estado, x.cultura,
             coalesce(x.estado = 'plantado'
               and now() >= x.plantado_em + make_interval(secs => k.tempo_seg)
               and now() < x.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, x.seco, x.y, x.jogador_id)), false) as maduro
        from fazenda_canteiros x left join fazenda_culturas k on k.id = x.cultura
       where x.jogador_id = p_jogador and abs(x.x - r.x) <= r.raio and abs(x.y - r.y) <= r.raio
       order by x.posicao
    loop
      if cc.maduro then
        if v_seguro then
          begin   -- colhe (e ara, se não tiver trator): 4 ⚡ (fase 43; era 3)
            if not fazenda_gastar_energia(p_jogador, 4) then exit; end if;
            perform fazenda_aplicar(p_jogador, 'colher', cc.posicao, null, true);
            if (select estado from fazenda_canteiros where jogador_id = p_jogador and posicao = cc.posicao) = 'vazio' then
              perform fazenda_aplicar(p_jogador, 'arar', cc.posicao, null, true);
            end if;
          exception when others then null;
          end;
          begin   -- replanta a mesma semente (paga com suas moedas): 2 ⚡
            if fazenda_gastar_energia(p_jogador, 2) then
              perform fazenda_aplicar(p_jogador, 'plantar', cc.posicao, cc.cultura, true);
            end if;
          exception when others then null;
          end;
        else
          if not fazenda_gastar_energia(p_jogador, 4) then exit; end if;
          perform fazenda_aplicar(p_jogador, 'colher', cc.posicao, null, true);
          if (select estado from fazenda_canteiros where jogador_id = p_jogador and posicao = cc.posicao) = 'vazio' then
            perform fazenda_aplicar(p_jogador, 'arar', cc.posicao, null, true);
          end if;
          -- (no modo rápido, só replanta o que dá: estação, estufa, nível e moedas)
          if fazenda_bot_pode_plantar(p_jogador, cc.cultura, cc.posicao) and fazenda_gastar_energia(p_jogador, 2) then
            perform fazenda_aplicar(p_jogador, 'plantar', cc.posicao, cc.cultura, true);
          end if;
        end if;
      elsif cc.estado = 'arado' and v_sem is not null then
        if v_seguro then
          begin   -- canteiro arado vazio: planta a última semente que você usou (2 ⚡)
            if fazenda_gastar_energia(p_jogador, 2) then
              perform fazenda_aplicar(p_jogador, 'plantar', cc.posicao, v_sem, true);
            end if;
          exception when others then null;
          end;
        elsif fazenda_bot_pode_plantar(p_jogador, v_sem, cc.posicao) and fazenda_gastar_energia(p_jogador, 2) then
          perform fazenda_aplicar(p_jogador, 'plantar', cc.posicao, v_sem, true);
        end if;
      end if;
    end loop;
    exit;   -- deu certo: o próximo robô
    exception when others then
      if v_seguro then raise; end if;
    end;
   end loop;
  end loop;
  perform fazenda_bot_xp_gravar();   -- fase 72: o XP do que colheram, uma vez só
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
  if now() < c.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, c.seco, c.y, c.jogador_id)) then
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
    v_murcha := c.estado = 'plantado' and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, c.seco, c.y, c.jogador_id));
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
  if now() >= c.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, c.seco, c.y, c.jogador_id)) then
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
       and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, c.seco, c.y, c.jogador_id));
    if v_cap = 0 then raise exception 'nada_a_fazer'; end if;
    v_preco := (v_loja->>'preco')::int * ceil(v_cap / coalesce((v_loja->>'por')::numeric, v_cap))::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    update fazenda_canteiros c
       set plantado_em = now() - make_interval(secs => k.tempo_seg), erva = false, praga = false, seco = false, prox_evento = null
      from fazenda_culturas k
     where c.jogador_id = v_id and c.estado = 'plantado' and k.id = c.cultura
       and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, c.seco, c.y, c.jogador_id));
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


-- Registra o que está murcho e ainda não tem motivo. Roda dentro de fazenda_trabalhar, depois do
-- colhedor e antes do lavrador (que ara as murchas).
create or replace function public.fazenda_murchas_registrar(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  h      record;
  v_tem  boolean;
begin
  select a.nivel, a.ultimo_descanso_de, a.ultimo_descanso_ate, a.ultimo_descanso_motivo into h
    from fazenda_ajudantes a join fazenda_ajudantes_tipos t on t.id = a.tipo
   where a.jogador_id = p_jogador and t.funcao = 'colher' limit 1;
  v_tem := found;
  insert into fazenda_murchas (jogador_id, posicao, plantado_em, cultura, murchou_em, motivo, detalhe)
  select p_jogador, c.posicao, c.plantado_em, c.cultura, m.em, x.motivo,
         case x.motivo
           when 'descansando' then jsonb_build_object('como', h.ultimo_descanso_motivo,
                                                      'horas', round(extract(epoch from h.ultimo_descanso_ate - h.ultimo_descanso_de) / 3600))
           when 'nao_deu_conta' then jsonb_build_object('nivel', h.nivel, 'ritmo', fazenda_ritmo(h.nivel))
         end
    from fazenda_canteiros c
    join fazenda_culturas k on k.id = c.cultura
    cross join lateral (select c.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, c.seco, c.y, c.jogador_id)) as em) m
    cross join lateral (select case
             when c.seco then 'seca'   -- fase 121: com seca, murcha na metade do tempo
             when not v_tem then 'sem_colhedor'
             when h.ultimo_descanso_de is not null and m.em >= h.ultimo_descanso_de and m.em < h.ultimo_descanso_ate then 'descansando'
             when m.em < now() - make_interval(hours => fazenda_turno(p_jogador)::int) then 'fechada'
             else 'nao_deu_conta' end as motivo) x
   where c.jogador_id = p_jogador and c.estado = 'plantado' and now() >= m.em and m.em > now() - interval '7 days'
  on conflict (jogador_id, posicao, plantado_em) do nothing;
  delete from fazenda_murchas where jogador_id = p_jogador and murchou_em < now() - interval '7 days';
end;
$$;


revoke execute on function public.fazenda_obra_n(text), public.fazenda_obra_tem(uuid, text),
  public.fazenda_murcha_seg(int, boolean, int, uuid) from public, anon, authenticated;
grant execute on function public.fazenda_ilha_canhoes(text) to anon, authenticated;

-- conferência: tem que aparecer "fase 130 ok"
select case when public.fazenda_obra_n('canhoes') = 12
             and (public.fazenda_ilha_obras()->1->>'efeito') is not null
             and (select prosrc from pg_proc where proname = 'fazenda_trabalhar') like '%taverna%'
            then 'fase 130 ok' else 'não aplicou' end as resultado;
