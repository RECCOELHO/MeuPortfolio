-- ============================================================
-- FAZENDINHA — Fase 71c (sem timeout no pico),
-- só o que mudou. Não depende de outra fase: pode rodar a qualquer hora.
-- Supabase > SQL Editor > colar este arquivo > Run.
-- (O supabase/fazenda.sql inteiro já tem tudo isto; este arquivo é o atalho.)
-- ============================================================

-- O jogo entra como anon, e o Supabase corta cada chamada do anon em 3 s. Numa conexão nova o Postgres
-- recompila as funções grandes (fazenda_estado e as que ele chama), e a primeira chamada passava disso:
-- 20 erros 500 (57014) numa noite. O jogo espera até 25 s; 15 s deixa a chamada lenta terminar e ainda
-- corta uma travada de verdade.
alter role anon set statement_timeout = '15s';
alter role authenticated set statement_timeout = '15s';
notify pgrst, 'reload config';
notify pgrst, 'reload schema';

-- conferência: deve aparecer anon e authenticated com statement_timeout=15s
select rolname, rolconfig from pg_roles where rolname in ('anon', 'authenticated') order by rolname;
