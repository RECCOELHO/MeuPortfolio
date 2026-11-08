-- ============================================================
-- FAZENDINHA — Fase 128 (a presença mais leve: sem a fila do jogador e sem gravar à toa), só o que mudou.
-- Para o banco que já está no ar (com a fase 127): Supabase > SQL Editor > colar este arquivo > Run.
-- Pode rodar antes do merge do PR.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- ------------------------------------------------------------
-- Fase 128: a presença (quem joga junto) mais leve: não entra mais na fila de chamadas do jogador e só grava
-- quando alguma coisa mudou. O jogo também avisa menos vezes (em casa, a cada 30 s).
-- Pode rodar este arquivo de novo.
-- ------------------------------------------------------------

-- fase 128: quem é o dono do token, sem entrar na fila do jogador (a presença só diz onde ele está, não mexe
-- em nada dele; antes ela esperava a ação em andamento terminar e, com o disco lento, travava junto)
create or replace function public.fazenda_auth_leve(p_token text)
returns uuid language sql stable security definer set search_path = public, extensions as $$
  select s.jogador_id
    from fazenda_sessoes s join fazenda_jogadores j on j.id = s.jogador_id
   where p_token is not null and length(p_token) >= 32
     and s.token_hash = encode(digest(p_token, 'sha256'), 'hex')
     and j.banido_em is null;
$$;

create or replace function public.fazenda_presenca(p_token text, p_onde text, p_x real default null, p_y real default null,
                                                   p_acao text default null, p_peixe text default null)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_id   uuid := fazenda_auth_leve(p_token);   -- fase 128: sem a fila do jogador
  v_onde text;
  v_dono uuid;
begin
  if v_id is null then raise exception 'token_invalido'; end if;
  if p_onde is null or p_onde = 'sair' then
    delete from fazenda_presenca where jogador_id = v_id;
    return jsonb_build_object('outros', '[]'::jsonb);
  end if;
  if p_onde = 'mar' then
    v_onde := 'mar';
  else
    begin
      v_dono := p_onde::uuid;
    exception when others then
      raise exception 'lugar_invalido';
    end;
    v_onde := v_dono::text;
  end if;
  insert into fazenda_presenca as p (jogador_id, onde, x, y, acao, peixe, pegou_em, visto_em)
  values (v_id, v_onde,
          case when p_x is not null then greatest(-20, least(100, p_x)) end,
          case when p_y is not null then greatest(-20, least(140, p_y)) end,
          case when p_acao in ('parado', 'esperando', 'mordendo') then p_acao end,
          case when p_peixe is not null and exists (select 1 from fazenda_culturas where id = p_peixe) then p_peixe end,
          case when p_peixe is not null then now() end,
          now())
  on conflict (jogador_id) do update
    set onde = excluded.onde, x = excluded.x, y = excluded.y, acao = excluded.acao,
        peixe = coalesce(excluded.peixe, p.peixe), pegou_em = coalesce(excluded.pegou_em, p.pegou_em), visto_em = now()
    -- fase 128: só grava se mudou alguma coisa (ou a cada 20 s, para continuar aparecendo)
    where p.onde is distinct from excluded.onde or p.x is distinct from excluded.x or p.y is distinct from excluded.y
       or p.acao is distinct from excluded.acao or excluded.peixe is not null or p.visto_em < now() - interval '20 seconds';

  return jsonb_build_object(
    'outros', coalesce((select jsonb_agg(q) from (
        select left(p.jogador_id::text, 8) as id, j.apelido, j.avatar, round(p.x::numeric, 2) as x, round(p.y::numeric, 2) as y,
               p.acao, p.peixe,
               case when p.pegou_em > now() - interval '12 seconds' then floor(extract(epoch from p.pegou_em) * 1000)::bigint end as pegou,
               p.jogador_id = v_dono as dono,
               case when v_onde = 'mar' then jsonb_build_object(
                 'nivel', coalesce((fazenda_mar_item(p.jogador_id, 'barco')->>'valor')::int, 1),
                 'pecas', (select jsonb_object_agg(x, coalesce((select m.nivel from fazenda_melhorias m where m.jogador_id = p.jogador_id and m.id = x), 0))
                             from unnest(array['motor', 'sonar', 'porao', 'rede', 'expedicao']) x),
                 'visual', coalesce(j.barco_visual, '{}'::jsonb)) end as navio
          from fazenda_presenca p join fazenda_jogadores j on j.id = p.jogador_id
         where p.onde = v_onde and p.jogador_id <> v_id and p.visto_em > now() - interval '45 seconds'
           and j.banido_em is null
         order by (p.jogador_id = v_dono) desc, p.visto_em desc
         limit case when v_onde = 'mar' then 3 else 8 end) q), '[]'::jsonb),
    -- na visita: onde o dono está agora (casa = na fazenda dele, mar, fora = visitando alguém; null = fora do jogo)
    'dono', case when v_dono is not null and v_dono <> v_id then
      (select case when p.onde = 'mar' then 'mar' when p.onde = v_dono::text then 'casa' else 'fora' end
         from fazenda_presenca p where p.jogador_id = v_dono and p.visto_em > now() - interval '45 seconds') end);
end;
$$;


revoke execute on function public.fazenda_auth_leve(text) from public, anon, authenticated;

-- conferência: tem que aparecer "fase 128 ok"
select case when to_regprocedure('public.fazenda_auth_leve(text)') is not null
             and (select prosrc from pg_proc where proname = 'fazenda_presenca') like '%fazenda_auth_leve%'
            then 'fase 128 ok' else 'não aplicou' end as resultado;
