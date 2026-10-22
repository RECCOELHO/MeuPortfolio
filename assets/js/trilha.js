// A trilha do site, feita no navegador (Web Audio): sem arquivo, sem direitos autorais.
// Nunca fica parada: os acordes andam sozinhos a cada 2 compassos, um arpejo corre por baixo e uma
// melodia em pentatônica improvisa por cima. Na troca de cena entra um "whoosh" com um impacto grave;
// da farda para o hospital, o coração bate.
const ACORDES = {
    Dm9: { r: 38, n: [57, 60, 64, 65] }, Dm: { r: 38, n: [57, 62, 65, 69] }, Bb7M: { r: 34, n: [57, 62, 65, 69] },
    Bb: { r: 34, n: [58, 62, 65, 70] }, F: { r: 41, n: [57, 60, 65, 69] }, C: { r: 36, n: [55, 60, 64, 67] },
    Gm: { r: 43, n: [58, 62, 67, 70] }, A: { r: 33, n: [57, 61, 64, 69] }, Am: { r: 33, n: [57, 60, 64, 69] },
    G: { r: 43, n: [55, 59, 62, 67] },
};
const CENAS = [
    { seq: ['Dm9', 'Bb7M', 'F', 'C'], filtro: 950, escala: [62, 65, 67, 69, 72, 74, 77] },                  // abertura
    { seq: ['F', 'C', 'Dm', 'Bb'], filtro: 1350, escala: [65, 67, 69, 72, 74, 77, 79], pulso: 'leve' },     // SENAI
    { seq: ['Dm', 'Bb', 'Gm', 'A'], filtro: 1050, escala: [62, 65, 67, 69, 72, 74, 76], pulso: 'marcha' },  // Exército
    { seq: ['Am', 'F', 'C', 'G'], filtro: 950, escala: [64, 67, 69, 72, 74, 76, 79], bip: true },          // hospitais
    { seq: ['Bb7M', 'C', 'Dm', 'F'], filtro: 1650, escala: [65, 67, 69, 72, 74, 77, 79], pulso: 'leve' },   // projetos
];
const BPM = 72, COLCHEIA = 60 / BPM / 2, POR_ACORDE = 16; // 2 compassos de 8 colcheias
const hz = (nota) => 440 * Math.pow(2, (nota - 69) / 12);

export function criarTrilha() {
    let ctx = null, mestre, filtro, eco, vozes = [], baixo, cenaAtual = 0, relogio = null;
    let proximo = 0, passo = 0, acorde = 0, melodia = 3, semWhoosh = 0;

    function iniciar() {
        ctx = new (window.AudioContext || window.webkitAudioContext)();
        mestre = ctx.createGain(); mestre.gain.value = 0;
        const comp = ctx.createDynamicsCompressor();
        filtro = ctx.createBiquadFilter(); filtro.type = 'lowpass'; filtro.frequency.value = CENAS[0].filtro; filtro.Q.value = 0.8;
        filtro.connect(mestre); mestre.connect(comp); comp.connect(ctx.destination);
        // o timbre respira: um LFO bem lento abre e fecha o filtro
        const lfo = ctx.createOscillator(), lfoG = ctx.createGain(); lfo.frequency.value = 0.07; lfoG.gain.value = 320;
        lfo.connect(lfoG); lfoG.connect(filtro.frequency); lfo.start();
        // eco para dar espaço
        eco = ctx.createDelay(1.5); eco.delayTime.value = COLCHEIA * 3;
        const volta = ctx.createGain(); volta.gain.value = 0.3;
        eco.connect(volta); volta.connect(eco); volta.connect(filtro);
        // o pad: duas ondas levemente desafinadas por nota
        vozes = ACORDES[CENAS[0].seq[0]].n.map((nota) => {
            const g = ctx.createGain(); g.gain.value = 0.045; g.connect(filtro);
            const oscs = [-8, 8].map((desaf) => {
                const o = ctx.createOscillator(); o.type = 'sawtooth'; o.frequency.value = hz(nota); o.detune.value = desaf;
                o.connect(g); o.start(); return o;
            });
            return { g, oscs };
        });
        baixo = ctx.createOscillator(); baixo.type = 'sine'; baixo.frequency.value = hz(ACORDES[CENAS[0].seq[0]].r);
        const gb = ctx.createGain(); gb.gain.value = 0.2; baixo.connect(gb); gb.connect(mestre); baixo.start();
        proximo = ctx.currentTime + 0.1;
    }

    // ---------- instrumentos ----------
    function nota(t, freq, dur, vol, tipo = 'triangle', comEco = true) {
        const o = ctx.createOscillator(), g = ctx.createGain();
        o.type = tipo; o.frequency.value = freq;
        g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(vol, t + 0.02); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
        o.connect(g); g.connect(filtro); if (comEco) g.connect(eco);
        o.start(t); o.stop(t + dur + 0.05);
        return o;
    }
    function ruido(dur) {
        const tam = Math.floor(ctx.sampleRate * dur), buf = ctx.createBuffer(1, tam, ctx.sampleRate), d = buf.getChannelData(0);
        for (let i = 0; i < tam; i++) d[i] = Math.random() * 2 - 1;
        const s = ctx.createBufferSource(); s.buffer = buf; return s;
    }
    function grave(t, de, ate, vol, dur) {
        const o = ctx.createOscillator(), g = ctx.createGain();
        o.frequency.setValueAtTime(de, t); o.frequency.exponentialRampToValueAtTime(ate, t + dur * 0.7);
        g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.001, t + dur);
        o.connect(g); g.connect(mestre); o.start(t); o.stop(t + dur + 0.05);
    }
    function caixa(t) {
        const s = ruido(0.12), g = ctx.createGain(), f = ctx.createBiquadFilter();
        f.type = 'highpass'; f.frequency.value = 1200;
        g.gain.setValueAtTime(0.12, t); g.gain.exponentialRampToValueAtTime(0.001, t + 0.12);
        s.connect(f); f.connect(g); g.connect(mestre); s.start(t);
    }
    function bip(t) { nota(t, 988, 0.16, 0.08, 'sine', false); }
    function whoosh(t) {
        const s = ruido(1.1), f = ctx.createBiquadFilter(), g = ctx.createGain();
        f.type = 'bandpass'; f.Q.value = 1.4;
        f.frequency.setValueAtTime(300, t); f.frequency.exponentialRampToValueAtTime(5200, t + 0.9);
        g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.22, t + 0.8); g.gain.exponentialRampToValueAtTime(0.0001, t + 1.05);
        s.connect(f); f.connect(g); g.connect(mestre); s.start(t);
        grave(t + 0.9, 80, 35, 0.6, 0.9);
    }

    // ---------- o relógio: agenda as colcheias com folga ----------
    function agendar() {
        const c = CENAS[cenaAtual];
        while (proximo < ctx.currentTime + 0.25) {
            const t = proximo;
            // os acordes andam sozinhos: um novo a cada 2 compassos
            if (passo % POR_ACORDE === 0) {
                acorde = (passo / POR_ACORDE) % c.seq.length;
                const a = ACORDES[c.seq[acorde]];
                a.n.forEach((n, k) => vozes[k].oscs.forEach((o) => o.frequency.setTargetAtTime(hz(n), t, 0.25)));
                baixo.frequency.setTargetAtTime(hz(a.r), t, 0.15);
            }
            const a = ACORDES[c.seq[acorde]];
            // arpejo: sobe e desce pelas notas do acorde, às vezes pula uma
            const padrao = [0, 1, 2, 3, 4, 3, 2, 1], idx = padrao[passo % 8];
            const notaArp = idx === 4 ? a.n[0] + 12 : a.n[idx];
            if (Math.random() > (c.bip ? 0.45 : 0.15)) nota(t, hz(notaArp + 12), 0.35, 0.035 + Math.random() * 0.02);
            // melodia: a cada semínima, talvez uma nota, andando por passos curtos na escala
            if (passo % 2 === 0 && Math.random() < 0.5) {
                melodia = Math.max(0, Math.min(c.escala.length - 1, melodia + [-2, -1, -1, 1, 1, 2][Math.floor(Math.random() * 6)]));
                const o = nota(t, hz(c.escala[melodia]), 0.5 + Math.random() * 0.9, 0.04 + Math.random() * 0.035, 'sine');
                o.detune.setValueAtTime(0, t); o.detune.linearRampToValueAtTime(Math.random() < 0.3 ? 12 : 0, t + 0.4);
            }
            // percussão de cada cena
            const batida = passo % 2 === 0, tempo = passo / 2;
            if (batida && c.pulso === 'marcha') { grave(t, tempo % 4 === 0 ? 120 : 90, 42, tempo % 4 === 0 ? 0.5 : 0.28, 0.3); if (tempo % 2 === 1) caixa(t); }
            if (batida && c.pulso === 'leve' && tempo % 2 === 0) grave(t, 90, 42, 0.26, 0.3);
            if (batida && c.bip && tempo % 2 === 0) bip(t);
            passo++; proximo += COLCHEIA;
        }
    }

    function aplicarFiltro(i) { filtro.frequency.setTargetAtTime(CENAS[i].filtro, ctx.currentTime, 0.8); }

    return {
        get ligada() { return !!relogio; },
        ligar() {
            if (!ctx) iniciar();
            ctx.resume();
            aplicarFiltro(cenaAtual);
            mestre.gain.cancelScheduledValues(ctx.currentTime);
            mestre.gain.setTargetAtTime(0.5, ctx.currentTime, 0.6);
            proximo = Math.max(proximo, ctx.currentTime + 0.05);
            relogio = setInterval(agendar, 50);
        },
        desligar() {
            if (!ctx) return;
            clearInterval(relogio); relogio = null;
            mestre.gain.setTargetAtTime(0, ctx.currentTime, 0.25);
            setTimeout(() => { if (!relogio) ctx.suspend(); }, 1200);
        },
        cena(i) {
            if (i === cenaAtual) return;
            cenaAtual = i; melodia = 3;
            if (!ctx || !relogio) return;
            // recomeça a sequência da cena nova no próximo compasso
            passo = Math.ceil(passo / POR_ACORDE) * POR_ACORDE;
            aplicarFiltro(i);
            if (ctx.currentTime > semWhoosh) whoosh(ctx.currentTime);
        },
        // duas batidas de coração e o bip do monitor (passagem do Exército para o hospital)
        coracao() {
            if (!ctx || !relogio) return;
            const t = ctx.currentTime + 0.02;
            [0, 0.22, 0.9, 1.12].forEach((d, k) => grave(t + d, k % 2 ? 70 : 95, 38, k % 2 ? 0.45 : 0.6, 0.28));
            bip(t + 1.5);
            semWhoosh = ctx.currentTime + 3;
        },
    };
}
