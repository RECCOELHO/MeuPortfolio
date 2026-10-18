-- ============================================================
-- FAZENDINHA — Fase 80 (produtos das oficinas valendo 3,2x a matéria-prima),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 79): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 79 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (public.fazenda_loja_diamantes() ? 'moedas') then
    raise exception 'Rode o fase79.sql antes deste (a fase 79 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 80: os produtos das oficinas valem 3,2x a matéria-prima (eram ~1,7x).
-- Preço = 3,2 x o valor dos ingredientes, para cima de 5 em 5. Repete até parar de mudar, porque
-- 7 produtos também são ingrediente (açúcar, café torrado, chocolate, fio, molho, óleo e tecido):
-- cada etapa da cadeia dá 3,2x sobre o preço novo do que entra. Só sobe, nunca desce; as
-- matérias-primas, os bichos e os raros não mudam.
-- ------------------------------------------------------------
do $$
declare
  n int;
begin
  for k in 1..8 loop
    update public.fazenda_culturas p set venda = x.novo
      from (select i.produz, (ceil(3.2 * sum(c.venda * e.value::int) / i.produz_qtd / 5) * 5)::int as novo
              from public.fazenda_itens i
              cross join lateral jsonb_each_text(i.entradas) e
              join public.fazenda_culturas c on c.id = e.key
             where i.entradas is not null
             group by i.produz, i.produz_qtd) x
     where p.id = x.produz and p.venda < x.novo;
    get diagnostics n = row_count;
    exit when n = 0;
  end loop;
end $$;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- conferência: deve aparecer "Fase 80: oficinas a 3,2x ou mais (menor razão 3.20), queijo 450"
select 'Fase 80: oficinas a 3,2x ou mais (menor razão ' || min(r) || '), queijo '
       || (select venda from public.fazenda_culturas where id = 'queijo') as ok
  from (select round(p.venda * i.produz_qtd / sum(c.venda * e.value::int)::numeric, 2) as r
          from public.fazenda_itens i
          cross join lateral jsonb_each_text(i.entradas) e
          join public.fazenda_culturas c on c.id = e.key
          join public.fazenda_culturas p on p.id = i.produz
         where i.entradas is not null
         group by i.produz, i.produz_qtd, p.venda) t;
