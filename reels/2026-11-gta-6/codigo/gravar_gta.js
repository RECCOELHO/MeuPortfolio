// Grava as cenas do jogo e do site em 1080x1920 (432x768 @2.5), quadro a quadro (relógio virtual, 30 qps).
// Só o banco local de teste (cópia dreels3). Uso: node gravar_reels.js <saida> [cena,cena...]
const { chromium } = require('/opt/node-tools/node_modules/playwright');
const { execFileSync } = require('child_process');
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = '/home/user/meuportfolio', DB = process.env.DB || 'dreels', OUT = process.argv[2], SO = (process.argv[3] || '').split(',').filter(Boolean);
const LIMITE = +(process.env.LIMITE || 0);
const W = 432, H = 768, K = 2.5, FPS = 30, PASSO = 1000 / FPS + 0.01, PORTA = 8194;

const psql = (sql) => execFileSync('su', ['postgres', '-c', `psql -h /var/lib/postgresql/teste-fazenda -p 5499 -d ${DB} -qAt -v ON_ERROR_STOP=1`], { input: sql }).toString().trim();
const lit = (v) => v === null || v === undefined ? 'null' : `'${(Array.isArray(v) ? '{' + v.join(',') + '}' : typeof v === 'object' ? JSON.stringify(v) : String(v)).replace(/'/g, "''")}'`;
const TIPOS = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.webp': 'image/webp', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.mp4': 'video/mp4', '.json': 'application/json', '.mp3': 'audio/mpeg' };
const srv = http.createServer((q, r) => { const f = path.join(ROOT, decodeURIComponent(q.url.split('?')[0])); fs.readFile(f, (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'Content-Type': TIPOS[path.extname(f)] || 'application/octet-stream' }); r.end(d); }); }).listen(PORTA);
const RELOGIO = () => {
  const rp = performance.now.bind(performance), base = rp(), dbase = Date.now();
  let vt = 0, fila = [], nid = 0;
  window.__auto = true;
  performance.now = () => base + vt;
  Date.now = () => dbase + vt;
  window.requestAnimationFrame = (cb) => { fila.push([++nid, cb]); return nid; };
  window.cancelAnimationFrame = (i) => { fila = fila.filter((c) => c[0] !== i); };
  window.__passo = (ms) => { vt += ms; const r = fila; fila = []; const t = base + vt; for (const [, cb] of r) { try { cb(t); } catch (e) { console.error(e); } } };
  setInterval(() => { if (window.__auto) window.__passo(16); }, 16);
};
const RECTS = {};
async function abrir(b, url, jogo = true) {
  const ctx = await b.newContext({ viewport: { width: W, height: H }, deviceScaleFactor: K, ...(jogo ? {} : { isMobile: true, hasTouch: true }) });
  const p = await ctx.newPage();
  p.on('pageerror', (e) => console.log('ERRO JS:', e.message));
  await p.addInitScript(RELOGIO);
  if (jogo) {
    const tok = psql(`select fazenda_nova_sessao(id) from fazenda_jogadores where apelido = 'Jesse'`).split('\n').pop();
    await p.addInitScript((t) => {
      localStorage.setItem('fazenda_token', t); localStorage.setItem('fazenda_tutorial', '99');
      let fa; Object.defineProperty(window, 'FazendaArte', { configurable: true, get: () => fa, set: (v) => { const o = v.criarCena; v.criarCena = (c, cb) => { const cena = o(c, cb); window.__cena = cena; return cena; }; fa = v; } });
    }, tok);
  }
  await p.route('**/*', async (rt) => {
    const u = rt.request().url();
    if (u.startsWith('http://localhost:' + PORTA)) return rt.continue();
    const m = u.match(/rest\/v1\/rpc\/(\w+)/);
    if (!m) return /fonts\.(googleapis|gstatic)\.com|cdnjs|jsdelivr|unpkg/.test(u) ? rt.continue() : rt.abort();
    const args = JSON.parse(rt.request().postData() || '{}');
    const sql = `select ${m[1]}(${Object.entries(args).map(([k, v]) => `${k} => ${lit(v)}`).join(', ')});`;
    try { rt.fulfill({ status: 200, contentType: 'application/json', body: psql(sql) || 'null' }); }
    catch (e) { const mm = (e.stderr + '').match(/ERROR:\s+(\S+)/); rt.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ message: mm ? mm[1] : 'x' }) }); }
  });
  await p.goto(`http://localhost:${PORTA}/` + url);
  await p.waitForTimeout(jogo ? 5000 : 2500);
  return p;
}
const fechar = async (p) => { for (let k = 0; k < 6; k++) { await p.evaluate(() => { const f = [...document.querySelectorAll('[data-fechar]')].find((x) => x.offsetParent); if (f) f.click(); }); await p.keyboard.press('Escape'); await p.waitForTimeout(200); } };
const irPainel = (p, nome) => p.evaluate((n) => { const c = document.getElementById('painelCorpo'); const bt = document.createElement('button'); bt.setAttribute('data-painel-ir', n); c.appendChild(bt); bt.click(); bt.remove(); }, nome);
const focar = (p, x, y) => p.evaluate(([x, y]) => window.__cena.focarTile(x, y), [x, y]);
const suave = (k) => k * k * (3 - 2 * k);
const semToasts = (p) => p.addStyleTag({ content: '.toasts { visibility: hidden !important; }' });
// a caixa (em px do quadro 1080x1920) de um elemento
const rect = async (p, nome, fn, arg) => { const r = await p.evaluate(fn, arg); if (r) RECTS[nome] = [r.x, r.y, r.w, r.h].map((v) => Math.round(v * K)); else console.log('sem rect:', nome); };
const caixa = (sel, txt) => { const e = [...document.querySelectorAll(sel)].find((x) => x.offsetParent !== null && (!txt || x.textContent.includes(txt))); if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; };
const cx = (p, nome, sel, txt) => rect(p, nome, new Function('a', `return (${caixa.toString()})(a[0], a[1])`), [sel, txt]);
async function gravar(p, nome, segundos, porQuadro) {
  const dir = path.join(OUT, nome); fs.rmSync(dir, { recursive: true, force: true }); fs.mkdirSync(dir, { recursive: true });
  await p.evaluate(() => { window.__auto = false; });
  let n = Math.round(segundos * FPS); if (LIMITE) n = Math.min(n, LIMITE);
  for (let k = 0; k < n; k++) {
    if (porQuadro) await porQuadro(k / n, k);
    await p.evaluate((ms) => window.__passo(ms), PASSO);
    await p.screenshot({ path: path.join(dir, String(k).padStart(4, '0') + '.jpg'), type: 'jpeg', quality: 93 });
  }
  await p.evaluate(() => { window.__auto = true; });
  if (!LIMITE) {
    execFileSync('ffmpeg', ['-nostdin', '-v', 'error', '-y', '-framerate', String(FPS), '-i', path.join(dir, '%04d.jpg'), '-c:v', 'libx264', '-crf', '15', '-g', '10', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', path.join(OUT, nome + '.mp4')]);
    fs.copyFileSync(path.join(dir, '0000.jpg'), path.join(OUT, nome + '-0.jpg'));
    fs.rmSync(dir, { recursive: true, force: true });
  }
  console.log(nome, n, 'quadros');
}
const foto = (p, nome) => p.screenshot({ path: path.join(OUT, nome + '.png') });
const fixosFora = (p) => p.evaluate(() => [...document.querySelectorAll('body *')].filter((e) => getComputedStyle(e).position === 'fixed').forEach((e) => { e.style.visibility = 'hidden'; }));
const CENAS = {
  async site(b) {
    const p = await abrir(b, 'index.html', false);
    await p.addStyleTag({ content: 'html { scroll-behavior: auto !important; }' });
    await p.evaluate(() => { window.__auto = false; });
    const pos = await p.evaluate(() => { const y = (s) => { const e = document.querySelector(s); return e ? e.getBoundingClientRect().top + scrollY : null; };
      return { c1: y('.cena.c1'), c2: y('.cena.c2'), c3: y('.cena.c3'), c4: y('.cena.c4'), planos: y('#planos'), contato: y('#contato'), h: document.scrollingElement.scrollHeight, ih: innerHeight }; });
    console.log('site:', JSON.stringify(pos));
    // as cenas da história (2018, 2020, 2025), do começo da 1ª até o começo dos Projetos: sem o topo (o crachá)
    const a = 1120, z = 3420;   // 2018 → 2020 → 2025 (medido: o topo com o crachá acaba antes de 1120; os Projetos começam em ~3640)
    // a animação do site segue a rolagem com atraso: deixa assentar bem antes de gravar (o topo tem o crachá com a foto da Elena e não pode aparecer)
    await p.evaluate((y) => { for (let k = 0; k <= 40; k++) { window.scrollTo(0, y * k / 40); for (let j = 0; j < 4; j++) window.__passo(40); } for (let k = 0; k < 200; k++) window.__passo(40); }, a);
    await gravar(p, 'site-cenas', 12, (u) => p.evaluate((y) => window.scrollTo(0, y), a + (z - a) * (0.15 * suave(u) + 0.85 * u)));
    // os projetos (o monitor da Fazendinha e a trilha das lojas e sistemas)
    await p.evaluate((y) => { window.scrollTo(0, y); for (let k = 0; k < 150; k++) window.__passo(40); }, 3560);
    await gravar(p, 'site-projetos', 5, (u) => p.evaluate((y) => window.scrollTo(0, y), 3560 + (4150 - 3560) * suave(u)));   // só o monitor da Fazendinha (a trilha das lojas tem foto de modelo: fica de fora)
    // planos e contato (telas inteiras, sem o que fica fixo)
    await p.addStyleTag({ content: '.sobe, .sobe * { opacity: 1 !important; transform: none !important; visibility: visible !important; }' });
    for (const [sel, nome] of [['#planos', 'planos'], ['#contato', 'contato']]) {
      await p.evaluate((s) => { const e = document.querySelector(s); window.scrollTo(0, e.getBoundingClientRect().top + scrollY); for (let k = 0; k < 12; k++) window.__passo(42); }, sel);
      await fixosFora(p);
      const e = await p.$(sel); await e.screenshot({ path: path.join(OUT, 'site-' + nome + '.png') });
      const base = await p.evaluate((s) => { const r = document.querySelector(s).getBoundingClientRect(); return { x: r.left, y: r.top }; }, sel);
      const marca = async (n, s, txt) => { const r = await p.evaluate(([s, txt]) => { const e = [...document.querySelectorAll(s)].find((x) => !txt || x.textContent.includes(txt)); if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; }, [s, txt]); if (r) RECTS[n] = [r.x - base.x, r.y - base.y, r.w, r.h].map((v) => Math.round(v * K)); else console.log('sem rect:', n); };
      if (nome === 'planos') { await marca('pl-zap', '#planos li', 'Atalho direto para o WhatsApp'); await marca('pl-pag', '#planos li', 'Pagamento: cartão'); await marca('pl-rel', '#planos li', 'Relatórios financeiros'); await marca('pl-banco', '#planos li', 'Banco de dados'); await marca('pl-sup', '#planos li', 'Suporte técnico'); }
      else { await marca('ct-numero', '#contato .numero'); }
    }
    await p.context().close();
  },
  async loja(b) {
    const p = await abrir(b, 'fazenda.html?noite=0'); await fechar(p); await semToasts(p); await irPainel(p, 'loja'); await p.waitForTimeout(900);
    await p.evaluate(() => [...document.querySelectorAll('#painelCorpo button')].find((x) => /^\s*Diamantes\s*$/.test(x.textContent)).click());
    await p.waitForTimeout(2500);
    await p.evaluate(() => { const h = [...document.querySelectorAll('#painelCorpo .secao-titulo')].find((x) => /Comprar diamantes/.test(x.textContent)); let rol = h.parentElement; while (rol && !(rol.scrollHeight > rol.clientHeight + 4 && /auto|scroll/.test(getComputedStyle(rol).overflowY))) rol = rol.parentElement; h.scrollIntoView({ block: 'start' }); if (rol) rol.scrollTop -= 14; });
    await p.waitForTimeout(500);
    await foto(p, 'loja-pac');
    for (const k of ['p1', 'p5', 'p10', 'p20']) await cx(p, 'pac-' + k, `[data-diamantes="${k}"]`);
    await cx(p, 'pac-aviso', '#painelCorpo p.aviso', 'Mercado Pago');
    await p.context().close();
  },
  async ilha(b) {
    const p = await abrir(b, 'fazenda.html?noite=0'); await fechar(p); await semToasts(p); await p.waitForTimeout(500);
    console.log('btnIlha:', await p.evaluate(() => { const bt = document.getElementById('btnIlha'); return bt ? { hidden: bt.hidden, txt: bt.textContent.trim() } : null; }));
    await focar(p, 30, 33); await p.waitForTimeout(300);
    await p.evaluate(() => { window.__auto = false; });
    await p.evaluate(() => { const bt = document.getElementById('btnIlha'); if (bt && !bt.hidden) bt.click(); else if (window.__cena.irPara) window.__cena.irPara('ilha'); });
    await gravar(p, 'viagem', 6.2);
    await fechar(p);
    await gravar(p, 'ilha', 8, (u) => focar(p, 46 + 9 * suave(u), 57 + 2 * suave(u)));
    await p.context().close();
  },
};
(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  for (const [nome, f] of Object.entries(CENAS)) if (!SO.length || SO.includes(nome)) { const t = Date.now(); await f(b); console.log('  ', nome, ((Date.now() - t) / 1000).toFixed(0) + 's'); }
  const arq = path.join(OUT, 'rects.json'); const ant = fs.existsSync(arq) ? JSON.parse(fs.readFileSync(arq)) : {};
  fs.writeFileSync(arq, JSON.stringify({ ...ant, ...RECTS }, null, 1));
  await b.close(); srv.close(); process.exit(0);
})();