-- ============================================================
-- FAZENDINHA — Fase 84 (a loja de raros e os vales do calendário),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 83): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 83 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_roca_um')) then
    raise exception 'Rode o fase83.sql antes deste (a fase 83 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 84: a loja de raros (D9) e os vales do calendário (D10).
-- • Loja → Diamantes vende os materiais do píer e do barco a 1 💎 a cada 10 mil do preço, até 2 compras
--   por semana (fazenda_comprar_raro; a semana vira na segunda, em Brasília).
-- • O café e o XP em dobro do calendário viram vales guardados (fazenda_vales), ligados quando o jogador
--   quiser (fazenda_usar_vale); com ele já ligado, soma o tempo.
-- ------------------------------------------------------------
create table if not exists public.fazenda_vales (
  id         bigserial primary key,
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  tipo       text not null check (tipo in ('cafe', 'xp2')),
  minutos    int  not null,
  criado_em  timestamptz not null default now()
);
create index if not exists fazenda_vales_jogador on public.fazenda_vales (jogador_id);
alter table public.fazenda_vales enable row level security;
revoke all on public.fazenda_vales from anon, authenticated;
revoke all on sequence public.fazenda_vales_id_seq from anon, authenticated;

-- as funções que já existiam e mudaram

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
           "agora": {"horas": 4},
           "moedas": {"preco": 10, "por_nivel": 2000},
           "raros": {"por": 10000, "por_semana": 2,
                     "itens": ["madeira_nobre", "corda_naval", "pedra_cantaria", "ferro_forjado", "ancora", "leme_dourado", "perola_negra", "luva_perks"]}}'::jsonb;   -- fase 84: a loja de raros   -- fase 79: 10 diamantes = 2.000 moedas por nível
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
  select fazenda_nivel(xp) into v_nivel from fazenda_jogadores where id = p_jogador;
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

-- O calendário como o jogo mostra: o ciclo, quantos dias já foram, se dá para resgatar hoje e se a
-- trilha dourada está liberada. Ciclo acabado e já é outro dia: mostra o ciclo novo (o resgate começa ele).
create or replace function public.fazenda_calendario_estado(p_jogador uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  r      record;
  v_pode boolean;
  v_dias int := (fazenda_calendario_regras()->>'dias')::int;
  v_ciclo int := 1;
  v_dia   int := 0;
begin
  select * into r from fazenda_calendario where jogador_id = p_jogador;
  v_pode := r.ultimo is null or r.ultimo < fazenda_hoje();
  if found then v_ciclo := r.ciclo; v_dia := r.dia; end if;
  if v_dia >= v_dias and v_pode then v_ciclo := v_ciclo + 1; v_dia := 0; end if;
  return jsonb_build_object('ciclo', v_ciclo, 'dia', v_dia, 'pode', v_pode,
                            'dourado', coalesce(r.dourado_ciclo = v_ciclo, false),
                            'regras', fazenda_calendario_regras(), 'premios', fazenda_calendario_premios(),
                            'vales', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'tipo', v.tipo, 'minutos', v.minutos) order by v.id)
                                                 from fazenda_vales v where v.jogador_id = p_jogador), '[]'::jsonb));
end;
$$;

-- fase 84 (D10): usa um vale (o café ou o XP em dobro guardado); com ele já ligado, soma o tempo
create or replace function public.fazenda_usar_vale(p_token text, p_vale bigint)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  v    record;
  g    jsonb;
begin
  select * into v from fazenda_vales where id = p_vale and jogador_id = v_id for update;
  if not found then raise exception 'vale_invalido'; end if;
  if v.tipo = 'cafe' and not exists (select 1 from fazenda_ajudantes where jogador_id = v_id) then raise exception 'sem_ajudantes'; end if;
  delete from fazenda_vales where id = p_vale;
  g := fazenda_calendario_dar(v_id, jsonb_build_object('tipo', v.tipo, 'qtd', v.minutos, 'usar', true));
  return jsonb_build_object('ganho', g, 'estado', fazenda_estado(v_id));
end;
$$;

-- fase 84 (D9): quantas compras na loja de raros esta semana (a semana vira na segunda, em Brasília)
create or replace function public.fazenda_raros_semana(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from fazenda_diamantes_usos
   where jogador_id = p_jogador and item like 'raro:%'
     and em >= (date_trunc('week', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo');
$$;

-- fase 84 (D9): compra 1 material raro com diamantes (1 💎 a cada 10 mil do preço de venda), até 2 por semana
create or replace function public.fazenda_comprar_raro(p_token text, p_item text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_l     jsonb := fazenda_loja_diamantes()->'raros';
  v_preco int;
begin
  if v_l is null or not (v_l->'itens' ? p_item) then raise exception 'item_invalido'; end if;
  perform 1 from fazenda_jogadores where id = v_id for update;   -- (dois toques juntos: um só passa)
  if fazenda_raros_semana(v_id) >= (v_l->>'por_semana')::int then raise exception 'limite_semana'; end if;
  select ceil(venda / (v_l->>'por')::numeric)::int into v_preco from fazenda_culturas where id = p_item;
  if v_preco is null then raise exception 'item_invalido'; end if;
  if (select diamantes from fazenda_jogadores where id = v_id) < v_preco then raise exception 'diamantes_insuficientes'; end if;
  update fazenda_jogadores set diamantes = diamantes - v_preco where id = v_id;
  insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, p_item, 1)
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
  insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, 'raro:' || p_item, v_preco);
  return jsonb_build_object('item', p_item, 'diamantes', v_preco, 'estado', fazenda_estado(v_id));
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
    'estoque_max', fazenda_estoque_max_de(p_jogador),   -- fase 82: 15 com a fila de diamante
    -- fase 83: o alarme sem energia (o total de segundos desligado) e o resumo dos últimos 7 dias do
    -- que os vizinhos fizeram aqui (o jogo mostra o que é novo desde a última vez)
    'social', jsonb_build_object(   -- (fase 83: num objeto só: o estado chegou no limite de 100 argumentos)
      'alarme_off', jsonb_build_object('seg', j.alarme_off_seg, 'em', j.alarme_off_em),
      'raros_semana', fazenda_raros_semana(p_jogador),   -- fase 84
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

-- permissões
revoke execute on function
  public.fazenda_raros_semana(uuid)
from public, anon, authenticated;

grant execute on function
  public.fazenda_comprar_raro(text, text),
  public.fazenda_usar_vale(text, bigint)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- conferência: deve aparecer "Fase 84: 8 raros na loja (até 2 por semana), vales do calendário"
select 'Fase 84: ' || jsonb_array_length(public.fazenda_loja_diamantes()->'raros'->'itens') || ' raros na loja (até '
       || (public.fazenda_loja_diamantes()->'raros'->>'por_semana') || ' por semana), vales do calendário' as ok
 where exists (select 1 from pg_tables where tablename = 'fazenda_vales');
