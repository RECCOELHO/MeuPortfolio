// Compra de diamantes da Fazendinha pelo Mercado Pago (Checkout Pro).
//
//   POST /functions/v1/fazenda-diamantes          { token, pacote } → { url } da página de pagamento
//   POST /functions/v1/fazenda-diamantes/webhook  aviso do Mercado Pago (notification_url)
//
// O aviso não é levado a sério sozinho: a função busca o pagamento na API do Mercado Pago
// com o nosso token e só então chama fazenda_compra_pagamento (supabase/fazenda.sql).
//
// Segredo necessário (Edge Functions → Secrets): MP_ACCESS_TOKEN (o Access Token do Mercado Pago).
// SUPABASE_URL e SUPABASE_DB_URL o Supabase já fornece. "Verify JWT" desligado: quem chama é
// o jogo (sem login) e o Mercado Pago.
import postgres from 'npm:postgres@3.4.5';

const MP = 'https://api.mercadopago.com';
const TOKEN_MP = Deno.env.get('MP_ACCESS_TOKEN') ?? '';
const SITE = 'https://www.jessecoelho.com.br/fazenda.html';
const AVISOS = `${Deno.env.get('SUPABASE_URL')}/functions/v1/fazenda-diamantes/webhook`;
const sql = postgres(Deno.env.get('SUPABASE_DB_URL')!, { prepare: false, max: 2 });

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, apikey, authorization, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};
const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  const url = new URL(req.url);
  try {
    if (url.pathname.endsWith('/webhook')) return await aviso(req, url);
    if (req.method !== 'POST') return json({ message: 'metodo_invalido' }, 405);
    return await comprar(req);
  } catch (e) {
    // erros do jogo (token_invalido, pacote_invalido...) voltam como 400; o resto, 500
    const msg = String((e as Error)?.message ?? e);
    if (/^[a-z_]+$/.test(msg) && msg !== 'mp_indisponivel') return json({ message: msg }, 400);
    console.error(e);
    return json({ message: 'erro_pagamento' }, 500);
  }
});

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
  if (!r.ok) {
    console.error('preferência recusada', r.status, await r.text());
    throw new Error('mp_indisponivel');
  }
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
  if (!r.ok) throw new Error('mp_indisponivel');   // 500: o Mercado Pago manda o aviso de novo depois
  const p = await r.json();
  // pagamento de outra coisa da mesma conta, ou em outra moeda: não é com a gente
  if (!UUID.test(String(p.external_reference ?? '')) || p.currency_id !== 'BRL') return json({ ok: true, pagamento: 'outro' });

  const [{ res }] = await sql`
    select public.fazenda_compra_pagamento(${p.external_reference}::uuid, ${String(p.id)}, ${String(p.status)}, ${Number(p.transaction_amount)}) as res`;
  return json({ ok: true, ...res });
}
