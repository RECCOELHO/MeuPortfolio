/* ============================================================
   FAZENDINHA — a Invasão de Varginha (fase 94)
   A sala do evento, por cima da fazenda (que para de desenhar): o céu da noite sobre os morros de
   Varginha, a nave brilhando lá em cima e os ETs descendo pelo feixe de luz, do jeito da lenda de
   1996 (pele marrom, olhos vermelhos grandes e três calombos na cabeça). Embaixo, os fazendeiros de
   quem está na sala. Tocar num ET faz o seu fazendeiro atirar nele; os tiros dos outros aparecem
   também. Os ETs têm número e hora certos, iguais para todos e iguais ao servidor
   (fazenda_invasao_alien): o jogo só desenha. Quem conta os pontos é o servidor (fazenda_invasao_lote):
   o jogo junta os toques e manda a cada 2,5 s; fazenda.js faz a chamada e passa a resposta por "op".
   ============================================================ */
(() => {
    'use strict';
    const A = window.FazendaArte;
    const LOTE_MS = 2500;

    // o ET de Varginha (9×12): b contorno, B pele, R olho, w brilho do olho, m boca
    const ET = [
        '..b.b.b..',
        '.bBbBbBb.',
        'bBBBBBBBb',
        'bRRRBRRRb',
        'bRwRBRwRb',
        '.bRBBBRb.',
        '..bBmBb..',
        '...bBb...',
        '..bBBBb..',
        '.bBbBbBb.',
        '..bB.Bb..',
        '..bb.bb..'
    ];
    const COR_ET = { b: '#2e1a0e', B: '#8a5a32', R: '#e3261c', w: '#ffd8cf', m: '#2e1a0e' };
    const COR_CHEFE = { b: '#1e0f22', B: '#6d4a8a', R: '#ff3b2f', w: '#ffffff', m: '#1e0f22' };
    const COR_OURO = { b: '#5a3a00', B: '#ffd23f', R: '#ff8a00', w: '#fffbe0', m: '#5a3a00' };   // fase 98: o ET dourado

    // números "aleatórios" que não mudam de um quadro para o outro
    function rng(seed) {
        let s = seed >>> 0 || 1;
        return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
    }
    // a faixa de cada ET (igual para todos os jogadores)
    const faixa = (k) => ((k * 2654435761) % 4294967296) / 4294967296;

    // um ET: igual a fazenda_invasao_alien no servidor (k >= 100000: o chefão da hora k - 100000)
    function etDe(k, R) {
        const ini = Date.parse(R.inicio), fim = Date.parse(R.fim), dur = fim - ini;
        if (k >= 100000) {
            const b = k - 100000, seg = b * R.chefe_a_cada + R.chefe_atraso;
            if (seg * 1000 >= dur) return null;
            const nasce = ini + seg * 1000;
            return { k, nasce, morre: Math.min(nasce + R.vida_chefe * 1000, fim), hp: R.hp_chefe + b * R.hp_chefe_por_hora, chefe: true };
        }
        const seg = k * R.intervalo;
        if (k < 0 || seg * 1000 >= dur) return null;
        const nasce = ini + seg * 1000;
        return { k, nasce, morre: nasce + R.vida * 1000, hp: R.hp_base + Math.floor(seg / 3600) * R.hp_por_hora, chefe: false };
    }
    // os ETs na tela no momento t
    function vivos(t, R) {
        const ini = Date.parse(R.inicio), lista = [];
        const k1 = Math.floor((t - ini) / (R.intervalo * 1000)), k0 = Math.max(0, Math.ceil((t - ini - R.vida * 1000) / (R.intervalo * 1000)));
        for (let k = k0; k <= k1; k++) { const e = etDe(k, R); if (e && t >= e.nasce && t < e.morre) lista.push(e); }
        const b = Math.floor((t - ini - R.chefe_atraso * 1000) / (R.chefe_a_cada * 1000));
        if (b >= 0) { const e = etDe(100000 + b, R); if (e && t >= e.nasce && t < e.morre) lista.push(e); }
        return lista;
    }

    function criar(op) {
        const raiz = document.createElement('div');
        raiz.className = 'mar invasao';
        raiz.innerHTML = `
            <canvas class="mar-cena" aria-label="Invasão de Varginha: toque nos ETs para atirar"></canvas>
            <div class="mar-topo" data-invasao-topo></div>
            <p class="mar-dica" data-invasao-dica aria-live="polite"></p>`;
        document.body.appendChild(raiz);
        const canvas = raiz.querySelector('canvas'), ctx = canvas.getContext('2d');
        const elTopo = raiz.querySelector('[data-invasao-topo]'), elDica = raiz.querySelector('[data-invasao-dica]');
        const buf = document.createElement('canvas'), g = buf.getContext('2d');
        let LW = 140, LH = 280, escala = 3, dpr = 1;

        function redimensionar() {
            dpr = Math.min(window.devicePixelRatio || 1, 3);
            const W = window.innerWidth, H = window.innerHeight;
            escala = Math.max(2, Math.min(6, Math.round(Math.min(W / 150, H / 250))));
            LW = Math.ceil(W / escala); LH = Math.ceil(H / escala);
            buf.width = LW; buf.height = LH;
            canvas.width = Math.round(W * dpr); canvas.height = Math.round(H * dpr);
            canvas.style.width = W + 'px'; canvas.style.height = H + 'px';
            montarFundo();
        }

        /* ---------- o fundo: céu, estrelas, lua, morros com as luzes da cidade e o pasto ---------- */
        let fundo = null;
        const chao = () => Math.round(LH * 0.8);
        function montarFundo() {
            fundo = document.createElement('canvas'); fundo.width = LW; fundo.height = LH;
            const f = fundo.getContext('2d'), r = rng(1996);
            const ceu = ['#070a1f', '#0d1030', '#161544', '#231a55', '#33215e', '#45286a'];
            const hor = Math.round(LH * 0.66);
            for (let y = 0; y < hor; y++) { f.fillStyle = ceu[Math.min(ceu.length - 1, Math.floor(y / hor * ceu.length))]; f.fillRect(0, y, LW, 1); }
            for (let n = 0; n < LW * LH / 90; n++) { f.fillStyle = r() < 0.2 ? '#ffe9b0' : '#cfd8ff'; f.fillRect(Math.floor(r() * LW), Math.floor(r() * hor * 0.9), 1, 1); }
            // a lua
            const lx = Math.round(LW * 0.14), ly = Math.round(LH * 0.09);
            f.fillStyle = '#f4ecd0'; for (let y = -5; y <= 5; y++) for (let x = -5; x <= 5; x++) if (x * x + y * y <= 26) f.fillRect(lx + x, ly + y, 1, 1);
            f.fillStyle = '#d9cfae'; f.fillRect(lx - 2, ly - 1, 2, 2); f.fillRect(lx + 2, ly + 2, 1, 1);
            // os morros de Varginha, com as luzinhas das casas
            for (const [base, amp, cor, seed] of [[hor - 10, 7, '#1b1f45', 7], [hor - 3, 5, '#15183a', 11]]) {
                const rr = rng(seed);
                const fases = [rr() * 6, rr() * 6];
                for (let x = 0; x < LW; x++) {
                    const top = Math.round(base - amp * (0.6 * Math.sin(x / 19 + fases[0]) + 0.4 * Math.sin(x / 7 + fases[1])));
                    f.fillStyle = cor; f.fillRect(x, top, 1, LH - top);
                    if (rr() < 0.12) { f.fillStyle = rr() < 0.5 ? '#ffd66b' : '#ffb347'; f.fillRect(x, top + 2 + Math.floor(rr() * 6), 1, 1); }
                }
            }
            // o pasto e a cerca
            const c = chao() - 22;
            f.fillStyle = '#1f3a24'; f.fillRect(0, c, LW, LH - c);
            f.fillStyle = '#2b4d2e'; for (let x = 0; x < LW; x += 3) f.fillRect(x + (x % 2), c + Math.floor(r() * 4), 1, 2);
            f.fillStyle = '#5b3a24';
            for (let x = 2; x < LW; x += 12) f.fillRect(x, c - 7, 2, 8);
            f.fillRect(0, c - 5, LW, 1); f.fillRect(0, c - 2, LW, 1);
        }
        redimensionar();
        window.addEventListener('resize', redimensionar);

        /* ---------- a nave ---------- */
        const naveX = (t) => Math.round(LW / 2 + Math.sin(t / 4200) * LW * 0.22);
        const naveY = (t) => Math.round(Math.max(26, LH * 0.15) + Math.sin(t / 650) * 1.5);
        const fimFeixe = () => Math.round(LH * 0.32);
        function desenharNave(t) {
            const x = naveX(t), y = naveY(t), pulso = 0.5 + 0.5 * Math.sin(t / 300);
            // o feixe (mais forte quando um ET está saindo)
            const R = op.regras(), desde = (t - Date.parse(R.inicio)) % (R.intervalo * 1000), forte = desde < 500 ? 1 - desde / 500 : 0;
            g.globalAlpha = 0.12 + 0.08 * pulso + 0.2 * forte;
            g.fillStyle = '#a8ffcf';
            const y0 = y + 5, y1 = fimFeixe();
            for (let yy = y0; yy < y1; yy++) { const w = 7 + (yy - y0) * 0.45; g.fillRect(Math.round(x - w), yy, Math.round(w * 2), 1); }
            g.globalAlpha = 1;
            // o brilho embaixo
            g.globalAlpha = 0.35 + 0.25 * pulso; g.fillStyle = '#7dffb8';
            g.fillRect(x - 14, y + 3, 28, 3); g.globalAlpha = 1;
            // o disco
            for (let dy = -3; dy <= 3; dy++) {
                const w = Math.round(24 * Math.sqrt(1 - (dy / 4) ** 2));
                g.fillStyle = dy < 0 ? '#c9d3e0' : dy === 0 ? '#e9eef5' : dy < 2 ? '#8d99ab' : '#5d6878';
                g.fillRect(x - w, y + dy, w * 2, 1);
            }
            // a cúpula
            for (let dy = -8; dy < -2; dy++) {
                const w = Math.round(9 * Math.sqrt(1 - ((dy + 2) / 6.5) ** 2));
                g.fillStyle = dy < -6 ? '#c8f6ff' : '#6fd8f5'; g.fillRect(x - w, y + dy, w * 2, 1);
            }
            g.fillStyle = '#ffffff'; g.fillRect(x - 4, y - 6, 2, 1);
            // as luzes da borda, girando
            const cores = ['#ff4d4d', '#ffd84d', '#6aff6a', '#4de1ff'];
            for (let i = 0; i < 10; i++) {
                const a = i / 10 * Math.PI * 2 + t / 500, lx = Math.round(x + Math.cos(a) * 20), ly = Math.round(y + Math.sin(a) * 1.5);
                if (Math.sin(a) < -0.2) continue;
                g.fillStyle = cores[(i + Math.floor(t / 250)) % 4]; g.fillRect(lx, ly, 2, 1);
            }
            return { x, y };
        }

        /* ---------- os ETs ---------- */
        function onde(e, t) {
            const R = op.regras(), u = Math.max(0, Math.min(1, (t - e.nasce) / (e.morre - e.nasce)));
            const sx = naveX(e.nasce), sy = naveY(e.nasce) + 6, by = fimFeixe();
            if (e.chefe) {
                const desce = Math.min(1, (t - e.nasce) / 6000);
                return { x: Math.round(sx + (LW / 2 - sx) * desce + Math.sin(t / 1300) * LW * 0.25 * desce), y: Math.round(sy + (LH * 0.4 - sy) * desce + Math.sin(t / 500) * 2), u, s: 3 };
            }
            const destino = 10 + faixa(e.k) * (LW - 20), queda = 1.1 / R.vida;
            if (u < queda) { const q = u / queda; return { x: Math.round(sx), y: Math.round(sy + (by - sy) * q * q), u, s: 1 }; }
            const v = (u - queda) / (1 - queda), ease = v < 0.3 ? v / 0.3 : 1;
            return { x: Math.round(sx + (destino - sx) * Math.min(1, ease * (2 - ease)) + Math.sin(t / 300 + e.k) * 1.5),
                     y: Math.round(by + (chao() - 38 - by) * v), u, s: 1 };
        }
        function desenharEt(e, p, t, feito) {
            const pal = e.chefe ? COR_CHEFE : COR_ET, s = p.s, w = ET[0].length * s, h = ET.length * s;
            const x0 = p.x - Math.floor(w / 2), y0 = p.y - h;
            g.globalAlpha = p.u > 0.94 ? (1 - p.u) / 0.06 : 1;
            if (e.chefe) {   // a aura do chefão
                g.globalAlpha *= 0.35 + 0.2 * Math.sin(t / 200); g.fillStyle = '#c77dff';
                g.fillRect(x0 - 3, y0 - 3, w + 6, h + 6); g.globalAlpha = 1;
            }
            const pisca = Math.floor((t + e.k * 137) / 180) % 9 === 0;   // os olhos piscando
            ET.forEach((linha, y) => [...linha].forEach((ch, x) => {
                if (ch === '.') return;
                const c = pisca && (ch === 'R' || ch === 'w') ? pal.b : pal[ch];
                g.fillStyle = c; g.fillRect(x0 + x * s, y0 + y * s, s, s);
            }));
            // a vida (o dano que VOCÊ já fez nele)
            if (feito > 0 && !e.chefe) {
                const bw = 9, f = Math.max(0, 1 - feito / hpDe(e));
                g.fillStyle = '#2e1a0e'; g.fillRect(x0, y0 - 3, bw, 2);
                g.fillStyle = f > 0.5 ? '#6aff6a' : f > 0.25 ? '#ffd84d' : '#ff4d4d'; g.fillRect(x0, y0 - 3, Math.max(1, Math.round(bw * f)), 2);
            }
            g.globalAlpha = 1;
            return { x0, y0, w, h };
        }

        /* ---------- quem está na sala ---------- */
        const fileira = (i) => chao() - (i % 2 ? 6 : 0);
        function lugarDe(j, i) { return { x: Math.round(10 + j.x * (LW - 20)), y: fileira(i) }; }
        function desenharFazendeiro(av, x, y, eu) {
            const cv = A.avatarCanvas(av);
            if (eu) { g.globalAlpha = 0.5; g.fillStyle = '#ffe08a'; g.fillRect(x - 9, y - 1, 18, 2); g.globalAlpha = 1; }
            g.drawImage(cv, x - 8, y - 16);
        }
        function desenharDrone(x, y, t) {
            const yy = y + Math.round(Math.sin(t / 220 + x) * 1.5);
            g.fillStyle = '#3f4b5c'; g.fillRect(x - 3, yy, 7, 2);
            g.fillStyle = Math.floor(t / 80) % 2 ? '#c9d3e0' : '#8d99ab'; g.fillRect(x - 5, yy - 1, 3, 1); g.fillRect(x + 3, yy - 1, 3, 1);
            g.fillStyle = '#6aff6a'; g.fillRect(x, yy + 2, 1, 1);
        }

        /* ---------- tiros, explosões e números ---------- */
        let tiros = [], pedacos = [], textos = [];
        function atirar(de, para, cor, t, quando) { tiros.push({ de, para, cor, t0: quando || t, dur: 160 }); }
        function explodir(x, y, n, cor, t) {
            const r = rng(Math.floor(t) + x * 31 + y);
            for (let i = 0; i < n; i++) pedacos.push({ x, y, vx: (r() - 0.5) * 0.12, vy: (r() - 0.9) * 0.1, t0: t, cor: cor || (r() < 0.5 ? '#7dff6a' : '#b6ff9e') });
        }
        function numero(x, y, txt, cor, t) { textos.push({ x, y, txt, cor, t0: t }); }

        /* ---------- o jogo: toques, saldo, lote ---------- */
        let pend = {}, feito = {}, mortos = new Set(), saldo = 5, ultSaldo = performance.now(), ultRelogio = 0;
        // fase 98: o ET dourado ("ainda tá aí?"): o número dele em que você tocou (vai no próximo lote) e
        // o último que você tocou (some da tela na hora, sem esperar o servidor)
        let ouroPend = 0, ouroTocado = 0, ouroCaixa = null;
        let vivo = true, enviando = false, ultTiroOutros = new Map();
        let dica = { texto: 'Toque nos ETs!', ate: 0 };
        const eu = () => op.eu() || {};
        // fase 99: a ameaça. A vida de cada ET é multiplicada pelos SEUS pontos (o servidor manda eu.mult)
        const hpDe = (e) => Math.ceil(e.hp * (Number(eu().mult) || 1));
        const bonusDe = (n) => Math.round(n * (Number(eu().mult) || 1));
        function mostrarDica(texto, ms) { dica = { texto, ate: ms ? performance.now() + ms : 0 }; pintarDica(); }
        function pintarDica() { elDica.textContent = dica.texto || ''; elDica.className = 'mar-dica'; }
        function pintarTopo() { elTopo.innerHTML = op.htmlTopo(); }

        let alvosNaTela = [];   // [{ e, caixa }] do último quadro, para o toque achar o ET
        function tocar(ev) {
            if (op.painelAberto()) return;
            const r = canvas.getBoundingClientRect();
            const lx = (ev.clientX - r.left) / escala, ly = (ev.clientY - r.top) / escala;
            // fase 98: o ET dourado vem antes de tudo
            const o = eu().ouro;
            if (o && ouroCaixa && o.n !== ouroTocado) {
                const c = ouroCaixa, folga = 6;
                if (lx >= c.x0 - folga && lx <= c.x0 + c.w + folga && ly >= c.y0 - folga && ly <= c.y0 + c.h + folga) {
                    const t = op.agora();
                    ouroTocado = o.n; ouroPend = o.n;
                    explodir(c.x0 + c.w / 2, c.y0 + c.h / 2, 30, '#ffd23f', t);
                    numero(c.x0 + c.w / 2, c.y0 - 4, `DOURADO! +${op.regras().bonus_ouro || 50}`, '#ffd23f', t);
                    op.som('festa');
                    mostrarDica('Boa! Pode continuar.', 1500);
                    setTimeout(lote, 60);
                    return;
                }
            }
            if (eu().pausado && !(o && o.n === ouroTocado)) { mostrarDica('Toque no ET DOURADO primeiro!', 1500); return; }
            let melhor = null, dist = 1e9;
            for (const a of alvosNaTela) {
                const c = a.caixa, folga = a.e.chefe ? 4 : 7;
                if (lx < c.x0 - folga || lx > c.x0 + c.w + folga || ly < c.y0 - folga || ly > c.y0 + c.h + folga) continue;
                const d = Math.hypot(lx - (c.x0 + c.w / 2), ly - (c.y0 + c.h / 2));
                if (d < dist) { dist = d; melhor = a; }
            }
            if (!melhor) return;
            const t = op.agora(), agoraP = performance.now();
            saldo = Math.min(op.regras().toques_max, saldo + (agoraP - ultSaldo) / 1000 * op.regras().toques_seg); ultSaldo = agoraP;
            const de = { x: Math.round(LW / 2), y: chao() - 12 }, para = { x: melhor.caixa.x0 + melhor.caixa.w / 2, y: melhor.caixa.y0 + melhor.caixa.h / 2 };
            if (saldo < 1) { mostrarDica('Calma! O forcado está esquentando…', 900); return; }
            saldo -= 1;
            const e = melhor.e, k = String(e.k), dano = Math.min(eu().por_toque || 1, hpDe(e) - (feito[k] || 0));
            if (dano <= 0) return;
            pend[k] = (pend[k] || 0) + 1;
            feito[k] = (feito[k] || 0) + dano;
            atirar(de, para, '#ffe08a', t);
            numero(para.x, para.y - 4, '+' + dano, '#ffe08a', t);
            op.som('tiro');
            if (feito[k] >= hpDe(e)) {
                mortos.add(k);
                explodir(para.x, para.y, e.chefe ? 40 : 12, null, t);
                numero(para.x, para.y - 10, e.chefe ? `CHEFÃO! +${bonusDe(op.regras().bonus_chefe)}` : `+${bonusDe(op.regras().bonus_abate)}`, '#7dff6a', t);
                op.som(e.chefe ? 'festa' : 'et');
            }
            try { if (navigator.vibrate) navigator.vibrate(12); } catch { /* sem vibrar */ }
        }
        canvas.addEventListener('pointerdown', tocar);
        // para os testes (Playwright): onde está cada ET na tela agora
        canvas.alvos = () => alvosNaTela.map((x) => ({ k: x.e.k, x: (x.caixa.x0 + x.caixa.w / 2) * escala, y: (x.caixa.y0 + x.caixa.h / 2) * escala }));
        canvas.ouro = () => (ouroCaixa ? { x: (ouroCaixa.x0 + ouroCaixa.w / 2) * escala, y: (ouroCaixa.y0 + ouroCaixa.h / 2) * escala } : null);
        elTopo.addEventListener('click', (ev) => {
            if (ev.target.closest('[data-invasao-sair]')) op.sair();
            else if (ev.target.closest('[data-invasao-armas]')) op.armas();
            else if (ev.target.closest('[data-invasao-placar]')) op.placar();
        });

        async function lote() {
            if (!vivo || enviando) return;
            enviando = true;
            const manda = pend, ouro = ouroPend; pend = {}; ouroPend = 0;
            try {
                const r = await op.lote(manda, ouro);
                if (!vivo || !r) return;
                // o que o servidor diz que você já fez em cada ET (o que ele não aceitou volta a aparecer)
                const g2 = (r.eu && r.eu.golpes) || {}, R = op.regras(), t0 = op.agora();
                for (const k of Object.keys(feito)) {
                    const e = etDe(Number(k), R);
                    if (!e || e.morre < t0 - 5000) { delete feito[k]; mortos.delete(k); continue; }   // já saiu da tela
                    if (k in pend) continue;
                    feito[k] = g2[k] || 0;
                    if (feito[k] < hpDe(e)) mortos.delete(k);   // o servidor não contou: o ET volta
                }
                for (const [k, v] of Object.entries(g2)) feito[k] = Math.max(feito[k] || 0, v);
                if (r.ganhou > 0) numero(LW / 2, chao() - 24, `+${r.ganhou} pontos`, '#fff3b0', op.agora());
                // os tiros dos outros, espalhados até o próximo lote
                const t = op.agora(), meu = op.meuId();
                ((r.sala && r.sala.jogadores) || []).forEach((j, i) => {
                    if (j.id === meu || !j.qtd) return;
                    const n = Math.min(10, j.qtd);
                    for (let q = 0; q < n; q++) ultTiroOutros.set(j.id + ':' + q, { de: lugarDe(j, i), alvo: j.alvo, quando: t + q * (LOTE_MS / n), feito: false });
                });
                pintarTopo();
            } catch (e) {
                if (ouro && !ouroPend) ouroPend = ouro;   // não chegou: manda de novo no próximo
                if (vivo) op.erro(e);
            } finally {
                enviando = false;
            }
        }
        const relogioLote = setInterval(lote, LOTE_MS);
        setTimeout(lote, 200);   // entra na sala já

        /* ---------- cada quadro ---------- */
        function quadro() {
            if (!vivo) return;
            const t = op.agora(), R = op.regras();
            g.drawImage(fundo, 0, 0);
            desenharNave(t);
            // os ETs
            alvosNaTela = [];
            let chefe = null;
            for (const e of vivos(t, R)) {
                const k = String(e.k);
                if (mortos.has(k)) continue;
                const p = onde(e, t), caixa = desenharEt(e, p, t, feito[k] || 0);
                alvosNaTela.push({ e, caixa });
                if (e.chefe) chefe = { e, caixa };
            }
            // fase 98: o ET dourado (só seu), num lugar sorteado pelo servidor
            ouroCaixa = null;
            const ouro = eu().ouro;
            if (ouro && ouro.n !== ouroTocado) {
                const s = 2, w = ET[0].length * s, h = ET.length * s;
                const x0 = Math.round(Math.max(4, Math.min(LW - w - 4, ouro.x * LW - w / 2))), y0 = Math.round(Math.max(LH * 0.2, Math.min(chao() - h - 30, ouro.y * LH - h / 2)) + Math.sin(t / 220) * 2);
                const brilho = 0.35 + 0.25 * Math.sin(t / 130);
                g.globalAlpha = brilho; g.fillStyle = '#fff2a8'; g.fillRect(x0 - 4, y0 - 4, w + 8, h + 8); g.globalAlpha = 1;
                ET.forEach((linha, y) => [...linha].forEach((ch, x) => { if (ch !== '.') { g.fillStyle = COR_OURO[ch]; g.fillRect(x0 + x * s, y0 + y * s, s, s); } }));
                ouroCaixa = { x0, y0, w, h };
            }
            // quem está na sala (você no meio, na frente)
            const sala = op.sala(), meu = op.meuId(), lista = ((sala && sala.jogadores) || []).filter((j) => j.id !== meu);
            lista.forEach((j, i) => {
                const l = lugarDe(j, i);
                desenharFazendeiro(j.avatar, l.x, l.y, false);
                if (j.armas && j.armas.drone) desenharDrone(l.x + 6, l.y - 24, t);
            });
            const ex = Math.round(LW / 2), ey = chao() + 4;
            desenharFazendeiro(op.avatar(), ex, ey, true);
            const minhas = eu().armas || {};
            if (minhas.drone) desenharDrone(ex + 9, ey - 26, t);
            if (minhas.espantalho) { g.fillStyle = '#c9a46a'; g.fillRect(ex - 18, ey - 12, 2, 12); g.fillStyle = '#e38628'; g.fillRect(ex - 20, ey - 14, 6, 3); }
            if (minhas.trator) { g.fillStyle = '#c34b35'; g.fillRect(ex + 12, ey - 6, 9, 5); g.fillStyle = '#2b2b38'; g.fillRect(ex + 12, ey - 1, 3, 2); g.fillRect(ex + 18, ey - 1, 3, 2); g.fillRect(ex + 20, ey - 9, 2, 4); }
            // as automáticas atiram sozinhas (desenho; os pontos são do servidor)
            if (eu().auto_ligado && eu().por_seg > 0 && alvosNaTela.length && t - ultRelogio > Math.max(180, 1400 / Math.sqrt(eu().por_seg))) {
                ultRelogio = t;
                const a = alvosNaTela[Math.floor((t / 97) % alvosNaTela.length)], para = { x: a.caixa.x0 + a.caixa.w / 2, y: a.caixa.y0 + a.caixa.h / 2 };
                const de = minhas.drone ? { x: ex + 9, y: ey - 26 } : minhas.trator ? { x: ex + 20, y: ey - 9 } : { x: ex - 17, y: ey - 13 };
                atirar(de, para, '#7de3ff', t);
                explodir(para.x, para.y, 3, '#7de3ff', t);
            }
            // os tiros dos outros na hora marcada
            for (const [id, s] of ultTiroOutros) {
                if (t < s.quando) continue;
                ultTiroOutros.delete(id);
                let a = alvosNaTela.find((x) => x.e.k === s.alvo) || alvosNaTela[Math.floor(Math.random() * alvosNaTela.length)];
                if (!a) continue;
                const para = { x: a.caixa.x0 + a.caixa.w / 2, y: a.caixa.y0 + a.caixa.h / 2 };
                atirar({ x: s.de.x, y: s.de.y - 12 }, para, '#9fe3ff', t);
                explodir(para.x, para.y, 2, '#9fe3ff', t);
            }
            // tiros, pedaços e números
            tiros = tiros.filter((s) => t - s.t0 < s.dur);
            for (const s of tiros) {
                const f = (t - s.t0) / s.dur, x = s.de.x + (s.para.x - s.de.x) * f, y = s.de.y + (s.para.y - s.de.y) * f;
                g.fillStyle = s.cor; g.fillRect(Math.round(x), Math.round(y), 2, 2);
                g.globalAlpha = 0.4; g.fillRect(Math.round(x - (s.para.x - s.de.x) * 0.06), Math.round(y - (s.para.y - s.de.y) * 0.06), 1, 1); g.globalAlpha = 1;
            }
            pedacos = pedacos.filter((p) => t - p.t0 < 700);
            for (const p of pedacos) {
                const d = t - p.t0; g.globalAlpha = 1 - d / 700; g.fillStyle = p.cor;
                g.fillRect(Math.round(p.x + p.vx * d), Math.round(p.y + p.vy * d + 0.00012 * d * d), 1, 1);
            }
            g.globalAlpha = 1;

            ctx.imageSmoothingEnabled = false;
            ctx.drawImage(buf, 0, 0, LW, LH, 0, 0, LW * escala * dpr, LH * escala * dpr);

            // por cima, na resolução da tela: os nomes, os números e a barra do chefão
            const k = escala * dpr;
            ctx.textAlign = 'center'; ctx.textBaseline = 'bottom';
            ctx.font = `700 ${Math.round(9 * dpr)}px Nunito, sans-serif`;
            lista.slice(0, 24).forEach((j, i) => {
                const l = lugarDe(j, i); ctx.lineWidth = 3 * dpr; ctx.strokeStyle = 'rgba(14,10,30,.85)'; ctx.fillStyle = '#e6ecff';
                ctx.strokeText(j.apelido, l.x * k, (l.y - 17) * k); ctx.fillText(j.apelido, l.x * k, (l.y - 17) * k);
            });
            ctx.font = `800 ${Math.round(11 * dpr)}px Nunito, sans-serif`; ctx.fillStyle = '#ffe08a'; ctx.strokeStyle = 'rgba(14,10,30,.9)';
            ctx.strokeText('Você', ex * k, (ey - 17) * k); ctx.fillText('Você', ex * k, (ey - 17) * k);
            textos = textos.filter((s) => t - s.t0 < 900);
            ctx.font = `800 ${Math.round(13 * dpr)}px 'Jersey 10', Nunito, sans-serif`;
            for (const s of textos) {
                const d = (t - s.t0) / 900; ctx.globalAlpha = 1 - d; ctx.fillStyle = s.cor;
                ctx.strokeText(s.txt, s.x * k, (s.y - d * 10) * k); ctx.fillText(s.txt, s.x * k, (s.y - d * 10) * k);
            }
            ctx.globalAlpha = 1;
            if (chefe) {
                const e = chefe.e, f = Math.max(0, 1 - (feito[String(e.k)] || 0) / hpDe(e)), W = canvas.width * 0.6, X = canvas.width * 0.2, Y = canvas.height * 0.27;
                ctx.fillStyle = 'rgba(14,10,30,.75)'; ctx.fillRect(X - 4 * dpr, Y - 22 * dpr, W + 8 * dpr, 34 * dpr);
                ctx.fillStyle = '#3b1f4a'; ctx.fillRect(X, Y, W, 8 * dpr);
                ctx.fillStyle = '#c77dff'; ctx.fillRect(X, Y, W * f, 8 * dpr);
                ctx.font = `800 ${Math.round(14 * dpr)}px 'Jersey 10', Nunito, sans-serif`; ctx.fillStyle = '#fff'; ctx.textBaseline = 'bottom';
                ctx.fillText(`ET CHEFÃO! ${Math.max(0, hpDe(e) - (feito[String(e.k)] || 0))}/${hpDe(e)} · sai em ${Math.max(0, Math.ceil((e.morre - t) / 1000))} s`, canvas.width / 2, Y - 3 * dpr);
            }
            desenharOuroAviso(t, k);
            const PAUSA = 'Pausado: toque no ET DOURADO para voltar a pontuar!', pausou = eu().pausado && ouroCaixa;
            if (pausou && !dica.ate && dica.texto !== PAUSA) mostrarDica(PAUSA, 0);
            else if (!pausou && dica.texto === PAUSA) mostrarDica('Toque nos ETs!', 0);
            if (dica.ate && performance.now() > dica.ate) mostrarDica(alvosNaTela.length ? 'Toque nos ETs!' : 'Os ETs estão vindo…', 0);
            requestAnimationFrame(quadro);
        }
        // fase 98: o contador em cima do ET dourado e, se pausou, o aviso grande
        function desenharOuroAviso(t, k) {
            const o = eu().ouro;
            if (!ouroCaixa || !o || o.n === ouroTocado) return;
            const c = ouroCaixa, falta = Math.max(0, Math.ceil((Date.parse(o.ate) - t) / 1000));
            ctx.textAlign = 'center'; ctx.textBaseline = 'bottom'; ctx.lineWidth = 3 * dpr; ctx.strokeStyle = 'rgba(40,24,0,.9)';
            ctx.font = `800 ${Math.round(14 * dpr)}px 'Jersey 10', Nunito, sans-serif`; ctx.fillStyle = '#ffd23f';
            const txt = eu().pausado ? 'TOQUE AQUI!' : `TOQUE! ${falta}s`;
            ctx.strokeText(txt, (c.x0 + c.w / 2) * k, (c.y0 - 6) * k); ctx.fillText(txt, (c.x0 + c.w / 2) * k, (c.y0 - 6) * k);
            if (eu().pausado) {
                const Y = canvas.height * 0.13;
                ctx.fillStyle = 'rgba(40,24,0,.82)'; ctx.fillRect(canvas.width * 0.06, Y - 26 * dpr, canvas.width * 0.88, 40 * dpr);
                ctx.font = `800 ${Math.round(20 * dpr)}px 'Jersey 10', Nunito, sans-serif`; ctx.fillStyle = '#ffd23f';
                ctx.fillText('PAUSADO: TOQUE NO ET DOURADO!', canvas.width / 2, Y + 8 * dpr);
            }
        }
        requestAnimationFrame(quadro);
        const relogioTopo = setInterval(pintarTopo, 1000);
        pintarTopo(); pintarDica();

        return {
            atualizar() { pintarTopo(); },
            fechar() {
                vivo = false;
                clearInterval(relogioLote); clearInterval(relogioTopo);
                window.removeEventListener('resize', redimensionar);
                canvas.removeEventListener('pointerdown', tocar);
                raiz.remove();
            }
        };
    }

    window.FazendaInvasao = { criar, etDe, vivos };
})();
