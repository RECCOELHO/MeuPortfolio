-- ============================================================
-- FAZENDINHA — Fase 78 (terrenos à direita, mais energia antes do 29, mais dinheiro do 29 para baixo e a conquista do milhão),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 77): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 77 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_tempestade')) then
    raise exception 'Rode o fase77.sql antes deste (a fase 77 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 78: terrenos à direita, mais energia antes do 29, mais dinheiro do 29 para baixo e a conquista do
-- milhão.
-- • Terrenos 8, 9 e 10 na faixa x 48..63 (níveis 29, 33 e 38; 250 mil, 500 mil e 1 milhão), comprados à
--   parte dos de 1 a 7 (fazenda_jogadores.direita, de 0 a 3). As funções de terreno recebem
--   fazenda_terrenos(zonas, direita) = zonas + 10 x direita; o litoral vai até x 63.
-- • Energia: painel e turbina +1 por nível do 17 ao 29; gerador a biomassa 2 → 6 até o 28; a pequena
--   central hidrelétrica (nível 20, 120 ⚡/h sem parar, 80 no calor; 1, 2 e 3 nos níveis 20, 23 e 27).
-- • Venda: +50% do nível 29 para baixo (fazenda_bonus_venda), caindo 10 por nível do 30 ao 34.
-- • Feira: 50 compras por dia (eram 40).
-- • Conquista "Compra milionária": pagar 1 milhão de moedas de uma vez (um gatilho guarda a maior
--   queda das moedas numa mudança só, em fazenda_estatisticas.maior_compra).
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists direita smallint not null default 0;
alter table public.fazenda_jogadores drop constraint if exists fazenda_jogadores_direita_check;
alter table public.fazenda_jogadores add constraint fazenda_jogadores_direita_check check (direita between 0 and 3);

insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, efeito, raio, limite, descricao) values
  ('hidreletrica', 'Pequena central hidrelétrica', 'energia', 30000, 20, 84, 'hidro', 0, 1,
   'Uma rodinha d''água num riacho: 120 ⚡/h sem parar, de dia e de noite (80 na onda de calor, com o rio baixo). Tempestade e furacão não estragam. Até 1, mais 1 no nível 23 e no 27.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min, ordem = excluded.ordem,
  efeito = excluded.efeito, raio = excluded.raio, limite = excluded.limite, descricao = excluded.descricao;
update public.fazenda_itens set descricao = 'Gera até 12 ⚡/h de dia (sol forte: 14; nublado: 5; chuva: 3). À noite, nada: no jogo, o dia e a noite se revezam a cada 2 horas. Até 8, mais 1 por nível do 17 ao 29 e 1 a cada 2 níveis depois.' where id = 'painel_solar';
update public.fazenda_itens set descricao = 'Gera 8 ⚡/h de dia e de noite; 30 ⚡/h na ventania e 14 na chuva. Na calmaria (sem vento, uns 25% do tempo fora da ventania e da chuva), cai para 3 ⚡/h: o painel de energia avisa quando vem. Até 6, mais 1 por nível do 18 ao 29 e 1 a cada 2 níveis depois.' where id = 'turbina';
update public.fazenda_itens set descricao = 'Ligado, queima 1 milho a cada 30 min: 50 ⚡/h. Toque nele para ligar ou desligar. Até 2, 3 no nível 21, 4 no 24 e 6 no 28.' where id = 'gerador_bio';

-- a conquista do milhão: a maior queda das moedas numa mudança só
alter table public.fazenda_estatisticas add column if not exists maior_compra bigint not null default 0;
create or replace function public.fazenda_moedas_pagou()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.moedas < old.moedas - 999999 then
    insert into fazenda_estatisticas (jogador_id, maior_compra) values (new.id, old.moedas - new.moedas)
    on conflict (jogador_id) do update set maior_compra = greatest(fazenda_estatisticas.maior_compra, excluded.maior_compra);
  end if;
  return new;
end;
$$;
drop trigger if exists fazenda_moedas_pagou on public.fazenda_jogadores;
create trigger fazenda_moedas_pagou after update of moedas on public.fazenda_jogadores
  for each row when (new.moedas < old.moedas - 999999) execute function public.fazenda_moedas_pagou();
insert into public.fazenda_conquistas_tipos (id, nome, descricao, medida, meta, recompensa, ordem) values
  ('milhao', 'Compra milionária', 'Pague 1 milhão de moedas numa compra só', 'maior_compra', 1000000, 50000, 60)
on conflict (id) do update set nome = excluded.nome, descricao = excluded.descricao, medida = excluded.medida,
  meta = excluded.meta, recompensa = excluded.recompensa;
update public.fazenda_conquistas_tipos set diamantes = 20 where id = 'milhao';

-- as funções que já existiam e mudaram

-- Bônus nas vendas, em %: beleza (+1% a cada 10, até 20) + caixote (+10)
-- fase 78: do nível 29 para baixo, +50% nas vendas (do 30 ao 34 vai caindo 10 por nível, sem tombo)
create or replace function public.fazenda_bonus_venda(p_jogador uuid)
returns int language plpgsql stable security definer set search_path = public as $$
begin   -- (plpgsql: fazenda_nivel vem mais para baixo no arquivo)
  return least(fazenda_beleza(p_jogador) / 10, 20) + 10 * fazenda_tem_efeito(p_jogador, 'venda')::int
       + greatest(0, least(50, 50 - 10 * ((select fazenda_nivel(xp) from fazenda_jogadores where id = p_jogador) - 29)));
end;
$$;

-- Terrenos à venda: áreas de mata em volta da fazenda (22 x 13), compradas em ordem.
-- Precisa bater com ZONAS em assets/fazenda/fazenda-arte.js. canteiros = quanto o limite sobe.
-- Fase 24: mais 3 terrenos grandes (leste, sul e sudeste): o mapa vai até 48 x 32.
create or replace function public.fazenda_zonas()
returns jsonb language sql immutable as $$
  select '[{"n":1,"nome":"Campo do sul","x":0,"y":13,"w":22,"h":7,"custo":500,"nivel":4,"canteiros":6},
           {"n":2,"nome":"Mata do leste","x":22,"y":0,"w":10,"h":13,"custo":1500,"nivel":7,"canteiros":6},
           {"n":3,"nome":"Vale do sudeste","x":22,"y":13,"w":10,"h":7,"custo":3500,"nivel":10,"lago":true,"canteiros":6},
           {"n":4,"nome":"Chapada do leste","x":32,"y":0,"w":16,"h":20,"custo":8000,"nivel":13,"canteiros":10},
           {"n":5,"nome":"Várzea do sul","x":0,"y":20,"w":32,"h":12,"custo":18000,"nivel":16,"canteiros":12},
           {"n":6,"nome":"Sertão do sudeste","x":32,"y":20,"w":16,"h":12,"custo":87500,"nivel":20,"canteiros":10},
           {"n":7,"nome":"Litoral","x":0,"y":32,"w":64,"h":10,"custo":750000,"nivel":31,"canteiros":10,"mar":true},
           {"n":8,"nome":"Serra do leste","x":48,"y":0,"w":16,"h":11,"custo":250000,"nivel":29,"canteiros":10,"lado":"direita"},
           {"n":9,"nome":"Planalto do leste","x":48,"y":11,"w":16,"h":11,"custo":500000,"nivel":33,"canteiros":10,"lado":"direita"},
           {"n":10,"nome":"Cerrado do leste","x":48,"y":22,"w":16,"h":10,"custo":1000000,"nivel":38,"canteiros":10,"lado":"direita"}]'::jsonb;
   -- fase 61 (fase 72: do 20 em diante, 2,5x). Fase 78: os 3 da direita (8 a 10), comprados à parte,
   -- e o litoral vai até a ponta da direita (x 63)
$$;

-- fase 78: os terrenos de um jogador num número só: zonas (de 1 a 7, em ordem) + 10 x direita (de 8 a 10,
-- em ordem entre eles). É o que as funções de terreno recebem em p_zonas.
create or replace function public.fazenda_terrenos(p_zonas int, p_direita int)
returns int language sql immutable as $$
  select coalesce(p_zonas, 0) + 10 * coalesce(p_direita, 0);
$$;

create or replace function public.fazenda_zona_minha(p_n int, p_terrenos int)
returns boolean language sql immutable as $$
  select case when p_n <= 7 then p_n <= p_terrenos % 10 else p_n - 7 <= p_terrenos / 10 end;
$$;

-- (x, y) fica dentro do terreno de quem já comprou p_zonas terrenos?
create or replace function public.fazenda_no_terreno(p_zonas int, p_x int, p_y int)
returns boolean language sql immutable as $$
  select (p_x between 0 and 21 and p_y between 0 and 12)
      or exists (select 1 from jsonb_array_elements(fazenda_zonas()) z
                  where fazenda_zona_minha((z->>'n')::int, p_zonas)   -- (fase 78: p_zonas = fazenda_terrenos)
                    and p_x >= (z->>'x')::int and p_x < (z->>'x')::int + (z->>'w')::int
                    and p_y >= (z->>'y')::int and p_y < (z->>'y')::int + (z->>'h')::int);
$$;

-- Quantos canteiros o jogador pode ter: +2 por nível até o 25 e o que cada terreno comprado dá
-- (6 nos três primeiros, 10 a 12 nos grandes; igual a limiteCanteirosNivel em fazenda.js)
-- Fase 40: quantas construções cabem na fazenda (cerca, caminho, cano, enfeite, máquina...):
-- 250 e mais 150 a cada terreno comprado (antes era 200 fixo, pouco para o mapa grande e os canos).
-- Igual a maxConstrucoes em fazenda.js.
create or replace function public.fazenda_max_construcoes(p_zonas int)
returns int language sql immutable as $$
  select 250 + 150 * greatest(coalesce(p_zonas, 0) % 10 + coalesce(p_zonas, 0) / 10, 0);   -- (fase 78: os da direita também)
$$;

-- fase 69: +2 por nível até o último (era até o 25: o limite parava em 54)
create or replace function public.fazenda_limite_canteiros(p_nivel int, p_zonas int)
returns int language sql immutable as $$
  select least(6 + (p_nivel - 1) * 2, 94)
       + coalesce((select sum(coalesce((z->>'canteiros')::int, 6))::int from jsonb_array_elements(fazenda_zonas()) z
                    where fazenda_zona_minha((z->>'n')::int, p_zonas)), 0);
$$;

-- Fase 49: as metas de cada nível = tudo o que ele libera: construir cada oficina, máquina, coisa de
-- energia, cercado e árvore do pomar (e o baú); ter cada bicho; contratar cada ajudante; comprar cada
-- terreno; e ocupar todos os canteiros do nível. Vêm as do nível de agora e as que ficaram para trás.
create or replace function public.fazenda_metas(p_jogador uuid, p_nivel int)
returns jsonb language sql stable security definer set search_path = public as $$
  with j as (select fazenda_terrenos(zonas, direita) as ter from fazenda_jogadores where id = p_jogador),
       mx as (select fazenda_limite_canteiros(p_nivel, (select ter from j)) as max,
                     (select count(*) from fazenda_canteiros where jogador_id = p_jogador)::int as tem)
  select coalesce(jsonb_agg(m order by (m->>'nivel')::int, m->>'tipo', m->>'id'), '[]'::jsonb) from (
    select jsonb_build_object('tipo', 'construir', 'id', i.id, 'nivel', i.nivel_min,
             'feito', exists (select 1 from fazenda_construcoes c where c.jogador_id = p_jogador and c.tipo = i.id)) as m
      from fazenda_itens i
     where i.nivel_min <= p_nivel and (i.categoria in ('oficina', 'maquina', 'energia', 'bichos', 'pomar') or i.id = 'bau')
    union all
    select jsonb_build_object('tipo', 'bicho', 'id', t.id, 'nivel', t.nivel_min,
             'feito', exists (select 1 from fazenda_animais a where a.jogador_id = p_jogador and a.tipo = t.id))
      from fazenda_animais_tipos t where t.nivel_min <= p_nivel
    union all
    select jsonb_build_object('tipo', 'ajudante', 'id', h.id, 'nivel', h.nivel_min,
             'feito', exists (select 1 from fazenda_ajudantes a where a.jogador_id = p_jogador and a.tipo = h.id))
      from fazenda_ajudantes_tipos h where h.nivel_min <= p_nivel
    union all
    select jsonb_build_object('tipo', 'terreno', 'id', z->>'n', 'nivel', (z->>'nivel')::int,
             'feito', fazenda_zona_minha((z->>'n')::int, (select ter from j)))
      from jsonb_array_elements(fazenda_zonas()) z where (z->>'nivel')::int <= p_nivel
    union all
    select jsonb_build_object('tipo', 'canteiros', 'id', 'canteiros', 'nivel', p_nivel,
             'feito', mx.tem >= mx.max, 'tem', mx.tem, 'max', mx.max)
      from mx
  ) x;
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
  v_max := fazenda_limite_canteiros(v_nivel, fazenda_terrenos(j.zonas, j.direita));
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
      'max_construcoes', fazenda_max_construcoes(fazenda_terrenos(j.zonas, j.direita)),
      'zonas', j.zonas,
      'direita', j.direita,   -- fase 78: os terrenos da direita
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
    'culturas', fazenda_cache_ler('culturas'),   -- fase 71: os catálogos vêm prontos (fazenda_cache)
    'animais', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'alimentado_em', alimentado_em,
               'radioativo_ate', case when radioativo_ate > now() then radioativo_ate end) order by id)   -- fase 68
        from fazenda_animais where jogador_id = p_jogador), '[]'::jsonb),
    'animais_tipos', fazenda_cache_ler('animais_tipos'),
    'construcoes', coalesce((
      select jsonb_agg(jsonb_build_object('x', x, 'y', y, 'tipo', tipo, 'colhido_em', colhido_em, 'iniciado_em', iniciado_em,
                                          'estoque', estoque, 'prontos', prontos, 'pago', pago,   -- fase 72: pago
                                          'sobrecarga_em', sobrecarga_em))   -- fase 77: parado até o conserto
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
  update fazenda_clima_eventos set visto = true where jogador_id = p_jogador and not visto;   -- e o raio e o furacão (fase 77)
  return v_json;
end;
$$;

-- Fazenda de um vizinho vista por quem está visitando
create or replace function public.fazenda_vizinho(p_dono uuid, p_ator uuid)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  j       record;
  v_nivel int;
begin
  select * into j from fazenda_jogadores where id = p_dono;
  v_nivel := fazenda_nivel(j.xp);
  return jsonb_build_object(
    'agora', now(),
    'id', j.id,
    'apelido', j.apelido,
    'avatar', j.avatar,
    'nivel', v_nivel,
    'max_canteiros', fazenda_max_canteiros(v_nivel),
    'zonas', j.zonas,
    'direita', j.direita,   -- fase 78
    -- fase 48: hoje o visitante ainda pode salvar até 2 plantas murchas e dar ração a até 10 bichos aqui
    'salvos_hoje', (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'salvar'
                     and criado_em > now() - interval '1 day'),
    'pode_salvar', (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'salvar'
                     and criado_em > now() - interval '1 day') < 2,
    'bichos_hoje', (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'bicho'
                     and criado_em > now() - interval '1 day'),
    'premio_ajuda', fazenda_premio_ajuda(p_ator),
    'canteiros', coalesce((
      select jsonb_agg(jsonb_build_object(
               'posicao', c.posicao, 'x', c.x, 'y', c.y, 'estado', c.estado, 'cultura', c.cultura,
               'plantado_em', c.plantado_em, 'erva', c.erva, 'praga', c.praga, 'seco', c.seco,
               'roubado', c.roubado,
               'ja_peguei', exists (
                 select 1 from fazenda_visitas v
                  where v.tipo = 'roubo' and v.ator_id = p_ator and v.dono_id = p_dono
                    and v.posicao = c.posicao and v.plantado_em = c.plantado_em))
             order by c.posicao)
        from fazenda_canteiros c where c.jogador_id = p_dono), '[]'::jsonb),
    'animais', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'alimentado_em', alimentado_em,
               'radioativo_ate', case when radioativo_ate > now() then radioativo_ate end) order by id)   -- fase 68
        from fazenda_animais where jogador_id = p_dono), '[]'::jsonb),
    'construcoes', coalesce((
      select jsonb_agg(jsonb_build_object('x', x, 'y', y, 'tipo', tipo))
        from fazenda_construcoes where jogador_id = p_dono), '[]'::jsonb),
    'perfil', jsonb_build_object(
      'criado_em', j.criado_em,
      'estatisticas', (select to_jsonb(e) - 'jogador_id' || jsonb_build_object('energia', e.energia + floor(g.energia_gasta)::int)
                         from fazenda_estatisticas e join fazenda_jogadores g on g.id = e.jogador_id where e.jogador_id = p_dono),
      'conquistas', coalesce((select jsonb_agg(conquista order by obtida_em)
                                from fazenda_conquistas where jogador_id = p_dono), '[]'::jsonb),
      'trofeus', fazenda_trofeus(p_dono))   -- fase 63: os troféus do evento da semana
  );
end;
$$;

-- p_categoria: animal (as construções têm funções próprias, logo abaixo)
create or replace function public.fazenda_comprar(p_token text, p_categoria text, p_tipo text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  j       record;
  a       record;
  v_n     int;
  v_preco int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;

  if p_categoria = 'animal' then
    select * into a from fazenda_animais_tipos where id = p_tipo;
    if not found then raise exception 'item_invalido'; end if;
    if fazenda_nivel(j.xp) < a.nivel_min then raise exception 'nivel_insuficiente'; end if;
    -- fase 45: o bicho precisa da casa dele antes (Construir → Bichos)
    if not exists (select 1 from fazenda_construcoes where jogador_id = v_id and tipo = 'cercado_' || a.id) then
      raise exception 'sem_cercado';
    end if;
    select count(*) into v_n from fazenda_animais where jogador_id = v_id and tipo = a.id;
    if v_n >= a.maximo then
      raise exception 'limite_animais';
    end if;
    -- cada bicho da mesma espécie sai 50% mais caro que o anterior (igual a precoAnimal em fazenda.js)
    v_preco := round(a.custo * power(1.5::numeric, v_n))::int;
    if j.moedas < v_preco then raise exception 'moedas_insuficientes'; end if;
    update fazenda_jogadores set moedas = moedas - v_preco where id = v_id;
    insert into fazenda_animais (jogador_id, tipo) values (v_id, a.id);

  elsif p_categoria = 'terreno' then
    -- de 1 a 7, sempre o próximo da fila; fase 78: p_tipo 8 a 10 = o próximo da direita (à parte,
    -- do nível 29). Sem p_tipo (jogo antigo), o próximo da fila.
    if coalesce(nullif(p_tipo, ''), '0')::int >= 8 then
      if j.direita >= 3 then raise exception 'terreno_max'; end if;
      if p_tipo::int <> 8 + j.direita then raise exception 'terreno_fora_de_ordem'; end if;
    elsif j.zonas >= 7 then raise exception 'terreno_max';
    end if;
    select (z->>'n')::int as n, (z->>'custo')::int as custo, (z->>'nivel')::int as nivel into a
      from jsonb_array_elements(fazenda_zonas()) z
     where (z->>'n')::int = case when coalesce(nullif(p_tipo, ''), '0')::int >= 8 then 8 + j.direita else j.zonas + 1 end;
    if fazenda_nivel(j.xp) < a.nivel then raise exception 'nivel_insuficiente'; end if;
    if j.moedas < a.custo then raise exception 'moedas_insuficientes'; end if;
    if a.n >= 8 then update fazenda_jogadores set moedas = moedas - a.custo, direita = direita + 1 where id = v_id;
    else update fazenda_jogadores set moedas = moedas - a.custo, zonas = zonas + 1 where id = v_id; end if;

  elsif p_categoria = 'melhoria' then
    -- fase 57: o próximo nível da melhoria (p_tipo = adubo, pomar ou pes)
    -- fase 62: e as do alto-mar (barco, vara e marinheiro), que pedem o píer pronto
    select (n->>'nivel')::int as nivel, (n->>'custo')::int as custo, coalesce((m->>'mar')::boolean, false) as mar,
           n->'itens' as itens into a
      from jsonb_array_elements(fazenda_melhorias_tipos()) m,
           jsonb_array_elements(m->'niveis') with ordinality as x(n, i)
     where m->>'id' = p_tipo
       and x.i = 1 + coalesce((select nivel from fazenda_melhorias where jogador_id = v_id and id = p_tipo), 0);
    if not found then raise exception 'melhoria_max'; end if;
    if a.mar and j.pier_em is null then raise exception 'sem_pier'; end if;
    if fazenda_nivel(j.xp) < a.nivel then raise exception 'nivel_insuficiente'; end if;
    -- fase 65: a rede é do marinheiro; o kit de expedição pede o barco oceânico
    if p_tipo = 'rede' and fazenda_mar_item(v_id, 'marinheiro') is null then raise exception 'sem_marinheiro'; end if;
    if p_tipo = 'expedicao' and coalesce((select nivel from fazenda_melhorias where jogador_id = v_id and id = 'barco'), 0) < 4 then
      raise exception 'barco_pequeno';
    end if;
    if j.moedas < a.custo then raise exception 'moedas_insuficientes'; end if;
    -- fase 65: as peças pedem materiais raros do celeiro (o que está guardado para o píer fica)
    if exists (select 1 from jsonb_each_text(coalesce(a.itens, '{}'::jsonb)) e
                where coalesce((select quantidade from fazenda_celeiro where jogador_id = v_id and item = e.key), 0)
                    - coalesce((select quantidade from fazenda_reservas where jogador_id = v_id and item = e.key), 0) < e.value::int) then
      raise exception 'faltam_materiais';
    end if;
    -- barco ou marinheiro novo (e o motor e a rede) mudam o ritmo: o que já está no cardume (ou no cesto) fica lá
    v_n := case when p_tipo in ('barco', 'motor') then fazenda_mar_contar(v_id, 'barco')
                when p_tipo in ('marinheiro', 'rede') then fazenda_mar_contar(v_id, 'marinheiro') end;
    update fazenda_jogadores set moedas = moedas - a.custo where id = v_id;
    update fazenda_celeiro c set quantidade = c.quantidade - e.value::int
      from jsonb_each_text(coalesce(a.itens, '{}'::jsonb)) e
     where c.jogador_id = v_id and c.item = e.key;
    insert into fazenda_melhorias (jogador_id, id, nivel) values (v_id, p_tipo, 1)
    on conflict (jogador_id, id) do update set nivel = fazenda_melhorias.nivel + 1;
    if p_tipo in ('barco', 'motor') then
      update fazenda_jogadores set mar_em = now() - make_interval(secs => v_n * (fazenda_mar_item(v_id, 'barco')->>'intervalo')::int)
       where id = v_id;
    elsif p_tipo in ('marinheiro', 'rede') then
      update fazenda_jogadores set marinheiro_em = now() - make_interval(secs => v_n * (fazenda_mar_item(v_id, 'marinheiro')->>'intervalo')::int)
       where id = v_id;
    end if;

  else
    raise exception 'item_invalido';
  end if;

  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

create or replace function public.fazenda_livre(p_x int, p_y int)
returns boolean language sql immutable as $$
  select p_x between 0 and 63 and p_y between 0 and 36            -- fase 61: o litoral vai até a areia (y 36); fase 78: até x 63
     and not (p_x between 1 and 3  and p_y between 1 and 6)     -- celeiro
     and not (p_x between 5 and 7  and p_y between 1 and 3)     -- casa
     and not (p_x between 24 and 29 and p_y between 14 and 18)  -- lago
     and not (p_x between 22 and 24 and p_y between 35 and 36); -- fase 61: o lugar do píer (o resto dele é no mar, y 37 a 41)
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
       >= fazenda_limite_canteiros(fazenda_nivel(j.xp), fazenda_terrenos(j.zonas, j.direita)) then
      raise exception 'limite_canteiros';
    end if;
    perform fazenda_checar_lugar(v_id, fazenda_terrenos(j.zonas, j.direita), p_x, p_y, 1, 1);
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
  perform fazenda_checar_lugar(v_id, fazenda_terrenos(j.zonas, j.direita), p_x, p_y, i.largura, i.altura);
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
                  then i.por_terreno * (1 + (j.zonas + j.direita) / 2) + fazenda_melhoria(v_id, 'pes')::int   -- (fase 78: + os da direita)
                  else i.por_terreno * (1 + j.zonas + j.direita) end) then
    raise exception 'limite_terreno';
  end if;
  if (select count(*) from fazenda_construcoes where jogador_id = v_id) >= fazenda_max_construcoes(fazenda_terrenos(j.zonas, j.direita)) then
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
-- fase 73b: p_leve devolve só {ok, x, y} (o jogo já mostra o item no lugar; a fazenda inteira a cada
-- movimento travava quem movia várias coisas seguidas). Sem ele, como antes (o jogo antigo no cache).
create or replace function public.fazenda_mover(p_token text, p_x int, p_y int, p_nx int, p_ny int, p_leve boolean default false)
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
    perform fazenda_checar_lugar(v_id, fazenda_terrenos(j.zonas, j.direita), p_nx, p_ny, 1, 1, null, null, v_pos);
    update fazenda_canteiros set x = p_nx, y = p_ny where jogador_id = v_id and posicao = v_pos;
    if p_leve then return jsonb_build_object('ok', true, 'x', p_nx, 'y', p_ny); end if;
    return jsonb_build_object('estado', fazenda_estado(v_id));
  end if;

  select k.* into i from fazenda_construcoes c join fazenda_itens k on k.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y;
  if not found then raise exception 'item_invalido'; end if;
  perform fazenda_checar_lugar(v_id, fazenda_terrenos(j.zonas, j.direita), p_nx, p_ny, i.largura, i.altura, p_x, p_y);
  if i.categoria = 'praia' and not (p_ny >= 32 and p_ny + i.altura - 1 <= 36) then raise exception 'so_na_areia'; end if;   -- fase 73
  update fazenda_construcoes set x = p_nx, y = p_ny
   where jogador_id = v_id and x = p_x and y = p_y;
  if not found then raise exception 'item_invalido'; end if;
  -- o que está guardado no baú e o que já chegou pelo cano na oficina vão junto (fase 39)
  update fazenda_bau_itens set x = p_nx, y = p_ny where jogador_id = v_id and x = p_x and y = p_y;
  update fazenda_oficina_itens set x = p_nx, y = p_ny where jogador_id = v_id and x = p_x and y = p_y;
  if p_leve then return jsonb_build_object('ok', true, 'x', p_nx, 'y', p_ny); end if;
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- o limite de cada máquina no nível (null = sem limite)
create or replace function public.fazenda_limite_maquina(p_item text, p_limite int, p_nivel int)
returns int language sql immutable as $$
  select case p_item
           -- fase 78: do 17 ao 29, +1 por nível (era +1 a cada 2); do 30 em diante, +1 a cada 2
           when 'painel_solar' then p_limite + greatest(0, least(p_nivel, 29) - 16) + greatest(0, (p_nivel - 29) / 2)
           when 'turbina'      then p_limite + greatest(0, least(p_nivel, 29) - 17) + greatest(0, (p_nivel - 29) / 2)
           when 'gerador_bio'  then p_limite + (p_nivel >= 21)::int + (p_nivel >= 24)::int + 2 * (p_nivel >= 28)::int   -- fase 78: 2, 3, 4 e 6
           when 'hidreletrica' then p_limite + (p_nivel >= 23)::int + (p_nivel >= 27)::int                                -- fase 78: 1, 2 e 3
           when 'reator'       then p_limite + (p_nivel >= 40)::int   -- fase 75: o 2º reator no nível 40
           else p_limite end;
$$;

-- fase 78: a pequena central hidrelétrica, ⚡ por hora (o rio baixa na onda de calor)
create or replace function public.fazenda_hidro_em(p_t timestamptz)
returns real language sql stable as $$
  select case fazenda_clima_em(p_t) when 'calor' then 80 else 120 end::real;
$$;

create or replace function public.fazenda_energia_taxa(p_jogador uuid, p_t timestamptz)
returns real language sql stable security definer set search_path = public as $$
  select coalesce(sum(case i.efeito when 'solar' then g.solar when 'eolica' then g.eolica when 'reator' then g.reator when 'hidro' then fazenda_hidro_em(p_t) else 0 end), 0)::real
         -- fase 47: cada alarme gasta 1 ⚡ por hora (a conta só roda para quem tem energia elétrica)
         - (select count(*) from fazenda_construcoes a where a.jogador_id = p_jogador and a.tipo = 'alarme')::real
    from fazenda_construcoes c
    join fazenda_itens i on i.id = c.tipo
    cross join fazenda_gera_em(p_t) g
   where c.jogador_id = p_jogador and i.efeito in ('solar', 'eolica', 'reator', 'hidro')
     and c.sobrecarga_em is null;   -- fase 77: em sobrecarga, parado até o conserto
$$;

-- quanto cada gerador dá em média por hora: uma semana de clima, de 12 em 12 min (a mesma conta de
-- fazenda_energia_taxa), guardada em fazenda_cache (o fim de cada faseN.sql refaz)
create or replace function public.fazenda_energia_medias()
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v jsonb := (select valor from fazenda_cache where chave = 'energia_medias');
begin
  if v is not null then return v; end if;
  select jsonb_build_object(   -- (fase 77: a mesma conta da taxa, com a tempestade e o furacão)
           'solar', round(avg(g.solar)::numeric, 1), 'eolica', round(avg(g.eolica)::numeric, 1),
           'reator', round(avg(g.reator)::numeric, 1), 'hidro', round(avg(fazenda_hidro_em(t))::numeric, 1), 'biomassa', 50)
    into v
    from generate_series(date_trunc('hour', now()), date_trunc('hour', now()) + interval '7 days', interval '12 minutes') t
   cross join lateral fazenda_gera_em(t) g;
  perform fazenda_cache_gravar('energia_medias', v);
  return v;
end;
$$;

-- a conta da energia de uma fazenda: gera (média por hora) e gasta (no máximo por hora, tudo
-- trabalhando), por tipo. Guardada por jogador enquanto as construções e o eletricista não mudam.
create or replace function public.fazenda_energia_conta(p_jogador uuid)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_ass  text;
  v      jsonb;
  m      jsonb;
  v_tri  boolean;
  v_fab  boolean;
  v_desc real;
  v_rede jsonb;
  v_gera jsonb;
  v_gasta jsonb;
  v_g    real;
  v_c    real;
begin
  select md5(coalesce(string_agg(c.tipo || c.x || ',' || c.y, ';' order by c.x, c.y), '') || ':' ||
             coalesce((select h.nivel from fazenda_ajudantes h join fazenda_ajudantes_tipos t on t.id = h.tipo
                        where h.jogador_id = p_jogador and t.funcao = 'energia' limit 1), 0))
    into v_ass from fazenda_construcoes c where c.jogador_id = p_jogador;
  select valor into v from fazenda_cache where chave = 'energia:' || p_jogador;
  if v is not null and v->>'ass' = v_ass then return v - 'ass'; end if;

  m := fazenda_energia_medias();
  v_tri := fazenda_tem_efeito(p_jogador, 'triturar');
  v_fab := fazenda_tem_efeito(p_jogador, 'automatico');
  v_desc := fazenda_energia_preco(p_jogador, 1);   -- quanto 1 ⚡ custa de verdade (0,8 e o eletricista)
  v_rede := coalesce((select jsonb_agg(to_jsonb(r)) from fazenda_rede(p_jogador) r), '[]'::jsonb);

  -- gera: cada gerador pela média dele
  select coalesce(jsonb_agg(jsonb_build_object('tipo', x.tipo, 'n', x.n, 'h', round(x.h::numeric))), '[]'::jsonb), coalesce(sum(x.h), 0)
    into v_gera, v_g
    from (select c.tipo, count(*) as n, count(*) * (m->>i.efeito)::real as h
            from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
           where c.jogador_id = p_jogador and i.efeito in ('solar', 'eolica', 'reator', 'biomassa', 'hidro')
           group by c.tipo, i.efeito) x;

  -- gasta: cada coisa trabalhando sem parar
  with cons as (
    select c.x, c.y, c.tipo, i.efeito, i.raio, i.produz_seg, i.entradas
      from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo where c.jogador_id = p_jogador),
  cant as (   -- colheitas por hora de cada canteiro (o que está plantado; vazio conta como 2 h)
    select c.x, c.y, 3600.0 / coalesce(k.tempo_seg, 7200) as por_h
      from fazenda_canteiros c left join fazenda_culturas k on k.id = c.cultura where c.jogador_id = p_jogador),
  itens as (
    -- oficinas: na rede, 2 do puxar e 2 da entrega (e 15 do triturador); fora dela, com a fábrica automática, 8
    select 'oficinas' as tipo,
           sum(3600.0 / o.produz_seg *
               case when exists (select 1 from jsonb_array_elements(v_rede) r where r->>'papel' = 'oficina' and (r->>'x')::int = o.x and (r->>'y')::int = o.y)
                    then 4 when v_fab then 8 else 0 end) as h
      from cons o where o.entradas is not null
    union all
    select 'triturador', case when v_tri then sum(3600.0 / o.produz_seg) * 15 end
      from cons o where o.entradas is not null
       and (exists (select 1 from jsonb_array_elements(v_rede) r where r->>'papel' = 'oficina' and (r->>'x')::int = o.x and (r->>'y')::int = o.y) or v_fab)
    union all
    select 'robo_colheita', sum(ct.por_h) * 6   -- 4 da colheita e 2 do replantio
      from cons r join cant ct on abs(ct.x - r.x) <= r.raio and abs(ct.y - r.y) <= r.raio where r.efeito = 'robo'
    union all
    select 'bau', sum(ct.por_h) * 2   -- o baú recolhe o que está encostado nele
      from cons b join cant ct on abs(ct.x - b.x) <= 1 and abs(ct.y - b.y) <= 1 where b.tipo = 'bau'
    union all
    select 'aspersor', sum(ct.por_h) * 2   -- uma seca por plantio, mais ou menos
      from cons a join cant ct on abs(ct.x - a.x) <= a.raio and abs(ct.y - a.y) <= a.raio where a.efeito = 'aspersor'
    union all
    select 'estufa', sum(ct.por_h) * 5   -- 5 por plantio no alcance dela
      from cons e join cant ct on abs(ct.x - e.x) <= e.raio and abs(ct.y - e.y) <= e.raio where e.efeito = 'estufa'
    union all
    select 'alarme', count(*)::real from cons where tipo = 'alarme'
  )
  select coalesce(jsonb_agg(jsonb_build_object('tipo', tipo, 'h', round((h * case when tipo = 'alarme' then 1 else v_desc end)::numeric)) order by h desc)
                    filter (where coalesce(h, 0) > 0), '[]'::jsonb),
         coalesce(sum(h * case when tipo = 'alarme' then 1 else v_desc end), 0)
    into v_gasta, v_c
    from itens;

  v := jsonb_build_object('gera', round(v_g), 'gasta', round(v_c), 'saldo', round(v_g - v_c),
                          'gera_itens', v_gera, 'gasta_itens', v_gasta, 'desconto', round((1 - v_desc)::numeric * 100));
  perform fazenda_cache_gravar('energia:' || p_jogador, v || jsonb_build_object('ass', v_ass));
  return v;
end;
$$;

-- Libera as conquistas que o jogador já alcançou (com prêmio em moedas)
create or replace function public.fazenda_checar_conquistas(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  s        record;
  r        record;
  v_nivel  int;
  v_constr int;
  v_conv   int;
  v_valor  int;
  v_ev     jsonb;   -- fase 63
  v_podios int;
begin
  insert into fazenda_estatisticas (jogador_id) values (p_jogador) on conflict do nothing;
  select * into s from fazenda_estatisticas where jogador_id = p_jogador;
  select fazenda_nivel(xp) into v_nivel from fazenda_jogadores where id = p_jogador;
  select count(*) into v_constr from fazenda_construcoes where jogador_id = p_jogador;
  select count(*) into v_conv from fazenda_convites where dono_id = p_jogador;
  -- fase 63: os 1º lugares de cada categoria do evento e os pódios
  select coalesce(jsonb_object_agg(categoria, n), '{}'::jsonb) into v_ev
    from (select categoria, count(*) as n from fazenda_semana_premios where jogador_id = p_jogador and posicao = 1 group by categoria) x;
  select count(*) into v_podios from fazenda_semana_premios where jogador_id = p_jogador;
  for r in
    select t.* from fazenda_conquistas_tipos t
     where not exists (select 1 from fazenda_conquistas c where c.jogador_id = p_jogador and c.conquista = t.id)
  loop
    v_valor := case r.medida
      when 'nivel' then v_nivel
      when 'construcoes' then v_constr
      when 'colher' then s.colher
      when 'plantar' then s.plantar
      when 'cuidar' then s.cuidar
      when 'vender' then s.vender
      when 'animal' then s.animal
      when 'ajudar' then s.ajudar
      when 'pegar' then s.pegar
      when 'energia' then s.energia + floor((select energia_gasta from fazenda_jogadores where id = p_jogador))::int
      when 'convites' then v_conv
      when 'peixes' then s.peixes
      when 'lendarios' then s.lendarios
      when 'pedidos' then s.pedidos
      when 'peixes_mar' then s.peixes_mar   -- fase 62: o alto-mar
      when 'marlins' then s.marlins
      when 'evento_ranking' then coalesce((v_ev->>'ranking')::int, 0)   -- fase 63: o evento da semana
      when 'evento_niveis' then coalesce((v_ev->>'niveis')::int, 0)
      when 'evento_moedas' then coalesce((v_ev->>'moedas')::int, 0)
      when 'evento_vendeu' then coalesce((v_ev->>'vendeu')::int, 0)
      when 'evento_comprou' then coalesce((v_ev->>'comprou')::int, 0)
      when 'evento_convites' then coalesce((v_ev->>'convites')::int, 0)
      when 'evento_podio' then v_podios
      when 'maior_compra' then coalesce(s.maior_compra, 0)::int   -- fase 78: a maior compra de uma vez
      else 0
    end;
    if v_valor >= r.meta then
      insert into fazenda_conquistas (jogador_id, conquista) values (p_jogador, r.id) on conflict do nothing;
      if found then   -- fase 70: só paga quem gravou agora (duas chamadas juntas pagavam duas vezes)
        update fazenda_jogadores set moedas = moedas + r.recompensa, diamantes = diamantes + r.diamantes where id = p_jogador;   -- fase 72
      end if;
    end if;
  end loop;
end;
$$;

create or replace function public.fazenda_feira_regras()
returns jsonb language sql immutable as $$
  select '{"taxa": 0, "min": 0.5, "max": 3, "horas": 48, "por_barraca": 2, "barracas_max": 4, "barraca_nivel": 5,
           "barraca_precos": [800, 1600, 2400], "compras_dia": 50, "qtd_max": 99}'::jsonb;
$$;

-- permissões
revoke execute on function
  public.fazenda_terrenos(int, int),
  public.fazenda_zona_minha(int, int),
  public.fazenda_hidro_em(timestamptz),
  public.fazenda_moedas_pagou()
from public, anon, authenticated;

grant execute on function
  public.fazenda_comprar(text, text, text)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- conferência: deve aparecer "Fase 78: 10 terrenos, 21 painéis no 29, a usina no 20, +50% de venda no 25, 50 compras na barraca"
select 'Fase 78: ' || jsonb_array_length(public.fazenda_zonas()) || ' terrenos, '
       || public.fazenda_limite_maquina('painel_solar', 8, 29) || ' painéis no 29, a usina no '
       || (select nivel_min from public.fazenda_itens where id = 'hidreletrica') || ', +'
       || (50 - 0) || '% de venda no 25, ' || (public.fazenda_feira_regras()->>'compras_dia') || ' compras na barraca' as ok;
