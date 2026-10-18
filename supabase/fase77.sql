-- ============================================================
-- FAZENDINHA — Fase 77 (a tela do clima, a tempestade com raios e o furacão),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 76): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 76 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_atender' and pronargs = 3)) then
    raise exception 'Rode o fase76.sql antes deste (a fase 76 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 77: a tela do clima, a tempestade com raios e o furacão.
-- • Alguns pedaços de 36 min da chuva viram tempestade (1 em 4; no inverno, nevasca) e da ventania viram
--   furacão (1 em 6): fazenda_extremo_em, igual para todo mundo. A tempestade rega como a chuva; o furacão
--   espalha pragas como a ventania. Na tempestade o painel solar quase para (2 ⚡/h) e a turbina dá 20; no
--   furacão, a turbina dá 40 (fazenda_gera_em).
-- • Em cada um, do nível 5 em diante, cada painel solar e cada turbina tem 1 chance em 250 de levar um raio
--   (ou de ser derrubado pelo vento): sobrecarga, para de gerar até o conserto. No furacão, cada canteiro
--   plantado também tem 1 em 250 de ser arrancado (a estufa protege os canteiros em volta dela).
-- • Consertar: tocar no gerador e pagar 20% do preço dele (fazenda_consertar), ou ter o eletricista, que
--   conserta sozinho (nível 1: 1 h; 2: 40 min; 3: 25 min; 4: 15 min; 5: 10 min).
-- • fazenda_clima_info: a tela do clima (as próximas 24 h, as chances de cada clima por estação e as regras).
-- ------------------------------------------------------------
alter table public.fazenda_construcoes add column if not exists sobrecarga_em timestamptz;
alter table public.fazenda_jogadores add column if not exists tempestade_em timestamptz;   -- o último pedaço de 36 min já sorteado

create table if not exists public.fazenda_clima_eventos (
  id         bigint generated always as identity primary key,
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  evento     text not null check (evento in ('sobrecarga', 'arrancou', 'consertou')),
  clima      text,       -- tempestade ou furacao
  item       text,       -- o gerador ou a planta
  x          smallint,
  y          smallint,
  em         timestamptz not null default now(),
  visto      boolean not null default false
);
create index if not exists fazenda_clima_eventos_jogador on public.fazenda_clima_eventos (jogador_id, visto);
alter table public.fazenda_clima_eventos enable row level security;
revoke all on public.fazenda_clima_eventos from anon, authenticated;

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
  select tempestade_em, fazenda_nivel(xp) into v_desde, v_nivel from fazenda_jogadores where id = p_jogador;
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

-- Conserta um gerador em sobrecarga: 20% do preço dele
create or replace function public.fazenda_consertar(p_token text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_custo int;
begin
  select ceil(i.custo * (fazenda_extremo_regras()->>'conserto_pct')::int / 100.0)::int into v_custo
    from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y and c.sobrecarga_em is not null
     for update of c;
  if v_custo is null then raise exception 'sem_sobrecarga'; end if;
  if (select moedas from fazenda_jogadores where id = v_id for update) < v_custo then raise exception 'moedas_insuficientes'; end if;
  perform fazenda_energia_atualizar(v_id);   -- até agora, ele estava parado
  update fazenda_jogadores set moedas = moedas - v_custo where id = v_id;
  update fazenda_construcoes set sobrecarga_em = null where jogador_id = v_id and x = p_x and y = p_y;
  return jsonb_build_object('pagou', v_custo, 'estado', fazenda_estado(v_id));
end;
$$;

-- A tela do clima: as próximas 24 h (de 36 em 36 min, juntando os pedaços iguais), as chances de cada
-- clima em cada estação e as regras da tempestade e do furacão. Igual para todo mundo: uma vez por minuto.
create or replace function public.fazenda_clima_info()
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  k       text := to_char(date_trunc('minute', now()), 'YYYY-MM-DD HH24:MI');
  v       jsonb;
  v_t     timestamptz := to_timestamp(floor(extract(epoch from now()) / 2160) * 2160);
  v_c     text;
  v_e     text;
  v_ant   text;
  v_lista jsonb := '[]'::jsonb;
  v_teste boolean := coalesce(current_setting('fazenda.clima_teste', true), '') <> ''
                     or coalesce(current_setting('fazenda.estacao_teste', true), '') <> ''
                     or coalesce(current_setting('fazenda.extremo_teste', true), '') <> '';
begin
  if not v_teste then
    select valor into v from fazenda_cache where chave = 'clima_info' and valor->>'minuto' = k;
    if v is not null then return v; end if;
  end if;
  for i in 0..40 loop
    v_c := fazenda_clima_em(v_t + interval '1 minute');
    v_e := fazenda_extremo_de(v_t + interval '1 minute', v_c);
    if v_ant is distinct from v_c || ':' || coalesce(v_e, '') then
      v_lista := v_lista || jsonb_build_array(jsonb_build_object('clima', v_c, 'extremo', v_e, 'de', v_t));
      v_ant := v_c || ':' || coalesce(v_e, '');
    end if;
    v_t := v_t + interval '36 minutes';
  end loop;
  v := jsonb_build_object('minuto', k, 'lista', v_lista, 'regras', fazenda_extremo_regras(),
         'tabela', (select jsonb_object_agg(e.est, (select jsonb_object_agg(t.clima, t.pct) from fazenda_clima_tabela(e.est) t))
                      from unnest(array['primavera', 'verao', 'outono', 'inverno']) e(est)));
  if not v_teste then perform fazenda_cache_gravar('clima_info', v); end if;
  return v;
end;
$$;

-- as funções que já existiam e mudaram

create or replace function public.fazenda_extremo_regras()
returns jsonb language sql immutable as $$
  select '{"tempestade": 4, "furacao": 6, "chance": 250, "nivel": 5, "conserto_pct": 20,
           "eletricista_min": [60, 40, 25, 15, 10], "fatias_max": 80}'::jsonb;
$$;

-- o clima extremo de um momento, dado o clima de baixo: null, 'tempestade' ou 'furacao'
create or replace function public.fazenda_extremo_de(p_t timestamptz, p_clima text)
returns text language sql stable as $$
  select case
    when coalesce(current_setting('fazenda.extremo_teste', true), '') <> '' then nullif(current_setting('fazenda.extremo_teste', true), 'nenhum')
    when p_clima = 'chuva' and ('x' || substr(x.h, 1, 4))::bit(16)::int % (fazenda_extremo_regras()->>'tempestade')::int = 0 then 'tempestade'
    when p_clima = 'vento' and ('x' || substr(x.h, 5, 4))::bit(16)::int % (fazenda_extremo_regras()->>'furacao')::int = 0 then 'furacao'
  end
  from (select md5('extremo:' || floor(extract(epoch from p_t) / 2160)::bigint) as h) x;   -- o pedaço de 36 min
$$;

create or replace function public.fazenda_extremo_em(p_t timestamptz)
returns text language sql stable as $$
  select fazenda_extremo_de(p_t, fazenda_clima_em(p_t));
$$;

-- ⚡ por hora de cada gerador num momento (fase 77: uma conta só, para a taxa e para a média). Na
-- tempestade o sol some e a turbina gira forte; no furacão, a turbina gira no máximo.
create or replace function public.fazenda_gera_em(p_t timestamptz)
returns table (solar real, eolica real, reator real) language sql stable as $$
  select (case when not fazenda_dia_em(p_t) then 0
               when x.e = 'tempestade' then 2 when x.e = 'furacao' then 3
               else case x.c when 'sol' then 12 when 'calor' then 14 when 'vento' then 10 when 'nublado' then 5 else 3 end end)::real,
         (case when x.e = 'tempestade' then 20 when x.e = 'furacao' then 40
               when fazenda_vento_calmo(p_t) then 3   -- fase 48: calmaria
               else case x.c when 'vento' then 30 when 'chuva' then 14 when 'nublado' then 10 when 'sol' then 8 else 5 end end)::real,
         (case x.c when 'calor' then 500 else 700 end)::real   -- fase 75: era 120 (80 no calor)
    from (select y.c, fazenda_extremo_de(p_t, y.c) as e from (select fazenda_clima_em(p_t) as c) y) x;
$$;

create or replace function public.fazenda_energia_taxa(p_jogador uuid, p_t timestamptz)
returns real language sql stable security definer set search_path = public as $$
  select coalesce(sum(case i.efeito when 'solar' then g.solar when 'eolica' then g.eolica when 'reator' then g.reator else 0 end), 0)::real
         -- fase 47: cada alarme gasta 1 ⚡ por hora (a conta só roda para quem tem energia elétrica)
         - (select count(*) from fazenda_construcoes a where a.jogador_id = p_jogador and a.tipo = 'alarme')::real
    from fazenda_construcoes c
    join fazenda_itens i on i.id = c.tipo
    cross join fazenda_gera_em(p_t) g
   where c.jogador_id = p_jogador and i.efeito in ('solar', 'eolica', 'reator')
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
           'reator', round(avg(g.reator)::numeric, 1), 'biomassa', 50)
    into v
    from generate_series(date_trunc('hour', now()), date_trunc('hour', now()) + interval '7 days', interval '12 minutes') t
   cross join lateral fazenda_gera_em(t) g;
  perform fazenda_cache_gravar('energia_medias', v);
  return v;
end;
$$;

-- Previsão: o clima de agora, até quando vai e qual vem depois
create or replace function public.fazenda_clima_previsao(p_t timestamptz)
returns jsonb language plpgsql stable as $$
declare
  v_agora text := fazenda_clima_em(p_t);
  v_t     timestamptz := date_trunc('minute', p_t) + make_interval(mins => 36 - fazenda_minuto_semana(p_t) % 36);
  v_prox  text;
  k       int;
  -- fase 77: a tempestade ou o furacão de agora e até quando (o jogo antigo só vê a chuva e a ventania)
  v_ext   jsonb := jsonb_build_object('extremo', fazenda_extremo_de(p_t, v_agora));
  v_e     timestamptz := v_t;
begin
  if v_ext->>'extremo' is not null then
    while v_e < p_t + interval '6 hours' and fazenda_extremo_em(v_e) is not distinct from v_ext->>'extremo' loop
      v_e := v_e + interval '36 minutes';
    end loop;
    v_ext := v_ext || jsonb_build_object('extremo_ate', v_e);
  end if;
  for k in 1..80 loop
    v_prox := fazenda_clima_em(v_t);
    if v_prox <> v_agora then
      return jsonb_build_object('agora', v_agora, 'ate', v_t, 'proximo', v_prox) || v_ext;
    end if;
    v_t := v_t + interval '36 minutes';
  end loop;
  return jsonb_build_object('agora', v_agora, 'ate', null, 'proximo', null) || v_ext;
end;
$$;

create or replace function public.fazenda_carregar(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
begin
  -- carregado_antes = o carregar anterior: se foi há menos de 2 minutos, a fazenda está aberta (a Dona Rosa descansa)
  update fazenda_jogadores set carregado_antes = carregado_em, carregado_em = now() where id = v_id;
  perform fazenda_tick(v_id);
  perform fazenda_trabalhar(v_id);   -- (fase 66: e registra o que murchou sem ninguém colher, e por quê)
  perform fazenda_industria(v_id);
  perform fazenda_feira_vencidos(v_id);   -- fase 50: anúncio vencido volta para o celeiro
  perform fazenda_reator(v_id);   -- fase 68: a radiação do reator nos bichos
  perform fazenda_tempestade(v_id);   -- fase 77: o raio e o furacão (e o eletricista consertando)
  return fazenda_estado(v_id);
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

-- permissões
revoke execute on function
  public.fazenda_extremo_regras(),
  public.fazenda_extremo_de(timestamptz, text),
  public.fazenda_extremo_em(timestamptz),
  public.fazenda_gera_em(timestamptz),
  public.fazenda_tempestade(uuid)
from public, anon, authenticated;

grant execute on function
  public.fazenda_consertar(text, int, int),
  public.fazenda_clima_info()
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- conferência: deve aparecer "Fase 77: N tempestade(s) ou furacão(ões) nas próximas 24 h, raio 1 em 250"
select 'Fase 77: ' || (select count(*) from jsonb_array_elements(public.fazenda_clima_info()->'lista') x where x->>'extremo' is not null)
       || ' tempestade(s) ou furacão(ões) nas próximas 24 h, raio 1 em ' || (public.fazenda_extremo_regras()->>'chance') as ok;
