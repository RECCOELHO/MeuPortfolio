-- ============================================================
-- FAZENDINHA — Fase 59 (etapa 3: a tela do ajudante e as camas das casinhas), só o que mudou.
-- Para o banco que já está no ar (com a fase 58): Supabase > SQL Editor > colar este arquivo > Run.
-- Pode rodar de novo (se já tinha rodado a primeira versão deste arquivo, rode esta por cima).
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- ------------------------------------------------------------
-- Fase 59: a tela do ajudante (ideias de 15/10, etapa 3). Tocar no ajudante abre o que ele fez hoje
-- e ontem, a barra de energia e o botão de mandar descansar.
-- • Energia de 0 a 100: cada tarefa gasta 100 / (ritmo x 8), então a barra cheia dura 8 horas de
--   trabalho em qualquer nível (o mesmo teto de crédito que já existia). Sem energia para mais uma
--   tarefa, ele descansa 2 h sozinho; mandado descansar, para na hora e descansa 1 h. Descansando não
--   trabalha nem junta crédito; acordou, volta com a barra cheia (fazenda_trabalhar).
-- • O eletricista não faz tarefas (só baixa o gasto da energia elétrica): não tem barra.
-- • Camas (fazenda_camas): cansado com cama livre descansa 2 h; sem cama, 4 h na sombra.
-- • O que fez: um contador por dia (fazenda_ajudantes_feito), gravado uma vez por rodada de trabalho
--   junto com a atualização que já existia; guarda só hoje, ontem e anteontem.
-- ------------------------------------------------------------
alter table public.fazenda_ajudantes add column if not exists energia real not null default 100;
alter table public.fazenda_ajudantes add column if not exists descanso_ate timestamptz;
alter table public.fazenda_ajudantes add column if not exists descanso_motivo text;   -- cansou | mandado
alter table public.fazenda_ajudantes add column if not exists descanso_casa boolean;   -- descansa numa cama (true) ou na sombra

-- Camas para descansar (ideia do Jessé: dá uso às casinhas): a casa da fazenda tem 1, cada casinha
-- vermelha mais 1 e cada azul mais 2. Cansado com cama livre: 2 h; sem cama, 4 h na sombra.
-- Mandar descansar só com cama livre.
create or replace function public.fazenda_camas(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select 1 + coalesce(sum(case tipo when 'casa_vermelha' then 1 when 'casa_azul' then 2 else 0 end), 0)::int
    from fazenda_construcoes where jogador_id = p_jogador and tipo in ('casa_vermelha', 'casa_azul');
$$;
create or replace function public.fazenda_camas_ocupadas(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from fazenda_ajudantes
   where jogador_id = p_jogador and descanso_casa and descanso_ate > now();
$$;

create table if not exists public.fazenda_ajudantes_feito (
  jogador_id uuid not null references public.fazenda_jogadores(id) on delete cascade,
  tipo       text not null,
  dia        date not null,
  feito      jsonb not null default '{}'::jsonb,
  primary key (jogador_id, tipo, dia)
);
alter table public.fazenda_ajudantes_feito enable row level security;
revoke all on public.fazenda_ajudantes_feito from anon, authenticated;

-- soma n no contador k
create or replace function public.fazenda_conta(p jsonb, k text, n int default 1)
returns jsonb language sql immutable as $$
  select coalesce(p, '{}'::jsonb) || jsonb_build_object(k, coalesce((p->>k)::int, 0) + coalesce(n, 0));
$$;

-- junta o que o ajudante fez nesta rodada no contador do dia
create or replace function public.fazenda_ajudante_registrar(p_jogador uuid, p_tipo text, p_log jsonb)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if p_log is null or p_log = '{}'::jsonb then return; end if;
  insert into fazenda_ajudantes_feito as f (jogador_id, tipo, dia, feito) values (p_jogador, p_tipo, fazenda_hoje(), p_log)
  on conflict (jogador_id, tipo, dia) do update
    set feito = (select coalesce(jsonb_object_agg(k, coalesce((f.feito->>k)::int, 0) + coalesce((excluded.feito->>k)::int, 0)), '{}'::jsonb)
                   from jsonb_object_keys(f.feito || excluded.feito) k);
  delete from fazenda_ajudantes_feito where jogador_id = p_jogador and dia < fazenda_hoje() - 2;
end;
$$;

-- mandar descansar: para na hora e volta em 1 h com a energia cheia
create or replace function public.fazenda_ajudante_descansar(p_token text, p_tipo text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
begin
  perform fazenda_trabalhar(v_id);   -- fecha o trabalho de até agora antes
  if exists (select 1 from fazenda_ajudantes where jogador_id = v_id and tipo = p_tipo and (descanso_ate is null or descanso_ate <= now()))
     and fazenda_camas_ocupadas(v_id) >= fazenda_camas(v_id) then
    raise exception 'sem_cama';   -- todas as camas das casinhas ocupadas
  end if;
  update fazenda_ajudantes h
     set descanso_ate = now() + interval '1 hour', descanso_motivo = 'mandado', descanso_casa = true, credito = 0, atualizado_em = now()
   where h.jogador_id = v_id and h.tipo = p_tipo and (h.descanso_ate is null or h.descanso_ate <= now())
     and exists (select 1 from fazenda_ajudantes_tipos t where t.id = h.tipo and t.funcao <> 'energia');
  if not found then raise exception 'ajudante_descansando'; end if;
  return jsonb_build_object('estado', fazenda_estado(v_id));
end;
$$;

-- os ajudantes gastam energia, descansam (numa cama ou na sombra) e contam o que fizeram

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
begin
  select cafe_de, cafe_ate into v_cafe_de, v_cafe_ate from fazenda_jogadores where id = p_jogador;
  for a in
    select h.tipo, h.nivel, h.credito, h.atualizado_em, h.energia, h.descanso_ate, t.funcao, t.alvo
      from fazenda_ajudantes h join fazenda_ajudantes_tipos t on t.id = h.tipo
     where h.jogador_id = p_jogador
     order by (t.funcao = 'colher') desc, t.ordem   -- fase 48: quem colhe vem antes de quem ara as murchas
       for update of h
  loop
    -- o eletricista não faz tarefas: ele baixa o gasto de energia (fazenda_energia_preco)
    continue when a.funcao = 'energia';
    -- fase 59: descansando não trabalha (nem junta crédito); acabou o descanso, volta com a energia cheia
    if a.descanso_ate is not null then
      continue when a.descanso_ate > now();
      update fazenda_ajudantes set energia = 100, descanso_ate = null, descanso_motivo = null, descanso_casa = null, credito = 0, atualizado_em = a.descanso_ate
       where jogador_id = p_jogador and tipo = a.tipo;
      a.energia := 100; a.credito := 0; a.atualizado_em := a.descanso_ate;
    end if;
    v_custo := 100 / (fazenda_ritmo(a.nivel) * 8);
    v_log := '{}'::jsonb;
    -- fase 43: com o café (diamantes) o tempo dentro dele vale em dobro
    v_seg := extract(epoch from now() - a.atualizado_em)::real
           + case when v_cafe_ate is null then 0
                  else greatest(extract(epoch from least(now(), v_cafe_ate) - greatest(a.atualizado_em, v_cafe_de))::real, 0) end;
    v_cred := least(a.credito + v_seg / 3600 * fazenda_ritmo(a.nivel), fazenda_ritmo(a.nivel) * 8);
    v_n := least(floor(v_cred), floor(a.energia / v_custo + 0.001))::int;   -- fase 59: e o que a energia deixa
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
        begin perform fazenda_aplicar(p_jogador, case when c.murcha then 'colher_tarde' else 'colher' end, c.posicao, null, true); v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'colheu');
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
             and k.estoque + (k.iniciado_em is not null)::int < fazenda_estoque_max()
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
        begin perform fazenda_aplicar(p_jogador, 'arar', c.posicao, null, true); v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'arou');
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
          begin perform fazenda_aplicar(p_jogador, 'adubar', c.posicao, null, true); v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'adubou');
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
            v_feito := v_feito + 1; v_ok := true; v_log := fazenda_conta(v_log, 'plantou');
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
          if c.erva and v_feito < v_n then perform fazenda_aplicar(p_jogador, 'erva', c.posicao, null, true); v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'erva'); end if;
          if c.praga and v_feito < v_n then perform fazenda_aplicar(p_jogador, 'praga', c.posicao, null, true); v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'praga'); end if;
          if c.seco and v_feito < v_n then perform fazenda_aplicar(p_jogador, 'seco', c.posicao, null, true); v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'seco'); end if;
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
            v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'coletou');
            m.alimentado_em := null;
          end if;
        exception when others then null;
        end;
        begin
          if m.alimentado_em is null and v_feito < v_n then
            perform fazenda_animal_um(p_jogador, m.id, 'alimentar', true);   -- sem ração no celeiro: pula
            v_feito := v_feito + 1; v_log := fazenda_conta(v_log, 'alimentou');
          end if;
        exception when others then null;
        end;
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
             descanso_casa = case when v_energia < v_custo then v_cama end
       where jogador_id = p_jogador and tipo = a.tipo;
      perform fazenda_ajudante_registrar(p_jogador, a.tipo, v_log);
    end if;
  end loop;
end;
$$;

-- o jogo recebe a energia, o descanso, as camas e o que fizeram hoje e ontem

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
    'camas', jsonb_build_object('total', fazenda_camas(p_jogador), 'ocupadas', fazenda_camas_ocupadas(p_jogador)),   -- fase 59
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
      select jsonb_agg(jsonb_build_object('tipo', h.tipo, 'nivel', h.nivel, 'relatorio', h.relatorio,
               -- fase 59: a barra de energia, o descanso e o que fez hoje e ontem
               'energia', round(h.energia::numeric, 1), 'custo', round((100 / (fazenda_ritmo(h.nivel) * 8))::numeric, 3),
               'descanso_ate', h.descanso_ate, 'descanso_motivo', h.descanso_motivo, 'descanso_casa', h.descanso_casa,
               'hoje', coalesce((select f.feito from fazenda_ajudantes_feito f where f.jogador_id = p_jogador and f.tipo = h.tipo and f.dia = fazenda_hoje()), '{}'::jsonb),
               'ontem', coalesce((select f.feito from fazenda_ajudantes_feito f where f.jogador_id = p_jogador and f.tipo = h.tipo and f.dia = fazenda_hoje() - 1), '{}'::jsonb)))
        from fazenda_ajudantes h where h.jogador_id = p_jogador), '[]'::jsonb),
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

-- as casinhas dizem quantas camas dão

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
    ('casa_vermelha', null,           0, 20, 'Casinha: +20 de beleza (beleza dá bônus nas vendas) e 1 cama para um ajudante descansar (2 h numa cama; sem cama livre, 4 h na sombra).', null, null, null),
    ('casa_azul',     null,           0, 30, 'Casinha: +30 de beleza (beleza dá bônus nas vendas) e 2 camas para os ajudantes descansarem (2 h numa cama; sem cama livre, 4 h na sombra).', null, null, null)
  ) v(id, efeito, raio, beleza, descricao, produz, produz_seg, produz_qtd)
 where i.id = v.id;

revoke execute on function
  public.fazenda_conta(jsonb, text, int),
  public.fazenda_ajudante_registrar(uuid, text, jsonb),
  public.fazenda_camas(uuid),
  public.fazenda_camas_ocupadas(uuid)
from public, anon, authenticated;
grant execute on function public.fazenda_ajudante_descansar(text, text) to anon, authenticated;

-- conferência: as três linhas devem aparecer
select 'energia dos ajudantes' as ok where exists (select 1 from information_schema.columns where table_name = 'fazenda_ajudantes' and column_name = 'energia')
union all select 'mandar descansar' where exists (select 1 from pg_proc where proname = 'fazenda_ajudante_descansar')
union all select 'camas das casinhas' where exists (select 1 from pg_proc where proname = 'fazenda_camas');
