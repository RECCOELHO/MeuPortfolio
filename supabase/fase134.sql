-- ============================================================
-- FAZENDINHA — Fase 134 (o nível que você tem não cai quando sai uma construção), só o que mudou.
-- Para o banco que já está no ar (com a fase 131): Supabase > SQL Editor > colar este arquivo > Run.
-- Pode rodar antes ou depois do merge do PR, e rodar de novo não muda nada. (O supabase/fazenda.sql inteiro já tem tudo isto.)
--
-- O que acontecia: para passar de nível, a fazenda precisa ter as construções daquele nível; quem já tinha o nível
-- ficava protegido pelo "piso" (nivel_base). Só que o piso só subia na PRIMEIRA vez que a pessoa chegava num nível
-- (quando ganhava o presente). Quem subiu de novo depois de cair (curva de XP nova, corte da fase 106...) ficou com
-- o piso lá atrás: o Pedruu tinha o piso no 31 e, quando a Queijaria saiu da fazenda, caiu do 60 para o 31.
-- • Agora, quando sai uma construção (ou algo do depósito), o nível que a pessoa tinha naquela hora vira o piso.
-- • E quem está abaixo do maior nível que já alcançou (e ganhou o presente) volta para ele, até onde o XP dá.
-- ============================================================

-- a fase anterior que mexeu no banco (131) está aplicada?
do $$
begin
  if not exists (select 1 from public.fazenda_culturas where id = 'viih' and tempo_seg = 1501) then
    raise exception 'Rode antes a fase 131 (supabase/fase131.sql). Nada foi mudado.';
  end if;
end $$;

-- a trava se refaz sozinha quando entra ou sai uma construção (ou algo do depósito). Fase 134: o nível de antes
-- da mudança vira o piso (as colunas do lado direito do SET são as de antes do UPDATE)
create or replace function public.fazenda_trava_gatilho()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    update fazenda_jogadores j
       set nivel_base = greatest(coalesce(j.nivel_base, 1), fazenda_nivel_de(j.xp, j.nivel_trava)),
           nivel_trava = greatest(fazenda_nivel_trava(j.id), coalesce(j.nivel_base, 1), fazenda_nivel_de(j.xp, j.nivel_trava))
     where j.id in (select distinct jogador_id from velhas)
       and j.nivel_trava is distinct from greatest(fazenda_nivel_trava(j.id), coalesce(j.nivel_base, 1), fazenda_nivel_de(j.xp, j.nivel_trava));
  else
    update fazenda_jogadores j
       set nivel_base = greatest(coalesce(j.nivel_base, 1), fazenda_nivel_de(j.xp, j.nivel_trava)),
           nivel_trava = greatest(fazenda_nivel_trava(j.id), coalesce(j.nivel_base, 1), fazenda_nivel_de(j.xp, j.nivel_trava))
     where j.id in (select distinct jogador_id from novas)
       and j.nivel_trava is distinct from greatest(fazenda_nivel_trava(j.id), coalesce(j.nivel_base, 1), fazenda_nivel_de(j.xp, j.nivel_trava));
  end if;
  return null;
end;
$$;

-- quem está abaixo do maior nível que já alcançou volta para ele (até onde o XP dá); o piso de todo mundo vira
-- pelo menos o nível de agora. Só sobe: ninguém perde nada.
drop table if exists fase134_antes;
create temp table fase134_antes as
  select id, apelido, public.fazenda_nivel_de(xp, nivel_trava) as nivel_antes from public.fazenda_jogadores;
update public.fazenda_jogadores j
   set nivel_base = greatest(coalesce(j.nivel_base, 1), public.fazenda_nivel_de(j.xp, j.nivel_trava),
                             least(coalesce(j.nivel_premiado, 1), public.fazenda_nivel(j.xp), 60))
 where greatest(coalesce(j.nivel_base, 1), public.fazenda_nivel_de(j.xp, j.nivel_trava),
                least(coalesce(j.nivel_premiado, 1), public.fazenda_nivel(j.xp), 60)) > coalesce(j.nivel_base, 1);
update public.fazenda_jogadores
   set nivel_trava = greatest(nivel_trava, public.fazenda_nivel_trava(id), coalesce(nivel_base, 1))
 where greatest(nivel_trava, public.fazenda_nivel_trava(id), coalesce(nivel_base, 1)) > nivel_trava;

-- conferência: quem voltou de nível agora (se a lista vier vazia, ninguém estava abaixo)
select a.apelido, a.nivel_antes, public.fazenda_nivel_de(j.xp, j.nivel_trava) as nivel_agora, 'fase 134 ok' as status
  from fase134_antes a join public.fazenda_jogadores j on j.id = a.id
 where public.fazenda_nivel_de(j.xp, j.nivel_trava) <> a.nivel_antes
union all
select null, null, null, 'fase 134 ok'
 order by 3 desc nulls last;
