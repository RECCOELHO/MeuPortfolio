# Sprint 0 — Fundação — Nós² Finanças

Repositório: novo e **privado** no GitHub (conforme decidido).
Whitelist: `tv.coelho01@gmail.com`, `ranya.vms@gmail.com`.

---

## 1. Pré-requisitos (contas e acessos, antes de codar)

- [c ] Conta no [GitHub](https://github.com) (você já tem — `RECCOELHO`)
- [c ] Conta no [Vercel](https://vercel.com) (você já usa)
- [ ] Conta no [Supabase](https://supabase.com) — criar um projeto novo (ex: `nos2-financas`), anotar a **region** mais próxima do Brasil (South America - São Paulo)
- [ ] Conta no [Google Cloud Console](https://console.cloud.google.com) (para criar as credenciais OAuth)
- [ ] Conta no [Resend](https://resend.com) (para e-mail transacional)
- [ ] Acesso ao painel de DNS do domínio `jessecoelho.com.br` (Registro.br, Cloudflare, etc.) — para criar o subdomínio `financas`
- [ ] Node.js 20+ instalado localmente

---

## 2. Comandos de Setup

```bash
# Criar o projeto Next.js
npx create-next-app@latest nos2-financas --typescript --tailwind --app --eslint
cd nos2-financas

# Dependências principais
npm install @supabase/supabase-js @supabase/ssr
npm install resend
npm install next-pwa

# Inicializar git e criar repositório PRIVADO no GitHub
git init
git add .
git commit -m "chore: setup inicial Next.js + Tailwind"

# Se tiver o GitHub CLI instalado (gh):
gh repo create nos2-financas --private --source=. --remote=origin --push

# Se NÃO tiver o gh CLI: crie o repo manualmente em github.com/new
# (marcar "Private"), depois:
git remote add origin https://github.com/RECCOELHO/nos2-financas.git
git branch -M main
git push -u origin main
```

**Variáveis de ambiente** — crie `.env.local` (nunca commitado) e `.env.example` (commitado, sem valores reais):

```bash
# .env.example
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
RESEND_API_KEY=
CRON_SECRET=
```

> ⚠️ `SUPABASE_SERVICE_ROLE_KEY` tem acesso total ao banco, ignorando RLS. Nunca prefixar com `NEXT_PUBLIC_`, nunca expor no client — só usar em rotas server-side (cron, webhooks).

Adicione ao `.gitignore` (o `create-next-app` já inclui `.env*.local`, confirme que está lá).

---

## 3. Estrutura de Pastas

```
nos2-financas/
├── app/
│   ├── (auth)/
│   │   └── login/page.tsx
│   ├── (app)/
│   │   ├── layout.tsx              # layout autenticado (sidebar, header)
│   │   ├── dashboard/page.tsx
│   │   ├── transacoes/page.tsx
│   │   ├── categorias/page.tsx
│   │   ├── metas/page.tsx
│   │   └── cofres/page.tsx
│   ├── api/
│   │   ├── auth/callback/route.ts  # callback do OAuth Google
│   │   └── cron/keep-alive/route.ts
│   ├── layout.tsx
│   └── globals.css
├── lib/
│   ├── supabase/
│   │   ├── client.ts                # cliente Supabase (browser)
│   │   ├── server.ts                # cliente Supabase (server components)
│   │   └── middleware.ts            # helper de sessão pro middleware.ts
│   ├── notifications/
│   │   ├── notifier.ts              # INTERFACE abstrata (porta aberta p/ WhatsApp futuro)
│   │   └── email-resend.ts          # implementação atual via Resend
│   └── categorization/
│       ├── categorizer.ts           # INTERFACE abstrata (porta aberta p/ IA futura)
│       └── rules-engine.ts          # implementação atual (regras/palavras-chave)
├── supabase/
│   └── migrations/
│       └── 0001_init.sql            # schema completo (seção 4)
├── public/
│   ├── manifest.json
│   └── icons/
├── middleware.ts                     # protege rotas (app) exigindo sessão
├── vercel.json                       # config do cron (seção 7)
├── next.config.js
├── .env.example
└── package.json
```

**Por que essa separação em `lib/notifications` e `lib/categorization`:** são as duas "portas abertas" que o documento de projeto exige. Hoje `notifier.ts` só tem um método `send(household, message)` implementado por `email-resend.ts`; amanhã, para plugar WhatsApp, basta criar `whatsapp.ts` implementando a mesma interface — nenhum outro código muda. O mesmo vale para `categorizer.ts`: hoje só `rules-engine.ts` existe; a IA entraria como uma segunda implementação, chamada apenas quando as regras não resolverem.

---

## 4. Schema SQL Completo (Supabase / Postgres)

Salve como `supabase/migrations/0001_init.sql` e rode no SQL Editor do Supabase (ou via CLI `supabase db push`).

```sql
-- ==========================================================
-- EXTENSÕES
-- ==========================================================
create extension if not exists "pgcrypto"; -- para gen_random_uuid()

-- ==========================================================
-- HOUSEHOLDS E WHITELIST
-- ==========================================================
create table households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table allowed_emails (
  email text primary key,
  household_id uuid not null references households(id),
  created_at timestamptz not null default now()
);

-- ==========================================================
-- USERS (espelha auth.users, 1:1)
-- ==========================================================
create table users (
  id uuid primary key references auth.users(id) on delete cascade,
  household_id uuid not null references households(id),
  name text,
  email text not null,
  role text not null default 'member' check (role in ('admin','member')),
  created_at timestamptz not null default now()
);

-- ==========================================================
-- CATEGORIAS
-- ==========================================================
create table categories (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id),
  name text not null,
  icon text,
  monthly_budget numeric,
  scope text not null default 'shared' check (scope in ('shared','personal')),
  owner_user_id uuid references users(id),
  created_at timestamptz not null default now(),
  constraint personal_needs_owner check (
    (scope = 'shared' and owner_user_id is null) or
    (scope = 'personal' and owner_user_id is not null)
  )
);

-- ==========================================================
-- TRANSAÇÕES
-- Decisão documentada: transações são sempre "realizadas" no MVP
-- (sem campo `paid`). Se precisar de "a pagar" no futuro, criar
-- esse campo em v2 junto com a modelagem formal de fatura.
-- ==========================================================
create table transactions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id),
  user_id uuid not null references users(id),
  category_id uuid references categories(id),
  type text not null check (type in ('expense','income')),
  amount numeric not null check (amount > 0),
  description text,
  notes text,
  visibility text not null default 'shared' check (visibility in ('shared','private')),
  source text not null default 'manual' check (source in ('manual','chat')),
  installment_group_id uuid,
  installment_current int,
  installment_total int,
  occurred_at date not null default current_date,
  created_at timestamptz not null default now()
);

create index on transactions (household_id, occurred_at desc);

-- ==========================================================
-- TRANSAÇÕES RECORRENTES (contas fixas)
-- ==========================================================
create table recurring_transactions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id),
  user_id uuid not null references users(id),
  category_id uuid references categories(id),
  description text not null,
  amount numeric not null,
  day_of_month int not null check (day_of_month between 1 and 28),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- ==========================================================
-- METAS E COFRES
-- ==========================================================
create table goals (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id),
  name text not null,
  target_amount numeric not null,
  current_amount numeric not null default 0,
  deadline date,
  created_at timestamptz not null default now()
);

create table vaults (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id),
  name text not null,
  balance numeric not null default 0,
  created_at timestamptz not null default now()
);

-- ==========================================================
-- CARTÃO DE CRÉDITO (simplificado — sem fatura formal no MVP)
-- ==========================================================
create table credit_cards (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id),
  user_id uuid not null references users(id),
  name text not null,
  closing_day int,
  due_day int,
  limit_amount numeric,
  created_at timestamptz not null default now()
);

-- ==========================================================
-- PARCELAS INFORMAIS ("boca a boca")
-- ==========================================================
create table informal_debts (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id),
  description text not null,
  total_amount numeric not null,
  installment_total int not null,
  installment_paid int not null default 0,
  monthly_amount numeric not null,
  created_at timestamptz not null default now()
);

-- ==========================================================
-- REGRAS DE CATEGORIZAÇÃO (aprendizado incremental)
-- ==========================================================
create table category_rules (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id),
  keyword text not null,
  category_id uuid not null references categories(id),
  created_at timestamptz not null default now(),
  unique (household_id, keyword)
);

-- ==========================================================
-- LOG DE ALERTAS (só orçamento no MVP)
-- ==========================================================
create table alerts_log (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references households(id),
  type text not null,
  message text not null,
  sent_at timestamptz not null default now()
);

-- ==========================================================
-- FUNÇÃO HELPER PARA RLS
-- ==========================================================
create or replace function auth_household_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select household_id from public.users where id = auth.uid()
$$;

-- ==========================================================
-- TRIGGER DE WHITELIST — bloqueia criação de auth.users
-- fora da lista, e já cria a linha em public.users
-- ==========================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_household_id uuid;
begin
  select household_id into v_household_id
  from public.allowed_emails
  where email = new.email;

  if v_household_id is null then
    raise exception 'E-mail não autorizado: %', new.email
      using errcode = 'P0001';
  end if;

  insert into public.users (id, household_id, name, email, role)
  values (
    new.id,
    v_household_id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.email,
    'member'
  );

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ==========================================================
-- ROW LEVEL SECURITY
-- ==========================================================
alter table households enable row level security;
alter table allowed_emails enable row level security;
alter table users enable row level security;
alter table categories enable row level security;
alter table transactions enable row level security;
alter table recurring_transactions enable row level security;
alter table goals enable row level security;
alter table vaults enable row level security;
alter table credit_cards enable row level security;
alter table informal_debts enable row level security;
alter table category_rules enable row level security;
alter table alerts_log enable row level security;

-- households: cada um só vê o próprio household
create policy "select own household"
  on households for select
  using (id = auth_household_id());

-- allowed_emails: NENHUMA policy para client (nem select, nem insert).
-- Só a service_role (usada no trigger, que roda como security definer)
-- e o dashboard do Supabase podem gerenciar essa tabela.

-- users: ver membros do mesmo household
create policy "select household members"
  on users for select
  using (household_id = auth_household_id());

-- categories
create policy "manage household categories"
  on categories for all
  using (household_id = auth_household_id())
  with check (household_id = auth_household_id());

-- transactions: regra especial por causa de `visibility`
create policy "select transactions (respeita visibility)"
  on transactions for select
  using (
    household_id = auth_household_id()
    and (visibility = 'shared' or user_id = auth.uid())
  );

create policy "insert own transactions"
  on transactions for insert
  with check (household_id = auth_household_id() and user_id = auth.uid());

create policy "update own transactions"
  on transactions for update
  using (household_id = auth_household_id() and user_id = auth.uid());

create policy "delete own transactions"
  on transactions for delete
  using (household_id = auth_household_id() and user_id = auth.uid());

-- recurring_transactions, goals, vaults, credit_cards, informal_debts, category_rules, alerts_log:
-- compartilhados no household inteiro (sem regra de visibility)
create policy "manage recurring_transactions" on recurring_transactions for all
  using (household_id = auth_household_id()) with check (household_id = auth_household_id());

create policy "manage goals" on goals for all
  using (household_id = auth_household_id()) with check (household_id = auth_household_id());

create policy "manage vaults" on vaults for all
  using (household_id = auth_household_id()) with check (household_id = auth_household_id());

create policy "manage credit_cards" on credit_cards for all
  using (household_id = auth_household_id()) with check (household_id = auth_household_id());

create policy "manage informal_debts" on informal_debts for all
  using (household_id = auth_household_id()) with check (household_id = auth_household_id());

create policy "manage category_rules" on category_rules for all
  using (household_id = auth_household_id()) with check (household_id = auth_household_id());

create policy "select alerts_log" on alerts_log for select
  using (household_id = auth_household_id());
-- inserts em alerts_log só via service_role (job de alertas), sem policy de insert pro client
```

**Seed inicial (rodar depois do schema, uma vez):**

```sql
-- Criar o household do casal
insert into households (id, name) values
  ('00000000-0000-0000-0000-000000000001', 'Coelho');

-- Whitelist
insert into allowed_emails (email, household_id) values
  ('tv.coelho01@gmail.com', '00000000-0000-0000-0000-000000000001'),
  ('ranya.vms@gmail.com', '00000000-0000-0000-0000-000000000001');
```

---

## 5. Configuração do Auth Google

**No Google Cloud Console:**
1. Criar um projeto novo (ex: "Nós² Finanças").
2. Ir em **APIs & Services → OAuth consent screen**. Tipo: **External**. Preencher nome do app e e-mail de suporte.
3. Em **Test users**, adicionar exatamente `tv.coelho01@gmail.com` e `ranya.vms@gmail.com`. Enquanto o app estiver em modo "Testing" (não publicado), **só esses e-mails conseguem completar o login** — isso é uma camada extra de proteção, além da whitelist no banco.
4. Ir em **Credentials → Create Credentials → OAuth Client ID**, tipo **Web application**.
5. Em **Authorized redirect URIs**, adicionar:
   `https://<seu-project-ref>.supabase.co/auth/v1/callback`
   (o `project-ref` aparece na URL do seu projeto Supabase)
6. Copiar o **Client ID** e o **Client Secret** gerados.

**No Supabase:**
1. **Authentication → Providers → Google** → habilitar → colar Client ID e Client Secret.
2. **Authentication → URL Configuration**:
   - Site URL: `https://financas.jessecoelho.com.br`
   - Redirect URLs: adicionar também `http://localhost:3000/**` (para testar em dev)

---

## 6. Whitelist de E-mails — onde e como é aplicada

A whitelist é aplicada em **duas camadas**, nenhuma delas no client (client-side seria inseguro, pois dá pra contornar):

1. **Google Cloud (modo Testing + test users)** — bloqueia antes mesmo de chegar no Supabase.
2. **Trigger no Postgres** (`handle_new_user`, seção 4) — se por algum motivo alguém fora da whitelist chegasse a autenticar no Google, a tentativa de criar o registro em `auth.users` do Supabase é **revertida** (a exceção cancela a transação inteira).

**Tratamento no front-end:** quando o trigger rejeita, o Supabase retorna um erro na troca do código OAuth. Em `app/api/auth/callback/route.ts`, capture esse erro e redirecione para `/login?error=not_authorized`, mostrando algo como *"Esse e-mail não tem acesso a este app."*

```ts
// app/api/auth/callback/route.ts (esqueleto)
export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get('code');

  if (code) {
    const supabase = createServerClient(/* ... */);
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (error) {
      return NextResponse.redirect(`${origin}/login?error=not_authorized`);
    }
  }
  return NextResponse.redirect(`${origin}/dashboard`);
}
```

---

## 7. Vercel Cron — Keep-alive do Supabase

`vercel.json` na raiz do projeto:

```json
{
  "crons": [
    { "path": "/api/cron/keep-alive", "schedule": "0 6 * * *" }
  ]
}
```

Isso roda 1x por dia às 06:00 UTC — mais que suficiente para evitar a pausa por 7 dias de inatividade do plano free do Supabase.

```ts
// app/api/cron/keep-alive/route.ts
import { NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

export async function GET(request: Request) {
  const authHeader = request.headers.get('authorization');
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return new NextResponse('Unauthorized', { status: 401 });
  }

  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!
  );
  await supabase.from('households').select('id').limit(1);

  return NextResponse.json({ ok: true, ts: new Date().toISOString() });
}
```

Configure `CRON_SECRET` (um valor aleatório qualquer) nas variáveis de ambiente do Vercel. O Vercel Cron já envia esse header automaticamente quando você configura um "Cron Job Secret" no projeto (Settings → Cron Jobs).

---

## 8. Subdomínio `financas.jessecoelho.com.br` na Vercel

1. No projeto na Vercel: **Settings → Domains → Add** → digitar `financas.jessecoelho.com.br`.
2. A Vercel vai indicar um registro **CNAME** (algo como `cname.vercel-dns.com`).
3. No painel de DNS onde `jessecoelho.com.br` está registrado, criar:
   - Tipo: `CNAME`
   - Nome/Host: `financas`
   - Valor: o que a Vercel indicou
4. Aguardar propagação (minutos a poucas horas). A Vercel emite o certificado SSL automaticamente assim que detectar o DNS correto.
5. Atualizar `NEXT_PUBLIC_SUPABASE_URL`/Site URL no Supabase (seção 5) se ainda não tiver usado a URL final.

---

## 9. Configuração do Resend (só setup, sem enviar nada ainda)

1. Criar conta em [resend.com](https://resend.com).
2. **Domains → Add Domain** → `jessecoelho.com.br` (ou um subdomínio tipo `mail.jessecoelho.com.br`, para não misturar com outros usos do domínio principal).
3. Adicionar os registros DNS que o Resend pedir (SPF e DKIM) no mesmo painel de DNS.
4. Aguardar verificação (geralmente rápido).
5. **API Keys → Create API Key** → copiar e colocar em `RESEND_API_KEY` (local e no Vercel).
6. Criar `lib/notifications/email-resend.ts` já com a função pronta, mas **sem nenhuma chamada real ainda** (isso fica pro Sprint 5):

```ts
// lib/notifications/email-resend.ts
import { Resend } from 'resend';
import type { Notifier } from './notifier';

const resend = new Resend(process.env.RESEND_API_KEY);

export const emailNotifier: Notifier = {
  async send(to: string, subject: string, body: string) {
    await resend.emails.send({
      from: 'Nós² Finanças <financas@jessecoelho.com.br>',
      to,
      subject,
      html: body,
    });
  },
};
```

```ts
// lib/notifications/notifier.ts — a "porta aberta" para WhatsApp no futuro
export interface Notifier {
  send(to: string, subject: string, body: string): Promise<void>;
}
```

---

## 10. Backup Mensal (GitHub Action + pg_dump)

Como o repo é privado, é seguro guardar a `SUPABASE_DB_URL` como *secret* do repositório (Settings → Secrets and variables → Actions).

```yaml
# .github/workflows/backup.yml
name: Backup mensal do banco
on:
  schedule:
    - cron: '0 3 1 * *'   # dia 1 de cada mês, 03:00 UTC
  workflow_dispatch:        # permite rodar manualmente também

jobs:
  backup:
    runs-on: ubuntu-latest
    steps:
      - name: Instalar postgresql-client
        run: sudo apt-get install -y postgresql-client

      - name: Rodar pg_dump
        run: |
          pg_dump "${{ secrets.SUPABASE_DB_URL }}" \
            --no-owner --no-privileges -F c \
            -f backup-$(date +%Y-%m-%d).dump

      - name: Guardar como artifact
        uses: actions/upload-artifact@v4
        with:
          name: backup-mensal
          path: backup-*.dump
          retention-days: 90
```

> `SUPABASE_DB_URL` é a "Connection string" (modo direto, não pooler) que aparece em **Project Settings → Database** no Supabase.

---

## Checklist Final — Sprint 0 está pronto quando:

- [ ] Repositório `nos2-financas` criado como **privado** no GitHub, código commitado e pushado
- [ ] `npm run dev` roda localmente sem erros
- [ ] Projeto Supabase criado, migration `0001_init.sql` aplicada (todas as tabelas + RLS + trigger de whitelist)
- [ ] Seed de `households` e `allowed_emails` rodado
- [ ] Login com Google **funciona** para `tv.coelho01@gmail.com` e `ranya.vms@gmail.com`
- [ ] Login **é rejeitado** para um e-mail de teste fora da whitelist (testar com uma conta Google qualquer)
- [ ] Deploy funcionando na Vercel (build sem erros)
- [ ] `financas.jessecoelho.com.br` resolve para o app, com cadeado HTTPS válido
- [ ] Cron de keep-alive configurado e aparecendo nos logs do Vercel (Settings → Cron Jobs)
- [ ] Domínio verificado no Resend e `RESEND_API_KEY` configurada (sem nenhum e-mail enviado ainda)
- [ ] GitHub Action de backup existe e rodou com sucesso pelo menos uma vez manualmente (`workflow_dispatch`)

---

## Proposta de Sprint 1 (para você validar antes de eu codar)

1. Popular categorias padrão iniciais (Mercado, Delivery, Transporte, Contas fixas, Lazer, etc.), todas `scope: shared`
2. CRUD de categorias (criar/editar categoria própria com `scope: personal`)
3. CRUD de transações (valor, tipo, categoria, `notes`, `visibility`)
4. Engine de regras de categorização: ao digitar uma transação, sugerir categoria por palavra-chave já cadastrada; se não achar, pedir escolha manual e salvar como nova regra
5. Tela de dashboard básica: saldo do mês, últimas transações, gasto por categoria
6. Teste ponta a ponta com sua esposa: ela loga, lança um gasto, categoriza, e o resultado aparece no dashboard compartilhado

Confirma esse escopo do Sprint 1, ou quer ajustar algo antes de eu começar a gerar o código?
