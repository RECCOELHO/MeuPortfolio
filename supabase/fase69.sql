-- ============================================================
-- FAZENDINHA — Fase 69 (o calendário de resgate diário e os canteiros até o 45),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 68): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- ------------------------------------------------------------
-- Fase 69: o calendário de resgate diário (e os canteiros até o 45, em fazenda_limite_canteiros).
-- • 28 dias: um resgate por dia (o dia de Brasília, fazenda_hoje). Faltou um dia? Não perde nada: no
--   próximo resgate pega o dia seguinte do ciclo. Depois do 28, começa um ciclo novo.
-- • Trilha grátis para todos: moedas (vezes o nível), XP, café dos ajudantes, XP em dobro e diamantes
--   nos dias 7, 14, 21 e 28.
-- • Trilha dourada: liberada com 120 diamantes por ciclo. Dá um prêmio a mais por dia (XP em dobro,
--   café, pacote de XP, moedas, raros, 50 diamantes de volta) e, no dia 28, o Fazendeiro de ouro, um
--   personagem que só sai aqui (fazenda_avatar_exclusivos). Liberada no meio do ciclo, já entrega os
--   prêmios dourados dos dias que passaram.
-- • No nível 45, XP vira moedas; sem ajudante, o café vira moedas.
-- ------------------------------------------------------------
create table if not exists public.fazenda_calendario (
  jogador_id    uuid primary key references public.fazenda_jogadores(id) on delete cascade,
  ciclo         int not null default 1,
  dia           smallint not null default 0,   -- quantos dias do ciclo já resgatou (0 a 28)
  ultimo        date,                          -- o dia (de Brasília) do último resgate
  dourado_ciclo int                            -- o ciclo em que liberou a trilha dourada
);
alter table public.fazenda_calendario enable row level security;
revoke all on public.fazenda_calendario from anon, authenticated;

create or replace function public.fazenda_calendario_regras()
returns jsonb language sql immutable as $$
  select '{"dias": 28, "dourado": 120}'::jsonb;
$$;

-- os prêmios de cada dia: g = grátis, d = dourada. moedas: vezes o nível; xp: % do nível; xp2 e cafe: minutos
create or replace function public.fazenda_calendario_premios()
returns jsonb language sql immutable as $$
  select '[
    {"g": [{"tipo": "moedas", "qtd": 15}],    "d": [{"tipo": "moedas", "qtd": 50}]},
    {"g": [{"tipo": "xp", "qtd": 3}],         "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "moedas", "qtd": 20}],    "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "cafe", "qtd": 30}],      "d": [{"tipo": "xp", "qtd": 10}]},
    {"g": [{"tipo": "moedas", "qtd": 25}],    "d": [{"tipo": "moedas", "qtd": 60}]},
    {"g": [{"tipo": "xp2", "qtd": 30}],       "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "diamantes", "qtd": 3}],  "d": [{"tipo": "diamantes", "qtd": 10}, {"tipo": "item", "item": "luva_perks", "qtd": 1}]},
    {"g": [{"tipo": "moedas", "qtd": 20}],    "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "xp", "qtd": 4}],         "d": [{"tipo": "moedas", "qtd": 70}]},
    {"g": [{"tipo": "moedas", "qtd": 25}],    "d": [{"tipo": "xp", "qtd": 10}]},
    {"g": [{"tipo": "cafe", "qtd": 30}],      "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "moedas", "qtd": 30}],    "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "xp2", "qtd": 30}],       "d": [{"tipo": "moedas", "qtd": 80}]},
    {"g": [{"tipo": "diamantes", "qtd": 5}],  "d": [{"tipo": "diamantes", "qtd": 10}, {"tipo": "item", "item": "perola_negra", "qtd": 1}]},
    {"g": [{"tipo": "moedas", "qtd": 25}],    "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "xp", "qtd": 5}],         "d": [{"tipo": "xp", "qtd": 10}]},
    {"g": [{"tipo": "moedas", "qtd": 30}],    "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "cafe", "qtd": 45}],      "d": [{"tipo": "moedas", "qtd": 90}]},
    {"g": [{"tipo": "moedas", "qtd": 35}],    "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "xp2", "qtd": 45}],       "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "diamantes", "qtd": 5}],  "d": [{"tipo": "diamantes", "qtd": 10}, {"tipo": "item", "item": "luva_perks", "qtd": 2}]},
    {"g": [{"tipo": "moedas", "qtd": 30}],    "d": [{"tipo": "xp", "qtd": 10}]},
    {"g": [{"tipo": "xp", "qtd": 5}],         "d": [{"tipo": "moedas", "qtd": 100}]},
    {"g": [{"tipo": "moedas", "qtd": 40}],    "d": [{"tipo": "xp2", "qtd": 60}]},
    {"g": [{"tipo": "cafe", "qtd": 60}],      "d": [{"tipo": "cafe", "qtd": 120}]},
    {"g": [{"tipo": "moedas", "qtd": 45}],    "d": [{"tipo": "xp", "qtd": 10}]},
    {"g": [{"tipo": "xp2", "qtd": 60}],       "d": [{"tipo": "moedas", "qtd": 120}]},
    {"g": [{"tipo": "diamantes", "qtd": 10}], "d": [{"tipo": "avatar", "avatar": "fazendeiro_ouro"}, {"tipo": "diamantes", "qtd": 20}]}
  ]'::jsonb;
$$;

-- personagens que não estão à venda: só saem de um prêmio (o do calendário dourado)
create or replace function public.fazenda_avatar_exclusivos()
returns jsonb language sql immutable as $$
  select '{"fazendeiro_ouro": "calendario"}'::jsonb;
$$;

-- Entrega um prêmio e devolve o que foi dado de fato (com as moedas já vezes o nível)
create or replace function public.fazenda_calendario_dar(p_jogador uuid, p jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_nivel int;
  v_tipo  text := p->>'tipo';
  v_qtd   int := coalesce((p->>'qtd')::int, 1);
  v_xp    int;
begin
  select fazenda_nivel(xp) into v_nivel from fazenda_jogadores where id = p_jogador;
  if v_tipo in ('xp', 'xp2') and v_nivel >= 45 then v_tipo := 'moedas'; v_qtd := 50; end if;   -- no último nível, XP não serve
  if v_tipo = 'cafe' and not exists (select 1 from fazenda_ajudantes where jogador_id = p_jogador) then v_tipo := 'moedas'; v_qtd := 20; end if;
  if v_tipo = 'moedas' then
    update fazenda_jogadores set moedas = moedas + v_qtd * v_nivel where id = p_jogador;
    return jsonb_build_object('tipo', 'moedas', 'qtd', v_qtd * v_nivel);
  elsif v_tipo = 'diamantes' then
    update fazenda_jogadores set diamantes = diamantes + v_qtd where id = p_jogador;
    return jsonb_build_object('tipo', 'diamantes', 'qtd', v_qtd);
  elsif v_tipo = 'xp' then
    v_xp := ceil((fazenda_xp_nivel(v_nivel + 1) - fazenda_xp_nivel(v_nivel)) * v_qtd / 100.0)::int;
    perform set_config('fazenda.xp_puro', '1', true);
    update fazenda_jogadores set xp = xp + v_xp where id = p_jogador;
    perform set_config('fazenda.xp_puro', '', true);
    return jsonb_build_object('tipo', 'xp', 'qtd', v_xp, 'pct', v_qtd);
  elsif v_tipo = 'xp2' then
    update fazenda_jogadores set xp2_ate = greatest(coalesce(xp2_ate, now()), now()) + make_interval(mins => v_qtd) where id = p_jogador;
    return jsonb_build_object('tipo', 'xp2', 'qtd', v_qtd);
  elsif v_tipo = 'cafe' then
    perform fazenda_trabalhar(p_jogador);   -- fecha o trabalho de antes no ritmo de antes (igual ao café da loja)
    perform fazenda_ajudantes_fechar(p_jogador, null);
    update fazenda_jogadores
       set cafe_de = case when cafe_ate > now() then cafe_de else now() end,
           cafe_ate = greatest(coalesce(cafe_ate, now()), now()) + make_interval(mins => v_qtd)
     where id = p_jogador;
    return jsonb_build_object('tipo', 'cafe', 'qtd', v_qtd);
  elsif v_tipo = 'item' then
    insert into fazenda_celeiro (jogador_id, item, quantidade) values (p_jogador, p->>'item', v_qtd)
    on conflict (jogador_id, item) do update set quantidade = fazenda_celeiro.quantidade + excluded.quantidade;
    return jsonb_build_object('tipo', 'item', 'item', p->>'item', 'qtd', v_qtd);
  elsif v_tipo = 'avatar' then
    update fazenda_jogadores set avatares = array_append(coalesce(avatares, '{}'), p->>'avatar')
     where id = p_jogador and not (p->>'avatar' = any(coalesce(avatares, '{}')));
    return jsonb_build_object('tipo', 'avatar', 'avatar', p->>'avatar');
  end if;
  return null;
end;
$$;

-- O calendário como o jogo mostra: o ciclo, quantos dias já foram, se dá para resgatar hoje e se a
-- trilha dourada está liberada. Ciclo acabado e já é outro dia: mostra o ciclo novo (o resgate começa ele).
create or replace function public.fazenda_calendario_estado(p_jogador uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare
  r      record;
  v_pode boolean;
  v_dias int := (fazenda_calendario_regras()->>'dias')::int;
  v_ciclo int := 1;
  v_dia   int := 0;
begin
  select * into r from fazenda_calendario where jogador_id = p_jogador;
  v_pode := r.ultimo is null or r.ultimo < fazenda_hoje();
  if found then v_ciclo := r.ciclo; v_dia := r.dia; end if;
  if v_dia >= v_dias and v_pode then v_ciclo := v_ciclo + 1; v_dia := 0; end if;
  return jsonb_build_object('ciclo', v_ciclo, 'dia', v_dia, 'pode', v_pode,
                            'dourado', coalesce(r.dourado_ciclo = v_ciclo, false),
                            'regras', fazenda_calendario_regras(), 'premios', fazenda_calendario_premios());
end;
$$;

create or replace function public.fazenda_calendario_resgatar(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_dias int := (fazenda_calendario_regras()->>'dias')::int;
  r      record;
  v_p    jsonb;
  x      jsonb;
  v_g    jsonb := '[]'::jsonb;
  v_d    jsonb := '[]'::jsonb;
begin
  insert into fazenda_calendario (jogador_id) values (v_id) on conflict (jogador_id) do nothing;
  select * into r from fazenda_calendario where jogador_id = v_id for update;   -- dois toques juntos: um só passa
  if r.ultimo = fazenda_hoje() then raise exception 'calendario_hoje'; end if;
  if r.dia >= v_dias then r.ciclo := r.ciclo + 1; r.dia := 0; end if;
  r.dia := r.dia + 1;
  v_p := fazenda_calendario_premios() -> (r.dia - 1);
  for x in select * from jsonb_array_elements(v_p->'g') loop v_g := v_g || jsonb_build_array(fazenda_calendario_dar(v_id, x)); end loop;
  if r.dourado_ciclo = r.ciclo then
    for x in select * from jsonb_array_elements(v_p->'d') loop v_d := v_d || jsonb_build_array(fazenda_calendario_dar(v_id, x)); end loop;
  end if;
  update fazenda_calendario set ciclo = r.ciclo, dia = r.dia, ultimo = fazenda_hoje() where jogador_id = v_id;
  return jsonb_build_object('dia', r.dia, 'gratis', v_g, 'dourado', v_d, 'estado', fazenda_estado(v_id));
end;
$$;

-- Libera a trilha dourada do ciclo de agora (os dias já resgatados ganham o prêmio dourado na hora)
create or replace function public.fazenda_calendario_dourado(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_regra jsonb := fazenda_calendario_regras();
  v_preco int := (v_regra->>'dourado')::int;
  r       record;
  x       jsonb;
  v_d     jsonb := '[]'::jsonb;
begin
  insert into fazenda_calendario (jogador_id) values (v_id) on conflict (jogador_id) do nothing;
  select * into r from fazenda_calendario where jogador_id = v_id for update;
  if r.dia >= (v_regra->>'dias')::int and (r.ultimo is null or r.ultimo < fazenda_hoje()) then   -- o ciclo novo já começou
    r.ciclo := r.ciclo + 1; r.dia := 0;
  end if;
  if r.dourado_ciclo = r.ciclo then raise exception 'ja_dourado'; end if;
  if (select diamantes from fazenda_jogadores where id = v_id for update) < v_preco then raise exception 'diamantes_insuficientes'; end if;
  update fazenda_jogadores set diamantes = diamantes - v_preco where id = v_id;
  insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, 'calendario_dourado', v_preco);
  update fazenda_calendario set ciclo = r.ciclo, dia = r.dia, dourado_ciclo = r.ciclo where jogador_id = v_id;
  for k in 1..r.dia loop
    for x in select * from jsonb_array_elements(fazenda_calendario_premios() -> (k - 1) -> 'd') loop
      v_d := v_d || jsonb_build_array(fazenda_calendario_dar(v_id, x));
    end loop;
  end loop;
  return jsonb_build_object('dourado', v_d, 'estado', fazenda_estado(v_id));
end;
$$;

-- as funções que já existiam e mudaram

-- fase 69: +2 por nível até o último (era até o 25: o limite parava em 54)
create or replace function public.fazenda_limite_canteiros(p_nivel int, p_zonas int)
returns int language sql immutable as $$
  select least(6 + (p_nivel - 1) * 2, 94)
       + coalesce((select sum(coalesce((z->>'canteiros')::int, 6))::int from jsonb_array_elements(fazenda_zonas()) z
                    where (z->>'n')::int <= p_zonas), 0);
$$;

-- Salva o avatar: o personagem (tipo) e o número de cada cor (0 = a cor original do personagem;
-- as cores ficam no cliente, em AVATAR_CORES de fazenda-arte.js). O que faltar vira 0.
create or replace function public.fazenda_avatar(p_token text, p_avatar jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v       jsonb;
  r       record;
  j       record;
  v_preco int;
  v_diam  int := 0;
begin
  if jsonb_typeof(p_avatar) is distinct from 'object' then raise exception 'avatar_invalido'; end if;
  if not (fazenda_avatar_precos() ? coalesce(p_avatar->>'tipo', 'fazendeiro')
          or fazenda_avatar_diamantes() ? coalesce(p_avatar->>'tipo', 'fazendeiro')
          or fazenda_avatar_exclusivos() ? coalesce(p_avatar->>'tipo', 'fazendeiro')) then   -- fase 69: os exclusivos
    raise exception 'avatar_invalido';
  end if;
  v := jsonb_build_object('tipo', coalesce(p_avatar->>'tipo', 'fazendeiro'));
  for r in select * from (values ('pele', 5), ('cabelo', 6), ('roupa', 8), ('calca', 6), ('chapeu', 6)) x(chave, n) loop
    if p_avatar ? r.chave then
      if jsonb_typeof(p_avatar->r.chave) <> 'number' or (p_avatar->>r.chave)::numeric % 1 <> 0
         or (p_avatar->>r.chave)::numeric not between 0 and r.n - 1 then
        raise exception 'avatar_invalido';
      end if;
      v := v || jsonb_build_object(r.chave, (p_avatar->>r.chave)::int);
    else
      v := v || jsonb_build_object(r.chave, 0);
    end if;
  end loop;
  -- personagem que ainda não é seu: compra agora (se tiver moedas)
  select * into j from fazenda_jogadores where id = v_id for update;
  v_preco := coalesce((fazenda_avatar_precos()->>(v->>'tipo'))::int, 0);
  v_diam := coalesce((fazenda_avatar_diamantes()->>(v->>'tipo'))::int, 0);
  if (v->>'tipo') = any(j.avatares) then
    v_preco := 0; v_diam := 0;
  elsif fazenda_avatar_exclusivos() ? (v->>'tipo') then   -- fase 69: exclusivo não se compra, só se ganha
    raise exception 'avatar_exclusivo';
  elsif v_diam > 0 then   -- personagem de diamante
    if j.diamantes < v_diam then raise exception 'diamantes_insuficientes'; end if;
    update fazenda_jogadores set diamantes = diamantes - v_diam, avatares = array_append(avatares, v->>'tipo') where id = v_id;
    insert into fazenda_diamantes_usos (jogador_id, item, diamantes) values (v_id, 'avatar:' || (v->>'tipo'), v_diam);
  elsif v_preco > 0 then
    if j.moedas < v_preco then raise exception 'moedas_insuficientes'; end if;
    update fazenda_jogadores set moedas = moedas - v_preco, avatares = array_append(avatares, v->>'tipo') where id = v_id;
  end if;
  update fazenda_jogadores set avatar = v where id = v_id;
  return jsonb_build_object('avatar', v, 'pagou', v_preco, 'pagou_diamantes', v_diam, 'estado', fazenda_estado(v_id));
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
     where id = p_jogador;
    select * into j from fazenda_jogadores where id = p_jogador;
  end if;
  -- canteiros não aparecem mais sozinhos: o jogador coloca no modo construir até este limite
  v_max := fazenda_limite_canteiros(v_nivel, j.zonas);
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
    'culturas', (
      select jsonb_agg(jsonb_build_object(
               'id', id, 'nome', nome, 'emoji', emoji, 'tempo_seg', tempo_seg,
               'custo', custo, 'venda', venda, 'rendimento', rendimento,
               'xp', xp, 'nivel_min', nivel_min, 'tipo', tipo, 'estacao', estacao)
             order by ordem)
        from fazenda_culturas),
    'animais', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'alimentado_em', alimentado_em,
               'radioativo_ate', case when radioativo_ate > now() then radioativo_ate end) order by id)   -- fase 68
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
    -- fase 63: o evento da semana (até quando vai, os prêmios ainda não vistos e os troféus)
    'evento', jsonb_build_object(
      'fim', fazenda_semana_inicio(now()) + interval '7 days',
      'novos', coalesce((select jsonb_agg(jsonb_build_object('semana', semana, 'categoria', categoria, 'posicao', posicao,
                                   'valor', valor, 'diamantes', diamantes, 'item', item) order by categoria, posicao)
                           from fazenda_semana_premios where jogador_id = p_jogador and not visto), '[]'::jsonb),
      'trofeus', fazenda_trofeus(p_jogador),
      'regras', fazenda_evento_regras()),
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
  update fazenda_semana_premios set visto = true where jogador_id = p_jogador and not visto;   -- e os prêmios do evento (fase 63)
  update fazenda_murchas set visto = true where jogador_id = p_jogador and not visto;   -- e o relatório das murchas (fase 66)
  update fazenda_feira set reserva_vista = true where reservado_para = p_jogador and not reserva_vista;   -- e o que separaram no chat (fase 67)
  update fazenda_radiacao set visto = true where jogador_id = p_jogador and not visto;   -- e a radiação do reator (fase 68)
  return v_json;
end;
$$;

-- permissões
revoke execute on function
  public.fazenda_calendario_regras(),
  public.fazenda_calendario_premios(),
  public.fazenda_avatar_exclusivos(),
  public.fazenda_calendario_dar(uuid, jsonb),
  public.fazenda_calendario_estado(uuid)
from public, anon, authenticated;

grant execute on function
  public.fazenda_calendario_resgatar(text),
  public.fazenda_calendario_dourado(text)
to anon, authenticated;

-- conferência: deve aparecer "Calendário: 28 dias, dourado por 120 diamantes; nível 45 com 94 canteiros"
select 'Calendário: ' || (public.fazenda_calendario_regras()->>'dias') || ' dias, dourado por ' || (public.fazenda_calendario_regras()->>'dourado')
    || ' diamantes; nível 45 com ' || public.fazenda_limite_canteiros(45, 0) || ' canteiros' as ok;
