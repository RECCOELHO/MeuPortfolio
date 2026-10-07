/* ============================================================
   FAZENDINHA SECRETA — arte e cena
   Pixel art dos pacotes "Tiny Farm", "Tiny Town" e "Tiny Ski" do
   Kenney (CC0, kenney.nl), desenhada num <canvas>. Os ícones pequenos
   (moeda, XP, praga...) são desenhados aqui, na mesma paleta.

   A fazenda é um mapa fixo de 22 x 13 quadrados cercado de mata.
   No PC a câmera mostra tudo; no celular dá para arrastar com o dedo.

   Expõe window.FazendaArte com:
     carregar()                → Promise quando a arte estiver pronta
     criarCena(canvas, cb)     → motor da cena
     htmlTile(i, px, pacote)   → <span> com um sprite (para a UI)
     htmlIcone(nome, px)       → <img> com um ícone pixel
     htmlItem(id, px)          → <span> com a arte de um item construível
     cultura(id), ANIMAL       → sprites de culturas e animais
     estacao(), livre(x, y)    → estação do ano e se um quadrado aceita construção
============================================================ */
(function () {
    'use strict';

    const T = 16;           // tamanho do tile
    const COLS = 12;        // colunas dos atlas
    const LINHAS = 11;

    const PAL = {
        o: '#3f2631', g: '#84c669', G: '#4e974c', l: '#c6e58d', y: '#fdbe53', Y: '#e38628',
        r: '#c34b35', R: '#aa2c23', b: '#99d8f8', B: '#79a7e8', w: '#ffffff', p: '#d176d0',
        P: '#9b4ca3', s: '#c0cbdc', S: '#8b9bb4', k: '#fec99c', t: '#eaa56c', d: '#cf8254', n: '#763b36'
    };

    /* ---------- Mapa fixo da fazenda (precisa bater com fazenda_livre no SQL) ---------- */
    const MAPA = {
        w: 22, h: 13,
        celeiro: { x: 1, y: 1 },                     // 3 x 6
        casa: { x: 5, y: 1 },                        // 3 x 3
        campo: { x: 9, y: 4 },                       // 6 x 3
        fazendeiro: { x: 8, y: 4 },
        galinheiro: { x: 0, y: 7, w: 7, h: 2 },
        pasto: { x: 16, y: 0, w: 6, h: 7 },          // cercado, porteira embaixo
        porteira: [18, 19],
        cochos: [{ i: 110, x: 18, y: 1 }, { i: 111, x: 19, y: 1 }],
        reservas: [
            { x: 1, y: 1, w: 3, h: 6 }, { x: 5, y: 1, w: 3, h: 3 }, { x: 0, y: 7, w: 7, h: 2 },
            { x: 9, y: 3, w: 6, h: 4 }, { x: 16, y: 0, w: 6, h: 7 }
        ]
    };
    const MARGEM = 9;   // quadrados de mata em volta do terreno

    function livre(x, y) {
        if (x < 0 || y < 0 || x >= MAPA.w || y >= MAPA.h) return false;
        return !MAPA.reservas.some((r) => x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h);
    }

    /* ---------- Estação do ano (hemisfério sul) ---------- */
    function estacao() {
        try {
            const forcada = new URLSearchParams(location.search).get('estacao');
            if (['primavera', 'verao', 'outono', 'inverno'].includes(forcada)) return forcada;
        } catch { /* ignora */ }
        const d = new Date(), m = d.getMonth() + 1, dia = d.getDate();
        const md = m * 100 + dia;
        if (md >= 1221 || md < 320) return 'verao';
        if (md < 621) return 'outono';
        if (md < 923) return 'inverno';
        return 'primavera';
    }

    /* ---------- Sprites do pacote por cultura ----------
       fases: [broto, crescendo, maduro], murcho, item colhido, semente (loja) */
    const CULTURAS = {
        alface:   { fases: [52, 53, 54], murcho: 55, item: 56, semente: 58 },
        cenoura:  { fases: [4, 5, 6],    murcho: 7,  item: 8,  semente: 10 },
        batata:   { fases: [16, 17, 18], murcho: 19, item: 20, semente: 22 }, // arte: beterraba
        milho:    { fases: [28, 29, 30], murcho: 31, item: 32, semente: 34 },
        tomate:   { fases: [40, 41, 42], murcho: 43, item: 44, semente: 46 },
        girassol: { fases: [81, 80, 83], murcho: 67, item: 83, semente: 74 },
        abobora:  { fases: [64, 65, 66], murcho: 67, item: 68, semente: 70 }, // arte: trigo
        morango:  { fases: [81, 39, 78], murcho: 43, item: 78, semente: 74 }, // arte: amora
        ovo:      { fases: [125, 125, 125], murcho: 125, item: 125, semente: 125 },
        leite:    { fases: [123, 123, 123], murcho: 123, item: 123, semente: 123 }
    };
    const CULTURA_PADRAO = CULTURAS.alface;
    const ANIMAL = { galinha: 122, vaca: 121, ovelha: 120 };

    /* ---------- Arte dos itens construíveis ----------
       p = pacote, i = tile, topo = tile de cima (árvores altas), auto = encaixe automático */
    function arteItem(id, est) {
        const inv = est === 'inverno';
        switch (id) {
            case 'cerca': return { p: 'town', auto: 'cerca' };
            case 'caminho_terra': return { p: 'town', auto: 'terra', chao: true };
            case 'caminho_pedra': return { p: 'town', i: 43, chao: true };
            case 'flores': return { p: 'town', i: 2, chao: true };
            case 'girassol': return { p: 'farm', i: 83 };
            case 'arbusto': return inv ? { p: 'ski', i: 31 } : { p: 'town', i: 5 };
            case 'cogumelos': return { p: 'town', i: 29 };
            case 'arvore':
                if (inv) return { p: 'ski', i: 19, topo: 7 };
                if (est === 'outono') return { p: 'town', i: 15, topo: 3 };
                return { p: 'town', i: 16, topo: 4 };
            case 'arvore_outono': return inv ? { p: 'ski', i: 19, topo: 7 } : { p: 'town', i: 15, topo: 3 };
            case 'pinheiro': return inv ? { p: 'ski', i: 18, topo: 6 } : { p: 'farm', i: 15, topo: 3 };
            case 'amoreira': return { p: 'farm', i: 78 };
            case 'pedras': return { p: 'farm', i: 89 };
            case 'tora': return { p: 'town', i: 106 };
            case 'placa': return { p: 'town', i: 83 };
            case 'balde': return { p: 'farm', i: 73 };
            case 'barril': return { p: 'farm', i: 85 };
            case 'feno': return { p: 'farm', i: 96 };
            case 'alvo': return { p: 'town', i: 95 };
            case 'caixote': return { p: 'farm', i: 47 };
            case 'colmeia': return { p: 'town', i: 94 };
            case 'bau': return { p: 'farm', i: 76 };
            case 'boneco_neve': return { p: 'ski', i: 64 };
            default: return { p: 'farm', i: 89 };
        }
    }

    // Cerca: escolhe a peça pelos vizinhos (cima, baixo, esquerda, direita)
    function tileCerca(c, b, e, d) {
        if (e && d) return 45;
        if (c && b) return 59;
        if (d && b) return 44;
        if (e && b) return 46;
        if (d && c) return 68;
        if (e && c) return 70;
        if (d) return 44;
        if (e) return 46;
        if (b) return 56;
        if (c) return 71;
        return 47;
    }
    // Caminho de terra: bloco 3x3 do Tiny Town (bordas com grama onde não há vizinho)
    function tileTerra(c, b, e, d) {
        const linha = !c && b ? 0 : c && !b ? 2 : 1;
        const coluna = !e && d ? 0 : e && !d ? 2 : 1;
        return [12, 24, 36][linha] + coluna;
    }

    /* ---------- Ícones pixel (mesma paleta) ---------- */
    const ICONES = {
        moeda: ['..oooo..', '.oyyyyo.', 'oywyyyYo', 'oywyYyYo', 'oyyyYyYo', 'oyyyyYYo', '.oYYYYo.', '..oooo..'],
        xp: ['....o....', '...oyo...', '..oywyo..', 'oooywyooo', 'oyyyyyyYo', '.oyyyyYo.', '.oyyoyYo.', 'oyYo.oYYo', 'ooo...ooo'],
        praga: ['.o.....o.', '..o...o..', '..ooooo..', '.oPwpPPo.', 'oPpPPPpPo', 'oPPPPPPPo', '.oPPpPPo.', '..ooooo..'],
        seco: ['...o...', '..obo..', '..obo..', '.obbbo.', 'obwbbbo', 'obwbbBo', 'obbbbBo', '.oBBBo.', '..ooo..'],
        erva: ['.o.....o.', 'oGo.o.oGo', 'oGgoGogGo', '.oGgGgGo.', '..oGgGo..', '...oGo...', '...oGo...', '....o....'],
        cadeado: ['..ooo..', '.o...o.', '.o...o.', 'ooooooo', 'oyyyyyo', 'oyyoyyo', 'oyyoyyo', 'oYYYYYo', 'ooooooo'],
        check: ['......oo', '.....oGo', 'oo..oGo.', 'oGooGo..', '.oGGo...', '..oo....'],
        brilho: ['..w..', '..w..', 'ww.ww', '..w..', '..w..'],
        mao: ['..o.o.o..', '.oko.oko.', '.okokoko.', 'ooko.okoo', 'okkkkkkko', 'okkkkkkko', '.okkkkko.', '..ooooo..'],
        coracao: ['.oo.oo.', 'orrorRo', 'orwrrRo', 'orrrrRo', '.orrRo.', '..oRo..', '...o...'],
        missao: ['ooooooo.', 'okkkkkko', 'okoooko.', 'okkkkkko', 'okoooko.', 'okkkkkko', 'okooko..', 'okkkkko.', 'oooooo..'],
        mover: ['....o....', '...oko...', '..okkko..', '....o....', 'oko.o.oko', 'okkoooko.', 'oko.o.oko', '....o....', '..okkko..', '...oko...', '....o....'],
        lixeira: ['..ooooo..', 'ooooooooo', 'okkkkkkko', '.okokoko.', '.okokoko.', '.okokoko.', '.okokoko.', '.okkkkko.', '..ooooo..']
    };

    const icones = {};
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

    const ARQUIVOS = { farm: 'tiny-farm.png', town: 'tiny-town.png', ski: 'tiny-ski.png' };
    function htmlTile(i, px = 32, pacote = 'farm') {
        const c = i % COLS, l = Math.floor(i / COLS);
        const img = pacote === 'farm' ? '' : `background-image:url('assets/fazenda/${ARQUIVOS[pacote]}');`;
        return `<span class="px-spr" style="${img}width:${px}px;height:${px}px;background-size:${COLS * px}px ${LINHAS * px}px;background-position:-${c * px}px -${l * px}px" aria-hidden="true"></span>`;
    }

    // Ícone de item para a UI (árvores altas mostram as duas peças)
    function htmlItem(id, px = 32) {
        const a = arteItem(id, estacao());
        const i = a.auto === 'cerca' ? 45 : a.auto === 'terra' ? 25 : a.i;
        if (a.topo == null) return htmlTile(i, px, a.p);
        const m = Math.round(px / 2);
        return `<span class="px-alto" style="width:${m}px;height:${px}px">${htmlTile(a.topo, m, a.p)}${htmlTile(i, m, a.p)}</span>`;
    }

    /* ---------- Atlas ---------- */
    const atlas = { farm: new Image(), town: new Image(), ski: new Image() };
    let atlasPronto = null;
    function carregar() {
        if (!atlasPronto) {
            atlasPronto = Promise.all(Object.entries(atlas).map(([p, img]) => new Promise((ok, erro) => {
                img.onload = ok;
                img.onerror = () => erro(new Error('Não deu para carregar a arte da fazenda.'));
                img.src = 'assets/fazenda/' + ARQUIVOS[p];
            })));
        }
        return atlasPronto;
    }

    function tile(ctx, i, x, y, flip, pacote = 'farm') {
        const img = atlas[pacote];
        const sx = (i % COLS) * T, sy = Math.floor(i / COLS) * T;
        if (flip) {
            ctx.save();
            ctx.translate(x + T, y);
            ctx.scale(-1, 1);
            ctx.drawImage(img, sx, sy, T, T, 0, 0, T, T);
            ctx.restore();
        } else {
            ctx.drawImage(img, sx, sy, T, T, x, y, T, T);
        }
    }

    function icone(ctx, nome, x, y) {
        ctx.drawImage(icones[nome], Math.round(x), Math.round(y));
    }

    /* ---------- Gerador pseudoaleatório estável (a mata não "pula") ---------- */
    function rng(seed) {
        let s = seed >>> 0 || 1;
        return () => {
            s ^= s << 13; s >>>= 0;
            s ^= s >> 17;
            s ^= s << 5; s >>>= 0;
            return s / 4294967296;
        };
    }
    function hash(v) {
        let h = 2166136261;
        for (const ch of String(v)) { h ^= ch.charCodeAt(0); h = Math.imul(h, 16777619); }
        return h >>> 0;
    }

    const CELEIRO = [
        [null, 82, null],
        [93, 94, 95],
        [105, 106, 107],
        [117, 118, 119],
        [[90, 129], [91, 130], [92, 131]],
        [114, 126, 116]
    ];
    const CASA = [[52, 53, 55], [64, 65, 67], [84, 85, 75]];   // Tiny Town

    /* ============================================================
       CENA
    ============================================================ */
    function criarCena(canvas, cb) {
        cb = cb || {};
        const ctx = canvas.getContext('2d');
        const EST = estacao();

        // mundo inteiro em pixels do jogo (terreno + mata em volta)
        const MW = (MAPA.w + MARGEM * 2) * T, MH = (MAPA.h + MARGEM * 2) * T;
        const mundo = document.createElement('canvas');
        mundo.width = MW; mundo.height = MH;
        const q = mundo.getContext('2d');
        const fundo = document.createElement('canvas');
        fundo.width = MW; fundo.height = MH;
        const f = fundo.getContext('2d');

        let escala = 3, dpr = 1, vw = 0, vh = 0;           // vw/vh: tela em pixels do jogo
        const cam = { x: 0, y: 0 };
        let margem = { topo: 0, base: 0 };
        let visual = () => null;
        let animaisFn = () => [];
        let construcoesFn = () => [];
        let construcao = { ativo: false };                 // estado do modo construir
        let hover = null;                                  // canteiro, 'celeiro', 'a:<id>' ou {tx, ty}
        const atores = new Map();
        const fazendeiro = { x: 0, y: 0, tx: 0, ty: 0, flip: false, passo: 0 };
        const t0 = performance.now();

        /* ---- geometria (coordenadas do mundo, em pixels do jogo) ---- */
        const wx = (tx) => (MARGEM + tx) * T;
        const wy = (ty) => (MARGEM + ty) * T;
        function posCanteiro(p) {
            return { x: wx(MAPA.campo.x + (p % 6)), y: wy(MAPA.campo.y + Math.floor(p / 6)) };
        }
        function retCeleiro() {
            return { x: wx(MAPA.celeiro.x), y: wy(MAPA.celeiro.y), w: 3 * T, h: 6 * T };
        }
        function areaDe(tipo) {
            const a = tipo === 'galinha'
                ? { x: MAPA.galinheiro.x, y: MAPA.galinheiro.y, w: MAPA.galinheiro.w, h: MAPA.galinheiro.h }
                : { x: MAPA.pasto.x + 1, y: MAPA.pasto.y + 2, w: MAPA.pasto.w - 2, h: MAPA.pasto.h - 3 };
            return { x0: wx(a.x), y0: wy(a.y), x1: wx(a.x + a.w - 1), y1: wy(a.y + a.h - 1) };
        }

        /* ---- câmera ---- */
        // a câmera só passeia pelo terreno (mais uma bordinha de mata), nunca se perde no mato
        function faixaCamera() {
            const borda = T * 1.5;
            const topo = margem.topo / escala, base = margem.base / escala;
            let minX = wx(0) - borda, maxX = wx(MAPA.w) + borda - vw;
            let minY = wy(0) - borda - topo, maxY = wy(MAPA.h) + borda + base - vh;
            if (maxX < minX) minX = maxX = (minX + maxX) / 2;
            if (maxY < minY) minY = maxY = (minY + maxY) / 2;
            return { minX, maxX, minY, maxY };
        }
        function limitarCamera() {
            const f = faixaCamera();
            cam.x = Math.min(Math.max(cam.x, f.minX), f.maxX);
            cam.y = Math.min(Math.max(cam.y, f.minY), f.maxY);
        }
        // centraliza um ponto do mundo no meio da área útil (entre o topo e a barra)
        function focar(px, py) {
            const meioY = (margem.topo + (innerHeight - margem.topo - margem.base) / 2) / escala;
            cam.x = px - vw / 2;
            cam.y = py - meioY;
            limitarCamera();
            sincronizarRolagem();
        }

        /* ---- celular: arrastar com a rolagem nativa do navegador ----
           Uma camada transparente rolável fica por cima do canvas. O dedo rola
           essa camada (com a inércia do próprio aparelho) e a câmera só segue
           a posição da rolagem. Toques rápidos viram cliques no jogo. */
        const toqueNativo = window.matchMedia('(hover: none) and (pointer: coarse)').matches;
        let rolagem = null, espaco = null, ajustandoRolagem = false, precisaDesenhar = false;
        if (toqueNativo) {
            rolagem = document.createElement('div');
            rolagem.className = 'cena-rolagem';
            rolagem.setAttribute('aria-hidden', 'true');
            espaco = document.createElement('div');
            rolagem.appendChild(espaco);
            canvas.after(rolagem);
            rolagem.addEventListener('scroll', () => {
                if (ajustandoRolagem) return;
                const f = faixaCamera();
                cam.x = f.minX + rolagem.scrollLeft / escala;
                cam.y = f.minY + rolagem.scrollTop / escala;
                precisaDesenhar = true;
            }, { passive: true });
            rolagem.addEventListener('click', (e) => acionar(e.clientX, e.clientY));
        }
        function sincronizarRolagem() {
            if (!rolagem) return;
            const f = faixaCamera();
            espaco.style.width = (innerWidth + (f.maxX - f.minX) * escala) + 'px';
            espaco.style.height = (innerHeight + (f.maxY - f.minY) * escala) + 'px';
            ajustandoRolagem = true;
            rolagem.scrollLeft = (cam.x - f.minX) * escala;
            rolagem.scrollTop = (cam.y - f.minY) * escala;
            requestAnimationFrame(() => { ajustandoRolagem = false; });
        }

        function redimensionar() {
            const W = window.innerWidth, H = window.innerHeight;
            dpr = Math.min(window.devicePixelRatio || 1, 3);
            canvas.width = Math.round(W * dpr);
            canvas.height = Math.round(H * dpr);
            canvas.style.width = W + 'px';
            canvas.style.height = H + 'px';

            const areaW = W - 24;
            const areaH = Math.max(200, H - margem.topo - margem.base - 12);
            let s = Math.min(areaW / (MAPA.w * T), areaH / (MAPA.h * T));
            // celular em pé: o terreno não cabe na largura, então usa a altura e deixa arrastar
            if (s < 2.5) s = Math.min(Math.max(areaH / (MAPA.h * T), 2.5), 3.4);
            s = Math.min(s, 6);
            if (s >= 3) s = Math.floor(s);
            escala = s;
            vw = W / escala;
            vh = H / escala;
            atores.clear();
            const c = MAPA.fazendeiro;
            fazendeiro.x = fazendeiro.tx = wx(c.x);
            fazendeiro.y = fazendeiro.ty = wy(c.y);
            // começa olhando para o campo
            focar(wx(MAPA.campo.x + 3), wy(MAPA.campo.y + 1));
        }

        /* ---- fundo estático: grama, mata, celeiro, casa, pasto ---- */
        function dentroTerreno(tx, ty) {
            return tx >= 0 && ty >= 0 && tx < MAPA.w && ty < MAPA.h;
        }

        function montarFundo() {
            const r = rng(20261007);
            const corGrama = EST === 'inverno' ? '#9fcf86' : PAL.g;
            f.fillStyle = corGrama;
            f.fillRect(0, 0, MW, MH);

            // neve fora do terreno no inverno, com borda irregular
            if (EST === 'inverno') {
                const img = f.getImageData(0, 0, MW, MH);
                const x0 = wx(0), y0 = wy(0), x1 = wx(MAPA.w), y1 = wy(MAPA.h);
                for (let y = 0; y < MH; y++) {
                    for (let x = 0; x < MW; x++) {
                        const dx = Math.max(x0 - x, x - x1, 0), dy = Math.max(y0 - y, y - y1, 0);
                        const dist = Math.max(dx, dy);
                        const ruido = (Math.sin(x * 0.37) + Math.sin(y * 0.29) + Math.sin((x + y) * 0.11)) * 2 + 6;
                        if (dist > ruido) {
                            const k = (y * MW + x) * 4;
                            const brilho = r() < 0.02;
                            img.data[k] = brilho ? 255 : 236; img.data[k + 1] = brilho ? 255 : 244; img.data[k + 2] = 255;
                        }
                    }
                }
                f.putImageData(img, 0, 0);
            }

            // textura: tufos, pontinhos e flores (mais flores na primavera, folhas no outono)
            const flores = { primavera: 0.3, verao: 0.14, outono: 0.04, inverno: 0.02 }[EST];
            for (let n = 0; n < (MW * MH) / 60; n++) {
                const x = Math.floor(r() * MW), y = Math.floor(r() * MH);
                const tx = Math.floor(x / T) - MARGEM, ty = Math.floor(y / T) - MARGEM;
                if (EST === 'inverno' && !dentroTerreno(tx, ty)) continue;
                const v = r();
                if (v < 0.5) {
                    f.fillStyle = PAL.G;
                    f.fillRect(x, y, 1, 1); f.fillRect(x + 2, y, 1, 1); f.fillRect(x + 1, y + 1, 1, 1);
                } else if (v < 0.5 + (EST === 'outono' ? 0.3 : 0.2)) {
                    f.fillStyle = EST === 'outono' ? (r() < 0.5 ? PAL.Y : PAL.y) : EST === 'inverno' ? PAL.w : PAL.l;
                    f.fillRect(x, y, 1, 1);
                    if (EST === 'outono') f.fillRect(x + 1, y, 1, 1);
                } else if (r() < flores * 3) {
                    f.fillStyle = r() < 0.4 ? PAL.y : r() < 0.5 ? PAL.w : PAL.p;
                    f.fillRect(x, y - 1, 1, 1); f.fillRect(x - 1, y, 3, 1); f.fillRect(x, y + 1, 1, 1);
                    f.fillStyle = PAL.Y;
                    f.fillRect(x, y, 1, 1);
                }
            }

            // terra batida do galinheiro (bloco 3x3 do Tiny Town)
            const g = MAPA.galinheiro;
            for (let yy = 0; yy < g.h; yy++) {
                for (let xx = 0; xx < g.w; xx++) {
                    tile(f, tileTerra(yy > 0, yy < g.h - 1, xx > 0, xx < g.w - 1), wx(g.x + xx), wy(g.y + yy), false, 'town');
                }
            }

            // mata em volta do terreno: árvores de duas peças, conforme a estação
            const arvores = [];
            for (let ty = -MARGEM; ty < MAPA.h + MARGEM; ty++) {
                for (let tx = -MARGEM; tx < MAPA.w + MARGEM; tx++) {
                    if (dentroTerreno(tx, ty)) continue;
                    const longe = Math.max(-tx, tx - MAPA.w + 1, -ty, ty - MAPA.h + 1);
                    const chance = longe >= 3 ? 0.9 : longe === 2 ? 0.6 : 0.3;
                    if (r() >= chance) continue;
                    const v = r();
                    let a;
                    if (EST === 'inverno') {
                        a = v < 0.6 ? { p: 'ski', i: 18, topo: 6 } : v < 0.75 ? { p: 'ski', i: 19, topo: 7 } : v < 0.9 ? { p: 'ski', i: 30 } : v < 0.98 ? { p: 'ski', i: 31 } : { p: 'ski', i: 64 };
                    } else if (EST === 'outono') {
                        a = v < 0.45 ? { p: 'town', i: 15, topo: 3 } : v < 0.7 ? { p: 'farm', i: 15, topo: 3 } : v < 0.85 ? { p: 'town', i: 27 } : { p: 'town', i: 5 };
                    } else {
                        a = v < 0.45 ? { p: 'farm', i: 15, topo: 3 } : v < 0.75 ? { p: 'town', i: 16, topo: 4 } : v < 0.85 ? { p: 'farm', i: 27 } : v < 0.93 ? { p: 'town', i: 28 } : { p: 'town', i: 5 };
                    }
                    arvores.push({ ...a, x: wx(tx) + Math.floor((r() - 0.5) * 6), y: wy(ty) + Math.floor((r() - 0.5) * 4) });
                }
            }
            arvores.sort((a, b) => a.y - b.y).forEach((a) => {
                if (a.topo != null) tile(f, a.topo, a.x, a.y - T, false, a.p);
                tile(f, a.i, a.x, a.y, false, a.p);
            });

            // celeiro e casa
            const c = retCeleiro();
            CELEIRO.forEach((linha, yy) => linha.forEach((cel, xx) => {
                if (cel == null) return;
                (Array.isArray(cel) ? cel : [cel]).forEach((i) => tile(f, i, c.x + xx * T, c.y + yy * T));
            }));
            CASA.forEach((linha, yy) => linha.forEach((i, xx) => tile(f, i, wx(MAPA.casa.x + xx), wy(MAPA.casa.y + yy), false, 'town')));

            // pasto cercado com porteira
            const pa = MAPA.pasto;
            const ehCerca = (tx, ty) => {
                if (tx < pa.x || ty < pa.y || tx >= pa.x + pa.w || ty >= pa.y + pa.h) return false;
                const borda = tx === pa.x || ty === pa.y || tx === pa.x + pa.w - 1 || ty === pa.y + pa.h - 1;
                if (!borda) return false;
                return !(ty === pa.y + pa.h - 1 && MAPA.porteira.includes(tx));
            };
            for (let ty = pa.y; ty < pa.y + pa.h; ty++) {
                for (let tx = pa.x; tx < pa.x + pa.w; tx++) {
                    if (!ehCerca(tx, ty)) continue;
                    tile(f, tileCerca(ehCerca(tx, ty - 1), ehCerca(tx, ty + 1), ehCerca(tx - 1, ty), ehCerca(tx + 1, ty)), wx(tx), wy(ty), false, 'town');
                }
            }
            for (const o of MAPA.cochos) tile(f, o.i, wx(o.x), wy(o.y));
        }

        /* ---- animais ---- */
        function sincronizarAnimais() {
            const vistos = new Set();
            for (const v of animaisFn()) {
                vistos.add(v.id);
                let a = atores.get(v.id);
                if (!a || a.tipo !== v.tipo) {
                    const area = areaDe(v.tipo);
                    const r = rng(hash(v.id));
                    const x = area.x0 + r() * (area.x1 - area.x0), y = area.y0 + r() * (area.y1 - area.y0);
                    a = {
                        id: v.id, tipo: v.tipo, i: ANIMAL[v.tipo] || 122, area, x, y, tx: x, ty: y,
                        flip: r() < 0.5, espera: r() * 2500, vel: v.tipo === 'galinha' ? 10 : 4
                    };
                    atores.set(v.id, a);
                }
                a.v = v;
            }
            for (const id of [...atores.keys()]) if (!vistos.has(id)) atores.delete(id);
        }

        function mover(dt) {
            for (const a of atores.values()) {
                if (a.v && a.v.estado !== 'produzindo') continue;   // esperando o toque
                if (a.espera > 0) { a.espera -= dt; continue; }
                const dx = a.tx - a.x, dy = a.ty - a.y, d = Math.hypot(dx, dy);
                if (d < 0.5) {
                    a.espera = 800 + Math.random() * 3500;
                    a.tx = a.area.x0 + Math.random() * (a.area.x1 - a.area.x0);
                    a.ty = a.area.y0 + Math.random() * (a.area.y1 - a.area.y0);
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

        /* ---- desenhos auxiliares ---- */
        function balao(bx, by, w, h) {
            q.fillStyle = PAL.o;
            q.fillRect(bx + 1, by, w - 2, h);
            q.fillRect(bx, by + 1, w, h - 2);
            q.fillRect(bx + Math.floor(w / 2) - 2, by + h, 4, 1);
            q.fillRect(bx + Math.floor(w / 2) - 1, by + h + 1, 2, 1);
            q.fillStyle = PAL.w;
            q.fillRect(bx + 1, by + 1, w - 2, h - 2);
            q.fillRect(bx + Math.floor(w / 2) - 1, by + h - 1, 2, 1);
        }

        function barraProgresso(x, y, p) {
            q.fillStyle = PAL.o; q.fillRect(x, y, 12, 3);
            q.fillStyle = PAL.d; q.fillRect(x + 1, y + 1, 10, 1);
            q.fillStyle = PAL.l; q.fillRect(x + 1, y + 1, Math.max(1, Math.round(10 * Math.min(1, p))), 1);
        }

        function moldura(x, y, w, h, cor = PAL.w) {
            q.fillStyle = cor;
            const c = 4;
            q.fillRect(x - 1, y - 1, c, 1); q.fillRect(x - 1, y - 1, 1, c);
            q.fillRect(x + w - c + 1, y - 1, c, 1); q.fillRect(x + w, y - 1, 1, c);
            q.fillRect(x - 1, y + h, c, 1); q.fillRect(x - 1, y + h - c + 1, 1, c);
            q.fillRect(x + w - c + 1, y + h, c, 1); q.fillRect(x + w, y + h - c + 1, 1, c);
        }

        /* ---- construções do jogador ---- */
        function mapaConstrucoes(lista) {
            const m = new Map();
            for (const c of lista) m.set(c.x + ',' + c.y, c.tipo);
            return m;
        }
        // devolve os sprites de uma construção já com o encaixe automático resolvido
        function spritesDe(tipo, x, y, m) {
            const a = arteItem(tipo, EST);
            if (a.auto) {
                const igual = (dx, dy) => m.get((x + dx) + ',' + (y + dy)) === tipo;
                const f2 = a.auto === 'cerca' ? tileCerca : tileTerra;
                return { p: a.p, i: f2(igual(0, -1), igual(0, 1), igual(-1, 0), igual(1, 0)), chao: a.chao };
            }
            return a;
        }

        /* ---- canteiros ---- */
        function desenharCanteiro(p, tempo) {
            const v = visual(p);
            const { x, y } = posCanteiro(p);
            if (!v || v.solo === 'bloqueado') {
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
            if (v.seco) {
                q.fillStyle = PAL.k;
                q.fillRect(x + 4, y + 5, 3, 1); q.fillRect(x + 6, y + 6, 1, 2);
                q.fillRect(x + 9, y + 10, 3, 1); q.fillRect(x + 9, y + 11, 1, 1);
            }
            if (v.planta != null) {
                const bob = v.maduro && Math.floor(tempo / 450) % 2 ? -1 : 0;
                tile(q, v.planta, x, y - 2 + bob);
            }
            if (v.progresso != null) barraProgresso(x + 2, y + T - 3, v.progresso);
            if (v.maduro && !v.cinza && Math.floor(tempo / 300) % 4 !== 0) {
                icone(q, 'brilho', x + 11 + (Math.floor(tempo / 1200) % 2) * -9, y - 2);
            }
            if (v.check) icone(q, 'check', x + 8, y + 9);
            if (v.probs && v.probs.length) {
                const w = v.probs.length * 10 + 3, bx = x + T / 2 - Math.floor(w / 2);
                const by = y - 14 + (Math.floor(tempo / 500) % 2);
                balao(bx, by, w, 12);
                v.probs.forEach((pr, n) => icone(q, pr, bx + 2 + n * 10, by + 2));
            }
            if (v.pegar) icone(q, 'mao', x + 4, y - 12 + (Math.floor(tempo / 400) % 2));
            if (v.pendente && Math.floor(tempo / 150) % 2) {
                q.fillStyle = 'rgba(255,255,255,.35)';
                q.fillRect(x + 1, y + 1, T - 2, T - 2);
            }
        }

        function desenharSinalAnimal(a, tempo) {
            const v = a.v;
            const x = Math.round(a.x), y = Math.round(a.y);
            if (v.estado === 'fome' && v.racao != null) {
                const by = y - 21 + (Math.floor(tempo / 500) % 2);
                balao(x - 2, by, 20, 18);
                tile(q, v.racao, x, by + 1);
            } else if (v.estado === 'pronto' && v.produto != null) {
                const by = y - 21 + (Math.floor(tempo / 350) % 2);
                balao(x - 2, by, 20, 18);
                tile(q, v.produto, x, by + 1);
                if (Math.floor(tempo / 300) % 3) icone(q, 'brilho', x + 15, by - 3);
            } else if (v.estado === 'produzindo' && v.progresso != null) {
                barraProgresso(x + 2, y + T, v.progresso);
            }
        }

        /* ---- modo construir: grade, fantasma do item e seleção ---- */
        function desenharGrade(m, tempo) {
            for (let ty = 0; ty < MAPA.h; ty++) {
                for (let tx = 0; tx < MAPA.w; tx++) {
                    const x = wx(tx), y = wy(ty);
                    if (!livre(tx, ty)) {
                        q.fillStyle = 'rgba(195,75,53,.16)';
                        q.fillRect(x, y, T, T);
                    } else {
                        q.fillStyle = 'rgba(63,38,49,.18)';
                        q.fillRect(x, y, 1, 1); q.fillRect(x + T - 1, y, 1, 1);
                        q.fillRect(x, y + T - 1, 1, 1); q.fillRect(x + T - 1, y + T - 1, 1, 1);
                    }
                }
            }
            const sel = construcao.movendo;
            if (sel) moldura(wx(sel.x), wy(sel.y), T, T, Math.floor(tempo / 250) % 2 ? PAL.y : PAL.w);
            if (hover && typeof hover === 'object' && 'tx' in hover) {
                const { tx, ty } = hover;
                const x = wx(tx), y = wy(ty);
                const ocupado = m.has(tx + ',' + ty);
                const pode = livre(tx, ty) && (construcao.modo === 'colocar' || construcao.movendo ? !ocupado : ocupado);
                if (pode && construcao.modo === 'colocar' && construcao.tipo) {
                    const temp = new Map(m); temp.set(tx + ',' + ty, construcao.tipo);
                    const s = spritesDe(construcao.tipo, tx, ty, temp);
                    q.globalAlpha = 0.65;
                    if (s.topo != null) tile(q, s.topo, x, y - T, false, s.p);
                    tile(q, s.i, x, y, false, s.p);
                    q.globalAlpha = 1;
                }
                moldura(x, y, T, T, pode ? PAL.w : PAL.r);
            }
        }

        /* ---- loop ---- */
        let ultimo = performance.now(), ultimoDesenho = 0;
        const inercia = { vx: 0, vy: 0 };   // px do jogo por ms, depois de soltar o dedo
        function quadroAnim(agora) {
            const dt = Math.min(100, agora - ultimo);
            ultimo = agora;
            mover(dt);
            const deslizando = !toque && (Math.abs(inercia.vx) + Math.abs(inercia.vy)) > 0.002;
            if (deslizando) {
                cam.x += inercia.vx * dt;
                cam.y += inercia.vy * dt;
                const atrito = Math.pow(0.92, dt / 16);
                inercia.vx *= atrito; inercia.vy *= atrito;
                limitarCamera();
            }
            const movendo = deslizando || (toque && toque.arrastou) || precisaDesenhar;
            if (movendo || agora - ultimoDesenho >= 1000 / 24) {
                ultimoDesenho = agora;
                precisaDesenhar = false;
                desenhar(agora - t0);
            }
            requestAnimationFrame(quadroAnim);
        }

        function desenhar(tempo) {
            sincronizarAnimais();
            q.drawImage(fundo, 0, 0);

            const lista = construcoesFn() || [];
            const m = mapaConstrucoes(lista);
            const pe = [];   // coisas "em pé", ordenadas pela altura
            for (const c of lista) {
                const s = spritesDe(c.tipo, c.x, c.y, m);
                if (s.chao) tile(q, s.i, wx(c.x), wy(c.y), false, s.p);   // caminho/flores: chão
                else pe.push({ ...s, x: wx(c.x), y: wy(c.y), flip: false, bob: 0 });
            }

            for (let p = 0; p < 18; p++) desenharCanteiro(p, tempo);

            for (const a of atores.values()) {
                const parado = a.v && a.v.estado !== 'produzindo';
                pe.push({ p: 'farm', i: a.i, x: a.x, y: a.y, flip: a.flip, bob: parado && Math.floor(tempo / 600) % 2 ? -1 : 0 });
            }
            const andando = fazendeiro.passo > 0;
            pe.push({ p: 'farm', i: 109, x: fazendeiro.x, y: fazendeiro.y, flip: fazendeiro.flip, bob: andando && Math.floor(tempo / 120) % 2 ? -1 : 0 });
            pe.sort((a, b) => a.y - b.y).forEach((a) => {
                const x = Math.round(a.x), y = Math.round(a.y) + a.bob;
                if (a.topo != null) tile(q, a.topo, x, y - T, a.flip, a.p);
                tile(q, a.i, x, y, a.flip, a.p);
            });

            for (const a of atores.values()) if (a.v) desenharSinalAnimal(a, tempo);

            if (construcao.ativo) {
                desenharGrade(m, tempo);
            } else if (typeof hover === 'number') {
                const { x, y } = posCanteiro(hover);
                moldura(x, y, T, T);
            } else if (hover === 'celeiro') {
                const c = retCeleiro();
                moldura(c.x, c.y + T, c.w, c.h - T);
            } else if (typeof hover === 'string' && hover.startsWith('a:')) {
                const a = atores.get(idDoHover(hover));
                if (a) moldura(Math.round(a.x), Math.round(a.y), T, T);
            }

            // recorte da câmera ampliado para a tela
            ctx.imageSmoothingEnabled = false;
            ctx.fillStyle = PAL.g;
            ctx.fillRect(0, 0, canvas.width, canvas.height);
            const k = escala * dpr;
            ctx.drawImage(mundo, 0, 0, MW, MH, -Math.round(cam.x * k), -Math.round(cam.y * k), MW * k, MH * k);
        }

        /* ---- entrada: toque/mouse, arrastar para mover a câmera ---- */
        const idDoHover = (h) => {
            const bruto = h.slice(2);
            return atores.has(bruto) ? bruto : Number(bruto);
        };
        const paraMundo = (clientX, clientY) => ({ x: cam.x + clientX / escala, y: cam.y + clientY / escala });

        function alvoEm(clientX, clientY) {
            const { x: px, y: py } = paraMundo(clientX, clientY);
            const tx = Math.floor(px / T) - MARGEM, ty = Math.floor(py / T) - MARGEM;
            if (construcao.ativo) return dentroTerreno(tx, ty) ? { tx, ty } : null;
            const lista = [...atores.values()].sort((a, b) => b.y - a.y);
            for (const a of lista) {
                const topo = a.v && a.v.estado !== 'produzindo' ? a.y - 22 : a.y;
                if (px >= a.x - 1 && px < a.x + T + 1 && py >= topo && py < a.y + T) return 'a:' + a.id;
            }
            const cx = wx(MAPA.campo.x), cy = wy(MAPA.campo.y);
            if (px >= cx && py >= cy && px < cx + 6 * T && py < cy + 3 * T) {
                return Math.floor((py - cy) / T) * 6 + Math.floor((px - cx) / T);
            }
            const c = retCeleiro();
            if (px >= c.x && py >= c.y && px < c.x + c.w && py < c.y + c.h) return 'celeiro';
            return null;
        }

        function traduzir(alvo) {
            if (typeof alvo === 'string' && alvo.startsWith('a:')) return { animal: idDoHover(alvo) };
            return alvo;
        }

        function mesmoAlvo(a, b) {
            if (a && b && typeof a === 'object' && typeof b === 'object') return a.tx === b.tx && a.ty === b.ty;
            return a === b;
        }

        let toque = null;   // { id, x, y, camX, camY, arrastou, ultX, ultY, ultT }
        canvas.addEventListener('pointerdown', (e) => {
            if (toque) return;   // ignora o segundo dedo
            inercia.vx = inercia.vy = 0;
            toque = { id: e.pointerId, x: e.clientX, y: e.clientY, camX: cam.x, camY: cam.y, arrastou: false,
                      ultX: e.clientX, ultY: e.clientY, ultT: performance.now() };
            if (e.pointerType !== 'mouse') { try { canvas.setPointerCapture(e.pointerId); } catch { /* ignora */ } }
        });
        canvas.addEventListener('pointermove', (e) => {
            if (toque && toque.id === e.pointerId) {
                const dx = e.clientX - toque.x, dy = e.clientY - toque.y;
                if (!toque.arrastou && Math.hypot(dx, dy) > 8) {
                    toque.arrastou = true;
                    try { canvas.setPointerCapture(e.pointerId); } catch { /* ignora */ }
                }
                if (toque.arrastou) {
                    const agoraT = performance.now(), passo = Math.max(1, agoraT - toque.ultT);
                    // velocidade suavizada (px do jogo por ms) para a inércia ao soltar
                    inercia.vx = inercia.vx * 0.6 + (-(e.clientX - toque.ultX) / escala / passo) * 0.4;
                    inercia.vy = inercia.vy * 0.6 + (-(e.clientY - toque.ultY) / escala / passo) * 0.4;
                    toque.ultX = e.clientX; toque.ultY = e.clientY; toque.ultT = agoraT;
                    cam.x = toque.camX - dx / escala;
                    cam.y = toque.camY - dy / escala;
                    limitarCamera();
                    canvas.style.cursor = 'grabbing';
                    return;
                }
            }
            const alvo = alvoEm(e.clientX, e.clientY);
            if (!mesmoAlvo(alvo, hover)) {
                hover = alvo;
                canvas.style.cursor = alvo == null ? 'default' : 'pointer';
                if (cb.aoPassar) cb.aoPassar(traduzir(alvo));
            }
        });
        const soltar = (e) => {
            if (!toque || toque.id !== e.pointerId) return;
            const arrastou = toque.arrastou;
            if (!arrastou || performance.now() - toque.ultT > 80) inercia.vx = inercia.vy = 0;
            toque = null;
            canvas.style.cursor = 'default';
            if (arrastou || e.type === 'pointercancel') return;
            acionar(e.clientX, e.clientY);
        };
        // um toque/clique sem arrastar: aciona o que estiver embaixo
        function acionar(clientX, clientY) {
            const bruto = alvoEm(clientX, clientY);
            const alvo = traduzir(bruto);
            hover = bruto;
            if (alvo == null) return;
            if (cb.aoPassar) cb.aoPassar(alvo);
            if (typeof alvo === 'object' && 'tx' in alvo) { if (cb.aoTile) cb.aoTile(alvo.tx, alvo.ty); }
            else if (alvo === 'celeiro') { if (cb.aoCeleiro) cb.aoCeleiro(); }
            else if (typeof alvo === 'object') { if (cb.aoAnimal) cb.aoAnimal(alvo.animal); }
            else if (cb.aoCanteiro) cb.aoCanteiro(alvo);
        }
        canvas.addEventListener('pointerup', soltar);
        canvas.addEventListener('pointercancel', soltar);
        canvas.addEventListener('pointerleave', () => { if (!toque) hover = null; });

        window.addEventListener('resize', redimensionar);

        return {
            iniciar() {
                montarFundo();
                redimensionar();
                requestAnimationFrame(quadroAnim);
            },
            definirMargens(topo, base) {
                if (topo === margem.topo && base === margem.base) return;
                margem = { topo, base };
                redimensionar();
            },
            definirVisual(fn) { visual = fn; },
            definirAnimais(fn) { animaisFn = fn; },
            definirConstrucoes(fn) { construcoesFn = fn; },
            definirModoConstrucao(estado) { construcao = estado || { ativo: false }; },
            irAte(p) {
                const { x, y } = posCanteiro(p);
                fazendeiro.tx = x;
                fazendeiro.ty = y + T - 4;
            },
            irAteAnimal(id) {
                const a = atores.get(id);
                if (!a) return;
                fazendeiro.tx = a.x + (a.x > fazendeiro.x ? -12 : 12);
                fazendeiro.ty = a.y;
            },
            voltarParaCasa() {
                fazendeiro.tx = wx(MAPA.fazendeiro.x);
                fazendeiro.ty = wy(MAPA.fazendeiro.y);
            },
            telaDoCanteiro(p) {
                const { x, y } = posCanteiro(p);
                return { x: (x + T / 2 - cam.x) * escala, y: (y - 2 - cam.y) * escala };
            },
            telaDoAnimal(id) {
                const a = atores.get(id);
                return a ? { x: (a.x + T / 2 - cam.x) * escala, y: (a.y - 4 - cam.y) * escala } : { x: innerWidth / 2, y: innerHeight / 2 };
            },
            telaDoTile(tx, ty) {
                return { x: (wx(tx) + T / 2 - cam.x) * escala, y: (wy(ty) - 2 - cam.y) * escala };
            }
        };
    }

    window.FazendaArte = {
        carregar,
        criarCena,
        htmlTile,
        htmlIcone,
        htmlItem,
        ANIMAL,
        MAPA,
        livre,
        estacao,
        cultura: (id) => CULTURAS[id] || CULTURA_PADRAO
    };
})();
