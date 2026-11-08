-- ============================================================
-- FAZENDINHA — Fase 125 (a 2ª fábrica automática, para a ilha; o navio do vizinho na visita), só o que mudou.
-- Para o banco que já está no ar (com a fase 124): Supabase > SQL Editor > colar este arquivo > Run.
-- Pode rodar antes do merge do PR.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- ------------------------------------------------------------
-- Fase 125: a 2ª fábrica automática no nível 46, para automatizar a ilha (no máximo uma de cada lado: uma na
-- fazenda e uma na ilha; a rede de canos encostada em cada uma leva e traz do celeiro), e o navio do vizinho
-- aparece na visita (fazenda_vizinho manda o nível, as peças e a pintura dele).
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------

-- as funções que mudaram

-- o limite de cada máquina no nível (null = sem limite)
create or replace function public.fazenda_limite_maquina(p_item text, p_limite int, p_nivel int)
returns int language sql immutable as $$
  select case p_item
           -- fase 78: do 17 ao 29, +1 por nível (era +1 a cada 2); do 30 em diante, +1 a cada 2
           when 'painel_solar' then p_limite + greatest(0, least(p_nivel, 29) - 16) + greatest(0, (p_nivel - 29) / 2)
           when 'turbina'      then p_limite + greatest(0, least(p_nivel, 29) - 17) + greatest(0, (p_nivel - 29) / 2)
           when 'gerador_bio'  then p_limite + (p_nivel >= 21)::int + (p_nivel >= 24)::int + 2 * (p_nivel >= 28)::int   -- fase 78: 2, 3, 4 e 6
           when 'hidreletrica' then p_limite + (p_nivel >= 23)::int + (p_nivel >= 27)::int                                -- fase 78: 1, 2 e 3
           when 'reator'       then p_limite + (p_nivel >= 40)::int   -- fase 75: o 2º reator no nível 40
           when 'fabrica_auto' then p_limite + (p_nivel >= 46)::int   -- fase 125: a 2ª fábrica automática, para a ilha
           else p_limite end;
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
  -- fase 125: fábrica automática, no máximo uma de cada lado (uma na fazenda e uma na ilha)
  if i.id = 'fabrica_auto' and exists (select 1 from fazenda_construcoes where jogador_id = v_id and tipo = 'fabrica_auto' and (y >= 45) = (p_y >= 45)) then
    raise exception 'fabrica_lado';
  end if;
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
  if i.id = 'fabrica_auto' and exists (select 1 from fazenda_construcoes where jogador_id = v_id and tipo = 'fabrica_auto'   -- fase 125
                                       and not (x = p_x and y = p_y) and (y >= 45) = (p_ny >= 45)) then
    raise exception 'fabrica_lado';
  end if;
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


-- Fazenda de um vizinho vista por quem está visitando
create or replace function public.fazenda_vizinho(p_dono uuid, p_ator uuid)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  j       record;
  v_nivel int;
begin
  select * into j from fazenda_jogadores where id = p_dono;
  v_nivel := fazenda_nivel_de(j.xp, j.nivel_trava);
  return jsonb_build_object(
    'agora', now(),
    'id', j.id,
    'apelido', j.apelido,
    'avatar', j.avatar,
    'nivel', v_nivel,
    'max_canteiros', fazenda_max_canteiros(v_nivel),
    'zonas', j.zonas,
    'direita', j.direita,   -- fase 78
    -- fase 125: o navio do vizinho (com o píer pronto): o nível, as peças e a pintura, para quem visita ver
    'navio', case when j.pier_em is not null then jsonb_build_object(
      'nivel', coalesce((fazenda_mar_item(p_dono, 'barco')->>'valor')::int, 1),
      'pecas', (select jsonb_object_agg(x, coalesce((select m.nivel from fazenda_melhorias m where m.jogador_id = p_dono and m.id = x), 0))
                  from unnest(array['motor', 'sonar', 'porao', 'rede', 'expedicao']) x),
      'visual', coalesce(j.barco_visual, '{}'::jsonb)) end,
    -- fase 48: hoje o visitante ainda pode salvar até 2 plantas murchas e dar ração a até 10 bichos aqui
    'salvos_hoje', (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'salvar'
                     and criado_em > now() - interval '1 day'),
    'pode_salvar', (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'salvar'
                     and criado_em > now() - interval '1 day') < 2,
    'bichos_hoje', (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'bicho'
                     and criado_em > now() - interval '1 day'),
    'premio_ajuda', fazenda_premio_ajuda(p_ator),
    -- fase 83: dono sumido há mais de 3 dias (+50% de XP e dá para plantar) e as murchas que ainda dá para limpar hoje
    'abandonada', fazenda_abandonada(p_dono),
    'limpos_hoje', (select count(*) from fazenda_visitas where ator_id = p_ator and dono_id = p_dono and tipo = 'limpar'
                     and criado_em > now() - interval '1 day'),
    'canteiros', coalesce((
      select jsonb_agg(jsonb_build_object(
               'posicao', c.posicao, 'x', c.x, 'y', c.y, 'estado', c.estado, 'cultura', c.cultura,
               'plantado_em', c.plantado_em, 'erva', c.erva, 'praga', c.praga, 'seco', c.seco,
               'roubado', c.roubado,
               'ja_peguei', exists (
                 select 1 from fazenda_visitas v
                  where v.tipo = 'roubo' and v.ator_id = p_ator and v.dono_id = p_dono
                    and v.posicao = c.posicao and v.plantado_em = c.plantado_em))
             order by c.posicao)
        from fazenda_canteiros c where c.jogador_id = p_dono), '[]'::jsonb),
    'animais', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'alimentado_em', alimentado_em,
               'radioativo_ate', case when radioativo_ate > now() then radioativo_ate end) order by id)   -- fase 68
        from fazenda_animais where jogador_id = p_dono), '[]'::jsonb),
    'construcoes', coalesce((
      select jsonb_agg(jsonb_build_object('x', x, 'y', y, 'tipo', tipo))
        from fazenda_construcoes where jogador_id = p_dono), '[]'::jsonb),
    'perfil', jsonb_build_object(
      'criado_em', j.criado_em,
      'estatisticas', (select to_jsonb(e) - 'jogador_id' || jsonb_build_object('energia', e.energia + floor(g.energia_gasta)::int)
                         from fazenda_estatisticas e join fazenda_jogadores g on g.id = e.jogador_id where e.jogador_id = p_dono),
      'conquistas', coalesce((select jsonb_agg(conquista order by obtida_em)
                                from fazenda_conquistas where jogador_id = p_dono), '[]'::jsonb),
      'trofeus', fazenda_trofeus(p_dono))   -- fase 63: os troféus do evento da semana
  );
end;
$$;


-- conferência: tem que aparecer "fase 125 ok"
select case when public.fazenda_limite_maquina('fabrica_auto', 1, 46) = 2 and public.fazenda_limite_maquina('fabrica_auto', 1, 45) = 1
             and (select prosrc from pg_proc where proname = 'fazenda_vizinho') like '%''navio''%'
            then 'fase 125 ok' else 'não aplicou' end as resultado;
