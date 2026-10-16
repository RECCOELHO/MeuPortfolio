-- ============================================================
-- FAZENDINHA — Fase 61 (etapa 5A: o litoral e o píer), só o que mudou.
-- Para o banco que já está no ar (com a fase 60): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- o terreno 7 (Litoral) e o mar fora do lugar de construir

create or replace function public.fazenda_zonas()
returns jsonb language sql immutable as $$
  select '[{"n":1,"nome":"Campo do sul","x":0,"y":13,"w":22,"h":7,"custo":500,"nivel":4,"canteiros":6},
           {"n":2,"nome":"Mata do leste","x":22,"y":0,"w":10,"h":13,"custo":1500,"nivel":7,"canteiros":6},
           {"n":3,"nome":"Vale do sudeste","x":22,"y":13,"w":10,"h":7,"custo":3500,"nivel":10,"lago":true,"canteiros":6},
           {"n":4,"nome":"Chapada do leste","x":32,"y":0,"w":16,"h":20,"custo":8000,"nivel":13,"canteiros":10},
           {"n":5,"nome":"Várzea do sul","x":0,"y":20,"w":32,"h":12,"custo":18000,"nivel":16,"canteiros":12},
           {"n":6,"nome":"Sertão do sudeste","x":32,"y":20,"w":16,"h":12,"custo":35000,"nivel":20,"canteiros":10},
           {"n":7,"nome":"Litoral","x":0,"y":32,"w":48,"h":10,"custo":300000,"nivel":31,"canteiros":10,"mar":true}]'::jsonb;   -- fase 61
$$;

create or replace function public.fazenda_livre(p_x int, p_y int)
returns boolean language sql immutable as $$
  select p_x between 0 and 47 and p_y between 0 and 36            -- fase 61: o litoral vai até a areia (y 36)
     and not (p_x between 1 and 3  and p_y between 1 and 6)     -- celeiro
     and not (p_x between 5 and 7  and p_y between 1 and 3)     -- casa
     and not (p_x between 24 and 29 and p_y between 14 and 18)  -- lago
     and not (p_x between 22 and 24 and p_y between 35 and 36); -- fase 61: o lugar do píer (o resto dele é no mar, y 37 a 41)
$$;

-- ------------------------------------------------------------
-- Fase 61: o litoral e o píer (ideias de 15/10, etapa 5A).
-- • Terreno 7, Litoral (nível 31, 300 mil): uma faixa ao sul, 48 x 10. As 5 fileiras de cima (y 32 a
--   36) são areia, para construir e plantar; as 5 de baixo (y 37 a 41) são mar (fazenda_livre).
-- • O píer: um lugar fixo na areia (x 22 a 24, y 35 e 36) que entra pelo mar. Receita: 9 peças
--   difíceis (5 do mercador, o peixe do Velho Chico do lago e o leme dourado, que só o ranking da
--   semana dá, etapa 6) e 100 mil moedas. Peça que falta dá para comprar com diamantes, caro, só até
--   completar a receita (fazenda_pier_comprar_peca). Depois do píer vem o alto-mar (etapa 5B).
-- • O peixe do Velho Chico continua vendendo no celeiro; na feira passa a ter preço de peça (50 a 150
--   mil), e dá para guardar para o píer (fazenda_reservar, o mesmo da ração dos bichos).
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists pier_em timestamptz;   -- quando o píer ficou pronto
alter table public.fazenda_jogadores drop constraint if exists fazenda_jogadores_zonas_check;
alter table public.fazenda_jogadores add constraint fazenda_jogadores_zonas_check check (zonas between 0 and 7);   -- o 7º terreno

insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('leme_dourado', 'Leme dourado', '☸️', 1, 0, 250000, 1, 0, 1, 95, 'raro')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, venda = excluded.venda, xp = excluded.xp,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;

-- a receita do píer, o preço em diamantes de cada peça que falta e o preço de peça na feira
create or replace function public.fazenda_pier_receita()
returns jsonb language sql immutable as $$
  select '{"nivel": 31, "zona": 7, "moedas": 100000,
           "itens": {"madeira_nobre": 2, "corda_naval": 2, "pedra_cantaria": 1, "ferro_forjado": 1, "ancora": 1,
                     "velho_chico": 1, "leme_dourado": 1},
           "diamantes": {"madeira_nobre": 80, "corda_naval": 90, "pedra_cantaria": 110, "ferro_forjado": 140,
                         "ancora": 200, "velho_chico": 60, "leme_dourado": 250},
           "feira": {"velho_chico": 50000}}'::jsonb;
$$;

-- a faixa da feira, agora com o preço de peça do peixe do Velho Chico (fase 61)
create or replace function public.fazenda_feira_faixa(p_item text)
returns int[] language sql stable security definer set search_path = public as $$
  select case when k.tipo = 'raro'   -- fase 60: material raro vai de venda (o mínimo) até o triplo
              then array[k.venda, k.venda * 3]
              -- fase 61: peça do píer que também vende no celeiro (o peixe do Velho Chico): preço de peça
              when fazenda_pier_receita()->'feira' ? k.id
              then array[(fazenda_pier_receita()->'feira'->>k.id)::int, (fazenda_pier_receita()->'feira'->>k.id)::int * 3]
              else array[greatest(1, floor(k.venda * (fazenda_feira_regras()->>'min')::numeric))::int,
                         greatest(1, ceil(k.venda * (fazenda_feira_regras()->>'max')::numeric))::int] end
    from fazenda_culturas k where k.id = p_item and k.venda > 0;
$$;

-- quanto falta de uma peça (o guardado conta: guardar é justamente para o píer)
create or replace function public.fazenda_pier_falta(p_jogador uuid, p_item text)
returns int language sql stable security definer set search_path = public as $$
  select greatest(coalesce((fazenda_pier_receita()->'itens'->>p_item)::int, 0)
                  - coalesce((select quantidade from fazenda_celeiro where jogador_id = p_jogador and item = p_item), 0), 0);
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
  if fazenda_nivel(j.xp) < (v_r->>'nivel')::int then raise exception 'nivel_insuficiente'; end if;
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

-- peça que falta, comprada com diamantes (caro), só até completar a receita
create or replace function public.fazenda_pier_comprar_peca(p_token text, p_item text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_r     jsonb := fazenda_pier_receita();
  v_preco int := (v_r->'diamantes'->>p_item)::int;
  j       record;
begin
  if v_preco is null then raise exception 'item_invalido'; end if;
  select * into j from fazenda_jogadores where id = v_id for update;
  if j.pier_em is not null then raise exception 'pier_pronto'; end if;
  if j.zonas < (v_r->>'zona')::int then raise exception 'sem_litoral'; end if;
  if fazenda_pier_falta(v_id, p_item) <= 0 then raise exception 'peca_nao_falta'; end if;
  if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
  update fazenda_jogadores set diamantes = diamantes - v_preco where id = v_id;
  insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, 'pier:' || p_item, v_preco);
  insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, p_item, 1)
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- o jogo recebe o píer (pronto ou não, e a receita)

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
  v_clima jsonb := fazenda_clima_previsao(now());
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
  v_nivel := fazenda_nivel(j.xp);
  -- subiu de nível: presente de moedas e 5 diamantes por cada nível novo
  if v_nivel > coalesce(j.nivel_premiado, 1) then
    update fazenda_jogadores
       set moedas = moedas + (select sum(fazenda_presente_nivel(n)) from generate_series(coalesce(j.nivel_premiado, 1) + 1, v_nivel) n),
           diamantes = diamantes + 5 * (v_nivel - coalesce(j.nivel_premiado, 1)),
           nivel_premiado = v_nivel
     where id = p_jogador;
    select * into j from fazenda_jogadores where id = p_jogador;
  end if;
  -- canteiros não aparecem mais sozinhos: o jogador coloca no modo construir até este limite
  v_max := fazenda_limite_canteiros(v_nivel, j.zonas);
  -- fase 49: as metas de nível; com todas em dia, o bônus de XP vale neste nível (só grava se mudou)
  v_metas := fazenda_metas(p_jogador, v_nivel);
  v_bonus := case when v_nivel < 30 and not exists (select 1 from jsonb_array_elements(v_metas) m where not (m->>'feito')::boolean)
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
                          'ate', f.criado_em + make_interval(hours => (fazenda_feira_regras()->>'horas')::int)) order by f.id)
                          from fazenda_feira f where f.vendedor_id = p_jogador and f.vendido_em is null), '[]'::jsonb),
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
      'vento', fazenda_vento_previsao(now()),
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
               'cultura', d.cultura, 'qtd', d.qtd, 'em', d.criado_em)
             order by d.criado_em desc)
        from (
          select v.tipo, v.ator_id, a.apelido, v.cultura, v.qtd, v.criado_em
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
    'culturas', (
      select jsonb_agg(jsonb_build_object(
               'id', id, 'nome', nome, 'emoji', emoji, 'tempo_seg', tempo_seg,
               'custo', custo, 'venda', venda, 'rendimento', rendimento,
               'xp', xp, 'nivel_min', nivel_min, 'tipo', tipo, 'estacao', estacao)
             order by ordem)
        from fazenda_culturas),
    'animais', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'alimentado_em', alimentado_em) order by id)
        from fazenda_animais where jogador_id = p_jogador), '[]'::jsonb),
    'animais_tipos', (
      select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_animais_tipos t),
    'construcoes', coalesce((
      select jsonb_agg(jsonb_build_object('x', x, 'y', y, 'tipo', tipo, 'colhido_em', colhido_em, 'iniciado_em', iniciado_em,
                                          'estoque', estoque, 'prontos', prontos))
        from fazenda_construcoes where jogador_id = p_jogador), '[]'::jsonb),
    'estoque_max', fazenda_estoque_max(),
    'itens', (   -- fase 57: o limite que vale para o nível de agora
      select jsonb_agg(to_jsonb(t) || jsonb_build_object('limite', fazenda_limite_maquina(t.id, t.limite, v_nivel)) order by t.ordem)
        from fazenda_itens t),
    'melhorias', coalesce((select jsonb_object_agg(id, nivel) from fazenda_melhorias where jogador_id = p_jogador), '{}'::jsonb),
    'camas', jsonb_build_object('total', fazenda_camas(p_jogador), 'ocupadas', fazenda_camas_ocupadas(p_jogador)),   -- fase 59
    'pier', jsonb_build_object('pronto', j.pier_em is not null, 'receita', fazenda_pier_receita()),   -- fase 61
    'melhorias_tipos', fazenda_melhorias_tipos(),
    'estatisticas', (select to_jsonb(e) - 'jogador_id' || jsonb_build_object('energia', e.energia + floor(j.energia_gasta)::int)
                       from fazenda_estatisticas e where e.jogador_id = p_jogador),
    'conquistas', coalesce((
      select jsonb_agg(jsonb_build_object('id', conquista, 'em', obtida_em) order by obtida_em)
        from fazenda_conquistas where jogador_id = p_jogador), '[]'::jsonb),
    'conquistas_tipos', (
      select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_conquistas_tipos t),
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
    'ajudantes_tipos', (
      select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_ajudantes_tipos t)
  );
  -- o relatório (o que fizeram enquanto você estava fora) aparece uma vez só
  update fazenda_ajudantes set relatorio = 0 where jogador_id = p_jogador and relatorio > 0;
  update fazenda_convites set visto = true where dono_id = p_jogador and not visto;   -- idem os amigos novos
  update fazenda_feira set visto = true where vendedor_id = p_jogador and vendido_em is not null and not visto;   -- e as vendas da feira
  return v_json;
end;
$$;

revoke execute on function
  public.fazenda_pier_receita(),
  public.fazenda_pier_falta(uuid, text)
from public, anon, authenticated;
grant execute on function public.fazenda_construir_pier(text), public.fazenda_pier_comprar_peca(text, text) to anon, authenticated;

-- conferência: deve aparecer "Litoral: 300000 moedas no nível 31; peixe do Chico na feira de 50000 a 150000"
select 'Litoral: ' || (z->>'custo') || ' moedas no nível ' || (z->>'nivel') || '; peixe do Chico na feira de '
    || (public.fazenda_feira_faixa('velho_chico'))[1] || ' a ' || (public.fazenda_feira_faixa('velho_chico'))[2] as ok
  from jsonb_array_elements(public.fazenda_zonas()) z where (z->>'n')::int = 7;
