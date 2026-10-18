-- ============================================================
-- FAZENDINHA — Fase 76 (visita a cada 10 minutos, pedidos que crescem com o nível e pedidos fora do nível),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 75): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 75 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_energia_conta')) then
    raise exception 'Rode o fase75.sql antes deste (a fase 75 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 76: visita na porteira a cada 10 min (era 3 h). O mercador e o Perks continuam no bloco de 3 h,
-- com a mesma chance de antes (1 em 100 e 1 em 30 blocos), e ficam até o fim dele. O tamanho do pedido
-- sai do esforço: uns 0,25% do nível em XP de colheita (o caminhoneiro, 3x), com pelo menos 2 itens e
-- sem os peixes raros da pescaria; assim cresce com o nível. Do 15 em diante, metade pede produto em vez
-- de semente, e de 15% a 30% pedem algo de até 8 níveis acima (feira ou chat), pagando o dobro do celeiro
-- e 3x o XP. O XP fica entre 0,1% e 1% do nível por visita.
-- fazenda_atender apaga as visitas respondidas de mais de 1 dia (a tabela não cresce 18x) e ganhou p_slot:
-- o jogo diz qual visita mostrou, para não entregar à que chegou depois (a assinatura antiga sai).
-- ------------------------------------------------------------
drop function if exists public.fazenda_atender(text, boolean);

-- as funções que já existiam e mudaram

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
  select fazenda_nivel(xp) into v_nivel from fazenda_jogadores where id = p_jogador;
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

-- Atende a visita: entregar (vende o pedido pelo preço dela, ou compra o adubo da mascate) ou
-- dispensar (ela vai embora e volta outra pessoa no próximo bloco de 3 horas)
create or replace function public.fazenda_atender(p_token text, p_entregar boolean, p_slot bigint default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v       jsonb := fazenda_visitante(v_id);
  v_tem   int;
  v_n     int := 0;
  v_preco int := 0;
begin
  if v is null then raise exception 'sem_visita'; end if;
  -- fase 76: a visita muda a cada 10 min; o jogo diz qual mostrou, para não entregar à que chegou depois
  if p_slot is not null and p_slot <> (v->>'slot')::bigint then raise exception 'visita_mudou'; end if;
  perform 1 from fazenda_jogadores where id = v_id for update;
  if not coalesce(p_entregar, false) then
    insert into fazenda_visitas_npc (jogador_id, slot, resposta) values (v_id, (v->>'slot')::bigint, 'dispensou');
    delete from fazenda_visitas_npc where jogador_id = v_id and em < now() - interval '1 day';   -- fase 76
    return jsonb_build_object('resposta', 'dispensou', 'estado', fazenda_estado(v_id));
  end if;

  if v->>'tipo' = 'mascate' then
    -- adubo: os canteiros crescendo, até 8; paga só pelos que adubou
    with alvo as (
      select cc.posicao from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
       where cc.jogador_id = v_id and cc.estado = 'plantado' and not cc.adubado
         and now() < cc.plantado_em + make_interval(secs => k.tempo_seg)
       order by cc.plantado_em limit (v->>'canteiros')::int)
    select count(*) into v_n from alvo;
    if v_n = 0 then raise exception 'sem_canteiros_crescendo'; end if;
    v_preco := ceil((v->>'preco')::numeric * v_n / (v->>'canteiros')::int);
    if (select moedas from fazenda_jogadores where id = v_id) < v_preco then raise exception 'moedas_insuficientes'; end if;
    update fazenda_canteiros c set adubado = true
      from (select cc.posicao from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
             where cc.jogador_id = v_id and cc.estado = 'plantado' and not cc.adubado
               and now() < cc.plantado_em + make_interval(secs => k.tempo_seg)
             order by cc.plantado_em limit (v->>'canteiros')::int) alvo
     where c.jogador_id = v_id and c.posicao = alvo.posicao;
    update fazenda_jogadores set moedas = moedas - v_preco where id = v_id;
  else
    select ce.quantidade - coalesce((select quantidade from fazenda_reservas where jogador_id = v_id and item = ce.item), 0)
      into v_tem from fazenda_celeiro ce where ce.jogador_id = v_id and ce.item = v->>'item' for update;
    if coalesce(v_tem, 0) < (v->>'qtd')::int then raise exception 'falta_pedido'; end if;
    update fazenda_celeiro set quantidade = quantidade - (v->>'qtd')::int where jogador_id = v_id and item = v->>'item';
    if v->>'tipo' = 'mercador' then   -- fase 60: em troca, 1 material raro
      insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, v->>'raro', 1)
      on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
    elsif v->>'tipo' = 'perks' then   -- fase 66: em troca, as luvas do Perks
      insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, 'luva_perks', (v->>'luvas')::int)
      on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
    else
      update fazenda_jogadores set moedas = moedas + (v->>'paga')::int, xp = xp + (v->>'xp')::int where id = v_id;
      perform fazenda_missao(v_id, 'vender', (v->>'paga')::int);
    end if;
  end if;
  insert into fazenda_visitas_npc (jogador_id, slot, resposta) values (v_id, (v->>'slot')::bigint, 'entregou');
  -- fase 76: com uma visita a cada 10 min, as respondidas de mais de 1 dia saem (só a do slot atual importa)
  delete from fazenda_visitas_npc where jogador_id = v_id and em < now() - interval '1 day';
  insert into fazenda_estatisticas (jogador_id) values (v_id) on conflict do nothing;
  update fazenda_estatisticas set pedidos = pedidos + 1 where jogador_id = v_id;
  return jsonb_build_object('resposta', 'entregou', 'visita', v, 'adubados', v_n, 'pagou', v_preco, 'estado', fazenda_estado(v_id));
end;
$$;

-- permissões
revoke execute on function
  public.fazenda_visitante(uuid),
  public.fazenda_atender(text, boolean, bigint)
from public, anon, authenticated;

grant execute on function
  public.fazenda_atender(text, boolean, bigint)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- conferência: deve aparecer "Fase 76: visita a cada 10 min, atender com p_slot"
select 'Fase 76: visita a cada ' || case when position('/ 600)' in prosrc) > 0 then '10' else '?' end || ' min, atender '
       || case when (select count(*) from pg_proc where proname = 'fazenda_atender') = 1
                and exists (select 1 from pg_proc where proname = 'fazenda_atender' and pronargs = 3) then 'com p_slot' else 'ERRADO' end as ok
  from pg_proc where proname = 'fazenda_visitante';
