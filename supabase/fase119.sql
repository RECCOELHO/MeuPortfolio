-- ============================================================
-- FAZENDINHA — Fase 119 (a conta de teste: fora dos rankings, do evento, das visitas, do chat e da feira),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 118): Supabase > SQL Editor > colar este arquivo > Run.
-- Pode rodar antes do merge do PR (o jogo não muda).
-- Depois, a conta: num SQL à parte, select * from fazenda_teste_criar('o apelido');
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 118 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not exists (select 1 from pg_proc where proname = 'fazenda_caverna_explorar') then
    raise exception 'Rode o fase118.sql antes deste. Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 119: a conta de teste do Jessé. Uma conta marcada como teste (fazenda_jogadores.teste) fica fora do
-- ranking, do evento da semana, do sorteio das visitas, do chat (só ela vê o que escreve) e da feira (só ela
-- vê o que anuncia). fazenda_teste_criar (só pelo SQL Editor: o jogo não chama) cria a conta, ou refaz a
-- que já existe, com tudo liberado para chegar na ilha: nível 60, todos os terrenos (também os da ilha), o
-- píer pronto, o barco com o kit de expedição, 50 milhões de moedas, 5 mil diamantes, os materiais das
-- 15 obras e os produtos da ilha para o Capitão. Devolve o código de entrada, gerado no banco: só quem roda
-- vê. Rodar de novo troca o código (o antigo para de funcionar).
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------
alter table public.fazenda_jogadores add column if not exists teste boolean not null default false;   -- fase 119: conta de teste (fora dos rankings, do evento, das visitas, do chat e da feira)

create or replace function public.fazenda_teste_criar(p_apelido text)
returns table (apelido text, codigo text)
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id     uuid;
  v_teste  boolean;
  v_codigo text := fazenda_codigo_recuperacao();
begin
  if char_length(coalesce(p_apelido, '')) not between 2 and 20 then raise exception 'O apelido precisa ter de 2 a 20 letras.'; end if;
  select j.id, j.teste into v_id, v_teste from fazenda_jogadores j where j.apelido = p_apelido;
  if v_id is not null and not v_teste then
    raise exception 'Já existe um jogador de verdade chamado "%". Escolha outro apelido para a conta de teste. Nada foi mudado.', p_apelido;
  end if;
  if v_id is null then
    insert into fazenda_jogadores (apelido, codigo_hash, convite, teste)
    values (p_apelido, encode(digest(v_codigo, 'sha256'), 'hex'), fazenda_novo_convite(), true)
    returning id into v_id;
    insert into fazenda_canteiros (jogador_id, posicao, estado, x, y)
    select v_id, g, 'arado', 9 + g, 4 from generate_series(0, 5) g;
    insert into fazenda_construcoes (jogador_id, x, y, tipo, colhido_em) values (v_id, 8, 3, 'lampiao', now());
    update fazenda_jogadores set ganhou_poste = true where id = v_id;
  else
    update fazenda_jogadores set codigo_hash = encode(digest(v_codigo, 'sha256'), 'hex') where id = v_id;
    delete from fazenda_sessoes where jogador_id = v_id;   -- o código antigo e quem estava dentro saem
  end if;
  -- tudo liberado (o XP não passa pelo dobro e os presentes de nível não chovem de uma vez)
  perform set_config('fazenda.xp_puro', '1', true);
  update fazenda_jogadores
     set teste = true, xp = greatest(xp, fazenda_xp_nivel(60)::int), nivel_premiado = 60, nivel_base = 60, nivel_trava = 60,
         moedas = greatest(moedas, 50000000), diamantes = greatest(diamantes, 5000),
         zonas = 7, direita = 3, ilha_terrenos = 3, pier_em = coalesce(pier_em, now())
   where id = v_id;
  perform set_config('fazenda.xp_puro', '', true);
  insert into fazenda_melhorias (jogador_id, id, nivel)
  values (v_id, 'barco', 4), (v_id, 'expedicao', 1), (v_id, 'motor', 3), (v_id, 'porao', 3), (v_id, 'rede', 2), (v_id, 'sonar', 3)
  on conflict (jogador_id, id) do update set nivel = greatest(fazenda_melhorias.nivel, excluded.nivel);
  -- os materiais das 15 obras (com folga) e os produtos da ilha (para o Capitão)
  insert into fazenda_celeiro (jogador_id, item, quantidade)
  select v_id, m.item, m.qtd
    from (values ('tora', 100), ('tabua_naval', 300), ('cravo', 300), ('vela', 30), ('corda_naval', 10), ('carta_nautica', 20),
                 ('madeira_nobre', 3), ('pedra_cantaria', 3), ('ferro_forjado', 3), ('leme_dourado', 2), ('ancora', 2), ('perola_negra', 3),
                 ('abacaxi', 300), ('banana', 100), ('cana_roxa', 200), ('especiarias', 200), ('rapadura', 100), ('tempero_indias', 100),
                 ('biscoito_bordo', 60), ('racao_marinheiro', 20), ('concha', 50), ('pena_arara', 50)) m(item, qtd)
   where exists (select 1 from fazenda_culturas k where k.id = m.item)
  on conflict (jogador_id, item) do update set quantidade = greatest(fazenda_celeiro.quantidade, excluded.quantidade);
  return query select p_apelido, v_codigo;
end;
$$;
revoke execute on function public.fazenda_teste_criar(text) from public, anon, authenticated;

-- as funções que mudaram

create or replace function public.fazenda_ranking(p_token text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_xp   int;
  v_desde timestamptz;
begin
  select xp, criado_em into v_xp, v_desde from fazenda_jogadores where id = v_id;
  return jsonb_build_object(
    -- mesmo critério de desempate da lista: quem chegou antes fica na frente
    'minha_posicao', (select count(*) + 1 from fazenda_jogadores
                       where (xp > v_xp or (xp = v_xp and criado_em < v_desde)) and banido_em is null and not teste),   -- (fase 119: sem as contas de teste)
    'total', (select count(*) from fazenda_jogadores where banido_em is null and not teste),
    'ranking', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', r.id, 'apelido', r.apelido, 'avatar', r.avatar, 'nivel', fazenda_nivel_de(r.xp, r.nivel_trava), 'xp', r.xp,
               'patrimonio', r.moedas + coalesce((
                 select sum(ce.quantidade * k.venda)
                   from fazenda_celeiro ce join fazenda_culturas k on k.id = ce.item
                  where ce.jogador_id = r.id), 0),
               'eu', r.id = v_id)
             order by r.xp desc, r.criado_em)
        from (select * from fazenda_jogadores where banido_em is null and (not teste or id = v_id) order by xp desc, criado_em limit 200) r), '[]'::jsonb)   -- (fase 53: eram 50)
  );
end;
$$;


-- os números de cada jogador numa semana (p_semana = o início dela; conta de p_desde a p_ate).
-- Quem entrou na semana não tem foto: conta do zero. Quem foi banido não entra.
create or replace function public.fazenda_semana_placar(p_semana timestamptz, p_desde timestamptz, p_ate timestamptz)
returns table (jogador_id uuid, apelido text, avatar jsonb, criado_em timestamptz, ranking bigint, niveis bigint,
               moedas bigint, vendeu bigint, comprou bigint, convites bigint)
language sql stable security definer set search_path = public as $$
  -- fase 70: o XP comprado com diamante não conta (ranking e níveis); na barraca, uma mesma pessoa do
  -- outro lado conta no máximo 25% do total (duas contas vendendo uma para a outra não ganham sozinhas)
  select j.id, j.apelido, j.avatar, j.criado_em,
         (j.xp - coalesce(b.xp, 0) - (j.xp_pago - coalesce(b.xp_pago, 0)))::bigint,
         -- fase 113: o nível da tela (com a trava; o XP comprado continua fora) menos o da foto; quem entrou na
         -- semana não tem foto e conta do nível 10 em diante
         greatest(0, fazenda_nivel_de((j.xp - (j.xp_pago - coalesce(b.xp_pago, 0)))::int, j.nivel_trava)
                     - case when b.jogador_id is null then 10 else coalesce(b.nivel, fazenda_nivel_de(b.xp::int, j.nivel_trava)) end)::bigint,
         (j.moedas_ganhas - coalesce(b.moedas_ganhas, 0))::bigint,
         coalesce((select sum(least(t.v, ceil(t.total * 0.25))) from (
                    select sum(f.qtd::bigint * f.preco) as v, sum(sum(f.qtd::bigint * f.preco)) over () as total from fazenda_feira f
                     where f.vendedor_id = j.id and f.vendido_em >= p_desde and f.vendido_em < p_ate group by f.comprador_id) t), 0)::bigint,
         coalesce((select sum(least(t.v, ceil(t.total * 0.25))) from (
                    select sum(f.qtd::bigint * f.preco) as v, sum(sum(f.qtd::bigint * f.preco)) over () as total from fazenda_feira f
                     where f.comprador_id = j.id and f.vendido_em >= p_desde and f.vendido_em < p_ate group by f.vendedor_id) t), 0)::bigint,
         (select count(*) from fazenda_convites c join fazenda_jogadores a on a.id = c.convidado_id
           where c.dono_id = j.id and c.criado_em >= p_desde and c.criado_em < p_ate and a.banido_em is null
             and fazenda_nivel_de(a.xp, a.nivel_trava) >= (fazenda_evento_regras()->>'convite_nivel')::int)::bigint
    from fazenda_jogadores j
    left join fazenda_semana_base b on b.jogador_id = j.id and b.semana = p_semana
   where j.banido_em is null and not j.teste   -- (fase 119: a conta de teste não entra no evento)
     -- fase 71: só quem jogou na semana (visto_em, com 1 h de folga), vendeu ou comprou na feira ou trouxe
     -- convite nela: quem não jogou tem tudo zerado (e o placar de todos pesava no fechamento e no Evento)
     and (j.visto_em >= p_desde - interval '1 hour'
          or exists (select 1 from fazenda_feira f
                      where (f.vendedor_id = j.id or f.comprador_id = j.id) and f.vendido_em >= p_desde and f.vendido_em < p_ate)
          or exists (select 1 from fazenda_convites c where c.dono_id = j.id and c.criado_em >= p_desde and c.criado_em < p_ate));
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
       and j.banido_em is null and not j.teste   -- (fase 119: ninguém cai na conta de teste)
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


-- A conversa da última hora (as 80 mais novas, sem as apagadas e sem as de banidos). Com p_depois, só as
-- novas, os ids que sumiram (apagados) e quem atendeu os pedidos (para a busca de 5 em 5 s ficar leve).
create or replace function public.fazenda_chat(p_token text, p_depois bigint default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth_ler(p_token);   -- fase 71: só lê, sem a fila de uma por vez
  v_r  jsonb := fazenda_chat_regras();
  v_de timestamptz := now() - make_interval(mins => (v_r->>'minutos')::int);
  j    record;
begin
  select fazenda_nivel_de(xp, nivel_trava) as nivel, admin into j from fazenda_jogadores where id = v_id;
  return jsonb_build_object(
    'regras', v_r,
    'pode_escrever', j.nivel >= (v_r->>'nivel')::int,
    'admin', j.admin is not null,
    'mensagens', coalesce((
      select jsonb_agg(m order by (m->>'id')::bigint) from (
        select jsonb_build_object('id', c.id, 'jogador', c.jogador_id, 'apelido', p.apelido, 'avatar', p.avatar,
                 'nivel', fazenda_nivel_de(p.xp, p.nivel_trava), 'admin', p.admin, 'texto', c.texto, 'em', c.criado_em,
                 'pedido', case when c.item is not null then jsonb_build_object('item', c.item, 'qtd', c.qtd, 'preco', c.preco) end) as m
          from fazenda_chat c join fazenda_jogadores p on p.id = c.jogador_id
         where c.criado_em >= v_de and c.apagado_em is null and p.banido_em is null
           and (not p.teste or p.id = v_id)   -- (fase 119: a conta de teste fala sozinha)
           and (p_depois is null or c.id > p_depois)
         order by c.id desc
         limit (v_r->>'mostrar')::int) x), '[]'::jsonb),
    'apagadas', case when p_depois is null then '[]'::jsonb else coalesce((
      select jsonb_agg(c.id) from fazenda_chat c join fazenda_jogadores p on p.id = c.jogador_id
       where c.criado_em >= v_de and c.id <= p_depois and (c.apagado_em is not null or p.banido_em is not null)), '[]'::jsonb) end,
    'atendidos', coalesce((
      select jsonb_object_agg(x.pedido_id::text, x.quem) from (
        select f.pedido_id, jsonb_agg(jsonb_build_object('apelido', vj.apelido, 'qtd', f.qtd) order by f.id) as quem
          from fazenda_feira f join fazenda_jogadores vj on vj.id = f.vendedor_id
          join fazenda_chat c on c.id = f.pedido_id
         where c.criado_em >= v_de
         group by f.pedido_id) x), '{}'::jsonb));
end;
$$;


-- as ofertas abertas dos outros (as mais baratas primeiro; com p_item, só daquele item) e as suas.
-- Fase 67: a reservada para outra pessoa não aparece enquanto a reserva vale; a reservada para você vem primeiro.
create or replace function public.fazenda_feira_lista(p_token text, p_item text default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth_ler(p_token);   -- fase 71: só lê, sem a fila de uma por vez
  v_r  jsonb := fazenda_feira_regras();
begin
  perform fazenda_feira_vencidos(v_id);
  return jsonb_build_object(
    'regras', v_r,
    'ofertas', coalesce((
      select jsonb_agg(o order by (o ? 'reservado_ate') desc, (o->>'preco')::int, (o->>'id')::bigint) from (
        select jsonb_build_object('id', f.id, 'item', f.item, 'qtd', f.qtd, 'preco', f.preco, 'vendedor', j.apelido,
                                  'avatar', j.avatar, 'ate', f.criado_em + make_interval(hours => (v_r->>'horas')::int))
               || case when f.reservado_para = v_id and f.reservado_ate > now() then jsonb_build_object('reservado_ate', f.reservado_ate) else '{}'::jsonb end as o
          from fazenda_feira f join fazenda_jogadores j on j.id = f.vendedor_id
         where f.vendido_em is null and f.vendedor_id <> v_id
           and not j.teste   -- (fase 119: as ofertas da conta de teste ninguém vê)
           and f.criado_em >= now() - make_interval(hours => (v_r->>'horas')::int)
           and (f.reservado_para is null or f.reservado_para = v_id or f.reservado_ate <= now())
           and (p_item is null or f.item = p_item)
         order by (f.reservado_para = v_id and f.reservado_ate > now()) desc nulls last, f.preco, f.id
         limit 60) x), '[]'::jsonb),
    'itens', coalesce((
      select jsonb_agg(distinct f.item) from fazenda_feira f
       where f.vendido_em is null and f.vendedor_id <> v_id
         and not exists (select 1 from fazenda_jogadores t where t.id = f.vendedor_id and t.teste)
         and f.criado_em >= now() - make_interval(hours => (v_r->>'horas')::int)
         and (f.reservado_para is null or f.reservado_para = v_id or f.reservado_ate <= now())), '[]'::jsonb),
    'compras_hoje', (select count(*) from fazenda_feira where comprador_id = v_id and vendido_em > now() - interval '1 day'));
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
  -- fase 89: sessão do jogo novo, que já tem os catálogos: manda só o que muda
  v_leve  boolean := coalesce(current_setting('fazenda.leve', true), '') = '1'
                     and current_setting('fazenda.eu', true) = p_jogador::text;
  v_omite boolean := false;
  v_ver   text;
begin
  -- fase 89: na sessão leve, as conquistas ficam para o carregar (de minuto em minuto)
  if not v_leve or coalesce(current_setting('fazenda.carregar', true), '') = '1' then
    perform fazenda_checar_conquistas(p_jogador);
  end if;
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
  v_nivel := fazenda_nivel_de(j.xp, j.nivel_trava);
  -- subiu de nível: presente de moedas e 5 diamantes por cada nível novo
  if v_nivel > coalesce(j.nivel_premiado, 1) then
    update fazenda_jogadores
       set moedas = moedas + (select sum(fazenda_presente_nivel(n)) from generate_series(coalesce(j.nivel_premiado, 1) + 1, v_nivel) n),
           diamantes = diamantes + 5 * (v_nivel - coalesce(j.nivel_premiado, 1)),
           nivel_premiado = v_nivel,
           nivel_base = greatest(coalesce(nivel_base, 1), v_nivel)   -- fase 112: o nível que você alcançou não cai mais
     where id = p_jogador and nivel_premiado is not distinct from j.nivel_premiado;   -- fase 70: paga uma vez só
    select * into j from fazenda_jogadores where id = p_jogador;
  end if;
  v_omite := v_leve and fazenda_catalogos_ver(v_nivel) = current_setting('fazenda.cat_ver', true);   -- fase 89
  -- canteiros não aparecem mais sozinhos: o jogador coloca no modo construir até este limite
  v_max := fazenda_limite_canteiros(v_nivel, fazenda_terrenos(j.zonas, j.direita) + 100 * j.ilha_terrenos);
  -- fase 49: as metas de nível; com todas em dia, o bônus de XP vale neste nível (só grava se mudou)
  v_metas := fazenda_metas(p_jogador, v_nivel);
  -- (fase 62: até o 44; era até o 29, quando o 30 era o último nível)
  v_bonus := case when v_nivel < 60 and not exists (select 1 from jsonb_array_elements(v_metas) m where not (m->>'feito')::boolean)
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
      -- fase 93: os bônus dos prêmios do evento (plantas 2x mais rápidas, +50% na venda, +50% na colheita) e
      -- quanto de cada item do celeiro veio da feira (sem o +50% do cofrinho). Num objeto só: o estado
      -- está no limite de 100 argumentos do jsonb_build_object
      'premios', jsonb_build_object(
        'crescer_ate', case when j.crescer_ate > now() then j.crescer_ate end,
        'venda50_ate', case when j.venda50_ate > now() then j.venda50_ate end,
        'colheita50_ate', case when j.colheita50_ate > now() then j.colheita50_ate end,
        'da_feira', coalesce((select jsonb_object_agg(item, least(da_feira, quantidade))
                                from fazenda_celeiro where jogador_id = p_jogador and quantidade > 0 and da_feira > 0), '{}'::jsonb)),
      'xp_compras_hoje', fazenda_diamantes_hoje(p_jogador, 'xp'),
      -- conta Google ligada (só aparece para o dono; null = não ligada)
      'google', case when j.google_sub is not null then coalesce(j.google_email, 'sua conta Google') end,
      'admin', j.admin,   -- fase 53: 'dono', 'admin' ou null
      'xp', j.xp,
      'nivel', v_nivel,
      -- fase 90: com XP para mais e travado por faltar algo do nível: o que falta comprar
      'trava', case when fazenda_nivel(j.xp) > v_nivel then
                 jsonb_build_object('nivel', v_nivel, 'faltam', fazenda_nivel_faltam(p_jogador, v_nivel)) end,
      'xp_nivel', fazenda_xp_nivel(v_nivel),
      'xp_proximo', fazenda_xp_nivel(v_nivel + 1),
      'bonus_nivel', v_bonus,   -- fase 49: +50% de XP neste nível (metas em dia)
      'max_canteiros', v_max,
      'max_construcoes', fazenda_max_construcoes(fazenda_terrenos(j.zonas, j.direita) + 100 * j.ilha_terrenos),
      'zonas', j.zonas,
      'direita', j.direita,   -- fase 78: os terrenos da direita
      'ilha_terrenos', j.ilha_terrenos,   -- fase 106: os da ilha
      'preco_chico', fazenda_preco_chico(v_nivel),   -- fase 107: o Peixe do Velho Chico vale mais a cada nível
      'beleza', fazenda_beleza(p_jogador),
      'bonus_venda', fazenda_bonus_venda(p_jogador),
      -- fase 106: a ilha (pode zarpar? quantas obras; do 45 em diante, a lista; o baú de hoje já foi aberto?)
      'ilha', jsonb_build_object('obras', coalesce(j.ilha_obras, 0), 'pode_ir', fazenda_ilha_pode(p_jogador, v_nivel),
                                 'bau_hoje', j.ilha_bau_dia = fazenda_hoje(), 'x', fazenda_ilha_x(p_jogador),
                                 -- fase 118: a caça ao tesouro (quantas pistas já achou hoje e onde está a próxima)
                                 'caca', fazenda_ilha_caca(p_jogador),
                                 -- fase 118: a caverna (abre com a 15ª obra): já explorou hoje? e a coleção dos tesouros
                                 'caverna', case when coalesce(j.ilha_obras, 0) >= 15 then jsonb_build_object(
                                     'hoje', coalesce(j.caverna_dia = fazenda_hoje(), false),
                                     'colecao', coalesce((select jsonb_object_agg(cv.item, cv.vezes) from fazenda_caverna cv where cv.jogador_id = p_jogador), '{}'::jsonb)) end,
                                 'partes', case when v_nivel >= 45 then fazenda_ilha_obras() end),
      -- fase 111: o cachorro da ilha (null: ainda não escolheu)
      'cachorro', case when j.cachorro_raca is not null then jsonb_build_object('raca', j.cachorro_raca, 'nome', j.cachorro_nome) end
    ),
    'zonas_venda', case when not v_omite then fazenda_zonas() end,
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
    'culturas', case when not v_omite then fazenda_cache_ler('culturas') end,   -- fase 71: os catálogos vêm prontos (fazenda_cache)
    'animais', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'tipo', tipo, 'alimentado_em', alimentado_em,
               'radioativo_ate', case when radioativo_ate > now() then radioativo_ate end) order by id)   -- fase 68
        from fazenda_animais where jogador_id = p_jogador), '[]'::jsonb),
    'animais_tipos', case when not v_omite then fazenda_cache_ler('animais_tipos') end,
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
      'raros_semana', fazenda_raros_semana(p_jogador),   -- fase 84
      -- fase 91: quantas vezes cada ajudante foi demitido (contratar e evoluir ficam 50% mais caros a cada uma)
      'demitidos', coalesce((select jsonb_object_agg(d.tipo, d.vezes) from fazenda_ajudantes_demitidos d where d.jogador_id = p_jogador), '{}'::jsonb),
      -- fase 85: o XP de ajuda de hoje e o teto (passou dele, cada ajuda vale 1/4)
      'ajuda_hoje', jsonb_build_object('xp', case when j.ajuda_dia = fazenda_hoje() then coalesce(j.ajuda_xp_dia, 0) else 0 end,
                                       'teto', fazenda_ajuda_teto(p_jogador)),
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
    'itens', case when not v_omite then fazenda_cache_itens(v_nivel) end,   -- fase 57: o limite que vale para o nível de agora (fase 71: pronto, um por nível)
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
                    and c.apagado_em is null and p.banido_em is null and (not p.teste or p.id = p_jogador)),   -- (fase 119)
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
    'melhorias_tipos', case when not v_omite then fazenda_cache_ler('melhorias_tipos') end,
    'estatisticas', (select to_jsonb(e) - 'jogador_id' || jsonb_build_object('energia', e.energia + floor(j.energia_gasta)::int)
                       from fazenda_estatisticas e where e.jogador_id = p_jogador),
    'conquistas', coalesce((
      select jsonb_agg(jsonb_build_object('id', conquista, 'em', obtida_em) order by obtida_em)
        from fazenda_conquistas where jogador_id = p_jogador), '[]'::jsonb),
    'conquistas_tipos', case when not v_omite then fazenda_cache_ler('conquistas_tipos') end,
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
    'ajudantes_tipos', case when not v_omite then fazenda_cache_ler('ajudantes_tipos') end
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
  -- fase 89: sem os catálogos que o jogo já tem; mandou tudo para a sessão leve: guarda a versão que ela tem agora
  if v_omite then
    v_json := v_json - array['zonas_venda', 'culturas', 'animais_tipos', 'itens', 'melhorias_tipos', 'conquistas_tipos', 'ajudantes_tipos'];
    v_ver := current_setting('fazenda.cat_ver', true);
  else
    v_ver := fazenda_catalogos_ver(v_nivel);
    if v_leve then
      update fazenda_sessoes set cat_ver = v_ver where token_hash = current_setting('fazenda.sessao', true) and cat_ver is distinct from v_ver;
      perform set_config('fazenda.cat_ver', v_ver, true);
    end if;
  end if;
  perform fazenda_recados_anuais_entregar(p_jogador);   -- fase 115: o recado do dia (todo ano)
  return v_json || jsonb_build_object('cat_ver', v_ver,
    -- fase 115: hoje é o Dia dos Namorados da Fazendinha (11/11)? e quantas Viih ainda dá para plantar
    'dia_especial', case when to_char(fazenda_hoje(), 'MM-DD') = '11-11' then 'namorados' end,
    -- fase 117: quantos pedidos do Capitão ainda faltam hoje (3 se ele ainda não pediu; null fora da ilha)
    'capitao_faltam', case when fazenda_ilha_pode(p_jogador, v_nivel) then
        coalesce((select count(*) filter (where c.feito_em is null) from fazenda_capitao c where c.jogador_id = p_jogador and c.dia = fazenda_hoje()
                   having count(*) > 0), 3) end,
    'viih_restam', greatest(0, 11 - coalesce((select v.plantadas from fazenda_viih_plantio v where v.jogador_id = p_jogador
                                                and v.ano = extract(year from fazenda_hoje())::int), 0)),
    -- fase 114: os recados particulares ainda não lidos (só os seus: o estado é sempre o do próprio jogador)
    'recados', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'titulo', r.titulo, 'texto', r.texto, 'de', r.de,
                                                             'diamantes', r.diamantes, 'em', r.criado_em) order by r.id)
                           from fazenda_recados r where r.jogador_id = p_jogador and r.visto_em is null), '[]'::jsonb));
end;
$$;


-- conferência: tem que aparecer "fase 119 ok"
select case when exists (select 1 from pg_proc where proname = 'fazenda_teste_criar')
             and (select prosrc from pg_proc where proname = 'fazenda_ranking') like '%not teste%'
             and (select prosrc from pg_proc where proname = 'fazenda_semana_placar') like '%not j.teste%'
            then 'fase 119 ok' else 'não aplicou' end as resultado;
