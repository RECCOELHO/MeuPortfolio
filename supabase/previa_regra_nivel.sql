-- ============================================================
-- PRÉVIA da regra nova de nível (SÓ LEITURA: não muda nada no banco).
-- Supabase > SQL Editor > colar > Run. Mostra, para cada jogador, para onde ele iria com a regra:
-- "só passa do nível N quem tem na fazenda tudo o que conta do nível N" (oficinas, cercados,
-- máquinas, energia sem o cano e pomar; enfeites, caminhos, objetos, casas e praia não contam).
-- O XP não muda. Itens de nível acima do novo sairiam da fazenda e as moedas pagas voltariam.
-- ============================================================
with conta as (   -- o que conta para passar de nível
  select id, nome, nivel_min from fazenda_itens
   where categoria in ('oficina', 'bichos', 'maquina', 'energia', 'pomar') and id <> 'cano' and nivel_min < 45
),
jog as (
  select j.id, j.apelido, j.xp, fazenda_nivel(j.xp) as nivel_xp,
         coalesce((select min(c.nivel_min) from conta c
                    where not exists (select 1 from fazenda_construcoes f where f.jogador_id = j.id and f.tipo = c.id)), 45) as trava
    from fazenda_jogadores j
   where j.banido_em is null
),
novo as (
  select jog.*, least(nivel_xp, trava) as nivel_novo from jog
),
sai as (   -- construções de nível acima do novo
  select n.id, count(*) as itens, sum(coalesce(f.pago, i.custo)) as moedas,
         string_agg(i.nome, ', ' order by i.nivel_min) as quais
    from novo n join fazenda_construcoes f on f.jogador_id = n.id join fazenda_itens i on i.id = f.tipo
   where i.nivel_min > n.nivel_novo
   group by n.id
),
bichos as (   -- bichos de tipo acima do nível novo
  select n.id, count(*) as bichos, sum(t.custo) as moedas
    from novo n join fazenda_animais a on a.jogador_id = n.id join fazenda_animais_tipos t on t.id = a.tipo
   where t.nivel_min > n.nivel_novo
   group by n.id
)
select n.apelido,
       n.nivel_xp as nivel_agora,
       n.nivel_novo,
       n.nivel_xp - n.nivel_novo as cai,
       case when n.nivel_novo < n.nivel_xp then
         (select string_agg(c.nome, ', ') from conta c
           where c.nivel_min = n.nivel_novo
             and not exists (select 1 from fazenda_construcoes f where f.jogador_id = n.id and f.tipo = c.id)) end as falta_para_subir,
       coalesce(s.itens, 0) as itens_que_saem,
       s.quais as quais_saem,
       coalesce(b.bichos, 0) as bichos_que_saem,
       coalesce(s.moedas, 0) + coalesce(b.moedas, 0) as moedas_devolvidas
  from novo n left join sai s on s.id = n.id left join bichos b on b.id = n.id
 order by n.nivel_xp - n.nivel_novo desc, n.nivel_xp desc;
