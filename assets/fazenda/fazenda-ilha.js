/* ============================================================
   FAZENDINHA — a Ilha da Caveira Dourada (fase 106)
   Do nível 46 em diante, com o kit de expedição, o navio zarpa do píer: primeiro a viagem (o navio
   cruzando o mar enquanto a ilha cresce no horizonte), depois a ilha. Nela o porto vai sendo
   construído, uma obra por nível do 46 ao 60 (fazenda_ilha_construir); a próxima obra aparece com a
   placa de "obra". Com o cais pronto, 1 vez por dia tem um baú enterrado no X da praia
   (fazenda_ilha_bau). O jogo (fazenda.js) faz as chamadas e passa os dados por "op".
   ============================================================ */
(() => {
    'use strict';
    const A = window.FazendaArte;
    const OL = '#3f2631';
    const CEU = ['#5fb6ec', '#74c2ef', '#8bcdf2', '#a3d8f5', '#bfe4f8'];
    const CEU_N = ['#0f1530', '#141c3d', '#1b2650', '#233363', '#2d4277'];
    const MAR = ['#7fb8e6', '#5b9ad6', '#4a8bcc', '#3a7cc4', '#336fb3', '#2b5f9e', '#244f86'];
    const MATA = ['#2f6e3a', '#3e8948', '#4e974c', '#5aa850', '#2a5838'];
    const hex = (c) => [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16));
    const mistura = (a, b, t) => { const x = hex(a), y = hex(b); return '#' + x.map((v, i) => Math.round(v + (y[i] - v) * t).toString(16).padStart(2, '0')).join(''); };
    function rng(seed) { let s = seed >>> 0 || 1; return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; }; }

    // onde fica cada obra: x na largura da ilha (0 a 1) e a base (a linha do chão) na altura da tela;
    // 'morro' fica na encosta e 'topo' no alto do morro
    const LUGAR = {
        cais: [0.30, 0], trapiche: [0.15, 0], armazem: [0.07, 0.585], muralha: [0.80, 0.705], taverna: [0.27, 0.575],
        portao: [0.42, 0.560], farol: [0.965, 0.690], vigia: [0.66, 'morro'], mercado: [0.50, 0.645], toldo: [0.64, 0.600],
        ancora: [0.36, 0.680], canhoes: [0.83, 0.668], sereia: [0.17, 0.668], cartografo: [0.82, 0.560], bandeira: [0.62, 'topo']
    };

    function criar(op) {
        const raiz = document.createElement('div');
        raiz.className = 'mar ilha';
        raiz.innerHTML = `
            <canvas class="mar-cena" aria-label="A Ilha da Caveira Dourada"></canvas>
            <div class="mar-topo" data-ilha-topo></div>
            <p class="mar-dica" data-ilha-dica aria-live="polite"></p>`;
        document.body.appendChild(raiz);
        const canvas = raiz.querySelector('canvas'), ctx = canvas.getContext('2d');
        const elTopo = raiz.querySelector('[data-ilha-topo]'), elDica = raiz.querySelector('[data-ilha-dica]');
        const buf = document.createElement('canvas'), g = buf.getContext('2d'), tinta = document.createElement('canvas');
        let LW = 216, LH = 384, escala = 2, dpr = 1, vivo = true, t = 0;
        const t0 = performance.now(), VIAGEM = 3200, CLARAO = 350;   // a viagem antes de chegar
        let alvos = [];   // onde tocar: { x, y, w, h, acao }
        let dica = null;

        function redimensionar() {
            dpr = Math.min(window.devicePixelRatio || 1, 3);
            const W = window.innerWidth, H = window.innerHeight;
            escala = Math.max(2, Math.min(6, Math.round(Math.min(W / 220, H / 380))));
            LW = Math.ceil(W / escala); LH = Math.ceil(H / escala);
            buf.width = LW; buf.height = LH;
            canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
            canvas.style.width = W + 'px'; canvas.style.height = H + 'px';
        }
        redimensionar();
        window.addEventListener('resize', redimensionar);
        const R = (x, y, w, h, c) => { g.fillStyle = c; g.fillRect(Math.round(x), Math.round(y), Math.max(1, Math.round(w)), Math.max(1, Math.round(h))); };
        const disco = (cx, cy, r, c) => { for (let dy = -r; dy <= r; dy++) { const w = Math.round(Math.sqrt(r * r - dy * dy)); R(cx - w, cy + dy, w * 2 + 1, 1, c); } };

        function pintarTopo() {
            const html = op.htmlTopo();
            if (elTopo.innerHTML !== html) elTopo.innerHTML = html;
        }
        function pintarDica() {
            const d = op.dados() || {}, texto = dica && performance.now() < dica.ate ? dica.texto
                : performance.now() - t0 < VIAGEM ? 'Zarpando para a Ilha da Caveira Dourada...'
                : d.obras >= 15 ? (d.bau_hoje ? 'A ilha é sua! Amanhã tem outro baú no X da praia.' : 'A ilha é sua! Toque no X da praia para cavar o baú do dia.')
                : d.obras >= 1 && !d.bau_hoje ? 'Toque no X da praia para cavar o baú do dia, ou na placa de obra para construir.'
                : `Toque na placa de obra para construir: ${d.proxima ? d.proxima.nome : ''}${d.proxima && d.proxima.nivel ? ` (nível ${d.proxima.nivel})` : ''}.`;
            if (elDica.textContent !== texto) elDica.textContent = texto;
        }

        // ----- a geografia -----
        const horizonte = () => Math.round(LH * 0.30);
        const IW = () => Math.min(LW, 260);
        const X = (f) => Math.round(LW / 2 - IW() / 2 + f * IW());
        const uDe = (x) => (x - (LW / 2 - IW() / 2)) / IW();
        const areiaTopo = (x) => Math.round(LH * 0.52 + Math.sin(x / 11) * 1.5);
        const praia = (x) => Math.round(LH * 0.71 + Math.sin(x / 13 + 1) * 1.5);
        // o morro: dois picos (o maior à direita) que somem nas pontas da ilha
        function morroTopo(x) {
            const u = uDe(x), borda = Math.max(0, Math.min(1, (u + 0.02) * 5, (1.02 - u) * 5));
            const alto = (LH * 0.25) * Math.exp(-(((u - 0.62) / 0.2) ** 2)) + (LH * 0.15) * Math.exp(-(((u - 0.26) / 0.18) ** 2)) + LH * 0.035;
            return Math.round(areiaTopo(x) - (alto + Math.sin(x / 5) * 1.2) * borda);
        }
        const picoX = () => X(0.62);

        function ceu(noite) {
            const h = horizonte();
            for (let k = 0; k < 5; k++) R(0, (h * k) / 5, LW, h / 5 + 1, mistura(CEU[k], CEU_N[k], noite));
            if (noite > 0.4) { const r = rng(5); g.globalAlpha = (noite - 0.4) * 1.6; for (let k = 0; k < 40; k++) R(r() * LW, r() * h * 0.9, 1, 1, Math.floor(t / 600 + k) % 7 ? '#e8ecff' : '#ffffff'); g.globalAlpha = 1; }
            if (noite < 0.5) { disco(LW - 26, 22, 7, '#fff3c4'); disco(LW - 26, 22, 5, '#ffe08a'); }
            else { disco(LW - 26, 22, 6, '#f4f1e6'); disco(LW - 23, 20, 5, mistura(CEU[0], CEU_N[0], noite)); }
            for (let k = 0; k < 3; k++) {   // as nuvens
                const x = ((t / 120 + k * 90) % (LW + 60)) - 40, y = 14 + k * 17, c = mistura('#ffffff', '#3a4a70', noite), s = mistura('#dbe9f6', '#2c3a60', noite);
                R(x, y, 30, 5, c); R(x + 6, y - 4, 16, 4, c); R(x + 18, y - 2, 10, 3, c); R(x + 2, y + 4, 26, 2, s);
            }
            if (noite < 0.6) for (let k = 0; k < 3; k++) {   // as gaivotas
                const x = ((t / 45 + k * 70) % (LW + 30)) - 15, y = 40 + k * 9 + Math.sin(t / 400 + k) * 3, asa = Math.floor(t / 180 + k) % 2;
                R(x, y + asa, 2, 1, OL); R(x + 2, y + 1, 1, 1, OL); R(x + 3, y + asa, 2, 1, OL);
            }
        }
        function mar(noite, corre) {
            const h = horizonte();
            for (let k = 0; k < 7; k++) R(0, h + ((LH - h) * k) / 7, LW, (LH - h) / 7 + 1, mistura(MAR[k], '#0e1a3a', noite * 0.7));
            const r = rng(77), vel = corre ? 6 : 40;
            for (let k = 0; k < 90; k++) {
                const prof = r(), y = h + 3 + prof * (LH - h - 6), w = 2 + Math.floor(prof * 5);
                const x = (((r() * LW - t / (vel + (1 - prof) * 30) * (corre ? 1 + prof * 2 : 1)) % (LW + 10)) + LW + 10) % (LW + 10) - 5;
                R(x, y, w, 1, mistura(prof < 0.3 ? '#cfe4f6' : '#a8cbee', '#3a5a90', noite));
            }
            if (noite < 0.5) for (let k = 0; k < 6; k++) { const x = LW - 26 + Math.sin(k * 2.1) * 6, y = h + 3 + k * 3; R(x - k, y, 3 + k, 1, '#fff3c4'); }   // o sol na água
        }

        // a ilha ao longe (na viagem): f = 0 (pontinho) a 1 (perto)
        function ilhaLonge(f, noite) {
            const h = horizonte(), w = Math.round(24 + f * f * IW() * 0.9), cx = Math.round(LW * 0.62), alt = Math.round(w * 0.28);
            const nevoa = 0.55 * (1 - f);
            for (let x = 0; x < w; x++) {
                const u = x / w, y = Math.round(alt * (0.7 * Math.exp(-(((u - 0.62) / 0.2) ** 2)) + 0.45 * Math.exp(-(((u - 0.26) / 0.18) ** 2)) + 0.1) * Math.min(1, u * 5, (1 - u) * 5));
                R(cx - w / 2 + x, h - y, 1, y + 1, mistura(mistura(x % 4 ? '#3e8948' : '#2f6e3a', '#8fb7d8', nevoa), '#1a2440', noite * 0.5));
            }
            R(cx - w / 2 - 2, h, w + 4, Math.max(1, Math.round(f * 3)), mistura(mistura('#ecd59a', '#8fb7d8', nevoa), '#1a2440', noite * 0.5));
            if (f > 0.35) {   // a caveira dourada já aparece
                const sx = Math.round(cx - w / 2 + w * 0.40), sy = h - Math.round(alt * 0.5), r = Math.max(1, Math.round(w / 40));
                disco(sx, sy, r, mistura('#d8b04a', '#8fb7d8', nevoa)); R(sx - r / 2, sy, 1, 1, '#2a1a10'); R(sx + r / 2, sy, 1, 1, '#2a1a10');
            }
        }

        function mata(noite) {
            const esc = (c) => mistura(c, '#14203a', noite * 0.6);
            const x0 = Math.max(0, X(-0.03)), x1 = Math.min(LW, X(1.03));
            for (let x = x0; x < x1; x++) { const tp = morroTopo(x), base = areiaTopo(x) + 2; if (base > tp) R(x, tp, 1, base - tp, esc(MATA[4])); }
            // as copas, de trás para a frente: bolinhas com contorno, luz em cima à esquerda
            const r = rng(31), copas = [];
            for (let x = x0; x < x1; x += 4) { const tp = morroTopo(x); if (areiaTopo(x) - tp > 4) copas.push([x + r() * 3, tp + 2, 3 + Math.floor(r() * 2)]); }
            for (let k = 0; k < IW() * 1.6; k++) {
                const x = x0 + r() * (x1 - x0), tp = morroTopo(Math.round(x)), base = areiaTopo(Math.round(x));
                if (base - tp < 8) continue;
                copas.push([x, tp + 5 + r() * (base - tp - 6), 3 + Math.floor(r() * 3)]);
            }
            copas.sort((a, b) => a[1] - b[1]);
            const rc = rng(9);
            for (const [cx, cy, rr] of copas) {
                const cor = MATA[Math.floor(rc() * 4)];
                disco(Math.round(cx), Math.round(cy), rr + 1, esc('#1e4a2a'));
                disco(Math.round(cx), Math.round(cy), rr, esc(cor));
                disco(Math.round(cx - rr / 3), Math.round(cy - rr / 3), Math.max(1, rr - 2), esc(mistura(cor, '#a7f070', 0.35)));
                R(cx + rr / 2, cy + rr / 2, 1, 1, esc('#1e4a2a'));
            }
            // as pedras do pé do morro, do lado do farol
            for (let k = 0; k < 4; k++) { const px = X(0.90 + k * 0.03), py = areiaTopo(px) - 3 - (k % 2) * 3; R(px - 1, py - 1, 8, 6, esc('#4a4250')); R(px, py, 6, 4, esc('#8b7d72')); R(px, py, 3, 1, esc('#b8aca2')); }
        }
        // a caveira dourada: a pedra que dá nome à ilha, na encosta do morro menor
        function caveira(noite) {
            const cx = X(0.30), cy = morroTopo(X(0.30)) + 13, esc = (c) => mistura(c, '#1a2440', noite * 0.45);
            disco(cx, cy, 10, '#5a3a14');
            disco(cx, cy, 9, esc('#d8b04a'));
            disco(cx + 3, cy + 2, 6, esc('#b8902e'));   // a sombra do lado direito
            disco(cx - 3, cy - 4, 4, esc('#f4d878'));   // o brilho
            R(cx - 6, cy + 7, 13, 6, '#5a3a14'); R(cx - 5, cy + 7, 11, 5, esc('#c9a040'));   // o queixo
            for (let k = -4; k <= 4; k += 2) R(cx + k, cy + 8, 1, 4, '#5a3a14');   // os dentes
            const olho = noite > 0.35 ? mistura('#2a1a10', '#ffd75e', Math.min(1, (noite - 0.35) * 2) * (0.7 + 0.3 * Math.sin(t / 500))) : '#2a1a10';
            disco(cx - 4, cy, 2, olho); disco(cx + 4, cy, 2, olho);
            R(cx - 1, cy + 3, 2, 2, '#2a1a10');   // o nariz
            if (Math.floor(t / 2200) % 5 === 0) { const b = Math.floor(t / 110) % 6; R(cx - 7 + b, cy - 7, 1, 1, '#ffffff'); }   // o brilho do ouro
        }
        // a trilha do portão até o alto do morro
        function trilha(noite) {
            const c = mistura('#d9bf84', '#1a2440', noite * 0.5);
            const a = [X(0.44), areiaTopo(X(0.44))], b = [X(0.52), morroTopo(X(0.52)) + 20], d = [picoX(), morroTopo(picoX()) + 3];
            for (let k = 0; k <= 40; k++) {
                const f = k / 40, p = f < 0.5 ? [a[0] + (b[0] - a[0]) * f * 2, a[1] + (b[1] - a[1]) * f * 2] : [b[0] + (d[0] - b[0]) * (f - 0.5) * 2, b[1] + (d[1] - b[1]) * (f - 0.5) * 2];
                if (k % 3 !== 2) R(p[0], p[1], 2, 1, c);
            }
        }
        function areia(noite) {
            const esc = (c) => mistura(c, '#1a2440', noite * 0.55);
            const x0 = Math.max(0, X(-0.05)), x1 = Math.min(LW, X(1.05));
            for (let x = x0; x < x1; x++) {
                const u = uDe(x), ponta = Math.sin(Math.max(0, Math.min(1, (u + 0.05) * 4, (1.05 - u) * 4)) * Math.PI / 2) ** 0.6;   // as pontas arredondadas
                const topo = areiaTopo(x), fim = Math.round(topo + (praia(x) - topo) * ponta);
                if (fim <= topo) continue;
                const meio = topo + Math.round((fim - topo) * 0.55);
                R(x, topo, 1, meio - topo, esc('#f0dca4'));
                R(x, meio, 1, fim - meio - 4, esc('#e6cc8c'));
                R(x, fim - 4, 1, 4, esc('#cdb074'));   // a areia molhada
                if ((x * 7) % 11 === 0) R(x, topo + 3 + (x % 9) * 2, 1, 1, esc('#c9a86a'));
                if ((x * 5) % 13 === 0) R(x, meio + (x % 5) * 2, 1, 1, esc('#fff4cf'));
                // a espuma vai e volta
                const vai = Math.round(1.5 + Math.sin(t / 700 + x / 9) * 1.5);
                R(x, fim - vai, 1, 1, esc('#f4f8fc')); if ((x + Math.floor(t / 300)) % 4) R(x, fim - vai + 1, 1, 1, esc('#d6e8f6'));
            }
            // conchas, uma estrela-do-mar e o caranguejo andando de lado
            const esc2 = (c) => mistura(c, '#1a2440', noite * 0.4);
            R(X(0.56), LH * 0.62, 2, 1, esc2('#f4b7c4')); R(X(0.09), LH * 0.67, 2, 1, esc2('#fff4cf'));
            const ex = X(0.72), ey = Math.round(LH * 0.685); R(ex + 1, ey, 1, 3, esc2('#e8735a')); R(ex, ey + 1, 3, 1, esc2('#e8735a'));
            const cx = X(0.45) + Math.round(Math.sin(t / 2600) * IW() * 0.08), cy = praia(cx) - 7, pe = Math.floor(t / 150) % 2;
            R(cx, cy, 5, 2, esc2('#d9452f')); R(cx + 1, cy - 1, 1, 1, OL); R(cx + 3, cy - 1, 1, 1, OL); R(cx - 1, cy - 1, 1, 2, esc2('#d9452f')); R(cx + 5, cy - 1, 1, 2, esc2('#d9452f'));
            R(cx + pe, cy + 2, 1, 1, OL); R(cx + 3 + pe, cy + 2, 1, 1, OL);
        }
        function coqueiro(x, base, alt, noite, fase) {
            const esc = (c) => mistura(c, '#1a2440', noite * 0.55);
            for (let k = 0; k < alt; k++) R(x + Math.round(Math.sin(k / 9 + fase) * 2), base - k, 2, 1, esc(k % 3 ? '#9a6a3c' : '#6e3d1b'));
            const tx = x + Math.round(Math.sin(alt / 9 + fase) * 2), ty = base - alt, bal = Math.sin(t / 700 + fase * 3);
            for (const [dx, dy] of [[-10, 3], [10, 3], [-8, -3], [8, -3], [-2, -6], [3, -6]]) for (let k = 0; k < 9; k++) {
                const px = tx + (dx * k) / 9 + bal * (k / 9), py = ty + (dy * k) / 9 + (k * k) / 16;
                R(px, py, 2, 1, esc(k % 3 === 2 ? '#2f6e3a' : '#5aa850')); if (k > 2) R(px, py + 1, 1, 1, esc('#2f6e3a'));
            }
            R(tx - 1, ty + 1, 2, 2, esc('#8a4a2b')); R(tx + 1, ty + 2, 2, 2, esc('#6e3d1b'));
        }

        // ----- as obras -----
        function baseDe(id) {
            const L = LUGAR[id], x = X(L[0]);
            if (L[1] === 'topo') return [x, morroTopo(x) + 1];
            if (L[1] === 'morro') return [x, morroTopo(x) + 22];
            if (id === 'cais' || id === 'trapiche') return [x, praia(x)];
            return [x, Math.round(LH * L[1])];
        }
        function obra(id, x, y, noite) {
            const esc = (c) => mistura(c, '#1a2440', noite * 0.5);
            const luz = noite > 0.4 ? '#ffd27a' : '#79a7e8';
            const telhado = (tx, ty, tw, c) => { R(tx - 1, ty - 1, tw + 2, 7, OL); R(tx, ty, tw, 5, esc(c)); R(tx, ty, tw, 1, esc(mistura(c, '#ffffff', 0.4))); for (let k = tx + 1; k < tx + tw; k += 3) R(k, ty + 2, 1, 3, esc(mistura(c, '#000000', 0.2))); };
            const parede = (px, py, pw, ph, c) => { R(px - 1, py, pw + 2, ph + 1, OL); R(px, py, pw, ph, esc(c)); for (let k = px + 2; k < px + pw; k += 3) R(k, py, 1, ph, esc(mistura(c, '#000000', 0.15))); R(px, py + ph - 2, pw, 2, esc(mistura(c, '#000000', 0.3))); };
            const janela = (jx, jy) => { R(jx, jy, 4, 4, OL); R(jx + 1, jy + 1, 2, 2, esc(luz)); if (noite > 0.4) { g.globalAlpha = 0.25; R(jx - 2, jy - 2, 8, 8, '#ffd27a'); g.globalAlpha = 1; } };
            const porta = (px, py, h) => { R(px, py, 5, h, OL); R(px + 1, py + 1, 3, h - 1, esc('#8a4a2b')); R(px + 3, py + Math.round(h / 2), 1, 1, '#fdbe53'); };
            const lampiao = (lx, ly) => { R(lx, ly, 1, 6, OL); R(lx - 1, ly - 3, 3, 3, OL); R(lx, ly - 2, 1, 1, noite > 0.4 ? '#ffe08a' : '#c9a46a'); if (noite > 0.4) { g.globalAlpha = 0.3 * noite; disco(lx, ly - 2, 5, '#ffd27a'); g.globalAlpha = 1; } };
            if (id === 'cais') {   // o cais entra no mar até o navio
                const fim = Math.round(LH * 0.82);
                R(x - 6, y - 2, 13, fim - y + 3, OL);
                for (let k = y - 1; k < fim; k += 3) { R(x - 5, k, 11, 2, esc('#b4804e')); R(x - 5, k + 2, 11, 1, esc('#6e3d1b')); }
                for (const px of [x - 7, x + 6]) for (let k = y + 4; k < fim + 2; k += 9) { R(px, k - 2, 2, 8, OL); R(px, k - 2, 1, 7, esc('#8a5a32')); }
                lampiao(x - 6, fim - 9); lampiao(x + 7, y + 6);
                R(x - 2, fim - 4, 4, 2, esc('#c9a46a'));   // a corda enrolada
            } else if (id === 'trapiche') {   // a passarela de tábuas na beira da praia
                const w = Math.round(IW() * 0.26), x0 = x - Math.round(w / 2);
                R(x0 - 1, y - 9, w + 2, 5, OL);
                for (let k = 0; k < w; k++) R(x0 + k, y - 8, 1, 3, esc(k % 4 === 3 ? '#8a5a32' : '#c98a4a'));
                for (let k = x0 + 1; k < x0 + w; k += 8) { R(k, y - 4, 2, 6, OL); R(k, y - 4, 1, 5, esc('#6e3d1b')); }
                for (let k = x0; k < x0 + w; k += 8) R(k, y - 12, 1, 4, OL);
                R(x0, y - 12, w, 1, esc('#c9a46a'));   // o corrimão de corda
            } else if (id === 'armazem') {
                parede(x - 2, y - 15, 22, 15, '#b4804e'); telhado(x - 4, y - 21, 26, '#c34b35');
                R(x + 5, y - 11, 8, 11, OL); R(x + 6, y - 10, 6, 10, esc('#6e3d1b')); R(x + 6, y - 10, 6, 1, esc('#8a5a32')); R(x + 8, y - 10, 1, 10, OL);
                janela(x, y - 12); for (const [bx, cor] of [[x + 20, '#8a5a32'], [x + 23, '#6e3d1b']]) { R(bx, y - 6, 4, 6, OL); R(bx + 1, y - 5, 2, 4, esc(cor)); }
                R(x + 2, y - 19, 14, 3, esc('#f4ecd8')); R(x + 4, y - 18, 10, 1, OL);   // a placa
            } else if (id === 'muralha') {
                const w = Math.round(IW() * 0.26), x0 = x - Math.round(w / 2);
                for (let k = 0; k < w; k += 6) for (let fila = 0; fila < 2; fila++) {
                    const bx = x0 + k + (fila ? 3 : 0); if (bx + 6 > x0 + w + 3) continue;
                    R(bx, y - 8 + fila * 4, 6, 4, OL); R(bx + 1, y - 7 + fila * 4, 4, 2, esc((k / 6 + fila) % 2 ? '#a39388' : '#8b7d72')); R(bx + 1, y - 7 + fila * 4, 2, 1, esc('#c8bcb2'));
                }
                for (let k = 0; k < w; k += 8) { R(x0 + k, y - 11, 5, 3, OL); R(x0 + k + 1, y - 10, 3, 2, esc('#a39388')); }   // as ameias
            } else if (id === 'taverna') {
                parede(x, y - 16, 24, 16, '#e8d8b0'); telhado(x - 2, y - 22, 28, '#5d6b80');
                R(x + 17, y - 27, 4, 6, OL); R(x + 18, y - 26, 2, 5, esc('#8b7d72'));   // a chaminé
                if (noite < 0.7) for (let k = 0; k < 3; k++) { const fx = x + 19 + Math.sin(t / 500 + k) * 2, fy = y - 29 - k * 3 - ((t / 120) % 3); g.globalAlpha = 0.5 - k * 0.12; R(fx, fy, 2, 2, '#e8ecf2'); g.globalAlpha = 1; }
                janela(x + 3, y - 12); janela(x + 17, y - 12); porta(x + 10, y - 9, 9);
                R(x + 26, y - 18, 1, 9, OL); R(x + 24, y - 14, 8, 6, OL); R(x + 25, y - 13, 6, 4, esc('#fdbe53')); R(x + 27, y - 12, 2, 2, esc('#f4ecd8'));   // a placa com a caneca
                R(x - 6, y - 4, 4, 4, OL); R(x - 5, y - 3, 2, 3, esc('#8a5a32'));   // o barril
                lampiao(x - 2, y - 14);
            } else if (id === 'portao') {
                for (const px of [x - 2, x + 14]) { R(px, y - 18, 5, 18, OL); R(px + 1, y - 17, 3, 17, esc('#8b7d72')); R(px + 1, y - 17, 1, 17, esc('#b8aca2')); R(px - 1, y - 20, 7, 3, OL); }
                R(x + 3, y - 16, 11, 2, OL);
                for (let k = x + 4; k < x + 14; k += 2) { R(k, y - 14, 1, 14, esc('#566c86')); R(k, y - 15, 1, 1, esc('#fdbe53')); }
                R(x + 3, y - 8, 11, 1, esc('#566c86'));
            } else if (id === 'farol') {
                for (let k = 0; k < 5; k++) { R(x - 8 + k * 3, y - 2 - (k % 2) * 2, 6, 6, OL); R(x - 7 + k * 3, y - 1 - (k % 2) * 2, 4, 4, esc('#8b7d72')); }
                for (let k = 0; k < 30; k++) { const w = 9 - Math.floor(k / 8); R(x - w / 2, y - 3 - k, w, 1, k % 8 < 4 ? esc('#f4f1e6') : esc('#d9452f')); R(x - w / 2 - 1, y - 3 - k, 1, 1, OL); R(x + w / 2, y - 3 - k, 1, 1, OL); }
                R(x - 1, y - 14, 2, 3, OL);
                R(x - 4, y - 34, 8, 1, OL); R(x - 3, y - 40, 6, 6, OL); R(x - 2, y - 39, 4, 4, noite > 0.3 ? '#fff2b8' : '#ffe08a'); R(x - 4, y - 42, 8, 2, OL); R(x - 1, y - 44, 2, 2, OL);
                if (noite > 0.3) {   // o facho girando
                    const a = (t / 1100) % (Math.PI * 2), dx = Math.cos(a);
                    g.globalAlpha = noite * 0.3 * Math.abs(dx);
                    for (let k = 0; k < 60; k++) R(x + dx * k, y - 37 - k * 0.04, 2, 2 + k * 0.08, '#fff2b8');
                    g.globalAlpha = 1;
                }
            } else if (id === 'vigia') {
                for (const k of [0, 13]) { R(x + k, y - 12, 2, 12, OL); R(x + k, y - 12, 1, 11, esc('#8a5a32')); }
                for (let k = 0; k < 3; k++) R(x + 2, y - 10 + k * 4, 11, 1, esc('#6e3d1b'));
                parede(x - 1, y - 21, 17, 9, '#b4804e'); telhado(x - 3, y - 26, 21, '#4e8a4c'); janela(x + 6, y - 19);
                R(x + 17, y - 30, 1, 10, OL); R(x + 18, y - 30, 4, 3, esc('#d9452f'));
            } else if (id === 'mercado') {
                for (let k = 0; k < 2; k++) {
                    const mx = x - 13 + k * 15, cor = k ? '#3b6fb6' : '#d9452f';
                    R(mx - 1, y - 14, 15, 5, OL); for (let j = 0; j < 13; j++) R(mx + j, y - 13, 1, 3, esc(Math.floor(j / 2) % 2 ? '#ffffff' : cor));
                    for (let j = 0; j < 13; j += 2) R(mx + j, y - 10, 1, 1, esc(cor));
                    R(mx, y - 9, 1, 9, OL); R(mx + 12, y - 9, 1, 9, OL); R(mx, y - 4, 13, 4, OL); R(mx + 1, y - 3, 11, 3, esc('#b4804e'));
                    for (let j = 0; j < 4; j++) R(mx + 2 + j * 3, y - 5, 2, 1, esc(['#e8434a', '#fdbe53', '#6ab04c', '#f4b7c4'][(j + k) % 4]));
                }
            } else if (id === 'toldo') {
                R(x - 3, y - 15, 26, 4, OL); for (let j = 0; j < 24; j++) R(x - 2 + j, y - 14, 1, 2, esc(j % 4 < 2 ? '#f4ecd8' : '#d6c8a8'));
                for (let j = 0; j < 24; j += 4) R(x - 2 + j, y - 12, 2, 1, esc('#d6c8a8'));
                R(x - 2, y - 11, 1, 11, OL); R(x + 21, y - 11, 1, 11, OL);
                R(x + 4, y - 5, 12, 2, OL); R(x + 5, y - 5, 10, 1, esc('#b4804e')); R(x + 6, y - 3, 1, 3, OL); R(x + 13, y - 3, 1, 3, OL);   // a mesa
                R(x + 7, y - 7, 2, 2, esc('#e8434a')); R(x + 11, y - 7, 2, 2, esc('#f4ecd8'));
            } else if (id === 'ancora') {
                const c = esc('#566c86'), c2 = esc('#8aa0bc');
                R(x - 5, y - 1, 12, 2, OL);
                R(x, y - 18, 3, 16, OL); R(x + 1, y - 17, 1, 15, c2);
                R(x - 4, y - 15, 11, 3, OL); R(x - 3, y - 14, 9, 1, c);
                disco(x + 1, y - 20, 2, OL); R(x + 1, y - 20, 1, 1, c2);
                R(x - 6, y - 5, 15, 3, OL); R(x - 5, y - 4, 13, 1, c); R(x - 7, y - 8, 3, 4, OL); R(x + 8, y - 8, 3, 4, OL); R(x - 6, y - 7, 1, 2, c); R(x + 9, y - 7, 1, 2, c);
            } else if (id === 'canhoes') {
                for (let k = 0; k < 3; k++) {
                    const cx = x - 11 + k * 9; R(cx, y - 6, 8, 4, OL); R(cx + 1, y - 5, 6, 2, esc('#2b2b38')); R(cx + 1, y - 5, 4, 1, esc('#5a5a6e')); R(cx + 6, y - 6, 2, 3, OL);
                    disco(cx + 2, y - 1, 1, esc('#8a5a32')); disco(cx + 6, y - 1, 1, esc('#8a5a32'));
                }
                if (Math.floor(t / 1500) % 6 === 0) { const r = rng(Math.floor(t / 1500)); for (let k = 0; k < 10; k++) R(x - 6 + r() * 26, y - 10 - r() * 18 - ((t % 1500) / 100), 1, 1, ['#e8434a', '#fdbe53', '#79a7e8', '#a7f070'][k % 4]); }
            } else if (id === 'sereia') {
                R(x - 5, y - 3, 13, 4, OL); R(x - 4, y - 2, 11, 2, esc('#a39388')); R(x - 4, y - 2, 11, 1, esc('#c8bcb2'));
                const ou = '#ffd75e', ou2 = '#e8a640';
                R(x - 1, y - 9, 7, 6, OL); R(x, y - 8, 5, 4, ou2); R(x + 5, y - 6, 3, 2, OL); R(x + 5, y - 6, 2, 1, ou);   // o rabo
                R(x - 1, y - 17, 5, 9, OL); R(x, y - 16, 3, 8, ou); R(x - 3, y - 15, 2, 4, OL); R(x - 2, y - 14, 1, 2, ou);   // o corpo e o braço
                disco(x + 1, y - 20, 3, OL); disco(x + 1, y - 20, 2, ou); R(x + 1, y - 20, 1, 1, '#f4f1e6');   // a cabeça com o olho de pérola
                R(x - 2, y - 22, 2, 6, ou2);   // o cabelo
                if (Math.floor(t / 1700) % 4 === 0) R(x + 3, y - 15 - Math.floor(t / 200) % 3, 1, 1, '#ffffff');
            } else if (id === 'cartografo') {
                parede(x, y - 15, 17, 15, '#f1e4c8'); telhado(x - 2, y - 21, 21, '#3b6fb6');
                janela(x + 2, y - 11); porta(x + 10, y - 9, 9);
                R(x + 19, y - 22, 1, 22, OL); disco(x + 19, y - 24, 3, OL); disco(x + 19, y - 24, 2, esc('#79a7e8')); R(x + 18, y - 25, 2, 1, esc('#6ab04c'));   // o globo
                R(x + 3, y - 19, 11, 3, esc('#c9a46a')); R(x + 4, y - 18, 9, 1, '#8a4a2b');   // o mapa na placa
            } else if (id === 'bandeira') {
                R(x, y - 24, 1, 24, OL); R(x - 1, y - 25, 3, 2, '#fdbe53');
                const ond = (k) => Math.round(Math.sin(t / 220 - k / 3));
                for (let k = 0; k < 14; k++) { R(x + 1 + k, y - 23 + ond(k), 1, 9, '#1a1630'); }
                const cx = x + 8, cy = y - 19 + ond(7);
                R(cx - 2, cy - 1, 5, 3, '#f4f1e6'); R(cx - 1, cy + 2, 3, 1, '#f4f1e6'); R(cx - 1, cy, 1, 1, '#1a1630'); R(cx + 1, cy, 1, 1, '#1a1630');
                R(cx - 4, cy + 4, 9, 1, '#e8a640'); R(cx - 3, cy + 3, 1, 1, '#e8a640'); R(cx + 3, cy + 5, 1, 1, '#e8a640');
            }
        }
        // a placa de obra (a próxima): toque nela para abrir as obras
        function placa(x, y, agora) {
            const py = y - 18 + (Math.floor(agora / 400) % 2);
            R(x, py + 8, 2, y - py - 8, OL); R(x, py + 8, 1, y - py - 9, '#8a5a32');
            R(x - 6, py - 1, 14, 10, OL); R(x - 5, py, 12, 8, '#fdbe53'); R(x - 5, py, 12, 1, '#ffe08a');
            R(x - 3, py + 2, 6, 2, OL); R(x - 1, py + 4, 2, 3, OL);   // o martelo
            for (let k = 0; k < 4; k++) R(x - 6 + k * 4, y - 1, 3, 1, k % 2 ? '#1a1630' : '#fdbe53');   // a faixa listrada
            alvos.push({ x: x - 12, y: py - 6, w: 26, h: y - py + 8, acao: 'obra' });
        }

        // o navio (o mesmo do píer e do mar), parado na água com o casco dentro do mar
        // (s = 0,5: lá no cais, mais longe)
        function desenharNavio(nv, x, wl, noite, s = 1) {
            const y = Math.round(wl - nv.agua * s), w = Math.round(nv.width * s), h = Math.round(nv.height * s);
            g.imageSmoothingEnabled = false;
            if (noite > 0) {   // de noite, escurece só o navio (não o retângulo todo)
                tinta.width = w; tinta.height = h;
                const tg = tinta.getContext('2d');
                tg.imageSmoothingEnabled = false; tg.drawImage(nv, 0, 0, w, h);
                tg.globalCompositeOperation = 'source-atop'; tg.globalAlpha = noite * 0.45; tg.fillStyle = '#0e1a3a'; tg.fillRect(0, 0, w, h);
                g.drawImage(tinta, Math.round(x), y);
            } else g.drawImage(nv, Math.round(x), y, w, h);
            const ini = nv.casco ? x + nv.casco.x0 * s - 2 : x, fim = nv.casco ? x + nv.casco.x1 * s + 2 : x + w;
            R(ini, wl + 1, fim - ini, Math.max(2, h - nv.agua * s), mistura(MAR[2], '#0e1a3a', noite * 0.7));
            for (let k = ini; k < fim; k++) if ((k + Math.floor(t / 200)) % 3) R(k, wl + (k % 2), 1, 1, mistura('#e8f2fb', '#5a7aa0', noite));
        }

        function quadro(agora) {
            if (!vivo) return;
            t = agora;
            const noite = (A && A.faseDoDia) ? A.faseDoDia(op.agora()).n : 0, d = op.dados() || { obras: 0 };
            alvos = [];
            const dt = agora - t0, viagem = dt < VIAGEM, nv = op.navio && op.navio();
            ceu(noite);
            mar(noite, viagem);
            if (viagem) {
                // a viagem: a ilha cresce no horizonte e o navio corta o mar, deixando a esteira
                const f = dt / VIAGEM;
                ilhaLonge(f, noite);
                if (nv) {
                    const ent = Math.min(1, f / 0.45), ease = 1 - (1 - ent) ** 3;
                    const x = -nv.width + ease * (LW / 2 + nv.width / 2 - nv.width * 0.15), wl = Math.round(LH * 0.80 + Math.sin(agora / 280) * 1.5);
                    for (let k = 0; k < 26; k++) { const ex = x + (nv.casco ? nv.casco.x0 : 0) - k * 3 - ((agora / 30) % 3), ey = wl + 1 + Math.round(Math.sin(k) * 1) + (k % 2) * Math.floor(k / 4); R(ex, ey, 3, 1, k % 3 ? '#e8f2fb' : '#ffffff'); R(ex, wl + 1 - Math.floor(k / 4), 2, 1, '#cfe4f6'); }
                    desenharNavio(nv, x, wl, noite);
                    const proa = x + nv.width - 4; for (let k = 0; k < 5; k++) R(proa + k, wl - 1 + Math.floor((agora / 80 + k) % 3), 1, 1, '#ffffff');
                }
                if (dt > VIAGEM - CLARAO) { g.globalAlpha = (dt - (VIAGEM - CLARAO)) / CLARAO; R(0, 0, LW, LH, '#f4f8fc'); g.globalAlpha = 1; }
            } else {
                mata(noite);
                caveira(noite);
                trilha(noite);
                areia(noite);
                // as coisas da ilha, de trás para a frente (pela base)
                const coisas = [];
                for (const [fx, alt, fase] of [[0.02, 30, 0], [0.13, 24, 1], [0.56, 22, 2], [0.91, 28, 3], [0.995, 20, 4]]) {
                    const x = X(fx); coisas.push({ y: areiaTopo(x) + 5, f: () => coqueiro(x, areiaTopo(x) + 5, alt, noite, fase) });
                }
                const lista = d.partes || [];
                lista.forEach((p, k) => {
                    if (!LUGAR[p.id]) return;
                    const [x, y] = baseDe(p.id);
                    if (k < d.obras) coisas.push({ y: p.id === 'cais' ? LH * 0.9 : y, f: () => obra(p.id, x, y, noite) });
                    else if (k === d.obras) coisas.push({ y: 999 + y, f: () => placa(x, p.id === 'cais' ? y + 8 : y, agora) });
                });
                // o baú do dia (o X na areia), com o cais pronto
                if (d.obras >= 1 && !d.bau_hoje) {
                    const bx = X(0.58), by = Math.round(LH * 0.69), br = Math.floor(agora / 300) % 2;
                    coisas.push({ y: by, f: () => {
                        for (let k = 0; k < 7; k++) { R(bx + k, by - 6 + k, 2, 1, '#b8321f'); R(bx + 6 - k, by - 6 + k, 2, 1, '#b8321f'); }
                        R(bx + 1, by + 1, 7, 1, '#cdb074');
                        if (br) { R(bx + 10, by - 9, 1, 3, '#ffffff'); R(bx + 9, by - 8, 3, 1, '#ffffff'); }
                        alvos.push({ x: bx - 8, y: by - 14, w: 24, h: 22, acao: 'bau' });
                    } });
                }
                coisas.sort((a, b) => a.y - b.y).forEach((c) => c.f());
                // o navio, no mar da frente, encostado no cais
                if (nv) desenharNavio(nv, X(LUGAR.cais[0]) - 8 - Math.round(nv.width * 0.5), Math.round(LH * 0.815 + Math.sin(agora / 760) * 0.6), noite, 0.5);
                if (dt < VIAGEM + CLARAO) { g.globalAlpha = 1 - (dt - VIAGEM) / CLARAO; R(0, 0, LW, LH, '#f4f8fc'); g.globalAlpha = 1; }
            }
            ctx.imageSmoothingEnabled = false;
            ctx.drawImage(buf, 0, 0, LW, LH, 0, 0, LW * escala * dpr, LH * escala * dpr);
            requestAnimationFrame(quadro);
        }
        requestAnimationFrame(quadro);

        canvas.addEventListener('pointerdown', (e) => {
            e.preventDefault();
            if (performance.now() - t0 < VIAGEM) return;
            const r = canvas.getBoundingClientRect(), x = (e.clientX - r.left) / escala, y = (e.clientY - r.top) / escala;
            const a = alvos.find((k) => x >= k.x && x <= k.x + k.w && y >= k.y && y <= k.y + k.h);
            if (a && a.acao === 'obra') op.obras();
            else if (a && a.acao === 'bau') op.bau();
            else { dica = { texto: 'Toque na placa de obra (o martelo) ou no X da praia.', ate: performance.now() + 2500 }; pintarDica(); }
        });
        raiz.addEventListener('click', (e) => {
            const b = e.target.closest('button');
            if (!b) return;
            if (b.matches('[data-ilha-sair]')) op.sair();
            else if (b.matches('[data-ilha-obras]')) op.obras();
        });
        const tecla = (e) => { if (e.key === 'Escape' && !(op.painelAberto && op.painelAberto())) op.sair(); };
        document.addEventListener('keydown', tecla, true);
        const relogio = setInterval(() => { pintarTopo(); pintarDica(); }, 700);
        pintarTopo(); pintarDica();
        return {
            atualizar() { pintarTopo(); pintarDica(); },
            avisar(texto) { dica = { texto, ate: performance.now() + 3500 }; pintarDica(); },
            fechar() { vivo = false; clearInterval(relogio); window.removeEventListener('resize', redimensionar); document.removeEventListener('keydown', tecla, true); raiz.remove(); }
        };
    }
    window.FazendaIlha = { criar };
})();
