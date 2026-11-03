-- ============================================================
-- FAZENDINHA — Fase 103 (a luva do Perks leva a muda inteira), só o que mudou.
-- Para o banco que já está no ar (com a fase 101): Supabase > SQL Editor > colar este arquivo > Run.
-- Rode ANTES do merge do PR.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 101 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_invasao_agendar')) then
    raise exception 'Rode o fase101.sql antes deste. Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 103: visitando um vizinho, a luva do Perks (que passa pelo alarme) não pega mais 2 ou 3: leva
-- a muda inteira, o mesmo que o dono colheria (menos os problemas e o que já pegaram, mais o adubo do
-- Seu Zé), e o canteiro dele fica arado. A cerca não segura a luva. Sem luva, nada muda.
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------

-- Pega colheita de um canteiro do vizinho. Retorna a quantidade pega.
-- fase 66: p_luva = pode gastar 1 luva do Perks para passar pelo alarme (só gasta no canteiro protegido)
-- fase 103: com a luva, leva a muda inteira (o que o dono colheria) e o canteiro do vizinho fica arado
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
  if c.roubado >= (case when v_luva then k.rendimento else fazenda_limite_roubo(k.rendimento) end) then
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

  if v_luva then
    -- fase 103: a muda inteira, o mesmo que o dono colheria agora (a cerca não segura a luva)
    v_qtd := greatest(k.rendimento - (c.erva::int + c.praga::int + c.seco::int) - c.roubado, 1) + c.adubado::int;
    update fazenda_canteiros set estado = 'arado', cultura = null, plantado_em = null,
           erva = false, praga = false, seco = false, roubado = 0, prox_evento = null, adubado = false
     where jogador_id = p_dono and posicao = p_posicao;
  else
    v_qtd := least(2 + (random() < 0.4)::int, fazenda_limite_roubo(k.rendimento) - c.roubado);
    if fazenda_protegido(p_dono, 'cerca', c.x, c.y) then
      v_qtd := least(v_qtd, 1);   -- cerca ou placa por perto
    end if;
    update fazenda_canteiros set roubado = roubado + v_qtd
     where jogador_id = p_dono and posicao = p_posicao;
  end if;
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

-- conferência: tem que aparecer "fase 103 ok"
select case when prosrc like '%fase 103%' then 'fase 103 ok' else 'não aplicou' end as resultado
  from pg_proc where proname = 'fazenda_pegar_um';
