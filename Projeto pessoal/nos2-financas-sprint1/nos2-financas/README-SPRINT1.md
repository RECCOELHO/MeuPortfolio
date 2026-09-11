# Sprint 1 — Registro Essencial

Estes arquivos implementam o Sprint 1 e devem ser copiados **por cima** da
estrutura de pastas criada no Sprint 0 (mesmos caminhos relativos à raiz do
projeto `nos2-financas`).

## O que tem aqui

- `lib/supabase/client.ts` e `server.ts` — clientes Supabase (browser e server)
- `lib/types.ts` — tipos TypeScript do domínio
- `lib/categorization/categorizer.ts` — interface abstrata de categorização
- `lib/categorization/rules-engine.ts` — implementação atual (regras + aprendizado)
- `app/actions/categories.ts` — Server Actions de CRUD de categorias
- `app/actions/transactions.ts` — Server Actions de CRUD de transações (já
  chama o motor de regras automaticamente)
- `app/(app)/categorias/page.tsx` — tela de categorias
- `app/(app)/transacoes/page.tsx` — tela de transações
- `app/(app)/dashboard/page.tsx` — dashboard com saldo do mês e gasto por categoria
- `components/transaction-form.tsx` — formulário rápido (1-2 toques + detalhes opcionais)
- `supabase/migrations/0002_seed_default_categories.sql` — categorias padrão

## Como aplicar

1. Copie as pastas `app/`, `lib/`, `components/` e `supabase/` deste pacote
   para dentro do seu projeto `nos2-financas` (criado no Sprint 0),
   sobrescrevendo/mesclando o que já existir.
2. Rode a migration nova no SQL Editor do Supabase:
   `supabase/migrations/0002_seed_default_categories.sql`
   (confira se o UUID do household bate com o que você criou no seed do Sprint 0).
3. Confirme que o `middleware.ts` do Sprint 0 está protegendo as rotas
   `app/(app)/*` — sem sessão válida, deve redirecionar para `/login`.
4. Rode `npm run dev` e teste o fluxo:
   - Ir em **Categorias**, conferir se as 7 categorias padrão apareceram.
   - Ir em **Transações**, registrar "mercado 50" sem escolher categoria
     manualmente na primeira vez → vai ficar sem categoria (ainda não existe
     regra aprendida).
   - Editar essa transação escolhendo "Mercado" manualmente (ou registrar uma
     nova já escolhendo a categoria) → isso ensina a regra.
   - Registrar outro "mercado 30" → agora deve vir com "Categorizado
     automaticamente como Mercado ✅".
   - Conferir o **Dashboard**: saldo do mês, gasto por categoria e últimas
     transações devem refletir o que foi lançado.
5. Testar com a sua esposa logada com o outro e-mail: lançar algo como
   `visibility: private` e confirmar que só aparece pra quem lançou; lançar
   algo `shared` e confirmar que aparece pros dois.

## Observações técnicas

- O tipo de retorno do Supabase para o `join` `categories(name, icon)` nas
  queries é tipado como array por padrão nos tipos genéricos do
  `@supabase/supabase-js`. Se o TypeScript reclamar disso, rode
  `npx supabase gen types typescript` para gerar tipos exatos do seu schema
  e ajuste os componentes de acordo — deixei o código com acesso direto
  (`t.categories?.name`) assumindo relação 1:1, que é o caso aqui.
- O "aprendizado" de regra acontece só quando o usuário **escolhe
  manualmente** uma categoria (campo `category_id` preenchido no formulário).
  Quando a sugestão automática é usada, não gera uma nova regra (evita
  reforçar regras erradas silenciosamente).
- Ainda não existe UI de edição de transação nesta versão (só criar/remover);
  se quiser, isso pode entrar como ajuste fino do Sprint 1 antes do Sprint 2.
