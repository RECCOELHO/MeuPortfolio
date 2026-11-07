-- ============================================================
-- FAZENDINHA — Fase 112 (ninguém cai de nível: o piso é o maior nível que você já alcançou, e o que está no
-- depósito conta na trava), só o que mudou.
-- Para o banco que já está no ar (com a fase 111): Supabase > SQL Editor > colar este arquivo > Run.
-- Pode rodar antes ou depois do merge (o jogo não muda).
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 111 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not exists (select 1 from pg_proc where proname = 'fazenda_cachorro_escolher') then
    raise exception 'Rode o fase111.sql antes deste. Nada foi mudado.';
  end if;
end $$;

-- as funções que mudaram (antes da conta, que usa a trava nova)

-- o menor nível que tem algo que conta e que o jogador não tem na fazenda (45: não falta nada)
create or replace function public.fazenda_nivel_trava(p_jogador uuid)
returns int language plpgsql stable security definer set search_path = public as $$
begin
  return coalesce((select min(i.nivel_min) from fazenda_itens i
                    where fazenda_conta_nivel(i.categoria, i.id) and i.nivel_min < 60   -- fase 106: até o 60
                      and not exists (select 1 from fazenda_construcoes c where c.jogador_id = p_jogador and c.tipo = i.id)
                      and not exists (select 1 from fazenda_deposito d where d.jogador_id = p_jogador and d.tipo = i.id)), 60);   -- fase 112: o guardado conta
end;
$$;


-- o que falta dos níveis até p_nivel (os ids, para a tela; fase 90: os de baixo também, de quem não caiu)
create or replace function public.fazenda_nivel_faltam(p_jogador uuid, p_nivel int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  return coalesce((select jsonb_agg(i.id order by i.nivel_min, i.ordem) from fazenda_itens i
                    where fazenda_conta_nivel(i.categoria, i.id) and i.nivel_min <= p_nivel
                      and not exists (select 1 from fazenda_construcoes c where c.jogador_id = p_jogador and c.tipo = i.id)
                      and not exists (select 1 from fazenda_deposito d where d.jogador_id = p_jogador and d.tipo = i.id)), '[]'::jsonb);   -- fase 112
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
      'ilha', jsonb_build_object('obras', coalesce(j.ilha_obras, 0), 'pode_ir', fazenda_ilha_pode(p_jogador, v_nivel),
                                 'bau_hoje', j.ilha_bau_dia = fazenda_hoje(), 'x', fazenda_ilha_x(p_jogador),
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


-- ------------------------------------------------------------
-- Fase 112: ninguém cai de nível (de novo). A regra da fase 90 era "o nível de cada um não baixa", mas o piso
-- (nivel_base) era o nível do dia da regra. Quando a fase 104 trouxe itens novos que contam para o nível
-- (o ipê no 32 e as oficinas navais no 33, 36, 39 e 42) e a fase 106 refez a trava de todo mundo, quem já
-- tinha passado desses níveis sem eles caiu até o piso antigo (ex.: do 45 para o 35). E guardar no
-- depósito uma oficina que conta também derrubava o nível.
-- • Quem caiu por causa desses itens volta para o maior nível que já tinha alcançado (e ganhado o presente:
--   nivel_premiado), até onde o XP dá; daqui para frente, cada nível novo sobe o piso junto (fazenda_estado).
-- • O que está guardado no depósito conta como seu na trava (fazenda_nivel_trava e fazenda_nivel_faltam), e
--   guardar ou tirar do depósito refaz a trava (gatilho em fazenda_deposito).
-- • Para passar do nível de agora, continua valendo ter o que falta (a regra votada).
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------
drop trigger if exists fazenda_trava_dep_ins on public.fazenda_deposito;
create trigger fazenda_trava_dep_ins after insert on public.fazenda_deposito
  referencing new table as novas for each statement execute function public.fazenda_trava_gatilho();
drop trigger if exists fazenda_trava_dep_del on public.fazenda_deposito;
create trigger fazenda_trava_dep_del after delete on public.fazenda_deposito
  referencing old table as velhas for each statement execute function public.fazenda_trava_gatilho();

-- (a foto de antes, para a conferência no fim)
create temp table if not exists fase112_antes as
  select id, public.fazenda_nivel_de(xp, nivel_trava) as nivel from public.fazenda_jogadores;
-- quem caiu por causa dos itens da fase 104 (o ipê e as oficinas navais) volta para o maior nível que já tinha
-- alcançado (e ganhado o presente), até onde o XP dá. Quem está segurado por um item antigo segue a regra.
with novo as (
  select j.id, least(coalesce(j.nivel_premiado, 1), public.fazenda_nivel(j.xp), 60,
           -- a trava sem os itens da fase 104: o que os itens antigos deixam (estes continuam valendo)
           coalesce((select min(i.nivel_min) from public.fazenda_itens i
                      where public.fazenda_conta_nivel(i.categoria, i.id) and i.nivel_min < 60
                        and i.id not in ('ipe', 'serraria_naval', 'forja', 'velaria', 'cartografia')
                        and not exists (select 1 from public.fazenda_construcoes c where c.jogador_id = j.id and c.tipo = i.id)
                        and not exists (select 1 from public.fazenda_deposito d where d.jogador_id = j.id and d.tipo = i.id)), 60)) as piso
    from public.fazenda_jogadores j)
update public.fazenda_jogadores j set nivel_base = n.piso
  from novo n
 where n.id = j.id and n.piso > greatest(coalesce(j.nivel_base, 1), public.fazenda_nivel_de(j.xp, j.nivel_trava));
update public.fazenda_jogadores set nivel_trava = greatest(public.fazenda_nivel_trava(id), coalesce(nivel_base, 1))
 where nivel_trava is distinct from greatest(public.fazenda_nivel_trava(id), coalesce(nivel_base, 1));

-- conferência (uma linha): tem que aparecer "fase 112 ok", quantos voltaram para o nível que tinham e quem
select case when (select prosrc from pg_proc where proname = 'fazenda_nivel_trava') like '%fazenda_deposito%'
             and exists (select 1 from pg_trigger where tgname = 'fazenda_trava_dep_ins')
            then 'fase 112 ok' else 'não aplicou' end as resultado,
       count(*) as voltaram,
       string_agg(j.apelido || ' ' || a.nivel || ' → ' || public.fazenda_nivel_de(j.xp, j.nivel_trava), ', '
                  order by public.fazenda_nivel_de(j.xp, j.nivel_trava) - a.nivel desc, j.apelido) as quem
  from fase112_antes a join public.fazenda_jogadores j on j.id = a.id
 where public.fazenda_nivel_de(j.xp, j.nivel_trava) <> a.nivel;
