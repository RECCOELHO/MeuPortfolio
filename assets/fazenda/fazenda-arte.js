/* ============================================================
   FAZENDINHA SECRETA — arte e cena
   Pixel art do pacote "Tiny Farm" do Kenney (CC0, kenney.nl),
   desenhada num <canvas>. Os ícones pequenos (moeda, XP, praga...)
   são desenhados aqui mesmo, na mesma paleta do pacote.

   Expõe window.FazendaArte com:
     carregar()              → Promise quando a arte estiver pronta
     criarCena(canvas, cb)   → motor da cena (mapa, canteiros, animais)
     htmlTile(i, px)         → <span> com um sprite do pacote (para a UI)
     htmlIcone(nome, px)     → <img> com um ícone pixel
     cultura(id)             → sprites de cada fase de uma cultura
============================================================ */
(function () {
    'use strict';

    const T = 16;           // tamanho do tile
    const COLS = 12;        // colunas do atlas
    const LINHAS = 11;

    const PAL = {
        o: '#3f2631', g: '#84c669', G: '#4e974c', l: '#c6e58d', y: '#fdbe53', Y: '#e38628',
        r: '#c34b35', R: '#aa2c23', b: '#99d8f8', B: '#79a7e8', w: '#ffffff', p: '#d176d0',
        P: '#9b4ca3', s: '#c0cbdc', S: '#8b9bb4', k: '#fec99c', t: '#eaa56c', d: '#cf8254', n: '#763b36'
    };

    /* ---------- Sprites do pacote por cultura ----------
       fases: [broto, crescendo, quase pronto/maduro], murcho, item colhido, semente (loja) */
    const CULTURAS = {
        alface:   { fases: [52, 53, 54], murcho: 55, item: 56, semente: 58 },
        cenoura:  { fases: [4, 5, 6],    murcho: 7,  item: 8,  semente: 10 },
        batata:   { fases: [16, 17, 18], murcho: 19, item: 20, semente: 22 }, // arte: beterraba
        milho:    { fases: [28, 29, 30], murcho: 31, item: 32, semente: 34 },
        tomate:   { fases: [40, 41, 42], murcho: 43, item: 44, semente: 46 },
        girassol: { fases: [81, 80, 83], murcho: 67, item: 83, semente: 74 },
        abobora:  { fases: [64, 65, 66], murcho: 67, item: 68, semente: 70 }, // arte: trigo
        morango:  { fases: [81, 39, 78], murcho: 43, item: 78, semente: 74 }  // arte: amora
    };
    const CULTURA_PADRAO = CULTURAS.alface;

    /* ---------- Ícones pixel (mesma paleta) ---------- */
    const ICONES = {
        moeda: [
            '..oooo..',
            '.oyyyyo.',
            'oywyyyYo',
            'oywyYyYo',
            'oyyyYyYo',
            'oyyyyYYo',
            '.oYYYYo.',
            '..oooo..'
        ],
        xp: [
            '....o....',
            '...oyo...',
            '..oywyo..',
            'oooywyooo',
            'oyyyyyyYo',
            '.oyyyyYo.',
            '.oyyoyYo.',
            'oyYo.oYYo',
            'ooo...ooo'
        ],
        praga: [
            '.o.....o.',
            '..o...o..',
            '..ooooo..',
            '.oPwpPPo.',
            'oPpPPPpPo',
            'oPPPPPPPo',
            '.oPPpPPo.',
            '..ooooo..'
        ],
        seco: [
            '...o...',
            '..obo..',
            '..obo..',
            '.obbbo.',
            'obwbbbo',
            'obwbbBo',
            'obbbbBo',
            '.oBBBo.',
            '..ooo..'
        ],
        erva: [
            '.o.....o.',
            'oGo.o.oGo',
            'oGgoGogGo',
            '.oGgGgGo.',
            '..oGgGo..',
            '...oGo...',
            '...oGo...',
            '....o....'
        ],
        cadeado: [
            '..ooo..',
            '.o...o.',
            '.o...o.',
            'ooooooo',
            'oyyyyyo',
            'oyyoyyo',
            'oyyoyyo',
            'oYYYYYo',
            'ooooooo'
        ],
        check: [
            '......oo',
            '.....oGo',
            'oo..oGo.',
            'oGooGo..',
            '.oGGo...',
            '..oo....'
        ],
        brilho: [
            '..w..',
            '..w..',
            'ww.ww',
            '..w..',
            '..w..'
        ],
        mao: [
            '..o.o.o..',
            '.oko.oko.',
            '.okokoko.',
            'ooko.okoo',
            'okkkkkkko',
            'okkkkkkko',
            '.okkkkko.',
            '..ooooo..'
        ],
        coracao: [
            '.oo.oo.',
            'orrorRo',
            'orwrrRo',
            'orrrrRo',
            '.orrRo.',
            '..oRo..',
            '...o...'
        ]
    };

    const icones = {};
    function montarIcones() {
        for (const [nome, linhas] of Object.entries(ICONES)) {
            const c = document.createElement('canvas');
            c.width = Math.max(...linhas.map((l) => l.length));
            c.height = linhas.length;
            const x = c.getContext('2d');
            linhas.forEach((linha, yy) => [...linha].forEach((ch, xx) => {
                if (PAL[ch]) { x.fillStyle = PAL[ch]; x.fillRect(xx, yy, 1, 1); }
            }));
            icones[nome] = c;
        }
    }
    montarIcones();

    const urls = {};
    function iconeURL(nome) {
        if (urls[nome]) return urls[nome];
        const src = icones[nome];
        const c = document.createElement('canvas');
        c.width = src.width * 4; c.height = src.height * 4;
        const x = c.getContext('2d');
        x.imageSmoothingEnabled = false;
        x.drawImage(src, 0, 0, c.width, c.height);
        return (urls[nome] = c.toDataURL());
    }

    function htmlIcone(nome, px = 18) {
        const src = icones[nome];
        const h = Math.round(px * src.height / src.width);
        return `<img class="px-ico" src="${iconeURL(nome)}" width="${px}" height="${h}" alt="">`;
    }

    function htmlTile(i, px = 32) {
        const c = i % COLS, l = Math.floor(i / COLS);
        return `<span class="px-spr" style="width:${px}px;height:${px}px;background-size:${COLS * px}px ${LINHAS * px}px;background-position:-${c * px}px -${l * px}px" aria-hidden="true"></span>`;
    }

    /* ---------- Atlas ---------- */
    const atlas = new Image();
    let atlasPronto = null;
    function carregar() {
        if (!atlasPronto) {
            atlasPronto = new Promise((ok, erro) => {
                atlas.onload = ok;
                atlas.onerror = () => erro(new Error('Não deu para carregar a arte da fazenda.'));
                atlas.src = 'assets/fazenda/tiny-farm.png';
            });
        }
        return atlasPronto;
    }

    function tile(ctx, i, x, y, flip) {
        const sx = (i % COLS) * T, sy = Math.floor(i / COLS) * T;
        if (flip) {
            ctx.save();
            ctx.translate(x + T, y);
            ctx.scale(-1, 1);
            ctx.drawImage(atlas, sx, sy, T, T, 0, 0, T, T);
            ctx.restore();
        } else {
            ctx.drawImage(atlas, sx, sy, T, T, x, y, T, T);
        }
    }

    function icone(ctx, nome, x, y) {
        ctx.drawImage(icones[nome], Math.round(x), Math.round(y));
    }

    /* ---------- Gerador pseudoaleatório estável (decoração não "pula") ---------- */
    function rng(seed) {
        let s = seed >>> 0 || 1;
        return () => {
            s ^= s << 13; s >>>= 0;
            s ^= s >> 17;
            s ^= s << 5; s >>>= 0;
            return s / 4294967296;
        };
    }

    /* ---------- Layouts (em tiles, relativos ao "núcleo" da fazenda) ---------- */
    const CELEIRO = [
        [null, 82, null],
        [93, 94, 95],
        [105, 106, 107],
        [117, 118, 119],
        [[90, 129], [91, 130], [92, 131]],
        [114, 126, 116]
    ];

    const LAYOUTS = {
        paisagem: {
            w: 18, h: 8,
            celeiro: { x: 0, y: 0 },
            campo: { x: 6, y: 2 },
            casaFazendeiro: { x: 4, y: 5 },
            terra: [{ x: 0, y: 6, w: 4, h: 2 }],
            cercas: [],
            objetos: [
                { i: 110, x: 14, y: 2 }, { i: 111, x: 15, y: 2 },
                { i: 96, x: 3, y: 4 }, { i: 85, x: 3, y: 5 }, { i: 73, x: 0, y: 7 },
                { i: 47, x: 12, y: 5 }, { i: 11, x: 12, y: 4 },
                { i: 83, x: 6, y: 0 }, { i: 83, x: 8, y: 0 }, { i: 83, x: 10, y: 0 }, { i: 78, x: 16, y: 6 }, { i: 78, x: 13, y: 1 }
            ],
            pasto: { x: 13, y: 3, w: 4, h: 3 },
            galinhas: { x: 0, y: 6, w: 5, h: 2 }
        },
        retrato: {
            w: 9, h: 13,
            celeiro: { x: 0, y: 0 },
            campo: { x: 1, y: 8 },
            casaFazendeiro: { x: 4, y: 6 },
            terra: [{ x: 0, y: 6, w: 4, h: 1 }],
            cercas: [],
            objetos: [
                { i: 110, x: 5, y: 1 }, { i: 111, x: 6, y: 1 },
                { i: 96, x: 3, y: 4 }, { i: 85, x: 3, y: 5 },
                { i: 47, x: 7, y: 11 }, { i: 11, x: 0, y: 11 }, { i: 83, x: 8, y: 7 }, { i: 83, x: 0, y: 7 }
            ],
            pasto: { x: 4, y: 2, w: 4, h: 2 },
            galinhas: { x: 0, y: 6, w: 9, h: 1 }
        }
    };

    /* ============================================================
       CENA
    ============================================================ */
    function criarCena(canvas, cb) {
        cb = cb || {};
        const ctx = canvas.getContext('2d');
        const quadro = document.createElement('canvas');   // a cena em pixels do jogo (1:1)
        const q = quadro.getContext('2d');
        const fundo = document.createElement('canvas');    // grama + decoração estática
        const f = fundo.getContext('2d');

        let escala = 3, dpr = 1, cols = 0, linhas = 0;
        let L = LAYOUTS.paisagem;
        let nucleo = { x: 0, y: 0 };
        let margem = { topo: 0, base: 0 };
        let visual = () => null;     // (posicao) → como desenhar o canteiro
        let hover = null;            // posição do canteiro sob o mouse, ou 'celeiro'
        let animais = [];
        const fazendeiro = { x: 0, y: 0, tx: 0, ty: 0, flip: false, passo: 0 };
        let t0 = performance.now();

        /* ---- geometria ---- */
        const campoX = () => (nucleo.x + L.campo.x) * T;
        const campoY = () => (nucleo.y + L.campo.y) * T;
        function posCanteiro(p) {
            return { x: campoX() + (p % 6) * T, y: campoY() + Math.floor(p / 6) * T };
        }
        function retCeleiro() {
            return { x: (nucleo.x + L.celeiro.x) * T, y: (nucleo.y + L.celeiro.y) * T, w: 3 * T, h: 6 * T };
        }

        function redimensionar() {
            const W = window.innerWidth, H = window.innerHeight;
            dpr = Math.min(window.devicePixelRatio || 1, 3);
            canvas.width = Math.round(W * dpr);
            canvas.height = Math.round(H * dpr);
            canvas.style.width = W + 'px';
            canvas.style.height = H + 'px';

            const areaW = W - 24;
            const areaH = Math.max(160, H - margem.topo - margem.base - 16);
            const sP = Math.min(areaW / (LAYOUTS.paisagem.w * T), areaH / (LAYOUTS.paisagem.h * T));
            const sR = Math.min(areaW / (LAYOUTS.retrato.w * T), areaH / (LAYOUTS.retrato.h * T));
            L = sP >= sR ? LAYOUTS.paisagem : LAYOUTS.retrato;
            let s = Math.min(Math.max(sP, sR), 6);
            if (s >= 3) s = Math.floor(s);           // escala inteira = pixels perfeitos
            escala = Math.max(s, 1.5);

            cols = Math.ceil(W / (T * escala)) + 1;
            linhas = Math.ceil(H / (T * escala)) + 1;
            const topoT = margem.topo / (T * escala);
            const areaT = areaH / (T * escala);
            nucleo = {
                x: Math.floor((W / (T * escala) - L.w) / 2),
                y: Math.floor(topoT + (areaT - L.h) / 2)
            };
            quadro.width = fundo.width = cols * T;
            quadro.height = fundo.height = linhas * T;
            montarFundo();
            montarAnimais();
            const c = L.casaFazendeiro;
            fazendeiro.x = fazendeiro.tx = (nucleo.x + c.x) * T;
            fazendeiro.y = fazendeiro.ty = (nucleo.y + c.y) * T;
        }

        /* ---- fundo estático ---- */
        function ocupado(tx, ty) {
            const nx = tx - nucleo.x, ny = ty - nucleo.y;
            return nx >= -1 && ny >= -1 && nx <= L.w && ny <= L.h;
        }

        function manchaTerra(x, y, w, h, r) {
            f.fillStyle = PAL.t;
            for (let yy = 0; yy < h; yy++) {
                for (let xx = 0; xx < w; xx++) {
                    const borda = (xx < 2 || yy < 2 || xx > w - 3 || yy > h - 3);
                    if (borda && r() < 0.35) continue;
                    f.fillRect(x + xx, y + yy, 1, 1);
                }
            }
            for (let n = 0; n < (w * h) / 40; n++) {
                f.fillStyle = r() < 0.5 ? PAL.d : PAL.k;
                f.fillRect(x + 3 + Math.floor(r() * (w - 6)), y + 3 + Math.floor(r() * (h - 6)), 1, 1);
            }
        }

        function montarFundo() {
            const r = rng(cols * 73856093 ^ linhas * 19349663);
            f.fillStyle = PAL.g;
            f.fillRect(0, 0, fundo.width, fundo.height);

            // textura da grama: tufos, pontinhos claros e flores
            for (let n = 0; n < cols * linhas * 2.2; n++) {
                const x = Math.floor(r() * fundo.width), y = Math.floor(r() * fundo.height);
                const v = r();
                if (v < 0.55) {
                    f.fillStyle = PAL.G;
                    f.fillRect(x, y, 1, 1); f.fillRect(x + 2, y, 1, 1); f.fillRect(x + 1, y + 1, 1, 1);
                } else if (v < 0.85) {
                    f.fillStyle = PAL.l;
                    f.fillRect(x, y, 1, 1);
                } else if (!ocupado(Math.floor(x / T), Math.floor(y / T))) {
                    f.fillStyle = v < 0.93 ? PAL.y : PAL.w;
                    f.fillRect(x, y - 1, 1, 1); f.fillRect(x - 1, y, 3, 1); f.fillRect(x, y + 1, 1, 1);
                    f.fillStyle = PAL.Y;
                    f.fillRect(x, y, 1, 1);
                }
            }

            // terra batida em volta do celeiro
            for (const m of L.terra) {
                manchaTerra((nucleo.x + m.x) * T - 4, (nucleo.y + m.y) * T - 2, m.w * T + 8, m.h * T + 4, r);
            }

            // floresta nas bordas e árvores soltas fora do núcleo
            const arvores = [];
            for (let ty = -1; ty < linhas; ty++) {
                for (let tx = -1; tx < cols; tx++) {
                    if (ocupado(tx, ty)) continue;
                    // distância (em tiles) até a borda do núcleo: quanto mais longe, mais mato
                    const longe = Math.max(
                        nucleo.x - 1 - tx, tx - (nucleo.x + L.w),
                        nucleo.y - 1 - ty, ty - (nucleo.y + L.h)
                    );
                    const chance = longe >= 3 ? 0.85 : longe === 2 ? 0.45 : 0.12;
                    if (r() < chance) {
                        const v = r();
                        const i = longe >= 2 ? (v < 0.75 ? 15 : v < 0.9 ? 27 : 39) : (v < 0.4 ? 39 : v < 0.6 ? 78 : v < 0.75 ? 89 : v < 0.85 ? 77 : 15);
                        arvores.push({ i, x: tx * T + Math.floor((r() - 0.5) * 6), y: ty * T + Math.floor((r() - 0.5) * 6) });
                    }
                }
            }
            arvores.sort((a, b) => a.y - b.y).forEach((a) => tile(f, a.i, a.x, a.y));

            // celeiro
            const c = retCeleiro();
            CELEIRO.forEach((linha, yy) => linha.forEach((cel, xx) => {
                if (cel == null) return;
                (Array.isArray(cel) ? cel : [cel]).forEach((i) => tile(f, i, c.x + xx * T, c.y + yy * T));
            }));

            // cercas e objetos
            for (const ce of L.cercas) {
                tile(f, 98, (nucleo.x + ce.x) * T, (nucleo.y + ce.y) * T);
                tile(f, 99, (nucleo.x + ce.x + 1) * T, (nucleo.y + ce.y) * T);
            }
            for (const o of L.objetos) tile(f, o.i, (nucleo.x + o.x) * T, (nucleo.y + o.y) * T);
        }

        /* ---- animais andando ---- */
        function montarAnimais() {
            const r = rng(4242);
            const area = (a) => ({
                x0: (nucleo.x + a.x) * T, y0: (nucleo.y + a.y) * T,
                x1: (nucleo.x + a.x + a.w - 1) * T, y1: (nucleo.y + a.y + a.h - 1) * T
            });
            const pasto = area(L.pasto), quintal = area(L.galinhas);
            const novo = (i, a, vel) => {
                const x = a.x0 + r() * (a.x1 - a.x0), y = a.y0 + r() * (a.y1 - a.y0);
                return { i, a, vel, x, y, tx: x, ty: y, flip: false, espera: r() * 3000 };
            };
            animais = [
                novo(121, pasto, 4), novo(120, pasto, 4), novo(121, pasto, 4),
                novo(122, quintal, 10), novo(122, quintal, 10), novo(122, quintal, 10)
            ];
        }

        function moverAnimais(dt) {
            for (const a of animais) {
                if (a.espera > 0) { a.espera -= dt; continue; }
                const dx = a.tx - a.x, dy = a.ty - a.y, d = Math.hypot(dx, dy);
                if (d < 0.5) {
                    a.espera = 800 + Math.random() * 3500;
                    a.tx = a.a.x0 + Math.random() * (a.a.x1 - a.a.x0);
                    a.ty = a.a.y0 + Math.random() * (a.a.y1 - a.a.y0);
                    continue;
                }
                const passo = Math.min(d, a.vel * dt / 1000);
                a.x += dx / d * passo; a.y += dy / d * passo;
                if (Math.abs(dx) > 0.2) a.flip = dx > 0;
            }
            const dx = fazendeiro.tx - fazendeiro.x, dy = fazendeiro.ty - fazendeiro.y, d = Math.hypot(dx, dy);
            if (d > 0.5) {
                const passo = Math.min(d, 56 * dt / 1000);
                fazendeiro.x += dx / d * passo; fazendeiro.y += dy / d * passo;
                if (Math.abs(dx) > 0.2) fazendeiro.flip = dx < 0;
                fazendeiro.passo += dt;
            } else {
                fazendeiro.passo = 0;
            }
        }

        /* ---- canteiros ---- */
        function desenharCanteiro(p, tempo) {
            const v = visual(p);
            const { x, y } = posCanteiro(p);
            if (!v || v.solo === 'bloqueado') {
                // grama com contorno tracejado e cadeado
                q.fillStyle = 'rgba(63,38,49,.28)';
                for (let k = 2; k < T - 2; k += 3) {
                    q.fillRect(x + k, y + 1, 2, 1); q.fillRect(x + k, y + T - 2, 2, 1);
                    q.fillRect(x + 1, y + k, 1, 2); q.fillRect(x + T - 2, y + k, 1, 2);
                }
                q.globalAlpha = 0.75;
                icone(q, 'cadeado', x + 5, y + 4);
                q.globalAlpha = 1;
                return;
            }
            tile(q, v.solo === 'arado' ? 1 : 0, x, y);
            if (v.seco) {   // terra rachada
                q.fillStyle = PAL.k;
                q.fillRect(x + 4, y + 5, 3, 1); q.fillRect(x + 6, y + 6, 1, 2);
                q.fillRect(x + 9, y + 10, 3, 1); q.fillRect(x + 9, y + 11, 1, 1);
            }
            if (v.planta != null) {
                const bob = v.maduro && Math.floor(tempo / 450) % 2 ? -1 : 0;
                tile(q, v.planta, x, y - 2 + bob);
            }
            if (v.progresso != null) {
                q.fillStyle = PAL.o; q.fillRect(x + 2, y + T - 3, 12, 3);
                q.fillStyle = PAL.d; q.fillRect(x + 3, y + T - 2, 10, 1);
                q.fillStyle = PAL.l; q.fillRect(x + 3, y + T - 2, Math.max(1, Math.round(10 * v.progresso)), 1);
            }
            if (v.maduro && !v.cinza && Math.floor(tempo / 300) % 4 !== 0) {
                icone(q, 'brilho', x + 11 + (Math.floor(tempo / 1200) % 2) * -9, y - 2);
            }
            if (v.check) icone(q, 'check', x + 8, y + 9);
            if (v.probs && v.probs.length) {
                // balãozinho com os problemas
                const w = v.probs.length * 10 + 3, bx = x + T / 2 - Math.floor(w / 2);
                const by = y - 14 + (Math.floor(tempo / 500) % 2);
                q.fillStyle = PAL.o; q.fillRect(bx, by, w, 13); q.fillRect(bx + 1, by - 1, w - 2, 15);
                q.fillStyle = PAL.w; q.fillRect(bx + 1, by, w - 2, 13);
                q.fillStyle = PAL.o; q.fillRect(bx + Math.floor(w / 2) - 1, by + 13, 3, 2);
                q.fillStyle = PAL.w; q.fillRect(bx + Math.floor(w / 2), by + 13, 1, 1);
                v.probs.forEach((pr, n) => icone(q, pr, bx + 2 + n * 10, by + 2));
            }
            if (v.pegar) {
                const by = y - 12 + (Math.floor(tempo / 400) % 2);
                icone(q, 'mao', x + 4, by);
            }
            if (v.pendente && Math.floor(tempo / 150) % 2) {
                q.fillStyle = 'rgba(255,255,255,.35)';
                q.fillRect(x + 1, y + 1, T - 2, T - 2);
            }
        }

        function moldura(x, y, w, h) {
            q.fillStyle = PAL.w;
            const c = 4;
            q.fillRect(x - 1, y - 1, c, 1); q.fillRect(x - 1, y - 1, 1, c);
            q.fillRect(x + w - c + 1, y - 1, c, 1); q.fillRect(x + w, y - 1, 1, c);
            q.fillRect(x - 1, y + h, c, 1); q.fillRect(x - 1, y + h - c + 1, 1, c);
            q.fillRect(x + w - c + 1, y + h, c, 1); q.fillRect(x + w, y + h - c + 1, 1, c);
        }

        /* ---- loop ---- */
        let ultimo = performance.now(), ultimoDesenho = 0;
        function quadroAnim(agora) {
            const dt = Math.min(100, agora - ultimo);
            ultimo = agora;
            moverAnimais(dt);
            if (agora - ultimoDesenho >= 1000 / 24) {
                ultimoDesenho = agora;
                desenhar(agora - t0);
            }
            requestAnimationFrame(quadroAnim);
        }

        function desenhar(tempo) {
            q.drawImage(fundo, 0, 0);
            for (let p = 0; p < 18; p++) desenharCanteiro(p, tempo);

            // personagens ordenados pela altura (quem está mais embaixo fica na frente)
            const atores = animais.map((a) => ({ i: a.i, x: a.x, y: a.y, flip: a.flip, bob: 0 }));
            const andando = fazendeiro.passo > 0;
            atores.push({ i: 109, x: fazendeiro.x, y: fazendeiro.y, flip: fazendeiro.flip, bob: andando && Math.floor(tempo / 120) % 2 ? -1 : 0 });
            atores.sort((a, b) => a.y - b.y).forEach((a) => tile(q, a.i, Math.round(a.x), Math.round(a.y) + a.bob, a.flip));

            if (typeof hover === 'number') {
                const { x, y } = posCanteiro(hover);
                moldura(x, y, T, T);
            } else if (hover === 'celeiro') {
                const c = retCeleiro();
                moldura(c.x, c.y + T, c.w, c.h - T);
            }

            ctx.imageSmoothingEnabled = false;
            ctx.drawImage(quadro, 0, 0, quadro.width * escala * dpr, quadro.height * escala * dpr);
        }

        /* ---- entrada do mouse/toque ---- */
        function alvoEm(clientX, clientY) {
            const px = clientX / escala, py = clientY / escala;
            const cx = campoX(), cy = campoY();
            if (px >= cx && py >= cy && px < cx + 6 * T && py < cy + 3 * T) {
                return Math.floor((py - cy) / T) * 6 + Math.floor((px - cx) / T);
            }
            const c = retCeleiro();
            if (px >= c.x && py >= c.y && px < c.x + c.w && py < c.y + c.h) return 'celeiro';
            return null;
        }

        canvas.addEventListener('pointermove', (e) => {
            const alvo = alvoEm(e.clientX, e.clientY);
            if (alvo !== hover) {
                hover = alvo;
                canvas.style.cursor = alvo == null ? 'default' : 'pointer';
                if (cb.aoPassar) cb.aoPassar(alvo);
            }
        });
        canvas.addEventListener('pointerleave', () => { hover = null; });
        canvas.addEventListener('click', (e) => {
            const alvo = alvoEm(e.clientX, e.clientY);
            if (alvo === 'celeiro') { if (cb.aoCeleiro) cb.aoCeleiro(); }
            else if (typeof alvo === 'number' && cb.aoCanteiro) cb.aoCanteiro(alvo);
        });

        window.addEventListener('resize', redimensionar);

        return {
            iniciar() {
                redimensionar();
                requestAnimationFrame(quadroAnim);
            },
            definirMargens(topo, base) {
                if (topo === margem.topo && base === margem.base) return;
                margem = { topo, base };
                redimensionar();
            },
            definirVisual(fn) { visual = fn; },
            // fazendeiro caminha até o canteiro (só enfeite)
            irAte(p) {
                const { x, y } = posCanteiro(p);
                fazendeiro.tx = x;
                fazendeiro.ty = y + T - 4;
            },
            voltarParaCasa() {
                const c = L.casaFazendeiro;
                fazendeiro.tx = (nucleo.x + c.x) * T;
                fazendeiro.ty = (nucleo.y + c.y) * T;
            },
            // posição na tela (px CSS) do centro de um canteiro, para números flutuantes
            telaDoCanteiro(p) {
                const { x, y } = posCanteiro(p);
                return { x: (x + T / 2) * escala, y: (y - 2) * escala };
            }
        };
    }

    window.FazendaArte = {
        carregar,
        criarCena,
        htmlTile,
        htmlIcone,
        cultura: (id) => CULTURAS[id] || CULTURA_PADRAO
    };
})();
