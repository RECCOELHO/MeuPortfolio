-- ============================================================
-- FAZENDINHA — Fase 102 (a sala da invasão sem fila no banco: o travamento de 1/11 às 21h), só o que mudou.
-- Para o banco que já está no ar (com a fase 101): Supabase > SQL Editor > colar este arquivo > Run.
-- Não precisa de merge para valer (o jogo não muda). Pode rodar a qualquer hora.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 101 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_invasao_agendar')) then
    raise exception 'Rode o fase101.sql antes deste (a fase 101 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 102: em 1/11, às 21h11, a sala da invasão travou o banco. A lista de quem está na sala e o placar
-- ficam prontos numa linha só (fazenda_cache) por 1,5 s; todo lote que a achava vencida regravava essa linha
-- e segurava a linha até o fim da chamada. Com a sala cheia, todo mundo esperava todo mundo: uma chamada
-- lenta virou fila, a fila esgotou as conexões, as tarefas do relógio não conseguiam nem começar e o banco
-- precisou ser reiniciado às 21h59. Agora só uma chamada por vez remonta a sala, sem esperar ninguém; as
-- outras usam a pronta (até 15 s). E as duas tabelas mais regravadas ganham espaço livre e limpeza mais
-- frequente. Pode rodar este arquivo de novo.
-- ------------------------------------------------------------

create or replace function public.fazenda_invasao_sala(p_r jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_chave text := 'invasao:' || (p_r->>'id');
  v jsonb;
  v_em timestamptz;
begin
  -- fase 102: sem fila. A sala pronta vale 2 s; quem a acha vencida só remonta se pegar a vez (sem esperar
  -- ninguém); quem não pega usa a de antes (até 15 s). Antes, todo mundo regravava a mesma linha do cache e
  -- esperava o outro terminar: com a sala cheia isso virou fila, esgotou as conexões e travou o banco (1/11, 21h).
  select valor, em into v, v_em from fazenda_cache where chave = v_chave;
  if v is not null and v_em > now() - interval '2 seconds' then return v; end if;
  if not pg_try_advisory_xact_lock(7072, hashtext(v_chave)) and v is not null and v_em > now() - interval '15 seconds' then
    return v;
  end if;
  v := jsonb_build_object(
    'jogadores', coalesce((select jsonb_agg(q order by q.pontos desc) from (
        select left(i.jogador_id::text, 8) as id, j.apelido, j.avatar, fazenda_nivel_de(j.xp, j.nivel_trava) as nivel, i.pontos,
               (abs(hashtext(i.jogador_id::text)) % 1000) / 1000.0 as x, i.armas,
               case when i.ult_lote > now() - interval '4 seconds' then i.ult_qtd else 0 end as qtd, i.ult_alvo as alvo
          from fazenda_invasao i join fazenda_jogadores j on j.id = i.jogador_id
         where i.evento = p_r->>'id' and i.visto_em > now() - interval '12 seconds'
         order by i.pontos desc limit 40) q), '[]'::jsonb),
    'na_sala', (select count(*) from fazenda_invasao where evento = p_r->>'id' and visto_em > now() - interval '12 seconds'),
    'top', coalesce((select jsonb_agg(q order by q.pontos desc, q.subiu_em) from (
        select left(i.jogador_id::text, 8) as id, j.apelido, j.avatar, i.pontos, i.abates, i.chefes, i.subiu_em
          from fazenda_invasao i join fazenda_jogadores j on j.id = i.jogador_id
         where i.evento = p_r->>'id' and i.pontos > 0
         order by i.pontos desc, i.subiu_em limit 10) q), '[]'::jsonb),
    'participantes', (select count(*) from fazenda_invasao where evento = p_r->>'id' and pontos > 0));
  -- grava sem fila (fazenda_cache_gravar: só quem tem a vez grava; a vez já é desta chamada, se ela pegou)
  perform fazenda_cache_gravar(v_chave, v);
  return v;
end;
$$;


-- as tabelas mais regravadas: espaço livre em cada página (a regravação fica na mesma página, sem índice
-- novo) e limpeza automática bem mais frequente (a linha da sala é regravada a cada 2 s o dia todo)
alter table public.fazenda_cache set (fillfactor = 50, autovacuum_vacuum_scale_factor = 0, autovacuum_vacuum_threshold = 200,
                                      autovacuum_analyze_scale_factor = 0.05);
alter table public.fazenda_invasao set (fillfactor = 70, autovacuum_vacuum_scale_factor = 0.02, autovacuum_vacuum_threshold = 500);

revoke execute on function public.fazenda_invasao_sala(jsonb) from public, anon, authenticated;

-- conferência: a função nova (sem a gravação que fazia fila) e os ajustes das tabelas
select (select prosrc like '%fazenda_cache_gravar%' from pg_proc where proname = 'fazenda_invasao_sala') as sala_sem_fila,
       (select reloptions::text from pg_class where relname = 'fazenda_cache') as ajustes_cache;
