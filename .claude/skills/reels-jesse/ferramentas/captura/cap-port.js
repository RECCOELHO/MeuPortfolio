const { chromium } = require('/opt/node-tools/node_modules/playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = '/home/user/meuportfolio', OUT = process.argv[2];
const tipos = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.webp': 'image/webp', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.mp4': 'video/mp4', '.json': 'application/json', '.woff2': 'font/woff2', '.wasm': 'application/wasm' };
const srv = http.createServer((q, r) => { const f = path.join(ROOT, decodeURIComponent(q.url.split('?')[0])); fs.readFile(f, (e, d) => { if (e) { r.writeHead(404); return r.end(); } r.writeHead(200, { 'Content-Type': tipos[path.extname(f)] || 'application/octet-stream' }); r.end(d); }); }).listen(8151);
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium', args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 432, height: 768 }, isMobile: true, hasTouch: true, deviceScaleFactor: 2.5 });
  p.on('pageerror', (e) => console.log('ERRO JS:', e.message));
  const NM = '/tmp/claude-0/-home-user-meuportfolio/af33bee6-9c31-5209-a92a-299062f0cf29/scratchpad/v4/node_modules';
  await p.route('**/*', (rt) => {
    const u = rt.request().url();
    if (u.startsWith('http://localhost:8151')) return rt.continue();
    const m = u.match(/cdn\.jsdelivr\.net\/npm\/(@?[^@]+)@[^/]+\/(.*)$/);
    if (m) { const f = path.join(NM, m[1], m[2]); if (fs.existsSync(f)) return rt.fulfill({ body: fs.readFileSync(f), contentType: f.endsWith('.wasm') ? 'application/wasm' : 'application/javascript', headers: { 'Access-Control-Allow-Origin': '*' } }); console.log('falta', u); }
    if (/fonts\.(googleapis|gstatic)/.test(u)) return rt.continue();
    return rt.abort();
  });
  await p.goto('http://localhost:8151/index.html', { waitUntil: 'networkidle' }).catch((e) => console.log('goto', e.message));
  await p.waitForFunction(() => window.__cracha && window.__teatro, null, { timeout: 90000 }).catch(() => console.log('não montou'));
  await p.waitForTimeout(3000);
  const H = await p.evaluate(() => document.documentElement.scrollHeight);
  console.log('altura', H);
  await p.screenshot({ path: `${OUT}/p00-topo.png` });
  const n = 26;
  for (let i = 1; i <= n; i++) {
    const y = Math.round((H - 768) * i / n);
    await p.evaluate((y) => window.scrollTo(0, y), y);
    await p.waitForTimeout(900);
    const t = await p.evaluate(() => window.__teatro ? window.__teatro.time().toFixed(2) : '-');
    await p.screenshot({ path: `${OUT}/p${String(i).padStart(2, '0')}-t${t}.png` });
  }
  await b.close(); srv.close(); process.exit(0);
})();
