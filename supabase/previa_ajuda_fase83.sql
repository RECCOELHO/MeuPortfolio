-- ============================================================
-- FAZENDINHA — prévia para a votação: quem mais ganhou XP ajudando os vizinhos desde a fase 83
-- (18/10 às 23:41 UTC, 20:41 de Brasília). SÓ LEITURA: não muda nada no banco.
-- Supabase > SQL Editor > colar > Run.
--
-- O XP de cada ajuda só passou a ser guardado na fase 85, então "xp_estimado" é uma conta aproximada:
-- as ajudas (plantar valia 5, salvar 3) vezes o prêmio do nível de AGORA, sem sequência, abandonada nem
-- XP em dobro. Serve para comparar quem usou muito com quem usou pouco, não como valor exato.
-- ============================================================
select j.apelido,
       fazenda_nivel(j.xp) as nivel_agora,
       sum(v.qtd + case when v.tipo = 'plantar' then 4 else 0 end) as ajudas,
       count(distinct v.dono_id) as fazendas_ajudadas,
       count(*) filter (where v.tipo = 'plantar') as plantou,
       count(*) filter (where v.tipo = 'colher')  as colheu,
       count(*) filter (where v.tipo = 'arar')    as arou,
       count(*) filter (where v.tipo = 'limpar')  as limpou,
       count(*) filter (where v.tipo = 'ajuda')   as cuidou,
       count(*) filter (where v.tipo in ('bicho', 'coleta')) as bichos,
       sum(v.qtd + case when v.tipo = 'plantar' then 4 else 0 end) * fazenda_premio_ajuda(j.id) as xp_estimado,
       fazenda_xp_nivel(fazenda_nivel(j.xp) + 1) - fazenda_xp_nivel(fazenda_nivel(j.xp)) as xp_de_1_nivel_agora,
       min(v.criado_em) as primeira, max(v.criado_em) as ultima
  from fazenda_visitas v
  join fazenda_jogadores j on j.id = v.ator_id
 where v.criado_em >= '2026-10-18 23:41:00+00' and v.tipo <> 'roubo'
 group by j.id, j.apelido, j.xp
 order by ajudas desc
 limit 30;
