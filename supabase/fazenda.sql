-- ============================================================
-- FAZENDINHA SECRETA — easter egg do portfólio (fase 1)
--
-- Roda no mesmo projeto Supabase do RabbitFin, mas totalmente isolado:
--   • NÃO usa Supabase Auth (o trigger on_auth_user_created do RabbitFin
--     criaria um "espaço financeiro" para cada jogador).
--   • Tabelas com prefixo fazenda_, RLS ligado e SEM policies: a chave
--     pública não lê nem escreve nada diretamente.
--   • Todo acesso passa por funções security definer que validam o token
--     do jogador e aplicam as regras (tempo, moedas, nível) no servidor.
--
-- Como rodar: Supabase > SQL Editor > colar este arquivo > Run.
-- Pode rodar de novo sem problemas (idempotente).
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

-- ------------------------------------------------------------
-- Tabelas
-- ------------------------------------------------------------
create table if not exists public.fazenda_culturas (
  id          text primary key,
  nome        text not null,
  emoji       text not null,
  tempo_seg   int  not null check (tempo_seg > 0),
  custo       int  not null check (custo >= 0),
  venda       int  not null check (venda >= 0),   -- preço por unidade
  rendimento  int  not null check (rendimento > 0), -- unidades por colheita perfeita
  xp          int  not null check (xp >= 0),
  nivel_min   int  not null default 1,
  ordem       int  not null default 0
);

create table if not exists public.fazenda_jogadores (
  id           uuid primary key default gen_random_uuid(),
  apelido      text not null check (char_length(apelido) between 2 and 20),
  codigo_hash  text not null unique,
  moedas       int  not null default 200 check (moedas >= 0),
  xp           int  not null default 0 check (xp >= 0),
  criado_em    timestamptz not null default now(),
  visto_em     timestamptz not null default now()
);

-- Um jogador pode ter várias sessões (um token por aparelho)
create table if not exists public.fazenda_sessoes (
  token_hash  text primary key,
  jogador_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  criado_em   timestamptz not null default now()
);
create index if not exists fazenda_sessoes_jogador_idx on public.fazenda_sessoes(jogador_id);

create table if not exists public.fazenda_canteiros (
  jogador_id   uuid not null references public.fazenda_jogadores(id) on delete cascade,
  posicao      smallint not null check (posicao between 0 and 17),
  estado       text not null default 'vazio' check (estado in ('vazio', 'arado', 'plantado')),
  cultura      text references public.fazenda_culturas(id),
  plantado_em  timestamptz,
  erva         boolean not null default false,
  praga        boolean not null default false,
  seco         boolean not null default false,
  prox_evento  timestamptz,
  primary key (jogador_id, posicao)
);

create table if not exists public.fazenda_celeiro (
  jogador_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  item        text not null references public.fazenda_culturas(id),
  quantidade  int  not null default 0 check (quantidade >= 0),
  primary key (jogador_id, item)
);

-- Fase 2: quanto já foi "pego" por vizinhos do plantio atual
alter table public.fazenda_canteiros add column if not exists roubado int not null default 0;

-- Fase 2: visitas de vizinhos (roubos e ajudas) — também é o diário do dono
create table if not exists public.fazenda_visitas (
  id           bigint generated always as identity primary key,
  ator_id      uuid not null references public.fazenda_jogadores(id) on delete cascade,
  dono_id      uuid not null references public.fazenda_jogadores(id) on delete cascade,
  tipo         text not null check (tipo in ('roubo', 'ajuda')),
  posicao      smallint not null,
  plantado_em  timestamptz not null,
  cultura      text not null references public.fazenda_culturas(id),
  qtd          int not null default 0,
  criado_em    timestamptz not null default now()
);
-- cada vizinho só pega uma vez de cada plantio
create unique index if not exists fazenda_visitas_roubo_unico
  on public.fazenda_visitas (ator_id, dono_id, posicao, plantado_em) where tipo = 'roubo';
create index if not exists fazenda_visitas_dono_idx on public.fazenda_visitas (dono_id, criado_em desc);
create index if not exists fazenda_visitas_ator_idx on public.fazenda_visitas (ator_id, tipo, criado_em desc);
create index if not exists fazenda_jogadores_xp_idx on public.fazenda_jogadores (xp desc);
create index if not exists fazenda_jogadores_criado_idx on public.fazenda_jogadores (criado_em desc);

-- RLS ligado e nenhuma policy = acesso direto negado para anon/authenticated
alter table public.fazenda_culturas  enable row level security;
alter table public.fazenda_jogadores enable row level security;
alter table public.fazenda_sessoes   enable row level security;
alter table public.fazenda_canteiros enable row level security;
alter table public.fazenda_celeiro   enable row level security;
alter table public.fazenda_visitas   enable row level security;

revoke all on public.fazenda_culturas, public.fazenda_jogadores, public.fazenda_sessoes,
              public.fazenda_canteiros, public.fazenda_celeiro, public.fazenda_visitas
  from anon, authenticated;

-- ------------------------------------------------------------
-- Catálogo de sementes
-- ------------------------------------------------------------
insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem) values
  ('alface',   'Alface',   '🥬',   120,  10,  4,  5,  2, 1, 1),
  ('cenoura',  'Cenoura',  '🥕',   900,  20,  6,  6,  4, 1, 2),
  -- os ids batata/abobora/morango ficaram da primeira versão; o nome segue a arte do jogo
  ('batata',   'Beterraba', '🟣',  3600,  35,  9,  7,  8, 2, 3),
  ('milho',    'Milho',     '🌽',  7200,  50, 12,  8, 12, 3, 4),
  ('tomate',   'Tomate',    '🍅', 14400,  70, 15,  9, 18, 4, 5),
  ('girassol', 'Girassol',  '🌻', 21600,  90, 20,  8, 24, 5, 6),
  ('abobora',  'Trigo',     '🌾', 28800, 110, 26,  8, 30, 6, 7),
  ('morango',  'Amora',     '🫐', 43200, 140, 22, 12, 40, 7, 8)
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, tempo_seg = excluded.tempo_seg,
  custo = excluded.custo, venda = excluded.venda, rendimento = excluded.rendimento,
  xp = excluded.xp, nivel_min = excluded.nivel_min, ordem = excluded.ordem;

-- A melancia saiu do catálogo (não existe na arte). Só apaga se ninguém usou.
delete from public.fazenda_culturas k
 where k.id = 'melancia'
   and not exists (select 1 from public.fazenda_canteiros c where c.cultura = k.id)
   and not exists (select 1 from public.fazenda_celeiro ce where ce.item = k.id)
   and not exists (select 1 from public.fazenda_visitas v where v.cultura = k.id);

-- ------------------------------------------------------------
-- Funções internas (não expostas à API)
-- ------------------------------------------------------------

-- Nível a partir do XP: nível n começa em 25·(n-1)² XP (25, 100, 225, 400...)
create or replace function public.fazenda_nivel(p_xp int)
returns int language sql immutable as $$
  select floor(sqrt(greatest(p_xp, 0) / 25.0))::int + 1;
$$;

create or replace function public.fazenda_max_canteiros(p_nivel int)
returns int language sql immutable as $$
  select least(6 + (p_nivel - 1) * 2, 18);
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
  update fazenda_jogadores set visto_em = now() where id = v_id;
  return v_id;
end;
$$;

create or replace function public.fazenda_nova_sessao(p_jogador uuid)
returns text
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_token text := encode(gen_random_bytes(24), 'hex');
begin
  insert into fazenda_sessoes (token_hash, jogador_id)
  values (encode(digest(v_token, 'sha256'), 'hex'), p_jogador);
  return v_token;
end;
$$;

-- Materializa os problemas (erva, praga, seca) que "aconteceram" enquanto a
-- planta crescia. Só ocorrem antes de a planta amadurecer.
create or replace function public.fazenda_tick(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  r        record;
  v_maduro timestamptz;
  v_evt    timestamptz;
  v_erva   boolean;
  v_praga  boolean;
  v_seco   boolean;
  v_tipo   int;
  i        int;
begin
  for r in
    select c.posicao, c.plantado_em, c.prox_evento, c.erva, c.praga, c.seco, k.tempo_seg
      from fazenda_canteiros c
      join fazenda_culturas k on k.id = c.cultura
     where c.jogador_id = p_jogador
       and c.estado = 'plantado'
       and c.prox_evento is not null
       and c.prox_evento <= now()
       for update of c
  loop
    v_maduro := r.plantado_em + make_interval(secs => r.tempo_seg);
    v_evt := r.prox_evento;
    v_erva := r.erva; v_praga := r.praga; v_seco := r.seco;
    i := 0;
    while v_evt <= now() and v_evt < v_maduro and i < 3 loop
      v_tipo := floor(random() * 3)::int;
      if v_tipo = 0 then v_erva := true;
      elsif v_tipo = 1 then v_praga := true;
      else v_seco := true;
      end if;
      v_evt := v_evt + make_interval(secs => r.tempo_seg * (0.25 + random() * 0.35));
      i := i + 1;
    end loop;
    if v_evt >= v_maduro then
      v_evt := null;
    end if;
    update fazenda_canteiros
       set erva = v_erva, praga = v_praga, seco = v_seco, prox_evento = v_evt
     where jogador_id = p_jogador and posicao = r.posicao;
  end loop;
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
begin
  select * into j from fazenda_jogadores where id = p_jogador;
  v_nivel := fazenda_nivel(j.xp);
  v_max := fazenda_max_canteiros(v_nivel);

  -- Libera canteiros novos conforme o nível
  insert into fazenda_canteiros (jogador_id, posicao)
  select p_jogador, g from generate_series(0, v_max - 1) g
  on conflict do nothing;

  return jsonb_build_object(
    'agora', now(),
    'jogador', jsonb_build_object(
      'id', j.id,
      'apelido', j.apelido,
      'moedas', j.moedas,
      'xp', j.xp,
      'nivel', v_nivel,
      'xp_nivel', 25 * (v_nivel - 1) * (v_nivel - 1),
      'xp_proximo', 25 * v_nivel * v_nivel,
      'max_canteiros', v_max
    ),
    'canteiros', coalesce((
      select jsonb_agg(jsonb_build_object(
               'posicao', posicao, 'estado', estado, 'cultura', cultura,
               'plantado_em', plantado_em, 'erva', erva, 'praga', praga, 'seco', seco,
               'roubado', roubado)
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
    'culturas', (
      select jsonb_agg(jsonb_build_object(
               'id', id, 'nome', nome, 'emoji', emoji, 'tempo_seg', tempo_seg,
               'custo', custo, 'venda', venda, 'rendimento', rendimento,
               'xp', xp, 'nivel_min', nivel_min)
             order by ordem)
        from fazenda_culturas)
  );
end;
$$;

-- Aplica uma ação em um canteiro. Retorna a quantidade colhida (0 se não colheu).
create or replace function public.fazenda_aplicar(p_jogador uuid, p_acao text, p_posicao int, p_cultura text)
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

  if p_acao = 'arar' then
    if c.estado = 'arado' then
      raise exception 'ja_arado';
    end if;
    if c.estado = 'plantado' and now() < v_murcho then
      raise exception 'canteiro_ocupado';
    end if;
    update fazenda_canteiros
       set estado = 'arado', cultura = null, plantado_em = null,
           erva = false, praga = false, seco = false, roubado = 0, prox_evento = null
     where jogador_id = p_jogador and posicao = p_posicao;
    update fazenda_jogadores set xp = xp + 1 where id = p_jogador;

  elsif p_acao = 'plantar' then
    if c.estado <> 'arado' then
      raise exception 'precisa_arar';
    end if;
    select * into k from fazenda_culturas where id = p_cultura;
    if not found then
      raise exception 'cultura_invalida';
    end if;
    if fazenda_nivel(j.xp) < k.nivel_min then
      raise exception 'nivel_insuficiente';
    end if;
    if j.moedas < k.custo then
      raise exception 'moedas_insuficientes';
    end if;
    update fazenda_jogadores set moedas = moedas - k.custo where id = p_jogador;
    update fazenda_canteiros
       set estado = 'plantado', cultura = k.id, plantado_em = now(),
           erva = false, praga = false, seco = false, roubado = 0,
           prox_evento = now() + make_interval(secs => k.tempo_seg * (0.15 + random() * 0.35))
     where jogador_id = p_jogador and posicao = p_posicao;

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
    update fazenda_jogadores set xp = xp + 1, moedas = moedas + 1 where id = p_jogador;

  elsif p_acao = 'colher' then
    if c.estado <> 'plantado' or now() < v_maduro then
      raise exception 'nao_maduro';
    end if;
    if now() >= v_murcho then
      raise exception 'murchou';
    end if;
    -- cada problema não resolvido custa 1 unidade; o que os vizinhos pegaram também sai
    v_qtd := greatest(k.rendimento - (c.erva::int + c.praga::int + c.seco::int) - c.roubado, 1);
    insert into fazenda_celeiro (jogador_id, item, quantidade)
    values (p_jogador, k.id, v_qtd)
    on conflict (jogador_id, item)
    do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
    update fazenda_jogadores set xp = xp + k.xp where id = p_jogador;
    update fazenda_canteiros
       set estado = 'vazio', cultura = null, plantado_em = null,
           erva = false, praga = false, seco = false, roubado = 0, prox_evento = null
     where jogador_id = p_jogador and posicao = p_posicao;

  else
    raise exception 'acao_invalida';
  end if;

  return v_qtd;
end;
$$;

-- ------------------------------------------------------------
-- API pública (chamada via /rest/v1/rpc/...)
-- ------------------------------------------------------------

create or replace function public.fazenda_criar(p_apelido text)
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
begin
  p_apelido := btrim(p_apelido);
  if p_apelido is null or char_length(p_apelido) not between 2 and 20 then
    raise exception 'apelido_invalido';
  end if;

  -- Freio contra spam: no máximo 300 fazendas novas por hora no total
  if (select count(*) from fazenda_jogadores where criado_em > now() - interval '1 hour') >= 300 then
    raise exception 'muitas_fazendas';
  end if;

  -- Código de recuperação: PALAVRA-XXXX-XXXX (~10^13 combinações)
  v_codigo := v_palavras[1 + get_byte(v_bytes, 0) % array_length(v_palavras, 1)] || '-';
  for i in 1..8 loop
    v_codigo := v_codigo || substr(v_alfabeto, 1 + get_byte(v_bytes, i) % length(v_alfabeto), 1);
    if i = 4 then
      v_codigo := v_codigo || '-';
    end if;
  end loop;

  insert into fazenda_jogadores (apelido, codigo_hash)
  values (p_apelido, encode(digest(v_codigo, 'sha256'), 'hex'))
  returning id into v_id;

  -- Começa com 6 canteiros já arados
  insert into fazenda_canteiros (jogador_id, posicao, estado)
  select v_id, g, 'arado' from generate_series(0, 5) g;

  return jsonb_build_object(
    'token', fazenda_nova_sessao(v_id),
    'codigo', v_codigo,
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
begin
  p_codigo := upper(regexp_replace(coalesce(p_codigo, ''), '\s', '', 'g'));
  select id into v_id from fazenda_jogadores
   where codigo_hash = encode(digest(p_codigo, 'sha256'), 'hex');
  if v_id is null then
    raise exception 'codigo_invalido';
  end if;
  perform fazenda_tick(v_id);
  return jsonb_build_object(
    'token', fazenda_nova_sessao(v_id),
    'estado', fazenda_estado(v_id)
  );
end;
$$;

create or replace function public.fazenda_carregar(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
begin
  perform fazenda_tick(v_id);
  return fazenda_estado(v_id);
end;
$$;

-- p_acao: arar | plantar | erva | praga | seco | colher
-- p_posicoes: um ou vários canteiros. Com um só, erros são devolvidos;
-- com vários (ações "em todos"), canteiros que não se aplicam são ignorados.
create or replace function public.fazenda_acao(p_token text, p_acao text, p_posicoes int[], p_cultura text default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id      uuid := fazenda_auth(p_token);
  v_pos     int;
  v_qtd     int;
  v_colhido jsonb := '{}'::jsonb;
  v_feitos  int := 0;
begin
  if p_posicoes is null or array_length(p_posicoes, 1) is null then
    raise exception 'nada_a_fazer';
  end if;
  if array_length(p_posicoes, 1) > 18 then
    raise exception 'acao_invalida';
  end if;

  perform fazenda_tick(v_id);

  foreach v_pos in array p_posicoes loop
    if array_length(p_posicoes, 1) = 1 then
      v_qtd := fazenda_aplicar(v_id, p_acao, v_pos, p_cultura);
      v_feitos := v_feitos + 1;
    else
      begin
        v_qtd := fazenda_aplicar(v_id, p_acao, v_pos, p_cultura);
        v_feitos := v_feitos + 1;
      exception when others then
        v_qtd := 0;
      end;
    end if;
    if v_qtd > 0 then
      v_colhido := v_colhido || jsonb_build_object(v_pos::text, v_qtd);
    end if;
  end loop;

  return jsonb_build_object(
    'feitos', v_feitos,
    'colhido', v_colhido,
    'estado', fazenda_estado(v_id)
  );
end;
$$;

-- p_quantidade null = vende tudo daquele item. p_item null = vende o celeiro todo.
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
begin
  if p_quantidade is not null and p_quantidade <= 0 then
    raise exception 'quantidade_invalida';
  end if;

  for r in
    select ce.item, ce.quantidade, k.venda
      from fazenda_celeiro ce
      join fazenda_culturas k on k.id = ce.item
     where ce.jogador_id = v_id
       and ce.quantidade > 0
       and (p_item is null or ce.item = p_item)
       for update of ce
  loop
    v_qtd := least(coalesce(p_quantidade, r.quantidade), r.quantidade);
    update fazenda_celeiro set quantidade = quantidade - v_qtd
     where jogador_id = v_id and item = r.item;
    v_ganho := v_ganho + v_qtd * r.venda;
  end loop;

  update fazenda_jogadores set moedas = moedas + v_ganho where id = v_id;

  return jsonb_build_object('ganho', v_ganho, 'estado', fazenda_estado(v_id));
end;
$$;

-- ============================================================
-- FASE 2 — VIZINHOS: ranking, visitar, pegar colheita e ajudar
--
-- Regras:
--   • Só dá pra pegar de canteiro maduro (e não murcho) de outra pessoa.
--   • Cada vizinho pega uma vez por plantio: 1 ou 2 unidades.
--   • Um canteiro perde no máximo 40% da colheita para vizinhos.
--   • Limite diário: 30 "pegadas" e 30 ajudas recompensadas por jogador.
--   • Ajudar tira todos os problemas do canteiro do vizinho e rende
--     +1 XP e +1 moeda por problema para quem ajudou.
-- ============================================================

create or replace function public.fazenda_limite_roubo(p_rendimento int)
returns int language sql immutable as $$
  select floor(p_rendimento * 0.4)::int;
$$;

-- Fazenda de um vizinho vista por quem está visitando
create or replace function public.fazenda_vizinho(p_dono uuid, p_ator uuid)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  j       record;
  v_nivel int;
begin
  select * into j from fazenda_jogadores where id = p_dono;
  v_nivel := fazenda_nivel(j.xp);
  return jsonb_build_object(
    'agora', now(),
    'id', j.id,
    'apelido', j.apelido,
    'nivel', v_nivel,
    'max_canteiros', fazenda_max_canteiros(v_nivel),
    'canteiros', coalesce((
      select jsonb_agg(jsonb_build_object(
               'posicao', c.posicao, 'estado', c.estado, 'cultura', c.cultura,
               'plantado_em', c.plantado_em, 'erva', c.erva, 'praga', c.praga, 'seco', c.seco,
               'roubado', c.roubado,
               'ja_peguei', exists (
                 select 1 from fazenda_visitas v
                  where v.tipo = 'roubo' and v.ator_id = p_ator and v.dono_id = p_dono
                    and v.posicao = c.posicao and v.plantado_em = c.plantado_em))
             order by c.posicao)
        from fazenda_canteiros c where c.jogador_id = p_dono), '[]'::jsonb)
  );
end;
$$;

-- Pega colheita de um canteiro do vizinho. Retorna a quantidade pega.
create or replace function public.fazenda_pegar_um(p_ator uuid, p_dono uuid, p_posicao int)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  c        record;
  k        record;
  v_maduro timestamptz;
  v_qtd    int;
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
  if exists (select 1 from fazenda_visitas
              where tipo = 'roubo' and ator_id = p_ator and dono_id = p_dono
                and posicao = p_posicao and plantado_em = c.plantado_em) then
    raise exception 'ja_pegou';
  end if;
  if c.roubado >= fazenda_limite_roubo(k.rendimento) then
    raise exception 'nada_pra_pegar';
  end if;
  if (select count(*) from fazenda_visitas
       where ator_id = p_ator and tipo = 'roubo' and criado_em > now() - interval '1 day') >= 30 then
    raise exception 'limite_pegadas';
  end if;

  v_qtd := least(1 + (random() < 0.4)::int, fazenda_limite_roubo(k.rendimento) - c.roubado);

  update fazenda_canteiros set roubado = roubado + v_qtd
   where jogador_id = p_dono and posicao = p_posicao;
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  values (p_ator, k.id, v_qtd)
  on conflict (jogador_id, item)
  do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd)
  values (p_ator, p_dono, 'roubo', p_posicao, c.plantado_em, k.id, v_qtd);

  return v_qtd;
end;
$$;

-- Tira os problemas de um canteiro do vizinho. Retorna quantos problemas resolveu.
create or replace function public.fazenda_ajudar_um(p_ator uuid, p_dono uuid, p_posicao int)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  c         record;
  k         record;
  v_n       int;
  v_hoje    int;
  v_premio  int;
begin
  select * into c from fazenda_canteiros
   where jogador_id = p_dono and posicao = p_posicao
     for update;
  if not found or c.estado <> 'plantado' then
    raise exception 'nada_a_fazer';
  end if;
  select * into k from fazenda_culturas where id = c.cultura;
  if now() >= c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) then
    raise exception 'nada_a_fazer';
  end if;
  v_n := c.erva::int + c.praga::int + c.seco::int;
  if v_n = 0 then
    raise exception 'nada_a_fazer';
  end if;

  update fazenda_canteiros set erva = false, praga = false, seco = false
   where jogador_id = p_dono and posicao = p_posicao;

  -- Recompensa só até 30 problemas resolvidos por dia (ajudar além disso é caridade)
  select coalesce(sum(qtd), 0) into v_hoje from fazenda_visitas
   where ator_id = p_ator and tipo = 'ajuda' and criado_em > now() - interval '1 day';
  v_premio := greatest(least(v_n, 30 - v_hoje), 0);
  if v_premio > 0 then
    update fazenda_jogadores set xp = xp + v_premio, moedas = moedas + v_premio where id = p_ator;
  end if;

  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd)
  values (p_ator, p_dono, 'ajuda', p_posicao, c.plantado_em, k.id, v_n);

  return v_n;
end;
$$;

create or replace function public.fazenda_ranking(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_xp   int;
  v_desde timestamptz;
begin
  select xp, criado_em into v_xp, v_desde from fazenda_jogadores where id = v_id;
  return jsonb_build_object(
    -- mesmo critério de desempate da lista: quem chegou antes fica na frente
    'minha_posicao', (select count(*) + 1 from fazenda_jogadores
                       where xp > v_xp or (xp = v_xp and criado_em < v_desde)),
    'total', (select count(*) from fazenda_jogadores),
    'ranking', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', r.id, 'apelido', r.apelido, 'nivel', fazenda_nivel(r.xp), 'xp', r.xp,
               'patrimonio', r.moedas + coalesce((
                 select sum(ce.quantidade * k.venda)
                   from fazenda_celeiro ce join fazenda_culturas k on k.id = ce.item
                  where ce.jogador_id = r.id), 0),
               'eu', r.id = v_id)
             order by r.xp desc, r.criado_em)
        from (select * from fazenda_jogadores order by xp desc, criado_em limit 50) r), '[]'::jsonb)
  );
end;
$$;

-- p_vizinho null = sorteia alguém (de preferência com colheita madura)
create or replace function public.fazenda_visitar(p_token text, p_vizinho uuid default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_dono uuid := p_vizinho;
begin
  if v_dono is null then
    select j.id into v_dono
      from fazenda_jogadores j
     where j.id <> v_id
       and j.visto_em > now() - interval '30 days'
     order by exists (
               select 1 from fazenda_canteiros c join fazenda_culturas k on k.id = c.cultura
                where c.jogador_id = j.id and c.estado = 'plantado'
                  and c.plantado_em + make_interval(secs => k.tempo_seg) <= now()) desc,
              random()
     limit 1;
    if v_dono is null then
      raise exception 'nenhum_vizinho';
    end if;
  elsif v_dono = v_id then
    raise exception 'propria_fazenda';
  elsif not exists (select 1 from fazenda_jogadores where id = v_dono) then
    raise exception 'vizinho_invalido';
  end if;

  perform fazenda_tick(v_dono);
  return fazenda_vizinho(v_dono, v_id);
end;
$$;

-- p_acao: pegar | ajudar. Mesmo esquema de lote do fazenda_acao.
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
  if not exists (select 1 from fazenda_jogadores where id = p_vizinho) then
    raise exception 'vizinho_invalido';
  end if;
  if p_acao not in ('pegar', 'ajudar') then
    raise exception 'acao_invalida';
  end if;
  if p_posicoes is null or array_length(p_posicoes, 1) is null then
    raise exception 'nada_a_fazer';
  end if;
  if array_length(p_posicoes, 1) > 18 then
    raise exception 'acao_invalida';
  end if;

  perform fazenda_tick(p_vizinho);

  foreach v_pos in array p_posicoes loop
    begin
      if p_acao = 'pegar' then
        v_qtd := fazenda_pegar_um(v_id, p_vizinho, v_pos);
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

-- ------------------------------------------------------------
-- Permissões: só a API pública fica executável pela chave anon
-- ------------------------------------------------------------
revoke execute on function
  public.fazenda_nivel(int),
  public.fazenda_max_canteiros(int),
  public.fazenda_auth(text),
  public.fazenda_nova_sessao(uuid),
  public.fazenda_tick(uuid),
  public.fazenda_estado(uuid),
  public.fazenda_aplicar(uuid, text, int, text),
  public.fazenda_criar(text),
  public.fazenda_recuperar(text),
  public.fazenda_carregar(text),
  public.fazenda_acao(text, text, int[], text),
  public.fazenda_vender(text, text, int),
  public.fazenda_limite_roubo(int),
  public.fazenda_vizinho(uuid, uuid),
  public.fazenda_pegar_um(uuid, uuid, int),
  public.fazenda_ajudar_um(uuid, uuid, int),
  public.fazenda_ranking(text),
  public.fazenda_visitar(text, uuid),
  public.fazenda_acao_vizinho(text, uuid, text, int[])
from public, anon, authenticated;

grant execute on function
  public.fazenda_criar(text),
  public.fazenda_recuperar(text),
  public.fazenda_carregar(text),
  public.fazenda_acao(text, text, int[], text),
  public.fazenda_vender(text, text, int),
  public.fazenda_ranking(text),
  public.fazenda_visitar(text, uuid),
  public.fazenda_acao_vizinho(text, uuid, text, int[])
to anon, authenticated;
