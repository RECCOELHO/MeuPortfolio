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
  posicao      smallint not null check (posicao between 0 and 99),
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

-- Terrenos, versão 1 (fileiras de canteiros compradas): trocados na fase 5 pela
-- plantação livre + terrenos que aumentam o mapa. A coluna fica só para a devolução abaixo.
alter table public.fazenda_jogadores add column if not exists terrenos int not null default 0;

-- Fase 5: cada canteiro tem seu lugar no mapa (x, y) e pode ser colocado,
-- movido e guardado no modo construir. posicao continua sendo o "nome" dele.
alter table public.fazenda_canteiros drop constraint if exists fazenda_canteiros_posicao_check;
alter table public.fazenda_canteiros add constraint fazenda_canteiros_posicao_check check (posicao between 0 and 99);
alter table public.fazenda_canteiros add column if not exists x smallint;
alter table public.fazenda_canteiros add column if not exists y smallint;
-- os canteiros que já existiam ficam onde estavam (campo de 6 colunas a partir de (9, 4))
update public.fazenda_canteiros set x = 9 + posicao % 6, y = 4 + posicao / 6 where x is null or y is null;
alter table public.fazenda_canteiros alter column x set not null;
alter table public.fazenda_canteiros alter column y set not null;
create unique index if not exists fazenda_canteiros_lugar_idx on public.fazenda_canteiros (jogador_id, x, y);

-- Fase 5: terrenos comprados (áreas de mata em volta; ver fazenda_zonas)
alter table public.fazenda_jogadores add column if not exists zonas int not null default 0;

-- Último nível que já ganhou o presente de moedas. Quem já jogava começa "em dia"
-- (sem presente retroativo); fazenda nova começa no 1.
alter table public.fazenda_jogadores add column if not exists nivel_premiado int;
update public.fazenda_jogadores set nivel_premiado = floor(sqrt(greatest(xp, 0) / 25.0))::int + 1 where nivel_premiado is null;
alter table public.fazenda_jogadores alter column nivel_premiado set default 1;
alter table public.fazenda_jogadores drop constraint if exists fazenda_jogadores_zonas_check;
alter table public.fazenda_jogadores add constraint fazenda_jogadores_zonas_check check (zonas between 0 and 3);
-- quem comprou fileiras na versão 1 recebe as moedas de volta (e fica com os canteiros)
update public.fazenda_jogadores
   set moedas = moedas + case terrenos when 1 then 400 when 2 then 1600 else 4600 end, terrenos = 0
 where terrenos > 0;

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
-- Fase 10: sementes da estação (só dá para plantar nela); null = o ano todo
alter table public.fazenda_culturas add column if not exists estacao text;

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
  check (categoria in ('caminho', 'natureza', 'objeto', 'construcao', 'maquina', 'oficina', 'energia'));
-- Fase 5: máquinas. efeito = o que fazem; raio = alcance em quadrados (0 = fazenda toda);
-- limite = quantas cada jogador pode ter (null = à vontade)
alter table public.fazenda_itens add column if not exists efeito text;
alter table public.fazenda_itens add column if not exists raio smallint not null default 0;
alter table public.fazenda_itens add column if not exists limite smallint;
alter table public.fazenda_itens add column if not exists descricao text;
-- Fase 6: todo item faz alguma coisa. beleza = pontos que viram bônus nas vendas;
-- produz/produz_seg/produz_qtd = itens que dão colheita sozinhos (amoreira)
alter table public.fazenda_itens add column if not exists beleza smallint not null default 0;
alter table public.fazenda_itens add column if not exists produz text references public.fazenda_culturas(id);
alter table public.fazenda_itens add column if not exists produz_seg int;
alter table public.fazenda_itens add column if not exists produz_qtd int;
alter table public.fazenda_construcoes add column if not exists colhido_em timestamptz;
-- Fase 9: oficinas. entradas = ingredientes de uma receita ({"trigo": 3, "ovo": 1});
-- a receita leva produz_seg e rende produz_qtd de produz. iniciado_em null = parada.
alter table public.fazenda_itens add column if not exists entradas jsonb;
alter table public.fazenda_construcoes add column if not exists iniciado_em timestamptz;
-- Fase 17: oficinas com estoque. estoque = receitas guardadas na oficina (os ingredientes já
-- saíram do celeiro); prontos = produtos feitos esperando você pegar. Ela trabalha sozinha
-- enquanto tiver estoque; iniciado_em = começo da receita em andamento (null = parada).
alter table public.fazenda_construcoes add column if not exists estoque smallint not null default 0;
alter table public.fazenda_construcoes add column if not exists prontos smallint not null default 0;

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

-- Fase 8: ajudantes — pessoas contratadas que trabalham sozinhas (arar, plantar, cuidar,
-- colher e um para cada animal). Trabalham no ritmo do nível (tarefas por hora) e
-- guardam até 8 horas de trabalho enquanto o jogador está fora.
create table if not exists public.fazenda_ajudantes_tipos (
  id         text primary key,
  nome       text not null,       -- nome da pessoa
  papel      text not null,       -- o que ela é (Colhedor, Granjeira...)
  funcao     text not null check (funcao in ('arar', 'plantar', 'cuidar', 'colher', 'animal')),
  alvo       text references public.fazenda_animais_tipos(id),   -- animal que ela cuida
  custo      int  not null,       -- contratar; evoluir custa 2x e 4x isso
  nivel_min  int  not null,
  descricao  text not null,
  ordem      int  not null default 0
);
create table if not exists public.fazenda_ajudantes (
  jogador_id     uuid not null references public.fazenda_jogadores(id) on delete cascade,
  tipo           text not null references public.fazenda_ajudantes_tipos(id),
  nivel          smallint not null default 1 check (nivel between 1 and 3),
  credito        real not null default 0,                 -- tarefas que já pode fazer
  atualizado_em  timestamptz not null default now(),
  relatorio      int not null default 0,                  -- tarefas feitas desde a última olhada
  primary key (jogador_id, tipo)
);
-- Fase 18: canteiro adubado pelo Seu Zé (+1 item na colheita; sai na colheita ou ao arar)
alter table public.fazenda_canteiros add column if not exists adubado boolean not null default false;
-- última semente que o jogador plantou (a semeadora usa a mesma)
alter table public.fazenda_jogadores add column if not exists semente text references public.fazenda_culturas(id);

-- Fase 11: energia (⚡) guardada nas baterias e quando foi a última conta.
-- O gerador a biomassa usa construcoes.iniciado_em: null = desligado.
alter table public.fazenda_jogadores add column if not exists energia real not null default 0;
alter table public.fazenda_jogadores add column if not exists energia_em timestamptz;
alter table public.fazenda_estatisticas add column if not exists energia int not null default 0;

-- Fase 12: curva de XP. 1 = a antiga (25·(n-1)² em todos os níveis), 2 = a nova (mais
-- difícil do nível 10 em diante). Quem já jogava é convertido uma vez só (ver abaixo).
alter table public.fazenda_jogadores add column if not exists curva smallint not null default 1;
alter table public.fazenda_jogadores alter column curva set default 2;

-- Fase 13: anúncio premiado (quando foi o último) e quantos cada jogador já assistiu
alter table public.fazenda_jogadores add column if not exists anuncio_em timestamptz;
alter table public.fazenda_estatisticas add column if not exists anuncios int not null default 0;

-- Fase 14: convites. Cada jogador tem um código curto (vai no link ?convite=); quem cria
-- uma fazenda nova pelo link fica registrado aqui (premiado = quem chamou ganhou as moedas).
alter table public.fazenda_jogadores add column if not exists convite text;
create unique index if not exists fazenda_jogadores_convite_idx on public.fazenda_jogadores (convite);
create table if not exists public.fazenda_convites (
  convidado_id uuid primary key references public.fazenda_jogadores(id) on delete cascade,
  dono_id      uuid not null references public.fazenda_jogadores(id) on delete cascade,
  premiado     boolean not null default false,
  visto        boolean not null default false,
  criado_em    timestamptz not null default now()
);
create index if not exists fazenda_convites_dono_idx on public.fazenda_convites (dono_id, criado_em);
alter table public.fazenda_convites enable row level security;
revoke all on public.fazenda_convites from anon, authenticated;

-- Fase 16: o lago. lago_em = desde quando o pescador Bira está enchendo o cesto (1 peixe a
-- cada 30 min, até 16); começa quando o jogador compra o terreno 3 (Vale do sudeste).
alter table public.fazenda_jogadores add column if not exists lago_em timestamptz;
alter table public.fazenda_estatisticas add column if not exists peixes int not null default 0;
alter table public.fazenda_estatisticas add column if not exists lendarios int not null default 0;

-- Fase 21: visitas na porteira. A cada 3 horas chega alguém (fazenda_visitante): o feirante,
-- a doceira e o caminhoneiro querem comprar algo pagando mais que o celeiro; a mascate vende
-- adubo. Cada visita fica até o fim das 3 horas ou até você atender (entregar ou dispensar).
create table if not exists public.fazenda_visitas_npc (
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  slot       bigint not null,                 -- floor(epoch / 10800): o bloco de 3 horas
  resposta   text not null check (resposta in ('entregou', 'dispensou')),
  em         timestamptz not null default now(),
  primary key (jogador_id, slot)
);
alter table public.fazenda_visitas_npc enable row level security;
revoke all on public.fazenda_visitas_npc from anon, authenticated;
alter table public.fazenda_estatisticas add column if not exists pedidos int not null default 0;

-- Fase 7: ração reservada para os animais (fica no celeiro, o "vender" não leva)
create table if not exists public.fazenda_reservas (
  jogador_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  item        text not null references public.fazenda_culturas(id),
  quantidade  int  not null check (quantidade > 0),
  primary key (jogador_id, item)
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
alter table public.fazenda_reservas       enable row level security;
alter table public.fazenda_ajudantes_tipos enable row level security;
alter table public.fazenda_ajudantes      enable row level security;

revoke all on public.fazenda_culturas, public.fazenda_jogadores, public.fazenda_sessoes,
              public.fazenda_canteiros, public.fazenda_celeiro, public.fazenda_visitas,
              public.fazenda_animais_tipos, public.fazenda_animais,
              public.fazenda_itens, public.fazenda_construcoes, public.fazenda_missoes,
              public.fazenda_estatisticas, public.fazenda_conquistas_tipos, public.fazenda_conquistas,
              public.fazenda_reservas, public.fazenda_ajudantes_tipos, public.fazenda_ajudantes
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
  ('girassol', 'Girassol',  '🌻', 21600,  90, 20,  8, 24, 6, 6),
  ('abobora',  'Trigo',     '🌾', 28800, 110, 26,  8, 30, 7, 7),
  ('morango',  'Amora',     '🫐', 43200, 140, 22, 12, 40, 9, 8)
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, tempo_seg = excluded.tempo_seg,
  custo = excluded.custo, venda = excluded.venda, rendimento = excluded.rendimento,
  xp = excluded.xp, nivel_min = excluded.nivel_min, ordem = excluded.ordem;

-- Sementes da estação (fase 10): só dá para plantar na estação delas, e rendem bem
insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, estacao) values
  ('moranguinho', 'Morango',  '🍓', 10800, 40, 14, 8, 14, 3,  9, 'primavera'),
  ('melancia',    'Melancia', '🍉', 21600, 60, 40, 5, 22, 4, 10, 'verao'),
  ('jerimum',     'Abóbora',  '🎃', 28800, 70, 45, 6, 26, 5, 11, 'outono'),
  ('repolho',     'Repolho',  '🥬', 14400, 45, 18, 7, 16, 3, 12, 'inverno')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, tempo_seg = excluded.tempo_seg,
  custo = excluded.custo, venda = excluded.venda, rendimento = excluded.rendimento,
  xp = excluded.xp, nivel_min = excluded.nivel_min, ordem = excluded.ordem, estacao = excluded.estacao;

-- Produtos dos animais (tempo_seg/custo não se aplicam: ficam no tipo de animal)
insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('ovo',   'Ovo',   '🥚', 1, 0, 26, 1,  6, 2, 20, 'produto'),
  ('leite', 'Leite', '🥛', 1, 0, 70, 1, 16, 4, 21, 'produto'),
  ('la',    'Lã',    '🧶', 1, 0, 150, 1, 32, 6, 22, 'produto'),
  ('pelo',  'Pelo de coelho', '🐇', 1, 0, 45, 1, 10, 6, 23, 'produto'),
  ('pena',  'Pena',  '🪶', 1, 0, 60, 1, 14, 11, 24, 'produto'),
  ('trufa', 'Trufa', '🍄', 1, 0, 180, 1, 36, 14, 25, 'produto'),
  ('salada',  'Salada',          '🥗', 1, 0,  30, 1,  4,  3, 30, 'produto'),
  ('pipoca',  'Pipoca',          '🍿', 1, 0,  70, 1,  8,  4, 31, 'produto'),
  ('molho',   'Molho de tomate', '🥫', 1, 0, 110, 1, 12,  5, 32, 'produto'),
  ('queijo',  'Queijo',          '🧀', 1, 0, 240, 1, 25,  6, 33, 'produto'),
  ('pao',     'Pão',             '🍞', 1, 0, 180, 1, 20,  7, 34, 'produto'),
  ('bolo',    'Bolo de cenoura', '🍰', 1, 0, 170, 1, 18,  9, 35, 'produto'),
  ('tecido',  'Tecido',          '🧵', 1, 0, 500, 1, 45, 10, 36, 'produto'),
  ('geleia',  'Geleia de amora', '🫙', 1, 0, 120, 1, 14, 11, 37, 'produto'),
  -- peixes do lago: quanto mais raro, mais vale (chances em fazenda_peixes)
  ('lambari',     'Lambari',              '🐟', 1, 0,   15, 1,   2, 10, 40, 'produto'),
  ('tilapia',     'Tilápia',              '🐟', 1, 0,   30, 1,   3, 10, 41, 'produto'),
  ('piau',        'Piau',                 '🐟', 1, 0,   50, 1,   5, 10, 42, 'produto'),
  ('curimata',    'Curimatã',             '🐟', 1, 0,   80, 1,   7, 10, 43, 'produto'),
  ('tucunare',    'Tucunaré',             '🐟', 1, 0,  150, 1,  12, 10, 44, 'produto'),
  ('surubim',     'Surubim',              '🐟', 1, 0,  300, 1,  20, 10, 45, 'produto'),
  ('velho_chico', 'Peixe do Velho Chico', '🐠', 1, 0, 2500, 1, 100, 10, 46, 'produto')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, venda = excluded.venda,
  xp = excluded.xp, nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;

insert into public.fazenda_animais_tipos (id, nome, custo, nivel_min, maximo, produto, tempo_seg, racao, racao_qtd, ordem) values
  ('galinha', 'Galinha', 100, 2, 4, 'ovo',    3600, 'alface', 1, 1),
  ('vaca',    'Vaca',    350, 5, 2, 'leite', 14400, 'batata', 2, 2),
  ('ovelha',  'Ovelha',  600, 8, 2, 'la',    28800, 'abobora', 2, 3),
  ('coelho',  'Coelho',  250, 6, 4, 'pelo',   7200, 'cenoura', 2, 4),
  ('pato',    'Pato',    450, 11, 3, 'pena', 10800, 'alface', 2, 5),
  ('porco',   'Porco',   900, 14, 2, 'trufa', 21600, 'milho', 2, 6)
on conflict (id) do update set
  nome = excluded.nome, custo = excluded.custo, nivel_min = excluded.nivel_min, maximo = excluded.maximo,
  produto = excluded.produto, tempo_seg = excluded.tempo_seg, racao = excluded.racao,
  racao_qtd = excluded.racao_qtd, ordem = excluded.ordem;

-- Ajudantes (fase 8): um por função e um por animal. Caros de contratar e de evoluir.
insert into public.fazenda_ajudantes_tipos (id, nome, papel, funcao, alvo, custo, nivel_min, descricao, ordem) values
  ('granjeira',  'Dona Cida', 'Granjeira',          'animal',  'galinha', 1500,  5, 'Dá a ração e coleta os ovos das galinhas.', 1),
  ('lavrador',   'Seu Zé',    'Lavrador',           'arar',    null,      2000,  6, 'Ara os canteiros vazios, limpa os murchos e, com o tempo que sobra, aduba os que estão crescendo: +1 item na colheita de cada um.', 2),
  ('jardineiro', 'Tião',      'Jardineiro',         'cuidar',  null,      2500,  7, 'Tira erva daninha, praga e seca dos canteiros.', 3),
  ('coelheira',  'Nina',      'Cuidadora de coelhos','animal', 'coelho',  2000,  8, 'Dá a ração e coleta o pelo dos coelhos.', 4),
  ('vaqueiro',   'Bento',     'Vaqueiro',           'animal',  'vaca',    3000,  9, 'Dá a ração e tira o leite das vacas.', 5),
  ('colhedor',   'Juca',      'Colhedor',           'colher',  null,      4000, 10, 'Colhe tudo o que estiver maduro, antes de murchar.', 6),
  ('semeadora',  'Dona Rosa', 'Semeadora',          'plantar', null,      4000, 11, 'Planta a última semente que você usou nos canteiros arados (paga com suas moedas). Se ela estiver fora de época, planta a semente da estação.', 7),
  ('patinheiro', 'Pedrinho',  'Cuidador de patos',  'animal',  'pato',    3000, 12, 'Dá a ração e junta as penas dos patos.', 8),
  ('pastora',    'Lia',       'Pastora',            'animal',  'ovelha',  4000, 13, 'Dá a ração e tosquia a lã das ovelhas.', 9),
  ('porqueiro',  'Tonho',     'Porqueiro',          'animal',  'porco',   5000, 15, 'Dá a ração e acha as trufas dos porcos.', 10)
on conflict (id) do update set
  nome = excluded.nome, papel = excluded.papel, funcao = excluded.funcao, alvo = excluded.alvo,
  custo = excluded.custo, nivel_min = excluded.nivel_min, descricao = excluded.descricao, ordem = excluded.ordem;

-- Itens do modo construir (a arte de cada um fica no cliente, em fazenda-arte.js)
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem) values
  ('cerca',         'Cerca de madeira',    'caminho',    8, 1,  1),
  ('caminho_terra', 'Caminho de terra',    'caminho',    4, 1,  2),
  ('caminho_pedra', 'Caminho de pedras',   'caminho',    6, 2,  3),
  ('flores',        'Flores',              'natureza',  15, 1, 10),
  ('girassol',      'Pé de girassol',      'natureza',  40, 4, 11),
  ('arbusto',       'Arbusto',             'natureza',  30, 2, 12),
  ('cogumelos',     'Cogumelos',           'natureza',  25, 4, 13),
  ('arvore',        'Árvore',              'natureza',  60, 3, 14),
  ('arvore_outono', 'Árvore de outono',    'natureza',  70, 6, 15),
  ('pinheiro',      'Pinheiro',            'natureza',  80, 7, 16),
  ('amoreira',      'Amoreira',            'natureza',  90, 9, 17),
  ('pedras',        'Pedras',              'objeto',    20, 2, 20),
  ('tora',          'Tora de madeira',     'objeto',    25, 3, 21),
  ('placa',         'Placa',               'objeto',    20, 1, 22),
  ('balde',         'Balde d''água',       'objeto',    30, 3, 23),
  ('barril',        'Barril',              'objeto',    50, 5, 24),
  ('feno',          'Fardo de feno',       'objeto',    60, 5, 25),
  ('alvo',          'Alvo',                'objeto',    80, 6, 26),
  ('caixote',       'Caixote de tomate',   'objeto',   100, 7, 27),
  ('colmeia',       'Colmeia',             'objeto',   120, 8, 28),
  ('bau',           'Baú',                 'objeto',   150, 11, 29)
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem;

-- O boneco de neve saiu da loja (a arte não funcionava): quem tinha recebe o preço de volta
update public.fazenda_jogadores j
   set moedas = moedas + x.qtd * (select custo from public.fazenda_itens where id = 'boneco_neve')
  from (select jogador_id, count(*)::int as qtd from public.fazenda_construcoes
         where tipo = 'boneco_neve' group by jogador_id) x
 where j.id = x.jogador_id;
delete from public.fazenda_construcoes where tipo = 'boneco_neve';
delete from public.fazenda_itens where id = 'boneco_neve';

-- Construções grandes (3 x 3) — fase 4
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, largura, altura) values
  ('casa_vermelha', 'Casinha vermelha', 'construcao',  600, 10, 40, 3, 3),
  ('casa_azul',     'Casinha azul',     'construcao',  900, 13, 41, 3, 3)
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem,
  largura = excluded.largura, altura = excluded.altura;

-- Oficinas — fase 9: casinhas que fazem produtos com o que você planta e cria
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, largura, altura,
                                  produz, produz_seg, produz_qtd, entradas, limite, beleza, descricao) values
  -- fase 17: tempos 29% menores que os de antes (20 min → 14, 2 h → 1 h 25...)
  ('saladeira',   'Barraca de saladas', 'oficina',  300,  3, 60, 2, 3, 'salada',  840,  1, '{"alface": 2, "cenoura": 1}', 2, 5, '2 alfaces + 1 cenoura → salada.'),
  ('pipocaria',   'Pipocaria',          'oficina',  500,  4, 61, 2, 3, 'pipoca', 1260,  1, '{"milho": 3}', 2, 5, '3 milhos → pipoca.'),
  ('fabrica_molho','Fábrica de molho',  'oficina',  700,  5, 62, 2, 3, 'molho',  2580,  1, '{"tomate": 4}', 2, 5, '4 tomates → molho de tomate.'),
  ('queijaria',   'Queijaria',          'oficina', 1200,  6, 63, 2, 3, 'queijo', 7680,  1, '{"leite": 2}', 2, 5, '2 leites → queijo.'),
  ('padaria',     'Padaria',            'oficina', 1200,  7, 64, 2, 3, 'pao',    5100,  1, '{"abobora": 3, "ovo": 1}', 2, 5, '3 trigos + 1 ovo → pão.'),
  ('confeitaria', 'Confeitaria',        'oficina', 1500,  9, 65, 2, 3, 'bolo',   5100,  1, '{"cenoura": 3, "ovo": 2, "abobora": 1}', 2, 5, '3 cenouras + 2 ovos + 1 trigo → bolo de cenoura.'),
  ('tecelagem',   'Tecelagem',          'oficina', 2500, 10, 66, 2, 3, 'tecido', 10200, 1, '{"la": 2}', 2, 5, '2 lãs → tecido.'),
  ('casa_geleia', 'Casa de geleias',    'oficina', 1800, 11, 67, 2, 3, 'geleia', 5100,  1, '{"morango": 3}', 2, 5, '3 amoras → geleia de amora.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, largura = excluded.largura, altura = excluded.altura, produz = excluded.produz,
  produz_seg = excluded.produz_seg, produz_qtd = excluded.produz_qtd, entradas = excluded.entradas,
  limite = excluded.limite, beleza = excluded.beleza, descricao = excluded.descricao;

-- Fase 16: a estátua dourada em homenagem ao Chico, nosso beta tester
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, efeito, raio, limite, beleza, descricao) values
  ('estatua_chico', 'O Velho Chico, Pescador de Betinhas', 'construcao', 30000, 30, 45, 'chico', 0, 1, 50,
   'Estátua dourada em homenagem ao Chico, nosso beta tester. Dobra a chance do Peixe do Velho Chico no lago (1% → 2%) e dá +50 de beleza.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, efeito = excluded.efeito, raio = excluded.raio, limite = excluded.limite,
  beleza = excluded.beleza, descricao = excluded.descricao;

-- O lago ocupa x 24..29, y 14..18 (terreno 3). Quem já tinha algo ali recebe de volta: o preço
-- das construções e a semente dos canteiros plantados (os canteiros voltam para o limite).
update public.fazenda_jogadores j
   set moedas = moedas + x.total
  from (select c.jogador_id, sum(i.custo)::int as total
          from public.fazenda_construcoes c join public.fazenda_itens i on i.id = c.tipo
         where c.x < 30 and c.x + i.largura > 24 and c.y < 19 and c.y + i.altura > 14
         group by c.jogador_id) x
 where j.id = x.jogador_id;
delete from public.fazenda_construcoes c using public.fazenda_itens i
 where i.id = c.tipo and c.x < 30 and c.x + i.largura > 24 and c.y < 19 and c.y + i.altura > 14;
update public.fazenda_jogadores j
   set moedas = moedas + x.total
  from (select c.jogador_id, coalesce(sum(k.custo), 0)::int as total
          from public.fazenda_canteiros c left join public.fazenda_culturas k on k.id = c.cultura and c.estado = 'plantado'
         where c.x between 24 and 29 and c.y between 14 and 18
         group by c.jogador_id) x
 where j.id = x.jogador_id;
delete from public.fazenda_canteiros where x between 24 and 29 and y between 14 and 18;

-- Máquinas — fase 5 (arte: Tiny Factory, Kenney)
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, efeito, raio, limite, descricao) values
  ('irrigador',     'Irrigador',         'maquina',  150, 3, 50, 'seco',     2, null, 'Sem seca nos canteiros em volta (2 quadrados).'),
  ('pulverizador',  'Pulverizador',      'maquina',  300, 5, 51, 'praga',    2, null, 'Sem pragas nos canteiros em volta (2 quadrados).'),
  ('alarme',        'Alarme antiladrão', 'maquina',  400, 6, 52, 'alarme',   3, null, 'Vizinhos não pegam nada dos canteiros em volta (3 quadrados).'),
  ('robo_capina',   'Robô capinador',    'maquina',  500, 8, 53, 'erva',     2, null, 'Sem ervas daninhas nos canteiros em volta (2 quadrados).'),
  ('trator',        'Trator',            'maquina', 1200, 9, 54, 'arar',     0, 1,    'Depois da colheita o canteiro já fica arado (fazenda toda).'),
  ('colheitadeira', 'Colheitadeira',     'maquina', 2500, 12, 55, 'colheita', 0, 1,    '+1 item em cada colheita (fazenda toda).')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem, efeito = excluded.efeito,
  raio = excluded.raio, limite = excluded.limite, descricao = excluded.descricao;

-- Energia — fase 11, níveis 16 a 25 (no espírito do IndustrialCraft): geradores enchem as
-- baterias e as máquinas elétricas gastam. Os números ficam nas funções fazenda_capacidade,
-- fazenda_energia_taxa e nos gastos de cada máquina; as descrições aparecem no jogo.
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, efeito, raio, limite, descricao) values
  ('painel_solar',  'Painel solar',       'energia',  2500, 16, 80, 'solar',      0, 6, 'Gera até 12 ⚡/h de dia (sol forte: 14; nublado: 5; chuva: 3). À noite, nada.'),
  ('bateria',       'Banco de baterias',  'energia',  2000, 16, 81, 'bateria',    0, 4, 'Guarda mais 100 ⚡ (sem bateria, a caixa de luz guarda só 50).'),
  ('turbina',       'Turbina eólica',     'energia',  4000, 17, 82, 'eolica',     0, 4, 'Gera 8 ⚡/h de dia e de noite; 30 ⚡/h na ventania e 14 na chuva.'),
  ('estufa',        'Estufa elétrica',    'energia',  5000, 18, 83, 'estufa',     2, 3, 'Canteiros em volta (2) aceitam sementes de qualquer estação e crescem 25% mais rápido. Gasta 5 ⚡ por plantio.'),
  ('gerador_bio',   'Gerador a biomassa', 'energia',  6000, 19, 84, 'biomassa',   0, 2, 'Ligado, queima 1 milho a cada 30 min: 50 ⚡/h. Toque nele para ligar ou desligar.'),
  ('triturador',    'Triturador',         'energia',  8000, 20, 85, 'triturar',   0, 1, 'As oficinas rendem 2 produtos por receita. Gasta 10 ⚡ por receita.'),
  ('supercap',      'Supercapacitor',     'energia',  9000, 21, 86, 'bateria',    0, 2, 'Guarda mais 500 ⚡.'),
  ('fabrica_auto',  'Fábrica automática', 'energia', 12000, 22, 87, 'automatico', 0, 1, 'Liga as oficinas ao celeiro: quando o estoque acaba, elas buscam ingredientes sozinhas (sem mexer na ração reservada) e os produtos vão direto para o celeiro. Gasta 8 ⚡ por receita.'),
  ('robo_colheita', 'Robô colheitador',   'energia', 14000, 23, 88, 'robo',       3, 2, 'Colhe, ara e replanta sozinho os canteiros em volta (3). Gasta 3 ⚡ por colheita e 1 por plantio.'),
  ('aspersor',      'Aspersor elétrico',  'energia', 10000, 24, 89, 'aspersor',   3, 4, 'Nenhuma erva, praga ou seca nos canteiros em volta (3). Gasta 1 ⚡ por problema evitado.'),
  ('reator',        'Reator nuclear',     'energia', 30000, 25, 90, 'reator',     0, 1, 'Gera 120 ⚡/h sem parar, de dia e de noite (80 na onda de calor, para não esquentar).')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem, efeito = excluded.efeito,
  raio = excluded.raio, limite = excluded.limite, descricao = excluded.descricao;
-- as duas grandes ocupam 2 x 2
update public.fazenda_itens set largura = 2, altura = 2 where id in ('fabrica_auto', 'reator');

-- O jogador tem alguma máquina com esse efeito? (trator, colheitadeira)
create or replace function public.fazenda_tem_efeito(p_jogador uuid, p_efeito text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
                  where c.jogador_id = p_jogador and i.efeito = p_efeito);
$$;

-- O quadrado (x, y) está no alcance de uma máquina com esse efeito? (irrigador, alarme...)
create or replace function public.fazenda_protegido(p_jogador uuid, p_efeito text, p_x int, p_y int)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
                  where c.jogador_id = p_jogador and i.efeito = p_efeito
                    and abs(c.x - p_x) <= i.raio and abs(c.y - p_y) <= i.raio);
$$;

-- Fase 6: o que cada enfeite faz. Efeitos em volta (raio): seco/praga/erva (evitam o
-- problema), crescer (planta 10% mais rápida), adubo (+1 item), xp (+1 XP), sorte (15%
-- de colheita em dobro), cerca (vizinho pega no máximo 1). Na fazenda toda (raio 0):
-- feno (animais 20% mais rápidos), venda (+10% nas vendas), missao (+25% nas missões).
-- Beleza: a soma de tudo vira bônus nas vendas (+1% a cada 10 pontos, até +20%).
-- As descrições aparecem no jogo; os efeitos valem no servidor (funções abaixo).
update public.fazenda_itens i
   set efeito = v.efeito, raio = v.raio, beleza = v.beleza, descricao = v.descricao,
       produz = v.produz, produz_seg = v.produz_seg, produz_qtd = v.produz_qtd
  from (values
    ('cerca',         'cerca'::text,  1::smallint,  1::smallint, 'Vizinhos pegam no máximo 1 item dos canteiros encostados.'::text, null::text, null::int, null::int),
    ('caminho_terra', null,           0,  1, 'Deixa a fazenda mais bonita: +1 de beleza (beleza dá bônus nas vendas).', null, null, null),
    ('caminho_pedra', null,           0,  2, 'Deixa a fazenda mais bonita: +2 de beleza (beleza dá bônus nas vendas).', null, null, null),
    ('flores',        'xp',           1,  2, '+1 XP ao colher os canteiros encostados.', null, null, null),
    ('girassol',      'crescer',      1,  3, 'Plantas encostadas crescem 10% mais rápido.', null, null, null),
    ('arbusto',       'praga',        1,  2, 'Joaninhas: sem pragas nos canteiros encostados.', null, null, null),
    ('cogumelos',     'adubo',        1,  2, 'Adubo natural: +1 item na colheita dos canteiros encostados.', null, null, null),
    ('arvore',        'seco',         1,  4, 'Sombra: sem seca nos canteiros encostados.', null, null, null),
    ('arvore_outono', 'crescer',      1,  4, 'Folhas viram adubo: plantas encostadas crescem 10% mais rápido.', null, null, null),
    ('pinheiro',      'praga',        2,  4, 'Passarinhos: sem pragas em volta (2 quadrados).', null, null, null),
    ('amoreira',      null,           0,  3, 'Dá 2 amoras a cada 6 horas: toque nela para colher.', 'morango', 21600, 2),
    ('pedras',        'erva',         1,  1, 'Cobertura de pedras: sem erva daninha nos canteiros encostados.', null, null, null),
    ('tora',          'crescer',      1,  2, 'Minhocas: plantas encostadas crescem 10% mais rápido.', null, null, null),
    ('placa',         'cerca',        2,  1, '"Proibido pegar": vizinhos pegam no máximo 1 item em volta (2 quadrados).', null, null, null),
    ('balde',         'seco',         1,  1, 'Sem seca nos canteiros encostados.', null, null, null),
    ('barril',        'adubo',        1,  2, 'Barril de adubo: +1 item na colheita dos canteiros encostados.', null, null, null),
    ('feno',          'feno',         0,  2, 'Animais produzem 20% mais rápido (fazenda toda, não acumula).', null, null, null),
    ('alvo',          'sorte',        2,  2, 'Sorte: 15% de chance de colheita em dobro em volta (2 quadrados).', null, null, null),
    ('caixote',       'venda',        0,  2, '+10% no preço de venda (fazenda toda, não acumula).', null, null, null),
    ('colmeia',       'adubo',        2,  3, 'Abelhas: +1 item na colheita em volta (2 quadrados).', null, null, null),
    ('bau',           'missao',       0,  3, '+25% de moedas nas missões (fazenda toda, não acumula).', null, null, null),
    ('casa_vermelha', null,           0, 20, 'Casinha: +20 de beleza (beleza dá bônus nas vendas).', null, null, null),
    ('casa_azul',     null,           0, 30, 'Casinha: +30 de beleza (beleza dá bônus nas vendas).', null, null, null)
  ) v(id, efeito, raio, beleza, descricao, produz, produz_seg, produz_qtd)
 where i.id = v.id;

-- Beleza da fazenda (soma dos itens construídos)
create or replace function public.fazenda_beleza(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select coalesce(sum(i.beleza), 0)::int from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
   where c.jogador_id = p_jogador;
$$;

-- Bônus nas vendas, em %: beleza (+1% a cada 10, até 20) + caixote (+10)
create or replace function public.fazenda_bonus_venda(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select least(fazenda_beleza(p_jogador) / 10, 20) + 10 * fazenda_tem_efeito(p_jogador, 'venda')::int;
$$;

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
  ('nivel_10',          'Fazendeiro nível 10', 'Chegue ao nível 10',              'nivel',        10,  400, 14),
  ('eletricista',       'Eletricista',         'Gaste 500 ⚡ com máquinas elétricas', 'energia',   500,  800, 15),
  ('nivel_20',          'Fazendeiro nível 20', 'Chegue ao nível 20',              'nivel',        20, 1500, 16),
  ('nivel_25',          'Fazenda industrial',  'Chegue ao nível 25',              'nivel',        25, 5000, 17),
  ('popular',           'Fazendeiro popular',  'Traga 3 amigos pelo seu convite', 'convites',      3,  500, 18),
  ('pescador',          'Pescador',            'Tire 100 peixes do cesto do lago', 'peixes',      100,  300, 19),
  ('velho_chico',       'Lenda do Velho Chico', 'Pesque o Peixe do Velho Chico',   'lendarios',     1, 1000, 20),
  ('freguesia',         'Freguesia fiel',      'Atenda 10 visitas na porteira',    'pedidos',      10,  400, 21)
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

-- Tempo rápido (fase 15). A semana tem as 4 estações, 42 h cada, a partir de segunda 0h
-- (horário de Brasília): primavera → verão (ter 18h) → outono (qui 12h) → inverno (sáb 6h).
-- Cada dia (24 h) tem todos os climas, cada um pelo tempo da porcentagem da estação
-- (fazenda_clima_tabela), em 2 pedaços por clima embaralhados pela data. Tudo muda em
-- fatias de 36 min alinhadas à meia-noite. Igual a estacao() em fazenda-arte.js.
-- Testes: set fazenda.estacao_teste / fazenda.clima_teste forçam a estação / o clima.
drop function if exists public.fazenda_estacao(date);
drop function if exists public.fazenda_clima(date);

-- Minutos desde segunda 0h, no horário de Brasília
create or replace function public.fazenda_minuto_semana(p_t timestamptz)
returns int language sql stable as $$
  select (extract(isodow from l)::int - 1) * 1440 + extract(hour from l)::int * 60 + extract(minute from l)::int
    from (select p_t at time zone 'America/Sao_Paulo' as l) x;
$$;

create or replace function public.fazenda_estacao_em(p_t timestamptz)
returns text language sql stable as $$
  select coalesce(nullif(current_setting('fazenda.estacao_teste', true), ''),
                  (array['primavera', 'verao', 'outono', 'inverno'])[fazenda_minuto_semana(p_t) / 2520 + 1]);
$$;

-- Quando acaba a estação em que p_t está
create or replace function public.fazenda_estacao_fim(p_t timestamptz)
returns timestamptz language sql stable as $$
  select date_trunc('minute', p_t) + make_interval(mins => 2520 - fazenda_minuto_semana(p_t) % 2520);
$$;

-- Quanto do dia (em %) cada clima ocupa em cada estação
create or replace function public.fazenda_clima_tabela(p_estacao text)
returns table (clima text, pct int) language sql immutable as $$
  select t.c, t.p from (values
    ('verao', 'sol', 40), ('verao', 'chuva', 25), ('verao', 'calor', 20), ('verao', 'nublado', 10), ('verao', 'vento', 5),
    ('outono', 'sol', 40), ('outono', 'nublado', 25), ('outono', 'chuva', 20), ('outono', 'vento', 10), ('outono', 'calor', 5),
    ('inverno', 'sol', 45), ('inverno', 'nublado', 30), ('inverno', 'vento', 10), ('inverno', 'chuva', 10), ('inverno', 'calor', 5),
    ('primavera', 'sol', 35), ('primavera', 'chuva', 25), ('primavera', 'nublado', 20), ('primavera', 'vento', 15), ('primavera', 'calor', 5)
  ) t(e, c, p) where t.e = p_estacao;
$$;

-- Clima num momento: sol (+1 na colheita) | chuva (rega: sem seca) | calor (mais seca) |
-- nublado (nenhum problema novo) | vento (mais pragas). Igual para todo mundo.
create or replace function public.fazenda_clima_em(p_t timestamptz)
returns text language sql stable as $$
  select coalesce(nullif(current_setting('fazenda.clima_teste', true), ''), (
    select b.clima
      from (select t.clima, x.minuto,
                   sum(t.pct * 36 / 5) over (order by md5(x.dia || x.est || t.clima || pt.parte)) as fim   -- pct% de 24 h em 2 pedaços
              from (select l::date::text as dia, fazenda_estacao_em(p_t) as est,
                           extract(hour from l)::int * 60 + extract(minute from l)::int as minuto
                      from (select p_t at time zone 'America/Sao_Paulo' as l) z) x
             cross join lateral fazenda_clima_tabela(x.est) t
             cross join (values (1), (2)) pt(parte)) b
     where b.fim > b.minuto
     order by b.fim
     limit 1));
$$;

-- Previsão: o clima de agora, até quando vai e qual vem depois
create or replace function public.fazenda_clima_previsao(p_t timestamptz)
returns jsonb language plpgsql stable as $$
declare
  v_agora text := fazenda_clima_em(p_t);
  v_t     timestamptz := date_trunc('minute', p_t) + make_interval(mins => 36 - fazenda_minuto_semana(p_t) % 36);
  v_prox  text;
  k       int;
begin
  for k in 1..80 loop
    v_prox := fazenda_clima_em(v_t);
    if v_prox <> v_agora then
      return jsonb_build_object('agora', v_agora, 'ate', v_t, 'proximo', v_prox);
    end if;
    v_t := v_t + interval '36 minutes';
  end loop;
  return jsonb_build_object('agora', v_agora, 'ate', null, 'proximo', null);
end;
$$;

-- XP onde começa o nível n. Até o 10: 25·(n-1)² (25, 100, 225... 2025). Do 10 em diante
-- cada nível pede 22% a mais que o anterior, começando em 700 (10→11: 700, 15→16: 1.892,
-- 20→21: 5.113, 24→25: 11.327). Os números da barra vêm daqui (estado: xp_nivel/xp_proximo).
create or replace function public.fazenda_xp_nivel(p_nivel int)
returns bigint language sql immutable as $$
  select case when p_nivel <= 10 then 25 * (p_nivel - 1) * (p_nivel - 1)
              else 2025 + round(700 * (power(1.22::float8, p_nivel - 10) - 1) / 0.22)::bigint end;
$$;

-- Nível a partir do XP (o inverso de fazenda_xp_nivel)
create or replace function public.fazenda_nivel(p_xp int)
returns int language plpgsql immutable as $$
declare
  n int;
begin
  if p_xp < 2025 then
    return floor(sqrt(greatest(p_xp, 0) / 25.0))::int + 1;
  end if;
  n := 10 + floor(ln(1 + (p_xp - 2025) * 0.22 / 700) / ln(1.22))::int;
  while fazenda_xp_nivel(n + 1) <= p_xp loop n := n + 1; end loop;    -- acerta o arredondamento
  while n > 10 and fazenda_xp_nivel(n) > p_xp loop n := n - 1; end loop;
  return n;
end;
$$;

-- Quem já jogava na curva antiga continua no mesmo nível e com a barra cheia na mesma
-- proporção (só muda o XP de quem passou do nível 10). Roda uma vez por jogador (curva 1 → 2).
update public.fazenda_jogadores j
   set xp = case when x.n < 10 then j.xp
                 else fazenda_xp_nivel(x.n) + floor((j.xp - 25 * (x.n - 1) * (x.n - 1))::numeric / (25 * (2 * x.n - 1))
                                                    * (fazenda_xp_nivel(x.n + 1) - fazenda_xp_nivel(x.n)))::int end,
       curva = 2
  from (select id, floor(sqrt(greatest(xp, 0) / 25.0))::int + 1 as n from public.fazenda_jogadores where curva = 1) x
 where j.id = x.id;

create or replace function public.fazenda_max_canteiros(p_nivel int)
returns int language sql immutable as $$
  select least(6 + (p_nivel - 1) * 2, 18);
$$;

drop function if exists public.fazenda_terrenos_venda();

-- Terrenos à venda: áreas de mata em volta da fazenda (22 x 13), compradas em ordem.
-- Precisa bater com ZONAS em assets/fazenda/fazenda-arte.js.
create or replace function public.fazenda_zonas()
returns jsonb language sql immutable as $$
  select '[{"n":1,"nome":"Campo do sul","x":0,"y":13,"w":22,"h":7,"custo":500,"nivel":4},
           {"n":2,"nome":"Mata do leste","x":22,"y":0,"w":10,"h":13,"custo":1500,"nivel":7},
           {"n":3,"nome":"Vale do sudeste","x":22,"y":13,"w":10,"h":7,"custo":3500,"nivel":10,"lago":true}]'::jsonb;
$$;

-- (x, y) fica dentro do terreno de quem já comprou p_zonas terrenos?
create or replace function public.fazenda_no_terreno(p_zonas int, p_x int, p_y int)
returns boolean language sql immutable as $$
  select (p_x between 0 and 21 and p_y between 0 and 12)
      or exists (select 1 from jsonb_array_elements(fazenda_zonas()) z
                  where (z->>'n')::int <= p_zonas
                    and p_x >= (z->>'x')::int and p_x < (z->>'x')::int + (z->>'w')::int
                    and p_y >= (z->>'y')::int and p_y < (z->>'y')::int + (z->>'h')::int);
$$;

-- Quantos canteiros o jogador pode ter: +2 por nível até o 25 e +6 por terreno
-- (igual a limiteCanteirosNivel em fazenda.js)
create or replace function public.fazenda_limite_canteiros(p_nivel int, p_zonas int)
returns int language sql immutable as $$
  select least(6 + (p_nivel - 1) * 2, 54) + 6 * p_zonas;
$$;

-- Presente de moedas ao chegar no nível n: 50·n até o 10 e o dobro depois, que custa mais
-- (igual a presenteNivel em fazenda.js)
create or replace function public.fazenda_presente_nivel(p_nivel int)
returns int language sql immutable as $$
  select case when p_nivel > 10 then 100 * p_nivel else 50 * p_nivel end;
$$;

-- ⚡ que cabe nas baterias: 50 da caixa de luz + 100 por banco de baterias + 500 por supercapacitor
create or replace function public.fazenda_capacidade(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select 50 + coalesce(sum(case c.tipo when 'bateria' then 100 when 'supercap' then 500 else 0 end), 0)::int
    from fazenda_construcoes c where c.jogador_id = p_jogador;
$$;

-- ⚡ por hora que sol, vento e reator geram num momento (o painel solar só de dia, 6h às 18h)
create or replace function public.fazenda_energia_taxa(p_jogador uuid, p_t timestamptz)
returns real language sql stable security definer set search_path = public as $$
  select coalesce(sum(case i.efeito
           when 'solar' then case when extract(hour from p_t at time zone 'America/Sao_Paulo') between 6 and 17
                                  then case x.clima when 'sol' then 12 when 'calor' then 14 when 'vento' then 10 when 'nublado' then 5 else 3 end
                                  else 0 end
           when 'eolica' then case x.clima when 'vento' then 30 when 'chuva' then 14 when 'nublado' then 10 when 'sol' then 8 else 5 end
           when 'reator' then case x.clima when 'calor' then 80 else 120 end
           else 0 end), 0)::real
    from fazenda_construcoes c
    join fazenda_itens i on i.id = c.tipo
    cross join (select fazenda_clima_em(p_t) as clima) x
   where c.jogador_id = p_jogador and i.efeito in ('solar', 'eolica', 'reator');
$$;

-- Prêmio do convite: quem entra pelo link e quem chamou (igual ao que o jogo mostra, que vem
-- do estado). Quem chamou ganha por no máximo 10 amigos por dia (contra fazendas falsas).
create or replace function public.fazenda_premio_convite()
returns jsonb language sql immutable as $$
  select '{"amigo": 200, "dono": 300, "por_dia": 10}'::jsonb;
$$;

-- Código de convite novo: 6 letras/números sem os que confundem (0/O, 1/I/L)
create or replace function public.fazenda_novo_convite()
returns text
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_alfabeto text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_bytes    bytea;
  v_codigo   text;
  i          int;
begin
  loop
    v_bytes := gen_random_bytes(6);
    v_codigo := '';
    for i in 0..5 loop
      v_codigo := v_codigo || substr(v_alfabeto, 1 + get_byte(v_bytes, i) % length(v_alfabeto), 1);
    end loop;
    exit when not exists (select 1 from fazenda_jogadores where convite = v_codigo);
  end loop;
  return v_codigo;
end;
$$;

-- Quem já jogava ganha seu código (um por vez, para a checagem de repetido enxergar os anteriores)
do $$
declare
  r record;
begin
  for r in select id from public.fazenda_jogadores where convite is null loop
    update public.fazenda_jogadores set convite = public.fazenda_novo_convite() where id = r.id;
  end loop;
end $$;

-- Peixes do lago e a chance (em %) de cada um no anzol. A estátua do Velho Chico dobra a do
-- lendário (tirando do lambari). Os preços ficam no catálogo (fazenda_culturas).
create or replace function public.fazenda_peixes(p_estatua boolean default false)
returns table (peixe text, chance int) language sql immutable as $$
  select t.p, case when p_estatua and t.p = 'velho_chico' then t.c * 2
                   when p_estatua and t.p = 'lambari' then t.c - 1 else t.c end
    from (values ('lambari', 40, 1), ('tilapia', 25, 2), ('piau', 15, 3), ('curimata', 10, 4),
                 ('tucunare', 6, 5), ('surubim', 3, 6), ('velho_chico', 1, 7)) t(p, c, o)
   order by t.o;
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
  v_ce     text;
begin
  -- chovendo agora: a chuva rega tudo (some a seca dos canteiros)
  if fazenda_clima_em(now()) = 'chuva' then
    update fazenda_canteiros set seco = false where jogador_id = p_jogador and estado = 'plantado' and seco;
  end if;
  for r in
    select c.posicao, c.x, c.y, c.plantado_em, c.prox_evento, c.erva, c.praga, c.seco, k.tempo_seg
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
      v_ce := fazenda_clima_em(v_evt);                                     -- o clima na hora do problema
      if v_ce = 'calor' and random() < 0.5 then v_tipo := 2; end if;       -- onda de calor: mais seca
      if v_ce = 'vento' and random() < 0.5 then v_tipo := 1; end if;       -- ventania espalha pragas
      if v_ce = 'chuva' and v_tipo = 2 then v_tipo := -1; end if;          -- com chuva não seca
      if v_ce = 'nublado' then v_tipo := -1; end if;                       -- nublado: nada de novo
      -- máquina por perto evita o problema (robô capinador, pulverizador, irrigador);
      -- o aspersor elétrico evita qualquer um, gastando 1 ⚡
      if v_tipo = 0 and not v_erva and not fazenda_protegido(p_jogador, 'erva', r.x, r.y) then
        if not fazenda_aspersor(p_jogador, r.x, r.y) then v_erva := true; end if;
      elsif v_tipo = 1 and not v_praga and not fazenda_protegido(p_jogador, 'praga', r.x, r.y) then
        if not fazenda_aspersor(p_jogador, r.x, r.y) then v_praga := true; end if;
      elsif v_tipo = 2 and not v_seco and not fazenda_protegido(p_jogador, 'seco', r.x, r.y) then
        if not fazenda_aspersor(p_jogador, r.x, r.y) then v_seco := true; end if;
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
  v_json  jsonb;
  v_ener  real;
  v_clima jsonb := fazenda_clima_previsao(now());
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
  v_nivel := fazenda_nivel(j.xp);
  -- subiu de nível: presente de moedas por cada nível novo
  if v_nivel > coalesce(j.nivel_premiado, 1) then
    update fazenda_jogadores
       set moedas = moedas + (select sum(fazenda_presente_nivel(n)) from generate_series(coalesce(j.nivel_premiado, 1) + 1, v_nivel) n),
           nivel_premiado = v_nivel
     where id = p_jogador;
    select * into j from fazenda_jogadores where id = p_jogador;
  end if;
  -- canteiros não aparecem mais sozinhos: o jogador coloca no modo construir até este limite
  v_max := fazenda_limite_canteiros(v_nivel, j.zonas);
  v_ener := fazenda_energia_atualizar(p_jogador);

  perform fazenda_gerar_missoes(p_jogador);

  v_json := jsonb_build_object(
    'agora', now(),
    'jogador', jsonb_build_object(
      'id', j.id,
      'apelido', j.apelido,
      'moedas', j.moedas,
      'xp', j.xp,
      'nivel', v_nivel,
      'xp_nivel', fazenda_xp_nivel(v_nivel),
      'xp_proximo', fazenda_xp_nivel(v_nivel + 1),
      'max_canteiros', v_max,
      'zonas', j.zonas,
      'beleza', fazenda_beleza(p_jogador),
      'bonus_venda', fazenda_bonus_venda(p_jogador)
    ),
    'zonas_venda', fazenda_zonas(),
    'galinheiro', jsonb_build_object('linhas', fazenda_galinheiro_linhas(p_jogador), 'quer', fazenda_galinheiro_quer(p_jogador)),
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
               'roubado', roubado, 'adubado', adubado)
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
        from fazenda_missoes where jogador_id = p_jogador and dia = fazenda_hoje()), '[]'::jsonb),
    'ajudantes', coalesce((
      select jsonb_agg(jsonb_build_object('tipo', tipo, 'nivel', nivel, 'relatorio', relatorio))
        from fazenda_ajudantes where jogador_id = p_jogador), '[]'::jsonb),
    'ajudantes_tipos', (
      select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_ajudantes_tipos t)
  );
  -- o relatório (o que fizeram enquanto você estava fora) aparece uma vez só
  update fazenda_ajudantes set relatorio = 0 where jogador_id = p_jogador and relatorio > 0;
  update fazenda_convites set visto = true where dono_id = p_jogador and not visto;   -- idem os amigos novos
  return v_json;
end;
$$;

-- Aplica uma ação em um canteiro. Retorna a quantidade colhida (0 se não colheu).
drop function if exists public.fazenda_aplicar(uuid, text, int, text);
-- p_bot = feita por um ajudante (sem XP, sem missão, sem moeda de "cuidar")
create or replace function public.fazenda_aplicar(p_jogador uuid, p_acao text, p_posicao int, p_cultura text, p_bot boolean default false)
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
  v_fora   boolean;
  v_estufa boolean;
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
           erva = false, praga = false, seco = false, roubado = 0, prox_evento = null, adubado = false
     where jogador_id = p_jogador and posicao = p_posicao;
    if not p_bot then update fazenda_jogadores set xp = xp + 1 where id = p_jogador; end if;

  elsif p_acao = 'adubar' then   -- só o Seu Zé (ajudante): +1 item na colheita desse plantio
    if not p_bot then raise exception 'acao_invalida'; end if;
    if c.estado <> 'plantado' or now() >= v_maduro or c.adubado then
      raise exception 'nada_a_fazer';
    end if;
    update fazenda_canteiros set adubado = true where jogador_id = p_jogador and posicao = p_posicao;

  elsif p_acao = 'plantar' then
    if c.estado <> 'arado' then
      raise exception 'precisa_arar';
    end if;
    select * into k from fazenda_culturas where id = p_cultura;
    if not found or k.tipo <> 'cultura' then
      raise exception 'cultura_invalida';
    end if;
    -- semente de outra estação só cresce no alcance de uma estufa elétrica
    v_fora := k.estacao is not null and k.estacao <> fazenda_estacao_em(now());
    v_estufa := fazenda_protegido(p_jogador, 'estufa', c.x, c.y);
    if v_fora and not v_estufa then
      raise exception 'fora_de_estacao';
    end if;
    if fazenda_nivel(j.xp) < k.nivel_min then
      raise exception 'nivel_insuficiente';
    end if;
    if j.moedas < k.custo then
      raise exception 'moedas_insuficientes';
    end if;
    if v_estufa then
      v_estufa := fazenda_gastar_energia(p_jogador, 5);   -- sem energia, a estufa não ajuda
    end if;
    if v_fora and not v_estufa then
      raise exception 'sem_energia';
    end if;
    update fazenda_jogadores set moedas = moedas - k.custo where id = p_jogador;
    update fazenda_canteiros
       -- pé de girassol, tora, árvore de outono por perto: começa 10% adiantada; estufa: 25%
       set estado = 'plantado', cultura = k.id,
           plantado_em = now() - make_interval(secs => k.tempo_seg *
                           (0.1 * fazenda_protegido(p_jogador, 'crescer', c.x, c.y)::int + 0.25 * v_estufa::int)),
           erva = false, praga = false, seco = false, roubado = 0, adubado = false,
           prox_evento = now() + make_interval(secs => k.tempo_seg * (0.15 + random() * 0.35))
     where jogador_id = p_jogador and posicao = p_posicao;
    if not p_bot then
      perform fazenda_missao(p_jogador, 'plantar', 1);
      update fazenda_jogadores set semente = k.id where id = p_jogador;   -- a semeadora usa a mesma
    end if;

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
    if not p_bot then
      update fazenda_jogadores set xp = xp + 1, moedas = moedas + 1 where id = p_jogador;
      perform fazenda_missao(p_jogador, 'cuidar', 1);
    end if;

  elsif p_acao = 'colher' then
    if c.estado <> 'plantado' or now() < v_maduro then
      raise exception 'nao_maduro';
    end if;
    if now() >= v_murcho then
      raise exception 'murchou';
    end if;
    -- cada problema não resolvido custa 1 unidade; o que os vizinhos pegaram também sai
    v_qtd := greatest(k.rendimento - (c.erva::int + c.praga::int + c.seco::int) - c.roubado, 1)
             + fazenda_tem_efeito(p_jogador, 'colheita')::int          -- colheitadeira
             + (fazenda_clima_em(now()) = 'sol')::int                    -- colheita no sol
             + fazenda_protegido(p_jogador, 'adubo', c.x, c.y)::int     -- cogumelos, barril, colmeia
             + c.adubado::int;                                          -- adubo do Seu Zé
    if fazenda_protegido(p_jogador, 'sorte', c.x, c.y) and random() < 0.15 then
      v_qtd := v_qtd * 2;                                               -- alvo
    end if;
    insert into fazenda_celeiro (jogador_id, item, quantidade)
    values (p_jogador, k.id, v_qtd)
    on conflict (jogador_id, item)
    do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
    if not p_bot then update fazenda_jogadores set xp = xp + k.xp + fazenda_protegido(p_jogador, 'xp', c.x, c.y)::int where id = p_jogador; end if;
    update fazenda_canteiros   -- com trator, o canteiro já fica arado
       set estado = case when fazenda_tem_efeito(p_jogador, 'arar') then 'arado' else 'vazio' end,
           cultura = null, plantado_em = null,
           erva = false, praga = false, seco = false, roubado = 0, prox_evento = null, adubado = false
     where jogador_id = p_jogador and posicao = p_posicao;
    if not p_bot then perform fazenda_missao(p_jogador, 'colher', v_qtd); end if;

  else
    raise exception 'acao_invalida';
  end if;

  return v_qtd;
end;
$$;

-- ------------------------------------------------------------
-- API pública (chamada via /rest/v1/rpc/...)
-- ------------------------------------------------------------

-- p_convite: código de quem chamou (link ?convite=); código errado não impede de criar
drop function if exists public.fazenda_criar(text);
create or replace function public.fazenda_criar(p_apelido text, p_convite text default null)
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
  v_dono   record;
  v_premio jsonb := fazenda_premio_convite();
  v_conv   jsonb;
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

  insert into fazenda_jogadores (apelido, codigo_hash, convite)
  values (p_apelido, encode(digest(v_codigo, 'sha256'), 'hex'), fazenda_novo_convite())
  returning id into v_id;

  -- Começa com 6 canteiros já arados
  insert into fazenda_canteiros (jogador_id, posicao, estado, x, y)
  select v_id, g, 'arado', 9 + g, 4 from generate_series(0, 5) g;

  -- Veio por um convite: os dois ganham moedas (quem chamou, até o limite do dia)
  if nullif(btrim(p_convite), '') is not null then
    select id, apelido into v_dono from fazenda_jogadores
     where convite = upper(btrim(p_convite)) and id <> v_id
       for update;
    if found then
      insert into fazenda_convites (convidado_id, dono_id, premiado)
      values (v_id, v_dono.id,
              (select count(*) from fazenda_convites
                where dono_id = v_dono.id and premiado and criado_em > now() - interval '1 day') < (v_premio->>'por_dia')::int);
      update fazenda_jogadores set moedas = moedas + (v_premio->>'amigo')::int where id = v_id;
      update fazenda_jogadores set moedas = moedas + (v_premio->>'dono')::int
       where id = v_dono.id and (select premiado from fazenda_convites where convidado_id = v_id);
      v_conv := jsonb_build_object('apelido', v_dono.apelido, 'moedas', (v_premio->>'amigo')::int);
    end if;
  end if;

  return jsonb_build_object(
    'token', fazenda_nova_sessao(v_id),
    'codigo', v_codigo,
    'convite', v_conv,
    'estado', fazenda_estado(v_id)
  );
end;
$$;

-- Tela de entrada aberta por um link de convite: de quem é o convite?
create or replace function public.fazenda_convite_info(p_codigo text)
returns jsonb
language sql stable security definer
set search_path = public, extensions
as $$
  select jsonb_build_object('apelido', apelido, 'nivel', fazenda_nivel(xp), 'moedas', (fazenda_premio_convite()->>'amigo')::int)
    from fazenda_jogadores where convite = upper(btrim(p_codigo));
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

-- Traz a energia até agora: soma o que os geradores fizeram desde a última conta (até
-- 12 horas, em fatias de 36 min: o sol se põe e o clima muda várias vezes por dia), queima o
-- milho do gerador a biomassa e corta no que cabe nas baterias.
create or replace function public.fazenda_energia_atualizar(p_jogador uuid)
returns real
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  j        record;
  g        record;
  v_e      real;
  v_cap    int;
  v_t      timestamptz;
  v_prox   timestamptz;
  v_tempo  int;
  v_milho  int;
  v_queima int;
begin
  select energia, energia_em into j from fazenda_jogadores where id = p_jogador for update;
  if j.energia_em is not null and j.energia_em >= now() then
    return j.energia;                                   -- já fez a conta nesta chamada
  end if;
  if not exists (select 1 from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
                  where c.jogador_id = p_jogador and i.categoria = 'energia') then
    update fazenda_jogadores set energia_em = now() where id = p_jogador;
    return j.energia;
  end if;
  v_cap := fazenda_capacidade(p_jogador);
  v_e := j.energia;
  v_t := greatest(coalesce(j.energia_em, now()), now() - interval '12 hours');
  while v_t < now() loop
    v_prox := least(date_trunc('minute', v_t) + make_interval(mins => 36 - fazenda_minuto_semana(v_t) % 36), now());
    v_e := v_e + fazenda_energia_taxa(p_jogador, v_t) * extract(epoch from v_prox - v_t)::real / 3600;
    v_t := v_prox;
  end loop;
  -- gerador a biomassa ligado: 1 milho a cada 30 min vira 25 ⚡ (acabou o milho, desliga)
  for g in
    select c.x, c.y, c.iniciado_em from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
     where c.jogador_id = p_jogador and i.efeito = 'biomassa' and c.iniciado_em is not null
       for update of c
  loop
    g.iniciado_em := greatest(g.iniciado_em, now() - interval '12 hours');
    v_tempo := floor(extract(epoch from now() - g.iniciado_em) / 1800);
    continue when v_tempo <= 0;
    v_milho := greatest(coalesce((select quantidade from fazenda_celeiro where jogador_id = p_jogador and item = 'milho'), 0)
                      - coalesce((select quantidade from fazenda_reservas where jogador_id = p_jogador and item = 'milho'), 0), 0);
    -- bateria cheia: não queima milho à toa
    v_queima := least(v_tempo, v_milho, ceil(greatest(v_cap - v_e, 0) / 25.0)::int);
    if v_queima > 0 then
      update fazenda_celeiro set quantidade = quantidade - v_queima where jogador_id = p_jogador and item = 'milho';
      v_e := v_e + 25 * v_queima;
    end if;
    update fazenda_construcoes
       set iniciado_em = case when v_milho - v_queima <= 0 then null
                              else g.iniciado_em + make_interval(secs => v_tempo * 1800) end
     where jogador_id = p_jogador and x = g.x and y = g.y;
  end loop;
  v_e := least(greatest(v_e, 0), v_cap);
  update fazenda_jogadores set energia = v_e, energia_em = now() where id = p_jogador;
  return v_e;
end;
$$;

-- Gasta energia se tiver o bastante (senão não gasta nada e devolve false)
create or replace function public.fazenda_gastar_energia(p_jogador uuid, p_qtd real)
returns boolean
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if fazenda_energia_atualizar(p_jogador) < p_qtd then
    return false;
  end if;
  update fazenda_jogadores set energia = energia - p_qtd where id = p_jogador;
  update fazenda_estatisticas set energia = energia + ceil(p_qtd)::int where jogador_id = p_jogador;
  return true;
end;
$$;

-- Tem aspersor elétrico com energia cobrindo (x, y)? Gasta 1 ⚡ por problema evitado.
create or replace function public.fazenda_aspersor(p_jogador uuid, p_x int, p_y int)
returns boolean
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if not fazenda_protegido(p_jogador, 'aspersor', p_x, p_y) then
    return false;
  end if;
  return fazenda_gastar_energia(p_jogador, 1);
end;
$$;

-- Oficinas: até 10 receitas no estoque de cada uma (os ingredientes saem do celeiro na hora de
-- guardar). Ela trabalha sozinha: termina uma receita, começa a próxima na hora, e o que fica
-- pronto espera em "prontos" até você tocar nela. Com a fábrica automática (energia), o estoque
-- vazio busca ingredientes no celeiro (8 ⚡ por receita) e os produtos vão direto para o celeiro.
create or replace function public.fazenda_estoque_max()
returns int language sql immutable as $$ select 10 $$;

-- Tira do celeiro os ingredientes de até p_max receitas (a ração reservada fica); devolve quantas
create or replace function public.fazenda_abastecer(p_jogador uuid, p_entradas jsonb, p_max int)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  e   record;
  v_n int := p_max;
begin
  if p_max <= 0 then return 0; end if;
  for e in select key as item, value::int as qtd from jsonb_each_text(p_entradas) loop
    v_n := least(v_n, (coalesce((select quantidade from fazenda_celeiro where jogador_id = p_jogador and item = e.item), 0)
                     - coalesce((select quantidade from fazenda_reservas where jogador_id = p_jogador and item = e.item), 0)) / e.qtd);
  end loop;
  v_n := greatest(v_n, 0);
  if v_n > 0 then
    for e in select key as item, value::int as qtd from jsonb_each_text(p_entradas) loop
      update fazenda_celeiro set quantidade = quantidade - e.qtd * v_n where jogador_id = p_jogador and item = e.item;
    end loop;
  end if;
  return v_n;
end;
$$;

-- Faz as oficinas andarem até agora (roda ao carregar a fazenda e antes de mexer numa oficina)
create or replace function public.fazenda_oficinas_andar(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  o      record;
  v_auto boolean := fazenda_tem_efeito(p_jogador, 'automatico');
  v_tri  boolean := fazenda_tem_efeito(p_jogador, 'triturar');
  v_t    timestamptz;
  v_fim  timestamptz;
  v_est  int;
  v_pr   int;
  v_cel  int;
  v_n    int;
  v_qtd  int;
begin
  for o in
    select c.x, c.y, c.iniciado_em, c.estoque, c.prontos, i.produz, i.produz_seg, i.produz_qtd, i.entradas
      from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
     where c.jogador_id = p_jogador and i.entradas is not null
       for update of c
  loop
    v_t := o.iniciado_em; v_est := o.estoque; v_pr := o.prontos; v_cel := 0; v_fim := null; v_n := 0;
    loop
      exit when v_n >= 48;
      v_n := v_n + 1;
      if v_t is not null then
        exit when now() < v_t + make_interval(secs => o.produz_seg);   -- ainda trabalhando
        v_qtd := o.produz_qtd;
        if v_tri and fazenda_gastar_energia(p_jogador, 10) then v_qtd := v_qtd * 2; end if;   -- triturador
        if v_auto then v_cel := v_cel + v_qtd; else v_pr := v_pr + v_qtd; end if;
        v_fim := v_t + make_interval(secs => o.produz_seg);
        v_t := null;
      end if;
      -- estoque vazio com a fábrica automática: busca uma receita no celeiro (8 ⚡)
      if v_est <= 0 and v_auto and fazenda_energia_atualizar(p_jogador) >= 8 then
        v_est := fazenda_abastecer(p_jogador, o.entradas, 1);
        if v_est > 0 then perform fazenda_gastar_energia(p_jogador, 8); end if;
      end if;
      exit when v_est <= 0;
      v_est := v_est - 1;
      -- emenda na receita anterior (o tempo fora vale, até 12 horas)
      v_t := greatest(coalesce(v_fim, now()), now() - interval '12 hours');
    end loop;
    if v_cel > 0 then
      insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, o.produz, v_cel)
      on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
    end if;
    update fazenda_construcoes set iniciado_em = v_t, estoque = v_est, prontos = least(v_pr, 32000)
     where jogador_id = p_jogador and x = o.x and y = o.y;
  end loop;
end;
$$;

-- As máquinas elétricas trabalham sozinhas (roda ao carregar a fazenda, como os ajudantes):
-- as oficinas andam (fábrica automática incluída); os robôs colhem e replantam.
create or replace function public.fazenda_industria(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  r     record;
  cc    record;
  v_sem text;
begin
  perform fazenda_energia_atualizar(p_jogador);
  perform fazenda_oficinas_andar(p_jogador);   -- oficinas: estoque, prontos e a fábrica automática

  select semente into v_sem from fazenda_jogadores where id = p_jogador;
  for r in
    select c.x, c.y, i.raio from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
     where c.jogador_id = p_jogador and i.efeito = 'robo'
  loop
    for cc in
      select x.posicao, x.estado, x.cultura,
             coalesce(x.estado = 'plantado'
               and now() >= x.plantado_em + make_interval(secs => k.tempo_seg)
               and now() < x.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)), false) as maduro
        from fazenda_canteiros x left join fazenda_culturas k on k.id = x.cultura
       where x.jogador_id = p_jogador and abs(x.x - r.x) <= r.raio and abs(x.y - r.y) <= r.raio
       order by x.posicao
    loop
      if cc.maduro then
        begin   -- colhe (e ara, se não tiver trator): 3 ⚡
          if not fazenda_gastar_energia(p_jogador, 3) then exit; end if;
          perform fazenda_aplicar(p_jogador, 'colher', cc.posicao, null, true);
          if (select estado from fazenda_canteiros where jogador_id = p_jogador and posicao = cc.posicao) = 'vazio' then
            perform fazenda_aplicar(p_jogador, 'arar', cc.posicao, null, true);
          end if;
        exception when others then null;
        end;
        begin   -- replanta a mesma semente (paga com suas moedas): 1 ⚡
          if fazenda_gastar_energia(p_jogador, 1) then
            perform fazenda_aplicar(p_jogador, 'plantar', cc.posicao, cc.cultura, true);
          end if;
        exception when others then null;
        end;
      elsif cc.estado = 'arado' and v_sem is not null then
        begin   -- canteiro arado vazio: planta a última semente que você usou
          if fazenda_gastar_energia(p_jogador, 1) then
            perform fazenda_aplicar(p_jogador, 'plantar', cc.posicao, v_sem, true);
          end if;
        exception when others then null;
        end;
      end if;
    end loop;
  end loop;
end;
$$;

-- Tarefas por hora de um ajudante em cada nível (fase 18: 12 / 30 / 90; antes 4 / 12 / 36)
create or replace function public.fazenda_ritmo(p_nivel int)
returns real language sql immutable as $$
  select (case p_nivel when 1 then 12 when 2 then 30 else 90 end)::real;
$$;

-- Os ajudantes fazem o trabalho acumulado desde a última vez (até 8 horas).
-- Roda quando a fazenda carrega (abrir a página e a cada 30 s com ela aberta).
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
  v_est   text;
begin
  for a in
    select h.tipo, h.nivel, h.credito, h.atualizado_em, t.funcao, t.alvo
      from fazenda_ajudantes h join fazenda_ajudantes_tipos t on t.id = h.tipo
     where h.jogador_id = p_jogador
     order by t.ordem
       for update of h
  loop
    v_cred := least(a.credito + extract(epoch from now() - a.atualizado_em)::real / 3600 * fazenda_ritmo(a.nivel),
                    fazenda_ritmo(a.nivel) * 8);
    v_n := floor(v_cred);
    v_feito := 0;

    if v_n > 0 and a.funcao = 'colher' then
      for c in
        select cc.posicao from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
         where cc.jogador_id = p_jogador and cc.estado = 'plantado'
           and now() >= cc.plantado_em + make_interval(secs => k.tempo_seg)
           and now() < cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600))
         order by cc.plantado_em limit v_n
      loop
        begin perform fazenda_aplicar(p_jogador, 'colher', c.posicao, null, true); v_feito := v_feito + 1;
        exception when others then null; end;
      end loop;

    elsif v_n > 0 and a.funcao = 'arar' then
      for c in
        select cc.posicao from fazenda_canteiros cc left join fazenda_culturas k on k.id = cc.cultura
         where cc.jogador_id = p_jogador
           and (cc.estado = 'vazio'
                or (cc.estado = 'plantado' and now() >= cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600))))
         order by cc.posicao limit v_n
      loop
        begin perform fazenda_aplicar(p_jogador, 'arar', c.posicao, null, true); v_feito := v_feito + 1;
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
          begin perform fazenda_aplicar(p_jogador, 'adubar', c.posicao, null, true); v_feito := v_feito + 1;
          exception when others then null; end;
        end loop;
      end if;

    elsif v_n > 0 and a.funcao = 'plantar' then
      select coalesce(semente, 'alface') into v_sem from fazenda_jogadores where id = p_jogador;
      -- se a última semente estiver fora de época: a melhor semente da estação que o nível deixa
      select k.id into v_est from fazenda_culturas k
       where k.tipo = 'cultura' and k.estacao = fazenda_estacao_em(now())
         and k.nivel_min <= fazenda_nivel((select xp from fazenda_jogadores where id = p_jogador))
       order by k.nivel_min desc limit 1;
      for c in
        select posicao from fazenda_canteiros
         where jogador_id = p_jogador and estado = 'arado' order by posicao limit v_n
      loop
        begin
          perform fazenda_aplicar(p_jogador, 'plantar', c.posicao, v_sem, true); v_feito := v_feito + 1;
        exception when others then
          exit when sqlerrm = 'moedas_insuficientes';   -- acabou o dinheiro: para
          begin
            perform fazenda_aplicar(p_jogador, 'plantar', c.posicao, coalesce(v_est, 'alface'), true); v_feito := v_feito + 1;
          exception when others then
            begin
              perform fazenda_aplicar(p_jogador, 'plantar', c.posicao, 'alface', true); v_feito := v_feito + 1;
            exception when others then exit;
            end;
          end;
        end;
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
          if c.erva and v_feito < v_n then perform fazenda_aplicar(p_jogador, 'erva', c.posicao, null, true); v_feito := v_feito + 1; end if;
          if c.praga and v_feito < v_n then perform fazenda_aplicar(p_jogador, 'praga', c.posicao, null, true); v_feito := v_feito + 1; end if;
          if c.seco and v_feito < v_n then perform fazenda_aplicar(p_jogador, 'seco', c.posicao, null, true); v_feito := v_feito + 1; end if;
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
            v_feito := v_feito + 1;
            m.alimentado_em := null;
          end if;
        exception when others then null;
        end;
        begin
          if m.alimentado_em is null and v_feito < v_n then
            perform fazenda_animal_um(p_jogador, m.id, 'alimentar', true);   -- sem ração no celeiro: pula
            v_feito := v_feito + 1;
          end if;
        exception when others then null;
        end;
      end loop;
    end if;

    update fazenda_ajudantes
       set credito = v_cred - v_feito, atualizado_em = now(), relatorio = relatorio + v_feito
     where jogador_id = p_jogador and tipo = a.tipo;
  end loop;
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
  perform fazenda_trabalhar(v_id);
  perform fazenda_industria(v_id);
  return fazenda_estado(v_id);
end;
$$;

-- Contrata um ajudante ou evolui o nível dele (2x e 4x o preço de contratar)
create or replace function public.fazenda_contratar(p_token text, p_tipo text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  j       record;
  t       record;
  v_nivel int;
  v_custo int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  select * into t from fazenda_ajudantes_tipos where id = p_tipo;
  if not found then raise exception 'item_invalido'; end if;
  if fazenda_nivel(j.xp) < t.nivel_min then raise exception 'nivel_insuficiente'; end if;
  perform fazenda_trabalhar(v_id);   -- fecha o trabalho no ritmo antigo antes de mudar
  select nivel into v_nivel from fazenda_ajudantes where jogador_id = v_id and tipo = p_tipo;
  if v_nivel >= 3 then raise exception 'nivel_maximo'; end if;
  v_custo := case coalesce(v_nivel, 0) when 0 then t.custo when 1 then t.custo * 2 else t.custo * 4 end;
  if j.moedas < v_custo then raise exception 'moedas_insuficientes'; end if;
  update fazenda_jogadores set moedas = moedas - v_custo where id = v_id;
  insert into fazenda_ajudantes (jogador_id, tipo) values (v_id, p_tipo)
  on conflict (jogador_id, tipo) do update set nivel = fazenda_ajudantes.nivel + 1;
  return jsonb_build_object('estado', fazenda_estado(v_id), 'nivel', coalesce(v_nivel, 0) + 1);
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
  if array_length(p_posicoes, 1) > 100 then
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

  -- o que está reservado para os animais fica no celeiro
  for r in
    select ce.item, ce.quantidade - coalesce(rs.quantidade, 0) as livre, k.venda
      from fazenda_celeiro ce
      join fazenda_culturas k on k.id = ce.item
      left join fazenda_reservas rs on rs.jogador_id = ce.jogador_id and rs.item = ce.item
     where ce.jogador_id = v_id
       and ce.quantidade > coalesce(rs.quantidade, 0)
       and (p_item is null or ce.item = p_item)
       for update of ce
  loop
    v_qtd := least(coalesce(p_quantidade, r.livre), r.livre);
    update fazenda_celeiro set quantidade = quantidade - v_qtd
     where jogador_id = v_id and item = r.item;
    v_ganho := v_ganho + v_qtd * r.venda;
  end loop;

  v_ganho := (v_ganho * (100 + fazenda_bonus_venda(v_id))) / 100;   -- beleza e caixote
  update fazenda_jogadores set moedas = moedas + v_ganho where id = v_id;
  if v_ganho > 0 then
    perform fazenda_missao(v_id, 'vender', v_ganho);
  end if;

  return jsonb_build_object('ganho', v_ganho, 'estado', fazenda_estado(v_id));
end;
$$;

-- Quanto de um item fica guardado no celeiro para os animais (0 = sem reserva)
create or replace function public.fazenda_reservar(p_token text, p_item text, p_quantidade int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
begin
  if not exists (select 1 from fazenda_culturas where id = p_item) then
    raise exception 'item_invalido';
  end if;
  if p_quantidade is null or p_quantidade < 0 or p_quantidade > 999 then
    raise exception 'quantidade_invalida';
  end if;
  if p_quantidade = 0 then
    delete from fazenda_reservas where jogador_id = v_id and item = p_item;
  else
    insert into fazenda_reservas (jogador_id, item, quantidade) values (v_id, p_item, p_quantidade)
    on conflict (jogador_id, item) do update set quantidade = excluded.quantidade;
  end if;
  return jsonb_build_object('estado', fazenda_estado(v_id));
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
    'zonas', j.zonas,
    'canteiros', coalesce((
      select jsonb_agg(jsonb_build_object(
               'posicao', c.posicao, 'x', c.x, 'y', c.y, 'estado', c.estado, 'cultura', c.cultura,
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
  if fazenda_protegido(p_dono, 'alarme', c.x, c.y) then
    raise exception 'alarme';
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
  if fazenda_protegido(p_dono, 'cerca', c.x, c.y) then
    v_qtd := least(v_qtd, 1);   -- cerca ou placa por perto
  end if;

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
  if array_length(p_posicoes, 1) > 100 then
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
      when 'energia' then s.energia
      when 'convites' then v_conv
      when 'peixes' then s.peixes
      when 'lendarios' then s.lendarios
      when 'pedidos' then s.pedidos
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
drop function if exists public.fazenda_animal_um(uuid, bigint, text);
create or replace function public.fazenda_animal_um(p_jogador uuid, p_animal bigint, p_acao text, p_bot boolean default false)
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
    -- com fardo de feno na fazenda, o animal produz 20% mais rápido
    update fazenda_animais
       set alimentado_em = now() - case when fazenda_tem_efeito(p_jogador, 'feno')
                                        then make_interval(secs => r.tempo_seg * 0.2) else interval '0' end
     where id = p_animal;
    return 0;

  elsif p_acao = 'coletar' then
    if r.alimentado_em is null or now() < r.alimentado_em + make_interval(secs => r.tempo_seg) then
      raise exception 'nao_pronto';
    end if;
    insert into fazenda_celeiro (jogador_id, item, quantidade)
    values (p_jogador, r.produto, 1)
    on conflict (jogador_id, item)
    do update set quantidade = fazenda_celeiro.quantidade + 1;
    if not p_bot then update fazenda_jogadores set xp = xp + r.produto_xp where id = p_jogador; end if;
    update fazenda_animais set alimentado_em = null where id = p_animal;
    if not p_bot then perform fazenda_missao(p_jogador, 'animal', 1); end if;
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

  elsif p_categoria = 'terreno' then
    -- sempre o próximo terreno da fila (p_tipo é ignorado)
    if j.zonas >= 3 then raise exception 'terreno_max'; end if;
    select (z->>'custo')::int as custo, (z->>'nivel')::int as nivel into a
      from jsonb_array_elements(fazenda_zonas()) z
     where (z->>'n')::int = j.zonas + 1;
    if fazenda_nivel(j.xp) < a.nivel then raise exception 'nivel_insuficiente'; end if;
    if j.moedas < a.custo then raise exception 'moedas_insuficientes'; end if;
    update fazenda_jogadores set moedas = moedas - a.custo, zonas = zonas + 1 where id = v_id;

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
     campo x9..14 y3..6 · pasto x16..21 y0..6 · lago x24..29 y14..18 (terreno 3) */
create or replace function public.fazenda_livre(p_x int, p_y int)
returns boolean language sql immutable as $$
  select p_x between 0 and 31 and p_y between 0 and 19
     and not (p_x between 1 and 3  and p_y between 1 and 6)     -- celeiro
     and not (p_x between 5 and 7  and p_y between 1 and 3)     -- casa
     and not (p_x between 0 and 6  and p_y between 7 and 8)     -- galinheiro
     and not (p_x between 16 and 21 and p_y between 0 and 6)    -- pasto
     and not (p_x between 24 and 29 and p_y between 14 and 18); -- lago
$$;

-- Fase 19: o galinheiro cresce com os bichos pequenos (galinha, pato, coelho): 2 fileiras
-- (y 7 e 8) até 5 bichos, 3 de 6 a 8 e 4 a partir de 9 — para baixo (y 9 e 10), e só ocupa
-- uma fileira nova se ela estiver livre (nada construído nem canteiro em x 0..6). Igual a
-- linhasGalinheiro em fazenda.js.
create or replace function public.fazenda_galinheiro_quer(p_jogador uuid)
returns int language sql stable security definer set search_path = public, extensions as $$
  select case when n >= 9 then 4 when n >= 6 then 3 else 2 end
    from (select count(*) as n from fazenda_animais
           where jogador_id = p_jogador and tipo in ('galinha', 'pato', 'coelho')) x;
$$;

create or replace function public.fazenda_galinheiro_linhas(p_jogador uuid)
returns int
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  v_quer   int := fazenda_galinheiro_quer(p_jogador);
  v_linhas int := 2;
begin
  while v_linhas < v_quer loop
    exit when exists (select 1 from fazenda_canteiros
                       where jogador_id = p_jogador and y = 7 + v_linhas and x between 0 and 6)
           or exists (select 1 from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
                       where c.jogador_id = p_jogador and c.x <= 6 and c.x + i.largura > 0
                         and c.y <= 7 + v_linhas and c.y + i.altura > 7 + v_linhas);
    v_linhas := v_linhas + 1;
  end loop;
  return v_linhas;
end;
$$;

-- Confere se dá para pôr algo de p_w x p_h em (p_x, p_y): dentro do terreno, fora
-- das áreas fixas e sem bater em construções ou canteiros (menos o que está sendo movido)
create or replace function public.fazenda_checar_lugar(p_jogador uuid, p_zonas int, p_x int, p_y int, p_w int, p_h int,
                                                       p_ign_x int default null, p_ign_y int default null,
                                                       p_ign_canteiro int default null)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if exists (select 1 from generate_series(p_x, p_x + p_w - 1) gx, generate_series(p_y, p_y + p_h - 1) gy
              where not fazenda_livre(gx, gy) or not fazenda_no_terreno(p_zonas, gx, gy)) then
    raise exception 'lugar_reservado';
  end if;
  -- o galinheiro que cresceu (fileiras 9 e 10) também é reservado
  if p_x <= 6 and p_y + p_h - 1 >= 9 and p_y <= 6 + fazenda_galinheiro_linhas(p_jogador) then
    raise exception 'lugar_reservado';
  end if;
  if exists (select 1 from fazenda_construcoes c join fazenda_itens k on k.id = c.tipo
              where c.jogador_id = p_jogador
                and not (c.x is not distinct from p_ign_x and c.y is not distinct from p_ign_y)
                and c.x < p_x + p_w and p_x < c.x + k.largura
                and c.y < p_y + p_h and p_y < c.y + k.altura)
     or exists (select 1 from fazenda_canteiros c
                 where c.jogador_id = p_jogador and c.posicao is distinct from p_ign_canteiro
                   and c.x between p_x and p_x + p_w - 1 and c.y between p_y and p_y + p_h - 1) then
    raise exception 'lugar_ocupado';
  end if;
end;
$$;

-- Compra um item e coloca no quadrado (x, y)
create or replace function public.fazenda_construir(p_token text, p_tipo text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id  uuid := fazenda_auth(p_token);
  j     record;
  i     record;
  v_pos int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;

  -- canteiro: não é item da loja, é um lugar de plantar (limite pelo nível e terrenos)
  if p_tipo = 'canteiro' then
    if (select count(*) from fazenda_canteiros where jogador_id = v_id)
       >= fazenda_limite_canteiros(fazenda_nivel(j.xp), j.zonas) then
      raise exception 'limite_canteiros';
    end if;
    perform fazenda_checar_lugar(v_id, j.zonas, p_x, p_y, 1, 1);
    select min(g) into v_pos from generate_series(0, 99) g
     where not exists (select 1 from fazenda_canteiros where jogador_id = v_id and posicao = g);
    if v_pos is null then raise exception 'limite_canteiros'; end if;
    insert into fazenda_canteiros (jogador_id, posicao, estado, x, y) values (v_id, v_pos, 'vazio', p_x, p_y);
    return jsonb_build_object('estado', fazenda_estado(v_id), 'posicao', v_pos);
  end if;

  select * into i from fazenda_itens where id = p_tipo;
  if not found then raise exception 'item_invalido'; end if;
  if fazenda_nivel(j.xp) < i.nivel_min then raise exception 'nivel_insuficiente'; end if;
  perform fazenda_checar_lugar(v_id, j.zonas, p_x, p_y, i.largura, i.altura);
  if i.limite is not null
     and (select count(*) from fazenda_construcoes where jogador_id = v_id and tipo = i.id) >= i.limite then
    raise exception 'limite_maquina';
  end if;
  if (select count(*) from fazenda_construcoes where jogador_id = v_id) >= 200 then
    raise exception 'limite_construcoes';
  end if;
  if j.moedas < i.custo then raise exception 'moedas_insuficientes'; end if;
  -- máquina elétrica nova: fecha a conta da energia antes (ela não gera pelo tempo de antes)
  if i.categoria = 'energia' then perform fazenda_energia_atualizar(v_id); end if;
  update fazenda_jogadores set moedas = moedas - i.custo where id = v_id;
  insert into fazenda_construcoes (jogador_id, x, y, tipo, colhido_em) values (v_id, p_x, p_y, i.id, now());
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
  v_id  uuid := fazenda_auth(p_token);
  j     record;
  i     record;
  v_pos int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  -- canteiro (mesmo plantado: a planta vai junto)
  select posicao into v_pos from fazenda_canteiros where jogador_id = v_id and x = p_x and y = p_y;
  if v_pos is not null then
    perform fazenda_checar_lugar(v_id, j.zonas, p_nx, p_ny, 1, 1, null, null, v_pos);
    update fazenda_canteiros set x = p_nx, y = p_ny where jogador_id = v_id and posicao = v_pos;
    return jsonb_build_object('estado', fazenda_estado(v_id));
  end if;

  select k.* into i from fazenda_construcoes c join fazenda_itens k on k.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y;
  if not found then raise exception 'item_invalido'; end if;
  perform fazenda_checar_lugar(v_id, j.zonas, p_nx, p_ny, i.largura, i.altura, p_x, p_y);
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
  c      record;
begin
  -- canteiro: só sai vazio ou arado (planta crescendo, colha ou limpe antes)
  select * into c from fazenda_canteiros where jogador_id = v_id and x = p_x and y = p_y for update;
  if found then
    if c.estado = 'plantado' then raise exception 'canteiro_ocupado'; end if;
    delete from fazenda_canteiros where jogador_id = v_id and posicao = c.posicao;
    return jsonb_build_object('devolvido', 0, 'estado', fazenda_estado(v_id));
  end if;

  -- oficina: o estoque (ingredientes) e os produtos prontos voltam para o celeiro
  perform fazenda_oficinas_andar(v_id);
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  select v_id, x.item, sum(x.qtd)::int from (
    select e.key as item, e.value::int * (oc.estoque + case when oc.iniciado_em is null then 0 else 1 end) as qtd
      from fazenda_construcoes oc join fazenda_itens oi on oi.id = oc.tipo, jsonb_each_text(oi.entradas) e
     where oc.jogador_id = v_id and oc.x = p_x and oc.y = p_y and oi.entradas is not null
    union all
    select oi.produz, oc.prontos
      from fazenda_construcoes oc join fazenda_itens oi on oi.id = oc.tipo
     where oc.jogador_id = v_id and oc.x = p_x and oc.y = p_y and oi.entradas is not null and oc.prontos > 0
  ) x where x.qtd > 0 group by x.item
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;

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

-- Colhe o que um item produz sozinho (amoreira). Toque nele fora do modo construir.
create or replace function public.fazenda_coletar(p_token text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  r    record;
  k    record;
begin
  select c.colhido_em, i.produz, i.produz_seg, i.produz_qtd, i.entradas into r
    from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y
     for update of c;
  if not found or r.produz is null or r.entradas is not null then raise exception 'item_invalido'; end if;
  if r.colhido_em is not null and now() < r.colhido_em + make_interval(secs => r.produz_seg) then
    raise exception 'nao_pronto';
  end if;
  select * into k from fazenda_culturas where id = r.produz;
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  values (v_id, r.produz, r.produz_qtd)
  on conflict (jogador_id, item)
  do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  update fazenda_construcoes set colhido_em = now() where jogador_id = v_id and x = p_x and y = p_y;
  update fazenda_jogadores set xp = xp + greatest(k.xp / 8, 1) where id = v_id;
  perform fazenda_missao(v_id, 'colher', r.produz_qtd);
  return jsonb_build_object('qtd', r.produz_qtd, 'item', r.produz, 'estado', fazenda_estado(v_id));
end;
$$;

-- Oficina (fase 17): tocar nela pega os produtos prontos. Sem nada pronto, parada e sem estoque,
-- guarda uma receita e começa (é o que a versão anterior do jogo fazia ao tocar).
create or replace function public.fazenda_oficina(p_token text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id  uuid := fazenda_auth(p_token);
  r     record;
  k     record;
begin
  perform fazenda_oficinas_andar(v_id);
  select c.iniciado_em, c.estoque, c.prontos, i.produz, i.entradas into r
    from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y
     for update of c;
  if not found or r.entradas is null then raise exception 'item_invalido'; end if;

  if r.prontos > 0 then
    select * into k from fazenda_culturas where id = r.produz;
    insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, r.produz, r.prontos)
    on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
    update fazenda_jogadores set xp = xp + k.xp * r.prontos where id = v_id;
    update fazenda_construcoes set prontos = 0 where jogador_id = v_id and x = p_x and y = p_y;
    return jsonb_build_object('acao', 'coletou', 'qtd', r.prontos, 'item', r.produz, 'xp', k.xp * r.prontos,
                              'estado', fazenda_estado(v_id));
  end if;

  if r.iniciado_em is null and r.estoque = 0 then
    if fazenda_abastecer(v_id, r.entradas, 1) = 0 then raise exception 'sem_ingredientes'; end if;
    update fazenda_construcoes set iniciado_em = now() where jogador_id = v_id and x = p_x and y = p_y;
    return jsonb_build_object('acao', 'iniciou', 'estado', fazenda_estado(v_id));
  end if;
  return jsonb_build_object('acao', 'nada', 'estado', fazenda_estado(v_id));
end;
$$;

-- Guarda (p_receitas > 0) ou tira (< 0) receitas do estoque de uma oficina. Guardar tira os
-- ingredientes do celeiro na hora (sem mexer na ração reservada), até 10 receitas no estoque;
-- tirar devolve os ingredientes. Parada e com estoque, ela já começa.
create or replace function public.fazenda_estoque(p_token text, p_x int, p_y int, p_receitas int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  r    record;
  e    record;
  v_n  int;
begin
  if p_receitas is null or p_receitas = 0 or abs(p_receitas) > 100 then raise exception 'quantidade_invalida'; end if;
  perform fazenda_oficinas_andar(v_id);
  select c.iniciado_em, c.estoque, i.entradas into r
    from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y
     for update of c;
  if not found or r.entradas is null then raise exception 'item_invalido'; end if;

  if p_receitas > 0 then
    -- a receita em andamento também ocupa um lugar
    v_n := least(p_receitas, fazenda_estoque_max() - r.estoque - (case when r.iniciado_em is null then 0 else 1 end));
    if v_n <= 0 then raise exception 'estoque_cheio'; end if;
    v_n := fazenda_abastecer(v_id, r.entradas, v_n);
    if v_n = 0 then raise exception 'sem_ingredientes'; end if;
    update fazenda_construcoes set estoque = estoque + v_n where jogador_id = v_id and x = p_x and y = p_y;
  else
    v_n := least(-p_receitas, r.estoque);
    if v_n <= 0 then raise exception 'estoque_vazio'; end if;
    for e in select key as item, value::int as qtd from jsonb_each_text(r.entradas) loop
      insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, e.item, e.qtd * v_n)
      on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
    end loop;
    update fazenda_construcoes set estoque = estoque - v_n where jogador_id = v_id and x = p_x and y = p_y;
    v_n := -v_n;
  end if;
  perform fazenda_oficinas_andar(v_id);   -- parada com estoque: começa agora
  return jsonb_build_object('receitas', v_n, 'estado', fazenda_estado(v_id));
end;
$$;

-- A visita de agora (null = já atendida, ou nível menor que 3). Tudo sai do md5 do jogador e
-- do bloco de 3 horas: a mesma visita a cada carga, e outra no bloco seguinte.
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
begin
  if exists (select 1 from fazenda_visitas_npc where jogador_id = p_jogador and slot = v_slot) then return null; end if;
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

-- Atende a visita: entregar (vende o pedido pelo preço dela, ou compra o adubo da mascate) ou
-- dispensar (ela vai embora e volta outra pessoa no próximo bloco de 3 horas)
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
    update fazenda_jogadores set moedas = moedas + (v->>'paga')::int, xp = xp + (v->>'xp')::int where id = v_id;
    perform fazenda_missao(v_id, 'vender', (v->>'paga')::int);
  end if;
  insert into fazenda_visitas_npc (jogador_id, slot, resposta) values (v_id, (v->>'slot')::bigint, 'entregou');
  insert into fazenda_estatisticas (jogador_id) values (v_id) on conflict do nothing;
  update fazenda_estatisticas set pedidos = pedidos + 1 where jogador_id = v_id;
  return jsonb_build_object('resposta', 'entregou', 'visita', v, 'adubados', v_n, 'pagou', v_preco, 'estado', fazenda_estado(v_id));
end;
$$;

-- Tira os peixes do cesto do Bira: 1 a cada 30 min desde lago_em, até 16 (o que passar disso
-- se perde: o cesto estava cheio). Cada peixe é sorteado pela chance (fazenda_peixes).
create or replace function public.fazenda_pescar(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id      uuid := fazenda_auth(p_token);
  j         record;
  p         record;
  v_estatua boolean := fazenda_tem_efeito(v_id, 'chico');
  v_n       int;
  v_k       int;
  v_r       numeric;
  v_soma    int;
  v_peixes  jsonb := '{}'::jsonb;
  v_xp      int;
  v_lend    int;
begin
  select zonas, lago_em into j from fazenda_jogadores where id = v_id for update;
  if j.zonas < 3 then raise exception 'sem_lago'; end if;
  if j.lago_em is null then
    update fazenda_jogadores set lago_em = now() where id = v_id;
    raise exception 'cesto_vazio';
  end if;
  v_n := least(floor(extract(epoch from now() - j.lago_em) / 1800)::int, 16);
  if v_n <= 0 then raise exception 'cesto_vazio'; end if;
  for v_k in 1..v_n loop
    v_r := random() * 100;
    v_soma := 0;
    for p in select * from fazenda_peixes(v_estatua) loop
      v_soma := v_soma + p.chance;
      if v_r < v_soma then
        v_peixes := jsonb_set(v_peixes, array[p.peixe], to_jsonb(coalesce((v_peixes->>p.peixe)::int, 0) + 1));
        exit;
      end if;
    end loop;
  end loop;
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  select v_id, e.key, e.value::int from jsonb_each_text(v_peixes) e
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  select coalesce(sum(k.xp * e.value::int), 0)::int into v_xp
    from jsonb_each_text(v_peixes) e join fazenda_culturas k on k.id = e.key;
  v_lend := coalesce((v_peixes->>'velho_chico')::int, 0);
  update fazenda_jogadores
     set xp = xp + v_xp,
         lago_em = case when now() - j.lago_em >= interval '8 hours' then now()   -- cesto cheio: recomeça agora
                        else j.lago_em + make_interval(secs => v_n * 1800) end    -- guarda o pedaço do próximo
   where id = v_id;
  insert into fazenda_estatisticas (jogador_id) values (v_id) on conflict do nothing;
  update fazenda_estatisticas set peixes = peixes + v_n, lendarios = lendarios + v_lend where jogador_id = v_id;
  perform fazenda_missao(v_id, 'colher', v_n);
  return jsonb_build_object('peixes', v_peixes, 'qtd', v_n, 'xp', v_xp, 'lendario', v_lend, 'estado', fazenda_estado(v_id));
end;
$$;

-- Liga ou desliga o gerador a biomassa (toque nele). Ao ligar já queima o primeiro milho.
create or replace function public.fazenda_gerador(p_token text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  r    record;
begin
  select c.iniciado_em, i.efeito into r
    from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y
     for update of c;
  if not found or r.efeito is distinct from 'biomassa' then raise exception 'item_invalido'; end if;
  perform fazenda_energia_atualizar(v_id);   -- fecha a conta do que já passou
  if r.iniciado_em is not null then
    update fazenda_construcoes set iniciado_em = null where jogador_id = v_id and x = p_x and y = p_y;
    return jsonb_build_object('ligado', false, 'estado', fazenda_estado(v_id));
  end if;
  if coalesce((select quantidade from fazenda_celeiro where jogador_id = v_id and item = 'milho'), 0)
     - coalesce((select quantidade from fazenda_reservas where jogador_id = v_id and item = 'milho'), 0) < 1 then
    raise exception 'sem_milho';
  end if;
  update fazenda_celeiro set quantidade = quantidade - 1 where jogador_id = v_id and item = 'milho';
  update fazenda_jogadores set energia = least(energia + 25, fazenda_capacidade(v_id)) where id = v_id;
  update fazenda_construcoes set iniciado_em = now() where jogador_id = v_id and x = p_x and y = p_y;
  return jsonb_build_object('ligado', true, 'estado', fazenda_estado(v_id));
end;
$$;

-- Anúncio premiado: o jogador assistiu até o fim e tudo o que está em andamento anda
-- 30 minutos — plantas, animais, oficinas, amoreira, ajudantes e geradores. Nada passa do
-- ponto (o que amadurece fica maduro, não murcha). Sem limite por dia: só um intervalo
-- mínimo entre dois anúncios, menor que a duração de um, contra clique repetido.
create or replace function public.fazenda_anuncio(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id  uuid := fazenda_auth(p_token);
  j     record;
  v_d   interval := interval '30 minutes';
  v_c   int;
  v_a   int;
  v_o   int;
  v_p   int;
begin
  select anuncio_em into j from fazenda_jogadores where id = v_id for update;
  if j.anuncio_em is not null and j.anuncio_em > now() - interval '10 seconds' then
    raise exception 'anuncio_cedo';
  end if;
  perform fazenda_energia_atualizar(v_id);   -- fecha a conta da energia antes de somar os 30 min

  -- plantas crescendo (os problemas que cairiam nesse tempo também chegam)
  update fazenda_canteiros c
     set plantado_em = greatest(c.plantado_em - v_d, now() - make_interval(secs => k.tempo_seg)),
         prox_evento = c.prox_evento - (c.plantado_em - greatest(c.plantado_em - v_d, now() - make_interval(secs => k.tempo_seg)))
    from fazenda_culturas k
   where c.jogador_id = v_id and k.id = c.cultura and c.estado = 'plantado'
     and now() < c.plantado_em + make_interval(secs => k.tempo_seg);
  get diagnostics v_c = row_count;

  -- animais produzindo
  update fazenda_animais a
     set alimentado_em = greatest(a.alimentado_em - v_d, now() - make_interval(secs => t.tempo_seg))
    from fazenda_animais_tipos t
   where a.jogador_id = v_id and t.id = a.tipo and a.alimentado_em is not null
     and now() < a.alimentado_em + make_interval(secs => t.tempo_seg);
  get diagnostics v_a = row_count;

  -- oficinas trabalhando
  update fazenda_construcoes c
     set iniciado_em = greatest(c.iniciado_em - v_d, now() - make_interval(secs => i.produz_seg))
    from fazenda_itens i
   where c.jogador_id = v_id and i.id = c.tipo and i.entradas is not null and c.iniciado_em is not null
     and now() < c.iniciado_em + make_interval(secs => i.produz_seg);
  get diagnostics v_o = row_count;

  -- o que produz sozinho (amoreira)
  update fazenda_construcoes c
     set colhido_em = greatest(c.colhido_em - v_d, now() - make_interval(secs => i.produz_seg))
    from fazenda_itens i
   where c.jogador_id = v_id and i.id = c.tipo and i.produz is not null and i.entradas is null
     and c.colhido_em is not null and now() < c.colhido_em + make_interval(secs => i.produz_seg);
  get diagnostics v_p = row_count;

  -- ajudantes ganham meia hora de trabalho; sol, vento e reator, meia hora de energia
  update fazenda_ajudantes
     set credito = least(credito + fazenda_ritmo(nivel) * 0.5, fazenda_ritmo(nivel) * 8)
   where jogador_id = v_id;
  update fazenda_jogadores
     set energia = least(energia + fazenda_energia_taxa(v_id, now()) * 0.5, fazenda_capacidade(v_id)),
         anuncio_em = now()
   where id = v_id;
  insert into fazenda_estatisticas (jogador_id) values (v_id) on conflict do nothing;
  update fazenda_estatisticas set anuncios = anuncios + 1 where jogador_id = v_id;
  update fazenda_jogadores set lago_em = lago_em - v_d where id = v_id and lago_em is not null;   -- +1 peixe no cesto

  -- já roda o que o tempo a mais destrava (problemas, ajudantes, máquinas)
  perform fazenda_tick(v_id);
  perform fazenda_trabalhar(v_id);
  perform fazenda_industria(v_id);
  return jsonb_build_object('canteiros', v_c, 'animais', v_a, 'oficinas', v_o + v_p, 'estado', fazenda_estado(v_id));
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
  -- baú na fazenda: +25% de moedas
  if fazenda_tem_efeito(v_id, 'missao') then m.moedas := (m.moedas * 125) / 100; end if;
  update fazenda_jogadores set moedas = moedas + m.moedas, xp = xp + m.xp where id = v_id;
  return jsonb_build_object('moedas', m.moedas, 'xp', m.xp, 'estado', fazenda_estado(v_id));
end;
$$;

-- ------------------------------------------------------------
-- Permissões: só a API pública fica executável pela chave anon
-- ------------------------------------------------------------
revoke execute on function
  public.fazenda_nivel(int),
  public.fazenda_xp_nivel(int),
  public.fazenda_minuto_semana(timestamptz),
  public.fazenda_estacao_em(timestamptz),
  public.fazenda_estacao_fim(timestamptz),
  public.fazenda_clima_tabela(text),
  public.fazenda_clima_em(timestamptz),
  public.fazenda_clima_previsao(timestamptz),
  public.fazenda_max_canteiros(int),
  public.fazenda_zonas(),
  public.fazenda_no_terreno(int, int, int),
  public.fazenda_limite_canteiros(int, int),
  public.fazenda_presente_nivel(int),
  public.fazenda_tem_efeito(uuid, text),
  public.fazenda_protegido(uuid, text, int, int),
  public.fazenda_beleza(uuid),
  public.fazenda_bonus_venda(uuid),
  public.fazenda_capacidade(uuid),
  public.fazenda_energia_taxa(uuid, timestamptz),
  public.fazenda_energia_atualizar(uuid),
  public.fazenda_gastar_energia(uuid, real),
  public.fazenda_aspersor(uuid, int, int),
  public.fazenda_industria(uuid),
  public.fazenda_gerador(text, int, int),
  public.fazenda_anuncio(text),
  public.fazenda_premio_convite(),
  public.fazenda_novo_convite(),
  public.fazenda_convite_info(text),
  public.fazenda_peixes(boolean),
  public.fazenda_pescar(text),
  public.fazenda_checar_lugar(uuid, int, int, int, int, int, int, int, int),
  public.fazenda_auth(text),
  public.fazenda_nova_sessao(uuid),
  public.fazenda_tick(uuid),
  public.fazenda_estado(uuid),
  public.fazenda_aplicar(uuid, text, int, text, boolean),
  public.fazenda_ritmo(int),
  public.fazenda_trabalhar(uuid),
  public.fazenda_criar(text, text),
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
  public.fazenda_animal_um(uuid, bigint, text, boolean),
  public.fazenda_comprar(text, text, text),
  public.fazenda_animal(text, text, bigint[]),
  public.fazenda_resgatar_missao(text, int),
  public.fazenda_livre(int, int),
  public.fazenda_construir(text, text, int, int),
  public.fazenda_mover(text, int, int, int, int),
  public.fazenda_demolir(text, int, int),
  public.fazenda_coletar(text, int, int),
  public.fazenda_reservar(text, text, int),
  public.fazenda_contratar(text, text),
  public.fazenda_oficina(text, int, int),
  public.fazenda_estoque_max(),
  public.fazenda_abastecer(uuid, jsonb, int),
  public.fazenda_oficinas_andar(uuid),
  public.fazenda_estoque(text, int, int, int),
  public.fazenda_galinheiro_quer(uuid),
  public.fazenda_galinheiro_linhas(uuid),
  public.fazenda_visitante(uuid),
  public.fazenda_atender(text, boolean),
  public.fazenda_checar_conquistas(uuid)
from public, anon, authenticated;

grant execute on function
  public.fazenda_criar(text, text),
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
  public.fazenda_demolir(text, int, int),
  public.fazenda_coletar(text, int, int),
  public.fazenda_reservar(text, text, int),
  public.fazenda_contratar(text, text),
  public.fazenda_oficina(text, int, int),
  public.fazenda_estoque(text, int, int, int),
  public.fazenda_atender(text, boolean),
  public.fazenda_gerador(text, int, int),
  public.fazenda_anuncio(text),
  public.fazenda_convite_info(text),
  public.fazenda_pescar(text)
to anon, authenticated;
