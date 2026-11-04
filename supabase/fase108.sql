-- ============================================================
-- FAZENDINHA — Fase 108 (o que só tem na Ilha da Caveira Dourada: abacaxi, cana-roxa, especiarias,
-- bananeira e 4 oficinas piratas), só o que mudou.
-- Para o banco que já está no ar (com a fase 107): Supabase > SQL Editor > colar este arquivo > Run.
-- Rode ANTES do merge do PR.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 107 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not exists (select 1 from pg_proc where proname = 'fazenda_preco_chico') then
    raise exception 'Rode o fase107.sql antes deste. Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 108: o que só tem na Ilha da Caveira Dourada (tema pirata). Planta e constrói só na ilha (y 45 em
-- diante: fazenda_aplicar, fazenda_roca_um, fazenda_construir e fazenda_mover dão 'so_na_ilha' fora dela)
-- e não trava o nível (fazenda_conta_nivel).
-- • Sementes: abacaxi (46), cana-roxa (50) e especiarias (54).
-- • Pomar: a bananeira (48), que dá bananas.
-- • Oficinas: o engenho pirata (rapadura, 49), a casa das especiarias (tempero das Índias, 51), o forno de
--   bordo (biscoito de bordo, 53) e a despensa do navio (ração de marinheiro, 55). O produto vale 3,2x os
--   ingredientes, como as outras oficinas (fase 80).
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------
alter table public.fazenda_culturas add column if not exists so_ilha boolean not null default false;
alter table public.fazenda_itens add column if not exists so_ilha boolean not null default false;

insert into public.fazenda_culturas (id, nome, emoji, tempo_seg, custo, venda, rendimento, xp, nivel_min, ordem, tipo, so_ilha) values
  ('abacaxi',     'Abacaxi',      '🍍', 36000, 450,  95,  9, 130, 46, 23, 'cultura', true),
  ('cana_roxa',   'Cana-roxa',    '🎋', 43200, 520, 110, 10, 150, 50, 24, 'cultura', true),
  ('especiarias', 'Especiarias',  '🌶', 50400, 620, 135,  9, 175, 54, 25, 'cultura', true),
  ('banana',      'Banana',       '🍌', 1, 0, 280, 1,  32, 48, 112, 'produto', false),
  ('rapadura',    'Rapadura pirata', '🟫', 1, 0, 1060, 1, 105, 49, 113, 'produto', false),
  ('tempero_indias', 'Tempero das Índias', '🫙', 1, 0, 980, 1, 98, 51, 114, 'produto', false),
  ('biscoito_bordo', 'Biscoito de bordo', '🍪', 1, 0, 3645, 1, 300, 53, 115, 'produto', false),
  ('racao_marinheiro', 'Ração de marinheiro', '📦', 1, 0, 16900, 1, 1200, 55, 116, 'produto', false)
on conflict (id) do update set
  nome = excluded.nome, emoji = excluded.emoji, tempo_seg = excluded.tempo_seg, custo = excluded.custo, venda = excluded.venda,
  rendimento = excluded.rendimento, xp = excluded.xp, nivel_min = excluded.nivel_min, ordem = excluded.ordem,
  tipo = excluded.tipo, so_ilha = excluded.so_ilha;

insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, beleza, produz, produz_seg, produz_qtd, por_terreno, grupo, descricao, so_ilha) values
  ('bananeira', 'Bananeira', 'pomar', 60000, 48, 122, 3, 'banana', 46800, 7, 1, null,
   'Dá 7 bananas a cada 13 horas: toque nela para colher. Só na ilha. Pomar: 1 pé de cada fruta, +1 a cada 2 terrenos (até 4).', true)
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min, ordem = excluded.ordem,
  beleza = excluded.beleza, produz = excluded.produz, produz_seg = excluded.produz_seg, produz_qtd = excluded.produz_qtd,
  por_terreno = excluded.por_terreno, grupo = excluded.grupo, descricao = excluded.descricao, so_ilha = excluded.so_ilha;
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, largura, altura,
                                  produz, produz_seg, produz_qtd, entradas, limite, beleza, descricao, so_ilha) values
  ('engenho_pirata',   'Engenho pirata',      'oficina', 300000, 49, 99, 2, 3, 'rapadura',         7200, 1, '{"cana_roxa": 3}', 2, 5,
   '3 canas-roxas → rapadura pirata. Só na ilha.', true),
  ('casa_especiarias', 'Casa das especiarias', 'oficina', 350000, 51, 99, 2, 3, 'tempero_indias',  7200, 1, '{"especiarias": 2, "pimenta": 1}', 2, 5,
   '2 especiarias + 1 pimenta → tempero das Índias. Só na ilha.', true),
  ('forno_bordo',      'Forno de bordo',      'oficina', 400000, 53, 99, 2, 3, 'biscoito_bordo',   10800, 1, '{"abobora": 3, "rapadura": 1}', 2, 5,
   '3 trigos + 1 rapadura → biscoito de bordo (o pão duro que aguenta a viagem). Só na ilha.', true),
  ('despensa_navio',   'Despensa do navio',   'oficina', 450000, 55, 99, 2, 3, 'racao_marinheiro', 14400, 1, '{"biscoito_bordo": 1, "tempero_indias": 1, "banana": 2, "abacaxi": 1}', 2, 5,
   '1 biscoito de bordo + 1 tempero das Índias + 2 bananas + 1 abacaxi → ração de marinheiro. Só na ilha.', true)
on conflict (id) do update set
  nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo, nivel_min = excluded.nivel_min,
  ordem = excluded.ordem, largura = excluded.largura, altura = excluded.altura, produz = excluded.produz,
  produz_seg = excluded.produz_seg, produz_qtd = excluded.produz_qtd, entradas = excluded.entradas,
  limite = excluded.limite, beleza = excluded.beleza, descricao = excluded.descricao, so_ilha = excluded.so_ilha;

select public.fazenda_cache_montar();

-- as funções que mudaram

-- o valor de um catálogo, montado na hora
create or replace function public.fazenda_cache_valor(p_chave text)
returns jsonb language sql stable security definer set search_path = public as $$
  select case p_chave
    when 'culturas' then (
      select jsonb_agg(jsonb_build_object(
               'id', id, 'nome', nome, 'emoji', emoji, 'tempo_seg', tempo_seg,
               'custo', custo, 'venda', venda, 'rendimento', rendimento,
               'xp', xp, 'nivel_min', nivel_min, 'tipo', tipo, 'estacao', estacao, 'so_ilha', so_ilha)   -- (fase 108)
             order by ordem)
        from fazenda_culturas)
    when 'animais_tipos' then (select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_animais_tipos t)
    when 'conquistas_tipos' then (select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_conquistas_tipos t)
    when 'ajudantes_tipos' then (select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_ajudantes_tipos t)
    when 'melhorias_tipos' then fazenda_melhorias_tipos()
    when 'melhorias' then (select jsonb_object_agg(m->>'id', m) from jsonb_array_elements(fazenda_melhorias_tipos()) m)
  end;
$$;


-- ------------------------------------------------------------
-- Fase 90: só passa de nível quem tem tudo dos seus níveis (a regra votada: vale daqui para frente). O XP não
-- é mais a única coisa: para passar do nível N, o jogador precisa ter na fazenda tudo o que conta dos níveis
-- 1 a N (oficinas, cercados, máquinas, energia sem o cano e pomar; enfeites, caminhos, objetos, casas e praia
-- não contam). Ninguém caiu: o nível de cada um no dia da regra fica guardado (nivel_base) e não baixa; daí
-- para cima, só sobe quem completar o que falta. Nenhum XP sai.
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists nivel_trava int not null default 2;
alter table public.fazenda_jogadores add column if not exists nivel_base int;   -- fase 90: o nível no dia da regra (não baixa)
create or replace function public.fazenda_conta_nivel(p_categoria text, p_id text)
returns boolean language sql immutable as $$
  select p_categoria in ('oficina', 'bichos', 'maquina', 'energia', 'pomar') and p_id <> 'cano'
     and p_id not in ('bananeira', 'engenho_pirata', 'casa_especiarias', 'forno_bordo', 'despensa_navio');   -- fase 108: as da ilha não travam
$$;


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
  v_preco  int;   -- fase 72
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

  -- colher agora (fase 31): diamante deixa pronto na hora o que está crescendo, sem os
  -- problemas, e já colhe. Maduro não precisa de diamante: só colhe.
  -- fase 72: 1 diamante a cada 4 h que faltam (era 1 por planta: caro na alface, barato na baunilha)
  if p_acao = 'agora' then
    if p_bot then raise exception 'acao_invalida'; end if;
    if c.estado <> 'plantado' or now() >= v_murcho then raise exception 'nada_a_fazer'; end if;
    if now() < v_maduro then
      v_preco := greatest(1, ceil(extract(epoch from v_maduro - now())
                                  / (3600 * (fazenda_loja_diamantes()->'agora'->>'horas')::numeric)))::int;
      if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
      update fazenda_jogadores set diamantes = diamantes - v_preco where id = p_jogador;
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
    -- (fase 70: o XP de arar e plantar da fazenda completa vem na colheita: arar, desmanchar e fazer o
    -- canteiro de novo virava XP sem fim)
    if not p_bot and fazenda_nivel_de(j.xp, j.nivel_trava) <= 5 then update fazenda_jogadores set xp = xp + 1 where id = p_jogador; end if;

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
    if k.so_ilha and c.y < 45 then raise exception 'so_na_ilha'; end if;   -- fase 108
    -- semente de outra estação só cresce no alcance de uma estufa elétrica
    v_fora := k.estacao is not null and k.estacao <> fazenda_estacao_em(now());
    v_estufa := fazenda_protegido(p_jogador, 'estufa', c.x, c.y);
    if v_fora and not v_estufa then
      raise exception 'fora_de_estacao';
    end if;
    if fazenda_nivel_de(j.xp, j.nivel_trava) < k.nivel_min then
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
           plantado_em = now() - make_interval(secs => k.tempo_seg * fazenda_adiantar(
                           0.1 * fazenda_protegido(p_jogador, 'crescer', c.x, c.y)::int + 0.25 * v_estufa::int
                            + fazenda_melhoria(p_jogador, 'adubo'), j.crescer_ate)),   -- fase 57: adubo premium; fase 93: ampulheta
           erva = false, praga = false, seco = false, roubado = 0, adubado = false,
           prox_evento = now() + make_interval(secs => k.tempo_seg * (0.15 + random() * 0.35))
     where jogador_id = p_jogador and posicao = p_posicao;
    if not p_bot then
      perform fazenda_missao(p_jogador, 'plantar', 1);
      -- fase 57: fazenda completa: plantar também dá XP (fase 70: ele vem na colheita; plantar e arrancar
      -- em seguida virava XP sem fim)
      update fazenda_jogadores set semente = k.id where id = p_jogador;
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
             + (fazenda_clima_agora() = 'sol')::int                      -- colheita no sol (fase 71: uma conta por chamada)
             + fazenda_protegido(p_jogador, 'adubo', c.x, c.y)::int     -- cogumelos, barril, colmeia
             + c.adubado::int;                                          -- adubo do Seu Zé
    if fazenda_protegido(p_jogador, 'sorte', c.x, c.y) and random() < 0.15 then
      v_qtd := v_qtd * 2;                                               -- alvo
    end if;
    if j.colheita50_ate > now() then
      v_qtd := v_qtd + ceil(v_qtd / 2.0)::int;                          -- fase 93: balança de ouro (+50%)
    end if;
    insert into fazenda_celeiro (jogador_id, item, quantidade)
    values (p_jogador, k.id, v_qtd)
    on conflict (jogador_id, item)
    do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
    -- XP cheio da planta, mas o mesmo canteiro dá XP no máximo 1 vez a cada 8 min (fase 41)
    -- fase 72: o que ajudante, robô ou baú colhe dá metade do XP (antes, nada), somado e gravado uma
    -- vez só no fim da rodada deles (fazenda_bot_xp)
    v_xp_colheita := c.xp_em is null or c.xp_em <= now() - interval '8 minutes';
    if v_xp_colheita and p_bot then
      perform fazenda_bot_xp(p_jogador, k.xp / 2);
    elsif v_xp_colheita then
      -- fase 70: fazenda completa: + 2 (o XP de arar e plantar, que antes vinha na hora)
      update fazenda_jogadores set xp = xp + k.xp + fazenda_protegido(p_jogador, 'xp', c.x, c.y)::int + 2 * fazenda_completa(p_jogador)::int
       where id = p_jogador;
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


-- Fase 83: cuidar da roça do vizinho (o que mais tem nas fazendas abandonadas). Devolve o XP.
--   limpar: tira 1 planta murcha (o canteiro fica arado); até 2 por dia em cada fazenda, como salvar. 1 ajuda.
--   arar: canteiro vazio vira arado. 1 ajuda.
--   colher: a planta madura vai para o celeiro do dono (ele ganha metade do XP, como com o ajudante). 1 ajuda.
--   plantar:<semente>: só na fazenda abandonada, com a semente paga por quem ajuda (o nível e a estação
--     valem os de quem ajuda e de agora). 5 ajudas.
create or replace function public.fazenda_roca_um(p_ator uuid, p_dono uuid, p_posicao int, p_acao text)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  c    record;
  k    record;
  v_murcha boolean;
  v_un int;
  v_tipo text;
  v_cult text;
  v_xp int;
begin
  select * into c from fazenda_canteiros where jogador_id = p_dono and posicao = p_posicao for update;
  if not found then raise exception 'nada_a_fazer'; end if;
  v_murcha := false;
  if c.cultura is not null then
    select * into k from fazenda_culturas where id = c.cultura;
    v_murcha := c.estado = 'plantado' and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600));
  end if;
  if p_acao = 'limpar' then
    if not v_murcha then raise exception 'nada_a_fazer'; end if;
    if (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'limpar'
          and criado_em > now() - interval '1 day') >= 2 then
      raise exception 'ja_limpou';
    end if;
    perform fazenda_aplicar(p_dono, 'arar', p_posicao, null, true);
    v_un := 1; v_tipo := 'limpar'; v_cult := c.cultura;
  elsif p_acao = 'arar' then
    if c.estado <> 'vazio' then raise exception 'nada_a_fazer'; end if;
    perform fazenda_aplicar(p_dono, 'arar', p_posicao, null, true);
    v_un := 1; v_tipo := 'arar'; v_cult := null;   -- (canteiro vazio: sem planta)
  elsif p_acao = 'colher' then
    if c.estado <> 'plantado' or v_murcha or now() < c.plantado_em + make_interval(secs => k.tempo_seg) then raise exception 'nao_maduro'; end if;
    perform fazenda_aplicar(p_dono, 'colher', p_posicao, null, true);
    v_un := 1; v_tipo := 'colher'; v_cult := c.cultura;
  else   -- plantar:<semente>
    if not fazenda_abandonada(p_dono) then raise exception 'nao_abandonada'; end if;
    if c.estado <> 'arado' then raise exception 'precisa_arar'; end if;
    select * into k from fazenda_culturas where id = split_part(p_acao, ':', 2) and tipo = 'cultura';
    if not found then raise exception 'cultura_invalida'; end if;
    if k.estacao is not null and k.estacao <> fazenda_estacao_em(now()) then raise exception 'fora_de_estacao'; end if;
    if k.so_ilha and c.y < 45 then raise exception 'so_na_ilha'; end if;   -- fase 108
    if (select fazenda_nivel_de(xp, nivel_trava) from fazenda_jogadores where id = p_ator) < k.nivel_min then raise exception 'nivel_insuficiente'; end if;
    perform fazenda_lote_gastar(p_ator, k.custo);   -- (fase 87: no Ajudar tudo, sai no fim, numa gravação só)
    update fazenda_canteiros
       set estado = 'plantado', cultura = k.id, plantado_em = now(),
           erva = false, praga = false, seco = false, roubado = 0, adubado = false,
           prox_evento = now() + make_interval(secs => k.tempo_seg * (0.15 + random() * 0.35))
     where jogador_id = p_dono and posicao = p_posicao;
    v_un := 2; v_tipo := 'plantar'; v_cult := k.id;   -- (fase 85: 2 ajudas; eram 5)
  end if;
  -- fase 86: colher, arar e plantar dão XP 1 vez por dia em cada canteiro (para quem ajuda); de novo no
  -- mesmo canteiro, a ajuda vale para o dono mas não dá XP (o vai e volta de plantar e colher não sobe nível)
  if v_tipo in ('colher', 'arar', 'plantar') and exists (
       select 1 from fazenda_visitas
        where ator_id = p_ator and tipo = v_tipo and dono_id = p_dono and posicao = p_posicao
          and criado_em >= (fazenda_hoje()::timestamp at time zone 'America/Sao_Paulo')) then
    v_un := 0;
  end if;
  v_xp := fazenda_premiar_ajuda(p_ator, v_un, p_dono);
  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd, xp)
  values (p_ator, p_dono, v_tipo, p_posicao, now(), v_cult, 1, v_xp);   -- (fase 85: e o XP dado)
  if v_un > 0 then perform fazenda_missao_ajuda(p_ator, 1); end if;
  return v_xp;
end;
$$;


-- Colocar: igual a antes, mas o que tem guardado no depósito sai primeiro, de graça
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
  v_dep record;   -- fase 95
begin
  select * into j from fazenda_jogadores where id = v_id for update;

  -- canteiro: não é item da loja, é um lugar de plantar (limite pelo nível e terrenos)
  if p_tipo = 'canteiro' then
    if (select count(*) from fazenda_canteiros where jogador_id = v_id)
       >= fazenda_limite_canteiros(fazenda_nivel_de(j.xp, j.nivel_trava), fazenda_terrenos(j.zonas, j.direita) + 100 * j.ilha_terrenos) then
      raise exception 'limite_canteiros';
    end if;
    perform fazenda_checar_lugar(v_id, fazenda_terrenos(j.zonas, j.direita) + 100 * j.ilha_terrenos, p_x, p_y, 1, 1);
    select min(g) into v_pos from generate_series(0, 299) g   -- fase 56: eram 0..99
     where not exists (select 1 from fazenda_canteiros where jogador_id = v_id and posicao = g);
    if v_pos is null then raise exception 'limite_canteiros'; end if;
    -- fase 70: canteiro novo espera os 8 min para dar XP de colheita (desmanchar e fazer de novo zerava)
    insert into fazenda_canteiros (jogador_id, posicao, estado, x, y, xp_em) values (v_id, v_pos, 'vazio', p_x, p_y, now());
    return jsonb_build_object('estado', fazenda_estado(v_id), 'posicao', v_pos);
  end if;

  select * into i from fazenda_itens where id = p_tipo;
  if not found then raise exception 'item_invalido'; end if;
  if fazenda_nivel_de(j.xp, j.nivel_trava) < i.nivel_min then raise exception 'nivel_insuficiente'; end if;
  perform fazenda_checar_lugar(v_id, fazenda_terrenos(j.zonas, j.direita) + 100 * j.ilha_terrenos, p_x, p_y, i.largura, i.altura);
  -- fase 73: o que é da praia só vai na areia do Litoral (y 32 a 36)
  if i.categoria = 'praia' and not (p_y >= 32 and p_y + i.altura - 1 <= 36) then raise exception 'so_na_areia'; end if;
  if i.so_ilha and p_y < 45 then raise exception 'so_na_ilha'; end if;   -- fase 108
  if i.limite is not null   -- fase 57: painel solar e turbina sobem com o nível
     and (select count(*) from fazenda_construcoes where jogador_id = v_id and tipo = i.id)
         >= fazenda_limite_maquina(i.id, i.limite, fazenda_nivel_de(j.xp, j.nivel_trava)) then
    raise exception 'limite_maquina';
  end if;
  -- itens por terreno (amoreira): mais terreno, mais pés (igual a maxItem em fazenda.js); fase 47: no
  -- pomar, cada fruta tem 1 pé e +1 a cada 2 terrenos (até 4); quem já passou fica com as que tem
  if i.por_terreno is not null
     and (select count(*) from fazenda_construcoes c join fazenda_itens k on k.id = c.tipo
           where c.jogador_id = v_id and (c.tipo = i.id or (i.grupo is not null and k.grupo = i.grupo)))
         >= (case when i.categoria = 'pomar'   -- fase 57: + os pés da melhoria "Mais pés de fruta"
                  then i.por_terreno * (1 + (j.zonas + j.direita) / 2) + fazenda_melhoria(v_id, 'pes')::int   -- (fase 78: + os da direita)
                  else i.por_terreno * (1 + j.zonas + j.direita) end) then
    raise exception 'limite_terreno';
  end if;
  if (select count(*) from fazenda_construcoes where jogador_id = v_id) >= fazenda_max_construcoes(fazenda_terrenos(j.zonas, j.direita) + 100 * j.ilha_terrenos) then
    raise exception 'limite_construcoes';
  end if;
  -- fase 95: tem um igual guardado no depósito? sai dele, de graça (e guarda o que foi pago na época)
  select id, pago into v_dep from fazenda_deposito where jogador_id = v_id and tipo = i.id order by id limit 1 for update;
  if v_dep.id is not null then
    delete from fazenda_deposito where id = v_dep.id;
    if i.categoria = 'energia' then
      perform fazenda_energia_atualizar(v_id);
      update fazenda_jogadores set energia_em = now() where id = v_id;
    end if;
    insert into fazenda_construcoes (jogador_id, x, y, tipo, colhido_em, pago) values (v_id, p_x, p_y, i.id, now(), v_dep.pago);
    return jsonb_build_object('estado', fazenda_estado(v_id), 'do_deposito', true, 'deposito', fazenda_deposito_mapa(v_id));
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
  -- fase 72: guarda o que pagou (desmanchar devolve a metade disso, não do preço de hoje)
  insert into fazenda_construcoes (jogador_id, x, y, tipo, colhido_em, pago) values (v_id, p_x, p_y, i.id, now(), v_custo);
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;


-- Leva uma construção de (x, y) para (nx, ny)
-- fase 73b: p_leve devolve só {ok, x, y} (o jogo já mostra o item no lugar; a fazenda inteira a cada
-- movimento travava quem movia várias coisas seguidas). Sem ele, como antes (o jogo antigo no cache).
create or replace function public.fazenda_mover(p_token text, p_x int, p_y int, p_nx int, p_ny int, p_leve boolean default false)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id  uuid := fazenda_auth(p_token);
  j     record;
  i     record;
  v_pos int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  -- canteiro (mesmo plantado: a planta vai junto)
  select posicao into v_pos from fazenda_canteiros where jogador_id = v_id and x = p_x and y = p_y;
  if v_pos is not null then
    perform fazenda_checar_lugar(v_id, fazenda_terrenos(j.zonas, j.direita) + 100 * j.ilha_terrenos, p_nx, p_ny, 1, 1, null, null, v_pos);
    update fazenda_canteiros set x = p_nx, y = p_ny where jogador_id = v_id and posicao = v_pos;
    if p_leve then return jsonb_build_object('ok', true, 'x', p_nx, 'y', p_ny); end if;
    return jsonb_build_object('estado', fazenda_estado(v_id));
  end if;

  select k.* into i from fazenda_construcoes c join fazenda_itens k on k.id = c.tipo
   where c.jogador_id = v_id and c.x = p_x and c.y = p_y;
  if not found then raise exception 'item_invalido'; end if;
  perform fazenda_checar_lugar(v_id, fazenda_terrenos(j.zonas, j.direita) + 100 * j.ilha_terrenos, p_nx, p_ny, i.largura, i.altura, p_x, p_y);
  if i.categoria = 'praia' and not (p_ny >= 32 and p_ny + i.altura - 1 <= 36) then raise exception 'so_na_areia'; end if;   -- fase 73
  if i.so_ilha and p_ny < 45 then raise exception 'so_na_ilha'; end if;   -- fase 108
  update fazenda_construcoes set x = p_nx, y = p_ny
   where jogador_id = v_id and x = p_x and y = p_y;
  if not found then raise exception 'item_invalido'; end if;
  -- o que está guardado no baú e o que já chegou pelo cano na oficina vão junto (fase 39)
  update fazenda_bau_itens set x = p_nx, y = p_ny where jogador_id = v_id and x = p_x and y = p_y;
  update fazenda_oficina_itens set x = p_nx, y = p_ny where jogador_id = v_id and x = p_x and y = p_y;
  if p_leve then return jsonb_build_object('ok', true, 'x', p_nx, 'y', p_ny); end if;
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;


select public.fazenda_cache_montar();

-- conferência: tem que aparecer "fase 108 ok", 3 sementes e 5 itens da ilha
select case when exists (select 1 from public.fazenda_itens where id = 'despensa_navio' and so_ilha) then 'fase 108 ok' else 'não aplicou' end as resultado,
       (select count(*) from public.fazenda_culturas where so_ilha) as sementes_da_ilha,
       (select count(*) from public.fazenda_itens where so_ilha) as itens_da_ilha;
