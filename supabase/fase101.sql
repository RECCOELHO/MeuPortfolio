-- ============================================================
-- FAZENDINHA — Fase 101 (a agenda de invasões: o dono agenda, os jogadores só veem quando tem uma),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 100): Supabase > SQL Editor > colar este arquivo > Run.
-- Rode ANTES do merge do PR.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 99 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_invasao_mult')) then
    raise exception 'Rode o fase99.sql e o fase100.sql antes deste. Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 101: a invasão deixa de ter dia marcado dentro do código. Fica numa agenda (fazenda_invasao_agenda),
-- e o dono do jogo agenda pelo próprio jogo: no botão da Invasão, escolhe o dia, a hora de começar e de
-- acabar e o nível mínimo. Cada invasão tem o seu placar e os seus prêmios (o "evento" é o id da agenda).
-- A invasão da vez é a que está rolando ou a próxima; sem nenhuma pela frente, vale a última (para o
-- placar e o prêmio). O fechamento paga cada invasão que acabou, uma vez. O aviso "Você ganhou" mostra o
-- prêmio ainda não visto de qualquer invasão. A sala de teste dos admins fica aberta o dia todo, todo dia.
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------

create table if not exists public.fazenda_invasao_agenda (
  id         text primary key,                       -- vira o "evento" do placar e dos prêmios
  nome       text not null default 'Invasão de Varginha',
  inicio     timestamptz not null,
  fim        timestamptz not null,
  nivel_min  int not null default 10,
  cancelada  boolean not null default false,
  criado_por uuid references public.fazenda_jogadores(id) on delete set null,
  criado_em  timestamptz not null default now(),
  check (fim > inicio)
);
alter table public.fazenda_invasao_agenda enable row level security;
revoke all on public.fazenda_invasao_agenda from anon, authenticated;
-- a primeira invasão (a de 1/11), que antes morava dentro das regras
insert into public.fazenda_invasao_agenda (id, nome, inicio, fim, nivel_min)
values ('varginha-2026', 'Invasão de Varginha', '2026-11-01 15:00:00-03', '2026-11-02 00:00:00-03', 10)
on conflict (id) do nothing;

-- as regras de uma invasão da agenda (p_id), ou da sala de teste dos admins (p_teste: aberta o dia todo,
-- placar próprio por dia, nível 1). Os números (armas, ETs, prêmios) são iguais para todas as invasões.
create or replace function public.fazenda_invasao_regras_de(p_id text, p_teste boolean default false)
returns jsonb language sql stable as $$
  with ev as (
    select 'teste-' || to_char(now() at time zone 'America/Sao_Paulo', 'YYYYMMDD') as id, 'Invasão de Varginha (teste)'::text as nome,
           (date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo') as inicio,
           (date_trunc('day', now() at time zone 'America/Sao_Paulo') + interval '1 day') at time zone 'America/Sao_Paulo' as fim,
           1 as nivel_min
     where p_teste
    union all
    select a.id, a.nome, a.inicio, a.fim, a.nivel_min from public.fazenda_invasao_agenda a where not p_teste and a.id = p_id
  )
  select jsonb_build_object(
    'id', ev.id, 'nome', ev.nome, 'teste', p_teste, 'inicio', ev.inicio, 'fim', ev.fim, 'nivel_min', ev.nivel_min,
    'toques_seg', 6, 'toques_max', 30,                 -- o saldo de toques: enche 6 por segundo, guarda até 30
    'intervalo', 1.2, 'vida', 9,                       -- um ET novo a cada 1,2 s; cada um fica 9 s na tela
    'hp_base', 4, 'hp_por_hora', 2,                    -- a cada hora os ETs aguentam mais
    -- fase 98: o chefão desce a cada 20 min (era 1 h); hp_chefe_por_hora agora soma a cada chefão (50 por chefão = 150 por hora, como antes)
    'chefe_a_cada', 1200, 'chefe_atraso', 30, 'vida_chefe', 120, 'hp_chefe', 400, 'hp_chefe_por_hora', 50,
    'bonus_abate', 2, 'bonus_chefe', 200,              -- pontos a mais por derrubar
    'auto_ativo_seg', 120, 'lote_max_seg', 5,
    -- fase 98: o ET dourado ("ainda tá aí?"): aparece só para você, num lugar sorteado, a cada 3 a 6 min
    -- (no teste dos admins: 45 s a 90 s). Tocou nele: +bonus_ouro. Não tocou no prazo: os seus toques e
    -- as armas automáticas param de valer até você tocar nele.
    'ouro_primeiro', case when p_teste then 20 else 90 end, 'ouro_min', case when p_teste then 45 else 180 end,
    'ouro_max', case when p_teste then 90 else 360 end, 'ouro_prazo', 15, 'bonus_ouro', 50,
    -- fase 99: a ameaça. A cada ameaca_pontos pontos SEUS, os ETs e o chefão aguentam +ameaca_passo da vida
    -- (1.000 pontos: ×1,5; 2.000: ×2; 10.000: ×6...), até ameaca_max. O bônus de derrubar sobe junto.
    'ameaca_pontos', 1000, 'ameaca_passo', 0.5, 'ameaca_max', 60,
    'premio', jsonb_build_object('diamantes', 40, 'moedas', 4000000, 'fator', 0.75, 'min_diamantes', 1, 'min_moedas', 1000),
    'armas', '[
      {"id": "forcado",    "nome": "Forcado elétrico",   "tipo": "toque", "efeito": 2,  "preco": 5000,   "fator": 1.22},
      {"id": "espantalho", "nome": "Espantalho-robô",    "tipo": "auto",  "efeito": 1,  "preco": 20000,  "fator": 1.3},
      {"id": "trator",     "nome": "Trator-canhão",      "tipo": "auto",  "efeito": 4,  "preco": 80000,  "fator": 1.32},
      {"id": "drone",      "nome": "Drone pulverizador", "tipo": "auto",  "efeito": 12, "preco": 250000, "fator": 1.35}
    ]'::jsonb,
    -- fase 100: as armas sobem até o nível 60 e o preço cresce mais devagar; o forcado dá +2 de dano por nível
    'arma_nivel_max', 60)
  from ev;
$$;


-- a invasão da vez: a que está rolando ou a próxima agendada; sem nenhuma pela frente, a última que houve
create or replace function public.fazenda_invasao_regras(p_teste boolean default false)
returns jsonb language sql stable as $$
  select public.fazenda_invasao_regras_de(
    case when p_teste then null else
      (select a.id from public.fazenda_invasao_agenda a where not a.cancelada
        order by (a.fim > now()) desc, case when a.fim > now() then a.inicio end, a.fim desc limit 1) end,
    p_teste);
$$;

create or replace function public.fazenda_invasao_fechar()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_r   jsonb;
  v_ev  text;
  ev    record;
  r     record;
  p     record;
  v_n   int;
  c     record;
begin
  -- fase 101: fecha cada invasão da agenda que já acabou (uma de cada vez, sem esperar ninguém)
  for ev in select a.id from fazenda_invasao_agenda a
             where not a.cancelada and a.fim <= now()
               and not exists (select 1 from fazenda_invasao_fechamentos f where f.evento = a.id)
             order by a.fim loop
    v_ev := ev.id; v_r := fazenda_invasao_regras_de(v_ev); v_n := 0;
    continue when not pg_try_advisory_xact_lock(9494, hashtext(v_ev));
    continue when exists (select 1 from fazenda_invasao_fechamentos where evento = v_ev);
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
  end loop;
end;
$$;

create or replace function public.fazenda_invasao(p_token text, p_visto boolean default false, p_teste boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id uuid := fazenda_auth_ler(p_token);
  v_r  jsonb := fazenda_invasao_regras(p_teste);
  v_pr record;
  v_fech boolean;
  v_dono boolean;
begin
  if p_teste and not exists (select 1 from fazenda_jogadores where id = v_id and admin is not null) then raise exception 'sem_permissao'; end if;
  perform fazenda_invasao_fechar();
  v_fech := exists (select 1 from fazenda_invasao_fechamentos where evento = v_r->>'id');
  -- fase 101: o prêmio ainda não visto de qualquer invasão (a mais recente); senão, o da invasão da vez
  select pr.* into v_pr from fazenda_invasao_premios pr left join fazenda_invasao_fechamentos fe on fe.evento = pr.evento
   where pr.jogador_id = v_id and not pr.visto and not p_teste order by fe.fechado_em desc nulls last limit 1;
  if not found then
    select * into v_pr from fazenda_invasao_premios where evento = v_r->>'id' and jogador_id = v_id;
  end if;
  if v_pr.evento is not null and p_visto and not v_pr.visto then
    update fazenda_invasao_premios set visto = true where evento = v_pr.evento and jogador_id = v_id;
  end if;
  v_dono := exists (select 1 from fazenda_jogadores where id = v_id and admin = 'dono');
  return jsonb_build_object('regras', v_r, 'agora', now(), 'fechada', v_fech,
    'nivel', (select fazenda_nivel_de(xp, nivel_trava) from fazenda_jogadores where id = v_id),
    'eu', fazenda_invasao_eu(v_r, v_id),
    'sala', case when now() >= (v_r->>'inicio')::timestamptz - interval '1 day' then fazenda_invasao_sala(v_r) end,
    'premio', case when v_pr.posicao is not null then jsonb_build_object('posicao', v_pr.posicao, 'pontos', v_pr.pontos,
      'diamantes', v_pr.diamantes, 'moedas', v_pr.moedas, 'visto', v_pr.visto,
      'nome', (select nome from fazenda_invasao_agenda where id = v_pr.evento)) end,
    -- fase 101: a agenda (só o dono vê): as que vêm e as da última semana
    'agenda', case when v_dono then coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'nome', a.nome, 'inicio', a.inicio, 'fim', a.fim,
        'nivel_min', a.nivel_min, 'cancelada', a.cancelada,
        'jogadores', (select count(*) from fazenda_invasao i where i.evento = a.id and i.pontos > 0)) order by a.inicio)
      from fazenda_invasao_agenda a where a.fim > now() - interval '7 days'), '[]'::jsonb) end);
end;
$$;


-- O dono agenda uma invasão (das 15h à meia-noite, por exemplo: p_fim no dia seguinte). Não pode cruzar
-- com outra que não foi cancelada; dura de 30 min a 24 h; começa daqui a no máximo 60 dias.
create or replace function public.fazenda_invasao_agendar(p_token text, p_inicio timestamptz, p_fim timestamptz,
                                                          p_nivel_min int default 10, p_nome text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_nome text := left(btrim(regexp_replace(coalesce(p_nome, ''), '[<>\s]+', ' ', 'g')), 40);
  v_ev   text;
begin
  if not exists (select 1 from fazenda_jogadores where id = v_id and admin = 'dono') then raise exception 'sem_permissao'; end if;
  if p_inicio is null or p_fim is null or p_fim < p_inicio + interval '30 minutes' or p_fim > p_inicio + interval '24 hours'
     or p_inicio < now() - interval '2 minutes' or p_inicio > now() + interval '60 days' then
    raise exception 'agenda_horario';
  end if;
  if exists (select 1 from fazenda_invasao_agenda where not cancelada and tstzrange(inicio, fim) && tstzrange(p_inicio, p_fim)) then
    raise exception 'agenda_conflito';
  end if;
  v_ev := 'invasao-' || to_char(p_inicio at time zone 'America/Sao_Paulo', 'YYYYMMDD-HH24MI');
  if exists (select 1 from fazenda_invasao_agenda where id = v_ev) then v_ev := v_ev || '-' || substr(md5(random()::text), 1, 4); end if;
  insert into fazenda_invasao_agenda (id, nome, inicio, fim, nivel_min, criado_por)
  values (v_ev, coalesce(nullif(v_nome, ''), 'Invasão de Varginha'), p_inicio, p_fim, greatest(1, least(70, coalesce(p_nivel_min, 10))), v_id);
  return fazenda_invasao(p_token);
end;
$$;

-- O dono cancela uma invasão que ainda não começou.
create or replace function public.fazenda_invasao_cancelar(p_token text, p_evento text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_id uuid := fazenda_auth(p_token);
begin
  if not exists (select 1 from fazenda_jogadores where id = v_id and admin = 'dono') then raise exception 'sem_permissao'; end if;
  update fazenda_invasao_agenda set cancelada = true where id = p_evento and inicio > now() and not cancelada;
  if not found then raise exception 'agenda_comecou'; end if;
  return fazenda_invasao(p_token);
end;
$$;

-- permissões
revoke execute on function
  public.fazenda_invasao_regras_de(text, boolean),
  public.fazenda_invasao_regras(boolean),
  public.fazenda_invasao_fechar()
from public, anon, authenticated;

grant execute on function
  public.fazenda_invasao(text, boolean, boolean),
  public.fazenda_invasao_agendar(text, timestamptz, timestamptz, int, text),
  public.fazenda_invasao_cancelar(text, text)
to anon, authenticated;

-- conferência: a agenda e a invasão da vez (deve ser a de 1/11, já fechada)
select (select count(*) from public.fazenda_invasao_agenda) as invasoes_na_agenda,
       public.fazenda_invasao_regras()->>'id' as invasao_da_vez,
       exists (select 1 from public.fazenda_invasao_fechamentos where evento = 'varginha-2026') as primeira_fechada;
