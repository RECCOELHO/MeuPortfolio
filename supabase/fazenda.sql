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
alter table public.fazenda_jogadores add constraint fazenda_jogadores_zonas_check check (zonas between 0 and 6);   -- fase 24: 6 terrenos
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
  check (categoria in ('caminho', 'natureza', 'objeto', 'construcao', 'maquina', 'oficina', 'energia', 'bichos', 'pomar'));
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
  nivel          smallint not null default 1 check (nivel between 1 and 3),
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
alter table public.fazenda_jogadores alter column curva set default 4;   -- 4 = fase 41 (mais puxada do 17 em diante)
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
    ('casa_vermelha', null,           0, 20, 'Casinha: +20 de beleza (beleza dá bônus nas vendas).', null, null, null),
    ('casa_azul',     null,           0, 30, 'Casinha: +30 de beleza (beleza dá bônus nas vendas).', null, null, null)
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

-- XP onde começa o nível n. Até o 10 é uma tabela que começa bem fácil (o nível 2 vem na
-- primeira colheita de alface) e chega nos mesmos 2025 de antes: 10, 35, 85, 175, 315, 525,
-- 825, 1325, 2025 (fase 31; antes era 25·(n-1)², e ninguém desce de nível com a troca). Do 10
-- em diante cada nível pede 22% a mais que o anterior, começando em 700 (10→11: 700,
-- 15→16: 1.892, 20→21: 5.113, 24→25: 11.327). Os números da barra vêm daqui (estado: xp_nivel/xp_proximo).
create or replace function public.fazenda_xp_nivel(p_nivel int)
returns bigint language sql immutable as $$
  select case when p_nivel <= 10 then (array[0, 10, 35, 85, 175, 315, 525, 825, 1325, 2025])[greatest(p_nivel, 1)]
              when p_nivel <= 16 then 2025 + round(700 * (power(1.22::float8, p_nivel - 10) - 1) / 0.22)::bigint
              -- fase 41: do 16 em diante cada nível pede 35% a mais que o anterior
              -- (16→17: 2.554, 18→19: 4.656, 20→21: 8.485, 24→25: 28.184, 29→30: 126.378)
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
                 else fazenda_xp_nivel(x.n) + floor(least(greatest((j.xp - fazenda_xp_nivel_v3(x.n))::numeric
                        / nullif(fazenda_xp_nivel_v3(x.n + 1) - fazenda_xp_nivel_v3(x.n), 0), 0), 0.999)
                        * (fazenda_xp_nivel(x.n + 1) - fazenda_xp_nivel(x.n)))::int end,
       curva = 4
  from (select id, (select max(g) from generate_series(1, 60) g where fazenda_xp_nivel_v3(g) <= xp) as n
          from public.fazenda_jogadores where curva = 3) x
 where j.id = x.id;

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
           {"n":6,"nome":"Sertão do sudeste","x":32,"y":20,"w":16,"h":12,"custo":35000,"nivel":20,"canteiros":10}]'::jsonb;
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

-- Quantos canteiros o jogador pode ter: +2 por nível até o 25 e o que cada terreno comprado dá
-- (6 nos três primeiros, 10 a 12 nos grandes; igual a limiteCanteirosNivel em fazenda.js)
-- Fase 40: quantas construções cabem na fazenda (cerca, caminho, cano, enfeite, máquina...):
-- 250 e mais 150 a cada terreno comprado (antes era 200 fixo, pouco para o mapa grande e os canos).
-- Igual a maxConstrucoes em fazenda.js.
create or replace function public.fazenda_max_construcoes(p_zonas int)
returns int language sql immutable as $$
  select 250 + 150 * greatest(coalesce(p_zonas, 0), 0);
$$;

create or replace function public.fazenda_limite_canteiros(p_nivel int, p_zonas int)
returns int language sql immutable as $$
  select least(6 + (p_nivel - 1) * 2, 54)
       + coalesce((select sum(coalesce((z->>'canteiros')::int, 6))::int from jsonb_array_elements(fazenda_zonas()) z
                    where (z->>'n')::int <= p_zonas), 0);
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

create or replace function public.fazenda_energia_taxa(p_jogador uuid, p_t timestamptz)
returns real language sql stable security definer set search_path = public as $$
  select coalesce(sum(case i.efeito
           when 'solar' then case when fazenda_dia_em(p_t)
                                  then case x.clima when 'sol' then 12 when 'calor' then 14 when 'vento' then 10 when 'nublado' then 5 else 3 end
                                  else 0 end
           when 'eolica' then case when fazenda_vento_calmo(p_t) then 3   -- fase 48: calmaria
                                   else case x.clima when 'vento' then 30 when 'chuva' then 14 when 'nublado' then 10 when 'sol' then 8 else 5 end end
           when 'reator' then case x.clima when 'calor' then 80 else 120 end
           else 0 end), 0)::real
         -- fase 47: cada alarme gasta 1 ⚡ por hora (a conta só roda para quem tem energia elétrica)
         - (select count(*) from fazenda_construcoes a where a.jogador_id = p_jogador and a.tipo = 'alarme')::real
    from fazenda_construcoes c
    join fazenda_itens i on i.id = c.tipo
    cross join (select fazenda_clima_em(p_t) as clima) x
   where c.jogador_id = p_jogador and i.efeito in ('solar', 'eolica', 'reator');
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
  with j as (select zonas from fazenda_jogadores where id = p_jogador),
       mx as (select fazenda_limite_canteiros(p_nivel, (select zonas from j)) as max,
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
             'feito', (select zonas from j) >= (z->>'n')::int)
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
  v_bonus := case when v_nivel < 30 and not exists (select 1 from jsonb_array_elements(v_metas) m where not (m->>'feito')::boolean)
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
      select jsonb_agg(jsonb_build_object('tipo', tipo, 'nivel', nivel, 'relatorio', relatorio))
        from fazenda_ajudantes where jogador_id = p_jogador), '[]'::jsonb),
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

  -- colher agora (fase 31): 1 diamante deixa pronto na hora o que está crescendo, sem os
  -- problemas, e já colhe. Maduro não precisa de diamante: só colhe.
  if p_acao = 'agora' then
    if p_bot then raise exception 'acao_invalida'; end if;
    if c.estado <> 'plantado' or now() >= v_murcho then raise exception 'nada_a_fazer'; end if;
    if now() < v_maduro then
      if j.diamantes < 1 then raise exception 'diamantes_insuficientes'; end if;
      update fazenda_jogadores set diamantes = diamantes - 1 where id = p_jogador;
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
    -- fase 57: e para quem tem a fazenda completa (do 20 em diante, com as metas do nível em dia)
    if not p_bot and (fazenda_nivel(j.xp) <= 5 or fazenda_completa(p_jogador)) then update fazenda_jogadores set xp = xp + 1 where id = p_jogador; end if;

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
      -- fase 57: fazenda completa: plantar também dá XP
      update fazenda_jogadores set semente = k.id, xp = xp + fazenda_completa(p_jogador)::int where id = p_jogador;
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
    -- XP cheio da planta, mas o mesmo canteiro dá XP no máximo 1 vez a cada 8 min (fase 41)
    v_xp_colheita := not p_bot and (c.xp_em is null or c.xp_em <= now() - interval '8 minutes');
    if v_xp_colheita then
      update fazenda_jogadores set xp = xp + k.xp + fazenda_protegido(p_jogador, 'xp', c.x, c.y)::int where id = p_jogador;
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
begin
  p_codigo := upper(regexp_replace(coalesce(p_codigo, ''), '\s', '', 'g'));
  select id into v_id from fazenda_jogadores
   where codigo_hash = encode(digest(p_codigo, 'sha256'), 'hex');
  if v_id is null then
    raise exception 'codigo_invalido';
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
    v_e := v_e + fazenda_energia_taxa(p_jogador, v_t) * extract(epoch from v_prox - v_t)::real / 3600;
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
  update fazenda_jogadores set energia = v_e, energia_em = now(), moedas = moedas + v_moedas where id = p_jogador;
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
  select (p_qtd * 0.8 * coalesce((select case h.nivel when 1 then 0.8 when 2 then 0.65 else 0.5 end
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
      update fazenda_bau_itens set quantidade = 0 where jogador_id = p_jogador and x = b.x and y = b.y and item = it.item;
      insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, it.item, it.quantidade)
      on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
      perform fazenda_viagem(p_jogador, it.item, it.quantidade, b.x, b.y, null, null, false, now());
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
    select c.x, c.y, c.iniciado_em, c.estoque, c.prontos, i.produz, i.produz_seg, i.produz_qtd, i.entradas
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
        if v_tri and fazenda_gastar_energia(p_jogador, 10) then v_qtd := v_qtd * 2; end if;   -- triturador
        v_fim := v_t + make_interval(secs => o.produz_seg);
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
  for v_volta in 1..fazenda_estoque_max() loop
    v_puxou := false;
    for o in
      select c.x, c.y, c.estoque, c.iniciado_em, i.entradas
        from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
       where c.jogador_id = p_jogador and i.entradas is not null
         and c.estoque + (c.iniciado_em is not null)::int < fazenda_estoque_max()
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
begin
  for b in select x, y from fazenda_construcoes where jogador_id = p_jogador and tipo = 'bau' loop
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
      begin
        v_qtd := fazenda_aplicar(p_jogador, 'colher', k.posicao, null, true);   -- cai no celeiro...
        perform fazenda_bau_guardar(p_jogador, b.x, b.y, k.cultura, v_qtd, k.x, k.y);   -- ...e passa para o baú
        v_livre := v_livre - v_qtd;
      exception when others then null; end;
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
  m     record;
  v_sem text;
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
      elsif cc.estado = 'arado' and v_sem is not null then
        begin   -- canteiro arado vazio: planta a última semente que você usou (2 ⚡)
          if fazenda_gastar_energia(p_jogador, 2) then
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
  v_nivel int;
  v_ok    boolean;
  v_cafe_de  timestamptz;
  v_cafe_ate timestamptz;
  v_seg   real;
begin
  select cafe_de, cafe_ate into v_cafe_de, v_cafe_ate from fazenda_jogadores where id = p_jogador;
  for a in
    select h.tipo, h.nivel, h.credito, h.atualizado_em, t.funcao, t.alvo
      from fazenda_ajudantes h join fazenda_ajudantes_tipos t on t.id = h.tipo
     where h.jogador_id = p_jogador
     order by (t.funcao = 'colher') desc, t.ordem   -- fase 48: quem colhe vem antes de quem ara as murchas
       for update of h
  loop
    -- o eletricista não faz tarefas: ele baixa o gasto de energia (fazenda_energia_preco)
    continue when a.funcao = 'energia';
    -- fase 43: com o café (diamantes) o tempo dentro dele vale em dobro
    v_seg := extract(epoch from now() - a.atualizado_em)::real
           + case when v_cafe_ate is null then 0
                  else greatest(extract(epoch from least(now(), v_cafe_ate) - greatest(a.atualizado_em, v_cafe_de))::real, 0) end;
    v_cred := least(a.credito + v_seg / 3600 * fazenda_ritmo(a.nivel), fazenda_ritmo(a.nivel) * 8);
    v_n := floor(v_cred);
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
        begin perform fazenda_aplicar(p_jogador, case when c.murcha then 'colher_tarde' else 'colher' end, c.posicao, null, true); v_feito := v_feito + 1;
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
          v_feito := v_feito + 1;
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
        v_feito := v_feito + 1;
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
            v_feito := v_feito + 1;
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
            v_feito := v_feito + 1; v_ok := true;
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

    -- fase 46: quem não fez nada não é regravado: o crédito continua saindo do tempo desde
    -- atualizado_em (até 8 h), igual; contratar/evoluir e o café fecham a conta antes (fazenda_ajudantes_fechar)
    if v_feito > 0 then
      update fazenda_ajudantes
         set credito = v_cred - v_feito, atualizado_em = now(), relatorio = relatorio + v_feito
       where jogador_id = p_jogador and tipo = a.tipo;
    end if;
  end loop;
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
  perform fazenda_trabalhar(v_id);
  perform fazenda_industria(v_id);
  perform fazenda_feira_vencidos(v_id);   -- fase 50: anúncio vencido volta para o celeiro
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
  perform fazenda_ajudantes_fechar(v_id, p_tipo);   -- (fase 46: quem não trabalhou também)
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
    -- fase 48: hoje o visitante ainda pode salvar até 2 plantas murchas e dar ração a até 10 bichos aqui
    'salvos_hoje', (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'salvar'
                     and criado_em > now() - interval '1 day'),
    'pode_salvar', (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'salvar'
                     and criado_em > now() - interval '1 day') < 2,
    'bichos_hoje', (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'bicho'
                     and criado_em > now() - interval '1 day'),
    'premio_ajuda', fazenda_premio_ajuda(p_ator),
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
      'estatisticas', (select to_jsonb(e) - 'jogador_id' || jsonb_build_object('energia', e.energia + floor(g.energia_gasta)::int)
                         from fazenda_estatisticas e join fazenda_jogadores g on g.id = e.jogador_id where e.jogador_id = p_dono),
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
  if fazenda_protegido(p_dono, 'alarme', c.x, c.y) and fazenda_alarme_ligado(p_dono) then
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
       where ator_id = p_ator and tipo = 'roubo' and criado_em > now() - interval '1 day') >= 40 then
    raise exception 'limite_pegadas';
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
  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd)
  values (p_ator, p_dono, 'roubo', p_posicao, c.plantado_em, k.id, v_qtd);
  perform fazenda_missao(p_ator, 'pegar', v_qtd);

  return v_qtd;
end;
$$;

-- Tira os problemas de um canteiro do vizinho. Retorna quantos problemas resolveu.
-- Fase 48: quanto XP vale cada ajuda a um vizinho: 0,25% do nível de quem ajuda (pelo menos 2)
create or replace function public.fazenda_premio_ajuda(p_ator uuid)
returns int language sql stable security definer set search_path = public as $$
  select greatest(2, round((fazenda_xp_nivel(n + 1) - fazenda_xp_nivel(n)) * 0.0025))::int
    from (select fazenda_nivel(xp) as n from fazenda_jogadores where id = p_ator) x;
$$;

-- Dá o prêmio de p_unidades ajudas (até 30 por dia, contando ajudar, salvar e bichos); devolve o XP
create or replace function public.fazenda_premiar_ajuda(p_ator uuid, p_unidades int)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_hoje int;
  v_n    int;
  v_xp   int;
begin
  select coalesce(sum(qtd), 0) into v_hoje from fazenda_visitas
   where ator_id = p_ator and tipo in ('ajuda', 'salvar', 'bicho') and criado_em > now() - interval '1 day';
  v_n := greatest(least(p_unidades, 30 - v_hoje), 0);
  if v_n = 0 then return 0; end if;
  v_xp := v_n * fazenda_premio_ajuda(p_ator);
  update fazenda_jogadores set xp = xp + v_xp, moedas = moedas + v_n where id = p_ator;
  return v_xp;
end;
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
  v_xp := fazenda_premiar_ajuda(p_ator, 3);
  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd)
  values (p_ator, p_dono, 'salvar', p_posicao, now() - make_interval(secs => k.tempo_seg), k.id, 3);
  perform fazenda_missao(p_ator, 'ajudar', 3);
  return v_xp;
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

  -- Recompensa só até 30 ajudas por dia (ajudar além disso é caridade); fase 48: o XP de cada uma
  -- cresce com o nível de quem ajuda (fazenda_premio_ajuda) e conta salvar planta e dar ração
  v_premio := fazenda_premiar_ajuda(p_ator, v_n);

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
begin
  if v_dono is null then
    select j.id into v_dono
      from fazenda_jogadores j
     where j.id <> v_id
       and j.visto_em > now() - interval '30 days'
       and j.banido_em is null
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
  if p_acao not in ('pegar', 'ajudar', 'salvar') then
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

-- Fase 48: o vizinho dá ração aos bichos com fome (a ração sai do celeiro do dono), até 10 por dia
-- em cada fazenda; cada um vale 1 ajuda
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
  v_hoje  int;
  v_racao text;
begin
  if p_vizinho is null or p_vizinho = v_id then raise exception 'propria_fazenda'; end if;
  if not exists (select 1 from fazenda_jogadores where id = p_vizinho and banido_em is null) then raise exception 'vizinho_invalido'; end if;
  if p_animais is null or array_length(p_animais, 1) is null or array_length(p_animais, 1) > 50 then raise exception 'nada_a_fazer'; end if;
  select count(*) into v_hoje from fazenda_visitas
   where ator_id = v_id and dono_id = p_vizinho and tipo = 'bicho' and criado_em > now() - interval '1 day';
  foreach v_a in array p_animais loop
    exit when v_hoje + v_feito >= 10;
    begin
      select t.racao into v_racao from fazenda_animais a join fazenda_animais_tipos t on t.id = a.tipo
       where a.id = v_a and a.jogador_id = p_vizinho;
      if not found then raise exception 'animal_invalido'; end if;
      perform fazenda_animal_um(p_vizinho, v_a, 'alimentar', true);
      v_xp := v_xp + fazenda_premiar_ajuda(v_id, 1);
      insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd)
      values (v_id, p_vizinho, 'bicho', 0, now(), v_racao, 1);
      v_feito := v_feito + 1;
    exception when others then
      if array_length(p_animais, 1) = 1 then raise; end if;
    end;
  end loop;
  if v_feito = 0 and v_hoje >= 10 then raise exception 'limite_bichos'; end if;
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
      when 'energia' then s.energia + floor((select energia_gasta from fazenda_jogadores where id = p_jogador))::int
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
    select (n->>'nivel')::int as nivel, (n->>'custo')::int as custo into a
      from jsonb_array_elements(fazenda_melhorias_tipos()) m,
           jsonb_array_elements(m->'niveis') with ordinality as x(n, i)
     where m->>'id' = p_tipo
       and x.i = 1 + coalesce((select nivel from fazenda_melhorias where jogador_id = v_id and id = p_tipo), 0);
    if not found then raise exception 'melhoria_max'; end if;
    if fazenda_nivel(j.xp) < a.nivel then raise exception 'nivel_insuficiente'; end if;
    if j.moedas < a.custo then raise exception 'moedas_insuficientes'; end if;
    update fazenda_jogadores set moedas = moedas - a.custo where id = v_id;
    insert into fazenda_melhorias (jogador_id, id, nivel) values (v_id, p_tipo, 1)
    on conflict (jogador_id, id) do update set nivel = fazenda_melhorias.nivel + 1;

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
  select p_x between 0 and 47 and p_y between 0 and 31
     and not (p_x between 1 and 3  and p_y between 1 and 6)     -- celeiro
     and not (p_x between 5 and 7  and p_y between 1 and 3)     -- casa
     and not (p_x between 24 and 29 and p_y between 14 and 18); -- lago
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
       >= fazenda_limite_canteiros(fazenda_nivel(j.xp), j.zonas) then
      raise exception 'limite_canteiros';
    end if;
    perform fazenda_checar_lugar(v_id, j.zonas, p_x, p_y, 1, 1);
    select min(g) into v_pos from generate_series(0, 299) g   -- fase 56: eram 0..99
     where not exists (select 1 from fazenda_canteiros where jogador_id = v_id and posicao = g);
    if v_pos is null then raise exception 'limite_canteiros'; end if;
    insert into fazenda_canteiros (jogador_id, posicao, estado, x, y) values (v_id, v_pos, 'vazio', p_x, p_y);
    return jsonb_build_object('estado', fazenda_estado(v_id), 'posicao', v_pos);
  end if;

  select * into i from fazenda_itens where id = p_tipo;
  if not found then raise exception 'item_invalido'; end if;
  if fazenda_nivel(j.xp) < i.nivel_min then raise exception 'nivel_insuficiente'; end if;
  perform fazenda_checar_lugar(v_id, j.zonas, p_x, p_y, i.largura, i.altura);
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
                  then i.por_terreno * (1 + j.zonas / 2) + fazenda_melhoria(v_id, 'pes')::int
                  else i.por_terreno * (1 + j.zonas) end) then
    raise exception 'limite_terreno';
  end if;
  if (select count(*) from fazenda_construcoes where jogador_id = v_id) >= fazenda_max_construcoes(j.zonas) then
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
  -- o que está guardado no baú e o que já chegou pelo cano na oficina vão junto (fase 39)
  update fazenda_bau_itens set x = p_nx, y = p_ny where jogador_id = v_id and x = p_x and y = p_y;
  update fazenda_oficina_itens set x = p_nx, y = p_ny where jogador_id = v_id and x = p_x and y = p_y;
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
          or fazenda_avatar_diamantes() ? coalesce(p_avatar->>'tipo', 'fazendeiro')) then
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
  v_n := least(floor(extract(epoch from now() - j.lago_em) / 1800)::int, 16, greatest(coalesce(p_max, 0), 0));
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
  update fazenda_jogadores set lago_em = greatest(j.lago_em, now() - interval '8 hours') + make_interval(secs => v_n * 1800)
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
  select coalesce(sum(quantidade), 0)::int into v_qtd from fazenda_bau_itens where jogador_id = v_id and x = p_x and y = p_y;
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  select v_id, item, quantidade from fazenda_bau_itens where jogador_id = v_id and x = p_x and y = p_y and quantidade > 0
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  delete from fazenda_bau_itens where jogador_id = v_id and x = p_x and y = p_y;
  return jsonb_build_object('qtd', v_qtd, 'estado', fazenda_estado(v_id));
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
         diamantes = diamantes + 1,   -- fase 31: cada anúncio também dá 1 diamante
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
  v_id uuid := fazenda_auth(p_token);
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
  select '{"xp2": {"preco": 15, "horas": 1},
           "xp": {"preco": 10, "pct": 10, "por_dia": 3},
           "cafe": {"preco": 10, "horas": 2},
           "energia": {"por": 50},
           "oficina": {"por_hora": 1},
           "murchas": {"preco": 1}}'::jsonb;
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
    if v_mult > 1 then new.xp := old.xp + round((new.xp - old.xp) * v_mult)::int; end if;
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
    if v_nivel >= 30 then raise exception 'xp_maximo'; end if;
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
           "barraca_precos": [800, 1600, 2400], "compras_dia": 40, "qtd_max": 99}'::jsonb;
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
  select array[greatest(1, floor(k.venda * (fazenda_feira_regras()->>'min')::numeric))::int,
               greatest(1, ceil(k.venda * (fazenda_feira_regras()->>'max')::numeric))::int]
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
  v_id    uuid := fazenda_auth(p_token);
  v_r     jsonb := fazenda_feira_regras();
  v_faixa int[] := fazenda_feira_faixa(p_item);
  v_livre int;
begin
  perform fazenda_feira_vencidos(v_id);
  if v_faixa is null then raise exception 'item_invalido'; end if;
  if p_qtd is null or p_qtd < 1 or p_qtd > (v_r->>'qtd_max')::int then raise exception 'quantidade_invalida'; end if;
  if p_preco is null or p_preco < v_faixa[1] or p_preco > v_faixa[2] then raise exception 'preco_invalido'; end if;
  if (select count(*) from fazenda_feira where vendedor_id = v_id and vendido_em is null) >= fazenda_feira_limite(v_id) then
    raise exception 'limite_anuncios';   -- (fase 51: compre mais barracas na feira)
  end if;
  -- a ração reservada para os bichos fica no celeiro
  select ce.quantidade - coalesce((select quantidade from fazenda_reservas where jogador_id = v_id and item = p_item), 0) into v_livre
    from fazenda_celeiro ce where ce.jogador_id = v_id and ce.item = p_item for update;
  if coalesce(v_livre, 0) < p_qtd then raise exception 'sem_itens'; end if;
  update fazenda_celeiro set quantidade = quantidade - p_qtd where jogador_id = v_id and item = p_item;
  insert into fazenda_feira (vendedor_id, item, qtd, preco) values (v_id, p_item, p_qtd, p_preco);
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
  if (select count(*) from fazenda_feira where comprador_id = v_id and vendido_em > now() - interval '1 day')
     >= (v_r->>'compras_dia')::int then
    raise exception 'limite_compras';
  end if;
  v_total := a.qtd * a.preco;
  v_taxa := ceil(v_total * (v_r->>'taxa')::int / 100.0)::int;
  if (select moedas from fazenda_jogadores where id = v_id for update) < v_total then raise exception 'moedas_insuficientes'; end if;
  update fazenda_jogadores set moedas = moedas - v_total where id = v_id;
  update fazenda_jogadores set moedas = moedas + v_total - v_taxa where id = a.vendedor_id;
  insert into fazenda_celeiro (jogador_id, item, quantidade, da_feira) values (v_id, a.item, a.qtd, a.qtd)   -- fase 56: da_feira
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade,
                                               da_feira = fazenda_celeiro.da_feira + excluded.da_feira;
  update fazenda_feira set comprador_id = v_id, vendido_em = now() where id = p_id;
  return jsonb_build_object('item', a.item, 'qtd', a.qtd, 'total', v_total,
                            'vendedor', (select apelido from fazenda_jogadores where id = a.vendedor_id),
                            'estado', fazenda_estado(v_id));
end;
$$;

-- as ofertas abertas dos outros (as mais baratas primeiro; com p_item, só daquele item) e as suas
create or replace function public.fazenda_feira_lista(p_token text, p_item text default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  v_r  jsonb := fazenda_feira_regras();
begin
  perform fazenda_feira_vencidos(v_id);
  return jsonb_build_object(
    'regras', v_r,
    'ofertas', coalesce((
      select jsonb_agg(o order by (o->>'preco')::int, (o->>'id')::bigint) from (
        select jsonb_build_object('id', f.id, 'item', f.item, 'qtd', f.qtd, 'preco', f.preco, 'vendedor', j.apelido,
                                  'avatar', j.avatar, 'ate', f.criado_em + make_interval(hours => (v_r->>'horas')::int)) as o
          from fazenda_feira f join fazenda_jogadores j on j.id = f.vendedor_id
         where f.vendido_em is null and f.vendedor_id <> v_id
           and f.criado_em >= now() - make_interval(hours => (v_r->>'horas')::int)
           and (p_item is null or f.item = p_item)
         order by f.preco, f.id
         limit 60) x), '[]'::jsonb),
    'itens', coalesce((
      select jsonb_agg(distinct f.item) from fazenda_feira f
       where f.vendido_em is null and f.vendedor_id <> v_id
         and f.criado_em >= now() - make_interval(hours => (v_r->>'horas')::int)), '[]'::jsonb),
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
create or replace function public.fazenda_melhorias_tipos()
returns jsonb language sql immutable as $$
  select '[{"id":"adubo","nome":"Adubo premium","descricao":"As plantas nascem adiantadas: crescem 10%, 20% e 30% mais rápido (soma com o girassol e a estufa).",
            "niveis":[{"nivel":23,"custo":50000,"valor":0.1},{"nivel":26,"custo":150000,"valor":0.2},{"nivel":29,"custo":300000,"valor":0.3}]},
           {"id":"pomar","nome":"Pomar fértil","descricao":"As árvores do pomar dão frutas 15% e 30% mais rápido.",
            "niveis":[{"nivel":24,"custo":80000,"valor":0.15},{"nivel":28,"custo":200000,"valor":0.3}]},
           {"id":"pes","nome":"Mais pés de fruta","descricao":"Mais 1 e mais 2 pés de cada fruta no pomar, além dos 4 que os terrenos dão.",
            "niveis":[{"nivel":25,"custo":60000,"valor":1},{"nivel":30,"custo":120000,"valor":2}]}]'::jsonb;
$$;

-- quanto a melhoria vale para o jogador agora (0 = não comprou)
create or replace function public.fazenda_melhoria(p_jogador uuid, p_id text)
returns real language sql stable security definer set search_path = public as $$
  select coalesce((select (m->'niveis'->(g.nivel - 1)->>'valor')::real
                     from fazenda_melhorias g, jsonb_array_elements(fazenda_melhorias_tipos()) m
                    where g.jogador_id = p_jogador and g.id = p_id and m->>'id' = p_id), 0)::real;
$$;

-- o limite de cada máquina no nível (null = sem limite)
create or replace function public.fazenda_limite_maquina(p_item text, p_limite int, p_nivel int)
returns int language sql immutable as $$
  select case p_item
           when 'painel_solar' then p_limite + greatest(0, (p_nivel - 16) / 2)
           when 'turbina'      then p_limite + greatest(0, (p_nivel - 17) / 2)
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
  public.fazenda_premiar_ajuda(uuid, int),
  public.fazenda_salvar_um(uuid, uuid, int),
  public.fazenda_alarme_ligado(uuid),
  public.fazenda_ajudantes_fechar(uuid, text),
  public.fazenda_galinheiro_linhas(uuid),
  public.fazenda_visitante(uuid),
  public.fazenda_atender(text, boolean),
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
  public.fazenda_completa(uuid)
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
  public.fazenda_avatar(text, jsonb),
  public.fazenda_gerador(text, int, int),
  public.fazenda_anuncio(text),
  public.fazenda_convite_info(text),
  public.fazenda_pescar(text),
  public.fazenda_compra_status(text, uuid),
  public.fazenda_google_desligar(text),
  public.fazenda_bau_esvaziar(text, int, int),
  public.fazenda_usar_diamantes(text, text, int, int),
  public.fazenda_vizinho_bicho(text, uuid, bigint[]),
  public.fazenda_feira_anunciar(text, text, int, int),
  public.fazenda_feira_cancelar(text, bigint),
  public.fazenda_feira_comprar(text, bigint),
  public.fazenda_feira_lista(text, text),
  public.fazenda_feira_barraca(text),
  public.fazenda_admin_jogadores(text, text),
  public.fazenda_admin_banir(text, uuid, boolean, text),
  public.fazenda_admin_definir(text, uuid, boolean),
  public.fazenda_admin_novo_codigo(text, uuid)
to anon, authenticated;
