-- ============================================================
-- FAZENDINHA — Fase 72 (os números: preços do 20 em diante, XP e diamantes),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 71): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- ------------------------------------------------------------
-- Fase 72: os números (a revisão de 17/10 e o "do nível 20 em diante está sobrando dinheiro").
-- • Preços: o que libera do nível 20 em diante custa 2,5x (construções, oficinas, pomar e os terrenos
--   6 e 7, em fazenda_zonas); melhorias (fazenda_melhorias_tipos) e evoluir ajudante, 2x. As sementes
--   ficam como estão.
-- • Desmanchar devolve a metade do que você pagou (fazenda_construcoes.pago), não a do preço de hoje:
--   com os preços novos, comprar barato antes e desmanchar depois dava lucro. O cercado que veio de
--   graça não devolve nada.
-- • Triturador: 40 mil, 15 ⚡ por receita e +50% (uma receita sim, outra não, sai 1 a mais), em vez do
--   dobro (fazenda_oficinas_andar).
-- • O que ajudante, robô e baú colhem (e os bichos que os ajudantes coletam) dá metade do XP.
-- • Alface em 5 min (era 2). Adega e vinícola em 2 h (eram 4), geleia em 60 min (85) e queijo em 90 (128).
-- • Missões: o XP é 1,5% do nível. Visitas: pelo menos 1% do nível em XP (o caminhoneiro, 2%), e o
--   adubo da mascate cobre 8 canteiros + 1 a cada 3 níveis. As moedas de missões e visitas não mudam.
-- • Diamantes (fazenda_loja_diamantes): salvar murchas, 1 a cada 25 plantas (era 1 para todas);
--   colher agora, 1 a cada 4 h que faltam (era 1 por planta); 1 diamante enche 150 ⚡ (eram 50); o
--   café dos ajudantes dura 4 h (eram 2).
-- • Conquistas dão diamantes (fazenda_conquistas_tipos.diamantes): nível 10, 15, 20, 25, 30, 35 e 40
--   dão o número do nível; o 45, 100; o Velho Chico, 20; o marlim, 50. Quem já tinha ganha agora, uma
--   vez só (fazenda_conquistas.diamantes_pagos).
-- ------------------------------------------------------------
-- o XP do que os ajudantes, robôs e baús colhem: soma na chamada (fazenda.xp_bot, que volta junto se a
-- tarefa for desfeita) e grava uma vez só no fim da rodada deles (uma gravação por colheita deixava a
-- volta de uma fazenda grande 2x mais lenta)
create or replace function public.fazenda_bot_xp(p_jogador uuid, p_xp int)
returns void
language plpgsql
set search_path = public
as $$
declare
  v text := current_setting('fazenda.xp_bot', true);
begin
  if coalesce(p_xp, 0) <= 0 then return; end if;
  if v is not null and v <> '' and split_part(v, '#', 1) <> p_jogador::text then
    perform fazenda_bot_xp_gravar();   -- (o de outra fazenda, que não deveria estar aí)
    v := null;
  end if;
  perform set_config('fazenda.xp_bot', p_jogador::text || '#'
                     || (coalesce(nullif(split_part(coalesce(v, ''), '#', 2), '')::bigint, 0) + p_xp), true);
end;
$$;

create or replace function public.fazenda_bot_xp_gravar()
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v text := current_setting('fazenda.xp_bot', true);
begin
  if v is null or v = '' then return; end if;
  perform set_config('fazenda.xp_bot', '', true);
  update fazenda_jogadores set xp = xp + split_part(v, '#', 2)::bigint where id = split_part(v, '#', 1)::uuid;
end;
$$;

alter table public.fazenda_construcoes add column if not exists pago int;
-- o que já estava construído vale pelo preço de antes desta fase (roda antes dos preços novos)
update public.fazenda_construcoes c set pago = i.custo
  from public.fazenda_itens i
 where i.id = c.tipo and c.pago is null;

update public.fazenda_itens i set custo = v.custo
  from (values
    ('engenho', 80000), ('fabrica_auto', 37500), ('torrefacao', 85000), ('robo_colheita', 45000),
    ('fiacao', 90000), ('aspersor', 30000), ('cafeteria', 100000), ('reator', 75000),
    ('alfaiataria', 112500), ('vitaminas', 50000), ('vinicola', 120000), ('mangueira', 7500),
    ('guacamolaria', 60000), ('abacateiro', 10000), ('chocolateria', 65000), ('pimentaria', 125000),
    ('cacaueiro', 12500), ('adega', 75000), ('jabuticabeira', 15000), ('estatua_chico', 75000),
    ('bombonaria', 150000), ('supercap', 22500),
    ('triturador', 40000)) v(id, custo)
 where i.id = v.id;
update public.fazenda_itens
   set descricao = 'As oficinas rendem 50% a mais: uma receita sim, outra não, sai 1 produto a mais. Gasta 15 ⚡ por receita.'
 where id = 'triturador';
update public.fazenda_itens i set produz_seg = v.seg
  from (values ('adega', 7200), ('vinicola', 7200), ('casa_geleia', 3600), ('queijaria', 5400)) v(id, seg)
 where i.id = v.id;
update public.fazenda_culturas set tempo_seg = 300 where id = 'alface';

alter table public.fazenda_conquistas_tipos add column if not exists diamantes int not null default 0;
update public.fazenda_conquistas_tipos t set diamantes = v.d
  from (values ('nivel_10', 10), ('nivel_15', 15), ('nivel_20', 20), ('nivel_25', 25), ('nivel_30', 30),
               ('nivel_35', 35), ('nivel_40', 40), ('nivel_45', 100), ('velho_chico', 20), ('marlim', 50)) v(id, d)
 where t.id = v.id;
-- quem já tinha a conquista ganha os diamantes dela agora, uma vez só (a coluna nasce vazia nas antigas;
-- as novas já nascem pagas, porque fazenda_checar_conquistas paga na hora)
alter table public.fazenda_conquistas add column if not exists diamantes_pagos boolean;
update public.fazenda_jogadores j set diamantes = j.diamantes + x.d
  from (select c.jogador_id, sum(t.diamantes)::int as d
          from public.fazenda_conquistas c join public.fazenda_conquistas_tipos t on t.id = c.conquista
         where c.diamantes_pagos is null and t.diamantes > 0
         group by c.jogador_id) x
 where j.id = x.jogador_id;
update public.fazenda_conquistas set diamantes_pagos = true where diamantes_pagos is null;
alter table public.fazenda_conquistas alter column diamantes_pagos set default true;

-- os catálogos prontos com os números novos (as melhorias são uma função: o gatilho não vê)
select public.fazenda_cache_montar();

-- as funções que já existiam e mudaram

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
           {"n":7,"nome":"Litoral","x":0,"y":32,"w":48,"h":10,"custo":750000,"nivel":31,"canteiros":10,"mar":true}]'::jsonb;   -- fase 61 (fase 72: do 20 em diante, 2,5x)
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
    v_murcho := v_maduro + make_interval(secs => greatest(k.tempo_seg * 2, 3600));
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
      v_murcho := now() + make_interval(secs => greatest(k.tempo_seg * 2, 3600));
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
    if not p_bot and fazenda_nivel(j.xp) <= 5 then update fazenda_jogadores set xp = xp + 1 where id = p_jogador; end if;

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
    -- semente de outra estação só cresce no alcance de uma estufa elétrica
    v_fora := k.estacao is not null and k.estacao <> fazenda_estacao_em(now());
    v_estufa := fazenda_protegido(p_jogador, 'estufa', c.x, c.y);
    if v_fora and not v_estufa then
      raise exception 'fora_de_estacao';
    end if;
    if fazenda_nivel(j.xp) < k.nivel_min then
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
           plantado_em = now() - make_interval(secs => k.tempo_seg *
                           (0.1 * fazenda_protegido(p_jogador, 'crescer', c.x, c.y)::int + 0.25 * v_estufa::int
                            + fazenda_melhoria(p_jogador, 'adubo'))),   -- fase 57: adubo premium
           erva = false, praga = false, seco = false, roubado = 0, adubado = false,
           prox_evento = now() + make_interval(secs => k.tempo_seg * (0.15 + random() * 0.35))
     where jogador_id = p_jogador and posicao = p_posicao;
    if not p_bot then
      perform fazenda_missao(p_jogador, 'plantar', 1);
      -- fase 57: fazenda completa: plantar também dá XP (fase 70: ele vem na colheita; plantar e arrancar
      -- em seguida virava XP sem fim)
      update fazenda_jogadores set semente = k.id where id = p_jogador;
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
             + c.adubado::int;                                          -- adubo do Seu Zé
    if fazenda_protegido(p_jogador, 'sorte', c.x, c.y) and random() < 0.15 then
      v_qtd := v_qtd * 2;                                               -- alvo
    end if;
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

-- Sorteia as 3 missões do dia, se ainda não existirem
create or replace function public.fazenda_gerar_missoes(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_hoje  date := fazenda_hoje();
  v_nivel int;
  v_tipos text[] := array['colher', 'plantar', 'cuidar', 'vender'];
  v_tipo  text;
  v_alvo  int;
  v_moeda int;
begin
  if exists (select 1 from fazenda_missoes where jogador_id = p_jogador and dia = v_hoje) then
    return;
  end if;
  select fazenda_nivel(xp) into v_nivel from fazenda_jogadores where id = p_jogador;
  if exists (select 1 from fazenda_animais where jogador_id = p_jogador) then
    v_tipos := v_tipos || 'animal'::text;
  end if;
  if v_nivel >= 2 then
    v_tipos := v_tipos || 'ajudar'::text;
  end if;
  select array_agg(t order by random()) into v_tipos from unnest(v_tipos) t;

  for i in 1..3 loop
    v_tipo := v_tipos[i];
    v_alvo := case v_tipo
      when 'colher'  then 8 + v_nivel * 2 + floor(random() * 6)::int
      when 'plantar' then 4 + v_nivel + floor(random() * 3)::int
      when 'cuidar'  then 3 + floor(random() * 3)::int
      when 'vender'  then ((60 + v_nivel * 30 + floor(random() * 60)::int) / 10) * 10
      else 2 + floor(random() * 3)::int
    end;
    v_moeda := case v_tipo
      when 'colher'  then v_alvo * 3
      when 'plantar' then v_alvo * 5
      when 'vender'  then v_alvo / 3
      when 'animal'  then v_alvo * 15
      else v_alvo * 8
    end + 10 * v_nivel;
    -- fase 72: o XP é 1,5% do nível (no 30, 634; no 44, 1.636), e no começo o de sempre se for maior
    insert into fazenda_missoes (jogador_id, dia, slot, tipo, alvo, moedas, xp)
    values (p_jogador, v_hoje, i - 1, v_tipo, v_alvo, v_moeda,
            greatest(5 + v_nivel * 3, ceil(0.015 * (fazenda_xp_nivel(least(v_nivel, 44) + 1) - fazenda_xp_nivel(least(v_nivel, 44))))::int))
    on conflict do nothing;
  end loop;
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

create or replace function public.fazenda_animal_um(p_jogador uuid, p_animal bigint, p_acao text, p_bot boolean default false)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  r      record;
  v_tem  int;
begin
  select a.id, a.tipo, a.alimentado_em, t.produto, t.tempo_seg, t.racao, t.racao_qtd, k.xp as produto_xp
    into r
    from fazenda_animais a
    join fazenda_animais_tipos t on t.id = a.tipo
    join fazenda_culturas k on k.id = t.produto
   where a.id = p_animal and a.jogador_id = p_jogador
     for update of a;
  if not found then
    raise exception 'animal_invalido';
  end if;

  if p_acao = 'alimentar' then
    if r.alimentado_em is not null then
      raise exception 'ja_alimentado';
    end if;
    select quantidade into v_tem from fazenda_celeiro
     where jogador_id = p_jogador and item = r.racao
       for update;
    if coalesce(v_tem, 0) < r.racao_qtd then
      raise exception 'sem_racao';
    end if;
    update fazenda_celeiro set quantidade = quantidade - r.racao_qtd
     where jogador_id = p_jogador and item = r.racao;
    -- com fardo de feno na fazenda, o animal produz 20% mais rápido; fase 54: o cuidador dele, mais
    -- 10% por nível (o bicho já começa adiantado, como com o feno)
    update fazenda_animais
       set alimentado_em = now() - make_interval(secs => r.tempo_seg * (
                             case when fazenda_tem_efeito(p_jogador, 'feno') then 0.2 else 0 end
                             + fazenda_cuidador_adianta(p_jogador, r.tipo)))
     where id = p_animal;
    return 0;

  elsif p_acao = 'coletar' then
    if r.alimentado_em is null or now() < r.alimentado_em + make_interval(secs => r.tempo_seg) then
      raise exception 'nao_pronto';
    end if;
    insert into fazenda_celeiro (jogador_id, item, quantidade)
    values (p_jogador, r.produto, 1)
    on conflict (jogador_id, item)
    do update set quantidade = fazenda_celeiro.quantidade + 1;
    -- fase 72: o que o ajudante coleta dá metade do XP (antes, nada)
    if not p_bot then update fazenda_jogadores set xp = xp + r.produto_xp where id = p_jogador;
    else perform fazenda_bot_xp(p_jogador, r.produto_xp / 2); end if;
    update fazenda_animais set alimentado_em = null where id = p_animal;
    if not p_bot then perform fazenda_missao(p_jogador, 'animal', 1); end if;
    return 1;
  end if;

  raise exception 'acao_invalida';
end;
$$;

-- Contrata um ajudante ou evolui o nível dele (fase 72: 4x e 8x o preço de contratar; eram 2x e 4x)
create or replace function public.fazenda_contratar(p_token text, p_tipo text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  j       record;
  t       record;
  v_nivel int;
  v_custo int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  select * into t from fazenda_ajudantes_tipos where id = p_tipo;
  if not found then raise exception 'item_invalido'; end if;
  if fazenda_nivel(j.xp) < t.nivel_min then raise exception 'nivel_insuficiente'; end if;
  perform fazenda_trabalhar(v_id);   -- fecha o trabalho no ritmo antigo antes de mudar
  perform fazenda_ajudantes_fechar(v_id, p_tipo);   -- (fase 46: quem não trabalhou também)
  select nivel into v_nivel from fazenda_ajudantes where jogador_id = v_id and tipo = p_tipo;
  if v_nivel >= 3 then raise exception 'nivel_maximo'; end if;
  v_custo := case coalesce(v_nivel, 0) when 0 then t.custo when 1 then t.custo * 4 else t.custo * 8 end;
  if j.moedas < v_custo then raise exception 'moedas_insuficientes'; end if;
  update fazenda_jogadores set moedas = moedas - v_custo where id = v_id;
  insert into fazenda_ajudantes (jogador_id, tipo) values (v_id, p_tipo)
  on conflict (jogador_id, tipo) do update set nivel = fazenda_ajudantes.nivel + 1;
  return jsonb_build_object('estado', fazenda_estado(v_id), 'nivel', coalesce(v_nivel, 0) + 1);
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

-- Tira uma construção e devolve metade do preço (fase 72: do que pagou)
create or replace function public.fazenda_demolir(p_token text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_tipo text;
  v_pago int;   -- fase 72
  c      record;
begin
  -- canteiro: só sai vazio ou arado (planta crescendo, colha ou limpe antes)
  select * into c from fazenda_canteiros where jogador_id = v_id and x = p_x and y = p_y for update;
  if found then
    if c.estado = 'plantado' then raise exception 'canteiro_ocupado'; end if;
    delete from fazenda_canteiros where jogador_id = v_id and posicao = c.posicao;
    return jsonb_build_object('devolvido', 0, 'estado', fazenda_estado(v_id));
  end if;

  -- fase 45: cercado com bicho dentro não sai (o bicho não tem mais para onde ir)
  if exists (select 1 from fazenda_construcoes k join fazenda_animais a on a.jogador_id = k.jogador_id and 'cercado_' || a.tipo = k.tipo
              where k.jogador_id = v_id and k.x = p_x and k.y = p_y) then   -- (k: c é o registro do canteiro)
    raise exception 'cercado_com_bichos';
  end if;

  -- oficina: o estoque (ingredientes) e os produtos prontos voltam para o celeiro
  perform fazenda_oficinas_andar(v_id);
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  select v_id, x.item, sum(x.qtd)::int from (
    select e.key as item, e.value::int * (oc.estoque + case when oc.iniciado_em is null then 0 else 1 end) as qtd
      from fazenda_construcoes oc join fazenda_itens oi on oi.id = oc.tipo, jsonb_each_text(oi.entradas) e
     where oc.jogador_id = v_id and oc.x = p_x and oc.y = p_y and oi.entradas is not null
    union all
    select oi.produz, oc.prontos
      from fazenda_construcoes oc join fazenda_itens oi on oi.id = oc.tipo
     where oc.jogador_id = v_id and oc.x = p_x and oc.y = p_y and oi.entradas is not null and oc.prontos > 0
  ) x where x.qtd > 0 group by x.item
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  -- fase 39: o que estava guardado no baú ou já tinha chegado na oficina volta para o celeiro
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  select v_id, x.item, sum(x.quantidade)::int from (
    select item, quantidade from fazenda_bau_itens where jogador_id = v_id and x = p_x and y = p_y
    union all
    select item, quantidade from fazenda_oficina_itens where jogador_id = v_id and x = p_x and y = p_y
  ) x where x.quantidade > 0 group by x.item
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  delete from fazenda_bau_itens where jogador_id = v_id and x = p_x and y = p_y;
  delete from fazenda_oficina_itens where jogador_id = v_id and x = p_x and y = p_y;

  delete from fazenda_construcoes where jogador_id = v_id and x = p_x and y = p_y
  returning tipo, pago into v_tipo, v_pago;
  if v_tipo is null then raise exception 'item_invalido'; end if;
  -- fase 72: metade do que pagou (com os preços novos, a metade do preço de hoje dava lucro); o que
  -- veio de presente (o lampião do começo) segue pela metade do preço
  v_pago := coalesce(v_pago, (select custo from fazenda_itens where id = v_tipo)) / 2;
  update fazenda_jogadores set moedas = moedas + v_pago where id = v_id;
  return jsonb_build_object('devolvido', v_pago, 'estado', fazenda_estado(v_id));
end;
$$;

-- Faz as oficinas andarem até agora (roda ao carregar a fazenda e antes de mexer numa oficina)
create or replace function public.fazenda_oficinas_andar(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  o       record;
  v_tri   boolean := fazenda_tem_efeito(p_jogador, 'triturar');
  v_membros jsonb := coalesce((select jsonb_agg(to_jsonb(r)) from fazenda_rede(p_jogador) r), '[]'::jsonb);
  v_t     timestamptz;
  v_fim   timestamptz;
  v_est   int;
  v_pr    int;
  v_n     int;
  v_qtd   int;
  v_rede  boolean;
  v_volta int;
  v_puxou boolean;
begin
  for o in
    select c.x, c.y, c.iniciado_em, c.estoque, c.prontos, i.produz, i.produz_seg, i.produz_qtd, i.entradas
      from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
     where c.jogador_id = p_jogador and i.entradas is not null
     order by i.ordem, c.x, c.y   -- (a prensa antes do empório: o óleo chega no mesmo passo)
       for update of c
  loop
    v_t := o.iniciado_em; v_est := o.estoque; v_pr := o.prontos; v_fim := null; v_n := 0;
    v_rede := fazenda_redes_de(v_membros, 'oficina', o.x, o.y) is not null;
    -- ligou na rede agora: o que estava pronto esperando já sai pelo cano
    if v_rede and v_pr > 0 then
      v_pr := v_pr - fazenda_rede_entregar(p_jogador, o.x, o.y, o.produz, v_pr, v_membros, now());
    end if;
    loop
      exit when v_n >= 48;
      v_n := v_n + 1;
      if v_t is not null then
        exit when now() < v_t + make_interval(secs => o.produz_seg);   -- ainda trabalhando
        v_qtd := o.produz_qtd;
        v_fim := v_t + make_interval(secs => o.produz_seg);
        -- triturador (fase 72: +50% em vez do dobro, e 15 ⚡ por receita): metade de mais; com 1 por
        -- receita, uma sim, uma não (pela hora em que fica pronta: receitas emendadas se alternam)
        if v_tri and fazenda_gastar_energia(p_jogador, 15) then
          v_qtd := v_qtd + greatest(v_qtd / 2, (floor(extract(epoch from v_fim) / o.produz_seg)::bigint % 2 = 0)::int);
        end if;
        -- pronto: sai pela rede (outra oficina, celeiro ou baú); o que não sai fica para você pegar
        v_pr := v_pr + v_qtd - case when v_rede then fazenda_rede_entregar(p_jogador, o.x, o.y, o.produz, v_qtd, v_membros, v_fim) else 0 end;
        v_t := null;
      end if;
      -- estoque vazio e na rede: busca uma receita nos baús/celeiro da rede (2 ⚡, fase 43)
      if v_est <= 0 and v_rede
         and fazenda_rede_puxar(p_jogador, o.x, o.y, o.entradas, v_membros, greatest(coalesce(v_fim, now()), now() - interval '12 hours')) then
        v_est := 1;
      end if;
      exit when v_est <= 0;
      v_est := v_est - 1;
      -- emenda na receita anterior (o tempo fora vale, até 12 horas)
      v_t := greatest(coalesce(v_fim, now()), now() - interval '12 hours');
    end loop;
    -- fase 46: só grava se mudou (rodava em toda carga para toda oficina)
    if v_t is distinct from o.iniciado_em or v_est <> o.estoque or least(v_pr, 32000) <> o.prontos then
      update fazenda_construcoes set iniciado_em = v_t, estoque = v_est, prontos = least(v_pr, 32000)
       where jogador_id = p_jogador and x = o.x and y = o.y;
    end if;
  end loop;
  -- Fase 42: a rede enche o estoque das oficinas sozinha (até o máximo), uma receita por vez em
  -- rodízio, para dividir o que tem entre todas; a oficina parada que ganhou ingrediente já começa
  for v_volta in 1..fazenda_estoque_max() loop
    v_puxou := false;
    for o in
      select c.x, c.y, c.estoque, c.iniciado_em, i.entradas
        from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
       where c.jogador_id = p_jogador and i.entradas is not null
         and c.estoque + (c.iniciado_em is not null)::int < fazenda_estoque_max()
       order by i.ordem, c.x, c.y
    loop
      continue when fazenda_redes_de(v_membros, 'oficina', o.x, o.y) is null;
      if fazenda_rede_puxar(p_jogador, o.x, o.y, o.entradas, v_membros, now()) then
        update fazenda_construcoes
           set iniciado_em = coalesce(iniciado_em, now()),
               estoque = estoque + case when iniciado_em is null then 0 else 1 end
         where jogador_id = p_jogador and x = o.x and y = o.y;
        v_puxou := true;
      end if;
    end loop;
    exit when not v_puxou;
  end loop;
  perform fazenda_rede_descarregar(p_jogador, v_membros);
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
         and now() < c.plantado_em + make_interval(secs => u.tempo_seg + greatest(u.tempo_seg * 2, 3600))
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
      select a.id, a.alimentado_em, t.tempo_seg, t.produto, t.racao, t.racao_qtd, p.x as px, p.y as py
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
               and now() < x.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)), false) as maduro
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
    if a.funcao = 'plantar' and coalesce((select carregado_antes > now() - interval '2 minutes' from fazenda_jogadores where id = p_jogador), false) then
      update fazenda_ajudantes set atualizado_em = now() where jogador_id = p_jogador and tipo = a.tipo;
      continue;
    end if;
    v_custo := 100 / (fazenda_ritmo(a.nivel) * 8);
    -- fase 43: com o café (diamantes) o tempo dentro dele vale em dobro
    v_seg := extract(epoch from now() - a.atualizado_em)::real
           + case when v_cafe_ate is null then 0
                  else greatest(extract(epoch from least(now(), v_cafe_ate) - greatest(a.atualizado_em, v_cafe_de))::real, 0) end;
    v_cred := least(a.credito + v_seg / 3600 * fazenda_ritmo(a.nivel), fazenda_ritmo(a.nivel) * 8);
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
            select cc.posicao, now() >= cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) as murcha
              from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
             where cc.jogador_id = p_jogador and cc.estado = 'plantado'
               and now() >= cc.plantado_em + make_interval(secs => k.tempo_seg)
               and cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600))
                   > greatest(a.atualizado_em, now() - interval '8 hours')
             order by cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) limit v_n
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
                 and k.estoque + (k.iniciado_em is not null)::int < fazenda_estoque_max()
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
                    or (cc.estado = 'plantado' and now() >= cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600))))
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
          v_nivel := fazenda_nivel((select xp from fazenda_jogadores where id = p_jogador));
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
               and now() < cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600))
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
            select an.id, an.alimentado_em, t.tempo_seg, t.racao, t.racao_qtd from fazenda_animais an join fazenda_animais_tipos t on t.id = an.tipo
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

-- A visita de agora (null = já atendida, ou nível menor que 3). Tudo sai do md5 do jogador e
-- do bloco de 3 horas: a mesma visita a cada carga, e outra no bloco seguinte.
create or replace function public.fazenda_visitante(p_jogador uuid)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_slot  bigint := floor(extract(epoch from now()) / 10800);
  v_h     text := md5(p_jogador::text || ':' || floor(extract(epoch from now()) / 10800)::bigint);
  v_tipo  text;
  v_nivel int;
  k       record;
  v_qtd   int;
  v_alvo  int;
  v_raro  text;
begin
  if exists (select 1 from fazenda_visitas_npc where jogador_id = p_jogador and slot = v_slot) then return null; end if;
  -- fase 66: o Perks (1 em cada 30 visitas, do nível 3 em diante; o mercador vem antes) pede uma planta
  -- fácil em número grande e paga com luvas que passam pelo alarme do vizinho
  if ('x' || substr(v_h, 9, 4))::bit(16)::int % 100 <> 0
     and ('x' || substr(v_h, 17, 4))::bit(16)::int % (fazenda_perks()->>'chance')::int = 0
     and (select fazenda_nivel(xp) from fazenda_jogadores where id = p_jogador) >= (fazenda_perks()->>'nivel')::int then
    select x.p->>'id', (x.p->>'qtd')::int into v_raro, v_qtd
      from jsonb_array_elements(fazenda_perks()->'pedidos') x(p) join fazenda_culturas c on c.id = x.p->>'id'
     where c.nivel_min <= (select fazenda_nivel(xp) from fazenda_jogadores where id = p_jogador)
     order by md5(v_h || c.id) limit 1;
    return jsonb_build_object('slot', v_slot, 'tipo', 'perks', 'ate', to_timestamp((v_slot + 1) * 10800),
                              'item', v_raro, 'qtd', v_qtd, 'luvas', (fazenda_perks()->>'luvas')::int, 'paga', 0, 'xp', 0);
  end if;
  -- fase 60: o mercador (1 em cada 100 visitas, desde o nível 1) troca 1 material raro do píer por
  -- frutos fora de época (só tem quem guardou da estação dele ou plantou na estufa)
  if ('x' || substr(v_h, 9, 4))::bit(16)::int % 100 = 0 then
    select y.r->>'id', (y.r->>'frutas')::int into v_raro, v_qtd
      from (select x.r, sum((x.r->>'peso')::int) over (order by x.ord) as acum
              from jsonb_array_elements(fazenda_raros()) with ordinality as x(r, ord)) y
     where y.acum > ('x' || substr(v_h, 13, 4))::bit(16)::int % 100
     order by y.acum limit 1;
    -- (fase 70: só o que o seu nível já planta; no nível 1 e 2, nada fora de época: ele não vem)
    select c.* into k from fazenda_culturas c
     where c.tipo = 'cultura' and c.estacao is not null and c.estacao <> fazenda_estacao_em(now())
       and c.nivel_min <= (select fazenda_nivel(xp) from fazenda_jogadores where id = p_jogador)
     order by md5(v_h || c.id) limit 1;
    if found then
      return jsonb_build_object('slot', v_slot, 'tipo', 'mercador', 'ate', to_timestamp((v_slot + 1) * 10800),
                                'item', k.id, 'qtd', v_qtd, 'raro', v_raro, 'paga', 0, 'xp', 0);
    end if;
  end if;
  select fazenda_nivel(xp) into v_nivel from fazenda_jogadores where id = p_jogador;
  if v_nivel < 3 then return null; end if;
  v_tipo := (array['feirante', 'doceira', 'caminhoneiro', 'mascate'])[1 + (('x' || substr(v_h, 1, 4))::bit(16)::int % 4)];
  if v_tipo = 'caminhoneiro' and v_nivel < 8 then v_tipo := 'feirante'; end if;
  if v_tipo = 'mascate' then   -- fase 72: o adubo cobre mais canteiros com o nível (8 + 1 a cada 3 níveis)
    return jsonb_build_object('slot', v_slot, 'tipo', v_tipo, 'ate', to_timestamp((v_slot + 1) * 10800),
                              'canteiros', 8 + v_nivel / 3, 'preco', 40 + 10 * v_nivel);
  end if;
  -- a doceira quer o que seus bichos ou suas oficinas fazem; os outros, o que você planta
  if v_tipo = 'doceira' then
    select c.* into k from fazenda_culturas c
     where c.tipo = 'produto' and (   -- (fase 70: sem o "ordem < 40", que deixava de fora tudo o que veio depois da fase 21)
           c.id in (select t.produto from fazenda_animais a join fazenda_animais_tipos t on t.id = a.tipo where a.jogador_id = p_jogador)
        or c.id in (select i.produz from fazenda_construcoes x join fazenda_itens i on i.id = x.tipo
                     where x.jogador_id = p_jogador and i.entradas is not null))
     order by md5(v_h || c.id) limit 1;
    if not found then v_tipo := 'feirante'; end if;
  end if;
  if v_tipo <> 'doceira' then   -- uma das 5 melhores sementes que você já tem (nada de 70 alfaces no nível 20)
    select x.* into k from (
      select c.* from fazenda_culturas c
       where c.tipo = 'cultura' and c.nivel_min <= v_nivel and (c.estacao is null or c.estacao = fazenda_estacao_em(now()))
       order by c.nivel_min desc limit 5) x
     order by md5(v_h || x.id) limit 1;
  end if;
  v_alvo := (60 + 20 * v_nivel) * case when v_tipo = 'caminhoneiro' then 3 else 1 end;
  v_qtd := greatest(2, least(80, round(v_alvo::numeric / k.venda)::int));
  return jsonb_build_object('slot', v_slot, 'tipo', v_tipo, 'ate', to_timestamp((v_slot + 1) * 10800),
    'item', k.id, 'qtd', v_qtd,
    'paga', round(v_qtd * k.venda * case v_tipo when 'feirante' then 1.5 when 'doceira' then 1.6 else 1.4 end)::int,
    -- XP de quanto você ganharia colhendo isso (o caminhoneiro dá o dobro); fase 72: pelo menos 1% do nível
    -- (o caminhoneiro, 2%), que cresce com ele: no fim, o de colher era quase nada
    'xp', greatest(1, v_qtd * k.xp / greatest(k.rendimento, 1),
                   ceil(0.01 * (fazenda_xp_nivel(least(v_nivel, 44) + 1) - fazenda_xp_nivel(least(v_nivel, 44))))::int)
          * case when v_tipo = 'caminhoneiro' then 2 else 1 end);
end;
$$;

create or replace function public.fazenda_loja_diamantes()
returns jsonb language sql immutable as $$
  -- fase 72: o café dura 4 h; 1 diamante enche 150 ⚡; salvar murchas, 1 a cada 25 plantas; colher
  -- agora, 1 a cada 4 h que faltam
  select '{"xp2": {"preco": 15, "horas": 1},
           "xp": {"preco": 10, "pct": 10, "por_dia": 3},
           "cafe": {"preco": 10, "horas": 4},
           "energia": {"por": 150},
           "oficina": {"por_hora": 1},
           "murchas": {"preco": 1, "por": 25},
           "agora": {"horas": 4}}'::jsonb;
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
    v_nivel := fazenda_nivel(j.xp);
    if v_nivel >= 45 then raise exception 'xp_maximo'; end if;   -- fase 62: o último nível agora é o 45
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
    select c.iniciado_em, i.produz_seg, i.entradas into o
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
  end if;

  insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, p_item, v_preco);
  return jsonb_build_object('item', p_item, 'diamantes', v_preco, 'xp', v_xp, 'estado', fazenda_estado(v_id));
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
  select '[{"id":"adubo","nome":"Adubo premium","descricao":"As plantas nascem adiantadas: crescem 10%, 20% e 30% mais rápido (soma com o girassol e a estufa).",
            "niveis":[{"nivel":23,"custo":100000,"valor":0.1},{"nivel":26,"custo":300000,"valor":0.2},{"nivel":29,"custo":600000,"valor":0.3}]},
           {"id":"pomar","nome":"Pomar fértil","descricao":"As árvores do pomar dão frutas 15% e 30% mais rápido.",
            "niveis":[{"nivel":24,"custo":160000,"valor":0.15},{"nivel":28,"custo":400000,"valor":0.3}]},
           {"id":"pes","nome":"Mais pés de fruta","descricao":"Mais 1 e mais 2 pés de cada fruta no pomar, além dos 4 que os terrenos dão.",
            "niveis":[{"nivel":25,"custo":120000,"valor":1},{"nivel":30,"custo":240000,"valor":2}]},
           {"id":"barco","nome":"Barco","mar":true,"descricao":"Barco maior vai mais longe: o cardume é maior, enche mais rápido e tem peixe que o bote não alcança.",
            "base":{"nome":"Bote","valor":1,"intervalo":900,"max":16},
            "niveis":[{"nivel":34,"custo":800000,"valor":2,"nome":"Traineira","intervalo":720,"max":24},
                      {"nivel":37,"custo":1800000,"valor":3,"nome":"Barco de pesca","intervalo":600,"max":32},
                      {"nivel":40,"custo":3600000,"valor":4,"nome":"Pesqueiro","intervalo":480,"max":40},
                      {"nivel":43,"custo":7000000,"valor":5,"nome":"Barco oceânico","intervalo":360,"max":48}]},
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
            "niveis":[{"nivel":33,"custo":400000,"valor":0.1,"nome":"Motor de popa","itens":{"ferro_forjado":1}},
                      {"nivel":39,"custo":1200000,"valor":0.2,"nome":"Motor a diesel","itens":{"ferro_forjado":2,"ancora":1}},
                      {"nivel":44,"custo":3000000,"valor":0.3,"nome":"Motor turbo","itens":{"ferro_forjado":3,"ancora":2,"perola_negra":1}}]},
           {"id":"sonar","nome":"Sonar","mar":true,"peca":true,"descricao":"Acha os cardumes de peixe grande e as ostras: mais peixe grande e mais pérola negra.",
            "niveis":[{"nivel":35,"custo":500000,"valor":1,"perola":150,"nome":"Sonar simples","itens":{"corda_naval":2}},
                      {"nivel":41,"custo":1600000,"valor":2,"perola":100,"nome":"Sonar colorido","itens":{"corda_naval":2,"perola_negra":1}},
                      {"nivel":45,"custo":4000000,"valor":3,"perola":70,"nome":"Sonar de varredura","itens":{"perola_negra":2,"marlim":1}}]},
           {"id":"porao","nome":"Porão","mar":true,"peca":true,"descricao":"Guarda o peixe no gelo: às vezes uma fisgada traz 2 peixes.",
            "niveis":[{"nivel":36,"custo":600000,"valor":0.15,"nome":"Caixa de gelo","itens":{"madeira_nobre":2}},
                      {"nivel":42,"custo":2000000,"valor":0.3,"nome":"Porão refrigerado","itens":{"madeira_nobre":3,"pedra_cantaria":2}},
                      {"nivel":45,"custo":5000000,"valor":0.45,"nome":"Câmara fria","itens":{"pedra_cantaria":2,"ferro_forjado":2,"perola_negra":1}}]},
           {"id":"rede","nome":"Rede de arrasto","mar":true,"peca":true,"descricao":"Para o marinheiro: ele pesca mais rápido (e o cesto continua guardando 8 horas).",
            "niveis":[{"nivel":37,"custo":600000,"valor":0.15,"nome":"Rede de arrasto","itens":{"corda_naval":2}},
                      {"nivel":43,"custo":2400000,"valor":0.3,"nome":"Rede dupla","itens":{"corda_naval":3,"ancora":1}}]},
           {"id":"expedicao","nome":"Kit de expedição","mar":true,"peca":true,"descricao":"Bússola, mapa e tanque extra: deixa o barco oceânico pronto para viajar às ilhas (nível 46, na próxima expansão).",
            "niveis":[{"nivel":45,"custo":6000000,"valor":1,"nome":"Kit de expedição","itens":{"perola_negra":3,"marlim":2,"ancora":2}}]}]'::jsonb;
$$;

-- permissões
revoke execute on function
  public.fazenda_bot_xp(uuid, int),
  public.fazenda_bot_xp_gravar(),
  public.fazenda_zonas(),
  public.fazenda_estado(uuid),
  public.fazenda_aplicar(uuid, text, int, text, boolean),
  public.fazenda_gerar_missoes(uuid),
  public.fazenda_checar_conquistas(uuid),
  public.fazenda_animal_um(uuid, bigint, text, boolean),
  public.fazenda_oficinas_andar(uuid),
  public.fazenda_baus(uuid),
  public.fazenda_industria(uuid),
  public.fazenda_trabalhar(uuid),
  public.fazenda_visitante(uuid),
  public.fazenda_loja_diamantes(),
  public.fazenda_melhorias_tipos()
from public, anon, authenticated;

grant execute on function
  public.fazenda_contratar(text, text),
  public.fazenda_construir(text, text, int, int),
  public.fazenda_demolir(text, int, int),
  public.fazenda_usar_diamantes(text, text, int, int)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- conferência: deve aparecer "Fase 72: triturador 40000, alface 300 s, 10 conquistas com diamante"
select 'Fase 72: triturador ' || (select custo from public.fazenda_itens where id = 'triturador')
       || ', alface ' || (select tempo_seg from public.fazenda_culturas where id = 'alface') || ' s, '
       || (select count(*) from public.fazenda_conquistas_tipos where diamantes > 0) || ' conquistas com diamante' as ok;
