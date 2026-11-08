-- ============================================================
-- FAZENDINHA — Fase 126 (colher já no pomar e nos bichos; contas paradas; quem joga junto aparece), só o que mudou.
-- Para o banco que já está no ar (com a fase 125): Supabase > SQL Editor > colar este arquivo > Run.
-- Rodar ANTES do merge do PR (o jogo novo chama fazenda_coletar com 4 parâmetros e fazenda_presenca).
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

alter table public.fazenda_jogadores add column if not exists inativo_em timestamptz;

-- ------------------------------------------------------------
-- Fase 126: colher já com diamante no pomar e nos bichos; contas paradas somem do ranking e das
-- visitas (e voltam sozinhas quando a pessoa entra); e quem está jogando junto aparece: no alto-mar,
-- os outros pescando lá no fundo; na visita, o dono e as visitas andando pela fazenda.
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------

-- quanto custa deixar pronto agora o que falta (em segundos): 1 diamante a cada 4 h, no mínimo 1
create or replace function public.fazenda_preco_agora(p_seg double precision)
returns int language sql stable set search_path = public as $$
  select greatest(1, ceil(greatest(p_seg, 0) / (3600 * (fazenda_loja_diamantes()->'agora'->>'horas')::numeric)))::int;
$$;

-- As contas paradas: criadas entre p_de e p_ate, que só entraram naquele primeiro dia, faz mais de 7 dias,
-- e nunca compraram diamante. Nada é apagado: elas só somem do ranking e das visitas, e voltam ao entrar.
create or replace function public.fazenda_inativar_parados(p_de timestamptz, p_ate timestamptz)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_n int;
begin
  update fazenda_jogadores j set inativo_em = now()
   where j.criado_em >= p_de and j.criado_em < p_ate
     and j.visto_em < j.criado_em + interval '1 day'
     and j.visto_em < now() - interval '7 days'
     and j.inativo_em is null and j.banido_em is null and not j.teste and j.admin is null
     and not exists (select 1 from fazenda_compras c where c.jogador_id = j.id and c.status = 'aprovada');
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- Quem está onde, agora: 'mar' (pescando no alto-mar) ou o id do dono da fazenda em que está (na sua,
-- ou visitando). O jogo avisa a cada poucos segundos; quem some por mais de 25 s não aparece mais.
-- Tabela sem diário (unlogged): é só o "agora", não precisa sobreviver a um reinício do banco.
create unlogged table if not exists public.fazenda_presenca (
  jogador_id uuid primary key,
  onde       text not null,
  x          real,              -- onde está o boneco (quadrados do mapa)
  y          real,
  acao       text,              -- no mar: parado, esperando, mordendo
  peixe      text,              -- o último peixe que pegou
  pegou_em   timestamptz,
  visto_em   timestamptz not null default now()
) with (fillfactor = 50, autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 200);
create index if not exists fazenda_presenca_onde on public.fazenda_presenca (onde, visto_em);
alter table public.fazenda_presenca enable row level security;
revoke all on public.fazenda_presenca from anon, authenticated;

create or replace function public.fazenda_presenca(p_token text, p_onde text, p_x real default null, p_y real default null,
                                                   p_acao text default null, p_peixe text default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_onde text;
  v_dono uuid;
begin
  if p_onde is null or p_onde = 'sair' then
    delete from fazenda_presenca where jogador_id = v_id;
    return jsonb_build_object('outros', '[]'::jsonb);
  end if;
  if p_onde = 'mar' then
    v_onde := 'mar';
  else
    begin
      v_dono := p_onde::uuid;
    exception when others then
      raise exception 'lugar_invalido';
    end;
    v_onde := v_dono::text;
  end if;
  insert into fazenda_presenca as p (jogador_id, onde, x, y, acao, peixe, pegou_em, visto_em)
  values (v_id, v_onde,
          case when p_x is not null then greatest(-20, least(100, p_x)) end,
          case when p_y is not null then greatest(-20, least(140, p_y)) end,
          case when p_acao in ('parado', 'esperando', 'mordendo') then p_acao end,
          case when p_peixe is not null and exists (select 1 from fazenda_culturas where id = p_peixe) then p_peixe end,
          case when p_peixe is not null then now() end,
          now())
  on conflict (jogador_id) do update
    set onde = excluded.onde, x = excluded.x, y = excluded.y, acao = excluded.acao,
        peixe = coalesce(excluded.peixe, p.peixe), pegou_em = coalesce(excluded.pegou_em, p.pegou_em), visto_em = now();

  return jsonb_build_object(
    'outros', coalesce((select jsonb_agg(q) from (
        select left(p.jogador_id::text, 8) as id, j.apelido, j.avatar, round(p.x::numeric, 2) as x, round(p.y::numeric, 2) as y,
               p.acao, p.peixe,
               case when p.pegou_em > now() - interval '12 seconds' then floor(extract(epoch from p.pegou_em) * 1000)::bigint end as pegou,
               p.jogador_id = v_dono as dono,
               case when v_onde = 'mar' then jsonb_build_object(
                 'nivel', coalesce((fazenda_mar_item(p.jogador_id, 'barco')->>'valor')::int, 1),
                 'pecas', (select jsonb_object_agg(x, coalesce((select m.nivel from fazenda_melhorias m where m.jogador_id = p.jogador_id and m.id = x), 0))
                             from unnest(array['motor', 'sonar', 'porao', 'rede', 'expedicao']) x),
                 'visual', coalesce(j.barco_visual, '{}'::jsonb)) end as navio
          from fazenda_presenca p join fazenda_jogadores j on j.id = p.jogador_id
         where p.onde = v_onde and p.jogador_id <> v_id and p.visto_em > now() - interval '25 seconds'
           and j.banido_em is null
         order by (p.jogador_id = v_dono) desc, p.visto_em desc
         limit case when v_onde = 'mar' then 3 else 8 end) q), '[]'::jsonb),
    -- na visita: onde o dono está agora (casa = na fazenda dele, mar, fora = visitando alguém; null = fora do jogo)
    'dono', case when v_dono is not null and v_dono <> v_id then
      (select case when p.onde = 'mar' then 'mar' when p.onde = v_dono::text then 'casa' else 'fora' end
         from fazenda_presenca p where p.jogador_id = v_dono and p.visto_em > now() - interval '25 seconds') end);
end;
$$;

-- as funções que mudaram

create or replace function public.fazenda_auth(p_token text)
returns uuid
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid;
  v_hash text;
  v_leve boolean;
  v_cat  text;
begin
  if p_token is null or length(p_token) < 32 then
    raise exception 'token_invalido';
  end if;
  v_hash := encode(digest(p_token, 'sha256'), 'hex');
  select jogador_id, leve, cat_ver into v_id, v_leve, v_cat
    from fazenda_sessoes
   where token_hash = v_hash;
  if v_id is null then
    raise exception 'token_invalido';
  end if;
  -- fase 89: o jogo dessa sessão já tem os catálogos? (o fazenda_estado manda só o que muda)
  perform set_config('fazenda.eu', v_id::text, true), set_config('fazenda.sessao', v_hash, true),
          set_config('fazenda.leve', case when v_leve then '1' else '' end, true),
          set_config('fazenda.cat_ver', coalesce(v_cat, ''), true);
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
  -- fase 126: quem estava parado (fazenda_inativar_parados) volta a aparecer assim que entra
  update fazenda_jogadores set visto_em = now(), inativo_em = null
   where id = v_id and (visto_em < now() - interval '1 hour' or inativo_em is not null);
  return v_id;
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
                       where (xp > v_xp or (xp = v_xp and criado_em < v_desde)) and banido_em is null and not teste and inativo_em is null),   -- (fase 119: sem as contas de teste; fase 126: nem as paradas)
    'total', (select count(*) from fazenda_jogadores where banido_em is null and not teste and inativo_em is null),
    'ranking', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', r.id, 'apelido', r.apelido, 'avatar', r.avatar, 'nivel', fazenda_nivel_de(r.xp, r.nivel_trava), 'xp', r.xp,
               'patrimonio', r.moedas + coalesce((
                 select sum(ce.quantidade * k.venda)
                   from fazenda_celeiro ce join fazenda_culturas k on k.id = ce.item
                  where ce.jogador_id = r.id), 0),
               'eu', r.id = v_id)
             order by r.xp desc, r.criado_em)
        from (select * from fazenda_jogadores where banido_em is null and (not teste or id = v_id) and (inativo_em is null or id = v_id) order by xp desc, criado_em limit 200) r), '[]'::jsonb)   -- (fase 53: eram 50)
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
       and j.banido_em is null and not j.teste   -- (fase 119: ninguém cai na conta de teste)
       and j.inativo_em is null                  -- (fase 126: nem numa conta parada)
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
    'inativos', (select count(*) from fazenda_jogadores where inativo_em is not null),   -- fase 126
    'jogadores', coalesce((select jsonb_agg(jsonb_build_object(
        'id', j.id, 'apelido', j.apelido, 'avatar', j.avatar, 'nivel', fazenda_nivel_de(j.xp, j.nivel_trava),
        'criado_em', j.criado_em, 'visto_em', j.visto_em, 'admin', j.admin,
        'banido_em', j.banido_em, 'inativo_em', j.inativo_em, 'banido_motivo', j.banido_motivo, 'eu', j.id = v_id) order by j.ordem)
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


-- Colhe o que um item produz sozinho (amoreira). Toque nele fora do modo construir.
-- fase 126: p_agora = colher já com diamante (1 a cada 4 h que faltam, como nos canteiros)
drop function if exists public.fazenda_coletar(text, int, int);
create or replace function public.fazenda_coletar(p_token text, p_x int, p_y int, p_agora boolean default false)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  r    record;
  k    record;
  v_preco int := 0;
begin
  select c.colhido_em, c.tipo, i.produz, i.produz_seg, i.produz_qtd, i.entradas into r
    from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y
     for update of c;
  if not found or r.produz is null or r.entradas is not null then raise exception 'item_invalido'; end if;
  if r.colhido_em is not null and now() < r.colhido_em + make_interval(secs => r.produz_seg) then
    if not coalesce(p_agora, false) then raise exception 'nao_pronto'; end if;
    v_preco := fazenda_preco_agora(extract(epoch from r.colhido_em + make_interval(secs => r.produz_seg) - now()));
    update fazenda_jogadores set diamantes = diamantes - v_preco where id = v_id and diamantes >= v_preco;
    if not found then raise exception 'diamantes_insuficientes'; end if;
    insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, 'agora:' || r.tipo, v_preco);
  end if;
  select * into k from fazenda_culturas where id = r.produz;
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  values (v_id, r.produz, r.produz_qtd)
  on conflict (jogador_id, item)
  do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  update fazenda_construcoes set colhido_em = fazenda_colhido_agora(v_id, r.tipo) where jogador_id = v_id and x = p_x and y = p_y;
  update fazenda_jogadores set xp = xp + greatest(k.xp / 8, 1) where id = v_id;
  perform fazenda_missao(v_id, 'colher', r.produz_qtd);
  return jsonb_build_object('qtd', r.produz_qtd, 'item', r.produz, 'diamantes', v_preco, 'estado', fazenda_estado(v_id));
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
  v_preco int;
begin
  select a.id, a.tipo, a.alimentado_em, t.produto, t.tempo_seg, t.racao, fazenda_racao_qtd(t.racao_qtd) as racao_qtd, k.xp as produto_xp
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

  elsif p_acao = 'agora' then
    -- fase 126: diamante deixa pronto na hora o que o bicho (já alimentado) está produzindo, e já coleta
    -- (1 diamante a cada 4 h que faltam, no mínimo 1, como nos canteiros)
    if p_bot then raise exception 'acao_invalida'; end if;
    if r.alimentado_em is null then raise exception 'nao_alimentado'; end if;
    if now() < r.alimentado_em + make_interval(secs => r.tempo_seg) then
      v_preco := fazenda_preco_agora(extract(epoch from r.alimentado_em + make_interval(secs => r.tempo_seg) - now()));
      update fazenda_jogadores set diamantes = diamantes - v_preco where id = p_jogador and diamantes >= v_preco;
      if not found then raise exception 'diamantes_insuficientes'; end if;
      insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (p_jogador, 'agora:' || r.tipo, v_preco);
      update fazenda_animais set alimentado_em = now() - make_interval(secs => r.tempo_seg) where id = p_animal;
    end if;
    return fazenda_animal_um(p_jogador, p_animal, 'coletar');
  end if;

  raise exception 'acao_invalida';
end;
$$;


revoke execute on function public.fazenda_preco_agora(double precision), public.fazenda_inativar_parados(timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.fazenda_coletar(text, int, int, boolean),
                          public.fazenda_presenca(text, text, real, real, text, text) to anon, authenticated;

-- a limpeza: as contas criadas em outubro que só entraram naquele dia e nunca compraram diamante
-- conferência: tem que aparecer "fase 126 ok" e quantas contas ficaram paradas
select case when public.fazenda_preco_agora(3600) = 1 and public.fazenda_preco_agora(5 * 3600) = 2
             and to_regclass('public.fazenda_presenca') is not null
             and (select prosrc from pg_proc where proname = 'fazenda_animal_um') like '%''agora''%'
            then 'fase 126 ok' else 'não aplicou' end as resultado,
       public.fazenda_inativar_parados('2026-10-01 00:00:00-03', '2026-11-01 00:00:00-03') as contas_paradas;
