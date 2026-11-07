-- ============================================================
-- FAZENDINHA — prêmio extra do "Mais níveis" da semana que fechou na sexta (06/11), pela regra nova
-- (o nível do jogo; conta nova, do 10 em diante): Pedruu ficaria em 1º (15 níveis) e Chico em 3º (12).
-- EMANUEL já levou o 2º. Ninguém perde o que já ganhou.
--   • Pedruu: 30 diamantes + 1 ampulheta dourada (o prêmio do 1º)
--   • Chico:  10 diamantes + 1 material do píer, sorteado como no fechamento (o prêmio do 3º)
-- Rodar UMA vez (Supabase > SQL Editor > Run). Rodar de novo não paga de novo (fica no log do admin).
-- ============================================================
do $$
declare
  v_pedruu uuid;
  v_chico  uuid;
  v_item   text;
  v_sorte  int := floor(random() * 100)::int;
begin
  if exists (select 1 from public.fazenda_admin_log where acao = 'premio_niveis_0611') then
    raise notice 'Já foi pago antes. Nada mudou.';
    return;
  end if;
  select id into v_pedruu from public.fazenda_jogadores where apelido = 'Pedruu';
  select id into v_chico  from public.fazenda_jogadores where apelido = 'Chico';
  if v_pedruu is null or v_chico is null
     or (select count(*) from public.fazenda_jogadores where apelido in ('Pedruu', 'Chico')) <> 2 then
    raise exception 'Não achei o Pedruu e o Chico (um de cada). Nada foi mudado.';
  end if;
  -- 1º: 30 diamantes e a ampulheta dourada
  update public.fazenda_jogadores set diamantes = diamantes + 30 where id = v_pedruu;
  insert into public.fazenda_celeiro (jogador_id, item, quantidade) values (v_pedruu, 'ampulheta_dourada', 1)
  on conflict (jogador_id, item) do update set quantidade = public.fazenda_celeiro.quantidade + 1;
  -- 3º: 10 diamantes e um material do píer (os pesos do mercador)
  select y.r->>'id' into v_item
    from (select x.r, sum((x.r->>'peso')::int) over (order by x.ord) as acum
            from jsonb_array_elements(public.fazenda_raros()) with ordinality as x(r, ord)) y
   where y.acum > v_sorte order by y.acum limit 1;
  update public.fazenda_jogadores set diamantes = diamantes + 10 where id = v_chico;
  if v_item is not null then
    insert into public.fazenda_celeiro (jogador_id, item, quantidade) values (v_chico, v_item, 1)
    on conflict (jogador_id, item) do update set quantidade = public.fazenda_celeiro.quantidade + 1;
  end if;
  insert into public.fazenda_admin_log (admin_id, alvo_id, acao, motivo) values
    (null, v_pedruu, 'premio_niveis_0611', 'Mais níveis da semana de 06/11 pela regra nova: 1º (30 diamantes + ampulheta dourada)'),
    (null, v_chico,  'premio_niveis_0611', 'Mais níveis da semana de 06/11 pela regra nova: 3º (10 diamantes + ' || coalesce(v_item, 'sem item') || ')');
end $$;

-- conferência: tem que aparecer as duas linhas (quem recebeu e o quê)
select j.apelido, l.motivo, to_char(l.em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as quando
  from public.fazenda_admin_log l join public.fazenda_jogadores j on j.id = l.alvo_id
 where l.acao = 'premio_niveis_0611' order by l.id;
