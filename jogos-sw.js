/* ============================================================
   SERVICE WORKER DOS JOGOS INSTALÁVEIS (Fazendinha e Pong)
   Registrado por assets/app/instalar.js só nos escopos /fazenda e
   /pong, então não mexe no resto do portfólio.
   Rede primeiro (sempre a versão mais nova); sem internet, abre a
   última cópia guardada. Troque CACHE para jogar fora as cópias.
============================================================ */
const CACHE = 'jogos-v1';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (e) => {
    e.waitUntil(caches.keys()
        .then((nomes) => Promise.all(nomes.filter((n) => n !== CACHE).map((n) => caches.delete(n))))
        .then(() => self.clients.claim()));
});

// guarda a resposta e apaga as cópias da mesma página com outro ?v=
async function guardar(pedido, resposta) {
    const c = await caches.open(CACHE);
    const antigas = await c.keys(pedido, { ignoreSearch: true });
    await Promise.all(antigas.filter((a) => a.url !== pedido.url).map((a) => c.delete(a)));
    await c.put(pedido, resposta);
}

// tocar no aviso (fazenda) abre o jogo, ou traz para a frente se já estiver aberto
self.addEventListener('notificationclick', (e) => {
    e.notification.close();
    e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((lista) => {
        const aberta = lista.find((c) => c.url.includes('/fazenda'));
        return aberta ? aberta.focus() : self.clients.openWindow('/fazenda.html');
    }));
});

self.addEventListener('fetch', (e) => {
    const pedido = e.request;
    // só arquivos do próprio site; o banco (Supabase) e as fontes passam direto
    if (pedido.method !== 'GET' || new URL(pedido.url).origin !== self.location.origin) return;
    e.respondWith(fetch(pedido).then((resposta) => {
        if (resposta.ok) e.waitUntil(guardar(pedido, resposta.clone()));
        return resposta;
    }).catch(async () => (await caches.match(pedido))
        || (await caches.match(pedido, { ignoreSearch: true }))
        || Response.error()));
});
