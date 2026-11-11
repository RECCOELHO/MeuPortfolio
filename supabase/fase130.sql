-- fase 130: o Dia dos Namorados da Fazendinha muda de 11/11 para 25/01.
-- • fazenda_estado passa a devolver dia_especial = 'namorados' em 25/01 (pétalas, coração do farol, constelação, painel).
-- • A Viih (so_dia) só pode ser plantada em 25/01; as outras funções já leem a coluna so_dia.
-- Aplicado direto no banco em 11/11/2026, reaproveitando o corpo da função que estava no ar.
do $$
declare d text;
begin
  d := pg_get_functiondef('public.fazenda_estado(uuid)'::regprocedure);
  if position('''11-11''' in d) > 0 then
    execute replace(d, '''11-11''', '''01-25''');
  end if;
  update public.fazenda_culturas set so_dia = '01-25' where id = 'viih';
end $$;
