-- ============================================================
-- PONG SECRETO — ranking do easter egg do portfólio
--
-- Mesmo padrão da fazenda: tabela com RLS ligado e SEM policies
-- (a chave pública não lê nem grava direto) e acesso só por funções.
-- O servidor recalcula a nota pelo placar, valida os números e
-- limita a quantidade de envios.
--
-- Como rodar: Supabase > SQL Editor > colar este arquivo > Run.
-- Pode rodar de novo sem problemas (idempotente).
-- ============================================================

create table if not exists public.pong_placares (
  id          bigint generated always as identity primary key,
  nome        text not null check (char_length(nome) between 1 and 20),
  jogador     smallint not null check (jogador between 0 and 7),
  cpu         smallint not null check (cpu between 0 and 7),
  tempo_seg   int not null check (tempo_seg between 1 and 3600),
  nota        text not null check (nota in ('S', 'A', 'B', 'C', 'D', 'F')),
  criado_em   timestamptz not null default now()
);
create index if not exists pong_placares_ranking_idx
  on public.pong_placares (jogador desc, cpu asc, tempo_seg asc);
create index if not exists pong_placares_criado_idx on public.pong_placares (criado_em desc);

alter table public.pong_placares enable row level security;
revoke all on public.pong_placares from anon, authenticated;

-- Mesma regra de nota do jogo
create or replace function public.pong_nota(p_jogador int, p_cpu int)
returns text language sql immutable as $$
  select case
    when p_jogador < 7 then 'F'
    when p_cpu = 0 then 'S'
    when p_cpu <= 2 then 'A'
    when p_cpu <= 4 then 'B'
    when p_cpu <= 5 then 'C'
    else 'D'
  end;
$$;

create or replace function public.pong_salvar(p_nome text, p_jogador int, p_cpu int, p_tempo int)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  p_nome := btrim(regexp_replace(coalesce(p_nome, ''), '\s+', ' ', 'g'));
  if char_length(p_nome) not between 1 and 20 then
    raise exception 'nome_invalido';
  end if;
  -- partida terminada: alguém fez 7 e o outro não
  if p_jogador is null or p_cpu is null or p_jogador not between 0 and 7 or p_cpu not between 0 and 7
     or (p_jogador = 7) = (p_cpu = 7) then
    raise exception 'placar_invalido';
  end if;
  -- cada ponto leva pelo menos ~1 segundo
  if p_tempo is null or p_tempo < (p_jogador + p_cpu) or p_tempo > 3600 then
    raise exception 'tempo_invalido';
  end if;
  -- freio contra spam: no máximo 30 placares por minuto no total
  if (select count(*) from pong_placares where criado_em > now() - interval '1 minute') >= 30 then
    raise exception 'muitos_envios';
  end if;

  insert into pong_placares (nome, jogador, cpu, tempo_seg, nota)
  values (p_nome, p_jogador, p_cpu, p_tempo, pong_nota(p_jogador, p_cpu))
  returning id into v_id;

  return jsonb_build_object(
    'id', v_id,
    'nota', pong_nota(p_jogador, p_cpu),
    -- posição desse placar no ranking geral
    'posicao', (select count(*) + 1 from pong_placares
                 where (jogador, -cpu, -tempo_seg) > (p_jogador, -p_cpu, -p_tempo))
  );
end;
$$;

create or replace function public.pong_ranking()
returns jsonb
language sql security definer stable
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'nome', nome, 'jogador', jogador, 'cpu', cpu, 'tempo', tempo_seg, 'nota', nota)
         order by jogador desc, cpu asc, tempo_seg asc, criado_em asc), '[]'::jsonb)
    from (select * from pong_placares
           order by jogador desc, cpu asc, tempo_seg asc, criado_em asc
           limit 20) t;
$$;

revoke execute on function public.pong_nota(int, int), public.pong_salvar(text, int, int, int), public.pong_ranking()
  from public, anon, authenticated;
grant execute on function public.pong_salvar(text, int, int, int), public.pong_ranking()
  to anon, authenticated;
