// A trilha do site, feita no navegador (Web Audio): sem arquivo, sem direitos autorais.
// Cada cena tem o seu acorde; o Exército tem tambor de marcha, o hospital tem o bip do monitor.
const CENAS = [
    { acorde: [50, 57, 60, 64, 69], filtro: 700 },                  // abertura: Ré menor com nona
    { acorde: [53, 57, 60, 64, 67], filtro: 1100, pulso: 'leve' },   // SENAI: Fá com sétima maior
    { acorde: [50, 53, 57, 62, 65], filtro: 900, pulso: 'marcha' },  // Exército: Ré menor
    { acorde: [45, 52, 57, 60, 64], filtro: 800, bip: true },        // hospitais: Lá menor
    { acorde: [46, 53, 58, 62, 69], filtro: 1500, pulso: 'leve' },   // projetos: Si bemol com sétima maior
];
const hz = (nota) => 440 * Math.pow(2, (nota - 69) / 12);

export function criarTrilha() {
    let ctx = null, mestre, filtro, vozes = [], baixo, cenaAtual = 0, relogio = null, proximaBatida = 0, batida = 0;

    function iniciar() {
        ctx = new (window.AudioContext || window.webkitAudioContext)();
        mestre = ctx.createGain(); mestre.gain.value = 0;
        const comp = ctx.createDynamicsCompressor();
        filtro = ctx.createBiquadFilter(); filtro.type = 'lowpass'; filtro.frequency.value = CENAS[0].filtro; filtro.Q.value = 0.7;
        filtro.connect(mestre); mestre.connect(comp); comp.connect(ctx.destination);
        // eco simples para dar espaço
        const eco = ctx.createDelay(1); eco.delayTime.value = 0.38;
        const volta = ctx.createGain(); volta.gain.value = 0.32;
        filtro.connect(eco); eco.connect(volta); volta.connect(eco); volta.connect(mestre);
        // o pad: duas ondas levemente desafinadas por nota
        vozes = CENAS[0].acorde.map((nota) => {
            const g = ctx.createGain(); g.gain.value = 0.05; g.connect(filtro);
            const oscs = [-7, 7].map((desaf) => {
                const o = ctx.createOscillator(); o.type = 'sawtooth'; o.frequency.value = hz(nota); o.detune.value = desaf;
                o.connect(g); o.start(); return o;
            });
            return { g, oscs };
        });
        // o baixo, respirando devagar
        baixo = ctx.createOscillator(); baixo.type = 'sine'; baixo.frequency.value = hz(CENAS[0].acorde[0] - 12);
        const gb = ctx.createGain(); gb.gain.value = 0.16;
        const lfo = ctx.createOscillator(); lfo.frequency.value = 0.12; const lg = ctx.createGain(); lg.gain.value = 0.06;
        lfo.connect(lg); lg.connect(gb.gain); baixo.connect(gb); gb.connect(mestre); baixo.start(); lfo.start();
        proximaBatida = ctx.currentTime + 0.1;
    }

    function tambor(t, forte) {
        const o = ctx.createOscillator(), g = ctx.createGain();
        o.frequency.setValueAtTime(forte ? 120 : 90, t); o.frequency.exponentialRampToValueAtTime(42, t + 0.18);
        g.gain.setValueAtTime(forte ? 0.5 : 0.28, t); g.gain.exponentialRampToValueAtTime(0.001, t + 0.3);
        o.connect(g); g.connect(mestre); o.start(t); o.stop(t + 0.32);
    }
    function caixa(t) {
        const tam = Math.floor(ctx.sampleRate * 0.12), buf = ctx.createBuffer(1, tam, ctx.sampleRate), d = buf.getChannelData(0);
        for (let i = 0; i < tam; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / tam);
        const s = ctx.createBufferSource(), g = ctx.createGain(), f = ctx.createBiquadFilter();
        f.type = 'highpass'; f.frequency.value = 1200; g.gain.value = 0.12;
        s.buffer = buf; s.connect(f); f.connect(g); g.connect(mestre); s.start(t);
    }
    function bip(t) {
        const o = ctx.createOscillator(), g = ctx.createGain();
        o.type = 'sine'; o.frequency.value = 988;
        g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.09, t + 0.01); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.16);
        o.connect(g); g.connect(mestre); o.start(t); o.stop(t + 0.2);
    }
    // marca o tempo com folga, a 72 batidas por minuto
    function agendar() {
        const c = CENAS[cenaAtual];
        while (proximaBatida < ctx.currentTime + 0.2) {
            const t = proximaBatida;
            if (c.pulso === 'marcha') { tambor(t, batida % 4 === 0); if (batida % 2 === 1) caixa(t); }
            if (c.pulso === 'leve' && batida % 2 === 0) tambor(t, false);
            if (c.bip && batida % 2 === 0) bip(t);
            batida++; proximaBatida += 60 / 72;
        }
    }

    function aplicarCena(i) {
        if (!ctx) return;
        const c = CENAS[i], t = ctx.currentTime;
        c.acorde.forEach((nota, k) => vozes[k].oscs.forEach((o) => o.frequency.setTargetAtTime(hz(nota), t, 0.6)));
        baixo.frequency.setTargetAtTime(hz(c.acorde[0] - 12), t, 0.6);
        filtro.frequency.setTargetAtTime(c.filtro, t, 0.8);
    }

    return {
        get ligada() { return !!relogio; },
        ligar() {
            if (!ctx) iniciar();
            ctx.resume();
            aplicarCena(cenaAtual);
            mestre.gain.cancelScheduledValues(ctx.currentTime);
            mestre.gain.setTargetAtTime(0.5, ctx.currentTime, 0.6);
            proximaBatida = Math.max(proximaBatida, ctx.currentTime + 0.05);
            relogio = setInterval(agendar, 50);
        },
        desligar() {
            if (!ctx) return;
            clearInterval(relogio); relogio = null;
            mestre.gain.setTargetAtTime(0, ctx.currentTime, 0.25);
            setTimeout(() => { if (!relogio) ctx.suspend(); }, 1200);
        },
        cena(i) { if (i === cenaAtual) return; cenaAtual = i; aplicarCena(i); },
    };
}
