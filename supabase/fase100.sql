-- ============================================================
-- FAZENDINHA — Fase 100 (Invasão de Varginha: mais liberdade para melhorar as armas), só o que mudou.
-- Para o banco que já está no ar (com a fase 99): Supabase > SQL Editor > colar este arquivo > Run.
-- Pode rodar com o evento acontecendo. Não precisa de merge para valer (o jogo lê as regras do banco).
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 99 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_invasao_mult')) then
    raise exception 'Rode o fase99.sql antes deste (a fase 99 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 100: com a ameaça (fase 99) os ETs de quem pontua muito ficaram duros. Agora dá para ir mais longe:
--  * as armas sobem até o nível 60 (era 25);
--  * o preço de cada nível cresce bem mais devagar (forcado ×1,22 por nível, era ×1,6; espantalho ×1,3,
--    era ×1,7; trator ×1,32, era ×1,8; drone ×1,35, era ×2);
--  * o forcado elétrico dá +2 de dano por toque a cada nível (era +1); vale também para quem já comprou.
-- As automáticas continuam com o mesmo dano por nível (para não virar só quem tem mais ouro).
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------

create or replace function public.fazenda_invasao_regras(p_teste boolean default false)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'id', case when p_teste then 'varginha-teste' else 'varginha-2026' end, 'nome', 'Invasão de Varginha',
    'teste', p_teste,
    'inicio', case when p_teste then '2026-10-31 00:00:00-03' else '2026-11-01 15:00:00-03' end::timestamptz,
    'fim', case when p_teste then '2026-11-01 14:00:00-03' else '2026-11-02 00:00:00-03' end::timestamptz,
    'nivel_min', case when p_teste then 1 else 10 end,
    'toques_seg', 6, 'toques_max', 30,                 -- o saldo de toques: enche 6 por segundo, guarda até 30
    'intervalo', 1.2, 'vida', 9,                       -- um ET novo a cada 1,2 s; cada um fica 9 s na tela
    'hp_base', 4, 'hp_por_hora', 2,                    -- a cada hora os ETs aguentam mais
    -- fase 98: o chefão desce a cada 20 min (era 1 h); hp_chefe_por_hora agora soma a cada chefão (50 por chefão = 150 por hora, como antes)
    'chefe_a_cada', 1200, 'chefe_atraso', 30, 'vida_chefe', 120, 'hp_chefe', 400, 'hp_chefe_por_hora', 50,
    'bonus_abate', 2, 'bonus_chefe', 200,              -- pontos a mais por derrubar
    'auto_ativo_seg', 120, 'lote_max_seg', 5,
    -- fase 98: o ET dourado ("ainda tá aí?"): aparece só para você, num lugar sorteado, a cada 3 a 6 min
    -- (no teste dos admins: 45 s a 90 s). Tocou nele: +bonus_ouro. Não tocou no prazo: os seus toques e
    -- as armas automáticas param de valer até você tocar nele.
    'ouro_primeiro', case when p_teste then 20 else 90 end, 'ouro_min', case when p_teste then 45 else 180 end,
    'ouro_max', case when p_teste then 90 else 360 end, 'ouro_prazo', 15, 'bonus_ouro', 50,
    -- fase 99: a ameaça. A cada ameaca_pontos pontos SEUS, os ETs e o chefão aguentam +ameaca_passo da vida
    -- (1.000 pontos: ×1,5; 2.000: ×2; 10.000: ×6...), até ameaca_max. O bônus de derrubar sobe junto.
    'ameaca_pontos', 1000, 'ameaca_passo', 0.5, 'ameaca_max', 60,
    'premio', jsonb_build_object('diamantes', 40, 'moedas', 4000000, 'fator', 0.75, 'min_diamantes', 1, 'min_moedas', 1000),
    'armas', '[
      {"id": "forcado",    "nome": "Forcado elétrico",   "tipo": "toque", "efeito": 2,  "preco": 5000,   "fator": 1.22},
      {"id": "espantalho", "nome": "Espantalho-robô",    "tipo": "auto",  "efeito": 1,  "preco": 20000,  "fator": 1.3},
      {"id": "trator",     "nome": "Trator-canhão",      "tipo": "auto",  "efeito": 4,  "preco": 80000,  "fator": 1.32},
      {"id": "drone",      "nome": "Drone pulverizador", "tipo": "auto",  "efeito": 12, "preco": 250000, "fator": 1.35}
    ]'::jsonb,
    -- fase 100: as armas sobem até o nível 60 e o preço cresce mais devagar; o forcado dá +2 de dano por nível
    'arma_nivel_max', 60);
$$;


revoke execute on function public.fazenda_invasao_regras(boolean) from public, anon, authenticated;

-- conferência: o nível máximo e quanto custa o próximo nível do forcado no 10, no 20 e no 30
select (public.fazenda_invasao_regras()->>'arma_nivel_max')::int as nivel_max,
       public.fazenda_invasao_preco(public.fazenda_invasao_regras(), 'forcado', 10) as forcado_nv10,
       public.fazenda_invasao_preco(public.fazenda_invasao_regras(), 'forcado', 20) as forcado_nv20,
       public.fazenda_invasao_preco(public.fazenda_invasao_regras(), 'forcado', 30) as forcado_nv30;
