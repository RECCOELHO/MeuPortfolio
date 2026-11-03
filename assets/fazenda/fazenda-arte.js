/* ============================================================
   FAZENDINHA SECRETA — arte e cena
   Pixel art dos pacotes "Tiny Farm", "Tiny Town" e "Tiny Ski" do
   Kenney (CC0, kenney.nl), desenhada num <canvas>. Os ícones pequenos
   (moeda, XP, praga...) são desenhados aqui, na mesma paleta.

   A fazenda começa com 22 x 13 quadrados cercados de mata e cresce
   até 48 x 32 com os terrenos comprados (ZONAS). Os canteiros têm
   lugar livre (x, y) e se emendam em fileiras quando ficam lado a lado.
   Máquinas: pacote "Tiny Factory" do Kenney (CC0).
   Visitas na porteira: personagens do pacote "Tiny Dungeon" do Kenney (CC0).

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
    const LINHAS_PROPRIA = 15;   // fase 73: a arte própria passou de 132 peças (os pacotes do Kenney continuam com 11 linhas)

    const PAL = {
        o: '#3f2631', g: '#84c669', G: '#4e974c', l: '#c6e58d', y: '#fdbe53', Y: '#e38628',
        r: '#c34b35', R: '#aa2c23', b: '#99d8f8', B: '#79a7e8', w: '#ffffff', p: '#d176d0',
        P: '#9b4ca3', s: '#c0cbdc', S: '#8b9bb4', k: '#fec99c', t: '#eaa56c', d: '#cf8254', n: '#763b36'
    };

    /* ---------- O chão de cada estação (como no The Sims: o mapa todo muda) ----------
       grama = fundo; tufo = tufinhos; ponto = pontinhos; mancha = manchas grandes no chão
       (grama aparecendo na neve, grama seca, folhas amontoadas) */
    const CHAO = {
        primavera: { grama: '#84c669', tufo: '#4e974c', ponto: '#c6e58d', mancha: '#9ad57a', flores: 0.32 },
        verao: { grama: '#97c95c', tufo: '#5f9a41', ponto: '#e3d77a', mancha: '#bcc865', flores: 0.12 },
        outono: { grama: '#adb35c', tufo: '#7b8a3d', ponto: '#e38628', mancha: '#c9924a', flores: 0.03 },
        inverno: { grama: '#eef3f8', tufo: '#c9d6e3', ponto: '#ffffff', mancha: '#b4cfa2', flores: 0 }
    };

    /* ---------- Mapa da fazenda (precisa bater com fazenda_livre no SQL) ---------- */
    const MAPA = {
        w: 64, h: 42,   // (fase 78: + a faixa da direita, x 48 a 63)                                // tamanho máximo, com todos os terrenos (fase 61: + o litoral)
        celeiro: { x: 1, y: 1 },                     // 3 x 6
        casa: { x: 5, y: 1 },                        // 3 x 3
        campo: { x: 9, y: 4 },                       // onde os 6 primeiros canteiros nascem
        fazendeiro: { x: 8, y: 4 },
        galinheiro: { x: 0, y: 7, w: 7, h: 2 },
        pasto: { x: 16, y: 0, w: 6, h: 7 },          // cercado, porteira embaixo
        porteira: [18, 19],
        cochos: [{ i: 110, x: 18, y: 1 }, { i: 111, x: 19, y: 1 }],
        // celeiro, casa, galinheiro e pasto: o resto do terreno é livre (até para canteiros)
        // o lago (terreno 3, Vale do sudeste): o tanque e a grama do pescador, à esquerda; igual a fazenda_livre no SQL
        lago: { x: 24, y: 14, w: 6, h: 5 },
        // fase 51: a feira, numa pracinha de terra na mata à esquerda do celeiro (fora do terreno,
        // onde não dá para expandir). A 1ª barraca todo mundo tem; as outras são compradas.
        feira: { x: -5, y: 1, w: 5, h: 6, barracas: [{ x: -2, y: 2 }, { x: -4, y: 2 }, { x: -2, y: 5 }, { x: -4, y: 5 }, { x: -3, y: 2 }, { x: -3, y: 5 }] },   // (fase 82: a 5ª e a 6ª, de diamante)
        // fase 61: o litoral (terreno 7): areia de y 32 a 36 e mar dali para baixo; o píer é um lugar
        // fixo na areia que entra pelo mar. Igual a fazenda_livre no SQL.
        mar: { x: 0, y: 37, w: 64, h: 5 },
        pier: { x: 22, y: 35, w: 3, h: 7 },
        reservas: [
            { x: 1, y: 1, w: 3, h: 6 }, { x: 5, y: 1, w: 3, h: 3 }, null,
            { x: 16, y: 0, w: 6, h: 7 }, { x: 24, y: 14, w: 6, h: 5 },
            { x: 0, y: 37, w: 64, h: 5 }, { x: 22, y: 35, w: 3, h: 7 }
        ]
    };
    // o galinheiro cresce com os bichos (definirGalinheiro): a reserva é o mesmo objeto
    MAPA.reservas[2] = MAPA.galinheiro;
    // fase 45: o galinheiro (0 fileiras) e o pasto só existem para quem ainda tem bicho sem cercado;
    // sem eles a reserva some (largura 0) e dá para construir ali
    MAPA.pastoAtivo = true;
    const MARGEM = 9;   // quadrados de mata em volta do terreno
    // fase 67: a areia vai da linha 32 até o mar; nela não tem mata, tem peças de praia (PROPRIA 107 a 112)
    const AREIA_Y = 32;
    const PRAIA = { coqueiro: { i: 108, topo: 107 }, pedra: { i: 109 }, duna: { i: 110, fixo: true }, tronco: { i: 111 }, concha: { i: 112 } };

    /* ---------- Terrenos: começa com BASE e compra as ZONAS em ordem ----------
       (precisa bater com fazenda_zonas no SQL; placa = onde fica a placa de "à venda") */
    const BASE = { x: 0, y: 0, w: 22, h: 13 };
    const ZONAS = [
        { n: 1, x: 0, y: 13, w: 22, h: 7, placa: { x: 10, y: 13 } },
        { n: 2, x: 22, y: 0, w: 10, h: 13, placa: { x: 22, y: 9 } },
        { n: 3, x: 22, y: 13, w: 10, h: 7, placa: { x: 23, y: 14 } },
        // terrenos grandes (fase 24)
        { n: 4, x: 32, y: 0, w: 16, h: 20, placa: { x: 32, y: 9 } },
        { n: 5, x: 0, y: 20, w: 32, h: 12, placa: { x: 15, y: 20 } },
        { n: 6, x: 32, y: 20, w: 16, h: 12, placa: { x: 33, y: 21 } },
        // fase 61: o litoral, nível 31 (areia em cima, mar embaixo: MAPA.mar)
        { n: 7, x: 0, y: 32, w: 64, h: 10, placa: { x: 10, y: 33 } },   // (fase 78: até a ponta da direita)
        // fase 78: a faixa da direita (x 48 a 63), do nível 29, comprada à parte dos de 1 a 7
        { n: 8, x: 48, y: 0, w: 16, h: 11, placa: { x: 49, y: 5 }, direita: true },
        { n: 9, x: 48, y: 11, w: 16, h: 11, placa: { x: 49, y: 16 }, direita: true },
        { n: 10, x: 48, y: 22, w: 16, h: 10, placa: { x: 49, y: 26 }, direita: true }
    ];
    let zonasAtuais = 0, direitaAtuais = 0;   // terrenos da fazenda que está na tela (a sua ou a do vizinho)
    const dentroRet = (r, x, y) => x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h;
    const zonaMinha = (z, zonas = zonasAtuais, direita = direitaAtuais) => (z.direita ? z.n - 7 <= direita : z.n <= zonas);
    const areasDoTerreno = (zonas = zonasAtuais, direita = direitaAtuais) => [BASE, ...ZONAS.filter((z) => zonaMinha(z, zonas, direita))];
    function noTerreno(x, y, zonas = zonasAtuais, direita = direitaAtuais) {
        return areasDoTerreno(zonas, direita).some((r) => dentroRet(r, x, y));
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

    /* ---------- Dia e noite do jogo ----------
       Em 24 h, 12 h de dia e 12 h de noite, se revezando de 2 em 2 horas no relógio de Brasília
       (UTC-3): dia das 0h às 2h, noite das 2h às 4h... Igual a fazenda_dia_em no SQL (que decide
       quando o painel solar gera). n = quanto está escuro (0 a 1): escurece nos 10 primeiros
       minutos da noite e clareia nos 10 primeiros do dia. ?noite=1 / ?noite=0 força no teste. */
    const BLOCO_DIA = 120, VIRADA = 10;   // minutos
    function faseDoDia(ms) {
        try {
            const f = new URLSearchParams(location.search).get('noite');
            if (f === '1' || f === '0') return { noite: f === '1', n: f === '1' ? 1 : 0, fim: ms + 3600e3 };
        } catch { /* ignora */ }
        const m = ms / 60000 - 180;
        const b = Math.floor(m / BLOCO_DIA), dentro = m - b * BLOCO_DIA;
        const noite = Math.abs(b % 2) === 1;
        const rampa = Math.min(1, dentro / VIRADA);
        return { noite, n: noite ? rampa : 1 - rampa, fim: ((b + 1) * BLOCO_DIA + 180) * 60000 };
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
        // peixes do lago (arte própria 1030..1036)
        laranja: { item: 1041 }, limao: { item: 1042 }, goiaba: { item: 1043 }, manga: { item: 1044 },
        abacate: { item: 1045 }, cacau: { item: 1046 }, jabuticaba: { item: 1047 },
        lambari: { item: 1030 }, tilapia: { item: 1031 }, piau: { item: 1032 }, curimata: { item: 1033 },
        tucunare: { item: 1034 }, surubim: { item: 1035 }, velho_chico: { item: 1036 },
        // produtos das oficinas da fase 38 (arte própria 1050..1062)
        picles: { item: 1050 }, oleo: { item: 1051 }, doce_abobora: { item: 1052 }, peixe_frito: { item: 1053 },
        suco: { item: 1054 }, sorvete: { item: 1055 }, peixe_defumado: { item: 1056 }, almofada: { item: 1057 },
        moqueca: { item: 1058 }, azeite_trufado: { item: 1059 }, vitamina: { item: 1060 }, guacamole: { item: 1061 },
        licor: { item: 1062 }, chocolate: { item: 1063 },
        // fase 58: sementes do 20 ao 30 (broto e meio do pacote; madura e fruta próprias) e os produtos das oficinas novas
        cana:     { fases: [52, 53, 1065], murcho: 55, item: 1066, semente: 1066 },
        cafe:     { fases: [52, 53, 1067], murcho: 55, item: 1068, semente: 1068 },
        algodao:  { fases: [52, 53, 1069], murcho: 55, item: 1070, semente: 1070 },
        uva:      { fases: [52, 53, 1071], murcho: 55, item: 1072, semente: 1072 },
        pimenta:  { fases: [52, 53, 1073], murcho: 55, item: 1074, semente: 1074 },
        baunilha: { fases: [52, 53, 1075], murcho: 55, item: 1076, semente: 1076 },
        acucar: { item: 1077 }, cafe_torrado: { item: 1078 }, fio: { item: 1079 }, cappuccino: { item: 1080 },
        roupa: { item: 1081 }, vinho: { item: 1082 }, molho_picante: { item: 1083 }, bombom: { item: 1084 },
        // fase 60: materiais raros do píer
        madeira_nobre: { item: 1085 }, corda_naval: { item: 1086 }, pedra_cantaria: { item: 1087 },
        ferro_forjado: { item: 1088 }, ancora: { item: 1089 },
        leme_dourado: { item: 1090 },   // fase 61
        // fase 62: os peixes do alto-mar e a pérola negra
        sardinha: { item: 1091 }, cavala: { item: 1092 }, robalo: { item: 1093 }, garoupa: { item: 1094 },
        dourado_mar: { item: 1095 }, atum: { item: 1096 }, marlim: { item: 1097 }, perola_negra: { item: 1098 },
        // fase 63: os prêmios do evento da semana
        trofeu_ouro: { item: 1099 }, trofeu_prata: { item: 1100 }, trofeu_bronze: { item: 1101 }, ampulheta_dourada: { item: 1102 },
        cofrinho_ouro: { item: 1103 }, balanca_ouro: { item: 1104 }, sacola_ouro: { item: 1105 },
        luva_perks: { item: 1106 },   // fase 66
        // fase 73: as frutas e os produtos do 31 ao 45 e as sementes de estação (broto e meio do pacote)
        coco: { item: 1121 }, caju: { item: 1122 }, acai: { item: 1123 }, cupuacu: { item: 1124 }, castanha: { item: 1125 },
        leite_cabra: { item: 1148 }, leite_bufala: { item: 1149 }, mussarela: { item: 1150 },   // fase 74
        sardinha_lata: { item: 1151 }, sashimi: { item: 1152 }, caldeirada: { item: 1153 },
        tora: { item: 1155 }, tabua_naval: { item: 1156 }, cravo: { item: 1157 }, vela: { item: 1158 }, carta_nautica: { item: 1159 },   // fase 104
        cocada: { item: 1126 }, cajuina: { item: 1127 }, acai_tigela: { item: 1128 }, creme_cupuacu: { item: 1129 }, pacoca: { item: 1130 },
        maracuja: { fases: [52, 53, 1135], murcho: 55, item: 1131, semente: 1131 },
        mexerica: { fases: [52, 53, 1136], murcho: 55, item: 1132, semente: 1132 },
        caqui:    { fases: [52, 53, 1137], murcho: 55, item: 1133, semente: 1133 },
        lichia:   { fases: [52, 53, 1138], murcho: 55, item: 1134, semente: 1134 },
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
    const ANIMAL = { galinha: 122, vaca: 121, ovelha: 120, porco: 1000, pato: 1001, coelho: 1002, cabra: 1146, bufala: 1147 };   // (fase 74: cabra e búfala)
    // bichos pequenos ficam no galinheiro; os grandes, no pasto
    const PEQUENOS = ['galinha', 'pato', 'coelho'];
    const BICHOS_NOVOS = new Set(['galinha', 'pato', 'coelho', 'vaca', 'ovelha', 'porco', 'cabra', 'bufala']);   // fase 107

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
        E: '#3b5dc9', F: '#29366f', K: '#566c86', W: '#a7f070',
        // fase 62: o alto-mar (verde-água, o fundo do mar e a pérola negra)
        T: '#3fb6c9', S: '#1f7f94', Y: '#cdeef4', I: '#25406e', J: '#1a1630',
        // fase 67: a praia (areia da duna, madeira desbotada do tronco e do coqueiro)
        o: '#ecd59a', p: '#d2b06c', q: '#b8955c', t: '#6e5a48', u: '#9c8466', z: '#cdb898'
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
        // 26 reator (cima, esq.) (fase 79: torre de resfriamento e a cúpula)
        ['................', '................', '...aaaaaaaaaaaaa', '...aKeeeeeeeeeeK', '...addffffffllKK', '....addfffffllKa', '....arrrrrrrbbba', '....arrrrrrrbbba', '....addfffffllKa', '....addfffffllKa', '.....addfffflKa.', '.....addfffflKa.', '.....addfffflKa.', '.....adllllllKa.', '.....addfffflKa.', '.....addfffflKa.'],
        // 27 reator (cima, dir.)
        ['................', '................', 'a...............', 'a...............', 'a...............', '................', '................', '................', '................', '................', '................', '................', '................', '........aa......', '.....aaflllaa...', '....affflllKKa..'],
        // 28 reator (baixo, esq.)
        ['.....addfffflKa.', '.....addfffflKa.', '.....addfffflKa.', '.....addfffflKa.', '....adllllllllKa', '....addfffffllKa', '....addfffffllKa', '...addffffffllKK', '...addffffffllKK', '...adllllllllllK', '..adddfffffffllK', '.adddfffffffflll', '.adddfffffffflll', 'addddfffffffffll', 'ddddffffffffflll', 'aaaaaaaaaaaaaaaa'],
        // 29 reator (baixo, dir.)
        ['...afffflllKKKa.', '...afffflllKKKa.', '...afffddllKKKa.', '..alllllllllllla', '..aKKaaaaaaaKKKa', '..adfavWWWvallla', '..adfavdWWvallla', 'a.adfavWWWvallla', 'a.adfavvvvvallla', 'Kaadfaaaaaaallla', 'Kaaaaaaaaaaaaala', 'KKadeeefagHggala', 'KKadeeefagaagala', 'lKadeeefaggHgala', 'lKadeeefaaaaaala', 'aaaaaaaaaaaaaaaa'],
        // 30 lambari
        ['................', '................', '................', '......aa..aa....', '.....aggaalla...', '....agggllefa...', '.....agllffda...', '.....alfffdda...', '.aaaalffddda....', 'aggggfdddgga....', '.agggaaaaaa.....', '.aggga..........', '..agga..........', '...aga..........', '....a...........', '................'],
        // 31 tilápia
        ['................', '................', '......aa........', '.....aKKaaaaa...', '....aKKKKKKlla..', '....aKKKKKlela..', '.....aKKlKllfa..', '....aKKllKfffa..', 'a...aKlKlfKfa...', 'laaaKllfKffKa...', 'allllfffaaKa....', '.alllaaa..a.....', '.alla...........', '..ala...........', '...a............', '................'],
        // 32 piau
        ['................', '................', '.......a........', '......araaaaa...', '.....arrallefa..', '....arrlllfffa..', '.....alllefdda..', '.....alefedda...', '....alfeddda....', '.aaalffdddrra...', 'arrrfdaaaara....', 'arrrra....a.....', '.arra...........', '..ara...........', '...a............', '................'],
        // 33 curimatã
        ['................', '................', '......aa...a....', '.....aKKaaala...', '....aKKKlllefa..', '....aKKlllfffa..', '.....allfBBfda..', '....allfBBddda..', '....alfBfddda...', 'aaaalBBdddKKa...', 'llllBdddaaKa....', 'alllaaaa..a.....', '.alla...........', '.alla...........', '..aa............', '................'],
        // 34 tucunaré
        ['................', '................', '......aa...a....', '.....aDDaaaDa...', '....aDDDDLDrMa..', '....aDDLDLMMMa..', '.....aDLMMLMsa..', '....aLDMLMsssa..', '....aDLMMsssa...', 'aaaaDMMsssDDa...', 'ggggMsssaaDa....', 'agggaaaa..a.....', '.agea...........', '.agga...........', '..aa............', '................'],
        // 35 surubim
        ['................', '................', '................', '......aa.aaaaaaa', '.....aKKaeeeleee', '....aKKKKKellaaa', '.....aKeellffa..', '.....aKlelffa...', '....aKeleffa....', 'aaaaKleffKKa....', 'KKKKlfaaaaa.....', 'KKKKaa..........', 'aKKKa...........', '.aKa............', '..a.............', '................'],
        // 36 Peixe do Velho Chico
        ['............ada.', '...........adada', '.a....aa..aaada.', 'ada..aHHaaHHaa..', '.a..aHHHdHHega..', '....aHdddHggga..', '.....aHdggggGa..', '....aHHgggGGGa..', '....aHgggGGGa...', 'aaaaHggGGGGHa...', 'gggggGGGaaHa....', 'agggaaaa..a.....', '.agga...........', '.agga...........', '.ada............', '..a.............'],
        // 37 estátua do Velho Chico (metade de baixo)
        ['...aGGGGGGga.aGg', '...aGGggGGGaaGGa', '..aaaagggaaaGGga', '.aGgHggggHgGGaa.', '.aGgHggggHgaa...', '.aGgHggggHga....', '.aGgHHHHHHga....', '.aGaHiddiHa.....', '.agaHiiiiHa.....', '..aaHHHHHHa.....', '...aHHHHHHa.....', '...aHHHHHHa.....', '...aHHHaHHa.....', '...aHHHaHHaa....', '..aiiiiaiiiia...', '..aiiiiaiiiia...'],
        // 38 estátua do Velho Chico (pedestal)
        ['affffffffffffffa', 'alllllllllllllla', '.aafllllllllKaa.', '..afllllllllKa..', '..aflHHHHHHlKa..', '..aflHggggHlKa..', '..aflHgGGGHlKa..', '..aflHGGGgHlKa..', '..aflHgggGHlKa..', '..aflHHHHHHlKa..', '..afllllllllKa..', '..afllllllllKa..', '.aafllllllllKaa.', 'alllllllllllllla', 'aKKKKKKKKKKKKKKa', '.aaaaaaaaaaaaaa.'],
        // 39 estátua do Velho Chico (metade de cima: cabeça e o peixe erguido)
        ['.............a..', '............aga.', '...d.......aggga', '..d.d.....agdHGa', '...d......agdgGg', '..........aHggGH', '..........agHHGg', '..........agggGa', '....aaaaaaaaggga', '...aHHHHHHHagaga', '..aHHggHHHHHaaag', '..aHHHHHgHHHGGGa', '..aHHHHHHHHHgGGg', '..aHHGHGHGHHaGGa', '..aHGGGGGGGHaGGa', '..aHGHGGHGGaaGGa'],
        // 40 saco de adubo (o que a mascate vende)
        ['................', '................', '.......aa.......', '......aDLa......', '.....aaDDaa.....', '....anyyyyna....', '...anyyyyyyna...', '...ayyDDDDyya...', '...ayDLLLLDya...', '...ayyDDDDyya...', '...ayyyyyyyya...', '...anyyyyyyna...', '....annnnnna....', '.....aaaaaa.....', '................', '................'],
        // 41 laranja
        ['................', '................', '........aa......', '.......aLDa.....', '.....aaaLaa.....', '....agiiiiia....', '...agGiiiiiia...', '...agiiiiiiia...', '...aiiiiiiiNa...', '...aiiiiiiiNa...', '...aiiiiiiNNa...', '....aiiiNNNa....', '.....aaaaaa.....', '................', '................', '................'],
        // 42 limao
        ['................', '................', '................', '................', '................', '......aaaa......', '....aaCCMMaa....', '...aCCMMMMMDa...', '..aCMMMMMMMMDa..', '..aMMMMMMMMDDa..', '...aMMMMMMDDa...', '....aaDDDDaa....', '......aaaa......', '................', '................', '................'],
        // 43 goiaba
        ['................', '................', '................', '.......aa.......', '......aDDa......', '.....aaaaaa.....', '....aCCMMMMa....', '...aCCMMMMMMa...', '...aCMMMMPPMa...', '...aMMMMMPPDa...', '...aMMMMMMDDa...', '....aMMMDDDa....', '.....aaaaaa.....', '................', '................', '................'],
        // 44 manga
        ['................', '................', '................', '................', '.......aaaa.....', '.....aaXXOOaa...', '....aXXXOOOOga..', '...aXXXOOOOggga.', '...aXXOOOOOggga.', '...aZXOOOOOOgga.', '....aZXOOOOOga..', '.....aZZXOOaa...', '.......aaaa.....', '................', '................', '................'],
        // 45 abacate
        ['................', '................', '.......aa.......', '......aDDa......', '.....aDMDDa.....', '.....aMMDDa.....', '....aDMDDDLa....', '...aDMDDDDDLa...', '...aMDDDDDDLa...', '...aDDDDDDLLa...', '...aDDDDDDLLa...', '....aDDDLLLa....', '.....aaaaaa.....', '................', '................', '................'],
        // 46 cacau
        ['................', '................', '.......aa.......', '......aNNa......', '.....aONONa.....', '....aOgONONa....', '....aOgONONa....', '....aOgONONa....', '....aOOONONa....', '....aOOONONa....', '.....aOONNa.....', '......aNNa......', '.......aa.......', '................', '................', '................'],
        // 47 jabuticaba
        ['................', '................', '................', '................', '......aaaa......', '.....aVUVVa.....', '.....aVdVVa.....', '.....aVVVea.....', '...aaaaeeaaaa...', '..aVUVVaaVUVVa..', '..aVdVVaaVdVVa..', '..aVVVeaaVVVea..', '...aaaa..aaaa...', '................', '................', '................'],
        // 48 cano de vidro (ícone do Construir; no mapa o cano é desenhado na hora, transparente)
        ['................', '................', '................', '................', '................', 'aaaaaaaaaaaaaaaa', 'dddddddddddddddd', 'ffffffiiifffffff', 'fffffiiiiiffffff', 'ffffffiiifffffff', 'llllllllllllllll', 'aaaaaaaaaaaaaaaa', '................', '................', '................', '................'],
        // 49 lampião (de noite a luz dele é desenhada por cima, em desenharNoite)
        ['......aaaa......', '.....aeeeea.....', '....aeeeeeea....', '.....aGGGGa.....', '.....aGdGGa.....', '.....aGGGga.....', '.....agggga.....', '.....aeeeea.....', '......aKKa......', '......aKKa......', '......aKKa......', '......aKKa......', '......aKKa......', '.....aKKKKa.....', '....aeeeeeea....', '....aaaaaaaa....'],
        // produtos das oficinas da fase 38 (50..62)
        // 50 picles (pote de vidro com pepinos)
        ['................', '................', '.....aaaaaa.....', '....allllllla...', '....aaaaaaaaa...', '...adhvhhvhhha..', '...adhhvhhvhha..', '...ahssssssvha..', '...ahssssssvva..', '...ahvhhvhhhva..', '...avhhhvhhvva..', '....aaaaaaaaa...', '................', '................', '................', '................'],
        // 51 óleo de girassol (garrafa amarela)
        ['................', '.......aa.......', '......aHHa......', '......aaaa......', '......adga......', '......adga......', '.....adggga.....', '....adggggga....', '....adGGGGga....', '....adGssGga....', '....adGssGga....', '....adGGGGga....', '....adggggga....', '....aHHHHHHa....', '.....aaaaaa.....', '................'],
        // 52 doce de abóbora (pote laranja)
        ['................', '................', '.....aaaaaa.....', '....allllllla...', '....aaaaaaaaa...', '...adOOOOOOOOa..', '...adOOOOOOOOa..', '...aOssssssONa..', '...aOssssssONa..', '...aOOOOOOOONa..', '...aNOOOOOONNa..', '....aaaaaaaaa...', '................', '................', '................', '................'],
        // 53 peixe frito (dourado, no prato)
        ['................', '................', '................', '................', '.....aaaaa......', '...aagggggaa.a..', '..agHgggggggaga.', '..agdgggHgggHga.', '..agggHgggggaga.', '...aagggggaa.a..', '.....aaaaa......', '.aaaaaaaaaaaaaa.', '.afffffffffffla.', '..aaaaaaaaaaaa..', '................', '................'],
        // 54 suco de frutas (copo laranja com canudo)
        ['................', '...........a....', '..........ara...', '....aaaaaaraa...', '....addddrdda...', '....adOOOrOOa...', '....adOOOOOOa...', '....adOgOOOOa...', '.....adOOOOa....', '.....adOOOOa....', '.....adOOONa....', '......aOOOa.....', '......aNNNa.....', '.......aaa......', '................', '................'],
        // 55 sorvete (casquinha com bola rosa)
        ['................', '.......aaa......', '.....aamPmaa....', '....amPPdPPma...', '....aPPPPPPPa...', '...aPmPPPPPmPa..', '...aPPPPmPPPPa..', '....aaaaaaaaa...', '....awxwxwxwa...', '.....axwxwxa....', '.....awxwxwa....', '......axwxa.....', '......awxwa.....', '.......axa......', '........a.......', '................'],
        // 56 peixe defumado (marrom, na tábua)
        ['................', '................', '................', '................', '.....aaaaa......', '...aannnnnaa.a..', '..anynnnnnnnana.', '..andnnnynnnyna.', '..annnynnnnnana.', '...aannnnnaa.a..', '.....aaaaa......', '.aaaaaaaaaaaaaa.', '.ayyyyyyyyyyyya.', '..aaaaaaaaaaaa..', '................', '................'],
        // 57 almofada (creme, com bordado rosa)
        ['................', '................', '..aaa......aaa..', '..amsaaaaaasma..', '...assssssssa...', '..asdssssssssa..', '..assssmmssssa..', '..asssmPPmsssa..', '..assssmmssssa..', '..asssssssssxa..', '...assssssssa...', '..amsaaaaaasma..', '..aaa......aaa..', '................', '................', '................'],
        // 58 moqueca (panela de barro fumegando)
        ['................', '.....l...l......', '......l...l.....', '.....l...l......', '....aaaaaaaa....', '...aOrOOrOOOa...', '..aOOgOOOrOgOa..', '.aaaaaaaaaaaaaa.', '.ayyyyyyyyyyyya.', '..aynyyyyyynya..', '..ayyyyyyyyyya..', '...ayyyyyyyya...', '....aaaaaaaa....', '................', '................', '................'],
        // 59 azeite trufado (garrafa verde-escura)
        ['................', '.......aa.......', '......anna......', '......aaaa......', '......adLa......', '......adLa......', '.....adLLLa.....', '....adLLLLLa....', '....advvvvLa....', '....advssvLa....', '....advssvLa....', '....advvvvLa....', '....adLLLLLa....', '....annnnnna....', '.....aaaaaa.....', '................'],
        // 60 vitamina de manga (copo amarelo com canudo)
        ['................', '...........a....', '..........aBa...', '....aaaaaaBaa...', '....addddBdda...', '....adGGGBGGa...', '....adGGGGGGa...', '....adGdGGGGa...', '.....adGGGGa....', '.....adGGGGa....', '.....adGGGga....', '......aGGGa.....', '......aggga.....', '.......aaa......', '................', '................'],
        // 61 guacamole (tigela com chips)
        ['................', '................', '................', '.........aa.....', '........axxa....', '.......axgxa....', '...aaaaaxxaaa...', '..aMhMMhMaMhMa..', '.aaaaaaaaaaaaaa.', '.acccccccccccca.', '..acdccccccbca..', '...accccccbca...', '....aaaaaaaa....', '................', '................', '................'],
        // 62 licor de jabuticaba (garrafa roxa)
        ['................', '.......aa.......', '......ayya......', '......aaaa......', '......adVa......', '......adVa......', '.....adVVVa.....', '....adVVVVVa....', '....adUUUUVa....', '....adUssUVa....', '....adUssUVa....', '....adUUUUVa....', '....adVVVVVa....', '....ayyyyyya....', '.....aaaaaa.....', '................'],
        // 63 chocolate (barra, metade no papel)
        ['................', '................', '.aaaaaaaaaaaaa..', '.ayynayynayyna..', '.aynnaynnaynna..', '.annnannnannna..', '.aaaaaaaaaaaaa..', '.ayynayynayyna..', '.aynnaynnaynna..', '.annnannnannna..', '.aaaaaaaaaaaaa..', '.afffffffffffa..', '.aBBBBBBBBBBBa..', '.aaaaaaaaaaaaa..', '................', '................'],
        // 64 barraca da feira (toldo listrado, frutas no balcão de madeira)
        ['................', '.aaaaaaaaaaaaaa.', 'aXXddXXddXXddXXa', 'aXXddXXddXXddXXa', 'aZZffZZffZZffZZa', '.aZa.aZa.aZa.aZa', '.ay..........ya.', '.ay..O....h..ya.', '.ay.OrO..hMh.ya.', 'aaaaaaaaaaaaaaaa', 'axxxxxxxxxxxxxxa', 'awwwwwwwwwwwwwwa', 'ayyynyyynyyynyya', 'ayyynyyynyyynyya', 'aaaaaaaaaaaaaaaa', '.aa..........aa.'],
        // fase 58: sementes e produtos do nível 20 ao 30 (65..84)
        // 65 cana-de-açúcar (planta)
        ['...v.......v....', '..vh..v...vh....', '..vh.vh..vh..v..', '...avh..avh.vh..', '...aMa..aMa.ha..', '...aMa.vaMavhv..', '..vaHahvaHa.aMa.', '.vhaMa..aMa.aMa.', '...aMa..aMa.aHa.', '...aHa..aHa.aMa.', '...aMa..aMa.aMa.', '...aMa..aMa.aMa.', '...aHa..aHa.aHa.', '..aaaaaaaaaaaaa.', '................', '................'],
        // 66 cana-de-açúcar
        ['................', '................', '..aa..aa..aa....', '..aGa.aGa.aGa...', '..aMa.aMa.aMa...', '..aHa.aHa.aHa...', '..aMa.aMa.aMa...', '.aaaaaaaaaaaaa..', '.aXXXXXXXXXXXa..', '.aaaaaaaaaaaaa..', '..aMa.aMa.aMa...', '..aHa.aHa.aHa...', '..aMa.aMa.aMa...', '..aaa.aaa.aaa...', '................', '................'],
        // 67 café (planta)
        ['................', '......aaaa......', '....aavhvvaa....', '...avhvvhvvha...', '..avvrvhvvrvva..', '..avhvvvrvhvva..', '.avrvhvvhvvrvva.', '.avvvrvhrvvhvva.', '.avhvvvvvvrvhva.', '..avvrhvvhvvva..', '...avvvrvvhva...', '....aaavvaaa....', '......ayya......', '......ayya......', '.....aaaaaa.....', '................'],
        // 68 café
        ['................', '................', '................', '................', '...aaaa.........', '..aynnya..aaaa..', '.aynnanya.aynnya', '.aynnanyaaynnany', '.aynnanyaaynnany', '.aynnanyaaynnany', '..aynaya.aynnany', '...aaaa..aynaya.', '..........aaaa..', '................', '................', '................'],
        // 69 algodão (planta)
        ['................', '....aaa...aaa...', '...adddaa.addda.', '...addfdaadfdda.', '....aaavaaaaaa..', '..aaa.avhva.....', '.addda.avva.aaa.', '.adfdda.vv.addda', '..aaaavaavafdda.', '.....avhvvaaaa..', '......avvva.....', '.......avva.....', '.......ayya.....', '.......ayya.....', '......aaaaaa....', '................'],
        // 70 algodão
        ['................', '................', '................', '.....aaaaaa.....', '...aaddddddaa...', '..adddfdddddda..', '.adddddddfdddda.', '.addfdddddddfda.', '.adddddfdddddda.', '..addddddddfda..', '...aaddfdddaa...', '....anyaaayna...', '.....annnnna....', '......aaaaa.....', '................', '................'],
        // 71 uva (planta)
        ['................', '..aaa......aaa..', '.avhva....avhva.', '.avvvaaaaaavvva.', '..aaayyyyyyaaa..', '.....aa..aya....', '....aUVa.aya....', '...aUVUVaaya....', '...aVUVUVaya....', '....aUVUVaya....', '.....aVUaaya....', '......aa.aya....', '........aaya....', '........ayya....', '.......aaaaaa...', '................'],
        // 72 uva
        ['................', '........aa......', '.......aya.aa...', '......aaya.avha.', '.....aUVaaavvha.', '....aUVUVaUVaa..', '...aUVdVUVUVa...', '...aVUVUVUVUa...', '....aUVdVUVa....', '....aVUVUVUa....', '.....aUVUVa.....', '.....aVUVUa.....', '......aUVa......', '.......aa.......', '................', '................'],
        // 73 pimenta (planta)
        ['................', '.....aaaaaa.....', '...aavhvvhvaa...', '..avhvvhvvhvva..', '..avvavvhavvha..', '.avhaXavvaXavva.', '.avvaXXavaXXava.', '..aaaXXaaaXXaa..', '.....aXa.aXa....', '......a..a......', '......avva......', '......avva......', '.......vv.......', '.......ay.......', '.....aaaaaa.....', '................'],
        // 74 pimenta
        ['................', '................', '...........aa...', '..........ava...', '.........avha...', '........aavva...', '.......aXXaa....', '......aXdXXa....', '.....aXXXXZa....', '....aXXXXXZa....', '...aXXXXXZa.....', '..aXXXXZZa......', '.aXXZZZaa.......', '.aZZaaa.........', '..aa............', '................'],
        // 75 baunilha (planta)
        ['................', '..aaa.....aaa...', '.aGsGa...aGsGa..', '.asgsa...asgsa..', '.aGsGa.a.aGsGa..', '..aaavavavaaa...', '....avhvhva.....', '...aavvhvvaa....', '..aGa.avva.aGa..', '.aGsGa.vv.aGsGa.', '.asgsa.vv.asgsa.', '..aaa..vv..aaa..', '......ayya......', '......ayya......', '.....aaaaaa.....', '................'],
        // 76 baunilha
        ['................', '................', '..aa............', '..ayaa..........', '...aynaa........', '....aynnaa......', '.....aynnnaa....', '....aaaggggaa...', '...aynnaggaynna.', '....aaynnnynnaa.', '......aaynnnnya.', '........aaynnya.', '..........aaaa..', '................', '................', '................'],
        // 77 açúcar (tigela de torrões)
        ['................', '................', '................', '......aaaa......', '....aaddfdaa....', '...adfdddfdda...', '..adddfddddfda..', '.aaaaaaaaaaaaaa.', '.aBBBBBBBBBBBBa.', '..aBdBBBBBBBBa..', '..aBBBBBBBBBBa..', '...aBBBBBBBBa...', '....aaaaaaaa....', '................', '................', '................'],
        // 78 café torrado (saco)
        ['................', '......aaaa......', '.....anyyna.....', '......aaaa......', '.....awwwwa.....', '....awwwwwwa....', '...awwaaaawwa...', '...awaynnyawa...', '...awaynanyawa..', '...awaynanyawa..', '...awwaaaawwa...', '...awwwwwwwwa...', '...anwwwwwwna...', '....aaaaaaaa....', '................', '................'],
        // 79 fio de algodão (carretel)
        ['................', '................', '....aaaaaaaa....', '....ayyyyyyna...', '....aaaaaaaaa...', '.....adddfda....', '.....afdddda....', '.....addfdda....', '.....adddfda....', '.....afdddda....', '.....addfddaa...', '....aaaaaaaafa..', '....ayyyyyyna.a.', '....aaaaaaaa....', '................', '................'],
        // 80 cappuccino (xícara com espuma)
        ['................', '......l..l......', '.......l..l.....', '......l..l......', '...aaaaaaaaaa...', '..axxxxxxxxxxa..', '..axxwxxxxwxxaaa', '..aaxxxwwxxxxada', '..adaaaaaaaaada.', '..addddddddddaa.', '..addddddddfda..', '...addddddfda...', '....aaaaaaaa....', '..aaaaaaaaaaaa..', '..afffffffffla..', '...aaaaaaaaaa...'],
        // 81 roupa (camisa)
        ['................', '................', '...aaaa..aaaa...', '..aBBBBaaBBBBa..', '.aBBBBBddBBBBBa.', 'aBBBBBBadBBBBBBa', 'aBBaBBBaEBBBaBBa', '.aaaBBBBEBBBaaa.', '...aBBBBEBBBa...', '...aBBBBEBBBa...', '...aBBBBEBBBa...', '...aBBBBEBBBa...', '...aBBBBEBBBa...', '...aaaaaaaaaa...', '................', '................'],
        // 82 vinho (garrafa)
        ['................', '.......aa.......', '......ayya......', '......aaaa......', '......aVVa......', '......adVa......', '.....adVVVa.....', '....adVVVVVa....', '....adZZZZVa....', '....adZssZVa....', '....adZssZVa....', '....adZZZZVa....', '....adVVVVVa....', '....aVVVVVVa....', '.....aaaaaa.....', '................'],
        // 83 molho picante (frasco)
        ['................', '.......aa.......', '......avva......', '......aaaa......', '......adXa......', '.....adXXXa.....', '....adXXXXXa....', '....adXXXXXa....', '....adsssssa....', '....adsXXXsa....', '....adsXdXsa....', '....adsXXXsa....', '....adsssssa....', '....aXXXXXZa....', '.....aaaaaa.....', '................'],
        // 84 bombom (papel dourado)
        ['................', '................', '................', '................', '.aa..........aa.', '.aga.aaaaaa.aga.', '.aggaynnnnyaaga.', '.aHgaynydnnyaHa.', '.aHgaynnnnnyaga.', '.aggaynnnnyaaga.', '.aHa.aaaaaa.aHa.', '.aa..........aa.', '................', '................', '................', '................'],
        // fase 60: materiais raros do píer (85..89)
        // 85 madeira nobre (tábuas escuras amarradas)
        ['................', '................', '................', '..aaaaaaaaaaaa..', '.anyyyyyyyyyyna.', '.aaaaaaaaaaaaaa.', '.aynnnnynnnnnya.', '.aaaaGaaaaGaaaa.', '.anyyyGyyyGyyna.', '.aaaaGaaaaGaaaa.', '.aynnnGnnnGnnya.', '.aaaaaaaaaaaaaa.', '..aynnnnnnnnya..', '...aaaaaaaaaa...', '................', '................'],
        // 86 corda naval (rolo)
        ['................', '................', '......aaaa......', '....aawxxwaa....', '...axwaaaawxa...', '..awxa....axwa..', '..axa.aaaa.axa..', '.awxa.axxa.awxa.', '.axwa.awwa.axwa.', '..axa.aaaa.axa..', '..awxa....axwa..', '...axwaaaawxa...', '....aawxxwaa..a.', '......aaaaaaaxa.', '.............aa.', '................'],
        // 87 pedra de cantaria (bloco lavrado)
        ['................', '................', '................', '....aaaaaaaaa...', '...adffffffdla..', '..adffffffdlla..', '..aaaaaaaaalla..', '..afffllfffala..', '..aflffffflala..', '..affffllffala..', '..aflfffffflaa..', '..afffflffffa...', '..aaaaaaaaaaa...', '................', '................', '................'],
        // 88 ferro forjado (barras)
        ['................', '................', '................', '................', '.....aaaaaaaa...', '....afddffffla..', '...aaaaaaaaaala.', '...afdffffflaaa.', '..aaaaaaaaaaalla', '..afdfffffflala.', '.afdffffffflaa..', '.aKKKKKKKKKKa...', '.aaaaaaaaaaaa...', '................', '................', '................'],
        // 89 âncora
        ['................', '.......aa.......', '......affa......', '......afla......', '.......aa.......', '....aaaKaaaa....', '....aKKKKKKa....', '.......aK.......', '.......aKa......', '.a.....aKa....a.', 'aKa....aKa...aKa', '.aKa...aKa..aKa.', '..aKaa.aKa.aKa..', '...aKKaaKaaKa...', '....aaKKKKKa....', '......aaaaa.....'],
        // fase 61: o leme dourado (prêmio do ranking da semana, peça do píer)
        // 90 leme dourado (aro dourado com brilho, miolo de madeira com os raios e 8 manoplas)
        ['......ayGa......', '..a...ayGa...a..', '.aGa.aayGaa.aGa.', '..ayaGGGdddaya..', '...aggGaaddda...', '..agganaanadda..', 'aaaggnaGGanddaaa', 'GGGHaaGaaGaadGGG', 'yyyHaaGaaGaaGyyy', 'aaaHHnaGGanGGaaa', '..aHHanaanagGa..', '...aHHHaaggga...', '..ayaHHHHggaya..', '.aGa.aayGaa.aGa.', '..a...ayGa...a..', '......ayGa......'],
        // fase 62: os peixes do alto-mar (de lado, a cabeça para a direita) e a pérola negra
        // 91 sardinha
        ['................', '................', '................', '................', '..........aa....', '........aaBBa...', 'a.....aaEEEEEaa.', 'aa...aEEEEEEdaEa', 'aBa.aEEEEEEEeaEa', 'aBBaEEEEEEEEEEEa', 'aBBaTTTTTTTTTTTa', 'aBa.aYYYYYYYYYYa', 'aa...aaYYYYYaa..', 'a......aaaaa....', '................', '................'],
        // 92 cavala
        ['................', '................', '................', '................', '..........aa....', '........aaSSa...', 'a.....aaSSSSSaa.', 'aa...aSSSSSSdaSa', 'aSa.aSSSSSSSeaSa', 'aSSaSSSSSSSSSSSa', 'aSSaBBBBBBBBBBBa', 'aSa.affffffffffa', 'aa...aafffffaa..', 'a......aaaaa....', '................', '................'],
        // 93 robalo
        ['................', '................', '................', '................', '..........aa....', '........aalla...', 'a.....aaKKKKKaa.', 'aa...aKKKKKKdaKa', 'ala.aKKKKKKKeaKa', 'allaKKKKKKKKKKKa', 'allaeeeeeeeeeeea', 'ala.affffffffffa', 'aa...aafffffaa..', 'a......aaaaa....', '................', '................'],
        // 94 garoupa
        ['................', '................', '........aaa.....', '.......aNNNa....', 'a....aayyyyyaa..', 'aa..ayyyyyyyyyya', 'aNaayysysyyyydya', 'aNNayyyyyyyyyyea', 'aNNasysyyysyyyya', 'aNNannnnnnnnnnna', 'aNNajjjjjjjjjjja', 'aNa.ajjjjjjjjjja', 'aa...ajjjjjjjaa.', 'a.....aaaNaaaa..', '........aa......', '................'],
        // 95 dourado-do-mar
        ['................', '................', '....aaaaaaaa....', '...aDDDDDDDDa...', 'a.aLLLLLLLLLLa..', 'aaLLLLLLLLLdLaa.', 'aDaLBLBLBLLeLaLa', 'aDDaLLLLLLLLLLLa', 'aDDaggggggggggga', 'aDDagGgGgGgGgGga', 'aDa.aGGGGGGGGGGa', 'aa...aaGGGGGGGa.', 'a......aDaaaa...', '........a.......', '................', '................'],
        // 96 atum
        ['................', '................', '........aa......', '.......agga.....', 'a....aaaFFFaaa..', 'aa..aFFFFFFFFFFa', 'agaagaFFFFFFFdFa', 'aggaFFFFFFFFFeaa', 'aggagallllllllla', 'aggafafffffffffa', 'agaagafffffffffa', 'aa..afffffffffa.', 'a....aaagaaaaa..', '........aa......', '................', '................'],
        // 97 marlim
        ['......a.........', '.....aEa........', '....aEEEa.......', '...aEEEEEa......', 'a.aEEEEEEEa.....', 'aaIIIIIIIIaa....', 'aEIIIIIIIIIdaaa.', 'aEIIIIIIIIIeIIaa', 'aEIEEEEEEEEEa...', 'aEafffffffffffa.', 'aa.afffffffffa..', 'a...aaaEaaaaaa..', '.......aa.......', '................', '................', '................'],
        // 98 pérola negra
        ['................', '................', '......aaaa......', '....aaJJJJaa....', '...aJJJJJJJJa...', '..aJdfJJJJJJVa..', '..aJfJJJJJJVVa..', '..aJJJJJJJVVUa..', '..aJJJJJJVVUUa..', '...aJJJVVVUUa...', '.aaaaaVVUUaaaaa.', 'aPmPPaaaaaaPPmPa', 'afPPmPPPPPPmPPfa', '.aflPPPPPPPPlfa.', '..aallllllllaa..', '....aaaaaaaa....'],
        // fase 63: os prêmios do evento da semana
        // 99 troféu de ouro
        ['................', '..aaaaaaaaaaaa..', '.aGaGGGGGgggaga.', 'aG.aGGGGgggga.ga', 'aG.aGGGGgggga.ga', '.aGaGGGGggggaga.', '..aaGGGggggHaa..', '....aGGgggHa....', '.....aGggHa.....', '......agHa......', '......agHa......', '.....aGggHa.....', '....aaaaaaaa....', '....ayyyyyyna...', '...annnnnnnnna..', '...aaaaaaaaaaa..'],
        // 100 troféu de prata
        ['................', '..aaaaaaaaaaaa..', '.adadddddfffafa.', 'ad.addddffffa.fa', 'ad.addddffffa.fa', '.adaddddffffafa.', '..aadddfffflaa..', '....addfffla....', '.....adffla.....', '......afla......', '......afla......', '.....adffla.....', '....aaaaaaaa....', '....ayyyyyyna...', '...annnnnnnnna..', '...aaaaaaaaaaa..'],
        // 101 troféu de bronze
        ['................', '..aaaaaaaaaaaa..', '.ajajjjjjkkkaka.', 'aj.ajjjjkkkka.ka', 'aj.ajjjjkkkka.ka', '.ajajjjjkkkkaka.', '..aajjjkkkkNaa..', '....ajjkkkNa....', '.....ajkkNa.....', '......akNa......', '......akNa......', '.....ajkkNa.....', '....aaaaaaaa....', '....ayyyyyyna...', '...annnnnnnnna..', '...aaaaaaaaaaa..'],
        // 102 ampulheta dourada
        ['................', '...aaaaaaaaaa...', '...agggggggHa...', '....aaaaaaaa....', '....aYYYYYYa....', '.....aGGGGa.....', '......aGGa......', '.......aa.......', '......aYGa......', '.....aYYGYa.....', '....aYYGGGYa....', '....aGGGGGGa....', '....aaaaaaaa....', '...agggggggHa...', '...aaaaaaaaaa...', '................'],
        // 103 cofrinho de ouro
        ['................', '.......aaa......', '......aGGga.....', '......aGHga.....', '...aaaaaaaaa.aa.', '..aGGGGaaGGGaGa.', '.aGGGGGGGGGGGGa.', 'aaGGGGGGGGGaGGGa', 'aGgGGGGGGGGGGaaa', 'aGgGGdGGGGGGGaga', '.aggGGGGGGGGGaaa', '..aggggggggggHa.', '..aHHa....aHHa..', '..aaaa....aaaa..', '................', '................'],
        // 104 balança de ouro
        ['................', '.......aa.......', '......aGga......', 'aaaaaaagHaaaaaaa', 'aGGGGGGgHgggggHa', 'aaaaaaagHaaaaaaa', '.a..a..gH..a..a.', '.a..a..gH..a..a.', '.a..a..gH..a..a.', 'aaaaaa.gH.aaaaaa', 'aGggHa.gH.aGggHa', '.aHHa..gH..aHHa.', '..aa...gH...aa..', '....aaagHaaa....', '...aGGggggHHa...', '...aaaaaaaaaa...'],
        // 105 sacola de ouro
        ['................', '.....aaaaaa.....', '....aHa..aHa....', '....aHa..aHa....', '..aaaaaaaaaaaa..', '..aGGGGGGGGgga..', '..aGdGGGGGGgga..', '..aGGGGGGGGgga..', '..aGGGaaaaGgga..', '..aGGaGGGgagga..', '..aGGaGgggagga..', '..aGGGaaaaGgga..', '..aGGGGGGGggHa..', '..agggggggggHa..', '..aaaaaaaaaaaa..', '................'],
        // fase 66: a luva do Perks (passa pelo alarme do vizinho)
        // 106 luva do Perks
        ['................', '....aa.aa.aa....', '...aVaaVaaVaa...', '...aVUaVUaVUaa..', '...aVUaVUaVUaUa.', '...aVUaVUaVUaUa.', '.aaaVUUVUUVUaUa.', 'aUUaVUUUUUUUUUa.', 'aVUUVUUUUUUUUUa.', '.aVVUUUUUUUUUUa.', '..aVUUUUUUUUUa..', '...aVUUUUUUUa...', '...aGGGGGGGGa...', '...agggHgggHa...', '...aaaaaaaaaa...', '................'],
        // fase 67: a praia (no lugar da mata na areia): coqueiro em 2 peças, pedras, duna, tronco e conchas
        // 107 copa do coqueiro
        ['................', '.....aa..aaaa...', '....aDDaahDDDa..', '....aLLDaDDLLa..', '....avaLhLLava..', '....aaaLDvaaa...',
         '...ahhhvDhhhha..', '..ahDDDDLDDDDha.', '..aDDLDDwDLhDDa.', '.aDDLDDnnnDDLDa.', 'aDDLDDaayyLDvDDa', 'aDLaDLaatuaDDLDa',
         'aDaDDvaanyaLDaDa', 'aLaDLa.anyavDDa.', 'avaDa..atuaaLDa.', '.aDa...anya.aDa.'],
        // 108 tronco do coqueiro
        ['.aDa...anya.aDa.', '.aLa...atua.aLa.', '.ava...anya..a..', '..a....anya.....', '.......atua.....', '.......anya.....',
         '.......anya.....', '.......atua.....', '.......anya.....', '.......anya.....', '.......atua.....', '.......anya.....',
         '......anya......', '......atua......', '......anya......', '......anya......'],
        // 109 pedras da praia
        ['................', '................', '................', '................', '................', '................',
         '....aaaaa.......', '..aafffflaa.....', '.afffffflKKa....', '.alllllllKKaaa..', 'allllllllKfffla.', '.allllllllllllKa',
         '.aKKKKKKKlllllKa', '..aaKKKKKaKKKKa.', '....aaaaa.aaaa..', '................'],
        // 110 duna com capim
        ['................', '................', '................', '................', '................', '......a.........',
         '....aaMa..a.a...', '...aMDMa.aMaMa..', '..aDaDDaaDDaDa..', '..aDaDDooDDaDa..', '..aooDooooDooa..', '.appppppppppppa.',
         'appppppppppppppa', 'aqqqqqqqqqqqqqqa', 'qqqqqqqqqqqqqqqq', 'aaaaaaaaaaaaaaaa'],
        // 111 tronco trazido pelo mar
        ['................', '................', '................', '................', '................', '................',
         '.....a..........', '....aua....a....', '..aauaaaaaauaa..', '.azzzzzzzzzzzza.', '.azuuuuuuuuuuqa.', '.atttttttttttta.',
         '..aaaaaaaaaaaa..', '................', '................', '................'],
        // 112 concha e estrela-do-mar
        ['................', '................', '................', '................', '................', '................',
         '..........aaa...', '....a....adPPa..', '...aia..aPPmPPa.', '..aiiia..aPPPa..', '.aiigiia..aQa...', '..aiaia....a....',
         '.aia.aia........', '..a...a.........', '................', '................'],
        // fase 69: as figuras das melhorias do alto-mar (no caminho dos níveis e no painel do píer)
        // 113 barco
        ['................', '...........a....', '..........ayaa..', '..........aygga.', '.....aaaaaaygga.', '....addddfaygga.',
         '....adBBdfayaa..', '....adBBdfaya...', '.aaaaddddfayaaa.', 'adddddddddddddda', '.aXXXXXXXXXXXXa.', '..abbbbbbbbbba..',
         'aaabbbbbbbbbbaaa', 'BBBBBBBBBBBBBBBB', 'BaaBaaBaaBaaBaaB', '................'],
        // 114 vara de pesca
        ['................', '................', '............aaa.', '...........aynfa', '..........aynafa', '.........aynaafa',
         '........ayna.afa', '.......ayna..afa', '......ayna...afa', '....aayna....afa', '...aKKKa.....afa', '...aKfKa....alla',
         '.aayKKKa....ala.', 'atttaaa......a..', 'attta...........', '.aaa............'],
        // 115 motor de popa
        ['................', '....aaaaaaaa....', '...abbbbbbbba...', '...abXXXXXbbaa..', '...abXXXXXbbKKa.', '...abbbbbbbbaa..',
         '...aZZZZZZZZa...', '....aalKKaaa....', '.....alKKa......', '.....alKKa......', '......aKKa......', '....aaaKKaaa....',
         '...afffKKfffa...', '...afffllfffa...', '....aaaaaaaa....', '................'],
        // 116 sonar
        ['.......aa.......', '....aaaKKaaa....', '...aKKKSSKKKa...', '..aKKSSSSSSKKa..', '.aKKSSSSSSSSKKa.', '.aKSShSSSSSWWKa.',
         '.aKSSSSSSWWSSKa.', 'aKSSSSSWWSSSSSKa', 'aKSSSSSSSSSSSSKa', '.aKShSSSSSSSSKa.', '.aKSSSSSSShSSKa.', '.aKKSSSSSSSSKKa.',
         '..aKKSSSSSSKKa..', '...aKKKSSKKKa...', '....aaaKKaaa....', '.......aa.......'],
        // 117 caixa de gelo
        ['.........aaa....', '....aaa.adYYa...', '...adYYaaYYYa...', '...aYYYaaYYYa...', '...aYYYfffaa....', '..aaaaffffaaaa..',
         '.adddddddddddda.', '.adddddddddddda.', '.aEEEEEEEEEEEEa.', '.aEBBBBBBBBBBEa.', '.aEBBBBBBBBBBEa.', '.aEBBBBBBBBBBEa.',
         '.aEBBBBBBBBBBEa.', '.aEEEEEEEEEEEEa.', '..aaaaaaaaaaaa..', '................'],
        // 118 rede de pesca
        ['................', '..aa.aa.aa.aa...', '.aiiaiiaiiaiia..', '.aiiaiiaiiaiia..', '.azazzazzazzaza.', '.azazzazzazzaza.',
         '..azaazaazaaza..', '.azazzazzazzaza.', '.azazzazzazzaza.', '..azaazaazaaza..', '.azazzazzazzaza.', '.azazzazzazzaza.',
         '..azaazaazaaza..', '.azazzazzazzaza.', '..a.aa.aa.aa.a..', '................'],
        // 119 bússola (kit de expedição)
        ['.......aa.......', '......aHHa......', '....aaHHHHaa....', '...aHHHYYHHHa...', '..aHHYYYYYYHHa..', '.aHHYYYbXYYYHHa.',
         '.aHYYYYbXYYYYHa.', 'aHHYYYYbXYYYYHHa', 'aHYYYYYKKYYYYYHa', 'aHYYYYYfdYYYYYHa', 'aHHYYYYfdYYYYHHa', '.aHYYYYfdYYYYHa.',
         '.aHHYYYfdYYYHHa.', '..aHHYYYYYYHHa..', '...aHHHYYHHHa...', '....aaHHHHaa....'],
        // 120 alicate do eletricista (cabos amarelos)
        ['................', '................', '................', '................', '................', '................',
         '.......aa.......', '......adla......', '......afla......', '.....afdfla.....', '.....aeaaea.....', '.....agaaga.....',
         '....aga..aga....', '....aHa..aHa....', '.....a....a.....', '................'],
        // fase 73: as frutas e os produtos do 31 ao 45, as sementes de estação, a praia e os baús da sorte
        // 121 coco
        ['................', '................', '................', '.....aaaaaa.....', '....annyyyya....', '...annyyyyyya...',
         '..annyayyayyya..', '..anyyyyyyyyya..', '..ayyyyyayyyya..', '..ayyyyyyyyyya..', '..ayyyyyyyyyya..', '...ayyyyyyyya...',
         '....ayyyyyya....', '.....aaaaaa.....', '................', '................'],
        // 122 caju
        ['................', '................', '......aaaa......', '....aaccXXaa....', '....accXXXXa....', '...accXXXXXXa...',
         '...acXXXXXXXa...', '...aXXXXXXXXa...', '....aXXXXXXa....', '....aaXXXXaa....', '......aaaa......', '......ayya......',
         '.....ayynna.....', '......anna......', '......aaaa......', '................'],
        // 123 açaí (cacho)
        ['................', '................', '....vv.vv.vv....', '......v..v..v...', '.....a..aVa.....', '....aVaaVUVa....',
         '...aVUVaaVa.a...', '....aVaa.a.aVa..', '.....aaVa.aVUVa.', '.....aVUVaaaVa..', '.....aaVaaVaaa..', '....aVaaaVUVaVa.',
         '...aVUVaVaVaVUVa', '....aVaVUVa.aVa.', '.....a.aVa...a..', '........a.......'],
        // 124 cupuaçu
        ['................', '........v.......', '......aaaa......', '.....awwnna.....', '....awwnynna....', '....awnnnnna....',
         '...awnynnnnna...', '...annnnnnnna...', '...annnnnynna...', '...annnnnnnna...', '...annnnnnnna...', '....annynnna....',
         '....annnnnya....', '.....annnna.....', '......aaaa......', '................'],
        // 125 castanha-do-pará (ouriço aberto)
        ['................', '................', '................', '.....aaaaaa.....', '....annyyyya....', '...annyyyyyya...',
         '..annaayyaayya..', '..anaxxaaxxaya..', '..ayaxxaaxxaya..', '..ayyaaaaaayya..', '..ayyyaxxayyya..', '..ayyyaxxayyya..',
         '...ayyyaayyya...', '....ayyyyyya....', '.....aaaaaa.....', '................'],
        // 126 cocada
        ['................', '................', '................', '................', '................', '................',
         '................', '..aaaaaaaaaaaa..', '..axxxxxxxxxxa..', '..axdxdxxxdxxa..', '..axxxxdxxxxxa..', '..axxdxxxdxdxa..',
         '..awwwwwwwwwwa..', '..aaaaaaaaaaaa..', '................', '................'],
        // 127 cajuína (garrafa)
        ['................', '......aaaa......', '......ayya......', '......aaaa......', '......adda......', '.....aGGGGa.....',
         '.....axGGGa.....', '....axGGGGGa....', '....axGGGGGa....', '....axXXXXXa....', '....axddddda....', '....axXXXXXa....',
         '....axGGGGGa....', '....axGGGGGa....', '....aaaaaaaa....', '................'],
        // 128 açaí na tigela
        ['................', '................', '................', '................', '................', '....aaaadaaa....',
         '..aaUUrVVXVVaa..', '..aUUGVVVVVGVa..', '..aaVVVVVVVVaa..', '..afaaaaaaaafa..', '...affffffffa...', '...affffffffa...',
         '....affffffa....', '....aaaaaaaa....', '................', '................'],
        // 129 creme de cupuaçu (pote)
        ['................', '................', '................', '.......aa.......', '....aaaynaaa....', '...ajjjjjwjja...',
         '...ajjjjjjjja...', '...aaaajjaaaa...', '...axxxaaxxxa...', '...awwwwwwwwa...', '...axxxxxxxxa...', '...awwwwwwwwa...',
         '...axxxxxxxxa...', '...axxxxxxxxa...', '...aaaaaaaaaa...', '................'],
        // 130 paçoca (3 tabletes)
        ['................', '................', '................', '................', '..aaaaaaaaaaaa..', '..axwxxaaxwxxa..',
         '..awxxwaawxxwa..', '..axxwxaaxxwxa..', '..aaaaaaaaaaaa..', '.....aaaaaa.....', '.....axxwxa.....', '.....axwxxa.....',
         '.....awxxwa.....', '.....aaaaaa.....', '................', '................'],
        // 131 maracujá
        ['................', '................', '........vv......', '......aaaa......', '....aasGGGaa....', '...assGGGGGGa...',
         '...asGGGGGHGa...', '..asGGGGGGGGGa..', '..aGGGHGGGGGGa..', '..aGGGGGGGHGGa..', '..aGGGGGGGGGGa..', '...aGGGGHGGGa...',
         '...aGGGHGGGGa...', '....aaGGGGaa....', '......aaaa......', '................'],
        // 132 mexerica
        ['................', '................', '.........vv.....', '........a.h.....', '.....aaaaaa.....', '...aaggiiiiaa...',
         '...aggiiiiiia...', '..aggiiiiiiiia..', '..agiiiiiiiiia..', '..aiiiiiiiiiia..', '..aiiiNiiiNiia..', '...aiiiiiiiia...',
         '...aaiiiiiiaa...', '.....aaaaaa.....', '................', '................'],
        // 133 caqui
        ['................', '................', '................', '........a.......', '.....vvvvvvv....', '...avOOccccva...',
         '...aOOcccccca...', '..aOOcccccccca..', '..aOccccccccca..', '..acccccccccca..', '..acccccccccca..', '...acccccccca...',
         '...aaccccccaa...', '.....aaaaaa.....', '................', '................'],
        // 134 lichia
        ['................', '................', '........v.......', '.......v.v......', '........vaaa....', '....aaaammrra...',
         '...ammramrrra...', '...amrrarrRra...', '...arraaaarra...', '...arammrraa....', '....aamrrra.....', '.....arrRra.....',
         '.....arrrra.....', '......aaaa......', '................', '................'],
        // 135 pé de maracujá
        ['................', '................', '................', '....MMLLLLLL....', '...MMDDDDDDDL...', '..MMDDGGDDGGDL..',
         '..MDDDGHDDGHDL..', '..LDGGDDDDDDDL..', '..LDGHDDDDDDDL..', '..LDDDDDDDDGGL..', '..LDDDDGGDDGHL..', '...LDDDGHDDDL...',
         '....LLLLLLLL....', '.......LL.......', '.......LL.......', '.......aa.......'],
        // 136 pé de mexerica
        ['................', '................', '................', '....MMLLLLLL....', '...MMDDDDDDDL...', '..MMDDiiDDiiDL..',
         '..MDDDiNDDiNDL..', '..LDiiDDDDDDDL..', '..LDiNDDDDDDDL..', '..LDDDDDDDDiiL..', '..LDDDDiiDDiNL..', '...LDDDiNDDDL...',
         '....LLLLLLLL....', '.......LL.......', '.......LL.......', '.......aa.......'],
        // 137 pé de caqui
        ['................', '................', '................', '....MMLLLLLL....', '...MMDDDDDDDL...', '..MMDDccDDccDL..',
         '..MDDDcNDDcNDL..', '..LDccDDDDDDDL..', '..LDcNDDDDDDDL..', '..LDDDDDDDDccL..', '..LDDDDccDDcNL..', '...LDDDcNDDDL...',
         '....LLLLLLLL....', '.......LL.......', '.......LL.......', '.......aa.......'],
        // 138 pé de lichia
        ['................', '................', '................', '....MMLLLLLL....', '...MMDDDDDDDL...', '..MMDDrrDDrrDL..',
         '..MDDDrRDDrRDL..', '..LDrrDDDDDDDL..', '..LDrRDDDDDDDL..', '..LDDDDDDDDrrL..', '..LDDDDrrDDrRL..', '...LDDDrRDDDL...',
         '....LLLLLLLL....', '.......LL.......', '.......LL.......', '.......aa.......'],
        // 139 guarda-sol
        ['........a.......', '.......ada......', '......adXXa.....', '.....adXXdda....', '...adXXddXXdda..', '..adXXddXXddXXa.',
         'aaaaaaaaaaaaaaaa', '........u.......', '........u.......', '........u.......', '........u.......', '........u.......',
         '........u.......', '........u.......', '........u.......', '.......pup......'],
        // 140 cadeira de praia
        ['................', '................', '................', '................', '..add...........', '...aBB..........',
         '....add.........', '.....aBB........', '......add.......', '.......aBB......', '........BBBBBB..', '....u...auaaua..',
         '....u....u..u...', '....u....u..u...', '....u....u..u...', '................'],
        // 141 castelo de areia
        ['................', '.......aXX......', '.......aX.......', '.......a........', '....a.aa.a.a....', '....aaaaaaaa....',
         '....aooooooa....', '....aooooooa....', '..a.aooooooa.a..', '..aaaaaaaaaaaa..', '..aooooooooooa..', '..aoooaaaaoooa..',
         '..aoooaqqaoooa..', '..appppppppppa..', '..aaaaaaaaaaaa..', '................'],
        // 142 barraca de coco
        ['................', '................', '................', '.aaaaaaaaaaaaaa.', '.adXdXdXdXdXdXa.', '.aaaaaaaaaaaaaa.',
         '..u..aa..aa..u..', '..u.ayyaayya.u..', '..u.ayyaayya.u..', '..aaaaaaaaaaaa..', '..annnnnnnnnna..', '..annnnnnnnnna..',
         '..annnnnnnnnna..', '..ayyyyyyyyyya..', '..aaaaaaaaaaaa..', '................'],
        // 143 baú da sorte de madeira
        ['................', '............d...', '..G..........G..', '..............d.', '.aaaaaaaaaaaaaa.', '.ayyyyyyyyyyyya.',
         '.annynnnnnnynna.', '.annynaaaanynna.', '.aaayaaGGaayaaa.', '.annynaaaanynna.', '.annynaaaanynna.', '.annynnnnnnynna.',
         '.annynnnnnnynna.', '.annynnnnnnynna.', '.aaaaaaaaaaaaaa.', '................'],
        // 144 baú da sorte de prata
        ['................', '............d...', '..G..........G..', '..............d.', '.aaaaaaaaaaaaaa.', '.affffffffffffa.',
         '.allfllllllflla.', '.allflaaaalflla.', '.aaafaaGGaafaaa.', '.allflaaaalflla.', '.allflaaaalflla.', '.allfllllllflla.',
         '.allfllllllflla.', '.allfllllllflla.', '.aaaaaaaaaaaaaa.', '................'],
        // 145 baú da sorte de ouro
        ['................', '............d...', '..G..........G..', '..............d.', '.aaaaaaaaaaaaaa.', '.aGGGGGGGGGGGGa.',
         '.aHHGHHHHHHGHHa.', '.aHHGHaaaaHGHHa.', '.aaaGaaGGaaGaaa.', '.aHHGHaaaaHGHHa.', '.aHHGHaaaaHGHHa.', '.aHHGHHHHHHGHHa.',
         '.aHHGHHHHHHGHHa.', '.aHHGHHHHHHGHHa.', '.aaaaaaaaaaaaaa.', '................'],
        // fase 74: cabra, búfala, os leites, a mussarela e os pratos dos peixes do mar
        // 146 cabra
        ['................', '..a.a...........', '.afafa..........', '..affda.........', '..adddda........', '.adeddda........',
         '.addddddaaaaaa..', '..aadddddddddda.', '....adddddddddda', '....affddddddfda', '....afffddddffa.', '....aaffffffffa.',
         '.....afa...afa..', '.....afa...afa..', '.....aaa...aaa..', '................'],
        // 147 búfala
        ['................', '.aa.............', 'afa.aa..........', '.afaKea.........', '..aKeeea........', '.aeeeeeeaaaaaaa.',
         'aeKeeeeeeeeeeeea', '.aaeeeeeeeeeeeea', '...aeKeeeeeeeKea', '...aeeeeeeeeeea.', '...aaeeeeeeeeea.', '....aea....aea..',
         '....aea....aea..', '....aaa....aaa..', '................', '................'],
        // 148 leite de cabra
        ['................', '......aaaa......', '......aaaa......', '......adda......', '......adda......', '....addfddda....',
         '....afddddda....', '....afddddda....', '....afhhhhha....', '....afhhhhha....', '....afhhhhha....', '....afhhhhha....',
         '....afddddda....', '....afddddda....', '....aaaaaaaa....', '................'],
        // 149 leite de búfala
        ['................', '......aaaa......', '......aaaa......', '......adda......', '......adda......', '....addfddda....',
         '....afddddda....', '....afddddda....', '....afKKKKKa....', '....afKKKKKa....', '....afKKKKKa....', '....afKKKKKa....',
         '....afddddda....', '....afddddda....', '....aaaaaaaa....', '................'],
        // 150 mussarela
        ['................', '................', '................', '.......hvh......', '.....aaaaaa.....', '...aaffddddaa...',
         '...affdddddda...', '..affdfdddddda..', '..afddddddddda..', '..adddddddddda..', '..adddddddfdda..', '...adddddddda...',
         '...aadddfddaa...', '.....aaaaaa.....', '................', '................'],
        // 151 sardinha em lata
        ['................', '................', '................', '................', '................', '.aKKKKKKKKKKKKa.',
         '.affffffffffffa.', '.afffffffffaffa.', '.afBKKKKKKKKKfa.', '.afKBBBBBBBBBfa.', '.affffffffffffa.', '.affffffffffffa.',
         '.aaaaaaaaaaaaaa.', '................', '................', '................'],
        // 152 sashimi
        ['................', '................', '................', '................', '................', '................',
         '................', '...aaaaaaaaaa...', '..adamaamaamaa..', '.addadaadaadada.', '.addaaaaaaaaaha.', '..adddddddddha..',
         '...aaaaaaaaaa...', '................', '................', '................'],
        // 153 caldeirada
        ['................', '................', '................', '.......f..f.....', '......f..f......', '................',
         '.aaaaaaaaaaaaaa.', '..aiiXiiiviiia..', 'a.adiidiidiXda.a', '..aKKKKKKKKKKa..', '..aKKKKKKKKKKa..', '..aKKKKKKKKKKa..',
         '..aKKKKKKKKKKa..', '..aaaaaaaaaaaa..', '................', '................'],
        // 154 carrinho de milho (fase 97: o vendedor da praia)
        ['................', '.aaaaaaaaaaaaaa.', '.aGXGXGXGXGXGXa.', '.aaaaaaaaaaaaaa.', '..u..........u..', '..u.aG.aG.aG.u..',
         '..uaGGaGGaGGau..', '..uavvavvavvau..', '..aaaaaaaaaaaa..', '..agggggggggga..', '..agHHgHHgHHga..', '..agggggggggga..',
         '..aaaaaaaaaaaa..', '...aKKa..aKKa...', '...aaaa..aaaa...', '................'],
        // fase 104: os materiais do barco
        // 155 tora de ipê
        ['................', '................', '................', '................', '..aaaaaaaaaaaa..', '.ayyyyyyyyyaxxa.',
         '.annnnynnnnawwxa', '.anynnnnnynaxwxa', '.annnnnynnnawwxa', '.ayyyyyyyyyaxxa.', '..aaaaaaaaaaaa..', '................',
         '................', '................', '................', '................'],
        // 156 tábua naval
        ['................', '................', '................', '.aaaaaaaaaaaaa..', '.axxxxxxxxxxxa..', '.awwwywwwwwywa..',
         '.aaaaaaaaaaaaaaa', '..axxxxxxxxxxxxa', '..awwwwwywwwwwwa', '.aaaaaaaaaaaaaaa', '.axxxxxxxxxxxxa.', '.awwywwwwwwywwa.',
         '.aaaaaaaaaaaaaa.', '................', '................', '................'],
        // 157 cravo de ferro
        ['................', '.aaaa.aaaa.aaaa.', '.affa.affa.affa.', '.aaaa.aaaa.aaaa.', '.afla.afla.afla.', '.afla.afla.afla.',
         '.afla.afla.afla.', '.alKa.alKa.alKa.', '.alKa.alKa.alKa.', '.alKa.alKa.alKa.', '.alKa.alKa.alKa.', '..aa...aa...aa..',
         '................', '................', '................', '................'],
        // 158 vela de navio
        ['.......aa.......', '..aaaaaaaaaaaa..', '..ayyyyyyyyyya..', '..aaaaaaaaaaaa..', '...addddddfda...', '...addddddfda...',
         '...addddddfda...', '...aXXXXXXXXa...', '...addddddfda...', '...addddddfda...', '...addddddfda...', '...affffffffa...',
         '...aaaaaaaaaa...', '.......aya......', '.......aya......', '.......aaa......'],
        // 159 carta náutica
        ['................', '................', '..aaaaaaaaaaaa..', '.awxxxxxxxxxxwa.', '.awxBBxxxxxxxwa.', '.awBBBBxxxtxxwa.',
         '.awxBBxxxtxxxwa.', '.awxxxxxtxxxxwa.', '.awxxxxtxxxXxwa.', '.awxxxtxxxXxXwa.', '.awxxxxxxxxXxwa.', '.awxxxxxxxXxXwa.',
         '..aaaaaaaaaaaa..', '................', '................', '................']
    ];
    const atlasProprio = document.createElement('canvas');
    atlasProprio.width = 12 * 16;
    atlasProprio.height = LINHAS_PROPRIA * 16;   // 12 colunas como os pacotes, mais linhas (htmlTile conta)
    {
        const g = atlasProprio.getContext('2d');
        PROPRIA.forEach((linhas, n) => linhas.forEach((linha, y) => [...linha].forEach((ch, x) => {
            if (PAL_PROPRIA[ch]) { g.fillStyle = PAL_PROPRIA[ch]; g.fillRect((n % COLS) * 16 + x, Math.floor(n / COLS) * 16 + y, 1, 1); }   // em grade, como os pacotes
        })));
    }
    let urlPropria = null;

    /* ---------- Avatar do fazendeiro ----------
       O avatar é um personagem pronto do Kenney (Tiny Farm e Tiny Dungeon, que usam a mesma
       paleta) com as cores trocadas por região: cada região diz quais cores do desenho são dela,
       em que linhas (e colunas) e em que tom (0 escuro, 1 médio, 2 claro). A cor 0 de cada
       região é sempre a original do personagem; as outras vêm de AVATAR_CORES, em três tons,
       então o sombreado continua certo em qualquer cor. */
    const AVATAR_TIPOS = {
        fazendeiro: { nome: 'Fazendeiro', p: 'farm', i: 109, regioes: {
            chapeu: { nome: 'Chapéu', cores: { '#cf8254': 1, '#fec99c': 2 }, y: [0, 7] },
            pele: { cores: { '#e19a65': 0, '#f7c282': 1 }, y: [6, 16] },
            roupa: { nome: 'Camisa', cores: { '#f28462': 1 }, y: [9, 16] },
            calca: { nome: 'Macacão', cores: { '#52607c': 1, '#8c9cb5': 2 }, y: [9, 16] } } },
        // fase 66: a fazendeira é a moça de cabelo comprido (a mesma da Dona Benta); a de antes, de
        // cabelo curto, parecia careca e barbuda. A flor do cabelo (linhas 3 a 5) não muda com a pele
        // fase 69: só sai no dia 28 do calendário dourado (fazenda_avatar_exclusivos). As cores de base
        // (base) valem quando a bolinha escolhida é a "original"
        fazendeiro_ouro: { nome: 'Fazendeiro de ouro', p: 'farm', i: 109, exclusivo: true,
            base: { chapeu: ['#9a6b22', '#d9a43a', '#f2d06b'], roupa: ['#8b9bb4', '#c0cbdc', '#f4f6fa'], calca: ['#9a6b22', '#d9a43a', '#f2d06b'] }, regioes: {
            chapeu: { nome: 'Chapéu', cores: { '#cf8254': 1, '#fec99c': 2 }, y: [0, 7] },
            pele: { cores: { '#e19a65': 0, '#f7c282': 1 }, y: [6, 16] },
            roupa: { nome: 'Camisa', cores: { '#f28462': 1 }, y: [9, 16] },
            calca: { nome: 'Macacão', cores: { '#52607c': 1, '#8c9cb5': 2 }, y: [9, 16] } } },
        fazendeira: { nome: 'Fazendeira', p: 'dungeon', i: 99, regioes: {
            cabelo: { nome: 'Cabelo', cores: { '#763b36': 1, '#bd6c4a': 2 }, y: [0, 14] },
            pele: { cores: { '#e19a65': 0, '#eaa56c': 0, '#f7c282': 1 }, y: [6, 16] },
            roupa: { nome: 'Vestido', cores: { '#9b4ca3': 1, '#d176d0': 2 }, y: [11, 16] } } },
        rapaz: { nome: 'Rapaz', p: 'dungeon', i: 85, regioes: {
            cabelo: { nome: 'Cabelo', cores: { '#763b36': 1, '#bd6c4a': 2 }, y: [0, 10] },
            pele: { cores: { '#e19a65': 0, '#f7c282': 1 }, y: [4, 16] },
            roupa: { nome: 'Camisa', cores: { '#8b9bb4': 1, '#c0cbdc': 2 }, y: [10, 13] },
            calca: { nome: 'Calça', cores: { '#bd6c4a': 2, '#763b36': 1 }, y: [13, 15] } } },
        mago: { nome: 'Mago', p: 'dungeon', i: 84, regioes: {
            roupa: { nome: 'Manto e chapéu', cores: { '#9b4ca3': 1, '#d176d0': 2 }, y: [0, 16] },
            cabelo: { nome: 'Barba', cores: { '#8b9bb4': 1, '#aab7cc': 2, '#c0cbdc': 2 }, y: [5, 16] },
            pele: { cores: { '#f7c282': 1 }, y: [0, 16] } } },
        viking: { nome: 'Viking', p: 'dungeon', i: 87, regioes: {
            chapeu: { nome: 'Capacete', cores: { '#8b9bb4': 1, '#c0cbdc': 2 }, y: [0, 9] },
            cabelo: { nome: 'Barba', cores: { '#bd6c4a': 1 }, y: [9, 13], x: [4, 12] },
            pele: { cores: { '#e19a65': 0, '#f7c282': 1 }, y: [0, 16] },
            roupa: { nome: 'Armadura', cores: { '#8b9bb4': 1, '#c0cbdc': 2 }, y: [9, 14] },
            calca: { nome: 'Calça', cores: { '#52607c': 1 }, y: [14, 15] } } },
        cavaleiro: { nome: 'Cavaleiro', p: 'dungeon', i: 97, regioes: {
            roupa: { nome: 'Armadura', cores: { '#52607c': 0, '#8b9bb4': 1, '#c0cbdc': 2 }, y: [0, 16] },
            pele: { cores: { '#e19a65': 0, '#f7c282': 1 }, y: [0, 16] } } },
        // fase 43: os de diamante (fazenda_avatar_diamantes). Os do caminhoneiro e da mascate
        // (112, 100) ficam só para as visitas da porteira
        soldado: { nome: 'Soldado', p: 'dungeon', i: 98, regioes: {
            cabelo: { nome: 'Cabelo', cores: { '#bd6c4a': 2, '#763b36': 1 }, y: [0, 9] },
            pele: { cores: { '#e19a65': 0, '#f7c282': 1 }, y: [0, 16] },
            roupa: { nome: 'Armadura', cores: { '#8b9bb4': 1, '#c0cbdc': 2 }, y: [10, 16] },
            calca: { nome: 'Calça', cores: { '#52607c': 1 }, y: [12, 16] } } },
        barbaro: { nome: 'Bárbaro', p: 'dungeon', i: 88, regioes: {
            cabelo: { nome: 'Cabelo', cores: { '#bd6c4a': 2, '#763b36': 1 }, y: [0, 6] },
            pele: { cores: { '#e19a65': 0, '#f7c282': 1 }, y: [0, 16] },
            calca: { nome: 'Tanga', cores: { '#bd6c4a': 2, '#763b36': 1 }, y: [12, 16] } } },
        guarda: { nome: 'Guarda', p: 'dungeon', i: 96, regioes: {
            roupa: { nome: 'Armadura', cores: { '#52607c': 0, '#8b9bb4': 1, '#c0cbdc': 2 }, y: [0, 16] } } },
        feiticeiro: { nome: 'Feiticeiro', p: 'dungeon', i: 111, regioes: {
            roupa: { nome: 'Manto', cores: { '#763b36': 0, '#bd6c4a': 1 }, y: [0, 16] },
            cabelo: { nome: 'Barba', cores: { '#8b9bb4': 1, '#aab7cc': 2, '#c0cbdc': 2 }, y: [8, 16] } } },
        fantasma: { nome: 'Fantasma', p: 'dungeon', i: 108, regioes: {
            roupa: { nome: 'Cor', cores: { '#25956a': 0, '#43e1b3': 1, '#69ffd4': 2 }, y: [0, 16] } } },
        ciclope: { nome: 'Ciclope', p: 'dungeon', i: 109, regioes: {
            pele: { cores: { '#e19a65': 0, '#f7c282': 1 }, y: [0, 16] },
            calca: { nome: 'Tanga', cores: { '#bd6c4a': 2, '#763b36': 1 }, y: [11, 16] } } },
        diabinho: { nome: 'Diabinho', p: 'dungeon', i: 110, regioes: {
            roupa: { nome: 'Cor', cores: { '#e84537': 1, '#ff706d': 2 }, y: [0, 16] } } },
        morcego: { nome: 'Morcego', p: 'dungeon', i: 120, regioes: {
            roupa: { nome: 'Asas', cores: { '#763b36': 0, '#bd6c4a': 1, '#eaa56c': 2 }, y: [0, 16] } } }
    };
    // cores à escolha (a 0, "original", não está aqui): [escuro, médio, claro]
    const TONS = {
        vermelho: ['#7a2420', '#c34b35', '#f28462'], azul: ['#29366f', '#3b5dc9', '#79a7e8'], verde: ['#2d5a32', '#3e8948', '#6abe30'],
        amarelo: ['#b0631e', '#e38628', '#fdbe53'], roxo: ['#5a2a6a', '#9b4ca3', '#d176d0'], branco: ['#8b9bb4', '#c0cbdc', '#f4f6fa'],
        preto: ['#1a1c2c', '#333c57', '#566c86'], marrom: ['#4d2a24', '#763b36', '#bd6c4a'], rosa: ['#8a3a5a', '#d27688', '#f5a3b0']
    };
    const AVATAR_CORES = {
        pele: [['#eaa56c', '#fde0c4'], ['#b9744a', '#d99a66'], ['#8a5236', '#ad6c45'], ['#5e3726', '#7d4c33']],   // [sombra, luz]
        cabelo: [['#3f2631', '#763b36', '#bd6c4a'], ['#1a1c2c', '#262b44', '#3f3f5f'], ['#9a6b22', '#d9a43a', '#f2d06b'], ['#6e2516', '#9e3a1f', '#e2683a'], ['#566c86', '#8b9bb4', '#c0cbdc']],
        roupa: [TONS.vermelho, TONS.azul, TONS.verde, TONS.amarelo, TONS.roxo, TONS.branco, TONS.preto],
        calca: [TONS.azul, TONS.marrom, TONS.verde, TONS.preto, TONS.rosa],
        chapeu: [TONS.vermelho, TONS.azul, TONS.verde, TONS.preto, TONS.roxo]
    };
    const NOME_REGIAO = { pele: 'Pele', cabelo: 'Cabelo', roupa: 'Roupa', calca: 'Calça', chapeu: 'Chapéu' };
    // avatar salvo na primeira versão ({ chapeu: 'palha', ... }): vira o fazendeiro com a mesma pele
    function normalizarAvatar(cfg) {
        cfg = cfg || {};
        if (!AVATAR_TIPOS[cfg.tipo]) cfg = { tipo: 'fazendeiro', pele: typeof cfg.chapeu === 'string' ? cfg.pele | 0 : 0 };
        return cfg;
    }
    /* ---- fase 107: os bichos desenhados aqui, com mais detalhe e maiores (vaca e búfala 26 x 20; ovelha,
       porco e cabra 22; galinha, pato e coelho 16), em dois quadros de andar. Olham para a direita (o
       jogo vira quando andam para a esquerda). O pato fica com 16 x 16, para nadar certo no laguinho. ---- */
    const cacheBicho = new Map();
    function bichoCanvas(tipo, quadro) {
        const chave = tipo + quadro;
        if (cacheBicho.has(chave)) return cacheBicho.get(chave);
        const TAM = { vaca: [26, 20], bufala: [26, 20], ovelha: [22, 17], porco: [22, 15], cabra: [22, 19], galinha: [16, 16], pato: [16, 16], coelho: [16, 16] };
        const [W, H] = TAM[tipo] || [16, 16];
        const cv = document.createElement('canvas'); cv.width = W; cv.height = H;
        const g = cv.getContext('2d'), OL = '#3f2631';
        const R = (x, y, w, h, c) => { if (w > 0 && h > 0) { g.fillStyle = c; g.fillRect(x, y, w, h); } };
        // um corpo oval com contorno e a barriga mais escura
        const oval = (cx, cy, rx, ry, cor, sombra, luz) => {
            for (let y = -ry; y <= ry; y++) {
                const w = Math.round(rx * Math.sqrt(Math.max(0, 1 - (y * y) / (ry * ry + 0.5))));
                R(cx - w - 1, cy + y, 2 * w + 3, 1, OL);
            }
            for (let y = -ry + 1; y <= ry - 1; y++) {
                const w = Math.round(rx * Math.sqrt(Math.max(0, 1 - (y * y) / (ry * ry + 0.5)))) - 1;
                R(cx - w, cy + y, 2 * w + 1, 1, y > ry * 0.35 ? sombra : cor);
                if (luz && y < -ry * 0.3) R(cx - w + 2, cy + y, Math.max(1, w), 1, luz);
            }
        };
        const perna = (x, y, h, cor, casco) => { R(x - 1, y, 4, h + 1, OL); R(x, y, 2, h - 1, cor); R(x, y + h - 1, 2, 1, casco || OL); };
        const pernas = (xs, y, h, cor, casco) => xs.forEach((x, k) => perna(x + (quadro && k % 2 ? 1 : 0) - (quadro && !(k % 2) ? 1 : 0), y + (quadro && k % 2 ? -1 : 0), h, cor, casco));
        R(2, H - 2, W - 4, 2, 'rgba(30,40,20,0.25)');   // a sombra no chão
        if (tipo === 'vaca' || tipo === 'bufala') {
            const bu = tipo === 'bufala', cor = bu ? '#4a4450' : '#f4f1e6', sombra = bu ? '#2f2a34' : '#d8d2c8', luz = bu ? '#6a6472' : '#ffffff';
            pernas([5, 9, 15, 19], 13, 6, bu ? '#2f2a34' : '#f4f1e6', bu ? '#1a1630' : '#5a3a28');
            oval(12, 10, 9, 5, cor, sombra, luz);
            if (!bu) { R(6, 7, 4, 3, '#2b2b38'); R(13, 9, 5, 3, '#2b2b38'); R(9, 12, 3, 2, '#2b2b38'); R(14, 6, 2, 2, '#2b2b38'); }   // as manchas
            if (!bu) { R(13, 14, 4, 2, OL); R(14, 14, 2, 2, '#f5a3b0'); }   // o úbere
            // a cabeça e o focinho
            R(19, 4, 7, 9, OL); R(20, 5, 5, 7, cor); R(20, 5, 5, 1, luz);
            R(21, 10, 5, 3, OL); R(21, 10, 4, 2, bu ? '#5a5560' : '#f5a3b0'); R(23, 11, 1, 1, OL);
            R(22, 7, 1, 1, OL);   // o olho
            if (bu) { R(17, 2, 4, 2, OL); R(18, 2, 2, 1, '#c8c0b0'); R(16, 3, 2, 2, OL); R(24, 2, 3, 2, OL); R(25, 2, 1, 1, '#c8c0b0'); }   // os chifres curvos
            else { R(20, 3, 2, 2, OL); R(20, 3, 1, 1, '#e8dcc0'); R(24, 3, 2, 2, OL); R(24, 3, 1, 1, '#e8dcc0'); R(18, 5, 2, 2, cor); }   // os chifrinhos e a orelha
            // o rabo com o tufo
            R(2, 7, 1, 6, OL); R(1, 12, 3, 2, bu ? '#1a1630' : '#2b2b38');
            if (!bu) R(3, 6, 1, 1, OL);
        } else if (tipo === 'ovelha') {
            pernas([6, 9, 13, 16], 11, 5, '#2b2b38', '#1a1630');
            // a lã: um monte de bolinhas
            oval(10, 8, 8, 5, '#f4f1e6', '#d8d2c8', '#ffffff');
            for (const [x, y] of [[4, 5], [8, 3], [12, 3], [15, 5], [3, 9], [17, 9], [7, 12], [13, 12]]) { R(x - 1, y - 1, 4, 4, OL); R(x, y, 2, 2, '#f4f1e6'); R(x, y, 1, 1, '#ffffff'); }
            for (let k = 0; k < 6; k++) R(5 + k * 2, 6 + (k % 2) * 3, 1, 1, '#d8d2c8');
            // a cara escura com a orelha
            R(16, 4, 6, 8, OL); R(17, 5, 4, 6, '#3a3440'); R(17, 5, 4, 1, '#5a5460'); R(19, 7, 1, 1, '#ffffff'); R(20, 9, 1, 1, '#1a1630');
            R(15, 5, 2, 2, '#3a3440');
            R(15, 2, 4, 3, '#f4f1e6'); R(15, 2, 4, 1, '#ffffff');   // o topete de lã
        } else if (tipo === 'porco') {
            pernas([6, 9, 13, 16], 10, 4, '#e98b9b', '#8a4a4a');
            oval(11, 7, 8, 5, '#f5a3b0', '#e98b9b', '#ffc8d0');
            // a cabeça, o focinho com os furinhos e as orelhas caídas
            R(16, 3, 6, 8, OL); R(17, 4, 4, 6, '#f5a3b0'); R(17, 4, 4, 1, '#ffc8d0');
            R(19, 7, 4, 3, OL); R(20, 7, 2, 2, '#e98b9b'); R(20, 8, 1, 1, '#8a4a4a'); R(21, 8, 1, 1, '#8a4a4a');
            R(18, 5, 1, 1, OL); R(16, 2, 3, 2, OL); R(17, 2, 1, 2, '#d27688');
            // o rabinho enrolado
            R(1, 4, 2, 1, '#d27688'); R(1, 3, 1, 1, '#d27688'); R(2, 2, 1, 1, '#d27688'); R(3, 3, 1, 2, OL);
            R(6, 4, 3, 1, '#ffc8d0'); R(10, 11, 2, 1, '#d27688');
        } else if (tipo === 'cabra') {
            pernas([6, 9, 13, 16], 13, 5, '#d8c8a8', '#3f2631');
            oval(10, 10, 8, 4, '#efe4cc', '#d0c0a0', '#ffffff');
            R(3, 8, 2, 3, OL); R(3, 8, 1, 2, '#efe4cc');   // o rabinho em pé
            // a cabeça com os chifres para trás e a barbicha
            R(15, 4, 6, 9, OL); R(16, 5, 4, 7, '#efe4cc'); R(16, 5, 4, 1, '#ffffff');
            R(19, 10, 3, 2, OL); R(19, 10, 2, 1, '#f5a3b0');
            R(18, 7, 1, 1, OL);
            R(15, 1, 2, 4, OL); R(14, 0, 2, 2, OL); R(15, 2, 1, 2, '#a89878'); R(18, 1, 2, 4, OL); R(18, 2, 1, 2, '#a89878');   // os chifres
            R(17, 12, 2, 4, OL); R(17, 12, 1, 3, '#d0c0a0');   // a barbicha
            R(13, 5, 3, 2, '#efe4cc'); R(13, 5, 3, 1, OL);   // a orelha
        } else if (tipo === 'galinha') {
            pernas([6, 9], 12, 3, '#e38628', '#e38628');
            oval(7, 8, 5, 4, '#ffffff', '#e4e8ee', null);
            R(1, 4, 3, 3, OL); R(2, 5, 2, 2, '#ffffff'); R(1, 3, 2, 2, OL); R(1, 3, 1, 1, '#ffffff');   // o rabo de penas
            R(5, 8, 4, 2, '#d8dee6'); R(5, 8, 4, 1, OL);   // a asa
            // a cabeça, a crista, o bico e a barbela
            R(9, 2, 6, 6, OL); R(10, 3, 4, 4, '#ffffff');
            R(10, 1, 4, 2, OL); R(10, 1, 3, 1, '#e8434a'); R(11, 0, 2, 1, '#e8434a');
            R(14, 4, 2, 2, OL); R(14, 4, 2, 1, '#fdbe53'); R(13, 6, 2, 2, '#e8434a');
            R(12, 4, 1, 1, OL);
        } else if (tipo === 'pato') {
            pernas([6, 9], 12, 2, '#e38628', '#e38628');
            oval(7, 9, 6, 3, '#ffffff', '#e4e8ee', null);
            R(1, 7, 3, 2, OL); R(1, 6, 2, 1, OL); R(2, 7, 2, 1, '#ffffff');   // o rabinho
            R(4, 8, 6, 2, '#d8dee6'); R(4, 8, 6, 1, OL);   // a asa
            R(10, 3, 5, 6, OL); R(11, 4, 3, 4, '#ffffff'); R(11, 4, 3, 1, '#ffffff');
            R(14, 6, 2, 2, OL); R(14, 6, 2, 1, '#fdbe53'); R(15, 7, 1, 1, '#e38628');   // o bico achatado
            R(13, 5, 1, 1, OL);
        } else if (tipo === 'coelho') {
            pernas([5, 9], 12, 2, '#b4a490', '#8a7a68');
            oval(7, 9, 5, 4, '#c8b8a0', '#a8987e', '#e0d4c0');
            R(1, 8, 3, 3, OL); R(2, 8, 2, 2, '#ffffff');   // o rabo de algodão
            R(9, 5, 6, 6, OL); R(10, 6, 4, 4, '#c8b8a0'); R(10, 6, 4, 1, '#e0d4c0');
            R(10, 0, 3, 6, OL); R(11, 1, 1, 4, '#f5a3b0'); R(12, 1, 3, 5, OL); R(13, 1, 1, 4, '#c8b8a0');   // as orelhas compridas
            R(12, 7, 1, 1, OL); R(14, 8, 1, 1, '#d27688');
        }
        cacheBicho.set(chave, cv);
        return cv;
    }

    /* ---- fase 107: o fazendeiro e a fazendeira redesenhados (16 x 16, com sombra). Usam as mesmas cores de
       base que a troca de cor procura (mais um tom escuro em cada região), então o editor continua valendo. ---- */
    const PAL_AVATAR = {
        o: '#3f2631', H: '#cf8254', h: '#fec99c', j: '#a35f3a', S: '#f7c282', s: '#e19a65', e: '#262b44', E: '#ffffff',
        C: '#f28462', c: '#c0563e', L: '#f8a88a', M: '#52607c', m: '#3a4558', N: '#8c9cb5', B: '#5a3a28', b: '#7a5038', y: '#ffd75e',
        K: '#763b36', k: '#bd6c4a', q: '#4e2420', V: '#9b4ca3', v: '#d176d0', w: '#6b2f74', F: '#f5a3b0', f: '#e8434a', g: '#4e974c'
    };
    const AVATAR_NOVO = {
        fazendeiro: [
            '......oooo......',
            '.....ohhHHo.....',
            '....ohhHHHjo....',
            '....ojjjjjjo....',
            '..oohhHHHHHjjoo.',
            '..ooooooooooooo.',
            '....osSSSSso....',
            '....oSeSSeSo....',
            '....osSssSso....',
            '...ooCyMMyCoo...',
            '..oCCLMNNMLCco..',
            '..oSCcMNNMcCSo..',
            '..oooMMMMMMooo..',
            '....oMmooMmo....',
            '....obBoobBo....',
            '....ooooooooo...'],
        fazendeira: [
            '.....ooooo......',
            '....oKkkKKo.....',
            '...oKkKKKKKo....',
            '...oKKoooKKo....',
            '..oKKoFfFoKKo...',
            '..oKoSSSSSoKo...',
            '..oKoSeSeSoKo...',
            '..oKosSSSsoKo...',
            '..oKKoSSSoKKqo..',
            '..oqKoVVVoKqo...',
            '..ooVvVVVVvoo...',
            '..oSVwVvVVwSo...',
            '...ooVVVVVVoo...',
            '....oVwVVwVo....',
            '....oSSooSSo....',
            '....obBoobBo....']
    };
    // as regiões com o tom escuro novo (0) de cada uma
    const ESCUROS_AVATAR = { chapeu: { '#a35f3a': 0 }, roupa: { '#c0563e': 0, '#f8a88a': 2, '#6b2f74': 0 }, calca: { '#3a4558': 0 }, cabelo: { '#4e2420': 0 } };
    const cacheAvatar = new Map();
    function avatarCanvas(cfg) {
        cfg = normalizarAvatar(cfg);
        const tipo = AVATAR_TIPOS[cfg.tipo], img = atlas[tipo.p];
        const chave = JSON.stringify([cfg.tipo, cfg.pele, cfg.cabelo, cfg.roupa, cfg.calca, cfg.chapeu]);
        if (cacheAvatar.has(chave)) return cacheAvatar.get(chave);
        const cv = document.createElement('canvas');
        cv.width = cv.height = 16;
        const g = cv.getContext('2d');
        const novo = AVATAR_NOVO[cfg.tipo === 'fazendeiro_ouro' ? 'fazendeiro' : cfg.tipo];   // fase 107: o desenho novo
        if (novo) novo.forEach((linha, y) => [...linha].forEach((ch, x) => { if (PAL_AVATAR[ch]) { g.fillStyle = PAL_AVATAR[ch]; g.fillRect(x, y, 1, 1); } }));
        else {
            if (!img.complete || !img.naturalWidth) { cv.url = cv.toDataURL(); return cv; }   // a arte ainda não carregou
            g.drawImage(img, (tipo.i % COLS) * T, Math.floor(tipo.i / COLS) * T, T, T, 0, 0, T, T);
        }
        const dados = g.getImageData(0, 0, T, T), d = dados.data;
        for (const [regiao, r] of Object.entries(tipo.regioes)) {
            const n = cfg[regiao] | 0;
            const tons = n > 0 ? AVATAR_CORES[regiao][n - 1] : tipo.base && tipo.base[regiao];   // fase 69: a cor de base do exclusivo
            if (!tons) continue;
            const cores = novo ? { ...r.cores, ...(ESCUROS_AVATAR[regiao] || {}) } : r.cores;   // fase 107: e o tom escuro
            const alvo = Object.fromEntries(Object.entries(cores).map(([hex, tom]) => [hex.slice(1), rgbDe(tons[tom])]));
            for (let y = novo ? 0 : r.y[0]; y < (novo ? T : r.y[1]); y++) {
                for (let x = r.x && !novo ? r.x[0] : 0; x < (r.x && !novo ? r.x[1] : T); x++) {
                    const k = (y * T + x) * 4;
                    if (d[k + 3] < 128) continue;
                    const novo = alvo[((d[k] << 16) | (d[k + 1] << 8) | d[k + 2]).toString(16).padStart(6, '0')];
                    if (novo) { d[k] = novo[0]; d[k + 1] = novo[1]; d[k + 2] = novo[2]; }
                }
            }
        }
        g.putImageData(dados, 0, 0);
        cv.url = cv.toDataURL();
        cacheAvatar.set(chave, cv);
        return cv;
    }
    function htmlAvatar(cfg, px = 32) {
        return `<span class="px-spr" style="background-image:url('${avatarCanvas(cfg).url}');width:${px}px;height:${px}px;background-size:${px}px ${px}px;background-position:0 0" aria-hidden="true"></span>`;
    }
    // a cor original de uma região (para a bolinha da opção 0 no editor)
    function corOriginal(tipo, regiao) {
        const r = (AVATAR_TIPOS[tipo] || {}).regioes && AVATAR_TIPOS[tipo].regioes[regiao];
        if (!r) return null;
        if (AVATAR_TIPOS[tipo].base && AVATAR_TIPOS[tipo].base[regiao]) return AVATAR_TIPOS[tipo].base[regiao][1];   // fase 69
        const [hex] = Object.entries(r.cores).sort((a, b) => Math.abs(a[1] - 1) - Math.abs(b[1] - 1))[0];
        return hex;
    }

    // ajudantes: quem é (pessoa) e o que carrega (ferramenta) — tudo dos pacotes. Fase 66: as moças são
    // a de cabelo comprido (a mesma da fazendeira do avatar), não mais a de cabelo curto. Fase 68: cada
    // moça com cabelo, pele e roupa dela (as cores do avatar) e um acessório por cima (ACESSORIOS)
    const MOCA = { p: 'dungeon', i: 99 }, MOCO = { p: 'factory', i: 120 };
    const AJUDANTE_ARTE = {
        granjeira: { ...MOCA, ferramenta: 125, visual: { cabelo: 5, pele: 2, roupa: 4, extra: 'chapeu_palha' } }, lavrador: { ...MOCO, ferramenta: 86 },
        jardineiro: { ...MOCO, ferramenta: 84 }, coelheira: { ...MOCA, ferramenta: 8, visual: { cabelo: 3, pele: 1, roupa: 1, extra: 'lenco' } },
        vaqueiro: { ...MOCO, ferramenta: 123 }, colhedor: { ...MOCO, ferramenta: 88 },
        semeadora: { ...MOCA, ferramenta: 10, visual: { cabelo: 4, pele: 1, roupa: 3, extra: 'avental' } }, patinheiro: { ...MOCO, ferramenta: 1003 },
        pastora: { ...MOCA, ferramenta: 74, visual: { cabelo: 2, pele: 4, roupa: 6, extra: 'lenco_cabeca' } }, porqueiro: { ...MOCO, ferramenta: 79 },
        // fase 43: a operária leva uma caixa e o eletricista uma engrenagem (do pacote da fábrica)
        operaria: { ...MOCA, ferramenta: 73, ferramentaP: 'factory', visual: { cabelo: 0, pele: 3, roupa: 2, extra: 'capacete' } }, eletricista: { ...MOCO, ferramenta: 1120 },   // o alicate
        // fase 74: a cabreira com o leite de cabra e o bufaleiro com o de búfala
        cabreira: { ...MOCA, ferramenta: 1148, visual: { cabelo: 1, pele: 2, roupa: 5, extra: 'lenco' } }, bufaleiro: { ...MOCO, ferramenta: 1149 }
    };
    // fase 68: os acessórios das moças (16 x 16, por cima do desenho, com as letras da PAL_PROPRIA)
    const ACESSORIOS = {
        chapeu_palha: ['................', '.....aaaaaa.....', '....axxxxxwa....', '....axxxxxwa....', '...abbbbbbbba...', 'aaaaxxxxxxxxaaaa', 'axxxxxxxxxxxxwwa', '.aaaaaaaaaaaaaa.'],
        lenco: ['................', '.....aaaaaa.....', '...aaPdPPdPaa...', '..aPPPPdPPPPPa..', '..aPdPPPPPdPPaa.', '..aaPPPPPPPPamPa', '...aaaaaaaaaaPma', '.............aa.'],
        capacete: ['................', '.....aaaaaa.....', '....aGGGdGGa....', '...aGGGGGdGGa...', '...agGGGGGGga...', '.aaaaaaaaaaaaaa.', '.aHHHHHHHHHHHHa.', '..aaaaaaaaaaaa..'],
        lenco_cabeca: ['................', '....aaaaaaaa....', '...aTTTTTTTTa...', '..aTTTTTTTTTTa..', '..aSTTTTTTTTSa..', '..aaSSSSSSSSaa..'],
        avental: ['', '', '', '', '', '', '', '', '', '', '', '', '......addda.....', '.....addddfa.....', '.....adddfda.....', '.....aaaaaaa.....']
    };
    const cacheAjudante = new Map();
    function ajudanteCanvas(tipo) {
        const v = (AJUDANTE_ARTE[tipo] || {}).visual;
        if (!v) return null;
        if (cacheAjudante.has(tipo)) return cacheAjudante.get(tipo);
        const base = avatarCanvas({ tipo: 'fazendeira', cabelo: v.cabelo, pele: v.pele, roupa: v.roupa });
        if (!atlas.dungeon.complete || !atlas.dungeon.naturalWidth) return base;   // a arte ainda não carregou
        const cv = document.createElement('canvas');
        cv.width = cv.height = T;
        const g = cv.getContext('2d');
        g.drawImage(base, 0, 0);
        (ACESSORIOS[v.extra] || []).forEach((linha, y) => [...linha].forEach((ch, x) => {
            if (PAL_PROPRIA[ch]) { g.fillStyle = PAL_PROPRIA[ch]; g.fillRect(x, y, 1, 1); }
        }));
        cv.url = cv.toDataURL();
        cacheAjudante.set(tipo, cv);
        return cv;
    }
    function htmlAjudante(tipo, px = 32) {
        const c = ajudanteCanvas(tipo);
        return c ? `<span class="px-spr" style="background-image:url('${c.url || c.toDataURL()}');width:${px}px;height:${px}px;background-size:${px}px ${px}px;background-position:0 0" aria-hidden="true"></span>` : null;
    }

    let quadroHelice = 0;   // a turbina eólica gira (troca a cada poucos quadros)

    /* ---------- Cercados dos bichos (Construir → Bichos) ----------
       Cada espécie pode ter o seu: cerca em volta (porteira aberta no meio de baixo) e o chão
       do bicho (terra, grama com cocho, laguinho, lama). Os bichos daquela espécie moram dentro. */
    const CERCADOS = {
        cercado_galinha: { bicho: 'galinha', w: 6, h: 4, chao: 'terra' },
        cercado_coelho: { bicho: 'coelho', w: 6, h: 4, chao: 'feno' },
        cercado_pato: { bicho: 'pato', w: 6, h: 4, chao: 'lago' },
        cercado_vaca: { bicho: 'vaca', w: 7, h: 5, chao: 'cocho' },
        cercado_ovelha: { bicho: 'ovelha', w: 7, h: 5, chao: 'cocho' },
        cercado_porco: { bicho: 'porco', w: 6, h: 4, chao: 'lama' },
        cercado_cabra: { bicho: 'cabra', w: 6, h: 4, chao: 'feno' },     // fase 74
        cercado_bufala: { bicho: 'bufala', w: 7, h: 5, chao: 'lama' }
    };
    function gradeCercado(id) {
        const k = CERCADOS[id];
        const ehCerca = (x, y) => x >= 0 && y >= 0 && x < k.w && y < k.h && (x === 0 || y === 0 || x === k.w - 1 || y === k.h - 1)
            && !(y === k.h - 1 && x === Math.floor(k.w / 2));
        return Array.from({ length: k.h }, (_, y) => Array.from({ length: k.w }, (_, x) =>
            ehCerca(x, y) ? tileCerca(ehCerca(x, y - 1), ehCerca(x, y + 1), ehCerca(x - 1, y), ehCerca(x + 1, y)) : null));
    }

    /* ---------- Arte dos itens construíveis ----------
       p = pacote, i = tile, topo = tile de cima (árvores altas), topo2 = mais um em cima, auto = encaixe automático */
    function arteItem(id, est) {
        const inv = est === 'inverno';
        if (OFICINA_PRODUTO[id]) return { p: 'casas', w: 2, h: 3, grade: gradeCasa(id, 2, 3) };   // fase 105: as oficinas desenhadas
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
            case 'laranjeira': case 'limoeiro': case 'goiabeira': case 'mangueira':
            case 'abacateiro': case 'cacaueiro': case 'jabuticabeira':
            case 'coqueiro': case 'cajueiro': case 'acaizeiro': case 'cupuacuzeiro': case 'castanheira':   // fase 73
            case 'ipe':   // fase 104
                return { p: 'pomar', i: 2 * POMAR[id].n + 1, topo: 2 * POMAR[id].n };
            // fase 73: a praia (só na areia)
            case 'cadeira_praia': return { p: 'farm', i: 1140 };
            case 'guarda_sol': return { p: 'farm', i: 1139 };
            case 'coqueiro_praia': return { p: 'farm', i: 1000 + PRAIA.coqueiro.i, topo: 1000 + PRAIA.coqueiro.topo };
            case 'castelo_areia': return { p: 'farm', i: 1141 };
            case 'barraca_coco': return { p: 'farm', i: 1142 };
            case 'barraca_milho': return { p: 'farm', i: 1154 };   // fase 97
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
            case 'lampiao': return { p: 'farm', i: 1049 };
            case 'barraca': return { p: 'farm', i: 1064 };
            case 'casa_vermelha': return { p: 'casas', w: 3, h: 3, grade: gradeCasa('casa_vermelha', 3, 3) };   // fase 105
            case 'casa_azul': return { p: 'casas', w: 3, h: 3, grade: gradeCasa('casa_azul', 3, 3) };
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
            // fase 38: telhado vermelho/azul com parede de madeira ou de pedra; defumadouro e adega de pedra
            case 'conservas': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [88, 89]] };
            case 'prensa_oleo': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [84, 85]] };
            case 'doceria': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [90, 91]] };
            case 'peixaria': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [85, 75]] };
            case 'casa_sucos': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [84, 85]] };
            case 'sorveteria': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [84, 87]] };
            case 'defumadouro': return { p: 'town', w: 2, h: 3, grade: [[99, 102], [111, 114], [125, 126]] };
            case 'atelie': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [89, 79]] };
            case 'cozinha_moqueca': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [88, 89]] };
            case 'emporio': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [85, 87]] };
            case 'vitaminas': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [90, 79]] };
            case 'guacamolaria': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [86, 75]] };
            case 'chocolateria': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [86, 87]] };
            case 'adega': return { p: 'town', w: 2, h: 3, grade: [[99, 102], [111, 114], [123, 124]] };
            // fase 58: oficinas do 21 ao 30 (engenho e vinícola de pedra, como a adega)
            case 'engenho': return { p: 'town', w: 2, h: 3, grade: [[99, 102], [111, 114], [125, 124]] };
            case 'torrefacao': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [86, 79]] };
            case 'fiacao': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [85, 87]] };
            case 'cafeteria': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [90, 87]] };
            case 'alfaiataria': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [89, 87]] };
            case 'vinicola': return { p: 'town', w: 2, h: 3, grade: [[99, 102], [111, 114], [126, 123]] };
            case 'pimentaria': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [88, 87]] };
            case 'bombonaria': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [86, 91]] };
            // fase 73: as oficinas das frutas do 31 ao 45
            case 'doceria_coco': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [84, 91]] };
            case 'cajuinaria': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [86, 79]] };
            case 'acaiteria': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [89, 91]] };
            case 'cremeria': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [84, 91]] };
            case 'pacocaria': return { p: 'town', w: 2, h: 3, grade: [[99, 102], [111, 114], [124, 125]] };
            // fase 74: as oficinas dos peixes do mar e a da búfala
            case 'enlatados': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [88, 87]] };
            case 'sushiteria': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [89, 87]] };
            case 'caldeiraria': return { p: 'town', w: 2, h: 3, grade: [[99, 102], [111, 114], [126, 124]] };
            case 'queijaria_bufala': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [90, 79]] };
            // fase 104: as oficinas do barco
            case 'serraria_naval': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [124, 75]] };
            case 'forja': return { p: 'town', w: 2, h: 3, grade: [[99, 102], [111, 114], [123, 126]] };
            case 'velaria': return { p: 'town', w: 2, h: 3, grade: [[48, 51], [60, 63], [91, 75]] };
            case 'cartografia': return { p: 'town', w: 2, h: 3, grade: [[52, 55], [64, 67], [87, 79]] };
            // máquinas (Tiny Factory)
            case 'cercado_galinha': case 'cercado_coelho': case 'cercado_pato': case 'cercado_cabra': case 'cercado_bufala':
            case 'cercado_vaca': case 'cercado_ovelha': case 'cercado_porco':
                return { p: 'town', w: CERCADOS[id].w, h: CERCADOS[id].h, grade: gradeCercado(id), cercado: CERCADOS[id] };
            case 'cano': return { p: 'farm', i: 1048, cano: true };
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
            case 'hidreletrica': return { p: 'factory', i: 112 };   // fase 78: a pequena central (a roda gira em desenharMaquinas)
            case 'triturador': return { p: 'factory', i: 101 };
            case 'supercap': return { p: 'factory', i: 86 };
            case 'fabrica_auto': return { p: 'factory', w: 2, h: 2, grade: [[76, 77], [88, 89]] };
            case 'robo_colheita': return { p: 'factory', i: 108 };
            case 'aspersor': return { p: 'factory', i: 94 };
            case 'reator': return { p: 'farm', w: 2, h: 2, grade: [[1026, 1027], [1028, 1029]] };
            case 'estatua_chico': return { p: 'farm', i: 1038, topo: 1037, topo2: 1039 };
            default: return { p: 'farm', i: 89, desconhecido: true };   // (fase 59: o jogo vê que falta arte)
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
        // lua: noite no jogo (meia-lua prateada com brilho, sombra azulada, crateras e uma estrelinha)
        lua: ['....oooo.y..', '..oowSo.yyy.', '.owsso...y..', '.ossSo......', 'owssSo......', 'owssSo....y.', 'osssSo......', 'osSsso......', 'ossssSo.....', '.ossssSo....', '.ossSssSoo..', '..oossssSoo.', '....ooooo...'],
        // sino: histórico de avisos
        // chat: balão de fala com reticências (fase 67)
        chat: ['..ooooooo..', '.owwwwwwwo.', 'owwwwwwwwso', 'owBwwBwwBso', 'owwwwwwwwso', '.owwwwwwso.', '..oowooooo.', '...owo.....', '...oo......'],
        // calendário de resgate diário (fase 69): folhinha com a argola, a faixa vermelha e o dia marcado
        calendario: ['.o.o.o.o.', 'ooooooooo', 'orrrrrrro', 'ooooooooo', 'owwwwwwwo', 'owSwSwSwo', 'owwwwwwwo', 'owSwSwrwo', 'owwwwwwwo', 'ooooooooo'],
        radio: ['........o..', '.......o...', 'ooooooooooo', 'orrrrrrrrro', 'owwoyyyowwo', 'owSwoyowSwo', 'owwoyyyowwo', 'orrrrrrrrro', 'ooooooooooo'],   // fase 107: o rádio da feira
        engrenagem: ['...ooo...', '.oosSsoo.', '.osSSSso.', 'osSSoSSso', 'oSSo.oSSo', 'osSSoSSso', '.osSSSso.', '.oosSsoo.', '...ooo...'],   // fase 105: a tela das oficinas
        gerente: ['ooooooooo', 'ogggogggo', 'ogGgogGgo', 'ooooooooo', 'oyyyogggo', 'oyYyogGgo', 'ooooooooo', 'onnnoyyyo', 'onnnoyYyo', 'ooooooooo'],   // fase 103: o modo gerente (a grade dos canteiros)
        sino: ['....o....', '...oyo...', '..oyyyo..', '..owyyo..', '..owyyo..', '.oyyyyyo.', 'oyyyyyyYo', 'ooooooooo', '...oYo...', '....o....'],
        // diamante: a moeda especial (colher na hora)
        diamante: ['..ooooo..', '.owwbbBo.', 'owbbbbbBo', 'oBbBbBbBo', '.obbbbBo.', '..obbBo..', '...oBo...', '....o....'],
        ajuda: ['.ooooooo.', 'owwwwwwwo', 'owwooowwo', 'owowwwowo', 'owwwwowwo', 'owwwowwwo', 'owwwwwwwo', 'owwwowwwo', '.oooooooo', '.....oo..'],
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
        // ventania: a nuvem com rajadas azuis saindo pela esquerda; a de baixo enrola na ponta
        vento: ['.........ooo....', '........owwwo...', 'BBB...oowwwwwoo.', '.....owwwwwwwwso', '.BBBBowwwwwwwsso', '......ossssssso.', '.......ooooooo..', '................', 'BB.BBBBBBBBB....', '............B...', '.........B..B...', '..........BB....'],
        // fase 77: a tempestade (nuvem escura com raio) e o furacão (o funil girando)
        tempestade: ['....ooo....', '...oSSSo...', '.ooSSSSSoo.', 'oSSSSSSSSSo', 'oSSSSSSSSSo', '.oooyyoooo.', '..b.yy..b..', '...yy......', '..yyyyy.b..', '....yy.....', '...yy......', '..y........'],
        furacao: ['ooooooooooo', 'oSSSSSSSSSo', '.ooooooooo.', '.osssssSSo.', '..ooooooo..', '..oSSSSSo..', '...ooooo...', '...osSSo...', '....ooo....', '....oSo....', '.....o.....'],
        play: ['oo.....', 'owoo...', 'owwwoo.', 'owwwwwo', 'owwwoo.', 'owoo...', 'oo.....'],
        raio: ['...oooo', '..oyyyo', '..oyyo.', '.oyyo..', '.oyyyyo', 'oyyyyo.', 'ooyyo..', '..oyo..', '.oyo...', '.oo....'],
        coracao: ['.oo.oo.', 'orrorRo', 'orwrrRo', 'orrrrRo', '.orrRo.', '..oRo..', '...o...'],
        missao: ['ooooooo.', 'okkkkkko', 'okoooko.', 'okkkkkko', 'okoooko.', 'okkkkkko', 'okooko..', 'okkkkko.', 'oooooo..'],
        mover: ['....o....', '...oko...', '..okkko..', '....o....', 'oko.o.oko', 'okkoooko.', 'oko.o.oko', '....o....', '..okkko..', '...oko...', '....o....'],
        lixeira: ['..ooooo..', 'ooooooooo', 'okkkkkkko', '.okokoko.', '.okokoko.', '.okokoko.', '.okokoko.', '.okkkkko.', '..ooooo..'],
        medalha: ['.oo...oo.', '.obo.obo.', '..obobo..', '...ooo...', '..oyyyo..', '.oywyyYo.', '.oyyyyYo.', '.oyyyYYo.', '..oYYYo..', '...ooo...'],
        // escudo: painel de admin
        escudo: ['.ooooooo.', 'oBBbbbBBo', 'oBbwbbbBo', 'oBbbbbbBo', 'oBbbbbbBo', '.oBbbbBo.', '.oBbbbBo.', '..oBbBo..', '...oBo...', '....o....'],
        medalha_off: ['.oo...oo.', '.oSo.oSo.', '..oSoSo..', '...ooo...', '..ossso..', '.ossssSo.', '.ossssSo.', '.osssSSo.', '..oSSSo..', '...ooo...'],
        som: ['....o....', '...oo.o..', 'oooko..o.', 'okkko.o.o', 'okkko.o.o', 'okkko.o.o', 'oooko..o.', '...oo.o..', '....o....'],
        mudo: ['....o....', '...oo....', 'oooko.o.o', 'okkko..o.', 'okkko.o.o', 'okkko....', 'oooko....', '...oo....', '....o....'],
        // fase 98: os ícones das telas novas (a invasão, os itens, os funcionários, o depósito e as armas)
        et: ['..o.o.o..', '.odododo.', 'odddddddo', 'orrdddrro', 'orwrdrwro', 'odrrdrrdo', '.odddddo.', '..odndo..', '...ooo...'],
        mochila: ['...ooo...', '..o...o..', '.ooooooo.', 'otttttddo', 'otttttddo', 'ooooooooo', 'otyyyttdo', 'otyoyttdo', 'otttttddo', '.ooooooo.'],
        funcionario: ['...ooo...', '..oyyyo..', '.oyyyyyo.', 'ooooooooo', '.okkkkko.', '.okokoko.', '.okkkkko.', '..ooooo..', '.oBBBBBo.', 'oBBBBBBBo'],
        caixa: ['ooooooooo', 'ottttttto', 'odtdtdtdo', 'ooooooooo', 'ottttttto', 'odtdtdtdo', 'ottttttto', 'ooooooooo'],
        forcado: ['.y.......y.', 'oso.oso.oso', 'oso.oso.oso', 'oso.oso.oso', 'ossssssssso', '.oooosoooo.', '....oto....', '....oto....', '....odo....', '....odo....', '....ooo....'],
        espantalho: ['...ooooo...', '..oyyyyyo..', 'ooooooooooo', '..ossssso..', '..osrsrso..', '..ossssso..', 'ooooooooooo', 'ottttttttto', 'ooooBBBoooo', '...oBBBo...', '...oBoBo...', '...oo.oo...'],
        trator: ['..oooo.......', '..obbo..ooooo', 'ooooooooSSSSo', 'orrrrrroooooo', 'orrrrrrrrro..', 'ooooooooooo..', 'oSSSo...oSo..', 'oSoSo...ooo..', 'oSSSo........', '.ooo.........'],
        drone: ['SSS.....SSS', '.o.......o.', 'ooooooooooo', '..ossssso..', '..osbrbso..', '...ooooo...', '....oSo....', '...g.g.g...', '..g..g..g..']
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

    const ARQUIVOS = { farm: 'tiny-farm.png', town: 'tiny-town.png', ski: 'tiny-ski.png', factory: 'tiny-factory.png', dungeon: 'tiny-dungeon.png' };
    const VERSAO_ARTE = '2';   // troque se as imagens dos pacotes mudarem (cache de 4 h do Cloudflare)
    function htmlTile(i, px = 32, pacote = 'farm') {
        if (i >= 1000) { i -= 1000; pacote = 'propria'; }
        const c = i % COLS, l = Math.floor(i / COLS);
        if (pacote === 'propria' && !urlPropria) urlPropria = atlasProprio.toDataURL();
        if (pacote === 'pomar' && !urlPomar && atlas.pomar) urlPomar = atlas.pomar.toDataURL();
        if (pacote === 'casas' && !urlCasas && atlas.casas) urlCasas = atlas.casas.toDataURL();   // fase 105
        const img = pacote === 'farm' ? '' : pacote === 'propria' ? `background-image:url('${urlPropria}');`
            : pacote === 'pomar' ? `background-image:url('${urlPomar}');`
            : pacote === 'casas' ? `background-image:url('${urlCasas}');`
            : `background-image:url('assets/fazenda/${ARQUIVOS[pacote]}');`;
        return `<span class="px-spr" style="${img}width:${px}px;height:${px}px;background-size:${COLS * px}px ${(pacote === 'propria' ? LINHAS_PROPRIA : pacote === 'casas' ? LINHAS_CASAS : LINHAS) * px}px;background-position:-${c * px}px -${l * px}px" aria-hidden="true"></span>`;
    }

    // Ícone de item para a UI (árvores altas mostram as duas peças)
    function htmlItem(id, px = 32) {
        const a = arteItem(id, estacao());
        if (a.grade) {
            const m = Math.round(px / a.w);
            return `<span class="px-grade" style="width:${m * a.w}px;height:${m * a.h}px;grid-template-columns:repeat(${a.w},${m}px)">${a.grade.flat().map((i) => (i == null ? `<span style="width:${m}px;height:${m}px"></span>` : htmlTile(i, m, a.p))).join('')}</span>`;
        }
        const i = a.auto === 'cerca' ? 45 : a.auto === 'terra' ? 25 : a.i;
        if (a.topo == null) return htmlTile(i, px, a.p);
        const pecas = a.topo2 != null ? 3 : 2, m = Math.round(px / pecas);
        return `<span class="px-alto" style="width:${m}px;height:${m * pecas}px">${a.topo2 != null ? htmlTile(a.topo2, m, a.p) : ''}${htmlTile(a.topo, m, a.p)}${htmlTile(i, m, a.p)}</span>`;
    }

    /* ---------- Atlas ---------- */
    const atlas = { farm: new Image(), town: new Image(), ski: new Image(), factory: new Image(), dungeon: new Image() };
    /* ---- pomar: cada árvore frutífera é a árvore redonda do Tiny Town (copa 4 + tronco 16) com as
       frutas pintadas em cima da copa (ou no tronco: cacau, jabuticaba). Peças 2k (copa) e 2k+1 (tronco). */
    const POMAR = {
        laranjeira: { n: 0, cores: ['#e38628', '#fdbe53'], onde: 'copa' },
        limoeiro: { n: 1, cores: ['#d9c22e', '#fff27a'], onde: 'copa' },
        goiabeira: { n: 2, cores: ['#c9d65a', '#f5a3b0'], onde: 'copa' },
        mangueira: { n: 3, cores: ['#d9452f', '#fdbe53'], onde: 'copa' },
        abacateiro: { n: 4, cores: ['#1e2a1a', '#5a7a3a'], onde: 'copa' },
        cacaueiro: { n: 5, cores: ['#c96b28', '#f0a04b'], onde: 'tronco' },
        jabuticabeira: { n: 6, cores: ['#262b44', '#6b2f74'], onde: 'tronco' },
        // fase 73
        coqueiro: { n: 7, cores: ['#8a4a2b', '#b4673a'], onde: 'copa' },
        cajueiro: { n: 8, cores: ['#d9452f', '#fdbe53'], onde: 'copa' },
        acaizeiro: { n: 9, cores: ['#3f2631', '#6b2f74'], onde: 'copa' },
        cupuacuzeiro: { n: 10, cores: ['#8a4a2b', '#c96b28'], onde: 'tronco' },
        castanheira: { n: 11, cores: ['#6e5a48', '#b8955c'], onde: 'copa' },
        ipe: { n: 12, cores: ['#e0a800', '#ffe14d'], onde: 'copa', flores: 14 }   // fase 104: o ipê-amarelo florido
    };
    let urlPomar = null;
    function montarPomar() {
        const c = document.createElement('canvas');
        c.width = 12 * 16; c.height = LINHAS * 16;
        const g = c.getContext('2d');
        const t = document.createElement('canvas');
        t.width = 16; t.height = 32;
        const tg = t.getContext('2d');
        for (const p of Object.values(POMAR)) {
            tg.clearRect(0, 0, 16, 32);
            // tronco curto (no contorno do pacote) e a copa redonda do Tiny Town (o arbusto 5) por cima
            tg.fillStyle = '#3f2631'; tg.fillRect(5, 20, 6, 11);
            tg.fillStyle = '#8a4a2b'; tg.fillRect(6, 20, 4, 10);
            tg.fillStyle = '#b4673a'; tg.fillRect(7, 20, 1, 10);
            tg.fillStyle = '#3f2631'; tg.fillRect(4, 30, 8, 1);
            tg.drawImage(atlas.town, (5 % COLS) * 16, Math.floor(5 / COLS) * 16, 16, 16, 0, 7, 16, 16);
            const d = tg.getImageData(0, 0, 16, 32).data;
            const folha = (x, y) => { const k = (y * 16 + x) * 4; return d[k + 3] > 200 && d[k + 1] > d[k] + 20 && d[k + 1] > d[k + 2]; };
            const tronco = (x, y) => { const k = (y * 16 + x) * 4; return d[k + 3] > 200 && d[k] > d[k + 1] + 20; };
            const r = rng(p.n * 977 + 13);
            let postas = 0;
            const lugares = [];
            for (let tentativa = 0; tentativa < 600 && postas < (p.flores || (p.onde === 'tronco' ? 6 : 7)); tentativa++) {
                const x = 2 + Math.floor(r() * 11), y = (p.onde === 'tronco' ? 16 : 8) + Math.floor(r() * (p.onde === 'tronco' ? 13 : 14));
                const serve = p.onde === 'tronco' ? (tronco(x, y) || folha(x, y)) && (tronco(x + 1, y) || folha(x + 1, y)) : folha(x, y) && folha(x + 1, y + 1) && folha(x, y + 1) && folha(x + 1, y);
                if (!serve || lugares.some(([a, b]) => Math.abs(a - x) < (p.flores ? 2 : 3) && Math.abs(b - y) < (p.flores ? 2 : 3))) continue;
                lugares.push([x, y]);
                postas++;
            }
            for (const [x, y] of lugares) {
                tg.fillStyle = p.cores[0]; tg.fillRect(x, y, 2, 2);
                tg.fillStyle = p.cores[1]; tg.fillRect(x, y, 1, 1);
            }
            g.drawImage(t, 0, 0, 16, 16, ((2 * p.n) % COLS) * 16, Math.floor((2 * p.n) / COLS) * 16, 16, 16);
            g.drawImage(t, 0, 16, 16, 16, ((2 * p.n + 1) % COLS) * 16, Math.floor((2 * p.n + 1) / COLS) * 16, 16, 16);
        }
        atlas.pomar = c;
        urlPomar = null;
    }
    /* ---- fase 105: as casas, o celeiro e as oficinas desenhados aqui, em pixel art com detalhe (no lugar
       das peças do Tiny Town). Ficam num atlas próprio ("casas"), refeito a cada estação (neve no inverno).
       Cada oficina sai com o seu telhado, parede, porta e uma placa com o produto dela. ---- */
    const OFICINA_PRODUTO = {
        saladeira: 'salada', pipocaria: 'pipoca', fabrica_molho: 'molho', queijaria: 'queijo', conservas: 'picles', padaria: 'pao',
        prensa_oleo: 'oleo', confeitaria: 'bolo', doceria: 'doce_abobora', tecelagem: 'tecido', casa_geleia: 'geleia', peixaria: 'peixe_frito',
        casa_sucos: 'suco', sorveteria: 'sorvete', defumadouro: 'peixe_defumado', atelie: 'almofada', cozinha_moqueca: 'moqueca',
        emporio: 'azeite_trufado', engenho: 'acucar', torrefacao: 'cafe_torrado', fiacao: 'fio', cafeteria: 'cappuccino', alfaiataria: 'roupa',
        vinicola: 'vinho', vitaminas: 'vitamina', guacamolaria: 'guacamole', pimentaria: 'molho_picante', chocolateria: 'chocolate',
        adega: 'licor', bombonaria: 'bombom', doceria_coco: 'cocada', serraria_naval: 'tabua_naval', enlatados: 'sardinha_lata',
        cajuinaria: 'cajuina', forja: 'cravo', acaiteria: 'acai_tigela', sushiteria: 'sashimi', velaria: 'vela', queijaria_bufala: 'mussarela',
        cremeria: 'creme_cupuacu', cartografia: 'carta_nautica', caldeiraria: 'caldeirada', pacocaria: 'pacoca'
    };
    const COM_CHAMINE = new Set(['padaria', 'defumadouro', 'engenho', 'torrefacao', 'caldeiraria', 'enlatados', 'peixaria', 'cozinha_moqueca',
        'forja', 'pipocaria', 'confeitaria', 'chocolateria', 'doceria_coco', 'pacocaria', 'fabrica_molho', 'conservas', 'casa_geleia']);
    const DE_PEDRA = new Set(['adega', 'vinicola', 'engenho', 'defumadouro', 'forja', 'caldeiraria', 'pacocaria', 'emporio', 'queijaria']);
    const COM_TOLDO = new Set(['sorveteria', 'casa_sucos', 'vitaminas', 'acaiteria', 'cajuinaria', 'cafeteria', 'saladeira', 'guacamolaria',
        'bombonaria', 'doceria', 'sushiteria', 'cremeria', 'pipocaria']);
    // fase 106: o jeito de cada oficina (o que fica na frente dela)
    const JEITO_OFICINA = {
        padaria: 'forno', confeitaria: 'doce', doceria: 'doce', bombonaria: 'doce', chocolateria: 'doce', doceria_coco: 'doce',
        pacocaria: 'doce', cremeria: 'doce', casa_geleia: 'pote', conservas: 'pote', pimentaria: 'pote', fabrica_molho: 'pote',
        guacamolaria: 'horta', saladeira: 'horta', forja: 'forja', serraria_naval: 'serraria', vinicola: 'adega', adega: 'adega',
        queijaria: 'queijo', queijaria_bufala: 'queijo', peixaria: 'peixe', enlatados: 'peixe', sushiteria: 'peixe', caldeiraria: 'peixe',
        cozinha_moqueca: 'peixe', defumadouro: 'defumado', tecelagem: 'tecido', fiacao: 'tecido', alfaiataria: 'tecido', atelie: 'tecido',
        velaria: 'vela', engenho: 'cana', torrefacao: 'cafe', cafeteria: 'cafe', sorveteria: 'bebida', casa_sucos: 'bebida',
        vitaminas: 'bebida', acaiteria: 'bebida', cajuinaria: 'bebida', prensa_oleo: 'oleo', emporio: 'oleo', pipocaria: 'pipoca',
        cartografia: 'mapa', sushiteria2: 'peixe'
    };
    // os vidros de cada prédio (x, y, w, h a partir do canto dele), para acender à noite; "id:2" é a oficina dupla
    const JANELAS_CASAS = {};
    const LINHAS_CASAS = 30;
    const CASAS_POS = { casa: [0, 0], casa_vermelha: [3, 0], casa_azul: [6, 0], celeiro: [9, 0] };
    Object.keys(OFICINA_PRODUTO).forEach((id, k) => { CASAS_POS[id] = [(k % 6) * 2, 6 + Math.floor(k / 6) * 3]; });
    const gradeCasa = (id, w, h) => { const [c0, r0] = CASAS_POS[id]; return Array.from({ length: h }, (_, r) => Array.from({ length: w }, (_, c) => (r0 + r) * COLS + c0 + c)); };
    const TELHAS = {
        vermelho: ['#c34b35', '#8e2e22', '#e0735a'], azul: ['#3b6fb6', '#25406e', '#6a9be0'], verde: ['#4e8a4c', '#2f5e3a', '#7ab46a'],
        marrom: ['#8a5a32', '#5a3a20', '#b4804e'], ardosia: ['#5d6b80', '#3a4558', '#8b9bb4'], laranja: ['#d97a2b', '#9e4f1a', '#f2a65a'],
        roxo: ['#8a4c9b', '#5a2f6a', '#b47ac4']
    };
    const PAREDES = {
        madeira: ['#c98a4a', '#8a5a2a', '#e0a868'], pedra: ['#a39388', '#6e625a', '#c8bcb0'], reboco: ['#f1e4c8', '#c9b48e', '#fff6e2'],
        tijolo: ['#b8603e', '#7e3a24', '#d88a68'], azulejo: ['#e8eef4', '#9fb4c8', '#ffffff']
    };
    let urlCasas = null;
    function montarCasas(est) {
        const inverno = est === 'inverno', outono = est === 'outono';
        const cv = document.createElement('canvas');
        cv.width = COLS * T; cv.height = LINHAS_CASAS * T;
        let g = cv.getContext('2d');
        const OL = '#3f2631';
        const R = (x, y, w, h, c) => { if (w <= 0 || h <= 0) return; g.fillStyle = c; g.fillRect(Math.round(x), Math.round(y), Math.round(w), Math.round(h)); };
        const icone = (item, x, y, tam = 8) => {   // o ícone do produto (8 px; 16 na placa grande) na placa
            if (item == null) return;
            let i = item, img = atlas.farm;
            if (i >= 1000) { i -= 1000; img = atlasProprio; }
            g.imageSmoothingEnabled = false;
            g.drawImage(img, (i % COLS) * T, Math.floor(i / COLS) * T, T, T, x, y, tam, tam);
        };
        // o prédio que está sendo desenhado (para guardar onde ficam os vidros)
        let atual = null, aox = 0, aoy = 0;
        const marca = (id, ox, oy) => { atual = id; aox = ox; aoy = oy; JANELAS_CASAS[id] = []; };
        // o telhado visto de frente e de cima: fileiras de telhas desencontradas, cumeeira clara e beiral escuro
        function telhado(x, y, w, h, cor, r) {
            const [c, esc, cla] = TELHAS[cor];
            R(x - 1, y - 1, w + 2, h + 2, OL);
            R(x, y, w, h, c);
            for (let yy = y + 2, k = 0; yy < y + h - 1; yy += 3, k++) {
                R(x, yy, w, 1, esc);
                for (let xx = x + (k % 2 ? 2 : 0); xx < x + w; xx += 4) { R(xx, yy - 2, 1, 2, esc); R(xx + 1, yy - 2, 2, 1, cla); }
            }
            R(x, y, w, 1, cla); R(x, y + 1, w, 1, tomCasa(c, 0.15));                 // a cumeeira
            R(x, y + h - 1, w, 1, esc);                                              // o beiral
            if (r) for (let k = 0; k < Math.floor(w * h / 60); k++) R(x + Math.floor(r() * w), y + 3 + Math.floor(r() * (h - 4)), 1, 1, r() < 0.5 ? esc : cla);   // telha gasta
            if (inverno) {   // a neve: grossa em cima, escorrendo nas bordas, com sombra azulada
                R(x - 1, y - 2, w + 2, 4, '#ffffff'); R(x, y + 2, w, 1, '#e4edf6');
                for (let xx = x; xx < x + w; xx++) { const d = ((xx * 7) % 5) === 0 ? 3 : ((xx * 3) % 4 === 0 ? 2 : 0); if (d) R(xx, y + 2, 1, d, '#f4f8fc'); }
                R(x - 1, y + h - 1, w + 2, 1, '#e4edf6');
            } else if (outono && r) for (let k = 0; k < 4; k++) R(x + Math.floor(r() * w), y + 2 + Math.floor(r() * (h - 3)), 2, 1, r() < 0.5 ? '#e38628' : '#c96b28');
        }
        // a parede: tábuas em pé, pedras ou reboco com vigas de madeira
        function parede(x, y, w, h, tipo, r) {
            const [c, esc, cla] = PAREDES[tipo];
            R(x - 1, y, w + 2, h + 1, OL);
            R(x, y, w, h, c);
            if (tipo === 'madeira') {
                for (let xx = x + 3; xx < x + w; xx += 4) R(xx, y, 1, h, esc);
                for (let xx = x; xx < x + w; xx += 4) R(xx, y, 1, h, cla);
                for (let k = 0; k < w / 3; k++) R(x + Math.floor(r() * w), y + Math.floor(r() * h), 1, 1, esc);   // os nós
            } else if (tipo === 'pedra' || tipo === 'tijolo') {
                const alt = tipo === 'pedra' ? 4 : 3;
                for (let yy = y, k = 0; yy < y + h; yy += alt, k++) {
                    R(x, yy + alt - 1, w, 1, esc);
                    for (let xx = x + (k % 2 ? 0 : (tipo === 'pedra' ? 3 : 2)); xx < x + w; xx += (tipo === 'pedra' ? 6 + Math.floor(r() * 3) : 5)) R(xx, yy, 1, alt - 1, esc);
                    R(x, yy, w, 1, tomCasa(c, 0.12));
                }
            } else if (tipo === 'reboco') {
                R(x, y, w, 1, cla);
                R(x, y, 2, h, '#7a4a2a'); R(x + w - 2, y, 2, h, '#7a4a2a'); R(x, y + 1, w, 2, '#7a4a2a');   // as vigas
                for (let k = 0; k < w / 4; k++) R(x + 3 + Math.floor(r() * (w - 6)), y + 4 + Math.floor(r() * (h - 6)), 1, 1, esc);
            } else {
                for (let yy = y + 1; yy < y + h; yy += 4) R(x, yy, w, 1, esc);
                for (let xx = x + 2; xx < x + w; xx += 4) R(xx, y, 1, h, esc);
            }
            R(x, y, w, 2, 'rgba(40,20,30,0.35)');   // a sombra do beiral
        }
        function porta(x, y, w, h, cor) {
            R(x - 1, y - 1, w + 2, h + 1, OL); R(x - 1, y - 2, w + 2, 1, '#e8d8b0');
            R(x, y, w, h, cor); R(x, y, w, 1, tomCasa(cor, 0.25));
            for (let xx = x + 2; xx < x + w - 1; xx += 3) R(xx, y + 1, 1, h - 1, tomCasa(cor, -0.25));
            R(x + w - 3, y + Math.floor(h / 2), 1, 1, '#ffd75e');                       // a maçaneta
            R(x - 2, y + h, w + 4, 2, '#a39388'); R(x - 2, y + h, w + 4, 1, '#c8bcb0');   // o degrau de pedra
        }
        function janela(x, y, w, h, veneziana, flores, r) {
            if (atual) JANELAS_CASAS[atual].push([x - aox, y + 1 - aoy, w, h - 2]);
            R(x - 2, y - 1, w + 4, h + 2, OL);
            R(x - 1, y, w + 2, h, '#f4ecd8');
            R(x, y + 1, w, h - 2, '#3b6fb6'); R(x, y + 1, w, 1, '#9fd3f5'); R(x + 1, y + 2, 1, 2, '#cfeaff');
            R(x + Math.floor(w / 2), y + 1, 1, h - 2, '#f4ecd8'); R(x, y + Math.floor(h / 2), w, 1, '#f4ecd8');
            if (veneziana) for (const vx of [x - 4, x + w + 2]) { R(vx, y, 3, h, OL); R(vx, y, 2, h, veneziana); for (let yy = y + 1; yy < y + h; yy += 2) R(vx, yy, 2, 1, tomCasa(veneziana, -0.3)); }
            if (flores) {   // a floreira com flores (no inverno, só a terra com neve)
                R(x - 2, y + h, w + 4, 3, OL); R(x - 1, y + h, w + 2, 2, '#8a5a2a');
                if (!inverno) for (let xx = x - 1; xx < x + w + 1; xx += 2) { R(xx, y + h - 2, 1, 2, '#4e974c'); R(xx, y + h - 3, 2, 1, ['#e8434a', '#f5a3b0', '#ffe08a', '#d176d0'][Math.floor(r() * 4)]); }
                else R(x - 1, y + h - 1, w + 2, 1, '#ffffff');
            }
        }
        function chamine(x, y, h, tipo) {
            R(x - 1, y - 1, 7, h + 1, OL); R(x, y, 5, h, tipo === 'pedra' ? '#8b7d72' : '#b8603e');
            for (let yy = y + 2; yy < y + h; yy += 3) R(x, yy, 5, 1, tipo === 'pedra' ? '#6e625a' : '#7e3a24');
            R(x - 1, y - 2, 7, 2, OL); R(x, y - 2, 5, 1, '#5a5560');
            if (inverno) R(x - 1, y - 3, 7, 1, '#ffffff');
        }
        function toldo(x, y, w, cor) {   // o toldo listrado em cima da janela
            R(x - 1, y - 1, w + 2, 6, OL);
            for (let xx = x; xx < x + w; xx++) { const lis = Math.floor((xx - x) / 3) % 2 ? '#ffffff' : cor; R(xx, y, 1, 4, lis); }
            for (let xx = x; xx < x + w; xx += 3) R(xx, y + 4, 2, 1, Math.floor((xx - x) / 3) % 2 ? '#ffffff' : cor);
            R(x, y, w, 1, 'rgba(255,255,255,0.45)');
        }
        function barril(x, y) { R(x - 1, y - 1, 8, 9, OL); R(x, y, 6, 7, '#9a5a32'); R(x, y, 2, 7, '#c07a48'); R(x, y + 2, 6, 1, '#5a3a28'); R(x, y + 5, 6, 1, '#5a3a28'); R(x + 1, y, 4, 1, '#d08a48'); if (inverno) R(x, y - 1, 6, 1, '#ffffff'); }
        function caixa(x, y) { R(x - 1, y - 1, 8, 8, OL); R(x, y, 6, 6, '#c98a4a'); R(x, y, 6, 1, '#e0a868'); R(x + 2, y + 1, 1, 5, '#8a5a2a'); R(x, y + 3, 6, 1, '#8a5a2a'); if (inverno) R(x, y - 1, 6, 1, '#ffffff'); }
        function lenha(x, y) { for (let k = 0; k < 3; k++) for (let j = 0; j < 3 - k; j++) { const lx = x + j * 4 + k * 2, ly = y - k * 3; R(lx - 1, ly - 1, 5, 4, OL); R(lx, ly, 3, 2, '#b4673a'); R(lx, ly, 1, 1, '#f2c88a'); } }
        function placa(x, y, item) {   // a placa pendurada com o produto
            R(x + 4, y - 3, 1, 3, '#3f2631'); R(x - 1, y - 4, 13, 1, '#5a3a20');
            R(x - 1, y - 1, 12, 12, OL); R(x, y, 10, 10, '#e0c088'); R(x, y, 10, 1, '#f4dca8'); R(x, y + 9, 10, 1, '#b8955c');
            icone(item, x + 1, y + 1);
        }
        const base = (x, y, w) => { R(x - 1, y, w + 2, 3, OL); R(x, y, w, 2, '#8b7d72'); for (let xx = x + 2; xx < x + w; xx += 5) R(xx, y, 1, 2, '#6e625a'); R(x, y, w, 1, '#a39388'); };

        // ----- a casa da fazenda e as casinhas (3 x 3 = 48 x 48) -----
        function casa(id, tel, par, veneziana, portaCor) {
            const [c0, r0] = CASAS_POS[id], ox = c0 * T, oy = r0 * T, r = rng(id.length * 911 + 7);
            marca(id, ox, oy);
            JANELAS_CASAS[id].push([21, 11, 6, 4]);   // a lucarna
            // a sombra no chão
            R(ox + 4, oy + 44, 42, 3, 'rgba(30,40,20,0.28)');
            parede(ox + 4, oy + 22, 40, 20, par, r);
            chamine(ox + 33, oy + 2, 12, 'tijolo');
            telhado(ox + 2, oy + 6, 44, 17, tel, r);
            // a lucarna (a janelinha do sótão) no telhado
            R(ox + 19, oy + 8, 10, 9, OL); R(ox + 20, oy + 10, 8, 6, '#f4ecd8'); R(ox + 21, oy + 11, 6, 4, '#3b6fb6'); R(ox + 21, oy + 11, 6, 1, '#9fd3f5');
            R(ox + 19, oy + 7, 10, 3, TELHAS[tel][1]); R(ox + 20, oy + 7, 8, 1, TELHAS[tel][2]); if (inverno) R(ox + 19, oy + 6, 10, 2, '#ffffff');
            // a varandinha: telhadinho em cima da porta com dois pilares
            porta(ox + 20, oy + 30, 8, 12, portaCor);
            R(ox + 17, oy + 25, 14, 4, OL); R(ox + 18, oy + 26, 12, 2, TELHAS[tel][0]); R(ox + 18, oy + 26, 12, 1, TELHAS[tel][2]);
            if (inverno) R(ox + 17, oy + 24, 14, 2, '#ffffff');
            R(ox + 18, oy + 29, 1, 13, '#f4ecd8'); R(ox + 29, oy + 29, 1, 13, '#f4ecd8');
            janela(ox + 9, oy + 29, 6, 7, veneziana, true, r);
            janela(ox + 33, oy + 29, 6, 7, veneziana, true, r);
            base(ox + 4, oy + 42, 40);
            R(ox + 21, oy + 43, 6, 2, '#a39388');   // o caminho de pedra até a porta
            // o lampião do lado da porta
            R(ox + 15, oy + 31, 2, 3, OL); R(ox + 15, oy + 31, 1, 2, '#ffe08a');
        }
        casa('casa', 'vermelho', 'reboco', '#4e974c', '#8a4a2b');
        casa('casa_vermelha', 'vermelho', 'madeira', '#f4ecd8', '#5a3a20');
        casa('casa_azul', 'azul', 'pedra', '#3b6fb6', '#25406e');

        // ----- o celeiro (3 x 6 = 48 x 96): o telhado comprido visto de cima e a frente vermelha -----
        {
            const [c0, r0] = CASAS_POS.celeiro, ox = c0 * T, oy = r0 * T, r = rng(5150);
            marca('celeiro', ox, oy);
            const TV = ['#3e7a4c', '#2a5838', '#5f9a5a'];   // o telhado verde de sempre, em tábuas de zinco
            R(ox + 3, oy + 90, 44, 4, 'rgba(30,40,20,0.28)');
            // o telhado, as duas águas (a da esquerda na sombra)
            R(ox + 1, oy + 9, 46, 56, OL);
            R(ox + 2, oy + 10, 22, 54, TV[1]); R(ox + 24, oy + 10, 22, 54, TV[0]);
            for (let xx = ox + 4; xx < ox + 46; xx += 4) R(xx, oy + 10, 1, 54, xx < ox + 24 ? '#234a30' : TV[1]);
            for (let xx = ox + 26; xx < ox + 46; xx += 4) R(xx + 1, oy + 10, 1, 54, TV[2]);
            for (let k = 0; k < 18; k++) R(ox + 3 + Math.floor(r() * 42), oy + 12 + Math.floor(r() * 50), 1, 2, r() < 0.5 ? '#8a5a32' : '#a35a3a');   // ferrugem
            R(ox + 23, oy + 10, 2, 54, '#c9d6c0'); R(ox + 23, oy + 10, 1, 54, '#ffffff');   // a cumeeira
            if (inverno) {
                R(ox + 2, oy + 10, 44, 54, '#eef3f8'); for (let xx = ox + 4; xx < ox + 46; xx += 4) R(xx, oy + 10, 1, 54, '#c9d6e3');
                R(ox + 2, oy + 10, 22, 54, 'rgba(160,180,210,0.35)'); R(ox + 23, oy + 10, 2, 54, '#ffffff');
            }
            // a claraboia/ventilador no meio do telhado, com o cata-vento de galo
            R(ox + 19, oy + 28, 10, 9, OL); R(ox + 20, oy + 29, 8, 7, '#c34b35'); R(ox + 20, oy + 29, 8, 1, '#e0735a');
            for (let xx = ox + 21; xx < ox + 27; xx += 2) R(xx, oy + 31, 1, 4, '#7e2a1f');
            R(ox + 18, oy + 26, 12, 3, OL); R(ox + 19, oy + 26, 10, 2, '#8e2e22'); if (inverno) R(ox + 18, oy + 25, 12, 2, '#ffffff');
            R(ox + 23, oy + 16, 1, 10, '#3f2631');
            R(ox + 20, oy + 13, 7, 4, OL); R(ox + 21, oy + 14, 5, 2, '#2b2b38'); R(ox + 25, oy + 12, 2, 2, '#c34b35'); R(ox + 20, oy + 15, 2, 2, '#2b2b38');   // o galo
            R(ox + 21, oy + 19, 5, 1, '#3f2631'); R(ox + 23, oy + 18, 1, 3, '#3f2631');   // as setas N/S
            // a frente: o oitão vermelho com o acabamento branco
            R(ox + 3, oy + 63, 42, 30, OL);
            R(ox + 4, oy + 64, 40, 28, '#b8382a');
            for (let xx = ox + 6; xx < ox + 44; xx += 4) { R(xx, oy + 64, 1, 28, '#8e2a20'); R(xx - 1, oy + 64, 1, 28, '#d0503e'); }
            R(ox + 4, oy + 64, 40, 2, '#f4f1e6'); R(ox + 4, oy + 64, 2, 28, '#f4f1e6'); R(ox + 42, oy + 64, 2, 28, '#f4f1e6');
            // a porta do palheiro com o feno
            R(ox + 18, oy + 66, 12, 8, OL); R(ox + 19, oy + 67, 10, 6, '#5a2a1a'); R(ox + 19, oy + 67, 10, 1, '#f4f1e6');
            for (let xx = ox + 19; xx < ox + 29; xx++) R(xx, oy + 71 + ((xx * 3) % 3), 1, 2, xx % 2 ? '#f2c94c' : '#d9a83a');
            R(ox + 23, oy + 63, 2, 3, '#3f2631');   // a roldana
            // a porta grande de correr, com o X branco
            const px = ox + 13, py = oy + 76;
            R(px - 1, py - 1, 24, 17, OL);
            for (const [ax, sentido] of [[px, 1], [px + 11, -1]]) {
                R(ax, py, 11, 15, '#9e2e22');
                R(ax, py, 11, 1, '#f4f1e6'); R(ax, py + 14, 11, 1, '#f4f1e6'); R(ax, py, 1, 15, '#f4f1e6'); R(ax + 10, py, 1, 15, '#f4f1e6');
                for (let k = 0; k < 13; k++) { R(ax + 1 + Math.round(k * 9 / 12), py + 1 + k, 1, 1, '#f4f1e6'); R(ax + 9 - Math.round(k * 9 / 12), py + 1 + k, 1, 1, '#f4f1e6'); }
            }
            R(px - 2, py - 3, 26, 2, '#566c86'); R(px - 2, py - 3, 26, 1, '#8b9bb4');   // o trilho
            // a janelinha redonda dos lados, o lampião e o chão de terra batida na frente
            janela(ox + 6, oy + 77, 4, 5, null, false, r); janela(ox + 39, oy + 77, 4, 5, null, false, r);
            R(ox + 11, oy + 76, 2, 3, OL); R(ox + 11, oy + 76, 1, 2, '#ffe08a');
            base(ox + 4, oy + 92, 40);
            barril(ox + 1, oy + 85); lenha(ox + 37, oy + 89);
            if (!inverno) for (let k = 0; k < 5; k++) R(ox + 8 + Math.floor(r() * 32), oy + 94, 2, 1, '#f2c94c');   // feno caído
        }

        // ----- o que fica na frente de cada oficina (o jeito dela). x: a borda do lado livre; dir: para onde cresce -----
        function jeito(tipo, x, y, dir, r, grande) {
            const X = (dx) => (dir > 0 ? x + dx : x - dx);   // dx a partir da borda, para dentro do lado livre
            const W2 = (dx, w) => (dir > 0 ? x + dx : x - dx - w + 1);
            if (tipo === 'forno') {   // o forno de barro com a boca acesa e os pães na tábua
                const fx = W2(0, 12);
                R(fx - 1, y - 9, 14, 11, OL); R(fx, y - 8, 12, 9, '#b8603e'); R(fx + 1, y - 9, 10, 1, '#b8603e'); R(fx + 2, y - 8, 8, 2, '#d88a68');
                R(fx + 4, y - 5, 4, 4, '#3f2631'); R(fx + 5, y - 4, 2, 3, '#ff9a3c'); R(fx + 5, y - 2, 2, 1, '#ffe08a');
                R(W2(1, 8), y + 1, 8, 2, '#8a5a2a'); R(W2(2, 2), y, 2, 1, '#e0a050'); R(W2(5, 2), y, 2, 1, '#e0a050');
            } else if (tipo === 'forja') {   // a bigorna e o fogo da forja
                R(W2(0, 9), y - 3, 9, 3, OL); R(W2(1, 7), y - 3, 7, 2, '#566c86'); R(W2(1, 7), y - 3, 7, 1, '#8b9bb4'); R(W2(3, 3), y, 3, 2, '#3a4558');
                const fx = W2(0, 8);
                R(fx - 1, y - 12, 10, 7, OL); R(fx, y - 11, 8, 5, '#6e625a'); R(fx + 2, y - 10, 4, 3, '#ff5a2a'); R(fx + 3, y - 10, 2, 2, '#ffe08a');
                R(fx + 1, y - 14, 1, 1, '#ffb040'); R(fx + 6, y - 15, 1, 1, '#ffe08a');   // faíscas
            } else if (tipo === 'serraria') {   // as toras empilhadas e a serra redonda
                for (let k = 0; k < 3; k++) { const lx = W2(k * 4, 5), ly = y - 4 - (k === 1 ? 3 : 0); R(lx - 1, ly - 1, 7, 6, OL); R(lx, ly, 5, 4, '#b4673a'); R(lx + 1, ly + 1, 3, 2, '#f2c88a'); R(lx + 2, ly + 1, 1, 1, '#b4673a'); }
                const sx = W2(2, 7), sy = y - 15; R(sx, sy + 1, 7, 5, '#c0cbdc'); R(sx + 1, sy, 5, 7, '#c0cbdc'); R(sx + 2, sy + 2, 3, 3, '#566c86'); R(sx + 3, sy + 3, 1, 1, '#3f2631');
            } else if (tipo === 'adega') {   // os barris deitados e a parreira com uva
                for (const [bx, by] of [[0, 0], [7, 0], [3, -6]]) { const xx = W2(bx, 7), yy = y - 6 + by; R(xx - 1, yy - 1, 9, 8, OL); R(xx, yy, 7, 6, '#8a4a2b'); R(xx + 2, yy, 1, 6, '#5a2a1a'); R(xx + 4, yy, 1, 6, '#5a2a1a'); R(xx + 3, yy + 2, 1, 2, '#c07a48'); }
                for (let k = 0; k < 4; k++) { R(W2(k * 3, 2), y - 17 + (k % 2), 2, 2, '#6b2f74'); R(W2(k * 3 + 1, 1), y - 18, 1, 1, '#4e974c'); }
            } else if (tipo === 'queijo') {   // as rodas de queijo no banquinho
                R(W2(0, 10), y - 1, 10, 3, '#8a5a2a'); R(W2(0, 10), y - 1, 10, 1, '#b4804e');
                for (let k = 0; k < 2; k++) { const cx = W2(1 + k * 5, 5); R(cx - 1, y - 6, 6, 6, OL); R(cx, y - 5, 4, 4, grande && k ? '#f4f1e6' : '#fdd85a'); R(cx, y - 5, 4, 1, '#fff2a8'); }
                const cx = W2(3, 5); R(cx - 1, y - 11, 6, 6, OL); R(cx, y - 10, 4, 4, '#f2c94c'); R(cx + 1, y - 9, 1, 1, '#d9a83a');
            } else if (tipo === 'peixe' || tipo === 'defumado') {   // os peixes pendurados no varal e a rede
                R(W2(0, 11), y - 18, 11, 1, '#5a3a20');
                for (let k = 0; k < 3; k++) { const fx = W2(1 + k * 4, 3); R(fx + 1, y - 17, 1, 2, '#3f2631'); R(fx, y - 15, 3, 5, tipo === 'defumado' ? '#c27838' : '#8bb4d4'); R(fx, y - 15, 1, 5, tipo === 'defumado' ? '#8a4e22' : '#5d8ab0'); R(fx, y - 10, 3, 1, '#3f2631'); }
                for (let yy = 0; yy < 5; yy++) for (let xx = 0; xx < 8; xx++) if ((xx + yy) % 2 === 0) R(W2(xx, 1), y - 4 + yy, 1, 1, 'rgba(233,226,200,0.9)');
            } else if (tipo === 'tecido' || tipo === 'vela') {   // os rolos de pano encostados (ou a vela pendurada)
                if (tipo === 'vela') { const vx = W2(0, 9); R(vx, y - 17, 1, 17, '#5a3a20'); for (let k = 0; k < 12; k++) R(vx + 1, y - 16 + k, Math.max(1, 8 - Math.floor(k / 1.6)), 1, k % 4 === 3 ? '#e4d9bf' : '#f4ecd8'); R(vx + 1, y - 9, 6, 1, '#d9452f'); }
                else for (let k = 0; k < 3; k++) { const rx = W2(k * 4, 4), cor = ['#d9452f', '#3b6fb6', '#fdbe53', '#9b4ca3'][(k + Math.floor(r() * 4)) % 4]; R(rx - 1, y - 12, 5, 13, OL); R(rx, y - 11, 3, 11, cor); R(rx, y - 11, 1, 11, tomCasa(cor, 0.3)); R(rx, y - 11, 3, 1, '#f4ecd8'); }
            } else if (tipo === 'cana') {   // o feixe de cana amarrado
                for (let k = 0; k < 7; k++) { const cx = W2(k, 1); R(cx, y - 14 + (k % 3), 1, 14 - (k % 3), k % 2 ? '#c9d65a' : '#8ab84a'); }
                R(W2(0, 7), y - 7, 7, 1, '#8a5a2a'); R(W2(1, 2), y - 16, 2, 2, '#4e974c'); R(W2(4, 2), y - 17, 2, 2, '#4e974c');
            } else if (tipo === 'cafe') {   // os sacos de café
                for (const [k, dy] of [[0, 0], [6, 0], [3, -5]]) { const sx = W2(k, 6); R(sx - 1, y - 6 + dy, 8, 8, OL); R(sx, y - 5 + dy, 6, 6, '#c9a46a'); R(sx, y - 5 + dy, 6, 1, '#e0c088'); R(sx + 2, y - 3 + dy, 2, 2, '#5a3a20'); R(sx + 2, y - 6 + dy, 2, 1, '#8a6a3a'); }
            } else if (tipo === 'bebida') {   // o engradado de garrafas coloridas
                const cx = W2(0, 10); R(cx - 1, y - 6, 12, 8, OL); R(cx, y - 5, 10, 6, '#c98a4a'); R(cx, y - 3, 10, 1, '#8a5a2a');
                for (let k = 0; k < 4; k++) { R(cx + 1 + k * 2, y - 9, 1, 4, ['#e8434a', '#fdbe53', '#4e974c', '#9b4ca3'][k]); R(cx + 1 + k * 2, y - 10, 1, 1, '#f4f1e6'); }
            } else if (tipo === 'doce') {   // o bolo na vitrine e o docinho na bandeja
                const bx = W2(0, 10); R(bx - 1, y - 9, 12, 11, OL); R(bx, y - 8, 10, 9, '#cfeaff'); R(bx, y - 8, 10, 1, '#ffffff');
                R(bx + 2, y - 4, 6, 4, '#f5a3b0'); R(bx + 2, y - 5, 6, 1, '#ffffff'); R(bx + 4, y - 7, 2, 2, '#e8434a'); R(bx + 1, y, 8, 1, '#c0cbdc');
            } else if (tipo === 'pote') {   // a prateleira de potes com tampa
                const px = W2(0, 11); R(px - 1, y - 1, 13, 3, OL); R(px, y - 1, 11, 2, '#8a5a2a');
                for (let k = 0; k < 3; k++) { const jx = px + k * 4, cor = ['#d9452f', '#fdbe53', '#4e974c'][(k + Math.floor(r() * 3)) % 3]; R(jx - 1 + 1, y - 7, 4, 6, OL); R(jx + 1, y - 6, 2, 5, cor); R(jx + 1, y - 7, 2, 1, '#c0cbdc'); R(jx + 1, y - 5, 1, 1, '#ffffff'); }
            } else if (tipo === 'horta') {   // os cestos com verdura e tomate
                for (let k = 0; k < 2; k++) { const cx = W2(k * 6, 6); R(cx - 1, y - 5, 8, 7, OL); R(cx, y - 4, 6, 5, '#b4804e'); R(cx, y - 2, 6, 1, '#8a5a32'); for (let j = 0; j < 3; j++) R(cx + j * 2, y - 6, 2, 2, k ? '#e8434a' : '#6ab04c'); }
            } else if (tipo === 'oleo') {   // as ânforas de barro
                for (let k = 0; k < 2; k++) { const ax = W2(k * 6, 6); R(ax, y - 10, 6, 1, OL); R(ax + 1, y - 11, 4, 1, OL); R(ax - 1, y - 9, 8, 10, OL); R(ax, y - 9, 6, 9, '#c96b28'); R(ax, y - 9, 2, 9, '#e0904a'); R(ax + 1, y - 6, 4, 1, '#8a4a2b'); }
            } else if (tipo === 'pipoca') {   // o carrinho de pipoca
                const cx = W2(0, 11); R(cx - 1, y - 12, 13, 13, OL); R(cx, y - 11, 11, 7, '#cfeaff'); R(cx + 1, y - 9, 9, 4, '#fff2a8'); R(cx + 2, y - 10, 2, 1, '#ffffff');
                R(cx, y - 4, 11, 4, '#d9452f'); for (let k = 0; k < 11; k += 2) R(cx + k, y - 4, 1, 4, '#ffffff'); R(cx + 2, y, 2, 2, '#3f2631'); R(cx + 7, y, 2, 2, '#3f2631');
            } else if (tipo === 'mapa') {   // o globo e a luneta
                const gx = W2(0, 8); R(gx - 1, y - 10, 10, 10, OL); R(gx, y - 9, 8, 8, '#3b6fb6'); R(gx + 2, y - 8, 3, 3, '#6ab04c'); R(gx + 5, y - 4, 2, 2, '#6ab04c'); R(gx + 3, y - 1, 2, 2, '#8a5a2a');
                R(W2(9, 7), y - 14, 7, 2, '#c9a46a'); R(W2(9, 2), y - 14, 2, 2, '#e8a640');
            }
        }

        // ----- as oficinas (2 x 3 = 32 x 48) -----
        Object.entries(OFICINA_PRODUTO).forEach(([id, produto], k) => {
            const [c0, r0] = CASAS_POS[id], ox = c0 * T, oy = r0 * T, r = rng(k * 7919 + 17);
            marca(id, ox, oy);
            const cores = ['vermelho', 'azul', 'verde', 'marrom', 'ardosia', 'laranja', 'roxo'];
            const tel = DE_PEDRA.has(id) ? (k % 2 ? 'ardosia' : 'marrom') : cores[k % cores.length];
            const par = DE_PEDRA.has(id) ? 'pedra' : ['madeira', 'reboco', 'tijolo', 'madeira', 'azulejo', 'reboco'][k % 6];
            const item = (CULTURAS[produto] || {}).item;
            R(ox + 3, oy + 44, 28, 3, 'rgba(30,40,20,0.28)');
            parede(ox + 3, oy + 22, 26, 20, par, r);
            if (COM_CHAMINE.has(id)) chamine(ox + (k % 2 ? 6 : 21), oy + 3, 12, par === 'pedra' ? 'pedra' : 'tijolo');
            telhado(ox + 1, oy + 7, 30, 16, tel, r);
            const portaEsq = k % 2 === 0;
            porta(ox + (portaEsq ? 6 : 19), oy + 30, 7, 12, ['#8a4a2b', '#5a3a20', '#3b6fb6', '#4e974c', '#9e2e22'][k % 5]);
            const jx = portaEsq ? ox + 19 : ox + 6;
            janela(jx, oy + 28, 7, 7, null, !COM_TOLDO.has(id), r);
            if (COM_TOLDO.has(id)) toldo(jx - 2, oy + 25, 11, ['#d9452f', '#3b6fb6', '#4e974c', '#e38628'][k % 4]);
            placa(ox + (portaEsq ? 16 : 5), oy + 14, item);   // a placa fica no telhado, na frente, bem à vista
            base(ox + 3, oy + 42, 26);
            // o jeito da oficina, no canto livre (do lado da janela), encostado na parede
            jeito(JEITO_OFICINA[id], portaEsq ? ox + 31 : ox + 1, oy + 44, portaEsq ? -1 : 1, r, false);
        });

        // ----- fase 106: a oficina dupla (duas iguais lado a lado viram uma só, 4 x 3 = 64 x 48) -----
        const dup = document.createElement('canvas');
        dup.width = 6 * 64; dup.height = Math.ceil(Object.keys(OFICINA_PRODUTO).length / 6) * 48;
        const gSimples = g;
        g = dup.getContext('2d');
        cv.duplas = dup; cv.posDupla = {};
        Object.entries(OFICINA_PRODUTO).forEach(([id, produto], k) => {
            const ox = (k % 6) * 64, oy = Math.floor(k / 6) * 48, r = rng(k * 104729 + 3);
            cv.posDupla[id] = [ox, oy];
            marca(id + ':2', ox, oy);
            const cores = ['vermelho', 'azul', 'verde', 'marrom', 'ardosia', 'laranja', 'roxo'];
            const tel = DE_PEDRA.has(id) ? (k % 2 ? 'ardosia' : 'marrom') : cores[k % cores.length];
            const par = DE_PEDRA.has(id) ? 'pedra' : ['madeira', 'reboco', 'tijolo', 'madeira', 'azulejo', 'reboco'][k % 6];
            const item = (CULTURAS[produto] || {}).item, jt = JEITO_OFICINA[id];
            R(ox + 3, oy + 44, 60, 3, 'rgba(30,40,20,0.3)');
            parede(ox + 3, oy + 22, 58, 20, par, r);
            // o meio mais alto: o frontão com o relógio (é uma fábrica de verdade agora)
            if (COM_CHAMINE.has(id)) { chamine(ox + 8, oy + 2, 13, par === 'pedra' ? 'pedra' : 'tijolo'); chamine(ox + 51, oy + 2, 13, par === 'pedra' ? 'pedra' : 'tijolo'); }
            telhado(ox + 1, oy + 7, 62, 16, tel, r);
            R(ox + 22, oy + 1, 20, 9, OL); R(ox + 23, oy + 2, 18, 7, TELHAS[tel][0]); R(ox + 23, oy + 2, 18, 1, TELHAS[tel][2]);
            if (inverno) R(ox + 22, oy, 20, 2, '#ffffff');
            // a placa grande com o produto em 16 px
            R(ox + 23, oy + 9, 18, 18, OL); R(ox + 24, oy + 10, 16, 16, '#e0c088'); R(ox + 24, oy + 10, 16, 1, '#f4dca8'); R(ox + 24, oy + 25, 16, 1, '#b8955c');
            R(ox + 22, oy + 9, 1, 2, '#e8a640'); R(ox + 41, oy + 9, 1, 2, '#e8a640');
            icone(item, ox + 24, oy + 10, 16);
            // o portão duplo no meio e as quatro janelas
            const pc = ['#8a4a2b', '#5a3a20', '#3b6fb6', '#4e974c', '#9e2e22'][k % 5];
            porta(ox + 25, oy + 30, 7, 12, pc); porta(ox + 32, oy + 30, 7, 12, pc);
            R(ox + 24, oy + 28, 16, 2, OL); R(ox + 25, oy + 28, 14, 1, '#e8a640');
            for (const jx of [ox + 8, ox + 15, ox + 44, ox + 51]) janela(jx, oy + 28, 5, 7, null, !COM_TOLDO.has(id), r);
            if (COM_TOLDO.has(id)) { toldo(ox + 6, oy + 25, 16, ['#d9452f', '#3b6fb6', '#4e974c', '#e38628'][k % 4]); toldo(ox + 42, oy + 25, 16, ['#d9452f', '#3b6fb6', '#4e974c', '#e38628'][k % 4]); }
            base(ox + 3, oy + 42, 58);
            // os lampiões dos dois lados do portão
            for (const lx of [ox + 22, ox + 41]) { R(lx, oy + 31, 2, 3, OL); R(lx, oy + 31, 1, 2, '#ffe08a'); }
            // o jeito dela dos dois lados
            jeito(jt, ox + 1, oy + 44, 1, r, true);
            jeito(jt, ox + 63, oy + 44, -1, r, true);
        });
        g = gSimples;
        return cv;
    }
    function tomCasa(hex, f) {
        const k = (v) => Math.max(0, Math.min(255, Math.round(f < 0 ? v * (1 + f) : v + (255 - v) * f)));
        const [r, gg, b] = rgbDe(hex);
        return '#' + [k(r), k(gg), k(b)].map((v) => v.toString(16).padStart(2, '0')).join('');
    }
    let atlasPronto = null;
    function carregar() {
        if (!atlasPronto) {
            atlasPronto = Promise.all(Object.entries(atlas).map(([p, img]) => new Promise((ok, erro) => {
                img.onload = ok;
                img.onerror = () => erro(new Error('Não deu para carregar a arte da fazenda.'));
                img.src = 'assets/fazenda/' + ARQUIVOS[p] + '?v=' + VERSAO_ARTE;
            }))).then(() => { montarPomar(); atlas.casas = montarCasas('primavera'); urlCasas = null; });   // fase 105: as casas
        }
        return atlasPronto;
    }

    /* ---- grama pintada dentro das peças dos pacotes: troca pela grama da estação ----
       Só a grama ligada à borda da peça (preenchimento a partir das bordas): o que está
       dentro do contorno (telhado verde do celeiro, folhas) continua igual. */
    const GRAMA_PECA = { '84c669': 'grama', '65a556': 'tufo', '8bd87d': 'ponto', 'c6e58d': 'ponto', '4e974c': 'tufo', '479f4a': 'tufo' };
    const PECAS_COM_GRAMA = { town: [0, 1, 2, 12, 13, 14, 24, 25, 26, 36, 37, 38, 39, 40, 41, 42, 43], farm: [0, 1, 83], factory: [99, 100, 101] };
    let atlasDaEstacao = null, estacaoDoAtlas = null;
    const rgbDe = (hex) => [1, 3, 5].map((k) => parseInt(hex.slice(k, k + 2), 16));
    function pintarGrama(dados, x0, y0, w, h, chao, fundo, transparente) {
        const W = dados.width, d = dados.data, novo = {};
        for (const [hex, papel] of Object.entries(GRAMA_PECA)) novo[hex] = rgbDe(chao[papel]);
        const visto = new Uint8Array(w * h), fila = [];
        for (let x = 0; x < w; x++) fila.push(x, 0, x, h - 1);
        for (let y = 0; y < h; y++) fila.push(0, y, w - 1, y);
        while (fila.length) {
            const y = fila.pop(), x = fila.pop();
            if (x < 0 || y < 0 || x >= w || y >= h || visto[y * w + x]) continue;
            visto[y * w + x] = 1;
            const k = ((y0 + y) * W + x0 + x) * 4;
            if (d[k + 3] < 200) continue;
            const n = novo[((d[k] << 16) | (d[k + 1] << 8) | d[k + 2]).toString(16).padStart(6, '0')];
            if (!n) continue;
            if (transparente) d[k + 3] = 0;   // fase 104: a grama da peça some e aparece a do chão
            else if (fundo) { const j = (y * w + x) * 4; d[k] = fundo.data[j]; d[k + 1] = fundo.data[j + 1]; d[k + 2] = fundo.data[j + 2]; }
            else { d[k] = n[0]; d[k + 1] = n[1]; d[k + 2] = n[2]; }
            fila.push(x + 1, y, x - 1, y, x, y + 1, x, y - 1);
        }
    }
    // inverno: neve em cima dos telhados (as peças de cima das casas e oficinas do Tiny Town)
    const TELHADOS = [48, 49, 51, 52, 53, 55];
    function nevarTelhado(dados, x0, y0) {
        const W = dados.width, d = dados.data;
        for (let x = 0; x < T; x++) {
            let y = 0;
            while (y < T && d[((y0 + y) * W + x0 + x) * 4 + 3] < 200) y++;
            for (let k = 1; k <= 4 && y + k < T - 4; k++) {
                const i = ((y0 + y + k) * W + x0 + x) * 4;
                if (d[i + 3] < 200 || (d[i] < 90 && d[i + 1] < 70)) continue;   // não pinta o contorno escuro
                const cor = k < 4 ? [255, 255, 255] : [214, 226, 238];
                d[i] = cor[0]; d[i + 1] = cor[1]; d[i + 2] = cor[2];
            }
        }
    }
    function prepararAtlasDaEstacao(est) {
        if (est === estacaoDoAtlas) return;
        estacaoDoAtlas = est;
        const chao = CHAO[est], novo = {};
        for (const [p, lista] of Object.entries({ ...PECAS_COM_GRAMA, town: [...PECAS_COM_GRAMA.town] })) {
            const img = atlas[p], c = document.createElement('canvas');
            c.width = img.width; c.height = img.height;
            const g = c.getContext('2d');
            g.drawImage(img, 0, 0);
            const dados = g.getImageData(0, 0, c.width, c.height);
            for (const i of lista) pintarGrama(dados, (i % COLS) * T, Math.floor(i / COLS) * T, T, T, chao, null, true);   // fase 104
            if (est === 'inverno' && p === 'town') for (const i of TELHADOS) nevarTelhado(dados, (i % COLS) * T, Math.floor(i / COLS) * T);
            g.putImageData(dados, 0, 0);
            novo[p] = c;
        }
        if (atlas.casas) novo.casas = montarCasas(est);   // fase 105: as casas com a neve da estação
        atlasDaEstacao = novo;
    }

    function tile(ctx, i, x, y, flip, pacote = 'farm') {
        if (i == null) return;   // casa vazia de uma grade (porteira e meio dos cercados)
        if (i >= 1000) { i -= 1000; pacote = 'propria'; }
        const img = pacote === 'propria' ? atlasProprio : (atlasDaEstacao && atlasDaEstacao[pacote]) || atlas[pacote];
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

    /* ---------- Textura nova, nível 1: as árvores da mata em pixel art detalhada ----------
       Desenhadas aqui (não vêm de pacote): copa feita de cachos de folha, cada cacho com contorno e luz
       vindo do alto à esquerda (5 tons), tronco com casca e raízes, galhos com folhinhas, sombra no chão.
       Uma família por estação: primavera e verão (verdes), outono (laranja), inverno (pinheiros com neve e
       árvores peladas com neve nos galhos). As variações saem de uma semente, então a mata não "pula". */
    const PAL_ARV = {
        primavera: { folha: ['#1b3a1e', '#285a2b', '#3a7a36', '#549f44', '#7cc452', '#b5e46c'], flor: ['#ffd1e1', '#f59cbc', '#fff4c2'] },
        verao: { folha: ['#1b3318', '#2c5522', '#43772c', '#5f9a35', '#88bd43', '#c0e06a'], flor: null },
        outono: { folha: ['#3a180b', '#742a10', '#ad421c', '#da7428', '#f0a43e', '#ffd88a'], flor: null },
        inverno: { folha: ['#14261c', '#1e3a2a', '#2c5238', '#3e6c48', '#56875a', '#7aa676'], flor: null },
        florida: { folha: ['#4a1d33', '#83355a', '#bd5784', '#e486ad', '#f6b3cd', '#ffe4ef'], flor: ['#ffffff', '#fff4c2'] }   // a cerejeira da primavera
    };
    const PAL_TRONCO = ['#24130b', '#43271a', '#664027', '#8a5834', '#ad7a4b'];
    const PAL_NEVE = ['#7f9bbd', '#b9cde6', '#e6f0fb', '#ffffff'];
    const BAYER = [[0, 2], [3, 1]];

    function telaArv(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
    // ruído estável por pixel (para a textura de folha e casca)
    const ruido = (x, y, s) => { let h = Math.imul(x * 374761393 + y * 668265263 + s * 2246822519, 1274126177); h ^= h >>> 13; h = Math.imul(h, 1597334677); return ((h ^ (h >>> 16)) >>> 0) / 4294967296; };
    // um tom (0 a n-1) de um valor de luz 0..1, com pontilhado nas fronteiras
    function tom(lum, x, y, n) { const v = Math.max(0, Math.min(0.999, lum)) * n + (BAYER[y & 1][x & 1] / 4 - 0.375) * 0.9; return Math.max(0, Math.min(n - 1, Math.floor(v))); }

    // a grade de pixels: cada um guarda o que é (0 nada, 1 folha, 2 tronco, 3 neve) e o tom
    function grade(w, h) { return { w, h, k: new Uint8Array(w * h), t: new Int8Array(w * h).fill(-1), dono: new Int16Array(w * h).fill(-1) }; }
    function pinta(g, x, y, k, t, dono) { if (x < 0 || y < 0 || x >= g.w || y >= g.h) return; const i = y * g.w + x; g.k[i] = k; g.t[i] = t; if (dono != null) g.dono[i] = dono; }
    const em = (g, x, y) => (x < 0 || y < 0 || x >= g.w || y >= g.h ? 0 : g.k[y * g.w + x]);

    function tronco(g, cx, base, altura, larg, r) {
        for (let y = base; y > base - altura; y--) {
            const f = (base - y) / altura, meio = Math.max(1.5, larg * (1 - f * 0.35) / 2), raiz = y > base - 3 ? (3 - (base - y)) * 1.2 : 0;
            const x0 = Math.round(cx - meio - raiz), x1 = Math.round(cx + meio + raiz);
            for (let x = x0; x <= x1; x++) {
                const u = (x - x0) / Math.max(1, x1 - x0);   // 0 à esquerda (luz) .. 1 à direita (sombra)
                let lum = 0.85 - u * 0.75 + (ruido(x, Math.floor(y / 3), 7) - 0.5) * 0.25;
                if (ruido(x, Math.floor(y / 4), 11) < 0.18 && u > 0.2 && u < 0.85) lum -= 0.35;   // as linhas da casca
                pinta(g, x, y, 2, 1 + tom(lum, x, y, 4));
            }
        }
    }
    function galho(g, x0, y0, x1, y1, esp) {
        const n = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0));
        for (let s = 0; s <= n; s++) {
            const x = Math.round(x0 + (x1 - x0) * s / n), y = Math.round(y0 + (y1 - y0) * s / n);
            for (let e = 0; e < esp; e++) pinta(g, x, y + e, 2, e === 0 ? 3 : 2);
        }
    }
    // a copa: cachos (bolinhas) pintados de trás para a frente; cada cacho tem luz própria e contorno
    function copa(g, cachos, r, pal) {
        const n = pal.folha.length - 1;   // o tom 0 é o contorno
        cachos.sort((a, b) => a.y - b.y).forEach((b, id) => {
            for (let y = Math.floor(b.y - b.r); y <= b.y + b.r; y++) {
                for (let x = Math.floor(b.x - b.r); x <= b.x + b.r; x++) {
                    const dx = (x + 0.5 - b.x) / b.r, dy = (y + 0.5 - b.y) / b.r, d2 = dx * dx + dy * dy;
                    const borda = 1 + (ruido(x, y, 3) - 0.5) * 0.28;   // a borda irregular, de folha
                    if (d2 > borda) continue;
                    const luz = -0.62 * dx - 0.78 * dy;   // > 0 para o lado da luz (alto, esquerda)
                    let lum = 0.5 + luz * 0.42 + (0.25 - Math.min(0.25, d2 * 0.25)) * 0.3;
                    lum += (ruido(x >> 1, y >> 1, 5) - 0.5) * 0.32;   // a textura das folhas
                    lum -= (y - g.h * 0.2) / g.h * 0.28;   // a parte de baixo da copa fica na sombra
                    if (d2 > 0.62 && luz < -0.1) lum -= 0.22;   // o lado da sombra do cacho
                    pinta(g, x, y, 1, 1 + tom(lum, x, y, n), id);
                }
            }
        });
        // o contorno de cada cacho por cima do de trás (é o que separa os cachos)
        const k2 = g.dono.slice();
        for (let y = 0; y < g.h; y++) for (let x = 0; x < g.w; x++) {
            const i = y * g.w + x;
            if (g.k[i] !== 1) continue;
            const eu = k2[i];
            for (const [ax, ay] of [[0, 1], [1, 0], [1, 1]]) {
                const j = (y + ay) * g.w + (x + ax);
                if (x + ax < g.w && y + ay < g.h && g.k[j] === 1 && k2[j] > eu && g.t[i] > 1) { g.t[i] = Math.max(1, g.t[i] - 2); break; }
            }
            // brilho: um pontinho claro no alto dos cachos
            if (g.t[i] >= n - 1 && ruido(x, y, 9) < 0.12) g.t[i] = n;
        }
        if (pal.flor) for (let i = 0; i < g.k.length; i++) if (g.k[i] === 1 && g.t[i] >= 3 && ruido(i, 1, 13) < 0.025) { g.k[i] = 4; g.t[i] = Math.floor(ruido(i, 2, 17) * pal.flor.length); }
    }
    // neve por cima de tudo o que tem céu em cima
    function nevar(g, grossura) {
        for (let x = 0; x < g.w; x++) {
            let livre = true;
            for (let y = 0; y < g.h; y++) {
                const k = g.k[y * g.w + x];
                if (!k) { livre = true; continue; }
                if (livre && k !== 3) {
                    const gr = grossura + (ruido(x, y, 21) < 0.4 ? 1 : 0);
                    for (let e = 0; e < gr; e++) if (y + e < g.h && g.k[(y + e) * g.w + x]) pinta(g, x, y + e, 3, e < gr - 1 ? (x + e) % 5 === 0 ? 2 : 3 : 1);
                    if (y - 1 >= 0) pinta(g, x, y - 1, 3, 2);
                }
                livre = false;
            }
        }
    }
    // a grade vira imagem: contorno escuro em volta de tudo
    function revelar(g, pal) {
        const c = telaArv(g.w, g.h), x2 = c.getContext('2d'), img = x2.createImageData(g.w, g.h);
        const hex = (s) => [parseInt(s.slice(1, 3), 16), parseInt(s.slice(3, 5), 16), parseInt(s.slice(5, 7), 16)];
        for (let y = 0; y < g.h; y++) for (let x = 0; x < g.w; x++) {
            const i = y * g.w + x, k = g.k[i];
            let cor = null;
            if (k) {
                const fora = !em(g, x - 1, y) || !em(g, x + 1, y) || !em(g, x, y - 1) || !em(g, x, y + 1);
                if (k === 1) cor = fora ? pal.folha[0] : pal.folha[g.t[i]];
                else if (k === 2) cor = fora ? PAL_TRONCO[0] : PAL_TRONCO[g.t[i]];
                else if (k === 3) cor = fora && g.t[i] < 3 ? PAL_NEVE[0] : PAL_NEVE[g.t[i]];
                else if (k === 4) cor = pal.flor[g.t[i]];
            }
            if (!cor) continue;
            const [r, gg, b] = hex(cor);
            img.data.set([r, gg, b, 255], i * 4);
        }
        x2.putImageData(img, 0, 0);
        return c;
    }

    // a árvore de copa redonda (grande ou média)
    function arvoreCopa(est, semente, grande) {
        const r = rng(semente), W = grande ? 50 : 40, H = grande ? 72 : 58, g = grade(W, H), cx = W / 2 + (r() - 0.5) * 2;
        const alt = Math.round(H * (0.4 + r() * 0.06)), pal = PAL_ARV[est] || PAL_ARV.primavera;
        tronco(g, cx, H - 1, alt, grande ? 7 : 6, r);
        // galhos com um cachinho na ponta (o da esquerda mais baixo)
        const cachos = [], yb = H - 1 - alt;
        const ge = { x: cx - 11 - r() * 3, y: H - 1 - alt * (0.45 + r() * 0.12) }, gd = { x: cx + 10 + r() * 3, y: H - 1 - alt * (0.68 + r() * 0.1) };
        galho(g, Math.round(cx - 2), Math.round(ge.y + 5), Math.round(ge.x + 3), Math.round(ge.y + 1), 2);
        galho(g, Math.round(cx + 2), Math.round(gd.y + 5), Math.round(gd.x - 3), Math.round(gd.y + 1), 2);
        cachos.push({ x: ge.x, y: ge.y - 1, r: 4.5 + r() * 1.5 }, { x: gd.x, y: gd.y - 1, r: 4 + r() * 1.5 });
        // a copa: um anel de cachos e alguns no meio
        const R = W * 0.36, ccy = yb - R * 0.55 + 4;
        const n = 8 + Math.floor(r() * 3);
        for (let k = 0; k < n; k++) {
            const a = (k / n) * Math.PI * 2 + r() * 0.5;
            cachos.push({ x: cx + Math.cos(a) * R * 0.62, y: ccy + Math.sin(a) * R * 0.48, r: R * (0.42 + r() * 0.16) });
        }
        cachos.push({ x: cx - R * 0.2, y: ccy - R * 0.25, r: R * 0.5 }, { x: cx + R * 0.15, y: ccy + R * 0.15, r: R * 0.48 }, { x: cx, y: ccy + R * 0.42, r: R * 0.42 });
        copa(g, cachos, r, pal);
        return { img: revelar(g, pal), w: W, h: H };
    }
    // o pinheiro: andares de galhos em triângulo, cada andar sombreado pelo de cima
    function arvorePinheiro(est, semente, grande) {
        const r = rng(semente), W = grande ? 36 : 30, H = grande ? 70 : 58, g = grade(W, H), cx = W / 2;
        const pal = est === 'inverno' ? PAL_ARV.inverno : { folha: ['#13261a', '#1d3b26', '#2b5634', '#3c7443', '#579357', '#86b874'], flor: null };
        tronco(g, cx, H - 1, 12, 5, r);
        const andares = grande ? 5 : 4, topo = 3, fim = H - 9, alt = (fim - topo) / andares;
        for (let a = andares - 1; a >= 0; a--) {
            const y0 = Math.round(topo + a * alt * 0.92), y1 = Math.round(topo + (a + 1) * alt + 2), meia = (W / 2 - 1) * (0.42 + 0.58 * (a + 1) / andares);
            for (let y = y0; y <= y1; y++) {
                const f = (y - y0) / Math.max(1, y1 - y0), m = 1.5 + meia * f;
                for (let x = Math.floor(cx - m); x <= Math.ceil(cx + m); x++) {
                    // a barra de baixo, serrilhada (pontas dos galhos)
                    if (y === y1 && ruido(x, a, 31) < 0.45) continue;
                    const u = (x - (cx - m)) / Math.max(1, 2 * m);
                    let lum = 0.78 - u * 0.62 + (ruido(x >> 1, y >> 1, 33) - 0.5) * 0.3;
                    if (y - y0 < 4 && a > 0) lum -= 0.25;   // a sombra do andar de cima
                    // no inverno, a neve pousada nas pontas dos galhos de cada andar
                    if (est === 'inverno' && y >= y1 - 2 && ruido(x, y, 41) < (y === y1 ? 0.75 : 0.45)) { pinta(g, x, y, 3, ruido(x, y, 43) < 0.3 ? 2 : 3, a); continue; }
                    pinta(g, x, y, 1, 1 + tom(lum, x, y, pal.folha.length - 1), a);
                }
            }
        }
        if (est === 'inverno') nevar(g, 4);
        return { img: revelar(g, pal), w: W, h: H };
    }
    // a árvore pelada do inverno: galhos em forquilha, neve em cima
    function arvorePelada(semente, grande) {
        const r = rng(semente), W = grande ? 46 : 38, H = grande ? 66 : 54, g = grade(W, H), cx = W / 2;
        const alt = Math.round(H * 0.32);
        tronco(g, cx, H - 1, alt, grande ? 7 : 6, r);
        const ramo = (x, y, ang, comp, esp, nivel) => {
            const x1 = x + Math.cos(ang) * comp, y1 = y - Math.sin(ang) * comp;
            galho(g, Math.round(x), Math.round(y), Math.round(x1), Math.round(y1), esp);
            if (nivel <= 0 || y1 < 3) return;
            ramo(x1, y1, ang + 0.35 + r() * 0.35, comp * (0.62 + r() * 0.15), Math.max(1, esp - 1), nivel - 1);
            ramo(x1, y1, ang - 0.35 - r() * 0.35, comp * (0.62 + r() * 0.15), Math.max(1, esp - 1), nivel - 1);
        };
        const yb = H - 1 - alt;
        ramo(cx - 1, yb + 2, Math.PI / 2 + 0.55, H * 0.24, 3, 4);
        ramo(cx + 1, yb + 2, Math.PI / 2 - 0.5, H * 0.26, 3, 4);
        ramo(cx, yb + 1, Math.PI / 2 + 0.05, H * 0.22, 3, 3);
        nevar(g, 1);
        return { img: revelar(g, PAL_ARV.inverno), w: W, h: H };
    }
    // o arbusto: só a copa, baixinho
    function arbustoNovo(est, semente) {
        const r = rng(semente), W = 24, H = 17, g = grade(W, H), cachos = [];
        const pal = PAL_ARV[est === 'inverno' ? 'inverno' : est];
        for (let k = 0; k < 5; k++) cachos.push({ x: 5 + k * 3.4 + (r() - 0.5) * 2, y: 10 + (r() - 0.5) * 3 - (k === 2 ? 2 : 0), r: 4.4 + r() * 1.6 });
        copa(g, cachos, r, pal);
        if (est === 'inverno') nevar(g, 2);
        return { img: revelar(g, pal), w: W, h: H };
    }
    // as variações de cada estação (feitas uma vez e guardadas)
    const MATA_NOVA = {};
    function mataNova(est) {
        if (MATA_NOVA[est]) return MATA_NOVA[est];
        const s = hash('mata' + est), v = (f, n) => Array.from({ length: n }, (_, i) => f(s + i * 977));
        const m = est === 'inverno'
            ? { grande: [...v((x) => arvorePinheiro('inverno', x, true), 3), ...v((x) => arvorePelada(x, true), 2)],
                media: [...v((x) => arvorePinheiro('inverno', x + 5, false), 2), ...v((x) => arvorePelada(x + 7, false), 2)],
                arbusto: v((x) => arbustoNovo('inverno', x), 3) }
            : { grande: [...v((x) => arvoreCopa(est, x, true), 4), ...v((x) => arvorePinheiro(est, x, true), 1),
                         ...(est === 'primavera' ? v((x) => arvoreCopa('florida', x + 21, true), 2) : [])],
                media: [...v((x) => arvoreCopa(est, x + 3, false), 3), ...v((x) => arvorePinheiro(est, x + 9, false), 1)],
                arbusto: v((x) => arbustoNovo(est, x), 3) };
        MATA_NOVA[est] = m;
        return m;
    }
    // a sombra no chão (elipse achatada, um pouco para a direita: a luz vem da esquerda)
    function sombraArvore(ctx, cx, by, w) {
        ctx.save();
        ctx.fillStyle = 'rgba(18, 34, 16, 0.26)';
        ctx.beginPath();
        ctx.ellipse(cx + w * 0.08, by - 1, w * 0.36, Math.max(2.5, w * 0.09), 0, 0, Math.PI * 2);
        ctx.fill();
        ctx.restore();
    }

    /* ---------- Textura nova, nível 2: o chão ----------
       A grama é pintada pixel a pixel: 4 tons misturados por manchas grandes e pequenas (com pontilhado nas
       fronteiras), tufos com a ponta clara, campinhos de flores na primavera, capim seco no verão, folhas
       caídas no outono e neve com sombras azuis no inverno. A terra (caminhos, galinheiro, feira) tem borda
       orgânica: cantos arredondados, aro escuro, pedrinhas e a grama invadindo a beirada. */
    const CHAO_TONS = {
        primavera: ['#5d9b44', '#6eb04f', '#84c669', '#9ad57d'],
        verao: ['#6e9c3b', '#80ae49', '#97c95c', '#add86f'],
        outono: ['#878843', '#9a9c4d', '#adb35c', '#c2c56e'],
        inverno: ['#c4d2e3', '#d8e3ef', '#ecf2f8', '#ffffff']
    };
    const FLORES_CHAO = { primavera: ['#ffffff', '#f7a9c4', '#fdd85d', '#a6c8ff', '#ffd1e1'], verao: ['#fdd85d', '#ffffff', '#f0a24a'], outono: [], inverno: [] };
    // ruído suave (valor em grade, interpolado) para as manchas
    function ruidoSuave(x, y, cel, s) {
        const gx = Math.floor(x / cel), gy = Math.floor(y / cel), fx = x / cel - gx, fy = y / cel - gy;
        const sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
        const a = ruido(gx, gy, s), b = ruido(gx + 1, gy, s), c = ruido(gx, gy + 1, s), d = ruido(gx + 1, gy + 1, s);
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy;
    }
    function pintarChaoNovo(ctx, W, H, est, r) {
        const tons = (CHAO_TONS[est] || CHAO_TONS.primavera).map((h) => [1, 3, 5].map((k) => parseInt(h.slice(k, k + 2), 16)));
        const img = ctx.createImageData(W, H), d = img.data;
        for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
            const v = ruidoSuave(x, y, 46, 1) * 0.55 + ruidoSuave(x, y, 13, 2) * 0.3 + ruido(x, y, 3) * 0.15;
            const t = tons[Math.max(0, Math.min(3, Math.floor(v * 4 + (BAYER[y & 1][x & 1] / 4 - 0.375) * 0.8)))];
            const i = (y * W + x) * 4;
            d[i] = t[0]; d[i + 1] = t[1]; d[i + 2] = t[2]; d[i + 3] = 255;
        }
        ctx.putImageData(img, 0, 0);
        const px = (x, y, cor) => { ctx.fillStyle = cor; ctx.fillRect(Math.round(x), Math.round(y), 1, 1); };
        const [escuro, medio, base, claro] = CHAO_TONS[est] || CHAO_TONS.primavera;
        if (est === 'inverno') {
            // neve: sombras azuis em ondas, brilhinhos e a ponta da grama aparecendo
            for (let n = 0; n < (W * H) / 70; n++) {
                const x = r() * W, y = r() * H, w = 3 + Math.floor(r() * 6);
                ctx.fillStyle = '#b7c8dd'; ctx.fillRect(Math.round(x), Math.round(y), w, 1);
                ctx.fillStyle = '#ffffff'; ctx.fillRect(Math.round(x) + 1, Math.round(y) - 1, w - 2, 1);
            }
            for (let n = 0; n < (W * H) / 260; n++) { const x = r() * W, y = r() * H; px(x, y, '#3e6c48'); px(x + 1, y - 1, '#56875a'); px(x + 2, y, '#3e6c48'); }
            for (let n = 0; n < (W * H) / 120; n++) px(r() * W, r() * H, '#ffffff');
        } else {
            // tufos: um "v" de capim com a base escura e as pontas claras
            for (let n = 0; n < (W * H) / 26; n++) {
                const x = Math.floor(r() * W), y = Math.floor(r() * H), alto = r() < 0.4;
                px(x, y, escuro); px(x - 1, y - 1, medio); px(x + 1, y - 1, medio);
                if (alto) { px(x - 1, y - 2, claro); px(x + 1, y - 2, claro); px(x, y - 1, base); }
                else { px(x - 1, y - 2, base); px(x + 1, y - 2, base); }
            }
            // capim seco (verão e outono)
            if (est === 'verao' || est === 'outono') for (let n = 0; n < (W * H) / 140; n++) { const x = r() * W, y = r() * H; px(x, y, '#c9b65c'); px(x + 1, y - 1, '#e0cf7a'); }
            // folhas caídas no outono: em montinhos
            if (est === 'outono') {
                const cores = ['#e38628', '#c34b35', '#fdbe53', '#aa2c23', '#b8643a'];
                for (let m = 0; m < (W * H) / 1400; m++) {
                    const cx = r() * W, cy = r() * H;
                    for (let k = 0; k < 6 + r() * 10; k++) {
                        const x = cx + (r() - 0.5) * 16, y = cy + (r() - 0.5) * 10, c = cores[Math.floor(r() * cores.length)];
                        px(x, y, c); px(x + 1, y, c); px(x, y + 1, '#6b3a1c');
                    }
                }
            }
            // campinhos de flores: várias juntas da mesma cor, com a sombrinha embaixo
            const flores = FLORES_CHAO[est] || [];
            if (flores.length) for (let m = 0; m < (W * H) / (est === 'primavera' ? 900 : 2400); m++) {
                const cx = r() * W, cy = r() * H, cor = flores[Math.floor(r() * flores.length)], n = 3 + Math.floor(r() * 6);
                for (let k = 0; k < n; k++) {
                    const x = Math.round(cx + (r() - 0.5) * 14), y = Math.round(cy + (r() - 0.5) * 9);
                    px(x, y + 2, escuro);
                    px(x, y - 1, cor); px(x - 1, y, cor); px(x + 1, y, cor); px(x, y + 1, cor);
                    px(x, y, cor === '#fdd85d' ? '#e38628' : '#fdd85d');
                }
            }
            // trevinhos e pedrinhas
            for (let n = 0; n < (W * H) / 900; n++) { const x = r() * W, y = r() * H; px(x, y, '#a49a8a'); px(x + 1, y, '#c9c0b0'); px(x, y + 1, '#6f675c'); }
        }
    }

    // a terra com borda orgânica: uma peça 16x16 para cada combinação de vizinhos (8 bits), guardada
    const TERRA_NOVA = {};
    const TONS_TERRA = ['#6e4630', '#8f6142', '#a97650', '#c08c60', '#d4a575'];
    function terraNova(viz, est) {
        const chave = est + viz;
        if (TERRA_NOVA[chave]) return TERRA_NOVA[chave];
        const tem = (b) => !!(viz & b), N = tem(1), S = tem(2), O = tem(4), L = tem(8), NO = tem(16), NE = tem(32), SO = tem(64), SE = tem(128);
        const c = document.createElement('canvas'); c.width = T; c.height = T;
        const g = c.getContext('2d'), img = g.createImageData(T, T), d = img.data;
        const borda = 2, raio = 3;
        // quanto falta para a borda (negativo: fora da terra)
        const dentro = (x, y) => {
            const jit = (ruido(x, y, 61 + viz) - 0.5) * 1.4;
            let dist = 99;
            if (!N) dist = Math.min(dist, y - borda + jit);
            if (!S) dist = Math.min(dist, T - 1 - borda - y + jit);
            if (!O) dist = Math.min(dist, x - borda + jit);
            if (!L) dist = Math.min(dist, T - 1 - borda - x + jit);
            // cantos de fora redondos
            // (sx, sy: para que lado fica o canto; só vale do lado de fora do centro do arredondado)
            const canto = (cx, cy, sx, sy, ok) => { if (ok && (x - cx) * sx > 0 && (y - cy) * sy > 0) dist = Math.min(dist, raio - Math.hypot(x - cx, y - cy) + jit); };
            const a0 = borda + raio, a1 = T - 1 - borda - raio;
            canto(a0, a0, -1, -1, !N && !O); canto(a1, a0, 1, -1, !N && !L);
            canto(a0, a1, -1, 1, !S && !O); canto(a1, a1, 1, 1, !S && !L);
            // cantos de dentro: um tufinho de grama no canto quando falta só o vizinho da diagonal
            const dentroC = (cx, cy, ok) => { if (ok) dist = Math.min(dist, Math.hypot(x - cx, y - cy) - 2.2 + jit); };
            dentroC(0, 0, N && O && !NO); dentroC(T - 1, 0, N && L && !NE); dentroC(0, T - 1, S && O && !SO); dentroC(T - 1, T - 1, S && L && !SE);
            return dist;
        };
        const tons = TONS_TERRA.map((h) => [1, 3, 5].map((k) => parseInt(h.slice(k, k + 2), 16)));
        const grama = (CHAO_TONS[est] || CHAO_TONS.primavera).map((h) => [1, 3, 5].map((k) => parseInt(h.slice(k, k + 2), 16)));
        for (let y = 0; y < T; y++) for (let x = 0; x < T; x++) {
            const k = dentro(x, y), i = (y * T + x) * 4;
            let cor = null;
            if (k >= 1) {
                // a terra: tons em manchinhas, pedrinha clara com sombra, mais escura perto da borda
                let v = 0.55 + (ruido(x >> 1, y >> 1, 71) - 0.5) * 0.5 + (ruido(x, y, 72) - 0.5) * 0.25 - (k < 2.2 ? 0.35 : 0);
                let t = Math.max(1, Math.min(4, Math.floor(v * 4 + (BAYER[y & 1][x & 1] / 4 - 0.375) * 0.8)));
                if (ruido(x, y, 73) < 0.035) t = 4;
                cor = tons[t];
                if (est === 'inverno' && ruido(x >> 1, y >> 1, 74) < 0.2) cor = ruido(x, y, 77) < 0.5 ? [236, 242, 248] : [255, 255, 255];   // floquinhos de neve   // neve por cima
            } else if (k >= 0) {
                cor = tons[0];   // o aro escuro da beirada
            } else if (k > -1.6 && ruido(x, y, 75) < 0.55) {
                cor = grama[ruido(x, y, 76) < 0.5 ? 0 : 1];   // a grama encostando (um pouco mais escura, na sombra)
            }
            if (!cor) continue;
            d[i] = cor[0]; d[i + 1] = cor[1]; d[i + 2] = cor[2]; d[i + 3] = 255;
        }
        g.putImageData(img, 0, 0);
        TERRA_NOVA[chave] = c;
        return c;
    }
    // os 8 vizinhos de um quadrado de terra (igual(dx, dy) diz se o vizinho também é terra)
    const vizinhosTerra = (igual) => (igual(0, -1) ? 1 : 0) | (igual(0, 1) ? 2 : 0) | (igual(-1, 0) ? 4 : 0) | (igual(1, 0) ? 8 : 0)
        | (igual(-1, -1) ? 16 : 0) | (igual(1, -1) ? 32 : 0) | (igual(-1, 1) ? 64 : 0) | (igual(1, 1) ? 128 : 0);

    // (fase 105: o celeiro e a casa agora vêm do atlas "casas", desenhado em montarCasas)

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
        const fundoGrama = document.createElement('canvas');   // cópia do fundo antes do lago (cantos do tanque)
        fundoGrama.width = MW; fundoGrama.height = MH;
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
        let zonasVenda = [];                               // os terrenos à venda (ZONAS): o próximo da fila e o da direita (fase 78)
        let vendaTocada = null;                            // a placa tocada agora (o número do terreno)
        let pierPronto = false;                            // fase 61: o píer já foi construído?
        let pausada = false;                               // fase 62: no alto-mar, a fazenda para de desenhar
        let clima = null;                                  // sol | nublado | chuva | calor | vento
        let lago = null;                                   // { prontos, max } do seu lago, ou null
        // visita na porteira: { tipo, item (tile do balão), x, y, tx, ty, saindo }
        let visitante = null;
        let avatarAtual = null;   // avatar do fazendeiro na tela (o seu, ou o do vizinho visitado)
        const VISITANTE_ARTE = { feirante: 86, doceira: 99, caminhoneiro: 112, mascate: 100, mercador: 111, perks: 97 };   // Tiny Dungeon (fase 60: o mercador; fase 66: o Perks)
        const PORTEIRA = { x: 8, y: 2 };   // onde a visita para (do lado da casa)
        let hover = null;                                  // canteiro, 'celeiro', 'a:<id>' ou {tx, ty}
        let alcance = null;                                // alcance de um item tocado: { x, y, raio, ate }
        const SEGURAR_MS = 3000;                           // segurar 3 s num item: pega para mudar de lugar
        let segurando = null;                              // { alvo, t0, cx, cy, id, timer }
        let ignorarCliqueAte = 0;                          // o clique que vem depois de segurar não vale
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
        function areaCercado(bicho) {
            const c = (construcoesFn() || []).find((k) => CERCADOS[k.tipo] && CERCADOS[k.tipo].bicho === bicho);
            if (!c) return null;
            const k = CERCADOS[c.tipo];
            return { x0: wx(c.x) + 6, y0: wy(c.y) + 3, x1: wx(c.x + k.w) - 22, y1: wy(c.y + k.h) - 21, cercado: true };
        }
        // fase 69: por onde o Faísca anda: a estradinha de pedra (senão a de terra); sem estradinha, pela
        // fazenda toda, longe da plantação (nem no canteiro, nem colado nele, nem em cima de construção)
        let cacheCaminho = { chave: null, area: null };
        function areaCaminho() {
            const cons = construcoesFn() || [], cant = listaCanteiros();
            const chave = cons.length + ':' + cant.length + ':' + zonasAtuais + ':' + direitaAtuais;
            if (cacheCaminho.chave === chave) return cacheCaminho.area;
            let tiles = cons.filter((c) => c.tipo === 'caminho_pedra');
            if (!tiles.length) tiles = cons.filter((c) => c.tipo === 'caminho_terra');
            let pontos = tiles.map((c) => ({ x: wx(c.x), y: wy(c.y) }));
            if (!pontos.length) {
                const ocupado = new Set();
                for (const c of cant) for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) ocupado.add((c.x + dx) + ',' + (c.y + dy));
                for (const c of cons) {
                    const t = arteItem(c.tipo, EST) || {};
                    for (let dy = 0; dy < (t.h || 1); dy++) for (let dx = 0; dx < (t.w || 1); dx++) ocupado.add((c.x + dx) + ',' + (c.y + dy));
                }
                const cx = caixaTerreno();
                for (let ty = cx.y0; ty < cx.y1; ty++) {
                    for (let tx = cx.x0; tx < cx.x1; tx++) if (livre(tx, ty) && !ocupado.has(tx + ',' + ty)) pontos.push({ x: wx(tx), y: wy(ty) });
                }
            }
            const area = pontos.length ? {
                x0: Math.min(...pontos.map((p) => p.x)), y0: Math.min(...pontos.map((p) => p.y)),
                x1: Math.max(...pontos.map((p) => p.x)), y1: Math.max(...pontos.map((p) => p.y)), pontos
            } : null;
            cacheCaminho = { chave, area };
            return area;
        }
        // o Faísca anda no meio dos equipamentos de energia (painéis, turbinas, baterias, gerador, reator...):
        // os quadrados em volta de cada um, fora dos canteiros e das construções. Ao chegar, olha para o
        // equipamento e mexe nele (olhar = o meio dele). Às vezes atravessa para outro equipamento.
        const EQUIP_ENERGIA = ['painel_solar', 'turbina', 'bateria', 'supercap', 'gerador_bio', 'hidreletrica', 'reator', 'triturador', 'fabrica_auto'];
        let cacheEnergia = { chave: null, area: null };
        function areaEnergia() {
            const cons = construcoesFn() || [], cant = listaCanteiros();
            const equip = cons.filter((c) => EQUIP_ENERGIA.includes(c.tipo));
            const chave = equip.map((c) => c.tipo + c.x + ',' + c.y).join('|') + ':' + cons.length + ':' + cant.length + ':' + zonasAtuais + ':' + direitaAtuais;
            if (cacheEnergia.chave === chave) return cacheEnergia.area;
            const ocupado = new Set(cant.map((c) => c.x + ',' + c.y));
            for (const c of cons) {
                if (c.tipo === 'caminho_pedra' || c.tipo === 'caminho_terra') continue;   // na estradinha pode
                const t = arteItem(c.tipo, EST) || {};
                for (let dy = 0; dy < (t.h || 1); dy++) for (let dx = 0; dx < (t.w || 1); dx++) ocupado.add((c.x + dx) + ',' + (c.y + dy));
            }
            const pontos = [], vistos = new Set();
            for (const c of equip) {
                const t = arteItem(c.tipo, EST) || {}, w = t.w || 1, h = t.h || 1, olhar = wx(c.x) + w * T / 2 - T / 2;
                for (let ty = c.y - 1; ty <= c.y + h; ty++) {
                    for (let tx = c.x - 1; tx <= c.x + w; tx++) {
                        const k = tx + ',' + ty;
                        if (ocupado.has(k) || vistos.has(k) || !livre(tx, ty)) continue;
                        vistos.add(k);
                        pontos.push({ x: wx(tx), y: wy(ty), olhar });
                    }
                }
            }
            const area = pontos.length ? {
                x0: Math.min(...pontos.map((p) => p.x)), y0: Math.min(...pontos.map((p) => p.y)),
                x1: Math.max(...pontos.map((p) => p.x)), y1: Math.max(...pontos.map((p) => p.y)), pontos, salto: 0.2
            } : null;
            cacheEnergia = { chave, area };
            return area;
        }
        function areaDe(tipo) {
            if (tipo === 'energia') { const c = areaEnergia(); if (c) return c; tipo = 'caminho'; }   // sem equipamento: a estradinha
            if (tipo === 'caminho') { const c = areaCaminho(); if (c) return c; tipo = 'campo'; }
            const cercado = areaCercado(tipo);
            if (cercado) return cercado;
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
                ? { x: MAPA.galinheiro.x, y: MAPA.galinheiro.y, w: MAPA.galinheiro.w, h: MAPA.galinheiro.h || 2 }
                : { x: MAPA.pasto.x + 1, y: MAPA.pasto.y + 2, w: MAPA.pasto.w - 2, h: MAPA.pasto.h - 3 };
            return { x0: wx(a.x), y0: wy(a.y), x1: wx(a.x + a.w - 1), y1: wy(a.y + a.h - 1) };
        }

        /* ---- câmera ---- */
        // a câmera só passeia pelo terreno (mais uma bordinha de mata), nunca se perde no mato
        function faixaCamera() {
            const borda = T * 2;   // um pouco de mata (e a placa do terreno à venda)
            const topo = margem.topo / escala, base = margem.base / escala;
            const cx = caixaTerreno();
            let minX = Math.min(wx(cx.x0) - borda, wx(MAPA.feira.x - 1)), maxX = wx(cx.x1) + borda - vw;   // (até a feira, na mata à esquerda)
            let minY = wy(cx.y0) - borda - topo, maxY = wy(cx.y1) + borda + base - vh;
            // fase 78: a placa de cada terreno à venda sempre aparece inteira, com um pouco de mata em volta
            for (const zv of zonasVenda) {
                minX = Math.min(minX, wx(zv.placa.x - 2)); maxX = Math.max(maxX, wx(zv.placa.x + 3) - vw);
                minY = Math.min(minY, wy(zv.placa.y - 2) - topo); maxY = Math.max(maxY, wy(zv.placa.y + 3) + base - vh);
            }
            // fase 67: terreno que chega no litoral deixa descer até a areia e um pouco do mar (no
            // celular a tela é baixa e a praia sumia; no computador ela já aparecia)
            if (cx.y1 >= AREIA_Y && cx.y1 < MAPA.mar.y + 3) maxY = Math.max(maxY, wy(MAPA.mar.y + 3) + base - vh);
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
            dpr = Math.min(window.devicePixelRatio || 1, 2);   // (no máximo 2x: em tela 3x o celular desenhava 2,25 vezes mais pixels; o pixel art fica igual)
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
        // fase 51: a feira (barracas: quantas tem; vende: o que está à venda; vagas: mostra as que dá para comprar)
        const FEIRA = MAPA.feira;
        const RADIO = { x: FEIRA.x + 2, y: FEIRA.y + FEIRA.h - 1 };   // fase 107: embaixo das barracas da feira
        let radioTocando = false;
        let feira = { barracas: 1, vende: [], vagas: false };

        function montarFundo() {
            const r = rng(20261007);
            const chao = CHAO[EST] || CHAO.primavera;
            prepararAtlasDaEstacao(EST);
            // fase 104 (textura nova, nível 2): o chão pintado pixel a pixel
            pintarChaoNovo(f, MW, MH, EST, r);

            // terra batida do galinheiro (fase 104: a terra nova, com borda orgânica)
            const g = MAPA.galinheiro, retTerra = (q0, x0, y0, w0, h0) => {
                for (let yy = 0; yy < h0; yy++) for (let xx = 0; xx < w0; xx++) {
                    const viz = vizinhosTerra((dx, dy) => xx + dx >= 0 && xx + dx < w0 && yy + dy >= 0 && yy + dy < h0);
                    q0.drawImage(terraNova(viz, EST), wx(x0 + xx), wy(y0 + yy));
                }
            };
            retTerra(f, g.x, g.y, g.w, g.h);

            desenharLitoral();   // fase 61: a areia da praia e o mar (a mata do terreno à venda vem por cima)

            // mata em volta do terreno. Fase 103 (textura nova, nível 1): árvores grandes desenhadas em pixel
            // art detalhada (mataNova), com sombra no chão. Elas ocupam mais de um quadrado: se a copa fosse
            // cobrir o seu terreno, a feira ou a placa de um terreno à venda, entra uma menor (ou nada)
            const arvores = [], nova = mataNova(EST);
            const livre = (tx, ty) => !dentroTerreno(tx, ty) && ty < AREIA_Y
                && !zonasVenda.some((zv) => Math.abs(tx - zv.placa.x) <= 1 && ty >= zv.placa.y - 1 && ty <= zv.placa.y + 1)
                && !(tx >= FEIRA.x - 1 && ty >= FEIRA.y - 1 && tx < FEIRA.x + FEIRA.w && ty <= FEIRA.y + FEIRA.h + 1);
            const cabe = (a, bx, by) => {
                for (let y = by - a.h + 6; y <= by; y += 8) for (let x = bx - a.w / 2 + 3; x <= bx + a.w / 2 - 3; x += 8) {
                    if (!livre(Math.floor((x - wx(0)) / T), Math.floor((y - wy(0)) / T))) return false;
                }
                return true;
            };
            for (let ty = -MARGEM; ty < MAPA.h + MARGEM + 3; ty++) {
                for (let tx = -MARGEM - 1; tx < MAPA.w + MARGEM + 1; tx++) {
                    if (!livre(tx, ty)) continue;
                    const longe = distTerreno(tx, ty);
                    const chance = longe >= 3 ? 0.5 : longe === 2 ? 0.42 : 0.34;
                    const v = r(), w = r(), jx = Math.floor((r() - 0.5) * 8), jy = Math.floor((r() - 0.5) * 5);
                    if (v >= chance) continue;
                    const bx = wx(tx) + T / 2 + jx, by = wy(ty) + T - 1 + jy;
                    const ordem = w < 0.6 ? ['grande', 'media', 'arbusto'] : w < 0.85 ? ['media', 'arbusto'] : ['arbusto'];
                    for (const tam of ordem) {
                        const lista = nova[tam], a = lista[Math.floor(r() * lista.length)];
                        if (!cabe(a, bx, by)) continue;
                        arvores.push({ nova: a, x: Math.round(bx - a.w / 2), y: by - a.h + 1, base: by, cx: bx });
                        break;
                    }
                }
            }
            // fase 67: na areia, peças de praia em vez de mata. Na praia que ainda não é sua, uma barreira de
            // dunas e coqueiros na divisa com a fazenda e coisas espalhadas pela areia; na sua, só nas laterais
            const rp = rng(6767), coqueiros = new Set();
            for (let ty = AREIA_Y; ty < MAPA.mar.y; ty++) {
                for (let tx = -MARGEM; tx < MAPA.w + MARGEM; tx++) {
                    const v = rp(), w = rp(), jx = Math.floor((rp() - 0.5) * 6), jy = Math.floor((rp() - 0.5) * 3);
                    if (dentroTerreno(tx, ty)) continue;
                    if (zonasVenda.some((zv) => Math.abs(tx - zv.placa.x) <= 1 && ty >= zv.placa.y - 1 && ty <= zv.placa.y + 1)) continue;
                    const pecas = [];
                    if (tx < 0 || tx >= MAPA.w) {
                        const longe = tx < 0 ? -tx : tx - MAPA.w + 1;
                        if (v < (longe >= 3 ? 0.75 : 0.5)) pecas.push(w < 0.5 ? 'coqueiro' : w < 0.78 ? 'pedra' : 'duna');
                    } else if (ty === AREIA_Y) {   // a barreira: duna de ponta a ponta, com coqueiros atrás
                        if (w < 0.45) pecas.push('coqueiro');
                        pecas.push(v < 0.88 ? 'duna' : 'pedra');
                    } else if (v < 0.12) pecas.push('coqueiro');
                    else if (v < 0.2) pecas.push('pedra');
                    else if (v < 0.235) pecas.push('tronco');
                    else if (v < 0.27) pecas.push('concha');
                    for (let peca of pecas) {
                        if (peca === 'coqueiro' && (coqueiros.has(tx + ',' + (ty - 1)) || ty === MAPA.mar.y - 1)) peca = null;   // nem empilhado, nem na beira molhada
                        if (!peca) continue;
                        if (peca === 'coqueiro') coqueiros.add(tx + ',' + ty);
                        const k = PRAIA[peca], atras = peca === 'coqueiro' && ty === AREIA_Y ? -5 : 0;
                        arvores.push({ p: 'propria', i: k.i, topo: k.topo, x: wx(tx) + (k.fixo ? 0 : jx), y: wy(ty) + (k.fixo ? 0 : jy) + atras });
                    }
                }
            }
            // o chão de terra batida da feira
            retTerra(f, FEIRA.x, FEIRA.y, FEIRA.w, FEIRA.h);
            const pe = (a) => (a.nova ? a.base : a.y + T);
            arvores.sort((a, b) => pe(a) - pe(b)).forEach((a) => {
                if (a.nova) { sombraArvore(f, a.cx, a.base, a.nova.w); f.drawImage(a.nova.img, a.x, a.y); return; }
                if (a.topo != null) tile(f, a.topo, a.x, a.y - T, false, a.p);
                tile(f, a.i, a.x, a.y, false, a.p);
            });

            // celeiro e casa
            const c = retCeleiro();
            // fase 105: o celeiro e a casa desenhados (atlas "casas"; a grama do fundo aparece em volta)
            gradeCasa('celeiro', 3, 6).forEach((linha, yy) => linha.forEach((i, xx) => tile(f, i, c.x + xx * T, c.y + yy * T, false, 'casas')));
            gradeCasa('casa', 3, 3).forEach((linha, yy) => linha.forEach((i, xx) => tile(f, i, wx(MAPA.casa.x + xx), wy(MAPA.casa.y + yy), false, 'casas')));

            // pasto cercado com porteira (fase 45: só para quem ainda tem bicho grande sem cercado)
            const pa = MAPA.pastoAtivo ? MAPA.pasto : { x: 0, y: 0, w: 0, h: 0 };
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
            if (MAPA.pastoAtivo) for (const o of MAPA.cochos) tile(f, o.i, wx(o.x), wy(o.y));
            if (zonasAtuais >= 3) {
                fundoGrama.getContext('2d').drawImage(fundo, 0, 0);
                desenharLago();
            }
            if (zonasAtuais >= 7) desenharPier();   // fase 61
        }

        /* ---- fase 61: o litoral. Areia de y 32 a 36 (com a beirada molhada) e o mar de y 37 até a
           borda de baixo do mundo, de ponta a ponta; ondinhas e espuma na beira. ---- */
        function desenharLitoral() {
            const r = rng(6161);
            const ret = (x, y, w, h, cor) => { f.fillStyle = cor; f.fillRect(x, y, w, h); };
            const AREIA = wy(AREIA_Y), BEIRA = wy(MAPA.mar.y), X0 = wx(-MARGEM), X1 = wx(MAPA.w + MARGEM), FUNDO = MH;
            // fase 67: a areia vai de ponta a ponta, como o mar (nas laterais, coqueiros e pedras em vez de mata)
            ret(X0, AREIA, X1 - X0, BEIRA - AREIA, '#ecd59a');
            for (let k = 0; k < 1250; k++) ret(X0 + Math.floor(r() * (X1 - X0)), AREIA + Math.floor(r() * (BEIRA - AREIA)), 1, 1, r() < 0.5 ? '#d9bd7c' : '#f6e6b8');
            for (let x = X0; x < X1; x += 2) {   // areia molhada (fase 77b: a borda de cima irregular, nada de linha reta)
                const topo = BEIRA - 5 + Math.round(Math.sin(x / 11) * 1.2 + Math.sin(x / 5.3) * 0.6);
                ret(x, topo, 2, BEIRA - topo, '#d2b06c');
            }
            // o mar
            ret(X0, BEIRA, X1 - X0, FUNDO - BEIRA, '#3a7cc4');
            ret(X0, BEIRA + T * 2, X1 - X0, FUNDO - BEIRA - T * 2, '#336fb3');
            ret(X0, BEIRA + T * 5, X1 - X0, FUNDO - BEIRA - T * 5, '#2b5f9e');
            for (let k = 0; k < 420; k++) {
                const x = X0 + Math.floor(r() * (X1 - X0)), y = BEIRA + 6 + Math.floor(r() * (FUNDO - BEIRA - 8));
                ret(x, y, 3 + Math.floor(r() * 4), 1, r() < 0.65 ? '#5d9fe0' : '#2f6aac');
            }
            // (fase 76: a espuma da beira vai e volta, desenhada a cada quadro em desenharMarVivo; fase 77b: a
            // beira inteira, de BEIRA − 3 a BEIRA + 5, também: a areia molhada aparece quando a onda volta)
        }
        // o lugar do píer: estacas e uma plaquinha até ser construído; depois, o píer de tábuas e o barco
        /* ---- fase 106: duas oficinas iguais lado a lado (mesma fileira, encostadas) viram uma oficina dupla,
           maior e com mais detalhe. Cada uma continua sendo ela (tocar, encher, pegar); só o desenho junta.
           Três seguidas: as duas primeiras juntam. Devolve "x,y" -> 'esq' (desenha a dupla) ou 'dir' (pula). ---- */
        let cachePares = { lista: null, mapa: new Map() };
        function paresOficinas(todas) {
            if (cachePares.lista === todas) return cachePares.mapa;
            const mapa = new Map(), ofs = todas.filter((c) => OFICINA_PRODUTO[c.tipo]).sort((a, b) => a.y - b.y || a.x - b.x);
            const em = new Map(ofs.map((c) => [c.x + ',' + c.y, c]));
            for (const c of ofs) {
                if (mapa.has(c.x + ',' + c.y)) continue;
                const d = em.get((c.x + 2) + ',' + c.y);
                if (d && d.tipo === c.tipo && !mapa.has(d.x + ',' + d.y)) { mapa.set(c.x + ',' + c.y, 'esq'); mapa.set(d.x + ',' + d.y, 'dir'); }
            }
            cachePares = { lista: todas, mapa };
            return mapa;
        }

        /* ---- fase 106: as barracas da feira (18 x 26: o toldo listrado passa um pouco por cima), cada uma com a
           sua cor, o balcão de tábua e a mercadoria em caixotes; no inverno, neve no toldo ---- */
        const cacheBarraca = new Map();
        const CORES_TOLDO = [['#d9452f', '#ffffff'], ['#3b6fb6', '#ffffff'], ['#4e974c', '#ffe08a'], ['#e38628', '#ffffff'], ['#9b4ca3', '#ffe08a'], ['#1f7f94', '#ffffff']];
        function barracaCanvas(k) {
            const chave = k + EST;
            if (cacheBarraca.has(chave)) return cacheBarraca.get(chave);
            const cv = document.createElement('canvas'); cv.width = 18; cv.height = 26;
            const g = cv.getContext('2d'), R = (x, y, w, h, c) => { g.fillStyle = c; g.fillRect(x, y, w, h); }, OL = '#3f2631';
            const [c1, c2] = CORES_TOLDO[k % CORES_TOLDO.length], r = rng(k * 313 + 9);
            R(1, 24, 17, 2, 'rgba(30,40,20,0.3)');   // a sombra
            // os postes
            R(1, 6, 3, 19, OL); R(2, 7, 1, 17, '#8a5a32'); R(14, 6, 3, 19, OL); R(15, 7, 1, 17, '#8a5a32');
            // o balcão de tábua com a mercadoria em cima
            R(0, 14, 18, 11, OL); R(1, 15, 16, 9, '#b8692f'); R(1, 15, 16, 2, '#d08a48');
            for (let x = 4; x < 17; x += 4) R(x, 17, 1, 7, '#8a4e22');
            R(1, 20, 16, 1, '#8a4e22');
            const BENS = [['#e8434a', '#ff7a7a'], ['#fdbe53', '#ffe08a'], ['#6ab04c', '#9ad57a'], ['#9b4ca3', '#c47ad4'], ['#e38628', '#f2a65a'], ['#8a5a32', '#c49a6a']];
            for (let j = 0; j < 3; j++) {   // três caixotes com fruta empilhada
                const bx = 2 + j * 5, [a, b] = BENS[(k * 2 + j) % BENS.length];
                R(bx - 1, 11, 6, 5, OL); R(bx, 12, 4, 3, '#c98a4a');
                R(bx, 10, 4, 2, a); R(bx + 1, 9, 2, 1, a); R(bx, 10, 1, 1, b); R(bx + 2, 9, 1, 1, b);
            }
            // o toldo listrado com a barra recortada
            R(0, 1, 18, 7, OL);
            for (let x = 1; x < 17; x++) R(x, 2, 1, 5, Math.floor((x - 1) / 3) % 2 ? c2 : c1);
            for (let x = 1; x < 17; x += 3) { R(x, 7, 2, 1, Math.floor((x - 1) / 3) % 2 ? c2 : c1); R(x, 8, 2, 1, OL); }
            R(1, 2, 16, 1, 'rgba(255,255,255,0.45)');
            if (EST === 'inverno') { R(0, 0, 18, 2, '#ffffff'); R(1, 2, 16, 1, '#e4edf6'); }
            else if (EST === 'outono' && r() < 0.7) R(3 + Math.floor(r() * 10), 2, 2, 1, '#e38628');
            // a plaquinha de preço pendurada
            R(13, 8, 4, 4, OL); R(14, 9, 2, 2, '#f4ecd8');
            cacheBarraca.set(chave, cv);
            if (cacheBarraca.size > 30) cacheBarraca.clear();
            return cv;
        }

        /* ---- fase 104: o navio atracado no píer. Visto de cima e de lado, como o resto da fazenda: o convés
           de tábuas, a amurada, o costado com o friso e as portinholas, os mastros com as velas, o cordame e
           a bandeira. Cresce com o nível do barco (bote, traineira, barco de pesca, pesqueiro e o navio
           oceânico, de dois mastros) e mostra as peças (motor, sonar, porão, rede e o kit de expedição).
           Fica pronto num canvas (um por barco) e balança na água a cada quadro. ---- */
        let barcoInfo = null;   // { nivel, pecas, visual } (null: sem barco)
        const cacheNavio = new Map();
        const NAVIOS = {
            1: { L: 34, deck: 9, lado: 6, mastros: [], casco: '#9e5f34', remos: true },
            2: { L: 50, deck: 12, lado: 8, mastros: [{ t: 0.6, alt: 26, velas: 0 }], cabine: { t: 0.14, w: 15, h: 7 }, casco: '#3b6fb6' },
            3: { L: 66, deck: 14, lado: 10, mastros: [{ t: 0.55, alt: 46, velas: 1 }], cabine: { t: 0.1, w: 17, h: 8 }, casco: '#c34b35', gurupes: 10 },
            4: { L: 84, deck: 17, lado: 12, mastros: [{ t: 0.5, alt: 60, velas: 2 }], tombadilho: 0.22, casco: '#25406e', gurupes: 16, bujarrona: true, janelas: true },
            5: { L: 108, deck: 21, lado: 16, mastros: [{ t: 0.36, alt: 72, velas: 2, latina: true }, { t: 0.66, alt: 82, velas: 3, gavea: true }],
                 tombadilho: 0.24, castelo: 0.12, casco: '#7a4422', gurupes: 24, bujarrona: true, canhoes: 4, friso: true, proa: true, janelas: true }
        };
        const PAL_BAND = { G: '#4e974c', Y: '#ffe08a', B: '#3b5dc9', K: '#1a1630', W: '#ffffff', R: '#d9452f', O: '#e38628' };
        const tom = (hex, f) => {
            const k = (v) => Math.max(0, Math.min(255, Math.round(f < 0 ? v * (1 + f) : v + (255 - v) * f)));
            const [r, g, b] = rgbDe(hex);
            return '#' + [k(r), k(g), k(b)].map((v) => v.toString(16).padStart(2, '0')).join('');
        };
        function navioCanvas(info) {
            const nv = Math.max(1, Math.min(5, info.nivel || 1)), N = NAVIOS[nv], pc = info.pecas || {}, vis = info.visual || {};
            const chave = nv + '|' + JSON.stringify(pc) + '|' + [vis.casco, vis.faixa, vis.bandeira].join(',');
            if (cacheNavio.has(chave)) return cacheNavio.get(chave);
            const CM = (window.FazendaMar && window.FazendaMar.CORES) || {};
            const casco = (vis.casco && vis.casco !== 'padrao' && CM[vis.casco]) || N.casco;
            const friso = (vis.faixa && vis.faixa !== 'padrao' && CM[vis.faixa]) || (N.friso ? '#e8a640' : '#f2f2f2');
            const OL = '#3f2631', MAD = '#6e3d1b', MADc = '#a8683a', VELA = '#f2ead6', VELAs = '#d6c8a8', CORDA = 'rgba(63,38,49,0.55)';
            const alt = Math.max(10, ...N.mastros.map((m) => m.alt)), ML = 6, gur = N.gurupes || 0;
            const W = ML + N.L + gur + 10, H = alt + N.deck + N.lado + 14;
            const cv = document.createElement('canvas');
            cv.width = W; cv.height = H;
            const g = cv.getContext('2d');
            const R = (x, y, w, h, c) => { g.fillStyle = c; g.fillRect(Math.round(x), Math.round(y), Math.max(1, Math.round(w)), Math.max(1, Math.round(h))); };
            const linha = (ax, ay, bx, by, c) => {   // linha de 1 px, sem borrar (cordas e mastros finos)
                const n = Math.max(Math.abs(bx - ax), Math.abs(by - ay)) | 0;
                for (let k = 0; k <= n; k++) R(ax + (bx - ax) * k / Math.max(1, n), ay + (by - ay) * k / Math.max(1, n), 1, 1, c);
            };
            const triangulo = (pts, c, sombra) => {   // pinta um triângulo linha por linha (borda dura, como pixel art)
                const ys = pts.map((p) => p[1]), y0 = Math.round(Math.min(...ys)), y1 = Math.round(Math.max(...ys));
                for (let y = y0; y <= y1; y++) {
                    const xs = [];
                    for (let k = 0; k < 3; k++) {
                        const [ax, ay] = pts[k], [bx, by] = pts[(k + 1) % 3];
                        if ((y >= Math.min(ay, by)) && (y <= Math.max(ay, by)) && ay !== by) xs.push(ax + (bx - ax) * (y - ay) / (by - ay));
                    }
                    if (xs.length < 2) continue;
                    const a = Math.round(Math.min(...xs)), b = Math.round(Math.max(...xs));
                    R(a, y, b - a + 1, 1, c);
                    if (sombra && b - a > 3) R(b - 1, y, 1, 1, sombra);
                    R(a, y, 1, 1, OL); R(b, y, 1, 1, OL);
                }
            };
            const x0 = ML, x1 = ML + N.L, cy = H - N.lado - N.deck / 2 - 7;
            const forma = (x) => {   // a largura do convés em cada coluna: popa redonda, proa fina
                const t = (x - x0) / N.L;
                return Math.min(Math.min(1, 0.7 + t * 3), Math.min(1, Math.pow(Math.max(0, (1 - t) / 0.32), 0.7)));
            };
            const topo = {}, base = {}, fundo = {};
            for (let x = x0; x < x1; x++) {
                const h = N.deck / 2 * forma(x);
                topo[x] = Math.round(cy - h); base[x] = Math.round(cy + h);
                fundo[x] = base[x] + Math.max(2, Math.round(N.lado * Math.sqrt(forma(x))));
            }
            const xDe = (t) => Math.round(x0 + t * N.L);
            // 1) o costado: o lado do casco virado para a gente, com as tábuas, o fundo escuro e o friso
            for (let x = x0; x < x1; x++) {
                const y0 = base[x] + 1, y1 = fundo[x], lado = y1 - y0;
                R(x, y0, 1, lado, casco);
                R(x, y0 + Math.round(lado * 0.6), 1, lado - Math.round(lado * 0.6), tom(casco, -0.28));
                for (let k = y0 + 4; k < y1 - 1; k += 3) R(x, k, 1, 1, tom(casco, -0.16));
                const ye = y0 + 4 + ((x >> 2) % 3) * 3;
                if ((x * 7) % 23 === 0 && ye + 2 < y1) R(x, ye, 1, 2, tom(casco, -0.35));   // emendas das tábuas
                R(x, y0 + 1, 1, 1, tom(casco, 0.18));
                if (lado > 4) { R(x, y0 + 2, 1, N.friso ? 2 : 1, friso); if (N.friso) R(x, y0 + 4, 1, 1, tom(friso, -0.35)); }
                if (N.friso && lado > 9 && x % 7 === 3) { R(x, y0 + 5, 1, 1, friso); R(x + 1, y0 + 6, 1, 1, tom(friso, -0.2)); }   // o arabesco dourado
                R(x, y1, 1, 1, OL);
            }
            for (let y = base[x0]; y <= fundo[x0]; y++) R(x0 - 1, y, 1, 1, OL);
            // 2) o convés: tábuas no comprimento, com as emendas desencontradas
            const TAB = ['#c27838', '#b8692f', '#ad6330'];
            for (let x = x0; x < x1; x++) {
                for (let y = topo[x] + 1; y < base[x]; y++) {
                    const fila = Math.floor((y - cy + 60) / 3), meio = (y - cy + 60) % 3 === 0;
                    R(x, y, 1, 1, meio ? '#8a4e22' : ((x + fila * 13) % 19 === 0 ? '#7a4422' : TAB[fila % 3]));
                }
            }
            // a amurada: a de lá é fina; a de cá, grossa e com luz em cima, e com os balaústres
            for (let x = x0; x < x1; x++) {
                R(x, topo[x] - 1, 1, 1, OL); R(x, topo[x], 1, 1, tom(casco, 0.12));
                R(x, base[x] - 1, 1, 1, tom(casco, 0.3)); R(x, base[x], 1, 1, tom(casco, 0.05));
                if (x % 4 === 0 && N.L > 40) R(x, base[x] - 2, 1, 1, tom(casco, -0.2));
            }
            for (let y = topo[x0]; y <= base[x0]; y++) R(x0 - 1, y, 1, 1, OL);
            // a popa alta (tombadilho) e o castelo da proa: um degrau mais claro, com a escadinha
            const degrau = (t0, t1) => {
                const a = xDe(t0), b = xDe(t1);
                for (let x = a; x < b; x++) for (let y = topo[x] + 1; y < base[x]; y++) R(x, y, 1, 1, (y - cy + 60) % 3 === 0 ? '#9a5a2a' : '#d08a48');
                const e = t0 === 0 ? b : a;
                for (let y = topo[e]; y <= base[e]; y++) R(e, y, 1, 1, OL);
                R(e + (t0 === 0 ? 1 : -2), cy - 2, 2, 5, '#8a4e22');
                for (let y = cy - 2; y < cy + 3; y += 2) R(e + (t0 === 0 ? 1 : -2), y, 2, 1, '#e0a060');
            };
            if (N.tombadilho) degrau(0, N.tombadilho);
            if (N.castelo) degrau(1 - N.castelo - 0.06, 0.94);
            // as escotilhas de grade (o porão: mais peças, mais escotilhas)
            const nEsc = nv >= 3 ? 1 + Math.min(2, pc.porao || 0) : 0;
            for (let k = 0; k < nEsc; k++) {
                const ex = xDe(0.42 + k * 0.12) - 4, ey = cy - 3;
                R(ex - 1, ey - 1, 10, 7, OL); R(ex, ey, 8, 5, '#3a2416');
                for (let gx = ex + 1; gx < ex + 8; gx += 2) R(gx, ey, 1, 5, '#7a4a2a');
                for (let gy = ey + 1; gy < ey + 5; gy += 2) R(ex, gy, 8, 1, '#7a4a2a');
            }
            // a cabine (traineira e barco de pesca): o teto e a frente com janelinhas
            if (N.cabine) {
                const cx = xDe(N.cabine.t), cw = N.cabine.w, ch = N.cabine.h;
                R(cx - 1, cy - ch - 3, cw + 2, ch + 6, OL);
                R(cx, cy - ch - 2, cw, 3, '#dfe6ee'); R(cx, cy - ch - 2, cw, 1, '#ffffff');
                R(cx, cy - ch + 1, cw, ch + 1, '#f4f1e6'); R(cx + cw - 2, cy - ch + 1, 2, ch + 1, '#d8d2c0');
                for (let wx2 = cx + 2; wx2 < cx + cw - 3; wx2 += 4) { R(wx2, cy - ch + 3, 3, 3, '#3b5dc9'); R(wx2, cy - ch + 3, 1, 1, '#9fd3f5'); }
                if ((pc.sonar || 0) > 0) { R(cx + cw - 6, cy - ch - 7, 5, 2, '#c0cbdc'); R(cx + cw - 4, cy - ch - 5, 1, 3, '#566c86'); R(cx + cw - 6, cy - ch - 8, 5, 1, OL); }
            }
            // o timão dourado no tombadilho e a lanterna da popa
            if (N.tombadilho) {
                const tx = xDe(N.tombadilho * 0.62), ty = cy - 5;
                R(tx - 3, ty - 3, 7, 7, OL); R(tx - 2, ty - 2, 5, 5, '#e8a640'); R(tx - 1, ty - 1, 3, 3, '#7a4422'); R(tx, ty, 1, 1, '#ffe08a');
                R(tx, ty + 4, 1, 4, '#5a3a20');
                R(x0 + 1, topo[x0 + 1] - 6, 3, 5, OL); R(x0 + 2, topo[x0 + 1] - 5, 1, 3, '#ffe08a');
                if ((pc.sonar || 0) > 0) { const sx = xDe(N.tombadilho * 0.3); R(sx - 2, cy - 9, 5, 2, '#c0cbdc'); R(sx, cy - 7, 1, 4, '#566c86'); R(sx - 2, cy - 10, 5, 1, OL); }
            }
            // barris e caixas no convés (o kit de expedição traz mais: baú, mapa e o tanque extra)
            const barril = (bx, by) => { R(bx - 1, by - 1, 6, 7, OL); R(bx, by, 4, 5, '#9a5a32'); R(bx, by, 1, 5, '#c07a48'); R(bx, by + 1, 4, 1, '#5a3a28'); R(bx, by + 3, 4, 1, '#5a3a28'); };
            const caixa = (bx, by) => { R(bx - 1, by - 1, 7, 7, OL); R(bx, by, 5, 5, '#c98a4a'); R(bx, by, 5, 1, '#e0a868'); R(bx + 2, by, 1, 5, '#8a5a2a'); R(bx, by + 2, 5, 1, '#8a5a2a'); };
            if (nv >= 3) { barril(xDe(0.78), cy - 4); caixa(xDe(0.84), cy - 1); }
            if (nv >= 4) barril(xDe(0.3), cy + 1);
            if ((pc.expedicao || 0) > 0) {
                barril(xDe(0.88) - 6, cy + 2); caixa(xDe(0.58), cy + 1);
                const bx = xDe(0.24), by = cy - 2;   // o baú com o mapa
                R(bx - 1, by - 1, 8, 6, OL); R(bx, by, 6, 4, '#7a3a1a'); R(bx, by, 6, 1, '#e8a640'); R(bx + 2, by + 1, 2, 2, '#ffe08a');
            }
            // a rede pendurada na amurada
            if ((pc.rede || 0) > 0 && nv >= 2) {
                const rx = xDe(0.68);
                for (let y = 0; y < 6; y++) for (let x = 0; x < 9; x++) if ((x + y) % 2 === 0) R(rx + x, base[rx] + 1 + y, 1, 1, 'rgba(233,226,200,0.85)');
            }
            // os remos do bote e o motor de popa
            if (N.remos) {   // os dois remos no banco, com a pá para fora
                R(xDe(0.3), cy - 1, 1, 3, '#7a4a2a'); R(xDe(0.62), cy - 1, 1, 3, '#7a4a2a');
                linha(xDe(0.4), cy, xDe(0.4) - 5, base[xDe(0.4)] + 4, '#c98a4a'); R(xDe(0.4) - 7, base[xDe(0.4)] + 4, 3, 2, '#c98a4a');
            }
            if ((pc.motor || 0) > 0 && nv <= 3) { R(x0 - 5, cy - 3, 5, 7, OL); R(x0 - 4, cy - 2, 3, 5, '#566c86'); R(x0 - 4, cy - 2, 3, 1, '#c0cbdc'); R(x0 - 3, cy + 4, 1, fundo[x0] - cy - 2, '#3f2631'); }
            // o costado da popa com as janelas douradas (pesqueiro e navio)
            if (N.janelas) for (let k = 0; k < 3; k++) { const jx = x0 + 3 + k * 4, jy = base[jx] + 5; R(jx - 1, jy - 1, 4, 4, '#e8a640'); R(jx, jy, 2, 2, '#ffe08a'); }
            // as portinholas com os canhões (navio) ou as escotilhas redondas
            if (N.canhoes) for (let k = 0; k < N.canhoes; k++) {
                const px = xDe(0.32 + k * 0.13), py = base[px] + 6;
                R(px - 2, py - 2, 6, 5, tom(friso, -0.1)); R(px - 1, py - 1, 4, 3, '#1a1630'); R(px, py, 3, 1, '#3a3a48'); R(px + 3, py, 2, 1, '#566c86');
            } else if (nv >= 2) for (let k = 0; k < 3; k++) { const px = xDe(0.4 + k * 0.14), py = base[px] + 5; R(px - 1, py - 1, 4, 4, OL); R(px, py, 2, 2, '#9fd3f5'); }
            // a âncora na proa
            if (nv >= 3) {
                const ax = xDe(0.86), ay = base[ax] + 3;
                R(ax, ay, 1, 6, '#566c86'); R(ax - 2, ay + 1, 5, 1, '#566c86'); R(ax - 2, ay + 5, 1, 2, '#566c86'); R(ax + 2, ay + 5, 1, 2, '#566c86'); R(ax - 1, ay + 6, 3, 1, '#566c86');
                R(ax, ay - 1, 1, 1, '#c0cbdc');
            }
            // o gurupés (o pau da proa), a figura de proa e a bujarrona (a vela triangular da frente)
            const ponta = { x: x1 + gur, y: cy - 4 - Math.round(gur / 5) };
            if (gur) { linha(x1 - 3, cy - 1, ponta.x, ponta.y, '#5a3a20'); linha(x1 - 3, cy, ponta.x, ponta.y + 1, MAD); }
            if (N.proa) { R(x1 - 1, cy - 2, 3, 4, OL); R(x1, cy - 1, 2, 3, '#ffd75e'); R(x1 + 1, cy - 1, 1, 1, '#1a1630'); }
            // 3) os mastros, as vergas e as velas (a bujarrona primeiro: as velas quadradas ficam na frente dela)
            const topos = [];
            if (N.bujarrona && gur && N.mastros.length) {
                const mf = N.mastros[N.mastros.length - 1], mx = xDe(mf.t), top = cy - mf.alt;
                triangulo([[mx + 2, top + 12], [ponta.x - 2, ponta.y], [mx + 2, cy - 12]], VELA, VELAs);
            }
            N.mastros.forEach((m, mi) => {
                const mx = xDe(m.t), top = cy - m.alt;
                topos.push({ x: mx, y: top });
                R(mx - 2, top, 4, cy - top + 1, OL); R(mx - 1, top + 1, 2, cy - top - 1, MAD); R(mx, top + 1, 1, cy - top - 1, MADc);
                for (let y = top + 10; y < cy - 6; y += 14) R(mx - 2, y, 4, 1, '#c0cbdc');   // as braçadeiras de ferro
                if (m.gavea) { R(mx - 5, top + 12, 11, 4, OL); R(mx - 4, top + 13, 9, 2, '#8a4e22'); R(mx - 4, top + 13, 9, 1, '#c27838'); }   // o cesto da gávea
                const area = m.alt - 16, hv = m.velas ? Math.floor(area / m.velas) : 0;
                for (let k = 0; k < m.velas; k++) {
                    const yv = top + 6 + k * hv, w = (nv === 5 ? 12 : 14) + (k + (3 - m.velas)) * (nv === 5 ? 5 : 7) + nv;
                    R(mx - w / 2 - 1, yv - 1, w + 2, 3, OL); R(mx - w / 2, yv, w, 1, '#5a3a20');   // a verga
                    const h = hv - 4, curva = Math.max(1, Math.round(h / 6));
                    for (let y = 0; y < h; y++) {
                        const inc = Math.round(Math.sin((y / h) * Math.PI) * curva), a = mx - w / 2 - inc + 1, b = mx + w / 2 + inc - 1;
                        R(a, yv + 2 + y, b - a, 1, VELA); R(b - 3, yv + 2 + y, 3, 1, VELAs); R(a - 1, yv + 2 + y, 1, 1, OL); R(b, yv + 2 + y, 1, 1, OL);
                        if (y % 4 === 1) for (let sx = a + 3; sx < b - 3; sx += 5) R(sx, yv + 2 + y, 1, 1, '#e4d9bf');   // as costuras
                        if (nv === 5 && k === m.velas - 1 && y >= h - 4 && y < h - 2) R(a + 1, yv + 2 + y, b - a - 2, 1, friso === '#f2f2f2' ? '#d9452f' : tom(friso, -0.05));   // a faixa da vela de baixo
                    }
                    R(mx - w / 2, yv + 2 + h, w, 1, OL);
                }
                R(mx - 1, top, 2, 2, MADc);
                // a vela latina (triangular) atrás do mastro da popa
                if (m.latina) triangulo([[mx - 3, top + 18], [mx - 3, cy - 9], [mx - 3 - Math.round(N.L * 0.15), cy - 9]], VELA, VELAs);
            });
            // o cordame: dos topos dos mastros até a proa e até a popa
            topos.forEach((p, k) => {
                linha(p.x, p.y + 2, k === topos.length - 1 && gur ? ponta.x : xDe(0.92), k === topos.length - 1 && gur ? ponta.y : cy - 2, CORDA);
                linha(p.x, p.y + 2, k === 0 ? x0 + 2 : topos[k - 1].x, k === 0 ? topo[x0 + 2] : topos[k - 1].y + 4, CORDA);
                for (let d = -1; d <= 1; d += 2) linha(p.x, p.y + 4, p.x + d * 6, base[p.x] - 1, CORDA);
            });
            // a bandeira no mastro mais alto
            if (topos.length) {
                const p = topos.reduce((a, b) => (b.y < a.y ? b : a)), padrao = (window.FazendaMar && window.FazendaMar.BANDEIRAS || {})[vis.bandeira];
                R(p.x, p.y - 8, 1, 8, OL);
                if (padrao) padrao.forEach((lin, y) => [...lin].forEach((c, x) => R(p.x + 1 + x, p.y - 8 + y, 1, 1, PAL_BAND[c] || '#fff')));
                else { R(p.x + 1, p.y - 8, 6, 3, '#d9452f'); R(p.x + 7, p.y - 8, 2, 1, '#d9452f'); R(p.x + 7, p.y - 6, 2, 1, '#d9452f'); R(p.x + 1, p.y - 8, 6, 1, '#f07a5a'); }
            }
            cv.ml = ML; cv.agua = H - 7; cv.casco = { x0, x1, fundo }; cv.conves = Math.round(cy);
            if (cacheNavio.size > 12) cacheNavio.clear();
            cacheNavio.set(chave, cv);
            return cv;
        }
        // onde o navio fica: o casco começa logo depois do píer e a linha d'água fica na fileira 40
        const navioPos = (cv) => ({ x: wx(MAPA.pier.x + MAPA.pier.w) + 4 - cv.ml, y: wy(40) + 11 - cv.agua });
        function desenharNavio(pe, tempo) {
            if (!barcoInfo || !pierPronto || zonasAtuais < 7) return;
            const cv = navioCanvas(barcoInfo), p = navioPos(cv), sobe = Math.round(Math.sin(tempo / 760) * 0.7);
            // a sombra do casco na água e a espuma batendo, que não sobem junto
            const { x0, x1, fundo } = cv.casco;
            q.globalAlpha = 0.28; q.fillStyle = '#1a2a4a';
            for (let x = x0; x < x1; x += 1) q.fillRect(p.x + x - 2, p.y + fundo[x] + 1, 1, 3);
            q.globalAlpha = 1;
            for (let x = x0; x < x1; x += 2) {
                const f = (tempo / 260 + x * 0.37) % 6;
                if (f < 3) { q.fillStyle = f < 1.5 ? '#e8f2fb' : '#bcd8f2'; q.fillRect(p.x + x + (f < 1.5 ? 0 : 1), p.y + fundo[x] + 1, 2, 1); }
            }
            pe.push({ img: cv, x: p.x, y: p.y + sobe, ordem: p.y + cv.agua, flip: false, bob: 0 });
        }

        function desenharPier() {
            const P = MAPA.pier, ret = (x, y, w, h, cor) => { f.fillStyle = cor; f.fillRect(x, y, w, h); };
            const x0 = wx(P.x) + 6, x1 = wx(P.x + P.w) - 6, y0 = wy(P.y) + 4, y1 = wy(P.y + P.h) - 2;
            if (!pierPronto) {
                [[x0, wy(38)], [x1 - 3, wy(38)], [x0, wy(40)], [x1 - 3, wy(40)]].forEach(([x, y]) => {
                    ret(x, y, 3, 10, '#5a3a20'); ret(x, y, 1, 10, '#7a5230'); ret(x - 1, y + 9, 5, 2, '#bcd8f2');
                });
                tile(f, 83, wx(P.x + 1), wy(P.y), false, 'town');   // plaquinha: "o píer vai aqui"
                return;
            }
            // fase 104: o píer caprichado (pilares com musgo, tábuas de tons diferentes com os pregos, os frades de
            // amarração com tampa e, na entrada, barris, caixas e um rolo de corda)
            const r = rng(4242), OL = '#3f2631';
            const pilar = (x, y) => {
                ret(x - 3, y, 6, 15, OL); ret(x - 2, y + 1, 4, 13, '#6e3d1b'); ret(x - 2, y + 1, 1, 13, '#9a5a32');
                ret(x - 2, y + 9, 4, 3, '#4e7a3a'); ret(x - 2, y + 9, 4, 1, '#7aa84e');                     // o musgo na linha d'água
                ret(x - 4, y + 13, 8, 2, '#bcd8f2'); ret(x - 5, y + 14, 2, 1, '#e8f2fb'); ret(x + 3, y + 14, 2, 1, '#e8f2fb');
            };
            for (let y = wy(37); y < y1 + 2; y += T * 2) { pilar(x0, y + 4); pilar(x1, y + 4); }
            ret(x0 - 1, y0 - 1, x1 - x0 + 2, y1 - y0 + 2, OL);
            const TONS = ['#b8692f', '#a95f2a', '#c27838', '#b06530'];
            for (let y = y0, k = 0; y < y1; y += 4, k++) {
                ret(x0, y, x1 - x0, 3, TONS[Math.floor(r() * TONS.length)]);
                ret(x0, y, x1 - x0, 1, '#d08a48');                                                          // a luz na borda da tábua
                ret(x0, y + 3, x1 - x0, 1, '#6e3d1b');                                                      // a fresta
                const emenda = x0 + 6 + Math.floor(r() * (x1 - x0 - 12));
                ret(emenda, y, 1, 3, '#7a4422');
                ret(x0 + 2, y + 1, 1, 1, '#4a2f1a'); ret(x1 - 3, y + 1, 1, 1, '#4a2f1a');                // os pregos
                if (r() < 0.25) ret(x0 + 5 + Math.floor(r() * (x1 - x0 - 10)), y + 2, 2, 1, '#8a4e22');  // um nó na madeira
            }
            ret(x0, y0, 2, y1 - y0, '#6e3d1b'); ret(x1 - 2, y0, 2, y1 - y0, '#6e3d1b');
            // os frades de amarração (o navio fica preso neles), com a tampa redonda
            const frade = (x, y) => { ret(x - 3, y - 2, 6, 7, OL); ret(x - 2, y + 1, 4, 3, '#6e3d1b'); ret(x - 2, y - 1, 4, 2, '#e38628'); ret(x - 1, y - 1, 2, 1, '#fdbe53'); };
            for (let y = wy(37) + 6; y < y1 - 4; y += T + 4) frade(x1 - 4, y);
            frade(x0 + 3, wy(39) + 2);
            // a corda do frade até o navio (o navio fica do lado direito)
            for (let k = 0; k < 10; k++) ret(x1 - 2 + k, wy(38) + 8 + Math.round(Math.sin(k / 9 * Math.PI) * 3), 1, 1, '#d8c8a0');
            // na entrada do píer, na areia: barris, caixas e um rolo de corda
            const barril = (x, y) => {
                ret(x - 1, y - 1, 10, 12, OL); ret(x, y, 8, 10, '#9a5a32'); ret(x, y, 2, 10, '#c07a48'); ret(x + 6, y, 2, 10, '#7a4422');
                ret(x, y + 2, 8, 1, '#5a3a28'); ret(x, y + 7, 8, 1, '#5a3a28'); ret(x + 1, y, 6, 2, '#b4673a'); ret(x + 2, y, 4, 1, '#d08a48');
            };
            const caixa = (x, y) => {
                ret(x - 1, y - 1, 12, 12, OL); ret(x, y, 10, 10, '#c98a4a'); ret(x, y, 10, 2, '#e0a868');
                ret(x, y + 4, 10, 1, '#8a5a2a'); ret(x + 4, y + 2, 1, 8, '#8a5a2a'); ret(x + 1, y + 3, 1, 1, '#3f2631'); ret(x + 8, y + 3, 1, 1, '#3f2631');
            };
            barril(x0 - 14, wy(35) + 2); barril(x0 - 22, wy(35) + 8); caixa(x1 + 3, wy(35) + 3); caixa(x1 + 5, wy(35) - 6);
            // o rolo de corda
            const rx = x0 - 12, ry = wy(36) + 6;
            ret(rx - 1, ry - 1, 10, 7, OL); ret(rx, ry, 8, 5, '#d8c8a0'); ret(rx + 2, ry + 1, 4, 3, '#a8986a'); ret(rx + 3, ry + 2, 2, 1, '#6e5a48');
            // (fase 104: o barco atracado agora é o navio, desenhado a cada quadro em desenharNavio)
        }

        /* ---- o lago: tanque com borda de pedras, água funda com sombras de peixe, rede
           pendurada em dois postes e um balde no canto. O Bira pesca da grama, à esquerda. ---- */
        const LAGO = MAPA.lago;
        const lagoNaTela = () => zonasAtuais >= 3;
        const TANQUE = { x0: wx(LAGO.x + 1), y0: wy(LAGO.y) + 14, x1: wx(LAGO.x + LAGO.w), y1: wy(LAGO.y + LAGO.h), borda: 9 };
        function desenharLago() {
            const { x0, y0, x1, y1, borda } = TANQUE;
            const r = rng(7171);
            const ret = (x, y, w, h, cor) => { f.fillStyle = cor; f.fillRect(x, y, w, h); };
            // pedras da borda: argamassa escura e pedras de tamanhos e cores variados
            ret(x0, y0, x1 - x0, y1 - y0, '#4a3b35');
            const CORES = [['#a39388', '#c2b4a8', '#7d6f66'], ['#8b7d72', '#ab9d92', '#6a5d55'], ['#b88a7a', '#d4a898', '#8e6658'], ['#958a80', '#b5aaa0', '#71675f']];
            const pedra = (x, y, w, h) => {
                const [c, cl, cs] = CORES[Math.floor(r() * CORES.length)];
                ret(x + 1, y + 1, w - 2, h - 2, c);
                ret(x + 1, y + 1, w - 2, 1, cl); ret(x + 1, y + 1, 1, h - 2, cl);           // luz em cima e à esquerda
                ret(x + 1, y + h - 2, w - 2, 1, cs); ret(x + w - 2, y + 1, 1, h - 2, cs);   // sombra embaixo e à direita
            };
            const fileira = (a0, a1, fixo, horizontal) => {
                for (let a = a0; a < a1;) {
                    let tam = 9 + Math.floor(r() * 5);
                    if (a1 - a - tam < 7) tam = a1 - a;                                        // a última não fica miudinha
                    if (horizontal) pedra(a, fixo, tam, borda); else pedra(fixo, a, borda, tam);
                    a += tam;
                }
            };
            fileira(x0, x1, y0, true); fileira(x0, x1, y1 - borda, true);
            fileira(y0 + borda, y1 - borda, x0, false); fileira(y0 + borda, y1 - borda, x1 - borda, false);
            // cantos arredondados: volta a grama do fundo
            const grama = (x, y) => f.drawImage(fundoGrama, x, y, 1, 1, x, y, 1, 1);
            [[x0, y0], [x0 + 1, y0], [x0, y0 + 1], [x1 - 1, y0], [x1 - 2, y0], [x1 - 1, y0 + 1],
                [x0, y1 - 1], [x0 + 1, y1 - 1], [x0, y1 - 2], [x1 - 1, y1 - 1], [x1 - 2, y1 - 1], [x1 - 1, y1 - 2]].forEach(([x, y]) => grama(x, y));
            // água funda: sombra da borda em cima e à esquerda, ondinhas e sombras de peixe
            const ax0 = x0 + borda, ay0 = y0 + borda, ax1 = x1 - borda, ay1 = y1 - borda;
            ret(ax0, ay0, ax1 - ax0, ay1 - ay0, '#3a7cc4');
            ret(ax0, ay0, ax1 - ax0, 3, '#2b5f9e'); ret(ax0, ay0, 2, ay1 - ay0, '#2f6aac');
            for (let k = 0; k < 18; k++) {
                const x = ax0 + 3 + Math.floor(r() * (ax1 - ax0 - 8)), y = ay0 + 5 + Math.floor(r() * (ay1 - ay0 - 8));
                ret(x, y, 2 + Math.floor(r() * 3), 1, r() < 0.6 ? '#5d9fe0' : '#2f6aac');
            }
            // (fase 76: as sombras de peixe nadam, desenhadas a cada quadro em desenharAguaViva)
            // balde de madeira no canto de baixo, à direita
            const bx = x1 - 15, by = y1 - 16;
            ret(bx, by, 12, 13, '#3f2631');
            ret(bx + 1, by + 1, 10, 11, '#9a5a32'); ret(bx + 1, by + 1, 10, 3, '#5a3a28');
            ret(bx + 2, by + 2, 8, 1, '#3f2631');
            ret(bx + 1, by + 6, 10, 1, '#5a3a28'); ret(bx + 1, by + 10, 10, 1, '#5a3a28');
            ret(bx + 2, by + 4, 1, 7, '#c07a48');
            // rede pendurada entre dois postes, com um peixe preso
            const pe = x0 + 2, pd = x1 - 6, topo = wy(LAGO.y) + 1;
            [pe, pd].forEach((x) => { ret(x, topo, 4, y0 - topo + 8, '#3f2631'); ret(x + 1, topo + 1, 2, y0 - topo + 6, '#8a4a2b'); ret(x + 1, topo + 1, 1, y0 - topo + 6, '#b4673a'); });
            for (let x = pe + 4; x < pd; x++) {
                const t = (x - pe - 4) / (pd - pe - 4), yc = topo + 2 + Math.round(Math.sin(Math.PI * t) * 4);
                const fundoRede = topo + 6 + Math.round(Math.sin(Math.PI * t) * 7);
                ret(x, yc, 1, 1, '#c99a4a');
                for (let y = yc + 1; y <= fundoRede; y++) if ((x + y) % 3 === 0 || (x - y) % 3 === 0) ret(x, y, 1, 1, '#e8c070');
            }
            const mx = Math.round((pe + pd) / 2) - 4, my = topo + 8;
            ret(mx, my, 9, 4, '#3f2631'); ret(mx + 1, my + 1, 6, 2, '#c0cbdc'); ret(mx + 7, my, 2, 4, '#fdbe53');
        }

        /* ---- fase 74b: ninguém anda na água ----
           A água do lago (dentro das pedras), o laguinho de cada lago dos patos e o mar. Quem anda mira o
           pé (x + 8, y + 14); se a linha reta corta uma água, vai antes até o canto dela, por fora. Destino
           na água vai para a beira. Só os patos nadam (no laguinho deles). */
        // fase 76: o laguinho fica à esquerda e em cima; à direita e embaixo sobra chão para o cuidador andar
        const laguinhoPato = (c) => {   // (o desenho em desenharCercado usa este mesmo retângulo)
            const x = wx(c.x), y = wy(c.y);
            return { x0: x + 17, y0: y + 17, x1: x + 57, y1: y + 37 };
        };
        // fase 77b: o que ninguém pisa (e) é a água com a borda dela (as pedras do lago, a grama do laguinho)
        // e a folga do boneco: o desenho tem 16 px de largura (8 para cada lado do pé) e o pé fica no fim
        // dele. Antes a folga era de 5 px em volta da água de dentro, e quem andava ficava em cima das pedras,
        // com meio corpo na água, parado nos cantos.
        const FOLGA = { lado: 9, cima: 3, baixo: 4 };
        const obstaculo = (r) => ({ x0: r.x0 - FOLGA.lado, y0: r.y0 - FOLGA.cima, x1: r.x1 + FOLGA.lado, y1: r.y1 + FOLGA.baixo });
        let cacheAguas = { chave: null, lista: [] };
        function aguas() {
            const cons = construcoesFn() || [];
            const patos = cons.filter((c) => CERCADOS[c.tipo] && CERCADOS[c.tipo].chao === 'lago');
            const chave = zonasAtuais + '|' + patos.map((c) => c.x + ',' + c.y).join(';');
            if (cacheAguas.chave === chave) return cacheAguas.lista;
            const lista = patos.map((c) => {   // o laguinho e a margem de grama dele (desenharCercado)
                const L = laguinhoPato(c);
                return { ...L, e: obstaculo({ x0: L.x0 - 1, y0: L.y0 - 2, x1: L.x1 + 1, y1: L.y1 + 2 }) };
            });
            if (lagoNaTela()) lista.push({ x0: TANQUE.x0 + TANQUE.borda, y0: TANQUE.y0 + TANQUE.borda, x1: TANQUE.x1 - TANQUE.borda, y1: TANQUE.y1 - TANQUE.borda,
                                          lago: true, e: obstaculo(TANQUE) });   // (o tanque inteiro, com as pedras)
            const mar = wy(MAPA.mar.y);   // o mar: a onda sobe até 3 px na areia
            lista.push({ x0: -1e6, y0: mar, x1: 1e6, y1: 1e6, e: { x0: -1e6, y0: mar - 6, x1: 1e6, y1: 1e6 } });
            cacheAguas = { chave, lista };
            return lista;
        }
        const dentroDe = (r, x, y, m) => x > r.x0 - m && x < r.x1 + m && y > r.y0 - m && y < r.y1 + m;
        const naAgua = (x, y) => aguas().some((r) => dentroDe(r, x + 8, y + 12, -1));   // o pé (quase no fim do boneco) está na água
        const aguaEm = (x, y, m = 0) => aguas().find((r) => dentroDe(r.e, x + 8, y + 14, m)) || null;
        // um destino que caiu na água vai para a beira mais perto, por fora (e não noutra água)
        function foraDaAgua(x, y) {
            const r = aguaEm(x, y);
            if (!r) return null;
            const px = x + 8, py = y + 14, E = r.e;
            let melhor = null, dmin = Infinity;
            for (const [ox, oy] of [[E.x0 - 2, py], [E.x1 + 2, py], [px, E.y0 - 2], [px, E.y1 + 2]]) {
                if (Math.abs(ox) > 1e5 || Math.abs(oy) > 1e5 || aguaEm(ox - 8, oy - 14)) continue;
                const d = Math.hypot(ox - px, oy - py);
                if (d < dmin) { dmin = d; melhor = [ox, oy]; }
            }
            if (!melhor) melhor = [px, E.y0 - 2];   // (sem saída livre: para cima)
            return { x: melhor[0] - 8, y: melhor[1] - 14 };
        }
        // um passo de quem anda (ajudante, bicho, fazendeiro, visita); devolve dx do passo.
        // fase 79: anda reto, entrando na água se ela estiver no caminho (fica pela metade, como o pato).
        // Antes desviava pelos cantos e, perto da cerca do cercado, ficava preso tremendo na beira.
        function passoSeco(a, vel, dt) {
            const ex = a.tx - a.x, ey = a.ty - a.y, ed = Math.hypot(ex, ey);
            if (ed < 0.01) { a.x = a.tx; a.y = a.ty; return 0; }
            const passo = Math.min(ed, vel * dt / 1000);
            a.x += ex / ed * passo; a.y += ey / ed * passo;
            return ex;
        }

        /* ---- fase 76: a água viva (por cima do fundo, a cada quadro) ----
           Brilhinhos que acendem e apagam no mesmo lugar, sombras de peixe nadando devagar de um lado
           para o outro (o rabo mexe) e, de vez em quando, a rodinha de um peixe que pulou. No mar, a
           espuma vai e volta na areia, as cristas brilham e passam cardumes. */
        function sombraPeixe(x, y, dir, cor, rabo, tam = 1) {
            const R = (a, b, w, h) => { q.fillStyle = cor; q.fillRect(Math.round(a), Math.round(b), w, h); };
            const c = 5 * tam + 2, h = tam > 1 ? 4 : 3;
            R(x, y, c, h); R(x + 1, y - 1, c - 2, 1); R(x + 1, y + h, c - 2, 1);
            const tx = dir > 0 ? x - 2 : x + c;   // o rabo atrás, abrindo e fechando
            if (rabo) R(tx, y - 1, 2, h + 2); else R(tx, y, 2, h);
        }
        function pontosOval(cx, cy, rx, ry) {
            const pts = new Set();
            for (let k = 0; k < 24; k++) {
                const ang = k / 24 * Math.PI * 2;
                pts.add(Math.round(cx + Math.cos(ang) * rx) + ',' + Math.round(cy + Math.sin(ang) * ry));
            }
            return [...pts].map((p) => p.split(',').map(Number));
        }
        function desenharAguaViva(tempo, so) {   // so = um laguinho só (o dos patos, desenhado no cercado)
            for (const r of so ? [so] : aguas().filter((k) => k.lago)) {
                const w = r.x1 - r.x0, h = r.y1 - r.y0, sem = Math.abs(Math.round(r.x0 * 7 + r.y0 * 13));
                q.save(); q.beginPath(); q.rect(r.x0, r.y0, w, h); q.clip();
                // peixes: cada um numa faixa, ida e volta suave (vira na ponta)
                const nPeixes = so ? 1 : 3;
                for (let n = 0; n < nPeixes; n++) {
                    const per = 14000 + n * 5300, f = ((tempo + n * 4100 + sem) % (2 * per)) / per;   // 0..2
                    const u = f < 1 ? f : 2 - f, ida = f < 1, ease = (1 - Math.cos(Math.PI * u)) / 2;
                    const fx = r.x0 + 4 + ease * (w - 14), fy = r.y0 + 6 + ((n * 11 + 3) % Math.max(4, h - 12)) + Math.sin(tempo / 1700 + n) * 1.5;
                    sombraPeixe(fx, fy, ida ? 1 : -1, so ? '#4a86c8' : '#2d64a6', Math.floor(tempo / 260 + n) % 2);
                }
                // brilhinhos: acendem e apagam no lugar, cada um no seu ritmo
                const nBrilhos = Math.max(2, Math.floor(w * h / 500));
                for (let n = 0; n < nBrilhos; n++) {
                    const per = 2600 + (n % 5) * 370, ciclo = Math.floor((tempo + n * 733) / per), t = ((tempo + n * 733) % per) / per;
                    if (t > 0.45) continue;
                    const rr = rng(ciclo * 97 + n * 13 + sem);
                    const bx = Math.round(r.x0 + 3 + rr() * (w - 8)), by = Math.round(r.y0 + 3 + rr() * (h - 6));
                    q.fillStyle = '#8fc1ef'; q.fillRect(bx, by, 3, 1);
                    if (t > 0.12 && t < 0.32) { q.fillStyle = '#e8f4ff'; q.fillRect(bx + 1, by, 1, 1); }
                }
                // a rodinha do peixe que pulou: uma a cada ~6 s, abrindo e sumindo
                if (!so) {
                    const per = 6100, t = (tempo + sem * 3) % per;
                    if (t < 900) {
                        const rr = rng(Math.floor((tempo + sem * 3) / per) + sem);
                        const cx = r.x0 + 10 + rr() * (w - 20), cy = r.y0 + 8 + rr() * (h - 16), raio = 1.5 + t / 900 * 5;
                        q.globalAlpha = 1 - t / 900;
                        q.fillStyle = '#cfe6fb';
                        for (const [px, py] of pontosOval(cx, cy, raio, raio * 0.5)) q.fillRect(px, py, 1, 1);
                        q.globalAlpha = 1;
                    }
                }
                q.restore();
            }
        }
        // o mar da praia (sem o lugar do píer e do barco, que estão no fundo)
        function desenharMarVivo(tempo) {
            const BEIRA = wy(MAPA.mar.y), X0 = wx(-MARGEM), X1 = wx(MAPA.w + MARGEM), FUNDO = MH;
            const semPier = (sempre) => {   // o recorte do mar, sem o píer e o barco (sempre: também as estacas de antes de construir)
                q.save(); q.beginPath(); q.rect(X0, BEIRA - 3, X1 - X0, FUNDO - BEIRA + 3);
                if (zonasAtuais >= 7 && (pierPronto || sempre)) q.rect(wx(MAPA.pier.x) - 2, wy(MAPA.pier.y), (MAPA.pier.w + 3) * T + 4, FUNDO - wy(MAPA.pier.y));
                q.clip('evenodd');
            };
            // fase 77b: a beira mexe de verdade. A cada quadro, coluna por coluna: a areia molhada até onde a
            // onda chegou, o mar dali para baixo e a espuma em cima (no fundo não sobra a linha reta)
            semPier(false);
            const vai = Math.sin(tempo / 1300) * 1.6;
            for (let x = X0; x < X1; x += 2) {
                const topo = BEIRA + Math.round(Math.sin(x / 9 + tempo / 900) * 1.2 + vai);   // de BEIRA − 3 a BEIRA + 3
                q.fillStyle = '#d2b06c'; q.fillRect(x, BEIRA - 3, 2, topo - BEIRA + 3);
                q.fillStyle = '#3a7cc4'; q.fillRect(x, topo, 2, BEIRA + 5 - topo);
                q.fillStyle = '#e8f2fb'; q.fillRect(x, topo, 2, 2);
                if ((x / 2 + Math.floor(tempo / 400)) % 5 < 2) { q.fillStyle = '#bcd8f2'; q.fillRect(x, topo + 3, 2, 1); }
            }
            q.restore();
            semPier(true);   // os peixes e as cristas, nunca por cima das estacas, do píer ou do barco
            // cardumes: sombras passando bem devagar lá no fundo
            for (let n = 0; n < 5; n++) {
                const per = 52000 + n * 9700, f = ((tempo + n * 17000) % (2 * per)) / per, u = f < 1 ? f : 2 - f;
                const fx = X0 + 20 + (1 - Math.cos(Math.PI * u)) / 2 * (X1 - X0 - 60), fy = BEIRA + T * 2 + ((n * 13) % (T * 2)) + Math.sin(tempo / 2100 + n) * 2;
                for (let m = 0; m < 3; m++) sombraPeixe(fx + m * 11 * (f < 1 ? -1 : 1), fy + (m % 2) * 5, f < 1 ? 1 : -1, '#285a99', Math.floor(tempo / 300 + n + m) % 2, 1);
            }
            // cristas que brilham e somem, cada uma no seu ritmo
            for (let n = 0; n < 70; n++) {
                const per = 3100 + (n % 7) * 410, ciclo = Math.floor((tempo + n * 521) / per), t = ((tempo + n * 521) % per) / per;
                if (t > 0.55) continue;
                const rr = rng(ciclo * 71 + n * 29);
                const cx = Math.round(X0 + rr() * (X1 - X0)), cy = Math.round(BEIRA + 8 + rr() * (FUNDO - BEIRA - 12));
                q.fillStyle = cy > BEIRA + T * 4 ? '#4c88cc' : '#6fa8e6';
                q.fillRect(cx, cy, 2, 1); q.fillRect(cx + 2, cy - 1, 2, 1); q.fillRect(cx + 4, cy, 1, 1);
                if (t > 0.15 && t < 0.35) { q.fillStyle = '#d6ebff'; q.fillRect(cx + 2, cy - 1, 1, 1); }
            }
            q.restore();
        }

        /* ---- animais ---- */
        let assinaturaCercados = '';
        function sincronizarAnimais() {
            // cercado novo, movido ou guardado: os bichos (e quem cuida deles) mudam de casa
            const cercados = (construcoesFn() || []).filter((k) => CERCADOS[k.tipo]).map((k) => k.tipo + '@' + k.x + ',' + k.y).join('|');
            if (cercados !== assinaturaCercados) { assinaturaCercados = cercados; atores.clear(); }
            const vistos = new Set();
            for (const v of animaisFn()) {
                vistos.add(v.id);
                let a = atores.get(v.id);
                if (!a || a.tipo !== v.tipo) {
                    const area = areaDe(v.tipo);
                    const r = rng(hash(v.id));
                    // nasce no lugar mais longe dos outros bichos (com fome eles ficam parados: nada de balão em cima de balão)
                    let x = area.x0, y = area.y0, folga = -1;
                    for (let k = 0; k < 10; k++) {
                        const cx = area.x0 + r() * (area.x1 - area.x0), cy = area.y0 + r() * (area.y1 - area.y0);
                        if (v.tipo !== 'pato' && aguaEm(cx, cy)) continue;   // fase 77b: só o pato nasce na água
                        let perto = Infinity;
                        for (const b of atores.values()) if (!b.ajudante && b.v) perto = Math.min(perto, Math.hypot((cx - b.x) * 0.8, cy - b.y));
                        if (perto > folga) { folga = perto; x = cx; y = cy; }
                    }
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
                // fase 66: descansando numa cama, ele vai até a porta da casa e entra (dormir = { x, y, casa });
                // sem cama, fica parado na sombra (dormir = { sombra: true }) com os zzz em cima
                if (atores.has(h.id) && (h.area === 'caminho' || h.area === 'energia')) atores.get(h.id).area = areaDe(h.area);   // fase 69
                if (atores.has(h.id)) { const b = atores.get(h.id); b.nivel = h.nivel || 1; if (JSON.stringify(b.dormir || null) !== JSON.stringify(h.dormir || null)) { b.dormir = h.dormir || null; if (!b.dormir) b.dentro = false; } continue; }
                const arte = AJUDANTE_ARTE[h.tipo] || MOCO;
                const area = areaDe(h.area);
                const r = rng(hash(h.id));
                const nasce = area.pontos && area.pontos[Math.floor(r() * area.pontos.length)];
                let x = nasce ? nasce.x : area.x0 + r() * (area.x1 - area.x0), y = nasce ? nasce.y : area.y0 + r() * (area.y1 - area.y0);
                const seco = foraDaAgua(x, y);   // fase 77b: nunca nasce dentro da água
                if (seco) { x = seco.x; y = seco.y; }
                atores.set(h.id, {
                    dormir: h.dormir || null, dentro: !!(h.dormir && !h.dormir.sombra && h.dormir.ja),   // (já estava lá dentro quando a tela abriu)
                    id: h.id, tipo: h.tipo, i: arte.i, p: arte.p, ferramenta: arte.ferramenta, ferramentaP: arte.ferramentaP, area, x, y, tx: x, ty: y,
                    visual: !!arte.visual, nivel: h.nivel || 1,   // fase 68: a moça com o jeito dela; o nível (raios do eletricista)
                    flip: r() < 0.5, espera: r() * 2000, vel: 12, ajudante: true
                });
            }
            for (const id of [...atores.keys()]) if (!vistos.has(id)) atores.delete(id);
        }

        // sorteia uns lugares na área do bicho e fica com o mais longe dos outros (ninguém amontoado)
        function lugarLivre(a) {
            if (a.area.pontos) {   // fase 69: o próximo pedaço da estradinha, perto (até uns 3 quadrados): segue o caminho
                const perto = a.area.pontos.filter((p) => { const d = Math.hypot(p.x - a.x, p.y - a.y); return d > 2 && d < 3.5 * T; });
                const longe = !perto.length || Math.random() < (a.area.salto || 0);   // (o Faísca às vezes vai para outro equipamento)
                const lista = longe ? a.area.pontos : perto;
                let alvo = null;
                for (let k = 0; k < 6 && (!alvo || aguaEm(alvo.x, alvo.y)); k++) {   // (fase 77b: nada de ponto na água)
                    const p = lista[Math.floor(Math.random() * lista.length)];
                    alvo = { x: p.x + (Math.random() - 0.5) * 6, y: p.y + (Math.random() - 0.5) * 4, olhar: p.olhar };
                }
                return alvo;
            }
            let melhor = null, folga = -1;
            const nada = a.tipo === 'pato' && !a.ajudante;   // fase 74b: só o pato vai para a água
            for (let k = 0, validos = 0; k < 12 && validos < (a.ajudante ? 1 : 6); k++) {
                const x = a.area.x0 + Math.random() * (a.area.x1 - a.area.x0), y = a.area.y0 + Math.random() * (a.area.y1 - a.area.y0);
                if (!nada && aguaEm(x, y) && k < 11) continue;
                validos++;
                let perto = Infinity;
                for (const b of atores.values()) {
                    if (b === a || b.ajudante || !b.v) continue;
                    perto = Math.min(perto, Math.hypot(x - b.tx, y - b.ty), Math.hypot(x - b.x, y - b.y));
                }
                if (perto > folga) { folga = perto; melhor = { x, y }; }
            }
            return melhor;
        }

        function mover(dt) {
            for (const a of atores.values()) {
                if (a.v && a.v.estado !== 'produzindo') continue;   // esperando o toque
                // fase 66: indo dormir: anda até a porta da casa e entra; na sombra, fica parado
                if (a.ajudante && a.dormir) {
                    if (a.dormir.sombra || a.dentro) continue;
                    const px = wx(a.dormir.x), py = wy(a.dormir.y) + 2, ddx = px - a.x, ddy = py - a.y, dd = Math.hypot(ddx, ddy);
                    if (dd < 1) { a.dentro = true; a.x = px; a.y = py; a.tx = px; a.ty = py; precisaDesenhar = true; continue; }
                    a.tx = px; a.ty = py;
                    const ex = passoSeco(a, 30, dt);   // fase 74b: até a casa sem entrar na água
                    if (Math.abs(ex) > 0.2) a.flip = ex < 0;
                    continue;
                }
                if (a.espera > 0) { a.espera -= dt; continue; }
                // ajudante com trabalho na fila: vai até o canteiro (ou bicho), ao lado dele
                if (a.ajudante && a.fila && a.fila.length && !a.indo) {
                    const alvo = a.fila[0], b = alvo.animal != null ? atores.get(alvo.animal) : null;
                    if (alvo.animal != null && !b) { a.fila.shift(); continue; }
                    const px = b ? b.x : wx(alvo.x), py = b ? b.y : wy(alvo.y) + 2;
                    a.tx = px + (a.x > px ? 11 : -11);
                    a.ty = py;
                    a.olhar = px;
                    a.indo = true;
                    a.vel = 45;
                }
                const dx = a.tx - a.x, dy = a.ty - a.y, d = Math.hypot(dx, dy);
                if (d < 0.5 && a.indo) {   // chegou: trabalha um pouquinho (brilho) e segue a fila
                    a.indo = false;
                    a.fila.shift();
                    a.flip = a.x > a.olhar;   // de frente para o canteiro (os sprites olham para a direita)
                    a.brilho = performance.now() + 900;
                    a.espera = 700;
                    if (!a.fila.length) a.vel = 12;
                    continue;
                }
                if (d < 0.5) {
                    a.espera = 800 + Math.random() * 3500;
                    if (a.olharProx != null) {   // o Faísca chegou num equipamento: vira para ele e mexe um pouco
                        a.flip = a.x > a.olharProx;
                        a.brilho = performance.now() + 900;
                        a.espera += 1500;
                    }
                    const p = lugarLivre(a);
                    a.olharProx = p.olhar;
                    a.tx = p.x;
                    a.ty = p.y;
                    continue;
                }
                const ex = passoSeco(a, a.vel, dt);   // (fase 79: todo mundo pode entrar na água)
                // os sprites do pacote olham para a direita: espelha quando anda para a esquerda
                if (Math.abs(ex) > 0.2) a.flip = ex < 0;
            }
            if (visitante) {
                const vx = visitante.tx - visitante.x, vy = visitante.ty - visitante.y, vd = Math.hypot(vx, vy);
                if (vd > 0.5) {
                    const ex = passoSeco(visitante, 24, dt);   // fase 74b
                    if (Math.abs(ex) > 0.2) visitante.flip = ex < 0;
                    visitante.andando = true;
                } else {
                    visitante.andando = false;
                    if (visitante.saindo) visitante = null;
                }
            }
            const dx = fazendeiro.tx - fazendeiro.x, dy = fazendeiro.ty - fazendeiro.y, d = Math.hypot(dx, dy);
            if (d > 0.5) {
                const ex = passoSeco(fazendeiro, 56, dt);   // fase 74b: contorna o lago
                if (Math.abs(ex) > 0.2) fazendeiro.flip = ex < 0;
                fazendeiro.passo += dt;
            } else {
                fazendeiro.passo = 0;
            }
        }

        /* ---- fase 66: os zzz de quem está dormindo ----
           Saem do telhado da casa (um por casa, mesmo com mais gente dentro) e sobem sumindo; quem
           dorme na sombra ganha os zzz em cima da cabeça. */
        const LETRA_Z = ['####', '..#.', '.#..', '####'];
        function zzz(x, y, tempo, semente) {
            for (let k = 0; k < 3; k++) {
                const f = ((tempo / 1600 + k / 3 + semente) % 1);
                const px = Math.round(x + k * 4 + Math.sin(f * 6 + k) * 2), py = Math.round(y - f * 20);
                const tam = k === 0 ? 1 : 2;
                q.globalAlpha = f < 0.15 ? f / 0.15 : Math.min(1, 1.4 - f * 1.4);
                LETRA_Z.forEach((linha, yy) => [...linha].forEach((ch, xx) => {
                    if (ch !== '#') return;
                    q.fillStyle = '#3f2631'; q.fillRect(px + xx * tam - 1, py + yy * tam - 1, tam + 2, tam + 2);   // contorno escuro
                }));
                LETRA_Z.forEach((linha, yy) => [...linha].forEach((ch, xx) => {
                    if (ch !== '#') return;
                    q.fillStyle = '#ffffff'; q.fillRect(px + xx * tam, py + yy * tam, tam, tam);
                }));
            }
            q.globalAlpha = 1;
        }
        function desenharSono(tempo) {
            const casas = new Map();
            for (const a of atores.values()) {
                if (!a.ajudante || !a.dormir) continue;
                if (a.dormir.sombra) { zzz(a.x + 8, a.y - 4, tempo, hash(a.id) % 7 / 7); continue; }
                if (a.dentro) casas.set(a.dormir.casa, a.dormir);
            }
            for (const [casa, d] of casas) zzz(wx(d.telhadoX) , wy(d.telhadoY) - 2, tempo, (hash(casa) % 5) / 5);
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
        // . grama, b borda, c miolo (copiados das peças 60 e 62, encostados na borda do bloco)
        const CANTOS = {
            cimaEsq: ['....bb', '..bbbb', '.bbbcc', '.bbccc', 'bbbccc'],
            cimaDir: ['bb....', 'bbbb..', 'ccbbb.', 'cccbb.', 'cccbbb'],
            baixoEsq: ['bbbbcc', '.bbbbb', '.bbbbb', '..bbbb', '....bb'],
            baixoDir: ['ccbbbb', 'bbbbb.', 'bbbbb.', 'bbbb..', 'bb....']
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
            // cantos de fora arredondados: o mesmo desenho das pontas das tiras do pacote (60 e 62)
            const canto = (px, py, linhas) => linhas.forEach((l, dy) => [...l].forEach((ch, dx) => {
                if (ch === '.') grama(px + dx, py + dy, 1, 1);
                else pinta(px + dx, py + dy, 1, 1, ch === 'b' ? cor.borda : cor.miolo);
            }));
            if (!cima && !esq) canto(2, 4, CANTOS.cimaEsq);
            if (!cima && !dir) canto(8, 4, CANTOS.cimaDir);
            if (!baixo && !esq) canto(2, 11, CANTOS.baixoEsq);
            if (!baixo && !dir) canto(8, 11, CANTOS.baixoDir);
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
            if (v.adubado) {
                q.fillStyle = '#3f8f2f';
                q.fillRect(x + 2, y + 12, 1, 1); q.fillRect(x + 4, y + 13, 1, 1); q.fillRect(x + 3, y + 14, 1, 1);
                q.fillRect(x + 12, y + 12, 1, 1); q.fillRect(x + 13, y + 14, 1, 1); q.fillRect(x + 11, y + 14, 1, 1);
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
            const bob = Math.floor(tempo / 600) % 2 ? -1 : 0;
            for (const zv of zonasVenda) {   // (fase 78: até duas placas)
                const x = wx(zv.placa.x), y = wy(zv.placa.y);
                tile(q, 83, x, y, false, 'town');
                icone(q, 'moeda', x + 4, y - 10 + bob);
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
                    const ocup = sel ? ocupadoSem(construcoesFn() || [], sel) : m.ocupado;
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
                        if (tipo === 'caminho_terra') q.drawImage(terraNova(vizinhosTerra((dx, dy) => temp.get((tx + dx) + ',' + (ty + dy)) === 'caminho_terra'), EST), x, y);   // fase 104
                        else {
                            if (sp.topo != null) tile(q, sp.topo, x, y - T, false, sp.p);
                            if (sp.topo2 != null) tile(q, sp.topo2, x, y - 2 * T, false, sp.p);
                            tile(q, sp.i, x, y, false, sp.p);
                        }
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
            if (pausada) { requestAnimationFrame(quadroAnim); return; }   // fase 62: no alto-mar a fazenda não desenha
            if (movendo || agora - ultimoDesenho >= 1000 / 24) {
                ultimoDesenho = agora;
                precisaDesenhar = false;
                desenhar(agora - t0);
            }
            requestAnimationFrame(quadroAnim);
        }

        // fase 73b: o mapa de ocupação sem o item que está na mão, guardado (era refeito a cada quadro)
        let memoSem = { lista: null, sel: null, n: -1, ocupado: null };
        function ocupadoSem(lista, sel) {
            if (memoSem.lista !== lista || memoSem.sel !== sel || memoSem.n !== lista.length) {
                memoSem = { lista, sel, n: lista.length, ocupado: mapaConstrucoes(lista, sel).ocupado };
            }
            return memoSem.ocupado;
        }
        function desenhar(tempo) {
            sincronizarAnimais();
            quadroHelice = Math.floor(tempo / (clima === 'furacao' ? 45 : clima === 'vento' || clima === 'tempestade' ? 90 : 200)) % 2;   // venta mais, gira mais
            // só o pedaço do mundo que aparece na tela (com uma bordinha): o resto não é desenhado
            // (antes era o mundo inteiro a cada quadro, e o celular engasgava ao arrastar)
            const V = { x0: Math.max(0, Math.floor(cam.x) - T), y0: Math.max(0, Math.floor(cam.y) - T) };
            V.x1 = Math.min(MW, Math.ceil(cam.x + vw) + T); V.y1 = Math.min(MH, Math.ceil(cam.y + vh) + T);
            const vW = Math.max(1, V.x1 - V.x0), vH = Math.max(1, V.y1 - V.y0);
            // coisa no quadrado (x, y) que pode aparecer: as altas sobem até 3 quadrados e as largas vão até 4 para a direita
            const naTela = (x, y) => { const px = wx(x), py = wy(y); return px >= V.x0 - 4 * T && px <= V.x1 && py >= V.y0 - 4 * T && py <= V.y1 + 3 * T; };
            q.save();
            q.beginPath(); q.rect(V.x0, V.y0, vW, vH); q.clip();
            q.drawImage(fundo, V.x0, V.y0, vW, vH, V.x0, V.y0, vW, vH);
            desenharAguaViva(tempo);   // fase 74b: o lago (o laguinho dos patos é desenhado no cercado, com as dele)
            desenharMarVivo(tempo);    // fase 76: o mar da praia

            const todas = construcoesFn() || [];
            const m = mapaConstrucoes(todas);   // (os vizinhos de cerca e cano vêm da lista toda)
            const lista = todas.filter((c) => naTela(c.x, c.y));
            const pe = [];   // coisas "em pé", ordenadas pela altura
            const pares = paresOficinas(todas);   // fase 106: duas oficinas iguais lado a lado viram uma só
            const atlasCasas = (atlasDaEstacao && atlasDaEstacao.casas) || atlas.casas;
            for (const c of lista) {
                const par = pares.get(c.x + ',' + c.y);
                if (par === 'dir') continue;
                if (par === 'esq' && atlasCasas && atlasCasas.posDupla) {
                    const [sx, sy] = atlasCasas.posDupla[c.tipo];
                    pe.push({ img: atlasCasas.duplas, recorte: [sx, sy, 64, 48], x: wx(c.x), y: wy(c.y), ordem: wy(c.y + 2), flip: false, bob: 0 });
                    continue;
                }
                const s = spritesDe(c.tipo, c.x, c.y, m);
                if (s.cercado) { desenharCercado(c, s, tempo); continue; }
                if (s.cano) { desenharCano(c, tempo); continue; }
                if (s.chao && c.tipo === 'caminho_terra') q.drawImage(terraNova(vizinhosTerra((dx, dy) => m.get((c.x + dx) + ',' + (c.y + dy)) === 'caminho_terra'), EST), wx(c.x), wy(c.y));   // fase 104
                else if (s.chao) tile(q, s.i, wx(c.x), wy(c.y), false, s.p);   // caminho/flores: chão
                else if (s.grade) pe.push({ ...s, x: wx(c.x), y: wy(c.y + s.h - 1), gy: wy(c.y), flip: false, bob: 0 });
                else pe.push({ ...s, ...(c.sobrecarga_em && s.topo != null ? { topo: 1023 } : null),   // fase 77: em sobrecarga, a hélice para
                    x: wx(c.x), y: wy(c.y), flip: false, bob: ANIMA[c.tipo] === 'robo' && Math.floor((tempo + c.x * 97) / 380) % 2 ? -1 : 0 });
            }

            const canteiros = listaCanteiros(), mc = mapaCanteiros(canteiros);
            for (const c of canteiros) if (naTela(c.x, c.y)) desenharCanteiro(c, tempo, mc);
            desenharViagens();
            if (zonasVenda.length) desenharPlacaVenda(tempo);
            // fase 107: o rádio da feira (todo mundo tem), com as notinhas subindo quando a música toca
            pe.push({ img: icones.radio, x: wx(RADIO.x) + 2, y: wy(RADIO.y) + 6, flip: false, bob: radioTocando && Math.floor(tempo / 420) % 2 ? -1 : 0 });
            if (radioTocando) for (let k = 0; k < 3; k++) {
                const u = ((tempo / 2200) + k / 3) % 1, nx = wx(RADIO.x) + 8 + Math.sin(u * 6 + k) * 4, ny = wy(RADIO.y) + 6 - u * 18;
                q.globalAlpha = Math.sin(u * Math.PI) * 0.9; q.fillStyle = ['#7cc452', '#fdbe53', '#f59cbc'][k];
                q.fillRect(Math.round(nx), Math.round(ny), 2, 2); q.fillRect(Math.round(nx) + 1, Math.round(ny) - 3, 1, 3); q.fillRect(Math.round(nx) + 2, Math.round(ny) - 3, 1, 1);
                q.globalAlpha = 1;
            }
            FEIRA.barracas.forEach((b, k) => {   // fase 106: as barracas desenhadas (toldo, balcão e mercadoria)
                const bc = barracaCanvas(k);
                if (k < feira.barracas) pe.push({ img: bc, x: wx(b.x) - 1, y: wy(b.y) - 10, ordem: wy(b.y), flip: false, bob: 0 });
                else if (feira.vagas && (k < 4 || k === feira.barracas)) {   // (fase 82: das de diamante, só a próxima)
                     q.globalAlpha = 0.3; q.drawImage(bc, wx(b.x) - 1, wy(b.y) - 10); q.globalAlpha = 1; }
            });

            const naMaoPraia = pessoasDaPraia(todas, tempo, pe, naTela);   // fase 108: a praia viva
            for (const a of atores.values()) {
                if (a.dentro) continue;   // fase 66: dormindo dentro da casa
                const parado = a.v && a.v.estado !== 'produzindo';
                const andando = a.ajudante && Math.hypot(a.tx - a.x, a.ty - a.y) > 0.5;
                const bob = (parado && Math.floor(tempo / 600) % 2) || (andando && Math.floor(tempo / 140) % 2) ? -1 : 0;
                // fase 76: o pato nadando fica com metade do corpo dentro da água (fase 79: e todo mundo que entra nela)
                const nadando = naAgua(a.x, a.y);
                if (!a.visual && a.v && BICHOS_NOVOS.has(a.tipo)) {   // fase 107: os bichos desenhados, andando
                    const anda = Math.hypot(a.tx - a.x, a.ty - a.y) > 0.5;
                    const cv = bichoCanvas(a.tipo, anda ? Math.floor((tempo + a.x * 7) / 170) % 2 : 0);
                    pe.push({ img: cv, x: a.x + 8 - cv.width / 2, y: a.y + 16 - cv.height, ordem: a.y, flip: a.flip, bob: nadando ? 0 : bob, nadando });
                } else
                pe.push(a.visual ? { img: ajudanteCanvas(a.tipo), x: a.x, y: a.y, flip: a.flip, bob: nadando ? 0 : bob, nadando }
                    : { p: a.p || 'farm', i: a.i, x: a.x, y: a.y, flip: a.flip, bob: nadando ? 0 : bob, nadando });
                // ferramenta na mão do ajudante (do lado para onde ele olha; na água, a parte de baixo some junto)
                if (a.ferramenta != null) pe.push({ p: a.ferramentaP || 'farm', i: a.ferramenta, x: a.x + (a.flip ? -7 : 7), y: a.y + 0.5, flip: a.flip, bob: nadando ? 0 : bob, corte: nadando ? Math.round(a.y) : null });
            }
            const andando = fazendeiro.passo > 0, fazNada = naAgua(fazendeiro.x, fazendeiro.y);
            pe.push({ img: avatarCanvas(avatarAtual), x: fazendeiro.x, y: fazendeiro.y, flip: fazendeiro.flip, bob: !fazNada && andando && Math.floor(tempo / 120) % 2 ? -1 : 0, nadando: fazNada });
            if (lago && lagoNaTela()) pe.push({ p: 'factory', i: 120, x: wx(LAGO.x) + 1, y: wy(LAGO.y + 2), flip: false, bob: Math.floor(tempo / 700) % 2 ? -1 : 0 });
            if (visitante) { const vn = naAgua(visitante.x, visitante.y); pe.push({ p: 'dungeon', i: VISITANTE_ARTE[visitante.tipo] || 86, x: visitante.x, y: visitante.y, flip: visitante.flip, bob: !vn && visitante.andando && Math.floor(tempo / 140) % 2 ? -1 : 0, nadando: vn }); }
            desenharNavio(pe, tempo);   // fase 104: o navio no píer
            pe.sort((a, b) => (a.ordem != null ? a.ordem : a.y) - (b.ordem != null ? b.ordem : b.y)).forEach((a) => {
                const x = Math.round(a.x), y = Math.round(a.y) + a.bob;
                if (a.grade) {
                    a.grade.forEach((linha, dy) => linha.forEach((i, dx) => tile(q, i, x + dx * T, a.gy + dy * T, false, a.p)));
                    return;
                }
                // fase 76/79: na água, só a parte de cima, e a linha da água balançando em volta
                const base = a.corte != null ? a.corte : y;
                const linha = (a.nadando || a.corte != null) ? base + 10 + (Math.floor(tempo / 500 + Math.round(a.x)) % 2) : null;
                if (linha != null) { q.save(); q.beginPath(); q.rect(x - 10, y - 2 * T, 2 * T + 4, linha - (y - 2 * T)); q.clip(); }
                const dy = linha != null ? 2 : 0;
                const fim = () => {
                    if (linha == null) return;
                    q.restore();
                    if (!a.nadando) return;
                    q.fillStyle = '#cfe6fb'; q.fillRect(x + 2, linha, 12, 1);
                    q.fillStyle = '#8fc1ef'; q.fillRect(x, linha + 1, 3, 1); q.fillRect(x + 13, linha + 1, 3, 1);
                };
                if (a.recorte) { q.drawImage(a.img, a.recorte[0], a.recorte[1], a.recorte[2], a.recorte[3], x, y, a.recorte[2], a.recorte[3]); return; }   // fase 106
                if (a.img) {   // avatar (desenhado na hora, fora dos pacotes)
                    if (a.flip) { q.save(); q.translate(x + a.img.width, y + dy); q.scale(-1, 1); q.drawImage(a.img, 0, 0); q.restore(); }
                    else q.drawImage(a.img, x, y + dy);
                    fim();
                    return;
                }
                if (a.topo != null) tile(q, a.topo, x, y - T, a.flip, a.p);
                if (a.topo2 != null) tile(q, a.topo2, x, y - 2 * T, a.flip, a.p);
                tile(q, a.i, x, y + dy, a.flip, a.p);
                fim();
            });

            for (const m of naMaoPraia) if (A_ITEM_PRAIA[m.item] != null) miniTile(A_ITEM_PRAIA[m.item], m.x, m.y, 7);
            desenharMaquinas(lista, tempo);
            desenharSono(tempo);   // fase 66: os zzz das casas (e de quem dorme na sombra)
            desenharRaios(tempo);   // fase 68: as faíscas do eletricista
            const escuro = faseDoDia(relogio()).n;
            if (escuro > 0) desenharNoite(todas, tempo, escuro);   // (as luzes saem da lista toda: a camada fica guardada)   // balões e sinais vêm depois: ficam claros
            desenharRadiacao(tempo);   // fase 68: o bicho radioativo (brilha também de noite)
            if (visitante && !visitante.andando && !visitante.saindo) {   // balão com o pedido, pulando
                const bx = Math.round(visitante.x) - 2, by = Math.round(visitante.y) - 21 + (Math.floor(tempo / 350) % 2);
                balao(bx, by, 20, 18);
                tile(q, visitante.item != null ? visitante.item : 1040, bx + 2, by + 1);
                if (Math.floor(tempo / 300) % 3) icone(q, 'brilho', bx + 15, by - 3);
            }
            for (const a of atores.values()) if (a.v) desenharSinalAnimal(a, tempo);
            for (const a of atores.values()) {
                if (a.brilho && performance.now() < a.brilho) icone(q, 'brilho', Math.round(a.x) + (a.flip ? -3 : 11), Math.round(a.y) - 5 - (Math.floor(tempo / 150) % 2));
            }
            if (lago && lagoNaTela()) desenharPescaria(tempo);
            for (const c of lista) {
                // gerador a biomassa queimando milho e oficina trabalhando: fumacinha (a da oficina sai da chaminé, à direita)
                const oficina = c.oficina && c.oficina.trabalhando;
                if (!c.ligado && !oficina) continue;
                const a = oficina ? arteItem(c.tipo, EST) : null;
                const sx = oficina ? wx(c.x) + (a.w || 2) * T - 5 : wx(c.x) + 9, sy = oficina ? wy(c.y) + 3 : wy(c.y) + 1;
                for (let k = 0; k < 3; k++) {
                    const f = ((tempo / 900) + k / 3) % 1;
                    q.globalAlpha = 0.85 * (1 - f);
                    q.fillStyle = k === 1 ? '#8b9bb4' : '#c0cbdc';   // uma das bolinhas mais escura
                    const tam = 3 + Math.round(f * 3);
                    q.fillRect(Math.round(sx + Math.sin(f * 6 + k) * 2 + (oficina ? f * 5 : 0)), Math.round(sy - f * 14), tam, tam);
                }
                q.globalAlpha = 1;
            }
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
                if (of.trabalhando) barraProgresso(bx + 4, by + 19, of.progresso || 0);
                if (of.rede) {   // selo de cano: esta oficina está ligada na rede
                    q.fillStyle = '#566c86'; q.fillRect(bx - 3, by - 3, 8, 8);
                    q.fillStyle = of.rede === 'sem_energia' ? '#e8434a' : '#6ee68c'; q.fillRect(bx - 1, by - 1, 4, 4);
                }
                if (pronta && Math.floor(tempo / 300) % 3) icone(q, 'brilho', bx + 17, by - 3);
            }
            for (const c of lista) {
                if (!c.pronto || c.produto == null) continue;
                const x = wx(c.x), by = wy(c.y) - 21 + (Math.floor(tempo / 350) % 2);
                balao(x - 2, by, 20, 18);
                tile(q, c.produto, x, by + 1);
                if (Math.floor(tempo / 300) % 3) icone(q, 'brilho', x + 15, by - 3);
            }

            // fase 51: cada barraca mostra um anúncio seu (com mais anúncios que barracas, vão passando)
            const nv = feira.vende.length, nb = Math.min(feira.barracas, FEIRA.barracas.length);
            for (let k = 0; k < nb && nv; k++) {
                const item = nv <= nb ? feira.vende[k] : feira.vende[(k + Math.floor(tempo / 4000) * nb) % nv];
                if (item == null) continue;
                const b = FEIRA.barracas[k], x = wx(b.x), by = wy(b.y) - 20;
                balao(x - 2, by, 20, 18);
                tile(q, item, x, by + 1);
                icone(q, 'moeda', x + 12, by - 3);
            }
            for (const c of lista) {   // baú: barrinha de quanto está cheio (verde → amarelo → vermelho)
                if (!c.bau || !(c.bau.frac > 0)) continue;
                const f = Math.min(1, c.bau.frac), x = wx(c.x) + 2, y = wy(c.y) + T - 1;
                q.fillStyle = '#3f2631'; q.fillRect(x - 1, y - 1, T - 2, 4);
                q.fillStyle = f >= 1 ? '#e8434a' : f > 0.75 ? '#fdbe53' : '#6ee68c';
                q.fillRect(x, y, Math.max(1, Math.round((T - 4) * f)), 2);
            }
            if (!construcao.ativo && alcance) desenharAlcance();
            if (segurando) desenharSegurar(lista);

            if (construcao.ativo) {
                desenharGrade(m, tempo);
            } else if (typeof hover === 'number') {
                const { x, y } = posCanteiro(hover);
                moldura(x, y, T, T);
            } else if (hover === 'venda' && zonasVenda.length) {
                for (const zv of zonasVenda) if (zv.n === vendaTocada) moldura(wx(zv.placa.x), wy(zv.placa.y), T, T);
            } else if (typeof hover === 'string' && hover.startsWith('c:')) {
                const [hx, hy] = hover.slice(2).split(',').map(Number);
                const c = lista.find((k) => k.x === hx && k.y === hy);
                if (c) { const a = arteItem(c.tipo, EST); moldura(wx(hx), wy(hy), T * (a.w || 1), T * (a.h || 1)); }
            } else if (hover === 'visitante' && visitante) {
                moldura(Math.round(visitante.x), Math.round(visitante.y), T, T);
            } else if (hover === 'lago' && lagoNaTela()) {
                moldura(wx(LAGO.x), wy(LAGO.y), LAGO.w * T, LAGO.h * T);
            } else if (hover === 'celeiro') {
                const c = retCeleiro();
                moldura(c.x, c.y + T, c.w, c.h - T);
            } else if (hover === 'feira') {
                moldura(wx(FEIRA.x), wy(FEIRA.y), FEIRA.w * T, FEIRA.h * T);
            } else if (typeof hover === 'string' && hover.startsWith('a:')) {
                const a = atores.get(idDoHover(hover));
                if (a) moldura(Math.round(a.x), Math.round(a.y), T, T);
            }

            q.restore();   // (o recorte do pedaço da tela)

            // recorte da câmera ampliado para a tela
            ctx.imageSmoothingEnabled = false;
            const k = escala * dpr;
            const dx = V.x0 * k - Math.round(cam.x * k), dy = V.y0 * k - Math.round(cam.y * k);
            // a grama de fora do mapa só quando o mundo não cobre a tela toda (zoom bem afastado)
            if (dx > 0 || dy > 0 || dx + vW * k < canvas.width || dy + vH * k < canvas.height) {
                ctx.fillStyle = (CHAO[EST] || CHAO.primavera).grama;
                ctx.fillRect(0, 0, canvas.width, canvas.height);
                if (escuro > 0) {   // a grama fora do mapa escurece junto
                    ctx.fillStyle = `rgba(16, 22, 58, ${(0.62 * escuro).toFixed(3)})`;
                    ctx.fillRect(0, 0, canvas.width, canvas.height);
                }
            }
            ctx.drawImage(mundo, V.x0, V.y0, vW, vH, dx, dy, vW * k, vH * k);
            desenharClima(tempo, k);
        }

        /* ---- noite: o mundo escurece num azul e as luzes acendem por cima ----
           (casa, celeiro e casinhas com a janela acesa, lampiões, oficinas trabalhando, reator,
           estufa) e uns vaga-lumes piscam pela fazenda. "escuro" vai de 0 a 1 (faseDoDia). */
        let relogio = () => Date.now();
        const LUZ_QUENTE = '255, 196, 110';
        // cada luz: f = brilho por cima; ilumina = quanto ela tira da escuridão (o chão volta à cor do dia)
        // fase 81: com energia elétrica, a casa, as casinhas e os lampiões gastam 1 ⚡/h de noite; bateria zerada, apagam
        let luzesAcesas = true;
        function luzesDaNoite(lista, tempo) {
            const L = luzesAcesas ? [{ x: wx(MAPA.casa.x) + 1.5 * T, y: wy(MAPA.casa.y) + 2 * T, r: 3.5 * T, cor: LUZ_QUENTE, f: 0.3, ilumina: 0.6 }] : [];
            const cel = retCeleiro();
            L.push({ x: cel.x + cel.w / 2, y: cel.y + cel.h - T, r: 3 * T, cor: LUZ_QUENTE, f: 0.25, ilumina: 0.55 });
            for (const c of lista) {
                const x = wx(c.x), y = wy(c.y);
                if (!luzesAcesas && (c.tipo === 'lampiao' || c.tipo === 'casa_vermelha' || c.tipo === 'casa_azul')) continue;
                if (c.tipo === 'lampiao') {   // o poste: luz fixa (sem tremer) que ilumina uma área grande em volta
                    L.push({ x: x + T / 2, y: y + 5, r: 8 * T, cor: '255, 210, 120', f: 0.3, ilumina: 0.9 });
                } else if (c.tipo === 'casa_vermelha' || c.tipo === 'casa_azul') {
                    L.push({ x: x + 1.5 * T, y: y + 2 * T, r: 3.5 * T, cor: LUZ_QUENTE, f: 0.28, ilumina: 0.6 });
                } else if (c.oficina) {   // fábricas: janela acesa sempre; trabalhando, bem mais forte
                    const a = arteItem(c.tipo, EST), forte = c.oficina.trabalhando;
                    L.push({ x: x + (a.w || 1) * T / 2, y: y + (a.h || 1) * T * 0.65, r: (forte ? 4.5 : 3) * T, cor: LUZ_QUENTE,
                             f: forte ? 0.28 : 0.15, ilumina: forte ? 0.75 : 0.45 });
                } else if (c.tipo === 'fabrica_auto') {
                    L.push({ x: x + T, y: y + T, r: 4 * T, cor: LUZ_QUENTE, f: 0.28, ilumina: 0.7 });
                } else if (c.tipo === 'reator') {
                    L.push({ x: x + 24, y: y + 22, r: 4 * T, cor: '120, 255, 150', f: 0.5, ilumina: 0.7 });   // (fase 79: na janela do núcleo)
                } else if (c.tipo === 'estufa') {
                    L.push({ x: x + T, y: y + T, r: 3 * T, cor: '205, 165, 255', f: 0.4, ilumina: 0.55 });
                }
            }
            return L;
        }
        /* As duas camadas da noite, feitas a partir das luzes e guardadas até elas mudarem:
           - escuridão: azul, clareando até o branco onde tem luz (multiplica a cena: ali fica a cor do dia)
           - brilho: a cor quente das luzes (soma por cima)
           Fase 69: as luzes se SOMAM (por isso duas luzes perto viram uma mancha só, sem a "cintura" que
           fazia a luz de um poste parecer encolher perto do outro) e passam por um teto macio: até 3/4 do
           claro de um poste vale a soma; dali para cima vai chegando devagar no claro do pé do poste, sem
           nunca passar dele. Juntam, não encolhem e não estouram. (Na fase 48 era o máximo: vinco entre
           elas; na 67, um máximo suave: ainda com a cintura.) Feito em 1/4 da resolução (as luzes são
           suaves; poucos ms, só quando as luzes mudam) e esticado. */
        const NOITE_ESC = 4;
        let noiteCache = { chave: null, escuridao: null, brilho: null };
        // a soma até 3/4 do teto passa igual; dali para cima, encosta no teto sem passar
        const tetoMacio = (s, teto) => {
            const joelho = teto * 0.75;
            return s <= joelho ? s : joelho + (teto - joelho) * (1 - Math.exp(-(s - joelho) / (teto - joelho)));
        };
        function camadasNoite(luzes) {
            const chave = luzes.map((l) => [l.x, l.y, l.r, l.f, l.ilumina, l.cor].join(',')).join('|');
            if (noiteCache.chave === chave) return noiteCache;
            const W = Math.ceil(MW / NOITE_ESC), H = Math.ceil(MH / NOITE_ESC);
            const tela = (c) => {
                if (c && c.width === W && c.height === H) return c;
                c = document.createElement('canvas');
                c.width = W;
                c.height = H;
                return c;
            };
            const escuridao = tela(noiteCache.escuridao), brilho = tela(noiteCache.brilho);
            const ilu = new Float32Array(W * H), cor = new Float32Array(W * H * 3);
            let tetoIlu = 0;
            const tetoCor = [0, 0, 0];
            for (const l of luzes) {
                const cx = l.x / NOITE_ESC, cy = l.y / NOITE_ESC, r = l.r / NOITE_ESC, r2 = r * r;
                const [cr, cg, cb] = l.cor.split(',').map((n) => Number(n) / 255);
                const il = (l.ilumina || 0) * 0.89, fq = (l.f || 0) * 0.7;   // 0.89 e 0.7: o pé do poste com o mesmo claro de antes
                tetoIlu = Math.max(tetoIlu, il);
                tetoCor[0] = Math.max(tetoCor[0], fq * cr); tetoCor[1] = Math.max(tetoCor[1], fq * cg); tetoCor[2] = Math.max(tetoCor[2], fq * cb);
                const x0 = Math.max(0, Math.floor(cx - r)), x1 = Math.min(W - 1, Math.ceil(cx + r));
                const y0 = Math.max(0, Math.floor(cy - r)), y1 = Math.min(H - 1, Math.ceil(cy + r));
                for (let y = y0; y <= y1; y++) {
                    const dy = y + 0.5 - cy;
                    for (let x = x0; x <= x1; x++) {
                        const dx = x + 0.5 - cx, d2 = (dx * dx + dy * dy) / r2;
                        if (d2 >= 1) continue;
                        const u = 1 - d2, k = u * u, i = y * W + x;
                        if (il) ilu[i] += il * k;
                        if (fq) {   // o brilho quente fica mais perto da luz
                            const v = fq * k * k * u, j = i * 3;
                            cor[j] += v * cr; cor[j + 1] += v * cg; cor[j + 2] += v * cb;
                        }
                    }
                }
            }
            const e = escuridao.getContext('2d'), b = brilho.getContext('2d');
            const de = e.createImageData(W, H), db = b.createImageData(W, H), pe = de.data, pb = db.data;
            const byte = (v) => Math.min(255, Math.round(255 * v));
            for (let i = 0, j = 0; i < W * H; i++, j += 4) {
                pe[j + 3] = pb[j + 3] = 255;
                const g = ilu[i] ? byte(tetoMacio(ilu[i], tetoIlu)) : 0, c = i * 3;
                pe[j] = Math.max(0x3e, g); pe[j + 1] = Math.max(0x4c, g); pe[j + 2] = Math.max(0x8c, g);
                if (cor[c] || cor[c + 1] || cor[c + 2]) {
                    pb[j] = byte(tetoMacio(cor[c], tetoCor[0])); pb[j + 1] = byte(tetoMacio(cor[c + 1], tetoCor[1])); pb[j + 2] = byte(tetoMacio(cor[c + 2], tetoCor[2]));
                }
            }
            e.putImageData(de, 0, 0);
            b.putImageData(db, 0, 0);
            noiteCache = { chave, escuridao, brilho };
            return noiteCache;
        }
        // fase 67: o brilho do anel dos canos é um halo redondo (antes eram quadrados somados)
        const haloCano = {};
        function halo(cor) {
            if (haloCano[cor]) return haloCano[cor];
            const c = document.createElement('canvas');
            c.width = c.height = 24;
            const g = c.getContext('2d'), gr = g.createRadialGradient(12, 12, 0, 12, 12, 12);
            [[0, 1], [0.25, 0.88], [0.5, 0.56], [0.75, 0.19], [1, 0]].forEach(([t, a]) => gr.addColorStop(t, `rgba(${cor}, ${a})`));
            g.fillStyle = gr;
            g.fillRect(0, 0, 24, 24);
            return (haloCano[cor] = c);
        }
        /* ---- fase 106: de noite os vidros das casas, do celeiro e das oficinas acendem (amarelo quente, com um
           brilhinho em volta e uma tremidinha de vela). A casa e as casinhas seguem a energia (fase 81). ---- */
        function janelasAcesas(lista, tempo, escuro) {
            const acender = (id, ox, oy, k) => {
                const jan = JANELAS_CASAS[id];
                if (!jan) return;
                jan.forEach(([x, y, w, h], i) => {
                    const treme = 0.85 + 0.15 * Math.sin(tempo / 300 + k * 1.7 + i);
                    q.globalCompositeOperation = 'source-over';
                    q.globalAlpha = Math.min(1, escuro * 0.95 * treme);
                    q.fillStyle = '#ffd27a'; q.fillRect(ox + x, oy + y, w, h);
                    q.fillStyle = '#fff2b8'; q.fillRect(ox + x, oy + y, w, 1);
                    q.globalCompositeOperation = 'lighter';
                    q.globalAlpha = escuro * 0.35 * treme;
                    q.drawImage(halo(LUZ_QUENTE), ox + x + w / 2 - 8, oy + y + h / 2 - 8, 16, 16);
                });
            };
            q.save();
            if (luzesAcesas) acender('casa', wx(MAPA.casa.x), wy(MAPA.casa.y), 0);
            const cel = retCeleiro();
            acender('celeiro', cel.x, cel.y, 1);
            const pares = paresOficinas(construcoesFn() || []);
            for (const c of lista) {
                if ((c.tipo === 'casa_vermelha' || c.tipo === 'casa_azul') && luzesAcesas) acender(c.tipo, wx(c.x), wy(c.y), c.x + c.y);
                else if (OFICINA_PRODUTO[c.tipo]) {
                    const par = pares.get(c.x + ',' + c.y);
                    if (par === 'dir') continue;
                    acender(par === 'esq' ? c.tipo + ':2' : c.tipo, wx(c.x), wy(c.y), c.x * 3 + c.y);
                }
            }
            q.restore();
        }
        function desenharNoite(lista, tempo, escuro) {
            const luzes = luzesDaNoite(lista, tempo);
            const camadas = camadasNoite(luzes);
            q.save();
            q.globalCompositeOperation = 'multiply';   // tudo fica mais escuro e azulado, sem perder a cor
            q.globalAlpha = escuro;
            q.imageSmoothingEnabled = true;            // as camadas são pequenas: esticadas suaves
            q.drawImage(camadas.escuridao, 0, 0, MW, MH);
            q.globalCompositeOperation = 'lighter';    // a cor quente das luzes por cima
            q.drawImage(camadas.brilho, 0, 0, MW, MH);
            q.globalAlpha = 1;
            // canos da rede: a luz verde do anel brilha no escuro (vermelha piscando sem energia)
            for (const c of lista) {
                if (!c.cano || !c.rede) continue;
                const cx = wx(c.x) + 8, cy = wy(c.y) + 8;
                let cor, a;
                // fase 69: bem mais fraco e pequeno (um halo de 16 px só no anel): a luz é um sinal, não um poste
                if (c.rede === 'ok' && c.ativa) {
                    const onda = (Math.sin(tempo / 260 - (c.x + c.y) * 0.9) + 1) / 2;   // a mesma onda do anel
                    cor = '110, 230, 140'; a = escuro * (0.12 + 0.33 * onda);
                } else if (c.rede === 'ok') {   // parada: quase nada
                    cor = '110, 230, 140'; a = escuro * 0.1;
                } else {
                    if (!(Math.floor(tempo / 500) % 2)) continue;
                    cor = '232, 67, 74'; a = escuro * 0.4;
                }
                q.globalCompositeOperation = 'screen';   // canos juntos não estouram
                q.globalAlpha = Math.min(1, a);
                q.drawImage(halo(cor), cx - 8, cy - 8, 16, 16);
            }
            janelasAcesas(lista, tempo, escuro);   // fase 106: as janelas acesas
            q.globalCompositeOperation = 'lighter';
            q.globalAlpha = 1;
            // vaga-lumes: cada um passeia em volta de um ponto fixo e pisca no seu ritmo
            for (let k = 0; k < 32; k++) {
                const bx = ((k * 197 + 31) % 101) / 101 * MW, by = ((k * 131 + 17) % 89) / 89 * MH;
                const x = Math.round(bx + Math.sin(tempo / 1700 + k) * 12), y = Math.round(by + Math.cos(tempo / 2300 + k * 1.7) * 9);
                const pisca = (Math.sin(tempo / 380 + k * 2.3) + 1) / 2;
                if (pisca < 0.35) continue;
                q.fillStyle = `rgba(200, 255, 120, ${(0.25 * pisca * escuro).toFixed(3)})`;
                q.fillRect(x - 1, y - 1, 3, 3);
                q.fillStyle = `rgba(235, 255, 170, ${(pisca * escuro).toFixed(3)})`;
                q.fillRect(x, y, 1, 1);
            }
            q.restore();
        }

        /* ---- fase 68: o eletricista solta faíscas, 1 raiozinho por nível (até 3), piscando em volta da
           cabeça e dos ombros. Rápido e pequeno: diverte sem tampar nada. ---- */
        const RAIO = [[2, 0], [1, 1], [0, 2], [1, 2], [2, 2], [1, 3], [0, 4]];   // zigue-zague de 3 x 5
        const LUGAR_RAIO = [[-3, 3], [15, 4], [6, -5]];
        function desenharRaios(tempo) {
            for (const a of atores.values()) {
                if (a.tipo !== 'eletricista' || a.dentro || a.dormir) continue;
                for (let k = 0; k < Math.min(3, a.nivel || 1); k++) {
                    const t = Math.floor((tempo + k * 230) / 110);
                    if (t % 6 > 1) continue;   // aparece 2 de cada 6 quadros: uma faísca, não um holofote
                    const [lx, ly] = LUGAR_RAIO[k], h = hash(a.id + ':' + k + ':' + t);
                    const x = Math.round(a.x) + lx + (h % 3) - 1, y = Math.round(a.y) + ly + ((h >> 3) % 3) - 1, vira = (h >> 5) % 2;
                    for (const [px, py] of RAIO) {
                        const xx = x + (vira ? 2 - px : px);
                        q.fillStyle = '#3f2631';
                        q.fillRect(xx - 1, y + py, 1, 1);
                        q.fillStyle = py === 2 ? '#fff6a8' : '#fdbe53';
                        q.fillRect(xx, y + py, 1, 1);
                    }
                }
            }
        }

        /* ---- fase 68: o bicho radioativo brilha verde, pulsando, solta bolhinhas e o produto pulando de
           tempos em tempos (na tela é só o efeito; no servidor ele dá 1 a cada 2 minutos). ---- */
        function desenharRadiacao(tempo) {
            for (const a of atores.values()) {
                if (!a.v || !a.v.radioativo) continue;
                const cx = Math.round(a.x) + 8, cy = Math.round(a.y) + 10, pulso = (Math.sin(tempo / 300 + a.x) + 1) / 2;
                q.save();
                q.globalCompositeOperation = 'screen';
                q.globalAlpha = 0.55 + 0.35 * pulso;
                q.drawImage(halo('120, 255, 110'), cx - 15, cy - 15, 30, 30);
                q.drawImage(halo('190, 255, 150'), cx - 8, cy - 8, 16, 16);   // o miolo, mais claro
                q.restore();
                for (let k = 0; k < 3; k++) {
                    const f = (tempo / 1500 + k / 3 + a.x * 0.01) % 1;
                    q.fillStyle = `rgba(160, 255, 120, ${(1 - f).toFixed(2)})`;
                    q.fillRect(cx - 5 + k * 5, cy - 4 - Math.round(f * 14), 1, 1);
                }
                const f = ((tempo + a.x * 37) % 2400) / 2400;
                if (f < 0.6 && a.v.produto != null) {
                    q.globalAlpha = 1 - f / 0.6;
                    miniTile(a.v.produto, cx - 4, cy - 18 - Math.round(f * 10));
                    q.globalAlpha = 1;
                }
            }
        }

        /* ---- máquinas se mexendo: água, névoa, luz, fumaça, brilho, carga ---- */
        const ANIMA = {
            irrigador: 'agua', aspersor: 'agua', pulverizador: 'nevoa', alarme: 'luz', robo_capina: 'robo', robo_colheita: 'robo',
            trator: 'fumaca', colheitadeira: 'fumaca', fabrica_auto: 'fabrica', triturador: 'po', painel_solar: 'reflexo',
            bateria: 'carga', supercap: 'carga', estufa: 'estufa', reator: 'reator', hidreletrica: 'roda',
            guarda_sol: 'banhista', cadeira_praia: 'banhista', barraca_coco: 'fregues', barraca_milho: 'fregues'   // fase 97: a praia
        };
        // fase 97: os banhistas (gente de dia na areia; cada guarda-sol e cadeira tem o seu, e as barracas,
        // um freguês que vem e vai). O jeito de cada um sai da posição, sempre o mesmo.
        function banhistaDe(x, y) {
            const r = rng(x * 7919 + y * 104729), tipos = ['fazendeiro', 'fazendeira'];
            return { tipo: tipos[Math.floor(r() * 2)], pele: Math.floor(r() * 5), cabelo: 1 + Math.floor(r() * 6), roupa: 1 + Math.floor(r() * 8), calca: 1 + Math.floor(r() * 6) };
        }
        const deDia = () => !faseDoDia(relogio()).noite;   // o dia do jogo (o ciclo próprio, não a hora de verdade)

        /* ---- fase 108: a praia viva. Cada cadeira e guarda-sol tem o seu banhista: chega andando, senta, vai
           nadar, volta, vai comprar na barraca (se tiver), senta de novo comendo e vai embora; depois de um tempo
           vem outra pessoa. Quanto mais coisa na praia, menos tempo ela fica vazia e mais gente passeia pela
           areia (praia com pouca opção fica vazia). Tudo sai do relógio, sem guardar estado. ---- */
        const ASSENTO_PRAIA = { guarda_sol: 1, cadeira_praia: 1 };
        const BARRACA_PRAIA = { barraca_coco: 'coco', barraca_milho: 'milho' };
        const A_ITEM_PRAIA = { coco: CULTURAS.coco.item, milho: CULTURAS.milho.item };   // o que vem na mão
        const VEL_PRAIA = 1.5, VEL_NADO = 0.45;   // tiles por segundo
        let cachePraia = { chave: null };
        const cacheRoteiro = new Map();
        function praiaDe(todas) {
            const itens = todas.filter((c) => c.y >= AREIA_Y && c.y < MAPA.mar.y);
            const chave = itens.map((c) => c.tipo + c.x + ',' + c.y).join(';');
            if (cachePraia.chave === chave) return cachePraia;
            cacheRoteiro.clear();
            const assentos = itens.filter((c) => ASSENTO_PRAIA[c.tipo]);
            const barracas = itens.filter((c) => BARRACA_PRAIA[c.tipo]);
            const outros = itens.length - assentos.length - barracas.length;
            const atrai = assentos.length + barracas.length * 2 + Math.min(outros, 8) * 0.5;
            const xs = itens.map((c) => c.x);
            cachePraia = {
                chave, assentos, barracas, atrai,
                vazio: Math.max(6, 100 - atrai * 13),                 // segundos sem ninguém entre um banhista e o próximo
                passeantes: itens.length ? Math.min(7, Math.floor(atrai / 2)) : 0,
                x0: xs.length ? Math.max(0, Math.min(...xs) - 7) : 0,
                x1: xs.length ? Math.min(MAPA.w - 1, Math.max(...xs) + 7) : 0
            };
            return cachePraia;
        }
        // passos: { de, para, nado } andando (de/para em tiles) | { em, seg, modo } parado; o item fica na mão até o fim
        function montarRoteiro(passos, total) {
            let t = 0;
            const r = passos.map((p) => {
                const dur = p.para ? Math.hypot(p.para[0] - p.de[0], p.para[1] - p.de[1]) / (p.nado ? VEL_NADO : VEL_PRAIA) : p.seg;
                const o = { ...p, ini: t, dur: Math.max(0.05, dur) };
                t += o.dur;
                return o;
            });
            if (total && t < total) r.push({ em: null, seg: total - t, modo: 'fora', ini: t, dur: total - t });
            return { passos: r, total: Math.max(total || 0, t) };
        }
        function ondeNoRoteiro(rot, s) {
            const p = rot.passos.find((x) => s < x.ini + x.dur) || rot.passos[rot.passos.length - 1];
            if (p.para) {
                const f = Math.min(1, Math.max(0, (s - p.ini) / p.dur));
                return { x: p.de[0] + (p.para[0] - p.de[0]) * f, y: p.de[1] + (p.para[1] - p.de[1]) * f, modo: p.nado ? 'nadando' : 'andando',
                         flip: p.para[0] < p.de[0], item: p.item };
            }
            return { x: p.em ? p.em[0] : 0, y: p.em ? p.em[1] : 0, modo: p.modo, flip: false, item: p.item };
        }
        const BEIRA = () => MAPA.mar.y - 0.2;
        // o banhista do assento c, na volta n (cada volta é outra pessoa, com outro passeio)
        function roteiroAssento(c, n, P) {
            const k = 'a' + c.x + ',' + c.y + ':' + n;
            if (cacheRoteiro.has(k)) return cacheRoteiro.get(k);
            const r = rng(c.x * 4111 + c.y * 977 + n * 7919);
            const lado = r() < 0.5 ? -1 : 1;
            const entra = [Math.max(-2, Math.min(MAPA.w + 1, c.x + lado * (9 + Math.floor(r() * 6)))), AREIA_Y + 1.6 + r()];
            const sai = [Math.max(-2, Math.min(MAPA.w + 1, c.x - lado * (9 + Math.floor(r() * 6)))), AREIA_Y + 1.6 + r()];
            const sent = [c.x, c.y], frente = [c.x, c.y + 0.8];
            const ax = c.x + Math.round((r() - 0.5) * 4), beira = [ax, BEIRA()];
            const passos = [{ de: entra, para: frente }, { de: frente, para: sent }, { em: sent, seg: 10 + r() * 14, modo: 'sentado' }];
            if (r() < 0.85) {   // vai nadar
                const n1 = [ax + 1 + r() * 2, MAPA.mar.y + 0.7], n2 = [ax - 1 - r() * 2, MAPA.mar.y + 1];
                passos.push({ de: sent, para: beira }, { de: beira, para: n1, nado: true }, { de: n1, para: n2, nado: true },
                    { de: n2, para: [ax, MAPA.mar.y + 0.5], nado: true }, { de: [ax, MAPA.mar.y + 0.5], para: beira, nado: true },
                    { de: beira, para: sent }, { em: sent, seg: 8 + r() * 10, modo: 'sentado' });
            }
            const bs = cachePraia.barracas;
            if (bs.length && r() < 0.8) {   // vai comprar
                const b = bs[Math.floor(r() * bs.length)], item = BARRACA_PRAIA[b.tipo], balcao = [b.x + (r() - 0.5) * 0.6, b.y + 1];
                passos.push({ de: sent, para: balcao }, { em: balcao, seg: 3 + r() * 2, modo: 'comprando' },
                    { de: balcao, para: sent, item }, { em: sent, seg: 12 + r() * 10, modo: 'sentado', item });
            }
            passos.push({ de: sent, para: frente }, { de: frente, para: sai });
            let rot = montarRoteiro(passos, 0);
            const pausa = cachePraia.vazio * (0.6 + r() * 0.8);
            if (rot.total + pausa > P) {   // não coube: tira o tempo sentado
                const sobra = P - pausa - rot.total;
                passos.forEach((p) => { if (p.modo === 'sentado') p.seg = Math.max(3, p.seg + sobra / 3); });
                rot = montarRoteiro(passos, 0);
            }
            rot = montarRoteiro(passos, P);
            if (cacheRoteiro.size > 300) cacheRoteiro.clear();
            cacheRoteiro.set(k, rot);
            return rot;
        }
        // quem só passeia: atravessa a areia, às vezes para na barraca, às vezes dá um mergulho
        function roteiroPasseio(i, n, P) {
            const k = 'p' + i + ':' + n;
            if (cacheRoteiro.has(k)) return cacheRoteiro.get(k);
            const r = rng(i * 15731 + n * 104729 + 17), pr = cachePraia;
            const ida = r() < 0.5, y = AREIA_Y + 2 + r() * 2.2;
            const a = [ida ? pr.x0 - 3 : pr.x1 + 3, y], b = [ida ? pr.x1 + 3 : pr.x0 - 3, y + (r() - 0.5)];
            const passos = [];
            let atual = a;
            const ir = (para, extra) => { passos.push({ de: atual, para, ...extra }); atual = para; };
            if (pr.barracas.length && r() < 0.45) {
                const bb = pr.barracas[Math.floor(r() * pr.barracas.length)], item = BARRACA_PRAIA[bb.tipo], balcao = [bb.x, bb.y + 1];
                ir(balcao); passos.push({ em: balcao, seg: 3, modo: 'comprando' });
                ir(b, { item });
            } else if (r() < 0.5) {
                const mx = a[0] + (b[0] - a[0]) * (0.3 + r() * 0.4);
                ir([mx, BEIRA()]); ir([mx + (ida ? 2 : -2), MAPA.mar.y + 0.9], { nado: true }); ir([mx + (ida ? 3 : -3), BEIRA()], { nado: true }); ir(b);
            } else ir(b);
            const rot = montarRoteiro(passos, P);
            cacheRoteiro.set(k, rot);
            return rot;
        }
        function pessoaPraia(seed, n) { return banhistaDe(seed + n * 31, n * 17 + 3); }
        // quem está sentado agora no assento c (para o desenho pequeno em cima da cadeira), ou null
        function sentadoEm(c, tempo) {
            if (!cachePraia.chave) return null;
            const P = 150 + cachePraia.vazio, s0 = tempo / 1000 + ((c.x * 37 + c.y * 91) % 97) / 97 * P;
            const n = Math.floor(s0 / P), o = ondeNoRoteiro(roteiroAssento(c, n, P), s0 - n * P);
            return o.modo === 'sentado' ? { cfg: pessoaPraia(c.x * 7 + c.y, n), item: o.item } : null;
        }
        // põe na lista "em pé" quem está andando, nadando ou comprando (e devolve os itens na mão, para depois)
        function pessoasDaPraia(todas, tempo, pe, naTela) {
            const pr = praiaDe(todas);
            const naMao = [];
            if (!pr.chave || !deDia()) return naMao;
            const por = (tx, ty, cfg, o, andaRapido) => {
                if (!naTela(Math.floor(tx), Math.floor(ty))) return;
                const x = wx(tx), y = wy(ty) - 8;
                const nadando = naAgua(x, y);
                const passo = o.modo === 'andando' && Math.floor(tempo / (andaRapido ? 130 : 160) + tx * 3) % 2 ? -1 : 0;
                const bob = o.modo === 'comprando' ? (Math.floor(tempo / 300) % 2 ? -1 : 0) : nadando ? 0 : passo;
                pe.push({ img: avatarCanvas(cfg), x, y, flip: o.flip, bob, nadando });
                if (o.item && !nadando) naMao.push({ item: o.item, x: x + (o.flip ? 0 : 9), y: y + 6 + bob });
            };
            const P = 150 + pr.vazio;
            for (const c of pr.assentos) {
                const s0 = tempo / 1000 + ((c.x * 37 + c.y * 91) % 97) / 97 * P;
                const n = Math.floor(s0 / P), o = ondeNoRoteiro(roteiroAssento(c, n, P), s0 - n * P);
                if (o.modo === 'andando' || o.modo === 'nadando' || o.modo === 'comprando') por(o.x, o.y, pessoaPraia(c.x * 7 + c.y, n), o);
            }
            const PP = 60 + pr.vazio / 2;
            for (let i = 0; i < pr.passeantes; i++) {
                const s0 = tempo / 1000 + (i * 0.37 % 1) * PP;
                const n = Math.floor(s0 / PP), o = ondeNoRoteiro(roteiroPasseio(i, n, PP), s0 - n * PP);
                if (o.modo !== 'fora') por(o.x, o.y, pessoaPraia(900 + i * 13, n), o, true);
            }
            return naMao;
        }
        let energiaFrac = 0;   // 0..1, para as luzinhas das baterias
        // a fábrica automática em uso: algum item da rede saindo dela ou chegando nela agora
        // (null parada; senão o ícone do item e o quanto ele está na porta, 0..1)
        function fabricaEmUso(c) {
            const k = c.x + ',' + c.y, agoraMs = relogio();
            let uso = null;
            for (const v of viagensFn()) {
                if (v.fab !== k) continue;
                const f = (agoraMs - v.inicio) / v.dur;
                if (f < -0.05 || f > 1.05) continue;
                const perto = v.entra ? f : 1 - f;   // entrando: chega no fim; saindo: está no começo
                const porta = perto > 0.8 ? Math.min(1, (perto - 0.8) / 0.2) : 0;
                if (!uso || porta > uso.porta) uso = { icone: v.icone, porta };
            }
            return uso;
        }
        /* fábrica automática (2x2: duas prensas em cima, duas máquinas com telinha embaixo):
           parada, as luzinhas piscam devagar e sai um fio de fumaça; trabalhando, as luzinhas
           correm em verde, a telinha da esquerda mostra o item passando, a da direita uma barra
           enchendo, a fumaça engrossa e solta faísca na porta quando um item entra ou sai */
        function desenharFabrica(c, x, y, t, px) {
            const uso = fabricaEmUso(c);
            const leds = [[6, 4], [9, 4], [6, 6], [9, 6], [22, 4], [25, 4], [22, 6], [25, 6]];
            if (uso) {
                const passo = Math.floor(t / 120) % leds.length;
                leds.forEach(([lx, ly], k) => px(x + lx, y + ly, k === passo || k === (passo + 4) % 8 ? '#7dff6a' : '#3c8c4a', 2, 1));
                const tela = (sx, sy) => { q.fillStyle = 'rgba(125, 255, 106, 0.35)'; q.fillRect(x + sx, y + sy, 6, 5); };
                tela(5, 19); tela(21, 19);
                if (uso.icone != null) miniTile(uso.icone, x + 5, y + 18, 6);
                const enche = Math.floor(t / 90) % 6;
                px(x + 21, y + 22, '#7dff6a', enche + 1, 1);
                if (uso.porta > 0) {   // a faísca na porta: quatro pontinhos abrindo
                    const r = 2 + uso.porta * 5, cx = x + 16, cy = y + 16;
                    q.globalAlpha = 1 - uso.porta * 0.6;
                    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) px(cx + dx * r - 1, cy + dy * r - 1, '#fdf3a7', 2, 2);
                    q.globalAlpha = 1;
                }
            } else if (Math.floor(t / 900) % 2) {
                leds.forEach(([lx, ly], k) => { if (k % 3 === 0) px(x + lx, y + ly, '#fdbe53', 2, 1); });
            }
            const puffs = uso ? 4 : 2, ritmo = uso ? 700 : 1300;
            for (let k = 0; k < puffs; k++) {
                const f = (t / ritmo + k / puffs) % 1;
                q.globalAlpha = 0.7 * (1 - f);
                const tam = 2 + Math.round(f * (uso ? 3 : 2));
                px(x + 26 + Math.sin(f * 6 + k) * 1.5 + f * 3, y + 2 - f * (uso ? 14 : 10), k % 2 ? '#8b9bb4' : '#c0cbdc', tam, tam);
            }
            q.globalAlpha = 1;
        }
        function desenharMaquinas(lista, tempo) {
            const px = (x, y, cor, w = 1, h = 1) => { q.fillStyle = cor; q.fillRect(Math.round(x), Math.round(y), w, h); };
            for (const c of lista) {
                if (c.sobrecarga_em) {   // fase 77: o raio ou o furacão deu sobrecarga: fumaça escura e faísca vermelha
                    const x = wx(c.x), y = wy(c.y), t = tempo + (c.x * 137 + c.y * 61) % 997, topo = c.tipo === 'turbina' ? y - 13 : y + 1;
                    for (let k = 0; k < 4; k++) {
                        const f = (t / 1700 + k / 4) % 1, tam = 3 + Math.round(f * 4);
                        q.globalAlpha = 0.85 * (1 - f);
                        px(x + 8 + Math.sin(f * 6 + k * 2) * 3 + f * 4 - tam / 2, topo - f * 18 - tam / 2, k % 2 ? '#3f2631' : '#5d5560', tam, tam);
                    }
                    q.globalAlpha = 1;
                    const pisca = Math.floor(t / 220) % 5;
                    if (pisca === 0) { px(x + 5, topo + 2, '#ff3b2f', 2, 2); px(x + 10, topo + 4, '#fdbe53', 1, 2); }
                    else if (pisca === 2) { px(x + 10, topo + 1, '#ff3b2f', 2, 2); px(x + 6, topo + 5, '#fdbe53', 2, 1); }
                    continue;
                }
                const tipo = ANIMA[c.tipo];
                if (!tipo) continue;
                const x = wx(c.x), y = wy(c.y), t = tempo + (c.x * 137 + c.y * 61) % 997;   // cada uma no seu ritmo
                if (tipo === 'agua') {
                    const alcance = c.tipo === 'aspersor' ? 12 : 9;
                    for (let k = 0; k < 6; k++) {
                        const f = (t / 1100 + k / 6) % 1, dir = k % 2 ? 1 : -1, lado = Math.floor(k / 2) - 1;
                        q.globalAlpha = 1 - f * 0.8;
                        px(x + 8 + dir * f * alcance + lado * f * 3, y + 3 - Math.sin(f * Math.PI) * 7 + f * 6, k % 3 ? PAL.b : PAL.w);
                    }
                    q.globalAlpha = 1;
                } else if (tipo === 'nevoa') {
                    for (let k = 0; k < 3; k++) {
                        const f = (t / 1400 + k / 3) % 1;
                        q.globalAlpha = 0.55 * (1 - f);
                        const tam = 2 + Math.round(f * 3);
                        px(x + 7 + Math.sin(f * 5 + k * 2) * 3 - tam / 2, y + 2 - f * 10, '#dff3d4', tam, tam);
                    }
                    q.globalAlpha = 1;
                } else if (tipo === 'luz') {
                    if (!c.desligado && Math.floor(t / 450) % 2) {   // (alarme sem energia: desligado)
                        q.globalAlpha = 0.35; px(x + 5, y - 1, '#ff6b5a', 6, 4); q.globalAlpha = 1;
                        px(x + 7, y, '#ff3b2f', 2, 2);
                    }
                    if (c.desligado && Math.floor(t / 600) % 2) {   // fase 83: sem energia, um raio vermelho piscando em cima
                        const rx = x + 5, ry = y - 9;
                        px(rx + 2, ry, '#3f2631', 4, 1); px(rx + 1, ry + 1, '#ff3b2f', 3, 2); px(rx, ry + 3, '#ff3b2f', 5, 1);
                        px(rx + 2, ry + 4, '#ff3b2f', 2, 2); px(rx + 1, ry + 6, '#ff3b2f', 2, 1);
                    }
                } else if (tipo === 'robo') {
                    if (Math.floor(t / 700) % 3 === 0) px(x + 8, y + 1, '#7dff6a', 1, 1);   // luzinha da antena piscando
                } else if (tipo === 'fabrica') {
                    desenharFabrica(c, x, y, t, px);
                } else if (tipo === 'banhista' || tipo === 'fregues') {   // fase 97
                    if (!deDia()) continue;
                    if (tipo === 'fregues' && Math.floor(t / 4000) % 3 === 2) continue;   // o freguês vai e volta
                    const sent = tipo === 'banhista' ? sentadoEm(c, tempo) : null;   // fase 108: a cadeira fica vazia quando ele sai
                    if (tipo === 'banhista' && !sent) continue;
                    const cv = avatarCanvas(sent ? sent.cfg : banhistaDe(c.x, c.y + Math.floor(t / 12000)));
                    if (sent && sent.item && A_ITEM_PRAIA[sent.item] != null) miniTile(A_ITEM_PRAIA[sent.item], x + 14, y + 6 + Math.round(Math.sin(t / 700)), 7);
                    const bx = tipo === 'banhista' ? x + 6 : x + 2, by = tipo === 'banhista' ? y + 3 : y + 9;
                    const pulo = tipo === 'fregues' ? Math.round(Math.abs(Math.sin(t / 260)) * 1) : Math.round(Math.sin(t / 900) * 0.6);
                    q.drawImage(cv, 0, 0, 16, 16, Math.round(bx), Math.round(by - pulo), 12, 12);
                } else if (tipo === 'fumaca') {
                    const sx = x + 4, sy = y + 3;
                    for (let k = 0; k < 2; k++) {
                        const f = (t / 1300 + k / 2) % 1;
                        q.globalAlpha = 0.7 * (1 - f);
                        const tam = 2 + Math.round(f * 2);
                        px(sx + Math.sin(f * 6 + k) * 1.5 + f * 3, sy - f * 10, k ? '#8b9bb4' : '#c0cbdc', tam, tam);
                    }
                    q.globalAlpha = 1;
                } else if (tipo === 'po') {
                    for (let k = 0; k < 3; k++) {
                        const f = (t / 600 + k / 3) % 1;
                        q.globalAlpha = 1 - f;
                        px(x + 3 + k * 5 + Math.sin(t / 90 + k) , y + 12 + f * 4, '#c9a46a');
                    }
                    q.globalAlpha = 1;
                } else if (tipo === 'reflexo') {
                    const ciclo = (t % 3200) / 3200, h = new Date().getHours();
                    if (h >= 6 && h < 18 && ciclo < 0.35) {
                        const p = ciclo / 0.35;
                        q.globalAlpha = 0.8;
                        for (let d = 0; d < 6; d++) px(x + 2 + p * 14 - d * 0.5, y + 3 + d, PAL.w);
                        q.globalAlpha = 1;
                    }
                } else if (tipo === 'roda') {   // fase 78: a roda d'água girando do lado, e a água caindo
                    const cx = x + 13, cy = y + 9, ang = t / 600;
                    // a usina vem com o próprio tanque d'água embaixo da roda (não precisa de rio nem de lago)
                    q.fillStyle = '#3f2631'; q.fillRect(x + 7, y + 11, 10, 5);
                    q.fillStyle = '#3b7dd8'; q.fillRect(x + 8, y + 12, 8, 3);
                    px(x + 9 + Math.floor(t / 300) % 6, y + 12, '#9fd3ff', 2, 1);
                    q.fillStyle = '#5a3a20'; q.fillRect(cx - 1, cy - 1, 3, 3);
                    for (let k = 0; k < 4; k++) {
                        const a = ang + k * Math.PI / 2;
                        px(cx + Math.cos(a) * 4, cy + Math.sin(a) * 4, '#8a5a32', 2, 2);
                        px(cx + Math.cos(a) * 2, cy + Math.sin(a) * 2, '#6b4426');
                    }
                    for (let k = 0; k < 3; k++) {
                        const f = (t / 500 + k / 3) % 1;
                        q.globalAlpha = 1 - f; px(cx + 4, cy - 6 + f * 12, PAL.b); q.globalAlpha = 1;
                    }
                } else if (tipo === 'carga') {
                    const acesas = Math.round(energiaFrac * 3);
                    for (let k = 0; k < 3; k++) {
                        const ligada = k < acesas || (k === acesas && Math.floor(t / 500) % 2);
                        px(x + 12, y + 11 - k * 3, ligada ? (acesas <= 1 ? '#fdbe53' : '#6abe30') : '#3f2631', 2, 2);
                    }
                } else if (tipo === 'estufa') {
                    q.globalAlpha = 0.12 + 0.1 * Math.sin(t / 600);
                    px(x + 2, y + 4, '#fff3a0', 12, 9);
                    q.globalAlpha = 1;
                } else if (tipo === 'reator') {   // fase 79: brilho redondo na janela do núcleo e vapor saindo da torre
                    q.save();
                    q.globalCompositeOperation = 'screen';
                    q.globalAlpha = 0.45 + 0.3 * Math.sin(t / 450);
                    q.drawImage(halo('125, 255, 106'), x + 24 - 9, y + 22 - 9, 18, 18);
                    q.restore();
                    for (let k = 0; k < 4; k++) {
                        const f = (t / 2600 + k / 4) % 1, tam = 3 + Math.round(f * 5);
                        q.globalAlpha = 0.75 * (1 - f);
                        px(x + 10 + Math.sin(f * 5 + k) * 2 + f * 4 - tam / 2, y + 1 - f * 16 - tam / 2, k % 2 ? '#e4ebf3' : '#ffffff', tam, tam);
                    }
                    q.globalAlpha = 1;
                    if (Math.floor(t / 250) % 6 === 0) icone(q, 'brilho', x + 26, y + 17);
                }
            }
        }

        /* ---- canos de vidro: braços para os lados ligados (outro cano, oficina, canteiro, baú,
           celeiro), um anel de metal no meio e os itens passando por dentro ---- */
        function desenharCano(c, tempo) {
            const x = wx(c.x), y = wy(c.y), l = c.cano || [false, false, false, false];   // leste, oeste, sul, norte
            const vidro = 'rgba(214,236,255,.5)', borda = 'rgba(63,38,49,.65)', brilho = 'rgba(255,255,255,.85)';
            const braco = (x0, y0, w, h, deitado) => {
                q.fillStyle = borda; q.fillRect(x0, y0, w, h);
                q.fillStyle = vidro;
                if (deitado) q.fillRect(x0, y0 + 1, w, h - 2); else q.fillRect(x0 + 1, y0, w - 2, h);
                q.fillStyle = brilho;
                if (deitado) q.fillRect(x0, y0 + 1, w, 1); else q.fillRect(x0 + 1, y0, 1, h);
            };
            if (l[0]) braco(x + 8, y + 5, 8, 6, true);
            if (l[1]) braco(x, y + 5, 8, 6, true);
            if (l[2]) braco(x + 5, y + 8, 6, 8, false);
            if (l[3]) braco(x + 5, y, 6, 8, false);
            q.fillStyle = '#566c86'; q.fillRect(x + 4, y + 4, 8, 8);
            q.fillStyle = '#8b9bb4'; q.fillRect(x + 5, y + 5, 6, 6);
            // luzinha no anel: verde passando quando a rede está ligada e com energia, vermelha piscando
            // sem energia, apagada quando o cano não liga nada
            if (c.rede === 'ok' && c.ativa) {   // oficina da rede trabalhando: a onda corre pelos canos
                const onda = (Math.sin(tempo / 260 - (c.x + c.y) * 0.9) + 1) / 2;
                q.fillStyle = `rgba(110, 230, 140, ${(0.3 + 0.45 * onda).toFixed(2)})`;
            } else if (c.rede === 'ok') {   // ligada, mas parada: luzinha fraca e quieta
                q.fillStyle = 'rgba(110, 230, 140, 0.25)';
            } else if (c.rede === 'sem_energia') {
                q.fillStyle = Math.floor(tempo / 500) % 2 ? '#e8434a' : '#7a2a30';
            } else {
                q.fillStyle = 'rgba(214,236,255,.85)';
            }
            q.fillRect(x + 7, y + 6, 2, 4);   // fase 67: luzinha redonda (a cruz, sem os cantos)
            q.fillRect(x + 6, y + 7, 4, 2);
        }
        // itens pequenos (8 px) andando dentro dos canos: ingrediente da fonte para a oficina, produto de volta
        function miniTile(i, x, y, tam = 8) {
            if (i == null) return;
            let pacote = 'farm';
            if (i >= 1000) { i -= 1000; pacote = 'propria'; }
            const img = pacote === 'propria' ? atlasProprio : (atlasDaEstacao && atlasDaEstacao.farm) || atlas.farm;
            q.drawImage(img, (i % COLS) * T, Math.floor(i / COLS) * T, T, T, Math.round(x), Math.round(y), tam, tam);
        }
        // viagens dos itens pela rede (fase 39): cada item anda do ponto de saída, pelos canos, até
        // o destino, só enquanto a viagem acontece (o servidor marca a hora). Sem cano (do canteiro,
        // cercado, árvore ou lago para o baú encostado) ele dá um pulinho.
        let viagensFn = () => [];
        function desenharViagens() {
            const agoraMs = relogio();
            for (const v of viagensFn()) {
                const t = (agoraMs - v.inicio) / v.dur;
                if (t < 0 || t > 1) continue;
                const p = v.pontos, n = p.length - 1;
                if (n < 1) continue;
                const pos = t * n, i = Math.min(n - 1, Math.floor(pos)), f = pos - i;
                const [ax, ay] = p[i], [bx, by] = p[i + 1];
                const x = wx(ax + (bx - ax) * f) + 8, y = wy(ay + (by - ay) * f) + 8;
                const pulo = v.direto ? -Math.round(Math.sin(t * Math.PI) * 7) : 0;
                if (!v.direto) {   // uma sombrinha dentro do vidro ajuda a ver o item passando
                    q.fillStyle = 'rgba(63, 38, 49, .25)';
                    q.fillRect(Math.round(x) - 4, Math.round(y) + 3, 8, 2);
                }
                miniTile(v.icone, x - 4, y - 4 + pulo);   // (fase 47: de volta ao item pequeno dentro do cano)
            }
        }

        function desenharCercado(c, s, tempo) {
            const k = s.cercado, x = wx(c.x), y = wy(c.y), w = k.w * T, h = k.h * T;
            const ret = (rx, ry, rw, rh, cor) => { q.fillStyle = cor; q.fillRect(Math.round(rx), Math.round(ry), rw, rh); };
            const r = rng(c.x * 131 + c.y * 17 + 7);
            if (k.chao === 'terra' || k.chao === 'lama') {   // chão batido (galinhas) ou terra com poças de lama (porcos)
                ret(x + 5, y + 7, w - 10, h - 13, '#c98f5a');
                ret(x + 6, y + 6, w - 12, 1, '#c98f5a');
                for (let n = 0; n < w * h / 40; n++) ret(x + 6 + r() * (w - 14), y + 8 + r() * (h - 16), 2, 1, r() < 0.5 ? '#b07745' : '#dcac78');
                if (k.chao === 'lama') {
                    for (const [px, py, pw] of [[0.25, 0.45, 22], [0.62, 0.62, 18]]) {
                        ret(x + w * px, y + h * py, pw, 7, '#6b4330');
                        ret(x + w * px + 2, y + h * py - 1, pw - 4, 1, '#6b4330');
                        ret(x + w * px + 3, y + h * py + 1, pw - 10, 1, '#8a5a3c');
                    }
                }
            } else if (k.chao === 'feno') {   // coelhos: palha espalhada
                for (let n = 0; n < w * h / 22; n++) ret(x + 6 + r() * (w - 14), y + 7 + r() * (h - 14), 3, 1, r() < 0.5 ? '#e9c46a' : '#d4a743');
            } else if (k.chao === 'lago') {   // patos: laguinho com borda de grama clara (fase 76: menor, com chão em volta)
                const L = laguinhoPato(c), lx = L.x0, ly = L.y0, lw = L.x1 - L.x0, lh = L.y1 - L.y0;
                ret(lx + 1, ly - 2, lw - 2, lh + 4, '#7fae5a');                 // a margem
                ret(lx - 1, ly, lw + 2, lh, '#7fae5a');
                ret(lx + 2, ly - 1, lw - 4, lh + 2, '#3f78b0');                  // a água, com a borda funda
                ret(lx, ly + 1, lw, lh - 2, '#3f78b0');
                ret(lx + 2, ly + 1, lw - 4, lh - 2, '#5f98d8');
                ret(lx + 2, ly + 1, lw - 4, 2, '#4a86c8');                        // sombra da margem em cima
                desenharAguaViva(tempo, L);
            }
            s.grade.forEach((linha, dy) => linha.forEach((i, dx) => { if (i != null) tile(q, i, x + dx * T, y + dy * T, false, s.p); }));
            if (k.chao === 'cocho') {   // cocho de água no canto, por cima da cerca (fase 79: as duas metades, como no pasto)
                tile(q, 110, x + T + 2, y + T - 3);
                tile(q, 111, x + 2 * T + 2, y + T - 3);
            }
        }

        // o alcance de um item colocado (irrigador, alarme, estufa...): some sozinho em 5 s
        function desenharAlcance() {
            const resta = alcance.ate - performance.now();
            if (resta <= 0) { alcance = null; return; }
            const r = alcance.raio, rx = wx(alcance.x - r), ry = wy(alcance.y - r), lado = (r * 2 + 1) * T;
            q.globalAlpha = Math.min(1, resta / 600);
            q.fillStyle = 'rgba(153,216,248,.25)';
            q.fillRect(rx, ry, lado, lado);
            moldura(rx, ry, lado, lado, PAL.b);
            q.globalAlpha = 1;
        }

        // segurando o dedo num item: moldura amarela e a barrinha enchendo até os 3 s
        function desenharSegurar(lista) {
            const p = (performance.now() - segurando.t0) / SEGURAR_MS;
            if (p < 0.08) return;
            let x, y, w = T, h = T, alto = 0;
            if (typeof segurando.alvo === 'number') {
                ({ x, y } = posCanteiro(segurando.alvo));
            } else {
                const [cx, cy] = segurando.alvo.slice(2).split(',').map(Number);
                const c = lista.find((k) => k.x === cx && k.y === cy);
                if (!c) return;
                const a = arteItem(c.tipo, EST);
                x = wx(cx); y = wy(cy); w = T * (a.w || 1); h = T * (a.h || 1);
                alto = a.topo2 != null ? 2 * T : a.topo != null ? T : 0;
            }
            moldura(x, y, w, h, PAL.y);
            const bw = Math.max(14, w - 4), bx = x + Math.round((w - bw) / 2), by = y - alto - 7;
            q.fillStyle = PAL.o; q.fillRect(bx, by, bw, 4);
            q.fillStyle = PAL.d; q.fillRect(bx + 1, by + 1, bw - 2, 2);
            q.fillStyle = PAL.y; q.fillRect(bx + 1, by + 1, Math.max(1, Math.round((bw - 2) * Math.min(1, p))), 2);
        }

        // vara, linha e boia do Bira; balão com peixe quando tem peixe no cesto
        function desenharPescaria(tempo) {
            const hx = wx(LAGO.x) + 13, hy = wy(LAGO.y + 2) + 9;          // mão
            const tx = hx + 16, ty = hy - 12;                               // ponta da vara, já por cima da água
            q.fillStyle = '#8a4a2b';
            for (let k = 0; k <= 16; k++) q.fillRect(Math.round(hx + k), Math.round(hy - k * 12 / 16), 1, 1);
            const morde = lago.prontos > 0 && Math.floor(tempo / 260) % 3 === 0;
            const bx = tx + 8, by = hy + 4 + (morde ? 2 : Math.floor(tempo / 600) % 2);
            q.fillStyle = 'rgba(255,255,255,.7)';
            for (let k = 0; k <= 8; k++) q.fillRect(Math.round(tx + k), Math.round(ty + (by - ty) * (k / 8) ** 1.6), 1, 1);
            q.fillStyle = '#e8434a'; q.fillRect(bx, by, 2, 1);
            q.fillStyle = '#ffffff'; q.fillRect(bx, by + 1, 2, 1);
            if (lago.prontos > 0) {
                const px = wx(LAGO.x) + 1, py = wy(LAGO.y + 1) - 6 + (Math.floor(tempo / 350) % 2);
                balao(px - 2, py, 20, 18);
                tile(q, lago.ultimo || 1030, px, py + 1);
                if (lago.prontos >= lago.max && Math.floor(tempo / 300) % 3) icone(q, 'brilho', px + 15, py - 3);
            }
        }

        /* ---- clima por cima de tudo (na tela, não no mundo) ---- */
        function desenharEstacao(tempo, k) {
            const W = canvas.width, H = canvas.height, passo = Math.max(2, Math.round(k));
            const neve = EST === 'inverno', outono = EST === 'outono', primavera = EST === 'primavera';
            if (!neve && !outono && !primavera) return;
            const forte = neve && (clima === 'chuva' || clima === 'tempestade');
            const lado = forte ? 42 : 105;
            const n = neve ? Math.round((W * H) / (lado * lado * dpr * dpr)) : outono ? 12 : 8;
            for (let i = 0; i < n; i++) {
                const vel = neve ? (forte ? 0.05 : 0.022) * (0.7 + (i % 5) * 0.12) : outono ? 0.028 : 0.018;
                const y = (((i * 211) % H) + tempo * vel * passo) % (H + 20) - 10;
                const balanco = Math.sin(tempo / (neve ? 900 : 650) + i * 1.7) * passo * (neve ? 3 : 9);
                const x = ((((i * 97) % W) + balanco + (neve ? 0 : tempo * 0.012 * passo)) % W + W) % W;
                if (neve) {
                    ctx.fillStyle = 'rgba(255,255,255,.9)';
                    const g = i % 4 === 0 ? 2 : 1;
                    ctx.fillRect(Math.round(x), Math.round(y), passo * g, passo * g);
                } else {
                    ctx.fillStyle = outono ? ['#e38628', '#c34b35', '#fdbe53'][i % 3] : ['#f4b4d8', '#ffffff', '#f7a1c4'][i % 3];
                    const vira = Math.floor(tempo / 280 + i) % 2;   // girando no ar: deitada, em pé
                    ctx.fillRect(Math.round(x), Math.round(y), passo * (vira ? 2 : 1), passo * (vira ? 1 : 2));
                }
            }
        }

        // fase 77: o relâmpago da tempestade, de 4 a 7 s um do outro: a tela pisca e o raio desce em zigue-zague
        function desenharRelampago(tempo, k) {
            const W = canvas.width, H = canvas.height, ciclo = Math.floor(tempo / 5500), fase = tempo % 5500;
            const espera = 1200 + ((ciclo * 2654435761) >>> 0) % 3000;   // cada relâmpago numa hora do ciclo
            const dt = fase - espera;
            if (dt < 0 || dt > 260) return;
            ctx.fillStyle = `rgba(255, 255, 255, ${(0.45 * (1 - dt / 260)).toFixed(3)})`;
            ctx.fillRect(0, 0, W, H);
            if (dt > 140) return;
            const passo = Math.max(2, Math.round(k)), sem = (ciclo * 40503) >>> 0;
            let x = W * (0.15 + (sem % 70) / 100), y = 0;
            for (let i = 0; y < H * 0.55; i++) {
                const ny = y + passo * (6 + ((sem >> (i % 16)) & 3) * 2), nx = x + passo * ((((sem >> (i % 13)) & 7) - 3.5) * 1.6);
                const n = Math.max(1, Math.round((ny - y) / passo));
                for (let j = 0; j <= n; j++) {
                    const px = Math.round(x + (nx - x) * j / n), py = Math.round(y + (ny - y) * j / n);
                    ctx.fillStyle = 'rgba(253, 240, 160, .45)'; ctx.fillRect(px - passo, py, passo * 4, passo);   // o brilho em volta
                    ctx.fillStyle = '#ffffff'; ctx.fillRect(px, py, passo * 2, passo);
                }
                x = nx; y = ny;
            }
        }

        function desenharClima(tempo, k) {
            const W = canvas.width, H = canvas.height;
            desenharEstacao(tempo, k);
            if ((clima === 'chuva' || clima === 'tempestade') && EST === 'inverno') {   // no inverno a chuva vira neve (desenhada acima)
                ctx.fillStyle = clima === 'tempestade' ? 'rgba(40, 50, 80, .40)' : 'rgba(70, 80, 100, .12)';
                ctx.fillRect(0, 0, W, H);
                if (clima === 'tempestade') desenharRelampago(tempo, k);   // a nevasca também troveja
                return;
            }
            if (clima === 'tempestade') {   // fase 77: chuva forte e de lado, céu bem escuro e o relâmpago
                ctx.fillStyle = 'rgba(25, 35, 70, .42)';
                ctx.fillRect(0, 0, W, H);
                ctx.fillStyle = 'rgba(190, 225, 255, .6)';
                const passo = Math.max(2, Math.round(k)), alto = passo * 7, n = Math.round((W * H) / (60 * 60 * dpr * dpr));
                for (let i = 0; i < n; i++) {
                    const x = ((i * 97) % W + (tempo * 0.18 * passo)) % W;
                    const y = ((i * 211) % H + tempo * 0.9 * passo) % H;
                    ctx.fillRect(Math.round(x), Math.round(y), passo, alto);
                    ctx.fillRect(Math.round(x) + passo, Math.round(y) + alto - passo, passo, passo);
                }
                desenharRelampago(tempo, k);
                return;
            }
            if (clima === 'furacao') {   // fase 77: rajadas fortes, folhas e galhos voando, céu esverdeado
                ctx.fillStyle = 'rgba(40, 60, 55, .36)';
                ctx.fillRect(0, 0, W, H);
                const passo = Math.max(2, Math.round(k));
                ctx.fillStyle = 'rgba(255, 255, 255, .5)';
                for (let i = 0; i < 34; i++) {
                    const y = ((i * 131) % H + Math.sin(tempo / 300 + i) * passo * 6), x = ((i * 389) + tempo * 1.3 * passo) % (W + 300) - 150;
                    ctx.fillRect(Math.round(x), Math.round(y), passo * (18 + (i % 4) * 6), passo);
                }
                const cores = ['#4e974c', '#84c669', '#cf8254', '#e38628'];
                for (let i = 0; i < 18; i++) {
                    const x = ((i * 233) + tempo * (0.9 + (i % 3) * 0.3) * passo) % (W + 100) - 50;
                    const y = ((i * 173) % H) + Math.sin(tempo / 220 + i * 1.3) * passo * 10;
                    ctx.fillStyle = cores[i % 4];
                    const vira = Math.floor(tempo / 120 + i) % 2;
                    ctx.fillRect(Math.round(x), Math.round(y), passo * (vira ? 2 : 1), passo * (vira ? 1 : 2));
                }
                return;
            }
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
            if (visitante && !visitante.saindo && px >= visitante.x - 2 && px < visitante.x + T + 2 && py >= visitante.y - 22 && py < visitante.y + T) return 'visitante';
            const lista = [...atores.values()].sort((a, b) => b.y - a.y);
            for (const a of lista) {
                const topo = a.v && a.v.estado !== 'produzindo' ? a.y - 22 : a.y;
                if (px >= a.x - 1 && px < a.x + T + 1 && py >= topo && py < a.y + T) return 'a:' + a.id;
            }
            // fase 62: o barco atracado leva para o alto-mar; o píer (ou o lugar dele) abre a tela do píer
            if (zonasAtuais >= 7 && pierPronto && tx >= MAPA.pier.x + MAPA.pier.w && ty >= 37 && ty <= 40
                && tx <= MAPA.pier.x + MAPA.pier.w + Math.ceil(((NAVIOS[(barcoInfo && barcoInfo.nivel) || 1] || NAVIOS[1]).L) / T)) return 'barco';   // fase 104: o casco do navio
            if (zonasAtuais >= 7 && dentroRet(MAPA.pier, tx, ty)) return 'pier';   // fase 61
            const cant = listaCanteiros().find((k) => k.x === tx && k.y === ty);
            if (cant) return cant.posicao;
            const cons = (construcoesFn() || []).find((c) => {
                const a = arteItem(c.tipo, EST);
                return tx >= c.x && ty >= c.y && tx < c.x + (a.w || 1) && ty < c.y + (a.h || 1);
            });
            if (cons) return 'c:' + cons.x + ',' + cons.y;
            if (lagoNaTela() && dentroRet(LAGO, tx, ty)) return 'lago';
            if (tx >= MAPA.casa.x && tx < MAPA.casa.x + 3 && ty >= MAPA.casa.y && ty < MAPA.casa.y + 3) return 'casa';   // fase 66: quem dorme nela
            const c = retCeleiro();
            if (px >= c.x && py >= c.y && px < c.x + c.w && py < c.y + c.h) return 'celeiro';
            // terreno à venda: a placa ou qualquer pedaço de mata dele
            const zv = zonasVenda.find((z) => dentroRet(z, tx, ty));
            if (zv) { vendaTocada = zv.n; return 'venda'; }
            if (tx === RADIO.x && ty === RADIO.y) return 'radio';   // fase 107: o rádio, embaixo das barracas
            if (dentroRet(FEIRA, tx, ty)) return 'feira';
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

        /* ---- segurar 3 s num item ou canteiro (fora do modo construir): pega para mover ---- */
        function comecarSegurar(e) {
            pararSegurar();
            if (construcao.ativo || !cb.aoSegurar) return;
            const bruto = alvoEm(e.clientX, e.clientY);
            if (!(typeof bruto === 'number' || (typeof bruto === 'string' && bruto.startsWith('c:')))) return;
            segurando = { alvo: bruto, t0: performance.now(), cx: e.clientX, cy: e.clientY, id: e.pointerId };
            segurando.timer = setTimeout(() => {
                const s = segurando;
                segurando = null;
                ignorarCliqueAte = Infinity;   // até soltar o dedo
                if (toque) toque.segurou = true;
                cb.aoSegurar(traduzir(s.alvo));
            }, SEGURAR_MS);
        }
        function pararSegurar() {
            if (segurando) clearTimeout(segurando.timer);
            segurando = null;
        }
        function moverSegurar(e) {
            if (segurando && e.pointerId === segurando.id && Math.hypot(e.clientX - segurando.cx, e.clientY - segurando.cy) > 10) pararSegurar();
        }
        function soltarSegurar() {
            pararSegurar();
            if (ignorarCliqueAte === Infinity) ignorarCliqueAte = performance.now() + 500;
        }
        if (rolagem) {   // celular: os toques caem na camada de rolagem
            rolagem.addEventListener('pointerdown', comecarSegurar);
            rolagem.addEventListener('pointermove', moverSegurar);
            rolagem.addEventListener('pointerup', soltarSegurar);
            rolagem.addEventListener('pointercancel', soltarSegurar);
            rolagem.addEventListener('scroll', pararSegurar, { passive: true });
            rolagem.addEventListener('contextmenu', (e) => e.preventDefault());
        }

        let toque = null;   // { id, x, y, camX, camY, arrastou, ultX, ultY, ultT }
        canvas.addEventListener('pointerdown', (e) => {
            if (toque) return;   // ignora o segundo dedo
            inercia.vx = inercia.vy = 0;
            comecarSegurar(e);
            toque = { id: e.pointerId, x: e.clientX, y: e.clientY, camX: cam.x, camY: cam.y, arrastou: false,
                      ultX: e.clientX, ultY: e.clientY, ultT: performance.now() };
            if (e.pointerType !== 'mouse') { try { canvas.setPointerCapture(e.pointerId); } catch { /* ignora */ } }
        });
        canvas.addEventListener('pointermove', (e) => {
            moverSegurar(e);
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
                if (cb.aoPassar) cb.aoPassar(traduzir(alvo), vendaTocada);
            }
        });
        const soltar = (e) => {
            if (!toque || toque.id !== e.pointerId) return;
            soltarSegurar();
            const arrastou = toque.arrastou;
            if (!arrastou || performance.now() - toque.ultT > 80) inercia.vx = inercia.vy = 0;
            toque = null;
            canvas.style.cursor = 'default';
            if (arrastou || e.type === 'pointercancel') return;
            acionar(e.clientX, e.clientY);
        };
        // um toque/clique sem arrastar: aciona o que estiver embaixo
        function acionar(clientX, clientY) {
            if (performance.now() < ignorarCliqueAte) return;   // acabou de segurar um item
            const bruto = alvoEm(clientX, clientY);
            const alvo = traduzir(bruto);
            hover = bruto;
            if (alvo == null) return;
            if (cb.aoPassar) cb.aoPassar(alvo, vendaTocada);
            if (typeof alvo === 'object' && 'tx' in alvo) { if (cb.aoTile) cb.aoTile(alvo.tx, alvo.ty); }
            else if (alvo === 'celeiro') { if (cb.aoCeleiro) cb.aoCeleiro(); }
            else if (alvo === 'venda') { if (cb.aoVenda) cb.aoVenda(vendaTocada); }
            else if (alvo === 'radio') { if (cb.aoRadio) cb.aoRadio(); }
            else if (alvo === 'feira') { if (cb.aoFeira) cb.aoFeira(); }
            else if (alvo === 'lago') { if (cb.aoLago) cb.aoLago(); }
            else if (alvo === 'visitante') { if (cb.aoVisitante) cb.aoVisitante(); }
            else if (alvo === 'pier') { if (cb.aoPier) cb.aoPier(); }
            else if (alvo === 'casa') { if (cb.aoCasa) cb.aoCasa(); }   // fase 66: quem está dormindo na casa da fazenda
            else if (alvo === 'barco') { if (cb.aoBarco) cb.aoBarco(); else if (cb.aoPier) cb.aoPier(); }   // fase 62
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
            // manter = a câmera e o zoom ficam onde estão (abrir/fechar o construir não pula a fazenda)
            definirMargens(topo, base, manter) {
                if (topo === margem.topo && base === margem.base) return;
                margem = { topo, base };
                if (!manter) return redimensionar();
                limitarCamera();
                sincronizarRolagem();
                precisaDesenhar = true;
            },
            definirVisual(fn) { visual = fn; },
            definirAnimais(fn) { animaisFn = fn; },
            definirAjudantes(fn) { ajudantesFn = fn; },
            // um ajudante trabalhou: ele vai até cada canteiro ({ x, y }) ou bicho ({ animal }) — até 8 na fila
            ajudanteTrabalhou(tipo, alvos) {
                const a = atores.get('h:' + tipo);
                if (!a || !alvos || !alvos.length) return;
                a.fila = (a.fila || []).concat(alvos).slice(0, 8);
                a.espera = 0;
            },
            definirConstrucoes(fn) { construcoesFn = fn; },
            // fase 51: { barracas, vende: [tile do item de cada anúncio], vagas }
            definirFeira(f) { feira = { barracas: 1, vende: [], vagas: false, ...(f || {}) }; precisaDesenhar = true; },
            definirCanteiros(fn) { canteirosFn = fn; },
            // terrenos da fazenda na tela e os à venda (números das zonas; fase 78: até dois, e os da direita)
            definirTerreno(t) {
                const zonas = (t && t.zonas) || 0, direita = (t && t.direita) || 0;
                const venda = ZONAS.filter((z) => [].concat((t && t.venda) || []).includes(z.n));
                if (zonas === zonasAtuais && direita === direitaAtuais && venda.map((z) => z.n).join() === zonasVenda.map((z) => z.n).join()) return;
                zonasAtuais = zonas;
                direitaAtuais = direita;
                zonasVenda = venda;
                montarFundo();
                ajustarEscala();
                limitarCamera();
                sincronizarRolagem();
                precisaDesenhar = true;
            },
            focarTile(tx, ty) { focar(wx(tx) + T / 2, wy(ty) + T / 2); },
            radio(tocando) { radioTocando = !!tocando; precisaDesenhar = true; },   // fase 107: as notinhas saem do rádio
            definirClima(c) { clima = c || null; precisaDesenhar = true; },
            definirRelogio(fn) { if (typeof fn === 'function') relogio = fn; },
            definirViagens(fn) { if (typeof fn === 'function') viagensFn = fn; },
            // seu lago: { prontos, max } (null na visita ou sem o terreno 3)
            definirLago(l) { lago = l || null; },
            definirPier(pronto) { if (!!pronto === pierPronto) return; pierPronto = !!pronto; montarFundo(); precisaDesenhar = true; },   // fase 61
            definirBarco(info) { barcoInfo = info || null; precisaDesenhar = true; },   // fase 104: o navio no píer
            navioCanvas,   // fase 104 (para a prévia e os testes)
            pausar(sim) { pausada = !!sim; if (!pausada) precisaDesenhar = true; },   // fase 62
            // avatar do fazendeiro que anda na fazenda (null = o do pacote)
            definirAvatar(cfg) { avatarAtual = cfg || null; },
            // visita na porteira ({ tipo, item }) ou null (ela vai embora andando)
            definirVisitante(v) {
                if (!v) {
                    if (visitante && !visitante.saindo) { visitante.saindo = true; visitante.tx = wx(PORTEIRA.x); visitante.ty = wy(-3); }
                    return;
                }
                if (!visitante || visitante.saindo || visitante.tipo !== v.tipo) {
                    visitante = { tipo: v.tipo, item: v.item, x: wx(PORTEIRA.x), y: wy(-3), tx: wx(PORTEIRA.x), ty: wy(PORTEIRA.y), flip: false };
                } else {
                    visitante.item = v.item;
                }
            },
            telaDoVisitante() { return visitante ? { x: (visitante.x + T / 2 - cam.x) * escala, y: (visitante.y - 4 - cam.y) * escala } : null; },
            // quanto as baterias têm (0..1): as luzinhas delas acendem conforme a carga
            definirEnergia(frac) { energiaFrac = Math.max(0, Math.min(1, frac || 0)); },
            definirLuzes(acesas) { luzesAcesas = acesas !== false; },   // fase 81
            // fileiras do galinheiro (2 a 4; 0 = não tem, fase 45): refaz o chão e os bichos pequenos se espalham no espaço novo
            definirGalinheiro(linhas) {
                const h = linhas > 0 ? Math.max(2, Math.min(4, linhas)) : 0;
                if (h === MAPA.galinheiro.h) return;
                MAPA.galinheiro.h = h;
                for (const [id, a] of atores) if (!a.ajudante) atores.delete(id);
                montarFundo();
                precisaDesenhar = true;
            },
            // fase 45: o pasto do começo existe? (só com bicho grande sem cercado)
            definirPasto(ativo) {
                ativo = !!ativo;
                if (ativo === MAPA.pastoAtivo) return;
                MAPA.pastoAtivo = ativo;
                MAPA.reservas[3].w = ativo ? MAPA.pasto.w : 0;
                for (const [id, a] of atores) if (!a.ajudante) atores.delete(id);
                montarFundo();
                precisaDesenhar = true;
            },
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
            // marca no chão o alcance de um item colocado ({ x, y, raio }) por 5 s; null apaga
            mostrarAlcance(a) { alcance = a ? { ...a, ate: performance.now() + 5000 } : null; },
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
        montarCasas,
        bichoCanvas,   // fase 107 (para a prévia e os testes)   // fase 105 (para a prévia e os testes)
        mataNova,   // fase 103: as árvores novas (para a prévia)
        terraNova,   // fase 104: a terra nova (para a prévia)
        faseDoDia,
        CERCADOS,
        htmlAvatar,
        AVATAR_CORES,
        AVATAR_TIPOS,
        NOME_REGIAO,
        corOriginal,
        normalizarAvatar,
        carregar,
        criarCena,
        htmlTile,
        htmlIcone,
        htmlItem,
        ANIMAL,
        AJUDANTE_ARTE,
        htmlAjudante,
        MAPA,
        ZONAS,
        noTerreno,
        livre,
        estacao,
        cultura: (id) => CULTURAS[id] || CULTURA_PADRAO,
        // fase 59: este arquivo conhece o item / a cultura? (o servidor pode ter coisas novas antes do
        // jogo aberto recarregar: aí tudo novo aparecia como pedra)
        conhece: (id, cultura) => (cultura ? !!CULTURAS[id] : !arteItem(id, 0).desconhecido),
        // fase 62: para a cena do alto-mar (fazenda-mar.js) desenhar com a mesma arte
        desenharTile: tile,
        avatarCanvas
    };
})();
