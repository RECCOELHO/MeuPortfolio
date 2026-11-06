-- ============================================================
-- FAZENDINHA — Fase 109 (guardar para o navio: os materiais do navio e da ilha ficam guardados no celeiro,
-- fora do "Vender tudo", e a melhoria do navio e a obra da ilha usam o guardado), só o que mudou.
-- Para o banco que já está no ar (com a fase 108): Supabase > SQL Editor > colar este arquivo > Run.
-- Rode ANTES do merge do PR.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 108 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'fazenda_itens' and column_name = 'so_ilha') then
    raise exception 'Rode o fase108.sql antes deste. Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 109: guardar para o navio. No celeiro, o que as próximas melhorias do navio e a próxima obra da ilha
-- pedem (tora, tábua naval, cravo, vela, carta náutica, marlim, pérola negra e os raros do mercador) ganha o
-- botão "Guardar para o navio" (a mesma reserva da ração dos bichos, fazenda_reservar): o guardado não vai
-- no "Vender tudo", nem na feira, nem nas oficinas (a serraria não gasta a tora guardada).
-- • A melhoria do navio (fazenda_comprar) e a obra da ilha (fazenda_ilha_construir) usam o guardado; antes
--   só usavam o que estava livre, e o guardado travava a compra.
-- • O que elas gastam sai também do guardado (fazenda_reserva_gastar): o guardado é o que ainda falta juntar.
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------
create or replace function public.fazenda_reserva_gastar(p_jogador uuid, p_itens jsonb)
returns void language sql security definer set search_path = public as $$
  delete from fazenda_reservas r using jsonb_each_text(coalesce(p_itens, '{}'::jsonb)) e
   where r.jogador_id = p_jogador and r.item = e.key and r.quantidade <= e.value::int;
  update fazenda_reservas r set quantidade = r.quantidade - e.value::int
    from jsonb_each_text(coalesce(p_itens, '{}'::jsonb)) e
   where r.jogador_id = p_jogador and r.item = e.key and r.quantidade > e.value::int;
$$;
revoke all on function public.fazenda_reserva_gastar(uuid, jsonb) from public, anon, authenticated;

-- as funções que mudaram

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
    if fazenda_nivel_de(j.xp, j.nivel_trava) < a.nivel_min then raise exception 'nivel_insuficiente'; end if;
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
    if coalesce(nullif(p_tipo, ''), '0')::int >= 11 then   -- fase 106: os 3 da ilha (11 a 13), em ordem, com o kit de expedição
      if not fazenda_ilha_pode(v_id, fazenda_nivel_de(j.xp, j.nivel_trava)) then raise exception 'ilha_fechada'; end if;
      if j.ilha_terrenos >= 3 then raise exception 'terreno_max'; end if;
      if p_tipo::int <> 11 + j.ilha_terrenos then raise exception 'terreno_fora_de_ordem'; end if;
    elsif coalesce(nullif(p_tipo, ''), '0')::int >= 8 then
      if j.direita >= 3 then raise exception 'terreno_max'; end if;
      if p_tipo::int <> 8 + j.direita then raise exception 'terreno_fora_de_ordem'; end if;
    elsif j.zonas >= 7 then raise exception 'terreno_max';
    end if;
    select (z->>'n')::int as n, (z->>'custo')::int as custo, (z->>'nivel')::int as nivel into a
      from jsonb_array_elements(fazenda_zonas()) z
     where (z->>'n')::int = case when coalesce(nullif(p_tipo, ''), '0')::int >= 11 then 11 + j.ilha_terrenos
                                 when coalesce(nullif(p_tipo, ''), '0')::int >= 8 then 8 + j.direita else j.zonas + 1 end;
    if fazenda_nivel_de(j.xp, j.nivel_trava) < a.nivel then raise exception 'nivel_insuficiente'; end if;
    if j.moedas < a.custo then raise exception 'moedas_insuficientes'; end if;
    if a.n >= 11 then update fazenda_jogadores set moedas = moedas - a.custo, ilha_terrenos = ilha_terrenos + 1 where id = v_id;
    elsif a.n >= 8 then update fazenda_jogadores set moedas = moedas - a.custo, direita = direita + 1 where id = v_id;
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
    if fazenda_nivel_de(j.xp, j.nivel_trava) < a.nivel then raise exception 'nivel_insuficiente'; end if;
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
    -- fase 65: as peças pedem materiais raros do celeiro; fase 109: o que está guardado para o navio conta
    -- (só as melhorias do navio pedem materiais, e o píer já está pronto: não tem mais nada guardado para ele)
    if exists (select 1 from jsonb_each_text(coalesce(a.itens, '{}'::jsonb)) e
                where coalesce((select quantidade from fazenda_celeiro where jogador_id = v_id and item = e.key), 0) < e.value::int) then
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
    perform fazenda_reserva_gastar(v_id, a.itens);   -- fase 109
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


-- constrói a próxima obra (p_obra é o id dela: tocar duas vezes não constrói duas)
create or replace function public.fazenda_ilha_construir(p_token text, p_obra text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  j       record;
  c       record;
  v_p     jsonb;
  k       text;
  v_n     int;
  v_nivel int;
  v_xp    int;
begin
  select * into j from fazenda_jogadores where id = v_id for update;
  v_nivel := fazenda_nivel_de(j.xp, j.nivel_trava);
  if not fazenda_ilha_pode(v_id, v_nivel) then raise exception 'ilha_fechada'; end if;
  v_n := coalesce(j.ilha_obras, 0) + 1;
  select p into v_p from jsonb_array_elements(fazenda_ilha_obras()) p where (p->>'n')::int = v_n;
  if v_p is null then raise exception 'ilha_pronta'; end if;
  if v_p->>'id' is distinct from p_obra then raise exception 'ilha_ordem'; end if;
  if v_nivel < (v_p->>'nivel')::int then raise exception 'nivel_insuficiente'; end if;
  if j.moedas < (v_p->>'moedas')::int then raise exception 'moedas_insuficientes'; end if;
  for k in select jsonb_object_keys(v_p->'itens') loop   -- fase 109: o guardado para o navio conta
    if coalesce((select quantidade from fazenda_celeiro where jogador_id = v_id and item = k), 0) < (v_p->'itens'->>k)::int then
      raise exception 'faltam_materiais';
    end if;
  end loop;
  for k in select jsonb_object_keys(v_p->'itens') loop
    update fazenda_celeiro set quantidade = quantidade - (v_p->'itens'->>k)::int,
                               da_feira = least(da_feira, quantidade - (v_p->'itens'->>k)::int)
     where jogador_id = v_id and item = k;
  end loop;
  perform fazenda_reserva_gastar(v_id, v_p->'itens');   -- fase 109
  v_xp := round((fazenda_xp_nivel((v_p->>'nivel')::int + 1) - fazenda_xp_nivel((v_p->>'nivel')::int)) * 0.08)::int;
  perform set_config('fazenda.xp_puro', '1', true);
  update fazenda_jogadores set moedas = moedas - (v_p->>'moedas')::int, ilha_obras = v_n, xp = xp + v_xp where id = v_id;
  perform set_config('fazenda.xp_puro', '', true);
  if v_n = jsonb_array_length(fazenda_ilha_obras()) then
    select * into c from fazenda_conquistas_tipos where id = 'ilha_pronta';
    insert into fazenda_conquistas (jogador_id, conquista) values (v_id, 'ilha_pronta') on conflict do nothing;
    if found and c.id is not null then
      update fazenda_jogadores set moedas = least(2147483647, moedas::bigint + c.recompensa)::int, diamantes = diamantes + c.diamantes
       where id = v_id;
    end if;
  end if;
  return jsonb_build_object('obra', v_p, 'xp', v_xp, 'estado', fazenda_estado(v_id));
end;
$$;


-- conferência: tem que aparecer "fase 109 ok"
select case when exists (select 1 from pg_proc where proname = 'fazenda_reserva_gastar')
             and (select prosrc from pg_proc where proname = 'fazenda_comprar') like '%fazenda_reserva_gastar%'
             and (select prosrc from pg_proc where proname = 'fazenda_ilha_construir') like '%fazenda_reserva_gastar%'
            then 'fase 109 ok' else 'não aplicou' end as resultado;
