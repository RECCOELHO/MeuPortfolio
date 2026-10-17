-- ============================================================
-- FAZENDINHA — Fase 67 (o chat global com pedidos e o anúncio reservado na barraca),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 66): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- ------------------------------------------------------------
-- Fase 67: o chat global, com pedidos que viram anúncio reservado na barraca.
-- • fazenda_chat guarda só a última hora: as mensagens somem em 60 min e cada envio apaga as velhas, então
--   a tabela nunca passa de 1 hora de conversa. Escreve do nível 5 em diante (ler, todo mundo lê); uma
--   mensagem a cada 8 s, 30 por hora (6 pedidos). Texto até 120 letras, sem palavrão (fazenda_chat_palavras,
--   comparando o texto normalizado: sem acento, 0→o, 4→a..., letras repetidas juntas) e sem link.
-- • Pedido: item, quantidade e preço de cada (dentro da faixa da feira). "Vender pra ele"
--   (fazenda_chat_vender) põe o item na barraca de quem vende, pelo preço do pedido, reservado para quem
--   pediu por 2 h (só ele vê e compra); depois vira anúncio normal, com as 48 h de sempre.
-- • Cada um apaga as suas mensagens; o admin apaga qualquer uma (fica em fazenda_admin_log).
-- ------------------------------------------------------------
create or replace function public.fazenda_chat_regras()
returns jsonb language sql immutable as $$
  select '{"minutos": 60, "nivel": 5, "letras": 120, "intervalo": 8, "por_hora": 30, "pedidos_hora": 6,
           "reserva_horas": 2, "mostrar": 80}'::jsonb;
$$;

create table if not exists public.fazenda_chat (
  id          bigint generated always as identity primary key,
  jogador_id  uuid not null references public.fazenda_jogadores(id) on delete cascade,
  texto       text not null default '' check (char_length(texto) <= 120),
  item        text references public.fazenda_culturas(id),   -- pedido: o item, quantos e quanto paga cada
  qtd         int check (qtd > 0),
  preco       int check (preco > 0),
  criado_em   timestamptz not null default now(),
  apagado_por uuid references public.fazenda_jogadores(id) on delete set null,
  apagado_em  timestamptz
);
create index if not exists fazenda_chat_criado on public.fazenda_chat (criado_em);
create index if not exists fazenda_chat_jogador on public.fazenda_chat (jogador_id, criado_em);
alter table public.fazenda_chat enable row level security;
revoke all on public.fazenda_chat from anon, authenticated;

-- o anúncio reservado para quem pediu no chat (pedido_id sem chave: a mensagem some em 1 h)
alter table public.fazenda_feira add column if not exists reservado_para uuid references public.fazenda_jogadores(id) on delete set null;
alter table public.fazenda_feira add column if not exists reservado_ate timestamptz;
alter table public.fazenda_feira add column if not exists pedido_id bigint;
alter table public.fazenda_feira add column if not exists reserva_vista boolean not null default false;
create index if not exists fazenda_feira_pedido on public.fazenda_feira (pedido_id) where pedido_id is not null;
create index if not exists fazenda_feira_reservado on public.fazenda_feira (reservado_para) where reservado_para is not null;

-- o texto como o filtro enxerga: minúsculo, sem acento, 0→o 1→i 3→e 4→a 5→s 7→t @→a $→s e letras
-- repetidas juntas ("pooorrra" → "pora"); a lista passa pela mesma conta
create or replace function public.fazenda_chat_norm(p text)
returns text language sql immutable as $$
  select regexp_replace(translate(lower(coalesce(p, '')), 'áàâãäéèêëíìîïóòôõöúùûüç013457@$', 'aaaaaeeeeiiiiooooouuuucoieastas'),
                        '([a-z])\1+', '\1', 'g');
$$;
create or replace function public.fazenda_chat_palavras()
returns text[] language sql immutable as $$
  select array['porra', 'caralho', 'karalho', 'buceta', 'boceta', 'xoxota', 'xota', 'puta', 'puto', 'putaria', 'merda', 'bosta',
               'cu', 'cuzao', 'foder', 'foda', 'fodase', 'fodido', 'fudido', 'fuder', 'fdp', 'pqp', 'vsf', 'tnc', 'vtnc', 'krl',
               'crl', 'pnc', 'cacete', 'piroca', 'punheta', 'punheteiro', 'siririca', 'boquete', 'viado', 'bicha',
               'arrombado', 'arrombada', 'babaca', 'otario', 'otaria', 'corno', 'corna', 'vagabundo', 'vagabunda', 'vadia',
               'desgracado', 'desgracada', 'retardado', 'retardada', 'estupro', 'estuprador', 'escroto', 'escrota',
               'filho da puta', 'vai se foder', 'pau no cu'];
$$;
-- tem palavrão? palavra inteira (com plural), e também soletrado com espaço ou ponto ("p o r r a")
create or replace function public.fazenda_chat_palavrao(p text)
returns boolean language sql immutable as $$
  with l as (select string_agg(regexp_replace(fazenda_chat_norm(w), '([.*+?()\[\]{}|^$\\])', '\\\1', 'g'), '|') as re
               from unnest(fazenda_chat_palavras()) w),
       t as (select fazenda_chat_norm(p) as n)
  select t.n ~ ('\m(' || l.re || ')s?\M')
      or exists (select 1 from regexp_matches(t.n, '(?:\m[a-z]\M[^a-z]{1,2}){2,}\m[a-z]\M', 'g') m
                  where regexp_replace(regexp_replace(m[1], '[^a-z]', '', 'g'), '([a-z])\1+', '\1', 'g') ~ ('^(' || l.re || ')s?$'))
    from l, t;
$$;
-- limpa o texto (sem caractere de controle, espaços juntos) e barra o que não pode
create or replace function public.fazenda_chat_texto(p_texto text)
returns text
language plpgsql immutable
set search_path = public, extensions
as $$
declare
  v text := btrim(regexp_replace(regexp_replace(coalesce(p_texto, ''), '[[:cntrl:]]', ' ', 'g'), '\s+', ' ', 'g'));
begin
  if char_length(v) > (fazenda_chat_regras()->>'letras')::int then raise exception 'chat_longo'; end if;
  if v ~* '(https?://|www\.|\.(com|net|org|br|gg|io|me|ly|xyz|site|online|app|link)(\M|/)|discord\.|t\.me/|wa\.me/)' then
    raise exception 'chat_link';
  end if;
  if fazenda_chat_palavrao(v) then raise exception 'chat_palavrao'; end if;
  return v;
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
  v_id uuid := fazenda_auth(p_token);
  v_r  jsonb := fazenda_chat_regras();
  v_de timestamptz := now() - make_interval(mins => (v_r->>'minutos')::int);
  j    record;
begin
  select fazenda_nivel(xp) as nivel, admin into j from fazenda_jogadores where id = v_id;
  return jsonb_build_object(
    'regras', v_r,
    'pode_escrever', j.nivel >= (v_r->>'nivel')::int,
    'admin', j.admin is not null,
    'mensagens', coalesce((
      select jsonb_agg(m order by (m->>'id')::bigint) from (
        select jsonb_build_object('id', c.id, 'jogador', c.jogador_id, 'apelido', p.apelido, 'avatar', p.avatar,
                 'nivel', fazenda_nivel(p.xp), 'admin', p.admin, 'texto', c.texto, 'em', c.criado_em,
                 'pedido', case when c.item is not null then jsonb_build_object('item', c.item, 'qtd', c.qtd, 'preco', c.preco) end) as m
          from fazenda_chat c join fazenda_jogadores p on p.id = c.jogador_id
         where c.criado_em >= v_de and c.apagado_em is null and p.banido_em is null
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

create or replace function public.fazenda_chat_enviar(p_token text, p_texto text, p_item text default null,
                                                     p_qtd int default null, p_preco int default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_r     jsonb := fazenda_chat_regras();
  v_texto text;
  v_faixa int[];
  u       record;
  v_n     int;
  v_ped   int;
  v_novo  bigint;
begin
  -- o que passou de 60 min some de vez: a tabela nunca guarda mais de 1 hora de conversa
  delete from fazenda_chat where criado_em < now() - make_interval(mins => (v_r->>'minutos')::int);
  if (select fazenda_nivel(xp) from fazenda_jogadores where id = v_id) < (v_r->>'nivel')::int then raise exception 'chat_nivel'; end if;
  v_texto := fazenda_chat_texto(p_texto);
  if p_item is null and v_texto = '' then raise exception 'chat_vazio'; end if;
  if p_item is not null then
    v_faixa := fazenda_feira_faixa(p_item);
    if v_faixa is null then raise exception 'item_invalido'; end if;
    if p_qtd is null or p_qtd < 1 or p_qtd > (fazenda_feira_regras()->>'qtd_max')::int then raise exception 'quantidade_invalida'; end if;
    if p_preco is null or p_preco < v_faixa[1] or p_preco > v_faixa[2] then raise exception 'preco_invalido'; end if;
  end if;
  perform pg_advisory_xact_lock(hashtext('fazenda_chat:' || v_id::text));   -- dois envios juntos não furam o limite
  select texto, item, criado_em into u from fazenda_chat where jogador_id = v_id order by id desc limit 1;
  if found and u.criado_em > now() - make_interval(secs => (v_r->>'intervalo')::int) then raise exception 'chat_rapido'; end if;
  if found and p_item is null and u.item is null and lower(u.texto) = lower(v_texto) then raise exception 'chat_repetida'; end if;
  select count(*), count(item) into v_n, v_ped from fazenda_chat where jogador_id = v_id and criado_em > now() - interval '1 hour';
  if v_n >= (v_r->>'por_hora')::int or (p_item is not null and v_ped >= (v_r->>'pedidos_hora')::int) then
    raise exception 'chat_limite';
  end if;
  insert into fazenda_chat (jogador_id, texto, item, qtd, preco)
  values (v_id, v_texto, p_item, case when p_item is not null then p_qtd end, case when p_item is not null then p_preco end)
  returning id into v_novo;
  return jsonb_build_object('id', v_novo);
end;
$$;

create or replace function public.fazenda_chat_apagar(p_token text, p_id bigint)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
  m    record;
begin
  select * into m from fazenda_chat where id = p_id and apagado_em is null;
  if not found then raise exception 'mensagem_sumiu'; end if;
  if m.jogador_id <> v_id then
    perform fazenda_admin_id(p_token);   -- a dos outros, só o admin (sem_permissao)
    insert into fazenda_admin_log (admin_id, alvo_id, acao, motivo)
    values (v_id, m.jogador_id, 'apagar_chat', left(coalesce(nullif(m.texto, ''), '(pedido de ' || m.item || ')'), 200));
  end if;
  update fazenda_chat set apagado_em = now(), apagado_por = v_id where id = p_id;
  return jsonb_build_object('ok', true);
end;
$$;

-- Cria o anúncio na barraca (o anunciar da feira e o "vender pra ele" do chat passam por aqui). Com
-- p_para, fica reservado para essa pessoa por 2 h.
create or replace function public.fazenda_feira_criar(p_vendedor uuid, p_item text, p_qtd int, p_preco int,
                                                     p_para uuid default null, p_pedido bigint default null)
returns bigint
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_r     jsonb := fazenda_feira_regras();
  v_faixa int[] := fazenda_feira_faixa(p_item);
  v_livre int;
  v_novo  bigint;
begin
  perform fazenda_feira_vencidos(p_vendedor);
  if v_faixa is null then raise exception 'item_invalido'; end if;
  if p_qtd is null or p_qtd < 1 or p_qtd > (v_r->>'qtd_max')::int then raise exception 'quantidade_invalida'; end if;
  if p_preco is null or p_preco < v_faixa[1] or p_preco > v_faixa[2] then raise exception 'preco_invalido'; end if;
  if (select count(*) from fazenda_feira where vendedor_id = p_vendedor and vendido_em is null) >= fazenda_feira_limite(p_vendedor) then
    raise exception 'limite_anuncios';   -- (fase 51: compre mais barracas na feira)
  end if;
  -- a ração reservada para os bichos fica no celeiro
  select ce.quantidade - coalesce((select quantidade from fazenda_reservas where jogador_id = p_vendedor and item = p_item), 0) into v_livre
    from fazenda_celeiro ce where ce.jogador_id = p_vendedor and ce.item = p_item for update;
  if coalesce(v_livre, 0) < p_qtd then raise exception 'sem_itens'; end if;
  update fazenda_celeiro set quantidade = quantidade - p_qtd where jogador_id = p_vendedor and item = p_item;
  insert into fazenda_feira (vendedor_id, item, qtd, preco, reservado_para, reservado_ate, pedido_id)
  values (p_vendedor, p_item, p_qtd, p_preco, p_para,
          case when p_para is not null then now() + make_interval(hours => (fazenda_chat_regras()->>'reserva_horas')::int) end, p_pedido)
  returning id into v_novo;
  return v_novo;
end;
$$;

-- "Vender pra ele": o pedido do chat vira anúncio na sua barraca, pelo preço do pedido, reservado para quem
-- pediu. Vários podem atender o mesmo pedido, até somar a quantidade pedida.
create or replace function public.fazenda_chat_vender(p_token text, p_id bigint, p_qtd int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := fazenda_auth(p_token);
  v_r    jsonb := fazenda_chat_regras();
  m      record;
  v_ja   int;
  v_novo bigint;
begin
  select c.* into m from fazenda_chat c join fazenda_jogadores p on p.id = c.jogador_id
   where c.id = p_id and c.item is not null and c.apagado_em is null and p.banido_em is null
     and c.criado_em >= now() - make_interval(mins => (v_r->>'minutos')::int)
     for update of c;
  if not found then raise exception 'pedido_sumiu'; end if;
  if m.jogador_id = v_id then raise exception 'pedido_seu'; end if;
  select coalesce(sum(qtd), 0) into v_ja from fazenda_feira where pedido_id = p_id;
  if v_ja >= m.qtd then raise exception 'pedido_atendido'; end if;
  if p_qtd is null or p_qtd < 1 or p_qtd > m.qtd - v_ja then raise exception 'quantidade_invalida'; end if;
  v_novo := fazenda_feira_criar(v_id, m.item, p_qtd, m.preco, m.jogador_id, p_id);
  return jsonb_build_object('id', v_novo, 'para', (select apelido from fazenda_jogadores where id = m.jogador_id),
                            'ate', (select reservado_ate from fazenda_feira where id = v_novo), 'estado', fazenda_estado(v_id));
end;
$$;

-- as funções que já existiam e mudaram

create or replace function public.fazenda_feira_anunciar(p_token text, p_item text, p_qtd int, p_preco int)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
begin
  perform fazenda_feira_criar(v_id, p_item, p_qtd, p_preco);   -- fase 67: as checagens ficam lá (o chat usa também)
  return jsonb_build_object('estado', fazenda_estado(v_id));
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
  -- fase 67: separado para quem pediu no chat (por 2 h, só essa pessoa compra)
  if a.reservado_para is not null and a.reservado_para <> v_id and a.reservado_ate > now() then raise exception 'anuncio_reservado'; end if;
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

-- as ofertas abertas dos outros (as mais baratas primeiro; com p_item, só daquele item) e as suas.
-- Fase 67: a reservada para outra pessoa não aparece enquanto a reserva vale; a reservada para você vem primeiro.
create or replace function public.fazenda_feira_lista(p_token text, p_item text default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id uuid := fazenda_auth(p_token);
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
           and f.criado_em >= now() - make_interval(hours => (v_r->>'horas')::int)
           and (f.reservado_para is null or f.reservado_para = v_id or f.reservado_ate <= now())
           and (p_item is null or f.item = p_item)
         order by (f.reservado_para = v_id and f.reservado_ate > now()) desc nulls last, f.preco, f.id
         limit 60) x), '[]'::jsonb),
    'itens', coalesce((
      select jsonb_agg(distinct f.item) from fazenda_feira f
       where f.vendido_em is null and f.vendedor_id <> v_id
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
  return v_json;
end;
$$;

-- permissões
revoke execute on function
  public.fazenda_chat_regras(),
  public.fazenda_chat_norm(text),
  public.fazenda_chat_palavras(),
  public.fazenda_chat_palavrao(text),
  public.fazenda_chat_texto(text),
  public.fazenda_feira_criar(uuid, text, int, int, uuid, bigint)
from public, anon, authenticated;

grant execute on function
  public.fazenda_chat(text, bigint),
  public.fazenda_chat_enviar(text, text, text, int, int),
  public.fazenda_chat_apagar(text, bigint),
  public.fazenda_chat_vender(text, bigint, int)
to anon, authenticated;

-- conferência: deve aparecer "Chat: some em 60 min, escreve do nível 5; palavrão barrado: sim"
select 'Chat: some em ' || (public.fazenda_chat_regras()->>'minutos') || ' min, escreve do nível ' || (public.fazenda_chat_regras()->>'nivel')
    || '; palavrão barrado: ' || case when public.fazenda_chat_palavrao('que p0rr4 é essa') then 'sim' else 'NÃO' end as ok;
