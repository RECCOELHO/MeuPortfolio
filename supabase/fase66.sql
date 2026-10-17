-- ============================================================
-- FAZENDINHA — Fase 66 (o Perks e a luva, o relatório da planta murcha e o limite do descanso),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 65): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- ------------------------------------------------------------
-- Fase 66: o Perks e a luva, o relatório da planta murcha e o limite do descanso.
-- • O Perks (homenagem ao 1º do ranking): 1 em cada 30 visitas da porteira, do nível 3 em diante, pede
--   uma planta fácil em número grande (fazenda_perks) e paga com 4 luvas. A luva do Perks (rara: só na
--   feira) deixa pegar 1 canteiro do vizinho mesmo com alarme (fazenda_acao_vizinho 'pegar_luva'); o
--   canteiro sem alarme não gasta luva. O diário do dono mostra quem passou com a luva.
-- • Por que murchou: antes de o lavrador arar as murchas, fazenda_trabalhar registra cada planta que
--   murchou sem ninguém colher (fazenda_murchas), com o motivo: sem colhedor, ele estava descansando
--   (a janela do último descanso fica em fazenda_ajudantes), a fazenda ficou fechada mais de 8 h, ou ele
--   não deu conta (canteiro demais para o ritmo ou a energia). O jogo mostra o relatório ao abrir.
-- • Mandar descansar só com menos de 75% de energia (fazenda_ajudante_descansar: ajudante_disposto).
-- ------------------------------------------------------------
alter table public.fazenda_visitas add column if not exists luva boolean not null default false;   -- pegou com a luva do Perks
alter table public.fazenda_ajudantes add column if not exists ultimo_descanso_de timestamptz;
alter table public.fazenda_ajudantes add column if not exists ultimo_descanso_ate timestamptz;
alter table public.fazenda_ajudantes add column if not exists ultimo_descanso_motivo text;   -- cama, sombra ou mandado

insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('luva_perks', 'Luva do Perks', '🧤', 1, 0, 50000, 1, 0, 1, 104, 'raro')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, venda = excluded.venda, xp = excluded.xp,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;

-- o que o Perks pede (planta fácil, do ano todo, em número grande) e quantas luvas paga
create or replace function public.fazenda_perks()
returns jsonb language sql immutable as $$
  select '{"luvas": 4, "nivel": 3, "chance": 30,
           "pedidos": [{"id": "alface", "qtd": 1500}, {"id": "cenoura", "qtd": 1200}, {"id": "batata", "qtd": 1000},
                       {"id": "milho", "qtd": 1000}, {"id": "tomate", "qtd": 800}, {"id": "abobora", "qtd": 600}]}'::jsonb;
$$;

-- as plantas que murcharam sem ninguém colher, com o motivo (os últimos 7 dias)
create table if not exists public.fazenda_murchas (
  jogador_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  posicao     smallint not null,
  plantado_em timestamptz not null,
  cultura     text not null references public.fazenda_culturas(id),
  murchou_em  timestamptz not null,
  motivo      text not null check (motivo in ('sem_colhedor', 'descansando', 'fechada', 'nao_deu_conta')),
  detalhe     jsonb,
  visto       boolean not null default false,
  primary key (jogador_id, posicao, plantado_em)
);
alter table public.fazenda_murchas enable row level security;
revoke all on public.fazenda_murchas from anon, authenticated;

-- Registra o que está murcho e ainda não tem motivo. Roda dentro de fazenda_trabalhar, depois do
-- colhedor e antes do lavrador (que ara as murchas).
create or replace function public.fazenda_murchas_registrar(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  h      record;
  v_tem  boolean;
begin
  select a.nivel, a.ultimo_descanso_de, a.ultimo_descanso_ate, a.ultimo_descanso_motivo into h
    from fazenda_ajudantes a join fazenda_ajudantes_tipos t on t.id = a.tipo
   where a.jogador_id = p_jogador and t.funcao = 'colher' limit 1;
  v_tem := found;
  insert into fazenda_murchas (jogador_id, posicao, plantado_em, cultura, murchou_em, motivo, detalhe)
  select p_jogador, c.posicao, c.plantado_em, c.cultura, m.em, x.motivo,
         case x.motivo
           when 'descansando' then jsonb_build_object('como', h.ultimo_descanso_motivo,
                                                      'horas', round(extract(epoch from h.ultimo_descanso_ate - h.ultimo_descanso_de) / 3600))
           when 'nao_deu_conta' then jsonb_build_object('nivel', h.nivel, 'ritmo', fazenda_ritmo(h.nivel))
         end
    from fazenda_canteiros c
    join fazenda_culturas k on k.id = c.cultura
    cross join lateral (select c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) as em) m
    cross join lateral (select case
             when not v_tem then 'sem_colhedor'
             when h.ultimo_descanso_de is not null and m.em >= h.ultimo_descanso_de and m.em < h.ultimo_descanso_ate then 'descansando'
             when m.em < now() - interval '8 hours' then 'fechada'
             else 'nao_deu_conta' end as motivo) x
   where c.jogador_id = p_jogador and c.estado = 'plantado' and now() >= m.em and m.em > now() - interval '7 days'
  on conflict (jogador_id, posicao, plantado_em) do nothing;
  delete from fazenda_murchas where jogador_id = p_jogador and murchou_em < now() - interval '7 days';
end;
$$;

-- o Perks na porteira e a troca pelas luvas

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
    elsif v->>'tipo' = 'perks' then   -- fase 66: em troca, as luvas do Perks
      insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, 'luva_perks', (v->>'luvas')::int)
      on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
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

-- a luva no vizinho: passa pelo alarme e gasta 1 (só no canteiro protegido)

drop function if exists public.fazenda_pegar_um(uuid, uuid, int);
create or replace function public.fazenda_pegar_um(p_ator uuid, p_dono uuid, p_posicao int, p_luva boolean default false)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  c        record;
  k        record;
  v_maduro timestamptz;
  v_qtd    int;
  v_luva   boolean := false;
begin
  select * into c from fazenda_canteiros
   where jogador_id = p_dono and posicao = p_posicao
     for update;
  if not found or c.estado <> 'plantado' then
    raise exception 'nao_maduro';
  end if;
  select * into k from fazenda_culturas where id = c.cultura;
  v_maduro := c.plantado_em + make_interval(secs => k.tempo_seg);
  if now() < v_maduro then
    raise exception 'nao_maduro';
  end if;
  if now() >= v_maduro + make_interval(secs => greatest(k.tempo_seg * 2, 3600)) then
    raise exception 'murchou';
  end if;
  if fazenda_protegido(p_dono, 'alarme', c.x, c.y) and fazenda_alarme_ligado(p_dono) then
    if not coalesce(p_luva, false) then raise exception 'alarme'; end if;
    v_luva := true;   -- fase 66: passa com a luva do Perks (gasta lá embaixo, se der para pegar)
  end if;
  if exists (select 1 from fazenda_visitas
              where tipo = 'roubo' and ator_id = p_ator and dono_id = p_dono
                and posicao = p_posicao and plantado_em = c.plantado_em) then
    raise exception 'ja_pegou';
  end if;
  if c.roubado >= fazenda_limite_roubo(k.rendimento) then
    raise exception 'nada_pra_pegar';
  end if;
  if (select count(*) from fazenda_visitas
       where ator_id = p_ator and tipo = 'roubo' and criado_em > now() - interval '1 day') >= 40 then
    raise exception 'limite_pegadas';
  end if;

  if v_luva then
    update fazenda_celeiro set quantidade = quantidade - 1
     where jogador_id = p_ator and item = 'luva_perks'
       and quantidade - coalesce((select quantidade from fazenda_reservas where jogador_id = p_ator and item = 'luva_perks'), 0) >= 1;
    if not found then raise exception 'sem_luva'; end if;
  end if;

  v_qtd := least(2 + (random() < 0.4)::int, fazenda_limite_roubo(k.rendimento) - c.roubado);
  if fazenda_protegido(p_dono, 'cerca', c.x, c.y) then
    v_qtd := least(v_qtd, 1);   -- cerca ou placa por perto
  end if;

  update fazenda_canteiros set roubado = roubado + v_qtd
   where jogador_id = p_dono and posicao = p_posicao;
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  values (p_ator, k.id, v_qtd)
  on conflict (jogador_id, item)
  do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd, luva)
  values (p_ator, p_dono, 'roubo', p_posicao, c.plantado_em, k.id, v_qtd, v_luva);
  perform fazenda_missao(p_ator, 'pegar', v_qtd);

  return v_qtd;
end;
$$;

create or replace function public.fazenda_acao_vizinho(p_token text, p_vizinho uuid, p_acao text, p_posicoes int[])
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id     uuid := fazenda_auth(p_token);
  v_pos    int;
  v_qtd    int;
  v_result jsonb := '{}'::jsonb;
  v_feitos int := 0;
begin
  if p_vizinho is null or p_vizinho = v_id then
    raise exception 'propria_fazenda';
  end if;
  if not exists (select 1 from fazenda_jogadores where id = p_vizinho and banido_em is null) then
    raise exception 'vizinho_invalido';
  end if;
  if p_acao not in ('pegar', 'pegar_luva', 'ajudar', 'salvar') then   -- fase 66: pegar_luva (a luva do Perks)
    raise exception 'acao_invalida';
  end if;
  if p_posicoes is null or array_length(p_posicoes, 1) is null then
    raise exception 'nada_a_fazer';
  end if;
  if array_length(p_posicoes, 1) > 100 then
    raise exception 'acao_invalida';
  end if;

  perform fazenda_tick(p_vizinho);

  foreach v_pos in array p_posicoes loop
    begin
      if p_acao in ('pegar', 'pegar_luva') then
        v_qtd := fazenda_pegar_um(v_id, p_vizinho, v_pos, p_acao = 'pegar_luva');
      elsif p_acao = 'salvar' then
        v_qtd := fazenda_salvar_um(v_id, p_vizinho, v_pos);
      else
        v_qtd := fazenda_ajudar_um(v_id, p_vizinho, v_pos);
      end if;
      v_feitos := v_feitos + 1;
      v_result := v_result || jsonb_build_object(v_pos::text, v_qtd);
    exception when others then
      -- com um canteiro só, o erro volta para a tela; em lote, pula o canteiro
      if array_length(p_posicoes, 1) = 1 then
        raise;
      end if;
    end;
  end loop;

  return jsonb_build_object(
    'feitos', v_feitos,
    'resultado', v_result,
    'vizinho', fazenda_vizinho(p_vizinho, v_id),
    'estado', fazenda_estado(v_id)
  );
end;
$$;

-- os ajudantes: a janela do descanso fica guardada, as murchas ganham motivo e o "mandar descansar"
-- só com menos de 75% de energia

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
    v_custo := 100 / (fazenda_ritmo(a.nivel) * 8);
    v_log := '{}'::jsonb;
    -- fase 43: com o café (diamantes) o tempo dentro dele vale em dobro
    v_seg := extract(epoch from now() - a.atualizado_em)::real
           + case when v_cafe_ate is null then 0
                  else greatest(extract(epoch from least(now(), v_cafe_ate) - greatest(a.atualizado_em, v_cafe_de))::real, 0) end;
    v_cred := least(a.credito + v_seg / 3600 * fazenda_ritmo(a.nivel), fazenda_ritmo(a.nivel) * 8);
    v_n := least(floor(v_cred), floor(a.energia / v_custo + 0.001))::int;   -- fase 59: e o que a energia deixa
    v_feito := 0;

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
        begin perform fazenda_aplicar(p_jogador, case when c.murcha then 'colher_tarde' else 'colher' end, c.posicao, null, true); v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'colheu');
        exception when others then null; end;
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
        begin perform fazenda_aplicar(p_jogador, 'arar', c.posicao, null, true); v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'arou');
        exception when others then null; end;
      end loop;
      -- sobrou tempo: aduba os canteiros que estão crescendo (+1 item na colheita de cada um)
      if v_feito < v_n then
        for c in
          select cc.posicao from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
           where cc.jogador_id = p_jogador and cc.estado = 'plantado' and not cc.adubado
             and now() < cc.plantado_em + make_interval(secs => k.tempo_seg)
           order by cc.plantado_em limit v_n - v_feito
        loop
          begin perform fazenda_aplicar(p_jogador, 'adubar', c.posicao, null, true); v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'adubou');
          exception when others then null; end;
        end loop;
      end if;

    elsif a.funcao = 'plantar' and coalesce((select carregado_antes > now() - interval '2 minutes' from fazenda_jogadores where id = p_jogador), false) then
      -- com o jogador na fazenda ela descansa (o tempo online não conta para ela)
      update fazenda_ajudantes set atualizado_em = now() where jogador_id = p_jogador and tipo = a.tipo;
      continue;

    elsif v_n > 0 and a.funcao = 'plantar' then
      v_nivel := fazenda_nivel((select xp from fazenda_jogadores where id = p_jogador));
      for c in
        select posicao from fazenda_canteiros
         where jogador_id = p_jogador and estado = 'arado' order by posicao limit v_n
      loop
        -- rodízio com todas as sementes da estação que o nível libera: a menos plantada primeiro,
        -- pulando as que o dinheiro não paga
        v_ok := false;
        for v_sem in
          select k.id from fazenda_culturas k
           where k.tipo = 'cultura' and k.nivel_min <= v_nivel
             and (k.estacao is null or k.estacao = fazenda_estacao_em(now()))
             and k.custo <= (select moedas from fazenda_jogadores where id = p_jogador)
           order by (select count(*) from fazenda_canteiros cc
                      where cc.jogador_id = p_jogador and cc.estado = 'plantado' and cc.cultura = k.id), k.ordem
        loop
          begin
            perform fazenda_aplicar(p_jogador, 'plantar', c.posicao, v_sem, true);
            v_feito := v_feito + 1; v_ok := true; v_log := fazenda_conta(v_log, 'plantou');
            exit;
          exception when others then null;
          end;
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
        begin
          if c.erva and v_feito < v_n then perform fazenda_aplicar(p_jogador, 'erva', c.posicao, null, true); v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'erva'); end if;
          if c.praga and v_feito < v_n then perform fazenda_aplicar(p_jogador, 'praga', c.posicao, null, true); v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'praga'); end if;
          if c.seco and v_feito < v_n then perform fazenda_aplicar(p_jogador, 'seco', c.posicao, null, true); v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'seco'); end if;
        exception when others then null;
        end;
      end loop;

    elsif v_n > 0 and a.funcao = 'animal' then
      for m in
        select an.id, an.alimentado_em, t.tempo_seg from fazenda_animais an join fazenda_animais_tipos t on t.id = an.tipo
         where an.jogador_id = p_jogador and an.tipo = a.alvo order by an.id
      loop
        exit when v_feito >= v_n;
        -- coletar e dar ração em blocos separados: faltar ração não desfaz a coleta
        begin
          if m.alimentado_em is not null and now() >= m.alimentado_em + make_interval(secs => m.tempo_seg) then
            perform fazenda_animal_um(p_jogador, m.id, 'coletar', true);
            v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'coletou');
            m.alimentado_em := null;
          end if;
        exception when others then null;
        end;
        begin
          if m.alimentado_em is null and v_feito < v_n then
            perform fazenda_animal_um(p_jogador, m.id, 'alimentar', true);   -- sem ração no celeiro: pula
            v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'alimentou');
          end if;
        exception when others then null;
        end;
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
  end loop;
  if not v_reg then perform fazenda_murchas_registrar(p_jogador); end if;   -- fase 66
end;
$$;

create or replace function public.fazenda_ajudante_descansar(p_token text, p_tipo text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
begin
  perform fazenda_trabalhar(v_id);   -- fecha o trabalho de até agora antes
  if exists (select 1 from fazenda_ajudantes where jogador_id = v_id and tipo = p_tipo and (descanso_ate is null or descanso_ate <= now())
               and energia >= 75) then
    raise exception 'ajudante_disposto';
  end if;
  if exists (select 1 from fazenda_ajudantes where jogador_id = v_id and tipo = p_tipo and (descanso_ate is null or descanso_ate <= now()))
     and fazenda_camas_ocupadas(v_id) >= fazenda_camas(v_id) then
    raise exception 'sem_cama';   -- todas as camas das casinhas ocupadas
  end if;
  update fazenda_ajudantes h
     set descanso_ate = now() + interval '1 hour', descanso_motivo = 'mandado', descanso_casa = true, credito = 0, atualizado_em = now(),
         ultimo_descanso_de = now(), ultimo_descanso_ate = now() + interval '1 hour', ultimo_descanso_motivo = 'mandado'
   where h.jogador_id = v_id and h.tipo = p_tipo and (h.descanso_ate is null or h.descanso_ate <= now())
     and exists (select 1 from fazenda_ajudantes_tipos t where t.id = h.tipo and t.funcao <> 'energia');
  if not found then raise exception 'ajudante_descansando'; end if;
  return jsonb_build_object('estado', fazenda_estado(v_id));
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
     where id = p_jogador;
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
  return v_json;
end;
$$;

revoke execute on function
  public.fazenda_pegar_um(uuid, uuid, int, boolean),
  public.fazenda_perks(),
  public.fazenda_murchas_registrar(uuid)
from public, anon, authenticated;

-- conferência: deve aparecer "Perks: 4 luvas, 1 em cada 30 visitas; descanso abaixo de 75%"
select 'Perks: ' || (public.fazenda_perks()->>'luvas') || ' luvas, 1 em cada ' || (public.fazenda_perks()->>'chance')
    || ' visitas; descanso abaixo de '
    || case when pg_get_functiondef('public.fazenda_ajudante_descansar(text, text)'::regprocedure) like '%>= 75%' then '75%' else '?' end as ok;
