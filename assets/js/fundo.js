// O pó 3D que passa por cima das cenas: os mesmos pontos mudam de forma a cada capítulo.
// poeira (abertura) → placa de circuito (SENAI) → campo (Exército) → batimento (hospitais) → esfera (projetos)
import * as THREE from 'three';

function aleatorio(semente) { let s = semente; return () => ((s = (s * 16807) % 2147483647) - 1) / 2147483646; }

function formacoes(n) {
    const r = aleatorio(7), f = Array.from({ length: 5 }, () => new Float32Array(n * 3));
    // ECG: linha reta, pico, vale e volta
    const ecg = (x) => {
        const m = ((x % 6) + 6) % 6 - 3;
        if (m > -0.6 && m < -0.3) return (m + 0.6) * 1.2;
        if (m >= -0.3 && m < 0) return 0.36 + (m + 0.3) * 9.5;
        if (m >= 0 && m < 0.35) return 3.2 - m * 13;
        if (m >= 0.35 && m < 0.6) return -1.35 + (m - 0.35) * 5.4;
        return 0;
    };
    for (let i = 0; i < n; i++) {
        const k = i * 3;
        // 0 poeira
        f[0].set([(r() - 0.5) * 18, (r() - 0.5) * 11, -6 + r() * 7], k);
        // 1 circuito: trilhas em grade numa placa inclinada
        const linha = Math.floor(r() * 14), ao = r() < 0.5, pos = (r() - 0.5) * 18, fixo = (linha - 7) * 1.1;
        const gx = ao ? pos : fixo, gz = ao ? fixo : pos * 0.6;
        f[1].set([gx, -2.6 + gz * 0.35, -3 + gz * 0.55], k);
        // 2 campo: chão ondulado e neblina baixa
        const cx = (r() - 0.5) * 22, cz = -10 + r() * 11;
        const chao = r() < 0.8;
        f[2].set([cx, chao ? -2.4 + Math.sin(cx * 0.7) * 0.25 + Math.cos(cz * 0.9) * 0.2 : -1.6 + r() * 2.4, cz], k);
        // 3 batimento: a linha do monitor, com um pouco de brilho em volta
        const ex = (r() - 0.5) * 20, na = r() < 0.75;
        f[3].set([ex, na ? ecg(ex + 1.2) * 0.7 + 0.6 + (r() - 0.5) * 0.06 : (r() - 0.5) * 10, na ? -1 + (r() - 0.5) * 0.2 : -6 + r() * 3], k);
        // 4 esfera
        const u = r() * 2 - 1, a = r() * Math.PI * 2, raio = 4.2 + (r() - 0.5) * 0.4;
        f[4].set([Math.sqrt(1 - u * u) * Math.cos(a) * raio + 3, u * raio, Math.sqrt(1 - u * u) * Math.sin(a) * raio - 4], k);
    }
    return f;
}

export function montarFundo(canvas, { leve = false } = {}) {
    const n = leve ? 1400 : 3200;
    const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: true });
    renderer.setPixelRatio(Math.min(devicePixelRatio, leve ? 1.25 : 1.75));
    const cena = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(50, 1, 0.1, 60);
    camera.position.set(0, 0, 8);

    const F = formacoes(n);
    const posicoes = new Float32Array(F[0]);
    const cores = new Float32Array(n * 3), vermelho = new THREE.Color('#d94040'), claro = new THREE.Color('#ece8e6');
    const r = aleatorio(3);
    for (let i = 0; i < n; i++) cores.set((r() < 0.72 ? vermelho : claro).toArray(), i * 3);
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(posicoes, 3));
    geo.setAttribute('color', new THREE.BufferAttribute(cores, 3));
    const ponto = document.createElement('canvas'); ponto.width = ponto.height = 32;
    const c = ponto.getContext('2d'); c.fillStyle = '#fff'; c.beginPath(); c.arc(16, 16, 14, 0, Math.PI * 2); c.fill();
    const mat = new THREE.PointsMaterial({ size: leve ? 0.07 : 0.055, map: new THREE.CanvasTexture(ponto), vertexColors: true, transparent: true, opacity: 0.85, depthWrite: false, blending: THREE.AdditiveBlending });
    const pontos = new THREE.Points(geo, mat);
    cena.add(pontos);

    function medir() {
        const w = canvas.clientWidth || innerWidth, h = canvas.clientHeight || innerHeight;
        renderer.setSize(w, h, false);
        camera.aspect = w / h;
        camera.position.z = w < 760 ? 11 : 8;
        camera.updateProjectionMatrix();
    }
    medir();
    addEventListener('resize', medir);

    let forma = 0, mostrado = -1, ligado = true, quadro = 0;
    const suave = (t) => t * t * (3 - 2 * t);
    function animar(agora) {
        quadro = requestAnimationFrame(animar);
        if (!ligado) return;
        if (forma !== mostrado) {
            const a = Math.floor(forma), b = Math.min(4, a + 1), t = suave(forma - a);
            const A = F[a], B = F[b];
            for (let i = 0; i < posicoes.length; i++) posicoes[i] = A[i] + (B[i] - A[i]) * t;
            geo.attributes.position.needsUpdate = true;
            mostrado = forma;
        }
        pontos.rotation.y = Math.sin(agora / 9000) * 0.12 + forma * 0.05;
        pontos.position.y = Math.sin(agora / 2400) * 0.08;
        renderer.render(cena, camera);
    }
    quadro = requestAnimationFrame(animar);

    return {
        // forma vai de 0 a 4, com frações durante a troca
        forma(v) { forma = Math.max(0, Math.min(4, v)); },
        ligar(sim) { ligado = sim; },
        parar() { cancelAnimationFrame(quadro); renderer.dispose(); },
    };
}
