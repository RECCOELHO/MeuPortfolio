const { chromium } = require('/opt/node-tools/node_modules/playwright');
const { execFileSync } = require('child_process');
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = '/home/user/meuportfolio', DB = 'dreels', OUT = process.argv[2], SO = process.argv[3] || '';
const psql = (sql) => execFileSync('su', ['postgres', '-c', `psql -h /var/lib/postgresql/teste-fazenda -p 5499 -d ${DB} -qAt -v ON_ERROR_STOP=1`], { input: sql }).toString().trim();
const lit = (v) => v === null || v === undefined ? 'null' : `'${(Array.isArray(v) ? '{' + v.join(',') + '}' : typeof v === 'object' ? JSON.stringify(v) : String(v)).replace(/'/g, "''")}'`;
const ANT = process.env.ANTIGO || null;
const EXPOR = (txt) => txt.replace('        function mover(dt) {', "        window.__atores = () => [...atores.values()].map((a) => ({ x: a.x, y: a.y, t: a.tipo || 'ajudante', aj: !!a.ajudante })).concat([{ x: fazendeiro.x, y: fazendeiro.y, t: 'fazendeiro', aj: true }]);\n        window.__aguas = () => aguas(); window.__faz = () => fazendeiro;\n        function mover(dt) {");
const srv = http.createServer((q, r) => /fazenda-arte\.js/.test(q.url) ? r.end(EXPOR(fs.readFileSync(path.join(ANT || ROOT, 'assets/fazenda/fazenda-arte.js'), 'utf8'))) : fs.readFile(path.join(ANT && /fazenda(-arte)?\.js$/.test(q.url.split('?')[0]) ? ANT : ROOT, decodeURIComponent(q.url.split('?')[0])), (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.end(d); })).listen(8157);
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
    if (u.startsWith('http://localhost:8157')) return rt.continue();
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
  await p.goto('http://localhost:8157/fazenda.html' + (q || ''));
  await p.waitForTimeout(4500);
  if (!semEsc) { await p.keyboard.press('Escape'); await p.waitForTimeout(300); }
  return p;
}
const painel = (p, nome) => p.evaluate((n) => { const c = document.getElementById('painelCorpo'); c.insertAdjacentHTML('beforeend', `<button data-painel-ir="${n}" id="__ir"></button>`); document.getElementById('__ir').click(); }, nome);
const esc4 = async (p) => { for (let k = 0; k < 5; k++) { await p.keyboard.press('Escape'); await p.waitForTimeout(250); } };
const toasts = (p) => p.evaluate(() => { try { return JSON.parse(localStorage.getItem('fazenda_historico') || '[]').slice(0, 8).map((a) => (a.html || a.h || JSON.stringify(a)).replace(/<[^>]+>/g, '')); } catch (e) { return [String(e)]; } });


(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const tok = psql(`select fazenda_nova_sessao(id) from fazenda_jogadores where apelido = 'Jessé'`).split('\n').pop();
  psql(`insert into fazenda_celeiro (jogador_id, item, quantidade) values ((select id from fazenda_jogadores where apelido = 'Jessé'), 'abobora', 24) on conflict (jogador_id, item) do update set quantidade = 24;`);
  const p = await abrir(b, tok, '?noite=0&estacao=primavera', true); await esc4(p);
  await painel(p, 'feira'); await p.waitForTimeout(1500);
  await p.evaluate(() => document.querySelector('[data-aba-feira="vender"]').click()); await p.waitForTimeout(1000);
  await p.evaluate(() => { const s = document.querySelector('[data-feira-item]'); if (s) { s.value = 'abobora'; s.dispatchEvent(new Event('change', { bubbles: true })); } }); await p.waitForTimeout(800);
  await p.screenshot({ path: `${OUT}/g12b-feira-vender.png` });
  await b.close(); srv.close(); process.exit(0);
})();
