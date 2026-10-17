-- ============================================================
-- FAZENDINHA — Fase 63 (etapa 6: o evento da semana), só o que mudou.
-- Para o banco que já está no ar (com a fase 62): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

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
  if new.moedas > old.moedas then new.moedas_ganhas := old.moedas_ganhas + (new.moedas - old.moedas); end if;
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
create or replace function public.fazenda_evento_regras()
returns jsonb language sql immutable as $$
  select '{"fecha": "sexta às 22h", "diamantes": [60, 35, 20], "convite_nivel": 5,
           "categorias": [
             {"id": "ranking",  "nome": "Ranking da semana",  "conta": "XP ganho na semana",            "itens": ["trofeu_ouro", "trofeu_prata", "trofeu_bronze"]},
             {"id": "niveis",   "nome": "Mais níveis",        "conta": "níveis subidos na semana",      "itens": ["ampulheta_dourada"]},
             {"id": "moedas",   "nome": "Mais moedas",        "conta": "moedas ganhas na semana",       "itens": ["cofrinho_ouro"]},
             {"id": "vendeu",   "nome": "Vendeu na barraca",  "conta": "moedas em vendas na feira",     "itens": ["balanca_ouro"]},
             {"id": "comprou",  "nome": "Comprou na barraca", "conta": "moedas em compras na feira",    "itens": ["sacola_ouro"]},
             {"id": "convites", "nome": "Mais convites",      "conta": "amigos convidados que chegaram ao nível 5", "itens": ["leme_dourado"]}]}'::jsonb;
$$;

-- os números de cada jogador numa semana (p_semana = o início dela; conta de p_desde a p_ate).
-- Quem entrou na semana não tem foto: conta do zero. Quem foi banido não entra.
create or replace function public.fazenda_semana_placar(p_semana timestamptz, p_desde timestamptz, p_ate timestamptz)
returns table (jogador_id uuid, apelido text, avatar jsonb, criado_em timestamptz, ranking bigint, niveis bigint,
               moedas bigint, vendeu bigint, comprou bigint, convites bigint)
language sql stable security definer set search_path = public as $$
  select j.id, j.apelido, j.avatar, j.criado_em,
         (j.xp - coalesce(b.xp, 0))::bigint,
         (fazenda_nivel(j.xp) - fazenda_nivel(coalesce(b.xp, 0)))::bigint,
         (j.moedas_ganhas - coalesce(b.moedas_ganhas, 0))::bigint,
         coalesce((select sum(f.qtd::bigint * f.preco) from fazenda_feira f
                    where f.vendedor_id = j.id and f.vendido_em >= p_desde and f.vendido_em < p_ate), 0)::bigint,
         coalesce((select sum(f.qtd::bigint * f.preco) from fazenda_feira f
                    where f.comprador_id = j.id and f.vendido_em >= p_desde and f.vendido_em < p_ate), 0)::bigint,
         (select count(*) from fazenda_convites c join fazenda_jogadores a on a.id = c.convidado_id
           where c.dono_id = j.id and c.criado_em >= p_desde and c.criado_em < p_ate and a.banido_em is null
             and fazenda_nivel(a.xp) >= (fazenda_evento_regras()->>'convite_nivel')::int)::bigint
    from fazenda_jogadores j
    left join fazenda_semana_base b on b.jogador_id = j.id and b.semana = p_semana
   where j.banido_em is null;
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
  insert into fazenda_semana_base (jogador_id, semana, xp, moedas_ganhas)
  select id, v_ini, xp, moedas_ganhas from fazenda_jogadores
  on conflict (jogador_id) do update set semana = excluded.semana, xp = excluded.xp, moedas_ganhas = excluded.moedas_ganhas;
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
  v_id    uuid := fazenda_auth(p_token);   -- (e fecha a semana, se virou)
  s       record;
  v_ant   timestamptz;
begin
  select * into s from fazenda_semanas order by inicio desc limit 1;
  select max(semana) into v_ant from fazenda_semana_premios;
  return jsonb_build_object(
    'inicio', s.inicio,
    'desde', s.aberta_em,
    'fim', s.inicio + interval '7 days',
    'regras', fazenda_evento_regras(),
    'placar', coalesce((
      select jsonb_object_agg(x.categoria, x.dados) from (
        select p.categoria, jsonb_build_object(
                 'top', coalesce(jsonb_agg(jsonb_build_object('apelido', p.apelido, 'avatar', p.avatar, 'valor', p.valor, 'eu', p.jogador_id = v_id)
                                           order by p.posicao) filter (where p.posicao <= 3), '[]'::jsonb),
                 'eu', (array_agg(jsonb_build_object('posicao', p.posicao, 'valor', p.valor)) filter (where p.jogador_id = v_id))[1],
                 'total', count(*)) as dados
          from fazenda_semana_posicoes(s.inicio, s.aberta_em, now()) p
         group by p.categoria) x), '{}'::jsonb),
    'passada', (
      select jsonb_build_object('semana', v_ant, 'premios', jsonb_agg(jsonb_build_object(
               'categoria', p.categoria, 'posicao', p.posicao, 'apelido', j.apelido, 'avatar', j.avatar,
               'valor', p.valor, 'item', p.item, 'diamantes', p.diamantes, 'eu', p.jogador_id = v_id) order by p.categoria, p.posicao))
        from fazenda_semana_premios p join fazenda_jogadores j on j.id = p.jogador_id
       where p.semana = v_ant)
  );
end;
$$;

-- a semana fecha sozinha na primeira chamada depois da sexta 22h; as conquistas do evento; o evento
-- no estado do jogo e os troféus no perfil dos vizinhos

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
  -- fase 63: a semana do evento virou (sexta 22h)? a primeira chamada fecha, premia e abre a nova
  if not exists (select 1 from fazenda_semanas where inicio = fazenda_semana_inicio(now())) then
    perform fazenda_semana_fechar();
  end if;
  return v_id;
end;
$$;

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
      else 0
    end;
    if v_valor >= r.meta then
      insert into fazenda_conquistas (jogador_id, conquista) values (p_jogador, r.id) on conflict do nothing;
      update fazenda_jogadores set moedas = moedas + r.recompensa where id = p_jogador;
    end if;
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
  return v_json;
end;
$$;

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

revoke execute on function
  public.fazenda_moedas_ganhas(),
  public.fazenda_semana_inicio(timestamptz),
  public.fazenda_evento_regras(),
  public.fazenda_semana_placar(timestamptz, timestamptz, timestamptz),
  public.fazenda_semana_posicoes(timestamptz, timestamptz, timestamptz),
  public.fazenda_semana_fechar(),
  public.fazenda_trofeus(uuid)
from public, anon, authenticated;
grant execute on function public.fazenda_evento(text) to anon, authenticated;

-- abre a semana de agora (a primeira: o evento começa quando este SQL roda)
select public.fazenda_semana_fechar();

-- conferência: deve aparecer "Evento: fecha em <a próxima sexta> às 22h; 8 itens do evento; troféu de ouro na feira de 200000 a 600000"
select 'Evento: fecha em ' || to_char((s.inicio + interval '7 days') at time zone 'America/Sao_Paulo', 'DD/MM') || ' às '
    || to_char((s.inicio + interval '7 days') at time zone 'America/Sao_Paulo', 'HH24') || 'h; '
    || (select count(*) from public.fazenda_culturas where id in ('trofeu_ouro', 'trofeu_prata', 'trofeu_bronze', 'ampulheta_dourada',
        'cofrinho_ouro', 'balanca_ouro', 'sacola_ouro', 'leme_dourado')) || ' itens do evento; troféu de ouro na feira de '
    || (public.fazenda_feira_faixa('trofeu_ouro'))[1] || ' a ' || (public.fazenda_feira_faixa('trofeu_ouro'))[2] as ok
  from public.fazenda_semanas s order by s.inicio desc limit 1;
