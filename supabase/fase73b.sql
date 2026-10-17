-- ============================================================
-- FAZENDINHA — Fase 73b (mover sem travar),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 73): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 73 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_abrir_bau_sorte')) then
    raise exception 'Rode o fase73.sql antes deste (a fase 73 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 73b: mover sem travar. fazenda_mover(..., p_leve) devolve só {ok, x, y}: o jogo já põe o item
-- no lugar na hora, e a fazenda inteira de volta a cada movimento (com o jogo refazendo tudo) travava
-- quem movia várias oficinas seguidas. Sem p_leve, devolve como antes.
-- ------------------------------------------------------------
drop function if exists public.fazenda_mover(text, int, int, int, int);

-- as funções que já existiam e mudaram

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
    perform fazenda_checar_lugar(v_id, j.zonas, p_nx, p_ny, 1, 1, null, null, v_pos);
    update fazenda_canteiros set x = p_nx, y = p_ny where jogador_id = v_id and posicao = v_pos;
    if p_leve then return jsonb_build_object('ok', true, 'x', p_nx, 'y', p_ny); end if;
    return jsonb_build_object('estado', fazenda_estado(v_id));
  end if;

  select k.* into i from fazenda_construcoes c join fazenda_itens k on k.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y;
  if not found then raise exception 'item_invalido'; end if;
  perform fazenda_checar_lugar(v_id, j.zonas, p_nx, p_ny, i.largura, i.altura, p_x, p_y);
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

-- permissões
revoke execute on function
  public.fazenda_mover(text, int, int, int, int, boolean)
from public, anon, authenticated;

grant execute on function
  public.fazenda_mover(text, int, int, int, int, boolean)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- conferência: deve aparecer "Fase 73b: mover leve pronto"
select 'Fase 73b: mover leve ' || case when exists (select 1 from pg_proc where proname = 'fazenda_mover' and pronargs = 6) and not exists (select 1 from pg_proc where proname = 'fazenda_mover' and pronargs = 5) then 'pronto' else 'COM PROBLEMA' end as ok;
