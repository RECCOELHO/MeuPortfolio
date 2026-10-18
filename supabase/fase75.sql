-- ============================================================
-- FAZENDINHA — Fase 75 (energia que fecha a conta, reator forte e radiação de 30 em 30 min),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 74b): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 74b precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_vender' and pronargs = 4)) then
    raise exception 'Rode o fase74b.sql antes deste (a fase 74b não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 75: a energia que fecha a conta, como no Cities: Skylines.
-- • A conta (fazenda_energia_conta): quanto a fazenda gera em média por hora (cada gerador pela média de
--   uma semana de clima e de dia e noite, guardada em fazenda_cache) e quanto gasta no máximo por hora,
--   com tudo trabalhando sem parar (oficinas, triturador, fábrica, robôs, baús, aspersores, estufas e
--   alarmes, com o desconto do eletricista). Fica pronta por jogador até as construções mudarem.
-- • Balanceamento: com tudo no máximo no nível 45, a fazenda gastava ~1.440 ⚡/h e gerava ~540. O reator
--   passa a dar 700 ⚡/h (500 no calor; eram 120 e 80) e o 2º reator libera no nível 40: no máximo, gera
--   ~1.770 e gasta ~1.650 sem eletricista (~830 com o eletricista no 3).
-- • A radiação do reator é sorteada a cada 30 min (era de hora em hora), 1 em 200 por bicho.
-- ------------------------------------------------------------
update public.fazenda_itens
   set descricao = 'Gera 700 ⚡/h sem parar, de dia e de noite (500 na onda de calor, para não esquentar). No nível 40 dá para ter o 2º. Cuidado com a radiação: a cada 30 min, cada bicho da fazenda tem 1 em 200 de ficar radioativo por meia hora (dá o produto dele a cada 2 minutos, direto no celeiro) e, no fim, 1 em 200 de não resistir.'
 where id = 'reator';

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
  select jsonb_build_object(
           'solar', round(avg(case when fazenda_dia_em(t)
                                   then case c when 'sol' then 12 when 'calor' then 14 when 'vento' then 10 when 'nublado' then 5 else 3 end
                                   else 0 end)::numeric, 1),
           'eolica', round(avg(case when calmo then 3
                                    else case c when 'vento' then 30 when 'chuva' then 14 when 'nublado' then 10 when 'sol' then 8 else 5 end end)::numeric, 1),
           'reator', round(avg(case c when 'calor' then 500 else 700 end)::numeric, 1),
           'biomassa', 50)
    into v
    from (select t, fazenda_clima_em(t) as c, fazenda_vento_calmo(t) as calmo
            from generate_series(date_trunc('hour', now()), date_trunc('hour', now()) + interval '7 days', interval '12 minutes') t) x;
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
           where c.jogador_id = p_jogador and i.efeito in ('solar', 'eolica', 'reator', 'biomassa')
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

select public.fazenda_cache_montar();

-- as funções que já existiam e mudaram

create or replace function public.fazenda_energia_taxa(p_jogador uuid, p_t timestamptz)
returns real language sql stable security definer set search_path = public as $$
  select coalesce(sum(case i.efeito
           when 'solar' then case when fazenda_dia_em(p_t)
                                  then case x.clima when 'sol' then 12 when 'calor' then 14 when 'vento' then 10 when 'nublado' then 5 else 3 end
                                  else 0 end
           when 'eolica' then case when fazenda_vento_calmo(p_t) then 3   -- fase 48: calmaria
                                   else case x.clima when 'vento' then 30 when 'chuva' then 14 when 'nublado' then 10 when 'sol' then 8 else 5 end end
           when 'reator' then case x.clima when 'calor' then 500 else 700 end   -- fase 75: era 120 (80 no calor)
           else 0 end), 0)::real
         -- fase 47: cada alarme gasta 1 ⚡ por hora (a conta só roda para quem tem energia elétrica)
         - (select count(*) from fazenda_construcoes a where a.jogador_id = p_jogador and a.tipo = 'alarme')::real
    from fazenda_construcoes c
    join fazenda_itens i on i.id = c.tipo
    cross join (select fazenda_clima_em(p_t) as clima) x
   where c.jogador_id = p_jogador and i.efeito in ('solar', 'eolica', 'reator');
$$;

-- o limite de cada máquina no nível (null = sem limite)
create or replace function public.fazenda_limite_maquina(p_item text, p_limite int, p_nivel int)
returns int language sql immutable as $$
  select case p_item
           when 'painel_solar' then p_limite + greatest(0, (p_nivel - 16) / 2)
           when 'turbina'      then p_limite + greatest(0, (p_nivel - 17) / 2)
           when 'reator'       then p_limite + (p_nivel >= 40)::int   -- fase 75: o 2º reator no nível 40
           else p_limite end;
$$;

create or replace function public.fazenda_radiacao_regras()
returns jsonb language sql immutable as $$
  -- fase 75: o sorteio é a cada 30 min (era de hora em hora), no máximo os últimos 48 (24 h)
  select '{"chance": 200, "minutos": 30, "cada_seg": 120, "morte": 200, "intervalo_min": 30, "sorteios_max": 48}'::jsonb;
$$;

-- Sorteia as horas que passaram com o reator na fazenda (no máximo as últimas 24) e entrega o que os
-- radioativos deram. Sem reator, para de contar (quem já estava radioativo termina a meia hora).
create or replace function public.fazenda_reator(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_r     jsonb := fazenda_radiacao_regras();
  v_max   int := (v_r->>'sorteios_max')::int;
  v_int   interval := make_interval(mins => (v_r->>'intervalo_min')::int);   -- fase 75: 30 min
  v_desde timestamptz;
  v_n     int;
  v_t     timestamptz;
  a       record;
begin
  if not exists (select 1 from fazenda_construcoes where jogador_id = p_jogador and tipo = 'reator') then
    update fazenda_jogadores set radiacao_em = null where id = p_jogador and radiacao_em is not null;
    perform fazenda_radiacao_fechar(p_jogador, now());
    return;
  end if;
  select radiacao_em into v_desde from fazenda_jogadores where id = p_jogador for update;
  if v_desde is null then   -- o reator acabou de chegar: conta daqui para a frente
    update fazenda_jogadores set radiacao_em = now() where id = p_jogador;
    return;
  end if;
  v_n := floor(extract(epoch from now() - v_desde) / extract(epoch from v_int))::int;
  if v_n > v_max then v_desde := v_desde + v_int * (v_n - v_max); v_n := v_max; end if;
  for k in 1..v_n loop
    v_t := v_desde + v_int * k;
    perform fazenda_radiacao_fechar(p_jogador, v_t);   -- o que acabou antes desta hora fecha primeiro
    for a in update fazenda_animais an
                set radioativo_de = v_t, radioativo_ate = v_t + make_interval(mins => (v_r->>'minutos')::int), radioativo_dado = 0
              where an.jogador_id = p_jogador and an.radioativo_de is null and an.criado_em <= v_t
                and random() < 1.0 / (v_r->>'chance')::int
             returning an.tipo loop
      insert into fazenda_radiacao (jogador_id, animal, evento, produto, qtd, em)
      select p_jogador, a.tipo, 'radioativo', t.produto, (v_r->>'minutos')::int * 60 / (v_r->>'cada_seg')::int, v_t
        from fazenda_animais_tipos t where t.id = a.tipo;
    end loop;
  end loop;
  if v_n > 0 then update fazenda_jogadores set radiacao_em = v_desde + v_int * v_n where id = p_jogador; end if;
  perform fazenda_radiacao_fechar(p_jogador, now());
  delete from fazenda_radiacao where jogador_id = p_jogador and em < now() - interval '7 days';
end;
$$;

-- refaz o cache (os gatilhos chamam; o fim de cada faseN.sql também)
create or replace function public.fazenda_cache_montar()
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  insert into fazenda_cache (chave, valor, em)
  select k, fazenda_cache_valor(k), now()
    from unnest(array['culturas', 'animais_tipos', 'conquistas_tipos', 'ajudantes_tipos', 'melhorias_tipos', 'melhorias']) k
  on conflict (chave) do update set valor = excluded.valor, em = excluded.em;
  delete from fazenda_cache where chave like 'itens:%' or chave like 'energia%';   -- se refazem na próxima vez (fase 75: e a conta da energia)
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

-- permissões
revoke execute on function
  public.fazenda_energia_medias(),
  public.fazenda_energia_conta(uuid),
  public.fazenda_energia_taxa(uuid, timestamptz),
  public.fazenda_limite_maquina(text, int, int),
  public.fazenda_radiacao_regras(),
  public.fazenda_reator(uuid),
  public.fazenda_cache_montar(),
  public.fazenda_estado(uuid)
from public, anon, authenticated;

grant execute on function
  public.fazenda_carregar(text)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- conferência: deve aparecer "Fase 75: reator ~680 ⚡/h em média, 2 reatores no nível 40, radiação a cada 30 min"
select 'Fase 75: reator ' || (public.fazenda_energia_medias()->>'reator')::numeric::int || ' ⚡/h em média, '
       || public.fazenda_limite_maquina('reator', 1, 40) || ' reatores no nível 40, radiação a cada '
       || (public.fazenda_radiacao_regras()->>'intervalo_min') || ' min' as ok;
