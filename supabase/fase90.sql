-- ============================================================
-- FAZENDINHA — Fase 90 (só passa de nível quem tem tudo dos seus níveis, daqui para frente),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 89): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 89 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from information_schema.columns where table_name = 'fazenda_sessoes' and column_name = 'cat_ver')) then
    raise exception 'Rode o fase89.sql antes deste (a fase 89 não está no banco). Nada foi mudado.';
  end if;
end $$;

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
  select p_categoria in ('oficina', 'bichos', 'maquina', 'energia', 'pomar') and p_id <> 'cano';
$$;

-- o menor nível que tem algo que conta e que o jogador não tem na fazenda (45: não falta nada)
create or replace function public.fazenda_nivel_trava(p_jogador uuid)
returns int language plpgsql stable security definer set search_path = public as $$
begin
  return coalesce((select min(i.nivel_min) from fazenda_itens i
                    where fazenda_conta_nivel(i.categoria, i.id) and i.nivel_min < 45
                      and not exists (select 1 from fazenda_construcoes c where c.jogador_id = p_jogador and c.tipo = i.id)), 45);
end;
$$;

-- o que falta dos níveis até p_nivel (os ids, para a tela; fase 90: os de baixo também, de quem não caiu)
create or replace function public.fazenda_nivel_faltam(p_jogador uuid, p_nivel int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  return coalesce((select jsonb_agg(i.id order by i.nivel_min, i.ordem) from fazenda_itens i
                    where fazenda_conta_nivel(i.categoria, i.id) and i.nivel_min <= p_nivel
                      and not exists (select 1 from fazenda_construcoes c where c.jogador_id = p_jogador and c.tipo = i.id)), '[]'::jsonb);
end;
$$;

-- a trava se refaz sozinha quando entra ou sai uma construção (por qualquer caminho: construir, desmanchar,
-- tempestade, bots...). Só grava quando muda.
create or replace function public.fazenda_trava_gatilho()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    update fazenda_jogadores j set nivel_trava = greatest(fazenda_nivel_trava(j.id), j.nivel_base)
     where j.id in (select distinct jogador_id from velhas) and j.nivel_trava is distinct from greatest(fazenda_nivel_trava(j.id), j.nivel_base);
  else
    update fazenda_jogadores j set nivel_trava = greatest(fazenda_nivel_trava(j.id), j.nivel_base)
     where j.id in (select distinct jogador_id from novas) and j.nivel_trava is distinct from greatest(fazenda_nivel_trava(j.id), j.nivel_base);
  end if;
  return null;
end;
$$;
drop trigger if exists fazenda_trava_ins on public.fazenda_construcoes;
create trigger fazenda_trava_ins after insert on public.fazenda_construcoes
  referencing new table as novas for each statement execute function public.fazenda_trava_gatilho();
drop trigger if exists fazenda_trava_del on public.fazenda_construcoes;
create trigger fazenda_trava_del after delete on public.fazenda_construcoes
  referencing old table as velhas for each statement execute function public.fazenda_trava_gatilho();
drop trigger if exists fazenda_trava_upd on public.fazenda_construcoes;
create trigger fazenda_trava_upd after update on public.fazenda_construcoes
  referencing new table as novas for each statement execute function public.fazenda_trava_gatilho();


-- o dia da regra: guarda o nível de cada um (pelo XP de hoje; ninguém cai) e a trava. Rodar de novo não muda
-- nada para quem já tem a base. Devolve quantos jogadores ganharam a base agora.
create or replace function public.fazenda_regra_nivel_aplicar()
returns int language plpgsql security definer set search_path = public as $fn$
declare
  v_n int;
begin
  update fazenda_jogadores set nivel_base = fazenda_nivel(xp) where nivel_base is null;
  get diagnostics v_n = row_count;
  update fazenda_jogadores set nivel_trava = greatest(fazenda_nivel_trava(id), nivel_base)
   where nivel_trava is distinct from greatest(fazenda_nivel_trava(id), nivel_base);
  return v_n;
end;
$fn$;

-- as funções que já existiam e mudaram

-- fase 90: o nível de verdade: o do XP, mas só passa do nível N quem tem tudo o que conta dos níveis até N
create or replace function public.fazenda_nivel_de(p_xp int, p_trava int)
returns int language sql immutable as $$
  select least(fazenda_nivel(p_xp), coalesce(p_trava, 45));
$$;

-- Bônus nas vendas, em %: beleza (+1% a cada 10, até 20) + caixote (+10)
-- fase 78: do nível 29 para baixo, +50% nas vendas (do 30 ao 34 vai caindo 10 por nível, sem tombo)
create or replace function public.fazenda_bonus_venda(p_jogador uuid)
returns int language plpgsql stable security definer set search_path = public as $$
begin   -- (plpgsql: fazenda_nivel vem mais para baixo no arquivo)
  return least(fazenda_beleza(p_jogador) / 10, 20) + 10 * fazenda_tem_efeito(p_jogador, 'venda')::int
       + greatest(0, least(50, 50 - 10 * ((select fazenda_nivel_de(xp, nivel_trava) from fazenda_jogadores where id = p_jogador) - 29)));
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
      'bonus_venda', fazenda_bonus_venda(p_jogador)
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

-- Tela de entrada aberta por um link de convite: de quem é o convite?
create or replace function public.fazenda_convite_info(p_codigo text)
returns jsonb
language sql stable security definer
set search_path = public, extensions
as $$
  select jsonb_build_object('apelido', apelido, 'nivel', fazenda_nivel_de(xp, nivel_trava), 'moedas', (fazenda_premio_convite()->>'amigo')::int)
    from fazenda_jogadores where convite = upper(btrim(p_codigo));
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
    v_custo := 100 / (fazenda_ritmo(a.nivel) * fazenda_turno(p_jogador));   -- fase 82: 12 h com o turno de diamante
    -- fase 43: com o café (diamantes) o tempo dentro dele vale em dobro
    v_seg := extract(epoch from now() - a.atualizado_em)::real
           + case when v_cafe_ate is null then 0
                  else greatest(extract(epoch from least(now(), v_cafe_ate) - greatest(a.atualizado_em, v_cafe_de))::real, 0) end;
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
            select cc.posicao, now() >= cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) as murcha
              from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
             where cc.jogador_id = p_jogador and cc.estado = 'plantado'
               and now() >= cc.plantado_em + make_interval(secs => k.tempo_seg)
               and cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600))
                   > greatest(a.atualizado_em, now() - make_interval(hours => fazenda_turno(p_jogador)::int))
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
  if fazenda_nivel_de(j.xp, j.nivel_trava) < t.nivel_min then raise exception 'nivel_insuficiente'; end if;
  perform fazenda_trabalhar(v_id);   -- fecha o trabalho no ritmo antigo antes de mudar
  perform fazenda_ajudantes_fechar(v_id, p_tipo);   -- (fase 46: quem não trabalhou também)
  select nivel into v_nivel from fazenda_ajudantes where jogador_id = v_id and tipo = p_tipo;
  -- fase 74: até o nível 5; o 4 pede o nível 35 do jogador e o 5, o 42 (igual a EVOLUIR_NIVEL em fazenda.js)
  if v_nivel >= 5 then raise exception 'nivel_maximo'; end if;
  if (v_nivel = 3 and fazenda_nivel_de(j.xp, j.nivel_trava) < 35) or (v_nivel = 4 and fazenda_nivel_de(j.xp, j.nivel_trava) < 42) then raise exception 'nivel_insuficiente'; end if;
  v_custo := t.custo * (array[1, 4, 8, 16, 32])[coalesce(v_nivel, 0) + 1];
  if j.moedas < v_custo then raise exception 'moedas_insuficientes'; end if;
  update fazenda_jogadores set moedas = moedas - v_custo where id = v_id;
  insert into fazenda_ajudantes (jogador_id, tipo) values (v_id, p_tipo)
  on conflict (jogador_id, tipo) do update set nivel = fazenda_ajudantes.nivel + 1;
  return jsonb_build_object('estado', fazenda_estado(v_id), 'nivel', coalesce(v_nivel, 0) + 1);
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
  v_nivel := fazenda_nivel_de(j.xp, j.nivel_trava);
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
    -- fase 83: dono sumido há mais de 3 dias (+50% de XP e dá para plantar) e as murchas que ainda dá para limpar hoje
    'abandonada', fazenda_abandonada(p_dono),
    'limpos_hoje', (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'limpar'
                     and criado_em > now() - interval '1 day'),
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

-- Tira os problemas de um canteiro do vizinho. Retorna quantos problemas resolveu.
-- Fase 48: quanto XP vale cada ajuda a um vizinho: 0,25% do nível de quem ajuda (pelo menos 2)
-- fase 83: 0,30% (e sem o limite de 30 por dia)
create or replace function public.fazenda_premio_ajuda(p_ator uuid)
returns int language sql stable security definer set search_path = public as $$
  select greatest(2, round((fazenda_xp_nivel(n + 1) - fazenda_xp_nivel(n)) * 0.003))::int
    from (select fazenda_nivel_de(xp, nivel_trava) as n from fazenda_jogadores where id = p_ator) x;
$$;

-- fase 85: o teto do dia (o XP de 1 nível inteiro do ator)
create or replace function public.fazenda_ajuda_teto(p_ator uuid)
returns int language sql stable security definer set search_path = public as $$
  select (fazenda_xp_nivel(n + 1) - fazenda_xp_nivel(n))::int from (select fazenda_nivel_de(xp, nivel_trava) as n from fazenda_jogadores where id = p_ator) x;
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
    v_murcha := c.estado = 'plantado' and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600));
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

create or replace function public.fazenda_ranking(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_xp   int;
  v_desde timestamptz;
begin
  select xp, criado_em into v_xp, v_desde from fazenda_jogadores where id = v_id;
  return jsonb_build_object(
    -- mesmo critério de desempate da lista: quem chegou antes fica na frente
    'minha_posicao', (select count(*) + 1 from fazenda_jogadores
                       where (xp > v_xp or (xp = v_xp and criado_em < v_desde)) and banido_em is null),
    'total', (select count(*) from fazenda_jogadores where banido_em is null),
    'ranking', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', r.id, 'apelido', r.apelido, 'avatar', r.avatar, 'nivel', fazenda_nivel_de(r.xp, r.nivel_trava), 'xp', r.xp,
               'patrimonio', r.moedas + coalesce((
                 select sum(ce.quantidade * k.venda)
                   from fazenda_celeiro ce join fazenda_culturas k on k.id = ce.item
                  where ce.jogador_id = r.id), 0),
               'eu', r.id = v_id)
             order by r.xp desc, r.criado_em)
        from (select * from fazenda_jogadores where banido_em is null order by xp desc, criado_em limit 200) r), '[]'::jsonb)   -- (fase 53: eram 50)
  );
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
  select fazenda_nivel_de(xp, nivel_trava) into v_nivel from fazenda_jogadores where id = p_jogador;
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
  select fazenda_nivel_de(xp, nivel_trava) into v_nivel from fazenda_jogadores where id = p_jogador;
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
    if fazenda_nivel_de(j.xp, j.nivel_trava) < a.nivel_min then raise exception 'nivel_insuficiente'; end if;
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
    if fazenda_nivel_de(j.xp, j.nivel_trava) < a.nivel then raise exception 'nivel_insuficiente'; end if;
    if j.moedas < a.custo then raise exception 'moedas_insuficientes'; end if;
    if a.n >= 8 then update fazenda_jogadores set moedas = moedas - a.custo, direita = direita + 1 where id = v_id;
    else update fazenda_jogadores set moedas = moedas - a.custo, zonas = zonas + 1 where id = v_id; end if;

  elsif p_categoria = 'melhoria' then
    -- fase 57: o próximo nível da melhoria (p_tipo = adubo, pomar ou pes)
    -- fase 62: e as do alto-mar (barco, vara e marinheiro), que pedem o píer pronto
    select (n->>'nivel')::int as nivel, (n->>'custo')::int as custo, coalesce((m->>'mar')::boolean, false) as mar,
           n->'itens' as itens, coalesce((n->>'diamantes')::int, 0) as diamantes into a
      from jsonb_array_elements(fazenda_melhorias_tipos()) m,
           jsonb_array_elements(m->'niveis') with ordinality as x(n, i)
     where m->>'id' = p_tipo
       and x.i = 1 + coalesce((select nivel from fazenda_melhorias where jogador_id = v_id and id = p_tipo), 0);
    if not found then raise exception 'melhoria_max'; end if;
    if a.mar and j.pier_em is null then raise exception 'sem_pier'; end if;
    if fazenda_nivel_de(j.xp, j.nivel_trava) < a.nivel then raise exception 'nivel_insuficiente'; end if;
    -- fase 65: a rede é do marinheiro; o kit de expedição pede o barco oceânico
    if p_tipo = 'rede' and fazenda_mar_item(v_id, 'marinheiro') is null then raise exception 'sem_marinheiro'; end if;
    if p_tipo = 'expedicao' and coalesce((select nivel from fazenda_melhorias where jogador_id = v_id and id = 'barco'), 0) < 4 then
      raise exception 'barco_pequeno';
    end if;
    -- fase 82: as de diamante (D8) e o que cada uma precisa antes
    if p_tipo = 'cesto_bira' and j.zonas < 3 then raise exception 'sem_lago'; end if;
    if p_tipo = 'cesto_nonato' and fazenda_mar_item(v_id, 'marinheiro') is null then raise exception 'sem_marinheiro'; end if;
    if p_tipo = 'barraca' and j.barracas < 4 then raise exception 'barracas_antes'; end if;
    if j.diamantes < a.diamantes then raise exception 'diamantes_insuficientes'; end if;
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
    update fazenda_jogadores set moedas = moedas - a.custo, diamantes = diamantes - a.diamantes,
           barracas = barracas + (p_tipo = 'barraca')::int   -- fase 82: a 5ª e a 6ª barraca
     where id = v_id;
    if a.diamantes > 0 then
      insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, 'melhoria:' || p_tipo, a.diamantes);
    end if;
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

  elsif p_categoria = 'oficina' then
    -- fase 82 (B10): oficina nível 2 e 3, por tipo (vale para todas as oficinas daquele tipo)
    if not exists (select 1 from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
                    where c.jogador_id = v_id and c.tipo = p_tipo and i.entradas is not null) then
      raise exception 'item_invalido';
    end if;
    v_n := coalesce((select nivel from fazenda_oficina_nivel where jogador_id = v_id and tipo = p_tipo), 1);
    if v_n >= 3 then raise exception 'melhoria_max'; end if;
    v_preco := (fazenda_oficina_niveis()->(v_n - 1)->>'custo')::int;
    if j.moedas < v_preco then raise exception 'moedas_insuficientes'; end if;
    perform fazenda_oficinas_andar(v_id);   -- o que já ficou pronto sai no ritmo de antes
    update fazenda_jogadores set moedas = moedas - v_preco where id = v_id;
    insert into fazenda_oficina_nivel (jogador_id, tipo, nivel) values (v_id, p_tipo, 2)
    on conflict (jogador_id, tipo) do update set nivel = fazenda_oficina_nivel.nivel + 1;

  else
    raise exception 'item_invalido';
  end if;

  return jsonb_build_object('estado', fazenda_estado(v_id));
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
       >= fazenda_limite_canteiros(fazenda_nivel_de(j.xp, j.nivel_trava), fazenda_terrenos(j.zonas, j.direita)) then
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
  if fazenda_nivel_de(j.xp, j.nivel_trava) < i.nivel_min then raise exception 'nivel_insuficiente'; end if;
  perform fazenda_checar_lugar(v_id, fazenda_terrenos(j.zonas, j.direita), p_x, p_y, i.largura, i.altura);
  -- fase 73: o que é da praia só vai na areia do Litoral (y 32 a 36)
  if i.categoria = 'praia' and not (p_y >= 32 and p_y + i.altura - 1 <= 36) then raise exception 'so_na_areia'; end if;
  if i.limite is not null   -- fase 57: painel solar e turbina sobem com o nível
     and (select count(*) from fazenda_construcoes where jogador_id = v_id and tipo = i.id)
         >= fazenda_limite_maquina(i.id, i.limite, fazenda_nivel_de(j.xp, j.nivel_trava)) then
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

-- A visita de agora (null = já atendida, ou nível menor que 3). Tudo sai do md5 do jogador e
-- do bloco de tempo (fase 76: de 10 min; os raros, de 3 h): a mesma visita a cada carga, e outra no
-- bloco seguinte.
create or replace function public.fazenda_visitante(p_jogador uuid)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
-- fase 76: uma visita a cada 10 min (era a cada 3 h), e cada pedido é menor, para o dia não render
-- 18x mais. Os raros (mercador e Perks) continuam no bloco de 3 h, com a mesma chance de antes: ficam
-- até o fim das 3 h ou até você atender, e depois as visitas de 10 min voltam. Os pedidos crescem com o
-- nível e às vezes pedem o que o seu nível ainda não faz (feira ou chat, pagando o dobro do celeiro).
declare
  v_bloco bigint := floor(extract(epoch from now()) / 10800);   -- os raros: de 3 em 3 h
  v_hb    text := md5(p_jogador::text || ':' || floor(extract(epoch from now()) / 10800)::bigint);
  v_slot  bigint := floor(extract(epoch from now()) / 600);     -- as outras: de 10 em 10 min
  v_h     text := md5(p_jogador::text || ':' || floor(extract(epoch from now()) / 600)::bigint);
  v_tipo  text;
  v_nivel int;
  k       record;
  v_qtd   int;
  v_alvo  numeric;
  v_alvo_xp numeric;
  v_raro  text;
  v_fora  boolean := false;
  v_achou boolean := false;
  v_span  bigint;
  v_xp    int;
  v_ate   timestamptz := to_timestamp((floor(extract(epoch from now()) / 600) + 1) * 600);
begin
  select fazenda_nivel_de(xp, nivel_trava) into v_nivel from fazenda_jogadores where id = p_jogador;
  if not exists (select 1 from fazenda_visitas_npc where jogador_id = p_jogador and slot = v_bloco) then
    -- fase 66: o Perks (1 em cada 30 blocos de 3 h, do nível 3 em diante; o mercador vem antes) pede uma
    -- planta fácil em número grande e paga com luvas que passam pelo alarme do vizinho
    if ('x' || substr(v_hb, 9, 4))::bit(16)::int % 100 <> 0
       and ('x' || substr(v_hb, 17, 4))::bit(16)::int % (fazenda_perks()->>'chance')::int = 0
       and v_nivel >= (fazenda_perks()->>'nivel')::int then
      select x.p->>'id', (x.p->>'qtd')::int into v_raro, v_qtd
        from jsonb_array_elements(fazenda_perks()->'pedidos') x(p) join fazenda_culturas c on c.id = x.p->>'id'
       where c.nivel_min <= v_nivel
       order by md5(v_hb || c.id) limit 1;
      return jsonb_build_object('slot', v_bloco, 'tipo', 'perks', 'ate', to_timestamp((v_bloco + 1) * 10800),
                                'item', v_raro, 'qtd', v_qtd, 'luvas', (fazenda_perks()->>'luvas')::int, 'paga', 0, 'xp', 0);
    end if;
    -- fase 60: o mercador (1 em cada 100 blocos de 3 h, desde o nível 1) troca 1 material raro do píer
    -- por frutos fora de época (só tem quem guardou da estação dele ou plantou na estufa)
    if ('x' || substr(v_hb, 9, 4))::bit(16)::int % 100 = 0 then
      select y.r->>'id', (y.r->>'frutas')::int into v_raro, v_qtd
        from (select x.r, sum((x.r->>'peso')::int) over (order by x.ord) as acum
                from jsonb_array_elements(fazenda_raros()) with ordinality as x(r, ord)) y
       where y.acum > ('x' || substr(v_hb, 13, 4))::bit(16)::int % 100
       order by y.acum limit 1;
      -- (fase 70: só o que o seu nível já planta; no nível 1 e 2, nada fora de época: ele não vem)
      select c.* into k from fazenda_culturas c
       where c.tipo = 'cultura' and c.estacao is not null and c.estacao <> fazenda_estacao_em(now())
         and c.nivel_min <= v_nivel
       order by md5(v_hb || c.id) limit 1;
      if found then
        return jsonb_build_object('slot', v_bloco, 'tipo', 'mercador', 'ate', to_timestamp((v_bloco + 1) * 10800),
                                  'item', k.id, 'qtd', v_qtd, 'raro', v_raro, 'paga', 0, 'xp', 0);
      end if;
    end if;
  end if;
  if exists (select 1 from fazenda_visitas_npc where jogador_id = p_jogador and slot = v_slot) then return null; end if;
  if v_nivel < 3 then return null; end if;
  v_tipo := (array['feirante', 'doceira', 'caminhoneiro', 'mascate'])[1 + (('x' || substr(v_h, 1, 4))::bit(16)::int % 4)];
  if v_tipo = 'caminhoneiro' and v_nivel < 8 then v_tipo := 'feirante'; end if;
  if v_tipo = 'mascate' then   -- fase 72: o adubo cobre mais canteiros com o nível (8 + 1 a cada 3 níveis)
    return jsonb_build_object('slot', v_slot, 'tipo', v_tipo, 'ate', v_ate,
                              'canteiros', 8 + v_nivel / 3, 'preco', 40 + 10 * v_nivel);
  end if;
  -- fase 76: o tamanho do pedido sai do esforço: uns 0,25% do nível em XP de colheita (o caminhoneiro, 3x),
  -- e no mínimo o de moedas de antes, dividido pelas 18 visitas. Sempre item que dê pelo menos 2 no pedido
  -- (nada de 2 marlins no lugar de 40 sardinhas) e nada dos peixes raros da pescaria.
  v_span := fazenda_xp_nivel(least(v_nivel, 44) + 1) - fazenda_xp_nivel(least(v_nivel, 44));
  v_alvo_xp := 0.0025 * v_span * case when v_tipo = 'caminhoneiro' then 3 else 1 end;
  v_alvo := (60 + 20 * v_nivel) / 3.0 * case when v_tipo = 'caminhoneiro' then 3 else 1 end;
  -- do nível 5 em diante, de 15% a 30% das visitas (sobe com o nível) pedem o que o seu nível ainda não
  -- faz (até 8 níveis acima): só comprando na feira ou pedindo no chat
  if v_nivel >= 5 and ('x' || substr(v_h, 21, 4))::bit(16)::int % 100 < 15 + v_nivel / 3 then
    select c.* into k from fazenda_culturas c
     where c.tipo in ('cultura', 'produto') and c.venda > 0 and c.nivel_min between v_nivel + 1 and v_nivel + 8
       and (c.xp::numeric / greatest(c.rendimento, 1) <= v_alvo_xp / 2 or c.venda <= v_alvo / 2)
       and c.id not in (select f.peixe from fazenda_peixes() f where f.chance < 10)
       and c.id not in (select m->>'id' from jsonb_array_elements(fazenda_mar_tabela()) m where (m->>'peso')::int < 15)
     order by md5(v_h || c.id) limit 1;
    v_fora := found;
  end if;
  if not v_fora then
    -- a doceira quer o que seus bichos ou suas oficinas fazem; os outros, o que você planta
    if v_tipo = 'doceira' then
      select c.* into k from fazenda_culturas c
       where c.tipo = 'produto' and (   -- (fase 70: sem o "ordem < 40", que deixava de fora tudo o que veio depois da fase 21)
             c.id in (select t.produto from fazenda_animais a join fazenda_animais_tipos t on t.id = a.tipo where a.jogador_id = p_jogador)
          or c.id in (select i.produz from fazenda_construcoes x join fazenda_itens i on i.id = x.tipo
                       where x.jogador_id = p_jogador and i.entradas is not null))
         and (c.xp::numeric / greatest(c.rendimento, 1) <= v_alvo_xp / 2 or c.venda <= v_alvo / 2)
       order by md5(v_h || c.id) limit 1;
      if not found then v_tipo := 'feirante'; end if;
    end if;
    if v_tipo <> 'doceira' then
      -- do nível 15 em diante, metade das vezes pede um produto (de oficina, bicho, pomar...) do seu
      -- nível, não só semente
      if v_nivel >= 15 and ('x' || substr(v_h, 25, 4))::bit(16)::int % 2 = 0 then
        select c.* into k from fazenda_culturas c
         where c.tipo = 'produto' and c.venda > 0 and c.nivel_min between greatest(1, v_nivel - 12) and v_nivel
           and (c.xp::numeric / greatest(c.rendimento, 1) <= v_alvo_xp / 2 or c.venda <= v_alvo / 2)
           and c.id not in (select f.peixe from fazenda_peixes() f where f.chance < 10)
           and c.id not in (select m->>'id' from jsonb_array_elements(fazenda_mar_tabela()) m where (m->>'peso')::int < 15)
         order by md5(v_h || c.id) limit 1;
        v_achou := found;
      end if;
      if not v_achou then   -- uma das 5 melhores sementes que você já tem (nada de 70 alfaces no nível 20)
        select x.* into k from (
          select c.* from fazenda_culturas c
           where c.tipo = 'cultura' and c.nivel_min <= v_nivel and (c.estacao is null or c.estacao = fazenda_estacao_em(now()))
           order by c.nivel_min desc limit 5) x
         order by md5(v_h || x.id) limit 1;
      end if;
    end if;
  end if;
  v_qtd := greatest(2, least(200, round(greatest(v_alvo_xp / greatest(k.xp::numeric / greatest(k.rendimento, 1), 0.1),
                                                 v_alvo / k.venda))::int));
  -- XP de quanto você ganharia colhendo isso (o fora do nível, o triplo; o caminhoneiro já leva 3x mais),
  -- de 0,1% a 1% do nível (fase 76: são 18 visitas no lugar de cada uma de antes)
  v_xp := least(ceil(0.01 * v_span)::int,
                greatest(1, v_qtd * k.xp / greatest(k.rendimento, 1), ceil(0.001 * v_span)::int)
                * case when v_fora then 3 else 1 end);
  return jsonb_build_object('slot', v_slot, 'tipo', v_tipo, 'ate', v_ate,
    'item', k.id, 'qtd', v_qtd,
    'paga', round(v_qtd * k.venda * case when v_fora then 2.0 when v_tipo = 'feirante' then 1.5 when v_tipo = 'doceira' then 1.6 else 1.4 end)::int,
    'xp', v_xp,
    'fora_nivel', v_fora, 'nivel_item', k.nivel_min);
end;
$$;

-- XP em dobro: todo XP que entra enquanto vale (colher, bichos, vender, missões...) vem dobrado.
-- O pacote de XP liga fazenda.xp_puro para não dobrar.
-- Fase 49: e +50% com as metas de nível em dia (bonus_nivel = o nível de agora); os dois somam
create or replace function public.fazenda_xp_dobro()
returns trigger language plpgsql set search_path = public as $$
declare
  v_mult real := 1;
begin
  if new.xp > old.xp and coalesce(current_setting('fazenda.xp_puro', true), '') <> '1' then
    if new.xp2_ate is not null and new.xp2_ate > now() then v_mult := v_mult + 1; end if;
    if new.bonus_nivel is not null and new.bonus_nivel = fazenda_nivel_de(old.xp, old.nivel_trava) then v_mult := v_mult + 0.5; end if;
    -- fase 57: fazenda completa (do 20 em diante, metas em dia): mais 25%
    if new.bonus_nivel is not null and new.bonus_nivel = fazenda_nivel_de(old.xp, old.nivel_trava) and fazenda_nivel_de(old.xp, old.nivel_trava) >= 20 then v_mult := v_mult + 0.25; end if;
    -- fase 70: a metade a mais do XP em dobro é XP comprado (não conta no evento)
    if new.xp2_ate is not null and new.xp2_ate > now() then new.xp_pago := new.xp_pago + (new.xp - old.xp); end if;
    if v_mult > 1 then new.xp := old.xp + round((new.xp - old.xp) * v_mult)::int; end if;
  end if;
  -- fase 70: pacote de XP e XP do calendário dourado: tudo comprado
  if new.xp > old.xp and coalesce(current_setting('fazenda.xp_pago', true), '') = '1' then
    new.xp_pago := old.xp_pago + (new.xp - old.xp);
  end if;
  return new;
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

-- Fase 51: compra mais uma barraca na feira (do nível 5 em diante, até 4): 800, 1600 e 2400 moedas
create or replace function public.fazenda_feira_barraca(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_r     jsonb := fazenda_feira_regras();
  j       record;
  v_preco int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  if j.barracas >= (v_r->>'barracas_max')::int then raise exception 'limite_barracas'; end if;
  if fazenda_nivel_de(j.xp, j.nivel_trava) < (v_r->>'barraca_nivel')::int then raise exception 'nivel_insuficiente'; end if;
  v_preco := (v_r->'barraca_precos'->>(j.barracas - 1))::int;
  if j.moedas < v_preco then raise exception 'moedas_insuficientes'; end if;
  update fazenda_jogadores set moedas = moedas - v_preco, barracas = barracas + 1 where id = v_id;
  return jsonb_build_object('barracas', j.barracas + 1, 'estado', fazenda_estado(v_id));
end;
$$;

-- a lista para o painel: sem busca, os banidos primeiro e depois os mais novos; com busca, pelo apelido
create or replace function public.fazenda_admin_jogadores(p_token text, p_busca text default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_admin_id(p_token);
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  return jsonb_build_object(
    'total', (select count(*) from fazenda_jogadores),
    'banidos', (select count(*) from fazenda_jogadores where banido_em is not null),
    'jogadores', coalesce((select jsonb_agg(jsonb_build_object(
        'id', j.id, 'apelido', j.apelido, 'avatar', j.avatar, 'nivel', fazenda_nivel_de(j.xp, j.nivel_trava),
        'criado_em', j.criado_em, 'visto_em', j.visto_em, 'admin', j.admin,
        'banido_em', j.banido_em, 'banido_motivo', j.banido_motivo, 'eu', j.id = v_id) order by j.ordem)
      from (select k.*, row_number() over (order by
                     case when v_busca is null then (k.banido_em is null)::int end,
                     case when v_busca is not null then -k.xp end,
                     k.criado_em desc) as ordem
              from fazenda_jogadores k
             where v_busca is null
                or k.apelido ilike '%' || replace(replace(replace(v_busca, '\', '\\'), '%', '\%'), '_', '\_') || '%'
             order by ordem limit 60) j), '[]'::jsonb),
    'log', coalesce((select jsonb_agg(jsonb_build_object(
        'acao', l.acao, 'motivo', l.motivo, 'em', l.em,
        'admin', (select apelido from fazenda_jogadores where id = l.admin_id),
        'alvo', (select apelido from fazenda_jogadores where id = l.alvo_id)) order by l.em desc)
      from (select * from fazenda_admin_log order by em desc limit 20) l), '[]'::jsonb)
  );
end;
$$;

-- fazenda completa = do nível 20 em diante, com as metas do nível em dia (fase 49: bonus_nivel)
create or replace function public.fazenda_completa(p_jogador uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select fazenda_nivel_de(j.xp, j.nivel_trava) >= 20 and j.bonus_nivel = fazenda_nivel_de(j.xp, j.nivel_trava)
                     from fazenda_jogadores j where j.id = p_jogador), false);
$$;

create or replace function public.fazenda_construir_pier(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  v_r  jsonb := fazenda_pier_receita();
  j    record;
  k    text;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  if j.pier_em is not null then raise exception 'pier_pronto'; end if;
  if fazenda_nivel_de(j.xp, j.nivel_trava) < (v_r->>'nivel')::int then raise exception 'nivel_insuficiente'; end if;
  if j.zonas < (v_r->>'zona')::int then raise exception 'sem_litoral'; end if;
  if exists (select 1 from jsonb_object_keys(v_r->'itens') i where fazenda_pier_falta(v_id, i) > 0) then
    raise exception 'faltam_pecas';
  end if;
  if j.moedas < (v_r->>'moedas')::int then raise exception 'moedas_insuficientes'; end if;
  for k in select jsonb_object_keys(v_r->'itens') loop
    update fazenda_celeiro set quantidade = quantidade - (v_r->'itens'->>k)::int where jogador_id = v_id and item = k;
    -- o que estava guardado para o píer sai junto (a reserva não pode passar do que sobrou nem ficar zerada)
    delete from fazenda_reservas r using fazenda_celeiro c
     where r.jogador_id = v_id and r.item = k and c.jogador_id = v_id and c.item = k and c.quantidade <= 0;
    update fazenda_reservas r set quantidade = c.quantidade
      from fazenda_celeiro c where r.jogador_id = v_id and r.item = k and c.jogador_id = v_id and c.item = k and r.quantidade > c.quantidade;
  end loop;
  update fazenda_jogadores set moedas = moedas - (v_r->>'moedas')::int, pier_em = now() where id = v_id;
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- os números de cada jogador numa semana (p_semana = o início dela; conta de p_desde a p_ate).
-- Quem entrou na semana não tem foto: conta do zero. Quem foi banido não entra.
create or replace function public.fazenda_semana_placar(p_semana timestamptz, p_desde timestamptz, p_ate timestamptz)
returns table (jogador_id uuid, apelido text, avatar jsonb, criado_em timestamptz, ranking bigint, niveis bigint,
               moedas bigint, vendeu bigint, comprou bigint, convites bigint)
language sql stable security definer set search_path = public as $$
  -- fase 70: o XP comprado com diamante não conta (ranking e níveis); na barraca, uma mesma pessoa do
  -- outro lado conta no máximo 25% do total (duas contas vendendo uma para a outra não ganham sozinhas)
  select j.id, j.apelido, j.avatar, j.criado_em,
         (j.xp - coalesce(b.xp, 0) - (j.xp_pago - coalesce(b.xp_pago, 0)))::bigint,
         (fazenda_nivel((j.xp - (j.xp_pago - coalesce(b.xp_pago, 0)))::int) - fazenda_nivel(coalesce(b.xp, 0)))::bigint,
         (j.moedas_ganhas - coalesce(b.moedas_ganhas, 0))::bigint,
         coalesce((select sum(least(t.v, ceil(t.total * 0.25))) from (
                    select sum(f.qtd::bigint * f.preco) as v, sum(sum(f.qtd::bigint * f.preco)) over () as total from fazenda_feira f
                     where f.vendedor_id = j.id and f.vendido_em >= p_desde and f.vendido_em < p_ate group by f.comprador_id) t), 0)::bigint,
         coalesce((select sum(least(t.v, ceil(t.total * 0.25))) from (
                    select sum(f.qtd::bigint * f.preco) as v, sum(sum(f.qtd::bigint * f.preco)) over () as total from fazenda_feira f
                     where f.comprador_id = j.id and f.vendido_em >= p_desde and f.vendido_em < p_ate group by f.vendedor_id) t), 0)::bigint,
         (select count(*) from fazenda_convites c join fazenda_jogadores a on a.id = c.convidado_id
           where c.dono_id = j.id and c.criado_em >= p_desde and c.criado_em < p_ate and a.banido_em is null
             and fazenda_nivel_de(a.xp, a.nivel_trava) >= (fazenda_evento_regras()->>'convite_nivel')::int)::bigint
    from fazenda_jogadores j
    left join fazenda_semana_base b on b.jogador_id = j.id and b.semana = p_semana
   where j.banido_em is null
     -- fase 71: só quem jogou na semana (visto_em, com 1 h de folga), vendeu ou comprou na feira ou trouxe
     -- convite nela: quem não jogou tem tudo zerado (e o placar de todos pesava no fechamento e no Evento)
     and (j.visto_em >= p_desde - interval '1 hour'
          or exists (select 1 from fazenda_feira f
                      where (f.vendedor_id = j.id or f.comprador_id = j.id) and f.vendido_em >= p_desde and f.vendido_em < p_ate)
          or exists (select 1 from fazenda_convites c where c.dono_id = j.id and c.criado_em >= p_desde and c.criado_em < p_ate));
$$;

-- A conversa da última hora (as 80 mais novas, sem as apagadas e sem as de banidos). Com p_depois, só as
-- novas, os ids que sumiram (apagados) e quem atendeu os pedidos (para a busca de 5 em 5 s ficar leve).
create or replace function public.fazenda_chat(p_token text, p_depois bigint default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth_ler(p_token);   -- fase 71: só lê, sem a fila de uma por vez
  v_r  jsonb := fazenda_chat_regras();
  v_de timestamptz := now() - make_interval(mins => (v_r->>'minutos')::int);
  j    record;
begin
  select fazenda_nivel_de(xp, nivel_trava) as nivel, admin into j from fazenda_jogadores where id = v_id;
  return jsonb_build_object(
    'regras', v_r,
    'pode_escrever', j.nivel >= (v_r->>'nivel')::int,
    'admin', j.admin is not null,
    'mensagens', coalesce((
      select jsonb_agg(m order by (m->>'id')::bigint) from (
        select jsonb_build_object('id', c.id, 'jogador', c.jogador_id, 'apelido', p.apelido, 'avatar', p.avatar,
                 'nivel', fazenda_nivel_de(p.xp, p.nivel_trava), 'admin', p.admin, 'texto', c.texto, 'em', c.criado_em,
                 'pedido', case when c.item is not null then jsonb_build_object('item', c.item, 'qtd', c.qtd, 'preco', c.preco) end) as m
          from fazenda_chat c join fazenda_jogadores p on p.id = c.jogador_id
         where c.criado_em >= v_de and c.apagado_em is null and p.banido_em is null
           and (p_depois is null or c.id > p_depois)
         order by c.id desc
         limit (v_r->>'mostrar')::int) x), '[]'::jsonb),
    'apagadas', case when p_depois is null then '[]'::jsonb else coalesce((
      select jsonb_agg(c.id) from fazenda_chat c join fazenda_jogadores p on p.id = c.jogador_id
       where c.criado_em >= v_de and c.id <= p_depois and (c.apagado_em is not null or p.banido_em is not null)), '[]'::jsonb) end,
    'atendidos', coalesce((
      select jsonb_object_agg(x.pedido_id::text, x.quem) from (
        select f.pedido_id, jsonb_agg(jsonb_build_object('apelido', vj.apelido, 'qtd', f.qtd) order by f.id) as quem
          from fazenda_feira f join fazenda_jogadores vj on vj.id = f.vendedor_id
          join fazenda_chat c on c.id = f.pedido_id
         where c.criado_em >= v_de
         group by f.pedido_id) x), '{}'::jsonb));
end;
$$;

create or replace function public.fazenda_chat_enviar(p_token text, p_texto text, p_item text default null,
                                                     p_qtd int default null, p_preco int default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_r     jsonb := fazenda_chat_regras();
  v_texto text;
  v_faixa int[];
  u       record;
  v_n     int;
  v_ped   int;
  v_novo  bigint;
begin
  -- o que passou de 60 min some de vez: a tabela nunca guarda mais de 1 hora de conversa
  delete from fazenda_chat where criado_em < now() - make_interval(mins => (v_r->>'minutos')::int);
  if (select fazenda_nivel_de(xp, nivel_trava) from fazenda_jogadores where id = v_id) < (v_r->>'nivel')::int then raise exception 'chat_nivel'; end if;
  v_texto := fazenda_chat_texto(p_texto);
  if p_item is null and v_texto = '' then raise exception 'chat_vazio'; end if;
  if p_item is not null then
    v_faixa := fazenda_feira_faixa(p_item);
    if v_faixa is null then raise exception 'item_invalido'; end if;
    if p_qtd is null or p_qtd < 1 or p_qtd > (fazenda_feira_regras()->>'qtd_max')::int then raise exception 'quantidade_invalida'; end if;
    if p_preco is null or p_preco < v_faixa[1] or p_preco > v_faixa[2] then raise exception 'preco_invalido'; end if;
  end if;
  perform pg_advisory_xact_lock(hashtext('fazenda_chat:' || v_id::text));   -- dois envios juntos não furam o limite
  select texto, item, criado_em into u from fazenda_chat where jogador_id = v_id order by id desc limit 1;
  if found and u.criado_em > now() - make_interval(secs => (v_r->>'intervalo')::int) then raise exception 'chat_rapido'; end if;
  if found and p_item is null and u.item is null and lower(u.texto) = lower(v_texto) then raise exception 'chat_repetida'; end if;
  select count(*), count(item) into v_n, v_ped from fazenda_chat where jogador_id = v_id and criado_em > now() - interval '1 hour';
  if v_n >= (v_r->>'por_hora')::int or (p_item is not null and v_ped >= (v_r->>'pedidos_hora')::int) then
    raise exception 'chat_limite';
  end if;
  insert into fazenda_chat (jogador_id, texto, item, qtd, preco)
  values (v_id, v_texto, p_item, case when p_item is not null then p_qtd end, case when p_item is not null then p_preco end)
  returning id into v_novo;
  return jsonb_build_object('id', v_novo);
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
  if v_tipo in ('xp', 'xp2') and v_nivel >= 45 then v_tipo := 'moedas'; v_qtd := 50; end if;   -- no último nível, XP não serve
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

-- o robô consegue plantar essa semente nesse canteiro? (as checagens de fazenda_aplicar: arado,
-- nível, moedas e a estação ou uma estufa por perto)
create or replace function public.fazenda_bot_pode_plantar(p_jogador uuid, p_cultura text, p_posicao int)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select c.estado = 'arado' and k.tipo = 'cultura' and fazenda_nivel_de(j.xp, j.nivel_trava) >= k.nivel_min and j.moedas >= k.custo
           and (k.estacao is null or k.estacao = fazenda_estacao_em(now()) or fazenda_protegido(p_jogador, 'estufa', c.x, c.y))
      from fazenda_canteiros c, fazenda_culturas k, fazenda_jogadores j
     where c.jogador_id = p_jogador and c.posicao = p_posicao and k.id = p_cultura and j.id = p_jogador), false);
$$;

-- abre um baú da sorte: paga, sorteia e entrega. Os prêmios (fase 74b: nunca moedas):
--   raro (o mais caro, mais difícil: peso 1 / preço) · diamantes · e o resto, itens que o seu nível já tem
--   (de 15% a 75% do preço, pelo preço do celeiro)
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
  if fazenda_nivel_de(j.xp, j.nivel_trava) < (v_b->>'nivel')::int then raise exception 'nivel_insuficiente'; end if;
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
  elsif v_r < v_lim + (v_b->>'chance_diamantes')::float8 then
    v_tipo := 'diamantes';
    v_diam := (v_b->'diamantes'->>0)::int + floor(random() * ((v_b->'diamantes'->>1)::int - (v_b->'diamantes'->>0)::int + 1))::int;
  else
    v_tipo := 'itens';
    select c.* into k from fazenda_culturas c
     where c.tipo in ('cultura', 'produto') and c.venda > 0 and c.nivel_min <= fazenda_nivel_de(j.xp, j.nivel_trava)
     order by random() limit 1;
    v_item := k.id;
    v_qtd := greatest(1, round(v_preco * (0.15 + random() * 0.6) / k.venda))::int;
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

-- permissões
revoke execute on function
  public.fazenda_nivel_de(int, int),
  public.fazenda_conta_nivel(text, text),
  public.fazenda_nivel_trava(uuid),
  public.fazenda_nivel_faltam(uuid, int),
  public.fazenda_trava_gatilho(),
  public.fazenda_regra_nivel_aplicar()
from public, anon, authenticated;

grant execute on function
  public.fazenda_ranking(text),
  public.fazenda_chat(text, bigint)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- a média dos geradores já pronta (as chamadas do jogo não montam mais na hora)
select public.fazenda_energia_medias_refazer() is not null as energia_medias_pronta;

-- o dia da regra: guarda o nível de cada um (ninguém cai; rodar de novo não muda nada)
select public.fazenda_regra_nivel_aplicar() as jogadores_com_base;

-- conferência: deve aparecer "Fase 90: só passa de nível quem tem tudo dos seus níveis"
select 'Fase 90: só passa de nível quem tem tudo dos seus níveis' as ok where exists (select 1 from pg_proc where proname = 'fazenda_nivel_trava');
