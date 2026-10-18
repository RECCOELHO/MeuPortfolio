-- ============================================================
-- FAZENDINHA — Fase 74b (vender produtos numa chamada só e baú sem moedas),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 74): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 74 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_ritmo' and prosrc like '%240%')) then
    raise exception 'Rode o fase74.sql antes deste (a fase 74 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 74b: vender produtos numa chamada só (fazenda_vender ganhou p_itens; a assinatura antiga sai).
-- ------------------------------------------------------------
drop function if exists public.fazenda_vender(text, text, int);

-- as funções que já existiam e mudaram

-- p_quantidade null = vende tudo daquele item. p_item null = vende o celeiro todo.
-- fase 74b: p_itens vende vários de uma vez (o "vender produtos" chamava uma vez por produto, cada uma
-- com a fazenda inteira de volta: 15 produtos travavam o jogo uns 5 s)
create or replace function public.fazenda_vender(p_token text, p_item text default null, p_quantidade int default null,
                                                 p_itens text[] default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  r       record;
  v_qtd   int;
  v_ganho int := 0;
  v_valor numeric := 0;   -- valor que conta para o XP (sem o bônus de beleza)
  v_xp    int;
  v_feira int;
  v_sem_xp int := 0;      -- fase 56: quantos itens comprados na feira foram vendidos (sem XP)
begin
  if p_quantidade is not null and p_quantidade <= 0 then
    raise exception 'quantidade_invalida';
  end if;

  -- o que está reservado para os animais fica no celeiro
  for r in
    select ce.item, ce.quantidade - coalesce(rs.quantidade, 0) as livre, ce.da_feira, k.venda, k.tipo, k.nivel_min
      from fazenda_celeiro ce
      join fazenda_culturas k on k.id = ce.item
      left join fazenda_reservas rs on rs.jogador_id = ce.jogador_id and rs.item = ce.item
     where ce.jogador_id = v_id
       and ce.quantidade > coalesce(rs.quantidade, 0)
       and (p_item is null or ce.item = p_item)
       and (p_itens is null or ce.item = any(p_itens))   -- fase 74b
       and k.tipo <> 'raro'   -- fase 60: material raro só vende na feira
       for update of ce
  loop
    v_qtd := least(coalesce(p_quantidade, r.livre), r.livre);
    -- fase 56: o que veio da feira sai primeiro e não dá XP (comprar na feira para revender ao
    -- jogo virava XP comprado com moedas); as moedas da venda são as de sempre
    v_feira := least(v_qtd, r.da_feira);
    update fazenda_celeiro set quantidade = quantidade - v_qtd, da_feira = da_feira - v_feira
     where jogador_id = v_id and item = r.item;
    v_ganho := v_ganho + v_qtd * r.venda;
    -- XP da venda: só os produtos (oficinas, bichos, lago, pomar); a planta já deu XP na colheita (fase 41)
    v_valor := v_valor + case when r.tipo <> 'cultura' then (v_qtd - v_feira) * r.venda else 0 end;
    v_sem_xp := v_sem_xp + case when r.tipo <> 'cultura' then v_feira else 0 end;
  end loop;

  v_ganho := (v_ganho * (100 + fazenda_bonus_venda(v_id))) / 100;   -- beleza e caixote
  -- 1 XP a cada 25 moedas do valor; o que sobra fica para a próxima venda
  select floor((venda_resto + v_valor) / 25)::int into v_xp from fazenda_jogadores where id = v_id;
  update fazenda_jogadores
     set moedas = moedas + v_ganho, xp = xp + v_xp, venda_resto = venda_resto + v_valor - v_xp * 25
   where id = v_id;
  if v_ganho > 0 then
    perform fazenda_missao(v_id, 'vender', v_ganho);
  end if;

  return jsonb_build_object('ganho', v_ganho, 'xp', v_xp, 'sem_xp', v_sem_xp, 'estado', fazenda_estado(v_id));
end;
$$;

-- os baús da sorte: preço, nível e as chances (raro, o prêmio grande, diamantes, itens; o resto é moeda)
create or replace function public.fazenda_baus_sorte()
returns jsonb language sql immutable as $$
  -- fase 74b: o baú nunca devolve moedas (sem o prêmio de moedas e o grande): só itens, diamantes e raro
  select '{"madeira": {"nome": "Baú de madeira", "preco": 50000,   "nivel": 20, "raro": 0.004, "diamantes": [5, 10],  "chance_diamantes": 0.08},
           "prata":   {"nome": "Baú de prata",   "preco": 250000,  "nivel": 25, "raro": 0.015, "diamantes": [15, 30], "chance_diamantes": 0.08},
           "ouro":    {"nome": "Baú de ouro",    "preco": 1000000, "nivel": 30, "raro": 0.05,  "diamantes": [40, 80], "chance_diamantes": 0.08}}'::jsonb;
$$;

-- abre um baú da sorte: paga, sorteia e entrega. Os prêmios (fase 74b: nunca moedas):
--   raro (o mais caro, mais difícil: peso 1 / preço) · diamantes · e o resto, itens que o seu nível já tem
--   (de 15% a 75% do preço, pelo preço do celeiro)
create or replace function public.fazenda_abrir_bau_sorte(p_token text, p_tipo text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_b     jsonb := fazenda_baus_sorte() -> p_tipo;
  j       record;
  k       record;
  v_preco int;
  v_r     double precision := random();
  v_lim   double precision;
  v_moeda int := 0;
  v_diam  int := 0;
  v_item  text;
  v_qtd   int := 0;
  v_tipo  text;
begin
  if v_b is null then raise exception 'item_invalido'; end if;
  select * into j from fazenda_jogadores where id = v_id for update;
  if fazenda_nivel(j.xp) < (v_b->>'nivel')::int then raise exception 'nivel_insuficiente'; end if;
  v_preco := (v_b->>'preco')::int;
  if j.moedas < v_preco then raise exception 'moedas_insuficientes'; end if;

  -- as faixas do sorteio, uma depois da outra (raro, grande, diamantes, itens; o resto é moeda)
  v_lim := (v_b->>'raro')::float8;
  if v_r < v_lim then
    v_tipo := 'raro';
    select c.id into v_item from fazenda_culturas c
     where c.tipo = 'raro' and c.venda > 0
     order by -ln(greatest(random(), 1e-12)) * c.venda limit 1;   -- sorteio com peso 1 / preço
    v_qtd := 1;
  elsif v_r < v_lim + (v_b->>'chance_diamantes')::float8 then
    v_tipo := 'diamantes';
    v_diam := (v_b->'diamantes'->>0)::int + floor(random() * ((v_b->'diamantes'->>1)::int - (v_b->'diamantes'->>0)::int + 1))::int;
  else
    v_tipo := 'itens';
    select c.* into k from fazenda_culturas c
     where c.tipo in ('cultura', 'produto') and c.venda > 0 and c.nivel_min <= fazenda_nivel(j.xp)
     order by random() limit 1;
    v_item := k.id;
    v_qtd := greatest(1, round(v_preco * (0.15 + random() * 0.6) / k.venda))::int;
  end if;

  -- o que veio do baú não conta como moeda ganha no evento (o gatilho soma o que entra)
  update fazenda_jogadores
     set moedas = moedas - v_preco + v_moeda, diamantes = diamantes + v_diam,
         moedas_ganhas = moedas_ganhas - greatest(v_moeda - v_preco, 0)
   where id = v_id;
  if v_item is not null then   -- e vendido no celeiro dá as moedas, mas não o XP (como o da feira)
    insert into fazenda_celeiro (jogador_id, item, quantidade, da_feira) values (v_id, v_item, v_qtd, v_qtd)
    on conflict (jogador_id, item) do update
      set quantidade = fazenda_celeiro.quantidade + excluded.quantidade, da_feira = fazenda_celeiro.da_feira + excluded.da_feira;
  end if;
  insert into fazenda_baus_abertos (jogador_id, tipo, preco, premio, item, qtd, moedas, diamantes)
  values (v_id, p_tipo, v_preco, v_tipo, v_item, v_qtd, v_moeda, v_diam);
  return jsonb_build_object('premio', jsonb_build_object('tipo', v_tipo, 'item', v_item, 'qtd', v_qtd, 'moedas', v_moeda, 'diamantes', v_diam),
                            'preco', v_preco, 'estado', fazenda_estado(v_id));
end;
$$;

-- permissões
revoke execute on function
  public.fazenda_vender(text, text, int, text[]),
  public.fazenda_baus_sorte()
from public, anon, authenticated;

grant execute on function
  public.fazenda_vender(text, text, int, text[]),
  public.fazenda_abrir_bau_sorte(text, text)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- conferência: deve aparecer "Fase 74b: vender em lote pronto; baú sem moedas"
select 'Fase 74b: vender em lote ' || case when exists (select 1 from pg_proc where proname = 'fazenda_vender' and pronargs = 4) and not exists (select 1 from pg_proc where proname = 'fazenda_vender' and pronargs = 3) then 'pronto' else 'COM PROBLEMA' end
       || case when public.fazenda_baus_sorte()->'madeira' ? 'grande' then '; baú AINDA COM MOEDAS' else '; baú sem moedas' end as ok;
