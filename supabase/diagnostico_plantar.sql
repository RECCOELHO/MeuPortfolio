-- ============================================================
-- DIAGNÓSTICO: por que um jogador não consegue plantar (feito para o Pajé, outubro de 2026)
--
-- NÃO GRAVA NADA. Roda tudo dentro de um bloco que termina com um "erro" de propósito: o
-- Postgres desfaz tudo o que o bloco fez (até o teste de arar e plantar) e mostra o relatório
-- na mensagem do erro. No SQL Editor: cole, clique em Run e copie o texto vermelho que aparecer
-- (começa com "DIAGNOSTICO"). Para outro jogador, troque o apelido na linha do v_busca.
-- ============================================================
do $$
declare
  v_busca text := 'paj%';          -- <- o começo do apelido (sem acento também acha)
  j       record;
  k       record;
  c       record;
  r       record;
  v_id    uuid;
  v_txt   text := '';
  v_t0    timestamptz;
  v_n     int;
  v_est   jsonb;
  v_res   text;
  v_pos   int;
begin
  -- quem é: pode haver mais de um com o mesmo começo de apelido
  for r in select id, apelido, xp, visto_em from fazenda_jogadores
            where translate(lower(apelido), 'áàâãéêíóôõúç', 'aaaaeeiooouc') like translate(lower(v_busca), 'áàâãéêíóôõúç', 'aaaaeeiooouc') order by visto_em desc limit 5 loop
    v_txt := v_txt || format(E'achado: %s (xp %s, visto %s)\n', r.apelido, r.xp, to_char(r.visto_em, 'DD/MM HH24:MI'));
    if v_id is null then v_id := r.id; end if;
  end loop;
  if v_id is null then raise exception 'DIAGNOSTICO: nenhum jogador com apelido parecido com %', v_busca; end if;

  select * into j from fazenda_jogadores where id = v_id;
  v_txt := v_txt || format(E'\nJOGADOR %s\n  nivel %s (trava %s), moedas %s, diamantes %s\n  semente salva: %s\n  estação agora: %s\n',
    j.apelido, fazenda_nivel_de(j.xp, j.nivel_trava), j.nivel_trava, j.moedas, j.diamantes,
    coalesce(j.semente, '(nenhuma)'), fazenda_estacao_em(now()));
  if j.semente is not null then
    select * into k from fazenda_culturas where id = j.semente;
    v_txt := v_txt || format(E'  essa semente: custo %s, nível mínimo %s, estação %s\n', k.custo, k.nivel_min, coalesce(k.estacao, 'todas'));
  end if;

  -- os canteiros, por estado
  v_txt := v_txt || E'\nCANTEIROS\n';
  for r in select estado, count(*) n from fazenda_canteiros where jogador_id = v_id group by estado order by estado loop
    v_txt := v_txt || format(E'  %s: %s\n', r.estado, r.n);
  end loop;

  -- o que está construído (as 12 coisas que mais aparecem)
  v_txt := v_txt || E'\nCONSTRUÇÕES (mais comuns)\n';
  for r in select tipo, count(*) n from fazenda_construcoes where jogador_id = v_id group by tipo order by n desc, tipo limit 12 loop
    v_txt := v_txt || format(E'  %s: %s\n', r.tipo, r.n);
  end loop;

  -- energia (a conta que o jogo faz ao abrir)
  begin
    v_txt := v_txt || format(E'\nENERGIA agora: %s\n', round(fazenda_energia_atualizar(v_id)::numeric, 1));
  exception when others then
    v_txt := v_txt || format(E'\nENERGIA: ERRO %s\n', sqlerrm);
  end;

  -- a fazenda inteira, do jeito que o jogo recebe (e quanto demora)
  v_t0 := clock_timestamp();
  begin
    v_est := fazenda_estado(v_id);
    v_txt := v_txt || format(E'\nESTADO da fazenda: ok em %s ms (%s kB)\n',
      round(extract(epoch from clock_timestamp() - v_t0) * 1000), round(length(v_est::text) / 1024.0));
    select count(*) into v_n from jsonb_array_elements(v_est->'canteiros') e where e->>'estado' = 'arado';
    v_txt := v_txt || format(E'  canteiros arados que o jogo vê: %s\n', v_n);
  exception when others then
    v_txt := v_txt || format(E'\nESTADO da fazenda: ERRO %s\n', sqlerrm);
  end;

  -- o teste de verdade: arar e plantar como se fosse ele tocando (tudo é desfeito no fim)
  v_txt := v_txt || E'\nTESTE (desfeito no fim)\n';
  select posicao into v_pos from fazenda_canteiros where jogador_id = v_id and estado = 'arado' order by posicao limit 1;
  if v_pos is not null and j.semente is not null then
    begin
      perform fazenda_aplicar(v_id, 'plantar', v_pos, j.semente);
      v_res := 'plantou';
    exception when others then v_res := 'ERRO ' || sqlerrm;
    end;
    v_txt := v_txt || format(E'  plantar %s no canteiro arado %s: %s\n', j.semente, v_pos, v_res);
  end if;
  select posicao into v_pos from fazenda_canteiros where jogador_id = v_id and estado = 'vazio' order by posicao limit 1;
  if v_pos is not null then
    begin
      perform fazenda_aplicar(v_id, 'arar', v_pos, null);
      v_res := 'arou';
    exception when others then v_res := 'ERRO ' || sqlerrm;
    end;
    v_txt := v_txt || format(E'  arar o canteiro vazio %s: %s\n', v_pos, v_res);
    if v_res = 'arou' then
      for r in select id from fazenda_culturas where id in (j.semente, 'alface') loop
        begin
          perform fazenda_aplicar(v_id, 'plantar', v_pos, r.id);
          v_res := 'plantou';
          update fazenda_canteiros set estado = 'arado', cultura = null, plantado_em = null where jogador_id = v_id and posicao = v_pos;
        exception when others then v_res := 'ERRO ' || sqlerrm;
        end;
        v_txt := v_txt || format(E'  plantar %s nele: %s\n', r.id, v_res);
      end loop;
    end if;
  end if;

  -- o "erro" de propósito: desfaz tudo e mostra o relatório
  raise exception E'DIAGNOSTICO (nada foi gravado)\n%', v_txt;
end;
$$;
