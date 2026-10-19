-- ============================================================
-- FAZENDINHA — Fase 86 (o jogo sem travar: o Ajudar tudo numa chamada só, a média de energia pronta e o XP por canteiro),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 85): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 85 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from information_schema.columns where table_name = 'fazenda_visitas' and column_name = 'xp')) then
    raise exception 'Rode o fase85.sql antes deste (a fase 85 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 86: o jogo travando com todo mundo ajudando, e o XP por canteiro.
-- • Desde a fase 83 o "Ajudar tudo" virou a coisa mais usada do jogo, e mandava até 8 chamadas, cada uma
--   devolvendo o estado inteiro de quem ajuda: o banco ficou lento para todos (até 10 s para carregar).
--   Agora é uma chamada só, fazenda_ajudar_tudo (as antigas continuam, para o jogo velho aberto).
-- • Sai o limite de 30 ajudas por vizinho (fase 85): numa fazenda grande, um Ajudar tudo já passava dele.
--   No lugar, colher, arar e plantar dão XP 1 vez por dia em cada canteiro (fazenda_roca_um). O teto do
--   dia continua: até 1 nível inteiro vale cheio, depois 1/4.
-- • A média dos geradores (energia_medias) custava 1,5 s para montar e era apagada no fim de cada faseN.sql;
--   com o banco cheio, a chamada que ia montar caía por tempo antes de gravar e todas tentavam de novo.
--   Agora fazenda_cache_montar não apaga mais ela, e fazenda_energia_medias_refazer() monta na hora da fase.
-- ------------------------------------------------------------

-- as funções que já existiam e mudaram

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
  v_base int;
  v_un   int;
  v_cheio int;
  v_dia  int;
begin
  if coalesce(p_unidades, 0) <= 0 then return 0; end if;
  select seq_donos, seq_em, xp, ajuda_dia, ajuda_xp_dia into j from fazenda_jogadores where id = p_ator for update;
  v_seq := case when j.seq_em is null or j.seq_em < now() - interval '10 minutes' then '{}'::uuid[] else coalesce(j.seq_donos, '{}') end;
  if p_dono is not null and not (p_dono = any(v_seq)) then v_seq := v_seq || p_dono; end if;
  -- fase 86: sem o limite de 30 por vizinho (fase 85); quem segura é o canteiro (fazenda_roca_um) e o teto do dia
  v_un := p_unidades;
  v_base := round(v_un * fazenda_premio_ajuda(p_ator) * (1 + fazenda_sequencia_bonus(cardinality(v_seq)))
                  * case when fazenda_abandonada(p_dono) then 1.25 else 1 end)::int;   -- fazenda abandonada: +25% (fase 85; era +50%)
  -- fase 85: até 1 nível de XP de ajuda por dia vale cheio; o que passar disso vale 1/4
  v_dia := case when j.ajuda_dia = fazenda_hoje() then coalesce(j.ajuda_xp_dia, 0) else 0 end;
  v_cheio := greatest(0, fazenda_ajuda_teto(p_ator) - v_dia);
  v_xp := least(v_base, v_cheio) + (v_base - least(v_base, v_cheio)) / 4;
  update fazenda_jogadores set xp = xp + v_xp, moedas = moedas + p_unidades, seq_donos = v_seq, seq_em = now(),
         ajuda_dia = fazenda_hoje(), ajuda_xp_dia = v_dia + v_xp
   where id = p_ator;
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
  if v_un > 0 then perform fazenda_missao(p_ator, 'ajudar', 1); end if;
  return v_xp;
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
  select a.tipo, a.alimentado_em, t.racao, t.racao_qtd, t.tempo_seg into r
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
begin
  if p_vizinho is null or p_vizinho = v_id then raise exception 'propria_fazenda'; end if;
  if not exists (select 1 from fazenda_jogadores where id = p_vizinho and banido_em is null) then raise exception 'vizinho_invalido'; end if;
  if p_animais is null or array_length(p_animais, 1) is null or array_length(p_animais, 1) > 50 then raise exception 'nada_a_fazer'; end if;
  foreach v_a in array p_animais loop
    begin
      v_xp := v_xp + fazenda_vizinho_bicho_um(v_id, p_vizinho, v_a);
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
-- Fase 86: o miolo de 1 bicho ficou em fazenda_vizinho_coletar_um. Devolve o XP.
create or replace function public.fazenda_vizinho_coletar_um(p_ator uuid, p_dono uuid, p_animal bigint)
returns int
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_prod text;
  v_xp   int;
begin
  select t.produto into v_prod from fazenda_animais a join fazenda_animais_tipos t on t.id = a.tipo
   where a.id = p_animal and a.jogador_id = p_dono;
  if not found then raise exception 'animal_invalido'; end if;
  perform fazenda_animal_um(p_dono, p_animal, 'coletar', true);
  v_xp := fazenda_premiar_ajuda(p_ator, 1, p_dono);
  insert into fazenda_visitas (ator_id, dono_id, tipo, posicao, plantado_em, cultura, qtd, xp)
  values (p_ator, p_dono, 'coleta', 0, now(), v_prod, 1, v_xp);
  return v_xp;
end;
$$;

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
begin
  if p_vizinho is null or p_vizinho = v_id then raise exception 'propria_fazenda'; end if;
  if not exists (select 1 from fazenda_jogadores where id = p_vizinho and banido_em is null) then raise exception 'vizinho_invalido'; end if;
  if p_animais is null or array_length(p_animais, 1) is null or array_length(p_animais, 1) > 50 then raise exception 'nada_a_fazer'; end if;
  foreach v_a in array p_animais loop
    begin
      v_xp := v_xp + fazenda_vizinho_coletar_um(v_id, p_vizinho, v_a);
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

-- Fase 86: o "Ajudar tudo" numa chamada só. Eram até 8 (ajudar, colher, salvar, limpar, arar, plantar,
-- ração e coleta) e cada uma devolvia o estado inteiro de quem ajuda, o que mais pesa no servidor: com
-- muita gente ajudando, o banco ficou lento para todo mundo. p_lista:
--   {"ajudar":[pos], "colher":[pos], "salvar":[pos], "limpar":[pos], "arar":[pos], "plantar":[pos],
--    "semente":"<id>", "bicho":[animal], "coleta":[animal]}
-- Faz na ordem do jogo; o que der erro é pulado (como em lote). Devolve, por ação, quantos fez, o XP
-- e o XP de cada canteiro (ou bicho).
create or replace function public.fazenda_ajudar_tudo(p_token text, p_vizinho uuid, p_lista jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id     uuid := fazenda_auth(p_token);
  v_acao   text;
  v_item   bigint;
  v_xp     int;
  v_um     jsonb;
  v_n      int;
  v_soma   int;
  v_bichos int := 0;
  v_feitos jsonb := '{}'::jsonb;
  v_total  jsonb := '{}'::jsonb;
  v_result jsonb := '{}'::jsonb;
begin
  if p_vizinho is null or p_vizinho = v_id then raise exception 'propria_fazenda'; end if;
  if not exists (select 1 from fazenda_jogadores where id = p_vizinho and banido_em is null) then raise exception 'vizinho_invalido'; end if;
  if p_lista is null or jsonb_typeof(p_lista) <> 'object' then raise exception 'nada_a_fazer'; end if;
  if (select coalesce(sum(jsonb_array_length(v)), 0) from jsonb_each(p_lista) e(k, v) where jsonb_typeof(v) = 'array') > 400 then
    raise exception 'acao_invalida';
  end if;

  perform fazenda_tick(p_vizinho);

  foreach v_acao in array array['ajudar', 'colher', 'salvar', 'limpar', 'arar', 'plantar', 'bicho', 'coleta'] loop
    continue when jsonb_typeof(p_lista->v_acao) is distinct from 'array';
    v_um := '{}'::jsonb; v_n := 0; v_soma := 0;
    for v_item in select (x #>> '{}')::bigint from jsonb_array_elements(p_lista->v_acao) x loop
      begin
        v_xp := case v_acao
          when 'ajudar'  then fazenda_ajudar_um(v_id, p_vizinho, v_item::int)
          when 'salvar'  then fazenda_salvar_um(v_id, p_vizinho, v_item::int)
          when 'plantar' then fazenda_roca_um(v_id, p_vizinho, v_item::int, 'plantar:' || coalesce(p_lista->>'semente', ''))
          when 'bicho'   then fazenda_vizinho_bicho_um(v_id, p_vizinho, v_item)
          when 'coleta'  then fazenda_vizinho_coletar_um(v_id, p_vizinho, v_item)
          else fazenda_roca_um(v_id, p_vizinho, v_item::int, v_acao) end;   -- colher, limpar, arar
        v_um := v_um || jsonb_build_object(v_item::text, v_xp);
        v_n := v_n + 1;
        v_soma := v_soma + v_xp;
      exception when others then
        null;   -- pula o que não deu (já feito, sem ração, sem moedas...)
      end;
    end loop;
    if v_n > 0 then
      v_feitos := v_feitos || jsonb_build_object(v_acao, v_n);
      v_total := v_total || jsonb_build_object(v_acao, v_soma);
      v_result := v_result || jsonb_build_object(v_acao, v_um);
      if v_acao in ('bicho', 'coleta') then v_bichos := v_bichos + v_n; end if;
    end if;
  end loop;

  if v_bichos > 0 then perform fazenda_missao(v_id, 'ajudar', v_bichos); end if;   -- (os canteiros contam lá dentro)
  perform fazenda_bot_xp_gravar();   -- a metade do XP da colheita que vai para o dono
  return jsonb_build_object('feitos', v_feitos, 'xp', v_total, 'resultado', v_result,
                            'vizinho', fazenda_vizinho(p_vizinho, v_id), 'estado', fazenda_estado(v_id));
end;
$$;

-- refaz o cache (os gatilhos chamam; o fim de cada faseN.sql também)
create or replace function public.fazenda_cache_montar()
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  insert into fazenda_cache (chave, valor, em)
  select k, fazenda_cache_valor(k), now()
    from unnest(array['culturas', 'animais_tipos', 'conquistas_tipos', 'ajudantes_tipos', 'melhorias_tipos', 'melhorias']) k
  on conflict (chave) do update set valor = excluded.valor, em = excluded.em;
  -- se refazem na próxima vez (fase 75: e a conta da energia de cada jogador). Fase 86: a média dos geradores
  -- (energia_medias) fica: montada na hora custava 1,5 s, e com o banco cheio a chamada caía antes de gravar,
  -- então todas tentavam de novo e o jogo travava. Ela se refaz com fazenda_energia_medias_refazer().
  delete from fazenda_cache where chave like 'itens:%' or chave like 'energia:%';
end;
$$;

-- fase 86: refaz a média dos geradores na hora (no fim do fazenda.sql e de cada faseN.sql), para nenhuma
-- chamada do jogo ter que montar
create or replace function public.fazenda_energia_medias_refazer()
returns jsonb
language plpgsql security definer
set search_path = public
as $$
begin
  delete from fazenda_cache where chave = 'energia_medias' or chave like 'energia:%';
  return fazenda_energia_medias();
end;
$$;

-- permissões
revoke execute on function
  public.fazenda_premiar_ajuda(uuid, int, uuid),
  public.fazenda_roca_um(uuid, uuid, int, text),
  public.fazenda_vizinho(uuid, uuid),
  public.fazenda_vizinho_bicho_um(uuid, uuid, bigint),
  public.fazenda_vizinho_coletar_um(uuid, uuid, bigint),
  public.fazenda_cache_montar(),
  public.fazenda_energia_medias_refazer()
from public, anon, authenticated;

grant execute on function
  public.fazenda_vizinho_bicho(text, uuid, bigint[]),
  public.fazenda_vizinho_coletar(text, uuid, bigint[]),
  public.fazenda_ajudar_tudo(text, uuid, jsonb)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- a média dos geradores já pronta (as chamadas do jogo não montam mais na hora)
select public.fazenda_energia_medias_refazer() is not null as energia_medias_pronta;

-- conferência: deve aparecer "Fase 86: Ajudar tudo numa chamada só, média de energia pronta, XP por canteiro"
select 'Fase 86: Ajudar tudo numa chamada só, média de energia pronta, XP por canteiro' as ok
 where exists (select 1 from pg_proc where proname = 'fazenda_ajudar_tudo')
   and exists (select 1 from public.fazenda_cache where chave = 'energia_medias');
