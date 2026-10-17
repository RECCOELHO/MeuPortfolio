-- ============================================================
-- FAZENDINHA — Fase 65 (a tunagem do barco: peças, pintura e o kit de expedição), só o que mudou.
-- Para o banco que já está no ar (com a fase 64): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

alter table public.fazenda_jogadores add column if not exists barco_visual jsonb;          -- a pintura do barco (casco, faixa, bandeira)

-- as peças entram no catálogo de melhorias (mar = true, peca = true), com os materiais de cada nível

create or replace function public.fazenda_melhorias_tipos()
returns jsonb language sql immutable as $$
  select '[{"id":"adubo","nome":"Adubo premium","descricao":"As plantas nascem adiantadas: crescem 10%, 20% e 30% mais rápido (soma com o girassol e a estufa).",
            "niveis":[{"nivel":23,"custo":50000,"valor":0.1},{"nivel":26,"custo":150000,"valor":0.2},{"nivel":29,"custo":300000,"valor":0.3}]},
           {"id":"pomar","nome":"Pomar fértil","descricao":"As árvores do pomar dão frutas 15% e 30% mais rápido.",
            "niveis":[{"nivel":24,"custo":80000,"valor":0.15},{"nivel":28,"custo":200000,"valor":0.3}]},
           {"id":"pes","nome":"Mais pés de fruta","descricao":"Mais 1 e mais 2 pés de cada fruta no pomar, além dos 4 que os terrenos dão.",
            "niveis":[{"nivel":25,"custo":60000,"valor":1},{"nivel":30,"custo":120000,"valor":2}]},
           {"id":"barco","nome":"Barco","mar":true,"descricao":"Barco maior vai mais longe: o cardume é maior, enche mais rápido e tem peixe que o bote não alcança.",
            "base":{"nome":"Bote","valor":1,"intervalo":900,"max":16},
            "niveis":[{"nivel":34,"custo":400000,"valor":2,"nome":"Traineira","intervalo":720,"max":24},
                      {"nivel":37,"custo":900000,"valor":3,"nome":"Barco de pesca","intervalo":600,"max":32},
                      {"nivel":40,"custo":1800000,"valor":4,"nome":"Pesqueiro","intervalo":480,"max":40},
                      {"nivel":43,"custo":3500000,"valor":5,"nome":"Barco oceânico","intervalo":360,"max":48}]},
           {"id":"vara","nome":"Vara","mar":true,"descricao":"Vara melhor dá mais tempo para fisgar e puxa peixe maior.",
            "base":{"nome":"Vara de bambu","valor":1,"janela":900},
            "niveis":[{"nivel":32,"custo":150000,"valor":2,"nome":"Vara de fibra","janela":1100},
                      {"nivel":35,"custo":400000,"valor":3,"nome":"Molinete","janela":1300},
                      {"nivel":38,"custo":900000,"valor":4,"nome":"Carretilha","janela":1500},
                      {"nivel":41,"custo":2000000,"valor":5,"nome":"Vara profissional","janela":1800}]},
           {"id":"marinheiro","nome":"Marinheiro","mar":true,"descricao":"O Seu Nonato pesca sozinho enquanto você cuida da fazenda: o cesto dele enche por até 8 horas. Cada nível pesca mais rápido.",
            "niveis":[{"nivel":33,"custo":250000,"valor":1,"nome":"Seu Nonato","intervalo":1800,"max":16},
                      {"nivel":36,"custo":700000,"valor":2,"nome":"Seu Nonato com rede","intervalo":1200,"max":24},
                      {"nivel":39,"custo":1800000,"valor":3,"nome":"Seu Nonato com barco de apoio","intervalo":720,"max":40}]},
           {"id":"motor","nome":"Motor","mar":true,"peca":true,"descricao":"Motor mais forte vai e volta mais rápido: o cardume enche mais rápido.",
            "niveis":[{"nivel":33,"custo":200000,"valor":0.1,"nome":"Motor de popa","itens":{"ferro_forjado":1}},
                      {"nivel":39,"custo":600000,"valor":0.2,"nome":"Motor a diesel","itens":{"ferro_forjado":2,"ancora":1}},
                      {"nivel":44,"custo":1500000,"valor":0.3,"nome":"Motor turbo","itens":{"ferro_forjado":3,"ancora":2,"perola_negra":1}}]},
           {"id":"sonar","nome":"Sonar","mar":true,"peca":true,"descricao":"Acha os cardumes de peixe grande e as ostras: mais peixe grande e mais pérola negra.",
            "niveis":[{"nivel":35,"custo":250000,"valor":1,"perola":150,"nome":"Sonar simples","itens":{"corda_naval":2}},
                      {"nivel":41,"custo":800000,"valor":2,"perola":100,"nome":"Sonar colorido","itens":{"corda_naval":2,"perola_negra":1}},
                      {"nivel":45,"custo":2000000,"valor":3,"perola":70,"nome":"Sonar de varredura","itens":{"perola_negra":2,"marlim":1}}]},
           {"id":"porao","nome":"Porão","mar":true,"peca":true,"descricao":"Guarda o peixe no gelo: às vezes uma fisgada traz 2 peixes.",
            "niveis":[{"nivel":36,"custo":300000,"valor":0.15,"nome":"Caixa de gelo","itens":{"madeira_nobre":2}},
                      {"nivel":42,"custo":1000000,"valor":0.3,"nome":"Porão refrigerado","itens":{"madeira_nobre":3,"pedra_cantaria":2}},
                      {"nivel":45,"custo":2500000,"valor":0.45,"nome":"Câmara fria","itens":{"pedra_cantaria":2,"ferro_forjado":2,"perola_negra":1}}]},
           {"id":"rede","nome":"Rede de arrasto","mar":true,"peca":true,"descricao":"Para o marinheiro: ele pesca mais rápido (e o cesto continua guardando 8 horas).",
            "niveis":[{"nivel":37,"custo":300000,"valor":0.15,"nome":"Rede de arrasto","itens":{"corda_naval":2}},
                      {"nivel":43,"custo":1200000,"valor":0.3,"nome":"Rede dupla","itens":{"corda_naval":3,"ancora":1}}]},
           {"id":"expedicao","nome":"Kit de expedição","mar":true,"peca":true,"descricao":"Bússola, mapa e tanque extra: deixa o barco oceânico pronto para viajar às ilhas (nível 46, na próxima expansão).",
            "niveis":[{"nivel":45,"custo":3000000,"valor":1,"nome":"Kit de expedição","itens":{"perola_negra":3,"marlim":2,"ancora":2}}]}]'::jsonb;
$$;

-- o motor e a rede mudam o ritmo; o sonar acha mais peixe grande e mais pérola; o porão traz 2 às vezes

create or replace function public.fazenda_mar_item(p_jogador uuid, p_id text)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when x.i is null then null
              when p_id = 'barco' and fazenda_melhoria(p_jogador, 'motor') > 0
                then x.i || jsonb_build_object('intervalo', round((x.i->>'intervalo')::int * (1 - fazenda_melhoria(p_jogador, 'motor')))::int)
              when p_id = 'marinheiro' and fazenda_melhoria(p_jogador, 'rede') > 0
                then x.i || jsonb_build_object('intervalo', round((x.i->>'intervalo')::int * (1 - fazenda_melhoria(p_jogador, 'rede')))::int,
                                               'max', ceil((x.i->>'max')::int / (1 - fazenda_melhoria(p_jogador, 'rede'))::numeric)::int)
              else x.i end
    from (select case when coalesce(g.nivel, 0) = 0 then m->'base' else m->'niveis'->(g.nivel - 1) end as i
            from jsonb_array_elements(fazenda_melhorias_tipos()) m
            left join fazenda_melhorias g on g.jogador_id = p_jogador and g.id = p_id
           where m->>'id' = p_id) x;
$$;

create or replace function public.fazenda_mar_perola(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select coalesce((fazenda_mar_item(p_jogador, 'sonar')->>'perola')::int, (fazenda_mar_regras()->>'perola')::int);
$$;

create or replace function public.fazenda_mar_estado(p_jogador uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when j.pier_em is not null then jsonb_build_object(
           'barco', b.i, 'vara', v.i, 'marinheiro', m.i,
           'cardume', jsonb_build_object('desde', j.mar_em, 'intervalo', (b.i->>'intervalo')::int, 'max', (b.i->>'max')::int),
           'cesto', case when m.i is not null then
                      jsonb_build_object('desde', j.marinheiro_em, 'intervalo', (m.i->>'intervalo')::int, 'max', (m.i->>'max')::int) end,
           'peixes', (select jsonb_agg(jsonb_build_object('id', t.peixe, 'chance', t.chance))
                        from fazenda_mar_peixes((b.i->>'valor')::int, (v.i->>'valor')::int + fazenda_melhoria(p_jogador, 'sonar')::int) t),
           'regras', fazenda_mar_regras(),
           'perola', fazenda_mar_perola(p_jogador),                  -- fase 65: o sonar acha mais pérola
           'visual', coalesce(j.barco_visual, '{}'::jsonb)) end
    from fazenda_jogadores j
    cross join lateral (select fazenda_mar_item(p_jogador, 'barco') as i) b
    cross join lateral (select fazenda_mar_item(p_jogador, 'vara') as i) v
    cross join lateral (select fazenda_mar_item(p_jogador, 'marinheiro') as i) m
   where j.id = p_jogador;
$$;

create or replace function public.fazenda_mar_lancar(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id     uuid := fazenda_auth(p_token);
  j        record;
  v_b      jsonb := fazenda_mar_item(v_id, 'barco');
  v_v      jsonb := fazenda_mar_item(v_id, 'vara');
  v_g      jsonb := fazenda_mar_regras();
  v_cheio  interval;
  v_peixe  text;
  v_espera int;
  v_tam    int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  if j.pier_em is null then raise exception 'sem_pier'; end if;
  if fazenda_mar_contar(v_id, 'barco') < 1 then raise exception 'cardume_vazio'; end if;
  -- tira 1 do cardume (o que passou do máximo já não contava)
  v_cheio := make_interval(secs => (v_b->>'max')::int * (v_b->>'intervalo')::int);
  update fazenda_jogadores
     set mar_em = greatest(coalesce(mar_em, now() - v_cheio), now() - v_cheio) + make_interval(secs => (v_b->>'intervalo')::int)
   where id = v_id;
  v_peixe := fazenda_mar_sortear((v_b->>'valor')::int, (v_v->>'valor')::int + fazenda_melhoria(v_id, 'sonar')::int);   -- fase 65: o sonar
  v_espera := (v_g->>'mordida_min')::int + floor(random() * ((v_g->>'mordida_max')::int - (v_g->>'mordida_min')::int))::int;
  select x.o into v_tam from jsonb_array_elements(fazenda_mar_tabela()) with ordinality as x(p, o) where x.p->>'id' = v_peixe;
  insert into fazenda_mar_lances (jogador_id, peixe, perola, mordida_em, janela_ms)
  values (v_id, v_peixe, random() < 1.0 / fazenda_mar_perola(v_id), now() + make_interval(secs => v_espera / 1000.0), (v_v->>'janela')::int)
  on conflict (jogador_id) do update set
    peixe = excluded.peixe, perola = excluded.perola, mordida_em = excluded.mordida_em,
    janela_ms = excluded.janela_ms, criado_em = now();
  return jsonb_build_object('espera_ms', v_espera, 'janela_ms', (v_v->>'janela')::int, 'tamanho', v_tam,
                            'agora', now(), 'mar', fazenda_mar_estado(v_id));
end;
$$;

create or replace function public.fazenda_mar_fisgar(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  v_g  jsonb := fazenda_mar_regras();
  l    record;
  v_xp int;
  v_qtd int;   -- fase 65: o porão às vezes traz 2
begin
  perform 1 from fazenda_jogadores where id = v_id for update;
  delete from fazenda_mar_lances where jogador_id = v_id returning * into l;
  if not found then raise exception 'sem_lance'; end if;
  if now() < l.mordida_em - make_interval(secs => (v_g->>'cedo_ms')::int / 1000.0) then
    return jsonb_build_object('pegou', false, 'motivo', 'cedo', 'mar', fazenda_mar_estado(v_id));
  end if;
  if now() > l.mordida_em + make_interval(secs => (l.janela_ms + (v_g->>'folga_ms')::int) / 1000.0) then
    return jsonb_build_object('pegou', false, 'motivo', 'tarde', 'mar', fazenda_mar_estado(v_id));
  end if;
  v_qtd := case when random() < fazenda_melhoria(v_id, 'porao') then 2 else 1 end;   -- fase 65: o porão
  insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, l.peixe, v_qtd)
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  if l.perola then
    insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, 'perola_negra', 1)
    on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
  end if;
  select xp * v_qtd into v_xp from fazenda_culturas where id = l.peixe;
  update fazenda_jogadores set xp = xp + v_xp where id = v_id;
  insert into fazenda_estatisticas (jogador_id) values (v_id) on conflict do nothing;
  update fazenda_estatisticas set peixes_mar = peixes_mar + v_qtd, marlins = marlins + (l.peixe = 'marlim')::int * v_qtd
   where jogador_id = v_id;
  perform fazenda_missao(v_id, 'colher', v_qtd);
  return jsonb_build_object('pegou', true, 'peixe', l.peixe, 'qtd', v_qtd, 'perola', l.perola, 'xp', v_xp, 'estado', fazenda_estado(v_id));
end;
$$;

create or replace function public.fazenda_mar_recolher(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id      uuid := fazenda_auth(p_token);
  j         record;
  v_m       jsonb := fazenda_mar_item(v_id, 'marinheiro');
  v_b       jsonb := fazenda_mar_item(v_id, 'barco');
  v_v       jsonb := fazenda_mar_item(v_id, 'vara');
  v_g       jsonb := fazenda_mar_regras();
  v_n       int;
  v_k       int;
  v_p       text;
  v_peixes  jsonb := '{}'::jsonb;
  v_perolas int := 0;
  v_xp      int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  if j.pier_em is null then raise exception 'sem_pier'; end if;
  if v_m is null then raise exception 'sem_marinheiro'; end if;
  v_n := fazenda_mar_contar(v_id, 'marinheiro');
  if v_n <= 0 then raise exception 'cesto_mar_vazio'; end if;
  for v_k in 1..v_n loop
    v_p := fazenda_mar_sortear((v_b->>'valor')::int, (v_v->>'valor')::int + fazenda_melhoria(v_id, 'sonar')::int);   -- fase 65: o sonar
    v_peixes := jsonb_set(v_peixes, array[v_p], to_jsonb(coalesce((v_peixes->>v_p)::int, 0) + 1));
    if random() < 1.0 / fazenda_mar_perola(v_id) then v_perolas := v_perolas + 1; end if;
  end loop;
  update fazenda_jogadores
     set marinheiro_em = greatest(coalesce(marinheiro_em, now()),
                                  now() - make_interval(secs => (v_m->>'max')::int * (v_m->>'intervalo')::int))
                         + make_interval(secs => v_n * (v_m->>'intervalo')::int)
   where id = v_id;
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  select v_id, e.key, e.value::int from jsonb_each_text(v_peixes) e
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  if v_perolas > 0 then
    insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, 'perola_negra', v_perolas)
    on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  end if;
  select coalesce(sum(k.xp * e.value::int), 0)::int into v_xp
    from jsonb_each_text(v_peixes) e join fazenda_culturas k on k.id = e.key;
  update fazenda_jogadores set xp = xp + v_xp where id = v_id;
  insert into fazenda_estatisticas (jogador_id) values (v_id) on conflict do nothing;
  update fazenda_estatisticas set peixes_mar = peixes_mar + v_n, marlins = marlins + coalesce((v_peixes->>'marlim')::int, 0)
   where jogador_id = v_id;
  perform fazenda_missao(v_id, 'colher', v_n);
  return jsonb_build_object('peixes', v_peixes, 'qtd', v_n, 'xp', v_xp, 'perolas', v_perolas, 'estado', fazenda_estado(v_id));
end;
$$;

-- a compra das peças: moedas + materiais raros; a rede pede o marinheiro e o kit, o barco oceânico

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
    if fazenda_nivel(j.xp) < a.nivel_min then raise exception 'nivel_insuficiente'; end if;
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
    -- sempre o próximo terreno da fila (p_tipo é ignorado)
    if j.zonas >= jsonb_array_length(fazenda_zonas()) then raise exception 'terreno_max'; end if;
    select (z->>'custo')::int as custo, (z->>'nivel')::int as nivel into a
      from jsonb_array_elements(fazenda_zonas()) z
     where (z->>'n')::int = j.zonas + 1;
    if fazenda_nivel(j.xp) < a.nivel then raise exception 'nivel_insuficiente'; end if;
    if j.moedas < a.custo then raise exception 'moedas_insuficientes'; end if;
    update fazenda_jogadores set moedas = moedas - a.custo, zonas = zonas + 1 where id = v_id;

  elsif p_categoria = 'melhoria' then
    -- fase 57: o próximo nível da melhoria (p_tipo = adubo, pomar ou pes)
    -- fase 62: e as do alto-mar (barco, vara e marinheiro), que pedem o píer pronto
    select (n->>'nivel')::int as nivel, (n->>'custo')::int as custo, coalesce((m->>'mar')::boolean, false) as mar,
           n->'itens' as itens into a
      from jsonb_array_elements(fazenda_melhorias_tipos()) m,
           jsonb_array_elements(m->'niveis') with ordinality as x(n, i)
     where m->>'id' = p_tipo
       and x.i = 1 + coalesce((select nivel from fazenda_melhorias where jogador_id = v_id and id = p_tipo), 0);
    if not found then raise exception 'melhoria_max'; end if;
    if a.mar and j.pier_em is null then raise exception 'sem_pier'; end if;
    if fazenda_nivel(j.xp) < a.nivel then raise exception 'nivel_insuficiente'; end if;
    -- fase 65: a rede é do marinheiro; o kit de expedição pede o barco oceânico
    if p_tipo = 'rede' and fazenda_mar_item(v_id, 'marinheiro') is null then raise exception 'sem_marinheiro'; end if;
    if p_tipo = 'expedicao' and coalesce((select nivel from fazenda_melhorias where jogador_id = v_id and id = 'barco'), 0) < 4 then
      raise exception 'barco_pequeno';
    end if;
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
    update fazenda_jogadores set moedas = moedas - a.custo where id = v_id;
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

  else
    raise exception 'item_invalido';
  end if;

  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- ------------------------------------------------------------
-- Fase 65: a tunagem do barco (até o nível 45, para as ilhas do 46).
-- • Peças (melhorias do mar com peca = true, em fazenda_melhorias_tipos): motor (o cardume enche mais
--   rápido), sonar (mais peixe grande e mais pérola), porão (às vezes 2 peixes numa fisgada), rede de
--   arrasto (o marinheiro pesca mais rápido) e o kit de expedição (deixa o barco oceânico pronto para as
--   ilhas). Cada nível pede moedas e materiais raros (do mercador, a pérola negra e o marlim-azul) e
--   aparece no desenho do barco. A compra é a de sempre: fazenda_comprar(…, 'melhoria', …).
-- • A pintura: a cor do casco e da faixa e a bandeira (barco_visual). 20 mil moedas por mudança; o
--   dourado pede 1 pérola negra.
-- ------------------------------------------------------------
create or replace function public.fazenda_barco_cores()
returns jsonb language sql immutable as $$
  select '{"preco": 20000, "dourado": "perola_negra",
           "cores": ["padrao", "branco", "azul", "vermelho", "verde", "amarelo", "preto", "roxo", "rosa", "dourado"],
           "bandeiras": ["padrao", "brasil", "pirata", "xadrez", "coracao", "estrela", "sertao"]}'::jsonb;
$$;

create or replace function public.fazenda_barco_pintar(p_token text, p_visual jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id      uuid := fazenda_auth(p_token);
  v_cat     jsonb := fazenda_barco_cores();
  j         record;
  v_atual   jsonb;
  v_novo    jsonb;
  v_mud     int := 0;
  v_perolas int := 0;
  k         text;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  if j.pier_em is null then raise exception 'sem_pier'; end if;
  v_atual := coalesce(j.barco_visual, '{}'::jsonb);
  v_novo := jsonb_build_object('casco', coalesce(p_visual->>'casco', 'padrao'), 'faixa', coalesce(p_visual->>'faixa', 'padrao'),
                               'bandeira', coalesce(p_visual->>'bandeira', 'padrao'));
  if not (v_cat->'cores' ? (v_novo->>'casco')) or not (v_cat->'cores' ? (v_novo->>'faixa'))
     or not (v_cat->'bandeiras' ? (v_novo->>'bandeira')) then
    raise exception 'cor_invalida';
  end if;
  foreach k in array array['casco', 'faixa', 'bandeira'] loop
    if v_novo->>k is distinct from coalesce(v_atual->>k, 'padrao') then
      v_mud := v_mud + 1;
      if v_novo->>k = 'dourado' then v_perolas := v_perolas + 1; end if;
    end if;
  end loop;
  if v_mud = 0 then raise exception 'nada_mudou'; end if;
  if j.moedas < v_mud * (v_cat->>'preco')::int then raise exception 'moedas_insuficientes'; end if;
  if v_perolas > 0 and coalesce((select quantidade from fazenda_celeiro where jogador_id = v_id and item = v_cat->>'dourado'), 0)
                       - coalesce((select quantidade from fazenda_reservas where jogador_id = v_id and item = v_cat->>'dourado'), 0) < v_perolas then
    raise exception 'faltam_materiais';
  end if;
  update fazenda_celeiro set quantidade = quantidade - v_perolas where v_perolas > 0 and jogador_id = v_id and item = v_cat->>'dourado';
  update fazenda_jogadores set moedas = moedas - v_mud * (v_cat->>'preco')::int, barco_visual = v_novo where id = v_id;
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

revoke execute on function public.fazenda_mar_perola(uuid), public.fazenda_barco_cores() from public, anon, authenticated;
grant execute on function public.fazenda_barco_pintar(text, jsonb) to anon, authenticated;

-- conferência: deve aparecer "Tunagem: motor, sonar, porao, rede, expedicao; pintura a 20000 moedas"
select 'Tunagem: ' || string_agg(m->>'id', ', ' order by o) || '; pintura a ' || (public.fazenda_barco_cores()->>'preco') || ' moedas' as ok
  from jsonb_array_elements(public.fazenda_melhorias_tipos()) with ordinality as x(m, o) where (m->>'peca')::boolean;
