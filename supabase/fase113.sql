-- ============================================================
-- FAZENDINHA — Fase 113 ("Mais níveis" conta o nível do jogo; conta nova, do 10 em diante), só o que mudou.
-- Para o banco que já está no ar (com a fase 112): Supabase > SQL Editor > colar este arquivo > Run.
-- Pode rodar antes do merge do PR (o jogo só muda um texto).
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 112 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'fazenda_trava_dep_ins') then
    raise exception 'Rode o fase112.sql antes deste. Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 113: "Mais níveis" conta o nível que aparece no jogo (escolha do Jessé). Antes contava pelo XP: quem
-- estava preso no 45 com XP sobrando e subiu quando o máximo virou 60 (ou terminou o que faltava para
-- passar de nível) via o nível subir e o evento não contava.
-- • A foto da semana guarda o nível da tela (fazenda_semana_base.nivel); a conta é o nível da tela de agora
--   menos o da foto (fazenda_semana_placar). O XP comprado com diamantes continua fora (o nível de agora é
--   o do XP sem ele, com a trava).
-- • Conta nova (sem foto, entrou na semana) conta do nível 10 em diante: os primeiros níveis são rápidos.
-- • Esta semana já começou sem o nível na foto: ele é o nível que o XP da foto dá com a trava de hoje.
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------
alter table public.fazenda_semana_base add column if not exists nivel int;
update public.fazenda_semana_base b set nivel = public.fazenda_nivel_de(b.xp::int, j.nivel_trava)
  from public.fazenda_jogadores j
 where j.id = b.jogador_id and b.nivel is null;

-- as funções que mudaram

-- as categorias, os diamantes do 1º, 2º e 3º e os itens (o 1º leva o primeiro; no ranking, um por lugar)
-- Fase 64: diamantes pela metade (eram 60, 35 e 20) e o item vem com 50% de chance (chance_item), para
-- cada lugar do pódio; o 2º e o 3º fora do ranking, se sair, levam um material do píer (fazenda_raros)
create or replace function public.fazenda_evento_regras()
returns jsonb language sql immutable as $$
  select '{"fecha": "sexta às 22h", "diamantes": [30, 18, 10], "chance_item": 50, "convite_nivel": 10,
           "categorias": [
             {"id": "ranking",  "nome": "Ranking da semana",  "conta": "XP ganho na semana",            "itens": ["trofeu_ouro", "trofeu_prata", "trofeu_bronze"]},
             {"id": "niveis",   "nome": "Mais níveis",        "conta": "níveis subidos na semana (o nível do jogo; conta nova, do 10 em diante)", "itens": ["ampulheta_dourada"]},
             {"id": "moedas",   "nome": "Mais moedas",        "conta": "moedas ganhas na semana",       "itens": ["cofrinho_ouro"]},
             {"id": "vendeu",   "nome": "Vendeu na barraca",  "conta": "moedas em vendas na feira",     "itens": ["balanca_ouro"]},
             {"id": "comprou",  "nome": "Comprou na barraca", "conta": "moedas em compras na feira",    "itens": ["sacola_ouro"]},
             {"id": "convites", "nome": "Mais convites",      "conta": "amigos convidados que chegaram ao nível 10", "itens": ["leme_dourado"]}]}'::jsonb;
$$;


-- os números de cada jogador numa semana (p_semana = o início dela; conta de p_desde a p_ate).
-- Quem entrou na semana não tem foto: conta do zero. Quem foi banido não entra.
create or replace function public.fazenda_semana_placar(p_semana timestamptz, p_desde timestamptz, p_ate timestamptz)
returns table (jogador_id uuid, apelido text, avatar jsonb, criado_em timestamptz, ranking bigint, niveis bigint,
               moedas bigint, vendeu bigint, comprou bigint, convites bigint)
language sql stable security definer set search_path = public as $$
  -- fase 70: o XP comprado com diamante não conta (ranking e níveis); na barraca, uma mesma pessoa do
  -- outro lado conta no máximo 25% do total (duas contas vendendo uma para a outra não ganham sozinhas)
  select j.id, j.apelido, j.avatar, j.criado_em,
         (j.xp - coalesce(b.xp, 0) - (j.xp_pago - coalesce(b.xp_pago, 0)))::bigint,
         -- fase 113: o nível da tela (com a trava; o XP comprado continua fora) menos o da foto; quem entrou na
         -- semana não tem foto e conta do nível 10 em diante
         greatest(0, fazenda_nivel_de((j.xp - (j.xp_pago - coalesce(b.xp_pago, 0)))::int, j.nivel_trava)
                     - case when b.jogador_id is null then 10 else coalesce(b.nivel, fazenda_nivel_de(b.xp::int, j.nivel_trava)) end)::bigint,
         (j.moedas_ganhas - coalesce(b.moedas_ganhas, 0))::bigint,
         coalesce((select sum(least(t.v, ceil(t.total * 0.25))) from (
                    select sum(f.qtd::bigint * f.preco) as v, sum(sum(f.qtd::bigint * f.preco)) over () as total from fazenda_feira f
                     where f.vendedor_id = j.id and f.vendido_em >= p_desde and f.vendido_em < p_ate group by f.comprador_id) t), 0)::bigint,
         coalesce((select sum(least(t.v, ceil(t.total * 0.25))) from (
                    select sum(f.qtd::bigint * f.preco) as v, sum(sum(f.qtd::bigint * f.preco)) over () as total from fazenda_feira f
                     where f.comprador_id = j.id and f.vendido_em >= p_desde and f.vendido_em < p_ate group by f.vendedor_id) t), 0)::bigint,
         (select count(*) from fazenda_convites c join fazenda_jogadores a on a.id = c.convidado_id
           where c.dono_id = j.id and c.criado_em >= p_desde and c.criado_em < p_ate and a.banido_em is null
             and fazenda_nivel_de(a.xp, a.nivel_trava) >= (fazenda_evento_regras()->>'convite_nivel')::int)::bigint
    from fazenda_jogadores j
    left join fazenda_semana_base b on b.jogador_id = j.id and b.semana = p_semana
   where j.banido_em is null
     -- fase 71: só quem jogou na semana (visto_em, com 1 h de folga), vendeu ou comprou na feira ou trouxe
     -- convite nela: quem não jogou tem tudo zerado (e o placar de todos pesava no fechamento e no Evento)
     and (j.visto_em >= p_desde - interval '1 hour'
          or exists (select 1 from fazenda_feira f
                      where (f.vendedor_id = j.id or f.comprador_id = j.id) and f.vendido_em >= p_desde and f.vendido_em < p_ate)
          or exists (select 1 from fazenda_convites c where c.dono_id = j.id and c.criado_em >= p_desde and c.criado_em < p_ate));
$$;


-- Fecha a semana que acabou (premia o top 3 de cada categoria) e abre a nova (a foto de cada um).
-- Roda na primeira chamada depois da sexta 22h (fazenda_auth); a trava impede premiar duas vezes.
create or replace function public.fazenda_semana_fechar()
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_ini  timestamptz := fazenda_semana_inicio(now());
  v_reg  jsonb := fazenda_evento_regras();
  s      record;
  r      record;
  v_dia  int;
  v_item text;
  v_sorte int;   -- fase 64
begin
  if exists (select 1 from fazenda_semanas where inicio = v_ini) then return; end if;
  perform pg_advisory_xact_lock(hashtext('fazenda_semana'));
  if exists (select 1 from fazenda_semanas where inicio = v_ini) then return; end if;   -- outra chamada fechou antes
  -- a última semana aberta (normalmente a que acabou agora)
  select * into s from fazenda_semanas where fechada_em is null order by inicio desc limit 1;
  if found then
    for r in select * from fazenda_semana_posicoes(s.inicio, s.aberta_em, now()) p where p.posicao <= 3 loop
      v_dia := (v_reg->'diamantes'->>(r.posicao::int - 1))::int;
      select c->'itens'->>(r.posicao::int - 1) into v_item from jsonb_array_elements(v_reg->'categorias') c where c->>'id' = r.categoria;
      -- fase 64: o item vem com 50% de chance; sem item próprio do lugar, um material do píer (pesos do mercador)
      if random() * 100 >= coalesce((v_reg->>'chance_item')::int, 100) then
        v_item := null;
      elsif v_item is null then
        v_sorte := floor(random() * 100)::int;   -- (um sorteio só: random() no where sorteava de novo a cada linha)
        select y.r->>'id' into v_item
          from (select x.r, sum((x.r->>'peso')::int) over (order by x.ord) as acum
                  from jsonb_array_elements(fazenda_raros()) with ordinality as x(r, ord)) y
         where y.acum > v_sorte
         order by y.acum limit 1;
      end if;
      insert into fazenda_semana_premios (semana, categoria, posicao, jogador_id, valor, diamantes, item)
      values (s.inicio, r.categoria, r.posicao, r.jogador_id, r.valor, v_dia, v_item);
      update fazenda_jogadores set diamantes = diamantes + v_dia where id = r.jogador_id;
      if v_item is not null then
        insert into fazenda_celeiro (jogador_id, item, quantidade) values (r.jogador_id, v_item, 1)
        on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + 1;
      end if;
    end loop;
    update fazenda_semanas set fechada_em = now() where fechada_em is null;
  end if;
  -- a foto do começo da semana nova
  insert into fazenda_semana_base (jogador_id, semana, xp, moedas_ganhas, xp_pago, nivel)
  select id, v_ini, xp, moedas_ganhas, xp_pago, fazenda_nivel_de(xp, nivel_trava) from fazenda_jogadores
  on conflict (jogador_id) do update set semana = excluded.semana, xp = excluded.xp, moedas_ganhas = excluded.moedas_ganhas,
                                          xp_pago = excluded.xp_pago, nivel = excluded.nivel;   -- (fase 70; fase 113: o nível)
  insert into fazenda_semanas (inicio) values (v_ini);
end;
$$;


-- conferência: tem que aparecer "fase 113 ok" e o "Mais níveis" desta semana como está agora (os 5 primeiros)
with s as (select inicio, aberta_em from public.fazenda_semanas order by inicio desc limit 1)
select case when (select prosrc from pg_proc where proname = 'fazenda_semana_placar') like '%then 10 else%'
            then 'fase 113 ok' else 'não aplicou' end as resultado,
       (select string_agg(p.posicao || 'º ' || p.apelido || ' (' || p.valor || ')', ', ' order by p.posicao)
          from public.fazenda_semana_posicoes((select inicio from s), (select aberta_em from s), now()) p
         where p.categoria = 'niveis' and p.posicao <= 5) as mais_niveis_agora;
