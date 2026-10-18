-- ============================================================
-- FAZENDINHA — Fase 78b (o texto da pequena central hidrelétrica),
-- só o que mudou. Precisa da fase 78.
-- Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================
do $$ begin
  if not exists (select 1 from public.fazenda_itens where id = 'hidreletrica') then
    raise exception 'Rode antes o supabase/fase78.sql';
  end if;
end $$;

-- a descrição falava de "riacho", mas a usina vai em qualquer lugar: ela vem com o próprio tanque d'água
update public.fazenda_itens set descricao = 'Uma rodinha d''água com o próprio tanque: vai em qualquer lugar da fazenda, sem precisar de rio nem de lago. 120 ⚡/h sem parar, de dia e de noite (80 na onda de calor, com menos água). Tempestade e furacão não estragam. Até 1, mais 1 no nível 23 e no 27.' where id = 'hidreletrica';

-- conferência: deve aparecer "Fase 78b: a usina vai em qualquer lugar"
select case when descricao like '%qualquer lugar%' then 'Fase 78b: a usina vai em qualquer lugar' else 'não mudou' end as ok
  from public.fazenda_itens where id = 'hidreletrica';
