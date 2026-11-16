// Grava as cenas do jogo e do site em 1080x1920 (432x768 @2.5), quadro a quadro (relógio virtual, 30 qps).
// Só o banco local de teste (cópia dreels3). Uso: node gravar_reels.js <saida> [cena,cena...]
const { chromium } = require('/opt/node-tools/node_modules/playwright');
const { execFileSync } = require('child_process');
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = '/home/user/meuportfolio', DB = process.env.DB || 'dreels3', OUT = process.argv[2], SO = (process.argv[3] || '').split(',').filter(Boolean);
const LIMITE = +(process.env.LIMITE || 0);
const W = 432, H = 768, K = 2.5, FPS = 30, PASSO = 1000 / FPS + 0.01, PORTA = 8194;
const PEDRUU = 'd0becfb5-8ae5-457c-94d8-fd67476d77a3';
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
const CENAS = {
  async fazenda(b) {
    const p = await abrir(b, 'fazenda.html?noite=0'); await fechar(p); await semToasts(p); await p.waitForTimeout(600);
    await gravar(p, 'fazenda', 8, (u) => focar(p, 12 + 12 * suave(u), 8 + 3 * suave(u)));
    await gravar(p, 'fazenda2', 7, (u) => focar(p, 22 + 8 * suave(u), 12 + 9 * suave(u)));
    await cx(p, 'hud-nome', '#hud'); await cx(p, 'btn-loja', '[data-painel="loja"]');
    // o caminho até a vaquinha: toca na Loja e depois na aba Diamantes
    await focar(p, 14, 9);
    await gravar(p, 'toque', 5, async (u, k) => {
      if (k === 36) await p.evaluate(() => [...document.querySelectorAll('[data-painel="loja"]')].find((x) => x.offsetParent).click());
      if (k === 60) await cx(p, 'aba-diamantes', '#painelCorpo button', 'Diamantes');
      if (k === 84) await p.evaluate(() => [...document.querySelectorAll('#painelCorpo button')].find((x) => /^\s*Diamantes\s*$/.test(x.textContent)).click());
    });
    await p.context().close();
  },
  async loja(b) {
    const p = await abrir(b, 'fazenda.html?noite=0'); await fechar(p); await semToasts(p); await irPainel(p, 'loja'); await p.waitForTimeout(900);
    await p.evaluate(() => [...document.querySelectorAll('#painelCorpo button')].find((x) => /^\s*Diamantes\s*$/.test(x.textContent)).click());
    await p.waitForTimeout(2500);
    await foto(p, 'loja-vaq');
    await cx(p, 'vaq', '.vaquinha'); await cx(p, 'vaq-barra', '.vaquinha .barra-prog'); await cx(p, 'vaq-det', '.vaquinha .det'); await cx(p, 'vaq-aviso', '.vaquinha .aviso'); await cx(p, 'vaq-selo', '.vaquinha .selo-apoiador'); await cx(p, 'vaq-tit', '.vaquinha .vaquinha-tit');
    await p.evaluate(() => { const h = [...document.querySelectorAll('#painelCorpo .secao-titulo')].find((x) => /Comprar diamantes/.test(x.textContent)); h.scrollIntoView({ block: 'start' }); document.getElementById('painelCorpo').scrollTop -= 14; });
    await p.waitForTimeout(500);
    await foto(p, 'loja-pac');
    for (const k of ['p1', 'p5', 'p10', 'p20']) await cx(p, 'pac-' + k, `[data-diamantes="${k}"]`);
    await cx(p, 'pac-aviso', '#painelCorpo p.aviso', 'Mercado Pago'); await cx(p, 'pac-lista', '#painelCorpo .secao-titulo', 'Comprar diamantes');
    await fechar(p); await irPainel(p, 'evento'); await p.waitForTimeout(1500);
    await foto(p, 'evento');
    await fechar(p); await p.evaluate(() => [...document.querySelectorAll('[data-painel="vizinhos"]')].find((x) => x.offsetParent).click()); await p.waitForTimeout(2500);
    await foto(p, 'ranking');
    await rect(p, 'rank-pedruu', () => { const s = document.querySelector('#painelCorpo .selo-live'); if (!s) return null; const e = s.closest('.item') || s.parentElement.parentElement; const r = e.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; });
    await cx(p, 'rank-selo', '#painelCorpo .selo-live');
    // a visita à fazenda do Pedruu (a faixa com o nome e o selo)
    await p.evaluate((id) => { const bt = document.createElement('button'); bt.setAttribute('data-visitar', id); document.querySelector('#painelCorpo').appendChild(bt); bt.click(); }, PEDRUU);
    await p.waitForTimeout(4500); await fechar(p); await p.waitForTimeout(500);
    await cx(p, 'visita-faixa', '.faixa-visita'); await cx(p, 'visita-selo', '.selo-live');
    await gravar(p, 'visita', 6, (u) => focar(p, 12 + 9 * suave(u), 8 + 3 * suave(u)));
    await p.context().close();
  },
  async ilha(b) {
    const p = await abrir(b, 'fazenda.html?noite=0'); await fechar(p); await semToasts(p); await p.waitForTimeout(500);
    await focar(p, 30, 33); await p.waitForTimeout(300);
    await p.evaluate(() => { window.__auto = false; });
    await p.evaluate(() => { const bt = document.getElementById('btnIlha'); if (bt) bt.click(); });
    await gravar(p, 'viagem', 6.2);
    await fechar(p);
    await gravar(p, 'ilha', 8, (u) => focar(p, 46 + 9 * suave(u), 57 + 2 * suave(u)));
    await irPainel(p, 'cachorro'); await p.waitForTimeout(1200);
    await foto(p, 'cao'); await cx(p, 'cao-fala', '#painelCorpo .cao-meu');
    await p.context().close();
  },
  async site(b) {
    const p = await abrir(b, 'index.html', false);
    await gravar(p, 'site-topo', 4);
    await p.addStyleTag({ content: '.sobe, .sobe * { opacity: 1 !important; transform: none !important; visibility: visible !important; } html { scroll-behavior: auto !important; }' });
    await p.evaluate(() => { window.__auto = false; });
    for (const [sel, nome] of [['#planos', 'planos'], ['#contato', 'contato']]) {
      await p.evaluate((s) => { const e = document.querySelector(s); window.scrollTo(0, e.getBoundingClientRect().top + scrollY); for (let k = 0; k < 12; k++) window.__passo(42); }, sel);
      await p.evaluate(() => [...document.querySelectorAll('body *')].filter((e) => getComputedStyle(e).position === 'fixed').forEach((e) => { e.style.visibility = 'hidden'; }));
      const e = await p.$(sel); await e.screenshot({ path: path.join(OUT, 'site-' + nome + '.png') });
      const base = await p.evaluate((s) => { const r = document.querySelector(s).getBoundingClientRect(); return { x: r.left, y: r.top }; }, sel);
      const marca = async (n, s, txt) => { const r = await p.evaluate(([s, txt]) => { const e = [...document.querySelectorAll(s)].find((x) => !txt || x.textContent.includes(txt)); if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; }, [s, txt]); if (r) RECTS[n] = [r.x - base.x, r.y - base.y, r.w, r.h].map((v) => Math.round(v * K)); else console.log('sem rect:', n); };
      if (nome === 'planos') {
        await marca('pl-titulo', '#planos h2'); await marca('pl-conexao', '#planos .bilhete'); await marca('pl-checkout', '#planos .bilhete:nth-of-type(2)');
        await marca('pl-zap', '#planos li', 'Atalho direto para o WhatsApp'); await marca('pl-pag', '#planos li', 'Pagamento: cartão'); await marca('pl-rel', '#planos li', 'Relatórios financeiros');
        await marca('pl-secao', '#planos');
      } else { await marca('ct-titulo', '#contato h2'); await marca('ct-numero', '#contato .numero'); await marca('ct-secao', '#contato'); }
    }
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