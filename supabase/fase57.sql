-- ============================================================
-- FAZENDINHA — Fase 57 (etapa 2A: energia, melhorias e fazenda completa), só o que mudou.
-- Para o banco que já está no ar (com a fase 56): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- ------------------------------------------------------------
-- Fase 57: fim de jogo (ideias de 15/10, etapa 2A).
-- • Energia: 20% mais barata (fazenda_energia_preco; a 56 tinha posto 40%) e painel solar e turbina
--   sobem de limite com o nível, um de cada vez: +1 painel nos níveis pares a partir do 18, +1 turbina
--   nos ímpares a partir do 19 (igual a limiteMaquina em fazenda.js).
-- • Melhorias (Loja → Melhorias): compras caras e permanentes para quem já juntou moedas.
--   adubo = a planta já nasce adiantada (soma com girassol e estufa); pomar = a árvore colhida recomeça
--   adiantada; pes = mais pés de cada fruta no pomar, além dos 4 dos terrenos.
-- • Fazenda completa: do nível 20 em diante, com as metas do nível em dia (tudo o que ele libera), o
--   bônus das metas sobe de +50% para +75% de XP, e arar e plantar também dão XP
--   (fazenda_xp_dobro, fazenda_aplicar).
-- ------------------------------------------------------------
create table if not exists public.fazenda_melhorias (
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  id         text not null,
  nivel      int  not null default 1,
  primary key (jogador_id, id)
);
alter table public.fazenda_melhorias enable row level security;
revoke all on public.fazenda_melhorias from anon, authenticated;

-- o catálogo (o jogo mostra o que vem daqui). valor: adubo e pomar = fração adiantada; pes = pés a mais
create or replace function public.fazenda_melhorias_tipos()
returns jsonb language sql immutable as $$
  select '[{"id":"adubo","nome":"Adubo premium","descricao":"As plantas nascem adiantadas: crescem 10%, 20% e 30% mais rápido (soma com o girassol e a estufa).",
            "niveis":[{"nivel":23,"custo":50000,"valor":0.1},{"nivel":26,"custo":150000,"valor":0.2},{"nivel":29,"custo":300000,"valor":0.3}]},
           {"id":"pomar","nome":"Pomar fértil","descricao":"As árvores do pomar dão frutas 15% e 30% mais rápido.",
            "niveis":[{"nivel":24,"custo":80000,"valor":0.15},{"nivel":28,"custo":200000,"valor":0.3}]},
           {"id":"pes","nome":"Mais pés de fruta","descricao":"Mais 1 e mais 2 pés de cada fruta no pomar, além dos 4 que os terrenos dão.",
            "niveis":[{"nivel":25,"custo":60000,"valor":1},{"nivel":30,"custo":120000,"valor":2}]}]'::jsonb;
$$;

-- quanto a melhoria vale para o jogador agora (0 = não comprou)
create or replace function public.fazenda_melhoria(p_jogador uuid, p_id text)
returns real language sql stable security definer set search_path = public as $$
  select coalesce((select (m->'niveis'->(g.nivel - 1)->>'valor')::real
                     from fazenda_melhorias g, jsonb_array_elements(fazenda_melhorias_tipos()) m
                    where g.jogador_id = p_jogador and g.id = p_id and m->>'id' = p_id), 0)::real;
$$;

-- o limite de cada máquina no nível (null = sem limite)
create or replace function public.fazenda_limite_maquina(p_item text, p_limite int, p_nivel int)
returns int language sql immutable as $$
  select case p_item
           when 'painel_solar' then p_limite + greatest(0, (p_nivel - 16) / 2)
           when 'turbina'      then p_limite + greatest(0, (p_nivel - 17) / 2)
           else p_limite end;
$$;

-- a hora de "colhido" de uma árvore colhida agora: com o pomar fértil, ela recomeça adiantada
create or replace function public.fazenda_colhido_agora(p_jogador uuid, p_tipo text)
returns timestamptz language sql stable security definer set search_path = public as $$
  select now() - make_interval(secs => coalesce((select i.produz_seg from fazenda_itens i
                                                  where i.id = p_tipo and i.categoria = 'pomar'), 0)
                                       * fazenda_melhoria(p_jogador, 'pomar'));
$$;

-- fazenda completa = do nível 20 em diante, com as metas do nível em dia (fase 49: bonus_nivel)
create or replace function public.fazenda_completa(p_jogador uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select fazenda_nivel(j.xp) >= 20 and j.bonus_nivel = fazenda_nivel(j.xp)
                     from fazenda_jogadores j where j.id = p_jogador), false);
$$;

-- energia: 20% mais barata (era 40% na fase 56)

create or replace function public.fazenda_energia_preco(p_jogador uuid, p_qtd real)
returns real language sql stable security definer set search_path = public as $$
  select (p_qtd * 0.8 * coalesce((select case h.nivel when 1 then 0.8 when 2 then 0.65 else 0.5 end
                              from fazenda_ajudantes h join fazenda_ajudantes_tipos t on t.id = h.tipo
                             where h.jogador_id = p_jogador and t.funcao = 'energia' limit 1), 1))::real;
$$;

-- descrições das máquinas (gasto novo e o limite do painel e da turbina)

insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, efeito, raio, limite, descricao) values
  ('cano',          'Cano de vidro',      'energia',    25, 16, 79, 'cano',       0, null, 'Canos encostados formam uma rede que liga baús, oficinas e o celeiro. A rede enche sozinha o estoque das oficinas com o que tem nos baús e no celeiro (1,6 ⚡ por receita); o produto vai para outra oficina que usa ele, para o celeiro ou para um baú; o que sobra no baú vai para o celeiro (1,2 ⚡ por viagem). Dá para ver cada item passando.'),
  ('painel_solar',  'Painel solar',       'energia',  2500, 16, 80, 'solar',      0, 8, 'Gera até 12 ⚡/h de dia (sol forte: 14; nublado: 5; chuva: 3). À noite, nada: no jogo, o dia e a noite se revezam a cada 2 horas. Até 8, mais 1 nos níveis pares a partir do 18 (18, 20, 22...).'),
  ('bateria',       'Banco de baterias',  'energia',  2000, 16, 81, 'bateria',    0, 4, 'Guarda mais 150 ⚡ (sem bateria, a caixa de luz guarda só 50). Bateria cheia: o que sobra é vendido, 1 moeda a cada 5 ⚡.'),
  ('turbina',       'Turbina eólica',     'energia',  4000, 17, 82, 'eolica',     0, 6, 'Gera 8 ⚡/h de dia e de noite; 30 ⚡/h na ventania e 14 na chuva. Na calmaria (sem vento, uns 25% do tempo fora da ventania e da chuva), cai para 3 ⚡/h: o painel de energia avisa quando vem. Até 6, mais 1 nos níveis ímpares a partir do 19 (19, 21, 23...).'),
  ('estufa',        'Estufa elétrica',    'energia',  6000, 18, 83, 'estufa',     2, 3, 'Canteiros em volta (2) aceitam sementes de qualquer estação e crescem 25% mais rápido. Gasta 4 ⚡ por plantio.'),
  ('gerador_bio',   'Gerador a biomassa', 'energia',  6000, 19, 84, 'biomassa',   0, 2, 'Ligado, queima 1 milho a cada 30 min: 50 ⚡/h. Toque nele para ligar ou desligar.'),
  ('triturador',    'Triturador',         'energia', 10000, 20, 85, 'triturar',   0, 1, 'As oficinas rendem 2 produtos por receita. Gasta 8 ⚡ por receita.'),
  ('supercap',      'Supercapacitor',     'energia',  9000, 21, 86, 'bateria',    0, 2, 'Guarda mais 800 ⚡.'),
  ('fabrica_auto',  'Fábrica automática', 'energia', 15000, 22, 87, 'automatico', 0, 1, 'Um pedaço do celeiro em qualquer lugar: a rede de canos encostada nela leva e traz do celeiro como se o cano chegasse até ele (sem mexer na ração reservada).'),
  ('robo_colheita', 'Robô colheitador',   'energia', 18000, 23, 88, 'robo',       3, 2, 'Colhe, ara e replanta sozinho os canteiros em volta (3). Gasta 3,2 ⚡ por colheita e 1,6 por plantio.'),
  ('aspersor',      'Aspersor elétrico',  'energia', 12000, 24, 89, 'aspersor',   3, 4, 'Nenhuma erva, praga ou seca nos canteiros em volta (3). Gasta 1,6 ⚡ por problema evitado.'),
  ('reator',        'Reator nuclear',     'energia', 30000, 25, 90, 'reator',     0, 1, 'Gera 120 ⚡/h sem parar, de dia e de noite (80 na onda de calor, para não esquentar).')
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem, efeito = excluded.efeito,
  raio = excluded.raio, limite = excluded.limite, descricao = excluded.descricao;

update public.fazenda_itens i
   set efeito = v.efeito, raio = v.raio, beleza = v.beleza, descricao = v.descricao,
       produz = v.produz, produz_seg = v.produz_seg, produz_qtd = v.produz_qtd
  from (values
    ('cerca',         'cerca'::text,  1::smallint,  1::smallint, 'Vizinhos pegam no máximo 1 item dos canteiros encostados.'::text, null::text, null::int, null::int),
    ('caminho_terra', null,           0,  1, 'Deixa a fazenda mais bonita: +1 de beleza (beleza dá bônus nas vendas).', null, null, null),
    ('caminho_pedra', null,           0,  2, 'Deixa a fazenda mais bonita: +2 de beleza (beleza dá bônus nas vendas).', null, null, null),
    ('flores',        'xp',           1,  2, '+1 XP ao colher os canteiros encostados.', null, null, null),
    ('girassol',      'crescer',      1,  3, 'Plantas encostadas crescem 10% mais rápido.', null, null, null),
    ('arbusto',       'praga',        1,  2, 'Joaninhas: sem pragas nos canteiros encostados.', null, null, null),
    ('cogumelos',     'adubo',        1,  2, 'Adubo natural: +1 item na colheita dos canteiros encostados.', null, null, null),
    ('arvore',        'seco',         1,  4, 'Sombra: sem seca nos canteiros encostados.', null, null, null),
    ('arvore_outono', 'crescer',      1,  4, 'Folhas viram adubo: plantas encostadas crescem 10% mais rápido.', null, null, null),
    ('pinheiro',      'praga',        2,  4, 'Passarinhos: sem pragas em volta (2 quadrados).', null, null, null),
    ('amoreira',      null,           0,  3, 'Dá 4 amoras a cada 5 horas: toque nela para colher. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).', 'morango', 18000, 4),
    ('pedras',        'erva',         1,  1, 'Cobertura de pedras: sem erva daninha nos canteiros encostados.', null, null, null),
    ('tora',          'crescer',      1,  2, 'Minhocas: plantas encostadas crescem 10% mais rápido.', null, null, null),
    ('placa',         'cerca',        2,  1, '"Proibido pegar": vizinhos pegam no máximo 1 item em volta (2 quadrados).', null, null, null),
    ('balde',         'seco',         1,  1, 'Sem seca nos canteiros encostados.', null, null, null),
    ('barril',        'adubo',        1,  2, 'Barril de adubo: +1 item na colheita dos canteiros encostados.', null, null, null),
    ('feno',          'feno',         0,  2, 'Animais produzem 20% mais rápido (fazenda toda, não acumula).', null, null, null),
    ('alvo',          'sorte',        2,  2, 'Sorte: 15% de chance de colheita em dobro em volta (2 quadrados).', null, null, null),
    ('caixote',       'venda',        0,  2, '+10% no preço de venda (fazenda toda, não acumula).', null, null, null),
    ('colmeia',       'adubo',        2,  3, 'Abelhas: +1 item na colheita em volta (2 quadrados).', null, null, null),
    ('bau',           'missao',       0,  3, '+25% de moedas nas missões. Com energia, guarda em si (até 200 itens) o que recolhe: encostado num bloco de canteiros, colhe o que amadurece; num cercado, coleta e dá ração aos bichos; numa árvore do pomar, colhe as frutas; no lago, pega o cesto do Bira (1,6 ⚡ cada). Com canos, manda para as oficinas e o celeiro.', null, null, null),
    ('lampiao',       null,           0,  3, 'Acende sozinho de noite e ilumina em volta. +3 de beleza (beleza dá bônus nas vendas).', null, null, null),
    ('casa_vermelha', null,           0, 20, 'Casinha: +20 de beleza (beleza dá bônus nas vendas).', null, null, null),
    ('casa_azul',     null,           0, 30, 'Casinha: +30 de beleza (beleza dá bônus nas vendas).', null, null, null)
  ) v(id, efeito, raio, beleza, descricao, produz, produz_seg, produz_qtd)
 where i.id = v.id;

-- painel e turbina por nível, pés extras do pomar

create or replace function public.fazenda_construir(p_token text, p_tipo text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id  uuid := fazenda_auth(p_token);
  j     record;
  i     record;
  v_pos int;
  v_custo int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;

  -- canteiro: não é item da loja, é um lugar de plantar (limite pelo nível e terrenos)
  if p_tipo = 'canteiro' then
    if (select count(*) from fazenda_canteiros where jogador_id = v_id)
       >= fazenda_limite_canteiros(fazenda_nivel(j.xp), j.zonas) then
      raise exception 'limite_canteiros';
    end if;
    perform fazenda_checar_lugar(v_id, j.zonas, p_x, p_y, 1, 1);
    select min(g) into v_pos from generate_series(0, 299) g   -- fase 56: eram 0..99
     where not exists (select 1 from fazenda_canteiros where jogador_id = v_id and posicao = g);
    if v_pos is null then raise exception 'limite_canteiros'; end if;
    insert into fazenda_canteiros (jogador_id, posicao, estado, x, y) values (v_id, v_pos, 'vazio', p_x, p_y);
    return jsonb_build_object('estado', fazenda_estado(v_id), 'posicao', v_pos);
  end if;

  select * into i from fazenda_itens where id = p_tipo;
  if not found then raise exception 'item_invalido'; end if;
  if fazenda_nivel(j.xp) < i.nivel_min then raise exception 'nivel_insuficiente'; end if;
  perform fazenda_checar_lugar(v_id, j.zonas, p_x, p_y, i.largura, i.altura);
  if i.limite is not null   -- fase 57: painel solar e turbina sobem com o nível
     and (select count(*) from fazenda_construcoes where jogador_id = v_id and tipo = i.id)
         >= fazenda_limite_maquina(i.id, i.limite, fazenda_nivel(j.xp)) then
    raise exception 'limite_maquina';
  end if;
  -- itens por terreno (amoreira): mais terreno, mais pés (igual a maxItem em fazenda.js); fase 47: no
  -- pomar, cada fruta tem 1 pé e +1 a cada 2 terrenos (até 4); quem já passou fica com as que tem
  if i.por_terreno is not null
     and (select count(*) from fazenda_construcoes c join fazenda_itens k on k.id = c.tipo
           where c.jogador_id = v_id and (c.tipo = i.id or (i.grupo is not null and k.grupo = i.grupo)))
         >= (case when i.categoria = 'pomar'   -- fase 57: + os pés da melhoria "Mais pés de fruta"
                  then i.por_terreno * (1 + j.zonas / 2) + fazenda_melhoria(v_id, 'pes')::int
                  else i.por_terreno * (1 + j.zonas) end) then
    raise exception 'limite_terreno';
  end if;
  if (select count(*) from fazenda_construcoes where jogador_id = v_id) >= fazenda_max_construcoes(j.zonas) then
    raise exception 'limite_construcoes';
  end if;
  -- fase 45: quem já tinha o bicho antes do cercado obrigatório ganha o primeiro cercado dele
  v_custo := case when i.efeito = 'cercado' and substr(i.id, 9) = any(coalesce(j.cercado_gratis, '{}')) then 0 else i.custo end;
  if j.moedas < v_custo then raise exception 'moedas_insuficientes'; end if;
  -- máquina elétrica nova: fecha a conta da energia antes (ela não gera pelo tempo de antes)
  if i.categoria = 'energia' then
    perform fazenda_energia_atualizar(v_id);
    update fazenda_jogadores set energia_em = now() where id = v_id;   -- (fase 46: a conta começa agora)
  end if;
  update fazenda_jogadores
     set moedas = moedas - v_custo,
         cercado_gratis = case when i.efeito = 'cercado' then array_remove(cercado_gratis, substr(i.id, 9)) else cercado_gratis end
   where id = v_id;
  insert into fazenda_construcoes (jogador_id, x, y, tipo, colhido_em) values (v_id, p_x, p_y, i.id, now());
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- o jogo recebe os limites e as melhorias

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
  v_clima jsonb := fazenda_clima_previsao(now());
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
  v_nivel := fazenda_nivel(j.xp);
  -- subiu de nível: presente de moedas e 5 diamantes por cada nível novo
  if v_nivel > coalesce(j.nivel_premiado, 1) then
    update fazenda_jogadores
       set moedas = moedas + (select sum(fazenda_presente_nivel(n)) from generate_series(coalesce(j.nivel_premiado, 1) + 1, v_nivel) n),
           diamantes = diamantes + 5 * (v_nivel - coalesce(j.nivel_premiado, 1)),
           nivel_premiado = v_nivel
     where id = p_jogador;
    select * into j from fazenda_jogadores where id = p_jogador;
  end if;
  -- canteiros não aparecem mais sozinhos: o jogador coloca no modo construir até este limite
  v_max := fazenda_limite_canteiros(v_nivel, j.zonas);
  -- fase 49: as metas de nível; com todas em dia, o bônus de XP vale neste nível (só grava se mudou)
  v_metas := fazenda_metas(p_jogador, v_nivel);
  v_bonus := case when v_nivel < 30 and not exists (select 1 from jsonb_array_elements(v_metas) m where not (m->>'feito')::boolean)
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
      'max_construcoes', fazenda_max_construcoes(j.zonas),
      'zonas', j.zonas,
      'beleza', fazenda_beleza(p_jogador),
      'bonus_venda', fazenda_bonus_venda(p_jogador)
    ),
    'zonas_venda', fazenda_zonas(),
    'pacotes_diamantes', fazenda_pacotes_diamantes(),
    'loja_diamantes', fazenda_loja_diamantes(),
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
                          'ate', f.criado_em + make_interval(hours => (fazenda_feira_regras()->>'horas')::int)) order by f.id)
                          from fazenda_feira f where f.vendedor_id = p_jogador and f.vendido_em is null), '[]'::jsonb),
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
      'desde', j.lago_em, 'intervalo', 1800, 'max', 16,
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
      'vento', fazenda_vento_previsao(now()),
      'capacidade', fazenda_capacidade(p_jogador),
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
               'cultura', d.cultura, 'qtd', d.qtd, 'em', d.criado_em)
             order by d.criado_em desc)
        from (
          select v.tipo, v.ator_id, a.apelido, v.cultura, v.qtd, v.criado_em
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
    'culturas', (
      select jsonb_agg(jsonb_build_object(
               'id', id, 'nome', nome, 'emoji', emoji, 'tempo_seg', tempo_seg,
               'custo', custo, 'venda', venda, 'rendimento', rendimento,
               'xp', xp, 'nivel_min', nivel_min, 'tipo', tipo, 'estacao', estacao)
             order by ordem)
        from fazenda_culturas),
    'animais', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'alimentado_em', alimentado_em) order by id)
        from fazenda_animais where jogador_id = p_jogador), '[]'::jsonb),
    'animais_tipos', (
      select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_animais_tipos t),
    'construcoes', coalesce((
      select jsonb_agg(jsonb_build_object('x', x, 'y', y, 'tipo', tipo, 'colhido_em', colhido_em, 'iniciado_em', iniciado_em,
                                          'estoque', estoque, 'prontos', prontos))
        from fazenda_construcoes where jogador_id = p_jogador), '[]'::jsonb),
    'estoque_max', fazenda_estoque_max(),
    'itens', (   -- fase 57: o limite que vale para o nível de agora
      select jsonb_agg(to_jsonb(t) || jsonb_build_object('limite', fazenda_limite_maquina(t.id, t.limite, v_nivel)) order by t.ordem)
        from fazenda_itens t),
    'melhorias', coalesce((select jsonb_object_agg(id, nivel) from fazenda_melhorias where jogador_id = p_jogador), '{}'::jsonb),
    'melhorias_tipos', fazenda_melhorias_tipos(),
    'estatisticas', (select to_jsonb(e) - 'jogador_id' || jsonb_build_object('energia', e.energia + floor(j.energia_gasta)::int)
                       from fazenda_estatisticas e where e.jogador_id = p_jogador),
    'conquistas', coalesce((
      select jsonb_agg(jsonb_build_object('id', conquista, 'em', obtida_em) order by obtida_em)
        from fazenda_conquistas where jogador_id = p_jogador), '[]'::jsonb),
    'conquistas_tipos', (
      select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_conquistas_tipos t),
    'criado_em', j.criado_em,
    'missoes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'slot', slot, 'tipo', tipo, 'alvo', alvo, 'progresso', progresso,
               'moedas', moedas, 'xp', xp, 'resgatada', resgatada) order by slot)
        from fazenda_missoes where jogador_id = p_jogador and dia = fazenda_hoje()), '[]'::jsonb),
    'ajudantes', coalesce((
      select jsonb_agg(jsonb_build_object('tipo', tipo, 'nivel', nivel, 'relatorio', relatorio))
        from fazenda_ajudantes where jogador_id = p_jogador), '[]'::jsonb),
    'ajudantes_tipos', (
      select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_ajudantes_tipos t)
  );
  -- o relatório (o que fizeram enquanto você estava fora) aparece uma vez só
  update fazenda_ajudantes set relatorio = 0 where jogador_id = p_jogador and relatorio > 0;
  update fazenda_convites set visto = true where dono_id = p_jogador and not visto;   -- idem os amigos novos
  update fazenda_feira set visto = true where vendedor_id = p_jogador and vendido_em is not null and not visto;   -- e as vendas da feira
  return v_json;
end;
$$;

-- adubo premium no plantio; arar e plantar dão XP com a fazenda completa

create or replace function public.fazenda_aplicar(p_jogador uuid, p_acao text, p_posicao int, p_cultura text, p_bot boolean default false)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  c        record;
  k        record;
  j        record;
  v_maduro timestamptz;
  v_murcho timestamptz;
  v_qtd    int := 0;
  v_fora   boolean;
  v_estufa boolean;
  v_xp_colheita boolean;
  v_tarde  boolean := false;
begin
  select * into j from fazenda_jogadores where id = p_jogador for update;

  select * into c from fazenda_canteiros
   where jogador_id = p_jogador and posicao = p_posicao
     for update;
  if not found then
    raise exception 'canteiro_bloqueado';
  end if;

  if c.cultura is not null then
    select * into k from fazenda_culturas where id = c.cultura;
    v_maduro := c.plantado_em + make_interval(secs => k.tempo_seg);
    v_murcho := v_maduro + make_interval(secs => greatest(k.tempo_seg * 2, 3600));
  end if;

  -- fase 48: o ajudante que colhe trabalha "atrasado" quando a fazenda estava fechada: o que murchou
  -- depois da última olhada dele, ele teria colhido a tempo (só para ajudante)
  if p_acao = 'colher_tarde' then
    if not p_bot then raise exception 'acao_invalida'; end if;
    v_tarde := true;
    p_acao := 'colher';
  end if;

  -- colher agora (fase 31): 1 diamante deixa pronto na hora o que está crescendo, sem os
  -- problemas, e já colhe. Maduro não precisa de diamante: só colhe.
  if p_acao = 'agora' then
    if p_bot then raise exception 'acao_invalida'; end if;
    if c.estado <> 'plantado' or now() >= v_murcho then raise exception 'nada_a_fazer'; end if;
    if now() < v_maduro then
      if j.diamantes < 1 then raise exception 'diamantes_insuficientes'; end if;
      update fazenda_jogadores set diamantes = diamantes - 1 where id = p_jogador;
      c.erva := false; c.praga := false; c.seco := false;
      v_maduro := now();
      v_murcho := now() + make_interval(secs => greatest(k.tempo_seg * 2, 3600));
    end if;
    p_acao := 'colher';
  end if;

  if p_acao = 'arar' then
    if c.estado = 'arado' then
      raise exception 'ja_arado';
    end if;
    if c.estado = 'plantado' and now() < v_murcho then
      raise exception 'canteiro_ocupado';
    end if;
    update fazenda_canteiros
       set estado = 'arado', cultura = null, plantado_em = null,
           erva = false, praga = false, seco = false, roubado = 0, prox_evento = null, adubado = false
     where jogador_id = p_jogador and posicao = p_posicao;
    -- arar só dá XP para quem está começando (até o nível 5): senão alface de 2 min vira fábrica de XP
    -- fase 57: e para quem tem a fazenda completa (do 20 em diante, com as metas do nível em dia)
    if not p_bot and (fazenda_nivel(j.xp) <= 5 or fazenda_completa(p_jogador)) then update fazenda_jogadores set xp = xp + 1 where id = p_jogador; end if;

  elsif p_acao = 'arrancar' then   -- o jogador tira o que está plantado (perde a planta) para plantar outra coisa
    if p_bot then raise exception 'acao_invalida'; end if;
    if c.estado <> 'plantado' then raise exception 'nada_a_fazer'; end if;
    update fazenda_canteiros
       set estado = 'arado', cultura = null, plantado_em = null,
           erva = false, praga = false, seco = false, roubado = 0, prox_evento = null, adubado = false
     where jogador_id = p_jogador and posicao = p_posicao;

  elsif p_acao = 'adubar' then   -- só o Seu Zé (ajudante): +1 item na colheita desse plantio
    if not p_bot then raise exception 'acao_invalida'; end if;
    if c.estado <> 'plantado' or now() >= v_maduro or c.adubado then
      raise exception 'nada_a_fazer';
    end if;
    update fazenda_canteiros set adubado = true where jogador_id = p_jogador and posicao = p_posicao;

  elsif p_acao = 'plantar' then
    if c.estado <> 'arado' then
      raise exception 'precisa_arar';
    end if;
    select * into k from fazenda_culturas where id = p_cultura;
    if not found or k.tipo <> 'cultura' then
      raise exception 'cultura_invalida';
    end if;
    -- semente de outra estação só cresce no alcance de uma estufa elétrica
    v_fora := k.estacao is not null and k.estacao <> fazenda_estacao_em(now());
    v_estufa := fazenda_protegido(p_jogador, 'estufa', c.x, c.y);
    if v_fora and not v_estufa then
      raise exception 'fora_de_estacao';
    end if;
    if fazenda_nivel(j.xp) < k.nivel_min then
      raise exception 'nivel_insuficiente';
    end if;
    if j.moedas < k.custo then
      raise exception 'moedas_insuficientes';
    end if;
    if v_estufa then
      v_estufa := fazenda_gastar_energia(p_jogador, 5);   -- sem energia, a estufa não ajuda
    end if;
    if v_fora and not v_estufa then
      raise exception 'sem_energia';
    end if;
    update fazenda_jogadores set moedas = moedas - k.custo where id = p_jogador;
    update fazenda_canteiros
       -- pé de girassol, tora, árvore de outono por perto: começa 10% adiantada; estufa: 25%
       set estado = 'plantado', cultura = k.id,
           plantado_em = now() - make_interval(secs => k.tempo_seg *
                           (0.1 * fazenda_protegido(p_jogador, 'crescer', c.x, c.y)::int + 0.25 * v_estufa::int
                            + fazenda_melhoria(p_jogador, 'adubo'))),   -- fase 57: adubo premium
           erva = false, praga = false, seco = false, roubado = 0, adubado = false,
           prox_evento = now() + make_interval(secs => k.tempo_seg * (0.15 + random() * 0.35))
     where jogador_id = p_jogador and posicao = p_posicao;
    if not p_bot then
      perform fazenda_missao(p_jogador, 'plantar', 1);
      -- fase 57: fazenda completa: plantar também dá XP
      update fazenda_jogadores set semente = k.id, xp = xp + fazenda_completa(p_jogador)::int where id = p_jogador;
    end if;

  elsif p_acao in ('erva', 'praga', 'seco') then
    if c.estado <> 'plantado' or now() >= v_murcho
       or (p_acao = 'erva'  and not c.erva)
       or (p_acao = 'praga' and not c.praga)
       or (p_acao = 'seco'  and not c.seco) then
      raise exception 'nada_a_fazer';
    end if;
    update fazenda_canteiros
       set erva  = case when p_acao = 'erva'  then false else erva  end,
           praga = case when p_acao = 'praga' then false else praga end,
           seco  = case when p_acao = 'seco'  then false else seco  end
     where jogador_id = p_jogador and posicao = p_posicao;
    if not p_bot then
      update fazenda_jogadores set xp = xp + 1, moedas = moedas + 1 where id = p_jogador;
      perform fazenda_missao(p_jogador, 'cuidar', 1);
    end if;

  elsif p_acao = 'colher' then
    if c.estado <> 'plantado' or now() < v_maduro then
      raise exception 'nao_maduro';
    end if;
    if now() >= v_murcho and not v_tarde then
      raise exception 'murchou';
    end if;
    -- cada problema não resolvido custa 1 unidade; o que os vizinhos pegaram também sai
    v_qtd := greatest(k.rendimento - (c.erva::int + c.praga::int + c.seco::int) - c.roubado, 1)
             + fazenda_tem_efeito(p_jogador, 'colheita')::int          -- colheitadeira
             + (fazenda_clima_em(now()) = 'sol')::int                    -- colheita no sol
             + fazenda_protegido(p_jogador, 'adubo', c.x, c.y)::int     -- cogumelos, barril, colmeia
             + c.adubado::int;                                          -- adubo do Seu Zé
    if fazenda_protegido(p_jogador, 'sorte', c.x, c.y) and random() < 0.15 then
      v_qtd := v_qtd * 2;                                               -- alvo
    end if;
    insert into fazenda_celeiro (jogador_id, item, quantidade)
    values (p_jogador, k.id, v_qtd)
    on conflict (jogador_id, item)
    do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
    -- XP cheio da planta, mas o mesmo canteiro dá XP no máximo 1 vez a cada 8 min (fase 41)
    v_xp_colheita := not p_bot and (c.xp_em is null or c.xp_em <= now() - interval '8 minutes');
    if v_xp_colheita then
      update fazenda_jogadores set xp = xp + k.xp + fazenda_protegido(p_jogador, 'xp', c.x, c.y)::int where id = p_jogador;
    end if;
    update fazenda_canteiros   -- com trator, o canteiro já fica arado
       set estado = case when fazenda_tem_efeito(p_jogador, 'arar') then 'arado' else 'vazio' end,
           cultura = null, plantado_em = null,
           erva = false, praga = false, seco = false, roubado = 0, prox_evento = null, adubado = false,
           xp_em = case when v_xp_colheita then now() else xp_em end
     where jogador_id = p_jogador and posicao = p_posicao;
    if not p_bot then perform fazenda_missao(p_jogador, 'colher', v_qtd); end if;

  else
    raise exception 'acao_invalida';
  end if;

  return v_qtd;
end;
$$;

-- pomar fértil: baú, Juca e colheita na mão

create or replace function public.fazenda_baus(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  b       record;
  k       record;
  m       record;
  arv     record;
  e       record;
  v_qtd   int;
  v_livre int;
  v_peixes jsonb;
begin
  for b in select x, y from fazenda_construcoes where jogador_id = p_jogador and tipo = 'bau' loop
    v_livre := fazenda_bau_livre(p_jogador, b.x, b.y);
    -- canteiros: o bloco encostado no baú (canteiros encostados uns nos outros)
    for k in
      with recursive bloco(posicao, x, y) as (
        select c.posicao, c.x, c.y from fazenda_canteiros c
         where c.jogador_id = p_jogador and abs(c.x - b.x) + abs(c.y - b.y) = 1
        union
        select c.posicao, c.x, c.y from fazenda_canteiros c join bloco o on abs(c.x - o.x) + abs(c.y - o.y) = 1
         where c.jogador_id = p_jogador)
      select c.posicao, c.cultura, c.x, c.y from bloco o
        join fazenda_canteiros c on c.jogador_id = p_jogador and c.posicao = o.posicao
        join fazenda_culturas u on u.id = c.cultura
       where c.estado = 'plantado'
         and now() >= c.plantado_em + make_interval(secs => u.tempo_seg)
         and now() < c.plantado_em + make_interval(secs => u.tempo_seg + greatest(u.tempo_seg * 2, 3600))
    loop
      exit when v_livre <= 0 or not fazenda_gastar_energia(p_jogador, 2);
      begin
        v_qtd := fazenda_aplicar(p_jogador, 'colher', k.posicao, null, true);   -- cai no celeiro...
        perform fazenda_bau_guardar(p_jogador, b.x, b.y, k.cultura, v_qtd, k.x, k.y);   -- ...e passa para o baú
        v_livre := v_livre - v_qtd;
      exception when others then null; end;
    end loop;

    -- cercados encostados: coleta o produto (para o baú) e dá ração (do baú, se ele tiver; senão do celeiro)
    for m in
      select a.id, a.alimentado_em, t.tempo_seg, t.produto, t.racao, t.racao_qtd, p.x as px, p.y as py
        from fazenda_animais a
        join fazenda_animais_tipos t on t.id = a.tipo
        join fazenda_construcoes p on p.jogador_id = p_jogador and p.tipo = 'cercado_' || a.tipo
        join fazenda_itens i on i.id = p.tipo
       where a.jogador_id = p_jogador
         and (((b.x = p.x - 1 or b.x = p.x + i.largura) and b.y between p.y and p.y + i.altura - 1)
           or ((b.y = p.y - 1 or b.y = p.y + i.altura) and b.x between p.x and p.x + i.largura - 1))
    loop
      begin
        if m.alimentado_em is not null and now() >= m.alimentado_em + make_interval(secs => m.tempo_seg)
           and v_livre > 0 and fazenda_gastar_energia(p_jogador, 2) then
          perform fazenda_animal_um(p_jogador, m.id, 'coletar', true);
          perform fazenda_bau_guardar(p_jogador, b.x, b.y, m.produto, 1, m.px, m.py);
          v_livre := v_livre - 1;
          m.alimentado_em := null;
        end if;
      exception when others then null;
      end;
      begin
        if m.alimentado_em is null and fazenda_energia_atualizar(p_jogador) >= fazenda_energia_preco(p_jogador, 2) then
          if coalesce((select quantidade from fazenda_bau_itens where jogador_id = p_jogador and x = b.x and y = b.y and item = m.racao), 0) >= m.racao_qtd then
            update fazenda_bau_itens set quantidade = quantidade - m.racao_qtd where jogador_id = p_jogador and x = b.x and y = b.y and item = m.racao;
            insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, m.racao, m.racao_qtd)   -- passa pelo celeiro
            on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
            perform fazenda_viagem(p_jogador, m.racao, m.racao_qtd, b.x, b.y, m.px, m.py, true, now());
            v_livre := v_livre + m.racao_qtd;
          end if;
          perform fazenda_animal_um(p_jogador, m.id, 'alimentar', true);   -- sem ração: pula (e desfaz o de cima)
          perform fazenda_gastar_energia(p_jogador, 2);
        end if;
      exception when others then null;
      end;
    end loop;

    -- árvores do pomar (e a amoreira) encostadas: colhe as frutas prontas
    for arv in
      select c.x, c.y, c.tipo, i.produz, i.produz_qtd from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
       where c.jogador_id = p_jogador and i.produz is not null and i.entradas is null
         and abs(c.x - b.x) + abs(c.y - b.y) = 1
         and (c.colhido_em is null or now() >= c.colhido_em + make_interval(secs => i.produz_seg))
    loop
      exit when v_livre <= 0 or not fazenda_gastar_energia(p_jogador, 2);
      update fazenda_construcoes set colhido_em = fazenda_colhido_agora(p_jogador, arv.tipo) where jogador_id = p_jogador and x = arv.x and y = arv.y;
      insert into fazenda_bau_itens (jogador_id, x, y, item, quantidade) values (p_jogador, b.x, b.y, arv.produz, arv.produz_qtd)
      on conflict (jogador_id, x, y, item) do update set quantidade = fazenda_bau_itens.quantidade + excluded.quantidade;
      perform fazenda_viagem(p_jogador, arv.produz, arv.produz_qtd, arv.x, arv.y, b.x, b.y, true, now());
      v_livre := v_livre - arv.produz_qtd;
    end loop;

    -- encostado no lago (x 24..29, y 14..18): pega o cesto do Bira
    if ((b.x in (23, 30) and b.y between 14 and 18) or (b.y in (13, 19) and b.x between 24 and 29))
       and v_livre > 0 and fazenda_energia_atualizar(p_jogador) >= fazenda_energia_preco(p_jogador, 2) then
      v_peixes := fazenda_cesto(p_jogador, v_livre);
      if v_peixes <> '{}'::jsonb then
        perform fazenda_gastar_energia(p_jogador, 2);
        for e in select key as item, value::int as qtd from jsonb_each_text(v_peixes) loop
          insert into fazenda_bau_itens (jogador_id, x, y, item, quantidade) values (p_jogador, b.x, b.y, e.item, e.qtd)
          on conflict (jogador_id, x, y, item) do update set quantidade = fazenda_bau_itens.quantidade + excluded.quantidade;
          perform fazenda_viagem(p_jogador, e.item, e.qtd, least(greatest(b.x, 24), 29), least(greatest(b.y, 14), 18), b.x, b.y, true, now());
          v_livre := v_livre - e.qtd;
        end loop;
      end if;
    end if;
  end loop;
end;
$$;

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
begin
  select cafe_de, cafe_ate into v_cafe_de, v_cafe_ate from fazenda_jogadores where id = p_jogador;
  for a in
    select h.tipo, h.nivel, h.credito, h.atualizado_em, t.funcao, t.alvo
      from fazenda_ajudantes h join fazenda_ajudantes_tipos t on t.id = h.tipo
     where h.jogador_id = p_jogador
     order by (t.funcao = 'colher') desc, t.ordem   -- fase 48: quem colhe vem antes de quem ara as murchas
       for update of h
  loop
    -- o eletricista não faz tarefas: ele baixa o gasto de energia (fazenda_energia_preco)
    continue when a.funcao = 'energia';
    -- fase 43: com o café (diamantes) o tempo dentro dele vale em dobro
    v_seg := extract(epoch from now() - a.atualizado_em)::real
           + case when v_cafe_ate is null then 0
                  else greatest(extract(epoch from least(now(), v_cafe_ate) - greatest(a.atualizado_em, v_cafe_de))::real, 0) end;
    v_cred := least(a.credito + v_seg / 3600 * fazenda_ritmo(a.nivel), fazenda_ritmo(a.nivel) * 8);
    v_n := floor(v_cred);
    v_feito := 0;

    if v_n > 0 and a.funcao = 'colher' then
      -- fase 48: também o que murchou depois da última olhada dele (até 8 h): com a fazenda fechada ele
      -- teria colhido a tempo; o que murcha primeiro vai primeiro
      for c in
        select cc.posicao, now() >= cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) as murcha
          from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
         where cc.jogador_id = p_jogador and cc.estado = 'plantado'
           and now() >= cc.plantado_em + make_interval(secs => k.tempo_seg)
           and cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600))
               > greatest(a.atualizado_em, now() - interval '8 hours')
         order by cc.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) limit v_n
      loop
        begin perform fazenda_aplicar(p_jogador, case when c.murcha then 'colher_tarde' else 'colher' end, c.posicao, null, true); v_feito := v_feito + 1;
        exception when others then null; end;
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
          v_feito := v_feito + 1;
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
        v_feito := v_feito + 1;
      end loop;
      -- ...e enche o estoque com o que tem no celeiro, uma receita por vez em rodízio (a parada já começa)
      v_ok := true;
      while v_ok and v_feito < v_n loop
        v_ok := false;
        for c in
          select k.x, k.y, i.entradas from fazenda_construcoes k join fazenda_itens i on i.id = k.tipo
           where k.jogador_id = p_jogador and i.entradas is not null
             and k.estoque + (k.iniciado_em is not null)::int < fazenda_estoque_max()
           order by i.ordem, k.x, k.y
        loop
          exit when v_feito >= v_n;
          if fazenda_abastecer(p_jogador, c.entradas, 1) = 1 then
            update fazenda_construcoes
               set iniciado_em = coalesce(iniciado_em, now()),
                   estoque = estoque + case when iniciado_em is null then 0 else 1 end
             where jogador_id = p_jogador and x = c.x and y = c.y;
            v_feito := v_feito + 1;
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
        begin perform fazenda_aplicar(p_jogador, 'arar', c.posicao, null, true); v_feito := v_feito + 1;
        exception when others then null; end;
      end loop;
      -- sobrou tempo: aduba os canteiros que estão crescendo (+1 item na colheita de cada um)
      if v_feito < v_n then
        for c in
          select cc.posicao from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
           where cc.jogador_id = p_jogador and cc.estado = 'plantado' and not cc.adubado
             and now() < cc.plantado_em + make_interval(secs => k.tempo_seg)
           order by cc.plantado_em limit v_n - v_feito
        loop
          begin perform fazenda_aplicar(p_jogador, 'adubar', c.posicao, null, true); v_feito := v_feito + 1;
          exception when others then null; end;
        end loop;
      end if;

    elsif a.funcao = 'plantar' and coalesce((select carregado_antes > now() - interval '2 minutes' from fazenda_jogadores where id = p_jogador), false) then
      -- com o jogador na fazenda ela descansa (o tempo online não conta para ela)
      update fazenda_ajudantes set atualizado_em = now() where jogador_id = p_jogador and tipo = a.tipo;
      continue;

    elsif v_n > 0 and a.funcao = 'plantar' then
      v_nivel := fazenda_nivel((select xp from fazenda_jogadores where id = p_jogador));
      for c in
        select posicao from fazenda_canteiros
         where jogador_id = p_jogador and estado = 'arado' order by posicao limit v_n
      loop
        -- rodízio com todas as sementes da estação que o nível libera: a menos plantada primeiro,
        -- pulando as que o dinheiro não paga
        v_ok := false;
        for v_sem in
          select k.id from fazenda_culturas k
           where k.tipo = 'cultura' and k.nivel_min <= v_nivel
             and (k.estacao is null or k.estacao = fazenda_estacao_em(now()))
             and k.custo <= (select moedas from fazenda_jogadores where id = p_jogador)
           order by (select count(*) from fazenda_canteiros cc
                      where cc.jogador_id = p_jogador and cc.estado = 'plantado' and cc.cultura = k.id), k.ordem
        loop
          begin
            perform fazenda_aplicar(p_jogador, 'plantar', c.posicao, v_sem, true);
            v_feito := v_feito + 1; v_ok := true;
            exit;
          exception when others then null;
          end;
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
        begin
          if c.erva and v_feito < v_n then perform fazenda_aplicar(p_jogador, 'erva', c.posicao, null, true); v_feito := v_feito + 1; end if;
          if c.praga and v_feito < v_n then perform fazenda_aplicar(p_jogador, 'praga', c.posicao, null, true); v_feito := v_feito + 1; end if;
          if c.seco and v_feito < v_n then perform fazenda_aplicar(p_jogador, 'seco', c.posicao, null, true); v_feito := v_feito + 1; end if;
        exception when others then null;
        end;
      end loop;

    elsif v_n > 0 and a.funcao = 'animal' then
      for m in
        select an.id, an.alimentado_em, t.tempo_seg from fazenda_animais an join fazenda_animais_tipos t on t.id = an.tipo
         where an.jogador_id = p_jogador and an.tipo = a.alvo order by an.id
      loop
        exit when v_feito >= v_n;
        -- coletar e dar ração em blocos separados: faltar ração não desfaz a coleta
        begin
          if m.alimentado_em is not null and now() >= m.alimentado_em + make_interval(secs => m.tempo_seg) then
            perform fazenda_animal_um(p_jogador, m.id, 'coletar', true);
            v_feito := v_feito + 1;
            m.alimentado_em := null;
          end if;
        exception when others then null;
        end;
        begin
          if m.alimentado_em is null and v_feito < v_n then
            perform fazenda_animal_um(p_jogador, m.id, 'alimentar', true);   -- sem ração no celeiro: pula
            v_feito := v_feito + 1;
          end if;
        exception when others then null;
        end;
      end loop;
    end if;

    -- fase 46: quem não fez nada não é regravado: o crédito continua saindo do tempo desde
    -- atualizado_em (até 8 h), igual; contratar/evoluir e o café fecham a conta antes (fazenda_ajudantes_fechar)
    if v_feito > 0 then
      update fazenda_ajudantes
         set credito = v_cred - v_feito, atualizado_em = now(), relatorio = relatorio + v_feito
       where jogador_id = p_jogador and tipo = a.tipo;
    end if;
  end loop;
end;
$$;

create or replace function public.fazenda_coletar(p_token text, p_x int, p_y int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  r    record;
  k    record;
begin
  select c.colhido_em, c.tipo, i.produz, i.produz_seg, i.produz_qtd, i.entradas into r
    from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y
     for update of c;
  if not found or r.produz is null or r.entradas is not null then raise exception 'item_invalido'; end if;
  if r.colhido_em is not null and now() < r.colhido_em + make_interval(secs => r.produz_seg) then
    raise exception 'nao_pronto';
  end if;
  select * into k from fazenda_culturas where id = r.produz;
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  values (v_id, r.produz, r.produz_qtd)
  on conflict (jogador_id, item)
  do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  update fazenda_construcoes set colhido_em = fazenda_colhido_agora(v_id, r.tipo) where jogador_id = v_id and x = p_x and y = p_y;
  update fazenda_jogadores set xp = xp + greatest(k.xp / 8, 1) where id = v_id;
  perform fazenda_missao(v_id, 'colher', r.produz_qtd);
  return jsonb_build_object('qtd', r.produz_qtd, 'item', r.produz, 'estado', fazenda_estado(v_id));
end;
$$;

-- comprar melhorias

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
    -- sempre o próximo terreno da fila (p_tipo é ignorado)
    if j.zonas >= jsonb_array_length(fazenda_zonas()) then raise exception 'terreno_max'; end if;
    select (z->>'custo')::int as custo, (z->>'nivel')::int as nivel into a
      from jsonb_array_elements(fazenda_zonas()) z
     where (z->>'n')::int = j.zonas + 1;
    if fazenda_nivel(j.xp) < a.nivel then raise exception 'nivel_insuficiente'; end if;
    if j.moedas < a.custo then raise exception 'moedas_insuficientes'; end if;
    update fazenda_jogadores set moedas = moedas - a.custo, zonas = zonas + 1 where id = v_id;

  elsif p_categoria = 'melhoria' then
    -- fase 57: o próximo nível da melhoria (p_tipo = adubo, pomar ou pes)
    select (n->>'nivel')::int as nivel, (n->>'custo')::int as custo into a
      from jsonb_array_elements(fazenda_melhorias_tipos()) m,
           jsonb_array_elements(m->'niveis') with ordinality as x(n, i)
     where m->>'id' = p_tipo
       and x.i = 1 + coalesce((select nivel from fazenda_melhorias where jogador_id = v_id and id = p_tipo), 0);
    if not found then raise exception 'melhoria_max'; end if;
    if fazenda_nivel(j.xp) < a.nivel then raise exception 'nivel_insuficiente'; end if;
    if j.moedas < a.custo then raise exception 'moedas_insuficientes'; end if;
    update fazenda_jogadores set moedas = moedas - a.custo where id = v_id;
    insert into fazenda_melhorias (jogador_id, id, nivel) values (v_id, p_tipo, 1)
    on conflict (jogador_id, id) do update set nivel = fazenda_melhorias.nivel + 1;

  else
    raise exception 'item_invalido';
  end if;

  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- +75% de XP com a fazenda completa

create or replace function public.fazenda_xp_dobro()
returns trigger language plpgsql set search_path = public as $$
declare
  v_mult real := 1;
begin
  if new.xp > old.xp and coalesce(current_setting('fazenda.xp_puro', true), '') <> '1' then
    if new.xp2_ate is not null and new.xp2_ate > now() then v_mult := v_mult + 1; end if;
    if new.bonus_nivel is not null and new.bonus_nivel = fazenda_nivel(old.xp) then v_mult := v_mult + 0.5; end if;
    -- fase 57: fazenda completa (do 20 em diante, metas em dia): mais 25%
    if new.bonus_nivel is not null and new.bonus_nivel = fazenda_nivel(old.xp) and fazenda_nivel(old.xp) >= 20 then v_mult := v_mult + 0.25; end if;
    if v_mult > 1 then new.xp := old.xp + round((new.xp - old.xp) * v_mult)::int; end if;
  end if;
  return new;
end;
$$;

revoke execute on function
  public.fazenda_melhorias_tipos(),
  public.fazenda_melhoria(uuid, text),
  public.fazenda_limite_maquina(text, int, int),
  public.fazenda_colhido_agora(uuid, text),
  public.fazenda_completa(uuid)
from public, anon, authenticated;

-- conferência: as três linhas devem aparecer
select 'melhorias' as ok where exists (select 1 from information_schema.tables where table_name = 'fazenda_melhorias')
union all select 'painel no nível 24: ' || public.fazenda_limite_maquina('painel_solar', 8, 24) || ', turbina: ' || public.fazenda_limite_maquina('turbina', 6, 24)
union all select 'energia 20% mais barata' where position('0.8' in pg_get_functiondef('public.fazenda_energia_preco(uuid, real)'::regprocedure)) > 0;
