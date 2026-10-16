-- ============================================================
-- FAZENDINHA — Fase 60 (etapa 4: materiais raros do píer e o mercador), só o que mudou.
-- Para o banco que já está no ar (com a fase 59): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- ------------------------------------------------------------
-- Fase 60: materiais raros do píer e o mercador (ideias de 15/10, etapa 4).
-- Cinco materiais (tipo 'raro'), que só vão servir no píer (nível 31, no terreno do litoral, etapa
-- 5), mas já aparecem desde o nível 1 e dá para vender na feira. Não vendem para o jogo; na feira, o
-- preço vai da venda (o mínimo, de 100 mil a 300 mil) até o triplo (fazenda_feira_faixa).
-- O mercador: 1 em cada 100 visitas da porteira, ele traz 1 material e troca por frutos fora de época
-- (fazenda_visitante e fazenda_atender). O mais raro vem menos (peso) e pede mais frutos.
-- ------------------------------------------------------------
alter table public.fazenda_culturas drop constraint if exists fazenda_culturas_tipo_chk;
alter table public.fazenda_culturas add constraint fazenda_culturas_tipo_chk check (tipo in ('cultura', 'produto', 'raro'));

insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('madeira_nobre',  'Madeira nobre',     '🪵', 1, 0, 100000, 1, 0, 1, 90, 'raro'),
  ('corda_naval',    'Corda naval',       '🪢', 1, 0, 120000, 1, 0, 1, 91, 'raro'),
  ('pedra_cantaria', 'Pedra de cantaria', '🧱', 1, 0, 150000, 1, 0, 1, 92, 'raro'),
  ('ferro_forjado',  'Ferro forjado',     '⚙️', 1, 0, 200000, 1, 0, 1, 93, 'raro'),
  ('ancora',         'Âncora',            '⚓', 1, 0, 300000, 1, 0, 1, 94, 'raro')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, venda = excluded.venda, xp = excluded.xp,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;

-- quem o mercador traz (peso em 100) e quantos frutos fora de época pede
create or replace function public.fazenda_raros()
returns jsonb language sql immutable as $$
  select '[{"id":"madeira_nobre","peso":30,"frutas":10},{"id":"corda_naval","peso":25,"frutas":12},
           {"id":"pedra_cantaria","peso":20,"frutas":15},{"id":"ferro_forjado","peso":15,"frutas":20},
           {"id":"ancora","peso":10,"frutas":30}]'::jsonb;
$$;

-- raro não vende para o jogo

create or replace function public.fazenda_vender(p_token text, p_item text default null, p_quantidade int default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  r       record;
  v_qtd   int;
  v_ganho int := 0;
  v_valor numeric := 0;   -- valor que conta para o XP (sem o bônus de beleza)
  v_xp    int;
  v_feira int;
  v_sem_xp int := 0;      -- fase 56: quantos itens comprados na feira foram vendidos (sem XP)
begin
  if p_quantidade is not null and p_quantidade <= 0 then
    raise exception 'quantidade_invalida';
  end if;

  -- o que está reservado para os animais fica no celeiro
  for r in
    select ce.item, ce.quantidade - coalesce(rs.quantidade, 0) as livre, ce.da_feira, k.venda, k.tipo, k.nivel_min
      from fazenda_celeiro ce
      join fazenda_culturas k on k.id = ce.item
      left join fazenda_reservas rs on rs.jogador_id = ce.jogador_id and rs.item = ce.item
     where ce.jogador_id = v_id
       and ce.quantidade > coalesce(rs.quantidade, 0)
       and (p_item is null or ce.item = p_item)
       and k.tipo <> 'raro'   -- fase 60: material raro só vende na feira
       for update of ce
  loop
    v_qtd := least(coalesce(p_quantidade, r.livre), r.livre);
    -- fase 56: o que veio da feira sai primeiro e não dá XP (comprar na feira para revender ao
    -- jogo virava XP comprado com moedas); as moedas da venda são as de sempre
    v_feira := least(v_qtd, r.da_feira);
    update fazenda_celeiro set quantidade = quantidade - v_qtd, da_feira = da_feira - v_feira
     where jogador_id = v_id and item = r.item;
    v_ganho := v_ganho + v_qtd * r.venda;
    -- XP da venda: só os produtos (oficinas, bichos, lago, pomar); a planta já deu XP na colheita (fase 41)
    v_valor := v_valor + case when r.tipo <> 'cultura' then (v_qtd - v_feira) * r.venda else 0 end;
    v_sem_xp := v_sem_xp + case when r.tipo <> 'cultura' then v_feira else 0 end;
  end loop;

  v_ganho := (v_ganho * (100 + fazenda_bonus_venda(v_id))) / 100;   -- beleza e caixote
  -- 1 XP a cada 25 moedas do valor; o que sobra fica para a próxima venda
  select floor((venda_resto + v_valor) / 25)::int into v_xp from fazenda_jogadores where id = v_id;
  update fazenda_jogadores
     set moedas = moedas + v_ganho, xp = xp + v_xp, venda_resto = venda_resto + v_valor - v_xp * 25
   where id = v_id;
  if v_ganho > 0 then
    perform fazenda_missao(v_id, 'vender', v_ganho);
  end if;

  return jsonb_build_object('ganho', v_ganho, 'xp', v_xp, 'sem_xp', v_sem_xp, 'estado', fazenda_estado(v_id));
end;
$$;

-- na feira, raro vai do mínimo dele até o triplo

create or replace function public.fazenda_feira_faixa(p_item text)
returns int[] language sql stable security definer set search_path = public as $$
  select case when k.tipo = 'raro'   -- fase 60: material raro vai de venda (o mínimo) até o triplo
              then array[k.venda, k.venda * 3]
              else array[greatest(1, floor(k.venda * (fazenda_feira_regras()->>'min')::numeric))::int,
                         greatest(1, ceil(k.venda * (fazenda_feira_regras()->>'max')::numeric))::int] end
    from fazenda_culturas k where k.id = p_item and k.venda > 0;
$$;

-- o mercador: 1 em cada 100 visitas

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
  -- fase 60: o mercador (1 em cada 100 visitas, desde o nível 1) troca 1 material raro do píer por
  -- frutos fora de época (só tem quem guardou da estação dele ou plantou na estufa)
  if ('x' || substr(v_h, 9, 4))::bit(16)::int % 100 = 0 then
    select y.r->>'id', (y.r->>'frutas')::int into v_raro, v_qtd
      from (select x.r, sum((x.r->>'peso')::int) over (order by x.ord) as acum
              from jsonb_array_elements(fazenda_raros()) with ordinality as x(r, ord)) y
     where y.acum > ('x' || substr(v_h, 13, 4))::bit(16)::int % 100
     order by y.acum limit 1;
    select c.* into k from fazenda_culturas c
     where c.tipo = 'cultura' and c.estacao is not null and c.estacao <> fazenda_estacao_em(now())
     order by md5(v_h || c.id) limit 1;
    return jsonb_build_object('slot', v_slot, 'tipo', 'mercador', 'ate', to_timestamp((v_slot + 1) * 10800),
                              'item', k.id, 'qtd', v_qtd, 'raro', v_raro, 'paga', 0, 'xp', 0);
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
     where c.tipo = 'produto' and c.ordem < 40 and (
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

create or replace function public.fazenda_atender(p_token text, p_entregar boolean)
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
  perform 1 from fazenda_jogadores where id = v_id for update;
  if not coalesce(p_entregar, false) then
    insert into fazenda_visitas_npc (jogador_id, slot, resposta) values (v_id, (v->>'slot')::bigint, 'dispensou');
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
    else
      update fazenda_jogadores set moedas = moedas + (v->>'paga')::int, xp = xp + (v->>'xp')::int where id = v_id;
      perform fazenda_missao(v_id, 'vender', (v->>'paga')::int);
    end if;
  end if;
  insert into fazenda_visitas_npc (jogador_id, slot, resposta) values (v_id, (v->>'slot')::bigint, 'entregou');
  insert into fazenda_estatisticas (jogador_id) values (v_id) on conflict do nothing;
  update fazenda_estatisticas set pedidos = pedidos + 1 where jogador_id = v_id;
  return jsonb_build_object('resposta', 'entregou', 'visita', v, 'adubados', v_n, 'pagou', v_preco, 'estado', fazenda_estado(v_id));
end;
$$;

revoke execute on function public.fazenda_raros() from public, anon, authenticated;

-- conferência: deve aparecer "5 materiais raros; âncora na feira de 300000 a 900000"
select (select count(*) from public.fazenda_culturas where tipo = 'raro') || ' materiais raros; âncora na feira de '
    || (public.fazenda_feira_faixa('ancora'))[1] || ' a ' || (public.fazenda_feira_faixa('ancora'))[2] as ok;
