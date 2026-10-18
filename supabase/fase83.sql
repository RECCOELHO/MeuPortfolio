-- ============================================================
-- FAZENDINHA — Fase 83 (ajudar os vizinhos sem limite, a roça do vizinho, o alarme sem energia e o Perks),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 82): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 82 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from pg_proc where proname = 'fazenda_oficina_rapidez')) then
    raise exception 'Rode o fase82.sql antes deste (a fase 82 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 83: ajudar os vizinhos sem limite e com sequência.
-- • Cada ajuda vale 0,30% do nível de quem ajuda (era 0,25%), sem o limite de 30 por dia.
-- • Sequência de vizinhos: +10% por vizinho diferente ajudado em até 10 min do anterior, até +100%
--   (fazenda_jogadores.seq_donos e seq_em; fazenda_premiar_ajuda passa a receber o dono).
-- • Ração: sai do celeiro de quem ajuda (era do dono), sem limite por dia.
-- • Coletar para o amigo: o produto pronto dos bichos vai para o celeiro do dono (fazenda_vizinho_coletar).
-- • A roça do vizinho (fazenda_roca_um): limpar murchas (2 por dia em cada fazenda), arar os vazios,
--   colher para o dono e, na fazenda abandonada (dono sumido há mais de 3 dias), plantar com o seu
--   dinheiro (5 ajudas). Na abandonada toda ajuda vale +50%. O dono vê o resumo quando volta.
-- • Alarme sem energia: o tempo com a bateria zerada fica em fazenda_jogadores.alarme_off_seg.
-- • O Perks aparece em 1 de cada 6 blocos de 3 h (era 30), e "Outro vizinho" leva primeiro às abandonadas.
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists seq_donos uuid[] not null default '{}';
alter table public.fazenda_jogadores add column if not exists seq_em timestamptz;
-- o tempo (somado, em segundos) com o alarme desligado por falta de energia: o jogo mostra o que mudou
alter table public.fazenda_jogadores add column if not exists alarme_off_seg bigint not null default 0;
alter table public.fazenda_jogadores add column if not exists alarme_off_em timestamptz;
alter table public.fazenda_visitas drop constraint if exists fazenda_visitas_tipo_check;
alter table public.fazenda_visitas add constraint fazenda_visitas_tipo_check check (tipo in ('roubo', 'ajuda', 'salvar', 'bicho', 'coleta', 'limpar', 'arar', 'colher', 'plantar'));
drop function if exists public.fazenda_premiar_ajuda(uuid, int);   -- (agora recebe o dono, para a sequência)
alter table public.fazenda_visitas alter column cultura drop not null;   -- (arar um canteiro vazio não tem planta)

-- as funções que já existiam e mudaram

-- Tira os problemas de um canteiro do vizinho. Retorna quantos problemas resolveu.
-- Fase 48: quanto XP vale cada ajuda a um vizinho: 0,25% do nível de quem ajuda (pelo menos 2)
-- fase 83: 0,30% (e sem o limite de 30 por dia)
create or replace function public.fazenda_premio_ajuda(p_ator uuid)
returns int language sql stable security definer set search_path = public as $$
  select greatest(2, round((fazenda_xp_nivel(n + 1) - fazenda_xp_nivel(n)) * 0.003))::int
    from (select fazenda_nivel(xp) as n from fazenda_jogadores where id = p_ator) x;
$$;

-- Dá o prêmio de p_unidades ajudas; devolve o XP. Fase 83: sem o limite de 30 por dia, e com a
-- sequência de vizinhos: cada vizinho diferente ajudado em até 10 min do anterior dá +10% (até +100%);
-- 10 min sem ajudar, ela zera. O XP em dobro e os bônus de nível somam por cima (gatilho do XP).
create or replace function public.fazenda_premiar_ajuda(p_ator uuid, p_unidades int, p_dono uuid)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  j      record;
  v_seq  uuid[];
  v_xp   int;
begin
  if coalesce(p_unidades, 0) <= 0 then return 0; end if;
  select seq_donos, seq_em into j from fazenda_jogadores where id = p_ator for update;
  v_seq := case when j.seq_em is null or j.seq_em < now() - interval '10 minutes' then '{}'::uuid[] else coalesce(j.seq_donos, '{}') end;
  if p_dono is not null and not (p_dono = any(v_seq)) then v_seq := v_seq || p_dono; end if;
  v_xp := round(p_unidades * fazenda_premio_ajuda(p_ator) * (1 + fazenda_sequencia_bonus(cardinality(v_seq)))
                * case when fazenda_abandonada(p_dono) then 1.5 else 1 end)::int;   -- fazenda abandonada: +50%
  update fazenda_jogadores set xp = xp + v_xp, moedas = moedas + p_unidades, seq_donos = v_seq, seq_em = now() where id = p_ator;
  return v_xp;
end;
$$;

-- fase 83: fazenda abandonada = o dono não aparece há mais de 3 dias (lá dá para plantar, e a ajuda vale +50%)
create or replace function public.fazenda_abandonada(p_dono uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select visto_em < now() - interval '3 days' from fazenda_jogadores where id = p_dono), false);
$$;

-- fase 83: o bônus da sequência com n vizinhos (o 1º não dá bônus; +10% a cada um depois, até +100%)
create or replace function public.fazenda_sequencia_bonus(p_n int)
returns real language sql immutable as $$
  select least(1.0, 0.1 * greatest(coalesce(p_n, 0) - 1, 0))::real;
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
  if now() < c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) then
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
  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd)
  values (p_ator, p_dono, 'salvar', p_posicao, now() - make_interval(secs => k.tempo_seg), k.id, 3);
  perform fazenda_missao(p_ator, 'ajudar', 3);
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
    if fazenda_nivel((select xp from fazenda_jogadores where id = p_ator)) < k.nivel_min then raise exception 'nivel_insuficiente'; end if;
    if (select moedas from fazenda_jogadores where id = p_ator) < k.custo then raise exception 'moedas_insuficientes'; end if;
    update fazenda_jogadores set moedas = moedas - k.custo where id = p_ator;
    update fazenda_canteiros
       set estado = 'plantado', cultura = k.id, plantado_em = now(),
           erva = false, praga = false, seco = false, roubado = 0, adubado = false,
           prox_evento = now() + make_interval(secs => k.tempo_seg * (0.15 + random() * 0.35))
     where jogador_id = p_dono and posicao = p_posicao;
    v_un := 5; v_tipo := 'plantar'; v_cult := k.id;
  end if;
  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd)
  values (p_ator, p_dono, v_tipo, p_posicao, now(), v_cult, 1);
  perform fazenda_missao(p_ator, 'ajudar', 1);
  return fazenda_premiar_ajuda(p_ator, v_un, p_dono);
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
  if now() >= c.plantado_em + make_interval(secs => k.tempo_seg + greatest(k.tempo_seg * 2, 3600)) then
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

  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd)
  values (p_ator, p_dono, 'ajuda', p_posicao, c.plantado_em, k.id, v_n);
  perform fazenda_missao(p_ator, 'ajudar', v_n);

  return v_premio;   -- (fase 48: o XP ganho; antes, os problemas)
end;
$$;

-- p_acao: pegar | ajudar. Mesmo esquema de lote do fazenda_acao.
create or replace function public.fazenda_acao_vizinho(p_token text, p_vizinho uuid, p_acao text, p_posicoes int[])
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id     uuid := fazenda_auth(p_token);
  v_pos    int;
  v_qtd    int;
  v_result jsonb := '{}'::jsonb;
  v_feitos int := 0;
begin
  if p_vizinho is null or p_vizinho = v_id then
    raise exception 'propria_fazenda';
  end if;
  if not exists (select 1 from fazenda_jogadores where id = p_vizinho and banido_em is null) then
    raise exception 'vizinho_invalido';
  end if;
  -- fase 66: pegar_luva (a luva do Perks); fase 83: limpar (murcha), arar (vazio), colher (para o dono) e plantar:<semente>
  if p_acao not in ('pegar', 'pegar_luva', 'ajudar', 'salvar', 'limpar', 'arar', 'colher') and p_acao not like 'plantar:%' then
    raise exception 'acao_invalida';
  end if;
  if p_posicoes is null or array_length(p_posicoes, 1) is null then
    raise exception 'nada_a_fazer';
  end if;
  if array_length(p_posicoes, 1) > 100 then
    raise exception 'acao_invalida';
  end if;

  perform fazenda_tick(p_vizinho);

  foreach v_pos in array p_posicoes loop
    begin
      if p_acao in ('pegar', 'pegar_luva') then
        v_qtd := fazenda_pegar_um(v_id, p_vizinho, v_pos, p_acao = 'pegar_luva');
      elsif p_acao = 'salvar' then
        v_qtd := fazenda_salvar_um(v_id, p_vizinho, v_pos);
      elsif p_acao in ('limpar', 'arar', 'colher') or p_acao like 'plantar:%' then
        v_qtd := fazenda_roca_um(v_id, p_vizinho, v_pos, p_acao);   -- fase 83
      else
        v_qtd := fazenda_ajudar_um(v_id, p_vizinho, v_pos);
      end if;
      v_feitos := v_feitos + 1;
      v_result := v_result || jsonb_build_object(v_pos::text, v_qtd);
    exception when others then
      -- com um canteiro só, o erro volta para a tela; em lote, pula o canteiro
      if array_length(p_posicoes, 1) = 1 then
        raise;
      end if;
    end;
  end loop;

  perform fazenda_bot_xp_gravar();   -- fase 83: a metade do XP da colheita que vai para o dono
  return jsonb_build_object(
    'feitos', v_feitos,
    'resultado', v_result,
    'vizinho', fazenda_vizinho(p_vizinho, v_id),
    'estado', fazenda_estado(v_id)
  );
end;
$$;

-- Fase 48: o vizinho dá ração aos bichos com fome; cada um vale 1 ajuda.
-- Fase 83: a ração sai do celeiro de quem ajuda (era do dono, até 10 por dia) e não tem limite. O
-- bicho começa com o feno e o cuidador do dono, como se o dono tivesse dado.
create or replace function public.fazenda_vizinho_bicho(p_token text, p_vizinho uuid, p_animais bigint[])
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_a     bigint;
  v_feito int := 0;
  v_xp    int := 0;
  r       record;
  v_tem   int;
begin
  if p_vizinho is null or p_vizinho = v_id then raise exception 'propria_fazenda'; end if;
  if not exists (select 1 from fazenda_jogadores where id = p_vizinho and banido_em is null) then raise exception 'vizinho_invalido'; end if;
  if p_animais is null or array_length(p_animais, 1) is null or array_length(p_animais, 1) > 50 then raise exception 'nada_a_fazer'; end if;
  foreach v_a in array p_animais loop
    begin
      select a.tipo, a.alimentado_em, t.racao, t.racao_qtd, t.tempo_seg into r
        from fazenda_animais a join fazenda_animais_tipos t on t.id = a.tipo
       where a.id = v_a and a.jogador_id = p_vizinho
         for update of a;
      if not found then raise exception 'animal_invalido'; end if;
      if r.alimentado_em is not null then raise exception 'ja_alimentado'; end if;
      -- a ração de quem ajuda (a que ele guardou para os bichos dele fica)
      select coalesce((select quantidade from fazenda_celeiro where jogador_id = v_id and item = r.racao), 0)
           - coalesce((select quantidade from fazenda_reservas where jogador_id = v_id and item = r.racao), 0) into v_tem;
      if v_tem < r.racao_qtd then raise exception 'sem_racao_sua'; end if;
      update fazenda_celeiro set quantidade = quantidade - r.racao_qtd where jogador_id = v_id and item = r.racao;
      update fazenda_animais
         set alimentado_em = now() - make_interval(secs => r.tempo_seg * (
                               case when fazenda_tem_efeito(p_vizinho, 'feno') then 0.2 else 0 end
                               + fazenda_cuidador_adianta(p_vizinho, r.tipo)))
       where id = v_a;
      v_xp := v_xp + fazenda_premiar_ajuda(v_id, 1, p_vizinho);
      insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd)
      values (v_id, p_vizinho, 'bicho', 0, now(), r.racao, 1);
      v_feito := v_feito + 1;
    exception when others then
      if array_length(p_animais, 1) = 1 then raise; end if;
    end;
  end loop;
  if v_feito > 0 then perform fazenda_missao(v_id, 'ajudar', v_feito); end if;
  return jsonb_build_object('feitos', v_feito, 'xp', v_xp,
                            'vizinho', fazenda_vizinho(p_vizinho, v_id), 'estado', fazenda_estado(v_id));
end;
$$;

-- Fase 83: o vizinho coleta o produto pronto dos bichos do dono: o produto vai para o celeiro do dono
-- (que ganha metade do XP, como com o ajudante) e quem ajuda ganha 1 ajuda por bicho
create or replace function public.fazenda_vizinho_coletar(p_token text, p_vizinho uuid, p_animais bigint[])
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_a     bigint;
  v_feito int := 0;
  v_xp    int := 0;
  v_prod  text;
begin
  if p_vizinho is null or p_vizinho = v_id then raise exception 'propria_fazenda'; end if;
  if not exists (select 1 from fazenda_jogadores where id = p_vizinho and banido_em is null) then raise exception 'vizinho_invalido'; end if;
  if p_animais is null or array_length(p_animais, 1) is null or array_length(p_animais, 1) > 50 then raise exception 'nada_a_fazer'; end if;
  foreach v_a in array p_animais loop
    begin
      select t.produto into v_prod from fazenda_animais a join fazenda_animais_tipos t on t.id = a.tipo
       where a.id = v_a and a.jogador_id = p_vizinho;
      if not found then raise exception 'animal_invalido'; end if;
      perform fazenda_animal_um(p_vizinho, v_a, 'coletar', true);
      v_xp := v_xp + fazenda_premiar_ajuda(v_id, 1, p_vizinho);
      insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd)
      values (v_id, p_vizinho, 'coleta', 0, now(), v_prod, 1);
      v_feito := v_feito + 1;
    exception when others then
      if array_length(p_animais, 1) = 1 then raise; end if;
    end;
  end loop;
  if v_feito > 0 then perform fazenda_missao(v_id, 'ajudar', v_feito); end if;
  return jsonb_build_object('feitos', v_feito, 'xp', v_xp,
                            'vizinho', fazenda_vizinho(p_vizinho, v_id), 'estado', fazenda_estado(v_id));
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
  v_nivel := fazenda_nivel(j.xp);
  return jsonb_build_object(
    'agora', now(),
    'id', j.id,
    'apelido', j.apelido,
    'avatar', j.avatar,
    'nivel', v_nivel,
    'max_canteiros', fazenda_max_canteiros(v_nivel),
    'zonas', j.zonas,
    'direita', j.direita,   -- fase 78
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

-- p_vizinho null = sorteia alguém (de preferência com colheita madura)
create or replace function public.fazenda_visitar(p_token text, p_vizinho uuid default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_dono uuid := p_vizinho;
  v_aband boolean := random() < 0.6;   -- fase 83: 6 em cada 10 vezes, primeiro as abandonadas (as que mais precisam)
begin
  if v_dono is null then
    select j.id into v_dono
      from fazenda_jogadores j
     where j.id <> v_id
       and j.visto_em > now() - interval '30 days'
       and j.banido_em is null
     order by (v_aband and j.visto_em < now() - interval '3 days') desc,
              exists (
               select 1 from fazenda_canteiros c join fazenda_culturas k on k.id = c.cultura
                where c.jogador_id = j.id and c.estado = 'plantado'
                  and c.plantado_em + make_interval(secs => k.tempo_seg) <= now()) desc,
              random()
     limit 1;
    if v_dono is null then
      raise exception 'nenhum_vizinho';
    end if;
  elsif v_dono = v_id then
    raise exception 'propria_fazenda';
  elsif not exists (select 1 from fazenda_jogadores where id = v_dono and banido_em is null) then
    raise exception 'vizinho_invalido';
  end if;

  perform fazenda_tick(v_dono);
  return fazenda_vizinho(v_dono, v_id);
end;
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
    -- fase 83: o alarme sem energia (o total de segundos desligado) e o resumo dos últimos 7 dias do
    -- que os vizinhos fizeram aqui (o jogo mostra o que é novo desde a última vez)
    'social', jsonb_build_object(   -- (fase 83: num objeto só: o estado chegou no limite de 100 argumentos)
      'alarme_off', jsonb_build_object('seg', j.alarme_off_seg, 'em', j.alarme_off_em),
      'vizinhos_resumo', coalesce((select jsonb_agg(jsonb_build_object('apelido', x.apelido, 'tipo', x.tipo, 'qtd', x.qtd, 'em', x.em) order by x.em desc)
        from (select a.apelido, v.tipo, sum(v.qtd)::int as qtd, max(v.criado_em) as em
                from fazenda_visitas v join fazenda_jogadores a on a.id = v.ator_id
               where v.dono_id = p_jogador and v.criado_em > now() - interval '7 days'
               group by a.apelido, v.tipo order by max(v.criado_em) desc limit 30) x), '[]'::jsonb),
      -- fase 83: a sequência de vizinhos ajudados (zera 10 min depois da última ajuda)
      'sequencia', case when j.seq_em > now() - interval '10 minutes' then jsonb_build_object(
                   'n', cardinality(j.seq_donos), 'bonus', fazenda_sequencia_bonus(cardinality(j.seq_donos)),
                   'ate', j.seq_em + interval '10 minutes') end),
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

-- Traz a energia até agora: soma o que os geradores fizeram desde a última conta (até
-- 12 horas, em fatias de 36 min: o sol se põe e o clima muda várias vezes por dia), queima o
-- milho do gerador a biomassa e corta no que cabe nas baterias.
create or replace function public.fazenda_energia_atualizar(p_jogador uuid)
returns real
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  j        record;
  g        record;
  v_e      real;
  v_cap    int;
  v_t      timestamptz;
  v_prox   timestamptz;
  v_tempo  int;
  v_milho  int;
  v_queima int;
  v_moedas int := 0;
  v_taxa   real;
  v_seg    real;
  v_zero   real := 0;    -- fase 83: segundos com a bateria zerada (alarme desligado)
  v_alarme boolean;
begin
  select energia, energia_em into j from fazenda_jogadores where id = p_jogador for update;
  if j.energia_em is not null and j.energia_em >= now() then
    return j.energia;                                   -- já fez a conta nesta chamada
  end if;
  if not exists (select 1 from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
                  where c.jogador_id = p_jogador and i.categoria = 'energia') then
    -- fase 46: sem máquina não tem o que contar: grava a hora no máximo de hora em hora (a primeira
    -- máquina acerta a hora em fazenda_construir)
    if j.energia_em is null or j.energia_em < now() - interval '1 hour' then
      update fazenda_jogadores set energia_em = now() where id = p_jogador;
    end if;
    return j.energia;
  end if;
  v_cap := fazenda_capacidade(p_jogador);
  v_e := j.energia;
  v_t := greatest(coalesce(j.energia_em, now()), now() - interval '12 hours');
  while v_t < now() loop
    -- fatia até a próxima troca de clima (36 min) ou de dia/noite (2 h), o que vier antes
    v_prox := least(date_trunc('minute', v_t) + make_interval(mins => 36 - fazenda_minuto_semana(v_t) % 36),
                    fazenda_dia_fim(v_t), now());
    v_taxa := fazenda_energia_taxa(p_jogador, v_t);
    v_seg := extract(epoch from v_prox - v_t)::real;
    -- fase 83: a bateria não fica abaixo de zero no meio da conta (antes a falta da noite comia o sol do
    -- dia seguinte), e o tempo zerada é guardado: é o tempo com o alarme desligado
    if v_taxa < 0 and v_e + v_taxa * v_seg / 3600 < 0 then
      v_zero := v_zero + v_seg - greatest(v_e, 0) / (-v_taxa) * 3600;
      v_e := 0;
    else
      v_e := v_e + v_taxa * v_seg / 3600;
    end if;
    v_t := v_prox;
  end loop;
  -- fase 48: bateria cheia, a sobra do sol, do vento e do reator é vendida (1 moeda a cada 5 ⚡)
  v_moedas := floor(greatest(v_e - v_cap, 0) / 5)::int;
  -- gerador a biomassa ligado: 1 milho a cada 30 min vira 25 ⚡ (acabou o milho, desliga)
  for g in
    select c.x, c.y, c.iniciado_em from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
     where c.jogador_id = p_jogador and i.efeito = 'biomassa' and c.iniciado_em is not null
       for update of c
  loop
    g.iniciado_em := greatest(g.iniciado_em, now() - interval '12 hours');
    v_tempo := floor(extract(epoch from now() - g.iniciado_em) / 1800);
    continue when v_tempo <= 0;
    v_milho := greatest(coalesce((select quantidade from fazenda_celeiro where jogador_id = p_jogador and item = 'milho'), 0)
                      - coalesce((select quantidade from fazenda_reservas where jogador_id = p_jogador and item = 'milho'), 0), 0);
    -- bateria cheia: não queima milho à toa
    v_queima := least(v_tempo, v_milho, ceil(greatest(v_cap - v_e, 0) / 25.0)::int);
    if v_queima > 0 then
      update fazenda_celeiro set quantidade = quantidade - v_queima where jogador_id = p_jogador and item = 'milho';
      v_e := v_e + 25 * v_queima;
    end if;
    update fazenda_construcoes
       set iniciado_em = case when v_milho - v_queima <= 0 then null
                              else g.iniciado_em + make_interval(secs => v_tempo * 1800) end
     where jogador_id = p_jogador and x = g.x and y = g.y;
  end loop;
  v_e := least(greatest(v_e, 0), v_cap);
  v_alarme := v_zero > 1 and exists (select 1 from fazenda_construcoes where jogador_id = p_jogador and tipo = 'alarme');
  update fazenda_jogadores set energia = v_e, energia_em = now(), moedas = moedas + v_moedas,
         alarme_off_seg = alarme_off_seg + case when v_alarme then round(v_zero)::bigint else 0 end,
         alarme_off_em = case when v_alarme then now() else alarme_off_em end
   where id = p_jogador;
  return v_e;
end;
$$;

-- o que o Perks pede (planta fácil, do ano todo, em número grande) e quantas luvas paga
create or replace function public.fazenda_perks()
returns jsonb language sql immutable as $$
  -- fase 83: 1 em cada 6 blocos de 3 h (era 30: quase ninguém via)
  select '{"luvas": 4, "nivel": 3, "chance": 6,
           "pedidos": [{"id": "alface", "qtd": 1500}, {"id": "cenoura", "qtd": 1200}, {"id": "batata", "qtd": 1000},
                       {"id": "milho", "qtd": 1000}, {"id": "tomate", "qtd": 800}, {"id": "abobora", "qtd": 600}]}'::jsonb;
$$;

-- permissões
revoke execute on function
  public.fazenda_premiar_ajuda(uuid, int, uuid),
  public.fazenda_sequencia_bonus(int),
  public.fazenda_abandonada(uuid),
  public.fazenda_roca_um(uuid, uuid, int, text)
from public, anon, authenticated;

grant execute on function
  public.fazenda_vizinho_coletar(text, uuid, bigint[]),
  public.fazenda_vizinho_bicho(text, uuid, bigint[]),
  public.fazenda_acao_vizinho(text, uuid, text, int[])
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- conferência: deve aparecer "Fase 83: ajuda vale 0,30% do nível, sequência até +100%, Perks 1 em 6"
select 'Fase 83: ajuda vale 0,30% do nível, sequência até +' || round(public.fazenda_sequencia_bonus(99) * 100) || '%, Perks 1 em ' || (public.fazenda_perks()->>'chance') as ok;
