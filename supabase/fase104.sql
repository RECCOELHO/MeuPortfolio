-- ============================================================
-- FAZENDINHA — Fase 104 (o barco até o 45 montado com tábuas, cravos, velas e cartas: ipê e 4 oficinas navais),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 103): Supabase > SQL Editor > colar este arquivo > Run.
-- Rode ANTES do merge do PR.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 103 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_pegar_um' and prosrc like '%fase 103%')) then
    raise exception 'Rode o fase103.sql antes deste. Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 104: o barco até o 45 é montado com materiais de verdade (o navio da viagem às ilhas).
-- • Ipê-amarelo (pomar, 32): dá toras de ipê, a madeira do barco.
-- • Quatro oficinas navais: serraria naval (33: tábua naval), forja (36: cravo de ferro), velaria (39:
--   vela de navio) e cartografia (42: carta náutica). Contam para passar de nível, como as outras.
-- • Os níveis do barco (traineira, barco de pesca, pesqueiro e o navio oceânico, que era "barco oceânico")
--   e as peças (motor, sonar, porão, rede e o kit de expedição) pedem tábuas, cravos, velas e cartas,
--   além do que já pediam (fazenda_melhorias_tipos). Quem já comprou, fica com o que tem.
-- • No nível 46 (na próxima parte), o navio com o kit zarpa para a primeira ilha.
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------
insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('tora',          'Tora de ipê',     '🪵', 1, 0,  300, 1,  30, 32, 112, 'produto'),
  ('tabua_naval',   'Tábua naval',     '🪵', 1, 0,  490, 1,  49, 33, 113, 'produto'),
  ('cravo',         'Cravo de ferro',  '🔩', 1, 0, 1940, 1, 190, 36, 114, 'produto'),
  ('vela',          'Vela de navio',   '⛵', 1, 0, 6220, 1, 620, 39, 115, 'produto'),
  ('carta_nautica', 'Carta náutica',   '🗺️', 1, 0, 1380, 1, 138, 42, 116, 'produto')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, venda = excluded.venda, xp = excluded.xp,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;

insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, beleza, produz, produz_seg, produz_qtd, por_terreno, grupo, descricao) values
  ('ipe', 'Ipê-amarelo', 'pomar', 30000, 32, 122, 4, 'tora', 43200, 6, 1, null,
   'Dá 6 toras de ipê a cada 12 horas: toque nele para colher. É a madeira do barco. Pomar: 1 pé de cada árvore, +1 a cada 2 terrenos (até 4).')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min, ordem = excluded.ordem,
  beleza = excluded.beleza, produz = excluded.produz, produz_seg = excluded.produz_seg, produz_qtd = excluded.produz_qtd,
  por_terreno = excluded.por_terreno, grupo = excluded.grupo, descricao = excluded.descricao;

insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, largura, altura,
                                  produz, produz_seg, produz_qtd, entradas, limite, beleza, descricao) values
  ('serraria_naval', 'Serraria naval', 'oficina', 160000, 33, 99, 2, 3, 'tabua_naval',   14400, 3, '{"tora": 2, "oleo": 1}', 2, 5, '2 toras de ipê + 1 óleo → 3 tábuas navais.'),
  ('forja',          'Forja',          'oficina', 200000, 36, 99, 2, 3, 'cravo',         18000, 6, '{"tora": 3, "sardinha_lata": 1}', 2, 5, '3 toras (o carvão) + 1 sardinha em lata (o ferro da lata) → 6 cravos de ferro.'),
  ('velaria',        'Velaria',        'oficina', 240000, 39, 99, 2, 3, 'vela',          10800, 1, '{"tecido": 2, "fio": 3}', 2, 5, '2 tecidos + 3 fios → 1 vela de navio.'),
  ('cartografia',    'Cartografia',    'oficina', 280000, 42, 99, 2, 3, 'carta_nautica', 10800, 1, '{"acai": 6, "algodao": 6}', 2, 5, '6 açaís (a tinta) + 6 algodões (o papel) → 1 carta náutica.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, largura = excluded.largura, altura = excluded.altura, produz = excluded.produz,
  produz_seg = excluded.produz_seg, produz_qtd = excluded.produz_qtd, entradas = excluded.entradas,
  limite = excluded.limite, beleza = excluded.beleza, descricao = excluded.descricao;

-- as melhorias (o barco e as peças pedem os materiais novos)

-- o catálogo (o jogo mostra o que vem daqui). valor: adubo e pomar = fração adiantada; pes = pés a mais
-- fase 62: barco, vara e marinheiro são do alto-mar (mar = só com o píer; aparecem na tela do barco, não
-- na loja). base = o que vem com o píer; intervalo/max = o cardume do barco (ou o cesto do marinheiro),
-- em segundos e peixes; janela = o tempo de fisgar da vara, em milésimos de segundo
-- fase 65: a tunagem do barco (peca = true): motor, sonar, porão, rede e o kit de expedição. Cada nível
-- pede moedas e materiais raros (itens); o efeito entra em fazenda_mar_item, na pescaria e no marinheiro
create or replace function public.fazenda_melhorias_tipos()
returns jsonb language sql immutable as $$
  -- fase 72: tudo 2x mais caro (o dinheiro do nível 20 em diante estava sobrando)
  select '[{"id":"adubo","nome":"Adubo premium","descricao":"As plantas nascem adiantadas: crescem 10%, 20%, 30% e 40% mais rápido (soma com o girassol e a estufa).",
            "niveis":[{"nivel":23,"custo":100000,"valor":0.1},{"nivel":26,"custo":300000,"valor":0.2},{"nivel":29,"custo":600000,"valor":0.3},{"nivel":36,"custo":1200000,"valor":0.4}]},
           {"id":"pomar","nome":"Pomar fértil","descricao":"As árvores do pomar dão frutas 15%, 30% e 45% mais rápido.",
            "niveis":[{"nivel":24,"custo":160000,"valor":0.15},{"nivel":28,"custo":400000,"valor":0.3},{"nivel":39,"custo":1000000,"valor":0.45}]},
           {"id":"pes","nome":"Mais pés de fruta","descricao":"Mais 1, 2 e 3 pés de cada fruta no pomar, além dos 4 que os terrenos dão.",
            "niveis":[{"nivel":25,"custo":120000,"valor":1},{"nivel":30,"custo":240000,"valor":2},{"nivel":41,"custo":600000,"valor":3}]},
           {"id":"barco","nome":"Barco","mar":true,"descricao":"Barco maior vai mais longe: o cardume é maior, enche mais rápido e tem peixe que o bote não alcança.",
            "base":{"nome":"Bote","valor":1,"intervalo":900,"max":16},
            "niveis":[{"nivel":34,"custo":800000,"valor":2,"nome":"Traineira","intervalo":720,"max":24,"itens":{"tabua_naval":10,"tora":10}},
                      {"nivel":37,"custo":1800000,"valor":3,"nome":"Barco de pesca","intervalo":600,"max":32,"itens":{"tabua_naval":20,"cravo":10}},
                      {"nivel":40,"custo":3600000,"valor":4,"nome":"Pesqueiro","intervalo":480,"max":40,"itens":{"tabua_naval":30,"cravo":20,"vela":2}},
                      {"nivel":43,"custo":7000000,"valor":5,"nome":"Navio oceânico","intervalo":360,"max":48,"itens":{"tabua_naval":40,"cravo":30,"vela":4,"carta_nautica":2}}]},
           {"id":"vara","nome":"Vara","mar":true,"descricao":"Vara melhor dá mais tempo para fisgar e puxa peixe maior.",
            "base":{"nome":"Vara de bambu","valor":1,"janela":900},
            "niveis":[{"nivel":32,"custo":300000,"valor":2,"nome":"Vara de fibra","janela":1100},
                      {"nivel":35,"custo":800000,"valor":3,"nome":"Molinete","janela":1300},
                      {"nivel":38,"custo":1800000,"valor":4,"nome":"Carretilha","janela":1500},
                      {"nivel":41,"custo":4000000,"valor":5,"nome":"Vara profissional","janela":1800}]},
           {"id":"marinheiro","nome":"Marinheiro","mar":true,"descricao":"O Seu Nonato pesca sozinho enquanto você cuida da fazenda: o cesto dele enche por até 8 horas. Cada nível pesca mais rápido.",
            "niveis":[{"nivel":33,"custo":500000,"valor":1,"nome":"Seu Nonato","intervalo":1800,"max":16},
                      {"nivel":36,"custo":1400000,"valor":2,"nome":"Seu Nonato com rede","intervalo":1200,"max":24},
                      {"nivel":39,"custo":3600000,"valor":3,"nome":"Seu Nonato com barco de apoio","intervalo":720,"max":40}]},
           {"id":"motor","nome":"Motor","mar":true,"peca":true,"descricao":"Motor mais forte vai e volta mais rápido: o cardume enche mais rápido.",
            "niveis":[{"nivel":33,"custo":400000,"valor":0.1,"nome":"Motor de popa","itens":{"ferro_forjado":1,"tabua_naval":5}},
                      {"nivel":39,"custo":1200000,"valor":0.2,"nome":"Motor a diesel","itens":{"ferro_forjado":2,"ancora":1,"cravo":10}},
                      {"nivel":44,"custo":3000000,"valor":0.3,"nome":"Motor turbo","itens":{"ferro_forjado":3,"ancora":2,"perola_negra":1,"cravo":20}}]},
           {"id":"sonar","nome":"Sonar","mar":true,"peca":true,"descricao":"Acha os cardumes de peixe grande e as ostras: mais peixe grande e mais pérola negra.",
            "niveis":[{"nivel":35,"custo":500000,"valor":1,"perola":150,"nome":"Sonar simples","itens":{"corda_naval":2}},
                      {"nivel":41,"custo":1600000,"valor":2,"perola":100,"nome":"Sonar colorido","itens":{"corda_naval":2,"perola_negra":1}},
                      {"nivel":45,"custo":4000000,"valor":3,"perola":70,"nome":"Sonar de varredura","itens":{"perola_negra":2,"marlim":1,"carta_nautica":2}}]},
           {"id":"porao","nome":"Porão","mar":true,"peca":true,"descricao":"Guarda o peixe no gelo: às vezes uma fisgada traz 2 peixes.",
            "niveis":[{"nivel":36,"custo":600000,"valor":0.15,"nome":"Caixa de gelo","itens":{"madeira_nobre":2,"tabua_naval":10}},
                      {"nivel":42,"custo":2000000,"valor":0.3,"nome":"Porão refrigerado","itens":{"madeira_nobre":3,"pedra_cantaria":2,"cravo":10}},
                      {"nivel":45,"custo":5000000,"valor":0.45,"nome":"Câmara fria","itens":{"pedra_cantaria":2,"ferro_forjado":2,"perola_negra":1,"cravo":15}}]},
           {"id":"rede","nome":"Rede de arrasto","mar":true,"peca":true,"descricao":"Para o marinheiro: ele pesca mais rápido (e o cesto continua guardando 8 horas).",
            "niveis":[{"nivel":37,"custo":600000,"valor":0.15,"nome":"Rede de arrasto","itens":{"corda_naval":2,"tabua_naval":5}},
                      {"nivel":43,"custo":2400000,"valor":0.3,"nome":"Rede dupla","itens":{"corda_naval":3,"ancora":1,"vela":1}}]},
           {"id":"expedicao","nome":"Kit de expedição","mar":true,"peca":true,"descricao":"Bússola, cartas náuticas e tanque extra: deixa o navio oceânico pronto para zarpar para as ilhas (nível 46, na próxima expansão).",
            "niveis":[{"nivel":45,"custo":6000000,"valor":1,"nome":"Kit de expedição","itens":{"perola_negra":3,"marlim":2,"ancora":2,"carta_nautica":4,"vela":2}}]},
           {"id":"turno","nome":"Turno de 12 horas","diamante":true,"descricao":"Os ajudantes trabalham 12 horas com a barra de energia cheia (eram 8) e guardam até 12 horas de trabalho com a fazenda fechada.",
            "niveis":[{"nivel":5,"custo":0,"diamantes":150,"valor":12,"texto":"12 h de trabalho"}]},
           {"id":"cesto_bira","nome":"Cesto grande do Bira","diamante":true,"descricao":"O cesto do Bira no lago guarda 50% mais peixe: 24 em vez de 16 (enche por 12 horas).",
            "niveis":[{"nivel":1,"custo":0,"diamantes":80,"valor":0.5,"texto":"24 peixes"}]},
           {"id":"cesto_nonato","nome":"Cesto grande do Seu Nonato","diamante":true,"descricao":"O cesto do marinheiro no alto-mar guarda 50% mais peixe.",
            "niveis":[{"nivel":33,"custo":0,"diamantes":80,"valor":0.5,"texto":"+50% no cesto"}]},
           {"id":"fila","nome":"Fila de 15 receitas","diamante":true,"descricao":"Cada oficina guarda até 15 receitas no estoque (eram 10): trabalha mais tempo sozinha.",
            "niveis":[{"nivel":3,"custo":0,"diamantes":100,"valor":15,"texto":"15 receitas"}]},
           {"id":"barraca","nome":"Mais barracas na feira","diamante":true,"descricao":"Depois das 4 barracas compradas com moedas, a 5ª e a 6ª: cada uma dá mais 2 anúncios na feira.",
            "niveis":[{"nivel":5,"custo":0,"diamantes":100,"valor":5,"texto":"5ª barraca"},{"nivel":5,"custo":0,"diamantes":150,"valor":6,"texto":"6ª barraca"}]}]'::jsonb;
$$;


-- fase 104: a trava de cada um com os itens novos (ipê e as 4 oficinas contam para passar de nível)
update public.fazenda_jogadores set nivel_trava = greatest(public.fazenda_nivel_trava(id), coalesce(nivel_base, 1))
 where nivel_trava is distinct from greatest(public.fazenda_nivel_trava(id), coalesce(nivel_base, 1));

select public.fazenda_cache_montar();

-- conferência: tem que aparecer "fase 104 ok" e os 5 materiais novos
select case when (select count(*) from public.fazenda_culturas where id in ('tora', 'tabua_naval', 'cravo', 'vela', 'carta_nautica')) = 5
             and public.fazenda_melhorias_tipos()::text like '%carta_nautica%' then 'fase 104 ok' else 'não aplicou' end as resultado;
