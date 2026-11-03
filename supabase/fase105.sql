-- ============================================================
-- FAZENDINHA — Fase 105 (a pescaria com a barra, como no Stardew, e o peixe do mar valendo no mínimo 5 mil),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 104): Supabase > SQL Editor > colar este arquivo > Run.
-- Rode ANTES do merge do PR.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 104 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from public.fazenda_culturas where id = 'carta_nautica')) then
    raise exception 'Rode o fase104.sql antes deste. Nada foi mudado.';
  end if;
end $$;

-- as regras da pescaria: 1 pérola a cada 200 peixes; a mordida vem de 1,5 a 5 s depois de lançar;
-- fisgar até 0,3 s antes da mordida conta (relógio), e a folga de 2,5 s depois da janela é a internet
create or replace function public.fazenda_mar_regras()
returns jsonb language sql immutable as $$
  -- fase 105: jogo_ms = o tempo do joguinho da fisgada (a barra), que vem depois da mordida
  select '{"perola": 200, "mordida_min": 1500, "mordida_max": 5000, "cedo_ms": 300, "folga_ms": 2500, "jogo_ms": 40000}'::jsonb;
$$;


-- Fisga: vale da mordida até o fim da janela (com a folga da internet). Antes ou depois, o peixe
-- foge (não é erro: o lance acaba do mesmo jeito). O jogo só chama quando o toque foi na janela.
create or replace function public.fazenda_mar_fisgar(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  v_g  jsonb := fazenda_mar_regras();
  l    record;
  v_xp int;
  v_qtd int;   -- fase 65: o porão às vezes traz 2
begin
  perform 1 from fazenda_jogadores where id = v_id for update;
  delete from fazenda_mar_lances where jogador_id = v_id returning * into l;
  if not found then raise exception 'sem_lance'; end if;
  if now() < l.mordida_em - make_interval(secs => (v_g->>'cedo_ms')::int / 1000.0) then
    return jsonb_build_object('pegou', false, 'motivo', 'cedo', 'mar', fazenda_mar_estado(v_id));
  end if;
  -- fase 105: depois de fisgar, o jogo da barra (até jogo_ms) decide; só então o jogo chama aqui
  if now() > l.mordida_em + make_interval(secs => (l.janela_ms + (v_g->>'folga_ms')::int + coalesce((v_g->>'jogo_ms')::int, 0)) / 1000.0) then
    return jsonb_build_object('pegou', false, 'motivo', 'tarde', 'mar', fazenda_mar_estado(v_id));
  end if;
  v_qtd := case when random() < fazenda_melhoria(v_id, 'porao') then 2 else 1 end;   -- fase 65: o porão
  insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, l.peixe, v_qtd)
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  if l.perola then
    insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, 'perola_negra', 1)
    on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
  end if;
  select xp * v_qtd into v_xp from fazenda_culturas where id = l.peixe;
  update fazenda_jogadores set xp = xp + v_xp where id = v_id;
  insert into fazenda_estatisticas (jogador_id) values (v_id) on conflict do nothing;
  update fazenda_estatisticas set peixes_mar = peixes_mar + v_qtd, marlins = marlins + (l.peixe = 'marlim')::int * v_qtd
   where jogador_id = v_id;
  perform fazenda_missao(v_id, 'colher', v_qtd);
  return jsonb_build_object('pegou', true, 'peixe', l.peixe, 'qtd', v_qtd, 'perola', l.perola, 'xp', v_xp, 'estado', fazenda_estado(v_id));
end;
$$;


-- ------------------------------------------------------------
-- Fase 105: a pescaria do alto-mar vira um joguinho (como no Stardew Valley) e o peixe do mar vale mais.
-- • Depois que o peixe morde e você fisga, abre a barra: segure (ou toque no ritmo) para subir a zona
--   verde e mantenha o peixe dentro dela até encher a barra de captura. Peixe maior foge mais rápido;
--   vara melhor dá zona maior. O jogo da barra roda no aparelho; o servidor aceita a fisgada até jogo_ms
--   depois da janela (fazenda_mar_regras, fazenda_mar_fisgar).
-- • Peixe do mar vale no mínimo 5 mil: sardinha 5.000, cavala 5.600, robalo 6.200, garoupa 7.000,
--   dourado-do-mar 8.000, atum 9.500 (o marlim continua 30 mil).
-- • Os pratos de peixe valem o triplo do que custam os ingredientes: sardinha em lata 60.780, sashimi
--   28.542, caldeirada 39.690.
-- • A forja não usa mais sardinha em lata (ficaria caríssima): 4 toras + 2 óleos → 6 cravos (cravo: 490).
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------
update public.fazenda_culturas c set venda = v.venda, xp = v.xp
  from (values ('sardinha', 5000, 40), ('cavala', 5600, 60), ('robalo', 6200, 90), ('garoupa', 7000, 130),
               ('dourado_mar', 8000, 180), ('atum', 9500, 260),
               ('sardinha_lata', 60780, 1200), ('sashimi', 28542, 900), ('caldeirada', 39690, 1100),
               ('cravo', 490, 49)) v(id, venda, xp)
 where c.id = v.id;
update public.fazenda_itens set entradas = '{"tora": 4, "oleo": 2}'::jsonb,
       descricao = '4 toras (o carvão) + 2 óleos (a têmpera) → 6 cravos de ferro.'
 where id = 'forja';

select public.fazenda_cache_montar();

-- conferência: tem que aparecer "fase 105 ok" e a sardinha valendo 5000
select case when public.fazenda_mar_regras() ? 'jogo_ms' then 'fase 105 ok' else 'não aplicou' end as resultado,
       (select venda from public.fazenda_culturas where id = 'sardinha') as sardinha;
