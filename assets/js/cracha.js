// O crachá do topo: um cartão 3D preso num cordão, com física de verdade (three.js + Rapier).
// Pega com o mouse ou o dedo, puxa, joga; um toque vira o cartão; o QR abre o WhatsApp.
import * as THREE from 'three';
import RAPIER from 'rapier';

const LARGURA = 1.6, ALTURA = 2.25, CANTO = 0.09, ESPESSURA = 0.03;
const TECNOLOGIAS = ['JavaScript', 'React', 'Next.js', 'Node.js', 'Supabase', 'PostgreSQL', 'SQL e SPData', 'PHP', 'HTML e CSS', 'Git e GitHub'];
const QR_AREA = { x0: 48 / 640, x1: 188 / 640, y0: 1 - 888 / 900, y1: 1 - 748 / 900 }; // onde o QR fica na frente (uv)

const carregarImagem = (src) => new Promise((ok, erro) => { const i = new Image(); i.onload = () => ok(i); i.onerror = erro; i.src = src; });

function retanguloRedondo(ctx, x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}

// o logo CJ do favicon: C claro, J vermelho
function logo(ctx, x, y, tam, corC, corJ) {
    ctx.font = `italic 700 ${tam}px Georgia, serif`;
    ctx.textBaseline = 'alphabetic';
    ctx.fillStyle = corC; ctx.fillText('C', x, y);
    ctx.fillStyle = corJ; ctx.fillText('J', x + tam * 0.62, y);
}

function faixaDoTopo(ctx, cor) {
    ctx.fillStyle = cor; ctx.fillRect(0, 0, 640, 150);
    ctx.fillStyle = '#0d0608'; retanguloRedondo(ctx, 260, 34, 120, 24, 12); ctx.fill(); // o furo do clipe
}

function desenharFrente(foto, qr) {
    const c = document.createElement('canvas'); c.width = 640; c.height = 900;
    const ctx = c.getContext('2d');
    ctx.fillStyle = '#ece8e6'; ctx.fillRect(0, 0, 640, 900);
    faixaDoTopo(ctx, '#b52828');
    logo(ctx, 48, 128, 60, '#ece8e6', '#0d0608');
    ctx.fillStyle = '#ece8e6'; ctx.font = '700 28px Montserrat, sans-serif'; ctx.textAlign = 'right';
    ctx.fillText('DEV', 592, 122); ctx.textAlign = 'left';
    // a foto recortada sobre o vermelho escuro
    ctx.fillStyle = '#2a0f13'; ctx.fillRect(48, 178, 544, 452);
    ctx.save(); ctx.beginPath(); ctx.rect(48, 178, 544, 452); ctx.clip();
    // a foto com a filha: os dois rostos no alto da janela, o resto do corpo fica fora
    const escala = 544 * 1.06 / foto.width, w = foto.width * escala;
    ctx.drawImage(foto, 48 + (544 - w) / 2, 178 + 18, w, foto.height * escala);
    ctx.restore();
    ctx.fillStyle = '#0d0608'; ctx.font = '900 66px "Playfair Display", serif';
    ctx.fillText('CARLOS JESSÉ', 46, 700);
    ctx.fillStyle = '#5c4744'; ctx.font = '600 26px Montserrat, sans-serif';
    ctx.fillText('Desenvolvedor full-stack', 48, 738);
    ctx.drawImage(qr, 48, 760, 128, 128);
    ctx.fillStyle = '#0d0608'; ctx.font = '700 28px Montserrat, sans-serif'; ctx.fillText('Fale comigo', 204, 800);
    ctx.fillStyle = '#5c4744'; ctx.font = '600 20px Montserrat, sans-serif';
    ctx.fillText('Aponte a câmera ou toque no QR', 204, 834);
    ctx.fillStyle = '#b52828'; ctx.font = '700 26px Montserrat, sans-serif'; ctx.fillText('(35) 99859-4066', 204, 872);
    return c;
}

function desenharVerso() {
    const c = document.createElement('canvas'); c.width = 640; c.height = 900;
    const ctx = c.getContext('2d');
    ctx.fillStyle = '#1a0a0d'; ctx.fillRect(0, 0, 640, 900);
    faixaDoTopo(ctx, '#8b1a1a');
    logo(ctx, 48, 128, 60, '#ece8e6', '#0d0608');
    ctx.fillStyle = '#ece8e6'; ctx.font = '900 54px "Playfair Display", serif';
    ctx.fillText('Tecnologias', 48, 236);
    ctx.font = '600 27px Montserrat, sans-serif';
    TECNOLOGIAS.forEach((t, i) => {
        const x = 48 + (i % 2) * 284, y = 300 + Math.floor(i / 2) * 58;
        ctx.fillStyle = '#d94040'; ctx.fillText('+', x, y);
        ctx.fillStyle = '#ece8e6'; ctx.fillText(t, x + 28, y);
    });
    ctx.fillStyle = '#d94040'; ctx.fillRect(48, 620, 72, 6);
    ctx.fillStyle = '#ece8e6'; ctx.font = 'italic 900 52px "Playfair Display", serif';
    ctx.fillText('Braço Forte,', 48, 704); ctx.fillText('Mão Amiga.', 48, 764);
    ctx.fillStyle = '#c9b8b1'; ctx.font = '600 22px Montserrat, sans-serif';
    ctx.fillText('Exército Brasileiro · 2020 a 2025', 48, 820);
    ctx.fillText('Toque para virar', 48, 862);
    return c;
}

function desenharCordao() {
    const c = document.createElement('canvas'); c.width = 1024; c.height = 64;
    const ctx = c.getContext('2d');
    ctx.fillStyle = '#b52828'; ctx.fillRect(0, 0, 1024, 64);
    ctx.fillStyle = '#ece8e6'; ctx.font = '700 30px Montserrat, sans-serif'; ctx.textBaseline = 'middle';
    ctx.fillText('CARLOS JESSÉ · DEV · CARLOS JESSÉ · DEV ·', 12, 34);
    return c;
}

function formaArredondada() {
    const s = new THREE.Shape(), w = LARGURA / 2, h = ALTURA / 2, r = CANTO;
    s.moveTo(-w + r, -h); s.lineTo(w - r, -h); s.quadraticCurveTo(w, -h, w, -h + r);
    s.lineTo(w, h - r); s.quadraticCurveTo(w, h, w - r, h); s.lineTo(-w + r, h);
    s.quadraticCurveTo(-w, h, -w, h - r); s.lineTo(-w, -h + r); s.quadraticCurveTo(-w, -h, -w + r, -h);
    return s;
}

function faceDoCartao(forma, textura) {
    const g = new THREE.ShapeGeometry(forma, 6);
    const uv = g.attributes.uv, pos = g.attributes.position;
    for (let i = 0; i < uv.count; i++) uv.setXY(i, (pos.getX(i) + LARGURA / 2) / LARGURA, (pos.getY(i) + ALTURA / 2) / ALTURA);
    return new THREE.Mesh(g, new THREE.MeshPhysicalMaterial({ map: textura, roughness: 0.42, clearcoat: 1, clearcoatRoughness: 0.18 }));
}

export async function montarCracha(canvas, { leve = false, calmo = false, aoTocarQr = () => {} } = {}) {
    await RAPIER.init();
    await Promise.all([
        document.fonts.load('900 66px "Playfair Display"'), document.fonts.load('italic 900 52px "Playfair Display"'),
        document.fonts.load('700 28px Montserrat'), document.fonts.load('600 26px Montserrat'),
    ]).catch(() => {});
    const [foto, qr] = await Promise.all([carregarImagem('assets/img/cenas/familia-recorte.webp'), carregarImagem('assets/img/cenas/qr-whatsapp.png')]);

    const renderer = new THREE.WebGLRenderer({ canvas, antialias: !leve, alpha: true });
    renderer.setPixelRatio(Math.min(devicePixelRatio, leve ? 1.5 : 2));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    const cena = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(25, 1, 0.1, 100);
    cena.add(new THREE.AmbientLight(0xffffff, 1.1));
    const luz = new THREE.DirectionalLight(0xffffff, 2.2); luz.position.set(2, 3, 6); cena.add(luz);
    const luzVermelha = new THREE.PointLight(0xd94040, 18, 14); luzVermelha.position.set(-3, -1, 3); cena.add(luzVermelha);

    const textura = (c) => { const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.anisotropy = renderer.capabilities.getMaxAnisotropy(); return t; };

    // o cartão: a borda grossa, a frente, o verso e o clipe de metal
    const forma = formaArredondada();
    const cartao = new THREE.Group();
    const borda = new THREE.Mesh(new THREE.ExtrudeGeometry(forma, { depth: ESPESSURA, bevelEnabled: false, curveSegments: 6 }), new THREE.MeshStandardMaterial({ color: 0x2a0f13, roughness: 0.6 }));
    borda.position.z = -ESPESSURA / 2;
    const frente = faceDoCartao(forma, textura(desenharFrente(foto, qr))); frente.position.z = ESPESSURA / 2 + 0.001;
    const verso = faceDoCartao(forma, textura(desenharVerso())); verso.rotation.y = Math.PI; verso.position.z = -ESPESSURA / 2 - 0.001;
    const metal = new THREE.MeshStandardMaterial({ color: 0xb8b2ae, metalness: 0.9, roughness: 0.25 });
    const clipe = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.12, 0.07), metal); clipe.position.y = ALTURA / 2 + 0.01;
    const argola = new THREE.Mesh(new THREE.TorusGeometry(0.07, 0.018, 10, 24), metal); argola.position.y = ALTURA / 2 + 0.13;
    cartao.add(borda, frente, verso, clipe, argola);
    cena.add(cartao);

    // o cordão: uma fita que passa pelos pontos da corrente
    const texCordao = textura(desenharCordao()); texCordao.wrapS = THREE.RepeatWrapping;
    const PONTOS = leve ? 24 : 40, LARG_CORDAO = 0.13;
    const geoCordao = new THREE.BufferGeometry();
    const posCordao = new Float32Array(PONTOS * 2 * 3), uvCordao = new Float32Array(PONTOS * 2 * 2), indices = [];
    for (let i = 0; i < PONTOS - 1; i++) { const a = i * 2; indices.push(a, a + 1, a + 2, a + 1, a + 3, a + 2); }
    geoCordao.setIndex(indices);
    geoCordao.setAttribute('position', new THREE.BufferAttribute(posCordao, 3));
    geoCordao.setAttribute('uv', new THREE.BufferAttribute(uvCordao, 2));
    const cordao = new THREE.Mesh(geoCordao, new THREE.MeshStandardMaterial({ map: texCordao, side: THREE.DoubleSide, roughness: 0.8 }));
    cordao.frustumCulled = false;
    cena.add(cordao);

    // a física: um ponto fixo, três elos de corda e o cartão preso no último
    const mundo = new RAPIER.World({ x: 0, y: -40, z: 0 });
    const corpo = (tipo, x, y) => mundo.createRigidBody(tipo.setTranslation(x, y, 0).setLinearDamping(2.5).setAngularDamping(2.5));
    const ancora = mundo.createRigidBody(RAPIER.RigidBodyDesc.fixed());
    const elos = [], inicio = calmo ? [[0, -1], [0, -2], [0, -3]] : [[0.5, 0], [1, 0], [1.5, 0]];
    for (const [dx, dy] of inicio) {
        const e = corpo(RAPIER.RigidBodyDesc.dynamic(), dx, dy);
        mundo.createCollider(RAPIER.ColliderDesc.ball(0.1).setCollisionGroups(0x00020002), e);
        elos.push(e);
    }
    const fisCartao = corpo(RAPIER.RigidBodyDesc.dynamic(), calmo ? 0 : 2, calmo ? -4.4 : 0);
    mundo.createCollider(RAPIER.ColliderDesc.cuboid(LARGURA / 2, ALTURA / 2, 0.01).setCollisionGroups(0x00010001), fisCartao);
    const zero = { x: 0, y: 0, z: 0 };
    mundo.createImpulseJoint(RAPIER.JointData.rope(1, zero, zero), ancora, elos[0], true);
    mundo.createImpulseJoint(RAPIER.JointData.rope(1, zero, zero), elos[0], elos[1], true);
    mundo.createImpulseJoint(RAPIER.JointData.rope(1, zero, zero), elos[1], elos[2], true);
    mundo.createImpulseJoint(RAPIER.JointData.spherical(zero, { x: 0, y: ALTURA / 2 + 0.15, z: 0 }), elos[2], fisCartao, true);

    // tamanho e lugar: no computador o crachá pende à direita do nome; no celular, no meio
    let largura = 1, altura = 1, ancoraPos = new THREE.Vector3();
    function medir() {
        const r = canvas.getBoundingClientRect();
        largura = Math.max(1, r.width); altura = Math.max(1, r.height);
        renderer.setSize(largura, altura, false);
        camera.aspect = largura / altura;
        const estreito = largura < 760;
        camera.position.set(0, 0, estreito ? 15 : 13);
        camera.updateProjectionMatrix();
        const vh = 2 * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * camera.position.z, vw = vh * camera.aspect;
        const novo = new THREE.Vector3(estreito ? 0 : vw * 0.24, estreito ? vh / 2 + 1.9 : vh / 2 + 1.55, 0);
        const desloca = novo.clone().sub(ancoraPos);
        ancoraPos = novo;
        ancora.setTranslation(novo, true);
        for (const b of [...elos, fisCartao]) { const t = b.translation(); b.setTranslation({ x: t.x + desloca.x, y: t.y + desloca.y, z: t.z }, true); }
    }
    medir();
    new ResizeObserver(medir).observe(canvas);

    // arrastar, jogar e virar
    const raio = new THREE.Raycaster(), ponteiro = new THREE.Vector2(), plano = new THREE.Plane(new THREE.Vector3(0, 0, 1), 0);
    let pegando = null, ladoAlvo = 0, giro = 0, acordadoAte = performance.now() + 8000;
    const rastro = [];
    function mirar(ev) {
        const r = canvas.getBoundingClientRect();
        ponteiro.set(((ev.clientX - r.left) / r.width) * 2 - 1, -((ev.clientY - r.top) / r.height) * 2 + 1);
        raio.setFromCamera(ponteiro, camera);
        return raio.intersectObjects([frente, verso, borda, clipe], false)[0];
    }
    function pontoNoPlano(ev) {
        mirar(ev);
        const p = new THREE.Vector3();
        return raio.ray.intersectPlane(plano, p) ? p : null;
    }
    // no toque, o dedo só "pega" o crachá se ficar parado nele um instante ou se puxar para o lado;
    // um deslize rápido para cima ou para baixo rola a página normalmente
    let dedo = null;
    canvas.addEventListener('touchstart', (ev) => {
        const t = ev.touches[0];
        dedo = mirar(t) ? { x: t.clientX, y: t.clientY, quando: performance.now(), decidido: false, pega: false } : null;
    }, { passive: true });
    canvas.addEventListener('touchmove', (ev) => {
        if (!dedo) return;
        if (!dedo.decidido) {
            const t = ev.touches[0], dx = Math.abs(t.clientX - dedo.x), dy = Math.abs(t.clientY - dedo.y);
            dedo.decidido = true;
            dedo.pega = performance.now() - dedo.quando > 150 || dx > dy;
        }
        if (dedo.pega) ev.preventDefault();
    }, { passive: false });
    canvas.addEventListener('pointerdown', (ev) => {
        const acerto = mirar(ev);
        if (!acerto) return;
        const t = fisCartao.translation(), p = pontoNoPlano(ev);
        pegando = { desloc: new THREE.Vector3(p.x - t.x, p.y - t.y, 0), x: ev.clientX, y: ev.clientY, quando: performance.now(), acerto };
        rastro.length = 0;
        fisCartao.setBodyType(RAPIER.RigidBodyType.KinematicPositionBased, true);
        canvas.setPointerCapture(ev.pointerId);
        canvas.style.cursor = 'grabbing';
        acordadoAte = Infinity;
    });
    canvas.addEventListener('pointermove', (ev) => {
        if (!pegando) { canvas.style.cursor = mirar(ev) ? 'grab' : ''; return; }
        const p = pontoNoPlano(ev);
        if (!p) return;
        const alvo = { x: p.x - pegando.desloc.x, y: p.y - pegando.desloc.y, z: 0 };
        fisCartao.setNextKinematicTranslation(alvo);
        rastro.push({ ...alvo, t: performance.now() }); if (rastro.length > 6) rastro.shift();
    });
    function soltar(ev) {
        if (!pegando) return;
        // pointercancel = o navegador decidiu rolar a página: só solta, sem contar como toque
        const toque = ev.type !== 'pointercancel' && performance.now() - pegando.quando < 280 && Math.hypot(ev.clientX - pegando.x, ev.clientY - pegando.y) < 8;
        fisCartao.setBodyType(RAPIER.RigidBodyType.Dynamic, true);
        if (rastro.length > 1) {
            const a = rastro[0], b = rastro[rastro.length - 1], dt = Math.max(16, b.t - a.t) / 1000;
            const lim = (v) => Math.max(-30, Math.min(30, v));
            fisCartao.setLinvel({ x: lim((b.x - a.x) / dt), y: lim((b.y - a.y) / dt), z: 0 }, true);
        }
        if (toque) {
            const { object, uv } = pegando.acerto;
            if (object === frente && uv && uv.x > QR_AREA.x0 && uv.x < QR_AREA.x1 && uv.y > QR_AREA.y0 && uv.y < QR_AREA.y1) aoTocarQr();
            else { ladoAlvo = ladoAlvo ? 0 : Math.PI; giro = 1; }
        }
        pegando = null;
        canvas.style.cursor = '';
        acordadoAte = performance.now() + 6000;
    }
    canvas.addEventListener('pointerup', soltar);
    canvas.addEventListener('pointercancel', soltar);

    // a fita do cordão acompanha a corrente
    const curva = new THREE.CatmullRomCurve3([new THREE.Vector3(), new THREE.Vector3(), new THREE.Vector3(), new THREE.Vector3(), new THREE.Vector3()], false, 'centripetal');
    const suaves = elos.map((e) => new THREE.Vector3().copy(e.translation()));
    const frenteDir = new THREE.Vector3(0, 0, 1), tangente = new THREE.Vector3(), lado = new THREE.Vector3(), ponto = new THREE.Vector3();
    const q = new THREE.Quaternion(), topoCartao = new THREE.Vector3();
    function desenharCordaoAgora() {
        topoCartao.set(0, ALTURA / 2 + 0.15, 0).applyQuaternion(cartao.quaternion).add(cartao.position);
        const pts = curva.points;
        pts[0].copy(topoCartao); pts[1].copy(suaves[2]); pts[2].copy(suaves[1]); pts[3].copy(suaves[0]); pts[4].copy(ancoraPos);
        const total = curva.getLength();
        for (let i = 0; i < PONTOS; i++) {
            const u = i / (PONTOS - 1);
            curva.getPointAt(u, ponto); curva.getTangentAt(u, tangente);
            lado.crossVectors(tangente, frenteDir).normalize().multiplyScalar(LARG_CORDAO / 2);
            posCordao.set([ponto.x - lado.x, ponto.y - lado.y, ponto.z - lado.z, ponto.x + lado.x, ponto.y + lado.y, ponto.z + lado.z], i * 6);
            const s = (u * total) / 1.9;
            uvCordao.set([s, 0, s, 1], i * 4);
        }
        geoCordao.attributes.position.needsUpdate = true;
        geoCordao.attributes.uv.needsUpdate = true;
        geoCordao.computeVertexNormals();
    }

    const PASSO = 1 / 60;
    let acumulado = 0, ultimo = performance.now(), ligado = true, quadro = 0;
    function passo() {
        // o cartão tende a ficar de frente (ou de costas, se foi virado)
        const r = fisCartao.rotation(); q.set(r.x, r.y, r.z, r.w);
        const dir = new THREE.Vector3(0, 0, 1).applyQuaternion(q);
        const guinada = Math.atan2(dir.x, dir.z);
        let dif = ladoAlvo - guinada; dif = Math.atan2(Math.sin(dif), Math.cos(dif));
        const ang = fisCartao.angvel();
        const empurrao = giro > 0 ? Math.sign(dif || 1) * 0.9 : 0;
        if (giro > 0 && Math.abs(dif) < 0.4) giro = 0;
        fisCartao.setAngvel({ x: ang.x, y: ang.y + dif * 0.25 + empurrao, z: ang.z }, true);
        mundo.step();
    }
    function animar(agora) {
        quadro = requestAnimationFrame(animar);
        if (!ligado) return;
        acumulado = Math.min(acumulado + (agora - ultimo) / 1000, 0.1); ultimo = agora;
        if (agora < acordadoAte || calmo === false) {
            while (acumulado >= PASSO) { passo(); acumulado -= PASSO; }
        }
        const t = fisCartao.translation(), r = fisCartao.rotation();
        cartao.position.set(t.x, t.y, t.z); cartao.quaternion.set(r.x, r.y, r.z, r.w);
        elos.forEach((e, i) => { const p = e.translation(); suaves[i].lerp(new THREE.Vector3(p.x, p.y, p.z), pegando ? 1 : 0.6); });
        desenharCordaoAgora();
        renderer.render(cena, camera);
    }
    quadro = requestAnimationFrame(animar);

    return {
        ligar(sim) { if (sim && !ligado) ultimo = performance.now(); ligado = sim; },
        // usado nos testes: onde o cartão está na tela
        posicaoNaTela() {
            const p = cartao.position.clone().project(camera);
            const r = canvas.getBoundingClientRect();
            return { x: r.left + (p.x + 1) / 2 * r.width, y: r.top + (1 - p.y) / 2 * r.height, lado: ladoAlvo };
        },
        parar() { cancelAnimationFrame(quadro); renderer.dispose(); },
    };
}
