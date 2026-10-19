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
  posicao      smallint not null check (posicao between 0 and 299),
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
-- fase 56: até 299 (o limite de canteiros já passa de 100 com os 6 terrenos; o 101º dava limite_canteiros)
alter table public.fazenda_canteiros add constraint fazenda_canteiros_posicao_check check (posicao between 0 and 299);
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
alter table public.fazenda_jogadores add constraint fazenda_jogadores_zonas_check check (zonas between 0 and 7);   -- fase 24: 6 terrenos; fase 61: + o litoral
-- fase 78: os 3 terrenos da direita (8, 9 e 10), comprados à parte dos de 1 a 7, do nível 29 em diante
alter table public.fazenda_jogadores add column if not exists direita smallint not null default 0;
-- quem comprou fileiras na versão 1 recebe as moedas de volta (e fica com os canteiros)
update public.fazenda_jogadores
   set moedas = moedas + case terrenos when 1 then 400 when 2 then 1600 else 4600 end, terrenos = 0
 where terrenos > 0;

-- Fase 2: visitas de vizinhos (roubos e ajudas) — também é o diário do dono
create table if not exists public.fazenda_visitas (
  id           bigint generated always as identity primary key,
  ator_id      uuid not null references public.fazenda_jogadores(id) on delete cascade,
  dono_id      uuid not null references public.fazenda_jogadores(id) on delete cascade,
  tipo         text not null check (tipo in ('roubo', 'ajuda')),   -- fase 48: + salvar, bicho (abaixo)
  posicao      smallint not null,
  plantado_em  timestamptz not null,
  cultura      text not null references public.fazenda_culturas(id),
  qtd          int not null default 0,
  criado_em    timestamptz not null default now()
);
-- Fase 48: o vizinho também salva planta murcha (salvar) e dá ração aos bichos (bicho)
alter table public.fazenda_visitas drop constraint if exists fazenda_visitas_tipo_check;
alter table public.fazenda_visitas add constraint fazenda_visitas_tipo_check check (tipo in ('roubo', 'ajuda', 'salvar', 'bicho'));
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
  check (categoria in ('caminho', 'natureza', 'objeto', 'construcao', 'maquina', 'oficina', 'energia', 'bichos', 'pomar', 'praia'));   -- (fase 73: praia)
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
-- Fase 25: por_terreno = quantas dá para ter a cada terreno (a fazenda inicial conta como um)
alter table public.fazenda_itens add column if not exists por_terreno smallint;
-- Fase 26: itens do mesmo grupo dividem o limite por terreno (pomar: 2 árvores frutíferas por terreno, de qualquer tipo)
alter table public.fazenda_itens add column if not exists grupo text;
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
-- Fase 43: a operária (oficinas) e o eletricista (energia mais barata)
alter table public.fazenda_ajudantes_tipos drop constraint if exists fazenda_ajudantes_tipos_funcao_check;
alter table public.fazenda_ajudantes_tipos add constraint fazenda_ajudantes_tipos_funcao_check
  check (funcao in ('arar', 'plantar', 'cuidar', 'colher', 'animal', 'oficina', 'energia'));
create table if not exists public.fazenda_ajudantes (
  jogador_id     uuid not null references public.fazenda_jogadores(id) on delete cascade,
  tipo           text not null references public.fazenda_ajudantes_tipos(id),
  nivel          smallint not null default 1 check (nivel between 1 and 5),   -- (fase 74: até o 5)
  credito        real not null default 0,                 -- tarefas que já pode fazer
  atualizado_em  timestamptz not null default now(),
  relatorio      int not null default 0,                  -- tarefas feitas desde a última olhada
  primary key (jogador_id, tipo)
);
-- Fase 18: canteiro adubado pelo Seu Zé (+1 item na colheita; sai na colheita ou ao arar)
alter table public.fazenda_canteiros add column if not exists adubado boolean not null default false;
-- Fase 29: quando o jogador carregou a fazenda (agora e na vez anterior): com ele na fazenda, a Dona Rosa descansa
-- Fase 30: ela passou a fazer rodízio com todas as sementes, então a lista das 3 últimas saiu
alter table public.fazenda_jogadores drop column if exists ultimas_sementes;
alter table public.fazenda_jogadores add column if not exists carregado_em timestamptz;
alter table public.fazenda_jogadores add column if not exists carregado_antes timestamptz;
-- Fase 31: diamantes, a moeda especial (colher na hora). Todo mundo começa com 10, inclusive
-- quem já jogava (o default preenche as linhas que existem), e ganha 5 a cada nível
alter table public.fazenda_jogadores add column if not exists diamantes int not null default 10 check (diamantes >= 0);
-- Fase 43: o que os diamantes compram e dura um tempo: XP em dobro até xp2_ate; o café dos
-- ajudantes (trabalham em dobro) de cafe_de até cafe_ate
alter table public.fazenda_jogadores add column if not exists xp2_ate timestamptz;
alter table public.fazenda_jogadores add column if not exists cafe_de timestamptz;
alter table public.fazenda_jogadores add column if not exists cafe_ate timestamptz;
-- Fase 49: com todas as metas de nível em dia, +50% de XP até o próximo nível (bonus_nivel = o nível em que vale)
alter table public.fazenda_jogadores add column if not exists bonus_nivel int;
-- última semente que o jogador plantou (a semeadora usa a mesma)
alter table public.fazenda_jogadores add column if not exists semente text references public.fazenda_culturas(id);
-- Fase 70: o XP que veio de diamante (pacote de XP, calendário dourado, a metade do XP em dobro) não conta
-- no evento; e os anúncios do dia (quando voltarem: 6 por dia, diamante só nos 3 primeiros)
alter table public.fazenda_jogadores add column if not exists xp_pago bigint not null default 0;
alter table public.fazenda_jogadores add column if not exists anuncio_dia date;
alter table public.fazenda_jogadores add column if not exists anuncio_n smallint not null default 0;

-- Fase 11: energia (⚡) guardada nas baterias e quando foi a última conta.
-- O gerador a biomassa usa construcoes.iniciado_em: null = desligado.
alter table public.fazenda_jogadores add column if not exists energia real not null default 0;
alter table public.fazenda_jogadores add column if not exists energia_em timestamptz;
-- Fase 46: a energia gasta soma aqui, na mesma gravação que tira a energia (antes era uma linha a mais
-- em fazenda_estatisticas a cada gasto); o total para conquista e perfil = estatisticas.energia + isto
alter table public.fazenda_jogadores add column if not exists energia_gasta real not null default 0;
alter table public.fazenda_estatisticas add column if not exists energia int not null default 0;

-- Fase 12: curva de XP. 1 = a antiga (25·(n-1)² em todos os níveis), 2 = a nova (mais
-- difícil do nível 10 em diante). Quem já jogava é convertido uma vez só (ver abaixo).
alter table public.fazenda_jogadores add column if not exists curva smallint not null default 1;
alter table public.fazenda_jogadores alter column curva set default 5;   -- 5 = fase 62 (7% a mais por nível do 25 em diante)
-- Fase 37: vender dá XP (1 a cada 25 moedas do valor); o que sobra de uma venda (menos de 25)
-- fica guardado para a próxima, para quem vende aos poucos não perder nada
alter table public.fazenda_jogadores add column if not exists venda_resto numeric not null default 0;
-- Fase 41: quando o canteiro deu XP de colheita pela última vez (no máximo 1 vez a cada 8 min)
alter table public.fazenda_canteiros add column if not exists xp_em timestamptz;

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

-- Fase 22: avatar do fazendeiro ({"tipo": "fazendeira", "pele": 0, ...}); null = o de sempre
alter table public.fazenda_jogadores add column if not exists avatar jsonb;
-- personagens do avatar que o jogador já comprou (fazendeiro e fazendeira são de graça)
alter table public.fazenda_jogadores add column if not exists avatares text[] not null default '{}';

-- Fase 21: visitas na porteira. A cada 3 horas chega alguém (fazenda_visitante): o feirante,
-- a doceira e o caminhoneiro querem comprar algo pagando mais que o celeiro; a mascate vende
-- adubo. Cada visita fica até o fim das 3 horas ou até você atender (entregar ou dispensar).
create table if not exists public.fazenda_visitas_npc (
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  slot       bigint not null,                 -- floor(epoch / 10800): o bloco de 3 horas (fase 76: de 10 min, floor(epoch / 600))
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

-- Fase 25: amora não tem mais semente — só dá no pé (amoreira). Vira produto (como ovo e leite):
-- não aparece na loja de sementes nem dá para plantar; o que já estava plantado termina normal.
update public.fazenda_culturas set tipo = 'produto' where id = 'morango';

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
  -- até 5 de cada (cada um 50% mais caro que o anterior: fazenda_comprar); vaca: 3 h (era 4)
  ('galinha', 'Galinha', 100, 2, 5, 'ovo',    3600, 'alface', 1, 1),
  ('vaca',    'Vaca',    350, 5, 5, 'leite', 10800, 'batata', 2, 2),
  ('ovelha',  'Ovelha',  600, 8, 5, 'la',    28800, 'abobora', 2, 3),
  ('coelho',  'Coelho',  250, 6, 5, 'pelo',   7200, 'cenoura', 2, 4),
  ('pato',    'Pato',    450, 11, 5, 'pena', 10800, 'alface', 2, 5),
  ('porco',   'Porco',   900, 14, 5, 'trufa', 21600, 'milho', 2, 6)
on conflict (id) do update set
  nome = excluded.nome, custo = excluded.custo, nivel_min = excluded.nivel_min, maximo = excluded.maximo,
  produto = excluded.produto, tempo_seg = excluded.tempo_seg, racao = excluded.racao,
  racao_qtd = excluded.racao_qtd, ordem = excluded.ordem;

-- Ajudantes (fase 8): um por função e um por animal. Caros de contratar e de evoluir.
insert into public.fazenda_ajudantes_tipos (id, nome, papel, funcao, alvo, custo, nivel_min, descricao, ordem) values
  ('granjeira',  'Dona Cida', 'Granjeira',          'animal',  'galinha', 1500,  5, 'Dá a ração e coleta os ovos das galinhas. Cada nível deixa os bichos dela mais rápidos: −10%, −20% e −30% no tempo (soma com o feno).', 1),
  ('lavrador',   'Seu Zé',    'Lavrador',           'arar',    null,      2000,  6, 'Ara os canteiros vazios, limpa os murchos e, com o tempo que sobra, aduba os que estão crescendo: +1 item na colheita de cada um.', 2),
  ('jardineiro', 'Tião',      'Jardineiro',         'cuidar',  null,      2500,  7, 'Tira erva daninha, praga e seca dos canteiros.', 3),
  ('coelheira',  'Nina',      'Cuidadora de coelhos','animal', 'coelho',  2000,  8, 'Dá a ração e coleta o pelo dos coelhos. Cada nível deixa os bichos dela mais rápidos: −10%, −20% e −30% no tempo (soma com o feno).', 4),
  ('vaqueiro',   'Bento',     'Vaqueiro',           'animal',  'vaca',    3000,  9, 'Dá a ração e tira o leite das vacas. Cada nível deixa os bichos dele mais rápidos: −10%, −20% e −30% no tempo (soma com o feno).', 5),
  ('colhedor',   'Juca',      'Colhedor',           'colher',  null,      4000, 10, 'Colhe tudo o que estiver maduro, antes de murchar. Com o tempo que sobra, colhe as frutas do pomar (menos as das árvores encostadas num baú, que são do baú).', 6),
  ('semeadora',  'Dona Rosa', 'Semeadora',          'plantar', null,      4000, 11, 'Quando você está fora, planta os canteiros arados em rodízio com todas as sementes da estação que o seu nível libera, a menos plantada primeiro. Paga com suas moedas e pula as que o dinheiro não dá. Com você na fazenda, ela descansa: quem escolhe é você.', 7),
  ('patinheiro', 'Pedrinho',  'Cuidador de patos',  'animal',  'pato',    3000, 12, 'Dá a ração e junta as penas dos patos. Cada nível deixa os bichos dele mais rápidos: −10%, −20% e −30% no tempo (soma com o feno).', 8),
  ('pastora',    'Lia',       'Pastora',            'animal',  'ovelha',  4000, 13, 'Dá a ração e tosquia a lã das ovelhas. Cada nível deixa os bichos dela mais rápidos: −10%, −20% e −30% no tempo (soma com o feno).', 9),
  ('porqueiro',  'Tonho',     'Porqueiro',          'animal',  'porco',   5000, 15, 'Dá a ração e acha as trufas dos porcos. Cada nível deixa os bichos dele mais rápidos: −10%, −20% e −30% no tempo (soma com o feno).', 10),
  ('operaria',   'Dona Lurdes','Operária',          'oficina', null,      6000, 12, 'Cuida das oficinas sem gastar energia: leva para o celeiro o que ficou pronto (o XP do produto vem quando você vende) e enche o estoque delas com o que tem no celeiro, uma receita de cada vez em rodízio (a ração reservada fica). Trabalha depois da rede de canos.', 11),
  ('eletricista','Faísca',    'Eletricista',        'energia', null,      8000, 17, 'Cuida das máquinas: tudo o que gasta energia gasta menos. Nível 1: −20%; nível 2: −35%; nível 3: metade.', 12)
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
  ('amoreira',      'Amoreira',            'pomar',    400, 9, 17),
  ('pedras',        'Pedras',              'objeto',    20, 2, 20),
  ('tora',          'Tora de madeira',     'objeto',    25, 3, 21),
  ('placa',         'Placa',               'objeto',    20, 1, 22),
  ('balde',         'Balde d''água',       'objeto',    30, 3, 23),
  ('barril',        'Barril',              'objeto',    50, 5, 24),
  ('feno',          'Fardo de feno',       'objeto',    60, 5, 25),
  ('alvo',          'Alvo',                'objeto',    80, 6, 26),
  ('caixote',       'Caixote de tomate',   'objeto',   100, 7, 27),
  ('colmeia',       'Colmeia',             'objeto',   120, 8, 28),
  ('bau',           'Baú',                 'objeto',   200, 11, 29),
  ('lampiao',       'Lampião',             'objeto',    70, 1, 30)   -- fase 54: era nível 4 (quem começa de noite ficava no escuro)
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

-- Fase 23: um cercado para cada bicho (Construir → Bichos). Os bichos daquela espécie moram nele
-- (o desenho e o tamanho ficam em CERCADOS de fazenda-arte.js). Fase 45: o cercado vem antes do bicho
-- (sem ele a loja não vende); o galinheiro e o pasto do começo ficam só para quem já tinha bicho sem cercado.
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, largura, altura, efeito, limite, beleza, descricao) values
  ('cercado_galinha', 'Cercado das galinhas', 'bichos', 200,  2, 100, 6, 4, 'cercado', 1, 3, 'Casa das galinhas: precisa dela para comprar galinhas, e elas moram aqui.'),
  ('cercado_vaca',    'Curral das vacas',     'bichos', 500,  5, 101, 7, 5, 'cercado', 1, 4, 'Curral com cocho de água: precisa dele para comprar vacas, e elas moram aqui.'),
  ('cercado_coelho',  'Cercado dos coelhos',  'bichos', 300,  6, 102, 6, 4, 'cercado', 1, 3, 'Casa dos coelhos: precisa dela para comprar coelhos, e eles moram aqui.'),
  ('cercado_ovelha',  'Cercado das ovelhas',  'bichos', 600,  8, 103, 7, 5, 'cercado', 1, 4, 'Casa das ovelhas: precisa dela para comprar ovelhas, e elas moram aqui.'),
  ('cercado_pato',    'Lago dos patos',       'bichos', 400, 11, 104, 6, 4, 'cercado', 1, 5, 'Cercado com laguinho: precisa dele para comprar patos, e eles nadam aqui.'),
  ('cercado_porco',   'Chiqueiro',            'bichos', 700, 14, 105, 6, 4, 'cercado', 1, 3, 'Cercado com lama: precisa dele para comprar porcos, e eles moram aqui.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, largura = excluded.largura, altura = excluded.altura, efeito = excluded.efeito,
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
  ('alarme',        'Alarme antiladrão', 'maquina',  500, 6, 52, 'alarme',   3, null, 'Vizinhos não pegam nada dos canteiros em volta (3 quadrados). Com energia elétrica na fazenda, gasta 1 ⚡ por hora e desliga se a bateria zerar.'),
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
  ('cano',          'Cano de vidro',      'energia',    25, 16, 79, 'cano',       0, null, 'Canos encostados formam uma rede que liga baús, oficinas e o celeiro. A rede enche sozinha o estoque das oficinas com o que tem nos baús e no celeiro (1,6 ⚡ por receita); o produto vai para outra oficina que usa ele, para o celeiro ou para um baú; o que sobra no baú vai para o celeiro (1,2 ⚡ por viagem). Dá para ver cada item passando.'),
  ('painel_solar',  'Painel solar',       'energia',  2500, 16, 80, 'solar',      0, 8, 'Gera até 12 ⚡/h de dia (sol forte: 14; nublado: 5; chuva: 3). À noite, nada: no jogo, o dia e a noite se revezam a cada 2 horas. Até 8, mais 1 nos níveis pares a partir do 18 (18, 20, 22...).'),
  ('bateria',       'Banco de baterias',  'energia',  2000, 16, 81, 'bateria',    0, 4, 'Guarda mais 150 ⚡ (sem bateria, a caixa de luz guarda só 50). Bateria cheia: o que sobra é vendido, 1 moeda a cada 5 ⚡.'),
  ('turbina',       'Turbina eólica',     'energia',  4000, 17, 82, 'eolica',     0, 6, 'Gera 8 ⚡/h de dia e de noite; 30 ⚡/h na ventania e 14 na chuva. Na calmaria (sem vento, uns 25% do tempo fora da ventania e da chuva), cai para 3 ⚡/h: o painel de energia avisa quando vem. Até 6, mais 1 nos níveis ímpares a partir do 19 (19, 21, 23...).'),
  ('estufa',        'Estufa elétrica',    'energia',  6000, 18, 83, 'estufa',     2, 3, 'Canteiros em volta (2) aceitam sementes de qualquer estação e crescem 25% mais rápido. Gasta 4 ⚡ por plantio.'),
  ('gerador_bio',   'Gerador a biomassa', 'energia',  6000, 19, 84, 'biomassa',   0, 2, 'Ligado, queima 1 milho a cada 30 min: 50 ⚡/h. Toque nele para ligar ou desligar.'),
  ('triturador',    'Triturador',         'energia', 10000, 20, 85, 'triturar',   0, 1, 'As oficinas rendem 2 produtos por receita. Gasta 8 ⚡ por receita.'),
  ('supercap',      'Supercapacitor',     'energia',  9000, 21, 86, 'bateria',    0, 2, 'Guarda mais 800 ⚡.'),
  ('fabrica_auto',  'Fábrica automática', 'energia', 15000, 22, 87, 'automatico', 0, 1, 'Um pedaço do celeiro em qualquer lugar: a rede de canos encostada nela leva e traz do celeiro como se o cano chegasse até ele (sem mexer na ração reservada).'),
  ('robo_colheita', 'Robô colheitador',   'energia', 18000, 23, 88, 'robo',       3, 2, 'Colhe, ara e replanta sozinho os canteiros em volta (3). Gasta 3,2 ⚡ por colheita e 1,6 por plantio.'),
  ('aspersor',      'Aspersor elétrico',  'energia', 12000, 24, 89, 'aspersor',   3, 4, 'Nenhuma erva, praga ou seca nos canteiros em volta (3). Gasta 1,6 ⚡ por problema evitado.'),
  ('reator',        'Reator nuclear',     'energia', 30000, 25, 90, 'reator',     0, 1, 'Gera 120 ⚡/h sem parar, de dia e de noite (80 na onda de calor, para não esquentar). Cuidado com a radiação: a cada hora, cada bicho da fazenda tem 1 em 200 de ficar radioativo por meia hora (dá o produto dele a cada 2 minutos, direto no celeiro) e, no fim, 1 em 200 de não resistir.')
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
    ('amoreira',      null,           0,  3, 'Dá 4 amoras a cada 5 horas: toque nela para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).', 'morango', 18000, 4),
    ('pedras',        'erva',         1,  1, 'Cobertura de pedras: sem erva daninha nos canteiros encostados.', null, null, null),
    ('tora',          'crescer',      1,  2, 'Minhocas: plantas encostadas crescem 10% mais rápido.', null, null, null),
    ('placa',         'cerca',        2,  1, '"Proibido pegar": vizinhos pegam no máximo 1 item em volta (2 quadrados).', null, null, null),
    ('balde',         'seco',         1,  1, 'Sem seca nos canteiros encostados.', null, null, null),
    ('barril',        'adubo',        1,  2, 'Barril de adubo: +1 item na colheita dos canteiros encostados.', null, null, null),
    ('feno',          'feno',         0,  2, 'Animais produzem 20% mais rápido (fazenda toda, não acumula).', null, null, null),
    ('alvo',          'sorte',        2,  2, 'Sorte: 15% de chance de colheita em dobro em volta (2 quadrados).', null, null, null),
    ('caixote',       'venda',        0,  2, '+10% no preço de venda (fazenda toda, não acumula).', null, null, null),
    ('colmeia',       'adubo',        2,  3, 'Abelhas: +1 item na colheita em volta (2 quadrados).', null, null, null),
    ('bau',           'missao',       0,  3, '+25% de moedas nas missões. Com energia, guarda em si (até 200 itens) o que recolhe: encostado num bloco de canteiros, colhe o que amadurece; num cercado, coleta e dá ração aos bichos; numa árvore do pomar, colhe as frutas; no lago, pega o cesto do Bira (1,6 ⚡ cada). Com canos, manda para as oficinas e o celeiro.', null, null, null),
    ('lampiao',       null,           0,  3, 'Acende sozinho de noite e ilumina em volta. +3 de beleza (beleza dá bônus nas vendas).', null, null, null),
    ('casa_vermelha', null,           0, 20, 'Casinha: +20 de beleza (beleza dá bônus nas vendas) e 1 cama para um ajudante descansar (2 h numa cama; sem cama livre, 4 h na sombra).', null, null, null),
    ('casa_azul',     null,           0, 30, 'Casinha: +30 de beleza (beleza dá bônus nas vendas) e 2 camas para os ajudantes descansarem (2 h numa cama; sem cama livre, 4 h na sombra).', null, null, null)
  ) v(id, efeito, raio, beleza, descricao, produz, produz_seg, produz_qtd)
 where i.id = v.id;

-- Fase 26: o pomar — fruta só dá no pé. Árvores frutíferas: 4 por terreno no total (fazenda inicial
-- + cada terreno comprado), de qualquer tipo, contando a amoreira. Algumas ficam depois do nível 25.
-- fase 43: o limite do pomar é de cada fruta (2 pés por terreno), não de todas juntas: grupo null
update public.fazenda_itens set limite = null, por_terreno = 1, grupo = null where id = 'amoreira';
insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('laranja', 'Laranja', '🍊', 1, 0, 15, 1, 3, 5, 50, 'produto'),
  ('limao', 'Limão', '🍊', 1, 0, 14, 1, 3, 8, 51, 'produto'),
  ('goiaba', 'Goiaba', '🍊', 1, 0, 28, 1, 5, 12, 52, 'produto'),
  ('manga', 'Manga', '🍊', 1, 0, 45, 1, 8, 26, 53, 'produto'),
  ('abacate', 'Abacate', '🍊', 1, 0, 80, 1, 12, 27, 54, 'produto'),
  ('cacau', 'Cacau', '🍊', 1, 0, 60, 1, 10, 28, 55, 'produto'),
  ('jabuticaba', 'Jabuticaba', '🍊', 1, 0, 45, 1, 8, 29, 56, 'produto')
on conflict (id) do update set
  nome = excluded.nome, venda = excluded.venda, xp = excluded.xp, nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, beleza, produz, produz_seg, produz_qtd, por_terreno, grupo, descricao) values
  ('laranjeira', 'Laranjeira', 'pomar', 300, 5, 110, 3, 'laranja', 14400, 4, 1, null, 'Dá 4 laranjas a cada 4 horas: toque nela para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).'),
  ('limoeiro', 'Limoeiro', 'pomar', 450, 8, 111, 3, 'limao', 21600, 6, 1, null, 'Dá 6 limões a cada 6 horas: toque nela para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).'),
  ('goiabeira', 'Goiabeira', 'pomar', 700, 12, 112, 3, 'goiaba', 18000, 4, 1, null, 'Dá 4 goiabas a cada 5 horas: toque nela para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).'),
  ('mangueira', 'Mangueira', 'pomar', 3000, 26, 113, 3, 'manga', 18000, 5, 1, null, 'Dá 5 mangas a cada 5 horas: toque nela para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).'),
  ('abacateiro', 'Abacateiro', 'pomar', 4000, 27, 114, 3, 'abacate', 21600, 4, 1, null, 'Dá 4 abacates a cada 6 horas: toque nela para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).'),
  ('cacaueiro', 'Cacaueiro', 'pomar', 5000, 28, 115, 3, 'cacau', 21600, 6, 1, null, 'Dá 6 cacaus a cada 6 horas: toque nela para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).'),
  ('jabuticabeira', 'Jabuticabeira', 'pomar', 6000, 29, 116, 3, 'jabuticaba', 28800, 12, 1, null, 'Dá 12 jabuticabas a cada 8 horas: toque nela para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min, ordem = excluded.ordem,
  beleza = excluded.beleza, produz = excluded.produz, produz_seg = excluded.produz_seg, produz_qtd = excluded.produz_qtd,
  por_terreno = excluded.por_terreno, grupo = excluded.grupo, descricao = excluded.descricao;

-- Fase 38: toda matéria-prima tem uma oficina. 14 oficinas novas para o que sobrava (beterraba,
-- girassol, morango, melancia, abóbora, repolho, pena, pelo, trufa, peixes e frutas). O produto
-- vale ~1,7x os ingredientes, como nas oficinas antigas; o empório usa o óleo da prensa.
insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('picles',         'Picles',              '🫙', 1, 0, 105, 1, 11,  6, 60, 'produto'),
  ('oleo',           'Óleo de girassol',    '🫗', 1, 0, 135, 1, 14,  8, 61, 'produto'),
  ('doce_abobora',   'Doce de abóbora',     '🍮', 1, 0, 275, 1, 28, 10, 62, 'produto'),
  ('peixe_frito',    'Peixe frito',         '🐟', 1, 0, 155, 1, 16, 11, 63, 'produto'),
  ('suco',           'Suco de frutas',      '🧃', 1, 0, 120, 1, 12, 12, 64, 'produto'),
  ('sorvete',        'Sorvete',             '🍦', 1, 0, 235, 1, 24, 12, 65, 'produto'),
  ('peixe_defumado', 'Peixe defumado',      '🐟', 1, 0, 355, 1, 36, 13, 66, 'produto'),
  ('almofada',       'Almofada',            '🛏', 1, 0, 560, 1, 50, 14, 67, 'produto'),
  ('moqueca',        'Moqueca',             '🍲', 1, 0, 840, 1, 70, 15, 68, 'produto'),
  ('azeite_trufado', 'Azeite trufado',      '🫒', 1, 0, 760, 1, 65, 18, 69, 'produto'),
  ('vitamina',       'Vitamina de manga',   '🥤', 1, 0, 270, 1, 27, 26, 70, 'produto'),
  ('guacamole',      'Guacamole',           '🥑', 1, 0, 320, 1, 32, 27, 71, 'produto'),
  ('licor',          'Licor de jabuticaba', '🍷', 1, 0, 305, 1, 30, 29, 72, 'produto'),
  ('chocolate',      'Chocolate',           '🍫', 1, 0, 425, 1, 42, 28, 73, 'produto')
on conflict (id) do update set
  nome = excluded.nome, venda = excluded.venda, xp = excluded.xp, nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, largura, altura,
                                  produz, produz_seg, produz_qtd, entradas, limite, beleza, descricao) values
  ('conservas',    'Conservas',          'oficina',  1000,  6, 68, 2, 3, 'picles',          3600, 1, '{"batata": 3, "repolho": 2}', 2, 5, '3 beterrabas + 2 repolhos → picles.'),
  ('prensa_oleo',  'Prensa de óleo',     'oficina',  1400,  8, 69, 2, 3, 'oleo',            3000, 1, '{"girassol": 4}', 2, 5, '4 girassóis → óleo de girassol.'),
  ('doceria',      'Doceria',            'oficina',  2200, 10, 70, 2, 3, 'doce_abobora',    5100, 1, '{"jerimum": 3, "ovo": 1}', 2, 5, '3 abóboras + 1 ovo → doce de abóbora.'),
  ('peixaria',     'Peixaria',           'oficina',  2000, 11, 71, 2, 3, 'peixe_frito',     2580, 1, '{"tilapia": 2, "lambari": 2}', 2, 5, '2 tilápias + 2 lambaris → peixe frito.'),
  ('casa_sucos',   'Casa de sucos',      'oficina',  2400, 12, 72, 2, 3, 'suco',            1800, 1, '{"laranja": 2, "limao": 1, "goiaba": 1}', 2, 5, '2 laranjas + 1 limão + 1 goiaba → suco de frutas.'),
  ('sorveteria',   'Sorveteria',         'oficina',  2600, 12, 73, 2, 3, 'sorvete',         3600, 1, '{"moranguinho": 2, "melancia": 1, "leite": 1}', 2, 5, '2 morangos + 1 melancia + 1 leite → sorvete.'),
  ('defumadouro',  'Defumadouro',        'oficina',  3000, 13, 74, 2, 3, 'peixe_defumado',  7200, 1, '{"curimata": 2, "piau": 1}', 2, 5, '2 curimatãs + 1 piau → peixe defumado.'),
  ('atelie',       'Ateliê de penas',    'oficina',  3500, 14, 75, 2, 3, 'almofada',        7680, 1, '{"pena": 4, "pelo": 2}', 2, 5, '4 penas + 2 pelos de coelho → almofada.'),
  ('cozinha_moqueca','Cozinha de moqueca','oficina', 4500, 15, 76, 2, 3, 'moqueca',         5100, 1, '{"tucunare": 1, "surubim": 1, "tomate": 2, "limao": 1}', 2, 5, '1 tucunaré + 1 surubim + 2 tomates + 1 limão → moqueca.'),
  ('emporio',      'Empório',            'oficina',  8000, 18, 77, 2, 3, 'azeite_trufado', 10200, 1, '{"trufa": 1, "oleo": 2}', 2, 5, '1 trufa + 2 óleos de girassol (da prensa) → azeite trufado.'),
  ('vitaminas',    'Casa de vitaminas',  'oficina', 20000, 26, 78, 2, 3, 'vitamina',        3600, 1, '{"manga": 2, "leite": 1}', 2, 5, '2 mangas + 1 leite → vitamina de manga.'),
  ('guacamolaria', 'Guacamolaria',       'oficina', 24000, 27, 80, 2, 3, 'guacamole',       3600, 1, '{"abacate": 2, "tomate": 1, "limao": 1}', 2, 5, '2 abacates + 1 tomate + 1 limão → guacamole.'),
  ('chocolateria', 'Chocolateria',       'oficina', 26000, 28, 81, 2, 3, 'chocolate',       7200, 1, '{"cacau": 3, "leite": 1}', 2, 5, '3 cacaus + 1 leite → chocolate.'),
  ('adega',        'Adega',              'oficina', 30000, 29, 82, 2, 3, 'licor',          14400, 1, '{"jabuticaba": 4}', 2, 5, '4 jabuticabas → licor de jabuticaba.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, largura = excluded.largura, altura = excluded.altura, produz = excluded.produz,
  produz_seg = excluded.produz_seg, produz_qtd = excluded.produz_qtd, entradas = excluded.entradas,
  limite = excluded.limite, beleza = excluded.beleza, descricao = excluded.descricao;

-- Fase 28: pomar menor (2 árvores frutíferas por terreno; antes 4). Quem passou do limite novo fica
-- com as árvores mais caras; as que sobram saem e o preço inteiro delas volta em moedas.
with arv as (
  select c.jogador_id, c.x, c.y, i.custo,
         row_number() over (partition by c.jogador_id order by i.custo desc, c.x, c.y) as n,
         i.por_terreno * (1 + j.zonas) as max
    from public.fazenda_construcoes c
    join public.fazenda_itens i on i.id = c.tipo
    join public.fazenda_jogadores j on j.id = c.jogador_id
   where i.grupo = 'pomar'),
sobra as (select * from arv where n > max),
volta as (
  update public.fazenda_jogadores j set moedas = moedas + d.total
    from (select jogador_id, sum(custo)::int as total from sobra group by jogador_id) d
   where j.id = d.jogador_id
  returning j.id)
delete from public.fazenda_construcoes c using sobra s
 where c.jogador_id = s.jogador_id and c.x = s.x and c.y = s.y;

-- Beleza da fazenda (soma dos itens construídos)
create or replace function public.fazenda_beleza(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select coalesce(sum(i.beleza), 0)::int from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
   where c.jogador_id = p_jogador;
$$;

-- Bônus nas vendas, em %: beleza (+1% a cada 10, até 20) + caixote (+10)
-- fase 78: do nível 29 para baixo, +50% nas vendas (do 30 ao 34 vai caindo 10 por nível, sem tombo)
create or replace function public.fazenda_bonus_venda(p_jogador uuid)
returns int language plpgsql stable security definer set search_path = public as $$
begin   -- (plpgsql: fazenda_nivel vem mais para baixo no arquivo)
  return least(fazenda_beleza(p_jogador) / 10, 20) + 10 * fazenda_tem_efeito(p_jogador, 'venda')::int
       + greatest(0, least(50, 50 - 10 * ((select fazenda_nivel(xp) from fazenda_jogadores where id = p_jogador) - 29)));
end;
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
  -- fase 77: a tempestade ou o furacão de agora e até quando (o jogo antigo só vê a chuva e a ventania)
  v_ext   jsonb := jsonb_build_object('extremo', fazenda_extremo_de(p_t, v_agora));
  v_e     timestamptz := v_t;
begin
  if v_ext->>'extremo' is not null then
    while v_e < p_t + interval '6 hours' and fazenda_extremo_em(v_e) is not distinct from v_ext->>'extremo' loop
      v_e := v_e + interval '36 minutes';
    end loop;
    v_ext := v_ext || jsonb_build_object('extremo_ate', v_e);
  end if;
  for k in 1..80 loop
    v_prox := fazenda_clima_em(v_t);
    if v_prox <> v_agora then
      return jsonb_build_object('agora', v_agora, 'ate', v_t, 'proximo', v_prox) || v_ext;
    end if;
    v_t := v_t + interval '36 minutes';
  end loop;
  return jsonb_build_object('agora', v_agora, 'ate', null, 'proximo', null) || v_ext;
end;
$$;

-- XP onde começa o nível n. Até o 10 é uma tabela que começa bem fácil (o nível 2 vem na
-- primeira colheita de alface) e chega nos mesmos 2025 de antes: 10, 35, 85, 175, 315, 525,
-- 825, 1325, 2025 (fase 31; antes era 25·(n-1)², e ninguém desce de nível com a troca). Do 10
-- em diante cada nível pede 22% a mais que o anterior, começando em 700 (10→11: 700,
-- 15→16: 1.892, 20→21: 5.113, 24→25: 11.327). Os números da barra vêm daqui (estado: xp_nivel/xp_proximo).
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

-- A curva da fase 37 (até o 18 em 22%, depois 30%): só para converter quem estava nela (curva 3 → 4)
create or replace function public.fazenda_xp_nivel_v3(p_nivel int)
returns bigint language sql immutable as $$
  select case when p_nivel <= 10 then (array[0, 10, 35, 85, 175, 315, 525, 825, 1325, 2025])[greatest(p_nivel, 1)]
              when p_nivel <= 18 then 2025 + round(700 * (power(1.22::float8, p_nivel - 10) - 1) / 0.22)::bigint
              else 2025 + round(700 * (power(1.22::float8, 8) - 1) / 0.22)::bigint
                   + round(700 * power(1.22::float8, 7) * 1.3 * (power(1.3::float8, p_nivel - 18) - 1) / 0.3)::bigint end;
$$;

-- Nível a partir do XP (o inverso de fazenda_xp_nivel)
create or replace function public.fazenda_nivel(p_xp int)
returns int language plpgsql immutable as $$
declare
  n int;
begin
  if p_xp < 2025 then
    return 1 + (select count(*)::int from unnest(array[10, 35, 85, 175, 315, 525, 825, 1325]) t where t <= p_xp);
  end if;
  n := 10 + floor(ln(1 + (p_xp - 2025) * 0.22 / 700) / ln(1.22))::int;
  while fazenda_xp_nivel(n + 1) <= p_xp loop n := n + 1; end loop;    -- acerta o arredondamento
  while n > 10 and fazenda_xp_nivel(n) > p_xp loop n := n - 1; end loop;
  return least(n, 45);   -- fase 70: o 45 é o último (passava para 46, 47... e o presente continuava)
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

-- Fase 37 (curva 2 → 3, uma vez): quem já passou do 18 na curva de 22% continua no mesmo
-- nível, com a barra cheia na mesma proporção (ninguém desce de nível). Até o 18 nada muda.
update public.fazenda_jogadores j
   set xp = case when x.n <= 18 then j.xp
                 else fazenda_xp_nivel_v3(x.n) + floor(least(greatest((j.xp - x.ini) / nullif(x.fim - x.ini, 0), 0), 0.999)
                                                    * (fazenda_xp_nivel_v3(x.n + 1) - fazenda_xp_nivel_v3(x.n)))::int end,
       curva = 3
  from (select id, n,
               2025 + round(700 * (power(1.22::float8, n - 10) - 1) / 0.22) as ini,
               2025 + round(700 * (power(1.22::float8, n + 1 - 10) - 1) / 0.22) as fim
          from (select id, case when xp < 2025 then 1
                                else 10 + floor(ln(1 + (xp - 2025) * 0.22 / 700) / ln(1.22))::int end as n
                  from public.fazenda_jogadores where curva = 2) y) x
 where j.id = x.id;

-- Fase 41 (curva 3 → 4, uma vez): do 17 em diante cada nível ficou mais caro (35% a mais que o
-- anterior). Quem já passou do 16 continua no mesmo nível, com a barra na mesma proporção.
update public.fazenda_jogadores j
   set xp = case when x.n <= 16 then j.xp
                 else fazenda_xp_nivel_v4(x.n) + floor(least(greatest((j.xp - fazenda_xp_nivel_v3(x.n))::numeric
                        / nullif(fazenda_xp_nivel_v3(x.n + 1) - fazenda_xp_nivel_v3(x.n), 0), 0), 0.999)
                        * (fazenda_xp_nivel_v4(x.n + 1) - fazenda_xp_nivel_v4(x.n)))::int end,
       curva = 4
  from (select id, (select max(g) from generate_series(1, 60) g where fazenda_xp_nivel_v3(g) <= xp) as n
          from public.fazenda_jogadores where curva = 3) x
 where j.id = x.id;

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

create or replace function public.fazenda_max_canteiros(p_nivel int)
returns int language sql immutable as $$
  select least(6 + (p_nivel - 1) * 2, 18);
$$;

drop function if exists public.fazenda_terrenos_venda();

-- Terrenos à venda: áreas de mata em volta da fazenda (22 x 13), compradas em ordem.
-- Precisa bater com ZONAS em assets/fazenda/fazenda-arte.js. canteiros = quanto o limite sobe.
-- Fase 24: mais 3 terrenos grandes (leste, sul e sudeste): o mapa vai até 48 x 32.
create or replace function public.fazenda_zonas()
returns jsonb language sql immutable as $$
  select '[{"n":1,"nome":"Campo do sul","x":0,"y":13,"w":22,"h":7,"custo":500,"nivel":4,"canteiros":6},
           {"n":2,"nome":"Mata do leste","x":22,"y":0,"w":10,"h":13,"custo":1500,"nivel":7,"canteiros":6},
           {"n":3,"nome":"Vale do sudeste","x":22,"y":13,"w":10,"h":7,"custo":3500,"nivel":10,"lago":true,"canteiros":6},
           {"n":4,"nome":"Chapada do leste","x":32,"y":0,"w":16,"h":20,"custo":8000,"nivel":13,"canteiros":10},
           {"n":5,"nome":"Várzea do sul","x":0,"y":20,"w":32,"h":12,"custo":18000,"nivel":16,"canteiros":12},
           {"n":6,"nome":"Sertão do sudeste","x":32,"y":20,"w":16,"h":12,"custo":87500,"nivel":20,"canteiros":10},
           {"n":7,"nome":"Litoral","x":0,"y":32,"w":64,"h":10,"custo":750000,"nivel":31,"canteiros":10,"mar":true},
           {"n":8,"nome":"Serra do leste","x":48,"y":0,"w":16,"h":11,"custo":250000,"nivel":29,"canteiros":10,"lado":"direita"},
           {"n":9,"nome":"Planalto do leste","x":48,"y":11,"w":16,"h":11,"custo":500000,"nivel":33,"canteiros":10,"lado":"direita"},
           {"n":10,"nome":"Cerrado do leste","x":48,"y":22,"w":16,"h":10,"custo":1000000,"nivel":38,"canteiros":10,"lado":"direita"}]'::jsonb;
   -- fase 61 (fase 72: do 20 em diante, 2,5x). Fase 78: os 3 da direita (8 a 10), comprados à parte,
   -- e o litoral vai até a ponta da direita (x 63)
$$;

-- fase 78: os terrenos de um jogador num número só: zonas (de 1 a 7, em ordem) + 10 x direita (de 8 a 10,
-- em ordem entre eles). É o que as funções de terreno recebem em p_zonas.
create or replace function public.fazenda_terrenos(p_zonas int, p_direita int)
returns int language sql immutable as $$
  select coalesce(p_zonas, 0) + 10 * coalesce(p_direita, 0);
$$;
create or replace function public.fazenda_zona_minha(p_n int, p_terrenos int)
returns boolean language sql immutable as $$
  select case when p_n <= 7 then p_n <= p_terrenos % 10 else p_n - 7 <= p_terrenos / 10 end;
$$;

-- (x, y) fica dentro do terreno de quem já comprou p_zonas terrenos?
create or replace function public.fazenda_no_terreno(p_zonas int, p_x int, p_y int)
returns boolean language sql immutable as $$
  select (p_x between 0 and 21 and p_y between 0 and 12)
      or exists (select 1 from jsonb_array_elements(fazenda_zonas()) z
                  where fazenda_zona_minha((z->>'n')::int, p_zonas)   -- (fase 78: p_zonas = fazenda_terrenos)
                    and p_x >= (z->>'x')::int and p_x < (z->>'x')::int + (z->>'w')::int
                    and p_y >= (z->>'y')::int and p_y < (z->>'y')::int + (z->>'h')::int);
$$;

-- Quantos canteiros o jogador pode ter: +2 por nível até o 25 e o que cada terreno comprado dá
-- (6 nos três primeiros, 10 a 12 nos grandes; igual a limiteCanteirosNivel em fazenda.js)
-- Fase 40: quantas construções cabem na fazenda (cerca, caminho, cano, enfeite, máquina...):
-- 250 e mais 150 a cada terreno comprado (antes era 200 fixo, pouco para o mapa grande e os canos).
-- Igual a maxConstrucoes em fazenda.js.
create or replace function public.fazenda_max_construcoes(p_zonas int)
returns int language sql immutable as $$
  select 250 + 150 * greatest(coalesce(p_zonas, 0) % 10 + coalesce(p_zonas, 0) / 10, 0);   -- (fase 78: os da direita também)
$$;

-- fase 69: +2 por nível até o último (era até o 25: o limite parava em 54)
create or replace function public.fazenda_limite_canteiros(p_nivel int, p_zonas int)
returns int language sql immutable as $$
  select least(6 + (p_nivel - 1) * 2, 94)
       + coalesce((select sum(coalesce((z->>'canteiros')::int, 6))::int from jsonb_array_elements(fazenda_zonas()) z
                    where fazenda_zona_minha((z->>'n')::int, p_zonas)), 0);
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
  select 50 + coalesce(sum(case c.tipo when 'bateria' then 150 when 'supercap' then 800 else 0 end), 0)::int
    from fazenda_construcoes c where c.jogador_id = p_jogador;
$$;

-- Fase 36: o dia e a noite do jogo. Em cada 24 h, 12 h de dia e 12 h de noite, se revezando
-- de 2 em 2 horas no relógio de Brasília (UTC-3): dia das 0h às 2h, noite das 2h às 4h, dia das
-- 4h às 6h... Igual a faseDoDia em fazenda-arte.js (que também escurece o mapa).
create or replace function public.fazenda_dia_em(p_t timestamptz)
returns boolean language sql immutable as $$
  select floor((extract(epoch from p_t) / 60 - 180) / 120)::bigint % 2 = 0;
$$;
-- quando o bloco de 2 h (dia ou noite) de p_t termina
create or replace function public.fazenda_dia_fim(p_t timestamptz)
returns timestamptz language sql immutable as $$
  select to_timestamp(((floor((extract(epoch from p_t) / 60 - 180) / 120) + 1) * 120 + 180) * 60);
$$;

-- ⚡ por hora que sol, vento e reator geram num momento (o painel solar só de dia: fazenda_dia_em)
-- Fase 48: calmaria. Em blocos de 72 min do dia (duas fatias de 36 min do clima, então a conta da
-- energia fecha nas mesmas fronteiras), uns 25% ficam sem vento; nunca na ventania nem na chuva
create or replace function public.fazenda_vento_calmo(p_t timestamptz)
returns boolean language sql stable as $$
  select fazenda_clima_em(p_t) not in ('vento', 'chuva')
     and ('x' || substr(md5(l::date::text || ':' || ((extract(hour from l)::int * 60 + extract(minute from l)::int) / 72)::text), 1, 4))::bit(16)::int % 4 = 0
    from (select p_t at time zone 'America/Sao_Paulo' as l) x;
$$;

-- Fase 48: a calmaria de agora (até quando) e a próxima nas próximas 24 h, para o jogo avisar
create or replace function public.fazenda_vento_previsao(p_t timestamptz)
returns jsonb language sql stable as $$
  with b as (
    select g as ini
      from generate_series(
             (date_trunc('day', p_t at time zone 'America/Sao_Paulo')
               + make_interval(mins => ((extract(hour from p_t at time zone 'America/Sao_Paulo')::int * 60
                                         + extract(minute from p_t at time zone 'America/Sao_Paulo')::int) / 72) * 72)) at time zone 'America/Sao_Paulo',
             p_t + interval '24 hours', interval '72 minutes') g)
  select jsonb_build_object(
    'calmo', fazenda_vento_calmo(p_t),
    'muda_em', (select min(ini) from b where ini > p_t),
    'proxima', (select min(ini) from b where ini > p_t and fazenda_vento_calmo(ini + interval '1 minute')));
$$;

-- Fase 77: tempestade e furacão, por cima da chuva e da ventania. Alguns pedaços de 36 min do clima
-- (os mesmos para todo mundo) viram tempestade com raios (1 em 4 dos de chuva; no inverno, nevasca) ou
-- furacão (1 em 6 dos de ventania). O clima de baixo continua valendo: a tempestade rega como a chuva e o
-- furacão espalha pragas como a ventania. Os estragos ficam em fazenda_tempestade (seção da fase 77).
alter table public.fazenda_construcoes add column if not exists sobrecarga_em timestamptz;   -- fase 77: parado até o conserto

create or replace function public.fazenda_extremo_regras()
returns jsonb language sql immutable as $$
  select '{"tempestade": 4, "furacao": 6, "chance": 250, "nivel": 5, "conserto_pct": 20,
           "eletricista_min": [60, 40, 25, 15, 10], "fatias_max": 80}'::jsonb;
$$;

-- o clima extremo de um momento, dado o clima de baixo: null, 'tempestade' ou 'furacao'
create or replace function public.fazenda_extremo_de(p_t timestamptz, p_clima text)
returns text language sql stable as $$
  select case
    when coalesce(current_setting('fazenda.extremo_teste', true), '') <> '' then nullif(current_setting('fazenda.extremo_teste', true), 'nenhum')
    when p_clima = 'chuva' and ('x' || substr(x.h, 1, 4))::bit(16)::int % (fazenda_extremo_regras()->>'tempestade')::int = 0 then 'tempestade'
    when p_clima = 'vento' and ('x' || substr(x.h, 5, 4))::bit(16)::int % (fazenda_extremo_regras()->>'furacao')::int = 0 then 'furacao'
  end
  from (select md5('extremo:' || floor(extract(epoch from p_t) / 2160)::bigint) as h) x;   -- o pedaço de 36 min
$$;

create or replace function public.fazenda_extremo_em(p_t timestamptz)
returns text language sql stable as $$
  select fazenda_extremo_de(p_t, fazenda_clima_em(p_t));
$$;

-- ⚡ por hora de cada gerador num momento (fase 77: uma conta só, para a taxa e para a média). Na
-- tempestade o sol some e a turbina gira forte; no furacão, a turbina gira no máximo.
create or replace function public.fazenda_gera_em(p_t timestamptz)
returns table (solar real, eolica real, reator real) language sql stable as $$
  select (case when not fazenda_dia_em(p_t) then 0
               when x.e = 'tempestade' then 2 when x.e = 'furacao' then 3
               else case x.c when 'sol' then 12 when 'calor' then 14 when 'vento' then 10 when 'nublado' then 5 else 3 end end)::real,
         (case when x.e = 'tempestade' then 20 when x.e = 'furacao' then 40
               when fazenda_vento_calmo(p_t) then 3   -- fase 48: calmaria
               else case x.c when 'vento' then 30 when 'chuva' then 14 when 'nublado' then 10 when 'sol' then 8 else 5 end end)::real,
         (case x.c when 'calor' then 500 else 700 end)::real   -- fase 75: era 120 (80 no calor)
    from (select y.c, fazenda_extremo_de(p_t, y.c) as e from (select fazenda_clima_em(p_t) as c) y) x;
$$;

-- fase 78: a pequena central hidrelétrica, ⚡ por hora (o rio baixa na onda de calor)
create or replace function public.fazenda_hidro_em(p_t timestamptz)
returns real language sql stable as $$
  select case fazenda_clima_em(p_t) when 'calor' then 80 else 120 end::real;
$$;

-- fase 81: quantas luzes ficam acesas de noite (a casa da fazenda + casinhas + lampiões); de dia, 0
create or replace function public.fazenda_luzes_noite(p_jogador uuid, p_t timestamptz)
returns int language sql stable security definer set search_path = public as $$
  select case when fazenda_dia_em(p_t) then 0
              else 1 + (select count(*) from fazenda_construcoes c
                         where c.jogador_id = p_jogador and c.tipo in ('casa_vermelha', 'casa_azul', 'lampiao'))::int end;
$$;

create or replace function public.fazenda_energia_taxa(p_jogador uuid, p_t timestamptz)
returns real language sql stable security definer set search_path = public as $$
  select coalesce(sum(case i.efeito when 'solar' then g.solar when 'eolica' then g.eolica when 'reator' then g.reator when 'hidro' then fazenda_hidro_em(p_t) else 0 end), 0)::real
         -- fase 47: cada alarme gasta ⚡ por hora (a conta só roda para quem tem energia elétrica); fase 81: 5 (era 1)
         - 5 * (select count(*) from fazenda_construcoes a where a.jogador_id = p_jogador and a.tipo = 'alarme')::real
         -- fase 81: de noite, cada luz gasta 1 ⚡ por hora: a casa da fazenda, as casinhas e os lampiões
         - fazenda_luzes_noite(p_jogador, p_t)::real
    from fazenda_construcoes c
    join fazenda_itens i on i.id = c.tipo
    cross join fazenda_gera_em(p_t) g
   where c.jogador_id = p_jogador and i.efeito in ('solar', 'eolica', 'reator', 'hidro')
     and c.sobrecarga_em is null;   -- fase 77: em sobrecarga, parado até o conserto
$$;

-- Fase 47: o alarme funciona? Sem nada elétrico na fazenda ele é o de sempre (de graça); com
-- energia elétrica, ele gasta 1 ⚡ por hora (fazenda_energia_taxa) e desliga com a bateria zerada.
create or replace function public.fazenda_alarme_ligado(p_jogador uuid)
returns boolean
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if not exists (select 1 from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
                  where c.jogador_id = p_jogador and i.categoria = 'energia') then
    return true;
  end if;
  return fazenda_energia_atualizar(p_jogador) >= 1;
end;
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
  -- fase 53: conta banida pelos admins não entra (nenhuma chamada passa daqui)
  if exists (select 1 from fazenda_jogadores where id = v_id and banido_em is not null) then
    raise exception 'conta_banida';
  end if;
  -- fase 70: uma chamada de cada vez por jogador (a próxima espera esta terminar). Chamadas juntas
  -- duplicavam o baú, pagavam a conquista e o presente do nível duas vezes e furavam os limites do dia.
  perform pg_advisory_xact_lock(7070, hashtext(v_id::text));
  -- fase 63: a semana do evento virou (sexta 22h)? a primeira chamada fecha, premia e abre a nova
  -- (fase 70: antes de gravar o visto_em, para não segurar a linha do jogador enquanto espera o fechamento;
  -- fase 71: sem fila: só uma chamada tenta, as outras seguem; o relógio do banco também fecha)
  perform fazenda_semana_tentar_fechar();
  -- visto_em só serve para "jogou nos últimos 30 dias": grava no máximo 1 vez por hora
  -- (cada chamada gravando pesava no orçamento de disco do Supabase)
  update fazenda_jogadores set visto_em = now() where id = v_id and visto_em < now() - interval '1 hour';
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
  if fazenda_clima_agora() = 'chuva' then   -- (fase 71: uma conta por chamada)
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
      -- o aspersor elétrico evita qualquer um, gastando 2 ⚡
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

-- Fase 49: as metas de cada nível = tudo o que ele libera: construir cada oficina, máquina, coisa de
-- energia, cercado e árvore do pomar (e o baú); ter cada bicho; contratar cada ajudante; comprar cada
-- terreno; e ocupar todos os canteiros do nível. Vêm as do nível de agora e as que ficaram para trás.
create or replace function public.fazenda_metas(p_jogador uuid, p_nivel int)
returns jsonb language sql stable security definer set search_path = public as $$
  with j as (select fazenda_terrenos(zonas, direita) as ter from fazenda_jogadores where id = p_jogador),
       mx as (select fazenda_limite_canteiros(p_nivel, (select ter from j)) as max,
                     (select count(*) from fazenda_canteiros where jogador_id = p_jogador)::int as tem)
  select coalesce(jsonb_agg(m order by (m->>'nivel')::int, m->>'tipo', m->>'id'), '[]'::jsonb) from (
    select jsonb_build_object('tipo', 'construir', 'id', i.id, 'nivel', i.nivel_min,
             'feito', exists (select 1 from fazenda_construcoes c where c.jogador_id = p_jogador and c.tipo = i.id)) as m
      from fazenda_itens i
     where i.nivel_min <= p_nivel and (i.categoria in ('oficina', 'maquina', 'energia', 'bichos', 'pomar') or i.id = 'bau')
    union all
    select jsonb_build_object('tipo', 'bicho', 'id', t.id, 'nivel', t.nivel_min,
             'feito', exists (select 1 from fazenda_animais a where a.jogador_id = p_jogador and a.tipo = t.id))
      from fazenda_animais_tipos t where t.nivel_min <= p_nivel
    union all
    select jsonb_build_object('tipo', 'ajudante', 'id', h.id, 'nivel', h.nivel_min,
             'feito', exists (select 1 from fazenda_ajudantes a where a.jogador_id = p_jogador and a.tipo = h.id))
      from fazenda_ajudantes_tipos h where h.nivel_min <= p_nivel
    union all
    select jsonb_build_object('tipo', 'terreno', 'id', z->>'n', 'nivel', (z->>'nivel')::int,
             'feito', fazenda_zona_minha((z->>'n')::int, (select ter from j)))
      from jsonb_array_elements(fazenda_zonas()) z where (z->>'nivel')::int <= p_nivel
    union all
    select jsonb_build_object('tipo', 'canteiros', 'id', 'canteiros', 'nivel', p_nivel,
             'feito', mx.tem >= mx.max, 'tem', mx.tem, 'max', mx.max)
      from mx
  ) x;
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
  v_max := fazenda_limite_canteiros(v_nivel, fazenda_terrenos(j.zonas, j.direita));
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
      'max_construcoes', fazenda_max_construcoes(fazenda_terrenos(j.zonas, j.direita)),
      'zonas', j.zonas,
      'direita', j.direita,   -- fase 78: os terrenos da direita
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
      'desde', j.lago_em, 'intervalo', 1800, 'max', fazenda_cesto_max(p_jogador),
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
                                          'estoque', estoque, 'prontos', prontos, 'pago', pago,   -- fase 72: pago
                                          'sobrecarga_em', sobrecarga_em))   -- fase 77: parado até o conserto
        from fazenda_construcoes where jogador_id = p_jogador), '[]'::jsonb),
    'estoque_max', fazenda_estoque_max_de(p_jogador),   -- fase 82: 15 com a fila de diamante
    -- fase 83: o alarme sem energia (o total de segundos desligado) e o resumo dos últimos 7 dias do
    -- que os vizinhos fizeram aqui (o jogo mostra o que é novo desde a última vez)
    'social', jsonb_build_object(   -- (fase 83: num objeto só: o estado chegou no limite de 100 argumentos)
      'alarme_off', jsonb_build_object('seg', j.alarme_off_seg, 'em', j.alarme_off_em),
      'raros_semana', fazenda_raros_semana(p_jogador),   -- fase 84
      'vizinhos_resumo', coalesce((select jsonb_agg(jsonb_build_object('apelido', x.apelido, 'tipo', x.tipo, 'qtd', x.qtd, 'em', x.em) order by x.em desc)
        from (select a.apelido, v.tipo, sum(v.qtd)::int as qtd, max(v.criado_em) as em
                from fazenda_visitas v join fazenda_jogadores a on a.id = v.ator_id
               where v.dono_id = p_jogador and v.criado_em > now() - interval '7 days'
               group by a.apelido, v.tipo order by max(v.criado_em) desc limit 30) x), '[]'::jsonb),
      -- fase 83: a sequência de vizinhos ajudados (zera 10 min depois da última ajuda)
      'sequencia', case when j.seq_em > now() - interval '10 minutes' then jsonb_build_object(
                   'n', cardinality(j.seq_donos), 'bonus', fazenda_sequencia_bonus(cardinality(j.seq_donos)),
                   'ate', j.seq_em + interval '10 minutes') end),
    'oficina_niveis', jsonb_build_object('regras', fazenda_oficina_niveis(),
                        'tem', coalesce((select jsonb_object_agg(tipo, nivel) from fazenda_oficina_nivel where jogador_id = p_jogador), '{}'::jsonb)),
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
    -- fase 77: o que a tempestade e o furacão fizeram (e o que o eletricista consertou), ainda não visto
    'clima_eventos', coalesce((select jsonb_agg(jsonb_build_object('evento', e.evento, 'clima', e.clima, 'item', e.item, 'x', e.x, 'y', e.y, 'em', e.em) order by e.id)
                                 from fazenda_clima_eventos e where e.jogador_id = p_jogador and not e.visto), '[]'::jsonb),
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
  update fazenda_clima_eventos set visto = true where jogador_id = p_jogador and not visto;   -- e o raio e o furacão (fase 77)
  return v_json;
end;
$$;

-- Aplica uma ação em um canteiro. Retorna a quantidade colhida (0 se não colheu).
drop function if exists public.fazenda_aplicar(uuid, text, int, text);
-- p_bot = feita por um ajudante (sem XP, sem missão, sem moeda de "cuidar")
-- Fase 41: colher volta a dar o XP cheio de cada planta em qualquer nível (a regra da fase 35,
-- que tirava XP das plantas fáceis, saiu). Contra a alface de 2 min virar fábrica de XP, o mesmo
-- canteiro dá XP de colheita no máximo uma vez a cada 8 minutos (canteiros.xp_em).
drop function if exists public.fazenda_xp_planta(int, int);

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
  v_xp_colheita boolean;
  v_tarde  boolean := false;
  v_preco  int;   -- fase 72
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

  -- fase 48: o ajudante que colhe trabalha "atrasado" quando a fazenda estava fechada: o que murchou
  -- depois da última olhada dele, ele teria colhido a tempo (só para ajudante)
  if p_acao = 'colher_tarde' then
    if not p_bot then raise exception 'acao_invalida'; end if;
    v_tarde := true;
    p_acao := 'colher';
  end if;

  -- colher agora (fase 31): diamante deixa pronto na hora o que está crescendo, sem os
  -- problemas, e já colhe. Maduro não precisa de diamante: só colhe.
  -- fase 72: 1 diamante a cada 4 h que faltam (era 1 por planta: caro na alface, barato na baunilha)
  if p_acao = 'agora' then
    if p_bot then raise exception 'acao_invalida'; end if;
    if c.estado <> 'plantado' or now() >= v_murcho then raise exception 'nada_a_fazer'; end if;
    if now() < v_maduro then
      v_preco := greatest(1, ceil(extract(epoch from v_maduro - now())
                                  / (3600 * (fazenda_loja_diamantes()->'agora'->>'horas')::numeric)))::int;
      if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
      update fazenda_jogadores set diamantes = diamantes - v_preco where id = p_jogador;
      c.erva := false; c.praga := false; c.seco := false;
      v_maduro := now();
      v_murcho := now() + make_interval(secs => greatest(k.tempo_seg * 2, 3600));
    end if;
    p_acao := 'colher';
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
    -- arar só dá XP para quem está começando (até o nível 5): senão alface de 2 min vira fábrica de XP
    -- (fase 70: o XP de arar e plantar da fazenda completa vem na colheita: arar, desmanchar e fazer o
    -- canteiro de novo virava XP sem fim)
    if not p_bot and fazenda_nivel(j.xp) <= 5 then update fazenda_jogadores set xp = xp + 1 where id = p_jogador; end if;

  elsif p_acao = 'arrancar' then   -- o jogador tira o que está plantado (perde a planta) para plantar outra coisa
    if p_bot then raise exception 'acao_invalida'; end if;
    if c.estado <> 'plantado' then raise exception 'nada_a_fazer'; end if;
    update fazenda_canteiros
       set estado = 'arado', cultura = null, plantado_em = null,
           erva = false, praga = false, seco = false, roubado = 0, prox_evento = null, adubado = false
     where jogador_id = p_jogador and posicao = p_posicao;

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
                           (0.1 * fazenda_protegido(p_jogador, 'crescer', c.x, c.y)::int + 0.25 * v_estufa::int
                            + fazenda_melhoria(p_jogador, 'adubo'))),   -- fase 57: adubo premium
           erva = false, praga = false, seco = false, roubado = 0, adubado = false,
           prox_evento = now() + make_interval(secs => k.tempo_seg * (0.15 + random() * 0.35))
     where jogador_id = p_jogador and posicao = p_posicao;
    if not p_bot then
      perform fazenda_missao(p_jogador, 'plantar', 1);
      -- fase 57: fazenda completa: plantar também dá XP (fase 70: ele vem na colheita; plantar e arrancar
      -- em seguida virava XP sem fim)
      update fazenda_jogadores set semente = k.id where id = p_jogador;
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
    if now() >= v_murcho and not v_tarde then
      raise exception 'murchou';
    end if;
    -- cada problema não resolvido custa 1 unidade; o que os vizinhos pegaram também sai
    v_qtd := greatest(k.rendimento - (c.erva::int + c.praga::int + c.seco::int) - c.roubado, 1)
             + fazenda_tem_efeito(p_jogador, 'colheita')::int          -- colheitadeira
             + (fazenda_clima_agora() = 'sol')::int                      -- colheita no sol (fase 71: uma conta por chamada)
             + fazenda_protegido(p_jogador, 'adubo', c.x, c.y)::int     -- cogumelos, barril, colmeia
             + c.adubado::int;                                          -- adubo do Seu Zé
    if fazenda_protegido(p_jogador, 'sorte', c.x, c.y) and random() < 0.15 then
      v_qtd := v_qtd * 2;                                               -- alvo
    end if;
    insert into fazenda_celeiro (jogador_id, item, quantidade)
    values (p_jogador, k.id, v_qtd)
    on conflict (jogador_id, item)
    do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
    -- XP cheio da planta, mas o mesmo canteiro dá XP no máximo 1 vez a cada 8 min (fase 41)
    -- fase 72: o que ajudante, robô ou baú colhe dá metade do XP (antes, nada), somado e gravado uma
    -- vez só no fim da rodada deles (fazenda_bot_xp)
    v_xp_colheita := c.xp_em is null or c.xp_em <= now() - interval '8 minutes';
    if v_xp_colheita and p_bot then
      perform fazenda_bot_xp(p_jogador, k.xp / 2);
    elsif v_xp_colheita then
      -- fase 70: fazenda completa: + 2 (o XP de arar e plantar, que antes vinha na hora)
      update fazenda_jogadores set xp = xp + k.xp + fazenda_protegido(p_jogador, 'xp', c.x, c.y)::int + 2 * fazenda_completa(p_jogador)::int
       where id = p_jogador;
    end if;
    update fazenda_canteiros   -- com trator, o canteiro já fica arado
       set estado = case when fazenda_tem_efeito(p_jogador, 'arar') then 'arado' else 'vazio' end,
           cultura = null, plantado_em = null,
           erva = false, praga = false, seco = false, roubado = 0, prox_evento = null, adubado = false,
           xp_em = case when v_xp_colheita then now() else xp_em end
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
  v_ip     text;   -- fase 70
begin
  p_apelido := btrim(p_apelido);
  if p_apelido is null or char_length(p_apelido) not between 2 and 20 then
    raise exception 'apelido_invalido';
  end if;

  -- Freio contra spam: no máximo 300 fazendas novas por hora no total
  if (select count(*) from fazenda_jogadores where criado_em > now() - interval '1 hour') >= 300 then
    raise exception 'muitas_fazendas';
  end if;
  -- fase 70: e 5 por hora (20 por dia) do mesmo endereço
  v_ip := fazenda_ip();
  if v_ip is not null and (
       (select count(*) from fazenda_tentativas where tipo = 'criar' and ip = v_ip and em > now() - interval '1 hour') >= 5
    or (select count(*) from fazenda_tentativas where tipo = 'criar' and ip = v_ip and em > now() - interval '1 day') >= 20) then
    raise exception 'muitas_fazendas_ip';
  end if;
  delete from fazenda_tentativas where em < now() - interval '2 days';
  if v_ip is not null then insert into fazenda_tentativas (ip, tipo) values (v_ip, 'criar'); end if;

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
  -- fase 54: e com um lampião aceso do lado da casa (quem começa de noite não fica no escuro)
  insert into fazenda_construcoes (jogador_id, x, y, tipo, colhido_em) values (v_id, 8, 3, 'lampiao', now());
  update fazenda_jogadores set ganhou_poste = true where id = v_id;

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
  v_ip text := fazenda_ip();   -- fase 70
begin
  -- fase 70: código errado tem limite: 10 por hora do mesmo endereço e 2000 por hora no total (sem isso
  -- dava para ir chutando códigos até achar a fazenda de alguém)
  if (select count(*) from fazenda_tentativas where tipo = 'recuperar' and em > now() - interval '1 hour') >= 2000
     or (v_ip is not null
         and (select count(*) from fazenda_tentativas where tipo = 'recuperar' and ip = v_ip and em > now() - interval '1 hour') >= 10) then
    raise exception 'muitas_tentativas';
  end if;
  p_codigo := upper(regexp_replace(coalesce(p_codigo, ''), '\s', '', 'g'));
  select id into v_id from fazenda_jogadores
   where codigo_hash = encode(digest(p_codigo, 'sha256'), 'hex');
  if v_id is null then
    -- o erro volta sem "raise" (que desfaria a anotação da tentativa): status 400 e a mensagem
    delete from fazenda_tentativas where em < now() - interval '2 days';
    insert into fazenda_tentativas (ip, tipo) values (coalesce(v_ip, '?'), 'recuperar');
    perform set_config('response.status', '400', true);
    return jsonb_build_object('code', 'P0001', 'message', 'codigo_invalido');
  end if;
  if exists (select 1 from fazenda_jogadores where id = v_id and banido_em is not null) then raise exception 'conta_banida'; end if;
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
  v_moedas int := 0;
  v_taxa   real;
  v_seg    real;
  v_zero   real := 0;    -- fase 83: segundos com a bateria zerada (alarme desligado)
  v_alarme boolean;
begin
  select energia, energia_em into j from fazenda_jogadores where id = p_jogador for update;
  if j.energia_em is not null and j.energia_em >= now() then
    return j.energia;                                   -- já fez a conta nesta chamada
  end if;
  if not exists (select 1 from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
                  where c.jogador_id = p_jogador and i.categoria = 'energia') then
    -- fase 46: sem máquina não tem o que contar: grava a hora no máximo de hora em hora (a primeira
    -- máquina acerta a hora em fazenda_construir)
    if j.energia_em is null or j.energia_em < now() - interval '1 hour' then
      update fazenda_jogadores set energia_em = now() where id = p_jogador;
    end if;
    return j.energia;
  end if;
  v_cap := fazenda_capacidade(p_jogador);
  v_e := j.energia;
  v_t := greatest(coalesce(j.energia_em, now()), now() - interval '12 hours');
  while v_t < now() loop
    -- fatia até a próxima troca de clima (36 min) ou de dia/noite (2 h), o que vier antes
    v_prox := least(date_trunc('minute', v_t) + make_interval(mins => 36 - fazenda_minuto_semana(v_t) % 36),
                    fazenda_dia_fim(v_t), now());
    v_taxa := fazenda_energia_taxa(p_jogador, v_t);
    v_seg := extract(epoch from v_prox - v_t)::real;
    -- fase 83: a bateria não fica abaixo de zero no meio da conta (antes a falta da noite comia o sol do
    -- dia seguinte), e o tempo zerada é guardado: é o tempo com o alarme desligado
    if v_taxa < 0 and v_e + v_taxa * v_seg / 3600 < 0 then
      v_zero := v_zero + v_seg - greatest(v_e, 0) / (-v_taxa) * 3600;
      v_e := 0;
    else
      v_e := v_e + v_taxa * v_seg / 3600;
    end if;
    v_t := v_prox;
  end loop;
  -- fase 48: bateria cheia, a sobra do sol, do vento e do reator é vendida (1 moeda a cada 5 ⚡)
  v_moedas := floor(greatest(v_e - v_cap, 0) / 5)::int;
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
  v_alarme := v_zero > 1 and exists (select 1 from fazenda_construcoes where jogador_id = p_jogador and tipo = 'alarme');
  update fazenda_jogadores set energia = v_e, energia_em = now(), moedas = moedas + v_moedas,
         alarme_off_seg = alarme_off_seg + case when v_alarme then round(v_zero)::bigint else 0 end,
         alarme_off_em = case when v_alarme then now() else alarme_off_em end
   where id = p_jogador;
  return v_e;
end;
$$;

-- Gasta energia se tiver o bastante (senão não gasta nada e devolve false)
-- Fase 43: quanto custa de verdade (o eletricista contratado baixa 20% / 35% / 50%)
-- Fase 56: tudo gasta menos; soma com o eletricista. Fase 57: 20% (0,8 de cada valor escrito nas
-- máquinas; a 56 tinha posto 40%, barato demais para valer a pena ter tudo). Em troca, painel solar e
-- turbina sobem de limite com o nível (fazenda_limite_maquina). As descrições mostram o valor novo.
create or replace function public.fazenda_energia_preco(p_jogador uuid, p_qtd real)
returns real language sql stable security definer set search_path = public as $$
  select (p_qtd * 0.8 * coalesce((select case h.nivel when 1 then 0.8 when 2 then 0.65 when 3 then 0.5 when 4 then 0.4 else 0.33 end   -- fase 74: 4 e 5
                              from fazenda_ajudantes h join fazenda_ajudantes_tipos t on t.id = h.tipo
                             where h.jogador_id = p_jogador and t.funcao = 'energia' limit 1), 1))::real;
$$;

create or replace function public.fazenda_gastar_energia(p_jogador uuid, p_qtd real)
returns boolean
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_qtd real := fazenda_energia_preco(p_jogador, p_qtd);
begin
  if fazenda_energia_atualizar(p_jogador) < v_qtd then
    return false;
  end if;
  update fazenda_jogadores set energia = energia - v_qtd, energia_gasta = energia_gasta + v_qtd where id = p_jogador;
  return true;
end;
$$;

-- Tem aspersor elétrico com energia cobrindo (x, y)? Gasta 2 ⚡ por problema evitado (fase 43; era 1).
create or replace function public.fazenda_aspersor(p_jogador uuid, p_x int, p_y int)
returns boolean
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if not fazenda_protegido(p_jogador, 'aspersor', p_x, p_y) then
    return false;
  end if;
  return fazenda_gastar_energia(p_jogador, 2);
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

-- ------------------------------------------------------------
-- Fase 39: a rede de verdade. Cada baú guarda o que recolhe (canteiros, cercados, árvores do
-- pomar e o cesto do lago). Canos encostados uns nos outros formam uma rede; baús, oficinas, o
-- celeiro e a fábrica automática encostados num cano dela fazem parte dela. Nada anda sem estar
-- ligado: a oficina busca os ingredientes nos baús e no celeiro da rede; o produto vai para outra
-- oficina da rede que usa ele, para o celeiro ou para um baú; e o que sobra num baú (o que
-- nenhuma oficina da rede usa) vai para o celeiro. Cada movimento vira uma viagem com hora
-- marcada, e o jogo só mostra o item andando quando ela está acontecendo. (Antes, fase 27: a
-- oficina com qualquer cano até um canteiro, baú ou o celeiro puxava do celeiro geral.)
-- Igual a redeCanos em fazenda.js.
-- ------------------------------------------------------------
create table if not exists public.fazenda_bau_itens (
  jogador_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  x           smallint not null,
  y           smallint not null,
  item        text not null references public.fazenda_culturas(id),
  quantidade  int not null default 0 check (quantidade >= 0),
  primary key (jogador_id, x, y, item)
);
-- ingredientes que chegaram pelo cano numa oficina e ainda não fecham uma receita
create table if not exists public.fazenda_oficina_itens (
  jogador_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  x           smallint not null,
  y           smallint not null,
  item        text not null references public.fazenda_culturas(id),
  quantidade  int not null default 0 check (quantidade >= 0),
  primary key (jogador_id, x, y, item)
);
create table if not exists public.fazenda_viagens (
  id          bigserial primary key,
  jogador_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  item        text not null,
  qtd         int not null,
  de_x        smallint, de_y smallint,       -- null = celeiro
  para_x      smallint, para_y smallint,     -- null = celeiro
  direto      boolean not null default false, -- sem cano: do canteiro, cercado, árvore ou lago para o baú encostado
  em          timestamptz not null default now()
);
create index if not exists fazenda_viagens_jogador on public.fazenda_viagens (jogador_id, em);
-- Fase 44: quando a viagem foi criada (o jogo mostra as novas, mesmo as com hora marcada antes)
alter table public.fazenda_viagens add column if not exists criada_em timestamptz not null default now();
create index if not exists fazenda_viagens_criada on public.fazenda_viagens (jogador_id, criada_em);
alter table public.fazenda_bau_itens enable row level security;
alter table public.fazenda_oficina_itens enable row level security;
alter table public.fazenda_viagens enable row level security;
revoke all on public.fazenda_bau_itens, public.fazenda_oficina_itens, public.fazenda_viagens from anon, authenticated;
drop function if exists public.fazenda_oficina_ligada(uuid, int, int, int, int);

-- Quanto ainda cabe num baú (200 itens ao todo)
create or replace function public.fazenda_bau_livre(p_jogador uuid, p_x int, p_y int)
returns int language sql stable security definer set search_path = public as $$
  select 200 - coalesce(sum(quantidade), 0)::int from fazenda_bau_itens where jogador_id = p_jogador and x = p_x and y = p_y;
$$;

-- Uma viagem de item. O que acontece agora se espalha pelos próximos 15 s, para não sair tudo junto.
create or replace function public.fazenda_viagem(p_jogador uuid, p_item text, p_qtd int, p_de_x int, p_de_y int,
                                                 p_para_x int, p_para_y int, p_direto boolean, p_em timestamptz)
returns void language sql security definer set search_path = public as $$
  insert into fazenda_viagens (jogador_id, item, qtd, de_x, de_y, para_x, para_y, direto, em)
  values (p_jogador, p_item, p_qtd, p_de_x, p_de_y, p_para_x, p_para_y, p_direto,
          p_em + case when p_em >= now() - interval '1 second' then random() * interval '15 seconds' else interval '0' end);
$$;

-- O que acabou de chegar no celeiro (colheita, coleta de bicho) passa para o baú encostado
create or replace function public.fazenda_bau_guardar(p_jogador uuid, p_x int, p_y int, p_item text, p_qtd int, p_de_x int, p_de_y int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if coalesce(p_qtd, 0) <= 0 then return; end if;
  update fazenda_celeiro set quantidade = quantidade - p_qtd where jogador_id = p_jogador and item = p_item;
  insert into fazenda_bau_itens (jogador_id, x, y, item, quantidade) values (p_jogador, p_x, p_y, p_item, p_qtd)
  on conflict (jogador_id, x, y, item) do update set quantidade = fazenda_bau_itens.quantidade + excluded.quantidade;
  perform fazenda_viagem(p_jogador, p_item, p_qtd, p_de_x, p_de_y, p_x, p_y, true, now());
end;
$$;

-- As redes: cada grupo de canos encostados é uma rede (o número é o do primeiro cano, o menor
-- x*100+y), e as coisas encostadas num cano dela fazem parte dela. papel: bau, oficina ou celeiro
-- (o celeiro do mapa, x 1..3 e y 1..6, e a fábrica automática, que leva e traz do celeiro de
-- qualquer lugar).
-- Fase 52: era um recursivo que ligava cada cano a todos os da rede (com 200 canos, 40 mil pares,
-- em todo carregamento e ação: o que mais gastava o banco). Agora uma busca em largura que passa
-- uma vez por cano; o resultado é o mesmo.
create or replace function public.fazenda_rede(p_jogador uuid)
returns table (rede int, papel text, x int, y int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_lbl  int[] := array_fill(-2, array[10000], array[0]);   -- k = x*100+y: -2 sem cano, -1 cano sem rede, senão a rede
  v_ks   int[];
  v_fila int[];
  v_i    int;
  v_k    int;
  v_n    int;
  v_viz  int;
begin
  select coalesce(array_agg(c.x * 100 + c.y order by c.x * 100 + c.y), '{}') into v_ks
    from fazenda_construcoes c
   where c.jogador_id = p_jogador and c.tipo = 'cano' and c.x between 0 and 99 and c.y between 0 and 99;
  foreach v_k in array v_ks loop v_lbl[v_k] := -1; end loop;
  -- do menor cano para o maior: quem começa uma rede é o menor dela
  foreach v_k in array v_ks loop
    continue when v_lbl[v_k] <> -1;
    v_lbl[v_k] := v_k;
    v_fila := array[v_k];
    v_i := 1;
    while v_i <= cardinality(v_fila) loop
      v_n := v_fila[v_i];
      v_i := v_i + 1;
      foreach v_viz in array array[v_n + 100, v_n - 100, v_n + 1, v_n - 1] loop
        if v_viz between 0 and 9999 and v_lbl[v_viz] = -1 then
          v_lbl[v_viz] := v_k;
          v_fila := v_fila || v_viz;
        end if;
      end loop;
    end loop;
  end loop;
  return query
  with cano as (select u.k / 100 as x, u.k % 100 as y, v_lbl[u.k] as rede from unnest(v_ks) u(k)),
  coisas as (
    select c.x, c.y, i.largura as w, i.altura as h,
           case when c.tipo = 'bau' then 'bau' when i.entradas is not null then 'oficina' else 'celeiro' end as papel
      from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
     where c.jogador_id = p_jogador and (c.tipo = 'bau' or i.entradas is not null or i.efeito = 'automatico')
    union all
    select 1, 1, 3, 6, 'celeiro')
  select distinct cano.rede::int, k.papel::text, k.x::int, k.y::int
    from coisas k join cano on
         ((cano.x = k.x - 1 or cano.x = k.x + k.w) and cano.y between k.y and k.y + k.h - 1)
      or ((cano.y = k.y - 1 or cano.y = k.y + k.h) and cano.x between k.x and k.x + k.w - 1);
end;
$$;

-- As redes em que uma coisa (papel, x, y) está, dentro da lista montada por fazenda_rede
create or replace function public.fazenda_redes_de(p_membros jsonb, p_papel text, p_x int, p_y int)
returns int[] language sql immutable as $$
  select array_agg(distinct (m->>'rede')::int) from jsonb_array_elements(p_membros) m
   where m->>'papel' = p_papel and (m->>'x')::int = p_x and (m->>'y')::int = p_y;
$$;
create or replace function public.fazenda_rede_tem_celeiro(p_membros jsonb, p_redes int[])
returns boolean language sql immutable as $$
  select coalesce(p_redes is not null and exists (select 1 from jsonb_array_elements(p_membros) m
                   where m->>'papel' = 'celeiro' and (m->>'rede')::int = any(p_redes)), false);
$$;

-- A oficina busca na rede os ingredientes de 1 receita: primeiro o que já chegou nela pelo cano,
-- depois os baús da rede e por último o celeiro (se a rede chega nele; a ração reservada fica).
-- Só tira se der a receita inteira. 2 ⚡ por receita; cada saída vira uma viagem.
create or replace function public.fazenda_rede_puxar(p_jogador uuid, p_x int, p_y int, p_entradas jsonb, p_membros jsonb, p_em timestamptz)
returns boolean
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  e       record;
  b       record;
  v_redes int[] := fazenda_redes_de(p_membros, 'oficina', p_x, p_y);
  v_cel   boolean;
  v_falta int;
  v_tira  int;
begin
  if v_redes is null then return false; end if;
  v_cel := fazenda_rede_tem_celeiro(p_membros, v_redes);
  for e in select key as item, value::int as qtd from jsonb_each_text(p_entradas) loop
    if coalesce((select quantidade from fazenda_oficina_itens where jogador_id = p_jogador and x = p_x and y = p_y and item = e.item), 0)
       + coalesce((select sum(bi.quantidade) from fazenda_bau_itens bi
                    where bi.jogador_id = p_jogador and bi.item = e.item
                      and fazenda_redes_de(p_membros, 'bau', bi.x, bi.y) && v_redes), 0)
       + (case when v_cel then greatest(coalesce((select quantidade from fazenda_celeiro where jogador_id = p_jogador and item = e.item), 0)
                                       - coalesce((select quantidade from fazenda_reservas where jogador_id = p_jogador and item = e.item), 0), 0)
               else 0 end)   -- (o case entre parênteses: senão o if do plpgsql para no primeiro then)
       < e.qtd then
      return false;
    end if;
  end loop;
  -- 2 ⚡ por receita (fase 43; na 42 foi 1): a rede enche o estoque inteiro, então pesa na energia
  if not fazenda_gastar_energia(p_jogador, 2) then return false; end if;
  for e in select key as item, value::int as qtd from jsonb_each_text(p_entradas) loop
    v_falta := e.qtd;
    select quantidade into v_tira from fazenda_oficina_itens where jogador_id = p_jogador and x = p_x and y = p_y and item = e.item for update;
    v_tira := least(coalesce(v_tira, 0), v_falta);
    if v_tira > 0 then
      update fazenda_oficina_itens set quantidade = quantidade - v_tira where jogador_id = p_jogador and x = p_x and y = p_y and item = e.item;
      v_falta := v_falta - v_tira;
    end if;
    for b in
      select bi.x, bi.y, bi.quantidade from fazenda_bau_itens bi
       where bi.jogador_id = p_jogador and bi.item = e.item and bi.quantidade > 0
         and fazenda_redes_de(p_membros, 'bau', bi.x, bi.y) && v_redes
       order by bi.quantidade desc, bi.x, bi.y
         for update
    loop
      exit when v_falta <= 0;
      v_tira := least(b.quantidade, v_falta);
      update fazenda_bau_itens set quantidade = quantidade - v_tira where jogador_id = p_jogador and x = b.x and y = b.y and item = e.item;
      perform fazenda_viagem(p_jogador, e.item, v_tira, b.x, b.y, p_x, p_y, false, p_em);
      v_falta := v_falta - v_tira;
    end loop;
    if v_falta > 0 then
      update fazenda_celeiro set quantidade = quantidade - v_falta where jogador_id = p_jogador and item = e.item;
      perform fazenda_viagem(p_jogador, e.item, v_falta, null, null, p_x, p_y, false, p_em);
    end if;
  end loop;
  return true;
end;
$$;

-- O produto pronto sai pelo cano: para outra oficina da rede que usa ele (até ela ter o bastante
-- para 2 receitas), senão para o celeiro (se a rede chega nele), senão para um baú da rede com
-- espaço. Devolve quanto saiu; o resto fica na oficina para você pegar.
create or replace function public.fazenda_rede_entregar(p_jogador uuid, p_x int, p_y int, p_item text, p_qtd int, p_membros jsonb, p_em timestamptz)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  o       record;
  b       record;
  v_redes int[] := fazenda_redes_de(p_membros, 'oficina', p_x, p_y);
  v_sai   int := 0;
  v_n     int;
begin
  if v_redes is null or coalesce(p_qtd, 0) <= 0 then return 0; end if;
  for o in
    select distinct (m->>'x')::int as x, (m->>'y')::int as y, (i.entradas->>p_item)::int as qtd
      from jsonb_array_elements(p_membros) m
      join fazenda_construcoes c on c.jogador_id = p_jogador and c.x = (m->>'x')::int and c.y = (m->>'y')::int
      join fazenda_itens i on i.id = c.tipo
     where m->>'papel' = 'oficina' and (m->>'rede')::int = any(v_redes) and i.entradas ? p_item
       and not ((m->>'x')::int = p_x and (m->>'y')::int = p_y)
  loop
    exit when v_sai >= p_qtd;
    v_n := least(greatest(2 * o.qtd - coalesce((select quantidade from fazenda_oficina_itens
                                                 where jogador_id = p_jogador and x = o.x and y = o.y and item = p_item), 0), 0),
                 p_qtd - v_sai);
    if v_n > 0 then
      insert into fazenda_oficina_itens (jogador_id, x, y, item, quantidade) values (p_jogador, o.x, o.y, p_item, v_n)
      on conflict (jogador_id, x, y, item) do update set quantidade = fazenda_oficina_itens.quantidade + excluded.quantidade;
      perform fazenda_viagem(p_jogador, p_item, v_n, p_x, p_y, o.x, o.y, false, p_em);
      v_sai := v_sai + v_n;
    end if;
  end loop;
  if v_sai < p_qtd and fazenda_rede_tem_celeiro(p_membros, v_redes) then
    insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, p_item, p_qtd - v_sai)
    on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
    perform fazenda_viagem(p_jogador, p_item, p_qtd - v_sai, p_x, p_y, null, null, false, p_em);
    v_sai := p_qtd;
  end if;
  for b in
    select distinct (m->>'x')::int as x, (m->>'y')::int as y from jsonb_array_elements(p_membros) m
     where m->>'papel' = 'bau' and (m->>'rede')::int = any(v_redes) order by 1, 2
  loop
    exit when v_sai >= p_qtd;
    v_n := least(fazenda_bau_livre(p_jogador, b.x, b.y), p_qtd - v_sai);
    if v_n > 0 then
      insert into fazenda_bau_itens (jogador_id, x, y, item, quantidade) values (p_jogador, b.x, b.y, p_item, v_n)
      on conflict (jogador_id, x, y, item) do update set quantidade = fazenda_bau_itens.quantidade + excluded.quantidade;
      perform fazenda_viagem(p_jogador, p_item, v_n, p_x, p_y, b.x, b.y, false, p_em);
      v_sai := v_sai + v_n;
    end if;
  end loop;
  return v_sai;
end;
$$;

-- O que sobra nos baús ligados ao celeiro (o que nenhuma oficina da rede usa) vai para o celeiro.
-- 2 ⚡ por viagem (um tipo de item de cada vez); sem energia, espera.
create or replace function public.fazenda_rede_descarregar(p_jogador uuid, p_membros jsonb)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  b       record;
  it      record;
  v_redes int[];
  v_q     int;   -- fase 70
begin
  for b in select distinct (m->>'x')::int as x, (m->>'y')::int as y from jsonb_array_elements(p_membros) m where m->>'papel' = 'bau' loop
    v_redes := fazenda_redes_de(p_membros, 'bau', b.x, b.y);
    continue when not fazenda_rede_tem_celeiro(p_membros, v_redes);
    for it in
      select bi.item, bi.quantidade from fazenda_bau_itens bi
       where bi.jogador_id = p_jogador and bi.x = b.x and bi.y = b.y and bi.quantidade > 0
         and not exists (
           select 1 from jsonb_array_elements(p_membros) m
             join fazenda_construcoes c on c.jogador_id = p_jogador and c.x = (m->>'x')::int and c.y = (m->>'y')::int
             join fazenda_itens i on i.id = c.tipo
            where m->>'papel' = 'oficina' and (m->>'rede')::int = any(v_redes) and i.entradas ? bi.item)
    loop
      exit when not fazenda_gastar_energia(p_jogador, 2);
      -- fase 70: tira e entrega o que estava lá de fato (o cursor podia estar velho)
      delete from fazenda_bau_itens where jogador_id = p_jogador and x = b.x and y = b.y and item = it.item
      returning quantidade into v_q;
      continue when coalesce(v_q, 0) <= 0;
      insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, it.item, v_q)
      on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
      perform fazenda_viagem(p_jogador, it.item, v_q, b.x, b.y, null, null, false, now());
    end loop;
  end loop;
end;
$$;

-- Faz as oficinas andarem até agora (roda ao carregar a fazenda e antes de mexer numa oficina)
create or replace function public.fazenda_oficinas_andar(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  o       record;
  v_tri   boolean := fazenda_tem_efeito(p_jogador, 'triturar');
  v_membros jsonb := coalesce((select jsonb_agg(to_jsonb(r)) from fazenda_rede(p_jogador) r), '[]'::jsonb);
  v_t     timestamptz;
  v_fim   timestamptz;
  v_est   int;
  v_pr    int;
  v_n     int;
  v_qtd   int;
  v_rede  boolean;
  v_volta int;
  v_puxou boolean;
begin
  for o in
    select c.x, c.y, c.iniciado_em, c.estoque, c.prontos, i.produz, i.produz_qtd, i.entradas,
           ceil(i.produz_seg * (1 - fazenda_oficina_rapidez(p_jogador, c.tipo)))::int as produz_seg   -- fase 82: nível 2 e 3
      from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
     where c.jogador_id = p_jogador and i.entradas is not null
     order by i.ordem, c.x, c.y   -- (a prensa antes do empório: o óleo chega no mesmo passo)
       for update of c
  loop
    v_t := o.iniciado_em; v_est := o.estoque; v_pr := o.prontos; v_fim := null; v_n := 0;
    v_rede := fazenda_redes_de(v_membros, 'oficina', o.x, o.y) is not null;
    -- ligou na rede agora: o que estava pronto esperando já sai pelo cano
    if v_rede and v_pr > 0 then
      v_pr := v_pr - fazenda_rede_entregar(p_jogador, o.x, o.y, o.produz, v_pr, v_membros, now());
    end if;
    loop
      exit when v_n >= 48;
      v_n := v_n + 1;
      if v_t is not null then
        exit when now() < v_t + make_interval(secs => o.produz_seg);   -- ainda trabalhando
        v_qtd := o.produz_qtd;
        v_fim := v_t + make_interval(secs => o.produz_seg);
        -- triturador (fase 72: +50% em vez do dobro, e 15 ⚡ por receita): metade de mais; com 1 por
        -- receita, uma sim, uma não (pela hora em que fica pronta: receitas emendadas se alternam)
        if v_tri and fazenda_gastar_energia(p_jogador, 15) then
          v_qtd := v_qtd + greatest(v_qtd / 2, (floor(extract(epoch from v_fim) / o.produz_seg)::bigint % 2 = 0)::int);
        end if;
        -- pronto: sai pela rede (outra oficina, celeiro ou baú); o que não sai fica para você pegar
        v_pr := v_pr + v_qtd - case when v_rede then fazenda_rede_entregar(p_jogador, o.x, o.y, o.produz, v_qtd, v_membros, v_fim) else 0 end;
        v_t := null;
      end if;
      -- estoque vazio e na rede: busca uma receita nos baús/celeiro da rede (2 ⚡, fase 43)
      if v_est <= 0 and v_rede
         and fazenda_rede_puxar(p_jogador, o.x, o.y, o.entradas, v_membros, greatest(coalesce(v_fim, now()), now() - interval '12 hours')) then
        v_est := 1;
      end if;
      exit when v_est <= 0;
      v_est := v_est - 1;
      -- emenda na receita anterior (o tempo fora vale, até 12 horas)
      v_t := greatest(coalesce(v_fim, now()), now() - interval '12 hours');
    end loop;
    -- fase 46: só grava se mudou (rodava em toda carga para toda oficina)
    if v_t is distinct from o.iniciado_em or v_est <> o.estoque or least(v_pr, 32000) <> o.prontos then
      update fazenda_construcoes set iniciado_em = v_t, estoque = v_est, prontos = least(v_pr, 32000)
       where jogador_id = p_jogador and x = o.x and y = o.y;
    end if;
  end loop;
  -- Fase 42: a rede enche o estoque das oficinas sozinha (até o máximo), uma receita por vez em
  -- rodízio, para dividir o que tem entre todas; a oficina parada que ganhou ingrediente já começa
  for v_volta in 1..fazenda_estoque_max_de(p_jogador) loop
    v_puxou := false;
    for o in
      select c.x, c.y, c.estoque, c.iniciado_em, i.entradas
        from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
       where c.jogador_id = p_jogador and i.entradas is not null
         and c.estoque + (c.iniciado_em is not null)::int < fazenda_estoque_max_de(p_jogador)
       order by i.ordem, c.x, c.y
    loop
      continue when fazenda_redes_de(v_membros, 'oficina', o.x, o.y) is null;
      if fazenda_rede_puxar(p_jogador, o.x, o.y, o.entradas, v_membros, now()) then
        update fazenda_construcoes
           set iniciado_em = coalesce(iniciado_em, now()),
               estoque = estoque + case when iniciado_em is null then 0 else 1 end
         where jogador_id = p_jogador and x = o.x and y = o.y;
        v_puxou := true;
      end if;
    end loop;
    exit when not v_puxou;
  end loop;
  perform fazenda_rede_descarregar(p_jogador, v_membros);
end;
$$;

-- Fase 29: baú coletor (precisa de energia). Encostado num bloco de canteiros (os canteiros
-- encostados uns nos outros), colhe sozinho o que amadurece; encostado num cercado, coleta o
-- produto e alimenta os bichos daquela espécie. 2 ⚡ por colheita, coleta ou ração (fase 43; era 1).
create or replace function public.fazenda_baus(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  b       record;
  k       record;
  m       record;
  arv     record;
  e       record;
  v_qtd   int;
  v_livre int;
  v_peixes jsonb;
  v_seguro boolean;   -- fase 71
begin
  for b in select x, y from fazenda_construcoes where jogador_id = p_jogador and tipo = 'bau' loop
   -- fase 71: cada baú num lote só (modo rápido); deu erro, o lote volta e é refeito no modo seguro
   for v_tent in 1..2 loop
    v_seguro := v_tent = 2;
    begin
    v_livre := fazenda_bau_livre(p_jogador, b.x, b.y);
    -- canteiros: o bloco encostado no baú (canteiros encostados uns nos outros)
    for k in
      with recursive bloco(posicao, x, y) as (
        select c.posicao, c.x, c.y from fazenda_canteiros c
         where c.jogador_id = p_jogador and abs(c.x - b.x) + abs(c.y - b.y) = 1
        union
        select c.posicao, c.x, c.y from fazenda_canteiros c join bloco o on abs(c.x - o.x) + abs(c.y - o.y) = 1
         where c.jogador_id = p_jogador)
      select c.posicao, c.cultura, c.x, c.y from bloco o
        join fazenda_canteiros c on c.jogador_id = p_jogador and c.posicao = o.posicao
        join fazenda_culturas u on u.id = c.cultura
       where c.estado = 'plantado'
         and now() >= c.plantado_em + make_interval(secs => u.tempo_seg)
         and now() < c.plantado_em + make_interval(secs => u.tempo_seg + greatest(u.tempo_seg * 2, 3600))
    loop
      exit when v_livre <= 0 or not fazenda_gastar_energia(p_jogador, 2);
      if v_seguro then
        begin
          v_qtd := fazenda_aplicar(p_jogador, 'colher', k.posicao, null, true);   -- cai no celeiro...
          perform fazenda_bau_guardar(p_jogador, b.x, b.y, k.cultura, v_qtd, k.x, k.y);   -- ...e passa para o baú
          v_livre := v_livre - v_qtd;
        exception when others then null; end;
      else
        v_qtd := fazenda_aplicar(p_jogador, 'colher', k.posicao, null, true);
        perform fazenda_bau_guardar(p_jogador, b.x, b.y, k.cultura, v_qtd, k.x, k.y);
        v_livre := v_livre - v_qtd;
      end if;
    end loop;

    -- cercados encostados: coleta o produto (para o baú) e dá ração (do baú, se ele tiver; senão do celeiro)
    for m in
      select a.id, a.alimentado_em, t.tempo_seg, t.produto, t.racao, t.racao_qtd, p.x as px, p.y as py
        from fazenda_animais a
        join fazenda_animais_tipos t on t.id = a.tipo
        join fazenda_construcoes p on p.jogador_id = p_jogador and p.tipo = 'cercado_' || a.tipo
        join fazenda_itens i on i.id = p.tipo
       where a.jogador_id = p_jogador
         and (((b.x = p.x - 1 or b.x = p.x + i.largura) and b.y between p.y and p.y + i.altura - 1)
           or ((b.y = p.y - 1 or b.y = p.y + i.altura) and b.x between p.x and p.x + i.largura - 1))
    loop
      if v_seguro then
        begin
          if m.alimentado_em is not null and now() >= m.alimentado_em + make_interval(secs => m.tempo_seg)
             and v_livre > 0 and fazenda_gastar_energia(p_jogador, 2) then
            perform fazenda_animal_um(p_jogador, m.id, 'coletar', true);
            perform fazenda_bau_guardar(p_jogador, b.x, b.y, m.produto, 1, m.px, m.py);
            v_livre := v_livre - 1;
            m.alimentado_em := null;
          end if;
        exception when others then null;
        end;
        begin
          if m.alimentado_em is null and fazenda_energia_atualizar(p_jogador) >= fazenda_energia_preco(p_jogador, 2) then
            if coalesce((select quantidade from fazenda_bau_itens where jogador_id = p_jogador and x = b.x and y = b.y and item = m.racao), 0) >= m.racao_qtd then
              update fazenda_bau_itens set quantidade = quantidade - m.racao_qtd where jogador_id = p_jogador and x = b.x and y = b.y and item = m.racao;
              insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, m.racao, m.racao_qtd)   -- passa pelo celeiro
              on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
              perform fazenda_viagem(p_jogador, m.racao, m.racao_qtd, b.x, b.y, m.px, m.py, true, now());
              v_livre := v_livre + m.racao_qtd;
            end if;
            perform fazenda_animal_um(p_jogador, m.id, 'alimentar', true);   -- sem ração: pula (e desfaz o de cima)
            perform fazenda_gastar_energia(p_jogador, 2);
          end if;
        exception when others then null;
        end;
      else
        if m.alimentado_em is not null and now() >= m.alimentado_em + make_interval(secs => m.tempo_seg)
           and v_livre > 0 and fazenda_gastar_energia(p_jogador, 2) then
          perform fazenda_animal_um(p_jogador, m.id, 'coletar', true);
          perform fazenda_bau_guardar(p_jogador, b.x, b.y, m.produto, 1, m.px, m.py);
          v_livre := v_livre - 1;
          m.alimentado_em := null;
        end if;
        -- (no modo rápido, só tenta a ração que existe: no baú ou no celeiro)
        if coalesce((select quantidade from fazenda_bau_itens where jogador_id = p_jogador and x = b.x and y = b.y and item = m.racao), 0) >= m.racao_qtd
           or coalesce((select quantidade from fazenda_celeiro where jogador_id = p_jogador and item = m.racao), 0) >= m.racao_qtd then
          if m.alimentado_em is null and fazenda_energia_atualizar(p_jogador) >= fazenda_energia_preco(p_jogador, 2) then
            if coalesce((select quantidade from fazenda_bau_itens where jogador_id = p_jogador and x = b.x and y = b.y and item = m.racao), 0) >= m.racao_qtd then
              update fazenda_bau_itens set quantidade = quantidade - m.racao_qtd where jogador_id = p_jogador and x = b.x and y = b.y and item = m.racao;
              insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, m.racao, m.racao_qtd)   -- passa pelo celeiro
              on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
              perform fazenda_viagem(p_jogador, m.racao, m.racao_qtd, b.x, b.y, m.px, m.py, true, now());
              v_livre := v_livre + m.racao_qtd;
            end if;
            perform fazenda_animal_um(p_jogador, m.id, 'alimentar', true);   -- sem ração: pula (e desfaz o de cima)
            perform fazenda_gastar_energia(p_jogador, 2);
          end if;
        end if;
      end if;
    end loop;

    -- árvores do pomar (e a amoreira) encostadas: colhe as frutas prontas
    for arv in
      select c.x, c.y, c.tipo, i.produz, i.produz_qtd from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
       where c.jogador_id = p_jogador and i.produz is not null and i.entradas is null
         and abs(c.x - b.x) + abs(c.y - b.y) = 1
         and (c.colhido_em is null or now() >= c.colhido_em + make_interval(secs => i.produz_seg))
    loop
      exit when v_livre <= 0 or not fazenda_gastar_energia(p_jogador, 2);
      update fazenda_construcoes set colhido_em = fazenda_colhido_agora(p_jogador, arv.tipo) where jogador_id = p_jogador and x = arv.x and y = arv.y;
      insert into fazenda_bau_itens (jogador_id, x, y, item, quantidade) values (p_jogador, b.x, b.y, arv.produz, arv.produz_qtd)
      on conflict (jogador_id, x, y, item) do update set quantidade = fazenda_bau_itens.quantidade + excluded.quantidade;
      perform fazenda_viagem(p_jogador, arv.produz, arv.produz_qtd, arv.x, arv.y, b.x, b.y, true, now());
      v_livre := v_livre - arv.produz_qtd;
    end loop;

    -- encostado no lago (x 24..29, y 14..18): pega o cesto do Bira
    if ((b.x in (23, 30) and b.y between 14 and 18) or (b.y in (13, 19) and b.x between 24 and 29))
       and v_livre > 0 and fazenda_energia_atualizar(p_jogador) >= fazenda_energia_preco(p_jogador, 2) then
      v_peixes := fazenda_cesto(p_jogador, v_livre);
      if v_peixes <> '{}'::jsonb then
        perform fazenda_gastar_energia(p_jogador, 2);
        for e in select key as item, value::int as qtd from jsonb_each_text(v_peixes) loop
          insert into fazenda_bau_itens (jogador_id, x, y, item, quantidade) values (p_jogador, b.x, b.y, e.item, e.qtd)
          on conflict (jogador_id, x, y, item) do update set quantidade = fazenda_bau_itens.quantidade + excluded.quantidade;
          perform fazenda_viagem(p_jogador, e.item, e.qtd, least(greatest(b.x, 24), 29), least(greatest(b.y, 14), 18), b.x, b.y, true, now());
          v_livre := v_livre - e.qtd;
        end loop;
      end if;
    end if;
    exit;   -- deu certo: o próximo baú
    exception when others then
      if v_seguro then raise; end if;
    end;
   end loop;
  end loop;
  perform fazenda_bot_xp_gravar();   -- fase 72: o XP do que colheram, uma vez só
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
  m     record;
  v_sem text;
  v_seguro boolean;   -- fase 71
begin
  perform fazenda_energia_atualizar(p_jogador);
  delete from fazenda_viagens where jogador_id = p_jogador and criada_em < now() - interval '10 minutes';
  delete from fazenda_bau_itens where jogador_id = p_jogador and quantidade = 0;
  delete from fazenda_oficina_itens where jogador_id = p_jogador and quantidade = 0;
  perform fazenda_baus(p_jogador);   -- baús: colhem os canteiros e cuidam dos cercados encostados (antes das oficinas)
  perform fazenda_oficinas_andar(p_jogador);   -- oficinas: estoque, prontos e a fábrica automática

  select semente into v_sem from fazenda_jogadores where id = p_jogador;
  for r in
    select c.x, c.y, i.raio from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
     where c.jogador_id = p_jogador and i.efeito = 'robo'
  loop
   -- fase 71: cada robô num lote só (modo rápido); deu erro, volta e refaz no modo seguro
   for v_tent in 1..2 loop
    v_seguro := v_tent = 2;
    begin
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
        if v_seguro then
          begin   -- colhe (e ara, se não tiver trator): 4 ⚡ (fase 43; era 3)
            if not fazenda_gastar_energia(p_jogador, 4) then exit; end if;
            perform fazenda_aplicar(p_jogador, 'colher', cc.posicao, null, true);
            if (select estado from fazenda_canteiros where jogador_id = p_jogador and posicao = cc.posicao) = 'vazio' then
              perform fazenda_aplicar(p_jogador, 'arar', cc.posicao, null, true);
            end if;
          exception when others then null;
          end;
          begin   -- replanta a mesma semente (paga com suas moedas): 2 ⚡
            if fazenda_gastar_energia(p_jogador, 2) then
              perform fazenda_aplicar(p_jogador, 'plantar', cc.posicao, cc.cultura, true);
            end if;
          exception when others then null;
          end;
        else
          if not fazenda_gastar_energia(p_jogador, 4) then exit; end if;
          perform fazenda_aplicar(p_jogador, 'colher', cc.posicao, null, true);
          if (select estado from fazenda_canteiros where jogador_id = p_jogador and posicao = cc.posicao) = 'vazio' then
            perform fazenda_aplicar(p_jogador, 'arar', cc.posicao, null, true);
          end if;
          -- (no modo rápido, só replanta o que dá: estação, estufa, nível e moedas)
          if fazenda_bot_pode_plantar(p_jogador, cc.cultura, cc.posicao) and fazenda_gastar_energia(p_jogador, 2) then
            perform fazenda_aplicar(p_jogador, 'plantar', cc.posicao, cc.cultura, true);
          end if;
        end if;
      elsif cc.estado = 'arado' and v_sem is not null then
        if v_seguro then
          begin   -- canteiro arado vazio: planta a última semente que você usou (2 ⚡)
            if fazenda_gastar_energia(p_jogador, 2) then
              perform fazenda_aplicar(p_jogador, 'plantar', cc.posicao, v_sem, true);
            end if;
          exception when others then null;
          end;
        elsif fazenda_bot_pode_plantar(p_jogador, v_sem, cc.posicao) and fazenda_gastar_energia(p_jogador, 2) then
          perform fazenda_aplicar(p_jogador, 'plantar', cc.posicao, v_sem, true);
        end if;
      end if;
    end loop;
    exit;   -- deu certo: o próximo robô
    exception when others then
      if v_seguro then raise; end if;
    end;
   end loop;
  end loop;
  perform fazenda_bot_xp_gravar();   -- fase 72: o XP do que colheram, uma vez só
end;
$$;

-- Tarefas por hora de um ajudante em cada nível (fase 18: 12 / 30 / 90; antes 4 / 12 / 36)
create or replace function public.fazenda_ritmo(p_nivel int)
returns real language sql immutable as $$
  select (case p_nivel when 1 then 12 when 2 then 30 when 3 then 90 when 4 then 150 else 240 end)::real;   -- fase 74: níveis 4 e 5
$$;

-- Os ajudantes fazem o trabalho acumulado desde a última vez (até 8 horas).
-- Roda quando a fazenda carrega (abrir a página e a cada 30 s com ela aberta).
-- Fase 71: cada ajudante trabalha num lote só. Primeiro no modo rápido: cada tarefa direto, sem o
-- "exception" em volta de cada uma (cada um abria uma sub-transação; com centenas delas numa chamada o
-- banco ficava lento para todo mundo e a volta depois de horas fora passava dos 3 s). Se alguma tarefa
-- der erro, o lote daquele ajudante volta e é refeito no modo seguro, cada tarefa protegida como antes.
-- O resultado é o mesmo. A estação sai uma vez só e a semeadora conta as sementes plantadas uma vez só.
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
  v_seguro boolean;          -- fase 71: refazendo o lote no modo seguro?
  v_est   text := fazenda_estacao_em(now());   -- fase 71: a estação de agora (uma vez só)
  v_cont  jsonb;             -- fase 71: quantos canteiros de cada semente (o rodízio da semeadora)
  v_moedas int;
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
    -- com o jogador na fazenda a semeadora descansa (o tempo online não conta para ela)
    if a.funcao = 'plantar' and coalesce((select carregado_antes > now() - interval '2 minutes' from fazenda_jogadores where id = p_jogador), false) then
      update fazenda_ajudantes set atualizado_em = now() where jogador_id = p_jogador and tipo = a.tipo;
      continue;
    end if;
    v_custo := 100 / (fazenda_ritmo(a.nivel) * fazenda_turno(p_jogador));   -- fase 82: 12 h com o turno de diamante
    -- fase 43: com o café (diamantes) o tempo dentro dele vale em dobro
    v_seg := extract(epoch from now() - a.atualizado_em)::real
           + case when v_cafe_ate is null then 0
                  else greatest(extract(epoch from least(now(), v_cafe_ate) - greatest(a.atualizado_em, v_cafe_de))::real, 0) end;
    v_cred := least(a.credito + v_seg / 3600 * fazenda_ritmo(a.nivel), fazenda_ritmo(a.nivel) * fazenda_turno(p_jogador));
    v_n := least(floor(v_cred), floor(a.energia / v_custo + 0.001))::int;   -- fase 59: e o que a energia deixa

    for v_tent in 1..2 loop   -- fase 71: 1 = modo rápido; 2 = deu erro, refaz no modo seguro
      v_seguro := v_tent = 2;
      v_feito := 0;
      v_log := '{}'::jsonb;
      begin
        if v_n > 0 and a.funcao = 'colher' then
          -- fase 48: também o que murchou depois da última olhada dele (até 8 h): com a fazenda fechada ele
          -- teria colhido a tempo; o que murcha primeiro vai primeiro
          for c in
            select cc.posicao, now() >= cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) as murcha
              from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
             where cc.jogador_id = p_jogador and cc.estado = 'plantado'
               and now() >= cc.plantado_em + make_interval(secs => k.tempo_seg)
               and cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600))
                   > greatest(a.atualizado_em, now() - make_interval(hours => fazenda_turno(p_jogador)::int))
             order by cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) limit v_n
          loop
            if fazenda_bot_aplicar(p_jogador, case when c.murcha then 'colher_tarde' else 'colher' end, c.posicao, null, v_seguro) is not null then
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'colheu');
            end if;
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
                 and k.estoque + (k.iniciado_em is not null)::int < fazenda_estoque_max_de(p_jogador)
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
            if fazenda_bot_aplicar(p_jogador, 'arar', c.posicao, null, v_seguro) is not null then
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'arou');
            end if;
          end loop;
          -- sobrou tempo: aduba os canteiros que estão crescendo (+1 item na colheita de cada um)
          if v_feito < v_n then
            for c in
              select cc.posicao from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
               where cc.jogador_id = p_jogador and cc.estado = 'plantado' and not cc.adubado
                 and now() < cc.plantado_em + make_interval(secs => k.tempo_seg)
               order by cc.plantado_em limit v_n - v_feito
            loop
              if fazenda_bot_aplicar(p_jogador, 'adubar', c.posicao, null, v_seguro) is not null then
                v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'adubou');
              end if;
            end loop;
          end if;

        elsif v_n > 0 and a.funcao = 'plantar' then
          v_nivel := fazenda_nivel((select xp from fazenda_jogadores where id = p_jogador));
          -- (fase 71: a conta de cada semente sai uma vez e anda junto com o que ela planta)
          select coalesce(jsonb_object_agg(x.cultura, x.n), '{}'::jsonb) into v_cont
            from (select cultura, count(*) as n from fazenda_canteiros
                   where jogador_id = p_jogador and estado = 'plantado' group by cultura) x;
          for c in
            select posicao from fazenda_canteiros
             where jogador_id = p_jogador and estado = 'arado' order by posicao limit v_n
          loop
            -- rodízio com todas as sementes da estação que o nível libera: a menos plantada primeiro,
            -- pulando as que o dinheiro não paga
            v_ok := false;
            select moedas into v_moedas from fazenda_jogadores where id = p_jogador;
            for v_sem in
              select k.id from fazenda_culturas k
               where k.tipo = 'cultura' and k.nivel_min <= v_nivel
                 and (k.estacao is null or k.estacao = v_est)
                 and k.custo <= v_moedas
               order by coalesce((v_cont->>k.id)::int, 0), k.ordem
            loop
              if fazenda_bot_aplicar(p_jogador, 'plantar', c.posicao, v_sem, v_seguro) is not null then
                v_feito := v_feito + 1; v_ok := true; v_log := fazenda_conta(v_log, 'plantou');
                v_cont := v_cont || jsonb_build_object(v_sem, coalesce((v_cont->>v_sem)::int, 0) + 1);
                exit;
              end if;
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
            if c.erva and v_feito < v_n and fazenda_bot_aplicar(p_jogador, 'erva', c.posicao, null, v_seguro) is not null then
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'erva');
            end if;
            if c.praga and v_feito < v_n and fazenda_bot_aplicar(p_jogador, 'praga', c.posicao, null, v_seguro) is not null then
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'praga');
            end if;
            if c.seco and v_feito < v_n and fazenda_bot_aplicar(p_jogador, 'seco', c.posicao, null, v_seguro) is not null then
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'seco');
            end if;
          end loop;

        elsif v_n > 0 and a.funcao = 'animal' then
          for m in
            select an.id, an.alimentado_em, t.tempo_seg, t.racao, t.racao_qtd from fazenda_animais an join fazenda_animais_tipos t on t.id = an.tipo
             where an.jogador_id = p_jogador and an.tipo = a.alvo order by an.id
          loop
            exit when v_feito >= v_n;
            -- coletar e dar ração separados: faltar ração não desfaz a coleta
            if m.alimentado_em is not null and now() >= m.alimentado_em + make_interval(secs => m.tempo_seg) then
              if fazenda_bot_animal(p_jogador, m.id, 'coletar', v_seguro) then
                v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'coletou');
                m.alimentado_em := null;
              end if;
            end if;
            -- sem ração no celeiro: pula (fase 71: confere antes de tentar)
            if m.alimentado_em is null and v_feito < v_n
               and coalesce((select quantidade from fazenda_celeiro where jogador_id = p_jogador and item = m.racao), 0) >= m.racao_qtd then
              if fazenda_bot_animal(p_jogador, m.id, 'alimentar', v_seguro) then
                v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'alimentou');
              end if;
            end if;
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
        exit;   -- deu certo: o próximo ajudante
      exception when others then
        if v_seguro then raise; end if;   -- (no modo seguro cada tarefa já se protege: este erro é de verdade)
      end;
    end loop;
  end loop;
  if not v_reg then perform fazenda_murchas_registrar(p_jogador); end if;   -- fase 66
  perform fazenda_bot_xp_gravar();   -- fase 72: o XP do que colheram, uma vez só
end;
$$;

-- Fase 46: grava o crédito que os ajudantes juntaram até agora (no ritmo de agora, com o café) e
-- zera o relógio deles. Antes de mudar o ritmo (evoluir) ou o café.
create or replace function public.fazenda_ajudantes_fechar(p_jogador uuid, p_tipo text)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_cafe_de  timestamptz;
  v_cafe_ate timestamptz;
begin
  select cafe_de, cafe_ate into v_cafe_de, v_cafe_ate from fazenda_jogadores where id = p_jogador;
  update fazenda_ajudantes h
     set credito = least(h.credito + (extract(epoch from now() - h.atualizado_em)::real
                          + case when v_cafe_ate is null then 0
                                 else greatest(extract(epoch from least(now(), v_cafe_ate) - greatest(h.atualizado_em, v_cafe_de))::real, 0) end)
                         / 3600 * fazenda_ritmo(h.nivel),
                         fazenda_ritmo(h.nivel) * 8),
         atualizado_em = now()
   where h.jogador_id = p_jogador and (p_tipo is null or h.tipo = p_tipo);
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
  perform fazenda_reator(v_id);   -- fase 68: a radiação do reator nos bichos
  perform fazenda_tempestade(v_id);   -- fase 77: o raio e o furacão (e o eletricista consertando)
  return fazenda_estado(v_id);
end;
$$;

-- Contrata um ajudante ou evolui o nível dele (fase 72: 4x e 8x o preço de contratar; eram 2x e 4x)
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
  perform fazenda_ajudantes_fechar(v_id, p_tipo);   -- (fase 46: quem não trabalhou também)
  select nivel into v_nivel from fazenda_ajudantes where jogador_id = v_id and tipo = p_tipo;
  -- fase 74: até o nível 5; o 4 pede o nível 35 do jogador e o 5, o 42 (igual a EVOLUIR_NIVEL em fazenda.js)
  if v_nivel >= 5 then raise exception 'nivel_maximo'; end if;
  if (v_nivel = 3 and fazenda_nivel(j.xp) < 35) or (v_nivel = 4 and fazenda_nivel(j.xp) < 42) then raise exception 'nivel_insuficiente'; end if;
  v_custo := t.custo * (array[1, 4, 8, 16, 32])[coalesce(v_nivel, 0) + 1];
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
-- fase 74b: p_itens vende vários de uma vez (o "vender produtos" chamava uma vez por produto, cada uma
-- com a fazenda inteira de volta: 15 produtos travavam o jogo uns 5 s)
create or replace function public.fazenda_vender(p_token text, p_item text default null, p_quantidade int default null,
                                                 p_itens text[] default null)
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
       and (p_itens is null or ce.item = any(p_itens))   -- fase 74b
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
  select floor(p_rendimento * 0.5)::int;
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
    'avatar', j.avatar,
    'nivel', v_nivel,
    'max_canteiros', fazenda_max_canteiros(v_nivel),
    'zonas', j.zonas,
    'direita', j.direita,   -- fase 78
    -- fase 48: hoje o visitante ainda pode salvar até 2 plantas murchas e dar ração a até 10 bichos aqui
    'salvos_hoje', (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'salvar'
                     and criado_em > now() - interval '1 day'),
    'pode_salvar', (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'salvar'
                     and criado_em > now() - interval '1 day') < 2,
    'bichos_hoje', (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'bicho'
                     and criado_em > now() - interval '1 day'),
    'premio_ajuda', fazenda_premio_ajuda(p_ator),
    -- fase 83: dono sumido há mais de 3 dias (+50% de XP e dá para plantar) e as murchas que ainda dá para limpar hoje
    'abandonada', fazenda_abandonada(p_dono),
    'limpos_hoje', (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'limpar'
                     and criado_em > now() - interval '1 day'),
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
      select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'alimentado_em', alimentado_em,
               'radioativo_ate', case when radioativo_ate > now() then radioativo_ate end) order by id)   -- fase 68
        from fazenda_animais where jogador_id = p_dono), '[]'::jsonb),
    'construcoes', coalesce((
      select jsonb_agg(jsonb_build_object('x', x, 'y', y, 'tipo', tipo))
        from fazenda_construcoes where jogador_id = p_dono), '[]'::jsonb),
    'perfil', jsonb_build_object(
      'criado_em', j.criado_em,
      'estatisticas', (select to_jsonb(e) - 'jogador_id' || jsonb_build_object('energia', e.energia + floor(g.energia_gasta)::int)
                         from fazenda_estatisticas e join fazenda_jogadores g on g.id = e.jogador_id where e.jogador_id = p_dono),
      'conquistas', coalesce((select jsonb_agg(conquista order by obtida_em)
                                from fazenda_conquistas where jogador_id = p_dono), '[]'::jsonb),
      'trofeus', fazenda_trofeus(p_dono))   -- fase 63: os troféus do evento da semana
  );
end;
$$;

-- Pega colheita de um canteiro do vizinho. Retorna a quantidade pega.
-- fase 66: p_luva = pode gastar 1 luva do Perks para passar pelo alarme (só gasta no canteiro protegido)
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

-- Tira os problemas de um canteiro do vizinho. Retorna quantos problemas resolveu.
-- Fase 48: quanto XP vale cada ajuda a um vizinho: 0,25% do nível de quem ajuda (pelo menos 2)
-- fase 83: 0,30% (e sem o limite de 30 por dia)
create or replace function public.fazenda_premio_ajuda(p_ator uuid)
returns int language sql stable security definer set search_path = public as $$
  select greatest(2, round((fazenda_xp_nivel(n + 1) - fazenda_xp_nivel(n)) * 0.003))::int
    from (select fazenda_nivel(xp) as n from fazenda_jogadores where id = p_ator) x;
$$;

-- Dá o prêmio de p_unidades ajudas; devolve o XP. Fase 83: sem o limite de 30 por dia, e com a
-- sequência de vizinhos: cada vizinho diferente ajudado em até 10 min do anterior dá +10% (até +100%);
-- 10 min sem ajudar, ela zera. O XP em dobro e os bônus de nível somam por cima (gatilho do XP).
create or replace function public.fazenda_premiar_ajuda(p_ator uuid, p_unidades int, p_dono uuid)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  j      record;
  v_seq  uuid[];
  v_xp   int;
begin
  if coalesce(p_unidades, 0) <= 0 then return 0; end if;
  select seq_donos, seq_em into j from fazenda_jogadores where id = p_ator for update;
  v_seq := case when j.seq_em is null or j.seq_em < now() - interval '10 minutes' then '{}'::uuid[] else coalesce(j.seq_donos, '{}') end;
  if p_dono is not null and not (p_dono = any(v_seq)) then v_seq := v_seq || p_dono; end if;
  v_xp := round(p_unidades * fazenda_premio_ajuda(p_ator) * (1 + fazenda_sequencia_bonus(cardinality(v_seq)))
                * case when fazenda_abandonada(p_dono) then 1.5 else 1 end)::int;   -- fazenda abandonada: +50%
  update fazenda_jogadores set xp = xp + v_xp, moedas = moedas + p_unidades, seq_donos = v_seq, seq_em = now() where id = p_ator;
  return v_xp;
end;
$$;

-- fase 83: fazenda abandonada = o dono não aparece há mais de 3 dias (lá dá para plantar, e a ajuda vale +50%)
create or replace function public.fazenda_abandonada(p_dono uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select visto_em < now() - interval '3 days' from fazenda_jogadores where id = p_dono), false);
$$;

-- fase 83: o bônus da sequência com n vizinhos (o 1º não dá bônus; +10% a cada um depois, até +100%)
create or replace function public.fazenda_sequencia_bonus(p_n int)
returns real language sql immutable as $$
  select least(1.0, 0.1 * greatest(coalesce(p_n, 0) - 1, 0))::real;
$$;

-- Fase 48: o vizinho salva uma planta murcha (1 por dia em cada fazenda): ela volta madura, sem
-- problemas, com o tempo todo para colher. Vale 3 ajudas. Devolve o XP.
create or replace function public.fazenda_salvar_um(p_ator uuid, p_dono uuid, p_posicao int)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  c   record;
  k   record;
  v_xp int;
begin
  select * into c from fazenda_canteiros where jogador_id = p_dono and posicao = p_posicao for update;
  if not found or c.estado <> 'plantado' then raise exception 'nada_a_fazer'; end if;
  select * into k from fazenda_culturas where id = c.cultura;
  if now() < c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) then
    raise exception 'nada_a_fazer';   -- não está murcha
  end if;
  if (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'salvar'
        and criado_em > now() - interval '1 day') >= 2 then
    raise exception 'ja_salvou';
  end if;
  update fazenda_canteiros
     set plantado_em = now() - make_interval(secs => k.tempo_seg), erva = false, praga = false, seco = false, prox_evento = null
   where jogador_id = p_dono and posicao = p_posicao;
  v_xp := fazenda_premiar_ajuda(p_ator, 3, p_dono);
  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd)
  values (p_ator, p_dono, 'salvar', p_posicao, now() - make_interval(secs => k.tempo_seg), k.id, 3);
  perform fazenda_missao(p_ator, 'ajudar', 3);
  return v_xp;
end;
$$;

-- Fase 83: cuidar da roça do vizinho (o que mais tem nas fazendas abandonadas). Devolve o XP.
--   limpar: tira 1 planta murcha (o canteiro fica arado); até 2 por dia em cada fazenda, como salvar. 1 ajuda.
--   arar: canteiro vazio vira arado. 1 ajuda.
--   colher: a planta madura vai para o celeiro do dono (ele ganha metade do XP, como com o ajudante). 1 ajuda.
--   plantar:<semente>: só na fazenda abandonada, com a semente paga por quem ajuda (o nível e a estação
--     valem os de quem ajuda e de agora). 5 ajudas.
create or replace function public.fazenda_roca_um(p_ator uuid, p_dono uuid, p_posicao int, p_acao text)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  c    record;
  k    record;
  v_murcha boolean;
  v_un int;
  v_tipo text;
  v_cult text;
begin
  select * into c from fazenda_canteiros where jogador_id = p_dono and posicao = p_posicao for update;
  if not found then raise exception 'nada_a_fazer'; end if;
  v_murcha := false;
  if c.cultura is not null then
    select * into k from fazenda_culturas where id = c.cultura;
    v_murcha := c.estado = 'plantado' and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600));
  end if;
  if p_acao = 'limpar' then
    if not v_murcha then raise exception 'nada_a_fazer'; end if;
    if (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'limpar'
          and criado_em > now() - interval '1 day') >= 2 then
      raise exception 'ja_limpou';
    end if;
    perform fazenda_aplicar(p_dono, 'arar', p_posicao, null, true);
    v_un := 1; v_tipo := 'limpar'; v_cult := c.cultura;
  elsif p_acao = 'arar' then
    if c.estado <> 'vazio' then raise exception 'nada_a_fazer'; end if;
    perform fazenda_aplicar(p_dono, 'arar', p_posicao, null, true);
    v_un := 1; v_tipo := 'arar'; v_cult := null;   -- (canteiro vazio: sem planta)
  elsif p_acao = 'colher' then
    if c.estado <> 'plantado' or v_murcha or now() < c.plantado_em + make_interval(secs => k.tempo_seg) then raise exception 'nao_maduro'; end if;
    perform fazenda_aplicar(p_dono, 'colher', p_posicao, null, true);
    v_un := 1; v_tipo := 'colher'; v_cult := c.cultura;
  else   -- plantar:<semente>
    if not fazenda_abandonada(p_dono) then raise exception 'nao_abandonada'; end if;
    if c.estado <> 'arado' then raise exception 'precisa_arar'; end if;
    select * into k from fazenda_culturas where id = split_part(p_acao, ':', 2) and tipo = 'cultura';
    if not found then raise exception 'cultura_invalida'; end if;
    if k.estacao is not null and k.estacao <> fazenda_estacao_em(now()) then raise exception 'fora_de_estacao'; end if;
    if fazenda_nivel((select xp from fazenda_jogadores where id = p_ator)) < k.nivel_min then raise exception 'nivel_insuficiente'; end if;
    if (select moedas from fazenda_jogadores where id = p_ator) < k.custo then raise exception 'moedas_insuficientes'; end if;
    update fazenda_jogadores set moedas = moedas - k.custo where id = p_ator;
    update fazenda_canteiros
       set estado = 'plantado', cultura = k.id, plantado_em = now(),
           erva = false, praga = false, seco = false, roubado = 0, adubado = false,
           prox_evento = now() + make_interval(secs => k.tempo_seg * (0.15 + random() * 0.35))
     where jogador_id = p_dono and posicao = p_posicao;
    v_un := 5; v_tipo := 'plantar'; v_cult := k.id;
  end if;
  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd)
  values (p_ator, p_dono, v_tipo, p_posicao, now(), v_cult, 1);
  perform fazenda_missao(p_ator, 'ajudar', 1);
  return fazenda_premiar_ajuda(p_ator, v_un, p_dono);
end;
$$;

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

  -- fase 48: o XP de cada uma cresce com o nível de quem ajuda (fazenda_premio_ajuda); fase 83: sem limite
  v_premio := fazenda_premiar_ajuda(p_ator, v_n, p_dono);

  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd)
  values (p_ator, p_dono, 'ajuda', p_posicao, c.plantado_em, k.id, v_n);
  perform fazenda_missao(p_ator, 'ajudar', v_n);

  return v_premio;   -- (fase 48: o XP ganho; antes, os problemas)
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
                       where (xp > v_xp or (xp = v_xp and criado_em < v_desde)) and banido_em is null),
    'total', (select count(*) from fazenda_jogadores where banido_em is null),
    'ranking', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', r.id, 'apelido', r.apelido, 'avatar', r.avatar, 'nivel', fazenda_nivel(r.xp), 'xp', r.xp,
               'patrimonio', r.moedas + coalesce((
                 select sum(ce.quantidade * k.venda)
                   from fazenda_celeiro ce join fazenda_culturas k on k.id = ce.item
                  where ce.jogador_id = r.id), 0),
               'eu', r.id = v_id)
             order by r.xp desc, r.criado_em)
        from (select * from fazenda_jogadores where banido_em is null order by xp desc, criado_em limit 200) r), '[]'::jsonb)   -- (fase 53: eram 50)
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
  v_aband boolean := random() < 0.6;   -- fase 83: 6 em cada 10 vezes, primeiro as abandonadas (as que mais precisam)
begin
  if v_dono is null then
    select j.id into v_dono
      from fazenda_jogadores j
     where j.id <> v_id
       and j.visto_em > now() - interval '30 days'
       and j.banido_em is null
     order by (v_aband and j.visto_em < now() - interval '3 days') desc,
              exists (
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
  elsif not exists (select 1 from fazenda_jogadores where id = v_dono and banido_em is null) then
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
  if not exists (select 1 from fazenda_jogadores where id = p_vizinho and banido_em is null) then
    raise exception 'vizinho_invalido';
  end if;
  -- fase 66: pegar_luva (a luva do Perks); fase 83: limpar (murcha), arar (vazio), colher (para o dono) e plantar:<semente>
  if p_acao not in ('pegar', 'pegar_luva', 'ajudar', 'salvar', 'limpar', 'arar', 'colher') and p_acao not like 'plantar:%' then
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
      elsif p_acao in ('limpar', 'arar', 'colher') or p_acao like 'plantar:%' then
        v_qtd := fazenda_roca_um(v_id, p_vizinho, v_pos, p_acao);   -- fase 83
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

  perform fazenda_bot_xp_gravar();   -- fase 83: a metade do XP da colheita que vai para o dono
  return jsonb_build_object(
    'feitos', v_feitos,
    'resultado', v_result,
    'vizinho', fazenda_vizinho(p_vizinho, v_id),
    'estado', fazenda_estado(v_id)
  );
end;
$$;

-- Fase 48: o vizinho dá ração aos bichos com fome; cada um vale 1 ajuda.
-- Fase 83: a ração sai do celeiro de quem ajuda (era do dono, até 10 por dia) e não tem limite. O
-- bicho começa com o feno e o cuidador do dono, como se o dono tivesse dado.
create or replace function public.fazenda_vizinho_bicho(p_token text, p_vizinho uuid, p_animais bigint[])
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_a     bigint;
  v_feito int := 0;
  v_xp    int := 0;
  r       record;
  v_tem   int;
begin
  if p_vizinho is null or p_vizinho = v_id then raise exception 'propria_fazenda'; end if;
  if not exists (select 1 from fazenda_jogadores where id = p_vizinho and banido_em is null) then raise exception 'vizinho_invalido'; end if;
  if p_animais is null or array_length(p_animais, 1) is null or array_length(p_animais, 1) > 50 then raise exception 'nada_a_fazer'; end if;
  foreach v_a in array p_animais loop
    begin
      select a.tipo, a.alimentado_em, t.racao, t.racao_qtd, t.tempo_seg into r
        from fazenda_animais a join fazenda_animais_tipos t on t.id = a.tipo
       where a.id = v_a and a.jogador_id = p_vizinho
         for update of a;
      if not found then raise exception 'animal_invalido'; end if;
      if r.alimentado_em is not null then raise exception 'ja_alimentado'; end if;
      -- a ração de quem ajuda (a que ele guardou para os bichos dele fica)
      select coalesce((select quantidade from fazenda_celeiro where jogador_id = v_id and item = r.racao), 0)
           - coalesce((select quantidade from fazenda_reservas where jogador_id = v_id and item = r.racao), 0) into v_tem;
      if v_tem < r.racao_qtd then raise exception 'sem_racao_sua'; end if;
      update fazenda_celeiro set quantidade = quantidade - r.racao_qtd where jogador_id = v_id and item = r.racao;
      update fazenda_animais
         set alimentado_em = now() - make_interval(secs => r.tempo_seg * (
                               case when fazenda_tem_efeito(p_vizinho, 'feno') then 0.2 else 0 end
                               + fazenda_cuidador_adianta(p_vizinho, r.tipo)))
       where id = v_a;
      v_xp := v_xp + fazenda_premiar_ajuda(v_id, 1, p_vizinho);
      insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd)
      values (v_id, p_vizinho, 'bicho', 0, now(), r.racao, 1);
      v_feito := v_feito + 1;
    exception when others then
      if array_length(p_animais, 1) = 1 then raise; end if;
    end;
  end loop;
  if v_feito > 0 then perform fazenda_missao(v_id, 'ajudar', v_feito); end if;
  return jsonb_build_object('feitos', v_feito, 'xp', v_xp,
                            'vizinho', fazenda_vizinho(p_vizinho, v_id), 'estado', fazenda_estado(v_id));
end;
$$;

-- Fase 83: o vizinho coleta o produto pronto dos bichos do dono: o produto vai para o celeiro do dono
-- (que ganha metade do XP, como com o ajudante) e quem ajuda ganha 1 ajuda por bicho
create or replace function public.fazenda_vizinho_coletar(p_token text, p_vizinho uuid, p_animais bigint[])
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_a     bigint;
  v_feito int := 0;
  v_xp    int := 0;
  v_prod  text;
begin
  if p_vizinho is null or p_vizinho = v_id then raise exception 'propria_fazenda'; end if;
  if not exists (select 1 from fazenda_jogadores where id = p_vizinho and banido_em is null) then raise exception 'vizinho_invalido'; end if;
  if p_animais is null or array_length(p_animais, 1) is null or array_length(p_animais, 1) > 50 then raise exception 'nada_a_fazer'; end if;
  foreach v_a in array p_animais loop
    begin
      select t.produto into v_prod from fazenda_animais a join fazenda_animais_tipos t on t.id = a.tipo
       where a.id = v_a and a.jogador_id = p_vizinho;
      if not found then raise exception 'animal_invalido'; end if;
      perform fazenda_animal_um(p_vizinho, v_a, 'coletar', true);
      v_xp := v_xp + fazenda_premiar_ajuda(v_id, 1, p_vizinho);
      insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd)
      values (v_id, p_vizinho, 'coleta', 0, now(), v_prod, 1);
      v_feito := v_feito + 1;
    exception when others then
      if array_length(p_animais, 1) = 1 then raise; end if;
    end;
  end loop;
  if v_feito > 0 then perform fazenda_missao(v_id, 'ajudar', v_feito); end if;
  return jsonb_build_object('feitos', v_feito, 'xp', v_xp,
                            'vizinho', fazenda_vizinho(p_vizinho, v_id), 'estado', fazenda_estado(v_id));
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
    -- fase 72: o XP é 1,5% do nível (no 30, 634; no 44, 1.636), e no começo o de sempre se for maior
    insert into fazenda_missoes (jogador_id, dia, slot, tipo, alvo, moedas, xp)
    values (p_jogador, v_hoje, i - 1, v_tipo, v_alvo, v_moeda,
            greatest(5 + v_nivel * 3, ceil(0.015 * (fazenda_xp_nivel(least(v_nivel, 44) + 1) - fazenda_xp_nivel(least(v_nivel, 44))))::int))
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
  v_ev     jsonb;   -- fase 63
  v_podios int;
begin
  insert into fazenda_estatisticas (jogador_id) values (p_jogador) on conflict do nothing;
  select * into s from fazenda_estatisticas where jogador_id = p_jogador;
  select fazenda_nivel(xp) into v_nivel from fazenda_jogadores where id = p_jogador;
  select count(*) into v_constr from fazenda_construcoes where jogador_id = p_jogador;
  select count(*) into v_conv from fazenda_convites where dono_id = p_jogador;
  -- fase 63: os 1º lugares de cada categoria do evento e os pódios
  select coalesce(jsonb_object_agg(categoria, n), '{}'::jsonb) into v_ev
    from (select categoria, count(*) as n from fazenda_semana_premios where jogador_id = p_jogador and posicao = 1 group by categoria) x;
  select count(*) into v_podios from fazenda_semana_premios where jogador_id = p_jogador;
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
      when 'evento_ranking' then coalesce((v_ev->>'ranking')::int, 0)   -- fase 63: o evento da semana
      when 'evento_niveis' then coalesce((v_ev->>'niveis')::int, 0)
      when 'evento_moedas' then coalesce((v_ev->>'moedas')::int, 0)
      when 'evento_vendeu' then coalesce((v_ev->>'vendeu')::int, 0)
      when 'evento_comprou' then coalesce((v_ev->>'comprou')::int, 0)
      when 'evento_convites' then coalesce((v_ev->>'convites')::int, 0)
      when 'evento_podio' then v_podios
      when 'maior_compra' then coalesce(s.maior_compra, 0)::int   -- fase 78: a maior compra de uma vez
      else 0
    end;
    if v_valor >= r.meta then
      insert into fazenda_conquistas (jogador_id, conquista) values (p_jogador, r.id) on conflict do nothing;
      if found then   -- fase 70: só paga quem gravou agora (duas chamadas juntas pagavam duas vezes)
        update fazenda_jogadores set moedas = moedas + r.recompensa, diamantes = diamantes + r.diamantes where id = p_jogador;   -- fase 72
      end if;
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
  select a.id, a.tipo, a.alimentado_em, t.produto, t.tempo_seg, t.racao, t.racao_qtd, k.xp as produto_xp
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
    -- com fardo de feno na fazenda, o animal produz 20% mais rápido; fase 54: o cuidador dele, mais
    -- 10% por nível (o bicho já começa adiantado, como com o feno)
    update fazenda_animais
       set alimentado_em = now() - make_interval(secs => r.tempo_seg * (
                             case when fazenda_tem_efeito(p_jogador, 'feno') then 0.2 else 0 end
                             + fazenda_cuidador_adianta(p_jogador, r.tipo)))
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
    -- fase 72: o que o ajudante coleta dá metade do XP (antes, nada)
    if not p_bot then update fazenda_jogadores set xp = xp + r.produto_xp where id = p_jogador;
    else perform fazenda_bot_xp(p_jogador, r.produto_xp / 2); end if;
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
    -- de 1 a 7, sempre o próximo da fila; fase 78: p_tipo 8 a 10 = o próximo da direita (à parte,
    -- do nível 29). Sem p_tipo (jogo antigo), o próximo da fila.
    if coalesce(nullif(p_tipo, ''), '0')::int >= 8 then
      if j.direita >= 3 then raise exception 'terreno_max'; end if;
      if p_tipo::int <> 8 + j.direita then raise exception 'terreno_fora_de_ordem'; end if;
    elsif j.zonas >= 7 then raise exception 'terreno_max';
    end if;
    select (z->>'n')::int as n, (z->>'custo')::int as custo, (z->>'nivel')::int as nivel into a
      from jsonb_array_elements(fazenda_zonas()) z
     where (z->>'n')::int = case when coalesce(nullif(p_tipo, ''), '0')::int >= 8 then 8 + j.direita else j.zonas + 1 end;
    if fazenda_nivel(j.xp) < a.nivel then raise exception 'nivel_insuficiente'; end if;
    if j.moedas < a.custo then raise exception 'moedas_insuficientes'; end if;
    if a.n >= 8 then update fazenda_jogadores set moedas = moedas - a.custo, direita = direita + 1 where id = v_id;
    else update fazenda_jogadores set moedas = moedas - a.custo, zonas = zonas + 1 where id = v_id; end if;

  elsif p_categoria = 'melhoria' then
    -- fase 57: o próximo nível da melhoria (p_tipo = adubo, pomar ou pes)
    -- fase 62: e as do alto-mar (barco, vara e marinheiro), que pedem o píer pronto
    select (n->>'nivel')::int as nivel, (n->>'custo')::int as custo, coalesce((m->>'mar')::boolean, false) as mar,
           n->'itens' as itens, coalesce((n->>'diamantes')::int, 0) as diamantes into a
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
    -- fase 82: as de diamante (D8) e o que cada uma precisa antes
    if p_tipo = 'cesto_bira' and j.zonas < 3 then raise exception 'sem_lago'; end if;
    if p_tipo = 'cesto_nonato' and fazenda_mar_item(v_id, 'marinheiro') is null then raise exception 'sem_marinheiro'; end if;
    if p_tipo = 'barraca' and j.barracas < 4 then raise exception 'barracas_antes'; end if;
    if j.diamantes < a.diamantes then raise exception 'diamantes_insuficientes'; end if;
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
    update fazenda_jogadores set moedas = moedas - a.custo, diamantes = diamantes - a.diamantes,
           barracas = barracas + (p_tipo = 'barraca')::int   -- fase 82: a 5ª e a 6ª barraca
     where id = v_id;
    if a.diamantes > 0 then
      insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, 'melhoria:' || p_tipo, a.diamantes);
    end if;
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

  elsif p_categoria = 'oficina' then
    -- fase 82 (B10): oficina nível 2 e 3, por tipo (vale para todas as oficinas daquele tipo)
    if not exists (select 1 from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
                    where c.jogador_id = v_id and c.tipo = p_tipo and i.entradas is not null) then
      raise exception 'item_invalido';
    end if;
    v_n := coalesce((select nivel from fazenda_oficina_nivel where jogador_id = v_id and tipo = p_tipo), 1);
    if v_n >= 3 then raise exception 'melhoria_max'; end if;
    v_preco := (fazenda_oficina_niveis()->(v_n - 1)->>'custo')::int;
    if j.moedas < v_preco then raise exception 'moedas_insuficientes'; end if;
    perform fazenda_oficinas_andar(v_id);   -- o que já ficou pronto sai no ritmo de antes
    update fazenda_jogadores set moedas = moedas - v_preco where id = v_id;
    insert into fazenda_oficina_nivel (jogador_id, tipo, nivel) values (v_id, p_tipo, 2)
    on conflict (jogador_id, tipo) do update set nivel = fazenda_oficina_nivel.nivel + 1;

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
     celeiro x1..3 y1..6 · casa x5..7 y1..3 · campo x9..14 y3..6 · lago x24..29 y14..18 (terreno 3).
     Fase 45: o galinheiro (x0..6 y7..) e o pasto (x16..21 y0..6) só existem enquanto houver bicho
     sem cercado (quem já tinha antes do cercado obrigatório): ver fazenda_checar_lugar */
create or replace function public.fazenda_livre(p_x int, p_y int)
returns boolean language sql immutable as $$
  select p_x between 0 and 63 and p_y between 0 and 36            -- fase 61: o litoral vai até a areia (y 36); fase 78: até x 63
     and not (p_x between 1 and 3  and p_y between 1 and 6)     -- celeiro
     and not (p_x between 5 and 7  and p_y between 1 and 3)     -- casa
     and not (p_x between 24 and 29 and p_y between 14 and 18)  -- lago
     and not (p_x between 22 and 24 and p_y between 35 and 36); -- fase 61: o lugar do píer (o resto dele é no mar, y 37 a 41)
$$;

-- Fase 19: o galinheiro cresce com os bichos pequenos (galinha, pato, coelho): 2 fileiras
-- (y 7 e 8) até 5 bichos, 3 de 6 a 8 e 4 a partir de 9 — para baixo (y 9 e 10), e só ocupa
-- uma fileira nova se ela estiver livre (nada construído nem canteiro em x 0..6). Igual a
-- linhasGalinheiro em fazenda.js.
create or replace function public.fazenda_galinheiro_quer(p_jogador uuid)
returns int language sql stable security definer set search_path = public, extensions as $$
  -- fase 45: sem bicho pequeno fora de cercado, não tem galinheiro (0 fileiras)
  select case when n >= 9 then 4 when n >= 6 then 3 when n >= 1 then 2 else 0 end
    from (select count(*) as n from fazenda_animais a
           where a.jogador_id = p_jogador and a.tipo in ('galinha', 'pato', 'coelho')
             and not exists (select 1 from fazenda_construcoes c where c.jogador_id = p_jogador and c.tipo = 'cercado_' || a.tipo)) x;
$$;

-- Fase 45: o pasto do começo só existe enquanto houver bicho grande (vaca, ovelha, porco) sem cercado
create or replace function public.fazenda_pasto(p_jogador uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from fazenda_animais a
                  where a.jogador_id = p_jogador and a.tipo in ('vaca', 'ovelha', 'porco')
                    and not exists (select 1 from fazenda_construcoes c where c.jogador_id = p_jogador and c.tipo = 'cercado_' || a.tipo));
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
  if v_quer = 0 then return 0; end if;
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
declare
  v_lin int := fazenda_galinheiro_linhas(p_jogador);
begin
  if exists (select 1 from generate_series(p_x, p_x + p_w - 1) gx, generate_series(p_y, p_y + p_h - 1) gy
              where not fazenda_livre(gx, gy) or not fazenda_no_terreno(p_zonas, gx, gy)) then
    raise exception 'lugar_reservado';
  end if;
  -- fase 45: o galinheiro (y 7 em diante, com as fileiras que cresceram) e o pasto só são
  -- reservados enquanto houver bicho sem cercado neles
  if v_lin > 0 and p_x <= 6 and p_y + p_h - 1 >= 7 and p_y <= 6 + v_lin then
    raise exception 'lugar_reservado';
  end if;
  if p_x <= 21 and p_x + p_w - 1 >= 16 and p_y <= 6 and fazenda_pasto(p_jogador) then
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
  v_custo int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;

  -- canteiro: não é item da loja, é um lugar de plantar (limite pelo nível e terrenos)
  if p_tipo = 'canteiro' then
    if (select count(*) from fazenda_canteiros where jogador_id = v_id)
       >= fazenda_limite_canteiros(fazenda_nivel(j.xp), fazenda_terrenos(j.zonas, j.direita)) then
      raise exception 'limite_canteiros';
    end if;
    perform fazenda_checar_lugar(v_id, fazenda_terrenos(j.zonas, j.direita), p_x, p_y, 1, 1);
    select min(g) into v_pos from generate_series(0, 299) g   -- fase 56: eram 0..99
     where not exists (select 1 from fazenda_canteiros where jogador_id = v_id and posicao = g);
    if v_pos is null then raise exception 'limite_canteiros'; end if;
    -- fase 70: canteiro novo espera os 8 min para dar XP de colheita (desmanchar e fazer de novo zerava)
    insert into fazenda_canteiros (jogador_id, posicao, estado, x, y, xp_em) values (v_id, v_pos, 'vazio', p_x, p_y, now());
    return jsonb_build_object('estado', fazenda_estado(v_id), 'posicao', v_pos);
  end if;

  select * into i from fazenda_itens where id = p_tipo;
  if not found then raise exception 'item_invalido'; end if;
  if fazenda_nivel(j.xp) < i.nivel_min then raise exception 'nivel_insuficiente'; end if;
  perform fazenda_checar_lugar(v_id, fazenda_terrenos(j.zonas, j.direita), p_x, p_y, i.largura, i.altura);
  -- fase 73: o que é da praia só vai na areia do Litoral (y 32 a 36)
  if i.categoria = 'praia' and not (p_y >= 32 and p_y + i.altura - 1 <= 36) then raise exception 'so_na_areia'; end if;
  if i.limite is not null   -- fase 57: painel solar e turbina sobem com o nível
     and (select count(*) from fazenda_construcoes where jogador_id = v_id and tipo = i.id)
         >= fazenda_limite_maquina(i.id, i.limite, fazenda_nivel(j.xp)) then
    raise exception 'limite_maquina';
  end if;
  -- itens por terreno (amoreira): mais terreno, mais pés (igual a maxItem em fazenda.js); fase 47: no
  -- pomar, cada fruta tem 1 pé e +1 a cada 2 terrenos (até 4); quem já passou fica com as que tem
  if i.por_terreno is not null
     and (select count(*) from fazenda_construcoes c join fazenda_itens k on k.id = c.tipo
           where c.jogador_id = v_id and (c.tipo = i.id or (i.grupo is not null and k.grupo = i.grupo)))
         >= (case when i.categoria = 'pomar'   -- fase 57: + os pés da melhoria "Mais pés de fruta"
                  then i.por_terreno * (1 + (j.zonas + j.direita) / 2) + fazenda_melhoria(v_id, 'pes')::int   -- (fase 78: + os da direita)
                  else i.por_terreno * (1 + j.zonas + j.direita) end) then
    raise exception 'limite_terreno';
  end if;
  if (select count(*) from fazenda_construcoes where jogador_id = v_id) >= fazenda_max_construcoes(fazenda_terrenos(j.zonas, j.direita)) then
    raise exception 'limite_construcoes';
  end if;
  -- fase 45: quem já tinha o bicho antes do cercado obrigatório ganha o primeiro cercado dele
  v_custo := case when i.efeito = 'cercado' and substr(i.id, 9) = any(coalesce(j.cercado_gratis, '{}')) then 0 else i.custo end;
  if j.moedas < v_custo then raise exception 'moedas_insuficientes'; end if;
  -- máquina elétrica nova: fecha a conta da energia antes (ela não gera pelo tempo de antes)
  if i.categoria = 'energia' then
    perform fazenda_energia_atualizar(v_id);
    update fazenda_jogadores set energia_em = now() where id = v_id;   -- (fase 46: a conta começa agora)
  end if;
  update fazenda_jogadores
     set moedas = moedas - v_custo,
         cercado_gratis = case when i.efeito = 'cercado' then array_remove(cercado_gratis, substr(i.id, 9)) else cercado_gratis end
   where id = v_id;
  -- fase 72: guarda o que pagou (desmanchar devolve a metade disso, não do preço de hoje)
  insert into fazenda_construcoes (jogador_id, x, y, tipo, colhido_em, pago) values (v_id, p_x, p_y, i.id, now(), v_custo);
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- Leva uma construção de (x, y) para (nx, ny)
-- fase 73b: p_leve devolve só {ok, x, y} (o jogo já mostra o item no lugar; a fazenda inteira a cada
-- movimento travava quem movia várias coisas seguidas). Sem ele, como antes (o jogo antigo no cache).
create or replace function public.fazenda_mover(p_token text, p_x int, p_y int, p_nx int, p_ny int, p_leve boolean default false)
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
    perform fazenda_checar_lugar(v_id, fazenda_terrenos(j.zonas, j.direita), p_nx, p_ny, 1, 1, null, null, v_pos);
    update fazenda_canteiros set x = p_nx, y = p_ny where jogador_id = v_id and posicao = v_pos;
    if p_leve then return jsonb_build_object('ok', true, 'x', p_nx, 'y', p_ny); end if;
    return jsonb_build_object('estado', fazenda_estado(v_id));
  end if;

  select k.* into i from fazenda_construcoes c join fazenda_itens k on k.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y;
  if not found then raise exception 'item_invalido'; end if;
  perform fazenda_checar_lugar(v_id, fazenda_terrenos(j.zonas, j.direita), p_nx, p_ny, i.largura, i.altura, p_x, p_y);
  if i.categoria = 'praia' and not (p_ny >= 32 and p_ny + i.altura - 1 <= 36) then raise exception 'so_na_areia'; end if;   -- fase 73
  update fazenda_construcoes set x = p_nx, y = p_ny
   where jogador_id = v_id and x = p_x and y = p_y;
  if not found then raise exception 'item_invalido'; end if;
  -- o que está guardado no baú e o que já chegou pelo cano na oficina vão junto (fase 39)
  update fazenda_bau_itens set x = p_nx, y = p_ny where jogador_id = v_id and x = p_x and y = p_y;
  update fazenda_oficina_itens set x = p_nx, y = p_ny where jogador_id = v_id and x = p_x and y = p_y;
  if p_leve then return jsonb_build_object('ok', true, 'x', p_nx, 'y', p_ny); end if;
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- Tira uma construção e devolve metade do preço (fase 72: do que pagou)
create or replace function public.fazenda_demolir(p_token text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_tipo text;
  v_pago int;   -- fase 72
  c      record;
begin
  -- canteiro: só sai vazio ou arado (planta crescendo, colha ou limpe antes)
  select * into c from fazenda_canteiros where jogador_id = v_id and x = p_x and y = p_y for update;
  if found then
    if c.estado = 'plantado' then raise exception 'canteiro_ocupado'; end if;
    delete from fazenda_canteiros where jogador_id = v_id and posicao = c.posicao;
    return jsonb_build_object('devolvido', 0, 'estado', fazenda_estado(v_id));
  end if;

  -- fase 45: cercado com bicho dentro não sai (o bicho não tem mais para onde ir)
  if exists (select 1 from fazenda_construcoes k join fazenda_animais a on a.jogador_id = k.jogador_id and 'cercado_' || a.tipo = k.tipo
              where k.jogador_id = v_id and k.x = p_x and k.y = p_y) then   -- (k: c é o registro do canteiro)
    raise exception 'cercado_com_bichos';
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
  -- fase 39: o que estava guardado no baú ou já tinha chegado na oficina volta para o celeiro
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  select v_id, x.item, sum(x.quantidade)::int from (
    select item, quantidade from fazenda_bau_itens where jogador_id = v_id and x = p_x and y = p_y
    union all
    select item, quantidade from fazenda_oficina_itens where jogador_id = v_id and x = p_x and y = p_y
  ) x where x.quantidade > 0 group by x.item
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  delete from fazenda_bau_itens where jogador_id = v_id and x = p_x and y = p_y;
  delete from fazenda_oficina_itens where jogador_id = v_id and x = p_x and y = p_y;

  delete from fazenda_construcoes where jogador_id = v_id and x = p_x and y = p_y
  returning tipo, pago into v_tipo, v_pago;
  if v_tipo is null then raise exception 'item_invalido'; end if;
  -- fase 72: metade do que pagou (com os preços novos, a metade do preço de hoje dava lucro); o que
  -- veio de presente (o lampião do começo) segue pela metade do preço
  v_pago := coalesce(v_pago, (select custo from fazenda_itens where id = v_tipo)) / 2;
  update fazenda_jogadores set moedas = moedas + v_pago where id = v_id;
  return jsonb_build_object('devolvido', v_pago, 'estado', fazenda_estado(v_id));
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
  select c.colhido_em, c.tipo, i.produz, i.produz_seg, i.produz_qtd, i.entradas into r
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
  update fazenda_construcoes set colhido_em = fazenda_colhido_agora(v_id, r.tipo) where jogador_id = v_id and x = p_x and y = p_y;
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
    v_n := least(p_receitas, fazenda_estoque_max_de(v_id) - r.estoque - (case when r.iniciado_em is null then 0 else 1 end));
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

-- Preço de cada personagem do avatar: quanto mais legal, mais caro (paga uma vez, fica seu)
create or replace function public.fazenda_avatar_precos()
returns jsonb language sql immutable as $$
  select '{"fazendeiro": 0, "fazendeira": 0, "rapaz": 3000, "mago": 20000, "viking": 35000, "cavaleiro": 50000}'::jsonb;
$$;
-- Fase 43: personagens que só saem com diamantes (paga uma vez, fica seu)
create or replace function public.fazenda_avatar_diamantes()
returns jsonb language sql immutable as $$
  select '{"soldado": 30, "barbaro": 40, "guarda": 50, "feiticeiro": 70, "fantasma": 100, "ciclope": 120, "diabinho": 150, "morcego": 200}'::jsonb;
$$;

-- Salva o avatar: o personagem (tipo) e o número de cada cor (0 = a cor original do personagem;
-- as cores ficam no cliente, em AVATAR_CORES de fazenda-arte.js). O que faltar vira 0.
create or replace function public.fazenda_avatar(p_token text, p_avatar jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v       jsonb;
  r       record;
  j       record;
  v_preco int;
  v_diam  int := 0;
begin
  if jsonb_typeof(p_avatar) is distinct from 'object' then raise exception 'avatar_invalido'; end if;
  if not (fazenda_avatar_precos() ? coalesce(p_avatar->>'tipo', 'fazendeiro')
          or fazenda_avatar_diamantes() ? coalesce(p_avatar->>'tipo', 'fazendeiro')
          or fazenda_avatar_exclusivos() ? coalesce(p_avatar->>'tipo', 'fazendeiro')) then   -- fase 69: os exclusivos
    raise exception 'avatar_invalido';
  end if;
  v := jsonb_build_object('tipo', coalesce(p_avatar->>'tipo', 'fazendeiro'));
  for r in select * from (values ('pele', 5), ('cabelo', 6), ('roupa', 8), ('calca', 6), ('chapeu', 6)) x(chave, n) loop
    if p_avatar ? r.chave then
      if jsonb_typeof(p_avatar->r.chave) <> 'number' or (p_avatar->>r.chave)::numeric % 1 <> 0
         or (p_avatar->>r.chave)::numeric not between 0 and r.n - 1 then
        raise exception 'avatar_invalido';
      end if;
      v := v || jsonb_build_object(r.chave, (p_avatar->>r.chave)::int);
    else
      v := v || jsonb_build_object(r.chave, 0);
    end if;
  end loop;
  -- personagem que ainda não é seu: compra agora (se tiver moedas)
  select * into j from fazenda_jogadores where id = v_id for update;
  v_preco := coalesce((fazenda_avatar_precos()->>(v->>'tipo'))::int, 0);
  v_diam := coalesce((fazenda_avatar_diamantes()->>(v->>'tipo'))::int, 0);
  if (v->>'tipo') = any(j.avatares) then
    v_preco := 0; v_diam := 0;
  elsif fazenda_avatar_exclusivos() ? (v->>'tipo') then   -- fase 69: exclusivo não se compra, só se ganha
    raise exception 'avatar_exclusivo';
  elsif v_diam > 0 then   -- personagem de diamante
    if j.diamantes < v_diam then raise exception 'diamantes_insuficientes'; end if;
    update fazenda_jogadores set diamantes = diamantes - v_diam, avatares = array_append(avatares, v->>'tipo') where id = v_id;
    insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, 'avatar:' || (v->>'tipo'), v_diam);
  elsif v_preco > 0 then
    if j.moedas < v_preco then raise exception 'moedas_insuficientes'; end if;
    update fazenda_jogadores set moedas = moedas - v_preco, avatares = array_append(avatares, v->>'tipo') where id = v_id;
  end if;
  update fazenda_jogadores set avatar = v where id = v_id;
  return jsonb_build_object('avatar', v, 'pagou', v_preco, 'pagou_diamantes', v_diam, 'estado', fazenda_estado(v_id));
end;
$$;

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

-- Tira os peixes do cesto do Bira: 1 a cada 30 min desde lago_em, até 16 (o que passar disso
-- se perde: o cesto estava cheio). Cada peixe é sorteado pela chance (fazenda_peixes).
-- Tira do cesto do Bira os peixes que já estão nele (no máximo p_max): sorteia cada um, conta
-- nas estatísticas e anda o relógio do cesto. Devolve {peixe: quantidade}. Usada pela pesca na
-- mão (fazenda_pescar) e pelo baú encostado no lago (fase 39).
create or replace function public.fazenda_cesto(p_jogador uuid, p_max int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  j         record;
  p         record;
  v_estatua boolean := fazenda_tem_efeito(p_jogador, 'chico');
  v_n       int;
  v_k       int;
  v_r       numeric;
  v_soma    int;
  v_peixes  jsonb := '{}'::jsonb;
begin
  select zonas, lago_em into j from fazenda_jogadores where id = p_jogador for update;
  if j.zonas < 3 or j.lago_em is null then return v_peixes; end if;
  v_n := least(floor(extract(epoch from now() - j.lago_em) / 1800)::int, fazenda_cesto_max(p_jogador), greatest(coalesce(p_max, 0), 0));   -- fase 82: 24 com o cesto grande
  if v_n <= 0 then return v_peixes; end if;
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
  -- o cesto enche até 16 (8 h): o que passou disso não conta; o que ficou no cesto continua lá
  update fazenda_jogadores set lago_em = greatest(j.lago_em, now() - make_interval(secs => fazenda_cesto_max(p_jogador) * 1800)) + make_interval(secs => v_n * 1800)
   where id = p_jogador;
  insert into fazenda_estatisticas (jogador_id) values (p_jogador) on conflict do nothing;
  update fazenda_estatisticas set peixes = peixes + v_n, lendarios = lendarios + coalesce((v_peixes->>'velho_chico')::int, 0)
   where jogador_id = p_jogador;
  return v_peixes;
end;
$$;

create or replace function public.fazenda_pescar(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id      uuid := fazenda_auth(p_token);
  j         record;
  v_peixes  jsonb;
  v_n       int;
  v_xp      int;
  v_lend    int;
begin
  select zonas, lago_em into j from fazenda_jogadores where id = v_id for update;
  if j.zonas < 3 then raise exception 'sem_lago'; end if;
  if j.lago_em is null then
    update fazenda_jogadores set lago_em = now() where id = v_id;
    raise exception 'cesto_vazio';
  end if;
  v_peixes := fazenda_cesto(v_id, 16);
  select coalesce(sum(e.value::int), 0)::int into v_n from jsonb_each_text(v_peixes) e;
  if v_n <= 0 then raise exception 'cesto_vazio'; end if;
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  select v_id, e.key, e.value::int from jsonb_each_text(v_peixes) e
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  select coalesce(sum(k.xp * e.value::int), 0)::int into v_xp
    from jsonb_each_text(v_peixes) e join fazenda_culturas k on k.id = e.key;
  v_lend := coalesce((v_peixes->>'velho_chico')::int, 0);
  update fazenda_jogadores set xp = xp + v_xp where id = v_id;
  perform fazenda_missao(v_id, 'colher', v_n);
  return jsonb_build_object('peixes', v_peixes, 'qtd', v_n, 'xp', v_xp, 'lendario', v_lend, 'estado', fazenda_estado(v_id));
end;
$$;

-- Leva tudo o que está no baú para o celeiro (na mão: sem cano e sem energia)
create or replace function public.fazenda_bau_esvaziar(p_token text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id  uuid := fazenda_auth(p_token);
  v_qtd int;
begin
  if not exists (select 1 from fazenda_construcoes where jogador_id = v_id and x = p_x and y = p_y and tipo = 'bau') then
    raise exception 'item_invalido';
  end if;
  -- fase 70: tira e entrega numa coisa só (somar, entregar e depois apagar deixava duas chamadas juntas
  -- entregarem tudo duas vezes)
  with tirado as (delete from fazenda_bau_itens where jogador_id = v_id and x = p_x and y = p_y returning item, quantidade),
       soma as (select item, sum(quantidade)::int as q from tirado where quantidade > 0 group by item),
       entregue as (insert into fazenda_celeiro (jogador_id, item, quantidade) select v_id, item, q from soma
                    on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade)
  select coalesce(sum(q), 0)::int into v_qtd from soma;
  return jsonb_build_object('qtd', v_qtd, 'estado', fazenda_estado(v_id));
end;
$$;

-- Liga ou desliga o gerador a biomassa (toque nele). Ao ligar já queima o primeiro milho.
-- Fase 64: só uma vez a cada 30 min (colhido_em = a última queima na hora; o gerador não usa essa
-- coluna para mais nada). Ligar e desligar seguido virava 25 ⚡ a cada toque. O milho queimado na hora
-- paga a primeira meia hora: iniciado_em fica 30 min para a frente (o ritmo é 1 milho a cada 30 min).
create or replace function public.fazenda_gerador(p_token text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  r    record;
begin
  select c.iniciado_em, c.colhido_em, i.efeito into r
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
  if r.colhido_em is null or r.colhido_em <= now() - interval '30 minutes' then
    update fazenda_celeiro set quantidade = quantidade - 1 where jogador_id = v_id and item = 'milho';
    update fazenda_jogadores set energia = least(energia + 25, fazenda_capacidade(v_id)) where id = v_id;
    update fazenda_construcoes set iniciado_em = now() + interval '30 minutes', colhido_em = now()
     where jogador_id = v_id and x = p_x and y = p_y;
  else
    -- (queimou na hora há menos de 30 min: liga sem queimar; o primeiro milho sai daqui a 30 min)
    update fazenda_construcoes set iniciado_em = now() where jogador_id = v_id and x = p_x and y = p_y;
  end if;
  return jsonb_build_object('ligado', true, 'estado', fazenda_estado(v_id));
end;
$$;

-- Anúncio premiado: o jogador assistiu até o fim e tudo o que está em andamento anda
-- 30 minutos — plantas, animais, oficinas, amoreira, ajudantes e geradores. Nada passa do
-- ponto (o que amadurece fica maduro, não murcha).
-- Fase 70: fechada para o jogo (os anúncios estão desligados e chamar pelo console dava 1 diamante a
-- cada 10 s). Quando voltarem: 1 a cada 5 min, 6 por dia, e o diamante só nos 3 primeiros do dia.
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
  v_n   int;   -- fase 70: os anúncios de hoje
begin
  select anuncio_em, anuncio_dia, anuncio_n into j from fazenda_jogadores where id = v_id for update;
  if j.anuncio_em is not null and j.anuncio_em > now() - interval '5 minutes' then
    raise exception 'anuncio_cedo';
  end if;
  v_n := case when j.anuncio_dia = fazenda_hoje() then j.anuncio_n else 0 end;   -- fase 70
  if v_n >= 6 then raise exception 'anuncio_limite'; end if;
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
         diamantes = diamantes + (v_n < 3)::int,   -- fase 31: cada anúncio também dá 1 diamante (fase 70: os 3 primeiros do dia)
         anuncio_em = now(), anuncio_dia = fazenda_hoje(), anuncio_n = v_n + 1
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
-- Fase 32: compra de diamantes pelo Mercado Pago (Checkout Pro)
-- A Edge Function fazenda-diamantes (supabase/functions) cria a compra aqui, abre a página
-- de pagamento e, quando o Mercado Pago avisa, confere o pagamento na API dele e chama
-- fazenda_compra_pagamento. As duas funções internas não ficam abertas para a chave anon.
-- ------------------------------------------------------------
create table if not exists public.fazenda_compras (
  id          uuid primary key default gen_random_uuid(),
  jogador_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  pacote      text not null,
  valor       numeric(10, 2) not null,
  diamantes   int  not null,
  status      text not null default 'pendente' check (status in ('pendente', 'aprovada', 'recusada', 'estornada')),
  mp_id       text unique,
  criado_em   timestamptz not null default now(),
  pago_em     timestamptz
);
create index if not exists fazenda_compras_jogador on public.fazenda_compras (jogador_id, criado_em);
alter table public.fazenda_compras enable row level security;
revoke all on public.fazenda_compras from anon, authenticated;

-- Pacotes à venda: R$ 1 = 24 diamantes, e os maiores vêm com bônus (fase 33):
-- R$ 5 +10, R$ 10 +30, R$ 20 +100. A compra guarda os diamantes do pacote na hora em que é criada.
create or replace function public.fazenda_pacotes_diamantes()
returns jsonb language sql immutable as $$
  select '[{"id":"p1","valor":1,"diamantes":24,"bonus":0},
           {"id":"p5","valor":5,"diamantes":130,"bonus":10},
           {"id":"p10","valor":10,"diamantes":270,"bonus":30},
           {"id":"p20","valor":20,"diamantes":580,"bonus":100}]'::jsonb;
$$;

-- Edge Function: o jogador escolheu um pacote. Cria a compra pendente.
create or replace function public.fazenda_compra_criar(p_token text, p_pacote text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  v_p  jsonb;
  v_c  record;
begin
  select p into v_p from jsonb_array_elements(fazenda_pacotes_diamantes()) p where p->>'id' = p_pacote;
  if v_p is null then raise exception 'pacote_invalido'; end if;
  -- contra clique repetido: no máximo 10 compras abertas por hora
  if (select count(*) from fazenda_compras where jogador_id = v_id and criado_em > now() - interval '1 hour') >= 10 then
    raise exception 'muitas_compras';
  end if;
  insert into fazenda_compras (jogador_id, pacote, valor, diamantes)
  values (v_id, p_pacote, (v_p->>'valor')::numeric, (v_p->>'diamantes')::int)
  returning * into v_c;
  return jsonb_build_object('id', v_c.id, 'pacote', v_c.pacote, 'valor', v_c.valor, 'diamantes', v_c.diamantes);
end;
$$;

-- Edge Function: o Mercado Pago avisou e a função já conferiu o pagamento na API dele.
-- Aprovado (e no valor certo) credita os diamantes uma vez só; estorno/chargeback tira de volta.
create or replace function public.fazenda_compra_pagamento(p_compra uuid, p_mp_id text, p_status text, p_valor numeric)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  c record;
begin
  select * into c from fazenda_compras where id = p_compra for update;
  if not found then return jsonb_build_object('resultado', 'desconhecida'); end if;
  if c.mp_id is not null and c.mp_id <> p_mp_id and c.status = 'aprovada' then
    return jsonb_build_object('resultado', 'outro_pagamento');   -- já foi paga por outro pagamento
  end if;

  if p_status = 'approved' and c.status in ('pendente', 'recusada') then
    if p_valor < c.valor then return jsonb_build_object('resultado', 'valor_errado'); end if;
    update fazenda_compras set status = 'aprovada', mp_id = p_mp_id, pago_em = now() where id = c.id;
    update fazenda_jogadores set diamantes = diamantes + c.diamantes where id = c.jogador_id;
    return jsonb_build_object('resultado', 'creditada', 'diamantes', c.diamantes);
  elsif p_status in ('refunded', 'charged_back') and c.status = 'aprovada' then
    update fazenda_compras set status = 'estornada' where id = c.id;
    update fazenda_jogadores set diamantes = greatest(diamantes - c.diamantes, 0) where id = c.jogador_id;
    return jsonb_build_object('resultado', 'estornada');
  elsif p_status in ('rejected', 'cancelled') and c.status = 'pendente' then
    update fazenda_compras set status = 'recusada', mp_id = p_mp_id where id = c.id;
    return jsonb_build_object('resultado', 'recusada');
  end if;
  return jsonb_build_object('resultado', 'nada');
end;
$$;

-- O jogador voltou do Mercado Pago (fazenda.html?compra=...): como está a compra?
create or replace function public.fazenda_compra_status(p_token text, p_compra uuid)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth_ler(p_token);   -- fase 71: só lê, sem a fila de uma por vez
  c    record;
begin
  select * into c from fazenda_compras where id = p_compra and jogador_id = v_id;
  if not found then raise exception 'compra_invalida'; end if;
  return jsonb_build_object('status', c.status, 'diamantes', c.diamantes, 'estado', fazenda_estado(v_id));
end;
$$;

-- ------------------------------------------------------------
-- Fase 34: fazenda ligada a uma conta Google, para voltar a ela sem o código de recuperação.
-- A Edge Function (rota /google) confere o login do Google (assinatura, aud, validade) e só
-- então chama ligar/entrar com o "sub" (id fixo da conta). Ligar e entrar não ficam abertas
-- para a chave anon; desligar sim (precisa do token da sessão).
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists google_sub text;
alter table public.fazenda_jogadores add column if not exists google_email text;
create unique index if not exists fazenda_jogadores_google on public.fazenda_jogadores (google_sub) where google_sub is not null;

create or replace function public.fazenda_google_ligar(p_token text, p_sub text, p_email text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
begin
  if coalesce(p_sub, '') = '' then raise exception 'google_invalido'; end if;
  -- uma conta Google abre uma fazenda só
  if exists (select 1 from fazenda_jogadores where google_sub = p_sub and id <> v_id) then
    raise exception 'google_em_uso';
  end if;
  update fazenda_jogadores set google_sub = p_sub, google_email = p_email where id = v_id;
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

create or replace function public.fazenda_google_entrar(p_sub text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid;
begin
  select id into v_id from fazenda_jogadores where google_sub = p_sub and coalesce(p_sub, '') <> '';
  if v_id is null then raise exception 'google_sem_fazenda'; end if;
  if exists (select 1 from fazenda_jogadores where id = v_id and banido_em is not null) then raise exception 'conta_banida'; end if;
  perform fazenda_tick(v_id);
  return jsonb_build_object('token', fazenda_nova_sessao(v_id), 'estado', fazenda_estado(v_id));
end;
$$;

create or replace function public.fazenda_google_desligar(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
begin
  update fazenda_jogadores set google_sub = null, google_email = null where id = v_id;
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- ------------------------------------------------------------
-- Fase 43: o que fazer com os diamantes. Além de colher agora (1 por planta) e dos personagens
-- (fazenda_avatar_diamantes), a loja tem: XP em dobro por 1 hora, um pacote de XP (10% do
-- nível, até 3 por dia), o café dos ajudantes (trabalham em dobro por 2 horas), encher a
-- energia (1 diamante a cada 50 ⚡ que faltam) e terminar a receita de uma oficina na hora
-- (1 diamante por hora que falta). O jogo monta a loja com fazenda_loja_diamantes.
-- ------------------------------------------------------------
create table if not exists public.fazenda_diamantes_usos (
  id         bigint generated always as identity primary key,
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  item       text not null,
  diamantes  int  not null,
  em         timestamptz not null default now()
);
create index if not exists fazenda_diamantes_usos_jogador on public.fazenda_diamantes_usos (jogador_id, item, em);
alter table public.fazenda_diamantes_usos enable row level security;
revoke all on public.fazenda_diamantes_usos from anon, authenticated;

create or replace function public.fazenda_loja_diamantes()
returns jsonb language sql immutable as $$
  -- fase 72: o café dura 4 h; 1 diamante enche 150 ⚡; salvar murchas, 1 a cada 25 plantas; colher
  -- agora, 1 a cada 4 h que faltam
  select '{"xp2": {"preco": 15, "horas": 1},
           "xp": {"preco": 10, "pct": 10, "por_dia": 3},
           "cafe": {"preco": 10, "horas": 4},
           "energia": {"por": 150},
           "oficina": {"por_hora": 1},
           "murchas": {"preco": 1, "por": 25},
           "agora": {"horas": 4},
           "moedas": {"preco": 10, "por_nivel": 2000},
           "raros": {"por": 10000, "por_semana": 2,
                     "itens": ["madeira_nobre", "corda_naval", "pedra_cantaria", "ferro_forjado", "ancora", "leme_dourado", "perola_negra", "luva_perks"]}}'::jsonb;   -- fase 84: a loja de raros   -- fase 79: 10 diamantes = 2.000 moedas por nível
$$;

-- o dia da loja (o pacote de XP tem limite por dia) é o de Brasília (UTC-3)
create or replace function public.fazenda_diamantes_hoje(p_jogador uuid, p_item text)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from fazenda_diamantes_usos
   where jogador_id = p_jogador and item = p_item
     and ((em at time zone 'UTC') - interval '3 hours')::date = ((now() at time zone 'UTC') - interval '3 hours')::date;
$$;

-- XP em dobro: todo XP que entra enquanto vale (colher, bichos, vender, missões...) vem dobrado.
-- O pacote de XP liga fazenda.xp_puro para não dobrar.
-- Fase 49: e +50% com as metas de nível em dia (bonus_nivel = o nível de agora); os dois somam
create or replace function public.fazenda_xp_dobro()
returns trigger language plpgsql set search_path = public as $$
declare
  v_mult real := 1;
begin
  if new.xp > old.xp and coalesce(current_setting('fazenda.xp_puro', true), '') <> '1' then
    if new.xp2_ate is not null and new.xp2_ate > now() then v_mult := v_mult + 1; end if;
    if new.bonus_nivel is not null and new.bonus_nivel = fazenda_nivel(old.xp) then v_mult := v_mult + 0.5; end if;
    -- fase 57: fazenda completa (do 20 em diante, metas em dia): mais 25%
    if new.bonus_nivel is not null and new.bonus_nivel = fazenda_nivel(old.xp) and fazenda_nivel(old.xp) >= 20 then v_mult := v_mult + 0.25; end if;
    -- fase 70: a metade a mais do XP em dobro é XP comprado (não conta no evento)
    if new.xp2_ate is not null and new.xp2_ate > now() then new.xp_pago := new.xp_pago + (new.xp - old.xp); end if;
    if v_mult > 1 then new.xp := old.xp + round((new.xp - old.xp) * v_mult)::int; end if;
  end if;
  -- fase 70: pacote de XP e XP do calendário dourado: tudo comprado
  if new.xp > old.xp and coalesce(current_setting('fazenda.xp_pago', true), '') = '1' then
    new.xp_pago := old.xp_pago + (new.xp - old.xp);
  end if;
  return new;
end;
$$;
drop trigger if exists fazenda_xp_dobro on public.fazenda_jogadores;
create trigger fazenda_xp_dobro before update of xp on public.fazenda_jogadores
  for each row execute function public.fazenda_xp_dobro();

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
    perform set_config('fazenda.xp_pago', '1', true);   -- fase 70: não conta no evento
    update fazenda_jogadores set diamantes = diamantes - v_preco, xp = xp + v_xp where id = v_id;
    perform set_config('fazenda.xp_puro', '', true);
    perform set_config('fazenda.xp_pago', '', true);

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
    -- fase 48: o diamante salva todas as plantas murchas (voltam maduras, sem problemas); fase 72: 1 a
    -- cada 25 plantas (era 1 para todas)
    select count(*) into v_cap from fazenda_canteiros c join fazenda_culturas k on k.id = c.cultura
     where c.jogador_id = v_id and c.estado = 'plantado'
       and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600));
    if v_cap = 0 then raise exception 'nada_a_fazer'; end if;
    v_preco := (v_loja->>'preco')::int * ceil(v_cap / coalesce((v_loja->>'por')::numeric, v_cap))::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    update fazenda_canteiros c
       set plantado_em = now() - make_interval(secs => k.tempo_seg), erva = false, praga = false, seco = false, prox_evento = null
      from fazenda_culturas k
     where c.jogador_id = v_id and c.estado = 'plantado' and k.id = c.cultura
       and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600));
    update fazenda_jogadores set diamantes = diamantes - v_preco where id = v_id;

  elsif p_item = 'oficina' then
    perform fazenda_oficinas_andar(v_id);
    select c.iniciado_em, ceil(i.produz_seg * (1 - fazenda_oficina_rapidez(v_id, c.tipo)))::int as produz_seg, i.entradas into o
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

  elsif p_item = 'moedas' then   -- fase 79: diamantes viram moedas (o pacote cresce com o nível)
    v_preco := (v_loja->>'preco')::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    v_nivel := fazenda_nivel(j.xp);
    -- moeda comprada não conta no evento (o gatilho soma o que entra; aqui já desconta)
    update fazenda_jogadores
       set diamantes = diamantes - v_preco, moedas = moedas + v_nivel * (v_loja->>'por_nivel')::int,
           moedas_ganhas = moedas_ganhas - v_nivel * (v_loja->>'por_nivel')::int
     where id = v_id;
  end if;

  insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, p_item, v_preco);
  return jsonb_build_object('item', p_item, 'diamantes', v_preco, 'xp', v_xp, 'estado', fazenda_estado(v_id));
end;
$$;

-- ------------------------------------------------------------
-- Fase 45: o cercado vem antes do bicho. O galinheiro na frente do celeiro e o pasto do começo
-- saem; quem já tinha bicho sem cercado fica com eles (só enquanto tiver bicho lá) e ganha o
-- primeiro cercado de cada uma dessas espécies de graça. A lista é feita uma vez só (quem tem
-- cercado_gratis null), para não virar moeda de graça (desmanchar devolve metade do preço).
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists cercado_gratis text[];
update public.fazenda_jogadores j
   set cercado_gratis = coalesce((select array_agg(distinct a.tipo order by a.tipo) from public.fazenda_animais a
                                   where a.jogador_id = j.id
                                     and not exists (select 1 from public.fazenda_construcoes c
                                                      where c.jogador_id = j.id and c.tipo = 'cercado_' || a.tipo)), '{}')
 where j.cercado_gratis is null;
alter table public.fazenda_jogadores alter column cercado_gratis set default '{}';

-- Fase 51: as barracas da feira. Ficam numa clareira da mata, à esquerda do celeiro (fora do
-- terreno, onde não dá para expandir): todo mundo já começa com uma e pode comprar mais 3.
-- Cada barraca dá 2 anúncios abertos na feira.
alter table public.fazenda_jogadores add column if not exists barracas smallint not null default 1;
-- (num rascunho a barraca era item de construir; quem tiver uma recebe as moedas de volta)
update public.fazenda_jogadores j set moedas = j.moedas + 800 * k.n
  from (select jogador_id, count(*)::int n from public.fazenda_construcoes where tipo = 'barraca' group by 1) k
 where k.jogador_id = j.id;
delete from public.fazenda_construcoes where tipo = 'barraca';
delete from public.fazenda_itens where id = 'barraca';

-- ------------------------------------------------------------
-- Fase 50: a feira entre jogadores (como no SimCity). Cada um anuncia um lote do celeiro (os itens
-- saem na hora e ficam guardados no anúncio) com o preço por unidade entre metade e o triplo do
-- preço de venda (para ninguém passar moedas de uma conta para outra com preço absurdo). Outro
-- jogador compra o lote inteiro e o vendedor recebe na hora, tudo (fase 51: sem taxa; antes, 5%).
-- Quantos anúncios dá para ter vem das barracas da feira: 2 por barraca (começa com 1; até 4).
-- O anúncio vale 2 dias; vencido, os itens voltam para o celeiro do vendedor.
-- ------------------------------------------------------------
create table if not exists public.fazenda_feira (
  id           bigint generated always as identity primary key,
  vendedor_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  item         text not null references public.fazenda_culturas(id),
  qtd          int  not null check (qtd > 0),
  preco        int  not null check (preco > 0),   -- por unidade
  criado_em    timestamptz not null default now(),
  comprador_id uuid references public.fazenda_jogadores(id) on delete set null,
  vendido_em   timestamptz,
  visto        boolean not null default false     -- o vendedor já foi avisado da venda
);
create index if not exists fazenda_feira_abertos on public.fazenda_feira (item, preco) where vendido_em is null;
create index if not exists fazenda_feira_vendedor on public.fazenda_feira (vendedor_id, vendido_em);
create index if not exists fazenda_feira_comprador on public.fazenda_feira (comprador_id, vendido_em);
alter table public.fazenda_feira enable row level security;
revoke all on public.fazenda_feira from anon, authenticated;

create or replace function public.fazenda_feira_regras()
returns jsonb language sql immutable as $$
  select '{"taxa": 0, "min": 0.5, "max": 3, "horas": 48, "por_barraca": 2, "barracas_max": 4, "barraca_nivel": 5,
           "barraca_precos": [800, 1600, 2400], "compras_dia": 50, "qtd_max": 99}'::jsonb;
$$;

-- Fase 51: quantos anúncios abertos dá para ter: 2 por barraca da feira
create or replace function public.fazenda_feira_limite(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select (fazenda_feira_regras()->>'por_barraca')::int
         * coalesce((select barracas from fazenda_jogadores where id = p_jogador), 1)::int;
$$;

-- Fase 51: compra mais uma barraca na feira (do nível 5 em diante, até 4): 800, 1600 e 2400 moedas
create or replace function public.fazenda_feira_barraca(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_r     jsonb := fazenda_feira_regras();
  j       record;
  v_preco int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  if j.barracas >= (v_r->>'barracas_max')::int then raise exception 'limite_barracas'; end if;
  if fazenda_nivel(j.xp) < (v_r->>'barraca_nivel')::int then raise exception 'nivel_insuficiente'; end if;
  v_preco := (v_r->'barraca_precos'->>(j.barracas - 1))::int;
  if j.moedas < v_preco then raise exception 'moedas_insuficientes'; end if;
  update fazenda_jogadores set moedas = moedas - v_preco, barracas = barracas + 1 where id = v_id;
  return jsonb_build_object('barracas', j.barracas + 1, 'estado', fazenda_estado(v_id));
end;
$$;

-- o preço mínimo e máximo por unidade de um item
create or replace function public.fazenda_feira_faixa(p_item text)
returns int[] language sql stable security definer set search_path = public as $$
  select case when k.tipo = 'raro'   -- fase 60: material raro vai de venda (o mínimo) até o triplo
              then array[k.venda, k.venda * 3]
              else array[greatest(1, floor(k.venda * (fazenda_feira_regras()->>'min')::numeric))::int,
                         greatest(1, ceil(k.venda * (fazenda_feira_regras()->>'max')::numeric))::int] end
    from fazenda_culturas k where k.id = p_item and k.venda > 0;
$$;

-- o que venceu sem vender volta para o celeiro do vendedor
create or replace function public.fazenda_feira_vencidos(p_jogador uuid)
returns void language sql security definer set search_path = public as $$
  with v as (
    delete from fazenda_feira
     where vendedor_id = p_jogador and vendido_em is null
       and criado_em < now() - make_interval(hours => (fazenda_feira_regras()->>'horas')::int)
    returning item, qtd)
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  select p_jogador, item, sum(qtd)::int from v group by item
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
$$;

create or replace function public.fazenda_feira_anunciar(p_token text, p_item text, p_qtd int, p_preco int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
begin
  perform fazenda_feira_criar(v_id, p_item, p_qtd, p_preco);   -- fase 67: as checagens ficam lá (o chat usa também)
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

create or replace function public.fazenda_feira_cancelar(p_token text, p_id bigint)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  a    record;
begin
  delete from fazenda_feira where id = p_id and vendedor_id = v_id and vendido_em is null returning item, qtd into a;
  if not found then raise exception 'anuncio_invalido'; end if;
  insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, a.item, a.qtd)
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

create or replace function public.fazenda_feira_comprar(p_token text, p_id bigint)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_r     jsonb := fazenda_feira_regras();
  a       record;
  v_total int;
  v_taxa  int;
begin
  select * into a from fazenda_feira where id = p_id for update;
  if not found or a.vendido_em is not null
     or a.criado_em < now() - make_interval(hours => (v_r->>'horas')::int) then
    raise exception 'anuncio_invalido';   -- já vendido, cancelado ou vencido
  end if;
  if a.vendedor_id = v_id then raise exception 'anuncio_seu'; end if;
  -- fase 67: separado para quem pediu no chat (por 2 h, só essa pessoa compra)
  if a.reservado_para is not null and a.reservado_para <> v_id and a.reservado_ate > now() then raise exception 'anuncio_reservado'; end if;
  if (select count(*) from fazenda_feira where comprador_id = v_id and vendido_em > now() - interval '1 day')
     >= (v_r->>'compras_dia')::int then
    raise exception 'limite_compras';
  end if;
  v_total := a.qtd * a.preco;
  v_taxa := ceil(v_total * (v_r->>'taxa')::int / 100.0)::int;
  -- fase 70: segura os dois sempre na mesma ordem (dois comprando um do outro ao mesmo tempo travavam)
  perform 1 from fazenda_jogadores where id in (v_id, a.vendedor_id) order by id for update;
  if (select moedas from fazenda_jogadores where id = v_id) < v_total then raise exception 'moedas_insuficientes'; end if;
  update fazenda_jogadores set moedas = moedas - v_total where id = v_id;
  -- fase 70: o que entra pela barraca não conta em "mais moedas" do evento (já conta em "vendeu")
  update fazenda_jogadores set moedas = moedas + v_total - v_taxa, moedas_ganhas = moedas_ganhas - (v_total - v_taxa)
   where id = a.vendedor_id;
  insert into fazenda_celeiro (jogador_id, item, quantidade, da_feira) values (v_id, a.item, a.qtd, a.qtd)   -- fase 56: da_feira
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade,
                                               da_feira = fazenda_celeiro.da_feira + excluded.da_feira;
  update fazenda_feira set comprador_id = v_id, vendido_em = now() where id = p_id;
  return jsonb_build_object('item', a.item, 'qtd', a.qtd, 'total', v_total,
                            'vendedor', (select apelido from fazenda_jogadores where id = a.vendedor_id),
                            'estado', fazenda_estado(v_id));
end;
$$;

-- as ofertas abertas dos outros (as mais baratas primeiro; com p_item, só daquele item) e as suas.
-- Fase 67: a reservada para outra pessoa não aparece enquanto a reserva vale; a reservada para você vem primeiro.
create or replace function public.fazenda_feira_lista(p_token text, p_item text default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth_ler(p_token);   -- fase 71: só lê, sem a fila de uma por vez
  v_r  jsonb := fazenda_feira_regras();
begin
  perform fazenda_feira_vencidos(v_id);
  return jsonb_build_object(
    'regras', v_r,
    'ofertas', coalesce((
      select jsonb_agg(o order by (o ? 'reservado_ate') desc, (o->>'preco')::int, (o->>'id')::bigint) from (
        select jsonb_build_object('id', f.id, 'item', f.item, 'qtd', f.qtd, 'preco', f.preco, 'vendedor', j.apelido,
                                  'avatar', j.avatar, 'ate', f.criado_em + make_interval(hours => (v_r->>'horas')::int))
               || case when f.reservado_para = v_id and f.reservado_ate > now() then jsonb_build_object('reservado_ate', f.reservado_ate) else '{}'::jsonb end as o
          from fazenda_feira f join fazenda_jogadores j on j.id = f.vendedor_id
         where f.vendido_em is null and f.vendedor_id <> v_id
           and f.criado_em >= now() - make_interval(hours => (v_r->>'horas')::int)
           and (f.reservado_para is null or f.reservado_para = v_id or f.reservado_ate <= now())
           and (p_item is null or f.item = p_item)
         order by (f.reservado_para = v_id and f.reservado_ate > now()) desc nulls last, f.preco, f.id
         limit 60) x), '[]'::jsonb),
    'itens', coalesce((
      select jsonb_agg(distinct f.item) from fazenda_feira f
       where f.vendido_em is null and f.vendedor_id <> v_id
         and f.criado_em >= now() - make_interval(hours => (v_r->>'horas')::int)
         and (f.reservado_para is null or f.reservado_para = v_id or f.reservado_ate <= now())), '[]'::jsonb),
    'compras_hoje', (select count(*) from fazenda_feira where comprador_id = v_id and vendido_em > now() - interval '1 day'));
end;
$$;

-- ------------------------------------------------------------
-- Fase 53: administração do jogo. admin = 'dono' (escolhe quem é admin; começa com o cjesse) ou
-- 'admin' (bane e desbane). Conta banida não entra mais (fazenda_auth, recuperar e Google), some do
-- ranking, das visitas e da feira (os anúncios abertos voltam para o celeiro dela). Admin não bane
-- admin: o dono tira o admin antes. Tudo fica anotado em fazenda_admin_log.
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists admin text;
alter table public.fazenda_jogadores drop constraint if exists fazenda_jogadores_admin_check;
alter table public.fazenda_jogadores add constraint fazenda_jogadores_admin_check check (admin in ('dono', 'admin'));
alter table public.fazenda_jogadores add column if not exists banido_em timestamptz;
alter table public.fazenda_jogadores add column if not exists banido_motivo text;
create table if not exists public.fazenda_admin_log (
  id        bigint generated always as identity primary key,
  admin_id  uuid references public.fazenda_jogadores(id) on delete set null,
  alvo_id   uuid references public.fazenda_jogadores(id) on delete set null,
  acao      text not null,   -- banir, desbanir, dar_admin, tirar_admin, novo_codigo (fase 55)
  motivo    text,
  em        timestamptz not null default now()
);
alter table public.fazenda_admin_log enable row level security;
revoke all on public.fazenda_admin_log from anon, authenticated;
-- o primeiro dono: o cjesse (o de mais XP, se tiver mais de um com esse apelido), só se ainda não houver dono
update public.fazenda_jogadores set admin = 'dono'
 where id = (select id from public.fazenda_jogadores where lower(btrim(apelido)) = 'cjesse' order by xp desc limit 1)
   and not exists (select 1 from public.fazenda_jogadores where admin = 'dono');

-- quem chama é admin? devolve o id (senão, sem_permissao)
create or replace function public.fazenda_admin_id(p_token text, p_dono boolean default false)
returns uuid
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_papel text := (select admin from fazenda_jogadores where id = v_id);
begin
  if v_papel is null or (p_dono and v_papel <> 'dono') then raise exception 'sem_permissao'; end if;
  return v_id;
end;
$$;

-- a lista para o painel: sem busca, os banidos primeiro e depois os mais novos; com busca, pelo apelido
create or replace function public.fazenda_admin_jogadores(p_token text, p_busca text default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_admin_id(p_token);
  v_busca text := nullif(btrim(coalesce(p_busca, '')), '');
begin
  return jsonb_build_object(
    'total', (select count(*) from fazenda_jogadores),
    'banidos', (select count(*) from fazenda_jogadores where banido_em is not null),
    'jogadores', coalesce((select jsonb_agg(jsonb_build_object(
        'id', j.id, 'apelido', j.apelido, 'avatar', j.avatar, 'nivel', fazenda_nivel(j.xp),
        'criado_em', j.criado_em, 'visto_em', j.visto_em, 'admin', j.admin,
        'banido_em', j.banido_em, 'banido_motivo', j.banido_motivo, 'eu', j.id = v_id) order by j.ordem)
      from (select k.*, row_number() over (order by
                     case when v_busca is null then (k.banido_em is null)::int end,
                     case when v_busca is not null then -k.xp end,
                     k.criado_em desc) as ordem
              from fazenda_jogadores k
             where v_busca is null
                or k.apelido ilike '%' || replace(replace(replace(v_busca, '\', '\\'), '%', '\%'), '_', '\_') || '%'
             order by ordem limit 60) j), '[]'::jsonb),
    'log', coalesce((select jsonb_agg(jsonb_build_object(
        'acao', l.acao, 'motivo', l.motivo, 'em', l.em,
        'admin', (select apelido from fazenda_jogadores where id = l.admin_id),
        'alvo', (select apelido from fazenda_jogadores where id = l.alvo_id)) order by l.em desc)
      from (select * from fazenda_admin_log order by em desc limit 20) l), '[]'::jsonb)
  );
end;
$$;

-- banir (com motivo) ou desbanir; banir tira os anúncios da feira (os itens voltam para o celeiro dele)
create or replace function public.fazenda_admin_banir(p_token text, p_jogador uuid, p_banir boolean, p_motivo text default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id     uuid := fazenda_admin_id(p_token);
  v_motivo text := left(nullif(btrim(coalesce(p_motivo, '')), ''), 200);
  a        record;
begin
  if p_jogador = v_id then raise exception 'admin_propria_conta'; end if;
  select * into a from fazenda_jogadores where id = p_jogador for update;
  if not found then raise exception 'vizinho_invalido'; end if;
  if a.admin is not null then raise exception 'admin_alvo_admin'; end if;
  if p_banir then
    if v_motivo is null then raise exception 'admin_motivo'; end if;
    update fazenda_jogadores set banido_em = now(), banido_motivo = v_motivo where id = p_jogador;
    with v as (delete from fazenda_feira where vendedor_id = p_jogador and vendido_em is null returning item, qtd)
    insert into fazenda_celeiro (jogador_id, item, quantidade)
    select p_jogador, item, sum(qtd)::int from v group by item
    on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  else
    update fazenda_jogadores set banido_em = null, banido_motivo = null where id = p_jogador;
  end if;
  insert into fazenda_admin_log (admin_id, alvo_id, acao, motivo)
  values (v_id, p_jogador, case when p_banir then 'banir' else 'desbanir' end, v_motivo);
  return jsonb_build_object('apelido', a.apelido, 'banido', p_banir);
end;
$$;

-- só o dono: dá ou tira o admin de alguém (o dono continua dono)
create or replace function public.fazenda_admin_definir(p_token text, p_jogador uuid, p_admin boolean)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_admin_id(p_token, true);
  a    record;
begin
  if p_jogador = v_id then raise exception 'admin_propria_conta'; end if;
  select * into a from fazenda_jogadores where id = p_jogador for update;
  if not found then raise exception 'vizinho_invalido'; end if;
  if a.admin = 'dono' then raise exception 'admin_propria_conta'; end if;
  if p_admin and a.banido_em is not null then raise exception 'admin_banido'; end if;
  update fazenda_jogadores set admin = case when p_admin then 'admin' end where id = p_jogador;
  insert into fazenda_admin_log (admin_id, alvo_id, acao) values (v_id, p_jogador, case when p_admin then 'dar_admin' else 'tirar_admin' end);
  return jsonb_build_object('apelido', a.apelido, 'admin', p_admin);
end;
$$;

-- ------------------------------------------------------------
-- Fase 54: poste para quem começa e cuidadores que aceleram os bichos.
-- O lampião libera no nível 1 (era 4) e toda fazenda nova já nasce com um aceso do lado da casa;
-- quem ainda não tem nenhum ganha um, uma vez só (ganhou_poste), no primeiro lugar livre perto da casa.
-- Cuidador de bicho: no máximo 5 de cada espécie, então até o nível 1 (12 tarefas por hora) já dava
-- conta e evoluir não servia para nada. Agora cada nível deixa a espécie dele mais rápida: 10% por
-- nível no tempo de produção (soma com o feno, 20%), na hora de comer.
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists ganhou_poste boolean not null default false;

create or replace function public.fazenda_cuidador_adianta(p_jogador uuid, p_tipo text)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select 0.1 * h.nivel from fazenda_ajudantes h join fazenda_ajudantes_tipos t on t.id = h.tipo
                    where h.jogador_id = p_jogador and t.funcao = 'animal' and t.alvo = p_tipo
                    order by h.nivel desc limit 1), 0)::numeric;
$$;

do $$
declare
  j  record;
  p  int[];
begin
  for j in select g.id, g.zonas from public.fazenda_jogadores g
            where not g.ganhou_poste
              and not exists (select 1 from public.fazenda_construcoes c where c.jogador_id = g.id and c.tipo = 'lampiao') loop
    foreach p slice 1 in array array[[8, 3], [8, 2], [8, 5], [4, 4], [8, 1], [15, 3], [15, 5], [4, 5], [8, 6], [16, 8]] loop
      begin
        perform public.fazenda_checar_lugar(j.id, j.zonas, p[1], p[2], 1, 1);
        insert into public.fazenda_construcoes (jogador_id, x, y, tipo, colhido_em) values (j.id, p[1], p[2], 'lampiao', now());
        exit;
      exception when others then null;   -- lugar ocupado: tenta o próximo
      end;
    end loop;
  end loop;
  update public.fazenda_jogadores set ganhou_poste = true where not ganhou_poste;
end;
$$;

-- ------------------------------------------------------------
-- Fase 55: o dono gera um código de recuperação novo para quem perdeu o seu.
-- O código só existe com hash no banco, então não dá para mostrar o antigo: o dono gera outro
-- (mesmo formato PALAVRA-XXXX-XXXX) pelo painel de admin e passa para o jogador. O antigo para de
-- valer e as sessões abertas da conta caem (se o código vazou, quem estava dentro sai junto).
-- Só o dono, porque o código abre a fazenda inteira; fica anotado em fazenda_admin_log.
-- ------------------------------------------------------------
create or replace function public.fazenda_codigo_recuperacao()
returns text
language plpgsql volatile security definer
set search_path = public, extensions
as $$
declare
  v_alfabeto text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  v_palavras text[] := array['MILHO','CENOURA','ABOBORA','TOMATE','MORANGO',
                             'BATATA','ALFACE','MELANCIA','GIRASSOL','TRIGO'];
  v_bytes  bytea;
  v_codigo text;
  i        int;
begin
  loop
    v_bytes := gen_random_bytes(9);
    v_codigo := v_palavras[1 + get_byte(v_bytes, 0) % array_length(v_palavras, 1)] || '-';
    for i in 1..8 loop
      v_codigo := v_codigo || substr(v_alfabeto, 1 + get_byte(v_bytes, i) % length(v_alfabeto), 1);
      if i = 4 then
        v_codigo := v_codigo || '-';
      end if;
    end loop;
    exit when not exists (select 1 from fazenda_jogadores where codigo_hash = encode(digest(v_codigo, 'sha256'), 'hex'));
  end loop;
  return v_codigo;
end;
$$;

create or replace function public.fazenda_admin_novo_codigo(p_token text, p_jogador uuid)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id     uuid := fazenda_admin_id(p_token, true);
  v_codigo text := fazenda_codigo_recuperacao();
  a        record;
begin
  if p_jogador = v_id then raise exception 'admin_propria_conta'; end if;
  select * into a from fazenda_jogadores where id = p_jogador for update;
  if not found then raise exception 'vizinho_invalido'; end if;
  if a.banido_em is not null then raise exception 'admin_codigo_banido'; end if;
  update fazenda_jogadores set codigo_hash = encode(digest(v_codigo, 'sha256'), 'hex') where id = p_jogador;
  delete from fazenda_sessoes where jogador_id = p_jogador;
  insert into fazenda_admin_log (admin_id, alvo_id, acao) values (v_id, p_jogador, 'novo_codigo');
  return jsonb_build_object('apelido', a.apelido, 'codigo', v_codigo);
end;
$$;

-- ------------------------------------------------------------
-- Fase 56: consertos e balanceamento (ideias de 15/10).
-- • Canteiros: a posição ia só até 99, então o 101º dava limite_canteiros mesmo com o limite em 102
--   (fazenda_canteiros_posicao_check e fazenda_construir, lá em cima, agora vão até 299).
-- • Energia: tudo gasta 40% menos (fazenda_energia_preco) e o supercapacitor guarda 800 ⚡ (era 500).
-- • Feira: o celeiro lembra quanto de cada item veio da feira (da_feira). Vender isso ao jogo dá as
--   moedas, mas não o XP (fazenda_vender); comprar na feira para revender virava XP comprado.
--   Usar em receitas, entregas e missões continua igual. Quando a quantidade cai por qualquer outro
--   motivo, da_feira acompanha (nunca passa da quantidade).
-- ------------------------------------------------------------
alter table public.fazenda_celeiro add column if not exists da_feira int not null default 0;

create or replace function public.fazenda_celeiro_da_feira()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.da_feira > new.quantidade then new.da_feira := greatest(new.quantidade, 0); end if;
  return new;
end;
$$;
drop trigger if exists fazenda_celeiro_da_feira on public.fazenda_celeiro;
create trigger fazenda_celeiro_da_feira before update on public.fazenda_celeiro
  for each row execute function public.fazenda_celeiro_da_feira();

-- ------------------------------------------------------------
-- Fase 57: fim de jogo (ideias de 15/10, etapa 2A).
-- • Energia: 20% mais barata (fazenda_energia_preco; a 56 tinha posto 40%) e painel solar e turbina
--   sobem de limite com o nível, um de cada vez: +1 painel nos níveis pares a partir do 18, +1 turbina
--   nos ímpares a partir do 19 (igual a limiteMaquina em fazenda.js).
-- • Melhorias (Loja → Melhorias): compras caras e permanentes para quem já juntou moedas.
--   adubo = a planta já nasce adiantada (soma com girassol e estufa); pomar = a árvore colhida recomeça
--   adiantada; pes = mais pés de cada fruta no pomar, além dos 4 dos terrenos.
-- • Fazenda completa: do nível 20 em diante, com as metas do nível em dia (tudo o que ele libera), o
--   bônus das metas sobe de +50% para +75% de XP, e arar e plantar também dão XP
--   (fazenda_xp_dobro, fazenda_aplicar).
-- ------------------------------------------------------------
create table if not exists public.fazenda_melhorias (
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  id         text not null,
  nivel      int  not null default 1,
  primary key (jogador_id, id)
);
alter table public.fazenda_melhorias enable row level security;
revoke all on public.fazenda_melhorias from anon, authenticated;

-- o catálogo (o jogo mostra o que vem daqui). valor: adubo e pomar = fração adiantada; pes = pés a mais
-- fase 62: barco, vara e marinheiro são do alto-mar (mar = só com o píer; aparecem na tela do barco, não
-- na loja). base = o que vem com o píer; intervalo/max = o cardume do barco (ou o cesto do marinheiro),
-- em segundos e peixes; janela = o tempo de fisgar da vara, em milésimos de segundo
-- fase 65: a tunagem do barco (peca = true): motor, sonar, porão, rede e o kit de expedição. Cada nível
-- pede moedas e materiais raros (itens); o efeito entra em fazenda_mar_item, na pescaria e no marinheiro
create or replace function public.fazenda_melhorias_tipos()
returns jsonb language sql immutable as $$
  -- fase 72: tudo 2x mais caro (o dinheiro do nível 20 em diante estava sobrando)
  select '[{"id":"adubo","nome":"Adubo premium","descricao":"As plantas nascem adiantadas: crescem 10%, 20%, 30% e 40% mais rápido (soma com o girassol e a estufa).",
            "niveis":[{"nivel":23,"custo":100000,"valor":0.1},{"nivel":26,"custo":300000,"valor":0.2},{"nivel":29,"custo":600000,"valor":0.3},{"nivel":36,"custo":1200000,"valor":0.4}]},
           {"id":"pomar","nome":"Pomar fértil","descricao":"As árvores do pomar dão frutas 15%, 30% e 45% mais rápido.",
            "niveis":[{"nivel":24,"custo":160000,"valor":0.15},{"nivel":28,"custo":400000,"valor":0.3},{"nivel":39,"custo":1000000,"valor":0.45}]},
           {"id":"pes","nome":"Mais pés de fruta","descricao":"Mais 1, 2 e 3 pés de cada fruta no pomar, além dos 4 que os terrenos dão.",
            "niveis":[{"nivel":25,"custo":120000,"valor":1},{"nivel":30,"custo":240000,"valor":2},{"nivel":41,"custo":600000,"valor":3}]},
           {"id":"barco","nome":"Barco","mar":true,"descricao":"Barco maior vai mais longe: o cardume é maior, enche mais rápido e tem peixe que o bote não alcança.",
            "base":{"nome":"Bote","valor":1,"intervalo":900,"max":16},
            "niveis":[{"nivel":34,"custo":800000,"valor":2,"nome":"Traineira","intervalo":720,"max":24},
                      {"nivel":37,"custo":1800000,"valor":3,"nome":"Barco de pesca","intervalo":600,"max":32},
                      {"nivel":40,"custo":3600000,"valor":4,"nome":"Pesqueiro","intervalo":480,"max":40},
                      {"nivel":43,"custo":7000000,"valor":5,"nome":"Barco oceânico","intervalo":360,"max":48}]},
           {"id":"vara","nome":"Vara","mar":true,"descricao":"Vara melhor dá mais tempo para fisgar e puxa peixe maior.",
            "base":{"nome":"Vara de bambu","valor":1,"janela":900},
            "niveis":[{"nivel":32,"custo":300000,"valor":2,"nome":"Vara de fibra","janela":1100},
                      {"nivel":35,"custo":800000,"valor":3,"nome":"Molinete","janela":1300},
                      {"nivel":38,"custo":1800000,"valor":4,"nome":"Carretilha","janela":1500},
                      {"nivel":41,"custo":4000000,"valor":5,"nome":"Vara profissional","janela":1800}]},
           {"id":"marinheiro","nome":"Marinheiro","mar":true,"descricao":"O Seu Nonato pesca sozinho enquanto você cuida da fazenda: o cesto dele enche por até 8 horas. Cada nível pesca mais rápido.",
            "niveis":[{"nivel":33,"custo":500000,"valor":1,"nome":"Seu Nonato","intervalo":1800,"max":16},
                      {"nivel":36,"custo":1400000,"valor":2,"nome":"Seu Nonato com rede","intervalo":1200,"max":24},
                      {"nivel":39,"custo":3600000,"valor":3,"nome":"Seu Nonato com barco de apoio","intervalo":720,"max":40}]},
           {"id":"motor","nome":"Motor","mar":true,"peca":true,"descricao":"Motor mais forte vai e volta mais rápido: o cardume enche mais rápido.",
            "niveis":[{"nivel":33,"custo":400000,"valor":0.1,"nome":"Motor de popa","itens":{"ferro_forjado":1}},
                      {"nivel":39,"custo":1200000,"valor":0.2,"nome":"Motor a diesel","itens":{"ferro_forjado":2,"ancora":1}},
                      {"nivel":44,"custo":3000000,"valor":0.3,"nome":"Motor turbo","itens":{"ferro_forjado":3,"ancora":2,"perola_negra":1}}]},
           {"id":"sonar","nome":"Sonar","mar":true,"peca":true,"descricao":"Acha os cardumes de peixe grande e as ostras: mais peixe grande e mais pérola negra.",
            "niveis":[{"nivel":35,"custo":500000,"valor":1,"perola":150,"nome":"Sonar simples","itens":{"corda_naval":2}},
                      {"nivel":41,"custo":1600000,"valor":2,"perola":100,"nome":"Sonar colorido","itens":{"corda_naval":2,"perola_negra":1}},
                      {"nivel":45,"custo":4000000,"valor":3,"perola":70,"nome":"Sonar de varredura","itens":{"perola_negra":2,"marlim":1}}]},
           {"id":"porao","nome":"Porão","mar":true,"peca":true,"descricao":"Guarda o peixe no gelo: às vezes uma fisgada traz 2 peixes.",
            "niveis":[{"nivel":36,"custo":600000,"valor":0.15,"nome":"Caixa de gelo","itens":{"madeira_nobre":2}},
                      {"nivel":42,"custo":2000000,"valor":0.3,"nome":"Porão refrigerado","itens":{"madeira_nobre":3,"pedra_cantaria":2}},
                      {"nivel":45,"custo":5000000,"valor":0.45,"nome":"Câmara fria","itens":{"pedra_cantaria":2,"ferro_forjado":2,"perola_negra":1}}]},
           {"id":"rede","nome":"Rede de arrasto","mar":true,"peca":true,"descricao":"Para o marinheiro: ele pesca mais rápido (e o cesto continua guardando 8 horas).",
            "niveis":[{"nivel":37,"custo":600000,"valor":0.15,"nome":"Rede de arrasto","itens":{"corda_naval":2}},
                      {"nivel":43,"custo":2400000,"valor":0.3,"nome":"Rede dupla","itens":{"corda_naval":3,"ancora":1}}]},
           {"id":"expedicao","nome":"Kit de expedição","mar":true,"peca":true,"descricao":"Bússola, mapa e tanque extra: deixa o barco oceânico pronto para viajar às ilhas (nível 46, na próxima expansão).",
            "niveis":[{"nivel":45,"custo":6000000,"valor":1,"nome":"Kit de expedição","itens":{"perola_negra":3,"marlim":2,"ancora":2}}]},
           {"id":"turno","nome":"Turno de 12 horas","diamante":true,"descricao":"Os ajudantes trabalham 12 horas com a barra de energia cheia (eram 8) e guardam até 12 horas de trabalho com a fazenda fechada.",
            "niveis":[{"nivel":5,"custo":0,"diamantes":150,"valor":12,"texto":"12 h de trabalho"}]},
           {"id":"cesto_bira","nome":"Cesto grande do Bira","diamante":true,"descricao":"O cesto do Bira no lago guarda 50% mais peixe: 24 em vez de 16 (enche por 12 horas).",
            "niveis":[{"nivel":1,"custo":0,"diamantes":80,"valor":0.5,"texto":"24 peixes"}]},
           {"id":"cesto_nonato","nome":"Cesto grande do Seu Nonato","diamante":true,"descricao":"O cesto do marinheiro no alto-mar guarda 50% mais peixe.",
            "niveis":[{"nivel":33,"custo":0,"diamantes":80,"valor":0.5,"texto":"+50% no cesto"}]},
           {"id":"fila","nome":"Fila de 15 receitas","diamante":true,"descricao":"Cada oficina guarda até 15 receitas no estoque (eram 10): trabalha mais tempo sozinha.",
            "niveis":[{"nivel":3,"custo":0,"diamantes":100,"valor":15,"texto":"15 receitas"}]},
           {"id":"barraca","nome":"Mais barracas na feira","diamante":true,"descricao":"Depois das 4 barracas compradas com moedas, a 5ª e a 6ª: cada uma dá mais 2 anúncios na feira.",
            "niveis":[{"nivel":5,"custo":0,"diamantes":100,"valor":5,"texto":"5ª barraca"},{"nivel":5,"custo":0,"diamantes":150,"valor":6,"texto":"6ª barraca"}]}]'::jsonb;
$$;

-- quanto a melhoria vale para o jogador agora (0 = não comprou)
-- (fase 71: o catálogo vem pronto do cache, e só é lido quando o jogador tem a melhoria)
create or replace function public.fazenda_melhoria(p_jogador uuid, p_id text)
returns real language plpgsql stable security definer set search_path = public as $$
declare
  v_n int;
begin
  select nivel into v_n from fazenda_melhorias where jogador_id = p_jogador and id = p_id;
  if v_n is null then return 0; end if;
  return coalesce((fazenda_cache_ler('melhorias')->p_id->'niveis'->(v_n - 1)->>'valor')::real, 0);
end;
$$;

-- fase 82: as melhorias de diamante (D8) e a oficina nível 2 e 3 (B10)
-- quantas receitas cabem no estoque de cada oficina (10; 15 com a fila de diamante)
create or replace function public.fazenda_estoque_max_de(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select greatest(fazenda_estoque_max(), fazenda_melhoria(p_jogador, 'fila')::int);
$$;
-- quantos peixes cabem no cesto do Bira (16; 24 com o cesto grande), 1 a cada 30 min
create or replace function public.fazenda_cesto_max(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select round(16 * (1 + fazenda_melhoria(p_jogador, 'cesto_bira')))::int;
$$;
-- quantas horas o ajudante trabalha com a barra cheia e guarda com a fazenda fechada (8; 12 com o turno)
create or replace function public.fazenda_turno(p_jogador uuid)
returns real language sql stable security definer set search_path = public as $$
  select greatest(8, fazenda_melhoria(p_jogador, 'turno'));
$$;
-- o nível de cada tipo de oficina (1 = a de sempre; 2 e 3 compradas com moedas)
create table if not exists public.fazenda_oficina_nivel (
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  tipo       text not null,
  nivel      smallint not null default 1 check (nivel between 1 and 3),
  primary key (jogador_id, tipo)
);
alter table public.fazenda_oficina_nivel enable row level security;
revoke all on public.fazenda_oficina_nivel from anon, authenticated;
-- os níveis 2 e 3: preço e quanto a receita fica mais rápida
create or replace function public.fazenda_oficina_niveis()
returns jsonb language sql immutable as $$
  select '[{"nivel": 2, "custo": 100000, "rapidez": 0.15}, {"nivel": 3, "custo": 400000, "rapidez": 0.3}]'::jsonb;
$$;
-- quanto mais rápida fica a receita desse tipo de oficina (0, 0.15 ou 0.3)
create or replace function public.fazenda_oficina_rapidez(p_jogador uuid, p_tipo text)
returns real language sql stable security definer set search_path = public as $$
  select coalesce((select (fazenda_oficina_niveis()->(n.nivel - 2)->>'rapidez')::real
                     from fazenda_oficina_nivel n where n.jogador_id = p_jogador and n.tipo = p_tipo and n.nivel >= 2), 0)::real;
$$;

-- o limite de cada máquina no nível (null = sem limite)
create or replace function public.fazenda_limite_maquina(p_item text, p_limite int, p_nivel int)
returns int language sql immutable as $$
  select case p_item
           -- fase 78: do 17 ao 29, +1 por nível (era +1 a cada 2); do 30 em diante, +1 a cada 2
           when 'painel_solar' then p_limite + greatest(0, least(p_nivel, 29) - 16) + greatest(0, (p_nivel - 29) / 2)
           when 'turbina'      then p_limite + greatest(0, least(p_nivel, 29) - 17) + greatest(0, (p_nivel - 29) / 2)
           when 'gerador_bio'  then p_limite + (p_nivel >= 21)::int + (p_nivel >= 24)::int + 2 * (p_nivel >= 28)::int   -- fase 78: 2, 3, 4 e 6
           when 'hidreletrica' then p_limite + (p_nivel >= 23)::int + (p_nivel >= 27)::int                                -- fase 78: 1, 2 e 3
           when 'reator'       then p_limite + (p_nivel >= 40)::int   -- fase 75: o 2º reator no nível 40
           else p_limite end;
$$;

-- a hora de "colhido" de uma árvore colhida agora: com o pomar fértil, ela recomeça adiantada
create or replace function public.fazenda_colhido_agora(p_jogador uuid, p_tipo text)
returns timestamptz language sql stable security definer set search_path = public as $$
  select now() - make_interval(secs => coalesce((select i.produz_seg from fazenda_itens i
                                                  where i.id = p_tipo and i.categoria = 'pomar'), 0)
                                       * fazenda_melhoria(p_jogador, 'pomar'));
$$;

-- fazenda completa = do nível 20 em diante, com as metas do nível em dia (fase 49: bonus_nivel)
create or replace function public.fazenda_completa(p_jogador uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select fazenda_nivel(j.xp) >= 20 and j.bonus_nivel = fazenda_nivel(j.xp)
                     from fazenda_jogadores j where j.id = p_jogador), false);
$$;

-- ------------------------------------------------------------
-- Fase 58: sementes e oficinas em cadeia do nível 20 ao 30 (ideias de 15/10, etapa 2B).
-- A última semente da loja era a amora (nível 9); do 20 ao 25 não liberava nada. Seis sementes
-- novas (o ano todo) e oito oficinas, umas usando o produto das outras: o açúcar do engenho entra
-- no cappuccino e no bombom; o fio da fiação, na roupa (com o tecido da tecelagem); o chocolate da
-- chocolateria, no bombom. Produto vale ~1,7x os ingredientes, como nas oficinas da fase 38.
-- A arte fica em fazenda-arte.js (CULTURAS e PROPRIA 65..84; as oficinas, no pacote town).
-- ------------------------------------------------------------
insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem) values
  ('cana',     'Cana-de-açúcar', '🎋', 21600, 150,  30, 10,  45, 20, 13),
  ('cafe',     'Café',           '☕', 28800, 200,  40,  9,  55, 22, 14),
  ('algodao',  'Algodão',        '☁️', 36000, 240,  45,  9,  65, 23, 15),
  ('uva',      'Uva',            '🍇', 43200, 300,  55, 10,  80, 25, 16),
  ('pimenta',  'Pimenta',        '🌶️', 14400, 180,  35,  8,  40, 27, 17),
  ('baunilha', 'Baunilha',       '🌼', 57600, 500, 120,  6, 120, 30, 18)
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, tempo_seg = excluded.tempo_seg,
  custo = excluded.custo, venda = excluded.venda, rendimento = excluded.rendimento,
  xp = excluded.xp, nivel_min = excluded.nivel_min, ordem = excluded.ordem;

insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('acucar',        'Açúcar',         '🧂', 1, 0,  205, 1,  20, 21, 74, 'produto'),
  ('cafe_torrado',  'Café torrado',   '☕', 1, 0,  205, 1,  20, 22, 75, 'produto'),
  ('fio',           'Fio de algodão', '🧵', 1, 0,  305, 1,  30, 23, 76, 'produto'),
  ('cappuccino',    'Cappuccino',     '☕', 1, 0,  815, 1,  80, 24, 77, 'produto'),
  ('roupa',         'Roupa',          '👕', 1, 0, 1890, 1, 180, 25, 78, 'produto'),
  ('vinho',         'Vinho',          '🍷', 1, 0,  470, 1,  46, 26, 79, 'produto'),
  ('molho_picante', 'Molho picante',  '🌶️', 1, 0,  365, 1,  36, 28, 80, 'produto'),
  ('bombom',        'Bombom',         '🍬', 1, 0, 1480, 1, 145, 30, 81, 'produto')
on conflict (id) do update set
  nome = excluded.nome, venda = excluded.venda, xp = excluded.xp, nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;

insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, largura, altura,
                                  produz, produz_seg, produz_qtd, entradas, limite, beleza, descricao) values
  ('engenho',     'Engenho',     'oficina', 32000, 21, 91, 2, 3, 'acucar',         3600, 1, '{"cana": 4}', 2, 5, '4 canas → açúcar (vai no cappuccino e no bombom).'),
  ('torrefacao',  'Torrefação',  'oficina', 34000, 22, 92, 2, 3, 'cafe_torrado',   5400, 1, '{"cafe": 3}', 2, 5, '3 cafés → café torrado (vai no cappuccino).'),
  ('fiacao',      'Fiação',      'oficina', 36000, 23, 93, 2, 3, 'fio',            5400, 1, '{"algodao": 4}', 2, 5, '4 algodões → fio de algodão (vai na roupa).'),
  ('cafeteria',   'Cafeteria',   'oficina', 40000, 24, 94, 2, 3, 'cappuccino',     7200, 1, '{"cafe_torrado": 1, "acucar": 1, "leite": 1}', 2, 5, '1 café torrado + 1 açúcar + 1 leite → cappuccino.'),
  ('alfaiataria', 'Alfaiataria', 'oficina', 45000, 25, 95, 2, 3, 'roupa',         10800, 1, '{"fio": 2, "tecido": 1}', 2, 5, '2 fios de algodão + 1 tecido (da tecelagem) → roupa.'),
  ('vinicola',    'Vinícola',    'oficina', 48000, 26, 96, 2, 3, 'vinho',         14400, 1, '{"uva": 5}', 2, 5, '5 uvas → vinho.'),
  ('pimentaria',  'Pimentaria',  'oficina', 50000, 28, 97, 2, 3, 'molho_picante',  5400, 1, '{"pimenta": 3, "molho": 1}', 2, 5, '3 pimentas + 1 molho de tomate → molho picante.'),
  ('bombonaria',  'Bombonaria',  'oficina', 60000, 30, 98, 2, 3, 'bombom',        10800, 1, '{"chocolate": 1, "acucar": 1, "baunilha": 2}', 2, 5, '1 chocolate + 1 açúcar + 2 baunilhas → bombom.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, largura = excluded.largura, altura = excluded.altura, produz = excluded.produz,
  produz_seg = excluded.produz_seg, produz_qtd = excluded.produz_qtd, entradas = excluded.entradas,
  limite = excluded.limite, beleza = excluded.beleza, descricao = excluded.descricao;

-- ------------------------------------------------------------
-- Fase 59: a tela do ajudante (ideias de 15/10, etapa 3). Tocar no ajudante abre o que ele fez hoje
-- e ontem, a barra de energia e o botão de mandar descansar.
-- • Energia de 0 a 100: cada tarefa gasta 100 / (ritmo x 8), então a barra cheia dura 8 horas de
--   trabalho em qualquer nível (o mesmo teto de crédito que já existia). Sem energia para mais uma
--   tarefa, ele descansa 2 h sozinho; mandado descansar, para na hora e descansa 1 h. Descansando não
--   trabalha nem junta crédito; acordou, volta com a barra cheia (fazenda_trabalhar).
-- • O eletricista não faz tarefas (só baixa o gasto da energia elétrica): não tem barra.
-- • Camas (fazenda_camas): cansado com cama livre descansa 2 h; sem cama, 4 h na sombra.
-- • O que fez: um contador por dia (fazenda_ajudantes_feito), gravado uma vez por rodada de trabalho
--   junto com a atualização que já existia; guarda só hoje, ontem e anteontem.
-- ------------------------------------------------------------
alter table public.fazenda_ajudantes add column if not exists energia real not null default 100;
alter table public.fazenda_ajudantes add column if not exists descanso_ate timestamptz;
alter table public.fazenda_ajudantes add column if not exists descanso_motivo text;   -- cansou | mandado
alter table public.fazenda_ajudantes add column if not exists descanso_casa boolean;   -- descansa numa cama (true) ou na sombra

-- Camas para descansar (ideia do Jessé: dá uso às casinhas): a casa da fazenda tem 1, cada casinha
-- vermelha mais 1 e cada azul mais 2. Cansado com cama livre: 2 h; sem cama, 4 h na sombra.
-- Mandar descansar só com cama livre.
create or replace function public.fazenda_camas(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select 1 + coalesce(sum(case tipo when 'casa_vermelha' then 1 when 'casa_azul' then 2 else 0 end), 0)::int
    from fazenda_construcoes where jogador_id = p_jogador and tipo in ('casa_vermelha', 'casa_azul');
$$;
create or replace function public.fazenda_camas_ocupadas(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from fazenda_ajudantes
   where jogador_id = p_jogador and descanso_casa and descanso_ate > now();
$$;

create table if not exists public.fazenda_ajudantes_feito (
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  tipo       text not null,
  dia        date not null,
  feito      jsonb not null default '{}'::jsonb,
  primary key (jogador_id, tipo, dia)
);
alter table public.fazenda_ajudantes_feito enable row level security;
revoke all on public.fazenda_ajudantes_feito from anon, authenticated;

-- soma n no contador k
create or replace function public.fazenda_conta(p jsonb, k text, n int default 1)
returns jsonb language sql immutable as $$
  select coalesce(p, '{}'::jsonb) || jsonb_build_object(k, coalesce((p->>k)::int, 0) + coalesce(n, 0));
$$;

-- junta o que o ajudante fez nesta rodada no contador do dia
create or replace function public.fazenda_ajudante_registrar(p_jogador uuid, p_tipo text, p_log jsonb)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if p_log is null or p_log = '{}'::jsonb then return; end if;
  insert into fazenda_ajudantes_feito as f (jogador_id, tipo, dia, feito) values (p_jogador, p_tipo, fazenda_hoje(), p_log)
  on conflict (jogador_id, tipo, dia) do update
    set feito = (select coalesce(jsonb_object_agg(k, coalesce((f.feito->>k)::int, 0) + coalesce((excluded.feito->>k)::int, 0)), '{}'::jsonb)
                   from jsonb_object_keys(f.feito || excluded.feito) k);
  delete from fazenda_ajudantes_feito where jogador_id = p_jogador and dia < fazenda_hoje() - 2;
end;
$$;

-- mandar descansar: para na hora e volta em 1 h com a energia cheia
-- fase 66: só com menos de 75% de energia (mandavam dormir toda hora para render mais)
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

-- ------------------------------------------------------------
-- Fase 61: o litoral e o píer (ideias de 15/10, etapa 5A).
-- • Terreno 7, Litoral (nível 31, 300 mil): uma faixa ao sul, 48 x 10. As 5 fileiras de cima (y 32 a
--   36) são areia, para construir e plantar; as 5 de baixo (y 37 a 41) são mar (fazenda_livre).
-- • O píer: um lugar fixo na areia (x 22 a 24, y 35 e 36) que entra pelo mar. Receita: 9 peças
--   difíceis (5 do mercador, o peixe do Velho Chico do lago e o leme dourado, que só o ranking da
--   semana dá, etapa 6) e 100 mil moedas. Peça que falta dá para comprar com diamantes, caro, só até
--   completar a receita (fazenda_pier_comprar_peca). Depois do píer vem o alto-mar (etapa 5B).
-- • O peixe do Velho Chico continua vendendo no celeiro; na feira passa a ter preço de peça (50 a 150
--   mil), e dá para guardar para o píer (fazenda_reservar, o mesmo da ração dos bichos).
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists pier_em timestamptz;   -- quando o píer ficou pronto
alter table public.fazenda_jogadores drop constraint if exists fazenda_jogadores_zonas_check;
alter table public.fazenda_jogadores add constraint fazenda_jogadores_zonas_check check (zonas between 0 and 7);   -- o 7º terreno

insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('leme_dourado', 'Leme dourado', '☸️', 1, 0, 250000, 1, 0, 1, 95, 'raro')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, venda = excluded.venda, xp = excluded.xp,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;

-- a receita do píer, o preço em diamantes de cada peça que falta e o preço de peça na feira
create or replace function public.fazenda_pier_receita()
returns jsonb language sql immutable as $$
  select '{"nivel": 31, "zona": 7, "moedas": 100000,
           "itens": {"madeira_nobre": 2, "corda_naval": 2, "pedra_cantaria": 1, "ferro_forjado": 1, "ancora": 1,
                     "velho_chico": 1, "leme_dourado": 1},
           "diamantes": {"madeira_nobre": 80, "corda_naval": 90, "pedra_cantaria": 110, "ferro_forjado": 140,
                         "ancora": 200, "velho_chico": 60, "leme_dourado": 250},
           "feira": {"velho_chico": 50000}}'::jsonb;
$$;

-- a faixa da feira, agora com o preço de peça do peixe do Velho Chico (fase 61)
create or replace function public.fazenda_feira_faixa(p_item text)
returns int[] language sql stable security definer set search_path = public as $$
  select case when k.tipo = 'raro'   -- fase 60: material raro vai de venda (o mínimo) até o triplo
              then array[k.venda, k.venda * 3]
              -- fase 61: peça do píer que também vende no celeiro (o peixe do Velho Chico): preço de peça
              when fazenda_pier_receita()->'feira' ? k.id
              then array[(fazenda_pier_receita()->'feira'->>k.id)::int, (fazenda_pier_receita()->'feira'->>k.id)::int * 3]
              else array[greatest(1, floor(k.venda * (fazenda_feira_regras()->>'min')::numeric))::int,
                         greatest(1, ceil(k.venda * (fazenda_feira_regras()->>'max')::numeric))::int] end
    from fazenda_culturas k where k.id = p_item and k.venda > 0;
$$;

-- quanto falta de uma peça (o guardado conta: guardar é justamente para o píer)
create or replace function public.fazenda_pier_falta(p_jogador uuid, p_item text)
returns int language sql stable security definer set search_path = public as $$
  select greatest(coalesce((fazenda_pier_receita()->'itens'->>p_item)::int, 0)
                  - coalesce((select quantidade from fazenda_celeiro where jogador_id = p_jogador and item = p_item), 0), 0);
$$;

create or replace function public.fazenda_construir_pier(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  v_r  jsonb := fazenda_pier_receita();
  j    record;
  k    text;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  if j.pier_em is not null then raise exception 'pier_pronto'; end if;
  if fazenda_nivel(j.xp) < (v_r->>'nivel')::int then raise exception 'nivel_insuficiente'; end if;
  if j.zonas < (v_r->>'zona')::int then raise exception 'sem_litoral'; end if;
  if exists (select 1 from jsonb_object_keys(v_r->'itens') i where fazenda_pier_falta(v_id, i) > 0) then
    raise exception 'faltam_pecas';
  end if;
  if j.moedas < (v_r->>'moedas')::int then raise exception 'moedas_insuficientes'; end if;
  for k in select jsonb_object_keys(v_r->'itens') loop
    update fazenda_celeiro set quantidade = quantidade - (v_r->'itens'->>k)::int where jogador_id = v_id and item = k;
    -- o que estava guardado para o píer sai junto (a reserva não pode passar do que sobrou nem ficar zerada)
    delete from fazenda_reservas r using fazenda_celeiro c
     where r.jogador_id = v_id and r.item = k and c.jogador_id = v_id and c.item = k and c.quantidade <= 0;
    update fazenda_reservas r set quantidade = c.quantidade
      from fazenda_celeiro c where r.jogador_id = v_id and r.item = k and c.jogador_id = v_id and c.item = k and r.quantidade > c.quantidade;
  end loop;
  update fazenda_jogadores set moedas = moedas - (v_r->>'moedas')::int, pier_em = now() where id = v_id;
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- peça que falta, comprada com diamantes (caro), só até completar a receita
create or replace function public.fazenda_pier_comprar_peca(p_token text, p_item text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_r     jsonb := fazenda_pier_receita();
  v_preco int := (v_r->'diamantes'->>p_item)::int;
  j       record;
begin
  if v_preco is null then raise exception 'item_invalido'; end if;
  select * into j from fazenda_jogadores where id = v_id for update;
  if j.pier_em is not null then raise exception 'pier_pronto'; end if;
  if j.zonas < (v_r->>'zona')::int then raise exception 'sem_litoral'; end if;
  if fazenda_pier_falta(v_id, p_item) <= 0 then raise exception 'peca_nao_falta'; end if;
  -- fase 70: com diamante, no máximo o que a receita pede (anunciar na feira e comprar de novo virava raro sem fim)
  if (select count(*) from fazenda_diamantes_usos where jogador_id = v_id and item = 'pier:' || p_item)
     >= coalesce((v_r->'itens'->>p_item)::int, 0) then
    raise exception 'peca_comprada';
  end if;
  if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
  update fazenda_jogadores set diamantes = diamantes - v_preco where id = v_id;
  insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, 'pier:' || p_item, v_preco);
  insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, p_item, 1)
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
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
alter table public.fazenda_jogadores add column if not exists barco_visual jsonb;          -- fase 65: a pintura do barco (casco, faixa, bandeira)
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
-- fase 65: o motor deixa o cardume do barco mais rápido; a rede, o marinheiro (e o cesto dele cresce
-- junto, para continuar guardando 8 horas)
create or replace function public.fazenda_mar_item(p_jogador uuid, p_id text)
returns jsonb language sql stable security definer set search_path = public as $$
  -- fase 82: o cesto grande do Seu Nonato (diamante) guarda 50% mais
  select case when y.r is not null and p_id = 'marinheiro' and fazenda_melhoria(p_jogador, 'cesto_nonato') > 0
              then y.r || jsonb_build_object('max', ceil((y.r->>'max')::int * (1 + fazenda_melhoria(p_jogador, 'cesto_nonato')))::int)
              else y.r end
    from (
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
           where m->>'id' = p_id) x) y(r);
$$;

-- fase 65: 1 pérola a cada quantos peixes (o sonar baixa de 200 para 150, 100 e 70)
create or replace function public.fazenda_mar_perola(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select coalesce((fazenda_mar_item(p_jogador, 'sonar')->>'perola')::int, (fazenda_mar_regras()->>'perola')::int);
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

-- ------------------------------------------------------------
-- Fase 63: o evento da semana (ideias de 15/10, etapa 6).
-- • A semana vai de sexta 22h a sexta 22h (Brasília, UTC−3 como fazenda_hoje). Fecha sozinha: a
--   primeira chamada depois da virada (fazenda_auth) premia a semana que acabou e tira a "foto" do
--   começo da nova (XP e moedas ganhas de cada um). Conta o que aconteceu entre a abertura de uma
--   semana e o fechamento dela: nada se perde e nada conta duas vezes.
-- • Seis categorias, top 3 de cada (60, 35 e 20 diamantes; o 1º leva o item exclusivo; no ranking,
--   os três levam troféu): XP ganho na semana, níveis subidos, moedas ganhas (gastar não desconta),
--   vendido e comprado na barraca (feira) e amigos convidados que chegaram ao nível 5. Quem mais
--   convidou leva o leme dourado, a peça do píer.
-- • Os itens exclusivos são raros (só na feira, do mínimo ao triplo, 60 mil para cima). Conquistas
--   próprias do evento e os troféus no perfil.
-- ------------------------------------------------------------
-- moedas ganhas desde sempre (o gatilho soma toda moeda que entra; o que sai não desconta)
alter table public.fazenda_jogadores add column if not exists moedas_ganhas bigint not null default 0;
create or replace function public.fazenda_moedas_ganhas()
returns trigger language plpgsql set search_path = public as $$
begin
  -- (fase 70: soma no que veio na gravação: a venda na barraca já desconta o que não conta)
  if new.moedas > old.moedas then new.moedas_ganhas := new.moedas_ganhas + (new.moedas - old.moedas); end if;
  return new;
end;
$$;
drop trigger if exists fazenda_moedas_ganhas on public.fazenda_jogadores;
create trigger fazenda_moedas_ganhas before update of moedas on public.fazenda_jogadores
  for each row execute function public.fazenda_moedas_ganhas();

insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('trofeu_ouro',       'Troféu de ouro',    '🏆', 1, 0, 200000, 1, 0, 1,  97, 'raro'),
  ('trofeu_prata',      'Troféu de prata',   '🥈', 1, 0, 100000, 1, 0, 1,  98, 'raro'),
  ('trofeu_bronze',     'Troféu de bronze',  '🥉', 1, 0,  60000, 1, 0, 1,  99, 'raro'),
  ('ampulheta_dourada', 'Ampulheta dourada', '⏳', 1, 0,  80000, 1, 0, 1, 100, 'raro'),
  ('cofrinho_ouro',     'Cofrinho de ouro',  '🐷', 1, 0, 100000, 1, 0, 1, 101, 'raro'),
  ('balanca_ouro',      'Balança de ouro',   '⚖️', 1, 0,  80000, 1, 0, 1, 102, 'raro'),
  ('sacola_ouro',       'Sacola de ouro',    '👜', 1, 0,  80000, 1, 0, 1, 103, 'raro')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, venda = excluded.venda, xp = excluded.xp,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;

insert into public.fazenda_conquistas_tipos (id, nome, descricao, medida, meta, recompensa, ordem) values
  ('evento_ranking',  'Campeão da semana', 'Fique em 1º no ranking do evento da semana',        'evento_ranking',   1, 10000, 25),
  ('evento_niveis',   'Foguete',           'Fique em 1º em níveis no evento da semana',          'evento_niveis',    1, 10000, 26),
  ('evento_moedas',   'Mão de ouro',       'Fique em 1º em moedas no evento da semana',          'evento_moedas',    1, 10000, 27),
  ('evento_vendeu',   'Rei da barraca',    'Fique em 1º em vendas na barraca no evento',         'evento_vendeu',    1, 10000, 28),
  ('evento_comprou',  'Freguês de ouro',   'Fique em 1º em compras na barraca no evento',        'evento_comprou',   1, 10000, 29),
  ('evento_convites', 'Embaixador',        'Fique em 1º em convites no evento da semana',        'evento_convites',  1, 10000, 30),
  ('evento_podio',    'No pódio',          'Fique no top 3 de qualquer categoria do evento',     'evento_podio',     1,  5000, 31),
  ('evento_veterano', 'Veterano dos eventos', 'Suba ao pódio do evento 10 vezes',                'evento_podio',    10, 30000, 32)
on conflict (id) do update set
  nome = excluded.nome, descricao = excluded.descricao, medida = excluded.medida,
  meta = excluded.meta, recompensa = excluded.recompensa, ordem = excluded.ordem;

-- as semanas (inicio = a sexta 22h em que começa; aberta_em = quando a foto foi tirada, e a semana
-- conta dali; fechada_em = quando premiou), a foto de cada jogador e os prêmios entregues
create table if not exists public.fazenda_semanas (
  inicio     timestamptz primary key,
  aberta_em  timestamptz not null default now(),
  fechada_em timestamptz
);
create table if not exists public.fazenda_semana_base (
  jogador_id    uuid primary key references public.fazenda_jogadores(id) on delete cascade,
  semana        timestamptz not null,
  xp            int not null,
  moedas_ganhas bigint not null
);
alter table public.fazenda_semana_base add column if not exists xp_pago bigint not null default 0;   -- fase 70
create table if not exists public.fazenda_semana_premios (
  semana     timestamptz not null,
  categoria  text not null,
  posicao    smallint not null check (posicao between 1 and 3),
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  valor      bigint not null,
  diamantes  int not null default 0,
  item       text references public.fazenda_culturas(id),
  visto      boolean not null default false,
  primary key (semana, categoria, posicao)
);
create index if not exists fazenda_semana_premios_jogador on public.fazenda_semana_premios (jogador_id);
alter table public.fazenda_semanas enable row level security;
alter table public.fazenda_semana_base enable row level security;
alter table public.fazenda_semana_premios enable row level security;
revoke all on public.fazenda_semanas, public.fazenda_semana_base, public.fazenda_semana_premios from anon, authenticated;

-- a sexta 22h (Brasília) em que começa a semana do instante p_t
create or replace function public.fazenda_semana_inicio(p_t timestamptz)
returns timestamptz language sql immutable as $$
  select (date_trunc('week', (p_t at time zone 'UTC') - interval '25 hours' + interval '3 days')
          - interval '3 days' + interval '25 hours') at time zone 'UTC';
$$;

-- as categorias, os diamantes do 1º, 2º e 3º e os itens (o 1º leva o primeiro; no ranking, um por lugar)
-- Fase 64: diamantes pela metade (eram 60, 35 e 20) e o item vem com 50% de chance (chance_item), para
-- cada lugar do pódio; o 2º e o 3º fora do ranking, se sair, levam um material do píer (fazenda_raros)
create or replace function public.fazenda_evento_regras()
returns jsonb language sql immutable as $$
  select '{"fecha": "sexta às 22h", "diamantes": [30, 18, 10], "chance_item": 50, "convite_nivel": 10,
           "categorias": [
             {"id": "ranking",  "nome": "Ranking da semana",  "conta": "XP ganho na semana",            "itens": ["trofeu_ouro", "trofeu_prata", "trofeu_bronze"]},
             {"id": "niveis",   "nome": "Mais níveis",        "conta": "níveis subidos na semana",      "itens": ["ampulheta_dourada"]},
             {"id": "moedas",   "nome": "Mais moedas",        "conta": "moedas ganhas na semana",       "itens": ["cofrinho_ouro"]},
             {"id": "vendeu",   "nome": "Vendeu na barraca",  "conta": "moedas em vendas na feira",     "itens": ["balanca_ouro"]},
             {"id": "comprou",  "nome": "Comprou na barraca", "conta": "moedas em compras na feira",    "itens": ["sacola_ouro"]},
             {"id": "convites", "nome": "Mais convites",      "conta": "amigos convidados que chegaram ao nível 10", "itens": ["leme_dourado"]}]}'::jsonb;
$$;

-- os números de cada jogador numa semana (p_semana = o início dela; conta de p_desde a p_ate).
-- Quem entrou na semana não tem foto: conta do zero. Quem foi banido não entra.
create or replace function public.fazenda_semana_placar(p_semana timestamptz, p_desde timestamptz, p_ate timestamptz)
returns table (jogador_id uuid, apelido text, avatar jsonb, criado_em timestamptz, ranking bigint, niveis bigint,
               moedas bigint, vendeu bigint, comprou bigint, convites bigint)
language sql stable security definer set search_path = public as $$
  -- fase 70: o XP comprado com diamante não conta (ranking e níveis); na barraca, uma mesma pessoa do
  -- outro lado conta no máximo 25% do total (duas contas vendendo uma para a outra não ganham sozinhas)
  select j.id, j.apelido, j.avatar, j.criado_em,
         (j.xp - coalesce(b.xp, 0) - (j.xp_pago - coalesce(b.xp_pago, 0)))::bigint,
         (fazenda_nivel((j.xp - (j.xp_pago - coalesce(b.xp_pago, 0)))::int) - fazenda_nivel(coalesce(b.xp, 0)))::bigint,
         (j.moedas_ganhas - coalesce(b.moedas_ganhas, 0))::bigint,
         coalesce((select sum(least(t.v, ceil(t.total * 0.25))) from (
                    select sum(f.qtd::bigint * f.preco) as v, sum(sum(f.qtd::bigint * f.preco)) over () as total from fazenda_feira f
                     where f.vendedor_id = j.id and f.vendido_em >= p_desde and f.vendido_em < p_ate group by f.comprador_id) t), 0)::bigint,
         coalesce((select sum(least(t.v, ceil(t.total * 0.25))) from (
                    select sum(f.qtd::bigint * f.preco) as v, sum(sum(f.qtd::bigint * f.preco)) over () as total from fazenda_feira f
                     where f.comprador_id = j.id and f.vendido_em >= p_desde and f.vendido_em < p_ate group by f.vendedor_id) t), 0)::bigint,
         (select count(*) from fazenda_convites c join fazenda_jogadores a on a.id = c.convidado_id
           where c.dono_id = j.id and c.criado_em >= p_desde and c.criado_em < p_ate and a.banido_em is null
             and fazenda_nivel(a.xp) >= (fazenda_evento_regras()->>'convite_nivel')::int)::bigint
    from fazenda_jogadores j
    left join fazenda_semana_base b on b.jogador_id = j.id and b.semana = p_semana
   where j.banido_em is null
     -- fase 71: só quem jogou na semana (visto_em, com 1 h de folga), vendeu ou comprou na feira ou trouxe
     -- convite nela: quem não jogou tem tudo zerado (e o placar de todos pesava no fechamento e no Evento)
     and (j.visto_em >= p_desde - interval '1 hour'
          or exists (select 1 from fazenda_feira f
                      where (f.vendedor_id = j.id or f.comprador_id = j.id) and f.vendido_em >= p_desde and f.vendido_em < p_ate)
          or exists (select 1 from fazenda_convites c where c.dono_id = j.id and c.criado_em >= p_desde and c.criado_em < p_ate));
$$;

-- a posição de cada um em cada categoria (só quem tem valor maior que 0; desempate: XP da semana e
-- quem chegou antes no jogo)
create or replace function public.fazenda_semana_posicoes(p_semana timestamptz, p_desde timestamptz, p_ate timestamptz)
returns table (categoria text, posicao bigint, jogador_id uuid, apelido text, avatar jsonb, valor bigint)
language sql stable security definer set search_path = public as $$
  with p as (select * from fazenda_semana_placar(p_semana, p_desde, p_ate)),
  v as (
    select 'ranking' as cat, p.jogador_id, p.apelido, p.avatar, p.criado_em, p.ranking as valor, p.ranking as xp from p
    union all select 'niveis',   p.jogador_id, p.apelido, p.avatar, p.criado_em, p.niveis,   p.ranking from p
    union all select 'moedas',   p.jogador_id, p.apelido, p.avatar, p.criado_em, p.moedas,   p.ranking from p
    union all select 'vendeu',   p.jogador_id, p.apelido, p.avatar, p.criado_em, p.vendeu,   p.ranking from p
    union all select 'comprou',  p.jogador_id, p.apelido, p.avatar, p.criado_em, p.comprou,  p.ranking from p
    union all select 'convites', p.jogador_id, p.apelido, p.avatar, p.criado_em, p.convites, p.ranking from p)
  select v.cat, row_number() over (partition by v.cat order by v.valor desc, v.xp desc, v.criado_em), v.jogador_id, v.apelido, v.avatar, v.valor
    from v where v.valor > 0;
$$;

-- Fecha a semana que acabou (premia o top 3 de cada categoria) e abre a nova (a foto de cada um).
-- Roda na primeira chamada depois da sexta 22h (fazenda_auth); a trava impede premiar duas vezes.
create or replace function public.fazenda_semana_fechar()
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_ini  timestamptz := fazenda_semana_inicio(now());
  v_reg  jsonb := fazenda_evento_regras();
  s      record;
  r      record;
  v_dia  int;
  v_item text;
  v_sorte int;   -- fase 64
begin
  if exists (select 1 from fazenda_semanas where inicio = v_ini) then return; end if;
  perform pg_advisory_xact_lock(hashtext('fazenda_semana'));
  if exists (select 1 from fazenda_semanas where inicio = v_ini) then return; end if;   -- outra chamada fechou antes
  -- a última semana aberta (normalmente a que acabou agora)
  select * into s from fazenda_semanas where fechada_em is null order by inicio desc limit 1;
  if found then
    for r in select * from fazenda_semana_posicoes(s.inicio, s.aberta_em, now()) p where p.posicao <= 3 loop
      v_dia := (v_reg->'diamantes'->>(r.posicao::int - 1))::int;
      select c->'itens'->>(r.posicao::int - 1) into v_item from jsonb_array_elements(v_reg->'categorias') c where c->>'id' = r.categoria;
      -- fase 64: o item vem com 50% de chance; sem item próprio do lugar, um material do píer (pesos do mercador)
      if random() * 100 >= coalesce((v_reg->>'chance_item')::int, 100) then
        v_item := null;
      elsif v_item is null then
        v_sorte := floor(random() * 100)::int;   -- (um sorteio só: random() no where sorteava de novo a cada linha)
        select y.r->>'id' into v_item
          from (select x.r, sum((x.r->>'peso')::int) over (order by x.ord) as acum
                  from jsonb_array_elements(fazenda_raros()) with ordinality as x(r, ord)) y
         where y.acum > v_sorte
         order by y.acum limit 1;
      end if;
      insert into fazenda_semana_premios (semana, categoria, posicao, jogador_id, valor, diamantes, item)
      values (s.inicio, r.categoria, r.posicao, r.jogador_id, r.valor, v_dia, v_item);
      update fazenda_jogadores set diamantes = diamantes + v_dia where id = r.jogador_id;
      if v_item is not null then
        insert into fazenda_celeiro (jogador_id, item, quantidade) values (r.jogador_id, v_item, 1)
        on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
      end if;
    end loop;
    update fazenda_semanas set fechada_em = now() where fechada_em is null;
  end if;
  -- a foto do começo da semana nova
  insert into fazenda_semana_base (jogador_id, semana, xp, moedas_ganhas, xp_pago)
  select id, v_ini, xp, moedas_ganhas, xp_pago from fazenda_jogadores
  on conflict (jogador_id) do update set semana = excluded.semana, xp = excluded.xp, moedas_ganhas = excluded.moedas_ganhas,
                                          xp_pago = excluded.xp_pago;   -- (fase 70)
  insert into fazenda_semanas (inicio) values (v_ini);
end;
$$;

-- os troféus de um jogador: quantas vezes ficou em 1º, 2º e 3º em cada categoria
create or replace function public.fazenda_trofeus(p_jogador uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(x.categoria, jsonb_build_array(x.p1, x.p2, x.p3)), '{}'::jsonb) from (
    select categoria, count(*) filter (where posicao = 1) as p1, count(*) filter (where posicao = 2) as p2,
           count(*) filter (where posicao = 3) as p3
      from fazenda_semana_premios where jogador_id = p_jogador group by categoria) x;
$$;

-- O painel do evento: até quando vai, o top 3 de agora em cada categoria, a sua posição e quem
-- ganhou na semana passada
create or replace function public.fazenda_evento(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth_ler(p_token);   -- (e fecha a semana, se virou; fase 71: sem a fila de uma por vez)
  s       record;
  c       record;
  v_ant   timestamptz;
  v_vez   boolean;
begin
  select * into s from fazenda_semanas order by inicio desc limit 1;
  select max(semana) into v_ant from fazenda_semana_premios;
  -- fase 71: o placar de todos fica pronto por 1 minuto; um recalcula e os outros leem o pronto (quem
  -- chega na primeira vez da semana espera o que está calculando)
  select * into c from fazenda_semana_cache where semana = s.inicio;
  if not found or c.calculado_em < now() - interval '1 minute' then
    if found then v_vez := pg_try_advisory_xact_lock(7071, hashtext(s.inicio::text));
    else perform pg_advisory_xact_lock(7071, hashtext(s.inicio::text)); v_vez := true;
    end if;
    if v_vez then
      select * into c from fazenda_semana_cache where semana = s.inicio;   -- (quem esperou pode já ter o novo)
      if not found or c.calculado_em < now() - interval '1 minute' then
        with p as (select * from fazenda_semana_posicoes(s.inicio, s.aberta_em, now()))
        insert into fazenda_semana_cache (semana, calculado_em, top, posicoes, totais)
        select s.inicio, now(),
               coalesce((select jsonb_object_agg(t.categoria, t.lista) from (
                 select categoria, jsonb_agg(jsonb_build_object('apelido', apelido, 'avatar', avatar, 'valor', valor, 'id', jogador_id) order by posicao) as lista
                   from p where posicao <= 3 group by categoria) t), '{}'::jsonb),
               coalesce((select jsonb_object_agg(q.jogador, q.cats) from (
                 select jogador_id::text as jogador, jsonb_object_agg(categoria, jsonb_build_array(posicao, valor)) as cats
                   from p group by jogador_id) q), '{}'::jsonb),
               coalesce((select jsonb_object_agg(n.categoria, n.total) from (
                 select categoria, count(*) as total from p group by categoria) n), '{}'::jsonb)
        on conflict (semana) do update
          set calculado_em = excluded.calculado_em, top = excluded.top, posicoes = excluded.posicoes, totais = excluded.totais
        returning * into c;
      end if;
    end if;
  end if;
  return jsonb_build_object(
    'inicio', s.inicio,
    'desde', s.aberta_em,
    'fim', s.inicio + interval '7 days',
    'regras', fazenda_evento_regras(),
    'placar', coalesce((
      select jsonb_object_agg(k.categoria, jsonb_build_object(
               'top', coalesce((select jsonb_agg((t.e - 'id') || jsonb_build_object('eu', t.e->>'id' = v_id::text) order by t.ord)
                                  from jsonb_array_elements(c.top->k.categoria) with ordinality t(e, ord)), '[]'::jsonb),
               'eu', case when c.posicoes->(v_id::text) ? k.categoria
                          then jsonb_build_object('posicao', (c.posicoes->(v_id::text)->k.categoria->>0)::bigint,
                                                  'valor', (c.posicoes->(v_id::text)->k.categoria->>1)::bigint) end,
               'total', (c.totais->>k.categoria)::bigint))
        from jsonb_object_keys(c.totais) k(categoria)), '{}'::jsonb),
    'passada', (
      select jsonb_build_object('semana', v_ant, 'premios', jsonb_agg(jsonb_build_object(
               'categoria', p.categoria, 'posicao', p.posicao, 'apelido', j.apelido, 'avatar', j.avatar,
               'valor', p.valor, 'item', p.item, 'diamantes', p.diamantes, 'eu', p.jogador_id = v_id) order by p.categoria, p.posicao))
        from fazenda_semana_premios p join fazenda_jogadores j on j.id = p.jogador_id
       where p.semana = v_ant)
  );
end;
$$;

-- abre a semana de agora (a primeira: o evento começa quando este SQL roda)
select public.fazenda_semana_fechar();

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
  -- fase 83: 1 em cada 6 blocos de 3 h (era 30: quase ninguém via)
  select '{"luvas": 4, "nivel": 3, "chance": 6,
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
             when m.em < now() - make_interval(hours => fazenda_turno(p_jogador)::int) then 'fechada'
             else 'nao_deu_conta' end as motivo) x
   where c.jogador_id = p_jogador and c.estado = 'plantado' and now() >= m.em and m.em > now() - interval '7 days'
  on conflict (jogador_id, posicao, plantado_em) do nothing;
  delete from fazenda_murchas where jogador_id = p_jogador and murchou_em < now() - interval '7 days';
end;
$$;

-- ------------------------------------------------------------
-- Fase 67: o chat global, com pedidos que viram anúncio reservado na barraca.
-- • fazenda_chat guarda só a última hora: as mensagens somem em 60 min e cada envio apaga as velhas, então
--   a tabela nunca passa de 1 hora de conversa. Escreve do nível 5 em diante (ler, todo mundo lê); uma
--   mensagem a cada 8 s, 30 por hora (6 pedidos). Texto até 120 letras, sem palavrão (fazenda_chat_palavras,
--   comparando o texto normalizado: sem acento, 0→o, 4→a..., letras repetidas juntas) e sem link.
-- • Pedido: item, quantidade e preço de cada (dentro da faixa da feira). "Vender pra ele"
--   (fazenda_chat_vender) põe o item na barraca de quem vende, pelo preço do pedido, reservado para quem
--   pediu por 2 h (só ele vê e compra); depois vira anúncio normal, com as 48 h de sempre.
-- • Cada um apaga as suas mensagens; o admin apaga qualquer uma (fica em fazenda_admin_log).
-- ------------------------------------------------------------
create or replace function public.fazenda_chat_regras()
returns jsonb language sql immutable as $$
  select '{"minutos": 60, "nivel": 5, "letras": 120, "intervalo": 8, "por_hora": 30, "pedidos_hora": 6,
           "reserva_horas": 2, "mostrar": 80}'::jsonb;
$$;

create table if not exists public.fazenda_chat (
  id          bigint generated always as identity primary key,
  jogador_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  texto       text not null default '' check (char_length(texto) <= 120),
  item        text references public.fazenda_culturas(id),   -- pedido: o item, quantos e quanto paga cada
  qtd         int check (qtd > 0),
  preco       int check (preco > 0),
  criado_em   timestamptz not null default now(),
  apagado_por uuid references public.fazenda_jogadores(id) on delete set null,
  apagado_em  timestamptz
);
create index if not exists fazenda_chat_criado on public.fazenda_chat (criado_em);
create index if not exists fazenda_chat_jogador on public.fazenda_chat (jogador_id, criado_em);
alter table public.fazenda_chat enable row level security;
revoke all on public.fazenda_chat from anon, authenticated;

-- o anúncio reservado para quem pediu no chat (pedido_id sem chave: a mensagem some em 1 h)
alter table public.fazenda_feira add column if not exists reservado_para uuid references public.fazenda_jogadores(id) on delete set null;
alter table public.fazenda_feira add column if not exists reservado_ate timestamptz;
alter table public.fazenda_feira add column if not exists pedido_id bigint;
alter table public.fazenda_feira add column if not exists reserva_vista boolean not null default false;
create index if not exists fazenda_feira_pedido on public.fazenda_feira (pedido_id) where pedido_id is not null;
create index if not exists fazenda_feira_reservado on public.fazenda_feira (reservado_para) where reservado_para is not null;

-- o texto como o filtro enxerga: minúsculo, sem acento, 0→o 1→i 3→e 4→a 5→s 7→t @→a $→s e letras
-- repetidas juntas ("pooorrra" → "pora"); a lista passa pela mesma conta
create or replace function public.fazenda_chat_norm(p text)
returns text language sql immutable as $$
  select regexp_replace(translate(lower(coalesce(p, '')), 'áàâãäéèêëíìîïóòôõöúùûüç013457@$', 'aaaaaeeeeiiiiooooouuuucoieastas'),
                        '([a-z])\1+', '\1', 'g');
$$;
create or replace function public.fazenda_chat_palavras()
returns text[] language sql immutable as $$
  select array['porra', 'caralho', 'karalho', 'buceta', 'boceta', 'xoxota', 'xota', 'puta', 'puto', 'putaria', 'merda', 'bosta',
               'cu', 'cuzao', 'foder', 'foda', 'fodase', 'fodido', 'fudido', 'fuder', 'fdp', 'pqp', 'vsf', 'tnc', 'vtnc', 'krl',
               'crl', 'pnc', 'cacete', 'piroca', 'punheta', 'punheteiro', 'siririca', 'boquete', 'viado', 'bicha',
               'arrombado', 'arrombada', 'babaca', 'otario', 'otaria', 'corno', 'corna', 'vagabundo', 'vagabunda', 'vadia',
               'desgracado', 'desgracada', 'retardado', 'retardada', 'estupro', 'estuprador', 'escroto', 'escrota',
               'filho da puta', 'vai se foder', 'pau no cu'];
$$;
-- tem palavrão? palavra inteira (com plural), e também soletrado com espaço ou ponto ("p o r r a")
create or replace function public.fazenda_chat_palavrao(p text)
returns boolean language sql immutable as $$
  with l as (select string_agg(regexp_replace(fazenda_chat_norm(w), '([.*+?()\[\]{}|^$\\])', '\\\1', 'g'), '|') as re
               from unnest(fazenda_chat_palavras()) w),
       t as (select fazenda_chat_norm(p) as n)
  select t.n ~ ('\m(' || l.re || ')s?\M')
      or exists (select 1 from regexp_matches(t.n, '(?:\m[a-z]\M[^a-z]{1,2}){2,}\m[a-z]\M', 'g') m
                  where regexp_replace(regexp_replace(m[1], '[^a-z]', '', 'g'), '([a-z])\1+', '\1', 'g') ~ ('^(' || l.re || ')s?$'))
    from l, t;
$$;
-- limpa o texto (sem caractere de controle, espaços juntos) e barra o que não pode
create or replace function public.fazenda_chat_texto(p_texto text)
returns text
language plpgsql immutable
set search_path = public, extensions
as $$
declare
  v text := btrim(regexp_replace(regexp_replace(coalesce(p_texto, ''), '[[:cntrl:]]', ' ', 'g'), '\s+', ' ', 'g'));
begin
  if char_length(v) > (fazenda_chat_regras()->>'letras')::int then raise exception 'chat_longo'; end if;
  if v ~* '(https?://|www\.|\.(com|net|org|br|gg|io|me|ly|xyz|site|online|app|link)(\M|/)|discord\.|t\.me/|wa\.me/)' then
    raise exception 'chat_link';
  end if;
  if fazenda_chat_palavrao(v) then raise exception 'chat_palavrao'; end if;
  return v;
end;
$$;

-- A conversa da última hora (as 80 mais novas, sem as apagadas e sem as de banidos). Com p_depois, só as
-- novas, os ids que sumiram (apagados) e quem atendeu os pedidos (para a busca de 5 em 5 s ficar leve).
create or replace function public.fazenda_chat(p_token text, p_depois bigint default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth_ler(p_token);   -- fase 71: só lê, sem a fila de uma por vez
  v_r  jsonb := fazenda_chat_regras();
  v_de timestamptz := now() - make_interval(mins => (v_r->>'minutos')::int);
  j    record;
begin
  select fazenda_nivel(xp) as nivel, admin into j from fazenda_jogadores where id = v_id;
  return jsonb_build_object(
    'regras', v_r,
    'pode_escrever', j.nivel >= (v_r->>'nivel')::int,
    'admin', j.admin is not null,
    'mensagens', coalesce((
      select jsonb_agg(m order by (m->>'id')::bigint) from (
        select jsonb_build_object('id', c.id, 'jogador', c.jogador_id, 'apelido', p.apelido, 'avatar', p.avatar,
                 'nivel', fazenda_nivel(p.xp), 'admin', p.admin, 'texto', c.texto, 'em', c.criado_em,
                 'pedido', case when c.item is not null then jsonb_build_object('item', c.item, 'qtd', c.qtd, 'preco', c.preco) end) as m
          from fazenda_chat c join fazenda_jogadores p on p.id = c.jogador_id
         where c.criado_em >= v_de and c.apagado_em is null and p.banido_em is null
           and (p_depois is null or c.id > p_depois)
         order by c.id desc
         limit (v_r->>'mostrar')::int) x), '[]'::jsonb),
    'apagadas', case when p_depois is null then '[]'::jsonb else coalesce((
      select jsonb_agg(c.id) from fazenda_chat c join fazenda_jogadores p on p.id = c.jogador_id
       where c.criado_em >= v_de and c.id <= p_depois and (c.apagado_em is not null or p.banido_em is not null)), '[]'::jsonb) end,
    'atendidos', coalesce((
      select jsonb_object_agg(x.pedido_id::text, x.quem) from (
        select f.pedido_id, jsonb_agg(jsonb_build_object('apelido', vj.apelido, 'qtd', f.qtd) order by f.id) as quem
          from fazenda_feira f join fazenda_jogadores vj on vj.id = f.vendedor_id
          join fazenda_chat c on c.id = f.pedido_id
         where c.criado_em >= v_de
         group by f.pedido_id) x), '{}'::jsonb));
end;
$$;

create or replace function public.fazenda_chat_enviar(p_token text, p_texto text, p_item text default null,
                                                     p_qtd int default null, p_preco int default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_r     jsonb := fazenda_chat_regras();
  v_texto text;
  v_faixa int[];
  u       record;
  v_n     int;
  v_ped   int;
  v_novo  bigint;
begin
  -- o que passou de 60 min some de vez: a tabela nunca guarda mais de 1 hora de conversa
  delete from fazenda_chat where criado_em < now() - make_interval(mins => (v_r->>'minutos')::int);
  if (select fazenda_nivel(xp) from fazenda_jogadores where id = v_id) < (v_r->>'nivel')::int then raise exception 'chat_nivel'; end if;
  v_texto := fazenda_chat_texto(p_texto);
  if p_item is null and v_texto = '' then raise exception 'chat_vazio'; end if;
  if p_item is not null then
    v_faixa := fazenda_feira_faixa(p_item);
    if v_faixa is null then raise exception 'item_invalido'; end if;
    if p_qtd is null or p_qtd < 1 or p_qtd > (fazenda_feira_regras()->>'qtd_max')::int then raise exception 'quantidade_invalida'; end if;
    if p_preco is null or p_preco < v_faixa[1] or p_preco > v_faixa[2] then raise exception 'preco_invalido'; end if;
  end if;
  perform pg_advisory_xact_lock(hashtext('fazenda_chat:' || v_id::text));   -- dois envios juntos não furam o limite
  select texto, item, criado_em into u from fazenda_chat where jogador_id = v_id order by id desc limit 1;
  if found and u.criado_em > now() - make_interval(secs => (v_r->>'intervalo')::int) then raise exception 'chat_rapido'; end if;
  if found and p_item is null and u.item is null and lower(u.texto) = lower(v_texto) then raise exception 'chat_repetida'; end if;
  select count(*), count(item) into v_n, v_ped from fazenda_chat where jogador_id = v_id and criado_em > now() - interval '1 hour';
  if v_n >= (v_r->>'por_hora')::int or (p_item is not null and v_ped >= (v_r->>'pedidos_hora')::int) then
    raise exception 'chat_limite';
  end if;
  insert into fazenda_chat (jogador_id, texto, item, qtd, preco)
  values (v_id, v_texto, p_item, case when p_item is not null then p_qtd end, case when p_item is not null then p_preco end)
  returning id into v_novo;
  return jsonb_build_object('id', v_novo);
end;
$$;

create or replace function public.fazenda_chat_apagar(p_token text, p_id bigint)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  m    record;
begin
  select * into m from fazenda_chat where id = p_id and apagado_em is null;
  if not found then raise exception 'mensagem_sumiu'; end if;
  if m.jogador_id <> v_id then
    perform fazenda_admin_id(p_token);   -- a dos outros, só o admin (sem_permissao)
    insert into fazenda_admin_log (admin_id, alvo_id, acao, motivo)
    values (v_id, m.jogador_id, 'apagar_chat', left(coalesce(nullif(m.texto, ''), '(pedido de ' || m.item || ')'), 200));
  end if;
  update fazenda_chat set apagado_em = now(), apagado_por = v_id where id = p_id;
  return jsonb_build_object('ok', true);
end;
$$;

-- Cria o anúncio na barraca (o anunciar da feira e o "vender pra ele" do chat passam por aqui). Com
-- p_para, fica reservado para essa pessoa por 2 h.
create or replace function public.fazenda_feira_criar(p_vendedor uuid, p_item text, p_qtd int, p_preco int,
                                                     p_para uuid default null, p_pedido bigint default null)
returns bigint
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_r     jsonb := fazenda_feira_regras();
  v_faixa int[] := fazenda_feira_faixa(p_item);
  v_livre int;
  v_novo  bigint;
begin
  perform fazenda_feira_vencidos(p_vendedor);
  if v_faixa is null then raise exception 'item_invalido'; end if;
  if p_qtd is null or p_qtd < 1 or p_qtd > (v_r->>'qtd_max')::int then raise exception 'quantidade_invalida'; end if;
  if p_preco is null or p_preco < v_faixa[1] or p_preco > v_faixa[2] then raise exception 'preco_invalido'; end if;
  if (select count(*) from fazenda_feira where vendedor_id = p_vendedor and vendido_em is null) >= fazenda_feira_limite(p_vendedor) then
    raise exception 'limite_anuncios';   -- (fase 51: compre mais barracas na feira)
  end if;
  -- a ração reservada para os bichos fica no celeiro
  select ce.quantidade - coalesce((select quantidade from fazenda_reservas where jogador_id = p_vendedor and item = p_item), 0) into v_livre
    from fazenda_celeiro ce where ce.jogador_id = p_vendedor and ce.item = p_item for update;
  if coalesce(v_livre, 0) < p_qtd then raise exception 'sem_itens'; end if;
  update fazenda_celeiro set quantidade = quantidade - p_qtd where jogador_id = p_vendedor and item = p_item;
  insert into fazenda_feira (vendedor_id, item, qtd, preco, reservado_para, reservado_ate, pedido_id)
  values (p_vendedor, p_item, p_qtd, p_preco, p_para,
          case when p_para is not null then now() + make_interval(hours => (fazenda_chat_regras()->>'reserva_horas')::int) end, p_pedido)
  returning id into v_novo;
  return v_novo;
end;
$$;

-- "Vender pra ele": o pedido do chat vira anúncio na sua barraca, pelo preço do pedido, reservado para quem
-- pediu. Vários podem atender o mesmo pedido, até somar a quantidade pedida.
create or replace function public.fazenda_chat_vender(p_token text, p_id bigint, p_qtd int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_r    jsonb := fazenda_chat_regras();
  m      record;
  v_ja   int;
  v_novo bigint;
begin
  select c.* into m from fazenda_chat c join fazenda_jogadores p on p.id = c.jogador_id
   where c.id = p_id and c.item is not null and c.apagado_em is null and p.banido_em is null
     and c.criado_em >= now() - make_interval(mins => (v_r->>'minutos')::int)
     for update of c;
  if not found then raise exception 'pedido_sumiu'; end if;
  if m.jogador_id = v_id then raise exception 'pedido_seu'; end if;
  select coalesce(sum(qtd), 0) into v_ja from fazenda_feira where pedido_id = p_id;
  if v_ja >= m.qtd then raise exception 'pedido_atendido'; end if;
  if p_qtd is null or p_qtd < 1 or p_qtd > m.qtd - v_ja then raise exception 'quantidade_invalida'; end if;
  v_novo := fazenda_feira_criar(v_id, m.item, p_qtd, m.preco, m.jogador_id, p_id);
  return jsonb_build_object('id', v_novo, 'para', (select apelido from fazenda_jogadores where id = m.jogador_id),
                            'ate', (select reservado_ate from fazenda_feira where id = v_novo), 'estado', fazenda_estado(v_id));
end;
$$;

-- ------------------------------------------------------------
-- Fase 68: o reator deixa bicho radioativo.
-- • Com o reator na fazenda, a cada hora cada bicho tem 1 em 200 de ficar radioativo por meia hora: nesse
--   tempo ele dá o produto dele a cada 2 minutos (15 ao todo), direto no celeiro, sem ração e sem XP.
-- • No fim da meia hora, 1 em 200 de o bicho não resistir: ele morre e é preciso comprar outro.
-- • As horas contam desde que o reator está lá (fazenda_jogadores.radiacao_em; no máximo as últimas 24 de
--   uma vez) e são sorteadas quando a fazenda carrega (fazenda_reator, dentro do fazenda_carregar).
-- • fazenda_radiacao guarda o que aconteceu (7 dias), para o aviso no jogo.
-- (No jogo, sem SQL: as moças ajudantes cada uma de um jeito e as faíscas do eletricista.)
-- ------------------------------------------------------------
alter table public.fazenda_animais add column if not exists radioativo_de timestamptz;
alter table public.fazenda_animais add column if not exists radioativo_ate timestamptz;
alter table public.fazenda_animais add column if not exists radioativo_dado smallint not null default 0;   -- quantos já deu
alter table public.fazenda_jogadores add column if not exists radiacao_em timestamptz;   -- a última hora sorteada

create table if not exists public.fazenda_radiacao (
  id         bigint generated always as identity primary key,
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  animal     text not null,   -- o tipo do bicho
  evento     text not null check (evento in ('radioativo', 'morreu')),
  produto    text,
  qtd        int,
  em         timestamptz not null default now(),
  visto      boolean not null default false
);
create index if not exists fazenda_radiacao_jogador on public.fazenda_radiacao (jogador_id, em);
alter table public.fazenda_radiacao enable row level security;
revoke all on public.fazenda_radiacao from anon, authenticated;

update public.fazenda_itens
   set descricao = 'Gera 120 ⚡/h sem parar, de dia e de noite (80 na onda de calor, para não esquentar). Cuidado com a radiação: a cada hora, cada bicho da fazenda tem 1 em 200 de ficar radioativo por meia hora (dá o produto dele a cada 2 minutos, direto no celeiro) e, no fim, 1 em 200 de não resistir.'
 where id = 'reator';

create or replace function public.fazenda_radiacao_regras()
returns jsonb language sql immutable as $$
  -- fase 75: o sorteio é a cada 30 min (era de hora em hora), no máximo os últimos 48 (24 h)
  select '{"chance": 200, "minutos": 30, "cada_seg": 120, "morte": 200, "intervalo_min": 30, "sorteios_max": 48}'::jsonb;
$$;

-- Entrega o que os bichos radioativos deram até p_ate (1 produto a cada 2 min) e fecha a radiação que já
-- acabou: 1 em 200 de o bicho morrer; senão ele volta ao normal.
create or replace function public.fazenda_radiacao_fechar(p_jogador uuid, p_ate timestamptz)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_r     jsonb := fazenda_radiacao_regras();
  v_cada  int := (v_r->>'cada_seg')::int;
  v_total int := (v_r->>'minutos')::int * 60 / (v_r->>'cada_seg')::int;
  a       record;
  v_deu   int;
begin
  for a in select an.id, an.tipo, an.radioativo_de, an.radioativo_ate, an.radioativo_dado, t.produto
             from fazenda_animais an join fazenda_animais_tipos t on t.id = an.tipo
            where an.jogador_id = p_jogador and an.radioativo_de is not null and an.radioativo_de <= p_ate
              for update of an loop
    v_deu := least(v_total, floor(extract(epoch from least(p_ate, a.radioativo_ate) - a.radioativo_de) / v_cada)::int);
    if v_deu > a.radioativo_dado then
      insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, a.produto, v_deu - a.radioativo_dado)
      on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
      update fazenda_animais set radioativo_dado = v_deu where id = a.id;
    end if;
    if p_ate >= a.radioativo_ate then
      if random() < 1.0 / (v_r->>'morte')::int then
        delete from fazenda_animais where id = a.id;
        insert into fazenda_radiacao (jogador_id, animal, evento, em) values (p_jogador, a.tipo, 'morreu', a.radioativo_ate);
      else
        update fazenda_animais set radioativo_de = null, radioativo_ate = null, radioativo_dado = 0 where id = a.id;
      end if;
    end if;
  end loop;
end;
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

-- ------------------------------------------------------------
-- Fase 69: o calendário de resgate diário (e os canteiros até o 45, em fazenda_limite_canteiros).
-- • 28 dias: um resgate por dia (o dia de Brasília, fazenda_hoje). Faltou um dia? Não perde nada: no
--   próximo resgate pega o dia seguinte do ciclo. Depois do 28, começa um ciclo novo.
-- • Trilha grátis para todos: moedas (vezes o nível), XP, café dos ajudantes, XP em dobro e diamantes
--   nos dias 7, 14, 21 e 28.
-- • Trilha dourada: liberada com 120 diamantes por ciclo. Dá um prêmio a mais por dia (XP em dobro,
--   café, pacote de XP, moedas, raros, 50 diamantes de volta) e, no dia 28, o Fazendeiro de ouro, um
--   personagem que só sai aqui (fazenda_avatar_exclusivos). Liberada no meio do ciclo, já entrega os
--   prêmios dourados dos dias que passaram.
-- • No nível 45, XP vira moedas; sem ajudante, o café vira moedas.
-- ------------------------------------------------------------
create table if not exists public.fazenda_calendario (
  jogador_id    uuid primary key references public.fazenda_jogadores(id) on delete cascade,
  ciclo         int not null default 1,
  dia           smallint not null default 0,   -- quantos dias do ciclo já resgatou (0 a 28)
  ultimo        date,                          -- o dia (de Brasília) do último resgate
  dourado_ciclo int                            -- o ciclo em que liberou a trilha dourada
);
alter table public.fazenda_calendario enable row level security;
revoke all on public.fazenda_calendario from anon, authenticated;

create or replace function public.fazenda_calendario_regras()
returns jsonb language sql immutable as $$
  select '{"dias": 28, "dourado": 120}'::jsonb;
$$;

-- os prêmios de cada dia: g = grátis, d = dourada. moedas: vezes o nível; xp: % do nível; xp2 e cafe: minutos
create or replace function public.fazenda_calendario_premios()
returns jsonb language sql immutable as $$
  select '[
    {"g": [{"tipo": "moedas", "qtd": 15}],    "d": [{"tipo": "moedas", "qtd": 50}]},
    {"g": [{"tipo": "xp", "qtd": 3}],         "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "moedas", "qtd": 20}],    "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "cafe", "qtd": 30}],      "d": [{"tipo": "xp", "qtd": 10}]},
    {"g": [{"tipo": "moedas", "qtd": 25}],    "d": [{"tipo": "moedas", "qtd": 60}]},
    {"g": [{"tipo": "xp2", "qtd": 30}],       "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "diamantes", "qtd": 3}],  "d": [{"tipo": "diamantes", "qtd": 10}, {"tipo": "item", "item": "madeira_nobre", "qtd": 1}]},
    {"g": [{"tipo": "moedas", "qtd": 20}],    "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "xp", "qtd": 4}],         "d": [{"tipo": "moedas", "qtd": 70}]},
    {"g": [{"tipo": "moedas", "qtd": 25}],    "d": [{"tipo": "xp", "qtd": 10}]},
    {"g": [{"tipo": "cafe", "qtd": 30}],      "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "moedas", "qtd": 30}],    "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "xp2", "qtd": 30}],       "d": [{"tipo": "moedas", "qtd": 80}]},
    {"g": [{"tipo": "diamantes", "qtd": 5}],  "d": [{"tipo": "diamantes", "qtd": 10}, {"tipo": "item", "item": "perola_negra", "qtd": 1}]},
    {"g": [{"tipo": "moedas", "qtd": 25}],    "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "xp", "qtd": 5}],         "d": [{"tipo": "xp", "qtd": 10}]},
    {"g": [{"tipo": "moedas", "qtd": 30}],    "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "cafe", "qtd": 45}],      "d": [{"tipo": "moedas", "qtd": 90}]},
    {"g": [{"tipo": "moedas", "qtd": 35}],    "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "xp2", "qtd": 45}],       "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "diamantes", "qtd": 5}],  "d": [{"tipo": "diamantes", "qtd": 10}, {"tipo": "item", "item": "corda_naval", "qtd": 1}, {"tipo": "item", "item": "pedra_cantaria", "qtd": 1}]},
    {"g": [{"tipo": "moedas", "qtd": 30}],    "d": [{"tipo": "xp", "qtd": 10}]},
    {"g": [{"tipo": "xp", "qtd": 5}],         "d": [{"tipo": "moedas", "qtd": 100}]},
    {"g": [{"tipo": "moedas", "qtd": 40}],    "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "cafe", "qtd": 60}],      "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "moedas", "qtd": 45}],    "d": [{"tipo": "xp", "qtd": 10}]},
    {"g": [{"tipo": "xp2", "qtd": 60}],       "d": [{"tipo": "moedas", "qtd": 120}]},
    {"g": [{"tipo": "diamantes", "qtd": 10}], "d": [{"tipo": "avatar", "avatar": "fazendeiro_ouro"}, {"tipo": "diamantes", "qtd": 20}]}
  ]'::jsonb;
$$;

-- personagens que não estão à venda: só saem de um prêmio (o do calendário dourado)
create or replace function public.fazenda_avatar_exclusivos()
returns jsonb language sql immutable as $$
  select '{"fazendeiro_ouro": "calendario"}'::jsonb;
$$;

-- fase 84 (D10): o café e o XP em dobro do calendário viram vales guardados (fazenda_usar_vale liga)
create table if not exists public.fazenda_vales (
  id         bigserial primary key,
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  tipo       text not null check (tipo in ('cafe', 'xp2')),
  minutos    int  not null,
  criado_em  timestamptz not null default now()
);
create index if not exists fazenda_vales_jogador on public.fazenda_vales (jogador_id);
alter table public.fazenda_vales enable row level security;
revoke all on public.fazenda_vales from anon, authenticated;
revoke all on sequence public.fazenda_vales_id_seq from anon, authenticated;

-- Entrega um prêmio e devolve o que foi dado de fato (com as moedas já vezes o nível)
-- Fase 70: cada moeda da tabela vale um décimo do presente do nível (no 30: 300; antes era só o nível,
-- 30, e o prêmio não fazia diferença); o XP da trilha dourada ({"pago": true}) não conta no evento.
create or replace function public.fazenda_calendario_dar(p_jogador uuid, p jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_nivel int;
  v_tipo  text := p->>'tipo';
  v_qtd   int := coalesce((p->>'qtd')::int, 1);
  v_xp    int;
begin
  select fazenda_nivel(xp) into v_nivel from fazenda_jogadores where id = p_jogador;
  if v_tipo in ('xp', 'xp2') and v_nivel >= 45 then v_tipo := 'moedas'; v_qtd := 50; end if;   -- no último nível, XP não serve
  if v_tipo = 'cafe' and not exists (select 1 from fazenda_ajudantes where jogador_id = p_jogador) then v_tipo := 'moedas'; v_qtd := 20; end if;
  -- fase 84: o café e o XP em dobro viram vale (o jogador liga quando quiser); {"usar": true} liga na hora
  if v_tipo in ('cafe', 'xp2') and not coalesce((p->>'usar')::boolean, false) then
    insert into fazenda_vales (jogador_id, tipo, minutos) values (p_jogador, v_tipo, v_qtd);
    return jsonb_build_object('tipo', 'vale', 'vale', v_tipo, 'qtd', v_qtd);
  end if;
  if v_tipo = 'moedas' then
    v_qtd := v_qtd * greatest(fazenda_presente_nivel(v_nivel) / 10, 1);
    update fazenda_jogadores set moedas = moedas + v_qtd where id = p_jogador;
    return jsonb_build_object('tipo', 'moedas', 'qtd', v_qtd);
  elsif v_tipo = 'diamantes' then
    update fazenda_jogadores set diamantes = diamantes + v_qtd where id = p_jogador;
    return jsonb_build_object('tipo', 'diamantes', 'qtd', v_qtd);
  elsif v_tipo = 'xp' then
    v_xp := ceil((fazenda_xp_nivel(v_nivel + 1) - fazenda_xp_nivel(v_nivel)) * v_qtd / 100.0)::int;
    perform set_config('fazenda.xp_puro', '1', true);
    if (p->>'pago')::boolean then perform set_config('fazenda.xp_pago', '1', true); end if;
    update fazenda_jogadores set xp = xp + v_xp where id = p_jogador;
    perform set_config('fazenda.xp_puro', '', true);
    perform set_config('fazenda.xp_pago', '', true);
    return jsonb_build_object('tipo', 'xp', 'qtd', v_xp, 'pct', v_qtd);
  elsif v_tipo = 'xp2' then
    update fazenda_jogadores set xp2_ate = greatest(coalesce(xp2_ate, now()), now()) + make_interval(mins => v_qtd) where id = p_jogador;
    return jsonb_build_object('tipo', 'xp2', 'qtd', v_qtd);
  elsif v_tipo = 'cafe' then
    perform fazenda_trabalhar(p_jogador);   -- fecha o trabalho de antes no ritmo de antes (igual ao café da loja)
    perform fazenda_ajudantes_fechar(p_jogador, null);
    update fazenda_jogadores
       set cafe_de = case when cafe_ate > now() then cafe_de else now() end,
           cafe_ate = greatest(coalesce(cafe_ate, now()), now()) + make_interval(mins => v_qtd)
     where id = p_jogador;
    return jsonb_build_object('tipo', 'cafe', 'qtd', v_qtd);
  elsif v_tipo = 'item' then
    insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, p->>'item', v_qtd)
    on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
    return jsonb_build_object('tipo', 'item', 'item', p->>'item', 'qtd', v_qtd);
  elsif v_tipo = 'avatar' then
    update fazenda_jogadores set avatares = array_append(coalesce(avatares, '{}'), p->>'avatar')
     where id = p_jogador and not (p->>'avatar' = any(coalesce(avatares, '{}')));
    return jsonb_build_object('tipo', 'avatar', 'avatar', p->>'avatar');
  end if;
  return null;
end;
$$;

-- O calendário como o jogo mostra: o ciclo, quantos dias já foram, se dá para resgatar hoje e se a
-- trilha dourada está liberada. Ciclo acabado e já é outro dia: mostra o ciclo novo (o resgate começa ele).
create or replace function public.fazenda_calendario_estado(p_jogador uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  r      record;
  v_pode boolean;
  v_dias int := (fazenda_calendario_regras()->>'dias')::int;
  v_ciclo int := 1;
  v_dia   int := 0;
begin
  select * into r from fazenda_calendario where jogador_id = p_jogador;
  v_pode := r.ultimo is null or r.ultimo < fazenda_hoje();
  if found then v_ciclo := r.ciclo; v_dia := r.dia; end if;
  if v_dia >= v_dias and v_pode then v_ciclo := v_ciclo + 1; v_dia := 0; end if;
  return jsonb_build_object('ciclo', v_ciclo, 'dia', v_dia, 'pode', v_pode,
                            'dourado', coalesce(r.dourado_ciclo = v_ciclo, false),
                            'regras', fazenda_calendario_regras(), 'premios', fazenda_calendario_premios(),
                            'vales', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'tipo', v.tipo, 'minutos', v.minutos) order by v.id)
                                                 from fazenda_vales v where v.jogador_id = p_jogador), '[]'::jsonb));
end;
$$;

-- fase 84 (D10): usa um vale (o café ou o XP em dobro guardado); com ele já ligado, soma o tempo
create or replace function public.fazenda_usar_vale(p_token text, p_vale bigint)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  v    record;
  g    jsonb;
begin
  select * into v from fazenda_vales where id = p_vale and jogador_id = v_id for update;
  if not found then raise exception 'vale_invalido'; end if;
  if v.tipo = 'cafe' and not exists (select 1 from fazenda_ajudantes where jogador_id = v_id) then raise exception 'sem_ajudantes'; end if;
  delete from fazenda_vales where id = p_vale;
  g := fazenda_calendario_dar(v_id, jsonb_build_object('tipo', v.tipo, 'qtd', v.minutos, 'usar', true));
  return jsonb_build_object('ganho', g, 'estado', fazenda_estado(v_id));
end;
$$;

-- fase 84 (D9): quantas compras na loja de raros esta semana (a semana vira na segunda, em Brasília)
create or replace function public.fazenda_raros_semana(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from fazenda_diamantes_usos
   where jogador_id = p_jogador and item like 'raro:%'
     and em >= (date_trunc('week', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo');
$$;

-- fase 84 (D9): compra 1 material raro com diamantes (1 💎 a cada 10 mil do preço de venda), até 2 por semana
create or replace function public.fazenda_comprar_raro(p_token text, p_item text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_l     jsonb := fazenda_loja_diamantes()->'raros';
  v_preco int;
begin
  if v_l is null or not (v_l->'itens' ? p_item) then raise exception 'item_invalido'; end if;
  perform 1 from fazenda_jogadores where id = v_id for update;   -- (dois toques juntos: um só passa)
  if fazenda_raros_semana(v_id) >= (v_l->>'por_semana')::int then raise exception 'limite_semana'; end if;
  select ceil(venda / (v_l->>'por')::numeric)::int into v_preco from fazenda_culturas where id = p_item;
  if v_preco is null then raise exception 'item_invalido'; end if;
  if (select diamantes from fazenda_jogadores where id = v_id) < v_preco then raise exception 'diamantes_insuficientes'; end if;
  update fazenda_jogadores set diamantes = diamantes - v_preco where id = v_id;
  insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, p_item, 1)
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
  insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, 'raro:' || p_item, v_preco);
  return jsonb_build_object('item', p_item, 'diamantes', v_preco, 'estado', fazenda_estado(v_id));
end;
$$;

create or replace function public.fazenda_calendario_resgatar(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_dias int := (fazenda_calendario_regras()->>'dias')::int;
  r      record;
  v_p    jsonb;
  x      jsonb;
  v_g    jsonb := '[]'::jsonb;
  v_d    jsonb := '[]'::jsonb;
begin
  insert into fazenda_calendario (jogador_id) values (v_id) on conflict (jogador_id) do nothing;
  select * into r from fazenda_calendario where jogador_id = v_id for update;   -- dois toques juntos: um só passa
  if r.ultimo = fazenda_hoje() then raise exception 'calendario_hoje'; end if;
  if r.dia >= v_dias then r.ciclo := r.ciclo + 1; r.dia := 0; end if;
  r.dia := r.dia + 1;
  v_p := fazenda_calendario_premios() -> (r.dia - 1);
  for x in select * from jsonb_array_elements(v_p->'g') loop v_g := v_g || jsonb_build_array(fazenda_calendario_dar(v_id, x)); end loop;
  if r.dourado_ciclo = r.ciclo then
    for x in select * from jsonb_array_elements(v_p->'d') loop v_d := v_d || jsonb_build_array(fazenda_calendario_dar(v_id, x || '{"pago": true}')); end loop;
  end if;
  update fazenda_calendario set ciclo = r.ciclo, dia = r.dia, ultimo = fazenda_hoje() where jogador_id = v_id;
  return jsonb_build_object('dia', r.dia, 'gratis', v_g, 'dourado', v_d, 'estado', fazenda_estado(v_id));
end;
$$;

-- Libera a trilha dourada do ciclo de agora (os dias já resgatados ganham o prêmio dourado na hora)
create or replace function public.fazenda_calendario_dourado(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_regra jsonb := fazenda_calendario_regras();
  v_preco int := (v_regra->>'dourado')::int;
  r       record;
  x       jsonb;
  v_d     jsonb := '[]'::jsonb;
begin
  insert into fazenda_calendario (jogador_id) values (v_id) on conflict (jogador_id) do nothing;
  select * into r from fazenda_calendario where jogador_id = v_id for update;
  if r.dia >= (v_regra->>'dias')::int and (r.ultimo is null or r.ultimo < fazenda_hoje()) then   -- o ciclo novo já começou
    r.ciclo := r.ciclo + 1; r.dia := 0;
  end if;
  if r.dourado_ciclo = r.ciclo then raise exception 'ja_dourado'; end if;
  if (select diamantes from fazenda_jogadores where id = v_id for update) < v_preco then raise exception 'diamantes_insuficientes'; end if;
  update fazenda_jogadores set diamantes = diamantes - v_preco where id = v_id;
  insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, 'calendario_dourado', v_preco);
  update fazenda_calendario set ciclo = r.ciclo, dia = r.dia, dourado_ciclo = r.ciclo where jogador_id = v_id;
  for k in 1..r.dia loop
    for x in select * from jsonb_array_elements(fazenda_calendario_premios() -> (k - 1) -> 'd') loop
      v_d := v_d || jsonb_build_array(fazenda_calendario_dar(v_id, x || '{"pago": true}'));   -- (fase 70)
    end loop;
  end loop;
  return jsonb_build_object('dourado', v_d, 'estado', fazenda_estado(v_id));
end;
$$;

-- ------------------------------------------------------------
-- Fase 70: segurança e jogo limpo (a revisão de 17/10).
-- • Anúncio premiado fechado: fazenda_anuncio sai da API (os anúncios estão desligados no jogo e chamar
--   pelo console dava 1 diamante a cada 10 s). Quando voltarem: 1 a cada 5 min, 6 por dia, diamante só
--   nos 3 primeiros do dia.
-- • Uma chamada de cada vez por jogador (fazenda_auth): chamadas juntas duplicavam o que saía do baú,
--   pagavam conquista e presente do nível duas vezes e furavam os limites do dia. O baú e a rede de
--   canos também tiram e entregam numa coisa só; conquista e presente do nível pagam uma vez só.
-- • Evento da semana: o XP comprado com diamante (pacote de XP, XP da trilha dourada e a metade a mais do
--   XP em dobro: fazenda_jogadores.xp_pago) não conta no ranking nem em níveis; o que entra pela barraca
--   não conta em "mais moedas"; em vendeu e comprou, uma mesma pessoa do outro lado vale no máximo 25%
--   do total; convite conta quando o amigo chega ao nível 10 (era 5).
-- • Fazendas novas: no máximo 5 por hora e 20 por dia do mesmo endereço (IP). Código de recuperação
--   errado: 10 por hora do mesmo endereço e 2000 por hora no total (fazenda_tentativas, 2 dias).
-- • Peça do píer com diamante: no máximo o que a receita pede (anunciar na feira e comprar de novo
--   virava material raro sem fim).
-- • XP sem fim: plantar e arrancar, arar e desmanchar o canteiro. O XP de arar e plantar da fazenda
--   completa vem na colheita (+2) e canteiro novo espera os 8 min para dar XP de colheita.
-- • Calendário dourado sem a luva do Perks (vantagem contra os outros jogadores): no lugar, peças do
--   píer. As moedas do calendário passam a valer pelo presente do nível (um décimo dele por moeda da
--   tabela), não só pelo nível.
-- • Regras que tinham ficado para trás: a doceira volta a pedir os produtos novos (o filtro "ordem < 40"
--   da fase 21 deixava de fora tudo o que veio depois); o mercador só pede fruto que o nível já planta;
--   o 45 é mesmo o último nível (fazenda_nivel passava dele); conquistas dos níveis 15, 30, 35 e 40.
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists xp_pago bigint not null default 0;
alter table public.fazenda_jogadores add column if not exists anuncio_dia date;
alter table public.fazenda_jogadores add column if not exists anuncio_n smallint not null default 0;
alter table public.fazenda_semana_base add column if not exists xp_pago bigint not null default 0;

create table if not exists public.fazenda_tentativas (
  id   bigint generated always as identity primary key,
  ip   text not null,
  tipo text not null check (tipo in ('criar', 'recuperar')),
  em   timestamptz not null default now()
);
create index if not exists fazenda_tentativas_ip on public.fazenda_tentativas (tipo, ip, em);
create index if not exists fazenda_tentativas_em on public.fazenda_tentativas (em);
alter table public.fazenda_tentativas enable row level security;
revoke all on public.fazenda_tentativas from anon, authenticated;

-- as conquistas dos níveis que faltavam (havia 5, 10, 20, 25 e 45): quem já passou ganha na hora
insert into public.fazenda_conquistas_tipos (id, nome, descricao, medida, meta, recompensa, ordem) values
  ('nivel_15', 'Fazendeiro nível 15', 'Chegue ao nível 15', 'nivel', 15,   800, 33),
  ('nivel_30', 'Fazendeiro nível 30', 'Chegue ao nível 30', 'nivel', 30, 15000, 34),
  ('nivel_35', 'Fazendeiro nível 35', 'Chegue ao nível 35', 'nivel', 35, 30000, 35),
  ('nivel_40', 'Fazendeiro nível 40', 'Chegue ao nível 40', 'nivel', 40, 60000, 36)
on conflict (id) do update set
  nome = excluded.nome, descricao = excluded.descricao, medida = excluded.medida,
  meta = excluded.meta, recompensa = excluded.recompensa, ordem = excluded.ordem;

-- o endereço de quem chamou (o Cloudflare do Supabase manda no cf-connecting-ip; fora dele, null)
create or replace function public.fazenda_ip()
returns text language sql stable as $$
  select nullif(btrim(coalesce(h->>'cf-connecting-ip', h->>'x-real-ip', split_part(h->>'x-forwarded-for', ',', 1))), '')
    from (select nullif(current_setting('request.headers', true), '')::json as h) x;
$$;

-- ------------------------------------------------------------
-- Fase 71: o servidor mais leve (o "servidor sobrecarregado" do jogo).
-- • Ajudantes, baús e robôs trabalham em lote: cada um primeiro no modo rápido, com as tarefas direto,
--   sem um "exception" em volta de cada uma. Cada um desses blocos abria uma sub-transação, e centenas
--   numa chamada deixavam o banco lento para todos; a volta depois de horas fora passava dos 3 s e era
--   desfeita. Se uma tarefa der erro, o lote daquele ajudante, baú ou robô volta e é refeito no modo
--   seguro, como antes. O resultado é o mesmo (fazenda_bot_aplicar, fazenda_bot_animal,
--   fazenda_bot_pode_plantar).
-- • O clima de agora sai uma vez por chamada (fazenda_clima_agora), e a estação uma vez por rodada dos
--   ajudantes.
-- • Os catálogos que o estado manda em toda ação (culturas, itens, bichos, conquistas, ajudantes e
--   melhorias) ficam prontos em fazenda_cache. Gatilhos refazem o cache quando uma fase mexe nas tabelas
--   (o fim de cada faseN.sql também refaz, por causa das melhorias, que são uma função).
-- • A previsão do clima e do vento (a do vento olhava 24 h para a frente em todo estado) fica pronta uma
--   vez por minuto (fazenda_previsao_agora). Quem grava no cache não faz fila: um grava, os outros seguem.
-- • O placar do evento fica pronto por 1 minuto (fazenda_semana_cache): um calcula, os outros leem.
-- • O que só lê (chat, evento, status da compra, lista da feira) não espera na fila de uma chamada por
--   vez (fazenda_auth_ler).
-- • O fechamento da semana não trava ninguém (fazenda_semana_tentar_fechar: só uma chamada tenta, as
--   outras seguem) e, com o pg_cron, é o relógio do banco que fecha, na sexta às 22h01. O placar só conta
--   quem jogou na semana (quem não jogou tem tudo zerado), o que deixa o fechamento e o Evento leves.
-- ------------------------------------------------------------
create table if not exists public.fazenda_cache (
  chave text primary key,
  valor jsonb not null,
  em    timestamptz not null default now()
);
alter table public.fazenda_cache enable row level security;
revoke all on public.fazenda_cache from anon, authenticated;

create table if not exists public.fazenda_semana_cache (
  semana       timestamptz primary key,
  calculado_em timestamptz not null,
  top          jsonb not null,   -- {categoria: [os 3 primeiros]}
  posicoes     jsonb not null,   -- {jogador: {categoria: [posição, valor]}}
  totais       jsonb not null    -- {categoria: quantos têm valor}
);
alter table public.fazenda_semana_cache enable row level security;
revoke all on public.fazenda_semana_cache from anon, authenticated;

-- uma tarefa de ajudante, baú ou robô num canteiro: no modo rápido direto (o erro sobe e o lote todo é
-- refeito no modo seguro); no modo seguro, protegida (null = não deu)
create or replace function public.fazenda_bot_aplicar(p_jogador uuid, p_acao text, p_posicao int, p_cultura text, p_seguro boolean)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if not p_seguro then return fazenda_aplicar(p_jogador, p_acao, p_posicao, p_cultura, true); end if;
  begin
    return fazenda_aplicar(p_jogador, p_acao, p_posicao, p_cultura, true);
  exception when others then
    return null;
  end;
end;
$$;

-- o mesmo para um bicho (coletar ou dar ração)
create or replace function public.fazenda_bot_animal(p_jogador uuid, p_animal bigint, p_acao text, p_seguro boolean)
returns boolean
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if not p_seguro then perform fazenda_animal_um(p_jogador, p_animal, p_acao, true); return true; end if;
  begin
    perform fazenda_animal_um(p_jogador, p_animal, p_acao, true);
    return true;
  exception when others then
    return false;
  end;
end;
$$;

-- o robô consegue plantar essa semente nesse canteiro? (as checagens de fazenda_aplicar: arado,
-- nível, moedas e a estação ou uma estufa por perto)
create or replace function public.fazenda_bot_pode_plantar(p_jogador uuid, p_cultura text, p_posicao int)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((
    select c.estado = 'arado' and k.tipo = 'cultura' and fazenda_nivel(j.xp) >= k.nivel_min and j.moedas >= k.custo
           and (k.estacao is null or k.estacao = fazenda_estacao_em(now()) or fazenda_protegido(p_jogador, 'estufa', c.x, c.y))
      from fazenda_canteiros c, fazenda_culturas k, fazenda_jogadores j
     where c.jogador_id = p_jogador and c.posicao = p_posicao and k.id = p_cultura and j.id = p_jogador), false);
$$;

-- o clima de agora, uma conta só por chamada (o now() é o mesmo a chamada toda)
create or replace function public.fazenda_clima_agora()
returns text
language plpgsql
set search_path = public
as $$
declare
  k text := now()::text || '|' || coalesce(current_setting('fazenda.clima_teste', true), '');
  v text := current_setting('fazenda.clima_memo', true);
begin
  if v is not null and v <> '' and split_part(v, '#', 1) = k then return split_part(v, '#', 2); end if;
  v := fazenda_clima_em(now());
  perform set_config('fazenda.clima_memo', k || '#' || v, true);
  return v;
end;
$$;

-- o valor de um catálogo, montado na hora
create or replace function public.fazenda_cache_valor(p_chave text)
returns jsonb language sql stable security definer set search_path = public as $$
  select case p_chave
    when 'culturas' then (
      select jsonb_agg(jsonb_build_object(
               'id', id, 'nome', nome, 'emoji', emoji, 'tempo_seg', tempo_seg,
               'custo', custo, 'venda', venda, 'rendimento', rendimento,
               'xp', xp, 'nivel_min', nivel_min, 'tipo', tipo, 'estacao', estacao)
             order by ordem)
        from fazenda_culturas)
    when 'animais_tipos' then (select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_animais_tipos t)
    when 'conquistas_tipos' then (select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_conquistas_tipos t)
    when 'ajudantes_tipos' then (select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_ajudantes_tipos t)
    when 'melhorias_tipos' then fazenda_melhorias_tipos()
    when 'melhorias' then (select jsonb_object_agg(m->>'id', m) from jsonb_array_elements(fazenda_melhorias_tipos()) m)
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

-- um catálogo pronto (sem o cache, monta na hora: só lê)
create or replace function public.fazenda_cache_ler(p_chave text)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select valor from fazenda_cache where chave = p_chave), fazenda_cache_valor(p_chave));
$$;

-- grava no cache sem fazer fila: só quem pegar a vez grava (a vez fica com ele até a chamada acabar); os
-- outros usam o que montaram e seguem, sem esperar a linha do cache
create or replace function public.fazenda_cache_gravar(p_chave text, p_valor jsonb)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if pg_try_advisory_xact_lock(7072, hashtext(p_chave)) then
    insert into fazenda_cache (chave, valor, em) values (p_chave, p_valor, now())
    on conflict (chave) do update set valor = excluded.valor, em = excluded.em;
  end if;
end;
$$;

-- a previsão do clima e do vento (igual para todo mundo): montada uma vez por minuto. A do vento olha as
-- próximas 24 h e era a parte mais pesada do estado, que vai em toda ação. Com o clima ou a estação de
-- teste ligados, monta na hora.
create or replace function public.fazenda_previsao_agora()
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  k text := to_char(date_trunc('minute', now()), 'YYYY-MM-DD HH24:MI');
  v jsonb;
begin
  if coalesce(current_setting('fazenda.clima_teste', true), '') <> '' or coalesce(current_setting('fazenda.estacao_teste', true), '') <> '' then
    return jsonb_build_object('clima', fazenda_clima_previsao(now()), 'vento', fazenda_vento_previsao(now()));
  end if;
  select valor into v from fazenda_cache where chave = 'previsao' and valor->>'minuto' = k;
  if v is null then
    v := jsonb_build_object('minuto', k, 'clima', fazenda_clima_previsao(now()), 'vento', fazenda_vento_previsao(now()));
    perform fazenda_cache_gravar('previsao', v);
  end if;
  return v;
end;
$$;

-- os itens com o limite do nível (painel solar e turbina sobem com o nível): um por nível, montado na
-- primeira vez que alguém daquele nível precisa
create or replace function public.fazenda_cache_itens(p_nivel int)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  k text := 'itens:' || p_nivel;
  v jsonb;
begin
  select valor into v from fazenda_cache where chave = k;
  if v is null then
    select jsonb_agg(to_jsonb(t) || jsonb_build_object('limite', fazenda_limite_maquina(t.id, t.limite, p_nivel)) order by t.ordem)
      into v from fazenda_itens t;
    perform fazenda_cache_gravar(k, v);
  end if;
  return v;
end;
$$;

create or replace function public.fazenda_cache_gatilho()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
  perform fazenda_cache_montar();
  return null;
end;
$$;
drop trigger if exists fazenda_cache_culturas on public.fazenda_culturas;
create trigger fazenda_cache_culturas after insert or update or delete or truncate on public.fazenda_culturas
  for each statement execute function public.fazenda_cache_gatilho();
drop trigger if exists fazenda_cache_itens on public.fazenda_itens;
create trigger fazenda_cache_itens after insert or update or delete or truncate on public.fazenda_itens
  for each statement execute function public.fazenda_cache_gatilho();
drop trigger if exists fazenda_cache_conquistas on public.fazenda_conquistas_tipos;
create trigger fazenda_cache_conquistas after insert or update or delete or truncate on public.fazenda_conquistas_tipos
  for each statement execute function public.fazenda_cache_gatilho();
drop trigger if exists fazenda_cache_animais on public.fazenda_animais_tipos;
create trigger fazenda_cache_animais after insert or update or delete or truncate on public.fazenda_animais_tipos
  for each statement execute function public.fazenda_cache_gatilho();
drop trigger if exists fazenda_cache_ajudantes on public.fazenda_ajudantes_tipos;
create trigger fazenda_cache_ajudantes after insert or update or delete or truncate on public.fazenda_ajudantes_tipos
  for each statement execute function public.fazenda_cache_gatilho();

-- as mesmas checagens do fazenda_auth, sem a trava de uma chamada por vez: para o que só lê (o chat, o
-- evento, o status da compra, a lista da feira), que não precisa esperar atrás de um carregar lento
create or replace function public.fazenda_auth_ler(p_token text)
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
  select jogador_id into v_id from fazenda_sessoes where token_hash = encode(digest(p_token, 'sha256'), 'hex');
  if v_id is null then
    raise exception 'token_invalido';
  end if;
  if exists (select 1 from fazenda_jogadores where id = v_id and banido_em is not null) then
    raise exception 'conta_banida';
  end if;
  perform fazenda_semana_tentar_fechar();
  return v_id;
end;
$$;

-- A semana do evento virou (sexta 22h)? Fecha sem fila: só uma chamada tenta (a vez fica com ela até
-- acabar) e as outras seguem com a semana de antes. Antes, todas esperavam na mesma trava e, se o
-- fechamento passasse dos 3 s, todas falhavam. Com o relógio do banco (pg_cron) ligado, quem fecha é ele
-- (às 22h01 e conferindo de 10 em 10 min); as chamadas só tentam se ele atrasar mais de 15 min.
create or replace function public.fazenda_semana_tentar_fechar()
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if exists (select 1 from fazenda_semanas where inicio = fazenda_semana_inicio(now())) then return; end if;
  -- (session_user: quem abriu a conexão; nas chamadas do jogo é o authenticator, no pg_cron é o postgres)
  if session_user <> 'postgres' and exists (select 1 from pg_extension where extname = 'pg_cron')
     and now() < fazenda_semana_inicio(now()) + interval '15 minutes' then
    return;   -- o relógio do banco fecha (sem o limite de 3 s das chamadas)
  end if;
  if pg_try_advisory_xact_lock(hashtext('fazenda_semana')) then
    perform fazenda_semana_fechar();
  end if;
end;
$$;

-- o relógio do banco: fecha a semana na sexta às 22h01 (sábado 01:01 UTC) e confere de 10 em 10 min.
-- Sem o pg_cron, só avisa (as chamadas continuam fechando, sem fila).
do $$
begin
  begin
    create extension if not exists pg_cron with schema pg_catalog;
  exception when others then
    raise notice 'Fase 71: o pg_cron não ligou aqui (%). No Supabase: Database > Extensions > pg_cron, ligue e rode este arquivo de novo.', sqlerrm;
    return;
  end;
  perform cron.unschedule(jobid) from cron.job where jobname in ('fazenda_semana', 'fazenda_semana_conferir');
  perform cron.schedule('fazenda_semana', '1 1 * * 6', 'select public.fazenda_semana_fechar()');
  perform cron.schedule('fazenda_semana_conferir', '*/10 * * * *', 'select public.fazenda_semana_tentar_fechar()');
  raise notice 'Fase 71: o relógio do banco fecha a semana do evento na sexta às 22h01.';
end $$;

-- monta o cache agora (e cada faseN.sql daqui para a frente refaz no fim)
select public.fazenda_cache_montar();

-- ------------------------------------------------------------
-- Fase 72: os números (a revisão de 17/10 e o "do nível 20 em diante está sobrando dinheiro").
-- • Preços: o que libera do nível 20 em diante custa 2,5x (construções, oficinas, pomar e os terrenos
--   6 e 7, em fazenda_zonas); melhorias (fazenda_melhorias_tipos) e evoluir ajudante, 2x. As sementes
--   ficam como estão.
-- • Desmanchar devolve a metade do que você pagou (fazenda_construcoes.pago), não a do preço de hoje:
--   com os preços novos, comprar barato antes e desmanchar depois dava lucro. O cercado que veio de
--   graça não devolve nada.
-- • Triturador: 40 mil, 15 ⚡ por receita e +50% (uma receita sim, outra não, sai 1 a mais), em vez do
--   dobro (fazenda_oficinas_andar).
-- • O que ajudante, robô e baú colhem (e os bichos que os ajudantes coletam) dá metade do XP.
-- • Alface em 5 min (era 2). Adega e vinícola em 2 h (eram 4), geleia em 60 min (85) e queijo em 90 (128).
-- • Missões: o XP é 1,5% do nível. Visitas: pelo menos 1% do nível em XP (o caminhoneiro, 2%), e o
--   adubo da mascate cobre 8 canteiros + 1 a cada 3 níveis. As moedas de missões e visitas não mudam.
-- • Diamantes (fazenda_loja_diamantes): salvar murchas, 1 a cada 25 plantas (era 1 para todas);
--   colher agora, 1 a cada 4 h que faltam (era 1 por planta); 1 diamante enche 150 ⚡ (eram 50); o
--   café dos ajudantes dura 4 h (eram 2).
-- • Conquistas dão diamantes (fazenda_conquistas_tipos.diamantes): nível 10, 15, 20, 25, 30, 35 e 40
--   dão o número do nível; o 45, 100; o Velho Chico, 20; o marlim, 50. Quem já tinha ganha agora, uma
--   vez só (fazenda_conquistas.diamantes_pagos).
-- ------------------------------------------------------------
-- o XP do que os ajudantes, robôs e baús colhem: soma na chamada (fazenda.xp_bot, que volta junto se a
-- tarefa for desfeita) e grava uma vez só no fim da rodada deles (uma gravação por colheita deixava a
-- volta de uma fazenda grande 2x mais lenta)
create or replace function public.fazenda_bot_xp(p_jogador uuid, p_xp int)
returns void
language plpgsql
set search_path = public
as $$
declare
  v text := current_setting('fazenda.xp_bot', true);
begin
  if coalesce(p_xp, 0) <= 0 then return; end if;
  if v is not null and v <> '' and split_part(v, '#', 1) <> p_jogador::text then
    perform fazenda_bot_xp_gravar();   -- (o de outra fazenda, que não deveria estar aí)
    v := null;
  end if;
  perform set_config('fazenda.xp_bot', p_jogador::text || '#'
                     || (coalesce(nullif(split_part(coalesce(v, ''), '#', 2), '')::bigint, 0) + p_xp), true);
end;
$$;

create or replace function public.fazenda_bot_xp_gravar()
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v text := current_setting('fazenda.xp_bot', true);
begin
  if v is null or v = '' then return; end if;
  perform set_config('fazenda.xp_bot', '', true);
  update fazenda_jogadores set xp = xp + split_part(v, '#', 2)::bigint where id = split_part(v, '#', 1)::uuid;
end;
$$;

alter table public.fazenda_construcoes add column if not exists pago int;
-- o que já estava construído vale pelo preço de antes desta fase (roda antes dos preços novos)
update public.fazenda_construcoes c set pago = i.custo
  from public.fazenda_itens i
 where i.id = c.tipo and c.pago is null;

update public.fazenda_itens i set custo = v.custo
  from (values
    ('engenho', 80000), ('fabrica_auto', 37500), ('torrefacao', 85000), ('robo_colheita', 45000),
    ('fiacao', 90000), ('aspersor', 30000), ('cafeteria', 100000), ('reator', 75000),
    ('alfaiataria', 112500), ('vitaminas', 50000), ('vinicola', 120000), ('mangueira', 7500),
    ('guacamolaria', 60000), ('abacateiro', 10000), ('chocolateria', 65000), ('pimentaria', 125000),
    ('cacaueiro', 12500), ('adega', 75000), ('jabuticabeira', 15000), ('estatua_chico', 75000),
    ('bombonaria', 150000), ('supercap', 22500),
    ('triturador', 40000)) v(id, custo)
 where i.id = v.id;
update public.fazenda_itens
   set descricao = 'As oficinas rendem 50% a mais: uma receita sim, outra não, sai 1 produto a mais. Gasta 15 ⚡ por receita.'
 where id = 'triturador';
update public.fazenda_itens i set produz_seg = v.seg
  from (values ('adega', 7200), ('vinicola', 7200), ('casa_geleia', 3600), ('queijaria', 5400)) v(id, seg)
 where i.id = v.id;
update public.fazenda_culturas set tempo_seg = 300 where id = 'alface';

alter table public.fazenda_conquistas_tipos add column if not exists diamantes int not null default 0;
update public.fazenda_conquistas_tipos t set diamantes = v.d
  from (values ('nivel_10', 10), ('nivel_15', 15), ('nivel_20', 20), ('nivel_25', 25), ('nivel_30', 30),
               ('nivel_35', 35), ('nivel_40', 40), ('nivel_45', 100), ('velho_chico', 20), ('marlim', 50)) v(id, d)
 where t.id = v.id;
-- quem já tinha a conquista ganha os diamantes dela agora, uma vez só (a coluna nasce vazia nas antigas;
-- as novas já nascem pagas, porque fazenda_checar_conquistas paga na hora)
alter table public.fazenda_conquistas add column if not exists diamantes_pagos boolean;
update public.fazenda_jogadores j set diamantes = j.diamantes + x.d
  from (select c.jogador_id, sum(t.diamantes)::int as d
          from public.fazenda_conquistas c join public.fazenda_conquistas_tipos t on t.id = c.conquista
         where c.diamantes_pagos is null and t.diamantes > 0
         group by c.jogador_id) x
 where j.id = x.jogador_id;
update public.fazenda_conquistas set diamantes_pagos = true where diamantes_pagos is null;
alter table public.fazenda_conquistas alter column diamantes_pagos set default true;

-- os catálogos prontos com os números novos (as melhorias são uma função: o gatilho não vê)
select public.fazenda_cache_montar();

-- ------------------------------------------------------------
-- Fase 73: o que liberar do nível 31 ao 45 (parte 1) e o baú da sorte.
-- • Pomar: coqueiro (31), cajueiro (34), açaizeiro (37), cupuaçuzeiro (40) e castanheira (43), cada um
--   com a sua oficina no nível seguinte (o produto vale ~1,7x os ingredientes, como nas fases 38 e 58).
-- • Sementes de estação do 31 em diante: maracujá (verão, 33), mexerica (inverno, 36), caqui (outono, 39)
--   e lichia (primavera, 42); fora da estação, só na estufa, como as outras.
-- • Praia (categoria nova): guarda-sol, cadeira, castelo de areia, barraca de coco e coqueiro, só na
--   areia do Litoral (y 32 a 36; fazenda_construir e fazenda_mover). Só enfeitam (beleza).
-- • Baú da sorte (fazenda_abrir_bau_sorte): comprado com moedas, sem limite, para gastar o que sobra.
--   Madeira 50 mil, prata 250 mil, ouro 1 milhão; vem de tudo, mas o que é bom vem pouco: na média
--   volta menos da metade. O que vem não conta no evento (moedas) nem dá XP na venda (da_feira).
-- ------------------------------------------------------------
alter table public.fazenda_itens drop constraint if exists fazenda_itens_categoria_check;
alter table public.fazenda_itens add constraint fazenda_itens_categoria_check
  check (categoria in ('caminho', 'natureza', 'objeto', 'construcao', 'maquina', 'oficina', 'energia', 'bichos', 'pomar', 'praia'));

insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('coco',          'Coco',               '🥥', 1, 0,   70, 1,   9, 31, 57, 'produto'),
  ('caju',          'Caju',               '🍊', 1, 0,   80, 1,  10, 34, 58, 'produto'),
  ('acai',          'Açaí',               '🫐', 1, 0,   90, 1,  11, 37, 59, 'produto'),
  ('cupuacu',       'Cupuaçu',            '🍊', 1, 0,  220, 1,  26, 40, 105, 'produto'),
  ('castanha',      'Castanha-do-pará',   '🌰', 1, 0,  260, 1,  30, 43, 106, 'produto'),
  ('cocada',        'Cocada',             '🍬', 1, 0,  700, 1,  70, 32, 107, 'produto'),
  ('cajuina',       'Cajuína',            '🧃', 1, 0,  545, 1,  54, 35, 108, 'produto'),
  ('acai_tigela',   'Açaí na tigela',     '🍧', 1, 0,  580, 1,  58, 38, 109, 'produto'),
  ('creme_cupuacu', 'Creme de cupuaçu',   '🍮', 1, 0, 1215, 1, 120, 41, 110, 'produto'),
  ('pacoca',        'Paçoca',             '🍪', 1, 0, 1675, 1, 165, 44, 111, 'produto')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, venda = excluded.venda, xp = excluded.xp,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;
insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo, estacao) values
  ('maracuja', 'Maracujá', '🍈', 21600, 200, 45,  9,  60, 33, 19, 'cultura', 'verao'),
  ('mexerica', 'Mexerica', '🍊', 28800, 260, 55, 10,  80, 36, 20, 'cultura', 'inverno'),
  ('caqui',    'Caqui',    '🍅', 36000, 320, 70,  9, 100, 39, 21, 'cultura', 'outono'),
  ('lichia',   'Lichia',   '🍒', 43200, 400, 85,  9, 120, 42, 22, 'cultura', 'primavera')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, tempo_seg = excluded.tempo_seg, custo = excluded.custo, venda = excluded.venda,
  rendimento = excluded.rendimento, xp = excluded.xp, nivel_min = excluded.nivel_min, ordem = excluded.ordem,
  tipo = excluded.tipo, estacao = excluded.estacao;

insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, beleza, produz, produz_seg, produz_qtd, por_terreno, grupo, descricao) values
  ('coqueiro',     'Coqueiro',     'pomar', 20000, 31, 117, 3, 'coco',     32400,  6, 1, null, 'Dá 6 cocos a cada 9 horas: toque nele para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).'),
  ('cajueiro',     'Cajueiro',     'pomar', 25000, 34, 118, 3, 'caju',     36000,  8, 1, null, 'Dá 8 cajus a cada 10 horas: toque nele para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).'),
  ('acaizeiro',    'Açaizeiro',    'pomar', 30000, 37, 119, 3, 'acai',     39600, 10, 1, null, 'Dá 10 açaís a cada 11 horas: toque nele para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).'),
  ('cupuacuzeiro', 'Cupuaçuzeiro', 'pomar', 40000, 40, 120, 3, 'cupuacu',  43200,  5, 1, null, 'Dá 5 cupuaçus a cada 12 horas: toque nele para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).'),
  ('castanheira',  'Castanheira',  'pomar', 50000, 43, 121, 3, 'castanha', 50400,  6, 1, null, 'Dá 6 castanhas a cada 14 horas: toque nela para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min, ordem = excluded.ordem,
  beleza = excluded.beleza, produz = excluded.produz, produz_seg = excluded.produz_seg, produz_qtd = excluded.produz_qtd,
  por_terreno = excluded.por_terreno, grupo = excluded.grupo, descricao = excluded.descricao;
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, largura, altura,
                                  produz, produz_seg, produz_qtd, entradas, limite, beleza, descricao) values
  ('doceria_coco',     'Doceria de coco',    'oficina', 120000, 32, 99, 2, 3, 'cocada',        5400, 1, '{"coco": 3, "acucar": 1}', 2, 5, '3 cocos + 1 açúcar → cocada.'),
  ('cajuinaria',       'Cajuína',            'oficina', 150000, 35, 99, 2, 3, 'cajuina',       7200, 1, '{"caju": 4}', 2, 5, '4 cajus → cajuína.'),
  ('acaiteria',        'Açaiteria',          'oficina', 180000, 38, 99, 2, 3, 'acai_tigela',   5400, 1, '{"acai": 3, "leite": 1}', 2, 5, '3 açaís + 1 leite → açaí na tigela.'),
  ('cremeria',         'Creme de cupuaçu',   'oficina', 220000, 41, 99, 2, 3, 'creme_cupuacu', 7200, 1, '{"cupuacu": 2, "leite": 1, "acucar": 1}', 2, 5, '2 cupuaçus + 1 leite + 1 açúcar → creme de cupuaçu.'),
  ('pacocaria',        'Paçocaria',          'oficina', 250000, 44, 99, 2, 3, 'pacoca',        7200, 1, '{"castanha": 3, "acucar": 1}', 2, 5, '3 castanhas + 1 açúcar → paçoca.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, largura = excluded.largura, altura = excluded.altura, produz = excluded.produz,
  produz_seg = excluded.produz_seg, produz_qtd = excluded.produz_qtd, entradas = excluded.entradas,
  limite = excluded.limite, beleza = excluded.beleza, descricao = excluded.descricao;
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, beleza, descricao) values
  ('cadeira_praia', 'Cadeira de praia', 'praia',  6000, 31, 130, 2, 'Para ver o mar. Só na areia do Litoral.'),
  ('guarda_sol',    'Guarda-sol',       'praia',  8000, 31, 131, 3, 'Sombra na areia. Só na areia do Litoral.'),
  ('coqueiro_praia','Coqueiro da praia','praia', 12000, 31, 132, 4, 'Só enfeita: o coco é do coqueiro do pomar. Só na areia do Litoral.'),
  ('castelo_areia', 'Castelo de areia', 'praia', 15000, 31, 133, 4, 'Com bandeirinha e tudo. Só na areia do Litoral.'),
  ('barraca_coco',  'Barraca de coco',  'praia', 25000, 31, 134, 5, 'Água de coco gelada na beira do mar. Só na areia do Litoral.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, beleza = excluded.beleza, descricao = excluded.descricao;

-- os baús da sorte: preço, nível e as chances (raro, o prêmio grande, diamantes, itens; o resto é moeda)
create or replace function public.fazenda_baus_sorte()
returns jsonb language sql immutable as $$
  -- fase 74b: o baú nunca devolve moedas (sem o prêmio de moedas e o grande): só itens, diamantes e raro
  -- fase 79: pela metade do preço (os itens diminuem junto; a chance de diamante e de raro fica)
  select '{"madeira": {"nome": "Baú de madeira", "preco": 25000,   "nivel": 20, "raro": 0.004, "diamantes": [5, 10],  "chance_diamantes": 0.08},
           "prata":   {"nome": "Baú de prata",   "preco": 125000,  "nivel": 25, "raro": 0.015, "diamantes": [15, 30], "chance_diamantes": 0.08},
           "ouro":    {"nome": "Baú de ouro",    "preco": 500000,  "nivel": 30, "raro": 0.05,  "diamantes": [40, 80], "chance_diamantes": 0.08}}'::jsonb;
$$;

-- abre um baú da sorte: paga, sorteia e entrega. Os prêmios (fase 74b: nunca moedas):
--   raro (o mais caro, mais difícil: peso 1 / preço) · diamantes · e o resto, itens que o seu nível já tem
--   (de 15% a 75% do preço, pelo preço do celeiro)
create or replace function public.fazenda_abrir_bau_sorte(p_token text, p_tipo text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_b     jsonb := fazenda_baus_sorte() -> p_tipo;
  j       record;
  k       record;
  v_preco int;
  v_r     double precision := random();
  v_lim   double precision;
  v_moeda int := 0;
  v_diam  int := 0;
  v_item  text;
  v_qtd   int := 0;
  v_tipo  text;
begin
  if v_b is null then raise exception 'item_invalido'; end if;
  select * into j from fazenda_jogadores where id = v_id for update;
  if fazenda_nivel(j.xp) < (v_b->>'nivel')::int then raise exception 'nivel_insuficiente'; end if;
  v_preco := (v_b->>'preco')::int;
  if j.moedas < v_preco then raise exception 'moedas_insuficientes'; end if;

  -- as faixas do sorteio, uma depois da outra (raro, grande, diamantes, itens; o resto é moeda)
  v_lim := (v_b->>'raro')::float8;
  if v_r < v_lim then
    v_tipo := 'raro';
    select c.id into v_item from fazenda_culturas c
     where c.tipo = 'raro' and c.venda > 0
     order by -ln(greatest(random(), 1e-12)) * c.venda limit 1;   -- sorteio com peso 1 / preço
    v_qtd := 1;
  elsif v_r < v_lim + (v_b->>'chance_diamantes')::float8 then
    v_tipo := 'diamantes';
    v_diam := (v_b->'diamantes'->>0)::int + floor(random() * ((v_b->'diamantes'->>1)::int - (v_b->'diamantes'->>0)::int + 1))::int;
  else
    v_tipo := 'itens';
    select c.* into k from fazenda_culturas c
     where c.tipo in ('cultura', 'produto') and c.venda > 0 and c.nivel_min <= fazenda_nivel(j.xp)
     order by random() limit 1;
    v_item := k.id;
    v_qtd := greatest(1, round(v_preco * (0.15 + random() * 0.6) / k.venda))::int;
  end if;

  -- o que veio do baú não conta como moeda ganha no evento (o gatilho soma o que entra)
  update fazenda_jogadores
     set moedas = moedas - v_preco + v_moeda, diamantes = diamantes + v_diam,
         moedas_ganhas = moedas_ganhas - greatest(v_moeda - v_preco, 0)
   where id = v_id;
  if v_item is not null then   -- e vendido no celeiro dá as moedas, mas não o XP (como o da feira)
    insert into fazenda_celeiro (jogador_id, item, quantidade, da_feira) values (v_id, v_item, v_qtd, v_qtd)
    on conflict (jogador_id, item) do update
      set quantidade = fazenda_celeiro.quantidade + excluded.quantidade, da_feira = fazenda_celeiro.da_feira + excluded.da_feira;
  end if;
  insert into fazenda_baus_abertos (jogador_id, tipo, preco, premio, item, qtd, moedas, diamantes)
  values (v_id, p_tipo, v_preco, v_tipo, v_item, v_qtd, v_moeda, v_diam);
  return jsonb_build_object('premio', jsonb_build_object('tipo', v_tipo, 'item', v_item, 'qtd', v_qtd, 'moedas', v_moeda, 'diamantes', v_diam),
                            'preco', v_preco, 'estado', fazenda_estado(v_id));
end;
$$;

-- o que saiu de cada baú (para conferir as chances depois)
create table if not exists public.fazenda_baus_abertos (
  id         bigserial primary key,
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  tipo       text not null,
  preco      int  not null,
  premio     text not null,
  item       text,
  qtd        int  not null default 0,
  moedas     int  not null default 0,
  diamantes  int  not null default 0,
  em         timestamptz not null default now()
);
create index if not exists fazenda_baus_abertos_jogador on public.fazenda_baus_abertos (jogador_id, em);
alter table public.fazenda_baus_abertos enable row level security;
revoke all on public.fazenda_baus_abertos from anon, authenticated;
revoke all on sequence public.fazenda_baus_abertos_id_seq from anon, authenticated;

select public.fazenda_cache_montar();

-- ------------------------------------------------------------
-- Fase 73b: mover sem travar. fazenda_mover(..., p_leve) devolve só {ok, x, y}: o jogo já põe o item
-- no lugar na hora, e a fazenda inteira de volta a cada movimento (com o jogo refazendo tudo) travava
-- quem movia várias oficinas seguidas. Sem p_leve, devolve como antes.
-- ------------------------------------------------------------
drop function if exists public.fazenda_mover(text, int, int, int, int);

-- ------------------------------------------------------------
-- Fase 74: o que liberar do nível 31 ao 45 (parte 2).
-- • Oficinas dos peixes do mar: enlatados (33: sardinha em lata), sushi (39: sashimi) e caldeirada (42).
-- • Cabra (33) e búfala (38), com cercado e cuidador (Dona Zefa e Seu Badu); a queijaria de búfala (40)
--   faz mussarela com o leite dela.
-- • Ajudantes nos níveis 4 e 5 (o 4 pede o nível 35 do jogador; o 5, o 42): 150 e 240 tarefas por hora,
--   o eletricista −60% e −67%, o cuidador −40% e −50%; evoluir custa 16x e 32x o preço de contratar.
-- • Melhorias: adubo nível 4 (36), pomar fértil 3 (39) e mais pés 3 (41).
-- ------------------------------------------------------------
alter table public.fazenda_ajudantes drop constraint if exists fazenda_ajudantes_nivel_check;
alter table public.fazenda_ajudantes add constraint fazenda_ajudantes_nivel_check check (nivel between 1 and 5);

insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('leite_cabra',   'Leite de cabra',     '🥛', 1, 0,   120, 1,  14, 33, 112, 'produto'),
  ('leite_bufala',  'Leite de búfala',    '🥛', 1, 0,   220, 1,  22, 38, 113, 'produto'),
  ('mussarela',     'Mussarela de búfala','🧀', 1, 0,   750, 1,  75, 40, 114, 'produto'),
  ('sardinha_lata', 'Sardinha em lata',   '🥫', 1, 0,  2950, 1, 290, 33, 115, 'produto'),
  ('sashimi',       'Sashimi',            '🍣', 1, 0, 11000, 1, 900, 39, 116, 'produto'),
  ('caldeirada',    'Caldeirada',         '🍲', 1, 0,  6850, 1, 600, 42, 117, 'produto')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, venda = excluded.venda, xp = excluded.xp,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;
insert into public.fazenda_animais_tipos (id, nome, custo, nivel_min, maximo, produto, tempo_seg, racao, racao_qtd, ordem) values
  ('cabra',  'Cabra',  5000, 33, 5, 'leite_cabra',  14400, 'milho',   2, 7),
  ('bufala', 'Búfala', 8000, 38, 5, 'leite_bufala', 21600, 'abobora', 3, 8)
on conflict (id) do update set
  nome = excluded.nome, custo = excluded.custo, nivel_min = excluded.nivel_min, maximo = excluded.maximo,
  produto = excluded.produto, tempo_seg = excluded.tempo_seg, racao = excluded.racao,
  racao_qtd = excluded.racao_qtd, ordem = excluded.ordem;
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, largura, altura, efeito, limite, beleza, descricao) values
  ('cercado_cabra',  'Capril',             'bichos', 25000, 33, 106, 6, 4, 'cercado', 1, 4, 'Casa das cabras: precisa dela para comprar cabras, e elas moram aqui.'),
  ('cercado_bufala', 'Curral das búfalas', 'bichos', 35000, 38, 107, 7, 5, 'cercado', 1, 4, 'Curral com lama: precisa dele para comprar búfalas, e elas moram aqui.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, largura = excluded.largura, altura = excluded.altura, efeito = excluded.efeito,
  limite = excluded.limite, beleza = excluded.beleza, descricao = excluded.descricao;
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, largura, altura,
                                  produz, produz_seg, produz_qtd, entradas, limite, beleza, descricao) values
  ('enlatados',        'Enlatados',            'oficina', 150000, 33, 99, 2, 3, 'sardinha_lata', 5400, 1, '{"sardinha": 4, "oleo": 1}', 2, 5, '4 sardinhas + 1 óleo de girassol → sardinha em lata.'),
  ('queijaria_bufala', 'Queijaria de búfala',  'oficina', 200000, 40, 99, 2, 3, 'mussarela',     5400, 1, '{"leite_bufala": 2}', 2, 5, '2 leites de búfala → mussarela de búfala.'),
  ('sushiteria',       'Sushi',                'oficina', 200000, 39, 99, 2, 3, 'sashimi',       7200, 1, '{"atum": 1, "limao": 1}', 2, 5, '1 atum + 1 limão → sashimi.'),
  ('caldeiraria',      'Caldeirada',           'oficina', 250000, 42, 99, 2, 3, 'caldeirada',    7200, 1, '{"robalo": 1, "garoupa": 1, "tomate": 2}', 2, 5, '1 robalo + 1 garoupa + 2 tomates → caldeirada.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, largura = excluded.largura, altura = excluded.altura, produz = excluded.produz,
  produz_seg = excluded.produz_seg, produz_qtd = excluded.produz_qtd, entradas = excluded.entradas,
  limite = excluded.limite, beleza = excluded.beleza, descricao = excluded.descricao;
insert into public.fazenda_ajudantes_tipos (id, nome, papel, funcao, alvo, custo, nivel_min, descricao, ordem) values
  ('cabreira',  'Dona Zefa', 'Cabreira',  'animal', 'cabra',  30000, 33, 'Dá a ração e tira o leite das cabras. Cada nível deixa os bichos dela mais rápidos: −10% por nível no tempo (soma com o feno).', 13),
  ('bufaleiro', 'Seu Badu',  'Bufaleiro', 'animal', 'bufala', 40000, 38, 'Dá a ração e tira o leite das búfalas. Cada nível deixa os bichos dele mais rápidos: −10% por nível no tempo (soma com o feno).', 14)
on conflict (id) do update set
  nome = excluded.nome, papel = excluded.papel, funcao = excluded.funcao, alvo = excluded.alvo,
  custo = excluded.custo, nivel_min = excluded.nivel_min, descricao = excluded.descricao, ordem = excluded.ordem;
-- os textos dos ajudantes com os níveis 4 e 5
update public.fazenda_ajudantes_tipos
   set descricao = replace(descricao, '−10%, −20% e −30% no tempo', '−10% por nível no tempo, até −50% no 5')
 where descricao like '%−10\%, −20\% e −30\%%';
update public.fazenda_ajudantes_tipos
   set descricao = 'Cuida das máquinas: tudo o que gasta energia gasta menos. Nível 1: −20%; 2: −35%; 3: metade; 4: −60%; 5: −67%.'
 where id = 'eletricista';

select public.fazenda_cache_montar();

-- ------------------------------------------------------------
-- Fase 74b: vender produtos numa chamada só (fazenda_vender ganhou p_itens; a assinatura antiga sai).
-- ------------------------------------------------------------
drop function if exists public.fazenda_vender(text, text, int);

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
  select jsonb_build_object(   -- (fase 77: a mesma conta da taxa, com a tempestade e o furacão)
           'solar', round(avg(g.solar)::numeric, 1), 'eolica', round(avg(g.eolica)::numeric, 1),
           'reator', round(avg(g.reator)::numeric, 1), 'hidro', round(avg(fazenda_hidro_em(t))::numeric, 1), 'biomassa', 50)
    into v
    from generate_series(date_trunc('hour', now()), date_trunc('hour', now()) + interval '7 days', interval '12 minutes') t
   cross join lateral fazenda_gera_em(t) g;
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
           where c.jogador_id = p_jogador and i.efeito in ('solar', 'eolica', 'reator', 'biomassa', 'hidro')
           group by c.tipo, i.efeito) x;

  -- gasta: cada coisa trabalhando sem parar
  with cons as (
    select c.x, c.y, c.tipo, i.efeito, i.raio, i.produz_seg * (1 - fazenda_oficina_rapidez(p_jogador, c.tipo)) as produz_seg, i.entradas
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
    select 'alarme', 5 * count(*)::real from cons where tipo = 'alarme'   -- fase 81: 5 ⚡/h cada (era 1)
    union all
    select 'luzes', 1 + count(*)::real from cons where tipo in ('casa_vermelha', 'casa_azul', 'lampiao')   -- fase 81: de noite
  )
  select coalesce(jsonb_agg(jsonb_build_object('tipo', tipo, 'h', round((h * case when tipo in ('alarme', 'luzes') then 1 else v_desc end)::numeric)) order by h desc)
                    filter (where coalesce(h, 0) > 0), '[]'::jsonb),
         coalesce(sum(h * case when tipo in ('alarme', 'luzes') then 1 else v_desc end), 0)
    into v_gasta, v_c
    from itens;

  v := jsonb_build_object('gera', round(v_g), 'gasta', round(v_c), 'saldo', round(v_g - v_c),
                          'gera_itens', v_gera, 'gasta_itens', v_gasta, 'desconto', round((1 - v_desc)::numeric * 100));
  perform fazenda_cache_gravar('energia:' || p_jogador, v || jsonb_build_object('ass', v_ass));
  return v;
end;
$$;

select public.fazenda_cache_montar();

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

-- ------------------------------------------------------------
-- Fase 77: a tela do clima, a tempestade com raios e o furacão.
-- • Alguns pedaços de 36 min da chuva viram tempestade (1 em 4; no inverno, nevasca) e da ventania viram
--   furacão (1 em 6): fazenda_extremo_em, igual para todo mundo. A tempestade rega como a chuva; o furacão
--   espalha pragas como a ventania. Na tempestade o painel solar quase para (2 ⚡/h) e a turbina dá 20; no
--   furacão, a turbina dá 40 (fazenda_gera_em).
-- • Em cada um, do nível 5 em diante, cada painel solar e cada turbina tem 1 chance em 250 de levar um raio
--   (ou de ser derrubado pelo vento): sobrecarga, para de gerar até o conserto. No furacão, cada canteiro
--   plantado também tem 1 em 250 de ser arrancado (a estufa protege os canteiros em volta dela).
-- • Consertar: tocar no gerador e pagar 20% do preço dele (fazenda_consertar), ou ter o eletricista, que
--   conserta sozinho (nível 1: 1 h; 2: 40 min; 3: 25 min; 4: 15 min; 5: 10 min).
-- • fazenda_clima_info: a tela do clima (as próximas 24 h, as chances de cada clima por estação e as regras).
-- ------------------------------------------------------------
alter table public.fazenda_construcoes add column if not exists sobrecarga_em timestamptz;
alter table public.fazenda_jogadores add column if not exists tempestade_em timestamptz;   -- o último pedaço de 36 min já sorteado

create table if not exists public.fazenda_clima_eventos (
  id         bigint generated always as identity primary key,
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  evento     text not null check (evento in ('sobrecarga', 'arrancou', 'consertou')),
  clima      text,       -- tempestade ou furacao
  item       text,       -- o gerador ou a planta
  x          smallint,
  y          smallint,
  em         timestamptz not null default now(),
  visto      boolean not null default false
);
create index if not exists fazenda_clima_eventos_jogador on public.fazenda_clima_eventos (jogador_id, visto);
alter table public.fazenda_clima_eventos enable row level security;
revoke all on public.fazenda_clima_eventos from anon, authenticated;

-- Sorteia os pedaços de 36 min que passaram (no máximo os das últimas 48 h) e aplica o raio e o furacão.
-- Depois, o eletricista conserta o que já esperou o tempo dele.
create or replace function public.fazenda_tempestade(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_r     jsonb := fazenda_extremo_regras();
  v_cur   bigint := floor(extract(epoch from now()) / 2160);
  v_chance real := 1.0 / (fazenda_extremo_regras()->>'chance')::int;
  v_desde timestamptz;
  v_nivel int;
  v_t     timestamptz;
  v_e     text;
  v_min   int;
  v_ult   bigint;
  a       record;
begin
  select tempestade_em, fazenda_nivel(xp) into v_desde, v_nivel from fazenda_jogadores where id = p_jogador;
  if v_desde is null then   -- conta daqui para a frente (ninguém leva raio de antes da fase 77)
    update fazenda_jogadores set tempestade_em = to_timestamp(v_cur * 2160) where id = p_jogador;
    return;
  end if;
  v_ult := floor(extract(epoch from v_desde) / 2160);
  if v_ult < v_cur then
    update fazenda_jogadores set tempestade_em = to_timestamp(v_cur * 2160) where id = p_jogador;
    if v_nivel >= (v_r->>'nivel')::int then
      for s in greatest(v_ult + 1, v_cur - (v_r->>'fatias_max')::int + 1)..v_cur loop
        v_t := to_timestamp(s::bigint * 2160);
        v_e := fazenda_extremo_em(v_t + interval '1 minute');
        continue when v_e is null;
        perform fazenda_energia_atualizar(p_jogador);   -- até aqui, os geradores contam ligados
        -- o raio (ou o vento do furacão) num painel solar ou numa turbina: sobrecarga
        for a in update fazenda_construcoes c
                    set sobrecarga_em = least(now(), v_t + make_interval(secs => floor(random() * 2160)::int))
                   from fazenda_itens i
                  where i.id = c.tipo and c.jogador_id = p_jogador and i.efeito in ('solar', 'eolica')
                    and c.sobrecarga_em is null and random() < v_chance
                 returning c.tipo, c.x, c.y, c.sobrecarga_em loop
          insert into fazenda_clima_eventos (jogador_id, evento, clima, item, x, y, em)
          values (p_jogador, 'sobrecarga', v_e, a.tipo, a.x, a.y, a.sobrecarga_em);
        end loop;
        if v_e = 'furacao' then   -- o furacão arranca a plantação (a estufa protege em volta dela)
          with alvo as (
            select cc.posicao, cc.cultura, cc.x, cc.y from fazenda_canteiros cc
             where cc.jogador_id = p_jogador and cc.estado = 'plantado' and cc.plantado_em < v_t + interval '36 minutes'
               and random() < v_chance and not fazenda_protegido(p_jogador, 'estufa', cc.x, cc.y)
               for update),
          feito as (
            update fazenda_canteiros cc
               set estado = 'arado', cultura = null, plantado_em = null,
                   erva = false, praga = false, seco = false, roubado = 0, prox_evento = null, adubado = false
              from alvo where cc.jogador_id = p_jogador and cc.posicao = alvo.posicao)
          insert into fazenda_clima_eventos (jogador_id, evento, clima, item, x, y, em)
          select p_jogador, 'arrancou', 'furacao', alvo.cultura, alvo.x, alvo.y, least(now(), v_t + interval '18 minutes') from alvo;
        end if;
      end loop;
    end if;
    delete from fazenda_clima_eventos where jogador_id = p_jogador and em < now() - interval '7 days';
  end if;
  -- o eletricista conserta sozinho
  if exists (select 1 from fazenda_construcoes where jogador_id = p_jogador and sobrecarga_em is not null) then
    select (v_r->'eletricista_min'->>(least(h.nivel, 5) - 1))::int into v_min
      from fazenda_ajudantes h where h.jogador_id = p_jogador and h.tipo = 'eletricista';
    if v_min is not null and exists (select 1 from fazenda_construcoes where jogador_id = p_jogador
                                        and sobrecarga_em <= now() - make_interval(mins => v_min)) then
      perform fazenda_energia_atualizar(p_jogador);   -- até aqui, eles estavam parados
      for a in update fazenda_construcoes set sobrecarga_em = null
                where jogador_id = p_jogador and sobrecarga_em <= now() - make_interval(mins => v_min)
               returning tipo, x, y loop
        insert into fazenda_clima_eventos (jogador_id, evento, item, x, y) values (p_jogador, 'consertou', a.tipo, a.x, a.y);
      end loop;
    end if;
  end if;
end;
$$;

-- Conserta um gerador em sobrecarga: 20% do preço dele
create or replace function public.fazenda_consertar(p_token text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_custo int;
begin
  select ceil(i.custo * (fazenda_extremo_regras()->>'conserto_pct')::int / 100.0)::int into v_custo
    from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y and c.sobrecarga_em is not null
     for update of c;
  if v_custo is null then raise exception 'sem_sobrecarga'; end if;
  if (select moedas from fazenda_jogadores where id = v_id for update) < v_custo then raise exception 'moedas_insuficientes'; end if;
  perform fazenda_energia_atualizar(v_id);   -- até agora, ele estava parado
  update fazenda_jogadores set moedas = moedas - v_custo where id = v_id;
  update fazenda_construcoes set sobrecarga_em = null where jogador_id = v_id and x = p_x and y = p_y;
  return jsonb_build_object('pagou', v_custo, 'estado', fazenda_estado(v_id));
end;
$$;

-- A tela do clima: as próximas 24 h (de 36 em 36 min, juntando os pedaços iguais), as chances de cada
-- clima em cada estação e as regras da tempestade e do furacão. Igual para todo mundo: uma vez por minuto.
create or replace function public.fazenda_clima_info()
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  k       text := to_char(date_trunc('minute', now()), 'YYYY-MM-DD HH24:MI');
  v       jsonb;
  v_t     timestamptz := to_timestamp(floor(extract(epoch from now()) / 2160) * 2160);
  v_c     text;
  v_e     text;
  v_ant   text;
  v_lista jsonb := '[]'::jsonb;
  v_teste boolean := coalesce(current_setting('fazenda.clima_teste', true), '') <> ''
                     or coalesce(current_setting('fazenda.estacao_teste', true), '') <> ''
                     or coalesce(current_setting('fazenda.extremo_teste', true), '') <> '';
begin
  if not v_teste then
    select valor into v from fazenda_cache where chave = 'clima_info' and valor->>'minuto' = k;
    if v is not null then return v; end if;
  end if;
  for i in 0..40 loop
    v_c := fazenda_clima_em(v_t + interval '1 minute');
    v_e := fazenda_extremo_de(v_t + interval '1 minute', v_c);
    if v_ant is distinct from v_c || ':' || coalesce(v_e, '') then
      v_lista := v_lista || jsonb_build_array(jsonb_build_object('clima', v_c, 'extremo', v_e, 'de', v_t));
      v_ant := v_c || ':' || coalesce(v_e, '');
    end if;
    v_t := v_t + interval '36 minutes';
  end loop;
  v := jsonb_build_object('minuto', k, 'lista', v_lista, 'regras', fazenda_extremo_regras(),
         'tabela', (select jsonb_object_agg(e.est, (select jsonb_object_agg(t.clima, t.pct) from fazenda_clima_tabela(e.est) t))
                      from unnest(array['primavera', 'verao', 'outono', 'inverno']) e(est)));
  if not v_teste then perform fazenda_cache_gravar('clima_info', v); end if;
  return v;
end;
$$;

-- ------------------------------------------------------------
-- Fase 71c: sem timeout no pico. O jogo entra como anon, e o Supabase corta cada chamada do anon em 3 s.
-- Numa conexão nova o Postgres recompila as funções grandes (fazenda_estado e as que ele chama), e a
-- primeira chamada passava disso: 20 erros 500 (57014) numa noite. O jogo espera até 25 s
-- (RPC_ESPERA_MS); 15 s deixa a chamada lenta terminar e ainda corta uma travada de verdade.
-- ------------------------------------------------------------
alter role anon set statement_timeout = '15s';
alter role authenticated set statement_timeout = '15s';
notify pgrst, 'reload config';
notify pgrst, 'reload schema';

-- ------------------------------------------------------------
-- Fase 78: terrenos à direita, mais energia antes do 29, mais dinheiro do 29 para baixo e a conquista do
-- milhão.
-- • Terrenos 8, 9 e 10 na faixa x 48..63 (níveis 29, 33 e 38; 250 mil, 500 mil e 1 milhão), comprados à
--   parte dos de 1 a 7 (fazenda_jogadores.direita, de 0 a 3). As funções de terreno recebem
--   fazenda_terrenos(zonas, direita) = zonas + 10 x direita; o litoral vai até x 63.
-- • Energia: painel e turbina +1 por nível do 17 ao 29; gerador a biomassa 2 → 6 até o 28; a pequena
--   central hidrelétrica (nível 20, 120 ⚡/h sem parar, 80 no calor; 1, 2 e 3 nos níveis 20, 23 e 27).
-- • Venda: +50% do nível 29 para baixo (fazenda_bonus_venda), caindo 10 por nível do 30 ao 34.
-- • Feira: 50 compras por dia (eram 40).
-- • Conquista "Compra milionária": pagar 1 milhão de moedas de uma vez (um gatilho guarda a maior
--   queda das moedas numa mudança só, em fazenda_estatisticas.maior_compra).
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists direita smallint not null default 0;
alter table public.fazenda_jogadores drop constraint if exists fazenda_jogadores_direita_check;
alter table public.fazenda_jogadores add constraint fazenda_jogadores_direita_check check (direita between 0 and 3);

insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, efeito, raio, limite, descricao) values
  ('hidreletrica', 'Pequena central hidrelétrica', 'energia', 30000, 20, 84, 'hidro', 0, 1,
   'Uma rodinha d''água com o próprio tanque: vai em qualquer lugar da fazenda, sem precisar de rio nem de lago. 120 ⚡/h sem parar, de dia e de noite (80 na onda de calor, com menos água). Tempestade e furacão não estragam. Até 1, mais 1 no nível 23 e no 27.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min, ordem = excluded.ordem,
  efeito = excluded.efeito, raio = excluded.raio, limite = excluded.limite, descricao = excluded.descricao;
update public.fazenda_itens set descricao = 'Gera até 12 ⚡/h de dia (sol forte: 14; nublado: 5; chuva: 3). À noite, nada: no jogo, o dia e a noite se revezam a cada 2 horas. Até 8, mais 1 por nível do 17 ao 29 e 1 a cada 2 níveis depois.' where id = 'painel_solar';
update public.fazenda_itens set descricao = 'Gera 8 ⚡/h de dia e de noite; 30 ⚡/h na ventania e 14 na chuva. Na calmaria (sem vento, uns 25% do tempo fora da ventania e da chuva), cai para 3 ⚡/h: o painel de energia avisa quando vem. Até 6, mais 1 por nível do 18 ao 29 e 1 a cada 2 níveis depois.' where id = 'turbina';
update public.fazenda_itens set descricao = 'Ligado, queima 1 milho a cada 30 min: 50 ⚡/h. Toque nele para ligar ou desligar. Até 2, 3 no nível 21, 4 no 24 e 6 no 28.' where id = 'gerador_bio';

-- a conquista do milhão: a maior queda das moedas numa mudança só
alter table public.fazenda_estatisticas add column if not exists maior_compra bigint not null default 0;
create or replace function public.fazenda_moedas_pagou()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.moedas < old.moedas - 999999 then
    insert into fazenda_estatisticas (jogador_id, maior_compra) values (new.id, old.moedas - new.moedas)
    on conflict (jogador_id) do update set maior_compra = greatest(fazenda_estatisticas.maior_compra, excluded.maior_compra);
  end if;
  return new;
end;
$$;
drop trigger if exists fazenda_moedas_pagou on public.fazenda_jogadores;
create trigger fazenda_moedas_pagou after update of moedas on public.fazenda_jogadores
  for each row when (new.moedas < old.moedas - 999999) execute function public.fazenda_moedas_pagou();
insert into public.fazenda_conquistas_tipos (id, nome, descricao, medida, meta, recompensa, ordem) values
  ('milhao', 'Compra milionária', 'Pague 1 milhão de moedas numa compra só', 'maior_compra', 1000000, 50000, 60)
on conflict (id) do update set nome = excluded.nome, descricao = excluded.descricao, medida = excluded.medida,
  meta = excluded.meta, recompensa = excluded.recompensa;
update public.fazenda_conquistas_tipos set diamantes = 20 where id = 'milhao';

-- ------------------------------------------------------------
-- Fase 79: diamantes viram moedas e baús pela metade.
-- • fazenda_loja_diamantes ganha "moedas": 10 diamantes = 2.000 moedas x nível (fazenda_usar_diamantes,
--   p_item = 'moedas'); essa moeda não conta no evento.
-- • fazenda_baus_sorte: madeira 25 mil, prata 125 mil, ouro 500 mil.
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- Fase 80: os produtos das oficinas valem 3,2x a matéria-prima (eram ~1,7x).
-- Preço = 3,2 x o valor dos ingredientes, para cima de 5 em 5. Repete até parar de mudar, porque
-- 7 produtos também são ingrediente (açúcar, café torrado, chocolate, fio, molho, óleo e tecido):
-- cada etapa da cadeia dá 3,2x sobre o preço novo do que entra. Só sobe, nunca desce; as
-- matérias-primas, os bichos e os raros não mudam.
-- ------------------------------------------------------------
do $$
declare
  n int;
begin
  for k in 1..8 loop
    update public.fazenda_culturas p set venda = x.novo
      from (select i.produz, (ceil(3.2 * sum(c.venda * e.value::int) / i.produz_qtd / 5) * 5)::int as novo
              from public.fazenda_itens i
              cross join lateral jsonb_each_text(i.entradas) e
              join public.fazenda_culturas c on c.id = e.key
             where i.entradas is not null
             group by i.produz, i.produz_qtd) x
     where p.id = x.produz and p.venda < x.novo;
    get diagnostics n = row_count;
    exit when n = 0;
  end loop;
end $$;

-- ------------------------------------------------------------
-- Fase 81: o alarme gasta 5 ⚡ por hora (era 1) e, de noite, cada luz gasta 1 ⚡ por hora: a casa da
-- fazenda, as casinhas (vermelha e azul) e os lampiões (fazenda_luzes_noite em fazenda_energia_taxa,
-- e "luzes" na conta da energia). Só para quem tem energia elétrica: sem máquina de energia a conta
-- nem roda (fazenda_energia_atualizar). Bateria zerada, as luzes apagam no jogo.
-- ------------------------------------------------------------
update public.fazenda_itens set descricao = 'Vizinhos não pegam nada dos canteiros em volta (3 quadrados). Com energia elétrica na fazenda, gasta 5 ⚡ por hora e desliga se a bateria zerar.' where id = 'alarme';
update public.fazenda_itens set descricao = 'Acende sozinho de noite e ilumina em volta. +3 de beleza (beleza dá bônus nas vendas). Com energia elétrica na fazenda, gasta 1 ⚡ por hora de noite e apaga se a bateria zerar.' where id = 'lampiao';
update public.fazenda_itens set descricao = 'Casinha: +20 de beleza (beleza dá bônus nas vendas) e 1 cama para um ajudante descansar (2 h numa cama; sem cama livre, 4 h na sombra). Com energia elétrica na fazenda, a luz gasta 1 ⚡ por hora de noite.' where id = 'casa_vermelha';
update public.fazenda_itens set descricao = 'Casinha: +30 de beleza (beleza dá bônus nas vendas) e 2 camas para os ajudantes descansarem (2 h numa cama; sem cama livre, 4 h na sombra). Com energia elétrica na fazenda, a luz gasta 1 ⚡ por hora de noite.' where id = 'casa_azul';

-- ------------------------------------------------------------
-- Fase 82: oficina nível 2 e 3 e as melhorias de diamante.
-- • B10: cada tipo de oficina sobe para o nível 2 (100 mil) e o 3 (400 mil): a receita fica 15% e 30%
--   mais rápida (fazenda_oficina_nivel, fazenda_comprar categoria 'oficina').
-- • D8, na Loja → Melhorias, pagas com diamante (fazenda_melhorias_tipos, "diamante": true):
--   turno de 12 h dos ajudantes (150), cesto do Bira +50% (80), cesto do Seu Nonato +50% (80),
--   fila de 15 receitas nas oficinas (100) e a 5ª e a 6ª barraca da feira (100 e 150).
-- ------------------------------------------------------------

-- (a tabela também fica lá em cima, antes de fazenda_oficina_rapidez, para o fazenda.sql do zero)
create table if not exists public.fazenda_oficina_nivel (
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  tipo       text not null,
  nivel      smallint not null default 1 check (nivel between 1 and 3),
  primary key (jogador_id, tipo)
);
alter table public.fazenda_oficina_nivel enable row level security;
revoke all on public.fazenda_oficina_nivel from anon, authenticated;

-- ------------------------------------------------------------
-- Fase 83: ajudar os vizinhos sem limite e com sequência.
-- • Cada ajuda vale 0,30% do nível de quem ajuda (era 0,25%), sem o limite de 30 por dia.
-- • Sequência de vizinhos: +10% por vizinho diferente ajudado em até 10 min do anterior, até +100%
--   (fazenda_jogadores.seq_donos e seq_em; fazenda_premiar_ajuda passa a receber o dono).
-- • Ração: sai do celeiro de quem ajuda (era do dono), sem limite por dia.
-- • Coletar para o amigo: o produto pronto dos bichos vai para o celeiro do dono (fazenda_vizinho_coletar).
-- • A roça do vizinho (fazenda_roca_um): limpar murchas (2 por dia em cada fazenda), arar os vazios,
--   colher para o dono e, na fazenda abandonada (dono sumido há mais de 3 dias), plantar com o seu
--   dinheiro (5 ajudas). Na abandonada toda ajuda vale +50%. O dono vê o resumo quando volta.
-- • Alarme sem energia: o tempo com a bateria zerada fica em fazenda_jogadores.alarme_off_seg.
-- • O Perks aparece em 1 de cada 6 blocos de 3 h (era 30), e "Outro vizinho" leva primeiro às abandonadas.
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists seq_donos uuid[] not null default '{}';
alter table public.fazenda_jogadores add column if not exists seq_em timestamptz;
-- o tempo (somado, em segundos) com o alarme desligado por falta de energia: o jogo mostra o que mudou
alter table public.fazenda_jogadores add column if not exists alarme_off_seg bigint not null default 0;
alter table public.fazenda_jogadores add column if not exists alarme_off_em timestamptz;
alter table public.fazenda_visitas drop constraint if exists fazenda_visitas_tipo_check;
alter table public.fazenda_visitas add constraint fazenda_visitas_tipo_check check (tipo in ('roubo', 'ajuda', 'salvar', 'bicho', 'coleta', 'limpar', 'arar', 'colher', 'plantar'));
drop function if exists public.fazenda_premiar_ajuda(uuid, int);   -- (agora recebe o dono, para a sequência)
alter table public.fazenda_visitas alter column cultura drop not null;   -- (arar um canteiro vazio não tem planta)

-- ------------------------------------------------------------
-- Fase 84: a loja de raros (D9) e os vales do calendário (D10).
-- • Loja → Diamantes vende os materiais do píer e do barco a 1 💎 a cada 10 mil do preço, até 2 compras
--   por semana (fazenda_comprar_raro; a semana vira na segunda, em Brasília).
-- • O café e o XP em dobro do calendário viram vales guardados (fazenda_vales), ligados quando o jogador
--   quiser (fazenda_usar_vale); com ele já ligado, soma o tempo.
-- ------------------------------------------------------------
create table if not exists public.fazenda_vales (
  id         bigserial primary key,
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  tipo       text not null check (tipo in ('cafe', 'xp2')),
  minutos    int  not null,
  criado_em  timestamptz not null default now()
);
create index if not exists fazenda_vales_jogador on public.fazenda_vales (jogador_id);
alter table public.fazenda_vales enable row level security;
revoke all on public.fazenda_vales from anon, authenticated;
revoke all on sequence public.fazenda_vales_id_seq from anon, authenticated;

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
  public.fazenda_max_construcoes(int),
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
  public.fazenda_vender(text, text, int, text[]),
  public.fazenda_limite_roubo(int),
  public.fazenda_vizinho(uuid, uuid),
  public.fazenda_pegar_um(uuid, uuid, int, boolean),
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
  public.fazenda_mover(text, int, int, int, int, boolean),
  public.fazenda_demolir(text, int, int),
  public.fazenda_coletar(text, int, int),
  public.fazenda_reservar(text, text, int),
  public.fazenda_contratar(text, text),
  public.fazenda_oficina(text, int, int),
  public.fazenda_estoque_max(),
  public.fazenda_abastecer(uuid, jsonb, int),
  public.fazenda_oficinas_andar(uuid),
  public.fazenda_rede(uuid),
  public.fazenda_redes_de(jsonb, text, int, int),
  public.fazenda_rede_tem_celeiro(jsonb, int[]),
  public.fazenda_rede_puxar(uuid, int, int, jsonb, jsonb, timestamptz),
  public.fazenda_rede_entregar(uuid, int, int, text, int, jsonb, timestamptz),
  public.fazenda_rede_descarregar(uuid, jsonb),
  public.fazenda_viagem(uuid, text, int, int, int, int, int, boolean, timestamptz),
  public.fazenda_bau_livre(uuid, int, int),
  public.fazenda_bau_guardar(uuid, int, int, text, int, int, int),
  public.fazenda_cesto(uuid, int),
  public.fazenda_baus(uuid),
  public.fazenda_estoque(text, int, int, int),
  public.fazenda_galinheiro_quer(uuid),
  public.fazenda_pasto(uuid),
  public.fazenda_cuidador_adianta(uuid, text),
  public.fazenda_admin_id(text, boolean),
  public.fazenda_feira_limite(uuid),
  public.fazenda_feira_regras(),
  public.fazenda_feira_faixa(text),
  public.fazenda_feira_vencidos(uuid),
  public.fazenda_metas(uuid, int),
  public.fazenda_vento_calmo(timestamptz),
  public.fazenda_vento_previsao(timestamptz),
  public.fazenda_premio_ajuda(uuid),
  public.fazenda_premiar_ajuda(uuid, int, uuid),
  public.fazenda_sequencia_bonus(int),
  public.fazenda_abandonada(uuid),
  public.fazenda_raros_semana(uuid),
  public.fazenda_roca_um(uuid, uuid, int, text),
  public.fazenda_salvar_um(uuid, uuid, int),
  public.fazenda_alarme_ligado(uuid),
  public.fazenda_ajudantes_fechar(uuid, text),
  public.fazenda_galinheiro_linhas(uuid),
  public.fazenda_visitante(uuid),
  public.fazenda_atender(text, boolean, bigint),
  public.fazenda_avatar(text, jsonb),
  public.fazenda_avatar_precos(),
  public.fazenda_checar_conquistas(uuid),
  public.fazenda_pacotes_diamantes(),
  public.fazenda_compra_criar(text, text),
  public.fazenda_compra_pagamento(uuid, text, text, numeric),
  public.fazenda_compra_status(text, uuid),
  public.fazenda_google_ligar(text, text, text),
  public.fazenda_google_entrar(text),
  public.fazenda_google_desligar(text),
  public.fazenda_xp_nivel_v3(int),
  public.fazenda_xp_nivel_v4(int),
  public.fazenda_dia_em(timestamptz),
  public.fazenda_dia_fim(timestamptz),
  public.fazenda_energia_preco(uuid, real),
  public.fazenda_avatar_diamantes(),
  public.fazenda_loja_diamantes(),
  public.fazenda_diamantes_hoje(uuid, text),
  public.fazenda_xp_dobro(),
  public.fazenda_usar_diamantes(text, text, int, int),
  public.fazenda_codigo_recuperacao(),
  public.fazenda_admin_novo_codigo(text, uuid),
  public.fazenda_celeiro_da_feira(),
  public.fazenda_melhorias_tipos(),
  public.fazenda_melhoria(uuid, text),
  public.fazenda_limite_maquina(text, int, int),
  public.fazenda_colhido_agora(uuid, text),
  public.fazenda_completa(uuid),
  public.fazenda_conta(jsonb, text, int),
  public.fazenda_ajudante_registrar(uuid, text, jsonb),
  public.fazenda_camas(uuid),
  public.fazenda_camas_ocupadas(uuid),
  public.fazenda_raros(),
  public.fazenda_pier_receita(),
  public.fazenda_pier_falta(uuid, text),
  public.fazenda_mar_tabela(),
  public.fazenda_mar_regras(),
  public.fazenda_mar_peixes(int, int),
  public.fazenda_mar_sortear(int, int),
  public.fazenda_mar_item(uuid, text),
  public.fazenda_mar_contar(uuid, text),
  public.fazenda_mar_estado(uuid),
  public.fazenda_moedas_ganhas(),
  public.fazenda_semana_inicio(timestamptz),
  public.fazenda_evento_regras(),
  public.fazenda_semana_placar(timestamptz, timestamptz, timestamptz),
  public.fazenda_semana_posicoes(timestamptz, timestamptz, timestamptz),
  public.fazenda_semana_fechar(),
  public.fazenda_trofeus(uuid),
  public.fazenda_mar_perola(uuid),
  public.fazenda_barco_cores(),
  public.fazenda_perks(),
  public.fazenda_murchas_registrar(uuid),
  public.fazenda_chat_regras(),
  public.fazenda_chat_norm(text),
  public.fazenda_chat_palavras(),
  public.fazenda_chat_palavrao(text),
  public.fazenda_chat_texto(text),
  public.fazenda_feira_criar(uuid, text, int, int, uuid, bigint),
  public.fazenda_radiacao_regras(),
  public.fazenda_radiacao_fechar(uuid, timestamptz),
  public.fazenda_reator(uuid),
  public.fazenda_calendario_regras(),
  public.fazenda_calendario_premios(),
  public.fazenda_avatar_exclusivos(),
  public.fazenda_calendario_dar(uuid, jsonb),
  public.fazenda_calendario_estado(uuid),
  public.fazenda_ip(),
  public.fazenda_anuncio(text),
  public.fazenda_bot_aplicar(uuid, text, int, text, boolean),
  public.fazenda_bot_animal(uuid, bigint, text, boolean),
  public.fazenda_bot_pode_plantar(uuid, text, int),
  public.fazenda_clima_agora(),
  public.fazenda_cache_valor(text),
  public.fazenda_cache_montar(),
  public.fazenda_cache_ler(text),
  public.fazenda_cache_itens(int),
  public.fazenda_cache_gatilho(),
  public.fazenda_cache_gravar(text, jsonb),
  public.fazenda_previsao_agora(),
  public.fazenda_auth_ler(text),
  public.fazenda_semana_tentar_fechar(),
  public.fazenda_bot_xp(uuid, int),
  public.fazenda_bot_xp_gravar(),
  public.fazenda_baus_sorte(),
  public.fazenda_energia_medias(),
  public.fazenda_energia_conta(uuid),
  public.fazenda_extremo_regras(),
  public.fazenda_extremo_de(timestamptz, text),
  public.fazenda_extremo_em(timestamptz),
  public.fazenda_gera_em(timestamptz),
  public.fazenda_tempestade(uuid),
  public.fazenda_terrenos(int, int),
  public.fazenda_hidro_em(timestamptz),
  public.fazenda_luzes_noite(uuid, timestamptz),
  public.fazenda_estoque_max_de(uuid),
  public.fazenda_cesto_max(uuid),
  public.fazenda_turno(uuid),
  public.fazenda_oficina_niveis(),
  public.fazenda_oficina_rapidez(uuid, text),
  public.fazenda_zona_minha(int, int),
  public.fazenda_moedas_pagou()
from public, anon, authenticated;

grant execute on function
  public.fazenda_criar(text, text),
  public.fazenda_recuperar(text),
  public.fazenda_carregar(text),
  public.fazenda_acao(text, text, int[], text),
  public.fazenda_vender(text, text, int, text[]),
  public.fazenda_ranking(text),
  public.fazenda_visitar(text, uuid),
  public.fazenda_acao_vizinho(text, uuid, text, int[]),
  public.fazenda_comprar(text, text, text),
  public.fazenda_animal(text, text, bigint[]),
  public.fazenda_resgatar_missao(text, int),
  public.fazenda_construir(text, text, int, int),
  public.fazenda_mover(text, int, int, int, int, boolean),
  public.fazenda_demolir(text, int, int),
  public.fazenda_coletar(text, int, int),
  public.fazenda_reservar(text, text, int),
  public.fazenda_contratar(text, text),
  public.fazenda_oficina(text, int, int),
  public.fazenda_estoque(text, int, int, int),
  public.fazenda_atender(text, boolean, bigint),
  public.fazenda_avatar(text, jsonb),
  public.fazenda_gerador(text, int, int),
  public.fazenda_convite_info(text),
  public.fazenda_pescar(text),
  public.fazenda_compra_status(text, uuid),
  public.fazenda_google_desligar(text),
  public.fazenda_bau_esvaziar(text, int, int),
  public.fazenda_usar_diamantes(text, text, int, int),
  public.fazenda_vizinho_bicho(text, uuid, bigint[]),
  public.fazenda_vizinho_coletar(text, uuid, bigint[]),
  public.fazenda_comprar_raro(text, text),
  public.fazenda_usar_vale(text, bigint),
  public.fazenda_feira_anunciar(text, text, int, int),
  public.fazenda_feira_cancelar(text, bigint),
  public.fazenda_feira_comprar(text, bigint),
  public.fazenda_feira_lista(text, text),
  public.fazenda_feira_barraca(text),
  public.fazenda_admin_jogadores(text, text),
  public.fazenda_admin_banir(text, uuid, boolean, text),
  public.fazenda_admin_definir(text, uuid, boolean),
  public.fazenda_admin_novo_codigo(text, uuid),
  public.fazenda_ajudante_descansar(text, text),
  public.fazenda_construir_pier(text),
  public.fazenda_pier_comprar_peca(text, text),
  public.fazenda_mar_lancar(text),
  public.fazenda_mar_fisgar(text),
  public.fazenda_mar_recolher(text),
  public.fazenda_evento(text),
  public.fazenda_barco_pintar(text, jsonb),
  public.fazenda_chat(text, bigint),
  public.fazenda_chat_enviar(text, text, text, int, int),
  public.fazenda_chat_apagar(text, bigint),
  public.fazenda_chat_vender(text, bigint, int),
  public.fazenda_calendario_resgatar(text),
  public.fazenda_calendario_dourado(text),
  public.fazenda_abrir_bau_sorte(text, text),
  public.fazenda_consertar(text, int, int),
  public.fazenda_clima_info()
to anon, authenticated;
