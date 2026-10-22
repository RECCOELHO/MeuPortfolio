// O site v4: o crachá no topo, o pó 3D, a trilha e as cenas que trocam enquanto se desce (estilo GTA 6).
import { montarCracha } from './cracha.js';
import { montarFundo } from './fundo.js';
import { criarTrilha } from './trilha.js';

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const calmo = document.documentElement.classList.contains('calmo');
const leve = matchMedia('(max-width: 760px)').matches || (navigator.hardwareConcurrency || 8) <= 4;
const WHATSAPP = 'https://wa.me/5535998594066?text=Ol%C3%A1%2C%20Carlos!%20Vi%20seu%20crach%C3%A1%20no%20portf%C3%B3lio.';

// ---------- a trilha: começa desligada, o botão liga ----------
const trilha = criarTrilha();
$('#som').addEventListener('click', () => {
    const ligar = !trilha.ligada;
    if (ligar) trilha.ligar(); else trilha.desligar();
    $('#som').setAttribute('aria-pressed', String(ligar));
    $('#somEstado').textContent = ligar ? 'ligado' : 'desligado';
});
// saiu da página (outra aba, app minimizado): a música pausa; voltou: continua de onde estava
let pausadaAoSair = false;
document.addEventListener('visibilitychange', () => {
    if (document.hidden && trilha.ligada) { trilha.desligar(); pausadaAoSair = true; }
    else if (!document.hidden && pausadaAoSair) { trilha.ligar(); pausadaAoSair = false; }
});

// ---------- o crachá ----------
let cracha = null;
montarCracha($('#cracha'), { leve, calmo, aoTocarQr: () => window.open(WHATSAPP, '_blank', 'noopener') })
    .then((c) => { cracha = c; window.__cracha = c; })
    .catch((erro) => {
        // sem WebGL: fica a foto recortada no lugar do crachá
        console.warn('Crachá 3D indisponível:', erro);
        $('#cracha').remove(); $('#dica').remove();
        const img = new Image();
        img.src = 'assets/img/cenas/sorriso-recorte.webp'; img.alt = ''; img.className = 'cracha-sem-3d';
        $('.c0').append(img);
    });

// ---------- o e-mail (Formspree) ----------
const form = $('#contactForm');
form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const botao = form.querySelector('button');
    botao.disabled = true;
    try {
        const r = await fetch(form.action, { method: 'POST', body: new FormData(form), headers: { Accept: 'application/json' } });
        if (!r.ok) throw new Error();
        form.reset();
        $('#formOk').hidden = false;
    } catch {
        botao.textContent = 'Não foi. Tente o WhatsApp';
    } finally {
        botao.disabled = false;
    }
});

// ---------- planos e contato: cada parte sobe uma vez ----------
const ver = new IntersectionObserver((itens) => itens.forEach((e) => {
    if (!e.isIntersecting) return;
    e.target.classList.add('visto');
    ver.unobserve(e.target);
}), { rootMargin: '0px 0px -8% 0px', threshold: 0 });
$$('.sobe').forEach((el) => ver.observe(el));

// ---------- o teatro ----------
const video = $('.tela-monitor video');
if (calmo || !window.gsap || !window.ScrollTrigger) {
    document.documentElement.classList.add('calmo');
    video.controls = true;
} else {
    montarTeatro();
}

function montarTeatro() {
    const { gsap, ScrollTrigger } = window;
    gsap.registerPlugin(ScrollTrigger);

    // rolagem macia (Lenis) ligada ao relógio do GSAP
    let lenis = null;
    if (window.Lenis) {
        lenis = new window.Lenis({ lerp: 0.085, wheelMultiplier: 0.9 });
        lenis.on('scroll', ScrollTrigger.update);
        gsap.ticker.add((t) => lenis.raf(t * 1000));
        gsap.ticker.lagSmoothing(0);
    }
    $$('a[href^="#"]').forEach((a) => a.addEventListener('click', (ev) => {
        const alvo = $(a.getAttribute('href'));
        if (!alvo) return;
        ev.preventDefault();
        if (lenis) lenis.scrollTo(alvo, { duration: 1.8 }); else alvo.scrollIntoView({ behavior: 'smooth' });
    }));

    const fundo = montarFundo($('#fundo3d'), { leve });
    ScrollTrigger.create({ trigger: '.teatro', start: 'top bottom', end: 'bottom top', onToggle: (s) => fundo.ligar(s.isActive) });

    // a máscara "CJ": as letras crescem até a cena do SENAI tomar a tela (como o "VI" do GTA 6)
    const c1 = $('.c1');
    const svgCJ = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 200 120'><g fill='none' stroke='#fff' stroke-width='26' stroke-linecap='round'><path d='M92 28 A40 40 0 1 0 92 92'/><path d='M150 16 V74 A28 28 0 0 1 100 92'/></g></svg>";
    const urlCJ = `url("data:image/svg+xml,${encodeURIComponent(svgCJ)}")`;
    function mascarar(m) {
        if (m <= 0.001) { c1.style.visibility = 'hidden'; return; }
        c1.style.visibility = 'visible';
        if (m >= 0.999) { c1.style.maskImage = c1.style.webkitMaskImage = 'none'; return; }
        const W = innerWidth, H = innerHeight;
        const S0 = Math.min(W * 0.42, H * 1.1), S1 = Math.max(10 * W, 4 * H);
        const S = S0 * Math.pow(S1 / S0, m);
        const f = Math.min(1, m * 1.5), u = 0.5 + 0.25 * f, v = 0.5 - 0.125 * f; // vai do meio do "CJ" para a haste do J
        Object.assign(c1.style, {
            maskImage: urlCJ, webkitMaskImage: urlCJ, maskRepeat: 'no-repeat', webkitMaskRepeat: 'no-repeat',
            maskSize: `${S}px ${S * 0.6}px`, webkitMaskSize: `${S}px ${S * 0.6}px`,
            maskPosition: `${W / 2 - u * S}px ${H / 2 - v * S * 0.6}px`, webkitMaskPosition: `${W / 2 - u * S}px ${H / 2 - v * S * 0.6}px`,
        });
    }

    // a linha do tempo: 8 telas de rolagem, cada unidade = uma altura de tela
    const trilho = $('.trilho');
    const tl = gsap.timeline({
        defaults: { ease: 'none' },
        scrollTrigger: { trigger: '.teatro', start: 'top top', end: 'bottom bottom', scrub: 0.9, invalidateOnRefresh: true },
    });
    const entra = (alvo, quando, de = { y: 70 }) => tl.fromTo(alvo, { ...de, opacity: 0 }, { y: 0, x: 0, opacity: 1, duration: 0.45, ease: 'power2.out' }, quando);
    const sai = (alvo, quando) => tl.to(alvo, { y: -60, opacity: 0, duration: 0.35, ease: 'power1.in' }, quando);

    // 0 → abertura: o nome e o crachá vão embora
    tl.to('.dica', { opacity: 0, duration: 0.25 }, 0.25);
    tl.to('.c0 .titulo', { yPercent: -18, scale: 0.94, opacity: 0, duration: 0.9, transformOrigin: '0% 100%' }, 0.45);
    tl.to('#cracha', { yPercent: -35, opacity: 0, duration: 0.8, ease: 'power1.in' }, 0.75);

    // 1 → SENAI
    const mascara = { m: 0 };
    tl.to(mascara, { m: 1, duration: 1.15, ease: 'power1.in', onUpdate: () => mascarar(mascara.m) }, 0.5);
    tl.fromTo('.c1 .miolo', { scale: 1.35 }, { scale: 1, duration: 1.3, ease: 'power2.out' }, 0.5);
    tl.fromTo('.c1 .foto-fundo', { yPercent: 5, scale: 1.12 }, { yPercent: -5, scale: 1, duration: 2.2 }, 0.6);
    tl.fromTo('.c1 .ano', { y: () => innerHeight * 0.18 }, { y: () => -innerHeight * 0.14, duration: 2.2 }, 0.6);
    tl.fromTo('.c1 .pessoa', { yPercent: 16, scale: 0.92 }, { yPercent: 0, scale: 1.04, duration: 1.8 }, 0.8);
    entra('.c1 .legenda', 1.4);
    sai('.c1 .legenda', 2.4);

    // 2 → Exército: abre num círculo
    tl.fromTo('.c2', { clipPath: 'circle(0% at 50% 55%)' }, { clipPath: 'circle(80% at 50% 55%)', duration: 0.7, ease: 'power2.in' }, 2.45);
    tl.fromTo('.c2 .miolo', { scale: 1.3 }, { scale: 1, duration: 0.9, ease: 'power2.out' }, 2.45);
    tl.fromTo('.c2 .foto-fundo', { scale: 1.15 }, { scale: 1, duration: 1.9 }, 2.5);
    tl.fromTo('.c2 .ano', { y: () => innerHeight * 0.15 }, { y: () => -innerHeight * 0.15, duration: 1.9 }, 2.5);
    tl.fromTo('.c2 .pessoa', { scale: 0.7, yPercent: 18 }, { scale: 1.12, yPercent: 0, duration: 1.8 }, 2.55);
    entra('.c2 .legenda', 3.0);
    entra('.c2 .lema', 3.35, { x: 80, y: 0 });
    sai('.c2 .legenda', 4.0);
    sai('.c2 .lema', 4.05);

    // 3 → hospitais: entra da direita, o batimento se desenha
    // a passagem 2020 → 2025 é um batimento: a tela pulsa duas vezes, a linha atravessa e, no pico, um flash
    tl.to('.c2 .miolo', { scale: 1.05, filter: 'brightness(.7)', duration: 0.07, ease: 'power2.out' }, 3.95);
    tl.to('.c2 .miolo', { scale: 1, filter: 'brightness(1)', duration: 0.1, ease: 'power2.in' }, 4.02);
    tl.to('.c2 .miolo', { scale: 1.09, filter: 'brightness(.55)', duration: 0.07, ease: 'power2.out' }, 4.17);
    tl.to('.c2 .miolo', { scale: 1.02, filter: 'brightness(.4)', duration: 0.12, ease: 'power2.in' }, 4.24);
    gsap.set('.ecg-passagem path', { strokeDasharray: 1 });
    tl.set('.ecg-passagem', { opacity: 1 }, 4.0);
    tl.fromTo('.ecg-passagem path', { strokeDashoffset: 1 }, { strokeDashoffset: 0, duration: 0.45 }, 4.0);
    tl.fromTo('.flash', { opacity: 0 }, { opacity: 0.95, duration: 0.05, ease: 'power3.in' }, 4.43);
    tl.set('.c3', { opacity: 1 }, 4.48);
    tl.set('.ecg-passagem', { opacity: 0 }, 4.48);
    tl.to('.flash', { opacity: 0, duration: 0.3, ease: 'power2.out' }, 4.48);
    tl.fromTo('.c3 .miolo', { scale: 1.12 }, { scale: 1, duration: 0.5, ease: 'power2.out' }, 4.48);
    tl.fromTo('.c3 .ano', { y: () => innerHeight * 0.15 }, { y: () => -innerHeight * 0.15, duration: 1.8 }, 4.1);
    tl.fromTo('.c3 .pessoa', { yPercent: 22, opacity: 0 }, { yPercent: 0, opacity: 1, duration: 0.7, ease: 'power2.out' }, 4.5);
    entra('.c3 .legenda.um', 4.7);
    sai('.c3 .legenda.um', 5.25);
    entra('.c3 .legenda.dois', 5.2);
    sai('.c3 .legenda.dois', 5.85);

    // 4 → projetos: sobe de baixo; o monitor gira para a frente; depois as telas passam
    tl.fromTo('.c4', { clipPath: 'inset(100% 0% 0% 0%)' }, { clipPath: 'inset(0% 0% 0% 0%)', duration: 0.6, ease: 'power2.inOut' }, 5.7);
    entra('.c4 .cabeca', 5.95, { y: 100 });
    tl.fromTo('.monitor', { rotationX: 28, rotationY: -32, scale: 0.55, y: () => innerHeight * 0.22, opacity: 0.2 },
        { rotationX: 0, rotationY: 0, scale: 1, y: () => innerHeight * 0.08, opacity: 1, duration: 1, ease: 'power2.out' }, 5.85);
    entra('.monitor-texto', 6.4, { y: 40 });
    tl.to('.monitor', { rotationY: 38, x: () => -innerWidth * 0.75, scale: 0.6, opacity: 0, duration: 0.6, ease: 'power2.in' }, 6.95);
    tl.to('.c4 .cabeca', { opacity: 0.25, duration: 0.5 }, 7.0);
    tl.fromTo(trilho, { x: 0 }, { x: () => -(trilho.scrollWidth - innerWidth * 0.95), duration: 0.8 }, 7.2);
    tl.set({}, {}, 8);

    // o que não é CSS: o pó 3D, a música, o crachá e o vídeo seguem a posição da linha do tempo
    const forma = (t) => {
        const trechos = [[0.6, 1.6, 0], [2.6, 3.2, 1], [4.2, 4.8, 2], [5.8, 6.4, 3]];
        for (const [a, b, n] of trechos) { if (t < a) return n; if (t < b) return n + (t - a) / (b - a); }
        return 4;
    };
    const cenaDe = (t) => (t < 1.1 ? 0 : t < 2.8 ? 1 : t < 4.46 ? 2 : t < 5.9 ? 3 : 4);
    let tocando = false, anterior = 0;
    tl.eventCallback('onUpdate', () => {
        const t = tl.time();
        fundo.forma(forma(t));
        trilha.cena(cenaDe(t));
        // descendo pela passagem 2020 → 2025, a música toca o coração junto com o pulso da tela
        if (anterior < 3.93 && t >= 3.93) trilha.coracao();
        anterior = t;
        if (cracha) cracha.ligar(t < 1.5);
        const deveTocar = t > 5.8 && t < 7.4;
        if (deveTocar !== tocando) { tocando = deveTocar; if (deveTocar) video.play().catch(() => {}); else video.pause(); }
    });
    window.__teatro = tl;
}
