-- ============================================================
-- FAZENDINHA — Fase 71 (o servidor mais leve),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 70): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

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
  delete from fazenda_cache where chave like 'itens:%';   -- os itens de cada nível se refazem na próxima vez
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

-- as funções que já existiam e mudaram

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
      'vento', v_prev->'vento',
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
                                          'estoque', estoque, 'prontos', prontos))
        from fazenda_construcoes where jogador_id = p_jogador), '[]'::jsonb),
    'estoque_max', fazenda_estoque_max(),
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
  return v_json;
end;
$$;

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
    v_xp_colheita := not p_bot and (c.xp_em is null or c.xp_em <= now() - interval '8 minutes');
    if v_xp_colheita then
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
end;
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
    v_custo := 100 / (fazenda_ritmo(a.nivel) * 8);
    -- fase 43: com o café (diamantes) o tempo dentro dele vale em dobro
    v_seg := extract(epoch from now() - a.atualizado_em)::real
           + case when v_cafe_ate is null then 0
                  else greatest(extract(epoch from least(now(), v_cafe_ate) - greatest(a.atualizado_em, v_cafe_de))::real, 0) end;
    v_cred := least(a.credito + v_seg / 3600 * fazenda_ritmo(a.nivel), fazenda_ritmo(a.nivel) * 8);
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
                   > greatest(a.atualizado_em, now() - interval '8 hours')
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
                 and k.estoque + (k.iniciado_em is not null)::int < fazenda_estoque_max()
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
end;
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

-- permissões
revoke execute on function
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
  public.fazenda_semana_tentar_fechar()
from public, anon, authenticated;

grant execute on function
  public.fazenda_evento(text),
  public.fazenda_chat(text, bigint),
  public.fazenda_compra_status(text, uuid),
  public.fazenda_feira_lista(text, text)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- conferência: deve aparecer "Fase 71: catálogos prontos (6); servidor mais leve"
select 'Fase 71: catálogos prontos (' || (select count(*) from public.fazenda_cache where chave not like 'itens:%' and chave <> 'previsao') || '); servidor mais leve' as ok;
