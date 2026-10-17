-- ============================================================
-- FAZENDINHA — Fase 74 (o 31 ao 45, parte 2: peixes do mar, cabra e búfala, ajudantes 4 e 5, melhorias),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 73b): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 73b precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_mover' and pronargs = 6)) then
    raise exception 'Rode o fase73b.sql antes deste (a fase 73b não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 74: o que liberar do nível 31 ao 45 (parte 2).
-- • Oficinas dos peixes do mar: enlatados (33: sardinha em lata), sushi (39: sashimi) e caldeirada (42).
-- • Cabra (33) e búfala (38), com cercado e cuidador (Dona Zefa e Seu Badu); a queijaria de búfala (40)
--   faz mussarela com o leite dela.
-- • Ajudantes nos níveis 4 e 5 (o 4 pede o nível 35 do jogador; o 5, o 42): 150 e 240 tarefas por hora,
--   o eletricista −60% e −67%, o cuidador −40% e −50%; evoluir custa 16x e 32x o preço de contratar.
-- • Melhorias: adubo nível 4 (36), pomar fértil 3 (39) e mais pés 3 (41).
-- ------------------------------------------------------------
alter table public.fazenda_ajudantes drop constraint if exists fazenda_ajudantes_nivel_check;
alter table public.fazenda_ajudantes add constraint fazenda_ajudantes_nivel_check check (nivel between 1 and 5);

insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo) values
  ('leite_cabra',   'Leite de cabra',     '🥛', 1, 0,   120, 1,  14, 33, 112, 'produto'),
  ('leite_bufala',  'Leite de búfala',    '🥛', 1, 0,   220, 1,  22, 38, 113, 'produto'),
  ('mussarela',     'Mussarela de búfala','🧀', 1, 0,   750, 1,  75, 40, 114, 'produto'),
  ('sardinha_lata', 'Sardinha em lata',   '🥫', 1, 0,  2950, 1, 290, 33, 115, 'produto'),
  ('sashimi',       'Sashimi',            '🍣', 1, 0, 11000, 1, 900, 39, 116, 'produto'),
  ('caldeirada',    'Caldeirada',         '🍲', 1, 0,  6850, 1, 600, 42, 117, 'produto')
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, venda = excluded.venda, xp = excluded.xp,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem, tipo = excluded.tipo;
insert into public.fazenda_animais_tipos (id, nome, custo, nivel_min, maximo, produto, tempo_seg, racao, racao_qtd, ordem) values
  ('cabra',  'Cabra',  5000, 33, 5, 'leite_cabra',  14400, 'milho',   2, 7),
  ('bufala', 'Búfala', 8000, 38, 5, 'leite_bufala', 21600, 'abobora', 3, 8)
on conflict (id) do update set
  nome = excluded.nome, custo = excluded.custo, nivel_min = excluded.nivel_min, maximo = excluded.maximo,
  produto = excluded.produto, tempo_seg = excluded.tempo_seg, racao = excluded.racao,
  racao_qtd = excluded.racao_qtd, ordem = excluded.ordem;
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, largura, altura, efeito, limite, beleza, descricao) values
  ('cercado_cabra',  'Capril',             'bichos', 25000, 33, 106, 6, 4, 'cercado', 1, 4, 'Casa das cabras: precisa dela para comprar cabras, e elas moram aqui.'),
  ('cercado_bufala', 'Curral das búfalas', 'bichos', 35000, 38, 107, 7, 5, 'cercado', 1, 4, 'Curral com lama: precisa dele para comprar búfalas, e elas moram aqui.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, largura = excluded.largura, altura = excluded.altura, efeito = excluded.efeito,
  limite = excluded.limite, beleza = excluded.beleza, descricao = excluded.descricao;
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, largura, altura,
                                  produz, produz_seg, produz_qtd, entradas, limite, beleza, descricao) values
  ('enlatados',        'Enlatados',            'oficina', 150000, 33, 99, 2, 3, 'sardinha_lata', 5400, 1, '{"sardinha": 4, "oleo": 1}', 2, 5, '4 sardinhas + 1 óleo de girassol → sardinha em lata.'),
  ('queijaria_bufala', 'Queijaria de búfala',  'oficina', 200000, 40, 99, 2, 3, 'mussarela',     5400, 1, '{"leite_bufala": 2}', 2, 5, '2 leites de búfala → mussarela de búfala.'),
  ('sushiteria',       'Sushi',                'oficina', 200000, 39, 99, 2, 3, 'sashimi',       7200, 1, '{"atum": 1, "limao": 1}', 2, 5, '1 atum + 1 limão → sashimi.'),
  ('caldeiraria',      'Caldeirada',           'oficina', 250000, 42, 99, 2, 3, 'caldeirada',    7200, 1, '{"robalo": 1, "garoupa": 1, "tomate": 2}', 2, 5, '1 robalo + 1 garoupa + 2 tomates → caldeirada.')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, largura = excluded.largura, altura = excluded.altura, produz = excluded.produz,
  produz_seg = excluded.produz_seg, produz_qtd = excluded.produz_qtd, entradas = excluded.entradas,
  limite = excluded.limite, beleza = excluded.beleza, descricao = excluded.descricao;
insert into public.fazenda_ajudantes_tipos (id, nome, papel, funcao, alvo, custo, nivel_min, descricao, ordem) values
  ('cabreira',  'Dona Zefa', 'Cabreira',  'animal', 'cabra',  30000, 33, 'Dá a ração e tira o leite das cabras. Cada nível deixa os bichos dela mais rápidos: −10% por nível no tempo (soma com o feno).', 13),
  ('bufaleiro', 'Seu Badu',  'Bufaleiro', 'animal', 'bufala', 40000, 38, 'Dá a ração e tira o leite das búfalas. Cada nível deixa os bichos dele mais rápidos: −10% por nível no tempo (soma com o feno).', 14)
on conflict (id) do update set
  nome = excluded.nome, papel = excluded.papel, funcao = excluded.funcao, alvo = excluded.alvo,
  custo = excluded.custo, nivel_min = excluded.nivel_min, descricao = excluded.descricao, ordem = excluded.ordem;
-- os textos dos ajudantes com os níveis 4 e 5
update public.fazenda_ajudantes_tipos
   set descricao = replace(descricao, '−10%, −20% e −30% no tempo', '−10% por nível no tempo, até −50% no 5')
 where descricao like '%−10\%, −20\% e −30\%%';
update public.fazenda_ajudantes_tipos
   set descricao = 'Cuida das máquinas: tudo o que gasta energia gasta menos. Nível 1: −20%; 2: −35%; 3: metade; 4: −60%; 5: −67%.'
 where id = 'eletricista';

select public.fazenda_cache_montar();

-- as funções que já existiam e mudaram

-- Tarefas por hora de um ajudante em cada nível (fase 18: 12 / 30 / 90; antes 4 / 12 / 36)
create or replace function public.fazenda_ritmo(p_nivel int)
returns real language sql immutable as $$
  select (case p_nivel when 1 then 12 when 2 then 30 when 3 then 90 when 4 then 150 else 240 end)::real;   -- fase 74: níveis 4 e 5
$$;

-- Gasta energia se tiver o bastante (senão não gasta nada e devolve false)
-- Fase 43: quanto custa de verdade (o eletricista contratado baixa 20% / 35% / 50%)
-- Fase 56: tudo gasta menos; soma com o eletricista. Fase 57: 20% (0,8 de cada valor escrito nas
-- máquinas; a 56 tinha posto 40%, barato demais para valer a pena ter tudo). Em troca, painel solar e
-- turbina sobem de limite com o nível (fazenda_limite_maquina). As descrições mostram o valor novo.
create or replace function public.fazenda_energia_preco(p_jogador uuid, p_qtd real)
returns real language sql stable security definer set search_path = public as $$
  select (p_qtd * 0.8 * coalesce((select case h.nivel when 1 then 0.8 when 2 then 0.65 when 3 then 0.5 when 4 then 0.4 else 0.33 end   -- fase 74: 4 e 5
                              from fazenda_ajudantes h join fazenda_ajudantes_tipos t on t.id = h.tipo
                             where h.jogador_id = p_jogador and t.funcao = 'energia' limit 1), 1))::real;
$$;

-- Contrata um ajudante ou evolui o nível dele (fase 72: 4x e 8x o preço de contratar; eram 2x e 4x)
create or replace function public.fazenda_contratar(p_token text, p_tipo text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  j       record;
  t       record;
  v_nivel int;
  v_custo int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  select * into t from fazenda_ajudantes_tipos where id = p_tipo;
  if not found then raise exception 'item_invalido'; end if;
  if fazenda_nivel(j.xp) < t.nivel_min then raise exception 'nivel_insuficiente'; end if;
  perform fazenda_trabalhar(v_id);   -- fecha o trabalho no ritmo antigo antes de mudar
  perform fazenda_ajudantes_fechar(v_id, p_tipo);   -- (fase 46: quem não trabalhou também)
  select nivel into v_nivel from fazenda_ajudantes where jogador_id = v_id and tipo = p_tipo;
  -- fase 74: até o nível 5; o 4 pede o nível 35 do jogador e o 5, o 42 (igual a EVOLUIR_NIVEL em fazenda.js)
  if v_nivel >= 5 then raise exception 'nivel_maximo'; end if;
  if (v_nivel = 3 and fazenda_nivel(j.xp) < 35) or (v_nivel = 4 and fazenda_nivel(j.xp) < 42) then raise exception 'nivel_insuficiente'; end if;
  v_custo := t.custo * (array[1, 4, 8, 16, 32])[coalesce(v_nivel, 0) + 1];
  if j.moedas < v_custo then raise exception 'moedas_insuficientes'; end if;
  update fazenda_jogadores set moedas = moedas - v_custo where id = v_id;
  insert into fazenda_ajudantes (jogador_id, tipo) values (v_id, p_tipo)
  on conflict (jogador_id, tipo) do update set nivel = fazenda_ajudantes.nivel + 1;
  return jsonb_build_object('estado', fazenda_estado(v_id), 'nivel', coalesce(v_nivel, 0) + 1);
end;
$$;

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
            "niveis":[{"nivel":34,"custo":800000,"valor":2,"nome":"Traineira","intervalo":720,"max":24},
                      {"nivel":37,"custo":1800000,"valor":3,"nome":"Barco de pesca","intervalo":600,"max":32},
                      {"nivel":40,"custo":3600000,"valor":4,"nome":"Pesqueiro","intervalo":480,"max":40},
                      {"nivel":43,"custo":7000000,"valor":5,"nome":"Barco oceânico","intervalo":360,"max":48}]},
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
            "niveis":[{"nivel":33,"custo":400000,"valor":0.1,"nome":"Motor de popa","itens":{"ferro_forjado":1}},
                      {"nivel":39,"custo":1200000,"valor":0.2,"nome":"Motor a diesel","itens":{"ferro_forjado":2,"ancora":1}},
                      {"nivel":44,"custo":3000000,"valor":0.3,"nome":"Motor turbo","itens":{"ferro_forjado":3,"ancora":2,"perola_negra":1}}]},
           {"id":"sonar","nome":"Sonar","mar":true,"peca":true,"descricao":"Acha os cardumes de peixe grande e as ostras: mais peixe grande e mais pérola negra.",
            "niveis":[{"nivel":35,"custo":500000,"valor":1,"perola":150,"nome":"Sonar simples","itens":{"corda_naval":2}},
                      {"nivel":41,"custo":1600000,"valor":2,"perola":100,"nome":"Sonar colorido","itens":{"corda_naval":2,"perola_negra":1}},
                      {"nivel":45,"custo":4000000,"valor":3,"perola":70,"nome":"Sonar de varredura","itens":{"perola_negra":2,"marlim":1}}]},
           {"id":"porao","nome":"Porão","mar":true,"peca":true,"descricao":"Guarda o peixe no gelo: às vezes uma fisgada traz 2 peixes.",
            "niveis":[{"nivel":36,"custo":600000,"valor":0.15,"nome":"Caixa de gelo","itens":{"madeira_nobre":2}},
                      {"nivel":42,"custo":2000000,"valor":0.3,"nome":"Porão refrigerado","itens":{"madeira_nobre":3,"pedra_cantaria":2}},
                      {"nivel":45,"custo":5000000,"valor":0.45,"nome":"Câmara fria","itens":{"pedra_cantaria":2,"ferro_forjado":2,"perola_negra":1}}]},
           {"id":"rede","nome":"Rede de arrasto","mar":true,"peca":true,"descricao":"Para o marinheiro: ele pesca mais rápido (e o cesto continua guardando 8 horas).",
            "niveis":[{"nivel":37,"custo":600000,"valor":0.15,"nome":"Rede de arrasto","itens":{"corda_naval":2}},
                      {"nivel":43,"custo":2400000,"valor":0.3,"nome":"Rede dupla","itens":{"corda_naval":3,"ancora":1}}]},
           {"id":"expedicao","nome":"Kit de expedição","mar":true,"peca":true,"descricao":"Bússola, mapa e tanque extra: deixa o barco oceânico pronto para viajar às ilhas (nível 46, na próxima expansão).",
            "niveis":[{"nivel":45,"custo":6000000,"valor":1,"nome":"Kit de expedição","itens":{"perola_negra":3,"marlim":2,"ancora":2}}]}]'::jsonb;
$$;

-- permissões
revoke execute on function
  public.fazenda_ritmo(int),
  public.fazenda_energia_preco(uuid, real),
  public.fazenda_melhorias_tipos()
from public, anon, authenticated;

grant execute on function
  public.fazenda_contratar(text, text)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- conferência: deve aparecer "Fase 74: 4 oficinas, 2 bichos, 2 cuidadores; ajudantes até o nível 5"
select 'Fase 74: ' || (select count(*) from public.fazenda_itens where id in ('enlatados','queijaria_bufala','sushiteria','caldeiraria')) || ' oficinas, '
       || (select count(*) from public.fazenda_animais_tipos where id in ('cabra','bufala')) || ' bichos, '
       || (select count(*) from public.fazenda_ajudantes_tipos where id in ('cabreira','bufaleiro')) || ' cuidadores; ajudantes até o nível '
       || (case when public.fazenda_ritmo(5) = 240 then '5' else '3 (COM PROBLEMA)' end) as ok;
