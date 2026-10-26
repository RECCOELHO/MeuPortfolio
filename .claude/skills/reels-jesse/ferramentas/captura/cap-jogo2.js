const { chromium } = require('/opt/node-tools/node_modules/playwright');
const { execFileSync } = require('child_process');
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = '/home/user/meuportfolio', DB = 'dreels', OUT = process.argv[2], SO = process.argv[3] || '';
const psql = (sql) => execFileSync('su', ['postgres', '-c', `psql -h /var/lib/postgresql/teste-fazenda -p 5499 -d ${DB} -qAt -v ON_ERROR_STOP=1`], { input: sql }).toString().trim();
const lit = (v) => v === null || v === undefined ? 'null' : `'${(Array.isArray(v) ? '{' + v.join(',') + '}' : typeof v === 'object' ? JSON.stringify(v) : String(v)).replace(/'/g, "''")}'`;
const ANT = process.env.ANTIGO || null;
const EXPOR = (txt) => txt.replace('        function mover(dt) {', "        window.__atores = () => [...atores.values()].map((a) => ({ x: a.x, y: a.y, t: a.tipo || 'ajudante', aj: !!a.ajudante })).concat([{ x: fazendeiro.x, y: fazendeiro.y, t: 'fazendeiro', aj: true }]);\n        window.__aguas = () => aguas(); window.__faz = () => fazendeiro;\n        function mover(dt) {");
const srv = http.createServer((q, r) => /fazenda-arte\.js/.test(q.url) ? r.end(EXPOR(fs.readFileSync(path.join(ANT || ROOT, 'assets/fazenda/fazenda-arte.js'), 'utf8'))) : fs.readFile(path.join(ANT && /fazenda(-arte)?\.js$/.test(q.url.split('?')[0]) ? ANT : ROOT, decodeURIComponent(q.url.split('?')[0])), (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.end(d); })).listen(8154);
function novo(apelido, nivel, extra) {
  return psql(`select set_config('fazenda.xp_puro', '1', false);
    delete from fazenda_jogadores where apelido = '${apelido}';
    do $$ declare r jsonb := fazenda_criar('${apelido}', null); v uuid; begin
      select id into v from fazenda_jogadores where apelido = '${apelido}';
      update fazenda_jogadores set xp = fazenda_xp_nivel(${nivel}) + 9000, nivel_premiado = ${nivel}, zonas = 7, moedas = 5000000, diamantes = 300, bonus_nivel = null, pier_em = now() where id = v;
      ${extra || ''}
    end $$;
    select fazenda_nova_sessao(id) from fazenda_jogadores where apelido = '${apelido}';`).split('\n').pop();
}
async function abrir(b, tok, q, semEsc) {
  const p = await b.newPage({ viewport: { width: 432, height: 768 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2.5 });
  p.on('pageerror', (e) => console.log('ERRO JS:', e.message));
  p.on('console', (m) => { if (m.type() === 'error') console.log('console:', m.text()); });
  p.on('dialog', (d) => d.accept());
  await p.route('**/*', async (rt) => {
    const u = rt.request().url();
    if (u.startsWith('http://localhost:8154')) return rt.continue();
    const m = u.match(/rest\/v1\/rpc\/(\w+)/);
    if (!m) return /fonts\.(googleapis|gstatic)\.com/.test(u) ? rt.continue() : rt.abort();
    const args = JSON.parse(rt.request().postData() || '{}');
    const sql = `select ${m[1]}(${Object.entries(args).map(([k, v]) => `${k} => ${lit(v)}`).join(', ')});`;
    try { rt.fulfill({ status: 200, contentType: 'application/json', body: psql(sql) || 'null' }); }
    catch (e) { const mm = (e.stderr + '').match(/ERROR:\s+(\S+)/); rt.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ message: mm ? mm[1] : 'x' }) }); }
  });
  await p.addInitScript((t) => {
    localStorage.setItem('fazenda_token', t); localStorage.setItem('fazenda_tutorial', '99');
    let fa; Object.defineProperty(window, 'FazendaArte', { configurable: true, get: () => fa, set: (v) => { const o = v.criarCena; v.criarCena = (c, cb) => { window.__cb = cb; const cena = o(c, cb); window.__cena = cena; return cena; }; fa = v; } });
  }, tok);
  await p.goto('http://localhost:8154/fazenda.html' + (q || ''));
  await p.waitForTimeout(4500);
  if (!semEsc) { await p.keyboard.press('Escape'); await p.waitForTimeout(300); }
  return p;
}
const painel = (p, nome) => p.evaluate((n) => { const c = document.getElementById('painelCorpo'); c.insertAdjacentHTML('beforeend', `<button data-painel-ir="${n}" id="__ir"></button>`); document.getElementById('__ir').click(); }, nome);
const esc4 = async (p) => { for (let k = 0; k < 5; k++) { await p.keyboard.press('Escape'); await p.waitForTimeout(250); } };
const toasts = (p) => p.evaluate(() => { try { return JSON.parse(localStorage.getItem('fazenda_historico') || '[]').slice(0, 8).map((a) => (a.html || a.h || JSON.stringify(a)).replace(/<[^>]+>/g, '')); } catch (e) { return [String(e)]; } });

const tirar = async (p, n) => { await p.screenshot({ path: `${OUT}/${n}.png` }); console.log('foto', n); };
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const J = "(select id from fazenda_jogadores where apelido = 'Jessé')";
  const tok = psql(`select fazenda_nova_sessao(id) from fazenda_jogadores where apelido = 'Jessé'`).split('\n').pop();
  const p = await abrir(b, tok, '?noite=0&estacao=primavera', true); await esc4(p);
  await p.waitForTimeout(1500);
  // 1. a fazenda
  await p.evaluate(() => window.__cena.focarTile(11, 5)); await p.waitForTimeout(1800); await tirar(p, 'g01-campo');
  await p.evaluate(() => window.__cena.focarTile(17, 4)); await p.waitForTimeout(1800); await tirar(p, 'g02-bichos');
  // 2. plantar tudo no campo do sul (36 arados)
  await p.evaluate(() => window.__cena.focarTile(10, 16)); await p.waitForTimeout(1800); await tirar(p, 'g03-arados');
  await p.evaluate(() => document.querySelector('[data-massa="plantar"]').click());
  await p.waitForTimeout(120); await tirar(p, 'g04-plantando');
  await p.waitForTimeout(1800); await tirar(p, 'g05-plantou');
  await p.waitForTimeout(1500); await tirar(p, 'g05b-plantou');
  // 3. colher tudo: o campo de cima maduro
  psql(`update fazenda_canteiros c set plantado_em = now() - make_interval(secs => k.tempo_seg + 20), erva = false, praga = false, seco = false
          from fazenda_culturas k where k.id = c.cultura and c.jogador_id = ${J} and c.y <= 6;`);
  const p2 = await abrir(b, tok, '?noite=0&estacao=primavera', true); await esc4(p2); await p.close();
  await p2.evaluate(() => window.__cena.focarTile(11, 5)); await p2.waitForTimeout(1800); await tirar(p2, 'g06-maduros');
  await p2.evaluate(() => document.querySelector('[data-massa="colher"]').click());
  await p2.waitForTimeout(700); await tirar(p2, 'g07-colhendo');
  await p2.waitForTimeout(900); await tirar(p2, 'g08-colheu');
  console.log('avisos', JSON.stringify((await toasts(p2)).slice(0, 2)));
  // 4. o vizinho: visitar e ajudar tudo
  const viz = psql(`select id from fazenda_jogadores where apelido like 'Paj%'`);
  await p2.evaluate((id) => { const c = document.getElementById('painelCorpo'); c.insertAdjacentHTML('beforeend', '<button data-visitar="' + id + '" id="__v"></button>'); document.getElementById('__v').click(); }, viz);
  await p2.waitForTimeout(2500); await p2.evaluate(() => window.__cena.focarTile(11, 5)); await p2.waitForTimeout(1500); await tirar(p2, 'g09-vizinho');
  await p2.evaluate(() => document.querySelector('[data-visita="ajudar"]').click());
  await p2.waitForTimeout(700); await tirar(p2, 'g10-ajudando');
  await p2.waitForTimeout(900); await tirar(p2, 'g11-ajudou');
  console.log('avisos', JSON.stringify((await toasts(p2)).slice(0, 2)));
  await p2.evaluate(() => document.querySelector('#btnVoltarCasa').click()); await p2.waitForTimeout(2500);
  // 5. a feira
  await esc4(p2); await painel(p2, 'feira'); await p2.waitForTimeout(2000); await tirar(p2, 'g12-feira');
  // 6. o alto-mar
  await esc4(p2); await painel(p2, 'mar'); await p2.waitForTimeout(1200);
  const temMar = await p2.evaluate(() => { const b = document.querySelector('[data-mar-ir]'); if (b) b.click(); return !!b; });
  console.log('botão do mar', temMar);
  await p2.waitForTimeout(3500); await tirar(p2, 'g13-mar');
  await b.close(); srv.close(); process.exit(0);
})();
