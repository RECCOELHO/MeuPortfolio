-- ============================================================
-- FAZENDINHA — Fase 81 (alarme a 5 ⚡/h e as luzes gastando de noite),
-- só o que mudou.
-- Para o banco que já está no ar (com a fase 80): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 80 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (exists (select 1 from public.fazenda_culturas where id = 'queijo' and venda >= 450)) then
    raise exception 'Rode o fase80.sql antes deste (a fase 80 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 81: o alarme gasta 5 ⚡ por hora (era 1) e, de noite, cada luz gasta 1 ⚡ por hora: a casa da
-- fazenda, as casinhas (vermelha e azul) e os lampiões (fazenda_luzes_noite em fazenda_energia_taxa,
-- e "luzes" na conta da energia). Só para quem tem energia elétrica: sem máquina de energia a conta
-- nem roda (fazenda_energia_atualizar). Bateria zerada, as luzes apagam no jogo.
-- ------------------------------------------------------------
update public.fazenda_itens set descricao = 'Vizinhos não pegam nada dos canteiros em volta (3 quadrados). Com energia elétrica na fazenda, gasta 5 ⚡ por hora e desliga se a bateria zerar.' where id = 'alarme';
update public.fazenda_itens set descricao = 'Acende sozinho de noite e ilumina em volta. +3 de beleza (beleza dá bônus nas vendas). Com energia elétrica na fazenda, gasta 1 ⚡ por hora de noite e apaga se a bateria zerar.' where id = 'lampiao';
update public.fazenda_itens set descricao = 'Casinha: +20 de beleza (beleza dá bônus nas vendas) e 1 cama para um ajudante descansar (2 h numa cama; sem cama livre, 4 h na sombra). Com energia elétrica na fazenda, a luz gasta 1 ⚡ por hora de noite.' where id = 'casa_vermelha';
update public.fazenda_itens set descricao = 'Casinha: +30 de beleza (beleza dá bônus nas vendas) e 2 camas para os ajudantes descansarem (2 h numa cama; sem cama livre, 4 h na sombra). Com energia elétrica na fazenda, a luz gasta 1 ⚡ por hora de noite.' where id = 'casa_azul';

-- as funções que já existiam e mudaram

-- fase 81: quantas luzes ficam acesas de noite (a casa da fazenda + casinhas + lampiões); de dia, 0
create or replace function public.fazenda_luzes_noite(p_jogador uuid, p_t timestamptz)
returns int language sql stable security definer set search_path = public as $$
  select case when fazenda_dia_em(p_t) then 0
              else 1 + (select count(*) from fazenda_construcoes c
                         where c.jogador_id = p_jogador and c.tipo in ('casa_vermelha', 'casa_azul', 'lampiao'))::int end;
$$;

create or replace function public.fazenda_energia_taxa(p_jogador uuid, p_t timestamptz)
returns real language sql stable security definer set search_path = public as $$
  select coalesce(sum(case i.efeito when 'solar' then g.solar when 'eolica' then g.eolica when 'reator' then g.reator when 'hidro' then fazenda_hidro_em(p_t) else 0 end), 0)::real
         -- fase 47: cada alarme gasta ⚡ por hora (a conta só roda para quem tem energia elétrica); fase 81: 5 (era 1)
         - 5 * (select count(*) from fazenda_construcoes a where a.jogador_id = p_jogador and a.tipo = 'alarme')::real
         -- fase 81: de noite, cada luz gasta 1 ⚡ por hora: a casa da fazenda, as casinhas e os lampiões
         - fazenda_luzes_noite(p_jogador, p_t)::real
    from fazenda_construcoes c
    join fazenda_itens i on i.id = c.tipo
    cross join fazenda_gera_em(p_t) g
   where c.jogador_id = p_jogador and i.efeito in ('solar', 'eolica', 'reator', 'hidro')
     and c.sobrecarga_em is null;   -- fase 77: em sobrecarga, parado até o conserto
$$;

-- a conta da energia de uma fazenda: gera (média por hora) e gasta (no máximo por hora, tudo
-- trabalhando), por tipo. Guardada por jogador enquanto as construções e o eletricista não mudam.
create or replace function public.fazenda_energia_conta(p_jogador uuid)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_ass  text;
  v      jsonb;
  m      jsonb;
  v_tri  boolean;
  v_fab  boolean;
  v_desc real;
  v_rede jsonb;
  v_gera jsonb;
  v_gasta jsonb;
  v_g    real;
  v_c    real;
begin
  select md5(coalesce(string_agg(c.tipo || c.x || ',' || c.y, ';' order by c.x, c.y), '') || ':' ||
             coalesce((select h.nivel from fazenda_ajudantes h join fazenda_ajudantes_tipos t on t.id = h.tipo
                        where h.jogador_id = p_jogador and t.funcao = 'energia' limit 1), 0))
    into v_ass from fazenda_construcoes c where c.jogador_id = p_jogador;
  select valor into v from fazenda_cache where chave = 'energia:' || p_jogador;
  if v is not null and v->>'ass' = v_ass then return v - 'ass'; end if;

  m := fazenda_energia_medias();
  v_tri := fazenda_tem_efeito(p_jogador, 'triturar');
  v_fab := fazenda_tem_efeito(p_jogador, 'automatico');
  v_desc := fazenda_energia_preco(p_jogador, 1);   -- quanto 1 ⚡ custa de verdade (0,8 e o eletricista)
  v_rede := coalesce((select jsonb_agg(to_jsonb(r)) from fazenda_rede(p_jogador) r), '[]'::jsonb);

  -- gera: cada gerador pela média dele
  select coalesce(jsonb_agg(jsonb_build_object('tipo', x.tipo, 'n', x.n, 'h', round(x.h::numeric))), '[]'::jsonb), coalesce(sum(x.h), 0)
    into v_gera, v_g
    from (select c.tipo, count(*) as n, count(*) * (m->>i.efeito)::real as h
            from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo
           where c.jogador_id = p_jogador and i.efeito in ('solar', 'eolica', 'reator', 'biomassa', 'hidro')
           group by c.tipo, i.efeito) x;

  -- gasta: cada coisa trabalhando sem parar
  with cons as (
    select c.x, c.y, c.tipo, i.efeito, i.raio, i.produz_seg, i.entradas
      from fazenda_construcoes c join fazenda_itens i on i.id = c.tipo where c.jogador_id = p_jogador),
  cant as (   -- colheitas por hora de cada canteiro (o que está plantado; vazio conta como 2 h)
    select c.x, c.y, 3600.0 / coalesce(k.tempo_seg, 7200) as por_h
      from fazenda_canteiros c left join fazenda_culturas k on k.id = c.cultura where c.jogador_id = p_jogador),
  itens as (
    -- oficinas: na rede, 2 do puxar e 2 da entrega (e 15 do triturador); fora dela, com a fábrica automática, 8
    select 'oficinas' as tipo,
           sum(3600.0 / o.produz_seg *
               case when exists (select 1 from jsonb_array_elements(v_rede) r where r->>'papel' = 'oficina' and (r->>'x')::int = o.x and (r->>'y')::int = o.y)
                    then 4 when v_fab then 8 else 0 end) as h
      from cons o where o.entradas is not null
    union all
    select 'triturador', case when v_tri then sum(3600.0 / o.produz_seg) * 15 end
      from cons o where o.entradas is not null
       and (exists (select 1 from jsonb_array_elements(v_rede) r where r->>'papel' = 'oficina' and (r->>'x')::int = o.x and (r->>'y')::int = o.y) or v_fab)
    union all
    select 'robo_colheita', sum(ct.por_h) * 6   -- 4 da colheita e 2 do replantio
      from cons r join cant ct on abs(ct.x - r.x) <= r.raio and abs(ct.y - r.y) <= r.raio where r.efeito = 'robo'
    union all
    select 'bau', sum(ct.por_h) * 2   -- o baú recolhe o que está encostado nele
      from cons b join cant ct on abs(ct.x - b.x) <= 1 and abs(ct.y - b.y) <= 1 where b.tipo = 'bau'
    union all
    select 'aspersor', sum(ct.por_h) * 2   -- uma seca por plantio, mais ou menos
      from cons a join cant ct on abs(ct.x - a.x) <= a.raio and abs(ct.y - a.y) <= a.raio where a.efeito = 'aspersor'
    union all
    select 'estufa', sum(ct.por_h) * 5   -- 5 por plantio no alcance dela
      from cons e join cant ct on abs(ct.x - e.x) <= e.raio and abs(ct.y - e.y) <= e.raio where e.efeito = 'estufa'
    union all
    select 'alarme', 5 * count(*)::real from cons where tipo = 'alarme'   -- fase 81: 5 ⚡/h cada (era 1)
    union all
    select 'luzes', 1 + count(*)::real from cons where tipo in ('casa_vermelha', 'casa_azul', 'lampiao')   -- fase 81: de noite
  )
  select coalesce(jsonb_agg(jsonb_build_object('tipo', tipo, 'h', round((h * case when tipo in ('alarme', 'luzes') then 1 else v_desc end)::numeric)) order by h desc)
                    filter (where coalesce(h, 0) > 0), '[]'::jsonb),
         coalesce(sum(h * case when tipo in ('alarme', 'luzes') then 1 else v_desc end), 0)
    into v_gasta, v_c
    from itens;

  v := jsonb_build_object('gera', round(v_g), 'gasta', round(v_c), 'saldo', round(v_g - v_c),
                          'gera_itens', v_gera, 'gasta_itens', v_gasta, 'desconto', round((1 - v_desc)::numeric * 100));
  perform fazenda_cache_gravar('energia:' || p_jogador, v || jsonb_build_object('ass', v_ass));
  return v;
end;
$$;

-- permissões
revoke execute on function
  public.fazenda_luzes_noite(uuid, timestamptz)
from public, anon, authenticated;

grant execute on function
  public.fazenda_carregar(text)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache) com o que esta fase mudou
select public.fazenda_cache_montar();

-- conferência: deve aparecer "Fase 81: alarme 5 ⚡/h, luzes de noite 1 ⚡/h cada"
select 'Fase 81: alarme ' || substring((select descricao from public.fazenda_itens where id = 'alarme') from 'gasta (\d+)') || ' ⚡/h, luzes de noite 1 ⚡/h cada' as ok
 where exists (select 1 from pg_proc where proname = 'fazenda_luzes_noite');
