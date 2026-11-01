-- ============================================================
-- FAZENDINHA — Fase 99 (Invasão de Varginha: a ameaça — os ETs ficam mais fortes conforme os SEUS pontos),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 98): Supabase > SQL Editor > colar este arquivo > Run.
-- Pode rodar com o evento acontecendo: ninguém perde ponto. Rode ANTES do merge do PR.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 98 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from information_schema.columns where table_name = 'fazenda_invasao' and column_name = 'ouro_n')) then
    raise exception 'Rode o fase98.sql antes deste (a fase 98 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 99: a ameaça. Quem está pontuando muito derrubava os ETs com um toque e ficava sem graça.
-- Agora, a cada 1.000 pontos seus, os ETs (e o chefão) aguentam +50% da vida para você: com 1.000
-- pontos ×1,5, com 2.000 ×2, com 10.000 ×6 (até ×60). Cada um tem a sua ameaça (quem está começando
-- continua com os ETs fracos). O bônus de derrubar sobe junto. Os números ficam em
-- fazenda_invasao_regras (ameaca_pontos, ameaca_passo, ameaca_max): para ajustar, é só trocar ali.
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------

-- fase 99: quanto a vida dos ETs é multiplicada para quem tem p_pontos (igual a multDe() em fazenda-invasao.js)
create or replace function public.fazenda_invasao_mult(p_r jsonb, p_pontos bigint)
returns numeric language sql immutable as $$
  select least(coalesce((p_r->>'ameaca_max')::numeric, 1),
               1 + coalesce((p_r->>'ameaca_passo')::numeric, 0) * floor(greatest(0, coalesce(p_pontos, 0)) / greatest(1, coalesce((p_r->>'ameaca_pontos')::numeric, 1))));
$$;

-- as regras: + os números da ameaça
create or replace function public.fazenda_invasao_regras(p_teste boolean default false)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'id', case when p_teste then 'varginha-teste' else 'varginha-2026' end, 'nome', 'Invasão de Varginha',
    'teste', p_teste,
    'inicio', case when p_teste then '2026-10-31 00:00:00-03' else '2026-11-01 15:00:00-03' end::timestamptz,
    'fim', case when p_teste then '2026-11-01 14:00:00-03' else '2026-11-02 00:00:00-03' end::timestamptz,
    'nivel_min', case when p_teste then 1 else 10 end,
    'toques_seg', 6, 'toques_max', 30,                 -- o saldo de toques: enche 6 por segundo, guarda até 30
    'intervalo', 1.2, 'vida', 9,                       -- um ET novo a cada 1,2 s; cada um fica 9 s na tela
    'hp_base', 4, 'hp_por_hora', 2,                    -- a cada hora os ETs aguentam mais
    -- fase 98: o chefão desce a cada 20 min (era 1 h); hp_chefe_por_hora agora soma a cada chefão (50 por chefão = 150 por hora, como antes)
    'chefe_a_cada', 1200, 'chefe_atraso', 30, 'vida_chefe', 120, 'hp_chefe', 400, 'hp_chefe_por_hora', 50,
    'bonus_abate', 2, 'bonus_chefe', 200,              -- pontos a mais por derrubar
    'auto_ativo_seg', 120, 'lote_max_seg', 5,
    -- fase 98: o ET dourado ("ainda tá aí?"): aparece só para você, num lugar sorteado, a cada 3 a 6 min
    -- (no teste dos admins: 45 s a 90 s). Tocou nele: +bonus_ouro. Não tocou no prazo: os seus toques e
    -- as armas automáticas param de valer até você tocar nele.
    'ouro_primeiro', case when p_teste then 20 else 90 end, 'ouro_min', case when p_teste then 45 else 180 end,
    'ouro_max', case when p_teste then 90 else 360 end, 'ouro_prazo', 15, 'bonus_ouro', 50,
    -- fase 99: a ameaça. A cada ameaca_pontos pontos SEUS, os ETs e o chefão aguentam +ameaca_passo da vida
    -- (1.000 pontos: ×1,5; 2.000: ×2; 10.000: ×6...), até ameaca_max. O bônus de derrubar sobe junto.
    'ameaca_pontos', 1000, 'ameaca_passo', 0.5, 'ameaca_max', 60,
    'premio', jsonb_build_object('diamantes', 40, 'moedas', 4000000, 'fator', 0.75, 'min_diamantes', 1, 'min_moedas', 1000),
    'armas', '[
      {"id": "forcado",    "nome": "Forcado elétrico",   "tipo": "toque", "efeito": 1,  "preco": 5000,   "fator": 1.6},
      {"id": "espantalho", "nome": "Espantalho-robô",    "tipo": "auto",  "efeito": 1,  "preco": 20000,  "fator": 1.7},
      {"id": "trator",     "nome": "Trator-canhão",      "tipo": "auto",  "efeito": 4,  "preco": 80000,  "fator": 1.8},
      {"id": "drone",      "nome": "Drone pulverizador", "tipo": "auto",  "efeito": 12, "preco": 250000, "fator": 2.0}
    ]'::jsonb,
    'arma_nivel_max', 25);
$$;


-- o que o jogo mostra de você: + a ameaça (mult)
create or replace function public.fazenda_invasao_eu(p_r jsonb, p_jogador uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  m record;
  v_pos int;
  v_pod record;
begin
  select * into m from fazenda_invasao where evento = p_r->>'id' and jogador_id = p_jogador;
  if not found then
    return jsonb_build_object('pontos', 0, 'abates', 0, 'chefes', 0, 'armas', '{}'::jsonb, 'posicao', null,
      'precos', (select jsonb_object_agg(a->>'id', fazenda_invasao_preco(p_r, a->>'id', 0)) from jsonb_array_elements(p_r->'armas') a),
      'por_toque', 1, 'por_seg', 0, 'golpes', '{}'::jsonb, 'mult', 1);
  end if;
  select count(*) + 1 into v_pos from fazenda_invasao where evento = m.evento and pontos > m.pontos;
  select * into v_pod from fazenda_invasao_poder(p_r, m.armas);
  return jsonb_build_object('pontos', m.pontos, 'abates', m.abates, 'chefes', m.chefes, 'armas', m.armas, 'gastou', m.gastou,
    'posicao', case when m.pontos > 0 then v_pos end,
    'precos', (select jsonb_object_agg(a->>'id', fazenda_invasao_preco(p_r, a->>'id', coalesce((m.armas->>(a->>'id'))::int, 0)))
                 from jsonb_array_elements(p_r->'armas') a),
    'por_toque', v_pod.por_toque, 'por_seg', v_pod.por_seg, 'golpes', m.golpes,
    'auto_ligado', m.ult_toque is not null and m.ult_toque > now() - make_interval(secs => (p_r->>'auto_ativo_seg')::int),
    'ouro', case when m.ouro_n is not null then jsonb_build_object('n', m.ouro_n, 'x', m.ouro_x, 'y', m.ouro_y, 'ate', m.ouro_ate) end,
    'pausado', m.pausado, 'ouros', m.ouros, 'mult', fazenda_invasao_mult(p_r, m.pontos));
end;
$$;


-- o lote: a vida de cada ET multiplicada pela sua ameaça
create or replace function public.fazenda_invasao_lote(p_token text, p_toques jsonb, p_teste boolean default false, p_ouro int default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id    uuid := fazenda_auth_ler(p_token);
  v_r     jsonb := fazenda_invasao_regras(p_teste);
  v_ev    text := v_r->>'id';
  m       record;
  v_pod   record;
  a       record;
  e       record;
  v_dt    double precision;
  v_saldo double precision;
  v_golpes jsonb := '{}'::jsonb;
  v_k     int;
  v_n     int;
  v_feito int;
  v_dano  int;
  v_usou  int;
  v_qtd   int := 0;
  v_alvo  int;
  v_pts   bigint := 0;
  v_abat  int := 0;
  v_chef  int := 0;
  v_auto  double precision := 0;
  v_cont  int := 0;
  c       record;
  v_pausa boolean;
  v_ouro_ok boolean := false;
  v_on    int;
  v_ox    real;
  v_oy    real;
  v_oate  timestamptz;
  v_oprox timestamptz;
  v_mult  numeric;
  v_hp    int;
begin
  if p_teste and not exists (select 1 from fazenda_jogadores where id = v_id and admin is not null) then raise exception 'sem_permissao'; end if;
  if now() < (v_r->>'inicio')::timestamptz then raise exception 'invasao_antes'; end if;
  if now() >= (v_r->>'fim')::timestamptz then raise exception 'invasao_acabou'; end if;
  if (select fazenda_nivel_de(xp, nivel_trava) from fazenda_jogadores where id = v_id) < (v_r->>'nivel_min')::int then
    raise exception 'invasao_nivel';
  end if;
  insert into fazenda_invasao (evento, jogador_id, saldo, ult_lote) values (v_ev, v_id, 5, now()) on conflict do nothing;
  select * into m from fazenda_invasao where evento = v_ev and jogador_id = v_id for update;
  v_dt := least((v_r->>'lote_max_seg')::double precision, greatest(0, extract(epoch from now() - coalesce(m.ult_lote, now()))));
  v_saldo := least((v_r->>'toques_max')::double precision, m.saldo + (v_r->>'toques_seg')::double precision * v_dt);
  select * into v_pod from fazenda_invasao_poder(v_r, m.armas);
  v_mult := fazenda_invasao_mult(v_r, m.pontos);   -- fase 99: a ameaça (pelos seus pontos)

  -- o dano já feito só vale para os ETs que ainda estão na tela
  for e in select key, value from jsonb_each_text(m.golpes) loop
    select * into a from fazenda_invasao_alien(e.key::int, v_r);
    if found and a.morre + interval '3 seconds' > now() then v_golpes := v_golpes || jsonb_build_object(e.key, e.value::int); end if;
  end loop;

  -- fase 98: o ET dourado. Tocou no da vez (o número bate): ganha o bônus e volta a valer tudo.
  -- Passou do prazo sem tocar: fica pausado (os toques e as automáticas não contam) até tocar.
  v_pausa := m.pausado;
  v_on := m.ouro_n; v_ox := m.ouro_x; v_oy := m.ouro_y; v_oate := m.ouro_ate;
  v_oprox := coalesce(m.ouro_prox, now() + make_interval(secs => (v_r->>'ouro_primeiro')::int * (0.7 + random() * 0.6)));
  if p_ouro is not null and m.ouro_n is not null and p_ouro = m.ouro_n then
    v_ouro_ok := true; v_pausa := false;
    v_pts := v_pts + (v_r->>'bonus_ouro')::int;
    v_on := null; v_ox := null; v_oy := null; v_oate := null;
    v_oprox := now() + make_interval(secs => (v_r->>'ouro_min')::int + random() * ((v_r->>'ouro_max')::int - (v_r->>'ouro_min')::int));
  elsif m.ouro_n is not null and now() > m.ouro_ate and p_ouro is not null then
    v_pausa := true;
  end if;

  -- os toques: no máximo 40 ETs por lote; cada um só se estiver na tela agora; nunca além do saldo
  if not v_pausa and p_toques is not null and jsonb_typeof(p_toques) = 'object' then
    for e in select key, value from jsonb_each_text(p_toques) loop
      v_cont := v_cont + 1;
      exit when v_cont > 40 or v_saldo < 1;
      begin
        v_k := e.key::int; v_n := greatest(0, least(e.value::int, floor(v_saldo)::int));
      exception when others then continue;
      end;
      continue when v_n <= 0;
      select * into a from fazenda_invasao_alien(v_k, v_r);
      continue when not found or now() < a.nasce - interval '1 second' or now() > a.morre + interval '3 seconds';
      v_hp := ceil(a.hp * v_mult)::int;
      v_feito := coalesce((v_golpes->>v_k::text)::int, 0);
      continue when v_feito >= v_hp;
      v_dano := least(v_n * v_pod.por_toque, v_hp - v_feito);
      v_usou := ceil(v_dano::numeric / v_pod.por_toque)::int;
      v_saldo := v_saldo - v_usou;
      v_qtd := v_qtd + v_usou;
      v_alvo := v_k;
      v_pts := v_pts + v_dano;
      v_golpes := v_golpes || jsonb_build_object(v_k::text, v_feito + v_dano);
      if v_feito + v_dano >= v_hp then
        if a.chefe then v_chef := v_chef + 1; v_pts := v_pts + round((v_r->>'bonus_chefe')::int * v_mult)::int;
        else v_abat := v_abat + 1; v_pts := v_pts + round((v_r->>'bonus_abate')::int * v_mult)::int; end if;
      end if;
    end loop;
  end if;

  -- as automáticas: só para quem tocou num ET nos últimos 2 minutos
  if not v_pausa and (v_qtd > 0 or (m.ult_toque is not null and m.ult_toque > now() - make_interval(secs => (v_r->>'auto_ativo_seg')::int))) then
    v_auto := v_pod.por_seg * v_dt + m.auto_resto;
  end if;
  v_pts := v_pts + floor(v_auto)::bigint;

  -- fase 98: hora de um ET dourado novo (só para quem está jogando: tocou agora ou nos últimos 2 min)
  -- (p_ouro null: o jogo aberto é de antes da fase 98 e não desenha o ET dourado; esse não ganha um)
  if v_on is null and not v_ouro_ok and now() >= v_oprox and p_ouro is not null
     and (v_qtd > 0 or (m.ult_toque is not null and m.ult_toque > now() - make_interval(secs => (v_r->>'auto_ativo_seg')::int))) then
    v_on := 1 + floor(random() * 2000000000)::int;
    v_ox := (0.12 + random() * 0.76)::real; v_oy := (0.28 + random() * 0.34)::real;
    v_oate := now() + make_interval(secs => (v_r->>'ouro_prazo')::int);
  end if;

  update fazenda_invasao set
    pontos = pontos + v_pts, abates = abates + v_abat, chefes = chefes + v_chef, toques = toques + v_qtd,
    saldo = v_saldo, golpes = v_golpes, auto_resto = v_auto - floor(v_auto),
    ult_lote = now(), ult_toque = case when v_qtd > 0 then now() else ult_toque end,
    ult_qtd = v_qtd, ult_alvo = coalesce(v_alvo, ult_alvo), visto_em = now(),
    subiu_em = case when v_pts > 0 then now() else subiu_em end,
    ouro_n = v_on, ouro_x = v_ox, ouro_y = v_oy, ouro_ate = v_oate, ouro_prox = v_oprox, pausado = v_pausa,
    ouros = ouros + case when v_ouro_ok then 1 else 0 end
   where evento = v_ev and jogador_id = v_id;

  -- a conquista do chefão (paga só quem gravou agora; no teste, não)
  if v_chef > 0 and not p_teste then
    select * into c from fazenda_conquistas_tipos where id = 'invasao_chefe';
    insert into fazenda_conquistas (jogador_id, conquista) values (v_id, 'invasao_chefe') on conflict do nothing;
    if found then
      update fazenda_jogadores set moedas = least(2147483647, moedas::bigint + c.recompensa)::int, diamantes = diamantes + c.diamantes
       where id = v_id;
    end if;
  end if;

  return jsonb_build_object('agora', now(), 'ganhou', v_pts, 'valeram', v_qtd, 'ouro_ok', v_ouro_ok, 'eu', fazenda_invasao_eu(v_r, v_id),
                            'sala', fazenda_invasao_sala(v_r));
end;
$$;


-- permissões
revoke execute on function
  public.fazenda_invasao_mult(jsonb, bigint),
  public.fazenda_invasao_regras(boolean),
  public.fazenda_invasao_eu(jsonb, uuid)
from public, anon, authenticated;

grant execute on function
  public.fazenda_invasao_lote(text, jsonb, boolean, int)
to anon, authenticated;

-- conferência: a ameaça com 0, 2.000, 10.000 e 50.000 pontos
select public.fazenda_invasao_mult(public.fazenda_invasao_regras(), 0) as com_0,
       public.fazenda_invasao_mult(public.fazenda_invasao_regras(), 2000) as com_2mil,
       public.fazenda_invasao_mult(public.fazenda_invasao_regras(), 10000) as com_10mil,
       public.fazenda_invasao_mult(public.fazenda_invasao_regras(), 50000) as com_50mil;
