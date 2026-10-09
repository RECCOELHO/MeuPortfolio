/* ============================================================
   FAZENDINHA SECRETA — arte e cena
   Pixel art dos pacotes "Tiny Farm", "Tiny Town" e "Tiny Ski" do
   Kenney (CC0, kenney.nl), desenhada num <canvas>. Os ícones pequenos
   (moeda, XP, praga...) são desenhados aqui, na mesma paleta.

   A fazenda começa com 22 x 13 quadrados cercados de mata e cresce
   até 32 x 20 com os terrenos comprados (ZONAS). Os canteiros têm
   lugar livre (x, y) e se emendam em fileiras quando ficam lado a lado.
   Máquinas: pacote "Tiny Factory" do Kenney (CC0).

   Expõe window.FazendaArte com:
     carregar()                → Promise quando a arte estiver pronta
     criarCena(canvas, cb)     → motor da cena
     htmlTile(i, px, pacote)   → <span> com um sprite (para a UI)
     htmlIcone(nome, px)       → <img> com um ícone pixel
     htmlItem(id, px)          → <span> com a arte de um item construível
     cultura(id), ANIMAL       → sprites de culturas e animais
     estacao(), livre(x, y)    → estação do ano e se um quadrado aceita construção
     ZONAS                     → terrenos à venda (iguais a fazenda_zonas no SQL)
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

    /* ---------- Mapa da fazenda (precisa bater com fazenda_livre no SQL) ---------- */
    const MAPA = {
        w: 32, h: 20,                                // tamanho máximo, com todos os terrenos
        celeiro: { x: 1, y: 1 },                     // 3 x 6
        casa: { x: 5, y: 1 },                        // 3 x 3
        campo: { x: 9, y: 4 },                       // onde os 6 primeiros canteiros nascem
        fazendeiro: { x: 8, y: 4 },
        galinheiro: { x: 0, y: 7, w: 7, h: 2 },
        pasto: { x: 16, y: 0, w: 6, h: 7 },          // cercado, porteira embaixo
        porteira: [18, 19],
        cochos: [{ i: 110, x: 18, y: 1 }, { i: 111, x: 19, y: 1 }],
        // celeiro, casa, galinheiro e pasto: o resto do terreno é livre (até para canteiros)
        reservas: [
            { x: 1, y: 1, w: 3, h: 6 }, { x: 5, y: 1, w: 3, h: 3 }, { x: 0, y: 7, w: 7, h: 2 },
            { x: 16, y: 0, w: 6, h: 7 }
        ]
    };
    const MARGEM = 9;   // quadrados de mata em volta do terreno

    /* ---------- Terrenos: começa com BASE e compra as ZONAS em ordem ----------
       (precisa bater com fazenda_zonas no SQL; placa = onde fica a placa de "à venda") */
    const BASE = { x: 0, y: 0, w: 22, h: 13 };
    const ZONAS = [
        { n: 1, x: 0, y: 13, w: 22, h: 7, placa: { x: 10, y: 13 } },
        { n: 2, x: 22, y: 0, w: 10, h: 13, placa: { x: 22, y: 9 } },
        { n: 3, x: 22, y: 13, w: 10, h: 7, placa: { x: 23, y: 14 } }
    ];
    let zonasAtuais = 0;   // terrenos da fazenda que está na tela (a sua ou a do vizinho)
    const dentroRet = (r, x, y) => x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h;
    const areasDoTerreno = (zonas = zonasAtuais) => [BASE, ...ZONAS.filter((z) => z.n <= zonas)];
    function noTerreno(x, y, zonas = zonasAtuais) {
        return areasDoTerreno(zonas).some((r) => dentroRet(r, x, y));
    }
    // dá para construir/pôr canteiro em (x, y)? (dentro do terreno e fora das áreas fixas)
    function livre(x, y) {
        return noTerreno(x, y) && !MAPA.reservas.some((r) => dentroRet(r, x, y));
    }

    /* ---------- Estação: a do servidor; antes de entrar, a mesma conta dele ---------- */
    let estacaoServidor = null;
    function estacao() {
        try {
            const forcada = new URLSearchParams(location.search).get('estacao');
            if (['primavera', 'verao', 'outono', 'inverno'].includes(forcada)) return forcada;
        } catch { /* ignora */ }
        if (estacaoServidor) return estacaoServidor;
        // igual a fazenda_estacao_em no SQL: 4 estações por semana, 42 h cada, desde segunda 0h
        const b = new Date(Date.now() - 3 * 3600e3);   // Brasília: UTC-3 o ano todo
        const min = ((b.getUTCDay() + 6) % 7) * 1440 + b.getUTCHours() * 60 + b.getUTCMinutes();
        return ['primavera', 'verao', 'outono', 'inverno'][Math.floor(min / 2520)];
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
        la:       { fases: [74, 74, 74], murcho: 74, item: 74, semente: 74 },
        leite:    { fases: [123, 123, 123], murcho: 123, item: 123, semente: 123 },
        // produtos dos animais novos (1000+ = arte própria, ver PROPRIA abaixo)
        pelo:     { fases: [1004, 1004, 1004], murcho: 1004, item: 1004, semente: 1004 },
        pena:     { fases: [1003, 1003, 1003], murcho: 1003, item: 1003, semente: 1003 },
        trufa:    { fases: [79, 79, 79], murcho: 79, item: 79, semente: 79 },
        // sementes da estação (broto e meio do pacote; madura e fruta próprias)
        moranguinho: { fases: [52, 53, 1013], murcho: 55, item: 1014, semente: 1014 },
        melancia: { fases: [52, 53, 1015], murcho: 55, item: 1016, semente: 1016 },
        jerimum:  { fases: [52, 53, 1017], murcho: 55, item: 1018, semente: 1018 },
        repolho:  { fases: [52, 53, 1019], murcho: 55, item: 1020, semente: 1020 },
        // produtos das oficinas (arte própria 1005..1012)
        pao:      { fases: [1005, 1005, 1005], murcho: 1005, item: 1005, semente: 1005 },
        queijo:   { fases: [1006, 1006, 1006], murcho: 1006, item: 1006, semente: 1006 },
        molho:    { fases: [1007, 1007, 1007], murcho: 1007, item: 1007, semente: 1007 },
        geleia:   { fases: [1008, 1008, 1008], murcho: 1008, item: 1008, semente: 1008 },
        tecido:   { fases: [1009, 1009, 1009], murcho: 1009, item: 1009, semente: 1009 },
        pipoca:   { fases: [1010, 1010, 1010], murcho: 1010, item: 1010, semente: 1010 },
        bolo:     { fases: [1011, 1011, 1011], murcho: 1011, item: 1011, semente: 1011 },
        salada:   { fases: [1012, 1012, 1012], murcho: 1012, item: 1012, semente: 1012 }
    };
    const CULTURA_PADRAO = CULTURAS.alface;
    const ANIMAL = { galinha: 122, vaca: 121, ovelha: 120, porco: 1000, pato: 1001, coelho: 1002 };
    // bichos pequenos ficam no galinheiro; os grandes, no pasto
    const PEQUENOS = ['galinha', 'pato', 'coelho'];

    /* ---------- Arte própria (desenhada aqui, no estilo do Kenney) ----------
       Os pacotes não têm porco, pato nem coelho: cada sprite é um 16 x 16 em
       texto (uma letra por cor, "." = transparente). Índices 1000+ em tile(). */
    const PAL_PROPRIA = {
        a: '#3f2631', e: '#262b44', d: '#ffffff', f: '#c0cbdc', l: '#8b9bb4', i: '#e38628',
        j: '#f7c282', k: '#e19a65', m: '#ff9aa8', P: '#f5a3b0', Q: '#d27688', R: '#e98b9b',
        // produtos das oficinas
        w: '#e8a053', x: '#f8d08f', y: '#b8692f', G: '#ffe08a', g: '#fdbe53', H: '#d99a2b',
        X: '#d9452f', Z: '#9e2a1f', U: '#9b4ca3', V: '#6b2f74', B: '#79a7e8', c: '#f28462',
        b: '#c34b35', v: '#4e974c', h: '#84c669', n: '#b4673a',
        // plantas da estação
        O: '#f0a04b', N: '#c96b28', L: '#3e8948', M: '#9fd06c', r: '#e8434a', s: '#fbe7a1', C: '#b9e08a', D: '#6aa84f',
        // máquinas elétricas
        E: '#3b5dc9', F: '#29366f', K: '#566c86', W: '#a7f070'
    };
    const PROPRIA = [
        // 0 porco
        ['................', '................', '..........a..a..', '.........aQaaQa.', '...aaaaaaaPPPPa.', '..aPPPPPPPPPPPPa',
         '.aaPPPPPPPPPePPa', 'aQaPPPPPPPPPPRRa', '.aaPPPPPPPPPPRRa', '..aPPPPPPPPPPPa.', '..aQPPPPPPPPPQa.', '..aaQQQQQQQQQaa.',
         '...aQa....aQa...', '...aaa....aaa...', '................', '................'],
        // 1 pato
        ['................', '................', '.........aaaa...', '........adddda..', '........addedaaa', '........addddiia',
         '........addddaaa', '.aa.....addda...', '.adaaaaadddda...', '.addddddddddda..', '.adfddddddddda..', '.aadffffddddfa..',
         '..aafffffffaa...', '....aia..aia....', '....aaa..aaa....', '................'],
        // 2 coelho
        ['..........a.a...', '.........ajaja..', '.........ajaja..', '.........amama..', '........ajjjjja.', '........ajjejja.',
         '....aaaaajjjjmja', '...ajjjjjjjjjjaa', '..ajjjjjjjjjja..', '.adajjjjjjjjja..', '.addjjjjjjjjja..', '..aajkkjjjjkka..',
         '...akkaaaakka...', '...aaa....aaa...', '................', '................'],
        // 3 pena
        ['................', '...........aa...', '.........aadda..', '........adddfa..', '.......addddfa..', '......adddlfa...',
         '.....adddlfa....', '....addflfa.....', '...addflfa......', '...adflfa.......', '...aflfa........', '..alaaa.........',
         '.ala............', '.aa.............', '................', '................'],
        // 4 pelo de coelho
        ['................', '................', '................', '.....aaaaaa.....', '....ajjdjjja....', '...ajdjjjjjja...',
         '..ajjjjjjdjjja..', '..ajdjjjjjjjja..', '..ajjjjjdjjjka..', '..ajjjjjjjjkka..', '...ajjjjjjkka...', '....akkkkkka....',
         '.....aaaaaa.....', '................', '................', '................'],
        // 5 pao
        ['................', '................', '................', '................', '.....aaaaaa.....', '...aawwwwwwaa...', '..awwxwwxwwxwa..', '.awwxxwwxxwwxwa.', '.awwwwwwwwwwwwa.', '.aywwwwwwwwwwya.', '.ayyyyyyyyyyyya.', '..aayyyyyyyyaa..', '....aaaaaaaa....', '................', '................', '................'],
        // 6 queijo
        ['................', '................', '................', '...........aa...', '.........aaGGa..', '.......aaGGGGa..', '.....aaGGGGGGa..', '...aaGGGGGGGGa..', '.aaGGGGGGGGGGa..', '.aggHgggggHgga..', '.agggggHggggga..', '.agHgggggggHga..', '.aaaaaaaaaaaaa..', '................', '................', '................'],
        // 7 molho
        ['................', '................', '.....aaaaaa.....', '....allllllla...', '....aaaaaaaaa...', '...adXXXXXXXXa..', '...adXXXXXXXXa..', '...aXjjjjjjXXa..', '...aXjjjjjjXZa..', '...aXXXXXXXXZa..', '...aZXXXXXXZZa..', '....aaaaaaaaa...', '................', '................', '................', '................'],
        // 8 geleia
        ['................', '................', '.....aaaaaa.....', '....allllllla...', '....aaaaaaaaa...', '...adUUUUUUUUa..', '...adUUUUUUUUa..', '...aUjjjjjjUUa..', '...aUjjjjjjUVa..', '...aUUUUUUUUVa..', '...aVUUUUUUVVa..', '....aaaaaaaaa...', '................', '................', '................', '................'],
        // 9 tecido
        ['................', '................', '................', '................', '..aaaaaaaaaaaa..', '..aBBBBBBBBBBa..', '..aBdBBBBBBdBa..', '..aBBBBBBBBBBa..', '..aaaaaaaaaaaa..', '..acccccccccca..', '..acdccccccdca..', '..acccccccccca..', '..aaaaaaaaaaaa..', '................', '................', '................'],
        // 10 pipoca
        ['................', '................', '....aaa.aaa.....', '...adddadddda...', '..adddddgddda...', '..adgdddddddda..', '..aaaaaaaaaaaa..', '..abdbdbdbdbda..', '..abdbdbdbdbda..', '...abdbdbdbda...', '...abdbdbdbda...', '....aaaaaaaa....', '................', '................', '................', '................'],
        // 11 bolo
        ['................', '................', '................', '................', '..........aa....', '........aamma...', '......aammmma...', '....aammmmmma...', '..aammmmmmmma...', '.amjjjjjjjjjja..', '.addddddddddda..', '.ajjjjjjjjjjja..', '.aaaaaaaaaaaaa..', '................', '................', '................'],
        // 12 salada
        ['................', '................', '................', '....ava.ava.....', '...avhvavhva....', '..avhbbvhvhva...', '.avhvhvbbvhvha..', '.aaaaaaaaaaaaa..', '.annnnnnnnnnna..', '..annnnnnnnna...', '...annnnnnna....', '....aaaaaaa.....', '................', '................', '................', '................'],
        // 13 morango (planta)
        ['................', '................', '................', '.....aaaaaa.....', '...aavhvvhvaa...', '..avhvvhvvhvva..', '..avvhvrrvhvva..', '.avhvvarrrahvva.', '.avvhvvarravhva.', '.avrrvhvaavhvva.', '.arrravvhvvvva..', '..arrahvvvhva...', '...aaavvvvaa....', '......aaaa......', '................', '................'],
        // 14 morango
        ['................', '................', '......vv.v......', '.....vhvvhv.....', '....aavvvvaa....', '...arrrrrrrra...', '..arrsrrrsrrra..', '..arrrrrrrrrra..', '..arsrrrsrrsra..', '...arrrrrrrra...', '...arrsrrrsra...', '....arrrrrra....', '.....arrrra.....', '......aaaa......', '................', '................'],
        // 15 melancia (planta)
        ['................', '................', '.......ava......', '......avhva.....', '.....aaavaaa....', '...aaMMLMMLaa...', '..aMLMMLMMLMMa..', '.aMMLMMLMMLMMLa.', '.aMMLMMLMMLMMLa.', '.aMMLMMLMMLMMLa.', '..aMLMMLMMLMMa..', '...aaMMLMMLaa...', '.....aaaaaa.....', '................', '................', '................'],
        // 16 melancia
        ['................', '................', '................', '................', '.....aaaaaa.....', '...aaMMLMMLaa...', '..aMLMMLMMLMMa..', '.aMMLMMLMMLMMLa.', '.aMMLMMLMMLMMLa.', '.aMMLMMLMMLMMLa.', '..aMLMMLMMLMMa..', '...aaMMLMMLaa...', '.....aaaaaa.....', '................', '................', '................'],
        // 17 abóbora (planta)
        ['................', '................', '....avhva.ava...', '....avvvaavhva..', '.....aavvvaa....', '....aaaaaaaa....', '...aONOONOONa...', '..aONOONOONOOa..', '.aONOONOONOONOa.', '.aONOONOONOONOa.', '.aNNONNONNONNNa.', '..aNNNNNNNNNNa..', '...aaaaaaaaaa...', '................', '................', '................'],
        // 18 abóbora
        ['................', '................', '................', '.......aa.......', '......avva......', '....aaaaaaaa....', '...aONOONOONa...', '..aONOONOONOOa..', '.aONOONOONOONOa.', '.aONOONOONOONOa.', '.aNNONNONNONNNa.', '..aNNNNNNNNNNa..', '...aaaaaaaaaa...', '................', '................', '................'],
        // 19 repolho (planta)
        ['................', '................', '................', '................', '.....aaaaaa.....', '...aaCCDCCCaa...', '..aCCDCCCDCCCa..', '.aCDCCCDDCCCDCa.', '.aCDCCDCCDCCDCa.', '.aDCCDCCCCDCCDa.', '..aDCDCCCCDCDa..', '..avvaaaaaavva..', '..avva....avva..', '...aa......aa...', '................', '................'],
        // 20 repolho
        ['................', '................', '................', '................', '.....aaaaaa.....', '...aaCCDCCCaa...', '..aCCDCCCDCCCa..', '.aCDCCCDDCCCDCa.', '.aCDCCDCCDCCDCa.', '.aDCCDCCCCDCCDa.', '..aDCDCCCCDCDa..', '...aaDDDDDDaa...', '.....aaaaaa.....', '................', '................', '................'],
        // 21 painel solar
        ['................', '................', '................', '.aaaaaaaaaaaaa..', '.aBBEFBBEFBBEa..', '.aBEEFBEEFBEEa..', '.aFFFFFFFFFFFa..', '.aBEEFBEEFBEEa..', '.aEEEFEEEFEEEa..', '.aaaaaaaaaaaaa..', '......aKa.......', '......aKa.......', '......aKa.......', '....aaaKaaa.....', '....aKKKKKa.....', '....aaaaaaa.....'],
        // 22 turbina (torre)
        ['......adfa......', '......adfa......', '......adfa......', '......adfa......', '......adfa......', '.....addfla.....', '.....addfla.....', '.....addfla.....', '.....addfla.....', '.....addfla.....', '.....addfla.....', '.....adeela.....', '.....adeela.....', '....aadddlaa....', '...alllllllla...', '...aaaaaaaaaa...'],
        // 23 turbina (hélice 1)
        ['......adda......', '......adda......', '......adda......', '......adda......', '......adda......', '......adda......', '......aKKa......', '....aadKKdaa....', '...adddddddda...', '.aadddadfadddaa.', 'adddaaadfaadddda', 'adaa..adfa.aadda', '.a....adfa...aa.', '......adfa......', '......adfa......', '......adfa......'],
        // 24 turbina (hélice 2)
        ['................', '................', '.aa..........aa.', 'addaa......aadda', 'adddda....adddda', '.aadddaaaadddaa.', '...adddKKddaa...', '....aadKKaa.....', '......adda......', '......adda......', '......adda......', '......adda......', '......adfa......', '......adfa......', '......adfa......', '......adfa......'],
        // 25 estufa elétrica
        ['................', '................', '................', '.....aaaaaa.....', '....adBGGBfa....', '...adfBBBBfBa...', '..aBdfBBBBfBBa..', '..adfffffffffa..', '.aBBBfBBBBfBBBa.', '.aBBvfBBvBfBvBa.', '.aBvhvBvhvfvhBa.', '.aBBBfhBBBhBBBa.', 'alllllllllllllla', 'aKKKKKKKKKKKKKKa', 'aKKKKKKKKKKKKKKa', '.aaaaaaaaaaaaaa.'],
        // 26 reator (cima, esq.)
        ['........dddddd..', '.......dffffddd.', '......ddddddddd.', '.....dddddfffff.', '......ffff.fff..', '..aaaaaffaaaaaaa', '.allllllllllllll', '..adddffffffflll', '..adddffffffflll', '...addffffffflll', '...allllllllllll', '...adddfffffllll', '....addfffffllla', '....addfffffllla', '.....adffffflla.', '.....adffffflla.'],
        // 27 reator (cima, dir.)
        ['................', '................', '................', '................', '................', 'aa..............', 'lla.............', 'la..............', 'la..............', 'a...............', 'a...............', 'a...............', '................', '.........a......', '......aaafaaa...', '.....adfffffla..'],
        // 28 reator (baixo, esq.)
        ['.....addfffflla.', '.....addfffflla.', '.....addfffflla.', '.....addfffflla.', '.....addfffflla.', '.....addfffflla.', '.....addfffflla.', '.....addfffflla.', '.....addfffflla.', '.....adffffflla.', '....addfffffllla', '...adddfffffflll', '...addffffffflll', '..adddffffffflll', '.adddfffffffffll', '..aaaaaaaaaaaaaa'],
        // 29 reator (baixo, dir.)
        ['....addffffflla.', '....affffffflla.', '...affffffffllla', '...affffffffllla', '...allllllllKKKa', '...allllllllKKKa', '...alWllggglKWKa', '...alWlgegegKWKa', '...alllggeggKKKa', '...alllgggggKKKa', '...allllgeglKKKa', 'a..allllllllKKKa', 'a..allllllllKKKa', 'la.aKKKKKKKKKKKa', 'llaaKKKKKKKKKKKa', 'aa..aaaaaaaaaaa.']
    ];
    const atlasProprio = document.createElement('canvas');
    atlasProprio.width = 12 * 16;
    atlasProprio.height = LINHAS * 16;   // mesmo formato dos pacotes (htmlTile conta 12 x 11)
    {
        const g = atlasProprio.getContext('2d');
        PROPRIA.forEach((linhas, n) => linhas.forEach((linha, y) => [...linha].forEach((ch, x) => {
            if (PAL_PROPRIA[ch]) { g.fillStyle = PAL_PROPRIA[ch]; g.fillRect((n % COLS) * 16 + x, Math.floor(n / COLS) * 16 + y, 1, 1); }   // em grade, como os pacotes
        })));
    }
    let urlPropria = null;

    // ajudantes: quem é (pessoa) e o que carrega (ferramenta) — tudo dos pacotes
    const MOCA = { p: 'farm', i: 108 }, MOCO = { p: 'factory', i: 120 };
    const AJUDANTE_ARTE = {
        granjeira: { ...MOCA, ferramenta: 125 }, lavrador: { ...MOCO, ferramenta: 86 },
        jardineiro: { ...MOCO, ferramenta: 84 }, coelheira: { ...MOCA, ferramenta: 8 },
        vaqueiro: { ...MOCO, ferramenta: 123 }, colhedor: { ...MOCO, ferramenta: 88 },
        semeadora: { ...MOCA, ferramenta: 10 }, patinheiro: { ...MOCO, ferramenta: 1003 },
        pastora: { ...MOCA, ferramenta: 74 }, porqueiro: { ...MOCO, ferramenta: 79 }
    };

    let quadroHelice = 0;   // a turbina eólica gira (troca a cada poucos quadros)

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
            case 'casa_vermelha': return { p: 'town', w: 3, h: 3, grade: [[52, 53, 55], [64, 65, 67], [84, 85, 75]] };
            case 'casa_azul': return { p: 'town', w: 3, h: 3, grade: [[48, 49, 51], [60, 61, 63], [88, 89, 79]] };
            case 'canteiro': return { p: 'farm', i: 1 };
            // oficinas (2 x 3)
            case 'saladeira': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [86, 87]] };
            case 'pipocaria': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [86, 87]] };
            case 'fabrica_molho': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [88, 91]] };
            case 'queijaria': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [88, 91]] };
            case 'padaria': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [84, 87]] };
            case 'confeitaria': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [90, 91]] };
            case 'tecelagem': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [85, 75]] };
            case 'casa_geleia': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [89, 79]] };
            // máquinas (Tiny Factory)
            case 'irrigador': return { p: 'factory', i: 91 };
            case 'pulverizador': return { p: 'factory', i: 126 };
            case 'alarme': return { p: 'factory', i: 129 };
            case 'robo_capina': return { p: 'factory', i: 110 };
            case 'trator': return { p: 'factory', i: 98 };
            case 'colheitadeira': return { p: 'factory', i: 100 };
            // energia (nível 16+): arte própria e Tiny Factory
            case 'painel_solar': return { p: 'farm', i: 1021 };
            case 'bateria': return { p: 'factory', i: 84 };
            case 'turbina': return { p: 'farm', i: 1022, topo: quadroHelice ? 1024 : 1023 };
            case 'estufa': return { p: 'farm', i: 1025 };
            case 'gerador_bio': return { p: 'factory', i: 75 };
            case 'triturador': return { p: 'factory', i: 101 };
            case 'supercap': return { p: 'factory', i: 86 };
            case 'fabrica_auto': return { p: 'factory', w: 2, h: 2, grade: [[76, 77], [88, 89]] };
            case 'robo_colheita': return { p: 'factory', i: 108 };
            case 'aspersor': return { p: 'factory', i: 94 };
            case 'reator': return { p: 'farm', w: 2, h: 2, grade: [[1026, 1027], [1028, 1029]] };
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
        // mão aberta (pegar do vizinho): 3 dedos + polegar, estilo luva de desenho
        mao: ['......oo.....', '...oooktooo..', '..oktoktokto.', '..oktoktokto.', '..oktoktokto.', 'oooktoktokto.', 'okkkkkkkkkto.', 'okkkkkkkkkto.', '.okkkkkkkkto.', '..okkkkkkkto.', '..otkkkkkkto.', '...otttttto..', '....oooooo...'],
        // guaxinim mascarado: quem pegou da sua plantação (diário)
        guaxinim: ['.oo.......oo.', 'oSso.....osSo', 'oSSSoooooSSSo', 'oSSSSSSSSSSSo', 'oooooSSSooooo', 'oowwooSoowwoo', 'oSoooSSSoooSo', 'oSSwwwwwwwSSo', '.oSwwwowwwSo.', '..oSwwwwwSo..', '...ooooooo...'],
        sol: ['....y....', '.y.ooo.y.', '..oyyyo..', '.oywyyyo.', 'yoyyyyyoy', '.oyyyYyo.', '..oyYYo..', '.y.ooo.y.', '....y....'],
        calor: ['....Y....', '.Y.ooo.Y.', '..oYYYo..', '.oYwYYYo.', 'YoYYYYYoY', '.oYYYrYo.', '..oYrro..', '.Y.ooo.Y.', '....Y....'],
        nuvem: ['....ooo....', '...owwwo...', '.oowwwwwoo.', 'owwwwwwwwso', 'owwwwwwwsso', '.ossssssso.', '..ooooooo..'],
        chuva: ['....ooo....', '...owwwo...', '.oowwwwwoo.', 'owwwwwwwsso', '.ossssssso.', '..ooooooo..', '..b..b..b..', '.b..b..b...'],
        vento: ['.....SSS...', 'SSSSSS..S..', '........S..', '.SSSSSSSS..', '...........', 'SSSSSSS....', '.......S...', '......S....'],
        play: ['oo.....', 'owoo...', 'owwwoo.', 'owwwwwo', 'owwwoo.', 'owoo...', 'oo.....'],
        raio: ['...oooo', '..oyyyo', '..oyyo.', '.oyyo..', '.oyyyyo', 'oyyyyo.', 'ooyyo..', '..oyo..', '.oyo...', '.oo....'],
        coracao: ['.oo.oo.', 'orrorRo', 'orwrrRo', 'orrrrRo', '.orrRo.', '..oRo..', '...o...'],
        missao: ['ooooooo.', 'okkkkkko', 'okoooko.', 'okkkkkko', 'okoooko.', 'okkkkkko', 'okooko..', 'okkkkko.', 'oooooo..'],
        mover: ['....o....', '...oko...', '..okkko..', '....o....', 'oko.o.oko', 'okkoooko.', 'oko.o.oko', '....o....', '..okkko..', '...oko...', '....o....'],
        lixeira: ['..ooooo..', 'ooooooooo', 'okkkkkkko', '.okokoko.', '.okokoko.', '.okokoko.', '.okokoko.', '.okkkkko.', '..ooooo..'],
        medalha: ['.oo...oo.', '.obo.obo.', '..obobo..', '...ooo...', '..oyyyo..', '.oywyyYo.', '.oyyyyYo.', '.oyyyYYo.', '..oYYYo..', '...ooo...'],
        medalha_off: ['.oo...oo.', '.oSo.oSo.', '..oSoSo..', '...ooo...', '..ossso..', '.ossssSo.', '.ossssSo.', '.osssSSo.', '..oSSSo..', '...ooo...'],
        som: ['....o....', '...oo.o..', 'oooko..o.', 'okkko.o.o', 'okkko.o.o', 'okkko.o.o', 'oooko..o.', '...oo.o..', '....o....'],
        mudo: ['....o....', '...oo....', 'oooko.o.o', 'okkko..o.', 'okkko.o.o', 'okkko....', 'oooko....', '...oo....', '....o....']
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

    const ARQUIVOS = { farm: 'tiny-farm.png', town: 'tiny-town.png', ski: 'tiny-ski.png', factory: 'tiny-factory.png' };
    const VERSAO_ARTE = '2';   // troque se as imagens dos pacotes mudarem (cache de 4 h do Cloudflare)
    function htmlTile(i, px = 32, pacote = 'farm') {
        if (i >= 1000) { i -= 1000; pacote = 'propria'; }
        const c = i % COLS, l = Math.floor(i / COLS);
        if (pacote === 'propria' && !urlPropria) urlPropria = atlasProprio.toDataURL();
        const img = pacote === 'farm' ? '' : pacote === 'propria' ? `background-image:url('${urlPropria}');`
            : `background-image:url('assets/fazenda/${ARQUIVOS[pacote]}');`;
        return `<span class="px-spr" style="${img}width:${px}px;height:${px}px;background-size:${COLS * px}px ${LINHAS * px}px;background-position:-${c * px}px -${l * px}px" aria-hidden="true"></span>`;
    }

    // Ícone de item para a UI (árvores altas mostram as duas peças)
    function htmlItem(id, px = 32) {
        const a = arteItem(id, estacao());
        if (a.grade) {
            const m = Math.round(px / a.w);
            return `<span class="px-grade" style="width:${m * a.w}px;height:${m * a.h}px;grid-template-columns:repeat(${a.w},${m}px)">${a.grade.flat().map((i) => htmlTile(i, m, a.p)).join('')}</span>`;
        }
        const i = a.auto === 'cerca' ? 45 : a.auto === 'terra' ? 25 : a.i;
        if (a.topo == null) return htmlTile(i, px, a.p);
        const m = Math.round(px / 2);
        return `<span class="px-alto" style="width:${m}px;height:${px}px">${htmlTile(a.topo, m, a.p)}${htmlTile(i, m, a.p)}</span>`;
    }

    /* ---------- Atlas ---------- */
    const atlas = { farm: new Image(), town: new Image(), ski: new Image(), factory: new Image() };
    let atlasPronto = null;
    function carregar() {
        if (!atlasPronto) {
            atlasPronto = Promise.all(Object.entries(atlas).map(([p, img]) => new Promise((ok, erro) => {
                img.onload = ok;
                img.onerror = () => erro(new Error('Não deu para carregar a arte da fazenda.'));
                img.src = 'assets/fazenda/' + ARQUIVOS[p] + '?v=' + VERSAO_ARTE;
            })));
        }
        return atlasPronto;
    }

    function tile(ctx, i, x, y, flip, pacote = 'farm') {
        if (i >= 1000) { i -= 1000; pacote = 'propria'; }
        const img = pacote === 'propria' ? atlasProprio : atlas[pacote];
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
        let EST = estacao();   // muda junto com a estação do servidor (definirEstacao)

        // mundo inteiro em pixels do jogo (terreno + mata em volta)
        const MW = (MAPA.w + MARGEM * 2) * T, MH = (MAPA.h + MARGEM * 2) * T;
        const mundo = document.createElement('canvas');
        mundo.width = MW; mundo.height = MH;
        const q = mundo.getContext('2d');
        const fundo = document.createElement('canvas');
        fundo.width = MW; fundo.height = MH;
        const f = fundo.getContext('2d');

        let escala = 3, dpr = 1, vw = 0, vh = 0;           // vw/vh: tela em pixels do jogo
        let escalaBase = 3, zoomFator = 1;                 // zoom: pinça no celular, rodinha no PC
        const cam = { x: 0, y: 0 };
        let margem = { topo: 0, base: 0 };
        let visual = () => null;
        let animaisFn = () => [];
        let ajudantesFn = () => [];                        // [{ id, tipo, area: campo|galinheiro|pasto }]
        let construcoesFn = () => [];
        let canteirosFn = () => [];                        // [{ posicao, x, y }]
        let construcao = { ativo: false };                 // estado do modo construir
        let zonaVenda = null;                              // próximo terreno à venda (ZONAS) ou null
        let clima = null;                                  // sol | nublado | chuva | calor | vento
        let hover = null;                                  // canteiro, 'celeiro', 'a:<id>' ou {tx, ty}
        const atores = new Map();
        const fazendeiro = { x: 0, y: 0, tx: 0, ty: 0, flip: false, passo: 0 };
        const t0 = performance.now();

        /* ---- geometria (coordenadas do mundo, em pixels do jogo) ---- */
        const wx = (tx) => (MARGEM + tx) * T;
        const wy = (ty) => (MARGEM + ty) * T;
        const listaCanteiros = () => canteirosFn() || [];
        function mapaCanteiros(lista) {
            const m = new Map();
            for (const c of lista) m.set(c.x + ',' + c.y, c);
            return m;
        }
        function posCanteiro(p) {
            const c = listaCanteiros().find((k) => k.posicao === p);
            return c ? { x: wx(c.x), y: wy(c.y) } : { x: wx(MAPA.campo.x), y: wy(MAPA.campo.y) };
        }
        // retângulo que contém todo o terreno da fazenda (em quadrados)
        function caixaTerreno() {
            const a = areasDoTerreno();
            return {
                x0: Math.min(...a.map((r) => r.x)), y0: Math.min(...a.map((r) => r.y)),
                x1: Math.max(...a.map((r) => r.x + r.w)), y1: Math.max(...a.map((r) => r.y + r.h))
            };
        }
        // distância (em quadrados) de (tx, ty) até o terreno: 0 dentro
        function distTerreno(tx, ty) {
            return Math.min(...areasDoTerreno().map((r) => Math.max(r.x - tx, tx - (r.x + r.w - 1), r.y - ty, ty - (r.y + r.h - 1), 0)));
        }
        function retCeleiro() {
            return { x: wx(MAPA.celeiro.x), y: wy(MAPA.celeiro.y), w: 3 * T, h: 6 * T };
        }
        function areaDe(tipo) {
            if (tipo === 'campo') {
                // ajudantes da lavoura andam em volta dos canteiros
                const l = listaCanteiros();
                if (l.length) {
                    const xs = l.map((c) => c.x), ys = l.map((c) => c.y);
                    return { x0: wx(Math.min(...xs) - 1), y0: wy(Math.min(...ys)), x1: wx(Math.max(...xs) + 1), y1: wy(Math.max(...ys) + 1) };
                }
                return { x0: wx(MAPA.campo.x), y0: wy(MAPA.campo.y), x1: wx(MAPA.campo.x + 5), y1: wy(MAPA.campo.y + 1) };
            }
            const a = tipo === 'galinheiro' || PEQUENOS.includes(tipo)
                ? { x: MAPA.galinheiro.x, y: MAPA.galinheiro.y, w: MAPA.galinheiro.w, h: MAPA.galinheiro.h }
                : { x: MAPA.pasto.x + 1, y: MAPA.pasto.y + 2, w: MAPA.pasto.w - 2, h: MAPA.pasto.h - 3 };
            return { x0: wx(a.x), y0: wy(a.y), x1: wx(a.x + a.w - 1), y1: wy(a.y + a.h - 1) };
        }

        /* ---- câmera ---- */
        // a câmera só passeia pelo terreno (mais uma bordinha de mata), nunca se perde no mato
        function faixaCamera() {
            const borda = T * 2;   // um pouco de mata (e a placa do terreno à venda)
            const topo = margem.topo / escala, base = margem.base / escala;
            const cx = caixaTerreno();
            let minX = wx(cx.x0) - borda, maxX = wx(cx.x1) + borda - vw;
            let minY = wy(cx.y0) - borda - topo, maxY = wy(cx.y1) + borda + base - vh;
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

        // escala para o terreno caber na tela (usada no início e quando a fazenda cresce)
        function ajustarEscala() {
            const W = window.innerWidth, H = window.innerHeight;
            const cx = caixaTerreno(), tw = (cx.x1 - cx.x0) * T, th = (cx.y1 - cx.y0) * T;
            const areaW = W - 24;
            const areaH = Math.max(200, H - margem.topo - margem.base - 12);
            let s = Math.min(areaW / tw, areaH / th);
            // celular em pé (ou fazenda grande): não cabe, então usa a altura e deixa arrastar
            if (s < 2.5) s = Math.min(Math.max(areaH / th, 2.5), 3.4);
            s = Math.min(s, 6);
            if (s >= 3) s = Math.floor(s);
            escalaBase = s;
            escala = s * zoomFator;
            vw = W / escala;
            vh = H / escala;
        }

        function redimensionar() {
            const W = window.innerWidth, H = window.innerHeight;
            dpr = Math.min(window.devicePixelRatio || 1, 3);
            canvas.width = Math.round(W * dpr);
            canvas.height = Math.round(H * dpr);
            canvas.style.width = W + 'px';
            canvas.style.height = H + 'px';
            ajustarEscala();
            atores.clear();
            const c = MAPA.fazendeiro;
            fazendeiro.x = fazendeiro.tx = wx(c.x);
            fazendeiro.y = fazendeiro.ty = wy(c.y);
            // começa olhando para o meio da plantação
            const lista = listaCanteiros();
            if (lista.length) {
                focar(wx(lista.reduce((a, k) => a + k.x, 0) / lista.length) + T / 2,
                      wy(lista.reduce((a, k) => a + k.y, 0) / lista.length) + T / 2);
            } else {
                focar(wx(MAPA.campo.x + 3), wy(MAPA.campo.y + 1));
            }
        }

        /* ---- fundo estático: grama, mata, celeiro, casa, pasto ---- */
        const dentroTerreno = (tx, ty) => noTerreno(tx, ty);

        function montarFundo() {
            const r = rng(20261007);
            const corGrama = EST === 'inverno' ? '#9fcf86' : PAL.g;
            f.fillStyle = corGrama;
            f.fillRect(0, 0, MW, MH);

            // neve fora do terreno no inverno, com borda irregular
            if (EST === 'inverno') {
                const img = f.getImageData(0, 0, MW, MH);
                const rets = areasDoTerreno().map((a) => ({ x0: wx(a.x), y0: wy(a.y), x1: wx(a.x + a.w), y1: wy(a.y + a.h) }));
                for (let y = 0; y < MH; y++) {
                    for (let x = 0; x < MW; x++) {
                        let dist = Infinity;
                        for (const a of rets) dist = Math.min(dist, Math.max(a.x0 - x, x - a.x1, a.y0 - y, y - a.y1, 0));
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
                    // perto da placa do terreno à venda fica uma clareira
                    if (zonaVenda && Math.abs(tx - zonaVenda.placa.x) <= 1 && ty >= zonaVenda.placa.y - 1 && ty <= zonaVenda.placa.y + 1) continue;
                    const longe = distTerreno(tx, ty);
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
                        flip: r() < 0.5, espera: r() * 2500, vel: PEQUENOS.includes(v.tipo) ? 10 : 4
                    };
                    atores.set(v.id, a);
                }
                a.v = v;
            }
            for (const h of ajudantesFn() || []) {
                vistos.add(h.id);
                if (atores.has(h.id)) continue;
                const arte = AJUDANTE_ARTE[h.tipo] || MOCO;
                const area = areaDe(h.area);
                const r = rng(hash(h.id));
                const x = area.x0 + r() * (area.x1 - area.x0), y = area.y0 + r() * (area.y1 - area.y0);
                atores.set(h.id, {
                    id: h.id, tipo: h.tipo, i: arte.i, p: arte.p, ferramenta: arte.ferramenta, area, x, y, tx: x, ty: y,
                    flip: r() < 0.5, espera: r() * 2000, vel: 12, ajudante: true
                });
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
                // os sprites do pacote olham para a direita: espelha quando anda para a esquerda
                if (Math.abs(dx) > 0.2) a.flip = dx < 0;
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
        // tipo de cada quadrado + quadrados ocupados (construções e canteiros, menos o "ignorar")
        function mapaConstrucoes(lista, ignorar) {
            const m = new Map();
            m.ocupado = new Set();
            const mesmo = (o) => ignorar && o.x === ignorar.x && o.y === ignorar.y;
            for (const c of lista) {
                m.set(c.x + ',' + c.y, c.tipo);
                if (mesmo(c) && ignorar.tipo !== 'canteiro') continue;
                const a = arteItem(c.tipo, EST);
                for (let dy = 0; dy < (a.h || 1); dy++) {
                    for (let dx = 0; dx < (a.w || 1); dx++) m.ocupado.add((c.x + dx) + ',' + (c.y + dy));
                }
            }
            for (const c of listaCanteiros()) {
                if (mesmo(c) && ignorar.tipo === 'canteiro') continue;
                m.ocupado.add(c.x + ',' + c.y);
            }
            return m;
        }
        // cabe um item de w x h com o canto em (tx, ty)?
        function cabe(tx, ty, w, h, ocupado) {
            for (let dy = 0; dy < h; dy++) {
                for (let dx = 0; dx < w; dx++) {
                    if (!livre(tx + dx, ty + dy) || ocupado.has((tx + dx) + ',' + (ty + dy))) return false;
                }
            }
            return true;
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

        /* ---- canteiros ----
           Sozinho: a peça do Tiny Farm (0 terra clara, 1 arada). Encostados (em fileira, em
           coluna, em L ou em bloco) viram um canteiro grande só: a terra é desenhada aqui,
           com as cores e medidas das tiras do pacote (60-62 / 12-36), borda só nos lados sem
           vizinho, cantos de fora arredondados e a borda dobrando nos cantos de dentro.
           Onde não é terra, volta a grama do fundo (com as flores e a neve da estação). */
        const TERRA = {
            clara: { borda: '#cf8254', miolo: '#eaa56c', ponto: '#cf8254', brilho: '#fec99c' },
            arada: { borda: '#b86542', miolo: '#cf8254', ponto: '#b86542', brilho: '#eaa56c' }
        };
        function desenharTerra(c, escuro, mc) {
            const viz = (dx, dy) => mc.has((c.x + dx) + ',' + (c.y + dy));
            const cima = viz(0, -1), baixo = viz(0, 1), esq = viz(-1, 0), dir = viz(1, 0);
            const x = wx(c.x), y = wy(c.y);
            if (!cima && !baixo && !esq && !dir) return tile(q, escuro ? 1 : 0, x, y);
            const cor = escuro ? TERRA.arada : TERRA.clara;
            const pinta = (px, py, w, h, cc) => { q.fillStyle = cc; q.fillRect(x + px, y + py, w, h); };
            const grama = (px, py, w, h) => q.drawImage(fundo, x + px, y + py, w, h, x + px, y + py, w, h);
            // até onde vai a terra nesta casa: sem vizinho, recua como nas tiras do pacote
            const x0 = esq ? 0 : 2, x1 = dir ? 16 : 14, y0 = cima ? 0 : 4;
            pinta(x0, y0, x1 - x0, 16 - y0, cor.borda);
            // miolo: borda de 3 nos lados, 2 em cima e 4 embaixo (a sombra da terra)
            const m0 = esq ? 0 : 5, m1 = dir ? 16 : 11, n0 = cima ? 0 : 6, n1 = baixo ? 16 : 12;
            pinta(m0, n0, m1 - m0, n1 - n0, cor.miolo);
            // pontinhos da terra, sempre nos mesmos lugares em cada casa
            let r = ((c.x * 73856093) ^ (c.y * 19349663)) >>> 0;
            const sorteia = (a, b) => { r = (r * 1103515245 + 12345) >>> 0; return a + (r >>> 8) % Math.max(1, b - a); };
            for (let k = 0; k < 3; k++) pinta(sorteia(m0 + 1, m1 - 2), sorteia(n0 + 1, n1 - 1), 2, 1, cor.ponto);
            pinta(sorteia(m0 + 1, m1 - 1), sorteia(n0 + 1, n1 - 1), 1, 1, cor.brilho);
            // cantos de fora arredondados (3 pixels, como as pontas das tiras do pacote)
            const canto = (px, py, sx, sy) => { grama(px, py, 2, 1); grama(sx > 0 ? px : px + 1, py + sy, 1, 1); };
            if (!cima && !esq) canto(x0, y0, 1, 1);
            if (!cima && !dir) canto(x1 - 2, y0, -1, 1);
            if (!baixo && !esq) canto(x0, 15, 1, -1);
            if (!baixo && !dir) canto(x1 - 2, 15, -1, -1);
            // cantos de dentro (vizinho dos dois lados, mas não na diagonal): a borda dobra
            if (cima && esq && !viz(-1, -1)) { grama(0, 0, 2, 4); pinta(2, 0, 3, 6, cor.borda); pinta(0, 4, 5, 2, cor.borda); }
            if (cima && dir && !viz(1, -1)) { grama(14, 0, 2, 4); pinta(11, 0, 3, 6, cor.borda); pinta(11, 4, 5, 2, cor.borda); }
            if (baixo && esq && !viz(-1, 1)) pinta(0, 12, 5, 4, cor.borda);
            if (baixo && dir && !viz(1, 1)) pinta(11, 12, 5, 4, cor.borda);
        }

        function desenharCanteiro(c, tempo, mc) {
            const v = visual(c.posicao);
            if (!v) return;
            const x = wx(c.x), y = wy(c.y);
            desenharTerra(c, v.solo === 'arado', mc);
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
            if (v.alarme) icone(q, 'cadeado', x + 5, y + 4);
            if (v.pendente && Math.floor(tempo / 150) % 2) {
                q.fillStyle = 'rgba(255,255,255,.35)';
                q.fillRect(x + 1, y + 1, T - 2, T - 2);
            }
        }

        // terreno à venda: placa na clareira da mata, com uma moeda pulando
        function desenharPlacaVenda(tempo) {
            const x = wx(zonaVenda.placa.x), y = wy(zonaVenda.placa.y);
            const bob = Math.floor(tempo / 600) % 2 ? -1 : 0;
            tile(q, 83, x, y, false, 'town');
            icone(q, 'moeda', x + 4, y - 10 + bob);
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
                    if (!noTerreno(tx, ty)) continue;
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
            if (sel) moldura(wx(sel.x), wy(sel.y), T * (sel.w || 1), T * (sel.h || 1), Math.floor(tempo / 250) % 2 ? PAL.y : PAL.w);
            if (hover && typeof hover === 'object' && 'tx' in hover) {
                const { tx, ty } = hover;
                const x = wx(tx), y = wy(ty);
                const tipo = construcao.modo === 'colocar' ? construcao.tipo : sel ? sel.tipo : null;
                const a = tipo ? arteItem(tipo, EST) : {};
                const w = a.w || 1, h = a.h || 1;
                let pode;
                if (construcao.modo === 'colocar' || sel) {
                    const ocup = sel ? mapaConstrucoes(construcoesFn() || [], sel).ocupado : m.ocupado;
                    pode = cabe(tx, ty, w, h, ocup);
                } else {
                    pode = m.ocupado.has(tx + ',' + ty);
                }
                // alcance da máquina (irrigador, alarme...) em volta do quadrado
                const raio = construcao.modo === 'colocar' ? construcao.raio : 0;
                if (raio > 0 && pode) {
                    const rx = wx(tx - raio), ry = wy(ty - raio), lado = (raio * 2 + 1) * T;
                    q.fillStyle = 'rgba(153,216,248,.22)';
                    q.fillRect(rx, ry, lado, lado);
                    moldura(rx, ry, lado, lado, PAL.b);
                }
                if (pode && tipo && (construcao.modo === 'colocar' || sel)) {
                    q.globalAlpha = 0.65;
                    if (a.grade) {
                        a.grade.forEach((linha, dy) => linha.forEach((i, dx) => tile(q, i, x + dx * T, y + dy * T, false, a.p)));
                    } else {
                        const temp = new Map(m); temp.set(tx + ',' + ty, tipo);
                        const sp = spritesDe(tipo, tx, ty, temp);
                        if (sp.topo != null) tile(q, sp.topo, x, y - T, false, sp.p);
                        tile(q, sp.i, x, y, false, sp.p);
                    }
                    q.globalAlpha = 1;
                }
                moldura(x, y, T * (pode && tipo ? w : 1), T * (pode && tipo ? h : 1), pode ? PAL.w : PAL.r);
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
            quadroHelice = Math.floor(tempo / (clima === 'vento' ? 90 : 200)) % 2;   // venta mais, gira mais
            q.drawImage(fundo, 0, 0);

            const lista = construcoesFn() || [];
            const m = mapaConstrucoes(lista);
            const pe = [];   // coisas "em pé", ordenadas pela altura
            for (const c of lista) {
                const s = spritesDe(c.tipo, c.x, c.y, m);
                if (s.chao) tile(q, s.i, wx(c.x), wy(c.y), false, s.p);   // caminho/flores: chão
                else if (s.grade) pe.push({ ...s, x: wx(c.x), y: wy(c.y + s.h - 1), gy: wy(c.y), flip: false, bob: 0 });
                else pe.push({ ...s, x: wx(c.x), y: wy(c.y), flip: false, bob: 0 });
            }

            const canteiros = listaCanteiros(), mc = mapaCanteiros(canteiros);
            for (const c of canteiros) desenharCanteiro(c, tempo, mc);
            if (zonaVenda) desenharPlacaVenda(tempo);

            for (const a of atores.values()) {
                const parado = a.v && a.v.estado !== 'produzindo';
                const andando = a.ajudante && Math.hypot(a.tx - a.x, a.ty - a.y) > 0.5;
                const bob = (parado && Math.floor(tempo / 600) % 2) || (andando && Math.floor(tempo / 140) % 2) ? -1 : 0;
                pe.push({ p: a.p || 'farm', i: a.i, x: a.x, y: a.y, flip: a.flip, bob });
                // ferramenta na mão do ajudante (do lado para onde ele olha)
                if (a.ferramenta != null) pe.push({ p: 'farm', i: a.ferramenta, x: a.x + (a.flip ? -7 : 7), y: a.y + 0.5, flip: a.flip, bob });
            }
            const andando = fazendeiro.passo > 0;
            pe.push({ p: 'farm', i: 109, x: fazendeiro.x, y: fazendeiro.y, flip: fazendeiro.flip, bob: andando && Math.floor(tempo / 120) % 2 ? -1 : 0 });
            pe.sort((a, b) => a.y - b.y).forEach((a) => {
                const x = Math.round(a.x), y = Math.round(a.y) + a.bob;
                if (a.grade) {
                    a.grade.forEach((linha, dy) => linha.forEach((i, dx) => tile(q, i, x + dx * T, a.gy + dy * T, false, a.p)));
                    return;
                }
                if (a.topo != null) tile(q, a.topo, x, y - T, a.flip, a.p);
                tile(q, a.i, x, y, a.flip, a.p);
            });

            for (const a of atores.values()) if (a.v) desenharSinalAnimal(a, tempo);
            for (const c of lista) {
                const of = c.oficina;
                if (!of) continue;
                const a = arteItem(c.tipo, EST);
                const bx = wx(c.x) + Math.round(((a.w || 1) * T) / 2) - 10;
                const pronta = of.estado === 'pronta';
                const by = wy(c.y) - 14 + (pronta ? Math.floor(tempo / 350) % 2 : 0);
                balao(bx, by, 20, 18);
                q.globalAlpha = of.estado === 'parada' ? 0.4 : pronta ? 1 : 0.7;
                tile(q, of.produto, bx + 2, by + 1);
                q.globalAlpha = 1;
                if (of.estado === 'trabalhando') barraProgresso(bx + 4, by + 19, of.progresso || 0);
                if (pronta && Math.floor(tempo / 300) % 3) icone(q, 'brilho', bx + 17, by - 3);
            }
            for (const c of lista) {
                if (!c.ligado) continue;   // gerador a biomassa queimando milho: fumacinha
                for (let k = 0; k < 3; k++) {
                    const f = ((tempo / 900) + k / 3) % 1;
                    q.globalAlpha = 0.85 * (1 - f);
                    q.fillStyle = k === 1 ? '#8b9bb4' : '#c0cbdc';   // uma das bolinhas mais escura
                    const tam = 3 + Math.round(f * 3);
                    q.fillRect(Math.round(wx(c.x) + 9 + Math.sin(f * 6 + k) * 2), Math.round(wy(c.y) + 1 - f * 14), tam, tam);
                }
                q.globalAlpha = 1;
            }
            for (const c of lista) {
                if (!c.pronto || c.produto == null) continue;
                const x = wx(c.x), by = wy(c.y) - 21 + (Math.floor(tempo / 350) % 2);
                balao(x - 2, by, 20, 18);
                tile(q, c.produto, x, by + 1);
                if (Math.floor(tempo / 300) % 3) icone(q, 'brilho', x + 15, by - 3);
            }

            if (construcao.ativo) {
                desenharGrade(m, tempo);
            } else if (typeof hover === 'number') {
                const { x, y } = posCanteiro(hover);
                moldura(x, y, T, T);
            } else if (hover === 'venda' && zonaVenda) {
                moldura(wx(zonaVenda.placa.x), wy(zonaVenda.placa.y), T, T);
            } else if (typeof hover === 'string' && hover.startsWith('c:')) {
                const [hx, hy] = hover.slice(2).split(',').map(Number);
                const c = lista.find((k) => k.x === hx && k.y === hy);
                if (c) { const a = arteItem(c.tipo, EST); moldura(wx(hx), wy(hy), T * (a.w || 1), T * (a.h || 1)); }
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
            desenharClima(tempo, k);
        }

        /* ---- clima por cima de tudo (na tela, não no mundo) ---- */
        function desenharClima(tempo, k) {
            const W = canvas.width, H = canvas.height;
            if (clima === 'nublado') {
                ctx.fillStyle = 'rgba(70, 80, 100, .12)';
                ctx.fillRect(0, 0, W, H);
            } else if (clima === 'calor') {
                ctx.fillStyle = 'rgba(255, 140, 40, .08)';
                ctx.fillRect(0, 0, W, H);
            } else if (clima === 'chuva') {
                ctx.fillStyle = 'rgba(40, 60, 100, .14)';
                ctx.fillRect(0, 0, W, H);
                ctx.fillStyle = 'rgba(190, 225, 255, .55)';
                const passo = Math.max(2, Math.round(k)), alto = passo * 5, n = Math.round((W * H) / (90 * 90 * dpr * dpr));
                for (let i = 0; i < n; i++) {
                    const x = ((i * 97) % W + (tempo * 0.05 * passo)) % W;
                    const y = ((i * 211) % H + tempo * 0.6 * passo) % H;
                    ctx.fillRect(Math.round(x), Math.round(y), passo, alto);
                }
            } else if (clima === 'vento') {
                ctx.fillStyle = 'rgba(255, 255, 255, .45)';
                const passo = Math.max(2, Math.round(k));
                for (let i = 0; i < 14; i++) {
                    const y = (i * 131) % H, x = ((i * 389) + tempo * 0.4 * passo) % (W + 200) - 100;
                    ctx.fillRect(Math.round(x), Math.round(y), passo * 14, passo);
                }
            }
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
            const cant = listaCanteiros().find((k) => k.x === tx && k.y === ty);
            if (cant) return cant.posicao;
            const cons = (construcoesFn() || []).find((c) => {
                const a = arteItem(c.tipo, EST);
                return tx >= c.x && ty >= c.y && tx < c.x + (a.w || 1) && ty < c.y + (a.h || 1);
            });
            if (cons) return 'c:' + cons.x + ',' + cons.y;
            const c = retCeleiro();
            if (px >= c.x && py >= c.y && px < c.x + c.w && py < c.y + c.h) return 'celeiro';
            // terreno à venda: a placa ou qualquer pedaço de mata dele
            if (zonaVenda && dentroRet(zonaVenda, tx, ty)) return 'venda';
            return null;
        }

        function traduzir(alvo) {
            if (typeof alvo === 'string' && alvo.startsWith('a:')) return { animal: idDoHover(alvo) };
            if (typeof alvo === 'string' && alvo.startsWith('c:')) {
                const [x, y] = alvo.slice(2).split(',').map(Number);
                return { construcao: { x, y } };
            }
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
            else if (alvo === 'venda') { if (cb.aoVenda) cb.aoVenda(); }
            else if (typeof alvo === 'object' && alvo.construcao) { if (cb.aoConstrucao) cb.aoConstrucao(alvo.construcao.x, alvo.construcao.y); }
            else if (typeof alvo === 'object') { if (cb.aoAnimal) cb.aoAnimal(alvo.animal); }
            else if (cb.aoCanteiro) cb.aoCanteiro(alvo);
        }
        canvas.addEventListener('pointerup', soltar);
        canvas.addEventListener('pointercancel', soltar);
        canvas.addEventListener('pointerleave', () => { if (!toque) hover = null; });

        window.addEventListener('resize', redimensionar);

        /* ---- zoom ---- */
        // muda o zoom mantendo parado o ponto que está embaixo do dedo/mouse
        function aplicarZoom(fator, fx, fy) {
            const novo = Math.min(2.2, Math.max(0.6, fator));
            if (novo === zoomFator) return;
            const mx = cam.x + fx / escala, my = cam.y + fy / escala;
            zoomFator = novo;
            escala = escalaBase * zoomFator;
            vw = innerWidth / escala;
            vh = innerHeight / escala;
            cam.x = mx - fx / escala;
            cam.y = my - fy / escala;
            limitarCamera();
            sincronizarRolagem();
            precisaDesenhar = true;
        }
        canvas.addEventListener('wheel', (e) => {
            e.preventDefault();
            aplicarZoom(zoomFator * (e.deltaY < 0 ? 1.12 : 1 / 1.12), e.clientX, e.clientY);
        }, { passive: false });
        if (rolagem) {
            let pinca = null;
            const distancia = (t) => Math.hypot(t[0].clientX - t[1].clientX, t[0].clientY - t[1].clientY);
            rolagem.addEventListener('touchstart', (e) => {
                if (e.touches.length === 2) {
                    pinca = { d: distancia(e.touches), fator: zoomFator };
                    rolagem.style.overflow = 'hidden';   // enquanto pinça, a rolagem não briga com o zoom
                }
            }, { passive: true });
            rolagem.addEventListener('touchmove', (e) => {
                if (!pinca || e.touches.length !== 2) return;
                e.preventDefault();
                const meioX = (e.touches[0].clientX + e.touches[1].clientX) / 2;
                const meioY = (e.touches[0].clientY + e.touches[1].clientY) / 2;
                aplicarZoom(pinca.fator * distancia(e.touches) / pinca.d, meioX, meioY);
            }, { passive: false });
            const fimPinca = (e) => {
                if (pinca && e.touches.length < 2) {
                    pinca = null;
                    rolagem.style.overflow = '';
                    sincronizarRolagem();
                }
            };
            rolagem.addEventListener('touchend', fimPinca);
            rolagem.addEventListener('touchcancel', fimPinca);
        }

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
            definirAjudantes(fn) { ajudantesFn = fn; },
            definirConstrucoes(fn) { construcoesFn = fn; },
            definirCanteiros(fn) { canteirosFn = fn; },
            // terrenos da fazenda na tela e o próximo à venda (número da zona ou null)
            definirTerreno(t) {
                const zonas = (t && t.zonas) || 0;
                const venda = (t && ZONAS.find((z) => z.n === t.venda)) || null;
                if (zonas === zonasAtuais && venda === zonaVenda) return;
                zonasAtuais = zonas;
                zonaVenda = venda;
                montarFundo();
                ajustarEscala();
                limitarCamera();
                sincronizarRolagem();
                precisaDesenhar = true;
            },
            focarTile(tx, ty) { focar(wx(tx) + T / 2, wy(ty) + T / 2); },
            definirClima(c) { clima = c || null; precisaDesenhar = true; },
            // estação nova: refaz o chão (neve, folhas, flores) e a arte das árvores
            definirEstacao(e) {
                estacaoServidor = e || null;
                const nova = estacao();
                if (nova === EST) return;
                EST = nova;
                montarFundo();
                precisaDesenhar = true;
            },
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
        AJUDANTE_ARTE,
        MAPA,
        ZONAS,
        noTerreno,
        livre,
        estacao,
        cultura: (id) => CULTURAS[id] || CULTURA_PADRAO
    };
})();
