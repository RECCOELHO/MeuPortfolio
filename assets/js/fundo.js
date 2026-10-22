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
        // 1 circuito: uma placa vista de frente, atrás de tudo; trilhas em grade com cotovelos de 90° e nós
        if (r() < 0.12) {
            // nó: um bloquinho de pontos num cruzamento da grade
            const nx = (Math.floor(r() * 13) - 6) * 1.6, ny = (Math.floor(r() * 7) - 3) * 1.5;
            f[1].set([nx + (r() - 0.5) * 0.22, ny + (r() - 0.5) * 0.22, -5], k);
        } else {
            // trilha: anda na horizontal até a coluna de um cotovelo e depois desce/sobe na vertical
            const y0 = (Math.floor(r() * 7) - 3) * 1.5, x0 = (Math.floor(r() * 13) - 6) * 1.6;
            const horiz = r() < 0.55, passo = (r() - 0.5) * 3.2;
            f[1].set(horiz ? [x0 + passo, y0, -5] : [x0, y0 + passo * 0.9, -5], k);
        }
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

export function montarFundo(canvas, { leve = false, celular = false } = {}) {
    // celular: poucos pontos, desenho em 75% do tamanho e a 30 quadros por segundo
    const n = celular ? 700 : leve ? 1400 : 3200;
    const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: true, powerPreference: celular ? 'low-power' : 'default' });
    renderer.setPixelRatio(celular ? 0.75 : Math.min(devicePixelRatio, leve ? 1.25 : 1.75));
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
    const mat = new THREE.PointsMaterial({ size: leve ? 0.07 : 0.055, map: new THREE.CanvasTexture(ponto), vertexColors: true, transparent: true, opacity: celular ? 0.95 : 0.85, depthWrite: false, blending: celular ? THREE.NormalBlending : THREE.AdditiveBlending });
    if (celular) mat.size = 0.085;
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

    // cada ponto sai na troca com um atraso próprio: assim não andam todos juntos em linha (os "riscos")
    const atraso = new Float32Array(n);
    for (let i = 0; i < n; i++) atraso[i] = r() * 0.25;
    let forma = 0, mostrado = -1, ligado = true, quadro = 0, ultimo = 0;
    const suave = (t) => t * t * (3 - 2 * t);
    function animar(agora) {
        quadro = requestAnimationFrame(animar);
        if (!ligado) return;
        if (celular && agora - ultimo < 32) return;
        ultimo = agora;
        if (forma !== mostrado) {
            const a = Math.floor(forma), b = Math.min(4, a + 1), f = forma - a;
            const A = F[a], B = F[b];
            for (let i = 0; i < n; i++) {
                const t = suave(Math.max(0, Math.min(1, (f - atraso[i]) / 0.75))), k = i * 3;
                posicoes[k] = A[k] + (B[k] - A[k]) * t;
                posicoes[k + 1] = A[k + 1] + (B[k + 1] - A[k + 1]) * t;
                posicoes[k + 2] = A[k + 2] + (B[k + 2] - A[k + 2]) * t;
            }
            geo.attributes.position.needsUpdate = true;
            mostrado = forma;
        }
        // no circuito (forma 1) a placa fica quase parada, de frente; nas outras formas o grupo gira devagar
        const perto1 = Math.max(0, 1 - Math.abs(forma - 1));
        pontos.rotation.y = (Math.sin(agora / 9000) * 0.12 + forma * 0.05) * (1 - perto1 * 0.9);
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
