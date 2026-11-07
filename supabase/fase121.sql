-- ============================================================
-- FAZENDINHA — Fase 121 (estações e clima valendo: a seca murcha mais rápido, cada planta rende mais na
-- estação dela e no inverno os bichos comem mais), só o que mudou.
-- Para o banco que já está no ar (com a fase 120): Supabase > SQL Editor > colar este arquivo > Run.
-- Rode ANTES do merge do PR.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 120 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not exists (select 1 from pg_proc where proname = 'fazenda_teste_entrar') then
    raise exception 'Rode o fase120.sql antes deste. Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 121: as estações e o clima valendo mais no jogo (o clima já mexia: sol +1 na colheita, chuva rega,
-- calor seca, ventania espalha praga, nublado não traz problema).
-- • Seca: a planta madura com seca (sem regar) murcha na metade do tempo (fazenda_murcha_seg). A chuva rega
--   só o que ainda cresce; a madura com seca precisa de rega na mão (ou do irrigador/aspersor antes).
-- • Cada planta tem a estação boa (fazenda_culturas.estacao_boa): colhida nela, rende um quarto a mais
--   (no mínimo +1). As de estação rendem mais quando colhidas ainda na estação delas.
-- • Inverno: os bichos comem 1 ração a mais por refeição (fazenda_racao_qtd).
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------
alter table public.fazenda_culturas add column if not exists estacao_boa text;   -- fase 121: a estação em que a planta rende mais
alter table public.fazenda_murchas drop constraint if exists fazenda_murchas_motivo_check;   -- fase 121: e a seca
alter table public.fazenda_murchas add constraint fazenda_murchas_motivo_check
  check (motivo in ('sem_colhedor', 'descansando', 'fechada', 'nao_deu_conta', 'seca'));

-- fase 121: quanto tempo a planta madura aguenta antes de murchar: o dobro do tempo dela (no mínimo 1 h); com
-- seca (sem regar), a metade disso (o tempo dela, no mínimo 30 min)
create or replace function public.fazenda_murcha_seg(p_tempo int, p_seco boolean)
returns int language sql immutable as $$
  select case when coalesce(p_seco, false) then greatest(p_tempo, 1800) else greatest(p_tempo * 2, 3600) end;
$$;

-- fase 121: a ração de cada refeição: no inverno, os bichos comem 1 a mais
create or replace function public.fazenda_racao_qtd(p_qtd int)
returns int language sql stable as $$
  select p_qtd + (fazenda_estacao_em(now()) = 'inverno')::int;
$$;

-- fase 121: o extra da colheita na estação da planta (um quarto do que ela rende, no mínimo 1)
create or replace function public.fazenda_bonus_estacao(p_estacao_boa text, p_rendimento int)
returns int language sql stable as $$
  select case when p_estacao_boa is not null and p_estacao_boa = fazenda_estacao_em(now())
              then greatest(1, round(p_rendimento * 0.25))::int else 0 end;
$$;

-- a estação boa de cada planta (as de estação rendem mais quando colhidas na estação delas)
update public.fazenda_culturas k set estacao_boa = v.e
  from (values ('alface', 'primavera'), ('girassol', 'primavera'), ('algodao', 'primavera'), ('cana_roxa', 'primavera'),
               ('milho', 'verao'), ('tomate', 'verao'), ('cana', 'verao'), ('pimenta', 'verao'), ('abacaxi', 'verao'),
               ('batata', 'outono'), ('abobora', 'outono'), ('uva', 'outono'),
               ('cenoura', 'inverno'), ('cafe', 'inverno'), ('baunilha', 'inverno'), ('especiarias', 'inverno')) v(id, e)
 where k.id = v.id;
update public.fazenda_culturas set estacao_boa = estacao where estacao is not null;

select public.fazenda_cache_montar();

-- as funções que mudaram

-- Materializa os problemas (erva, praga, seca) que "aconteceram" enquanto a
-- planta crescia. Só ocorrem antes de a planta amadurecer.
create or replace function public.fazenda_tick(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  r        record;
  v_maduro timestamptz;
  v_evt    timestamptz;
  v_erva   boolean;
  v_praga  boolean;
  v_seco   boolean;
  v_tipo   int;
  i        int;
  v_ce     text;
begin
  -- chovendo agora: a chuva rega tudo (some a seca dos canteiros)
  if fazenda_clima_agora() = 'chuva' then   -- (fase 71: uma conta por chamada)
    update fazenda_canteiros c set seco = false from fazenda_culturas k   -- (fase 121: só o que ainda cresce)
     where c.jogador_id = p_jogador and c.estado = 'plantado' and c.seco and k.id = c.cultura
       and now() < c.plantado_em + make_interval(secs => k.tempo_seg);
  end if;
  for r in
    select c.posicao, c.x, c.y, c.plantado_em, c.prox_evento, c.erva, c.praga, c.seco, k.tempo_seg
      from fazenda_canteiros c
      join fazenda_culturas k on k.id = c.cultura
     where c.jogador_id = p_jogador
       and c.estado = 'plantado'
       and c.prox_evento is not null
       and c.prox_evento <= now()
       for update of c
  loop
    v_maduro := r.plantado_em + make_interval(secs => r.tempo_seg);
    v_evt := r.prox_evento;
    v_erva := r.erva; v_praga := r.praga; v_seco := r.seco;
    i := 0;
    while v_evt <= now() and v_evt < v_maduro and i < 3 loop
      v_tipo := floor(random() * 3)::int;
      v_ce := fazenda_clima_em(v_evt);                                     -- o clima na hora do problema
      if v_ce = 'calor' and random() < 0.5 then v_tipo := 2; end if;       -- onda de calor: mais seca
      if v_ce = 'vento' and random() < 0.5 then v_tipo := 1; end if;       -- ventania espalha pragas
      if v_ce = 'chuva' and v_tipo = 2 then v_tipo := -1; end if;          -- com chuva não seca
      if v_ce = 'nublado' then v_tipo := -1; end if;                       -- nublado: nada de novo
      -- máquina por perto evita o problema (robô capinador, pulverizador, irrigador);
      -- o aspersor elétrico evita qualquer um, gastando 2 ⚡
      if v_tipo = 0 and not v_erva and not fazenda_protegido(p_jogador, 'erva', r.x, r.y) then
        if not fazenda_aspersor(p_jogador, r.x, r.y) then v_erva := true; end if;
      elsif v_tipo = 1 and not v_praga and not fazenda_protegido(p_jogador, 'praga', r.x, r.y) then
        if not fazenda_aspersor(p_jogador, r.x, r.y) then v_praga := true; end if;
      elsif v_tipo = 2 and not v_seco and not fazenda_protegido(p_jogador, 'seco', r.x, r.y) then
        if not fazenda_aspersor(p_jogador, r.x, r.y) then v_seco := true; end if;
      end if;
      v_evt := v_evt + make_interval(secs => r.tempo_seg * (0.25 + random() * 0.35));
      i := i + 1;
    end loop;
    if v_evt >= v_maduro then
      v_evt := null;
    end if;
    update fazenda_canteiros
       set erva = v_erva, praga = v_praga, seco = v_seco, prox_evento = v_evt
     where jogador_id = p_jogador and posicao = r.posicao;
  end loop;
end;
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
    v_murcho := v_maduro + make_interval(secs => fazenda_murcha_seg(k.tempo_seg, c.seco));
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
      v_murcho := now() + make_interval(secs => fazenda_murcha_seg(k.tempo_seg, c.seco));
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
    if k.so_dia is not null then perform fazenda_so_dia_plantar(p_jogador, k.so_dia); end if;   -- fase 115: a Viih
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
      if k.so_dia is null then update fazenda_jogadores set semente = k.id where id = p_jogador; end if;   -- (fase 115: a Viih não)
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
             + c.adubado::int                                           -- adubo do Seu Zé
             + (c.y >= 45 and j.cachorro_raca is not null)::int         -- fase 111: o cachorro da ilha
             + fazenda_bonus_estacao(k.estacao_boa, k.rendimento);     -- fase 121: na estação dela, rende mais
    if fazenda_protegido(p_jogador, 'sorte', c.x, c.y) and random() < 0.15 then
      v_qtd := v_qtd * 2;                                               -- alvo
    end if;
    if j.colheita50_ate > now() then
      v_qtd := v_qtd + ceil(v_qtd / 2.0)::int;                          -- fase 93: balança de ouro (+50%)
    end if;
    if k.so_dia is not null then v_qtd := k.rendimento; end if;        -- fase 115: a Viih, sem bônus
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


-- Fase 29: baú coletor (precisa de energia). Encostado num bloco de canteiros (os canteiros
-- encostados uns nos outros), colhe sozinho o que amadurece; encostado num cercado, coleta o
-- produto e alimenta os bichos daquela espécie. 2 ⚡ por colheita, coleta ou ração (fase 43; era 1).
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
  v_seguro boolean;   -- fase 71
begin
  for b in select x, y from fazenda_construcoes where jogador_id = p_jogador and tipo = 'bau' loop
   -- fase 71: cada baú num lote só (modo rápido); deu erro, o lote volta e é refeito no modo seguro
   for v_tent in 1..2 loop
    v_seguro := v_tent = 2;
    begin
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
         and now() < c.plantado_em + make_interval(secs => u.tempo_seg + fazenda_murcha_seg(u.tempo_seg, c.seco))
    loop
      exit when v_livre <= 0 or not fazenda_gastar_energia(p_jogador, 2);
      if v_seguro then
        begin
          v_qtd := fazenda_aplicar(p_jogador, 'colher', k.posicao, null, true);   -- cai no celeiro...
          perform fazenda_bau_guardar(p_jogador, b.x, b.y, k.cultura, v_qtd, k.x, k.y);   -- ...e passa para o baú
          v_livre := v_livre - v_qtd;
        exception when others then null; end;
      else
        v_qtd := fazenda_aplicar(p_jogador, 'colher', k.posicao, null, true);
        perform fazenda_bau_guardar(p_jogador, b.x, b.y, k.cultura, v_qtd, k.x, k.y);
        v_livre := v_livre - v_qtd;
      end if;
    end loop;

    -- cercados encostados: coleta o produto (para o baú) e dá ração (do baú, se ele tiver; senão do celeiro)
    for m in
      select a.id, a.alimentado_em, t.tempo_seg, t.produto, t.racao, fazenda_racao_qtd(t.racao_qtd) as racao_qtd, p.x as px, p.y as py
        from fazenda_animais a
        join fazenda_animais_tipos t on t.id = a.tipo
        join fazenda_construcoes p on p.jogador_id = p_jogador and p.tipo = 'cercado_' || a.tipo
        join fazenda_itens i on i.id = p.tipo
       where a.jogador_id = p_jogador
         and (((b.x = p.x - 1 or b.x = p.x + i.largura) and b.y between p.y and p.y + i.altura - 1)
           or ((b.y = p.y - 1 or b.y = p.y + i.altura) and b.x between p.x and p.x + i.largura - 1))
    loop
      if v_seguro then
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
      else
        if m.alimentado_em is not null and now() >= m.alimentado_em + make_interval(secs => m.tempo_seg)
           and v_livre > 0 and fazenda_gastar_energia(p_jogador, 2) then
          perform fazenda_animal_um(p_jogador, m.id, 'coletar', true);
          perform fazenda_bau_guardar(p_jogador, b.x, b.y, m.produto, 1, m.px, m.py);
          v_livre := v_livre - 1;
          m.alimentado_em := null;
        end if;
        -- (no modo rápido, só tenta a ração que existe: no baú ou no celeiro)
        if coalesce((select quantidade from fazenda_bau_itens where jogador_id = p_jogador and x = b.x and y = b.y and item = m.racao), 0) >= m.racao_qtd
           or coalesce((select quantidade from fazenda_celeiro where jogador_id = p_jogador and item = m.racao), 0) >= m.racao_qtd then
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
        end if;
      end if;
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
    exit;   -- deu certo: o próximo baú
    exception when others then
      if v_seguro then raise; end if;
    end;
   end loop;
  end loop;
  perform fazenda_bot_xp_gravar();   -- fase 72: o XP do que colheram, uma vez só
end;
$$;


-- As máquinas elétricas trabalham sozinhas (roda ao carregar a fazenda, como os ajudantes):
-- as oficinas andam (fábrica automática incluída); os robôs colhem e replantam.
create or replace function public.fazenda_industria(p_jogador uuid)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  r     record;
  cc    record;
  m     record;
  v_sem text;
  v_seguro boolean;   -- fase 71
begin
  perform fazenda_energia_atualizar(p_jogador);
  delete from fazenda_viagens where jogador_id = p_jogador and criada_em < now() - interval '10 minutes';
  delete from fazenda_bau_itens where jogador_id = p_jogador and quantidade = 0;
  delete from fazenda_oficina_itens where jogador_id = p_jogador and quantidade = 0;
  perform fazenda_baus(p_jogador);   -- baús: colhem os canteiros e cuidam dos cercados encostados (antes das oficinas)
  perform fazenda_oficinas_andar(p_jogador);   -- oficinas: estoque, prontos e a fábrica automática

  select semente into v_sem from fazenda_jogadores where id = p_jogador;
  for r in
    select c.x, c.y, i.raio from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
     where c.jogador_id = p_jogador and i.efeito = 'robo'
  loop
   -- fase 71: cada robô num lote só (modo rápido); deu erro, volta e refaz no modo seguro
   for v_tent in 1..2 loop
    v_seguro := v_tent = 2;
    begin
    for cc in
      select x.posicao, x.estado, x.cultura,
             coalesce(x.estado = 'plantado'
               and now() >= x.plantado_em + make_interval(secs => k.tempo_seg)
               and now() < x.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, x.seco)), false) as maduro
        from fazenda_canteiros x left join fazenda_culturas k on k.id = x.cultura
       where x.jogador_id = p_jogador and abs(x.x - r.x) <= r.raio and abs(x.y - r.y) <= r.raio
       order by x.posicao
    loop
      if cc.maduro then
        if v_seguro then
          begin   -- colhe (e ara, se não tiver trator): 4 ⚡ (fase 43; era 3)
            if not fazenda_gastar_energia(p_jogador, 4) then exit; end if;
            perform fazenda_aplicar(p_jogador, 'colher', cc.posicao, null, true);
            if (select estado from fazenda_canteiros where jogador_id = p_jogador and posicao = cc.posicao) = 'vazio' then
              perform fazenda_aplicar(p_jogador, 'arar', cc.posicao, null, true);
            end if;
          exception when others then null;
          end;
          begin   -- replanta a mesma semente (paga com suas moedas): 2 ⚡
            if fazenda_gastar_energia(p_jogador, 2) then
              perform fazenda_aplicar(p_jogador, 'plantar', cc.posicao, cc.cultura, true);
            end if;
          exception when others then null;
          end;
        else
          if not fazenda_gastar_energia(p_jogador, 4) then exit; end if;
          perform fazenda_aplicar(p_jogador, 'colher', cc.posicao, null, true);
          if (select estado from fazenda_canteiros where jogador_id = p_jogador and posicao = cc.posicao) = 'vazio' then
            perform fazenda_aplicar(p_jogador, 'arar', cc.posicao, null, true);
          end if;
          -- (no modo rápido, só replanta o que dá: estação, estufa, nível e moedas)
          if fazenda_bot_pode_plantar(p_jogador, cc.cultura, cc.posicao) and fazenda_gastar_energia(p_jogador, 2) then
            perform fazenda_aplicar(p_jogador, 'plantar', cc.posicao, cc.cultura, true);
          end if;
        end if;
      elsif cc.estado = 'arado' and v_sem is not null then
        if v_seguro then
          begin   -- canteiro arado vazio: planta a última semente que você usou (2 ⚡)
            if fazenda_gastar_energia(p_jogador, 2) then
              perform fazenda_aplicar(p_jogador, 'plantar', cc.posicao, v_sem, true);
            end if;
          exception when others then null;
          end;
        elsif fazenda_bot_pode_plantar(p_jogador, v_sem, cc.posicao) and fazenda_gastar_energia(p_jogador, 2) then
          perform fazenda_aplicar(p_jogador, 'plantar', cc.posicao, v_sem, true);
        end if;
      end if;
    end loop;
    exit;   -- deu certo: o próximo robô
    exception when others then
      if v_seguro then raise; end if;
    end;
   end loop;
  end loop;
  perform fazenda_bot_xp_gravar();   -- fase 72: o XP do que colheram, uma vez só
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
            select cc.posicao, now() >= cc.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, cc.seco)) as murcha
              from fazenda_canteiros cc join fazenda_culturas k on k.id = cc.cultura
             where cc.jogador_id = p_jogador and cc.estado = 'plantado'
               and now() >= cc.plantado_em + make_interval(secs => k.tempo_seg)
               and cc.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, cc.seco))
                   > greatest(a.atualizado_em, now() - make_interval(hours => fazenda_turno(p_jogador)::int))
             order by cc.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, cc.seco)) limit v_n
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
                    or (cc.estado = 'plantado' and now() >= cc.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, cc.seco))))
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
          v_nivel := (select fazenda_nivel_de(xp, nivel_trava) from fazenda_jogadores where id = p_jogador);
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
               and now() < cc.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, cc.seco))
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
            select an.id, an.alimentado_em, t.tempo_seg, t.racao, fazenda_racao_qtd(t.racao_qtd) as racao_qtd from fazenda_animais an join fazenda_animais_tipos t on t.id = an.tipo
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


-- Pega colheita de um canteiro do vizinho. Retorna a quantidade pega.
-- fase 66: p_luva = pode gastar 1 luva do Perks para passar pelo alarme (só gasta no canteiro protegido)
-- fase 103: com a luva, leva a muda inteira (o que o dono colheria) e o canteiro do vizinho fica arado
drop function if exists public.fazenda_pegar_um(uuid, uuid, int);
create or replace function public.fazenda_pegar_um(p_ator uuid, p_dono uuid, p_posicao int, p_luva boolean default false)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  c        record;
  k        record;
  v_maduro timestamptz;
  v_qtd    int;
  v_luva   boolean := false;
begin
  select * into c from fazenda_canteiros
   where jogador_id = p_dono and posicao = p_posicao
     for update;
  if not found or c.estado <> 'plantado' then
    raise exception 'nao_maduro';
  end if;
  select * into k from fazenda_culturas where id = c.cultura;
  if k.so_dia is not null then raise exception 'nada_pra_pegar'; end if;   -- fase 115: a Viih ninguém pega
  v_maduro := c.plantado_em + make_interval(secs => k.tempo_seg);
  if now() < v_maduro then
    raise exception 'nao_maduro';
  end if;
  if now() >= v_maduro + make_interval(secs => fazenda_murcha_seg(k.tempo_seg, c.seco)) then
    raise exception 'murchou';
  end if;
  if fazenda_protegido(p_dono, 'alarme', c.x, c.y) and fazenda_alarme_ligado(p_dono) then
    if not coalesce(p_luva, false) then raise exception 'alarme'; end if;
    v_luva := true;   -- fase 66: passa com a luva do Perks (gasta lá embaixo, se der para pegar)
  end if;
  if exists (select 1 from fazenda_visitas
              where tipo = 'roubo' and ator_id = p_ator and dono_id = p_dono
                and posicao = p_posicao and plantado_em = c.plantado_em) then
    raise exception 'ja_pegou';
  end if;
  if c.roubado >= (case when v_luva then k.rendimento else fazenda_limite_roubo(k.rendimento) end) then
    raise exception 'nada_pra_pegar';
  end if;
  if (select count(*) from fazenda_visitas
       where ator_id = p_ator and tipo = 'roubo' and criado_em > now() - interval '1 day') >= 40 then
    raise exception 'limite_pegadas';
  end if;

  if v_luva then
    update fazenda_celeiro set quantidade = quantidade - 1
     where jogador_id = p_ator and item = 'luva_perks'
       and quantidade - coalesce((select quantidade from fazenda_reservas where jogador_id = p_ator and item = 'luva_perks'), 0) >= 1;
    if not found then raise exception 'sem_luva'; end if;
  end if;

  if v_luva then
    -- fase 103: a muda inteira, o mesmo que o dono colheria agora (a cerca não segura a luva)
    v_qtd := greatest(k.rendimento - (c.erva::int + c.praga::int + c.seco::int) - c.roubado, 1) + c.adubado::int;
    update fazenda_canteiros set estado = 'arado', cultura = null, plantado_em = null,
           erva = false, praga = false, seco = false, roubado = 0, prox_evento = null, adubado = false
     where jogador_id = p_dono and posicao = p_posicao;
  else
    v_qtd := least(2 + (random() < 0.4)::int, fazenda_limite_roubo(k.rendimento) - c.roubado);
    if fazenda_protegido(p_dono, 'cerca', c.x, c.y) then
      v_qtd := least(v_qtd, 1);   -- cerca ou placa por perto
    end if;
    update fazenda_canteiros set roubado = roubado + v_qtd
     where jogador_id = p_dono and posicao = p_posicao;
  end if;
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  values (p_ator, k.id, v_qtd)
  on conflict (jogador_id, item)
  do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd, luva)
  values (p_ator, p_dono, 'roubo', p_posicao, c.plantado_em, k.id, v_qtd, v_luva);
  perform fazenda_missao(p_ator, 'pegar', v_qtd);

  return v_qtd;
end;
$$;


-- Fase 48: o vizinho salva uma planta murcha (1 por dia em cada fazenda): ela volta madura, sem
-- problemas, com o tempo todo para colher. Vale 3 ajudas. Devolve o XP.
create or replace function public.fazenda_salvar_um(p_ator uuid, p_dono uuid, p_posicao int)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  c   record;
  k   record;
  v_xp int;
begin
  select * into c from fazenda_canteiros where jogador_id = p_dono and posicao = p_posicao for update;
  if not found or c.estado <> 'plantado' then raise exception 'nada_a_fazer'; end if;
  select * into k from fazenda_culturas where id = c.cultura;
  if now() < c.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, c.seco)) then
    raise exception 'nada_a_fazer';   -- não está murcha
  end if;
  if (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'salvar'
        and criado_em > now() - interval '1 day') >= 2 then
    raise exception 'ja_salvou';
  end if;
  update fazenda_canteiros
     set plantado_em = now() - make_interval(secs => k.tempo_seg), erva = false, praga = false, seco = false, prox_evento = null
   where jogador_id = p_dono and posicao = p_posicao;
  v_xp := fazenda_premiar_ajuda(p_ator, 3, p_dono);
  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd, xp)
  values (p_ator, p_dono, 'salvar', p_posicao, now() - make_interval(secs => k.tempo_seg), k.id, 3, v_xp);
  perform fazenda_missao_ajuda(p_ator, 3);
  return v_xp;
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
    v_murcha := c.estado = 'plantado' and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, c.seco));
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
    if k.so_dia is not null then raise exception 'cultura_invalida'; end if;   -- fase 115: a Viih só na sua fazenda
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


create or replace function public.fazenda_ajudar_um(p_ator uuid, p_dono uuid, p_posicao int)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  c         record;
  k         record;
  v_n       int;
  v_hoje    int;
  v_premio  int;
begin
  select * into c from fazenda_canteiros
   where jogador_id = p_dono and posicao = p_posicao
     for update;
  if not found or c.estado <> 'plantado' then
    raise exception 'nada_a_fazer';
  end if;
  select * into k from fazenda_culturas where id = c.cultura;
  if now() >= c.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, c.seco)) then
    raise exception 'nada_a_fazer';
  end if;
  v_n := c.erva::int + c.praga::int + c.seco::int;
  if v_n = 0 then
    raise exception 'nada_a_fazer';
  end if;

  update fazenda_canteiros set erva = false, praga = false, seco = false
   where jogador_id = p_dono and posicao = p_posicao;

  -- fase 48: o XP de cada uma cresce com o nível de quem ajuda (fazenda_premio_ajuda); fase 83: sem limite
  v_premio := fazenda_premiar_ajuda(p_ator, v_n, p_dono);

  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd, xp)
  values (p_ator, p_dono, 'ajuda', p_posicao, c.plantado_em, k.id, v_n, v_premio);
  perform fazenda_missao_ajuda(p_ator, v_n);

  return v_premio;   -- (fase 48: o XP ganho; antes, os problemas)
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
    v_nivel := fazenda_nivel_de(j.xp, j.nivel_trava);
    if v_nivel >= 60 then raise exception 'xp_maximo'; end if;   -- fase 106: o último nível agora é o 60 (fase 62: 45)
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
       and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, c.seco));
    if v_cap = 0 then raise exception 'nada_a_fazer'; end if;
    v_preco := (v_loja->>'preco')::int * ceil(v_cap / coalesce((v_loja->>'por')::numeric, v_cap))::int;
    if j.diamantes < v_preco then raise exception 'diamantes_insuficientes'; end if;
    update fazenda_canteiros c
       set plantado_em = now() - make_interval(secs => k.tempo_seg), erva = false, praga = false, seco = false, prox_evento = null
      from fazenda_culturas k
     where c.jogador_id = v_id and c.estado = 'plantado' and k.id = c.cultura
       and now() >= c.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, c.seco));
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
    v_nivel := fazenda_nivel_de(j.xp, j.nivel_trava);
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
    cross join lateral (select c.plantado_em + make_interval(secs => k.tempo_seg + fazenda_murcha_seg(k.tempo_seg, c.seco)) as em) m
    cross join lateral (select case
             when c.seco then 'seca'   -- fase 121: com seca, murcha na metade do tempo
             when not v_tem then 'sem_colhedor'
             when h.ultimo_descanso_de is not null and m.em >= h.ultimo_descanso_de and m.em < h.ultimo_descanso_ate then 'descansando'
             when m.em < now() - make_interval(hours => fazenda_turno(p_jogador)::int) then 'fechada'
             else 'nao_deu_conta' end as motivo) x
   where c.jogador_id = p_jogador and c.estado = 'plantado' and now() >= m.em and m.em > now() - interval '7 days'
  on conflict (jogador_id, posicao, plantado_em) do nothing;
  delete from fazenda_murchas where jogador_id = p_jogador and murchou_em < now() - interval '7 days';
end;
$$;


-- Alimenta ou coleta um animal. Retorna quantos produtos coletou.
drop function if exists public.fazenda_animal_um(uuid, bigint, text);
create or replace function public.fazenda_animal_um(p_jogador uuid, p_animal bigint, p_acao text, p_bot boolean default false)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  r      record;
  v_tem  int;
begin
  select a.id, a.tipo, a.alimentado_em, t.produto, t.tempo_seg, t.racao, fazenda_racao_qtd(t.racao_qtd) as racao_qtd, k.xp as produto_xp
    into r
    from fazenda_animais a
    join fazenda_animais_tipos t on t.id = a.tipo
    join fazenda_culturas k on k.id = t.produto
   where a.id = p_animal and a.jogador_id = p_jogador
     for update of a;
  if not found then
    raise exception 'animal_invalido';
  end if;

  if p_acao = 'alimentar' then
    if r.alimentado_em is not null then
      raise exception 'ja_alimentado';
    end if;
    select quantidade into v_tem from fazenda_celeiro
     where jogador_id = p_jogador and item = r.racao
       for update;
    if coalesce(v_tem, 0) < r.racao_qtd then
      raise exception 'sem_racao';
    end if;
    update fazenda_celeiro set quantidade = quantidade - r.racao_qtd
     where jogador_id = p_jogador and item = r.racao;
    -- com fardo de feno na fazenda, o animal produz 20% mais rápido; fase 54: o cuidador dele, mais
    -- 10% por nível (o bicho já começa adiantado, como com o feno)
    update fazenda_animais
       set alimentado_em = now() - make_interval(secs => r.tempo_seg * (
                             case when fazenda_tem_efeito(p_jogador, 'feno') then 0.2 else 0 end
                             + fazenda_cuidador_adianta(p_jogador, r.tipo)))
     where id = p_animal;
    return 0;

  elsif p_acao = 'coletar' then
    if r.alimentado_em is null or now() < r.alimentado_em + make_interval(secs => r.tempo_seg) then
      raise exception 'nao_pronto';
    end if;
    insert into fazenda_celeiro (jogador_id, item, quantidade)
    values (p_jogador, r.produto, 1)
    on conflict (jogador_id, item)
    do update set quantidade = fazenda_celeiro.quantidade + 1;
    -- fase 72: o que o ajudante coleta dá metade do XP (antes, nada)
    if not p_bot then update fazenda_jogadores set xp = xp + r.produto_xp where id = p_jogador;
    else perform fazenda_bot_xp(p_jogador, r.produto_xp / 2); end if;
    update fazenda_animais set alimentado_em = null where id = p_animal;
    if not p_bot then perform fazenda_missao(p_jogador, 'animal', 1); end if;
    return 1;
  end if;

  raise exception 'acao_invalida';
end;
$$;


-- Fase 48: o vizinho dá ração aos bichos com fome; cada um vale 1 ajuda.
-- Fase 83: a ração sai do celeiro de quem ajuda (era do dono, até 10 por dia) e não tem limite. O
-- bicho começa com o feno e o cuidador do dono, como se o dono tivesse dado.
-- Fase 86: o miolo de 1 bicho ficou em fazenda_vizinho_bicho_um (o Ajudar tudo também usa). Devolve o XP.
create or replace function public.fazenda_vizinho_bicho_um(p_ator uuid, p_dono uuid, p_animal bigint)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  r     record;
  v_tem int;
  v_xp  int;
begin
  select a.tipo, a.alimentado_em, t.racao, fazenda_racao_qtd(t.racao_qtd) as racao_qtd, t.tempo_seg into r
    from fazenda_animais a join fazenda_animais_tipos t on t.id = a.tipo
   where a.id = p_animal and a.jogador_id = p_dono
     for update of a;
  if not found then raise exception 'animal_invalido'; end if;
  if r.alimentado_em is not null then raise exception 'ja_alimentado'; end if;
  -- a ração de quem ajuda (a que ele guardou para os bichos dele fica)
  select coalesce((select quantidade from fazenda_celeiro where jogador_id = p_ator and item = r.racao), 0)
       - coalesce((select quantidade from fazenda_reservas where jogador_id = p_ator and item = r.racao), 0) into v_tem;
  if v_tem < r.racao_qtd then raise exception 'sem_racao_sua'; end if;
  update fazenda_celeiro set quantidade = quantidade - r.racao_qtd where jogador_id = p_ator and item = r.racao;
  update fazenda_animais
     set alimentado_em = now() - make_interval(secs => r.tempo_seg * (
                           case when fazenda_tem_efeito(p_dono, 'feno') then 0.2 else 0 end
                           + fazenda_cuidador_adianta(p_dono, r.tipo)))
   where id = p_animal;
  v_xp := fazenda_premiar_ajuda(p_ator, 1, p_dono);
  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd, xp)
  values (p_ator, p_dono, 'bicho', 0, now(), r.racao, 1, v_xp);
  return v_xp;
end;
$$;


-- o valor de um catálogo, montado na hora
create or replace function public.fazenda_cache_valor(p_chave text)
returns jsonb language sql stable security definer set search_path = public as $$
  select case p_chave
    when 'culturas' then (
      select jsonb_agg(jsonb_build_object(
               'id', id, 'nome', nome, 'emoji', emoji, 'tempo_seg', tempo_seg,
               'custo', custo, 'venda', venda, 'rendimento', rendimento,
               'xp', xp, 'nivel_min', nivel_min, 'tipo', tipo, 'estacao', estacao, 'estacao_boa', estacao_boa, 'so_ilha', so_ilha, 'so_dia', so_dia)   -- (fase 108; fase 115)
             order by ordem)
        from fazenda_culturas)
    when 'animais_tipos' then (select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_animais_tipos t)
    when 'conquistas_tipos' then (select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_conquistas_tipos t)
    when 'ajudantes_tipos' then (select jsonb_agg(to_jsonb(t) order by t.ordem) from fazenda_ajudantes_tipos t)
    when 'melhorias_tipos' then fazenda_melhorias_tipos()
    when 'melhorias' then (select jsonb_object_agg(m->>'id', m) from jsonb_array_elements(fazenda_melhorias_tipos()) m)
  end;
$$;


select public.fazenda_cache_montar();

-- conferência: tem que aparecer "fase 121 ok" e as plantas de cada estação boa
select case when exists (select 1 from pg_proc where proname = 'fazenda_murcha_seg')
             and (select prosrc from pg_proc where proname = 'fazenda_aplicar') like '%fazenda_bonus_estacao%'
             and (select prosrc from pg_proc where proname = 'fazenda_animal_um') like '%fazenda_racao_qtd%'
            then 'fase 121 ok' else 'não aplicou' end as resultado,
       (select string_agg(e || ': ' || n, ' | ') from (select estacao_boa e, string_agg(nome, ', ' order by nivel_min) n
          from public.fazenda_culturas where estacao_boa is not null group by estacao_boa) x) as estacoes;
