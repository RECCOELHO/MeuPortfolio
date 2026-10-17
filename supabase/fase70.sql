-- ============================================================
-- FAZENDINHA — Fase 70 (segurança e jogo limpo),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 69): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- ------------------------------------------------------------
-- Fase 70: segurança e jogo limpo (a revisão de 17/10).
-- • Anúncio premiado fechado: fazenda_anuncio sai da API (os anúncios estão desligados no jogo e chamar
--   pelo console dava 1 diamante a cada 10 s). Quando voltarem: 1 a cada 5 min, 6 por dia, diamante só
--   nos 3 primeiros do dia.
-- • Uma chamada de cada vez por jogador (fazenda_auth): chamadas juntas duplicavam o que saía do baú,
--   pagavam conquista e presente do nível duas vezes e furavam os limites do dia. O baú e a rede de
--   canos também tiram e entregam numa coisa só; conquista e presente do nível pagam uma vez só.
-- • Evento da semana: o XP comprado com diamante (pacote de XP, XP da trilha dourada e a metade a mais do
--   XP em dobro: fazenda_jogadores.xp_pago) não conta no ranking nem em níveis; o que entra pela barraca
--   não conta em "mais moedas"; em vendeu e comprou, uma mesma pessoa do outro lado vale no máximo 25%
--   do total; convite conta quando o amigo chega ao nível 10 (era 5).
-- • Fazendas novas: no máximo 5 por hora e 20 por dia do mesmo endereço (IP). Código de recuperação
--   errado: 10 por hora do mesmo endereço e 2000 por hora no total (fazenda_tentativas, 2 dias).
-- • Peça do píer com diamante: no máximo o que a receita pede (anunciar na feira e comprar de novo
--   virava material raro sem fim).
-- • XP sem fim: plantar e arrancar, arar e desmanchar o canteiro. O XP de arar e plantar da fazenda
--   completa vem na colheita (+2) e canteiro novo espera os 8 min para dar XP de colheita.
-- • Calendário dourado sem a luva do Perks (vantagem contra os outros jogadores): no lugar, peças do
--   píer. As moedas do calendário passam a valer pelo presente do nível (um décimo dele por moeda da
--   tabela), não só pelo nível.
-- • Regras que tinham ficado para trás: a doceira volta a pedir os produtos novos (o filtro "ordem < 40"
--   da fase 21 deixava de fora tudo o que veio depois); o mercador só pede fruto que o nível já planta;
--   o 45 é mesmo o último nível (fazenda_nivel passava dele); conquistas dos níveis 15, 30, 35 e 40.
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists xp_pago bigint not null default 0;
alter table public.fazenda_jogadores add column if not exists anuncio_dia date;
alter table public.fazenda_jogadores add column if not exists anuncio_n smallint not null default 0;
alter table public.fazenda_semana_base add column if not exists xp_pago bigint not null default 0;

create table if not exists public.fazenda_tentativas (
  id   bigint generated always as identity primary key,
  ip   text not null,
  tipo text not null check (tipo in ('criar', 'recuperar')),
  em   timestamptz not null default now()
);
create index if not exists fazenda_tentativas_ip on public.fazenda_tentativas (tipo, ip, em);
create index if not exists fazenda_tentativas_em on public.fazenda_tentativas (em);
alter table public.fazenda_tentativas enable row level security;
revoke all on public.fazenda_tentativas from anon, authenticated;

-- as conquistas dos níveis que faltavam (havia 5, 10, 20, 25 e 45): quem já passou ganha na hora
insert into public.fazenda_conquistas_tipos (id, nome, descricao, medida, meta, recompensa, ordem) values
  ('nivel_15', 'Fazendeiro nível 15', 'Chegue ao nível 15', 'nivel', 15,   800, 33),
  ('nivel_30', 'Fazendeiro nível 30', 'Chegue ao nível 30', 'nivel', 30, 15000, 34),
  ('nivel_35', 'Fazendeiro nível 35', 'Chegue ao nível 35', 'nivel', 35, 30000, 35),
  ('nivel_40', 'Fazendeiro nível 40', 'Chegue ao nível 40', 'nivel', 40, 60000, 36)
on conflict (id) do update set
  nome = excluded.nome, descricao = excluded.descricao, medida = excluded.medida,
  meta = excluded.meta, recompensa = excluded.recompensa, ordem = excluded.ordem;

-- o endereço de quem chamou (o Cloudflare do Supabase manda no cf-connecting-ip; fora dele, null)
create or replace function public.fazenda_ip()
returns text language sql stable as $$
  select nullif(btrim(coalesce(h->>'cf-connecting-ip', h->>'x-real-ip', split_part(h->>'x-forwarded-for', ',', 1))), '')
    from (select nullif(current_setting('request.headers', true), '')::json as h) x;
$$;

-- as funções que já existiam e mudaram

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
  return least(n, 45);   -- fase 70: o 45 é o último (passava para 46, 47... e o presente continuava)
end;
$$;

create or replace function public.fazenda_auth(p_token text)
returns uuid
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid;
begin
  if p_token is null or length(p_token) < 32 then
    raise exception 'token_invalido';
  end if;
  select jogador_id into v_id
    from fazenda_sessoes
   where token_hash = encode(digest(p_token, 'sha256'), 'hex');
  if v_id is null then
    raise exception 'token_invalido';
  end if;
  -- fase 53: conta banida pelos admins não entra (nenhuma chamada passa daqui)
  if exists (select 1 from fazenda_jogadores where id = v_id and banido_em is not null) then
    raise exception 'conta_banida';
  end if;
  -- fase 70: uma chamada de cada vez por jogador (a próxima espera esta terminar). Chamadas juntas
  -- duplicavam o baú, pagavam a conquista e o presente do nível duas vezes e furavam os limites do dia.
  perform pg_advisory_xact_lock(7070, hashtext(v_id::text));
  -- fase 63: a semana do evento virou (sexta 22h)? a primeira chamada fecha, premia e abre a nova
  -- (fase 70: antes de gravar o visto_em, para não segurar a linha do jogador enquanto espera o fechamento)
  if not exists (select 1 from fazenda_semanas where inicio = fazenda_semana_inicio(now())) then
    perform fazenda_semana_fechar();
  end if;
  -- visto_em só serve para "jogou nos últimos 30 dias": grava no máximo 1 vez por hora
  -- (cada chamada gravando pesava no orçamento de disco do Supabase)
  update fazenda_jogadores set visto_em = now() where id = v_id and visto_em < now() - interval '1 hour';
  return v_id;
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
    'culturas', (
      select jsonb_agg(jsonb_build_object(
               'id', id, 'nome', nome, 'emoji', emoji, 'tempo_seg', tempo_seg,
               'custo', custo, 'venda', venda, 'rendimento', rendimento,
               'xp', xp, 'nivel_min', nivel_min, 'tipo', tipo, 'estacao', estacao)
             order by ordem)
        from fazenda_culturas),
    'animais', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'alimentado_em', alimentado_em,
               'radioativo_ate', case when radioativo_ate > now() then radioativo_ate end) order by id)   -- fase 68
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

  -- colher agora (fase 31): 1 diamante deixa pronto na hora o que está crescendo, sem os
  -- problemas, e já colhe. Maduro não precisa de diamante: só colhe.
  if p_acao = 'agora' then
    if p_bot then raise exception 'acao_invalida'; end if;
    if c.estado <> 'plantado' or now() >= v_murcho then raise exception 'nada_a_fazer'; end if;
    if now() < v_maduro then
      if j.diamantes < 1 then raise exception 'diamantes_insuficientes'; end if;
      update fazenda_jogadores set diamantes = diamantes - 1 where id = p_jogador;
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
             + (fazenda_clima_em(now()) = 'sol')::int                    -- colheita no sol
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
    v_xp_colheita := not p_bot and (c.xp_em is null or c.xp_em <= now() - interval '8 minutes');
    if v_xp_colheita then
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

create or replace function public.fazenda_criar(p_apelido text, p_convite text default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_alfabeto text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_palavras text[] := array['MILHO','CENOURA','ABOBORA','TOMATE','MORANGO',
                             'BATATA','ALFACE','MELANCIA','GIRASSOL','TRIGO'];
  v_bytes  bytea := gen_random_bytes(9);
  v_codigo text;
  v_id     uuid;
  i        int;
  v_dono   record;
  v_premio jsonb := fazenda_premio_convite();
  v_conv   jsonb;
  v_ip     text;   -- fase 70
begin
  p_apelido := btrim(p_apelido);
  if p_apelido is null or char_length(p_apelido) not between 2 and 20 then
    raise exception 'apelido_invalido';
  end if;

  -- Freio contra spam: no máximo 300 fazendas novas por hora no total
  if (select count(*) from fazenda_jogadores where criado_em > now() - interval '1 hour') >= 300 then
    raise exception 'muitas_fazendas';
  end if;
  -- fase 70: e 5 por hora (20 por dia) do mesmo endereço
  v_ip := fazenda_ip();
  if v_ip is not null and (
       (select count(*) from fazenda_tentativas where tipo = 'criar' and ip = v_ip and em > now() - interval '1 hour') >= 5
    or (select count(*) from fazenda_tentativas where tipo = 'criar' and ip = v_ip and em > now() - interval '1 day') >= 20) then
    raise exception 'muitas_fazendas_ip';
  end if;
  delete from fazenda_tentativas where em < now() - interval '2 days';
  if v_ip is not null then insert into fazenda_tentativas (ip, tipo) values (v_ip, 'criar'); end if;

  -- Código de recuperação: PALAVRA-XXXX-XXXX (~10^13 combinações)
  v_codigo := v_palavras[1 + get_byte(v_bytes, 0) % array_length(v_palavras, 1)] || '-';
  for i in 1..8 loop
    v_codigo := v_codigo || substr(v_alfabeto, 1 + get_byte(v_bytes, i) % length(v_alfabeto), 1);
    if i = 4 then
      v_codigo := v_codigo || '-';
    end if;
  end loop;

  insert into fazenda_jogadores (apelido, codigo_hash, convite)
  values (p_apelido, encode(digest(v_codigo, 'sha256'), 'hex'), fazenda_novo_convite())
  returning id into v_id;

  -- Começa com 6 canteiros já arados
  insert into fazenda_canteiros (jogador_id, posicao, estado, x, y)
  select v_id, g, 'arado', 9 + g, 4 from generate_series(0, 5) g;
  -- fase 54: e com um lampião aceso do lado da casa (quem começa de noite não fica no escuro)
  insert into fazenda_construcoes (jogador_id, x, y, tipo, colhido_em) values (v_id, 8, 3, 'lampiao', now());
  update fazenda_jogadores set ganhou_poste = true where id = v_id;

  -- Veio por um convite: os dois ganham moedas (quem chamou, até o limite do dia)
  if nullif(btrim(p_convite), '') is not null then
    select id, apelido into v_dono from fazenda_jogadores
     where convite = upper(btrim(p_convite)) and id <> v_id
       for update;
    if found then
      insert into fazenda_convites (convidado_id, dono_id, premiado)
      values (v_id, v_dono.id,
              (select count(*) from fazenda_convites
                where dono_id = v_dono.id and premiado and criado_em > now() - interval '1 day') < (v_premio->>'por_dia')::int);
      update fazenda_jogadores set moedas = moedas + (v_premio->>'amigo')::int where id = v_id;
      update fazenda_jogadores set moedas = moedas + (v_premio->>'dono')::int
       where id = v_dono.id and (select premiado from fazenda_convites where convidado_id = v_id);
      v_conv := jsonb_build_object('apelido', v_dono.apelido, 'moedas', (v_premio->>'amigo')::int);
    end if;
  end if;

  return jsonb_build_object(
    'token', fazenda_nova_sessao(v_id),
    'codigo', v_codigo,
    'convite', v_conv,
    'estado', fazenda_estado(v_id)
  );
end;
$$;

create or replace function public.fazenda_recuperar(p_codigo text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid;
  v_ip text := fazenda_ip();   -- fase 70
begin
  -- fase 70: código errado tem limite: 10 por hora do mesmo endereço e 2000 por hora no total (sem isso
  -- dava para ir chutando códigos até achar a fazenda de alguém)
  if (select count(*) from fazenda_tentativas where tipo = 'recuperar' and em > now() - interval '1 hour') >= 2000
     or (v_ip is not null
         and (select count(*) from fazenda_tentativas where tipo = 'recuperar' and ip = v_ip and em > now() - interval '1 hour') >= 10) then
    raise exception 'muitas_tentativas';
  end if;
  p_codigo := upper(regexp_replace(coalesce(p_codigo, ''), '\s', '', 'g'));
  select id into v_id from fazenda_jogadores
   where codigo_hash = encode(digest(p_codigo, 'sha256'), 'hex');
  if v_id is null then
    -- o erro volta sem "raise" (que desfaria a anotação da tentativa): status 400 e a mensagem
    delete from fazenda_tentativas where em < now() - interval '2 days';
    insert into fazenda_tentativas (ip, tipo) values (coalesce(v_ip, '?'), 'recuperar');
    perform set_config('response.status', '400', true);
    return jsonb_build_object('code', 'P0001', 'message', 'codigo_invalido');
  end if;
  if exists (select 1 from fazenda_jogadores where id = v_id and banido_em is not null) then raise exception 'conta_banida'; end if;
  perform fazenda_tick(v_id);
  return jsonb_build_object(
    'token', fazenda_nova_sessao(v_id),
    'estado', fazenda_estado(v_id)
  );
end;
$$;

-- O que sobra nos baús ligados ao celeiro (o que nenhuma oficina da rede usa) vai para o celeiro.
-- 2 ⚡ por viagem (um tipo de item de cada vez); sem energia, espera.
create or replace function public.fazenda_rede_descarregar(p_jogador uuid, p_membros jsonb)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  b       record;
  it      record;
  v_redes int[];
  v_q     int;   -- fase 70
begin
  for b in select distinct (m->>'x')::int as x, (m->>'y')::int as y from jsonb_array_elements(p_membros) m where m->>'papel' = 'bau' loop
    v_redes := fazenda_redes_de(p_membros, 'bau', b.x, b.y);
    continue when not fazenda_rede_tem_celeiro(p_membros, v_redes);
    for it in
      select bi.item, bi.quantidade from fazenda_bau_itens bi
       where bi.jogador_id = p_jogador and bi.x = b.x and bi.y = b.y and bi.quantidade > 0
         and not exists (
           select 1 from jsonb_array_elements(p_membros) m
             join fazenda_construcoes c on c.jogador_id = p_jogador and c.x = (m->>'x')::int and c.y = (m->>'y')::int
             join fazenda_itens i on i.id = c.tipo
            where m->>'papel' = 'oficina' and (m->>'rede')::int = any(v_redes) and i.entradas ? bi.item)
    loop
      exit when not fazenda_gastar_energia(p_jogador, 2);
      -- fase 70: tira e entrega o que estava lá de fato (o cursor podia estar velho)
      delete from fazenda_bau_itens where jogador_id = p_jogador and x = b.x and y = b.y and item = it.item
      returning quantidade into v_q;
      continue when coalesce(v_q, 0) <= 0;
      insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, it.item, v_q)
      on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
      perform fazenda_viagem(p_jogador, it.item, v_q, b.x, b.y, null, null, false, now());
    end loop;
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
        update fazenda_jogadores set moedas = moedas + r.recompensa where id = p_jogador;
      end if;
    end if;
  end loop;
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
  insert into fazenda_construcoes (jogador_id, x, y, tipo, colhido_em) values (v_id, p_x, p_y, i.id, now());
  return jsonb_build_object('estado', fazenda_estado(v_id));
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
  if v_tipo = 'mascate' then
    return jsonb_build_object('slot', v_slot, 'tipo', v_tipo, 'ate', to_timestamp((v_slot + 1) * 10800),
                              'canteiros', 8, 'preco', 40 + 10 * v_nivel);
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
    -- XP de quanto você ganharia colhendo isso (o caminhoneiro dá o dobro)
    'xp', greatest(1, v_qtd * k.xp * case when v_tipo = 'caminhoneiro' then 2 else 1 end / greatest(k.rendimento, 1)));
end;
$$;

-- Leva tudo o que está no baú para o celeiro (na mão: sem cano e sem energia)
create or replace function public.fazenda_bau_esvaziar(p_token text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id  uuid := fazenda_auth(p_token);
  v_qtd int;
begin
  if not exists (select 1 from fazenda_construcoes where jogador_id = v_id and x = p_x and y = p_y and tipo = 'bau') then
    raise exception 'item_invalido';
  end if;
  -- fase 70: tira e entrega numa coisa só (somar, entregar e depois apagar deixava duas chamadas juntas
  -- entregarem tudo duas vezes)
  with tirado as (delete from fazenda_bau_itens where jogador_id = v_id and x = p_x and y = p_y returning item, quantidade),
       soma as (select item, sum(quantidade)::int as q from tirado where quantidade > 0 group by item),
       entregue as (insert into fazenda_celeiro (jogador_id, item, quantidade) select v_id, item, q from soma
                    on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade)
  select coalesce(sum(q), 0)::int into v_qtd from soma;
  return jsonb_build_object('qtd', v_qtd, 'estado', fazenda_estado(v_id));
end;
$$;

-- Anúncio premiado: o jogador assistiu até o fim e tudo o que está em andamento anda
-- 30 minutos — plantas, animais, oficinas, amoreira, ajudantes e geradores. Nada passa do
-- ponto (o que amadurece fica maduro, não murcha).
-- Fase 70: fechada para o jogo (os anúncios estão desligados e chamar pelo console dava 1 diamante a
-- cada 10 s). Quando voltarem: 1 a cada 5 min, 6 por dia, e o diamante só nos 3 primeiros do dia.
create or replace function public.fazenda_anuncio(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id  uuid := fazenda_auth(p_token);
  j     record;
  v_d   interval := interval '30 minutes';
  v_c   int;
  v_a   int;
  v_o   int;
  v_p   int;
  v_n   int;   -- fase 70: os anúncios de hoje
begin
  select anuncio_em, anuncio_dia, anuncio_n into j from fazenda_jogadores where id = v_id for update;
  if j.anuncio_em is not null and j.anuncio_em > now() - interval '5 minutes' then
    raise exception 'anuncio_cedo';
  end if;
  v_n := case when j.anuncio_dia = fazenda_hoje() then j.anuncio_n else 0 end;   -- fase 70
  if v_n >= 6 then raise exception 'anuncio_limite'; end if;
  perform fazenda_energia_atualizar(v_id);   -- fecha a conta da energia antes de somar os 30 min

  -- plantas crescendo (os problemas que cairiam nesse tempo também chegam)
  update fazenda_canteiros c
     set plantado_em = greatest(c.plantado_em - v_d, now() - make_interval(secs => k.tempo_seg)),
         prox_evento = c.prox_evento - (c.plantado_em - greatest(c.plantado_em - v_d, now() - make_interval(secs => k.tempo_seg)))
    from fazenda_culturas k
   where c.jogador_id = v_id and k.id = c.cultura and c.estado = 'plantado'
     and now() < c.plantado_em + make_interval(secs => k.tempo_seg);
  get diagnostics v_c = row_count;

  -- animais produzindo
  update fazenda_animais a
     set alimentado_em = greatest(a.alimentado_em - v_d, now() - make_interval(secs => t.tempo_seg))
    from fazenda_animais_tipos t
   where a.jogador_id = v_id and t.id = a.tipo and a.alimentado_em is not null
     and now() < a.alimentado_em + make_interval(secs => t.tempo_seg);
  get diagnostics v_a = row_count;

  -- oficinas trabalhando
  update fazenda_construcoes c
     set iniciado_em = greatest(c.iniciado_em - v_d, now() - make_interval(secs => i.produz_seg))
    from fazenda_itens i
   where c.jogador_id = v_id and i.id = c.tipo and i.entradas is not null and c.iniciado_em is not null
     and now() < c.iniciado_em + make_interval(secs => i.produz_seg);
  get diagnostics v_o = row_count;

  -- o que produz sozinho (amoreira)
  update fazenda_construcoes c
     set colhido_em = greatest(c.colhido_em - v_d, now() - make_interval(secs => i.produz_seg))
    from fazenda_itens i
   where c.jogador_id = v_id and i.id = c.tipo and i.produz is not null and i.entradas is null
     and c.colhido_em is not null and now() < c.colhido_em + make_interval(secs => i.produz_seg);
  get diagnostics v_p = row_count;

  -- ajudantes ganham meia hora de trabalho; sol, vento e reator, meia hora de energia
  update fazenda_ajudantes
     set credito = least(credito + fazenda_ritmo(nivel) * 0.5, fazenda_ritmo(nivel) * 8)
   where jogador_id = v_id;
  update fazenda_jogadores
     set energia = least(energia + fazenda_energia_taxa(v_id, now()) * 0.5, fazenda_capacidade(v_id)),
         diamantes = diamantes + (v_n < 3)::int,   -- fase 31: cada anúncio também dá 1 diamante (fase 70: os 3 primeiros do dia)
         anuncio_em = now(), anuncio_dia = fazenda_hoje(), anuncio_n = v_n + 1
   where id = v_id;
  insert into fazenda_estatisticas (jogador_id) values (v_id) on conflict do nothing;
  update fazenda_estatisticas set anuncios = anuncios + 1 where jogador_id = v_id;
  update fazenda_jogadores set lago_em = lago_em - v_d where id = v_id and lago_em is not null;   -- +1 peixe no cesto

  -- já roda o que o tempo a mais destrava (problemas, ajudantes, máquinas)
  perform fazenda_tick(v_id);
  perform fazenda_trabalhar(v_id);
  perform fazenda_industria(v_id);
  return jsonb_build_object('canteiros', v_c, 'animais', v_a, 'oficinas', v_o + v_p, 'estado', fazenda_estado(v_id));
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
    if new.bonus_nivel is not null and new.bonus_nivel = fazenda_nivel(old.xp) then v_mult := v_mult + 0.5; end if;
    -- fase 57: fazenda completa (do 20 em diante, metas em dia): mais 25%
    if new.bonus_nivel is not null and new.bonus_nivel = fazenda_nivel(old.xp) and fazenda_nivel(old.xp) >= 20 then v_mult := v_mult + 0.25; end if;
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
    -- fase 48: 1 diamante salva todas as plantas murchas (voltam maduras, sem problemas)
    v_preco := (v_loja->>'preco')::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    update fazenda_canteiros c
       set plantado_em = now() - make_interval(secs => k.tempo_seg), erva = false, praga = false, seco = false, prox_evento = null
      from fazenda_culturas k
     where c.jogador_id = v_id and c.estado = 'plantado' and k.id = c.cultura
       and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600));
    if not found then raise exception 'nada_a_fazer'; end if;
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

create or replace function public.fazenda_feira_comprar(p_token text, p_id bigint)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_r     jsonb := fazenda_feira_regras();
  a       record;
  v_total int;
  v_taxa  int;
begin
  select * into a from fazenda_feira where id = p_id for update;
  if not found or a.vendido_em is not null
     or a.criado_em < now() - make_interval(hours => (v_r->>'horas')::int) then
    raise exception 'anuncio_invalido';   -- já vendido, cancelado ou vencido
  end if;
  if a.vendedor_id = v_id then raise exception 'anuncio_seu'; end if;
  -- fase 67: separado para quem pediu no chat (por 2 h, só essa pessoa compra)
  if a.reservado_para is not null and a.reservado_para <> v_id and a.reservado_ate > now() then raise exception 'anuncio_reservado'; end if;
  if (select count(*) from fazenda_feira where comprador_id = v_id and vendido_em > now() - interval '1 day')
     >= (v_r->>'compras_dia')::int then
    raise exception 'limite_compras';
  end if;
  v_total := a.qtd * a.preco;
  v_taxa := ceil(v_total * (v_r->>'taxa')::int / 100.0)::int;
  -- fase 70: segura os dois sempre na mesma ordem (dois comprando um do outro ao mesmo tempo travavam)
  perform 1 from fazenda_jogadores where id in (v_id, a.vendedor_id) order by id for update;
  if (select moedas from fazenda_jogadores where id = v_id) < v_total then raise exception 'moedas_insuficientes'; end if;
  update fazenda_jogadores set moedas = moedas - v_total where id = v_id;
  -- fase 70: o que entra pela barraca não conta em "mais moedas" do evento (já conta em "vendeu")
  update fazenda_jogadores set moedas = moedas + v_total - v_taxa, moedas_ganhas = moedas_ganhas - (v_total - v_taxa)
   where id = a.vendedor_id;
  insert into fazenda_celeiro (jogador_id, item, quantidade, da_feira) values (v_id, a.item, a.qtd, a.qtd)   -- fase 56: da_feira
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade,
                                               da_feira = fazenda_celeiro.da_feira + excluded.da_feira;
  update fazenda_feira set comprador_id = v_id, vendido_em = now() where id = p_id;
  return jsonb_build_object('item', a.item, 'qtd', a.qtd, 'total', v_total,
                            'vendedor', (select apelido from fazenda_jogadores where id = a.vendedor_id),
                            'estado', fazenda_estado(v_id));
end;
$$;

create or replace function public.fazenda_moedas_ganhas()
returns trigger language plpgsql set search_path = public as $$
begin
  -- (fase 70: soma no que veio na gravação: a venda na barraca já desconta o que não conta)
  if new.moedas > old.moedas then new.moedas_ganhas := new.moedas_ganhas + (new.moedas - old.moedas); end if;
  return new;
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
  -- fase 70: com diamante, no máximo o que a receita pede (anunciar na feira e comprar de novo virava raro sem fim)
  if (select count(*) from fazenda_diamantes_usos where jogador_id = v_id and item = 'pier:' || p_item)
     >= coalesce((v_r->'itens'->>p_item)::int, 0) then
    raise exception 'peca_comprada';
  end if;
  if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
  update fazenda_jogadores set diamantes = diamantes - v_preco where id = v_id;
  insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, 'pier:' || p_item, v_preco);
  insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, p_item, 1)
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- as categorias, os diamantes do 1º, 2º e 3º e os itens (o 1º leva o primeiro; no ranking, um por lugar)
-- Fase 64: diamantes pela metade (eram 60, 35 e 20) e o item vem com 50% de chance (chance_item), para
-- cada lugar do pódio; o 2º e o 3º fora do ranking, se sair, levam um material do píer (fazenda_raros)
create or replace function public.fazenda_evento_regras()
returns jsonb language sql immutable as $$
  select '{"fecha": "sexta às 22h", "diamantes": [30, 18, 10], "chance_item": 50, "convite_nivel": 10,
           "categorias": [
             {"id": "ranking",  "nome": "Ranking da semana",  "conta": "XP ganho na semana",            "itens": ["trofeu_ouro", "trofeu_prata", "trofeu_bronze"]},
             {"id": "niveis",   "nome": "Mais níveis",        "conta": "níveis subidos na semana",      "itens": ["ampulheta_dourada"]},
             {"id": "moedas",   "nome": "Mais moedas",        "conta": "moedas ganhas na semana",       "itens": ["cofrinho_ouro"]},
             {"id": "vendeu",   "nome": "Vendeu na barraca",  "conta": "moedas em vendas na feira",     "itens": ["balanca_ouro"]},
             {"id": "comprou",  "nome": "Comprou na barraca", "conta": "moedas em compras na feira",    "itens": ["sacola_ouro"]},
             {"id": "convites", "nome": "Mais convites",      "conta": "amigos convidados que chegaram ao nível 10", "itens": ["leme_dourado"]}]}'::jsonb;
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
             and fazenda_nivel(a.xp) >= (fazenda_evento_regras()->>'convite_nivel')::int)::bigint
    from fazenda_jogadores j
    left join fazenda_semana_base b on b.jogador_id = j.id and b.semana = p_semana
   where j.banido_em is null;
$$;

-- Fecha a semana que acabou (premia o top 3 de cada categoria) e abre a nova (a foto de cada um).
-- Roda na primeira chamada depois da sexta 22h (fazenda_auth); a trava impede premiar duas vezes.
create or replace function public.fazenda_semana_fechar()
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_ini  timestamptz := fazenda_semana_inicio(now());
  v_reg  jsonb := fazenda_evento_regras();
  s      record;
  r      record;
  v_dia  int;
  v_item text;
  v_sorte int;   -- fase 64
begin
  if exists (select 1 from fazenda_semanas where inicio = v_ini) then return; end if;
  perform pg_advisory_xact_lock(hashtext('fazenda_semana'));
  if exists (select 1 from fazenda_semanas where inicio = v_ini) then return; end if;   -- outra chamada fechou antes
  -- a última semana aberta (normalmente a que acabou agora)
  select * into s from fazenda_semanas where fechada_em is null order by inicio desc limit 1;
  if found then
    for r in select * from fazenda_semana_posicoes(s.inicio, s.aberta_em, now()) p where p.posicao <= 3 loop
      v_dia := (v_reg->'diamantes'->>(r.posicao::int - 1))::int;
      select c->'itens'->>(r.posicao::int - 1) into v_item from jsonb_array_elements(v_reg->'categorias') c where c->>'id' = r.categoria;
      -- fase 64: o item vem com 50% de chance; sem item próprio do lugar, um material do píer (pesos do mercador)
      if random() * 100 >= coalesce((v_reg->>'chance_item')::int, 100) then
        v_item := null;
      elsif v_item is null then
        v_sorte := floor(random() * 100)::int;   -- (um sorteio só: random() no where sorteava de novo a cada linha)
        select y.r->>'id' into v_item
          from (select x.r, sum((x.r->>'peso')::int) over (order by x.ord) as acum
                  from jsonb_array_elements(fazenda_raros()) with ordinality as x(r, ord)) y
         where y.acum > v_sorte
         order by y.acum limit 1;
      end if;
      insert into fazenda_semana_premios (semana, categoria, posicao, jogador_id, valor, diamantes, item)
      values (s.inicio, r.categoria, r.posicao, r.jogador_id, r.valor, v_dia, v_item);
      update fazenda_jogadores set diamantes = diamantes + v_dia where id = r.jogador_id;
      if v_item is not null then
        insert into fazenda_celeiro (jogador_id, item, quantidade) values (r.jogador_id, v_item, 1)
        on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
      end if;
    end loop;
    update fazenda_semanas set fechada_em = now() where fechada_em is null;
  end if;
  -- a foto do começo da semana nova
  insert into fazenda_semana_base (jogador_id, semana, xp, moedas_ganhas, xp_pago)
  select id, v_ini, xp, moedas_ganhas, xp_pago from fazenda_jogadores
  on conflict (jogador_id) do update set semana = excluded.semana, xp = excluded.xp, moedas_ganhas = excluded.moedas_ganhas,
                                          xp_pago = excluded.xp_pago;   -- (fase 70)
  insert into fazenda_semanas (inicio) values (v_ini);
end;
$$;

-- os prêmios de cada dia: g = grátis, d = dourada. moedas: vezes o nível; xp: % do nível; xp2 e cafe: minutos
create or replace function public.fazenda_calendario_premios()
returns jsonb language sql immutable as $$
  select '[
    {"g": [{"tipo": "moedas", "qtd": 15}],    "d": [{"tipo": "moedas", "qtd": 50}]},
    {"g": [{"tipo": "xp", "qtd": 3}],         "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "moedas", "qtd": 20}],    "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "cafe", "qtd": 30}],      "d": [{"tipo": "xp", "qtd": 10}]},
    {"g": [{"tipo": "moedas", "qtd": 25}],    "d": [{"tipo": "moedas", "qtd": 60}]},
    {"g": [{"tipo": "xp2", "qtd": 30}],       "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "diamantes", "qtd": 3}],  "d": [{"tipo": "diamantes", "qtd": 10}, {"tipo": "item", "item": "madeira_nobre", "qtd": 1}]},
    {"g": [{"tipo": "moedas", "qtd": 20}],    "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "xp", "qtd": 4}],         "d": [{"tipo": "moedas", "qtd": 70}]},
    {"g": [{"tipo": "moedas", "qtd": 25}],    "d": [{"tipo": "xp", "qtd": 10}]},
    {"g": [{"tipo": "cafe", "qtd": 30}],      "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "moedas", "qtd": 30}],    "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "xp2", "qtd": 30}],       "d": [{"tipo": "moedas", "qtd": 80}]},
    {"g": [{"tipo": "diamantes", "qtd": 5}],  "d": [{"tipo": "diamantes", "qtd": 10}, {"tipo": "item", "item": "perola_negra", "qtd": 1}]},
    {"g": [{"tipo": "moedas", "qtd": 25}],    "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "xp", "qtd": 5}],         "d": [{"tipo": "xp", "qtd": 10}]},
    {"g": [{"tipo": "moedas", "qtd": 30}],    "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "cafe", "qtd": 45}],      "d": [{"tipo": "moedas", "qtd": 90}]},
    {"g": [{"tipo": "moedas", "qtd": 35}],    "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "xp2", "qtd": 45}],       "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "diamantes", "qtd": 5}],  "d": [{"tipo": "diamantes", "qtd": 10}, {"tipo": "item", "item": "corda_naval", "qtd": 1}, {"tipo": "item", "item": "pedra_cantaria", "qtd": 1}]},
    {"g": [{"tipo": "moedas", "qtd": 30}],    "d": [{"tipo": "xp", "qtd": 10}]},
    {"g": [{"tipo": "xp", "qtd": 5}],         "d": [{"tipo": "moedas", "qtd": 100}]},
    {"g": [{"tipo": "moedas", "qtd": 40}],    "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "cafe", "qtd": 60}],      "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "moedas", "qtd": 45}],    "d": [{"tipo": "xp", "qtd": 10}]},
    {"g": [{"tipo": "xp2", "qtd": 60}],       "d": [{"tipo": "moedas", "qtd": 120}]},
    {"g": [{"tipo": "diamantes", "qtd": 10}], "d": [{"tipo": "avatar", "avatar": "fazendeiro_ouro"}, {"tipo": "diamantes", "qtd": 20}]}
  ]'::jsonb;
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

create or replace function public.fazenda_calendario_resgatar(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_dias int := (fazenda_calendario_regras()->>'dias')::int;
  r      record;
  v_p    jsonb;
  x      jsonb;
  v_g    jsonb := '[]'::jsonb;
  v_d    jsonb := '[]'::jsonb;
begin
  insert into fazenda_calendario (jogador_id) values (v_id) on conflict (jogador_id) do nothing;
  select * into r from fazenda_calendario where jogador_id = v_id for update;   -- dois toques juntos: um só passa
  if r.ultimo = fazenda_hoje() then raise exception 'calendario_hoje'; end if;
  if r.dia >= v_dias then r.ciclo := r.ciclo + 1; r.dia := 0; end if;
  r.dia := r.dia + 1;
  v_p := fazenda_calendario_premios() -> (r.dia - 1);
  for x in select * from jsonb_array_elements(v_p->'g') loop v_g := v_g || jsonb_build_array(fazenda_calendario_dar(v_id, x)); end loop;
  if r.dourado_ciclo = r.ciclo then
    for x in select * from jsonb_array_elements(v_p->'d') loop v_d := v_d || jsonb_build_array(fazenda_calendario_dar(v_id, x || '{"pago": true}')); end loop;
  end if;
  update fazenda_calendario set ciclo = r.ciclo, dia = r.dia, ultimo = fazenda_hoje() where jogador_id = v_id;
  return jsonb_build_object('dia', r.dia, 'gratis', v_g, 'dourado', v_d, 'estado', fazenda_estado(v_id));
end;
$$;

-- Libera a trilha dourada do ciclo de agora (os dias já resgatados ganham o prêmio dourado na hora)
create or replace function public.fazenda_calendario_dourado(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_regra jsonb := fazenda_calendario_regras();
  v_preco int := (v_regra->>'dourado')::int;
  r       record;
  x       jsonb;
  v_d     jsonb := '[]'::jsonb;
begin
  insert into fazenda_calendario (jogador_id) values (v_id) on conflict (jogador_id) do nothing;
  select * into r from fazenda_calendario where jogador_id = v_id for update;
  if r.dia >= (v_regra->>'dias')::int and (r.ultimo is null or r.ultimo < fazenda_hoje()) then   -- o ciclo novo já começou
    r.ciclo := r.ciclo + 1; r.dia := 0;
  end if;
  if r.dourado_ciclo = r.ciclo then raise exception 'ja_dourado'; end if;
  if (select diamantes from fazenda_jogadores where id = v_id for update) < v_preco then raise exception 'diamantes_insuficientes'; end if;
  update fazenda_jogadores set diamantes = diamantes - v_preco where id = v_id;
  insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, 'calendario_dourado', v_preco);
  update fazenda_calendario set ciclo = r.ciclo, dia = r.dia, dourado_ciclo = r.ciclo where jogador_id = v_id;
  for k in 1..r.dia loop
    for x in select * from jsonb_array_elements(fazenda_calendario_premios() -> (k - 1) -> 'd') loop
      v_d := v_d || jsonb_build_array(fazenda_calendario_dar(v_id, x || '{"pago": true}'));   -- (fase 70)
    end loop;
  end loop;
  return jsonb_build_object('dourado', v_d, 'estado', fazenda_estado(v_id));
end;
$$;

-- permissões
revoke execute on function
  public.fazenda_ip(),
  public.fazenda_anuncio(text)
from public, anon, authenticated;

grant execute on function
  public.fazenda_criar(text, text),
  public.fazenda_recuperar(text)
to anon, authenticated;

-- conferência: deve aparecer "Fase 70: anúncio fechado; convite conta no nível 10; último nível 45"
select 'Fase 70: anúncio ' || case when has_function_privilege('anon', 'public.fazenda_anuncio(text)', 'execute') then 'ABERTO (rode de novo)' else 'fechado' end
    || '; convite conta no nível ' || (public.fazenda_evento_regras()->>'convite_nivel')
    || '; último nível ' || public.fazenda_nivel(2000000) as ok;
