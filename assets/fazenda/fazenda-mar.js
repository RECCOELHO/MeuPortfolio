/* ============================================================
   FAZENDINHA — o alto-mar (fase 62)
   Tocar no barco atracado no píer abre esta cena por cima da fazenda (que para de desenhar):
   o seu barco no mar aberto, o céu da hora do dia, as ondas, as gaivotas e as sombras do
   cardume. A pescaria é ativa: tocar no mar lança a linha; a boia balança (às vezes o peixe só
   belisca, para enganar) e, quando ela afunda de verdade, tocar dentro da janela fisga o peixe.
   Quem sorteia o peixe, a hora da mordida e diz se valeu é o servidor (fazenda_mar_lancar e
   fazenda_mar_fisgar); fazenda.js faz as chamadas e passa as respostas por "op".
   O barco muda de desenho a cada nível. O marinheiro (quando contratado) pesca no barquinho
   dele, mais adiante: tocar nele recolhe o cesto.
   ============================================================ */
(() => {
    'use strict';
    const A = window.FazendaArte;

    // as cores do mar e do céu (as mesmas do litoral da fazenda, mais o fundo)
    const MAR = ['#5b9ad6', '#4a8bcc', '#3a7cc4', '#336fb3', '#2b5f9e', '#244f86'];
    const CEU_DIA = ['#6ec3f0', '#86cff3', '#9fdaf6', '#b8e4f8', '#d2eefb'];
    const CEU_NOITE = ['#0f1530', '#141c3d', '#1b2650', '#233363', '#2d4277'];
    const NOITE_MAR = '#0e1a3a';
    const ESPUMA = '#e8f2fb';

    const hex = (c) => [1, 3, 5].map((i) => parseInt(c.slice(i, i + 2), 16));
    function misturar(c1, c2, t) {
        const a = hex(c1), b = hex(c2);
        return '#' + a.map((v, i) => Math.round(v + (b[i] - v) * t).toString(16).padStart(2, '0')).join('');
    }
    // números "aleatórios" que não mudam de um quadro para o outro
    function rng(seed) {
        let s = seed >>> 0 || 1;
        return () => { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; return s / 4294967296; };
    }

    /* ---------- Os barcos (proa para a direita) ----------
       w = comprimento, h = altura do casco acima da água; convés = topo do casco; pe = onde você
       fica (a partir da popa). Cada um tem o casco, as faixas e o que vai em cima. */
    const BARCOS = {
        1: { w: 34, h: 7, pe: 20, casco: '#9e5f34', borda: '#6e3d1b', faixa: '#f2f2f2', faixaY: 2, fundo: '#7a4a2a' },
        2: { w: 44, h: 9, pe: 30, casco: '#3b6fb6', borda: '#f2f2f2', faixa: '#d9452f', faixaY: 2, fundo: '#29366f' },
        3: { w: 52, h: 10, pe: 37, casco: '#c34b35', borda: '#f2f2f2', faixa: '#f2f2f2', faixaY: 3, fundo: '#9e2a1f' },
        4: { w: 60, h: 11, pe: 44, casco: '#25406e', borda: '#f2f2f2', faixa: '#d9452f', faixaY: 3, fundo: '#1a2a4a' },
        5: { w: 70, h: 12, pe: 53, casco: '#f4f1e6', borda: '#d8d2c0', faixa: '#25406e', faixaY: 6, fundo: '#25406e' }
    };

    function criar(op) {
        const raiz = document.createElement('div');
        raiz.className = 'mar';
        raiz.innerHTML = `
            <canvas class="mar-cena" aria-label="Alto-mar: toque no mar para lançar a linha"></canvas>
            <div class="mar-topo" data-mar-topo></div>
            <p class="mar-dica" data-mar-dica aria-live="polite"></p>`;
        document.body.appendChild(raiz);
        const canvas = raiz.querySelector('canvas'), ctx = canvas.getContext('2d');
        const elTopo = raiz.querySelector('[data-mar-topo]'), elDica = raiz.querySelector('[data-mar-dica]');
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
        }
        redimensionar();
        window.addEventListener('resize', redimensionar);

        // a cena (em pixels "lógicos")
        const horizonte = () => Math.round(LH * 0.38);
        const linhaAgua = () => Math.round(LH * 0.6);
        const nivelBarco = () => Math.max(1, Math.min(5, ((op.dados() || {}).barco || {}).valor | 0 || 1));
        const barcoX = () => Math.max(4, Math.round(LW * 0.06));
        const ondeEstou = () => {   // a sua mão e a ponta da vara
            const b = BARCOS[nivelBarco()], x = barcoX() + b.pe, conves = linhaAgua() - b.h + balanco;
            return { ax: x - 6, ay: conves - 16, mx: x + 4, my: conves - 8, px: x + 20, py: conves - 24 };
        };
        const barquinho = () => ({ x: Math.round(LW * 0.78), y: horizonte() + 12 + Math.round(Math.sin(t / 900) * 1) });

        /* ---------- O jogo ----------
           parado → lancando → esperando (beliscos) → mordendo → puxando → pegou | escapou → parado */
        let estado = 'parado';
        let t = performance.now(), balanco = 0;
        let alvo = null, tLanc = 0, tMordida = 0, janela = 0, tamanho = 1, beliscos = [], tFim = 0;
        let pescado = null;          // { sprite, t0, de, ate } (o peixe pulando para o barco)
        let particulas = [];
        let aneis = [];              // ondinhas em volta da boia
        let dica = null;             // { texto, tipo, ate }
        let vivo = true;

        function mostrarDica(texto, tipo, ms) { dica = { texto, tipo: tipo || '', ate: ms ? performance.now() + ms : 0 }; pintarDica(); }
        function pintarDica() {
            const d = op.dados();
            let texto = dica && (!dica.ate || performance.now() < dica.ate) ? dica.texto : null, tipo = texto ? dica.tipo : '';
            if (!texto) {
                if (estado === 'parado') {
                    const c = op.cardume();
                    texto = !d ? 'O mar está fechado.' : c.n > 0 ? 'Toque no mar para lançar a linha.' : 'O cardume acabou: ele enche sozinho com o tempo.';
                } else if (estado === 'lancando' || estado === 'esperando') texto = 'Espere a boia afundar...';
                else if (estado === 'mordendo') { texto = 'AGORA! Toque para fisgar!'; tipo = 'agora'; }
                else if (estado === 'puxando') texto = 'Puxando...';
                else texto = '';
            }
            if (elDica.textContent !== texto) elDica.textContent = texto;
            elDica.className = 'mar-dica' + (tipo ? ' ' + tipo : '');
        }
        // o topo muda a cada segundo (a contagem do cardume): não troca no meio de um toque num botão
        let segurando = false, topoAtual = '';
        function pintarTopo() {
            if (segurando) return;
            const html = op.htmlTopo();
            if (html !== topoAtual) { topoAtual = html; elTopo.innerHTML = html; }
        }
        elTopo.addEventListener('pointerdown', () => { segurando = true; });
        const soltar = () => { if (segurando) { segurando = false; setTimeout(pintarTopo, 50); } };
        document.addEventListener('pointerup', soltar);
        document.addEventListener('pointercancel', soltar);

        function pontoNaAgua(cx, cy) {
            const r = canvas.getBoundingClientRect();
            const x = (cx - r.left) / escala, y = (cy - r.top) / escala;
            const b = BARCOS[nivelBarco()], minX = barcoX() + b.w + 14, minY = linhaAgua() + 8, maxY = LH - 34;
            if (x >= minX && x <= LW - 8 && y >= minY && y <= maxY) return { x: Math.round(x), y: Math.round(y) };
            return { x: Math.round(Math.max(minX + 6, LW * 0.72)), y: Math.round(linhaAgua() + (LH - linhaAgua()) * 0.3) };
        }

        async function lancar(cx, cy) {
            const d = op.dados();
            if (!d) return;
            if (op.cardume().n < 1) { op.som('erro'); mostrarDica(`O cardume acabou: o próximo peixe chega em ${op.proximo()}.`, 'erro', 3500); return; }
            alvo = pontoNaAgua(cx, cy);
            estado = 'lancando'; tLanc = performance.now(); dica = null;
            op.som('plantar');
            pintarDica();
            let r;
            try { r = await op.lancar(); } catch (e) { if (!vivo) return; estado = 'parado'; pintarDica(); pintarTopo(); return; }
            if (!vivo) return;
            const chegou = performance.now();
            tMordida = chegou + (r.espera_ms || 2500);
            janela = r.janela_ms || 900;
            tamanho = r.tamanho || 1;
            // os beliscos: a boia mexe um pouco, mas ainda não é a hora (tocar agora espanta o peixe)
            beliscos = [];
            const nb = Math.floor(Math.random() * 3), ini = Math.max(chegou, tLanc + 500) + 300, fim = tMordida - 450;
            for (let k = 0; k < nb && fim > ini; k++) beliscos.push(ini + Math.random() * (fim - ini));
            estado = 'esperando';
            pintarTopo(); pintarDica();
        }

        function escapar(motivo) {
            estado = 'escapou'; tFim = performance.now() + 1300;
            espirrar(alvo.x, alvo.y, 6, 0.6);
            op.som('erro');
            mostrarDica(motivo === 'cedo' ? 'Cedo demais: o peixe fugiu! Espere a boia afundar.' : 'Escapou! Toque logo que a boia afundar.', 'erro', 2200);
        }

        async function fisgar() {
            estado = 'puxando'; tFim = 0;
            pintarDica();
            let r;
            try { r = await op.fisgar(); } catch (e) { if (!vivo) return; estado = 'parado'; pintarDica(); return; }
            if (!vivo) return;
            if (!r || !r.pegou) return escapar(r && r.motivo);
            const pt = ondeEstou();
            pescado = { sprite: op.sprite(r.peixe), t0: performance.now(), de: { x: alvo.x, y: alvo.y }, ate: { x: pt.mx - 4, y: pt.my - 18 } };
            estado = 'pegou'; tFim = performance.now() + 1500;
            espirrar(alvo.x, alvo.y, 10 + tamanho * 2, 1);
            mostrarDica(op.textoPeixe(r), 'pegou', 2600);
            op.pegou(r);
            pintarTopo();
        }

        function tocar(cx, cy) {
            // o barquinho do marinheiro: recolhe o cesto
            const d = op.dados();
            if (d && d.marinheiro) {
                const r = canvas.getBoundingClientRect(), x = (cx - r.left) / escala, y = (cy - r.top) / escala, bq = barquinho();
                if (x >= bq.x - 6 && x <= bq.x + 26 && y >= bq.y - 26 && y <= bq.y + 8) { op.recolher(); return; }
            }
            if (estado === 'parado') lancar(cx, cy);
            else if (estado === 'esperando') escapar('cedo');
            else if (estado === 'mordendo') fisgar();
        }

        raiz.addEventListener('click', (e) => {
            const b = e.target.closest('button, [data-mar-recolher]');
            if (b) {
                if (b.matches('[data-mar-sair]')) op.sair();
                else if (b.matches('[data-mar-melhorar]')) op.melhorar();
                else if (b.matches('[data-mar-recolher]')) op.recolher();
                return;
            }
        });
        canvas.addEventListener('pointerdown', (e) => { e.preventDefault(); tocar(e.clientX, e.clientY); });
        function tecla(e) {
            if (op.painelAberto && op.painelAberto()) return;
            if (e.key === 'Escape') { op.sair(); return; }
            if (e.key === ' ' || e.key === 'Enter') {
                if (document.activeElement && document.activeElement.closest && document.activeElement.closest('button')) return;
                e.preventDefault();
                const r = canvas.getBoundingClientRect();
                tocar(r.left + r.width * 0.72, r.top + r.height * 0.75);
            }
        }
        document.addEventListener('keydown', tecla, true);   // (antes do Escape de fazenda.js: com painel aberto, ele fecha só o painel)

        function espirrar(x, y, n, forca) {
            for (let k = 0; k < n; k++) {
                const a = Math.PI * (0.15 + 0.7 * Math.random());
                const v = (0.03 + Math.random() * 0.05) * forca;
                particulas.push({ x, y, vx: Math.cos(a) * v * (Math.random() < 0.5 ? -1 : 1), vy: -Math.sin(a) * v * 1.6, t0: performance.now(), vida: 500 + Math.random() * 400 });
            }
            aneis.push({ x, y, t0: performance.now(), forte: forca >= 1 });
        }

        /* ---------- Desenho ---------- */
        const ret = (x, y, w, h, cor) => { g.fillStyle = cor; g.fillRect(Math.round(x), Math.round(y), w, h); };
        const estrelas = (() => { const r = rng(7); return Array.from({ length: 40 }, () => ({ x: r(), y: r(), b: r() })); })();
        const ondas = (() => { const r = rng(11); return Array.from({ length: 70 }, () => ({ x: r(), y: r(), l: 2 + Math.floor(r() * 5), v: 0.004 + r() * 0.01, c: r() })); })();
        const nuvens = (() => { const r = rng(5); return Array.from({ length: 4 }, () => ({ x: r(), y: 0.15 + r() * 0.5, w: 14 + Math.floor(r() * 16), v: 0.0015 + r() * 0.002 })); })();
        const sombras = (() => { const r = rng(3); return Array.from({ length: 8 }, () => ({ x: r(), y: r(), v: (0.004 + r() * 0.006) * (r() < 0.5 ? -1 : 1), f: r() * 6 })); })();

        function desenharCeu(noite) {
            const hy = horizonte(), faixa = Math.ceil(hy / CEU_DIA.length);
            CEU_DIA.forEach((c, i) => ret(0, i * faixa, LW, faixa + 1, misturar(c, CEU_NOITE[i], noite)));
            if (noite > 0.25) {
                g.globalAlpha = Math.min(1, (noite - 0.25) * 1.5);
                for (const s of estrelas) {
                    const pisca = Math.sin(t / 700 + s.b * 20) > 0.6 ? '#ffffff' : '#c0cbdc';
                    ret(s.x * LW, s.y * hy * 0.9, 1, 1, pisca);
                }
                g.globalAlpha = 1;
            }
            // o sol de dia, a lua de noite (os dois mudam devagar na virada)
            const cx = Math.round(LW * 0.82), cy = Math.round(hy * 0.32);
            if (noite < 0.5) {
                g.globalAlpha = 1 - noite * 2;
                ret(cx - 4, cy - 6, 8, 12, '#ffe08a'); ret(cx - 6, cy - 4, 12, 8, '#ffe08a'); ret(cx - 5, cy - 5, 10, 10, '#ffe08a');
                ret(cx - 3, cy - 4, 6, 8, '#fff3c4'); ret(cx - 4, cy - 3, 8, 6, '#fff3c4');
                g.globalAlpha = 1;
            } else {
                g.globalAlpha = (noite - 0.5) * 2;
                ret(cx - 3, cy - 5, 6, 10, '#f2f2e6'); ret(cx - 5, cy - 3, 10, 6, '#f2f2e6'); ret(cx - 4, cy - 4, 8, 8, '#f2f2e6');
                ret(cx - 1, cy - 2, 2, 2, '#c0cbdc'); ret(cx + 2, cy + 1, 1, 1, '#c0cbdc');
                g.globalAlpha = 1;
            }
            // nuvens indo devagar
            for (const n of nuvens) {
                const x = ((n.x * (LW + 60) + t * n.v) % (LW + 60)) - 40, y = Math.round(n.y * hy);
                const cor = misturar('#ffffff', '#5a6a99', noite * 0.8), sombra = misturar('#dbe9f5', '#3d4a77', noite * 0.8);
                ret(x + 3, y, n.w - 6, 3, cor); ret(x, y + 2, n.w, 3, cor); ret(x + 5, y - 2, Math.round(n.w * 0.4), 2, cor);
                ret(x + 1, y + 4, n.w - 2, 1, sombra);
            }
        }

        function desenharIlha(noite) {
            // no barco 5 dá para ver a primeira ilha (nível 46, em breve)
            const hy = horizonte(), x = Math.round(LW * 0.42);
            const areia = misturar('#e8cf8f', '#4a4a5a', noite * 0.7), verde = misturar('#3e8948', '#1e3a2a', noite * 0.7);
            ret(x, hy - 2, 26, 2, areia); ret(x + 3, hy - 3, 20, 1, areia);
            ret(x + 5, hy - 5, 14, 2, verde); ret(x + 8, hy - 6, 8, 1, verde);
            // o coqueiro
            const tronco = misturar('#8a5a2b', '#3a2a20', noite * 0.7);
            ret(x + 17, hy - 12, 1, 7, tronco); ret(x + 18, hy - 13, 1, 2, tronco);
            ret(x + 14, hy - 14, 4, 1, verde); ret(x + 18, hy - 14, 4, 1, verde); ret(x + 13, hy - 13, 2, 1, verde); ret(x + 21, hy - 13, 2, 1, verde);
            ret(x + 17, hy - 15, 2, 1, verde);
        }

        function desenharMar(noite) {
            const hy = horizonte(), alturas = [0.06, 0.09, 0.13, 0.18, 0.24, 0.30];
            let y = hy;
            const total = LH - hy;
            MAR.forEach((c, i) => {
                const h = i === MAR.length - 1 ? LH - y : Math.round(total * alturas[i]);
                ret(0, y, LW, h, misturar(c, NOITE_MAR, noite * 0.65));
                y += h;
            });
            ret(0, hy, LW, 1, misturar('#d8eefc', '#36508a', noite));   // o brilho do horizonte
            // as sombras do cardume (quantas mais, mais peixe para pescar)
            const n = Math.min(sombras.length, Math.ceil(op.cardume().n / 3));
            const cor = misturar('#1f4a7a', '#0a1428', noite * 0.6);
            for (let k = 0; k < n; k++) {
                const s = sombras[k];
                const yy = linhaAgua() + 12 + s.y * (LH - linhaAgua() - 40);
                const xx = ((s.x * (LW + 30) + t * s.v * 3) % (LW + 30) + LW + 30) % (LW + 30) - 15;
                const rabo = Math.sin(t / 200 + s.f) > 0 ? 1 : 0;
                ret(xx, yy, 6, 2, cor); ret(xx + (s.v > 0 ? -2 : 6), yy + rabo, 2, 1, cor);
            }
            // as ondinhas (as de perto são maiores e andam mais)
            for (const o of ondas) {
                const yy = hy + 2 + Math.pow(o.y, 1.4) * (LH - hy - 4);
                const perto = (yy - hy) / (LH - hy);
                const l = Math.max(1, Math.round(o.l * (0.5 + perto)));
                const xx = ((o.x * (LW + 20) + t * o.v * (0.4 + perto)) % (LW + 20)) - 10;
                const cor = o.c > 0.85 ? misturar(ESPUMA, '#6a7fb0', noite) : misturar('#6fa8e0', '#25407a', noite * 0.7);
                const sobe = Math.sin(t / 600 + o.x * 30) > 0 ? 0 : 1;
                ret(xx, yy + sobe, l, 1, cor);
            }
        }

        function gaivotas(noite) {
            if (noite > 0.6) return;
            const hy = horizonte();
            g.globalAlpha = 1 - noite;
            for (let k = 0; k < 2; k++) {
                const x = ((t * (0.012 + k * 0.005) + k * 70) % (LW + 30)) - 15, y = hy * (0.45 + k * 0.18) + Math.sin(t / 500 + k) * 3;
                const asa = Math.floor(t / 180 + k) % 2;
                const c = '#3f2631';
                ret(x, y, 1, 1, c); ret(x - 1, y - 1 + asa, 1, 1, c); ret(x - 2, y - 1 + asa * 2, 1, 1, c);
                ret(x + 1, y - 1 + asa, 1, 1, c); ret(x + 2, y - 1 + asa * 2, 1, 1, c);
            }
            g.globalAlpha = 1;
        }

        function casco(x, wl, b) {
            for (let r = 0; r <= b.h + 2; r++) {
                const y = wl - b.h + r;
                const esq = x + Math.round(r * 0.35), dir = x + b.w - Math.round(Math.max(0, r - 1) * 1.6);
                if (dir <= esq) continue;
                const cor = r === 0 ? b.borda : r >= b.faixaY && r < b.faixaY + (b.faixaY > 4 ? 6 : 1) ? b.faixa : r > b.h - 2 ? b.fundo : b.casco;
                ret(esq, y, dir - esq, 1, cor);
                ret(esq - 1, y, 1, 1, '#3f2631'); ret(dir, y, 1, 1, '#3f2631');
            }
            ret(x - 1, wl - b.h - 1, b.w + 2, 1, '#3f2631');
        }

        function desenharBarco(noite) {
            const n = nivelBarco(), b = BARCOS[n], x = barcoX(), wl = linhaAgua() + balanco, topo = wl - b.h;
            // o que vai em cima do casco (atrás de você)
            if (n === 1) {
                // remo encostado e o banquinho
                ret(x + 8, topo - 3, 10, 3, '#7a4a2a'); ret(x + 8, topo - 3, 10, 1, '#9e5f34');
                for (let k = 0; k < 9; k++) ret(x + 4 + k, topo - 9 + k, 1, 1, '#b8692f');
            } else if (n === 2) {
                ret(x + 4, topo - 11, 13, 11, '#f4f1e6'); ret(x + 3, topo - 12, 15, 2, '#d9452f');
                ret(x + 7, topo - 8, 6, 3, '#79a7e8'); ret(x + 4, topo - 11, 1, 11, '#d8d2c0');
                ret(x + 23, topo - 22, 2, 22, '#5a3a20');                       // mastro
                for (let k = 0; k < 13; k++) ret(x + 24 + k, topo - 20 + Math.round(k * 0.7), 1, 1, '#7a4a2a');   // a lança
                for (let k = 0; k < 4; k++) ret(x + 34 + (k % 2), topo - 11 + k * 2, 1, 1, '#c0cbdc');            // a rede
                ret(x + 25, topo - 21, 6, 4, '#d9452f');                        // bandeirinha
            } else if (n === 3) {
                ret(x + 5, topo - 13, 19, 13, '#f4f1e6'); ret(x + 4, topo - 14, 21, 2, '#566c86');
                [8, 13, 18].forEach((wx) => ret(x + wx, topo - 10, 3, 3, '#25406e'));
                ret(x + 6, topo - 5, 4, 4, '#e38628'); ret(x + 7, topo - 4, 2, 2, '#f4f1e6');   // boia salva-vidas
                ret(x + 11, topo - 22, 1, 8, '#3f2631'); ret(x + 9, topo - 20, 5, 1, '#3f2631');   // antena
                for (let k = 0; k < 14; k += 2) ret(x + 27 + k, topo - 3, 1, 3, '#c0cbdc');      // guarda-corpo
                ret(x + 27, topo - 3, 22, 1, '#c0cbdc');
            } else if (n === 4) {
                ret(x + 5, topo - 14, 24, 14, '#f4f1e6'); ret(x + 4, topo - 15, 26, 2, '#d9452f');
                ret(x + 9, topo - 22, 16, 8, '#f4f1e6'); ret(x + 8, topo - 23, 18, 2, '#566c86');
                [8, 13, 18, 23].forEach((wx) => ret(x + wx, topo - 11, 3, 3, '#25406e'));
                [12, 17].forEach((wx) => ret(x + wx, topo - 20, 4, 3, '#25406e'));
                ret(x + 16, topo - 28, 1, 6, '#3f2631'); ret(x + 14, topo - 27, 5, 1, '#3f2631');
                ret(x + 33, topo - 20, 2, 20, '#e38628');                       // o guindaste
                for (let k = 0; k < 13; k++) ret(x + 34 + k, topo - 20 + Math.round(k * 0.45), 1, 1, '#e38628');
                ret(x + 46, topo - 14, 1, 7, '#c0cbdc'); ret(x + 45, topo - 8, 3, 2, '#566c86');
                if (noite > 0.3) { ret(x + 6, topo - 16, 1, 1, '#ffe08a'); ret(x + 28, topo - 16, 1, 1, '#ffe08a'); }
            } else {
                ret(x + 6, topo - 16, 32, 16, '#f4f1e6'); ret(x + 5, topo - 17, 34, 2, '#d8d2c0');
                ret(x + 8, topo - 12, 28, 4, '#1a1630');                        // a janela corrida da ponte
                ret(x + 12, topo - 25, 22, 8, '#f4f1e6'); ret(x + 11, topo - 26, 24, 2, '#d8d2c0');
                ret(x + 14, topo - 23, 18, 3, '#1a1630');
                ret(x + 20, topo - 31, 6, 5, '#ffffff'); ret(x + 19, topo - 30, 8, 3, '#ffffff'); ret(x + 20, topo - 31, 6, 1, '#c0cbdc');   // o radar
                ret(x + 31, topo - 38, 1, 12, '#3f2631');                       // mastro com a bandeira
                ret(x + 32, topo - 38, 6, 4, '#4e974c'); ret(x + 34, topo - 37, 2, 2, '#ffe08a');
                for (let k = 0; k < 20; k += 2) ret(x + 42 + k, topo - 3, 1, 3, '#c0cbdc');
                ret(x + 42, topo - 3, 24, 1, '#c0cbdc');
                if (noite > 0.3) { ret(x + 9, topo - 11, 2, 2, '#ffe08a'); ret(x + 26, topo - 11, 2, 2, '#ffe08a'); ret(x + 31, topo - 39, 1, 1, '#ff6b6b'); }
            }
            casco(x, wl, b);
            if (n === 5) [12, 20, 28].forEach((px) => { ret(x + px, wl - 4, 2, 2, '#79a7e8'); });   // as escotilhas
            // você, com a vara
            const pt = ondeEstou();
            const av = A.avatarCanvas(op.avatar());
            if (av) g.drawImage(av, Math.round(pt.ax), Math.round(pt.ay));
            const curva = estado === 'mordendo' || estado === 'puxando' ? 4 : 0;
            const tipX = pt.px, tipY = pt.py + curva;
            for (let k = 0; k <= 16; k++) {
                const f = k / 16;
                ret(pt.mx + (tipX - pt.mx) * f, pt.my + (tipY - pt.my) * f + Math.sin(f * Math.PI) * curva * 0.5, 1, 1, k > 12 ? '#c98a4b' : '#8a4a2b');
            }
            // a água por cima do fundo do casco (o barco está dentro do mar)
            g.globalAlpha = 0.55;
            ret(x - 2, wl + 1, b.w + 4, 2, misturar(MAR[3], NOITE_MAR, noite * 0.65));
            g.globalAlpha = 1;
            for (let xx = x - 3; xx < x + b.w + 4; xx += 2) ret(xx, wl + (Math.floor((xx + t / 120) / 3) % 2), 2, 1, misturar(ESPUMA, '#6a7fb0', noite));
            return { tipX, tipY };
        }

        function desenharMarinheiro(noite) {
            const d = op.dados();
            if (!d || !d.marinheiro) return;
            const bq = barquinho();
            // o bote dele, pequeno, mais longe
            ret(bq.x, bq.y - 3, 20, 3, misturar('#9e5f34', '#3a2a20', noite * 0.5)); ret(bq.x + 1, bq.y, 17, 1, '#6e3d1b');
            ret(bq.x - 1, bq.y - 4, 22, 1, '#3f2631');
            A.desenharTile(g, 120, bq.x + 3, bq.y - 19, false, 'factory');
            for (let k = 0; k < 10; k++) ret(bq.x + 13 + k, bq.y - 12 - Math.round(k * 0.6), 1, 1, '#8a4a2b');
            const by = bq.y + 3 + (Math.floor(t / 650) % 2);
            for (let k = 0; k <= 6; k++) ret(bq.x + 23 + Math.round(k * 0.3), bq.y - 18 + Math.round((by - bq.y + 18) * (k / 6)), 1, 1, 'rgba(255,255,255,.6)');
            ret(bq.x + 25, by, 2, 1, '#e8434a');
            for (let xx = bq.x - 2; xx < bq.x + 22; xx += 2) ret(xx, bq.y + 1, 1, 1, misturar(ESPUMA, '#6a7fb0', noite));
            // o balão com peixe quando o cesto tem peixe
            const c = op.cesto();
            if (c && c.n > 0) {
                const px = bq.x - 2, py = bq.y - 40 + (Math.floor(t / 350) % 2);
                ret(px, py, 20, 17, '#3f2631'); ret(px + 1, py + 1, 18, 15, '#ffffff'); ret(px + 7, py + 17, 4, 2, '#3f2631'); ret(px + 8, py + 16, 2, 2, '#ffffff');
                A.desenharTile(g, op.sprite(c.ultimo || 'sardinha'), px + 2, py + 1);
                if (c.n >= c.max && Math.floor(t / 300) % 3) ret(px + 17, py - 2, 2, 2, '#ffe08a');
            }
        }

        function desenharLinha(ponta) {
            if (!alvo || estado === 'parado') return;
            const agora = performance.now();
            let bx = alvo.x, by = alvo.y, voando = false;
            const dur = 450;
            if (estado === 'lancando' || (estado === 'esperando' && agora < tLanc + dur)) {
                const f = Math.min(1, (agora - tLanc) / dur);
                bx = ponta.tipX + (alvo.x - ponta.tipX) * f;
                by = ponta.tipY + (alvo.y - ponta.tipY) * f - Math.sin(f * Math.PI) * 24;
                voando = f < 1;
                if (f >= 1 && !alvo.caiu) { alvo.caiu = true; aneis.push({ x: alvo.x, y: alvo.y, t0: agora }); }
            }
            if (estado === 'puxando' || estado === 'pegou' || estado === 'escapou') {
                const f = Math.min(1, (agora - (tFim ? tFim - (estado === 'pegou' ? 1500 : 1300) : agora)) / 500);
                bx = alvo.x + (ponta.tipX - alvo.x) * f; by = alvo.y + (ponta.tipY + 6 - alvo.y) * f;
            }
            // a boia: balança; belisca; afunda na mordida
            let dy = Math.floor(t / 600) % 2;
            const belisca = beliscos.some((b) => agora >= b && agora < b + 220);
            if (estado === 'esperando' && belisca) dy = 1 + (Math.floor(t / 70) % 2);
            const afundou = estado === 'mordendo';
            if (afundou) dy = 2 + Math.min(2, Math.floor((agora - tMordida) / 120));
            // a linha (curva até a boia)
            const passos = 18;
            for (let k = 0; k <= passos; k++) {
                const f = k / passos;
                const x = ponta.tipX + (bx - ponta.tipX) * f, y = ponta.tipY + (by + dy - ponta.tipY) * f + (voando ? 0 : Math.sin(f * Math.PI) * 4);
                ret(x, y, 1, 1, 'rgba(255,255,255,.75)');
            }
            if (!(estado === 'pegou' && agora > tFim - 1000)) {
                if (!afundou || dy < 4) ret(bx - 1, by + dy - 1, 3, 2, '#e8434a');
                if (!afundou) ret(bx - 1, by + dy + 1, 3, 1, '#ffffff');
            }
            if (afundou) {
                // o "!" em cima e as bolhinhas
                const pisca = Math.floor(t / 120) % 2;
                ret(bx - 1, by - 14, 3, 6, pisca ? '#e8434a' : '#ffffff'); ret(bx - 1, by - 7, 3, 2, pisca ? '#e8434a' : '#ffffff');
                ret(bx - 2, by - 15, 5, 1, '#3f2631'); ret(bx - 2, by - 5, 5, 1, '#3f2631');
                if (Math.floor(t / 90) % 3 === 0) ret(bx + 2 + (Math.floor(t / 90) % 4), by - 1, 1, 1, ESPUMA);
            }
        }

        function desenharEfeitos() {
            const agora = performance.now();
            aneis = aneis.filter((a) => agora - a.t0 < 900);
            for (const a of aneis) {
                const f = (agora - a.t0) / 900, rx = 3 + f * (a.forte ? 14 : 9), ry = rx * 0.35;
                g.globalAlpha = 1 - f;
                for (let k = 0; k < 24; k++) {
                    const ang = (k / 24) * Math.PI * 2;
                    ret(a.x + Math.cos(ang) * rx, a.y + 1 + Math.sin(ang) * ry, 1, 1, ESPUMA);
                }
                g.globalAlpha = 1;
            }
            particulas = particulas.filter((p) => agora - p.t0 < p.vida);
            for (const p of particulas) {
                const dt = agora - p.t0;
                ret(p.x + p.vx * dt, p.y + p.vy * dt + 0.00012 * dt * dt, 1, 1, dt < p.vida * 0.6 ? '#ffffff' : '#bcd8f2');
            }
            if (pescado) {
                const f = Math.min(1, (agora - pescado.t0) / 900);
                if (f < 1) {
                    const x = pescado.de.x + (pescado.ate.x - pescado.de.x) * f - 8;
                    const y = pescado.de.y + (pescado.ate.y - pescado.de.y) * f - Math.sin(f * Math.PI) * 30 - 8;
                    A.desenharTile(g, pescado.sprite, x, y, true);
                } else {
                    // segura o peixe um pouquinho em cima da cabeça
                    const pt = ondeEstou();
                    if (agora < pescado.t0 + 1500) A.desenharTile(g, pescado.sprite, pt.ax, pt.ay - 15 + (Math.floor(t / 150) % 2), true);
                    else pescado = null;
                }
            }
        }

        function quadro(agora) {
            if (!vivo) return;
            t = agora;
            balanco = Math.round(Math.sin(agora / 700) * 1.2);
            if (estado === 'esperando' && agora >= tMordida) {
                estado = 'mordendo';
                espirrar(alvo.x, alvo.y, 4 + tamanho, 0.5);
                op.som('cuidar');
                try { if (navigator.vibrate) navigator.vibrate(tamanho >= 5 ? [70, 40, 110] : 70); } catch { /* sem vibrar */ }
                pintarDica();
            }
            if (estado === 'mordendo' && agora > tMordida + janela) escapar('tarde');
            if ((estado === 'pegou' || estado === 'escapou') && agora >= tFim) { estado = 'parado'; pintarDica(); }
            if (dica && dica.ate && agora >= dica.ate) { dica = null; pintarDica(); }

            const noite = A.faseDoDia(op.agora()).n;
            desenharCeu(noite);
            if (nivelBarco() >= 5) desenharIlha(noite);
            gaivotas(noite);
            desenharMar(noite);
            desenharMarinheiro(noite);
            const ponta = desenharBarco(noite);
            desenharLinha(ponta);
            desenharEfeitos();

            ctx.imageSmoothingEnabled = false;
            ctx.drawImage(buf, 0, 0, LW, LH, 0, 0, LW * escala * dpr, LH * escala * dpr);
            requestAnimationFrame(quadro);
        }
        requestAnimationFrame(quadro);
        const relogio = setInterval(() => { pintarTopo(); pintarDica(); }, 1000);
        pintarTopo(); pintarDica();

        return {
            atualizar() { pintarTopo(); pintarDica(); },
            fechar() {
                vivo = false;
                clearInterval(relogio);
                window.removeEventListener('resize', redimensionar);
                document.removeEventListener('keydown', tecla, true);
                document.removeEventListener('pointerup', soltar);
                document.removeEventListener('pointercancel', soltar);
                raiz.remove();
            }
        };
    }

    window.FazendaMar = { criar };
})();
