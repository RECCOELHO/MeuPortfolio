-- ============================================================
-- FAZENDINHA — devolve o XP que a fase 106 cortou (rodar UMA vez; rodar de novo não faz nada)
-- Para o banco que já está no ar: Supabase > SQL Editor > colar este arquivo > Run.
--
-- Na fase 106, quem já tinha XP de sobra no 45 ficou no começo do 46 (o XP acima disso foi cortado). Aqui ele
-- volta: o jogo guarda o XP de cada um no começo da semana (fazenda_semana_base, para o placar do evento), de
-- antes do corte; o que passava do começo do 46 nessa foto é somado de volta ao XP de agora (o que a pessoa
-- ganhou depois do corte continua). Com o XP de volta, o nível sobe sozinho até onde ele dá (até o 60, e até
-- onde a fazenda dela tem o que cada nível pede), com o presente de moedas e os diamantes de cada nível.
-- Não conta no placar da semana (o XP da semana continua sendo só o ganho jogando).
-- Só funciona nesta semana (a foto é trocada toda segunda); se a semana já virou, ele avisa e não muda nada.
-- ============================================================

create table if not exists public.fazenda_xp_devolvido (
  jogador_id uuid primary key references public.fazenda_jogadores(id) on delete cascade,
  xp         int not null,
  nivel_antes int,
  em         timestamptz not null default now()
);
alter table public.fazenda_xp_devolvido enable row level security;

do $$
declare
  v_ini timestamptz := public.fazenda_semana_inicio(now());
  v_46  int := public.fazenda_xp_nivel(46);
  v_n   int;
begin
  if not exists (select 1 from public.fazenda_semana_base where semana = v_ini) then
    raise exception 'A foto do XP desta semana não está no banco (a semana virou?). Nada foi mudado.';
  end if;
  perform set_config('fazenda.xp_puro', '1', true);   -- (o XP devolvido não é dobrado pelo bônus)
  with alvo as (
    select b.jogador_id, b.xp - v_46 as devolve, public.fazenda_nivel_de(j.xp, j.nivel_trava) as nivel
      from public.fazenda_semana_base b
      join public.fazenda_jogadores j on j.id = b.jogador_id
     where b.semana = v_ini and b.xp > v_46
       and not exists (select 1 from public.fazenda_xp_devolvido d where d.jogador_id = b.jogador_id)
  ), feito as (
    insert into public.fazenda_xp_devolvido (jogador_id, xp, nivel_antes)
    select jogador_id, devolve, nivel from alvo
    returning jogador_id, xp
  )
  update public.fazenda_jogadores j set xp = least(2147483647, j.xp::bigint + f.xp)::int
    from feito f where j.id = f.jogador_id;
  get diagnostics v_n = row_count;
  perform set_config('fazenda.xp_puro', '', true);
  -- (a trava de cada um, o que falta na fazenda para passar de nível, já está guardada: não mexe nela,
  -- para ninguém cair de nível)
  raise notice 'XP devolvido agora para % jogador(es).', v_n;
end $$;

-- conferência: quem recebeu, quanto e em que nível fica (o presente de cada nível cai quando a pessoa abrir o jogo)
select j.apelido, d.xp as xp_devolvido, d.nivel_antes, public.fazenda_nivel_de(j.xp, j.nivel_trava) as nivel_agora
  from public.fazenda_xp_devolvido d join public.fazenda_jogadores j on j.id = d.jogador_id
 order by d.xp desc;
