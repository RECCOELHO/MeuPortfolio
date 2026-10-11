// Compra de diamantes da Fazendinha pelo Mercado Pago (Checkout Pro) e conta Google ligada à fazenda.
//
//   POST /functions/v1/fazenda-diamantes          { token, pacote } → { url } da página de pagamento
//   POST /functions/v1/fazenda-diamantes/webhook  aviso do Mercado Pago (notification_url)
//   GET  /functions/v1/fazenda-diamantes/saude    o Access Token vale? (só o código da resposta do Mercado Pago)
//   POST /functions/v1/fazenda-diamantes/google   { credencial, acao: 'ligar' (com token) | 'entrar' }
//
// O aviso não é levado a sério sozinho: a função busca o pagamento na API do Mercado Pago
// com o nosso token e só então chama fazenda_compra_pagamento (supabase/fazenda.sql).
// O login do Google também: a assinatura é conferida com as chaves públicas do Google antes
// de chamar fazenda_google_ligar / fazenda_google_entrar.
//
// Segredo necessário (Edge Functions → Secrets): MP_ACCESS_TOKEN (o Access Token do Mercado Pago).
// SUPABASE_URL e SUPABASE_DB_URL o Supabase já fornece. "Verify JWT" desligado: quem chama é
// o jogo (sem login) e o Mercado Pago.
import postgres from 'npm:postgres@3.4.5';

const MP = 'https://api.mercadopago.com';
const TOKEN_MP = (Deno.env.get('MP_ACCESS_TOKEN') ?? '').trim();   // (espaço ou quebra de linha colados junto)
const SITE = 'https://www.jessecoelho.com.br/fazenda.html';
// ID do cliente OAuth do Google (público: é o mesmo que vai no fazenda.js)
const GOOGLE_CLIENT_ID = '399889578261-33gg9c2uq7d40v6nba2qf1g3b87qfugj.apps.googleusercontent.com';
const AVISOS = `${Deno.env.get('SUPABASE_URL')}/functions/v1/fazenda-diamantes/webhook`;
const sql = postgres(Deno.env.get('SUPABASE_DB_URL')!, { prepare: false, max: 2 });

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, apikey, authorization, x-client-info',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS'
};
const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  const url = new URL(req.url);
  try {
    if (url.pathname.endsWith('/webhook')) return await aviso(req, url);
    if (url.pathname.endsWith('/saude')) return await saude();
    if (url.pathname.endsWith('/google')) return await google(req);
    if (req.method !== 'POST') return json({ message: 'metodo_invalido' }, 405);
    return await comprar(req);
  } catch (e) {
    // erros do jogo (token_invalido, pacote_invalido...) voltam como 400; o resto, 500
    const msg = String((e as Error)?.message ?? e);
    if (/^[a-z_]+$/.test(msg) && msg !== 'mp_indisponivel') return json({ message: msg }, 400);
    console.error(e);
    // o código que o Mercado Pago respondeu (401 = token recusado) ajuda a achar o problema
    return json({ message: 'erro_pagamento', mp: (e as { mp?: number })?.mp }, 500);
  }
});

// Diagnóstico: o Access Token vale? Devolve só o código da resposta, nada da conta
async function saude() {
  if (!TOKEN_MP) return json({ ok: false, mp: 'sem_token' });
  const r = await fetch(`${MP}/users/me`, { headers: { Authorization: `Bearer ${TOKEN_MP}` } });
  return json({ ok: r.ok, mp: r.status, teste: TOKEN_MP.startsWith('TEST-') });
}
const falhaMp = async (onde: string, r: Response) => {
  console.error(onde, r.status, await r.text());
  return Object.assign(new Error('mp_indisponivel'), { mp: r.status });
};

// Conta Google: ligar à fazenda aberta (com o token da sessão) ou entrar num aparelho novo
async function google(req: Request) {
  if (!GOOGLE_CLIENT_ID) throw new Error('google_fechado');
  const { credencial, acao, token } = await req.json().catch(() => ({}));
  if (typeof credencial !== 'string') throw new Error('google_invalido');
  const conta = await conferirGoogle(credencial);
  if (acao === 'ligar') {
    if (typeof token !== 'string') throw new Error('token_invalido');
    const [{ r }] = await sql`select public.fazenda_google_ligar(${token}, ${conta.sub}, ${conta.email}) as r`;
    return json(r);
  }
  if (acao === 'entrar') {
    const [{ r }] = await sql`select public.fazenda_google_entrar(${conta.sub}) as r`;
    return json(r);
  }
  throw new Error('acao_invalida');
}

// Confere o ID token do Google (JWT RS256): assinatura com as chaves públicas dele, para quem
// foi emitido (aud), quem emitiu (iss) e a validade. Devolve o id fixo da conta (sub) e o e-mail.
let chavesGoogle: { em: number; keys: (JsonWebKey & { kid?: string })[] } | null = null;
async function chaves(renovar = false) {
  if (!renovar && chavesGoogle && Date.now() - chavesGoogle.em < 3600_000) return chavesGoogle.keys;
  const r = await fetch('https://www.googleapis.com/oauth2/v3/certs');
  if (!r.ok) throw new Error('google_indisponivel');
  chavesGoogle = { em: Date.now(), keys: (await r.json()).keys };
  return chavesGoogle.keys;
}
const base64url = (s: string) =>
  Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4)), (c) => c.charCodeAt(0));
async function conferirGoogle(jwt: string) {
  const partes = jwt.split('.');
  if (partes.length !== 3) throw new Error('google_invalido');
  let cab, dados;
  try {
    cab = JSON.parse(new TextDecoder().decode(base64url(partes[0])));
    dados = JSON.parse(new TextDecoder().decode(base64url(partes[1])));
  } catch {
    throw new Error('google_invalido');
  }
  if (cab.alg !== 'RS256') throw new Error('google_invalido');
  let jwk = (await chaves()).find((k) => k.kid === cab.kid);
  if (!jwk) jwk = (await chaves(true)).find((k) => k.kid === cab.kid);   // o Google trocou as chaves
  if (!jwk) throw new Error('google_invalido');
  const chave = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const assinada = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', chave, base64url(partes[2]),
    new TextEncoder().encode(`${partes[0]}.${partes[1]}`));
  const agora = Date.now() / 1000;
  if (!assinada || dados.aud !== GOOGLE_CLIENT_ID || !['accounts.google.com', 'https://accounts.google.com'].includes(dados.iss)
      || !(dados.exp > agora - 60) || typeof dados.sub !== 'string' || !dados.sub) {
    throw new Error('google_invalido');
  }
  return { sub: dados.sub as string, email: dados.email_verified && typeof dados.email === 'string' ? dados.email : null };
}

// O jogador escolheu um pacote: cria a compra e a preferência de pagamento
async function comprar(req: Request) {
  if (!TOKEN_MP) throw new Error('loja_fechada');
  const { token, pacote } = await req.json().catch(() => ({}));
  if (typeof token !== 'string' || typeof pacote !== 'string') throw new Error('pacote_invalido');
  const [{ c }] = await sql`select public.fazenda_compra_criar(${token}, ${pacote}) as c`;
  const volta = `${SITE}?compra=${c.id}`;
  const r = await fetch(`${MP}/checkout/preferences`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${TOKEN_MP}`, 'Content-Type': 'application/json', 'X-Idempotency-Key': c.id },
    body: JSON.stringify({
      items: [{ id: c.pacote, title: `${c.diamantes} diamantes - Fazendinha`, quantity: 1, unit_price: Number(c.valor), currency_id: 'BRL' }],
      external_reference: c.id,
      notification_url: AVISOS,
      back_urls: { success: volta, pending: volta, failure: volta },
      auto_return: 'approved',
      statement_descriptor: 'FAZENDINHA'
    })
  });
  if (!r.ok) throw await falhaMp('preferência recusada', r);
  const p = await r.json();
  // com as credenciais de teste o Mercado Pago usa o endereço do sandbox
  return json({ url: TOKEN_MP.startsWith('TEST-') ? p.sandbox_init_point : p.init_point, compra: c.id });
}

// Aviso do Mercado Pago: o id do pagamento vem na URL (?data.id= ou ?id=) ou no corpo
async function aviso(req: Request, url: URL) {
  const corpo = await req.json().catch(() => ({} as Record<string, any>));
  const tipo = url.searchParams.get('type') ?? url.searchParams.get('topic') ?? corpo.type ?? corpo.topic;
  const id = String(url.searchParams.get('data.id') ?? corpo?.data?.id ?? url.searchParams.get('id') ?? '');
  if (tipo !== 'payment' || !/^\d+$/.test(id)) return json({ ok: true });   // outros avisos não interessam

  const r = await fetch(`${MP}/v1/payments/${id}`, { headers: { Authorization: `Bearer ${TOKEN_MP}` } });
  if (r.status === 404) return json({ ok: true, pagamento: 'nao_existe' });
  if (!r.ok) throw await falhaMp('consulta do pagamento', r);   // 500: o Mercado Pago manda o aviso de novo depois
  const p = await r.json();
  // pagamento de outra coisa da mesma conta, ou em outra moeda: não é com a gente
  if (!UUID.test(String(p.external_reference ?? '')) || p.currency_id !== 'BRL') return json({ ok: true, pagamento: 'outro' });

  const [{ res }] = await sql`
    select public.fazenda_compra_pagamento(${p.external_reference}::uuid, ${String(p.id)}, ${String(p.status)}, ${Number(p.transaction_amount)}) as res`;
  return json({ ok: true, ...res });
}
