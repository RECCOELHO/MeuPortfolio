-- ============================================================
-- FAZENDINHA — Fase 94 (a Invasão de Varginha: o evento de domingo, 1/11, das 15h à meia-noite),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 93): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 93 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_usar_premio')) then
    raise exception 'Rode o fase93.sql antes deste (a fase 93 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 94: a Invasão de Varginha (em homenagem ao ET de Varginha, 1996). Uma sala que todos veem:
-- a nave lá em cima, os ETs descendo e os fazendeiros de quem está na sala embaixo. Tocar num ET faz
-- o seu fazendeiro atirar nele; o dano vira pontos. Armas compradas com moedas (o preço sobe a cada
-- nível) dão mais dano por toque ou atiram sozinhas. No fim, todo mundo que pontuou ganha: o 1º leva
-- 40 diamantes e 4 milhões de moedas, e cada lugar seguinte leva 3/4 do anterior, até 1 diamante (e
-- 1 mil moedas) para todos.
-- Contra trapaça (autoclicker): quem conta é o servidor. Os ETs têm número e hora certos, iguais para
-- todos (fazenda_invasao_alien; o jogo calcula igual), e só vale dano em ET que está na tela; os toques
-- chegam em lotes e cada jogador tem um saldo que enche 6 por segundo (no máximo 30 guardados): toque
-- além do saldo não conta. As armas automáticas só atiram para quem tocou num ET nos últimos 2 minutos
-- e está na sala (o lote chega a cada 2,5 s; o tempo que conta por lote é de no máximo 5 s).
-- A sala pesa pouco: quem está nela e o placar ficam prontos por 1,5 s (fazenda_cache), um calcula e
-- os outros leem; o lote e o painel não esperam na fila de uma chamada por vez (só a compra espera).
-- O teste dos admins (p_teste = true, só para quem é admin ou dono): uma invasão separada
-- ("varginha-teste"), aberta já, até domingo às 14h, com placar próprio, armas de graça e sem prêmio.
-- Pode rodar este arquivo de novo (a versão de antes, sem o teste, é trocada por esta).
-- ------------------------------------------------------------
drop function if exists public.fazenda_invasao_regras();
drop function if exists public.fazenda_invasao(text, boolean);
drop function if exists public.fazenda_invasao_lote(text, jsonb);
drop function if exists public.fazenda_invasao_comprar(text, text);

-- as regras (as horas e os números moram aqui: para outra invasão, é só trocar)
create or replace function public.fazenda_invasao_regras(p_teste boolean default false)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'id', case when p_teste then 'varginha-teste' else 'varginha-2026' end, 'nome', 'Invasão de Varginha',
    'teste', p_teste,
    'inicio', case when p_teste then '2026-10-31 00:00:00-03' else '2026-11-01 15:00:00-03' end::timestamptz,
    'fim', case when p_teste then '2026-11-01 14:00:00-03' else '2026-11-02 00:00:00-03' end::timestamptz,
    'nivel_min', case when p_teste then 1 else 10 end,
    'toques_seg', 6, 'toques_max', 30,                 -- o saldo de toques: enche 6 por segundo, guarda até 30
    'intervalo', 1.2, 'vida', 9,                       -- um ET novo a cada 1,2 s; cada um fica 9 s na tela
    'hp_base', 4, 'hp_por_hora', 2,                    -- a cada hora os ETs aguentam mais
    'chefe_a_cada', 3600, 'chefe_atraso', 30, 'vida_chefe', 120, 'hp_chefe', 400, 'hp_chefe_por_hora', 150,
    'bonus_abate', 2, 'bonus_chefe', 200,              -- pontos a mais por derrubar
    'auto_ativo_seg', 120, 'lote_max_seg', 5,
    'premio', jsonb_build_object('diamantes', 40, 'moedas', 4000000, 'fator', 0.75, 'min_diamantes', 1, 'min_moedas', 1000),
    'armas', '[
      {"id": "forcado",    "nome": "Forcado elétrico",   "tipo": "toque", "efeito": 1,  "preco": 5000,   "fator": 1.6},
      {"id": "espantalho", "nome": "Espantalho-robô",    "tipo": "auto",  "efeito": 1,  "preco": 20000,  "fator": 1.7},
      {"id": "trator",     "nome": "Trator-canhão",      "tipo": "auto",  "efeito": 4,  "preco": 80000,  "fator": 1.8},
      {"id": "drone",      "nome": "Drone pulverizador", "tipo": "auto",  "efeito": 12, "preco": 250000, "fator": 2.0}
    ]'::jsonb,
    'arma_nivel_max', 25);
$$;

-- cada jogador na invasão
create table if not exists public.fazenda_invasao (
  evento      text not null,
  jogador_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  pontos      bigint not null default 0,
  abates      int not null default 0,
  chefes      int not null default 0,
  toques      bigint not null default 0,
  armas       jsonb not null default '{}'::jsonb,   -- {"forcado": 2, "drone": 1}
  gastou      bigint not null default 0,
  saldo       real not null default 0,              -- toques que ainda valem
  golpes      jsonb not null default '{}'::jsonb,   -- dano já feito nos ETs que ainda estão na tela {"k": dano}
  auto_resto  real not null default 0,              -- a fração de ponto das armas automáticas
  ult_lote    timestamptz,
  ult_toque   timestamptz,
  ult_qtd     int not null default 0,               -- quantos toques valeram no último lote (para os outros verem os tiros)
  ult_alvo    int,
  entrou_em   timestamptz not null default now(),
  visto_em    timestamptz not null default now(),
  subiu_em    timestamptz not null default now(),   -- quando os pontos subiram por último (desempate: quem chegou antes)
  primary key (evento, jogador_id)
);
create index if not exists fazenda_invasao_pontos on public.fazenda_invasao (evento, pontos desc);
create index if not exists fazenda_invasao_visto on public.fazenda_invasao (evento, visto_em);
alter table public.fazenda_invasao enable row level security;
revoke all on public.fazenda_invasao from anon, authenticated;

create table if not exists public.fazenda_invasao_premios (
  evento      text not null,
  jogador_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  posicao     int not null,
  pontos      bigint not null,
  diamantes   int not null,
  moedas      int not null,
  visto       boolean not null default false,
  primary key (evento, jogador_id)
);
alter table public.fazenda_invasao_premios enable row level security;
revoke all on public.fazenda_invasao_premios from anon, authenticated;

create table if not exists public.fazenda_invasao_fechamentos (
  evento      text primary key,
  fechado_em  timestamptz not null default now(),
  premiados   int not null default 0
);
alter table public.fazenda_invasao_fechamentos enable row level security;
revoke all on public.fazenda_invasao_fechamentos from anon, authenticated;

-- as conquistas da invasão (dadas na hora: o chefão no lote, o top 4 no fechamento)
insert into public.fazenda_conquistas_tipos (id, nome, descricao, medida, meta, recompensa, ordem) values
  ('invasao_chefe',    'Caçador de ET',        'Derrube um ET chefão na Invasão de Varginha',  'invasao', 1, 10000, 33),
  ('invasao_defensor', 'Defensor de Varginha', 'Fique no top 4 da Invasão de Varginha',        'invasao', 1, 20000, 34)
on conflict (id) do update set nome = excluded.nome, descricao = excluded.descricao, medida = excluded.medida,
  meta = excluded.meta, recompensa = excluded.recompensa, ordem = excluded.ordem;

-- um ET: k de 0 em diante são os normais (um a cada "intervalo"); 100000 + b é o chefão da hora b.
-- Igual a etDe() em assets/fazenda/fazenda-invasao.js. Fora do evento: null.
create or replace function public.fazenda_invasao_alien(p_k int, p_r jsonb)
returns table (nasce timestamptz, morre timestamptz, hp int, chefe boolean)
language plpgsql immutable as $$
declare
  v_ini timestamptz := (p_r->>'inicio')::timestamptz;
  v_dur double precision := extract(epoch from (p_r->>'fim')::timestamptz - v_ini);
  v_seg double precision;
  v_b   int;
begin
  if p_k is null or p_k < 0 then return; end if;
  if p_k >= 100000 then
    v_b := p_k - 100000;
    v_seg := v_b * (p_r->>'chefe_a_cada')::double precision + (p_r->>'chefe_atraso')::double precision;
    if v_seg >= v_dur then return; end if;
    nasce := v_ini + make_interval(secs => v_seg);
    morre := least(nasce + make_interval(secs => (p_r->>'vida_chefe')::double precision), (p_r->>'fim')::timestamptz);
    hp := (p_r->>'hp_chefe')::int + v_b * (p_r->>'hp_chefe_por_hora')::int;
    chefe := true;
  else
    v_seg := p_k * (p_r->>'intervalo')::double precision;
    if v_seg >= v_dur then return; end if;
    nasce := v_ini + make_interval(secs => v_seg);
    morre := nasce + make_interval(secs => (p_r->>'vida')::double precision);
    hp := (p_r->>'hp_base')::int + floor(v_seg / 3600)::int * (p_r->>'hp_por_hora')::int;
    chefe := false;
  end if;
  return next;
end;
$$;

-- o preço do próximo nível de uma arma (null: arma que não existe ou já no máximo)
create or replace function public.fazenda_invasao_preco(p_r jsonb, p_arma text, p_nivel int)
returns bigint language sql immutable as $$
  select case when p_nivel >= (p_r->>'arma_nivel_max')::int then null
              else round((a->>'preco')::numeric * power((a->>'fator')::numeric, p_nivel))::bigint end
    from jsonb_array_elements(p_r->'armas') a where a->>'id' = p_arma;
$$;

-- o dano por toque e o dano por segundo das automáticas, pelas armas compradas
create or replace function public.fazenda_invasao_poder(p_r jsonb, p_armas jsonb)
returns table (por_toque int, por_seg double precision)
language sql immutable as $$
  select 1 + coalesce(sum(case when a->>'tipo' = 'toque' then (a->>'efeito')::int * coalesce((p_armas->>(a->>'id'))::int, 0) end), 0)::int,
         coalesce(sum(case when a->>'tipo' = 'auto' then (a->>'efeito')::double precision * coalesce((p_armas->>(a->>'id'))::int, 0) end), 0)
    from jsonb_array_elements(p_r->'armas') a;
$$;

-- o prêmio de uma posição: o 1º leva o cheio e cada um seguinte 3/4 do anterior, até o mínimo
create or replace function public.fazenda_invasao_premio(p_r jsonb, p_pos int)
returns table (diamantes int, moedas int)
language sql immutable as $$
  select greatest((p_r->'premio'->>'min_diamantes')::int,
                  round((p_r->'premio'->>'diamantes')::numeric * power((p_r->'premio'->>'fator')::numeric, p_pos - 1))::int),
         greatest((p_r->'premio'->>'min_moedas')::int,
                  round((p_r->'premio'->>'moedas')::numeric * power((p_r->'premio'->>'fator')::numeric, p_pos - 1))::int);
$$;

-- o que o jogo mostra de você
create or replace function public.fazenda_invasao_eu(p_r jsonb, p_jogador uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  m record;
  v_pos int;
  v_pod record;
begin
  select * into m from fazenda_invasao where evento = p_r->>'id' and jogador_id = p_jogador;
  if not found then
    return jsonb_build_object('pontos', 0, 'abates', 0, 'chefes', 0, 'armas', '{}'::jsonb, 'posicao', null,
      'precos', (select jsonb_object_agg(a->>'id', fazenda_invasao_preco(p_r, a->>'id', 0)) from jsonb_array_elements(p_r->'armas') a),
      'por_toque', 1, 'por_seg', 0, 'golpes', '{}'::jsonb);
  end if;
  select count(*) + 1 into v_pos from fazenda_invasao where evento = m.evento and pontos > m.pontos;
  select * into v_pod from fazenda_invasao_poder(p_r, m.armas);
  return jsonb_build_object('pontos', m.pontos, 'abates', m.abates, 'chefes', m.chefes, 'armas', m.armas, 'gastou', m.gastou,
    'posicao', case when m.pontos > 0 then v_pos end,
    'precos', (select jsonb_object_agg(a->>'id', fazenda_invasao_preco(p_r, a->>'id', coalesce((m.armas->>(a->>'id'))::int, 0)))
                 from jsonb_array_elements(p_r->'armas') a),
    'por_toque', v_pod.por_toque, 'por_seg', v_pod.por_seg, 'golpes', m.golpes,
    'auto_ligado', m.ult_toque is not null and m.ult_toque > now() - make_interval(secs => (p_r->>'auto_ativo_seg')::int));
end;
$$;

-- quem está na sala agora (visto nos últimos 12 s) e o placar: prontos por 1,5 s para todos
create or replace function public.fazenda_invasao_sala(p_r jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_chave text := 'invasao:' || (p_r->>'id');
  v jsonb;
begin
  select valor into v from fazenda_cache where chave = v_chave and em > now() - interval '1.5 seconds';
  if v is not null then return v; end if;
  v := jsonb_build_object(
    'jogadores', coalesce((select jsonb_agg(q order by q.pontos desc) from (
        select left(i.jogador_id::text, 8) as id, j.apelido, j.avatar, fazenda_nivel_de(j.xp, j.nivel_trava) as nivel, i.pontos,
               (abs(hashtext(i.jogador_id::text)) % 1000) / 1000.0 as x, i.armas,
               case when i.ult_lote > now() - interval '4 seconds' then i.ult_qtd else 0 end as qtd, i.ult_alvo as alvo
          from fazenda_invasao i join fazenda_jogadores j on j.id = i.jogador_id
         where i.evento = p_r->>'id' and i.visto_em > now() - interval '12 seconds'
         order by i.pontos desc limit 40) q), '[]'::jsonb),
    'na_sala', (select count(*) from fazenda_invasao where evento = p_r->>'id' and visto_em > now() - interval '12 seconds'),
    'top', coalesce((select jsonb_agg(q order by q.pontos desc, q.subiu_em) from (
        select left(i.jogador_id::text, 8) as id, j.apelido, j.avatar, i.pontos, i.abates, i.chefes, i.subiu_em
          from fazenda_invasao i join fazenda_jogadores j on j.id = i.jogador_id
         where i.evento = p_r->>'id' and i.pontos > 0
         order by i.pontos desc, i.subiu_em limit 10) q), '[]'::jsonb),
    'participantes', (select count(*) from fazenda_invasao where evento = p_r->>'id' and pontos > 0));
  -- quem grava no cache não faz fila: um grava, os outros seguem
  begin
    insert into fazenda_cache (chave, valor, em) values (v_chave, v, now())
    on conflict (chave) do update set valor = excluded.valor, em = excluded.em;
  exception when others then null;
  end;
  return v;
end;
$$;

-- O fechamento: depois da meia-noite, a primeira chamada (ou o relógio do banco) paga todo mundo que
-- pontuou, do 1º ao último, e marca a invasão como fechada. Só uma chamada tenta.
create or replace function public.fazenda_invasao_fechar()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_r   jsonb := fazenda_invasao_regras();
  v_ev  text := v_r->>'id';
  r     record;
  p     record;
  v_n   int := 0;
  c     record;
begin
  if now() < (v_r->>'fim')::timestamptz then return; end if;
  if exists (select 1 from fazenda_invasao_fechamentos where evento = v_ev) then return; end if;
  if not pg_try_advisory_xact_lock(9494, hashtext(v_ev)) then return; end if;
  if exists (select 1 from fazenda_invasao_fechamentos where evento = v_ev) then return; end if;
  for r in select jogador_id, pontos, row_number() over (order by pontos desc, subiu_em, jogador_id)::int as pos
             from fazenda_invasao where evento = v_ev and pontos > 0 loop
    select * into p from fazenda_invasao_premio(v_r, r.pos);
    insert into fazenda_invasao_premios (evento, jogador_id, posicao, pontos, diamantes, moedas)
    values (v_ev, r.jogador_id, r.pos, r.pontos, p.diamantes, p.moedas) on conflict do nothing;
    -- (o prêmio em moedas não conta no "moedas" do evento da semana: o gatilho soma o que entra, e aqui desconta)
    update fazenda_jogadores set diamantes = diamantes + p.diamantes,
           moedas = least(2147483647, moedas::bigint + p.moedas)::int, moedas_ganhas = moedas_ganhas - p.moedas
     where id = r.jogador_id;
    if r.pos <= 4 then
      select * into c from fazenda_conquistas_tipos where id = 'invasao_defensor';
      insert into fazenda_conquistas (jogador_id, conquista) values (r.jogador_id, 'invasao_defensor') on conflict do nothing;
      if found then
        update fazenda_jogadores set moedas = least(2147483647, moedas::bigint + c.recompensa)::int, diamantes = diamantes + c.diamantes
         where id = r.jogador_id;
      end if;
    end if;
    v_n := v_n + 1;
  end loop;
  insert into fazenda_invasao_fechamentos (evento, premiados) values (v_ev, v_n) on conflict do nothing;
end;
$$;

-- O painel: as regras, a hora do servidor, você, o placar e (depois do fim) o seu prêmio.
-- p_visto = true marca o prêmio como visto (o aviso "Você ganhou" não volta).
create or replace function public.fazenda_invasao(p_token text, p_visto boolean default false, p_teste boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id uuid := fazenda_auth_ler(p_token);
  v_r  jsonb := fazenda_invasao_regras(p_teste);
  v_pr record;
  v_fech boolean;
begin
  if p_teste and not exists (select 1 from fazenda_jogadores where id = v_id and admin is not null) then raise exception 'sem_permissao'; end if;
  perform fazenda_invasao_fechar();
  v_fech := exists (select 1 from fazenda_invasao_fechamentos where evento = v_r->>'id');
  select * into v_pr from fazenda_invasao_premios where evento = v_r->>'id' and jogador_id = v_id;
  if found and p_visto and not v_pr.visto then
    update fazenda_invasao_premios set visto = true where evento = v_r->>'id' and jogador_id = v_id;
  end if;
  return jsonb_build_object('regras', v_r, 'agora', now(), 'fechada', v_fech,
    'nivel', (select fazenda_nivel_de(xp, nivel_trava) from fazenda_jogadores where id = v_id),
    'eu', fazenda_invasao_eu(v_r, v_id),
    'sala', case when now() >= (v_r->>'inicio')::timestamptz - interval '1 day' then fazenda_invasao_sala(v_r) end,
    'premio', case when v_pr.posicao is not null then jsonb_build_object('posicao', v_pr.posicao, 'pontos', v_pr.pontos,
      'diamantes', v_pr.diamantes, 'moedas', v_pr.moedas, 'visto', v_pr.visto) end);
end;
$$;

-- O lote: o que o jogo manda a cada 2,5 s enquanto você está na sala ({"k": toques} dos ETs em que você
-- tocou; vazio também vale: diz que você continua na sala e devolve a sala).
create or replace function public.fazenda_invasao_lote(p_token text, p_toques jsonb, p_teste boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id    uuid := fazenda_auth_ler(p_token);
  v_r     jsonb := fazenda_invasao_regras(p_teste);
  v_ev    text := v_r->>'id';
  m       record;
  v_pod   record;
  a       record;
  e       record;
  v_dt    double precision;
  v_saldo double precision;
  v_golpes jsonb := '{}'::jsonb;
  v_k     int;
  v_n     int;
  v_feito int;
  v_dano  int;
  v_usou  int;
  v_qtd   int := 0;
  v_alvo  int;
  v_pts   bigint := 0;
  v_abat  int := 0;
  v_chef  int := 0;
  v_auto  double precision := 0;
  v_cont  int := 0;
  c       record;
begin
  if p_teste and not exists (select 1 from fazenda_jogadores where id = v_id and admin is not null) then raise exception 'sem_permissao'; end if;
  if now() < (v_r->>'inicio')::timestamptz then raise exception 'invasao_antes'; end if;
  if now() >= (v_r->>'fim')::timestamptz then raise exception 'invasao_acabou'; end if;
  if (select fazenda_nivel_de(xp, nivel_trava) from fazenda_jogadores where id = v_id) < (v_r->>'nivel_min')::int then
    raise exception 'invasao_nivel';
  end if;
  insert into fazenda_invasao (evento, jogador_id, saldo, ult_lote) values (v_ev, v_id, 5, now()) on conflict do nothing;
  select * into m from fazenda_invasao where evento = v_ev and jogador_id = v_id for update;
  v_dt := least((v_r->>'lote_max_seg')::double precision, greatest(0, extract(epoch from now() - coalesce(m.ult_lote, now()))));
  v_saldo := least((v_r->>'toques_max')::double precision, m.saldo + (v_r->>'toques_seg')::double precision * v_dt);
  select * into v_pod from fazenda_invasao_poder(v_r, m.armas);

  -- o dano já feito só vale para os ETs que ainda estão na tela
  for e in select key, value from jsonb_each_text(m.golpes) loop
    select * into a from fazenda_invasao_alien(e.key::int, v_r);
    if found and a.morre + interval '3 seconds' > now() then v_golpes := v_golpes || jsonb_build_object(e.key, e.value::int); end if;
  end loop;

  -- os toques: no máximo 40 ETs por lote; cada um só se estiver na tela agora; nunca além do saldo
  if p_toques is not null and jsonb_typeof(p_toques) = 'object' then
    for e in select key, value from jsonb_each_text(p_toques) loop
      v_cont := v_cont + 1;
      exit when v_cont > 40 or v_saldo < 1;
      begin
        v_k := e.key::int; v_n := greatest(0, least(e.value::int, floor(v_saldo)::int));
      exception when others then continue;
      end;
      continue when v_n <= 0;
      select * into a from fazenda_invasao_alien(v_k, v_r);
      continue when not found or now() < a.nasce - interval '1 second' or now() > a.morre + interval '3 seconds';
      v_feito := coalesce((v_golpes->>v_k::text)::int, 0);
      continue when v_feito >= a.hp;
      v_dano := least(v_n * v_pod.por_toque, a.hp - v_feito);
      v_usou := ceil(v_dano::numeric / v_pod.por_toque)::int;
      v_saldo := v_saldo - v_usou;
      v_qtd := v_qtd + v_usou;
      v_alvo := v_k;
      v_pts := v_pts + v_dano;
      v_golpes := v_golpes || jsonb_build_object(v_k::text, v_feito + v_dano);
      if v_feito + v_dano >= a.hp then
        if a.chefe then v_chef := v_chef + 1; v_pts := v_pts + (v_r->>'bonus_chefe')::int;
        else v_abat := v_abat + 1; v_pts := v_pts + (v_r->>'bonus_abate')::int; end if;
      end if;
    end loop;
  end if;

  -- as automáticas: só para quem tocou num ET nos últimos 2 minutos
  if v_qtd > 0 or (m.ult_toque is not null and m.ult_toque > now() - make_interval(secs => (v_r->>'auto_ativo_seg')::int)) then
    v_auto := v_pod.por_seg * v_dt + m.auto_resto;
  end if;
  v_pts := v_pts + floor(v_auto)::bigint;

  update fazenda_invasao set
    pontos = pontos + v_pts, abates = abates + v_abat, chefes = chefes + v_chef, toques = toques + v_qtd,
    saldo = v_saldo, golpes = v_golpes, auto_resto = v_auto - floor(v_auto),
    ult_lote = now(), ult_toque = case when v_qtd > 0 then now() else ult_toque end,
    ult_qtd = v_qtd, ult_alvo = coalesce(v_alvo, ult_alvo), visto_em = now(),
    subiu_em = case when v_pts > 0 then now() else subiu_em end
   where evento = v_ev and jogador_id = v_id;

  -- a conquista do chefão (paga só quem gravou agora; no teste, não)
  if v_chef > 0 and not p_teste then
    select * into c from fazenda_conquistas_tipos where id = 'invasao_chefe';
    insert into fazenda_conquistas (jogador_id, conquista) values (v_id, 'invasao_chefe') on conflict do nothing;
    if found then
      update fazenda_jogadores set moedas = least(2147483647, moedas::bigint + c.recompensa)::int, diamantes = diamantes + c.diamantes
       where id = v_id;
    end if;
  end if;

  return jsonb_build_object('agora', now(), 'ganhou', v_pts, 'valeram', v_qtd, 'eu', fazenda_invasao_eu(v_r, v_id),
                            'sala', fazenda_invasao_sala(v_r));
end;
$$;

-- Comprar o próximo nível de uma arma (com moedas; só durante a invasão). Esta espera a fila do jogador,
-- porque mexe nas moedas.
create or replace function public.fazenda_invasao_comprar(p_token text, p_arma text, p_teste boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_r     jsonb := fazenda_invasao_regras(p_teste);
  v_ev    text := v_r->>'id';
  v_nivel int;
  v_preco bigint;
  v_moedas int;
begin
  if p_teste and not exists (select 1 from fazenda_jogadores where id = v_id and admin is not null) then raise exception 'sem_permissao'; end if;
  if now() < (v_r->>'inicio')::timestamptz then raise exception 'invasao_antes'; end if;
  if now() >= (v_r->>'fim')::timestamptz then raise exception 'invasao_acabou'; end if;
  if (select fazenda_nivel_de(xp, nivel_trava) from fazenda_jogadores where id = v_id) < (v_r->>'nivel_min')::int then
    raise exception 'invasao_nivel';
  end if;
  if not exists (select 1 from jsonb_array_elements(v_r->'armas') a where a->>'id' = p_arma) then
    raise exception 'arma_invalida';
  end if;
  insert into fazenda_invasao (evento, jogador_id, saldo, ult_lote) values (v_ev, v_id, 5, now()) on conflict do nothing;
  select coalesce((armas->>p_arma)::int, 0) into v_nivel from fazenda_invasao where evento = v_ev and jogador_id = v_id for update;
  v_preco := fazenda_invasao_preco(v_r, p_arma, v_nivel);
  if v_preco is null then raise exception 'arma_maxima'; end if;
  if p_teste then v_preco := 0; end if;   -- no teste dos admins, as armas são de graça
  select moedas into v_moedas from fazenda_jogadores where id = v_id for update;
  if v_moedas < v_preco then raise exception 'sem_moedas'; end if;
  update fazenda_jogadores set moedas = moedas - v_preco where id = v_id;
  update fazenda_invasao set armas = armas || jsonb_build_object(p_arma, v_nivel + 1), gastou = gastou + v_preco
   where evento = v_ev and jogador_id = v_id;
  return jsonb_build_object('moedas', v_moedas - v_preco, 'pagou', v_preco, 'arma', p_arma, 'nivel', v_nivel + 1,
                            'eu', fazenda_invasao_eu(v_r, v_id));
end;
$$;

-- permissões
revoke execute on function
  public.fazenda_invasao_regras(boolean),
  public.fazenda_invasao_alien(int, jsonb),
  public.fazenda_invasao_preco(jsonb, text, int),
  public.fazenda_invasao_poder(jsonb, jsonb),
  public.fazenda_invasao_premio(jsonb, int),
  public.fazenda_invasao_eu(jsonb, uuid),
  public.fazenda_invasao_sala(jsonb),
  public.fazenda_invasao_fechar()
from public, anon, authenticated;

grant execute on function
  public.fazenda_invasao(text, boolean, boolean),
  public.fazenda_invasao_lote(text, jsonb, boolean),
  public.fazenda_invasao_comprar(text, text, boolean)
to anon, authenticated;

-- o relógio do banco também fecha a invasão (de 5 em 5 min; depois de fechada, não faz nada)
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'fazenda_invasao';
    perform cron.schedule('fazenda_invasao', '*/5 * * * *', 'select public.fazenda_invasao_fechar()');
  else
    raise notice 'Fase 94: sem o pg_cron, a invasão fecha na primeira chamada depois da meia-noite (também funciona).';
  end if;
end $$;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou (as conquistas novas)
select public.fazenda_cache_montar();

-- conferência: 3 tabelas, as funções do jogo, as 2 conquistas e os prêmios do 1º ao 5º
select (select count(*) from information_schema.tables where table_schema = 'public'
          and table_name in ('fazenda_invasao', 'fazenda_invasao_premios', 'fazenda_invasao_fechamentos')) as tabelas_novas,
       (select count(*) from pg_proc where proname in ('fazenda_invasao', 'fazenda_invasao_lote', 'fazenda_invasao_comprar')) as funcoes_do_jogo,
       (select count(*) from public.fazenda_conquistas_tipos where id in ('invasao_chefe', 'invasao_defensor')) as conquistas_novas,
       (select count(*) from public.fazenda_jogadores where admin is not null) as admins_que_podem_testar,
       (select string_agg(p.diamantes || ' 💎 + ' || p.moedas || ' moedas', ' | ' order by g)
          from generate_series(1, 5) g, public.fazenda_invasao_premio(public.fazenda_invasao_regras(), g) p) as premios_1_ao_5;
