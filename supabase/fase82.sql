-- ============================================================
-- FAZENDINHA — Fase 82 (oficina nível 2 e 3 e as melhorias de diamante),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 81): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 81 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_luzes_noite')) then
    raise exception 'Rode o fase81.sql antes deste (a fase 81 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 82: oficina nível 2 e 3 e as melhorias de diamante.
-- • B10: cada tipo de oficina sobe para o nível 2 (100 mil) e o 3 (400 mil): a receita fica 15% e 30%
--   mais rápida (fazenda_oficina_nivel, fazenda_comprar categoria 'oficina').
-- • D8, na Loja → Melhorias, pagas com diamante (fazenda_melhorias_tipos, "diamante": true):
--   turno de 12 h dos ajudantes (150), cesto do Bira +50% (80), cesto do Seu Nonato +50% (80),
--   fila de 15 receitas nas oficinas (100) e a 5ª e a 6ª barraca da feira (100 e 150).
-- ------------------------------------------------------------

-- (a tabela também fica lá em cima, antes de fazenda_oficina_rapidez, para o fazenda.sql do zero)
create table if not exists public.fazenda_oficina_nivel (
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  tipo       text not null,
  nivel      smallint not null default 1 check (nivel between 1 and 3),
  primary key (jogador_id, tipo)
);
alter table public.fazenda_oficina_nivel enable row level security;
revoke all on public.fazenda_oficina_nivel from anon, authenticated;

-- as funções que já existiam e mudaram

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
            "niveis":[{"nivel":45,"custo":6000000,"valor":1,"nome":"Kit de expedição","itens":{"perola_negra":3,"marlim":2,"ancora":2}}]},
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

-- fase 82: as melhorias de diamante (D8) e a oficina nível 2 e 3 (B10)
-- quantas receitas cabem no estoque de cada oficina (10; 15 com a fila de diamante)
create or replace function public.fazenda_estoque_max_de(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select greatest(fazenda_estoque_max(), fazenda_melhoria(p_jogador, 'fila')::int);
$$;

-- quantos peixes cabem no cesto do Bira (16; 24 com o cesto grande), 1 a cada 30 min
create or replace function public.fazenda_cesto_max(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select round(16 * (1 + fazenda_melhoria(p_jogador, 'cesto_bira')))::int;
$$;

-- quantas horas o ajudante trabalha com a barra cheia e guarda com a fazenda fechada (8; 12 com o turno)
create or replace function public.fazenda_turno(p_jogador uuid)
returns real language sql stable security definer set search_path = public as $$
  select greatest(8, fazenda_melhoria(p_jogador, 'turno'));
$$;

-- os níveis 2 e 3: preço e quanto a receita fica mais rápida
create or replace function public.fazenda_oficina_niveis()
returns jsonb language sql immutable as $$
  select '[{"nivel": 2, "custo": 100000, "rapidez": 0.15}, {"nivel": 3, "custo": 400000, "rapidez": 0.3}]'::jsonb;
$$;

-- quanto mais rápida fica a receita desse tipo de oficina (0, 0.15 ou 0.3)
create or replace function public.fazenda_oficina_rapidez(p_jogador uuid, p_tipo text)
returns real language sql stable security definer set search_path = public as $$
  select coalesce((select (fazenda_oficina_niveis()->(n.nivel - 2)->>'rapidez')::real
                     from fazenda_oficina_nivel n where n.jogador_id = p_jogador and n.tipo = p_tipo and n.nivel >= 2), 0)::real;
$$;

create or replace function public.fazenda_estado(p_jogador uuid)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  j       record;
  v_nivel int;
  v_max   int;
  v_json  jsonb;
  v_ener  real;
  v_prev  jsonb := fazenda_previsao_agora();   -- fase 71: a previsão do clima e do vento, pronta (uma por minuto)
  v_clima jsonb := v_prev->'clima';
  v_metas jsonb;
  v_bonus int;
begin
  perform fazenda_checar_conquistas(p_jogador);
  select * into j from fazenda_jogadores where id = p_jogador;
  if j.convite is null then   -- (quem nasceu entre o SQL e o deploy)
    update fazenda_jogadores set convite = fazenda_novo_convite() where id = p_jogador;
    select * into j from fazenda_jogadores where id = p_jogador;
  end if;
  if j.zonas >= 3 and j.lago_em is null then   -- comprou o Vale do sudeste: o Bira começa a pescar
    update fazenda_jogadores set lago_em = now() where id = p_jogador;
    select * into j from fazenda_jogadores where id = p_jogador;
  end if;
  -- fase 62: com o píer pronto, o cardume do alto-mar começa cheio; o marinheiro, ao ser contratado
  if (j.pier_em is not null and j.mar_em is null)
     or (j.marinheiro_em is null and exists (select 1 from fazenda_melhorias where jogador_id = p_jogador and id = 'marinheiro')) then
    update fazenda_jogadores
       set mar_em = coalesce(mar_em, now() - make_interval(secs => (fazenda_mar_item(p_jogador, 'barco')->>'max')::int
                                                              * (fazenda_mar_item(p_jogador, 'barco')->>'intervalo')::int)),
           marinheiro_em = case when exists (select 1 from fazenda_melhorias where jogador_id = p_jogador and id = 'marinheiro')
                                then coalesce(marinheiro_em, now()) end
     where id = p_jogador;
    select * into j from fazenda_jogadores where id = p_jogador;
  end if;
  v_nivel := fazenda_nivel(j.xp);
  -- subiu de nível: presente de moedas e 5 diamantes por cada nível novo
  if v_nivel > coalesce(j.nivel_premiado, 1) then
    update fazenda_jogadores
       set moedas = moedas + (select sum(fazenda_presente_nivel(n)) from generate_series(coalesce(j.nivel_premiado, 1) + 1, v_nivel) n),
           diamantes = diamantes + 5 * (v_nivel - coalesce(j.nivel_premiado, 1)),
           nivel_premiado = v_nivel
     where id = p_jogador and nivel_premiado is not distinct from j.nivel_premiado;   -- fase 70: paga uma vez só
    select * into j from fazenda_jogadores where id = p_jogador;
  end if;
  -- canteiros não aparecem mais sozinhos: o jogador coloca no modo construir até este limite
  v_max := fazenda_limite_canteiros(v_nivel, fazenda_terrenos(j.zonas, j.direita));
  -- fase 49: as metas de nível; com todas em dia, o bônus de XP vale neste nível (só grava se mudou)
  v_metas := fazenda_metas(p_jogador, v_nivel);
  -- (fase 62: até o 44; era até o 29, quando o 30 era o último nível)
  v_bonus := case when v_nivel < 45 and not exists (select 1 from jsonb_array_elements(v_metas) m where not (m->>'feito')::boolean)
                  then v_nivel end;
  if v_bonus is distinct from j.bonus_nivel then
    update fazenda_jogadores set bonus_nivel = v_bonus where id = p_jogador;
  end if;
  v_ener := fazenda_energia_atualizar(p_jogador);

  perform fazenda_gerar_missoes(p_jogador);

  v_json := jsonb_build_object(
    'agora', now(),
    'jogador', jsonb_build_object(
      'id', j.id,
      'apelido', j.apelido,
      'avatar', j.avatar,
      'avatares', j.avatares,
      'avatar_precos', fazenda_avatar_precos(),
      'avatar_diamantes', fazenda_avatar_diamantes(),
      'avatar_exclusivos', fazenda_avatar_exclusivos(),   -- fase 69
      'cercado_gratis', coalesce(j.cercado_gratis, '{}'),   -- fase 45: espécies com o primeiro cercado de graça
      'moedas', j.moedas,
      'diamantes', j.diamantes,
      -- fase 43: o que os diamantes ligaram (até quando) e quantos pacotes de XP saíram hoje
      'xp2_ate', case when j.xp2_ate > now() then j.xp2_ate end,
      'cafe_ate', case when j.cafe_ate > now() then j.cafe_ate end,
      'xp_compras_hoje', fazenda_diamantes_hoje(p_jogador, 'xp'),
      -- conta Google ligada (só aparece para o dono; null = não ligada)
      'google', case when j.google_sub is not null then coalesce(j.google_email, 'sua conta Google') end,
      'admin', j.admin,   -- fase 53: 'dono', 'admin' ou null
      'xp', j.xp,
      'nivel', v_nivel,
      'xp_nivel', fazenda_xp_nivel(v_nivel),
      'xp_proximo', fazenda_xp_nivel(v_nivel + 1),
      'bonus_nivel', v_bonus,   -- fase 49: +50% de XP neste nível (metas em dia)
      'max_canteiros', v_max,
      'max_construcoes', fazenda_max_construcoes(fazenda_terrenos(j.zonas, j.direita)),
      'zonas', j.zonas,
      'direita', j.direita,   -- fase 78: os terrenos da direita
      'beleza', fazenda_beleza(p_jogador),
      'bonus_venda', fazenda_bonus_venda(p_jogador)
    ),
    'zonas_venda', fazenda_zonas(),
    'pacotes_diamantes', fazenda_pacotes_diamantes(),
    'loja_diamantes', fazenda_loja_diamantes(),
    'baus_sorte', fazenda_baus_sorte(),   -- fase 73
    -- fase 50: a feira (os seus anúncios abertos e o que vendeu desde a última olhada)
    'feira', jsonb_build_object(
      'regras', fazenda_feira_regras(),
      'limite', fazenda_feira_limite(p_jogador),   -- fase 51: 2 por barraca
      'barracas', (select barracas from fazenda_jogadores where id = p_jogador),
      'vendidos', coalesce((select jsonb_agg(v order by (v->>'em') desc) from (
                    select jsonb_build_object('item', f.item, 'qtd', f.qtd, 'total', f.qtd * f.preco,
                             'comprador', c.apelido, 'em', f.vendido_em) as v
                      from fazenda_feira f left join fazenda_jogadores c on c.id = f.comprador_id
                     where f.vendedor_id = p_jogador and f.vendido_em > now() - interval '7 days'
                     order by f.vendido_em desc limit 10) x), '[]'::jsonb),
      'meus', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'item', f.item, 'qtd', f.qtd, 'preco', f.preco,
                          'ate', f.criado_em + make_interval(hours => (fazenda_feira_regras()->>'horas')::int),
                          -- fase 67: separado para quem pediu no chat
                          'para', case when f.reservado_ate > now() then r.apelido end,
                          'reservado_ate', case when f.reservado_ate > now() then f.reservado_ate end) order by f.id)
                          from fazenda_feira f left join fazenda_jogadores r on r.id = f.reservado_para
                         where f.vendedor_id = p_jogador and f.vendido_em is null), '[]'::jsonb),
      'vendas_novas', coalesce((select jsonb_agg(jsonb_build_object('item', f.item, 'qtd', f.qtd, 'total', f.qtd * f.preco,
                          'recebeu', f.qtd * f.preco - ceil(f.qtd * f.preco * (fazenda_feira_regras()->>'taxa')::int / 100.0)::int,
                          'comprador', c.apelido) order by f.vendido_em)
                          from fazenda_feira f left join fazenda_jogadores c on c.id = f.comprador_id
                         where f.vendedor_id = p_jogador and f.vendido_em is not null and not f.visto), '[]'::jsonb)),
    'metas', v_metas,
    -- fase 39: o que está em cada baú, o que já chegou pelo cano em cada oficina e as viagens
    -- dos últimos 2 minutos (o jogo desenha o item andando só enquanto ela acontece)
    'baus', coalesce((select jsonb_object_agg(b.x || ',' || b.y, b.itens) from (
        select x, y, jsonb_object_agg(item, quantidade) as itens from fazenda_bau_itens
         where jogador_id = p_jogador and quantidade > 0 group by x, y) b), '{}'::jsonb),
    'oficina_itens', coalesce((select jsonb_object_agg(o.x || ',' || o.y, o.itens) from (
        select x, y, jsonb_object_agg(item, quantidade) as itens from fazenda_oficina_itens
         where jogador_id = p_jogador and quantidade > 0 group by x, y) o), '{}'::jsonb),
    'viagens', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'item', v.item, 'qtd', v.qtd,
        'de', case when v.de_x is null then null else jsonb_build_array(v.de_x, v.de_y) end,
        'para', case when v.para_x is null then null else jsonb_build_array(v.para_x, v.para_y) end,
        'direto', v.direto, 'em', v.em) order by v.em)
        -- fase 44: as criadas nos últimos 2 minutos (o jogo anima cada uma quando recebe, item por
        -- item; antes eram as com hora marcada nos últimos 2 min, e a entrega de uma receita que
        -- terminou antes ficava de fora)
        from (select * from fazenda_viagens where jogador_id = p_jogador and criada_em > now() - interval '2 minutes'
               order by criada_em desc, id desc limit 300) v), '[]'::jsonb),
    'galinheiro', jsonb_build_object('linhas', fazenda_galinheiro_linhas(p_jogador), 'quer', fazenda_galinheiro_quer(p_jogador),
                                     'pasto', fazenda_pasto(p_jogador)),   -- fase 45: o pasto do começo ainda existe?
    'visitante', fazenda_visitante(p_jogador),
    -- o lago (só com o terreno 3): desde quando o cesto enche, o ritmo, o máximo e as chances
    'lago', case when j.zonas >= 3 then jsonb_build_object(
      'desde', j.lago_em, 'intervalo', 1800, 'max', fazenda_cesto_max(p_jogador),
      'estatua', fazenda_tem_efeito(p_jogador, 'chico'),
      'peixes', (select jsonb_agg(jsonb_build_object('id', peixe, 'chance', chance))
                   from fazenda_peixes(fazenda_tem_efeito(p_jogador, 'chico')))) end,
    'convites', jsonb_build_object(
      'codigo', j.convite,
      'premio', fazenda_premio_convite(),
      'total', (select count(*) from fazenda_convites where dono_id = p_jogador),
      'novos', coalesce((
        select jsonb_agg(jsonb_build_object('apelido', a.apelido, 'premiado', c.premiado) order by c.criado_em)
          from fazenda_convites c join fazenda_jogadores a on a.id = c.convidado_id
         where c.dono_id = p_jogador and not c.visto), '[]'::jsonb)),
    -- energia agora, quanto cabe e quanto entra por hora (sol/vento/reator + biomassa ligada)
    'energia', jsonb_build_object(
      'carga', round(v_ener::numeric, 1),
      'calmo', fazenda_vento_calmo(now()),   -- fase 48: sem vento agora (a turbina quase para)
      'vento', v_prev->'vento',
      'capacidade', fazenda_capacidade(p_jogador),
      'conta', fazenda_energia_conta(p_jogador),   -- fase 75: quanto gera e quanto gasta, por hora
      'por_hora', fazenda_energia_taxa(p_jogador, now()) + 50 * (
        select count(*) from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
         where c.jogador_id = p_jogador and i.efeito = 'biomassa' and c.iniciado_em is not null)),
    'estacao', fazenda_estacao_em(now()),
    'estacao_fim', fazenda_estacao_fim(now()),
    'estacao_proxima', fazenda_estacao_em(fazenda_estacao_fim(now())),
    -- agora / até quando / o próximo (hoje e amanha: nomes da versão anterior do jogo)
    'clima', v_clima || jsonb_build_object('hoje', v_clima->>'agora', 'amanha', v_clima->>'proximo'),
    'canteiros', coalesce((
      select jsonb_agg(jsonb_build_object(
               'posicao', posicao, 'x', x, 'y', y, 'estado', estado, 'cultura', cultura,
               'plantado_em', plantado_em, 'erva', erva, 'praga', praga, 'seco', seco,
               'roubado', roubado, 'adubado', adubado, 'xp_em', xp_em)
             order by posicao)
        from fazenda_canteiros where jogador_id = p_jogador), '[]'::jsonb),
    'diario', coalesce((
      select jsonb_agg(jsonb_build_object(
               'tipo', d.tipo, 'id', d.ator_id, 'apelido', d.apelido,
               'cultura', d.cultura, 'qtd', d.qtd, 'em', d.criado_em, 'luva', d.luva)   -- fase 66: passou pelo alarme
             order by d.criado_em desc)
        from (
          select v.tipo, v.ator_id, a.apelido, v.cultura, v.qtd, v.criado_em, v.luva
            from fazenda_visitas v
            join fazenda_jogadores a on a.id = v.ator_id
           where v.dono_id = p_jogador
           order by v.criado_em desc
           limit 20
        ) d), '[]'::jsonb),
    'celeiro', coalesce((
      select jsonb_object_agg(item, quantidade)
        from fazenda_celeiro where jogador_id = p_jogador and quantidade > 0), '{}'::jsonb),
    'reservas', coalesce((
      select jsonb_object_agg(item, quantidade)
        from fazenda_reservas where jogador_id = p_jogador), '{}'::jsonb),
    'culturas', fazenda_cache_ler('culturas'),   -- fase 71: os catálogos vêm prontos (fazenda_cache)
    'animais', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'alimentado_em', alimentado_em,
               'radioativo_ate', case when radioativo_ate > now() then radioativo_ate end) order by id)   -- fase 68
        from fazenda_animais where jogador_id = p_jogador), '[]'::jsonb),
    'animais_tipos', fazenda_cache_ler('animais_tipos'),
    'construcoes', coalesce((
      select jsonb_agg(jsonb_build_object('x', x, 'y', y, 'tipo', tipo, 'colhido_em', colhido_em, 'iniciado_em', iniciado_em,
                                          'estoque', estoque, 'prontos', prontos, 'pago', pago,   -- fase 72: pago
                                          'sobrecarga_em', sobrecarga_em))   -- fase 77: parado até o conserto
        from fazenda_construcoes where jogador_id = p_jogador), '[]'::jsonb),
    'estoque_max', fazenda_estoque_max_de(p_jogador),   -- fase 82: 15 com a fila de diamante
    'oficina_niveis', jsonb_build_object('regras', fazenda_oficina_niveis(),
                        'tem', coalesce((select jsonb_object_agg(tipo, nivel) from fazenda_oficina_nivel where jogador_id = p_jogador), '{}'::jsonb)),
    'itens', fazenda_cache_itens(v_nivel),   -- fase 57: o limite que vale para o nível de agora (fase 71: pronto, um por nível)
    'melhorias', coalesce((select jsonb_object_agg(id, nivel) from fazenda_melhorias where jogador_id = p_jogador), '{}'::jsonb),
    'camas', jsonb_build_object('total', fazenda_camas(p_jogador), 'ocupadas', fazenda_camas_ocupadas(p_jogador)),   -- fase 59
    'pier', jsonb_build_object('pronto', j.pier_em is not null, 'receita', fazenda_pier_receita()),   -- fase 61
    'mar', fazenda_mar_estado(p_jogador),   -- fase 62: o alto-mar (null sem o píer)
    -- fase 66: por que murchou (cada canteiro murcho de agora), o resumo das novas e as das últimas 24 h
    'murchas', jsonb_build_object(
      'canteiros', coalesce((
        select jsonb_object_agg(m.posicao::text, jsonb_build_object('motivo', m.motivo, 'detalhe', m.detalhe, 'em', m.murchou_em))
          from fazenda_murchas m join fazenda_canteiros c on c.jogador_id = m.jogador_id and c.posicao = m.posicao and c.plantado_em = m.plantado_em
         where m.jogador_id = p_jogador and c.estado = 'plantado'), '{}'::jsonb),
      'novas', coalesce((
        select jsonb_agg(jsonb_build_object('motivo', x.motivo, 'qtd', x.n, 'detalhe', x.d) order by x.n desc)
          from (select motivo, count(*) as n, (array_agg(detalhe order by murchou_em desc))[1] as d
                  from fazenda_murchas where jogador_id = p_jogador and not visto group by motivo) x), '[]'::jsonb),
      'dia', coalesce((
        select jsonb_object_agg(x.motivo, x.n)
          from (select motivo, count(*) as n from fazenda_murchas
                 where jogador_id = p_jogador and murchou_em > now() - interval '24 hours' group by motivo) x), '{}'::jsonb)),
    -- fase 67: o chat (o id mais novo, para a bolinha) e o que separaram para você na feira
    'chat', jsonb_build_object(
      'ultimo', (select max(c.id) from fazenda_chat c join fazenda_jogadores p on p.id = c.jogador_id
                  where c.criado_em >= now() - make_interval(mins => (fazenda_chat_regras()->>'minutos')::int)
                    and c.apagado_em is null and p.banido_em is null),
      'reservas', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'item', f.item, 'qtd', f.qtd, 'preco', f.preco,
                             'vendedor', v.apelido, 'ate', f.reservado_ate, 'nova', not f.reserva_vista) order by f.id)
                             from fazenda_feira f join fazenda_jogadores v on v.id = f.vendedor_id
                            where f.reservado_para = p_jogador and f.vendido_em is null and f.reservado_ate > now()), '[]'::jsonb)),
    'calendario', fazenda_calendario_estado(p_jogador),   -- fase 69: o calendário de resgate diário
    -- fase 68: o que a radiação do reator fez nos bichos (ainda não visto)
    'radiacao', coalesce((select jsonb_agg(jsonb_build_object('evento', r.evento, 'animal', r.animal, 'produto', r.produto, 'qtd', r.qtd, 'em', r.em) order by r.id)
                            from fazenda_radiacao r where r.jogador_id = p_jogador and not r.visto), '[]'::jsonb),
    -- fase 77: o que a tempestade e o furacão fizeram (e o que o eletricista consertou), ainda não visto
    'clima_eventos', coalesce((select jsonb_agg(jsonb_build_object('evento', e.evento, 'clima', e.clima, 'item', e.item, 'x', e.x, 'y', e.y, 'em', e.em) order by e.id)
                                 from fazenda_clima_eventos e where e.jogador_id = p_jogador and not e.visto), '[]'::jsonb),
    -- fase 63: o evento da semana (até quando vai, os prêmios ainda não vistos e os troféus)
    'evento', jsonb_build_object(
      'fim', fazenda_semana_inicio(now()) + interval '7 days',
      'novos', coalesce((select jsonb_agg(jsonb_build_object('semana', semana, 'categoria', categoria, 'posicao', posicao,
                                   'valor', valor, 'diamantes', diamantes, 'item', item) order by categoria, posicao)
                           from fazenda_semana_premios where jogador_id = p_jogador and not visto), '[]'::jsonb),
      'trofeus', fazenda_trofeus(p_jogador),
      'regras', fazenda_evento_regras()),
    'melhorias_tipos', fazenda_cache_ler('melhorias_tipos'),
    'estatisticas', (select to_jsonb(e) - 'jogador_id' || jsonb_build_object('energia', e.energia + floor(j.energia_gasta)::int)
                       from fazenda_estatisticas e where e.jogador_id = p_jogador),
    'conquistas', coalesce((
      select jsonb_agg(jsonb_build_object('id', conquista, 'em', obtida_em) order by obtida_em)
        from fazenda_conquistas where jogador_id = p_jogador), '[]'::jsonb),
    'conquistas_tipos', fazenda_cache_ler('conquistas_tipos'),
    'criado_em', j.criado_em,
    'missoes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'slot', slot, 'tipo', tipo, 'alvo', alvo, 'progresso', progresso,
               'moedas', moedas, 'xp', xp, 'resgatada', resgatada) order by slot)
        from fazenda_missoes where jogador_id = p_jogador and dia = fazenda_hoje()), '[]'::jsonb),
    'ajudantes', coalesce((
      select jsonb_agg(jsonb_build_object('tipo', h.tipo, 'nivel', h.nivel, 'relatorio', h.relatorio,
               -- fase 59: a barra de energia, o descanso e o que fez hoje e ontem
               'energia', round(h.energia::numeric, 1), 'custo', round((100 / (fazenda_ritmo(h.nivel) * 8))::numeric, 3),
               'descanso_ate', h.descanso_ate, 'descanso_motivo', h.descanso_motivo, 'descanso_casa', h.descanso_casa,
               'hoje', coalesce((select f.feito from fazenda_ajudantes_feito f where f.jogador_id = p_jogador and f.tipo = h.tipo and f.dia = fazenda_hoje()), '{}'::jsonb),
               'ontem', coalesce((select f.feito from fazenda_ajudantes_feito f where f.jogador_id = p_jogador and f.tipo = h.tipo and f.dia = fazenda_hoje() - 1), '{}'::jsonb)))
        from fazenda_ajudantes h where h.jogador_id = p_jogador), '[]'::jsonb),
    'ajudantes_tipos', fazenda_cache_ler('ajudantes_tipos')
  );
  -- o relatório (o que fizeram enquanto você estava fora) aparece uma vez só
  update fazenda_ajudantes set relatorio = 0 where jogador_id = p_jogador and relatorio > 0;
  update fazenda_convites set visto = true where dono_id = p_jogador and not visto;   -- idem os amigos novos
  update fazenda_feira set visto = true where vendedor_id = p_jogador and vendido_em is not null and not visto;   -- e as vendas da feira
  update fazenda_semana_premios set visto = true where jogador_id = p_jogador and not visto;   -- e os prêmios do evento (fase 63)
  update fazenda_murchas set visto = true where jogador_id = p_jogador and not visto;   -- e o relatório das murchas (fase 66)
  update fazenda_feira set reserva_vista = true where reservado_para = p_jogador and not reserva_vista;   -- e o que separaram no chat (fase 67)
  update fazenda_radiacao set visto = true where jogador_id = p_jogador and not visto;   -- e a radiação do reator (fase 68)
  update fazenda_clima_eventos set visto = true where jogador_id = p_jogador and not visto;   -- e o raio e o furacão (fase 77)
  return v_json;
end;
$$;

-- Faz as oficinas andarem até agora (roda ao carregar a fazenda e antes de mexer numa oficina)
create or replace function public.fazenda_oficinas_andar(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  o       record;
  v_tri   boolean := fazenda_tem_efeito(p_jogador, 'triturar');
  v_membros jsonb := coalesce((select jsonb_agg(to_jsonb(r)) from fazenda_rede(p_jogador) r), '[]'::jsonb);
  v_t     timestamptz;
  v_fim   timestamptz;
  v_est   int;
  v_pr    int;
  v_n     int;
  v_qtd   int;
  v_rede  boolean;
  v_volta int;
  v_puxou boolean;
begin
  for o in
    select c.x, c.y, c.iniciado_em, c.estoque, c.prontos, i.produz, i.produz_qtd, i.entradas,
           ceil(i.produz_seg * (1 - fazenda_oficina_rapidez(p_jogador, c.tipo)))::int as produz_seg   -- fase 82: nível 2 e 3
      from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
     where c.jogador_id = p_jogador and i.entradas is not null
     order by i.ordem, c.x, c.y   -- (a prensa antes do empório: o óleo chega no mesmo passo)
       for update of c
  loop
    v_t := o.iniciado_em; v_est := o.estoque; v_pr := o.prontos; v_fim := null; v_n := 0;
    v_rede := fazenda_redes_de(v_membros, 'oficina', o.x, o.y) is not null;
    -- ligou na rede agora: o que estava pronto esperando já sai pelo cano
    if v_rede and v_pr > 0 then
      v_pr := v_pr - fazenda_rede_entregar(p_jogador, o.x, o.y, o.produz, v_pr, v_membros, now());
    end if;
    loop
      exit when v_n >= 48;
      v_n := v_n + 1;
      if v_t is not null then
        exit when now() < v_t + make_interval(secs => o.produz_seg);   -- ainda trabalhando
        v_qtd := o.produz_qtd;
        v_fim := v_t + make_interval(secs => o.produz_seg);
        -- triturador (fase 72: +50% em vez do dobro, e 15 ⚡ por receita): metade de mais; com 1 por
        -- receita, uma sim, uma não (pela hora em que fica pronta: receitas emendadas se alternam)
        if v_tri and fazenda_gastar_energia(p_jogador, 15) then
          v_qtd := v_qtd + greatest(v_qtd / 2, (floor(extract(epoch from v_fim) / o.produz_seg)::bigint % 2 = 0)::int);
        end if;
        -- pronto: sai pela rede (outra oficina, celeiro ou baú); o que não sai fica para você pegar
        v_pr := v_pr + v_qtd - case when v_rede then fazenda_rede_entregar(p_jogador, o.x, o.y, o.produz, v_qtd, v_membros, v_fim) else 0 end;
        v_t := null;
      end if;
      -- estoque vazio e na rede: busca uma receita nos baús/celeiro da rede (2 ⚡, fase 43)
      if v_est <= 0 and v_rede
         and fazenda_rede_puxar(p_jogador, o.x, o.y, o.entradas, v_membros, greatest(coalesce(v_fim, now()), now() - interval '12 hours')) then
        v_est := 1;
      end if;
      exit when v_est <= 0;
      v_est := v_est - 1;
      -- emenda na receita anterior (o tempo fora vale, até 12 horas)
      v_t := greatest(coalesce(v_fim, now()), now() - interval '12 hours');
    end loop;
    -- fase 46: só grava se mudou (rodava em toda carga para toda oficina)
    if v_t is distinct from o.iniciado_em or v_est <> o.estoque or least(v_pr, 32000) <> o.prontos then
      update fazenda_construcoes set iniciado_em = v_t, estoque = v_est, prontos = least(v_pr, 32000)
       where jogador_id = p_jogador and x = o.x and y = o.y;
    end if;
  end loop;
  -- Fase 42: a rede enche o estoque das oficinas sozinha (até o máximo), uma receita por vez em
  -- rodízio, para dividir o que tem entre todas; a oficina parada que ganhou ingrediente já começa
  for v_volta in 1..fazenda_estoque_max_de(p_jogador) loop
    v_puxou := false;
    for o in
      select c.x, c.y, c.estoque, c.iniciado_em, i.entradas
        from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
       where c.jogador_id = p_jogador and i.entradas is not null
         and c.estoque + (c.iniciado_em is not null)::int < fazenda_estoque_max_de(p_jogador)
       order by i.ordem, c.x, c.y
    loop
      continue when fazenda_redes_de(v_membros, 'oficina', o.x, o.y) is null;
      if fazenda_rede_puxar(p_jogador, o.x, o.y, o.entradas, v_membros, now()) then
        update fazenda_construcoes
           set iniciado_em = coalesce(iniciado_em, now()),
               estoque = estoque + case when iniciado_em is null then 0 else 1 end
         where jogador_id = p_jogador and x = o.x and y = o.y;
        v_puxou := true;
      end if;
    end loop;
    exit when not v_puxou;
  end loop;
  perform fazenda_rede_descarregar(p_jogador, v_membros);
end;
$$;

-- Os ajudantes fazem o trabalho acumulado desde a última vez (até 8 horas).
-- Roda quando a fazenda carrega (abrir a página e a cada 30 s com ela aberta).
-- Fase 71: cada ajudante trabalha num lote só. Primeiro no modo rápido: cada tarefa direto, sem o
-- "exception" em volta de cada uma (cada um abria uma sub-transação; com centenas delas numa chamada o
-- banco ficava lento para todo mundo e a volta depois de horas fora passava dos 3 s). Se alguma tarefa
-- der erro, o lote daquele ajudante volta e é refeito no modo seguro, cada tarefa protegida como antes.
-- O resultado é o mesmo. A estação sai uma vez só e a semeadora conta as sementes plantadas uma vez só.
create or replace function public.fazenda_trabalhar(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  a       record;
  c       record;
  m       record;
  v_cred  real;
  v_n     int;
  v_feito int;
  v_sem   text;
  v_nivel int;
  v_ok    boolean;
  v_cafe_de  timestamptz;
  v_cafe_ate timestamptz;
  v_seg   real;
  v_custo real;              -- fase 59: energia que cada tarefa gasta (a barra cheia dura 8 h de trabalho)
  v_energia real;
  v_cama  boolean;           -- fase 59: cansou e tem cama livre numa casinha
  v_log   jsonb;             -- fase 59: o que ele fez nesta rodada ({"colheu": 3, ...})
  v_reg   boolean := false;  -- fase 66: as murchas já foram registradas nesta rodada?
  v_seguro boolean;          -- fase 71: refazendo o lote no modo seguro?
  v_est   text := fazenda_estacao_em(now());   -- fase 71: a estação de agora (uma vez só)
  v_cont  jsonb;             -- fase 71: quantos canteiros de cada semente (o rodízio da semeadora)
  v_moedas int;
begin
  select cafe_de, cafe_ate into v_cafe_de, v_cafe_ate from fazenda_jogadores where id = p_jogador;
  for a in
    select h.tipo, h.nivel, h.credito, h.atualizado_em, h.energia, h.descanso_ate, t.funcao, t.alvo
      from fazenda_ajudantes h join fazenda_ajudantes_tipos t on t.id = h.tipo
     where h.jogador_id = p_jogador
     order by (t.funcao = 'colher') desc, t.ordem   -- fase 48: quem colhe vem antes de quem ara as murchas
       for update of h
  loop
    -- fase 66: o colhedor já passou; antes de o lavrador arar as murchas, cada uma ganha o seu motivo
    if not v_reg and a.funcao <> 'colher' then perform fazenda_murchas_registrar(p_jogador); v_reg := true; end if;
    -- o eletricista não faz tarefas: ele baixa o gasto de energia (fazenda_energia_preco)
    continue when a.funcao = 'energia';
    -- fase 59: descansando não trabalha (nem junta crédito); acabou o descanso, volta com a energia cheia
    if a.descanso_ate is not null then
      continue when a.descanso_ate > now();
      update fazenda_ajudantes set energia = 100, descanso_ate = null, descanso_motivo = null, descanso_casa = null, credito = 0, atualizado_em = a.descanso_ate
       where jogador_id = p_jogador and tipo = a.tipo;
      a.energia := 100; a.credito := 0; a.atualizado_em := a.descanso_ate;
    end if;
    -- com o jogador na fazenda a semeadora descansa (o tempo online não conta para ela)
    if a.funcao = 'plantar' and coalesce((select carregado_antes > now() - interval '2 minutes' from fazenda_jogadores where id = p_jogador), false) then
      update fazenda_ajudantes set atualizado_em = now() where jogador_id = p_jogador and tipo = a.tipo;
      continue;
    end if;
    v_custo := 100 / (fazenda_ritmo(a.nivel) * fazenda_turno(p_jogador));   -- fase 82: 12 h com o turno de diamante
    -- fase 43: com o café (diamantes) o tempo dentro dele vale em dobro
    v_seg := extract(epoch from now() - a.atualizado_em)::real
           + case when v_cafe_ate is null then 0
                  else greatest(extract(epoch from least(now(), v_cafe_ate) - greatest(a.atualizado_em, v_cafe_de))::real, 0) end;
    v_cred := least(a.credito + v_seg / 3600 * fazenda_ritmo(a.nivel), fazenda_ritmo(a.nivel) * fazenda_turno(p_jogador));
    v_n := least(floor(v_cred), floor(a.energia / v_custo + 0.001))::int;   -- fase 59: e o que a energia deixa

    for v_tent in 1..2 loop   -- fase 71: 1 = modo rápido; 2 = deu erro, refaz no modo seguro
      v_seguro := v_tent = 2;
      v_feito := 0;
      v_log := '{}'::jsonb;
      begin
        if v_n > 0 and a.funcao = 'colher' then
          -- fase 48: também o que murchou depois da última olhada dele (até 8 h): com a fazenda fechada ele
          -- teria colhido a tempo; o que murcha primeiro vai primeiro
          for c in
            select cc.posicao, now() >= cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) as murcha
              from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
             where cc.jogador_id = p_jogador and cc.estado = 'plantado'
               and now() >= cc.plantado_em + make_interval(secs => k.tempo_seg)
               and cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600))
                   > greatest(a.atualizado_em, now() - make_interval(hours => fazenda_turno(p_jogador)::int))
             order by cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) limit v_n
          loop
            if fazenda_bot_aplicar(p_jogador, case when c.murcha then 'colher_tarde' else 'colher' end, c.posicao, null, v_seguro) is not null then
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'colheu');
            end if;
          end loop;
          -- fase 43: com o tempo que sobra, colhe as frutas do pomar (para o celeiro); a árvore encostada
          -- num baú fica para o baú (é ela que alimenta a rede de canos)
          if v_feito < v_n then
            for c in
              select k.x, k.y, k.tipo, i.produz, i.produz_qtd from fazenda_construcoes k join fazenda_itens i on i.id = k.tipo
               where k.jogador_id = p_jogador and i.categoria = 'pomar' and i.produz is not null
                 and (k.colhido_em is null or now() >= k.colhido_em + make_interval(secs => i.produz_seg))
                 and not exists (select 1 from fazenda_construcoes b
                                  where b.jogador_id = p_jogador and b.tipo = 'bau' and abs(b.x - k.x) + abs(b.y - k.y) = 1)
               order by k.colhido_em nulls first, k.x, k.y limit v_n - v_feito
            loop
              update fazenda_construcoes set colhido_em = fazenda_colhido_agora(p_jogador, c.tipo) where jogador_id = p_jogador and x = c.x and y = c.y;
              insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, c.produz, c.produz_qtd)
              on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'frutas');
            end loop;
          end if;

        elsif v_n > 0 and a.funcao = 'oficina' then
          -- fase 43, a operária: a rede anda primeiro (ela só faz o que a rede não fez)...
          perform fazenda_oficinas_andar(p_jogador);
          -- ...leva para o celeiro o que ficou pronto esperando...
          for c in
            select k.x, k.y, k.prontos, i.produz from fazenda_construcoes k join fazenda_itens i on i.id = k.tipo
             where k.jogador_id = p_jogador and i.entradas is not null and k.prontos > 0
             order by i.ordem, k.x, k.y
          loop
            exit when v_feito >= v_n;
            insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, c.produz, c.prontos)
            on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
            update fazenda_construcoes set prontos = 0 where jogador_id = p_jogador and x = c.x and y = c.y;
            v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'levou', c.prontos);
          end loop;
          -- ...e enche o estoque com o que tem no celeiro, uma receita por vez em rodízio (a parada já começa)
          v_ok := true;
          while v_ok and v_feito < v_n loop
            v_ok := false;
            for c in
              select k.x, k.y, i.entradas from fazenda_construcoes k join fazenda_itens i on i.id = k.tipo
               where k.jogador_id = p_jogador and i.entradas is not null
                 and k.estoque + (k.iniciado_em is not null)::int < fazenda_estoque_max_de(p_jogador)
               order by i.ordem, k.x, k.y
            loop
              exit when v_feito >= v_n;
              if fazenda_abastecer(p_jogador, c.entradas, 1) = 1 then
                update fazenda_construcoes
                   set iniciado_em = coalesce(iniciado_em, now()),
                       estoque = estoque + case when iniciado_em is null then 0 else 1 end
                 where jogador_id = p_jogador and x = c.x and y = c.y;
                v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'encheu');
                v_ok := true;
              end if;
            end loop;
          end loop;

        elsif v_n > 0 and a.funcao = 'arar' then
          for c in
            select cc.posicao from fazenda_canteiros cc left join fazenda_culturas k on k.id = cc.cultura
             where cc.jogador_id = p_jogador
               and (cc.estado = 'vazio'
                    or (cc.estado = 'plantado' and now() >= cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600))))
             order by cc.posicao limit v_n
          loop
            if fazenda_bot_aplicar(p_jogador, 'arar', c.posicao, null, v_seguro) is not null then
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'arou');
            end if;
          end loop;
          -- sobrou tempo: aduba os canteiros que estão crescendo (+1 item na colheita de cada um)
          if v_feito < v_n then
            for c in
              select cc.posicao from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
               where cc.jogador_id = p_jogador and cc.estado = 'plantado' and not cc.adubado
                 and now() < cc.plantado_em + make_interval(secs => k.tempo_seg)
               order by cc.plantado_em limit v_n - v_feito
            loop
              if fazenda_bot_aplicar(p_jogador, 'adubar', c.posicao, null, v_seguro) is not null then
                v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'adubou');
              end if;
            end loop;
          end if;

        elsif v_n > 0 and a.funcao = 'plantar' then
          v_nivel := fazenda_nivel((select xp from fazenda_jogadores where id = p_jogador));
          -- (fase 71: a conta de cada semente sai uma vez e anda junto com o que ela planta)
          select coalesce(jsonb_object_agg(x.cultura, x.n), '{}'::jsonb) into v_cont
            from (select cultura, count(*) as n from fazenda_canteiros
                   where jogador_id = p_jogador and estado = 'plantado' group by cultura) x;
          for c in
            select posicao from fazenda_canteiros
             where jogador_id = p_jogador and estado = 'arado' order by posicao limit v_n
          loop
            -- rodízio com todas as sementes da estação que o nível libera: a menos plantada primeiro,
            -- pulando as que o dinheiro não paga
            v_ok := false;
            select moedas into v_moedas from fazenda_jogadores where id = p_jogador;
            for v_sem in
              select k.id from fazenda_culturas k
               where k.tipo = 'cultura' and k.nivel_min <= v_nivel
                 and (k.estacao is null or k.estacao = v_est)
                 and k.custo <= v_moedas
               order by coalesce((v_cont->>k.id)::int, 0), k.ordem
            loop
              if fazenda_bot_aplicar(p_jogador, 'plantar', c.posicao, v_sem, v_seguro) is not null then
                v_feito := v_feito + 1; v_ok := true; v_log := fazenda_conta(v_log, 'plantou');
                v_cont := v_cont || jsonb_build_object(v_sem, coalesce((v_cont->>v_sem)::int, 0) + 1);
                exit;
              end if;
            end loop;
            exit when not v_ok;   -- nenhuma semente que o dinheiro pague: para
          end loop;

        elsif v_n > 0 and a.funcao = 'cuidar' then
          for c in
            select cc.posicao, cc.erva, cc.praga, cc.seco from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
             where cc.jogador_id = p_jogador and cc.estado = 'plantado' and (cc.erva or cc.praga or cc.seco)
               and now() < cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600))
             order by cc.plantado_em
          loop
            exit when v_feito >= v_n;
            if c.erva and v_feito < v_n and fazenda_bot_aplicar(p_jogador, 'erva', c.posicao, null, v_seguro) is not null then
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'erva');
            end if;
            if c.praga and v_feito < v_n and fazenda_bot_aplicar(p_jogador, 'praga', c.posicao, null, v_seguro) is not null then
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'praga');
            end if;
            if c.seco and v_feito < v_n and fazenda_bot_aplicar(p_jogador, 'seco', c.posicao, null, v_seguro) is not null then
              v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'seco');
            end if;
          end loop;

        elsif v_n > 0 and a.funcao = 'animal' then
          for m in
            select an.id, an.alimentado_em, t.tempo_seg, t.racao, t.racao_qtd from fazenda_animais an join fazenda_animais_tipos t on t.id = an.tipo
             where an.jogador_id = p_jogador and an.tipo = a.alvo order by an.id
          loop
            exit when v_feito >= v_n;
            -- coletar e dar ração separados: faltar ração não desfaz a coleta
            if m.alimentado_em is not null and now() >= m.alimentado_em + make_interval(secs => m.tempo_seg) then
              if fazenda_bot_animal(p_jogador, m.id, 'coletar', v_seguro) then
                v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'coletou');
                m.alimentado_em := null;
              end if;
            end if;
            -- sem ração no celeiro: pula (fase 71: confere antes de tentar)
            if m.alimentado_em is null and v_feito < v_n
               and coalesce((select quantidade from fazenda_celeiro where jogador_id = p_jogador and item = m.racao), 0) >= m.racao_qtd then
              if fazenda_bot_animal(p_jogador, m.id, 'alimentar', v_seguro) then
                v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'alimentou');
              end if;
            end if;
          end loop;
        end if;

        -- fase 46: quem não fez nada não é regravado: o crédito continua saindo do tempo desde
        -- atualizado_em (até 8 h), igual; contratar/evoluir e o café fecham a conta antes (fazenda_ajudantes_fechar)
        if v_feito > 0 then
          -- fase 59: gasta a energia; sem energia para mais uma tarefa, descansa sozinho: 2 h numa cama
          -- livre das casinhas, 4 h na sombra se todas estiverem ocupadas
          v_energia := greatest(a.energia - v_feito * v_custo, 0);
          v_cama := v_energia < v_custo and fazenda_camas_ocupadas(p_jogador) < fazenda_camas(p_jogador);
          update fazenda_ajudantes
             set credito = v_cred - v_feito, atualizado_em = now(), relatorio = relatorio + v_feito,
                 energia = v_energia,
                 descanso_ate = case when v_energia < v_custo then now() + case when v_cama then interval '2 hours' else interval '4 hours' end end,
                 descanso_motivo = case when v_energia < v_custo then 'cansou' end,
                 descanso_casa = case when v_energia < v_custo then v_cama end,
                 -- fase 66: a janela do último descanso fica guardada (para o relatório da planta murcha)
                 ultimo_descanso_de = case when v_energia < v_custo then now() else ultimo_descanso_de end,
                 ultimo_descanso_ate = case when v_energia < v_custo then now() + case when v_cama then interval '2 hours' else interval '4 hours' end else ultimo_descanso_ate end,
                 ultimo_descanso_motivo = case when v_energia < v_custo then case when v_cama then 'cama' else 'sombra' end else ultimo_descanso_motivo end
           where jogador_id = p_jogador and tipo = a.tipo;
          perform fazenda_ajudante_registrar(p_jogador, a.tipo, v_log);
        end if;
        exit;   -- deu certo: o próximo ajudante
      exception when others then
        if v_seguro then raise; end if;   -- (no modo seguro cada tarefa já se protege: este erro é de verdade)
      end;
    end loop;
  end loop;
  if not v_reg then perform fazenda_murchas_registrar(p_jogador); end if;   -- fase 66
  perform fazenda_bot_xp_gravar();   -- fase 72: o XP do que colheram, uma vez só
end;
$$;

-- Registra o que está murcho e ainda não tem motivo. Roda dentro de fazenda_trabalhar, depois do
-- colhedor e antes do lavrador (que ara as murchas).
create or replace function public.fazenda_murchas_registrar(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  h      record;
  v_tem  boolean;
begin
  select a.nivel, a.ultimo_descanso_de, a.ultimo_descanso_ate, a.ultimo_descanso_motivo into h
    from fazenda_ajudantes a join fazenda_ajudantes_tipos t on t.id = a.tipo
   where a.jogador_id = p_jogador and t.funcao = 'colher' limit 1;
  v_tem := found;
  insert into fazenda_murchas (jogador_id, posicao, plantado_em, cultura, murchou_em, motivo, detalhe)
  select p_jogador, c.posicao, c.plantado_em, c.cultura, m.em, x.motivo,
         case x.motivo
           when 'descansando' then jsonb_build_object('como', h.ultimo_descanso_motivo,
                                                      'horas', round(extract(epoch from h.ultimo_descanso_ate - h.ultimo_descanso_de) / 3600))
           when 'nao_deu_conta' then jsonb_build_object('nivel', h.nivel, 'ritmo', fazenda_ritmo(h.nivel))
         end
    from fazenda_canteiros c
    join fazenda_culturas k on k.id = c.cultura
    cross join lateral (select c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) as em) m
    cross join lateral (select case
             when not v_tem then 'sem_colhedor'
             when h.ultimo_descanso_de is not null and m.em >= h.ultimo_descanso_de and m.em < h.ultimo_descanso_ate then 'descansando'
             when m.em < now() - make_interval(hours => fazenda_turno(p_jogador)::int) then 'fechada'
             else 'nao_deu_conta' end as motivo) x
   where c.jogador_id = p_jogador and c.estado = 'plantado' and now() >= m.em and m.em > now() - interval '7 days'
  on conflict (jogador_id, posicao, plantado_em) do nothing;
  delete from fazenda_murchas where jogador_id = p_jogador and murchou_em < now() - interval '7 days';
end;
$$;

-- Guarda (p_receitas > 0) ou tira (< 0) receitas do estoque de uma oficina. Guardar tira os
-- ingredientes do celeiro na hora (sem mexer na ração reservada), até 10 receitas no estoque;
-- tirar devolve os ingredientes. Parada e com estoque, ela já começa.
create or replace function public.fazenda_estoque(p_token text, p_x int, p_y int, p_receitas int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  r    record;
  e    record;
  v_n  int;
begin
  if p_receitas is null or p_receitas = 0 or abs(p_receitas) > 100 then raise exception 'quantidade_invalida'; end if;
  perform fazenda_oficinas_andar(v_id);
  select c.iniciado_em, c.estoque, i.entradas into r
    from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y
     for update of c;
  if not found or r.entradas is null then raise exception 'item_invalido'; end if;

  if p_receitas > 0 then
    -- a receita em andamento também ocupa um lugar
    v_n := least(p_receitas, fazenda_estoque_max_de(v_id) - r.estoque - (case when r.iniciado_em is null then 0 else 1 end));
    if v_n <= 0 then raise exception 'estoque_cheio'; end if;
    v_n := fazenda_abastecer(v_id, r.entradas, v_n);
    if v_n = 0 then raise exception 'sem_ingredientes'; end if;
    update fazenda_construcoes set estoque = estoque + v_n where jogador_id = v_id and x = p_x and y = p_y;
  else
    v_n := least(-p_receitas, r.estoque);
    if v_n <= 0 then raise exception 'estoque_vazio'; end if;
    for e in select key as item, value::int as qtd from jsonb_each_text(r.entradas) loop
      insert into fazenda_celeiro (jogador_id, item, quantidade) values (v_id, e.item, e.qtd * v_n)
      on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
    end loop;
    update fazenda_construcoes set estoque = estoque - v_n where jogador_id = v_id and x = p_x and y = p_y;
    v_n := -v_n;
  end if;
  perform fazenda_oficinas_andar(v_id);   -- parada com estoque: começa agora
  return jsonb_build_object('receitas', v_n, 'estado', fazenda_estado(v_id));
end;
$$;

create or replace function public.fazenda_usar_diamantes(p_token text, p_item text, p_x int default null, p_y int default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_loja  jsonb := fazenda_loja_diamantes() -> p_item;
  j       record;
  o       record;
  v_preco int;
  v_nivel int;
  v_xp    int := 0;
  v_e     real;
  v_cap   int;
begin
  if v_loja is null then raise exception 'item_invalido'; end if;
  perform fazenda_tick(v_id);
  select * into j from fazenda_jogadores where id = v_id for update;

  if p_item = 'xp2' then
    v_preco := (v_loja->>'preco')::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    -- comprar de novo com ele valendo soma mais 1 hora
    update fazenda_jogadores
       set diamantes = diamantes - v_preco,
           xp2_ate = greatest(coalesce(xp2_ate, now()), now()) + make_interval(hours => (v_loja->>'horas')::int)
     where id = v_id;

  elsif p_item = 'xp' then
    v_preco := (v_loja->>'preco')::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    if fazenda_diamantes_hoje(v_id, 'xp') >= (v_loja->>'por_dia')::int then raise exception 'limite_diario'; end if;
    v_nivel := fazenda_nivel(j.xp);
    if v_nivel >= 45 then raise exception 'xp_maximo'; end if;   -- fase 62: o último nível agora é o 45
    v_xp := ceil((fazenda_xp_nivel(v_nivel + 1) - fazenda_xp_nivel(v_nivel)) * (v_loja->>'pct')::int / 100.0)::int;
    perform set_config('fazenda.xp_puro', '1', true);
    perform set_config('fazenda.xp_pago', '1', true);   -- fase 70: não conta no evento
    update fazenda_jogadores set diamantes = diamantes - v_preco, xp = xp + v_xp where id = v_id;
    perform set_config('fazenda.xp_puro', '', true);
    perform set_config('fazenda.xp_pago', '', true);

  elsif p_item = 'cafe' then
    v_preco := (v_loja->>'preco')::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    if not exists (select 1 from fazenda_ajudantes where jogador_id = v_id) then raise exception 'sem_ajudantes'; end if;
    perform fazenda_trabalhar(v_id);   -- fecha o trabalho de antes no ritmo de antes
    perform fazenda_ajudantes_fechar(v_id, null);   -- (fase 46: quem não trabalhou também)
    update fazenda_jogadores
       set diamantes = diamantes - v_preco,
           cafe_de = case when cafe_ate > now() then cafe_de else now() end,
           cafe_ate = greatest(coalesce(cafe_ate, now()), now()) + make_interval(hours => (v_loja->>'horas')::int)
     where id = v_id;

  elsif p_item = 'energia' then
    if not exists (select 1 from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
                    where c.jogador_id = v_id and i.categoria = 'energia') then
      raise exception 'sem_maquinas';
    end if;
    v_e := fazenda_energia_atualizar(v_id);
    v_cap := fazenda_capacidade(v_id);
    if v_cap - v_e < 1 then raise exception 'energia_cheia'; end if;
    v_preco := greatest(1, ceil((v_cap - v_e) / (v_loja->>'por')::real))::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    update fazenda_jogadores set diamantes = diamantes - v_preco, energia = v_cap, energia_em = now() where id = v_id;

  elsif p_item = 'murchas' then
    -- fase 48: o diamante salva todas as plantas murchas (voltam maduras, sem problemas); fase 72: 1 a
    -- cada 25 plantas (era 1 para todas)
    select count(*) into v_cap from fazenda_canteiros c join fazenda_culturas k on k.id = c.cultura
     where c.jogador_id = v_id and c.estado = 'plantado'
       and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600));
    if v_cap = 0 then raise exception 'nada_a_fazer'; end if;
    v_preco := (v_loja->>'preco')::int * ceil(v_cap / coalesce((v_loja->>'por')::numeric, v_cap))::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    update fazenda_canteiros c
       set plantado_em = now() - make_interval(secs => k.tempo_seg), erva = false, praga = false, seco = false, prox_evento = null
      from fazenda_culturas k
     where c.jogador_id = v_id and c.estado = 'plantado' and k.id = c.cultura
       and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600));
    update fazenda_jogadores set diamantes = diamantes - v_preco where id = v_id;

  elsif p_item = 'oficina' then
    perform fazenda_oficinas_andar(v_id);
    select c.iniciado_em, ceil(i.produz_seg * (1 - fazenda_oficina_rapidez(v_id, c.tipo)))::int as produz_seg, i.entradas into o
      from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
     where c.jogador_id = v_id and c.x = p_x and c.y = p_y
       for update of c;
    if not found or o.entradas is null then raise exception 'item_invalido'; end if;
    if o.iniciado_em is null then raise exception 'oficina_parada'; end if;
    v_preco := greatest(1, ceil(extract(epoch from o.iniciado_em + make_interval(secs => o.produz_seg) - now()) / 3600
                                * (v_loja->>'por_hora')::int))::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    update fazenda_jogadores set diamantes = diamantes - v_preco where id = v_id;
    update fazenda_construcoes set iniciado_em = now() - make_interval(secs => o.produz_seg)
     where jogador_id = v_id and x = p_x and y = p_y;
    perform fazenda_oficinas_andar(v_id);   -- termina agora: o produto sai e a próxima começa

  elsif p_item = 'moedas' then   -- fase 79: diamantes viram moedas (o pacote cresce com o nível)
    v_preco := (v_loja->>'preco')::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    v_nivel := fazenda_nivel(j.xp);
    -- moeda comprada não conta no evento (o gatilho soma o que entra; aqui já desconta)
    update fazenda_jogadores
       set diamantes = diamantes - v_preco, moedas = moedas + v_nivel * (v_loja->>'por_nivel')::int,
           moedas_ganhas = moedas_ganhas - v_nivel * (v_loja->>'por_nivel')::int
     where id = v_id;
  end if;

  insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, p_item, v_preco);
  return jsonb_build_object('item', p_item, 'diamantes', v_preco, 'xp', v_xp, 'estado', fazenda_estado(v_id));
end;
$$;

-- a conta da energia de uma fazenda: gera (média por hora) e gasta (no máximo por hora, tudo
-- trabalhando), por tipo. Guardada por jogador enquanto as construções e o eletricista não mudam.
create or replace function public.fazenda_energia_conta(p_jogador uuid)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_ass  text;
  v      jsonb;
  m      jsonb;
  v_tri  boolean;
  v_fab  boolean;
  v_desc real;
  v_rede jsonb;
  v_gera jsonb;
  v_gasta jsonb;
  v_g    real;
  v_c    real;
begin
  select md5(coalesce(string_agg(c.tipo || c.x || ',' || c.y, ';' order by c.x, c.y), '') || ':' ||
             coalesce((select h.nivel from fazenda_ajudantes h join fazenda_ajudantes_tipos t on t.id = h.tipo
                        where h.jogador_id = p_jogador and t.funcao = 'energia' limit 1), 0))
    into v_ass from fazenda_construcoes c where c.jogador_id = p_jogador;
  select valor into v from fazenda_cache where chave = 'energia:' || p_jogador;
  if v is not null and v->>'ass' = v_ass then return v - 'ass'; end if;

  m := fazenda_energia_medias();
  v_tri := fazenda_tem_efeito(p_jogador, 'triturar');
  v_fab := fazenda_tem_efeito(p_jogador, 'automatico');
  v_desc := fazenda_energia_preco(p_jogador, 1);   -- quanto 1 ⚡ custa de verdade (0,8 e o eletricista)
  v_rede := coalesce((select jsonb_agg(to_jsonb(r)) from fazenda_rede(p_jogador) r), '[]'::jsonb);

  -- gera: cada gerador pela média dele
  select coalesce(jsonb_agg(jsonb_build_object('tipo', x.tipo, 'n', x.n, 'h', round(x.h::numeric))), '[]'::jsonb), coalesce(sum(x.h), 0)
    into v_gera, v_g
    from (select c.tipo, count(*) as n, count(*) * (m->>i.efeito)::real as h
            from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
           where c.jogador_id = p_jogador and i.efeito in ('solar', 'eolica', 'reator', 'biomassa', 'hidro')
           group by c.tipo, i.efeito) x;

  -- gasta: cada coisa trabalhando sem parar
  with cons as (
    select c.x, c.y, c.tipo, i.efeito, i.raio, i.produz_seg * (1 - fazenda_oficina_rapidez(p_jogador, c.tipo)) as produz_seg, i.entradas
      from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo where c.jogador_id = p_jogador),
  cant as (   -- colheitas por hora de cada canteiro (o que está plantado; vazio conta como 2 h)
    select c.x, c.y, 3600.0 / coalesce(k.tempo_seg, 7200) as por_h
      from fazenda_canteiros c left join fazenda_culturas k on k.id = c.cultura where c.jogador_id = p_jogador),
  itens as (
    -- oficinas: na rede, 2 do puxar e 2 da entrega (e 15 do triturador); fora dela, com a fábrica automática, 8
    select 'oficinas' as tipo,
           sum(3600.0 / o.produz_seg *
               case when exists (select 1 from jsonb_array_elements(v_rede) r where r->>'papel' = 'oficina' and (r->>'x')::int = o.x and (r->>'y')::int = o.y)
                    then 4 when v_fab then 8 else 0 end) as h
      from cons o where o.entradas is not null
    union all
    select 'triturador', case when v_tri then sum(3600.0 / o.produz_seg) * 15 end
      from cons o where o.entradas is not null
       and (exists (select 1 from jsonb_array_elements(v_rede) r where r->>'papel' = 'oficina' and (r->>'x')::int = o.x and (r->>'y')::int = o.y) or v_fab)
    union all
    select 'robo_colheita', sum(ct.por_h) * 6   -- 4 da colheita e 2 do replantio
      from cons r join cant ct on abs(ct.x - r.x) <= r.raio and abs(ct.y - r.y) <= r.raio where r.efeito = 'robo'
    union all
    select 'bau', sum(ct.por_h) * 2   -- o baú recolhe o que está encostado nele
      from cons b join cant ct on abs(ct.x - b.x) <= 1 and abs(ct.y - b.y) <= 1 where b.tipo = 'bau'
    union all
    select 'aspersor', sum(ct.por_h) * 2   -- uma seca por plantio, mais ou menos
      from cons a join cant ct on abs(ct.x - a.x) <= a.raio and abs(ct.y - a.y) <= a.raio where a.efeito = 'aspersor'
    union all
    select 'estufa', sum(ct.por_h) * 5   -- 5 por plantio no alcance dela
      from cons e join cant ct on abs(ct.x - e.x) <= e.raio and abs(ct.y - e.y) <= e.raio where e.efeito = 'estufa'
    union all
    select 'alarme', 5 * count(*)::real from cons where tipo = 'alarme'   -- fase 81: 5 ⚡/h cada (era 1)
    union all
    select 'luzes', 1 + count(*)::real from cons where tipo in ('casa_vermelha', 'casa_azul', 'lampiao')   -- fase 81: de noite
  )
  select coalesce(jsonb_agg(jsonb_build_object('tipo', tipo, 'h', round((h * case when tipo in ('alarme', 'luzes') then 1 else v_desc end)::numeric)) order by h desc)
                    filter (where coalesce(h, 0) > 0), '[]'::jsonb),
         coalesce(sum(h * case when tipo in ('alarme', 'luzes') then 1 else v_desc end), 0)
    into v_gasta, v_c
    from itens;

  v := jsonb_build_object('gera', round(v_g), 'gasta', round(v_c), 'saldo', round(v_g - v_c),
                          'gera_itens', v_gera, 'gasta_itens', v_gasta, 'desconto', round((1 - v_desc)::numeric * 100));
  perform fazenda_cache_gravar('energia:' || p_jogador, v || jsonb_build_object('ass', v_ass));
  return v;
end;
$$;

-- Tira os peixes do cesto do Bira: 1 a cada 30 min desde lago_em, até 16 (o que passar disso
-- se perde: o cesto estava cheio). Cada peixe é sorteado pela chance (fazenda_peixes).
-- Tira do cesto do Bira os peixes que já estão nele (no máximo p_max): sorteia cada um, conta
-- nas estatísticas e anda o relógio do cesto. Devolve {peixe: quantidade}. Usada pela pesca na
-- mão (fazenda_pescar) e pelo baú encostado no lago (fase 39).
create or replace function public.fazenda_cesto(p_jogador uuid, p_max int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  j         record;
  p         record;
  v_estatua boolean := fazenda_tem_efeito(p_jogador, 'chico');
  v_n       int;
  v_k       int;
  v_r       numeric;
  v_soma    int;
  v_peixes  jsonb := '{}'::jsonb;
begin
  select zonas, lago_em into j from fazenda_jogadores where id = p_jogador for update;
  if j.zonas < 3 or j.lago_em is null then return v_peixes; end if;
  v_n := least(floor(extract(epoch from now() - j.lago_em) / 1800)::int, fazenda_cesto_max(p_jogador), greatest(coalesce(p_max, 0), 0));   -- fase 82: 24 com o cesto grande
  if v_n <= 0 then return v_peixes; end if;
  for v_k in 1..v_n loop
    v_r := random() * 100;
    v_soma := 0;
    for p in select * from fazenda_peixes(v_estatua) loop
      v_soma := v_soma + p.chance;
      if v_r < v_soma then
        v_peixes := jsonb_set(v_peixes, array[p.peixe], to_jsonb(coalesce((v_peixes->>p.peixe)::int, 0) + 1));
        exit;
      end if;
    end loop;
  end loop;
  -- o cesto enche até 16 (8 h): o que passou disso não conta; o que ficou no cesto continua lá
  update fazenda_jogadores set lago_em = greatest(j.lago_em, now() - make_interval(secs => fazenda_cesto_max(p_jogador) * 1800)) + make_interval(secs => v_n * 1800)
   where id = p_jogador;
  insert into fazenda_estatisticas (jogador_id) values (p_jogador) on conflict do nothing;
  update fazenda_estatisticas set peixes = peixes + v_n, lendarios = lendarios + coalesce((v_peixes->>'velho_chico')::int, 0)
   where jogador_id = p_jogador;
  return v_peixes;
end;
$$;

-- o barco, a vara ou o marinheiro que o jogador tem agora (o nível 0 é o "base", que vem com o píer;
-- o marinheiro não tem base: null = não contratado)
-- fase 65: o motor deixa o cardume do barco mais rápido; a rede, o marinheiro (e o cesto dele cresce
-- junto, para continuar guardando 8 horas)
create or replace function public.fazenda_mar_item(p_jogador uuid, p_id text)
returns jsonb language sql stable security definer set search_path = public as $$
  -- fase 82: o cesto grande do Seu Nonato (diamante) guarda 50% mais
  select case when y.r is not null and p_id = 'marinheiro' and fazenda_melhoria(p_jogador, 'cesto_nonato') > 0
              then y.r || jsonb_build_object('max', ceil((y.r->>'max')::int * (1 + fazenda_melhoria(p_jogador, 'cesto_nonato')))::int)
              else y.r end
    from (
  select case when x.i is null then null
              when p_id = 'barco' and fazenda_melhoria(p_jogador, 'motor') > 0
                then x.i || jsonb_build_object('intervalo', round((x.i->>'intervalo')::int * (1 - fazenda_melhoria(p_jogador, 'motor')))::int)
              when p_id = 'marinheiro' and fazenda_melhoria(p_jogador, 'rede') > 0
                then x.i || jsonb_build_object('intervalo', round((x.i->>'intervalo')::int * (1 - fazenda_melhoria(p_jogador, 'rede')))::int,
                                               'max', ceil((x.i->>'max')::int / (1 - fazenda_melhoria(p_jogador, 'rede'))::numeric)::int)
              else x.i end
    from (select case when coalesce(g.nivel, 0) = 0 then m->'base' else m->'niveis'->(g.nivel - 1) end as i
            from jsonb_array_elements(fazenda_melhorias_tipos()) m
            left join fazenda_melhorias g on g.jogador_id = p_jogador and g.id = p_id
           where m->>'id' = p_id) x) y(r);
$$;

-- p_categoria: animal (as construções têm funções próprias, logo abaixo)
create or replace function public.fazenda_comprar(p_token text, p_categoria text, p_tipo text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  j       record;
  a       record;
  v_n     int;
  v_preco int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;

  if p_categoria = 'animal' then
    select * into a from fazenda_animais_tipos where id = p_tipo;
    if not found then raise exception 'item_invalido'; end if;
    if fazenda_nivel(j.xp) < a.nivel_min then raise exception 'nivel_insuficiente'; end if;
    -- fase 45: o bicho precisa da casa dele antes (Construir → Bichos)
    if not exists (select 1 from fazenda_construcoes where jogador_id = v_id and tipo = 'cercado_' || a.id) then
      raise exception 'sem_cercado';
    end if;
    select count(*) into v_n from fazenda_animais where jogador_id = v_id and tipo = a.id;
    if v_n >= a.maximo then
      raise exception 'limite_animais';
    end if;
    -- cada bicho da mesma espécie sai 50% mais caro que o anterior (igual a precoAnimal em fazenda.js)
    v_preco := round(a.custo * power(1.5::numeric, v_n))::int;
    if j.moedas < v_preco then raise exception 'moedas_insuficientes'; end if;
    update fazenda_jogadores set moedas = moedas - v_preco where id = v_id;
    insert into fazenda_animais (jogador_id, tipo) values (v_id, a.id);

  elsif p_categoria = 'terreno' then
    -- de 1 a 7, sempre o próximo da fila; fase 78: p_tipo 8 a 10 = o próximo da direita (à parte,
    -- do nível 29). Sem p_tipo (jogo antigo), o próximo da fila.
    if coalesce(nullif(p_tipo, ''), '0')::int >= 8 then
      if j.direita >= 3 then raise exception 'terreno_max'; end if;
      if p_tipo::int <> 8 + j.direita then raise exception 'terreno_fora_de_ordem'; end if;
    elsif j.zonas >= 7 then raise exception 'terreno_max';
    end if;
    select (z->>'n')::int as n, (z->>'custo')::int as custo, (z->>'nivel')::int as nivel into a
      from jsonb_array_elements(fazenda_zonas()) z
     where (z->>'n')::int = case when coalesce(nullif(p_tipo, ''), '0')::int >= 8 then 8 + j.direita else j.zonas + 1 end;
    if fazenda_nivel(j.xp) < a.nivel then raise exception 'nivel_insuficiente'; end if;
    if j.moedas < a.custo then raise exception 'moedas_insuficientes'; end if;
    if a.n >= 8 then update fazenda_jogadores set moedas = moedas - a.custo, direita = direita + 1 where id = v_id;
    else update fazenda_jogadores set moedas = moedas - a.custo, zonas = zonas + 1 where id = v_id; end if;

  elsif p_categoria = 'melhoria' then
    -- fase 57: o próximo nível da melhoria (p_tipo = adubo, pomar ou pes)
    -- fase 62: e as do alto-mar (barco, vara e marinheiro), que pedem o píer pronto
    select (n->>'nivel')::int as nivel, (n->>'custo')::int as custo, coalesce((m->>'mar')::boolean, false) as mar,
           n->'itens' as itens, coalesce((n->>'diamantes')::int, 0) as diamantes into a
      from jsonb_array_elements(fazenda_melhorias_tipos()) m,
           jsonb_array_elements(m->'niveis') with ordinality as x(n, i)
     where m->>'id' = p_tipo
       and x.i = 1 + coalesce((select nivel from fazenda_melhorias where jogador_id = v_id and id = p_tipo), 0);
    if not found then raise exception 'melhoria_max'; end if;
    if a.mar and j.pier_em is null then raise exception 'sem_pier'; end if;
    if fazenda_nivel(j.xp) < a.nivel then raise exception 'nivel_insuficiente'; end if;
    -- fase 65: a rede é do marinheiro; o kit de expedição pede o barco oceânico
    if p_tipo = 'rede' and fazenda_mar_item(v_id, 'marinheiro') is null then raise exception 'sem_marinheiro'; end if;
    if p_tipo = 'expedicao' and coalesce((select nivel from fazenda_melhorias where jogador_id = v_id and id = 'barco'), 0) < 4 then
      raise exception 'barco_pequeno';
    end if;
    -- fase 82: as de diamante (D8) e o que cada uma precisa antes
    if p_tipo = 'cesto_bira' and j.zonas < 3 then raise exception 'sem_lago'; end if;
    if p_tipo = 'cesto_nonato' and fazenda_mar_item(v_id, 'marinheiro') is null then raise exception 'sem_marinheiro'; end if;
    if p_tipo = 'barraca' and j.barracas < 4 then raise exception 'barracas_antes'; end if;
    if j.diamantes < a.diamantes then raise exception 'diamantes_insuficientes'; end if;
    if j.moedas < a.custo then raise exception 'moedas_insuficientes'; end if;
    -- fase 65: as peças pedem materiais raros do celeiro (o que está guardado para o píer fica)
    if exists (select 1 from jsonb_each_text(coalesce(a.itens, '{}'::jsonb)) e
                where coalesce((select quantidade from fazenda_celeiro where jogador_id = v_id and item = e.key), 0)
                    - coalesce((select quantidade from fazenda_reservas where jogador_id = v_id and item = e.key), 0) < e.value::int) then
      raise exception 'faltam_materiais';
    end if;
    -- barco ou marinheiro novo (e o motor e a rede) mudam o ritmo: o que já está no cardume (ou no cesto) fica lá
    v_n := case when p_tipo in ('barco', 'motor') then fazenda_mar_contar(v_id, 'barco')
                when p_tipo in ('marinheiro', 'rede') then fazenda_mar_contar(v_id, 'marinheiro') end;
    update fazenda_jogadores set moedas = moedas - a.custo, diamantes = diamantes - a.diamantes,
           barracas = barracas + (p_tipo = 'barraca')::int   -- fase 82: a 5ª e a 6ª barraca
     where id = v_id;
    if a.diamantes > 0 then
      insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, 'melhoria:' || p_tipo, a.diamantes);
    end if;
    update fazenda_celeiro c set quantidade = c.quantidade - e.value::int
      from jsonb_each_text(coalesce(a.itens, '{}'::jsonb)) e
     where c.jogador_id = v_id and c.item = e.key;
    insert into fazenda_melhorias (jogador_id, id, nivel) values (v_id, p_tipo, 1)
    on conflict (jogador_id, id) do update set nivel = fazenda_melhorias.nivel + 1;
    if p_tipo in ('barco', 'motor') then
      update fazenda_jogadores set mar_em = now() - make_interval(secs => v_n * (fazenda_mar_item(v_id, 'barco')->>'intervalo')::int)
       where id = v_id;
    elsif p_tipo in ('marinheiro', 'rede') then
      update fazenda_jogadores set marinheiro_em = now() - make_interval(secs => v_n * (fazenda_mar_item(v_id, 'marinheiro')->>'intervalo')::int)
       where id = v_id;
    end if;

  elsif p_categoria = 'oficina' then
    -- fase 82 (B10): oficina nível 2 e 3, por tipo (vale para todas as oficinas daquele tipo)
    if not exists (select 1 from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
                    where c.jogador_id = v_id and c.tipo = p_tipo and i.entradas is not null) then
      raise exception 'item_invalido';
    end if;
    v_n := coalesce((select nivel from fazenda_oficina_nivel where jogador_id = v_id and tipo = p_tipo), 1);
    if v_n >= 3 then raise exception 'melhoria_max'; end if;
    v_preco := (fazenda_oficina_niveis()->(v_n - 1)->>'custo')::int;
    if j.moedas < v_preco then raise exception 'moedas_insuficientes'; end if;
    perform fazenda_oficinas_andar(v_id);   -- o que já ficou pronto sai no ritmo de antes
    update fazenda_jogadores set moedas = moedas - v_preco where id = v_id;
    insert into fazenda_oficina_nivel (jogador_id, tipo, nivel) values (v_id, p_tipo, 2)
    on conflict (jogador_id, tipo) do update set nivel = fazenda_oficina_nivel.nivel + 1;

  else
    raise exception 'item_invalido';
  end if;

  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- permissões
revoke execute on function
  public.fazenda_estoque_max_de(uuid),
  public.fazenda_cesto_max(uuid),
  public.fazenda_turno(uuid),
  public.fazenda_oficina_niveis(),
  public.fazenda_oficina_rapidez(uuid, text)
from public, anon, authenticated;

grant execute on function
  public.fazenda_comprar(text, text, text)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- conferência: deve aparecer "Fase 82: 5 melhorias de diamante, oficina nível 3 por 400000"
select 'Fase 82: ' || (select count(*) from jsonb_array_elements(public.fazenda_melhorias_tipos()) m where (m->>'diamante')::boolean)
       || ' melhorias de diamante, oficina nível 3 por ' || (public.fazenda_oficina_niveis()->1->>'custo') as ok;
