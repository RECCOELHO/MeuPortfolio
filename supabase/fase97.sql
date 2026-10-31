-- ============================================================
-- FAZENDINHA — Fase 97 (a praia com vendedores: a barraca de coco e o carrinho de milho vendem para os
-- banhistas), só o que mudou.
-- Para o banco que já está no ar (com a fase 96): Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- antes de tudo: a fase 96 precisa estar no banco (senão para aqui, sem mudar nada)
do $$ begin
  if not (select (fazenda_premios_efeitos() ? 'perola_negra')) then
    raise exception 'Rode o fase96.sql antes deste (a fase 96 não está no banco). Nada foi mudado.';
  end if;
end $$;

-- ------------------------------------------------------------
-- Fase 97: a praia usável. Os banhistas vêm conforme o conforto da areia (guarda-sol 2, cadeira, castelo
-- e coqueiro da praia 1 cada, até 20) e compram nas barracas: a barraca de coco vende o coco do seu
-- celeiro e o carrinho de milho (novo) vende o milho, cada um mais caro que no celeiro (coco a 140, milho
-- cozido a 50). Por hora, cada barraca vende 6 + o conforto; o caixa junta até 8 h. Tocar na barraca
-- recolhe: o que foi vendido sai do celeiro (o guardado para ração fica) e as moedas entram.
-- ------------------------------------------------------------
insert into public.fazenda_itens (id, nome, categoria, custo, nivel_min, ordem, beleza, descricao) values
  ('barraca_milho', 'Carrinho de milho', 'praia', 20000, 31, 135, 4,
   'Vende o milho do seu celeiro cozido para os banhistas, a 50 moedas cada (no celeiro vale 12). Toque para recolher o caixa. Só na areia do Litoral.')
on conflict (id) do update set nome = excluded.nome, categoria = excluded.categoria, custo = excluded.custo,
  nivel_min = excluded.nivel_min, ordem = excluded.ordem, beleza = excluded.beleza, descricao = excluded.descricao;
update public.fazenda_itens set descricao = 'Vende o coco do seu celeiro para os banhistas, a 140 moedas cada (no celeiro vale 70). Toque para recolher o caixa. Só na areia do Litoral.'
 where id = 'barraca_coco';
update public.fazenda_itens set descricao = 'Sombra na areia: traz banhistas (+2 de conforto da praia). Só na areia do Litoral.' where id = 'guarda_sol';
update public.fazenda_itens set descricao = 'Para ver o mar: traz banhistas (+1 de conforto da praia). Só na areia do Litoral.' where id = 'cadeira_praia';
update public.fazenda_itens set descricao = 'Com bandeirinha e tudo: traz banhistas (+1 de conforto da praia). Só na areia do Litoral.' where id = 'castelo_areia';
update public.fazenda_itens set descricao = 'Traz banhistas (+1 de conforto da praia). O coco é do coqueiro do pomar. Só na areia do Litoral.' where id = 'coqueiro_praia';

-- as regras da praia (igual a PRAIA_REGRAS em assets/fazenda/fazenda.js)
create or replace function public.fazenda_praia_regras()
returns jsonb language sql immutable as $$
  select '{"vendedores": {"barraca_coco": {"item": "coco", "preco": 140}, "barraca_milho": {"item": "milho", "preco": 50}},
           "conforto": {"guarda_sol": 2, "cadeira_praia": 1, "castelo_areia": 1, "coqueiro_praia": 1},
           "base": 6, "conforto_max": 20, "horas_max": 8}'::jsonb;
$$;

-- o conforto da praia de um jogador (quantos banhistas vêm)
create or replace function public.fazenda_praia_conforto(p_jogador uuid)
returns int language sql stable security definer set search_path = public as $$
  select least((fazenda_praia_regras()->>'conforto_max')::int,
               coalesce(sum((fazenda_praia_regras()->'conforto'->>c.tipo)::int), 0)::int)
    from fazenda_construcoes c where c.jogador_id = p_jogador and fazenda_praia_regras()->'conforto' ? c.tipo;
$$;

-- recolher o caixa de uma barraca: vende o que deu no tempo (até 8 h), do que tem no celeiro
create or replace function public.fazenda_praia_caixa(p_token text, p_x int, p_y int)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id    uuid := fazenda_auth(p_token);
  v_r     jsonb := fazenda_praia_regras();
  c       record;
  v_vend  jsonb;
  v_horas double precision;
  v_quer  int;
  v_tem   int;
  v_n     int;
  v_ganho int;
begin
  select * into c from fazenda_construcoes where jogador_id = v_id and x = p_x and y = p_y for update;
  if not found then raise exception 'item_invalido'; end if;
  v_vend := v_r->'vendedores'->c.tipo;
  if v_vend is null then raise exception 'item_invalido'; end if;
  v_horas := least((v_r->>'horas_max')::double precision, greatest(0, extract(epoch from now() - coalesce(c.colhido_em, now())) / 3600));
  v_quer := floor(v_horas * ((v_r->>'base')::int + fazenda_praia_conforto(v_id)))::int;
  select greatest(0, ce.quantidade - coalesce(rs.quantidade, 0)) into v_tem
    from fazenda_celeiro ce left join fazenda_reservas rs on rs.jogador_id = ce.jogador_id and rs.item = ce.item
   where ce.jogador_id = v_id and ce.item = v_vend->>'item'
     for update of ce;
  v_n := least(v_quer, coalesce(v_tem, 0));
  if v_n < 1 then raise exception '%', case when coalesce(v_tem, 0) < 1 then 'praia_sem_estoque' else 'praia_juntando' end; end if;
  v_ganho := v_n * (v_vend->>'preco')::int;
  update fazenda_celeiro set quantidade = quantidade - v_n, da_feira = least(da_feira, quantidade - v_n)
   where jogador_id = v_id and item = v_vend->>'item';
  update fazenda_jogadores set moedas = least(2147483647, moedas::bigint + v_ganho)::int where id = v_id;
  update fazenda_construcoes set colhido_em = now() where jogador_id = v_id and x = p_x and y = p_y;
  return jsonb_build_object('item', v_vend->>'item', 'vendeu', v_n, 'ganhou', v_ganho, 'estado', fazenda_estado(v_id));
end;
$$;

-- permissões
revoke execute on function
  public.fazenda_praia_regras(),
  public.fazenda_praia_conforto(uuid)
from public, anon, authenticated;

grant execute on function
  public.fazenda_praia_caixa(text, int, int)
to anon, authenticated;

-- refaz os catálogos prontos (fazenda_cache): o carrinho de milho entra na loja do Construir
select public.fazenda_cache_montar();

-- conferência: o carrinho novo, a função do caixa e as barracas
select (select count(*) from public.fazenda_itens where id = 'barraca_milho') as carrinho_de_milho,
       (select count(*) from pg_proc where proname = 'fazenda_praia_caixa') as funcao_caixa,
       public.fazenda_praia_regras()->'vendedores' as vendedores;
