-- ============================================================
-- FAZENDINHA — Fase 96 (a tela dos itens especiais: a pérola negra também dá para usar), só o que mudou.
-- Para o banco que já está no ar (com a fase 95): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 95 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_guardar')) then
    raise exception 'Rode o fase95.sql antes deste (a fase 95 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 96: a tela dos itens especiais (🎒 Itens, no menu). Junta num lugar só os itens raros que você tem:
-- os que dá para usar (os prêmios do evento e, agora, a pérola negra) com o botão Usar, e os materiais
-- (peças do píer e do barco, a luva do Perks) com para que servem e o atalho para a feira.
-- A pérola negra passa a ter uso: 12 h de +50% na colheita (o mesmo bônus da balança de ouro, pela
-- metade do tempo). Ela continua servindo nas melhorias e na pintura do barco.
-- ------------------------------------------------------------
create or replace function public.fazenda_premios_efeitos()
returns jsonb language sql immutable as $$
  select '{"trofeu_ouro": {"xp2": 24, "crescer": 24}, "trofeu_prata": {"xp2": 24}, "trofeu_bronze": {"xp2": 12},
           "ampulheta_dourada": {"crescer": 24}, "cofrinho_ouro": {"venda": 24}, "balanca_ouro": {"colheita": 24},
           "sacola_ouro": {"cafe": 24}, "perola_negra": {"colheita": 12}}'::jsonb;
$$;

-- refaz os catálogos prontos (fazenda_cache)
select public.fazenda_cache_montar();

-- conferência: a pérola negra no que dá para usar
select public.fazenda_premios_efeitos()->'perola_negra' as perola_negra_usar;
