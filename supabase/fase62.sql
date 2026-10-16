-- ============================================================
-- FAZENDINHA — Fase 62 (etapa 5B: o alto-mar e a curva de XP de 7%), só o que mudou.
-- Para o banco que já está no ar (com a fase 61): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- a curva de XP: do 25 em diante, 7% a mais por nível (a de antes fica como _v4, para converter)

create or replace function public.fazenda_xp_nivel(p_nivel int)
returns bigint language sql immutable as $$
  select case when p_nivel <= 10 then (array[0, 10, 35, 85, 175, 315, 525, 825, 1325, 2025])[greatest(p_nivel, 1)]
              when p_nivel <= 16 then 2025 + round(700 * (power(1.22::float8, p_nivel - 10) - 1) / 0.22)::bigint
              -- fase 41: do 16 ao 25 cada nível pede 35% a mais que o anterior
              -- (16→17: 2.554, 18→19: 4.656, 20→21: 8.485, 24→25: 28.177)
              when p_nivel <= 25 then 2025 + round(700 * (power(1.22::float8, 6) - 1) / 0.22)::bigint
                   + round(700 * power(1.22::float8, 5) * 1.35 * (power(1.35::float8, p_nivel - 16) - 1) / 0.35)::bigint
              -- fase 62: do 25 em diante, 7% a mais que o anterior (o 25 continua em 110.722; 25→26: 30.149,
              -- 29→30: 39.519, 30→31: 42.286, 44→45: 116.669; o 45 fica em 1.346.711)
              else 110722 + round(28177 * 1.07 * (power(1.07::float8, p_nivel - 25) - 1) / 0.07)::bigint end;
$$;

-- A curva da fase 41 (35% do 16 em diante): só para converter quem estava nela (curva 4 → 5)
create or replace function public.fazenda_xp_nivel_v4(p_nivel int)
returns bigint language sql immutable as $$
  select case when p_nivel <= 10 then (array[0, 10, 35, 85, 175, 315, 525, 825, 1325, 2025])[greatest(p_nivel, 1)]
              when p_nivel <= 16 then 2025 + round(700 * (power(1.22::float8, p_nivel - 10) - 1) / 0.22)::bigint
              else 2025 + round(700 * (power(1.22::float8, 6) - 1) / 0.22)::bigint
                   + round(700 * power(1.22::float8, 5) * 1.35 * (power(1.35::float8, p_nivel - 16) - 1) / 0.35)::bigint end;
$$;

alter table public.fazenda_jogadores alter column curva set default 5;   -- 5 = fase 62 (7% a mais por nível do 25 em diante)

-- Fase 62 (curva 4 → 5, uma vez): do 25 em diante cada nível pede 7% a mais que o anterior (era 35%:
-- o 45 pedia 44 milhões de XP). Quem já está do 25 em diante continua no mesmo nível, com a barra na mesma
-- proporção (ninguém pula nem desce; o ranking fica na mesma ordem). O XP só desce aqui, então o
-- gatilho do XP em dobro não mexe (e o xp_puro garante).
select set_config('fazenda.xp_puro', '1', false);
update public.fazenda_jogadores j
   set xp = case when x.n <= 24 then j.xp
                 else fazenda_xp_nivel(x.n) + floor(least(greatest((j.xp - fazenda_xp_nivel_v4(x.n))::numeric
                        / nullif(fazenda_xp_nivel_v4(x.n + 1) - fazenda_xp_nivel_v4(x.n), 0), 0), 0.999)
                        * (fazenda_xp_nivel(x.n + 1) - fazenda_xp_nivel(x.n)))::int end,
       curva = 5
  from (select id, (select max(g) from generate_series(1, 60) g where fazenda_xp_nivel_v4(g) <= xp) as n
          from public.fazenda_jogadores where curva = 4) x
 where j.id = x.id;
select set_config('fazenda.xp_puro', '', false);

-- barco, vara e marinheiro entram no catálogo de melhorias (mar = true)

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
                      {"nivel":39,"custo":1800000,"valor":3,"nome":"Seu Nonato com barco de apoio","intervalo":720,"max":40}]}]'::jsonb;
$$;

-- ------------------------------------------------------------
-- Fase 62: o alto-mar (ideias de 15/10, etapa 5B).
-- • Com o píer pronto, tocar no barco leva para o alto-mar: pescaria ativa (lançar, esperar a boia
--   afundar e fisgar na hora certa) e o marinheiro, que pesca sozinho num cesto dele (até 8 h).
-- • O cardume: enche 1 peixe a cada intervalo do barco, até o máximo dele (mar_em, contado pelo tempo
--   como o cesto do Bira). Cada lançada usa 1 peixe; errou a fisgada, ele foge. É o que segura a pesca.
-- • Barco, vara e marinheiro são melhorias (fazenda_melhorias_tipos, mar = true), compradas em
--   fazenda_comprar(…, 'melhoria', …), do nível 32 ao 43, e caras (quem chega aqui já tem a roça no talo).
-- • Peixes do mar: produtos (vendem no celeiro e dão XP na pesca e na venda, como os do lago); a vara
--   melhor puxa os maiores. 1 em cada 200 vem com uma pérola negra (raro: só na feira, 50 a 150 mil).
-- • A curva de XP (7% do 25 em diante, curva 5) e o bônus das metas até o 44 ficam lá em cima
--   (fazenda_xp_nivel e fazenda_estado). O jogo desenha o mar em fazenda-mar.js.
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists mar_em timestamptz;          -- desde quando o cardume enche
alter table public.fazenda_jogadores add column if not exists marinheiro_em timestamptz;   -- desde quando o cesto do marinheiro enche
alter table public.fazenda_estatisticas add column if not exists peixes_mar int not null default 0;
alter table public.fazenda_estatisticas add column if not exists marlins int not null default 0;

insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('sardinha',     'Sardinha',       '🐟', 1, 0,   400, 1,   40, 31, 82, 'produto'),
  ('cavala',       'Cavala',         '🐟', 1, 0,   800, 1,   70, 31, 83, 'produto'),
  ('robalo',       'Robalo',         '🐟', 1, 0,  1500, 1,  120, 31, 84, 'produto'),
  ('garoupa',      'Garoupa',        '🐟', 1, 0,  2500, 1,  180, 31, 85, 'produto'),
  ('dourado_mar',  'Dourado-do-mar', '🐠', 1, 0,  4000, 1,  260, 31, 86, 'produto'),
  ('atum',         'Atum',           '🐟', 1, 0,  6500, 1,  380, 31, 87, 'produto'),
  ('marlim',       'Marlim-azul',    '🐟', 1, 0, 30000, 1, 1200, 31, 88, 'produto'),
  ('perola_negra', 'Pérola negra',   '🦪', 1, 0, 50000, 1,    0,  1, 96, 'raro')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, venda = excluded.venda, xp = excluded.xp,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;

insert into public.fazenda_conquistas_tipos (id, nome, descricao, medida, meta, recompensa, ordem) values
  ('lobo_do_mar', 'Lobo do mar', 'Pesque 100 peixes no alto-mar (você ou o marinheiro)', 'peixes_mar', 100,  20000, 22),
  ('marlim',      'Marlim-azul', 'Pesque o marlim-azul',                                'marlins',      1,  50000, 23),
  ('nivel_45',    'Capitão',     'Chegue ao nível 45',                                  'nivel',       45, 100000, 24)
on conflict (id) do update set
  nome = excluded.nome, descricao = excluded.descricao, medida = excluded.medida,
  meta = excluded.meta, recompensa = excluded.recompensa, ordem = excluded.ordem;

-- o lance que está na água (um por jogador; lançar de novo troca o anterior, que já fugiu)
create table if not exists public.fazenda_mar_lances (
  jogador_id uuid primary key references public.fazenda_jogadores(id) on delete cascade,
  peixe      text not null references public.fazenda_culturas(id),
  perola     boolean not null default false,
  mordida_em timestamptz not null,
  janela_ms  int not null,
  criado_em  timestamptz not null default now()
);
alter table public.fazenda_mar_lances enable row level security;
revoke all on public.fazenda_mar_lances from anon, authenticated;

-- os peixes do mar: o barco que alcança cada um e o peso no anzol (a vara puxa os do fim da lista)
create or replace function public.fazenda_mar_tabela()
returns jsonb language sql immutable as $$
  select '[{"id":"sardinha","barco":1,"peso":40},{"id":"cavala","barco":1,"peso":25},{"id":"robalo","barco":1,"peso":15},
           {"id":"garoupa","barco":2,"peso":10},{"id":"dourado_mar","barco":3,"peso":6},{"id":"atum","barco":4,"peso":3},
           {"id":"marlim","barco":5,"peso":1}]'::jsonb;
$$;

-- as regras da pescaria: 1 pérola a cada 200 peixes; a mordida vem de 1,5 a 5 s depois de lançar;
-- fisgar até 0,3 s antes da mordida conta (relógio), e a folga de 2,5 s depois da janela é a internet
create or replace function public.fazenda_mar_regras()
returns jsonb language sql immutable as $$
  select '{"perola": 200, "mordida_min": 1500, "mordida_max": 5000, "cedo_ms": 300, "folga_ms": 2500}'::jsonb;
$$;

-- a chance (%) de cada peixe com este barco e esta vara: cada nível de vara põe +50% (dividido pela
-- posição na lista) no peso dos maiores; na vara 5 o marlim pesa 3x
create or replace function public.fazenda_mar_peixes(p_barco int, p_vara int)
returns table (peixe text, peso real, chance real) language sql immutable as $$
  with t as (
    select x.p->>'id' as peixe, x.o,
           ((x.p->>'peso')::real * (1 + 0.5 * (greatest(p_vara, 1) - 1) * (x.o - 1) / 6.0))::real as peso
      from jsonb_array_elements(fazenda_mar_tabela()) with ordinality as x(p, o)
     where (x.p->>'barco')::int <= greatest(p_barco, 1))
  select t.peixe, t.peso, round((100 * t.peso / sum(t.peso) over ())::numeric, 1)::real from t order by t.o;
$$;

create or replace function public.fazenda_mar_sortear(p_barco int, p_vara int)
returns text language plpgsql volatile set search_path = public as $$
declare
  p      record;
  v_r    real;
  v_soma real := 0;
begin
  select random() * sum(t.peso) into v_r from fazenda_mar_peixes(p_barco, p_vara) t;
  for p in select * from fazenda_mar_peixes(p_barco, p_vara) loop
    v_soma := v_soma + p.peso;
    if v_r < v_soma then return p.peixe; end if;
  end loop;
  return p.peixe;   -- (arredondamento: fica o último)
end;
$$;

-- o barco, a vara ou o marinheiro que o jogador tem agora (o nível 0 é o "base", que vem com o píer;
-- o marinheiro não tem base: null = não contratado)
create or replace function public.fazenda_mar_item(p_jogador uuid, p_id text)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when coalesce(g.nivel, 0) = 0 then m->'base' else m->'niveis'->(g.nivel - 1) end
    from jsonb_array_elements(fazenda_melhorias_tipos()) m
    left join fazenda_melhorias g on g.jogador_id = p_jogador and g.id = p_id
   where m->>'id' = p_id;
$$;

-- quantos peixes há agora no cardume (p_qual = 'barco') ou no cesto do marinheiro ('marinheiro'):
-- 1 a cada intervalo desde mar_em / marinheiro_em, até o máximo (sem data: o cardume cheio, o cesto vazio)
create or replace function public.fazenda_mar_contar(p_jogador uuid, p_qual text)
returns int language sql stable security definer set search_path = public as $$
  select coalesce(greatest(0, least(
           floor(extract(epoch from now() - case when p_qual = 'barco'
                   then coalesce(j.mar_em, now() - make_interval(secs => (x.i->>'max')::int * (x.i->>'intervalo')::int))
                   else coalesce(j.marinheiro_em, now()) end) / (x.i->>'intervalo')::int)::int,
           (x.i->>'max')::int)), 0)
    from fazenda_jogadores j
    cross join lateral (select fazenda_mar_item(p_jogador, p_qual) as i) x
   where j.id = p_jogador;
$$;

-- o alto-mar no estado do jogo (null sem o píer)
create or replace function public.fazenda_mar_estado(p_jogador uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select case when j.pier_em is not null then jsonb_build_object(
           'barco', b.i, 'vara', v.i, 'marinheiro', m.i,
           'cardume', jsonb_build_object('desde', j.mar_em, 'intervalo', (b.i->>'intervalo')::int, 'max', (b.i->>'max')::int),
           'cesto', case when m.i is not null then
                      jsonb_build_object('desde', j.marinheiro_em, 'intervalo', (m.i->>'intervalo')::int, 'max', (m.i->>'max')::int) end,
           'peixes', (select jsonb_agg(jsonb_build_object('id', t.peixe, 'chance', t.chance))
                        from fazenda_mar_peixes((b.i->>'valor')::int, (v.i->>'valor')::int) t),
           'regras', fazenda_mar_regras()) end
    from fazenda_jogadores j
    cross join lateral (select fazenda_mar_item(p_jogador, 'barco') as i) b
    cross join lateral (select fazenda_mar_item(p_jogador, 'vara') as i) v
    cross join lateral (select fazenda_mar_item(p_jogador, 'marinheiro') as i) m
   where j.id = p_jogador;
$$;

-- Lança a linha: tira 1 peixe do cardume, sorteia qual é e quando ele morde. Volta rápido (sem o
-- estado inteiro): quanto esperar, a janela de fisgar, o tamanho do peixe (a boia puxa mais) e o mar.
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
  v_peixe := fazenda_mar_sortear((v_b->>'valor')::int, (v_v->>'valor')::int);
  v_espera := (v_g->>'mordida_min')::int + floor(random() * ((v_g->>'mordida_max')::int - (v_g->>'mordida_min')::int))::int;
  select x.o into v_tam from jsonb_array_elements(fazenda_mar_tabela()) with ordinality as x(p, o) where x.p->>'id' = v_peixe;
  insert into fazenda_mar_lances (jogador_id, peixe, perola, mordida_em, janela_ms)
  values (v_id, v_peixe, random() < 1.0 / (v_g->>'perola')::int, now() + make_interval(secs => v_espera / 1000.0), (v_v->>'janela')::int)
  on conflict (jogador_id) do update set
    peixe = excluded.peixe, perola = excluded.perola, mordida_em = excluded.mordida_em,
    janela_ms = excluded.janela_ms, criado_em = now();
  return jsonb_build_object('espera_ms', v_espera, 'janela_ms', (v_v->>'janela')::int, 'tamanho', v_tam,
                            'agora', now(), 'mar', fazenda_mar_estado(v_id));
end;
$$;

-- Fisga: vale da mordida até o fim da janela (com a folga da internet). Antes ou depois, o peixe
-- foge (não é erro: o lance acaba do mesmo jeito). O jogo só chama quando o toque foi na janela.
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
  insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, l.peixe, 1)
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
  if l.perola then
    insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, 'perola_negra', 1)
    on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
  end if;
  select xp into v_xp from fazenda_culturas where id = l.peixe;
  update fazenda_jogadores set xp = xp + v_xp where id = v_id;
  insert into fazenda_estatisticas (jogador_id) values (v_id) on conflict do nothing;
  update fazenda_estatisticas set peixes_mar = peixes_mar + 1, marlins = marlins + (l.peixe = 'marlim')::int
   where jogador_id = v_id;
  perform fazenda_missao(v_id, 'colher', 1);
  return jsonb_build_object('pegou', true, 'peixe', l.peixe, 'perola', l.perola, 'xp', v_xp, 'estado', fazenda_estado(v_id));
end;
$$;

-- Recolhe o cesto do marinheiro (igual ao do Bira no lago): cada peixe sorteado com o seu barco e a
-- sua vara; o que passou do máximo (8 h) se perdeu
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
    v_p := fazenda_mar_sortear((v_b->>'valor')::int, (v_v->>'valor')::int);
    v_peixes := jsonb_set(v_peixes, array[v_p], to_jsonb(coalesce((v_peixes->>v_p)::int, 0) + 1));
    if random() < 1.0 / (v_g->>'perola')::int then v_perolas := v_perolas + 1; end if;
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

-- as conquistas do mar, a compra das melhorias do mar, o pacote de XP até o 45 e o mar no estado

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
begin
  insert into fazenda_estatisticas (jogador_id) values (p_jogador) on conflict do nothing;
  select * into s from fazenda_estatisticas where jogador_id = p_jogador;
  select fazenda_nivel(xp) into v_nivel from fazenda_jogadores where id = p_jogador;
  select count(*) into v_constr from fazenda_construcoes where jogador_id = p_jogador;
  select count(*) into v_conv from fazenda_convites where dono_id = p_jogador;
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
      else 0
    end;
    if v_valor >= r.meta then
      insert into fazenda_conquistas (jogador_id, conquista) values (p_jogador, r.id) on conflict do nothing;
      update fazenda_jogadores set moedas = moedas + r.recompensa where id = p_jogador;
    end if;
  end loop;
end;
$$;

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
    select (n->>'nivel')::int as nivel, (n->>'custo')::int as custo, coalesce((m->>'mar')::boolean, false) as mar into a
      from jsonb_array_elements(fazenda_melhorias_tipos()) m,
           jsonb_array_elements(m->'niveis') with ordinality as x(n, i)
     where m->>'id' = p_tipo
       and x.i = 1 + coalesce((select nivel from fazenda_melhorias where jogador_id = v_id and id = p_tipo), 0);
    if not found then raise exception 'melhoria_max'; end if;
    if a.mar and j.pier_em is null then raise exception 'sem_pier'; end if;
    if fazenda_nivel(j.xp) < a.nivel then raise exception 'nivel_insuficiente'; end if;
    if j.moedas < a.custo then raise exception 'moedas_insuficientes'; end if;
    -- barco ou marinheiro novo muda o ritmo: o que já está no cardume (ou no cesto) fica lá
    v_n := case when p_tipo in ('barco', 'marinheiro') then fazenda_mar_contar(v_id, p_tipo) end;
    update fazenda_jogadores set moedas = moedas - a.custo where id = v_id;
    insert into fazenda_melhorias (jogador_id, id, nivel) values (v_id, p_tipo, 1)
    on conflict (jogador_id, id) do update set nivel = fazenda_melhorias.nivel + 1;
    if p_tipo = 'barco' then
      update fazenda_jogadores set mar_em = now() - make_interval(secs => v_n * (fazenda_mar_item(v_id, 'barco')->>'intervalo')::int)
       where id = v_id;
    elsif p_tipo = 'marinheiro' then
      update fazenda_jogadores set marinheiro_em = now() - make_interval(secs => v_n * (fazenda_mar_item(v_id, 'marinheiro')->>'intervalo')::int)
       where id = v_id;
    end if;

  else
    raise exception 'item_invalido';
  end if;

  return jsonb_build_object('estado', fazenda_estado(v_id));
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
    update fazenda_jogadores set diamantes = diamantes - v_preco, xp = xp + v_xp where id = v_id;
    perform set_config('fazenda.xp_puro', '', true);

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
    'mar', fazenda_mar_estado(p_jogador),   -- fase 62: o alto-mar (null sem o píer)
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
  public.fazenda_xp_nivel_v4(int),
  public.fazenda_mar_tabela(),
  public.fazenda_mar_regras(),
  public.fazenda_mar_peixes(int, int),
  public.fazenda_mar_sortear(int, int),
  public.fazenda_mar_item(uuid, text),
  public.fazenda_mar_contar(uuid, text),
  public.fazenda_mar_estado(uuid)
from public, anon, authenticated;
grant execute on function public.fazenda_mar_lancar(text), public.fazenda_mar_fisgar(text), public.fazenda_mar_recolher(text)
to anon, authenticated;

-- conferência: deve aparecer "Nível 45: 1346711 XP; bote: 16 peixes a cada 900 s; pérola na feira de 50000 a 150000"
select 'Nível 45: ' || public.fazenda_xp_nivel(45) || ' XP; bote: ' || (b->'base'->>'max') || ' peixes a cada '
    || (b->'base'->>'intervalo') || ' s; pérola na feira de ' || (public.fazenda_feira_faixa('perola_negra'))[1]
    || ' a ' || (public.fazenda_feira_faixa('perola_negra'))[2] as ok
  from jsonb_array_elements(public.fazenda_melhorias_tipos()) b where b->>'id' = 'barco';
