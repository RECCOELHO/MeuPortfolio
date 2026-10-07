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

-- Fase 3: produtos de animais (ovo, leite) também vivem no catálogo,
-- para poderem ir ao celeiro e ser vendidos. Só 'cultura' pode ser plantada.
alter table public.fazenda_culturas add column if not exists tipo text not null default 'cultura';
do $$ begin
  alter table public.fazenda_culturas add constraint fazenda_culturas_tipo_chk check (tipo in ('cultura', 'produto'));
exception when duplicate_object then null; end $$;

-- Fase 3: animais
create table if not exists public.fazenda_animais_tipos (
  id          text primary key,
  nome        text not null,
  custo       int  not null,
  nivel_min   int  not null,
  maximo      int  not null,             -- quantos cada jogador pode ter
  produto     text not null references public.fazenda_culturas(id),
  tempo_seg   int  not null,             -- tempo para produzir depois de alimentado
  racao       text not null references public.fazenda_culturas(id),
  racao_qtd   int  not null,
  ordem       int  not null default 0
);

create table if not exists public.fazenda_animais (
  id             bigint generated always as identity primary key,
  jogador_id     uuid not null references public.fazenda_jogadores(id) on delete cascade,
  tipo           text not null references public.fazenda_animais_tipos(id),
  alimentado_em  timestamptz,            -- null = com fome
  criado_em      timestamptz not null default now()
);
create index if not exists fazenda_animais_jogador_idx on public.fazenda_animais (jogador_id);

-- Fase 3: modo construir — itens que o jogador coloca em qualquer quadrado
-- livre do terreno (mapa fixo de 22 x 13; ver fazenda_livre)
create table if not exists public.fazenda_itens (
  id         text primary key,
  nome       text not null,
  categoria  text not null check (categoria in ('caminho', 'natureza', 'objeto')),
  custo      int  not null,
  nivel_min  int  not null,
  ordem      int  not null default 0
);

create table if not exists public.fazenda_construcoes (
  jogador_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  x           smallint not null,
  y           smallint not null,
  tipo        text not null references public.fazenda_itens(id),
  primary key (jogador_id, x, y)
);

-- Fase 4: construções grandes (casas 3x3). (x, y) é o canto de cima à esquerda.
alter table public.fazenda_itens add column if not exists largura smallint not null default 1;
alter table public.fazenda_itens add column if not exists altura smallint not null default 1;
alter table public.fazenda_itens drop constraint if exists fazenda_itens_categoria_check;
alter table public.fazenda_itens add constraint fazenda_itens_categoria_check
  check (categoria in ('caminho', 'natureza', 'objeto', 'construcao'));

-- Fase 4: números de cada jogador (para conquistas e perfil)
create table if not exists public.fazenda_estatisticas (
  jogador_id  uuid primary key references public.fazenda_jogadores(id) on delete cascade,
  colher      int not null default 0,
  plantar     int not null default 0,
  cuidar      int not null default 0,
  vender      int not null default 0,
  animal      int not null default 0,
  ajudar      int not null default 0,
  pegar       int not null default 0
);

-- Fase 4: conquistas (medida = coluna das estatísticas, 'nivel' ou 'construcoes')
create table if not exists public.fazenda_conquistas_tipos (
  id          text primary key,
  nome        text not null,
  descricao   text not null,
  medida      text not null,
  meta        int  not null,
  recompensa  int  not null,
  ordem       int  not null default 0
);

create table if not exists public.fazenda_conquistas (
  jogador_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  conquista   text not null references public.fazenda_conquistas_tipos(id),
  obtida_em   timestamptz not null default now(),
  primary key (jogador_id, conquista)
);

-- Fase 3: missões diárias (3 por dia, geradas na primeira carga do dia)
create table if not exists public.fazenda_missoes (
  jogador_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  dia         date not null,
  slot        smallint not null,
  tipo        text not null check (tipo in ('colher', 'plantar', 'cuidar', 'vender', 'animal', 'ajudar')),
  alvo        int  not null,
  progresso   int  not null default 0,
  moedas      int  not null,
  xp          int  not null,
  resgatada   boolean not null default false,
  primary key (jogador_id, dia, slot)
);

-- RLS ligado e nenhuma policy = acesso direto negado para anon/authenticated
alter table public.fazenda_culturas       enable row level security;
alter table public.fazenda_jogadores      enable row level security;
alter table public.fazenda_sessoes        enable row level security;
alter table public.fazenda_canteiros      enable row level security;
alter table public.fazenda_celeiro        enable row level security;
alter table public.fazenda_visitas        enable row level security;
alter table public.fazenda_animais_tipos  enable row level security;
alter table public.fazenda_animais        enable row level security;
alter table public.fazenda_itens          enable row level security;
alter table public.fazenda_construcoes    enable row level security;
alter table public.fazenda_missoes        enable row level security;
alter table public.fazenda_estatisticas   enable row level security;
alter table public.fazenda_conquistas_tipos enable row level security;
alter table public.fazenda_conquistas     enable row level security;

revoke all on public.fazenda_culturas, public.fazenda_jogadores, public.fazenda_sessoes,
              public.fazenda_canteiros, public.fazenda_celeiro, public.fazenda_visitas,
              public.fazenda_animais_tipos, public.fazenda_animais,
              public.fazenda_itens, public.fazenda_construcoes, public.fazenda_missoes,
              public.fazenda_estatisticas, public.fazenda_conquistas_tipos, public.fazenda_conquistas
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

-- Produtos dos animais (tempo_seg/custo não se aplicam: ficam no tipo de animal)
insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('ovo',   'Ovo',   '🥚', 1, 0, 26, 1,  6, 2, 20, 'produto'),
  ('leite', 'Leite', '🥛', 1, 0, 70, 1, 16, 4, 21, 'produto'),
  ('la',    'Lã',    '🧶', 1, 0, 150, 1, 32, 6, 22, 'produto')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, venda = excluded.venda,
  xp = excluded.xp, nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;

insert into public.fazenda_animais_tipos (id, nome, custo, nivel_min, maximo, produto, tempo_seg, racao, racao_qtd, ordem) values
  ('galinha', 'Galinha', 100, 2, 4, 'ovo',    3600, 'alface', 1, 1),
  ('vaca',    'Vaca',    350, 4, 2, 'leite', 14400, 'batata', 2, 2),
  ('ovelha',  'Ovelha',  600, 6, 2, 'la',    28800, 'abobora', 2, 3)
on conflict (id) do update set
  nome = excluded.nome, custo = excluded.custo, nivel_min = excluded.nivel_min, maximo = excluded.maximo,
  produto = excluded.produto, tempo_seg = excluded.tempo_seg, racao = excluded.racao,
  racao_qtd = excluded.racao_qtd, ordem = excluded.ordem;

-- Itens do modo construir (a arte de cada um fica no cliente, em fazenda-arte.js)
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem) values
  ('cerca',         'Cerca de madeira',    'caminho',    8, 1,  1),
  ('caminho_terra', 'Caminho de terra',    'caminho',    4, 1,  2),
  ('caminho_pedra', 'Caminho de pedras',   'caminho',    6, 1,  3),
  ('flores',        'Flores',              'natureza',  15, 1, 10),
  ('girassol',      'Girassol',            'natureza',  40, 1, 11),
  ('arbusto',       'Arbusto',             'natureza',  30, 1, 12),
  ('cogumelos',     'Cogumelos',           'natureza',  25, 1, 13),
  ('arvore',        'Árvore',              'natureza',  60, 2, 14),
  ('arvore_outono', 'Árvore de outono',    'natureza',  70, 2, 15),
  ('pinheiro',      'Pinheiro',            'natureza',  80, 3, 16),
  ('amoreira',      'Amoreira',            'natureza',  90, 3, 17),
  ('pedras',        'Pedras',              'objeto',    20, 1, 20),
  ('tora',          'Tora de madeira',     'objeto',    25, 1, 21),
  ('placa',         'Placa',               'objeto',    20, 1, 22),
  ('balde',         'Balde d''água',       'objeto',    30, 1, 23),
  ('barril',        'Barril',              'objeto',    50, 2, 24),
  ('feno',          'Fardo de feno',       'objeto',    60, 2, 25),
  ('alvo',          'Alvo',                'objeto',    80, 3, 26),
  ('caixote',       'Caixote de tomate',   'objeto',   100, 4, 27),
  ('colmeia',       'Colmeia',             'objeto',   120, 4, 28),
  ('bau',           'Baú',                 'objeto',   150, 5, 29),
  ('boneco_neve',   'Boneco de neve',      'objeto',   150, 5, 30)
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem;

-- Construções grandes (3 x 3) — fase 4
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, largura, altura) values
  ('casa_vermelha', 'Casinha vermelha', 'construcao',  600,  8, 40, 3, 3),
  ('casa_azul',     'Casinha azul',     'construcao',  900, 10, 41, 3, 3)
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem,
  largura = excluded.largura, altura = excluded.altura;

insert into public.fazenda_conquistas_tipos (id, nome, descricao, medida, meta, recompensa, ordem) values
  ('primeira_colheita', 'Primeira colheita',   'Colha pela primeira vez',         'colher',        1,   20,  1),
  ('colhedor',          'Colhedor',            'Colha 100 itens',                 'colher',      100,  100,  2),
  ('mestre_colheita',   'Mestre da colheita',  'Colha 1.000 itens',               'colher',     1000,  500,  3),
  ('plantador',         'Plantador',           'Plante 50 sementes',              'plantar',      50,   60,  4),
  ('cuidadoso',         'Cuidadoso',           'Resolva 50 problemas na fazenda', 'cuidar',       50,   80,  5),
  ('comerciante',       'Comerciante',         'Ganhe 1.000 moedas vendendo',     'vender',     1000,  100,  6),
  ('magnata',           'Magnata',             'Ganhe 10.000 moedas vendendo',    'vender',    10000,  500,  7),
  ('rancheiro',         'Rancheiro',           'Colete 25 produtos dos animais',  'animal',       25,  120,  8),
  ('bom_vizinho',       'Bom vizinho',         'Ajude vizinhos com 20 problemas', 'ajudar',       20,  150,  9),
  ('guaxinim',          'Guaxinim',            'Pegue 20 itens de vizinhos',      'pegar',        20,   80, 10),
  ('construtor',        'Construtor',          'Tenha 25 construções',            'construcoes',  25,  100, 11),
  ('arquiteto',         'Arquiteto',           'Tenha 75 construções',            'construcoes',  75,  300, 12),
  ('nivel_5',           'Fazendeiro nível 5',  'Chegue ao nível 5',               'nivel',         5,  100, 13),
  ('nivel_10',          'Fazendeiro nível 10', 'Chegue ao nível 10',              'nivel',        10,  400, 14)
on conflict (id) do update set
  nome = excluded.nome, descricao = excluded.descricao, medida = excluded.medida,
  meta = excluded.meta, recompensa = excluded.recompensa, ordem = excluded.ordem;

-- Quem rodou a primeira versão da fase 3 tinha "enfeites" em 8 lugares fixos:
-- eles viram construções numa fileira livre do mapa e as tabelas antigas saem.
do $$
begin
  if to_regclass('public.fazenda_enfeites') is not null then
    insert into public.fazenda_construcoes (jogador_id, x, y, tipo)
    select e.jogador_id, 9 + e.slot, 9, e.tipo
      from public.fazenda_enfeites e
     where exists (select 1 from public.fazenda_itens i where i.id = e.tipo)
    on conflict do nothing;
    drop table public.fazenda_enfeites;
  end if;
  drop table if exists public.fazenda_enfeites_tipos;
  drop function if exists public.fazenda_remover_enfeite(text, int);
end $$;

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
  perform fazenda_checar_conquistas(p_jogador);
  select * into j from fazenda_jogadores where id = p_jogador;
  v_nivel := fazenda_nivel(j.xp);
  v_max := fazenda_max_canteiros(v_nivel);

  -- Libera canteiros novos conforme o nível
  insert into fazenda_canteiros (jogador_id, posicao)
  select p_jogador, g from generate_series(0, v_max - 1) g
  on conflict do nothing;

  perform fazenda_gerar_missoes(p_jogador);

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
               'xp', xp, 'nivel_min', nivel_min, 'tipo', tipo)
             order by ordem)
        from fazenda_culturas),
    'animais', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'alimentado_em', alimentado_em) order by id)
        from fazenda_animais where jogador_id = p_jogador), '[]'::jsonb),
    'animais_tipos', (
      select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_animais_tipos t),
    'construcoes', coalesce((
      select jsonb_agg(jsonb_build_object('x', x, 'y', y, 'tipo', tipo))
        from fazenda_construcoes where jogador_id = p_jogador), '[]'::jsonb),
    'itens', (
      select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_itens t),
    'estatisticas', (select to_jsonb(e) - 'jogador_id' from fazenda_estatisticas e where e.jogador_id = p_jogador),
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
        from fazenda_missoes where jogador_id = p_jogador and dia = fazenda_hoje()), '[]'::jsonb)
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
    if not found or k.tipo <> 'cultura' then
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
    perform fazenda_missao(p_jogador, 'plantar', 1);

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
    perform fazenda_missao(p_jogador, 'cuidar', 1);

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
    perform fazenda_missao(p_jogador, 'colher', v_qtd);

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
  if v_ganho > 0 then
    perform fazenda_missao(v_id, 'vender', v_ganho);
  end if;

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
        from fazenda_canteiros c where c.jogador_id = p_dono), '[]'::jsonb),
    'animais', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'alimentado_em', alimentado_em) order by id)
        from fazenda_animais where jogador_id = p_dono), '[]'::jsonb),
    'construcoes', coalesce((
      select jsonb_agg(jsonb_build_object('x', x, 'y', y, 'tipo', tipo))
        from fazenda_construcoes where jogador_id = p_dono), '[]'::jsonb),
    'perfil', jsonb_build_object(
      'criado_em', j.criado_em,
      'estatisticas', (select to_jsonb(e) - 'jogador_id' from fazenda_estatisticas e where e.jogador_id = p_dono),
      'conquistas', coalesce((select jsonb_agg(conquista order by obtida_em)
                                from fazenda_conquistas where jogador_id = p_dono), '[]'::jsonb))
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
  perform fazenda_missao(p_ator, 'pegar', v_qtd);

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
  perform fazenda_missao(p_ator, 'ajudar', v_n);

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

-- ============================================================
-- FASE 3 — ANIMAIS, ENFEITES E MISSÕES DIÁRIAS
-- ============================================================

-- "Hoje" no horário de Brasília (as missões viram à meia-noite daqui)
create or replace function public.fazenda_hoje()
returns date language sql stable as $$
  select (now() at time zone 'America/Sao_Paulo')::date;
$$;

-- Sorteia as 3 missões do dia, se ainda não existirem
create or replace function public.fazenda_gerar_missoes(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_hoje  date := fazenda_hoje();
  v_nivel int;
  v_tipos text[] := array['colher', 'plantar', 'cuidar', 'vender'];
  v_tipo  text;
  v_alvo  int;
  v_moeda int;
begin
  if exists (select 1 from fazenda_missoes where jogador_id = p_jogador and dia = v_hoje) then
    return;
  end if;
  select fazenda_nivel(xp) into v_nivel from fazenda_jogadores where id = p_jogador;
  if exists (select 1 from fazenda_animais where jogador_id = p_jogador) then
    v_tipos := v_tipos || 'animal'::text;
  end if;
  if v_nivel >= 2 then
    v_tipos := v_tipos || 'ajudar'::text;
  end if;
  select array_agg(t order by random()) into v_tipos from unnest(v_tipos) t;

  for i in 1..3 loop
    v_tipo := v_tipos[i];
    v_alvo := case v_tipo
      when 'colher'  then 8 + v_nivel * 2 + floor(random() * 6)::int
      when 'plantar' then 4 + v_nivel + floor(random() * 3)::int
      when 'cuidar'  then 3 + floor(random() * 3)::int
      when 'vender'  then ((60 + v_nivel * 30 + floor(random() * 60)::int) / 10) * 10
      else 2 + floor(random() * 3)::int
    end;
    v_moeda := case v_tipo
      when 'colher'  then v_alvo * 3
      when 'plantar' then v_alvo * 5
      when 'vender'  then v_alvo / 3
      when 'animal'  then v_alvo * 15
      else v_alvo * 8
    end + 10 * v_nivel;
    insert into fazenda_missoes (jogador_id, dia, slot, tipo, alvo, moedas, xp)
    values (p_jogador, v_hoje, i - 1, v_tipo, v_alvo, v_moeda, 5 + v_nivel * 3)
    on conflict do nothing;
  end loop;
end;
$$;

-- Soma progresso nas missões de hoje daquele tipo
-- e soma nas estatísticas do jogador (para conquistas e perfil)
drop function if exists public.fazenda_missao(uuid, text, int);
create or replace function public.fazenda_missao(p_jogador uuid, p_tipo text, p_qtd int)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  update fazenda_missoes
     set progresso = least(alvo, progresso + p_qtd)
   where jogador_id = p_jogador and dia = fazenda_hoje() and tipo = p_tipo and not resgatada;
  if p_tipo in ('colher', 'plantar', 'cuidar', 'vender', 'animal', 'ajudar', 'pegar') then
    insert into fazenda_estatisticas (jogador_id) values (p_jogador) on conflict do nothing;
    execute format('update fazenda_estatisticas set %I = %I + $1 where jogador_id = $2', p_tipo, p_tipo)
      using p_qtd, p_jogador;
  end if;
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
  v_valor  int;
begin
  insert into fazenda_estatisticas (jogador_id) values (p_jogador) on conflict do nothing;
  select * into s from fazenda_estatisticas where jogador_id = p_jogador;
  select fazenda_nivel(xp) into v_nivel from fazenda_jogadores where id = p_jogador;
  select count(*) into v_constr from fazenda_construcoes where jogador_id = p_jogador;
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
      else 0
    end;
    if v_valor >= r.meta then
      insert into fazenda_conquistas (jogador_id, conquista) values (p_jogador, r.id) on conflict do nothing;
      update fazenda_jogadores set moedas = moedas + r.recompensa where id = p_jogador;
    end if;
  end loop;
end;
$$;

-- Alimenta ou coleta um animal. Retorna quantos produtos coletou.
create or replace function public.fazenda_animal_um(p_jogador uuid, p_animal bigint, p_acao text)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  r      record;
  v_tem  int;
begin
  select a.id, a.alimentado_em, t.produto, t.tempo_seg, t.racao, t.racao_qtd, k.xp as produto_xp
    into r
    from fazenda_animais a
    join fazenda_animais_tipos t on t.id = a.tipo
    join fazenda_culturas k on k.id = t.produto
   where a.id = p_animal and a.jogador_id = p_jogador
     for update of a;
  if not found then
    raise exception 'animal_invalido';
  end if;

  if p_acao = 'alimentar' then
    if r.alimentado_em is not null then
      raise exception 'ja_alimentado';
    end if;
    select quantidade into v_tem from fazenda_celeiro
     where jogador_id = p_jogador and item = r.racao
       for update;
    if coalesce(v_tem, 0) < r.racao_qtd then
      raise exception 'sem_racao';
    end if;
    update fazenda_celeiro set quantidade = quantidade - r.racao_qtd
     where jogador_id = p_jogador and item = r.racao;
    update fazenda_animais set alimentado_em = now() where id = p_animal;
    return 0;

  elsif p_acao = 'coletar' then
    if r.alimentado_em is null or now() < r.alimentado_em + make_interval(secs => r.tempo_seg) then
      raise exception 'nao_pronto';
    end if;
    insert into fazenda_celeiro (jogador_id, item, quantidade)
    values (p_jogador, r.produto, 1)
    on conflict (jogador_id, item)
    do update set quantidade = fazenda_celeiro.quantidade + 1;
    update fazenda_jogadores set xp = xp + r.produto_xp where id = p_jogador;
    update fazenda_animais set alimentado_em = null where id = p_animal;
    perform fazenda_missao(p_jogador, 'animal', 1);
    return 1;
  end if;

  raise exception 'acao_invalida';
end;
$$;

-- p_categoria: animal (as construções têm funções próprias, logo abaixo)
create or replace function public.fazenda_comprar(p_token text, p_categoria text, p_tipo text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  j       record;
  a       record;
begin
  select * into j from fazenda_jogadores where id = v_id for update;

  if p_categoria = 'animal' then
    select * into a from fazenda_animais_tipos where id = p_tipo;
    if not found then raise exception 'item_invalido'; end if;
    if fazenda_nivel(j.xp) < a.nivel_min then raise exception 'nivel_insuficiente'; end if;
    if (select count(*) from fazenda_animais where jogador_id = v_id and tipo = a.id) >= a.maximo then
      raise exception 'limite_animais';
    end if;
    if j.moedas < a.custo then raise exception 'moedas_insuficientes'; end if;
    update fazenda_jogadores set moedas = moedas - a.custo where id = v_id;
    insert into fazenda_animais (jogador_id, tipo) values (v_id, a.id);

  else
    raise exception 'item_invalido';
  end if;

  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- p_acao: alimentar | coletar. Lote igual ao fazenda_acao.
create or replace function public.fazenda_animal(p_token text, p_acao text, p_ids bigint[])
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id     uuid := fazenda_auth(p_token);
  v_animal bigint;
  v_feitos int := 0;
  v_qtd    int := 0;
begin
  if p_ids is null or array_length(p_ids, 1) is null or array_length(p_ids, 1) > 20 then
    raise exception 'nada_a_fazer';
  end if;
  foreach v_animal in array p_ids loop
    if array_length(p_ids, 1) = 1 then
      v_qtd := v_qtd + fazenda_animal_um(v_id, v_animal, p_acao);
      v_feitos := v_feitos + 1;
    else
      begin
        v_qtd := v_qtd + fazenda_animal_um(v_id, v_animal, p_acao);
        v_feitos := v_feitos + 1;
      exception when others then
        null;
      end;
    end if;
  end loop;
  return jsonb_build_object('feitos', v_feitos, 'coletado', v_qtd, 'estado', fazenda_estado(v_id));
end;
$$;

/* ---------- Modo construir ----------
   O terreno é um mapa fixo de 22 x 13 quadrados. Áreas reservadas
   (precisam bater com MAPA em assets/fazenda/fazenda-arte.js):
     celeiro x1..3 y1..6 · casa x5..7 y1..3 · galinheiro x0..6 y7..8
     campo x9..14 y3..6 · pasto x16..21 y0..6 */
create or replace function public.fazenda_livre(p_x int, p_y int)
returns boolean language sql immutable as $$
  select p_x between 0 and 21 and p_y between 0 and 12
     and not (p_x between 1 and 3  and p_y between 1 and 6)
     and not (p_x between 5 and 7  and p_y between 1 and 3)
     and not (p_x between 0 and 6  and p_y between 7 and 8)
     and not (p_x between 9 and 14 and p_y between 3 and 6)
     and not (p_x between 16 and 21 and p_y between 0 and 6);
$$;

-- Compra um item e coloca no quadrado (x, y)
create or replace function public.fazenda_construir(p_token text, p_tipo text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  j    record;
  i    record;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  select * into i from fazenda_itens where id = p_tipo;
  if not found then raise exception 'item_invalido'; end if;
  if fazenda_nivel(j.xp) < i.nivel_min then raise exception 'nivel_insuficiente'; end if;
  -- todos os quadrados da área precisam estar livres
  if exists (select 1 from generate_series(p_x, p_x + i.largura - 1) gx, generate_series(p_y, p_y + i.altura - 1) gy
              where not fazenda_livre(gx, gy)) then
    raise exception 'lugar_reservado';
  end if;
  if exists (select 1 from fazenda_construcoes c join fazenda_itens k on k.id = c.tipo
              where c.jogador_id = v_id
                and c.x < p_x + i.largura and p_x < c.x + k.largura
                and c.y < p_y + i.altura  and p_y < c.y + k.altura) then
    raise exception 'lugar_ocupado';
  end if;
  if (select count(*) from fazenda_construcoes where jogador_id = v_id) >= 200 then
    raise exception 'limite_construcoes';
  end if;
  if j.moedas < i.custo then raise exception 'moedas_insuficientes'; end if;
  update fazenda_jogadores set moedas = moedas - i.custo where id = v_id;
  insert into fazenda_construcoes (jogador_id, x, y, tipo) values (v_id, p_x, p_y, i.id);
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- Leva uma construção de (x, y) para (nx, ny)
create or replace function public.fazenda_mover(p_token text, p_x int, p_y int, p_nx int, p_ny int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  i    record;
begin
  select k.* into i from fazenda_construcoes c join fazenda_itens k on k.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y;
  if not found then raise exception 'item_invalido'; end if;
  if exists (select 1 from generate_series(p_nx, p_nx + i.largura - 1) gx, generate_series(p_ny, p_ny + i.altura - 1) gy
              where not fazenda_livre(gx, gy)) then
    raise exception 'lugar_reservado';
  end if;
  if exists (select 1 from fazenda_construcoes c join fazenda_itens k on k.id = c.tipo
              where c.jogador_id = v_id and not (c.x = p_x and c.y = p_y)
                and c.x < p_nx + i.largura and p_nx < c.x + k.largura
                and c.y < p_ny + i.altura  and p_ny < c.y + k.altura) then
    raise exception 'lugar_ocupado';
  end if;
  update fazenda_construcoes set x = p_nx, y = p_ny
   where jogador_id = v_id and x = p_x and y = p_y;
  if not found then raise exception 'item_invalido'; end if;
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- Tira uma construção e devolve metade do preço
create or replace function public.fazenda_demolir(p_token text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_tipo text;
begin
  delete from fazenda_construcoes where jogador_id = v_id and x = p_x and y = p_y
  returning tipo into v_tipo;
  if v_tipo is null then raise exception 'item_invalido'; end if;
  update fazenda_jogadores
     set moedas = moedas + (select custo / 2 from fazenda_itens where id = v_tipo)
   where id = v_id;
  return jsonb_build_object('devolvido', (select custo / 2 from fazenda_itens where id = v_tipo),
                            'estado', fazenda_estado(v_id));
end;
$$;

create or replace function public.fazenda_resgatar_missao(p_token text, p_slot int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  m    record;
begin
  select * into m from fazenda_missoes
   where jogador_id = v_id and dia = fazenda_hoje() and slot = p_slot
     for update;
  if not found then raise exception 'missao_invalida'; end if;
  if m.resgatada then raise exception 'ja_resgatada'; end if;
  if m.progresso < m.alvo then raise exception 'missao_incompleta'; end if;
  update fazenda_missoes set resgatada = true
   where jogador_id = v_id and dia = m.dia and slot = m.slot;
  update fazenda_jogadores set moedas = moedas + m.moedas, xp = xp + m.xp where id = v_id;
  return jsonb_build_object('moedas', m.moedas, 'xp', m.xp, 'estado', fazenda_estado(v_id));
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
  public.fazenda_acao_vizinho(text, uuid, text, int[]),
  public.fazenda_hoje(),
  public.fazenda_gerar_missoes(uuid),
  public.fazenda_missao(uuid, text, int),
  public.fazenda_animal_um(uuid, bigint, text),
  public.fazenda_comprar(text, text, text),
  public.fazenda_animal(text, text, bigint[]),
  public.fazenda_resgatar_missao(text, int),
  public.fazenda_livre(int, int),
  public.fazenda_construir(text, text, int, int),
  public.fazenda_mover(text, int, int, int, int),
  public.fazenda_demolir(text, int, int),
  public.fazenda_checar_conquistas(uuid)
from public, anon, authenticated;

grant execute on function
  public.fazenda_criar(text),
  public.fazenda_recuperar(text),
  public.fazenda_carregar(text),
  public.fazenda_acao(text, text, int[], text),
  public.fazenda_vender(text, text, int),
  public.fazenda_ranking(text),
  public.fazenda_visitar(text, uuid),
  public.fazenda_acao_vizinho(text, uuid, text, int[]),
  public.fazenda_comprar(text, text, text),
  public.fazenda_animal(text, text, bigint[]),
  public.fazenda_resgatar_missao(text, int),
  public.fazenda_construir(text, text, int, int),
  public.fazenda_mover(text, int, int, int, int),
  public.fazenda_demolir(text, int, int)
to anon, authenticated;
