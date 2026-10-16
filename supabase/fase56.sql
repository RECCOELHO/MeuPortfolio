-- ============================================================
-- FAZENDINHA — Fase 56 (consertos de 15/10), só o que mudou.
-- Para o banco que já está no ar: Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- ------------------------------------------------------------
-- Fase 56: consertos e balanceamento (ideias de 15/10).
-- • Canteiros: a posição ia só até 99, então o 101º dava limite_canteiros mesmo com o limite em 102
--   (fazenda_canteiros_posicao_check e fazenda_construir, lá em cima, agora vão até 299).
-- • Energia: tudo gasta 40% menos (fazenda_energia_preco) e o supercapacitor guarda 800 ⚡ (era 500).
-- • Feira: o celeiro lembra quanto de cada item veio da feira (da_feira). Vender isso ao jogo dá as
--   moedas, mas não o XP (fazenda_vender); comprar na feira para revender virava XP comprado.
--   Usar em receitas, entregas e missões continua igual. Quando a quantidade cai por qualquer outro
--   motivo, da_feira acompanha (nunca passa da quantidade).
-- ------------------------------------------------------------
alter table public.fazenda_celeiro add column if not exists da_feira int not null default 0;

create or replace function public.fazenda_celeiro_da_feira()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.da_feira > new.quantidade then new.da_feira := greatest(new.quantidade, 0); end if;
  return new;
end;
$$;
drop trigger if exists fazenda_celeiro_da_feira on public.fazenda_celeiro;
create trigger fazenda_celeiro_da_feira before update on public.fazenda_celeiro
  for each row execute function public.fazenda_celeiro_da_feira();

-- canteiros: posição até 299
alter table public.fazenda_canteiros drop constraint if exists fazenda_canteiros_posicao_check;
alter table public.fazenda_canteiros add constraint fazenda_canteiros_posicao_check check (posicao between 0 and 299);

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
  if i.limite is not null
     and (select count(*) from fazenda_construcoes where jogador_id = v_id and tipo = i.id) >= i.limite then
    raise exception 'limite_maquina';
  end if;
  -- itens por terreno (amoreira): mais terreno, mais pés (igual a maxItem em fazenda.js); fase 47: no
  -- pomar, cada fruta tem 1 pé e +1 a cada 2 terrenos (até 4); quem já passou fica com as que tem
  if i.por_terreno is not null
     and (select count(*) from fazenda_construcoes c join fazenda_itens k on k.id = c.tipo
           where c.jogador_id = v_id and (c.tipo = i.id or (i.grupo is not null and k.grupo = i.grupo)))
         >= (case when i.categoria = 'pomar' then i.por_terreno * (1 + j.zonas / 2) else i.por_terreno * (1 + j.zonas) end) then
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

-- energia: 40% mais barata e supercapacitor com 800 ⚡

create or replace function public.fazenda_energia_preco(p_jogador uuid, p_qtd real)
returns real language sql stable security definer set search_path = public as $$
  select (p_qtd * 0.6 * coalesce((select case h.nivel when 1 then 0.8 when 2 then 0.65 else 0.5 end
                              from fazenda_ajudantes h join fazenda_ajudantes_tipos t on t.id = h.tipo
                             where h.jogador_id = p_jogador and t.funcao = 'energia' limit 1), 1))::real;
$$;

create or replace function public.fazenda_capacidade(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select 50 + coalesce(sum(case c.tipo when 'bateria' then 150 when 'supercap' then 800 else 0 end), 0)::int
    from fazenda_construcoes c where c.jogador_id = p_jogador;
$$;

-- descrições das máquinas com o gasto novo

insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, efeito, raio, limite, descricao) values
  ('cano',          'Cano de vidro',      'energia',    25, 16, 79, 'cano',       0, null, 'Canos encostados formam uma rede que liga baús, oficinas e o celeiro. A rede enche sozinha o estoque das oficinas com o que tem nos baús e no celeiro (1,2 ⚡ por receita); o produto vai para outra oficina que usa ele, para o celeiro ou para um baú; o que sobra no baú vai para o celeiro (1,2 ⚡ por viagem). Dá para ver cada item passando.'),
  ('painel_solar',  'Painel solar',       'energia',  2500, 16, 80, 'solar',      0, 8, 'Gera até 12 ⚡/h de dia (sol forte: 14; nublado: 5; chuva: 3). À noite, nada: no jogo, o dia e a noite se revezam a cada 2 horas.'),
  ('bateria',       'Banco de baterias',  'energia',  2000, 16, 81, 'bateria',    0, 4, 'Guarda mais 150 ⚡ (sem bateria, a caixa de luz guarda só 50). Bateria cheia: o que sobra é vendido, 1 moeda a cada 5 ⚡.'),
  ('turbina',       'Turbina eólica',     'energia',  4000, 17, 82, 'eolica',     0, 6, 'Gera 8 ⚡/h de dia e de noite; 30 ⚡/h na ventania e 14 na chuva. Na calmaria (sem vento, uns 25% do tempo fora da ventania e da chuva), cai para 3 ⚡/h: o painel de energia avisa quando vem.'),
  ('estufa',        'Estufa elétrica',    'energia',  6000, 18, 83, 'estufa',     2, 3, 'Canteiros em volta (2) aceitam sementes de qualquer estação e crescem 25% mais rápido. Gasta 3 ⚡ por plantio.'),
  ('gerador_bio',   'Gerador a biomassa', 'energia',  6000, 19, 84, 'biomassa',   0, 2, 'Ligado, queima 1 milho a cada 30 min: 50 ⚡/h. Toque nele para ligar ou desligar.'),
  ('triturador',    'Triturador',         'energia', 10000, 20, 85, 'triturar',   0, 1, 'As oficinas rendem 2 produtos por receita. Gasta 6 ⚡ por receita.'),
  ('supercap',      'Supercapacitor',     'energia',  9000, 21, 86, 'bateria',    0, 2, 'Guarda mais 800 ⚡.'),
  ('fabrica_auto',  'Fábrica automática', 'energia', 15000, 22, 87, 'automatico', 0, 1, 'Um pedaço do celeiro em qualquer lugar: a rede de canos encostada nela leva e traz do celeiro como se o cano chegasse até ele (sem mexer na ração reservada).'),
  ('robo_colheita', 'Robô colheitador',   'energia', 18000, 23, 88, 'robo',       3, 2, 'Colhe, ara e replanta sozinho os canteiros em volta (3). Gasta 2,4 ⚡ por colheita e 1,2 por plantio.'),
  ('aspersor',      'Aspersor elétrico',  'energia', 12000, 24, 89, 'aspersor',   3, 4, 'Nenhuma erva, praga ou seca nos canteiros em volta (3). Gasta 1,2 ⚡ por problema evitado.'),
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
    ('bau',           'missao',       0,  3, '+25% de moedas nas missões. Com energia, guarda em si (até 200 itens) o que recolhe: encostado num bloco de canteiros, colhe o que amadurece; num cercado, coleta e dá ração aos bichos; numa árvore do pomar, colhe as frutas; no lago, pega o cesto do Bira (1,2 ⚡ cada). Com canos, manda para as oficinas e o celeiro.', null, null, null),
    ('lampiao',       null,           0,  3, 'Acende sozinho de noite e ilumina em volta. +3 de beleza (beleza dá bônus nas vendas).', null, null, null),
    ('casa_vermelha', null,           0, 20, 'Casinha: +20 de beleza (beleza dá bônus nas vendas).', null, null, null),
    ('casa_azul',     null,           0, 30, 'Casinha: +30 de beleza (beleza dá bônus nas vendas).', null, null, null)
  ) v(id, efeito, raio, beleza, descricao, produz, produz_seg, produz_qtd)
 where i.id = v.id;

-- feira: o que veio dela não dá XP na revenda ao jogo

create or replace function public.fazenda_vender(p_token text, p_item text default null, p_quantidade int default null)
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

create or replace function public.fazenda_feira_comprar(p_token text, p_id bigint)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_r     jsonb := fazenda_feira_regras();
  a       record;
  v_total int;
  v_taxa  int;
begin
  select * into a from fazenda_feira where id = p_id for update;
  if not found or a.vendido_em is not null
     or a.criado_em < now() - make_interval(hours => (v_r->>'horas')::int) then
    raise exception 'anuncio_invalido';   -- já vendido, cancelado ou vencido
  end if;
  if a.vendedor_id = v_id then raise exception 'anuncio_seu'; end if;
  if (select count(*) from fazenda_feira where comprador_id = v_id and vendido_em > now() - interval '1 day')
     >= (v_r->>'compras_dia')::int then
    raise exception 'limite_compras';
  end if;
  v_total := a.qtd * a.preco;
  v_taxa := ceil(v_total * (v_r->>'taxa')::int / 100.0)::int;
  if (select moedas from fazenda_jogadores where id = v_id for update) < v_total then raise exception 'moedas_insuficientes'; end if;
  update fazenda_jogadores set moedas = moedas - v_total where id = v_id;
  update fazenda_jogadores set moedas = moedas + v_total - v_taxa where id = a.vendedor_id;
  insert into fazenda_celeiro (jogador_id, item, quantidade, da_feira) values (v_id, a.item, a.qtd, a.qtd)   -- fase 56: da_feira
  on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade,
                                               da_feira = fazenda_celeiro.da_feira + excluded.da_feira;
  update fazenda_feira set comprador_id = v_id, vendido_em = now() where id = p_id;
  return jsonb_build_object('item', a.item, 'qtd', a.qtd, 'total', v_total,
                            'vendedor', (select apelido from fazenda_jogadores where id = a.vendedor_id),
                            'estado', fazenda_estado(v_id));
end;
$$;

revoke execute on function public.fazenda_celeiro_da_feira() from public, anon, authenticated;

-- conferência: as três linhas devem aparecer
select 'canteiros até 299' as ok where exists (select 1 from pg_constraint where conname = 'fazenda_canteiros_posicao_check' and pg_get_constraintdef(oid) like '%299%')
union all select 'coluna da_feira' where exists (select 1 from information_schema.columns where table_name = 'fazenda_celeiro' and column_name = 'da_feira')
union all select 'energia 40% mais barata' where position('0.6' in pg_get_functiondef('public.fazenda_energia_preco(uuid, real)'::regprocedure)) > 0;
