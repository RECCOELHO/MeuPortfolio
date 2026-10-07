/* ============================================================
   FAZENDINHA SECRETA — cliente
   Todas as regras (tempo, moedas, nível) são validadas no Supabase
   pelas funções fazenda_* (ver supabase/fazenda.sql). Aqui só
   desenhamos o estado (via fazenda-arte.js) e mandamos as ações.
============================================================ */
(function () {
    'use strict';

    const A = window.FazendaArte;
    const SUPABASE_URL = 'https://vhdjqppzylxdksgjzvsh.supabase.co';
    const SUPABASE_KEY = 'sb_publishable_y-rrBFvf0QRFG3WL3P0kxQ_gItonE2U';

    // Em localhost dá pra apontar para um backend de teste: fazenda.html?api=http://localhost:8787
    let API = SUPABASE_URL;
    try {
        const alt = new URLSearchParams(location.search).get('api');
        if (alt && /^(localhost|127\.0\.0\.1)$/.test(location.hostname)) API = alt;
    } catch { /* ignora */ }

    const TOTAL_CANTEIROS = 18;
    const POLL_MS = 30000;

    /* ---------- Armazenamento local (protegido) ---------- */
    const LS = { token: 'fazenda_token', codigo: 'fazenda_codigo', semente: 'fazenda_semente', diarioVisto: 'fazenda_diario_visto' };
    const store = {
        get(k) { try { return localStorage.getItem(k); } catch { return null; } },
        set(k, v) { try { localStorage.setItem(k, v); } catch { /* ignora */ } },
        del(k) { try { localStorage.removeItem(k); } catch { /* ignora */ } }
    };

    /* ---------- Mensagens de erro do servidor ---------- */
    const ERROS = {
        token_invalido: 'Sessão expirada. Entre de novo com seu código.',
        apelido_invalido: 'O apelido precisa ter de 2 a 20 letras.',
        codigo_invalido: 'Código não encontrado. Confira e tente de novo.',
        canteiro_bloqueado: 'Esse canteiro ainda está bloqueado.',
        ja_arado: 'Esse canteiro já está arado.',
        canteiro_ocupado: 'Tem uma planta crescendo aí.',
        precisa_arar: 'Are o canteiro antes de plantar.',
        cultura_invalida: 'Semente inválida.',
        nivel_insuficiente: 'Você ainda não tem nível para essa semente.',
        moedas_insuficientes: 'Moedas insuficientes.',
        nada_a_fazer: 'Nada pra fazer aqui.',
        nao_maduro: 'Ainda não está pronto.',
        murchou: 'Essa planta murchou… are o canteiro para limpar.',
        acao_invalida: 'Ação inválida.',
        quantidade_invalida: 'Quantidade inválida.',
        muitas_fazendas: 'Muita gente chegando agora! Tente de novo daqui a pouco.',
        propria_fazenda: 'Essa é a sua própria fazenda!',
        vizinho_invalido: 'Essa fazenda não existe mais.',
        nenhum_vizinho: 'Ainda não tem vizinhos por aqui. Chame alguém para jogar!',
        ja_pegou: 'Você já pegou desse canteiro. Deixa um pouco pro dono!',
        nada_pra_pegar: 'Esse canteiro já foi bem visitado… não sobrou nada.',
        limite_pegadas: 'Você já pegou demais hoje. Volte amanhã.',
        sem_racao: 'Falta ração no celeiro.',
        ja_alimentado: 'Esse bicho já comeu.',
        nao_pronto: 'Ainda não tem nada pra coletar.',
        animal_invalido: 'Esse animal não está mais aqui.',
        limite_animais: 'Você já tem o máximo desse animal.',
        item_invalido: 'Item inválido.',
        lugar_reservado: 'Esse lugar é reservado (celeiro, casa, campo, pasto ou galinheiro).',
        lugar_ocupado: 'Já tem algo nesse lugar.',
        limite_construcoes: 'Sua fazenda já está cheia de construções. Guarde algumas antes.',
        missao_invalida: 'Missão não encontrada.',
        ja_resgatada: 'Você já pegou essa recompensa.',
        missao_incompleta: 'Termine a missão antes de resgatar.'
    };

    async function rpc(fn, args) {
        let res;
        try {
            res = await fetch(`${API}/rest/v1/rpc/${fn}`, {
                method: 'POST',
                headers: {
                    apikey: SUPABASE_KEY,
                    Authorization: 'Bearer ' + SUPABASE_KEY,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(args)
            });
        } catch {
            throw Object.assign(new Error('Sem conexão com a fazenda. Tente de novo.'), { code: 'rede' });
        }
        const data = await res.json().catch(() => null);
        if (!res.ok) {
            const code = data && data.message;
            throw Object.assign(new Error(ERROS[code] || 'Algo deu errado na fazenda.'), { code });
        }
        return data;
    }

    /* ---------- DOM ---------- */
    const $ = (id) => document.getElementById(id);
    const el = {
        canvas: $('cena'), hud: $('hud'), barra: $('barra'), status: $('status'),
        apelido: $('hudApelido'), nivel: $('hudNivel'), xpBar: $('hudXpBar'), xp: $('hudXp'),
        moedas: $('hudMoedas'), celeiroCont: $('hudCeleiro'),
        semIcone: $('semIcone'), semNome: $('semNome'), btnSemente: $('btnSemente'),
        toasts: $('toasts'), flut: $('flutuantes'),
        entrada: $('telaEntrada'), entradaCarregando: $('entradaCarregando'), entradaAbas: $('entradaAbas'),
        entradaErro: $('entradaErro'), formNova: $('formNova'), formCodigo: $('formCodigo'),
        inApelido: $('inApelido'), inCodigo: $('inCodigo'),
        painel: $('painel'), painelTitulo: $('painelTitulo'), painelCorpo: $('painelCorpo'), painelFechar: $('painelFechar'),
        faixaVisita: $('faixaVisita'), visitaApelido: $('visitaApelido'), visitaNivel: $('visitaNivel'),
        btnVoltarCasa: $('btnVoltarCasa'), acoesVisita: $('acoesVisita'), acoesCasa: $('acoesCasa'),
        diarioCont: $('hudDiario'), missoesCont: $('hudMissoes'),
        barraConstr: $('barraConstr'), constrAbas: $('constrAbas'), constrItens: $('constrItens'),
        constrFerramentas: $('constrFerramentas'), btnConstruir: $('btnConstruir')
    };

    /* ---------- Ícones (pixel art) ---------- */
    const ico = (nome, px) => A.htmlIcone(nome, px);
    const spr = (i, px, pacote) => A.htmlTile(i, px, pacote);
    const moeda = (n) => `${ico('moeda', 14)}${n}`;
    const itemDe = (k, px = 22) => spr(A.cultura(k.id).item, px);

    document.querySelectorAll('[data-spr]').forEach((s) => { s.outerHTML = spr(Number(s.dataset.spr), Number(s.dataset.px) || 32, s.dataset.pack || 'farm'); });
    document.querySelectorAll('[data-ico]').forEach((s) => { s.outerHTML = ico(s.dataset.ico, Number(s.dataset.px) || 18); });

    /* ---------- Estado ---------- */
    let token = store.get(LS.token);
    let S = null;                 // último estado vindo do servidor
    let visita = null;            // fazenda do vizinho sendo visitada (null = em casa)
    let abaVizinhos = 'ranking';
    let abaLoja = 'sementes';
    let ultimoAvisoDiario = Number(store.get(LS.diarioVisto)) || 0;
    let culturas = {};            // id -> cultura
    let offset = 0;               // relógio do servidor - relógio local (ms)
    let semente = store.get(LS.semente) || 'alface';
    let fila = Promise.resolve(); // ações em série para o estado nunca voltar no tempo
    let pendentes = 0;
    const pendentesPos = new Set();
    let painelAtual = null;
    let ultimoFoco = null;
    let voltaFazendeiro = null;

    const agora = () => Date.now() + offset;
    const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

    function fmtTempo(ms) {
        const s = Math.max(0, Math.ceil(ms / 1000));
        const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60), ss = s % 60;
        if (d) return `${d}d ${h}h`;
        if (h) return `${h}h ${m}m`;
        if (m) return `${m}m ${ss}s`;
        return `${ss}s`;
    }

    function fmtDuracao(seg) {
        if (seg < 3600) return `${Math.round(seg / 60)} min`;
        if (seg < 86400) return `${Math.round(seg / 3600)} h`;
        return `${Math.round(seg / 86400)} dia`;
    }

    const nivelParaCanteiro = (pos) => Math.floor((pos - 6) / 2) + 2;

    /* ---------- Leitura de um canteiro ---------- */
    function canteiro(p) {
        const fonte = visita || S;
        return fonte && fonte.canteiros.find((c) => c.posicao === p);
    }

    function info(c) {
        if (!c) return { fase: 'bloqueado' };
        if (c.estado !== 'plantado') return { fase: c.estado };
        const k = culturas[c.cultura];
        const inicio = Date.parse(c.plantado_em);
        const maduro = inicio + k.tempo_seg * 1000;
        const murcho = maduro + Math.max(k.tempo_seg * 2, 3600) * 1000;
        const t = agora();
        const probs = ['erva', 'praga', 'seco'].filter((p) => c[p]);
        const base = { k, probs, maduro, murcho };
        if (t >= murcho) return { ...base, fase: 'murcho' };
        if (t >= maduro) return { ...base, fase: 'maduro', resta: murcho - t };
        return { ...base, fase: 'crescendo', prog: (t - inicio) / (maduro - inicio), resta: maduro - t };
    }

    // Ação do "clique esperto" em um canteiro
    function acaoPara(c) {
        const i = info(c);
        switch (i.fase) {
            case 'vazio': return 'arar';
            case 'arado': return 'plantar';
            case 'murcho': return 'arar';
            case 'crescendo':
            case 'maduro':
                if (i.probs.length) return i.probs[0];
                return i.fase === 'maduro' ? 'colher' : null;
            default: return null;
        }
    }

    // Visitando: o que dá pra fazer no canteiro do vizinho
    const limitePegar = (k) => Math.floor(k.rendimento * 0.4);
    function podePegar(c, i) {
        return i.fase === 'maduro' && !c.ja_peguei && c.roubado < limitePegar(i.k);
    }
    function acaoVisita(c) {
        const i = info(c);
        if ((i.fase === 'crescendo' || i.fase === 'maduro') && i.probs.length) return 'ajudar';
        if (podePegar(c, i)) return 'pegar';
        return null;
    }

    const PROB_NOME = { erva: 'erva daninha', praga: 'praga', seco: 'terra seca' };
    const probsHtml = (probs) => probs.map((x) => ico(x, 14)).join('');

    /* ---------- Cena ---------- */
    // Fazenda de enfeite que aparece atrás da tela de entrada
    const DEMO = [
        { solo: 'arado', planta: 6, maduro: true }, { solo: 'arado', planta: 29, progresso: 0.6 },
        { solo: 'arado', planta: 42, maduro: true }, { solo: 'arado', planta: 52, progresso: 0.2, probs: ['erva'] },
        { solo: 'arado', planta: 66, maduro: true }, { solo: 'arado' },
        { solo: 'arado', planta: 17, progresso: 0.5 }, { solo: 'vazio' }
    ];

    function visualCanteiro(p) {
        if (!S) return DEMO[p] || { solo: 'bloqueado' };
        const c = canteiro(p);
        const i = info(c);
        const pendente = pendentesPos.has(p);
        if (i.fase === 'bloqueado') return { solo: 'bloqueado' };
        if (i.fase === 'vazio' || i.fase === 'arado') return { solo: i.fase, pendente };
        const arte = A.cultura(i.k.id);
        const v = { solo: 'arado', seco: c.seco && i.fase !== 'murcho', pendente };
        if (i.fase === 'murcho') {
            v.planta = arte.murcho;
        } else {
            v.probs = i.probs;
            if (i.fase === 'maduro') { v.planta = arte.fases[2]; v.maduro = true; }
            else { v.planta = i.prog < 0.5 ? arte.fases[0] : arte.fases[1]; v.progresso = i.prog; }
        }
        if (visita && i.fase === 'maduro') {
            if (podePegar(c, i)) v.pegar = true;
            else { v.cinza = true; v.check = !!c.ja_peguei; }
        }
        return v;
    }

    /* ---------- Animais e construções ---------- */
    const tipoAnimal = (id) => S && S.animais_tipos && S.animais_tipos.find((t) => t.id === id);
    const tipoItem = (id) => S && S.itens && S.itens.find((t) => t.id === id);
    const meusAnimais = () => (visita ? visita.animais : S && S.animais) || [];
    const naCeleiro = (item) => (S && S.celeiro[item]) || 0;

    function infoAnimal(a) {
        const t = tipoAnimal(a.tipo);
        if (!t) return { estado: 'produzindo' };
        if (!a.alimentado_em) return { estado: 'fome', t };
        const pronto = Date.parse(a.alimentado_em) + t.tempo_seg * 1000;
        const falta = pronto - agora();
        if (falta <= 0) return { estado: 'pronto', t };
        return { estado: 'produzindo', t, prog: 1 - falta / (t.tempo_seg * 1000), resta: falta };
    }

    const DEMO_ANIMAIS = [
        { id: 'd1', tipo: 'galinha', estado: 'pronto', produto: 125 },
        { id: 'd2', tipo: 'galinha', estado: 'produzindo' },
        { id: 'd3', tipo: 'vaca', estado: 'produzindo' },
        { id: 'd4', tipo: 'vaca', estado: 'fome', racao: 20 }
    ];
    // Construções de enfeite atrás da tela de entrada
    const DEMO_CONSTRUCOES = [
        ...[8, 9, 10, 11, 12, 13, 14, 15].map((x) => ({ x, y: 8, tipo: 'caminho_terra' })),
        ...[9, 10, 11, 12, 13, 14].map((x) => ({ x, y: 2, tipo: 'cerca' })),
        { x: 8, y: 2, tipo: 'girassol' }, { x: 15, y: 2, tipo: 'girassol' },
        { x: 8, y: 10, tipo: 'arvore' }, { x: 12, y: 10, tipo: 'pinheiro' }, { x: 15, y: 10, tipo: 'arvore_outono' },
        { x: 10, y: 10, tipo: 'flores' }, { x: 11, y: 10, tipo: 'flores' }, { x: 14, y: 9, tipo: 'feno' },
        { x: 17, y: 8, tipo: 'colmeia' }, { x: 19, y: 9, tipo: 'placa' }
    ];

    function visualAnimais() {
        if (!S) return DEMO_ANIMAIS;
        return meusAnimais().map((a) => {
            const i = infoAnimal(a);
            return {
                id: a.id, tipo: a.tipo, estado: i.estado, progresso: i.prog,
                racao: i.t ? A.cultura(i.t.racao).item : null,
                produto: i.t ? A.cultura(i.t.produto).item : null
            };
        });
    }

    function visualConstrucoes() {
        if (!S) return DEMO_CONSTRUCOES;
        return (visita ? visita.construcoes : S.construcoes) || [];
    }

    const cena = A.criarCena(el.canvas, {
        aoCanteiro: (p) => clicarCanteiro(p),
        aoAnimal: (id) => clicarAnimal(id),
        aoTile: (x, y) => tocarTile(x, y),
        aoCeleiro: () => { if (S && !painelAtual) abrirPainel('celeiro'); },
        aoPassar: (alvo) => {
            if (!S || alvo == null) return;
            if (alvo === 'celeiro') mostrarStatus(`${spr(11, 22)} Celeiro: toque para ver e vender a colheita.`);
            else if (typeof alvo === 'object' && 'tx' in alvo) descreverTile(alvo.tx, alvo.ty);
            else if (typeof alvo === 'object') descreverAnimal(alvo.animal);
            else descrever(alvo);
        }
    });
    cena.definirVisual(visualCanteiro);
    cena.definirAnimais(visualAnimais);
    cena.definirConstrucoes(visualConstrucoes);

    /* ---------- Modo construir (abre e fecha pelo botão) ---------- */
    const constr = { ativo: false, modo: 'colocar', tipo: null, movendo: null, aba: 'caminho' };
    const atualizarModo = () => cena.definirModoConstrucao({ ...constr });
    const NOME_AREA = (x, y) => {
        const dentro = (r) => x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h;
        const [cel, casa, gal, campo, pasto] = A.MAPA.reservas;
        if (dentro(cel)) return 'o celeiro';
        if (dentro(casa)) return 'a casa';
        if (dentro(gal)) return 'o galinheiro';
        if (dentro(campo)) return 'o campo';
        if (dentro(pasto)) return 'o pasto';
        return 'fora do terreno';
    };
    const construcaoEm = (x, y) => (S.construcoes || []).find((c) => c.x === x && c.y === y);

    function descreverTile(x, y) {
        if (!A.livre(x, y)) return mostrarStatus(`${ico('cadeado', 12)} Aqui fica ${NOME_AREA(x, y)}: não dá para construir.`);
        const c = construcaoEm(x, y);
        const it = c && tipoItem(c.tipo);
        if (constr.modo === 'guardar') {
            return mostrarStatus(it ? `${A.htmlItem(c.tipo, 22)} Toque para guardar ${esc(it.nome.toLowerCase())} (volta ${moeda(Math.floor(it.custo / 2))}).` : 'Nada para guardar aqui.');
        }
        if (constr.modo === 'mover') {
            if (constr.movendo) return mostrarStatus(c ? 'Esse lugar está ocupado.' : 'Toque para levar o item para cá.');
            return mostrarStatus(it ? `${A.htmlItem(c.tipo, 22)} Toque para escolher ${esc(it.nome.toLowerCase())} e depois o novo lugar.` : 'Toque num item para mover.');
        }
        const sel = tipoItem(constr.tipo);
        if (c) return mostrarStatus(`${A.htmlItem(c.tipo, 22)} ${esc(it ? it.nome : c.tipo)}. Use Mover ou Guardar para mudar.`);
        mostrarStatus(sel ? `${A.htmlItem(sel.id, 22)} Toque para colocar ${esc(sel.nome.toLowerCase())} (${moeda(sel.custo)}).` : 'Escolha um item na barra de baixo.');
    }

    function abrirConstrucao() {
        if (!S || visita) return;
        constr.ativo = true;
        constr.modo = 'colocar';
        constr.movendo = null;
        document.body.classList.add('construindo');
        el.barraConstr.hidden = false;
        el.barra.hidden = true;
        desenharPaleta();
        atualizarModo();
        mostrarStatus('Modo construir: escolha um item e toque nos quadrados livres. Arraste para ver o terreno.');
        ajustarMargens();
    }

    function fecharConstrucao() {
        constr.ativo = false;
        constr.movendo = null;
        document.body.classList.remove('construindo');
        el.barraConstr.hidden = true;
        el.barra.hidden = false;
        atualizarModo();
        mostrarStatus('Fazenda salva do seu jeito!');
        ajustarMargens();
    }

    function desenharPaleta() {
        if (!S || !S.itens) return;
        const abas = [['caminho', 'Cercas e caminhos'], ['natureza', 'Natureza'], ['objeto', 'Objetos']];
        el.constrAbas.innerHTML = abas.map(([id, txt]) =>
            `<button type="button" data-constr-aba="${id}" class="${constr.aba === id ? 'ativa' : ''}">${txt}</button>`).join('');
        el.constrItens.innerHTML = S.itens.filter((i) => i.categoria === constr.aba).map((i) => {
            const travado = i.nivel_min > S.jogador.nivel;
            const sel = constr.modo === 'colocar' && constr.tipo === i.id;
            return `<button type="button" class="paleta-item${sel ? ' selecionado' : ''}${travado ? ' travado' : ''}" data-item="${esc(i.id)}" title="${esc(i.nome)}">
                ${travado ? ico('cadeado', 18) : A.htmlItem(i.id, 32)}
                <small>${travado ? `Nv ${i.nivel_min}` : `${ico('moeda', 11)}${i.custo}`}</small>
            </button>`;
        }).join('');
        el.constrFerramentas.querySelectorAll('[data-ferramenta]').forEach((b) => b.classList.toggle('ativa', b.dataset.ferramenta === constr.modo));
    }

    function flutuarTile(x, y, html) {
        const pos = cena.telaDoTile(x, y);
        const f = document.createElement('div');
        f.className = 'flut';
        f.innerHTML = html;
        f.style.left = `${pos.x}px`;
        f.style.top = `${pos.y}px`;
        el.flut.appendChild(f);
        setTimeout(() => f.remove(), 1300);
    }

    function tocarTile(x, y) {
        if (!constr.ativo || !S) return;
        descreverTile(x, y);
        if (!A.livre(x, y)) return toast(`Aqui fica ${NOME_AREA(x, y)}.`, 'erro');
        const ocupado = construcaoEm(x, y);

        if (constr.modo === 'colocar') {
            const it = tipoItem(constr.tipo);
            if (!it) return toast('Escolha um item na barra de baixo.');
            if (ocupado) return toast(ERROS.lugar_ocupado, 'erro');
            if (it.nivel_min > S.jogador.nivel) return toast(`${esc(it.nome)} libera no nível ${it.nivel_min}.`);
            if (S.jogador.moedas < it.custo) return toast(ERROS.moedas_insuficientes, 'erro');
            // aparece na hora; o servidor confirma em seguida
            S.construcoes.push({ x, y, tipo: it.id });
            S.jogador.moedas -= it.custo;
            desenharHud();
            flutuarTile(x, y, `−${it.custo} ${ico('moeda', 16)}`);
            enfileirar([], async () => {
                const r = await rpc('fazenda_construir', { p_token: token, p_tipo: it.id, p_x: x, p_y: y });
                aplicarEstado(r.estado);
            }).then(() => { if (!S.construcoes.some((c) => c.x === x && c.y === y)) recarregar(); });
        } else if (constr.modo === 'mover') {
            if (!constr.movendo) {
                if (!ocupado) return toast('Toque num item para mover.');
                constr.movendo = { x, y };
                atualizarModo();
                return mostrarStatus('Agora toque no lugar novo.');
            }
            const de = constr.movendo;
            constr.movendo = null;
            atualizarModo();
            if (de.x === x && de.y === y) return;
            if (ocupado) return toast(ERROS.lugar_ocupado, 'erro');
            const c = construcaoEm(de.x, de.y);
            if (c) { c.x = x; c.y = y; }
            enfileirar([], async () => {
                const r = await rpc('fazenda_mover', { p_token: token, p_x: de.x, p_y: de.y, p_nx: x, p_ny: y });
                aplicarEstado(r.estado);
            });
        } else if (constr.modo === 'guardar') {
            if (!ocupado) return;
            S.construcoes = S.construcoes.filter((c) => c !== ocupado);
            enfileirar([], async () => {
                const r = await rpc('fazenda_demolir', { p_token: token, p_x: x, p_y: y });
                flutuarTile(x, y, `+${r.devolvido} ${ico('moeda', 16)}`);
                aplicarEstado(r.estado);
            });
        }
    }

    function ajustarMargens() {
        const topo = el.hud.hidden ? 24 : el.hud.getBoundingClientRect().bottom + 8;
        const barra = !el.barraConstr.hidden ? el.barraConstr : el.barra.hidden ? null : el.barra;
        const base = barra ? window.innerHeight - barra.getBoundingClientRect().top + 44 : 24;
        cena.definirMargens(Math.round(topo), Math.round(base));
    }
    window.addEventListener('resize', ajustarMargens);

    /* ---------- HUD e status ---------- */
    function desenharHud() {
        const j = S.jogador;
        el.apelido.textContent = j.apelido;
        el.nivel.textContent = j.nivel;
        const faixa = j.xp_proximo - j.xp_nivel;
        el.xpBar.style.width = `${Math.min(100, ((j.xp - j.xp_nivel) / faixa) * 100)}%`;
        el.xp.textContent = `${j.xp}/${j.xp_proximo}`;
        if (el.moedas.textContent !== String(j.moedas)) {
            el.moedas.textContent = j.moedas;
            const box = el.moedas.parentElement;
            box.classList.remove('pulo');
            void box.offsetWidth;
            box.classList.add('pulo');
        }
        const totalCeleiro = Object.values(S.celeiro).reduce((a, b) => a + b, 0);
        el.celeiroCont.textContent = totalCeleiro;
        el.celeiroCont.hidden = !totalCeleiro;
        const prontas = (S.missoes || []).filter((m) => !m.resgatada && m.progresso >= m.alvo).length;
        el.missoesCont.textContent = prontas;
        el.missoesCont.hidden = !prontas;

        const k = culturas[semente];
        el.semIcone.innerHTML = k ? spr(A.cultura(k.id).item, 32) : '';
        el.semNome.innerHTML = k ? `${esc(k.nome)} · ${moeda(k.custo)}` : 'Escolher';
    }

    function mostrarStatus(html) {
        el.status.innerHTML = html;
    }

    function descreverVisita(c, i) {
        if (i.fase === 'bloqueado') return `${ico('cadeado', 12)} Canteiro bloqueado do vizinho.`;
        if (i.fase === 'vazio' || i.fase === 'arado') return 'Canteiro livre. Nada pra fazer aqui.';
        const item = itemDe(i.k);
        if (i.fase === 'murcho') return `O ${esc(i.k.nome.toLowerCase())} do vizinho murchou.`;
        let txt;
        if (i.fase === 'maduro') {
            if (c.ja_peguei) txt = `${item} Você já pegou desse ${esc(i.k.nome.toLowerCase())}.`;
            else if (c.roubado >= limitePegar(i.k)) txt = `${item} Já pegaram bastante desse ${esc(i.k.nome.toLowerCase())}.`;
            else txt = `${item} ${esc(i.k.nome)} maduro! Toque para pegar 1 ou 2 ${ico('mao', 16)}`;
        } else {
            txt = `${item} ${esc(i.k.nome)} do vizinho · pronto em ${fmtTempo(i.resta)}.`;
        }
        if (i.probs.length) txt += ` Ajude com ${probsHtml(i.probs)} e ganhe +${i.probs.length} ${ico('xp', 14)} e ${moeda(i.probs.length)}.`;
        return txt;
    }

    function descrever(p) {
        const c = canteiro(p);
        const i = info(c);
        if (visita) return mostrarStatus(descreverVisita(c, i));
        let txt;
        switch (i.fase) {
            case 'bloqueado': txt = `${ico('cadeado', 12)} Libera no nível ${nivelParaCanteiro(p)}.`; break;
            case 'vazio': txt = `${spr(86, 22)} Terra batida. Toque para arar (+1 ${ico('xp', 14)}).`; break;
            case 'arado': {
                const k = culturas[semente];
                txt = k ? `${itemDe(k)} Toque para plantar ${esc(k.nome.toLowerCase())} (${moeda(k.custo)}).` : 'Pronto para plantar.';
                break;
            }
            case 'murcho': txt = `${spr(A.cultura(i.k.id).murcho, 22)} ${esc(i.k.nome)} murchou. Toque para limpar.`; break;
            case 'maduro': txt = `${itemDe(i.k)} ${esc(i.k.nome)} pronto! Toque para colher. Murcha em ${fmtTempo(i.resta)}.`; break;
            default: txt = `${itemDe(i.k)} ${esc(i.k.nome)} · ${Math.floor(i.prog * 100)}% · pronto em ${fmtTempo(i.resta)}.`;
        }
        if (i.probs && i.probs.length && i.fase !== 'murcho') {
            txt += ` Cuide de ${probsHtml(i.probs)} (−1 cada na colheita).`;
        }
        mostrarStatus(txt);
    }

    function descreverAnimal(id) {
        const a = meusAnimais().find((x) => x.id === id);
        if (!a) return;
        const i = infoAnimal(a);
        if (!i.t) return;
        const racao = culturas[i.t.racao], produto = culturas[i.t.produto];
        const nome = esc(i.t.nome);
        if (visita) {
            return mostrarStatus(`${spr(A.ANIMAL[a.tipo], 22)} ${nome} do vizinho.`);
        }
        if (i.estado === 'fome') {
            const tem = naCeleiro(i.t.racao);
            mostrarStatus(`${spr(A.ANIMAL[a.tipo], 22)} ${nome} com fome! Come ${i.t.racao_qtd} ${racao ? itemDe(racao, 18) + esc(racao.nome.toLowerCase()) : ''}` +
                (tem >= i.t.racao_qtd ? ' — toque para alimentar.' : ` — você tem ${tem} no celeiro.`));
        } else if (i.estado === 'pronto') {
            mostrarStatus(`${spr(A.ANIMAL[a.tipo], 22)} ${produto ? itemDe(produto, 18) + esc(produto.nome) : ''} pronto! Toque para coletar.`);
        } else {
            mostrarStatus(`${spr(A.ANIMAL[a.tipo], 22)} ${nome} produzindo ${produto ? esc(produto.nome.toLowerCase()) : ''} · pronto em ${fmtTempo(i.resta)}.`);
        }
    }

    function clicarAnimal(id) {
        if (!S || painelAtual || visita) return;
        descreverAnimal(id);
        const a = S.animais.find((x) => x.id === id);
        if (!a) return;
        const i = infoAnimal(a);
        if (i.estado === 'fome') {
            if (naCeleiro(i.t.racao) < i.t.racao_qtd) {
                const r = culturas[i.t.racao];
                return toast(`Falta ${r ? esc(r.nome.toLowerCase()) : 'ração'} no celeiro: plante e colha primeiro.`, 'erro');
            }
            cena.irAteAnimal(id);
            executarAnimal('alimentar', [id]);
        } else if (i.estado === 'pronto') {
            cena.irAteAnimal(id);
            executarAnimal('coletar', [id]);
        }
    }

    function executarAnimal(acao, ids) {
        const antes = {};
        ids.forEach((id) => { antes[id] = S.animais.find((x) => x.id === id); });
        return enfileirar([], async () => {
            const r = await rpc('fazenda_animal', { p_token: token, p_acao: acao, p_ids: ids });
            ids.forEach((id, n) => {
                const a = antes[id], t = a && tipoAnimal(a.tipo);
                if (!t) return;
                const depois = r.estado.animais.find((x) => x.id === id);
                const mudou = depois && depois.alimentado_em !== a.alimentado_em;
                if (!mudou) return;
                const html = acao === 'coletar'
                    ? `+1 ${itemDe(culturas[t.produto], 20)} +${culturas[t.produto].xp} ${ico('xp', 16)}`
                    : `−${t.racao_qtd} ${itemDe(culturas[t.racao], 20)}`;
                setTimeout(() => {
                    const pos = cena.telaDoAnimal(id);
                    const f = document.createElement('div');
                    f.className = 'flut';
                    f.innerHTML = html;
                    f.style.left = `${pos.x}px`;
                    f.style.top = `${pos.y}px`;
                    el.flut.appendChild(f);
                    setTimeout(() => f.remove(), 1300);
                }, n * 80);
            });
            aplicarEstado(r.estado);
            return r;
        });
    }

    /* ---------- Estado vindo do servidor ---------- */
    function aplicarEstado(estado) {
        const antes = S;
        if (!estado.diario) estado.diario = []; // banco ainda sem o SQL da fase 2
        if (!estado.construcoes) estado.construcoes = [];
        S = estado;
        offset = Date.parse(estado.agora) - Date.now();
        culturas = {};
        for (const k of estado.culturas) culturas[k.id] = k;
        if (!culturas[semente]) semente = 'alface';

        if (antes && estado.jogador.nivel > antes.jogador.nivel) {
            const novas = estado.culturas.filter((k) => k.nivel_min > antes.jogador.nivel && k.nivel_min <= estado.jogador.nivel);
            let msg = `${ico('xp', 20)} Nível ${estado.jogador.nivel}!`;
            if (estado.jogador.max_canteiros > antes.jogador.max_canteiros) msg += ' +2 canteiros';
            if (novas.length) msg += ` · Nova semente: ${novas.map((k) => itemDe(k) + esc(k.nome)).join(', ')}`;
            toast(msg, 'festa');
        }
        avisarDiario();
        desenharHud();
        if (constr.ativo) desenharPaleta();
        if (['loja', 'celeiro', 'missoes'].includes(painelAtual)) abrirPainel(painelAtual, true);
    }

    /* ---------- Diário: quem passou pela sua fazenda ---------- */
    const quando = (d) => Date.parse(d.em);
    const diarioNovos = () => (S ? S.diario.filter((d) => quando(d) > (Number(store.get(LS.diarioVisto)) || 0)) : []);

    function textoDiario(d) {
        const k = culturas[d.cultura];
        const item = k ? `${itemDe(k, 18)}${esc(k.nome.toLowerCase())}` : esc(d.cultura);
        return d.tipo === 'roubo'
            ? `<b>${esc(d.apelido)}</b> pegou ${d.qtd} ${item} da sua fazenda!`
            : `<b>${esc(d.apelido)}</b> cuidou do seu ${item} (${d.qtd} problema${d.qtd > 1 ? 's' : ''}).`;
    }

    function avisarDiario() {
        const novos = diarioNovos();
        el.diarioCont.textContent = novos.length;
        el.diarioCont.hidden = !novos.length;
        // Só avisa por toast o que ainda não foi avisado nesta visita à página
        const ineditos = novos.filter((d) => quando(d) > ultimoAvisoDiario);
        if (!ineditos.length) return;
        ultimoAvisoDiario = Math.max(...ineditos.map(quando));
        const d = ineditos[0];
        toast((d.tipo === 'roubo' ? ico('mao', 18) : ico('coracao', 16)) + ' ' + textoDiario(d) + (ineditos.length > 1 ? ` (+${ineditos.length - 1} no diário)` : ''));
    }

    function marcarDiarioVisto() {
        if (!S || !S.diario.length) return;
        store.set(LS.diarioVisto, String(Math.max(...S.diario.map(quando))));
        avisarDiario();
    }

    /* ---------- Feedback visual ---------- */
    // html: monte com esc() em qualquer texto vindo de jogadores ou do servidor
    function toast(html, tipo) {
        const t = document.createElement('div');
        t.className = 'toast' + (tipo === 'erro' ? ' erro-t' : tipo === 'festa' ? ' festa' : '');
        t.innerHTML = html;
        el.toasts.appendChild(t);
        while (el.toasts.children.length > 3) el.toasts.firstChild.remove();
        setTimeout(() => t.remove(), tipo === 'festa' ? 4600 : 3100);
    }

    function flutuar(p, html, atraso = 0) {
        setTimeout(() => {
            const pos = cena.telaDoCanteiro(p);
            const f = document.createElement('div');
            f.className = 'flut';
            f.innerHTML = html;
            f.style.left = `${pos.x}px`;
            f.style.top = `${pos.y}px`;
            el.flut.appendChild(f);
            setTimeout(() => f.remove(), 1300);
        }, atraso);
    }

    /* ---------- Ações ---------- */
    function enfileirar(posicoes, tarefa) {
        posicoes.forEach((p) => pendentesPos.add(p));
        pendentes++;
        clearTimeout(voltaFazendeiro);
        const execucao = fila.then(tarefa).catch(tratarErro).finally(() => {
            pendentes--;
            posicoes.forEach((p) => pendentesPos.delete(p));
            if (!pendentes) voltaFazendeiro = setTimeout(() => cena.voltarParaCasa(), 6000);
        });
        fila = execucao;
        return execucao;
    }

    function tratarErro(e) {
        if (e && e.code === 'token_invalido') {
            sair(false);
            mostrarEntrada();
            mostrarErroEntrada(e.message);
            return;
        }
        toast(esc(e.message || 'Algo deu errado.'), 'erro');
    }

    const FEEDBACK = {
        arar: () => `+1 ${ico('xp', 16)}`,
        plantar: (k) => `−${k.custo} ${ico('moeda', 16)}`,
        erva: () => `+1 ${ico('xp', 16)} +1 ${ico('moeda', 16)}`,
        praga: () => `+1 ${ico('xp', 16)} +1 ${ico('moeda', 16)}`,
        seco: () => `+1 ${ico('xp', 16)} +1 ${ico('moeda', 16)}`
    };

    function validarPlantio() {
        const k = culturas[semente];
        if (!k || k.nivel_min > S.jogador.nivel) {
            abrirPainel('loja');
            toast('Escolha uma semente na loja.');
            return null;
        }
        return k;
    }

    function clicarCanteiro(p) {
        if (!S || painelAtual) return;
        descrever(p);
        if (visita) {
            const av = acaoVisita(canteiro(p));
            if (av) { cena.irAte(p); executarVisita(av, [p]); }
            return;
        }
        const acao = acaoPara(canteiro(p));
        if (!acao) return;
        let k = null;
        if (acao === 'plantar') {
            k = validarPlantio();
            if (!k) return;
            if (S.jogador.moedas < k.custo) {
                toast(`Faltam moedas para ${esc(k.nome.toLowerCase())}. Venda a colheita no celeiro.`, 'erro');
                return;
            }
        }
        cena.irAte(p);
        executar(acao, [p], k);
    }

    function executar(acao, posicoes, k) {
        return enfileirar(posicoes, async () => {
            const r = await rpc('fazenda_acao', {
                p_token: token,
                p_acao: acao,
                p_posicoes: posicoes,
                p_cultura: acao === 'plantar' ? k.id : null
            });
            if (acao === 'colher') {
                Object.entries(r.colhido).forEach(([pos, qtd], n) => {
                    const c = canteiro(Number(pos));
                    const kc = c && culturas[c.cultura];
                    if (kc) flutuar(Number(pos), `+${qtd} ${itemDe(kc, 20)} +${kc.xp} ${ico('xp', 16)}`, n * 80);
                });
            } else if (r.feitos > 0) {
                const fb = FEEDBACK[acao](k);
                const feitos = posicoes.length === 1 ? posicoes : posicoes.filter((p) => !mesmoEstado(p, r.estado));
                feitos.forEach((p, n) => flutuar(p, fb, n * 60));
            }
            aplicarEstado(r.estado);
            if (posicoes.length > 1) resumoMassa(acao, r, k);
            else descrever(posicoes[0]);
            return r;
        });
    }

    function mesmoEstado(p, novo) {
        const a = canteiro(p), b = novo.canteiros.find((c) => c.posicao === p);
        return a && b && a.estado === b.estado && a.cultura === b.cultura && a.erva === b.erva && a.praga === b.praga && a.seco === b.seco;
    }

    function resumoMassa(acao, r, k) {
        if (!r.feitos) return;
        if (acao === 'colher') {
            const total = Object.values(r.colhido).reduce((a, b) => a + b, 0);
            toast(`${spr(35, 22)} Colheu ${total} itens de ${r.feitos} canteiro(s)!`);
        } else if (acao === 'plantar') {
            toast(`${itemDe(k)} Plantou ${r.feitos} × ${esc(k.nome.toLowerCase())}`);
        } else if (acao === 'arar') {
            toast(`${spr(86, 22)} Arou ${r.feitos} canteiro(s)`);
        }
    }

    function posicoesOnde(filtro) {
        return S.canteiros.filter((c) => filtro(c, info(c))).map((c) => c.posicao);
    }

    async function acaoEmMassa(tipo) {
        if (!S) return;
        if (tipo === 'colher') {
            // colhe os canteiros maduros e coleta os produtos dos animais
            const ps = posicoesOnde((c, i) => i.fase === 'maduro');
            const prontos = (S.animais || []).filter((a) => infoAnimal(a).estado === 'pronto').map((a) => a.id);
            if (!ps.length && !prontos.length) return toast('Nada pronto ainda.');
            if (ps.length) executar('colher', ps);
            if (prontos.length) {
                const r = await executarAnimal('coletar', prontos);
                if (r && r.coletado) toast(`Coletou ${r.coletado} produto(s) dos animais!`);
            }
        } else if (tipo === 'arar') {
            const ps = posicoesOnde((c, i) => i.fase === 'vazio' || i.fase === 'murcho');
            if (!ps.length) return toast('Nenhum canteiro precisa ser arado.');
            executar('arar', ps);
        } else if (tipo === 'plantar') {
            const ps = posicoesOnde((c, i) => i.fase === 'arado');
            if (!ps.length) return toast('Nenhum canteiro arado livre.');
            const k = validarPlantio();
            if (!k) return;
            if (S.jogador.moedas < k.custo) return toast(`Faltam moedas para ${esc(k.nome.toLowerCase())}.`, 'erro');
            executar('plantar', ps, k);
        } else if (tipo === 'cuidar') {
            let algum = false, total = 0;
            for (const prob of ['erva', 'praga', 'seco']) {
                const ps = posicoesOnde((c, i) => (i.fase === 'crescendo' || i.fase === 'maduro') && c[prob]);
                if (ps.length) {
                    algum = true;
                    const r = await executar(prob, ps);
                    if (r) total += r.feitos;
                }
            }
            // alimenta os animais com fome, até onde a ração do celeiro der
            const estoque = { ...S.celeiro };
            const famintos = (S.animais || []).filter((a) => {
                const i = infoAnimal(a);
                if (i.estado !== 'fome' || !i.t) return false;
                if ((estoque[i.t.racao] || 0) < i.t.racao_qtd) return false;
                estoque[i.t.racao] -= i.t.racao_qtd;
                return true;
            }).map((a) => a.id);
            if (famintos.length) {
                algum = true;
                const r = await executarAnimal('alimentar', famintos);
                if (r && r.feitos) toast(`Alimentou ${r.feitos} animal(is).`);
            }
            if (!algum) toast('Tudo em ordem por aqui.');
            else if (total) toast(`${spr(84, 22)} Resolveu ${total} problema(s)!`);
        }
    }

    /* ---------- Visitas aos vizinhos ---------- */
    function mostrarVisita(v) {
        if (constr.ativo) fecharConstrucao();
        visita = v;
        offset = Date.parse(v.agora) - Date.now();
        document.body.classList.add('visitando');
        el.faixaVisita.hidden = false;
        el.visitaApelido.textContent = v.apelido;
        el.visitaNivel.textContent = v.nivel;
        el.acoesVisita.hidden = false;
        el.acoesCasa.hidden = true;
        el.btnSemente.hidden = true;
    }

    function visitar(id) {
        fecharPainel();
        return enfileirar([], async () => {
            const v = await rpc('fazenda_visitar', { p_token: token, p_vizinho: id || null });
            const trocou = !visita || visita.id !== v.id;
            mostrarVisita(v);
            if (trocou) {
                const prontos = v.canteiros.filter((c) => podePegar(c, info(c))).length;
                mostrarStatus(prontos
                    ? `<b>${esc(v.apelido)}</b> tem ${prontos} canteiro(s) maduro(s). Pegue um pouquinho… ou ajude!`
                    : `Você está na fazenda de <b>${esc(v.apelido)}</b>. Ajude com ${probsHtml(['erva', 'praga', 'seco'])} para ganhar ${ico('xp', 14)}.`);
            }
        });
    }

    function voltarCasa() {
        visita = null;
        document.body.classList.remove('visitando');
        el.faixaVisita.hidden = true;
        el.acoesVisita.hidden = true;
        el.acoesCasa.hidden = false;
        el.btnSemente.hidden = false;
        mostrarStatus('De volta à sua fazenda.');
        cena.voltarParaCasa();
        recarregar();
    }

    function executarVisita(acao, posicoes) {
        const dono = visita.id;
        return enfileirar(posicoes, async () => {
            const r = await rpc('fazenda_acao_vizinho', {
                p_token: token, p_vizinho: dono, p_acao: acao, p_posicoes: posicoes
            });
            Object.entries(r.resultado).forEach(([pos, qtd], n) => {
                const c = canteiro(Number(pos));
                const k = c && culturas[c.cultura];
                flutuar(Number(pos), acao === 'pegar'
                    ? `+${qtd} ${k ? itemDe(k, 20) : ''}`
                    : `+${qtd} ${ico('xp', 16)} +${qtd} ${ico('moeda', 16)}`, n * 70);
            });
            aplicarEstado(r.estado);
            if (visita && visita.id === dono) mostrarVisita(r.vizinho);
            if (posicoes.length > 1 && r.feitos) {
                const total = Object.values(r.resultado).reduce((a, b) => a + b, 0);
                toast(acao === 'pegar'
                    ? `${ico('mao', 18)} Pegou ${total} itens de ${r.feitos} canteiro(s)!`
                    : `${ico('coracao', 16)} Resolveu ${total} problema(s) do vizinho!`);
            } else if (posicoes.length === 1) {
                descrever(posicoes[0]);
            }
            return r;
        });
    }

    function acaoVisitaEmMassa(tipo) {
        if (tipo === 'casa') return voltarCasa();
        if (tipo === 'outro') return visitar(null);
        if (!visita) return;
        const ps = visita.canteiros.filter((c) => {
            const i = info(c);
            return tipo === 'pegar' ? podePegar(c, i) : (i.fase === 'crescendo' || i.fase === 'maduro') && i.probs.length > 0;
        }).map((c) => c.posicao);
        if (!ps.length) return toast(tipo === 'pegar' ? 'Nada pra pegar aqui agora.' : 'A fazenda do vizinho está em ordem.');
        executarVisita(tipo, ps);
    }

    async function recarregar() {
        if (!token || pendentes) return;
        try {
            aplicarEstado(await rpc('fazenda_carregar', { p_token: token }));
            if (visita) mostrarVisita(await rpc('fazenda_visitar', { p_token: token, p_vizinho: visita.id }));
        } catch (e) {
            if (e.code === 'token_invalido') tratarErro(e);
            else if (e.code === 'vizinho_invalido') voltarCasa();
        }
    }

    /* ---------- Painéis ---------- */
    function abrirPainel(nome, soAtualizar, boasVindas) {
        if (!soAtualizar) ultimoFoco = document.activeElement;
        painelAtual = nome;
        const corpo = el.painelCorpo;
        if (nome === 'loja') {
            el.painelTitulo.innerHTML = `${spr(9, 32)} Loja`;
            const abas = `<div class="painel-abas" role="tablist">
                ${[['sementes', 'Sementes'], ['animais', 'Animais']].map(([id, txt]) =>
                    `<button type="button" role="tab" data-aba-loja="${id}" class="${abaLoja === id ? 'ativa' : ''}">${txt}</button>`).join('')}
            </div>`;
            if (abaLoja === 'animais') corpo.innerHTML = abas + htmlLojaAnimais();
            else corpo.innerHTML = abas + htmlLojaSementes();
        } else if (nome === 'missoes') {
            el.painelTitulo.innerHTML = `${ico('missao', 26)} Missões do dia`;
            corpo.innerHTML = htmlMissoes();
        } else if (nome === 'celeiro') {
            el.painelTitulo.innerHTML = `${spr(11, 32)} Celeiro`;
            const itens = S.culturas.filter((k) => S.celeiro[k.id] > 0);
            if (!itens.length) {
                corpo.innerHTML = `<p class="vazio-msg">${spr(76, 48)}<br>Seu celeiro está vazio.<br>Colha algo e volte aqui para vender!</p>`;
            } else {
                const total = itens.reduce((a, k) => a + S.celeiro[k.id] * k.venda, 0);
                corpo.innerHTML = '<div class="lista">' + itens.map((k) => `
                    <div class="item">
                        <span class="ico">${spr(A.cultura(k.id).item, 44)}</span>
                        <span>
                            <span class="nome">${esc(k.nome)} × ${S.celeiro[k.id]}</span>
                            <span class="det"><span>${moeda(k.venda)} cada</span><span>total ${moeda(S.celeiro[k.id] * k.venda)}</span></span>
                        </span>
                        <button type="button" class="botao pequeno verde" data-vender="${esc(k.id)}">Vender</button>
                    </div>`).join('') + `</div>
                    <div class="rodape-painel">
                        <span class="preco">Valor total: ${ico('moeda', 16)} ${total}</span>
                        <button type="button" class="botao verde" data-vender="*">Vender tudo</button>
                    </div>`;
            }
        } else if (nome === 'conta') {
            el.painelTitulo.innerHTML = boasVindas ? `${spr(83, 32)} Bem-vindo(a) à fazenda!` : `${spr(76, 32)} Sua fazenda`;
            const codigo = store.get(LS.codigo);
            corpo.innerHTML = `
                <p>Fazendeiro(a): <b>${esc(S.jogador.apelido)}</b> · Nível ${S.jogador.nivel}</p>
                <h3 class="secao-titulo">Código de recuperação</h3>
                ${codigo ? `<div class="codigo-box"><code>${esc(codigo)}</code><button type="button" class="botao pequeno creme" data-copiar>Copiar</button></div>` : '<p class="aviso">O código não está salvo neste aparelho. Se você anotou, ele continua valendo.</p>'}
                <p class="aviso">Guarde esse código: é o único jeito de abrir sua fazenda em outro aparelho ou se o navegador for limpo.</p>
                <h3 class="secao-titulo">Como jogar</h3>
                <ul class="ajuda">
                    <li>Toque num canteiro e ele faz a ação certa: <b>arar</b>, <b>plantar</b>, <b>cuidar</b> ou <b>colher</b>.</li>
                    <li>As plantas crescem em tempo real, mesmo com a página fechada.</li>
                    <li>Aparecem ${ico('erva', 14)} ervas, ${ico('praga', 14)} pragas e ${ico('seco', 12)} seca: cada problema deixado custa 1 item na colheita.</li>
                    <li>Depois de madura, a planta <b>murcha</b> se ficar tempo demais sem colher.</li>
                    <li>Toque no <b>celeiro</b> para vender a colheita, compre sementes melhores e suba de nível para ganhar canteiros.</li>
                    <li>Na loja tem <b>animais</b>: dê ração (sai do celeiro) e colete ovos e leite. </li>
                    <li>No botão <b>Construir</b> você coloca cercas, caminhos, árvores, flores e objetos onde quiser. Toque em <b>Pronto</b> para fechar.</li>
                    <li>Cumpra as <b>missões do dia</b> para ganhar moedas e XP extras.</li>
                    <li>Em <b>Vizinhos</b> você visita outras fazendas: <b>pega</b> um pouco da colheita madura ou <b>ajuda</b> com os problemas e ganha XP.</li>
                </ul>
                <div class="rodape-painel">
                    ${boasVindas
                        ? '<span></span><button type="button" class="botao verde" data-fechar>Começar a jogar</button>'
                        : `<a class="botao creme" href="indexversao2.html">Voltar ao portfólio</a>
                    <button type="button" class="botao vermelho" data-sair>Sair desta fazenda</button>`}
                </div>`;
        } else if (nome === 'vizinhos') {
            el.painelTitulo.innerHTML = `${spr(108, 32)} Vizinhos`;
            const novos = diarioNovos().length;
            corpo.innerHTML = `
                <div class="painel-abas" role="tablist">
                    <button type="button" role="tab" data-aba-viz="ranking" class="${abaVizinhos === 'ranking' ? 'ativa' : ''}">Ranking</button>
                    <button type="button" role="tab" data-aba-viz="diario" class="${abaVizinhos === 'diario' ? 'ativa' : ''}">Diário${novos ? ` (${novos})` : ''}</button>
                </div>
                <div id="vizConteudo"></div>
                <div class="rodape-painel">
                    <span class="det">Visite alguém com colheita madura</span>
                    <button type="button" class="botao verde" data-visitar="">Visitar alguém</button>
                </div>`;
            preencherVizinhos();
        }
        if (!soAtualizar) {
            el.painel.classList.add('aberto');
            el.painelFechar.focus();
        }
    }

    /* ---- conteúdo da loja e das missões ---- */
    function htmlLojaSementes() {
        return '<div class="lista">' + S.culturas.filter((k) => k.tipo !== 'produto').map((k) => {
            const travada = k.nivel_min > S.jogador.nivel;
            const lucro = k.venda * k.rendimento - k.custo;
            return `<button type="button" class="item${k.id === semente ? ' selecionada' : ''}${travada ? ' travada' : ''}" data-semente="${esc(k.id)}" ${travada ? 'aria-disabled="true"' : ''}>
                <span class="ico">${travada ? ico('cadeado', 28) : spr(A.cultura(k.id).item, 44)}</span>
                <span>
                    <span class="nome">${esc(k.nome)}</span>
                    <span class="det">
                        <span>${fmtDuracao(k.tempo_seg)}</span>
                        <span>colhe ${k.rendimento} × ${moeda(k.venda)}</span>
                        <span>+${k.xp} ${ico('xp', 13)}</span>
                        <span>lucro ${moeda(lucro)}</span>
                    </span>
                </span>
                <span class="preco">${travada ? `Nível ${k.nivel_min}` : `${ico('moeda', 16)} ${k.custo}`}</span>
            </button>`;
        }).join('') + '</div><p class="aviso">Escolha uma semente e depois toque nos canteiros arados (ou em “Plantar tudo”).</p>';
    }

    function htmlLojaAnimais() {
        const tipos = S.animais_tipos || [];
        if (!tipos.length) return '<p class="vazio-msg">Os animais chegam em breve.</p>';
        return '<div class="lista">' + tipos.map((t) => {
            const tem = S.animais.filter((a) => a.tipo === t.id).length;
            const travado = t.nivel_min > S.jogador.nivel;
            const cheio = tem >= t.maximo;
            const racao = culturas[t.racao], produto = culturas[t.produto];
            return `<div class="item${travado ? ' travada' : ''}">
                <span class="ico">${travado ? ico('cadeado', 28) : spr(A.ANIMAL[t.id], 44)}</span>
                <span>
                    <span class="nome">${esc(t.nome)} <small class="qtd">${tem}/${t.maximo}</small></span>
                    <span class="det">
                        <span>come ${t.racao_qtd} ${racao ? itemDe(racao, 16) : ''}</span>
                        <span>dá ${produto ? itemDe(produto, 16) + esc(produto.nome.toLowerCase()) : ''} a cada ${fmtDuracao(t.tempo_seg)}</span>
                        <span>vende ${moeda(produto ? produto.venda : 0)}</span>
                    </span>
                </span>
                ${travado ? `<span class="preco">Nível ${t.nivel_min}</span>`
                    : cheio ? '<span class="preco">Completo</span>'
                    : `<button type="button" class="botao pequeno verde" data-comprar="animal:${esc(t.id)}">${ico('moeda', 14)} ${t.custo}</button>`}
            </div>`;
        }).join('') + '</div><p class="aviso">Toque no animal com fome para dar a ração (sai do seu celeiro) e volte para coletar o produto.</p>';
    }

    const TEXTO_MISSAO = {
        colher: (n) => `Colha ${n} itens`,
        plantar: (n) => `Plante ${n} sementes`,
        cuidar: (n) => `Resolva ${n} problemas na sua fazenda`,
        vender: (n) => `Ganhe ${n} moedas vendendo`,
        animal: (n) => `Colete ${n} produtos dos animais`,
        ajudar: (n) => `Ajude vizinhos com ${n} problemas`
    };
    const ICONE_MISSAO = { colher: spr(35, 32), plantar: spr(81, 32), cuidar: spr(84, 32), vender: spr(11, 32), animal: spr(125, 32), ajudar: ico('coracao', 26) };

    function htmlMissoes() {
        const ms = S.missoes || [];
        if (!ms.length) return '<p class="vazio-msg">As missões aparecem quando o banco estiver atualizado.</p>';
        return '<div class="lista">' + ms.map((m) => {
            const pronta = m.progresso >= m.alvo;
            return `<div class="missao${m.resgatada ? ' feita' : pronta ? ' pronta' : ''}">
                <span class="ico">${ICONE_MISSAO[m.tipo] || ''}</span>
                <span>
                    <span class="nome">${TEXTO_MISSAO[m.tipo] ? TEXTO_MISSAO[m.tipo](m.alvo) : esc(m.tipo)}</span>
                    <span class="barra-prog"><i style="width:${Math.min(100, (m.progresso / m.alvo) * 100)}%"></i></span>
                    <span class="det"><span>${m.progresso}/${m.alvo}</span><span>prêmio ${moeda(m.moedas)} +${m.xp} ${ico('xp', 13)}</span></span>
                </span>
                ${m.resgatada ? `<span class="preco">${ico('check', 18)} Feita</span>`
                    : pronta ? `<button type="button" class="botao pequeno verde" data-resgatar="${m.slot}">Resgatar</button>`
                    : '<span></span>'}
            </div>`;
        }).join('') + '</div><p class="aviso">Novas missões todo dia à meia-noite (horário de Brasília).</p>';
    }

    const tempoAtras = (iso) => {
        const s = Math.max(0, (agora() - Date.parse(iso)) / 1000);
        if (s < 60) return 'agora há pouco';
        if (s < 3600) return `há ${Math.floor(s / 60)} min`;
        if (s < 86400) return `há ${Math.floor(s / 3600)} h`;
        return `há ${Math.floor(s / 86400)} dia(s)`;
    };

    async function preencherVizinhos() {
        const alvo = $('vizConteudo');
        if (!alvo) return;
        if (abaVizinhos === 'diario') {
            const vistoAntes = Number(store.get(LS.diarioVisto)) || 0;
            alvo.innerHTML = S.diario.length
                ? '<div class="lista">' + S.diario.map((d) => `
                    <div class="diario-item${quando(d) > vistoAntes ? ' novo' : ''}">
                        <span>${d.tipo === 'roubo' ? ico('mao', 22) : ico('coracao', 20)}</span>
                        <span>${textoDiario(d)}<small>${tempoAtras(d.em)}</small></span>
                        ${S.jogador.id !== d.id ? `<button type="button" class="botao pequeno creme" data-visitar="${esc(d.id)}">Visitar</button>` : '<span></span>'}
                    </div>`).join('') + '</div>'
                : '<p class="vazio-msg">Ninguém passou pela sua fazenda ainda.<br>Quando um vizinho pegar ou ajudar, aparece aqui.</p>';
            marcarDiarioVisto();
            return;
        }
        alvo.innerHTML = '<p class="vazio-msg">Carregando ranking…</p>';
        try {
            const r = await rpc('fazenda_ranking', { p_token: token });
            if (painelAtual !== 'vizinhos' || abaVizinhos !== 'ranking') return;
            alvo.innerHTML = `<p class="det" style="margin:0 0 12px">Você está em <b>${r.minha_posicao}º</b> de ${r.total} fazendas.</p>
                <div class="lista">` + r.ranking.map((j, n) => `
                    <div class="rank${j.eu ? ' eu' : ''}">
                        <span class="pos">${n + 1}º</span>
                        <span style="min-width:0">
                            <span class="nome">${esc(j.apelido)}${j.eu ? ' (você)' : ''}</span>
                            <span class="det"><span>Nível ${j.nivel}</span><span>${j.xp} ${ico('xp', 13)}</span><span>${moeda(j.patrimonio)}</span></span>
                        </span>
                        ${j.eu ? '<span></span>' : `<button type="button" class="botao pequeno creme" data-visitar="${esc(j.id)}">Visitar</button>`}
                    </div>`).join('') + '</div>';
        } catch (e) {
            alvo.innerHTML = `<p class="vazio-msg">${esc(e.message)}</p>`;
        }
    }

    function fecharPainel() {
        el.painel.classList.remove('aberto');
        painelAtual = null;
        if (ultimoFoco && ultimoFoco.focus) ultimoFoco.focus();
    }

    el.painelCorpo.addEventListener('click', async (e) => {
        const sem = e.target.closest('[data-semente]');
        if (sem) {
            const k = culturas[sem.dataset.semente];
            if (k.nivel_min > S.jogador.nivel) return toast(`${ico('cadeado', 12)} ${esc(k.nome)} libera no nível ${k.nivel_min}.`);
            semente = k.id;
            store.set(LS.semente, semente);
            desenharHud();
            fecharPainel();
            toast(`Semente escolhida: ${itemDe(k)} ${esc(k.nome)}`);
            return;
        }
        const vend = e.target.closest('[data-vender]');
        if (vend) {
            vend.disabled = true;
            const item = vend.dataset.vender === '*' ? null : vend.dataset.vender;
            enfileirar([], async () => {
                const r = await rpc('fazenda_vender', { p_token: token, p_item: item, p_quantidade: null });
                if (r.ganho > 0) toast(`Vendeu por ${ico('moeda', 16)} ${r.ganho}!`);
                aplicarEstado(r.estado);
            }).finally(() => { vend.disabled = false; });
            return;
        }
        const abaL = e.target.closest('[data-aba-loja]');
        if (abaL) {
            abaLoja = abaL.dataset.abaLoja;
            abrirPainel('loja', true);
            return;
        }
        const comp = e.target.closest('[data-comprar]');
        if (comp) {
            const [categoria, tipo] = comp.dataset.comprar.split(':');
            comp.disabled = true;
            enfileirar([], async () => {
                const r = await rpc('fazenda_comprar', { p_token: token, p_categoria: categoria, p_tipo: tipo });
                aplicarEstado(r.estado);
                const nome = (tipoAnimal(tipo) || {}).nome;
                toast(`${esc(nome || 'Item')} chegou na fazenda!`);
                if (painelAtual === 'loja') abrirPainel('loja', true);
            }).finally(() => { comp.disabled = false; });
            return;
        }
        const resg = e.target.closest('[data-resgatar]');
        if (resg) {
            resg.disabled = true;
            enfileirar([], async () => {
                const r = await rpc('fazenda_resgatar_missao', { p_token: token, p_slot: Number(resg.dataset.resgatar) });
                aplicarEstado(r.estado);
                toast(`Missão cumprida! +${moeda(r.moedas)} +${r.xp} ${ico('xp', 16)}`, 'festa');
                if (painelAtual === 'missoes') abrirPainel('missoes', true);
            });
            return;
        }
        const aba = e.target.closest('[data-aba-viz]');
        if (aba) {
            abaVizinhos = aba.dataset.abaViz;
            abrirPainel('vizinhos', true);
            return;
        }
        const vis = e.target.closest('[data-visitar]');
        if (vis) {
            visitar(vis.dataset.visitar || null);
            return;
        }
        if (e.target.closest('[data-fechar]')) {
            fecharPainel();
            return;
        }
        if (e.target.closest('[data-copiar]')) {
            try {
                await navigator.clipboard.writeText(store.get(LS.codigo));
                toast('Código copiado!');
            } catch {
                toast('Não deu para copiar. Anote o código.', 'erro');
            }
            return;
        }
        if (e.target.closest('[data-sair]')) {
            const codigo = store.get(LS.codigo);
            const msg = codigo
                ? `Sair desta fazenda? Para voltar você vai precisar do código ${codigo}.`
                : 'Sair desta fazenda? Sem o código de recuperação você NÃO consegue voltar.';
            if (confirm(msg)) {
                fecharPainel();
                sair(true);
                mostrarEntrada();
            }
        }
    });

    el.painelFechar.addEventListener('click', fecharPainel);
    el.painel.addEventListener('click', (e) => { if (e.target === el.painel) fecharPainel(); });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && painelAtual) fecharPainel(); });
    document.querySelectorAll('[data-painel]').forEach((b) => b.addEventListener('click', () => S && abrirPainel(b.dataset.painel)));
    el.btnSemente.addEventListener('click', () => S && abrirPainel('loja'));
    document.querySelectorAll('[data-massa]').forEach((b) => b.addEventListener('click', () => acaoEmMassa(b.dataset.massa)));
    document.querySelectorAll('[data-visita]').forEach((b) => b.addEventListener('click', () => acaoVisitaEmMassa(b.dataset.visita)));
    el.btnVoltarCasa.addEventListener('click', voltarCasa);

    el.btnConstruir.addEventListener('click', abrirConstrucao);
    el.barraConstr.addEventListener('click', (e) => {
        const aba = e.target.closest('[data-constr-aba]');
        if (aba) { constr.aba = aba.dataset.constrAba; desenharPaleta(); return; }
        const item = e.target.closest('[data-item]');
        if (item) {
            const it = tipoItem(item.dataset.item);
            if (!it) return;
            if (it.nivel_min > S.jogador.nivel) return toast(`${esc(it.nome)} libera no nível ${it.nivel_min}.`);
            constr.modo = 'colocar';
            constr.tipo = it.id;
            constr.movendo = null;
            desenharPaleta();
            atualizarModo();
            mostrarStatus(`${A.htmlItem(it.id, 22)} ${esc(it.nome)} (${moeda(it.custo)}): toque nos quadrados livres.`);
            return;
        }
        const ferr = e.target.closest('[data-ferramenta]');
        if (ferr) {
            if (ferr.dataset.ferramenta === 'pronto') return fecharConstrucao();
            constr.modo = ferr.dataset.ferramenta;
            constr.movendo = null;
            desenharPaleta();
            atualizarModo();
            mostrarStatus(constr.modo === 'mover' ? 'Mover: toque num item e depois no lugar novo.' : 'Guardar: toque num item para tirar (volta metade do valor).');
        }
    });

    /* ---------- Entrada / sessão ---------- */
    function mostrarEntrada() {
        el.hud.hidden = el.barra.hidden = el.status.hidden = true;
        el.entrada.classList.add('aberto');
        el.entradaCarregando.hidden = true;
        el.entradaAbas.hidden = false;
        el.inApelido.focus();
        ajustarMargens();
    }

    function mostrarFazenda() {
        el.entrada.classList.remove('aberto');
        el.hud.hidden = el.barra.hidden = el.status.hidden = false;
        const est = { primavera: 'Primavera', verao: 'Verão', outono: 'Outono', inverno: 'Inverno' }[A.estacao()];
        mostrarStatus(`${est} na fazenda! Toque num canteiro para cuidar dele. Arraste para ver o terreno.`);
        ajustarMargens();
    }

    function mostrarErroEntrada(msg) {
        el.entradaErro.textContent = msg || '';
    }

    function sair(apagarCodigo) {
        if (constr.ativo) fecharConstrucao();
        token = null;
        S = null;
        visita = null;
        document.body.classList.remove('visitando');
        el.faixaVisita.hidden = el.acoesVisita.hidden = true;
        el.acoesCasa.hidden = el.btnSemente.hidden = false;
        store.del(LS.token);
        if (apagarCodigo) store.del(LS.codigo);
    }

    document.querySelectorAll('.abas-botoes button').forEach((b) => b.addEventListener('click', () => {
        document.querySelectorAll('.abas-botoes button').forEach((x) => {
            x.classList.toggle('ativa', x === b);
            x.setAttribute('aria-selected', x === b);
        });
        document.querySelectorAll('.aba').forEach((a) => a.classList.toggle('ativa', a.dataset.aba === b.dataset.aba));
        mostrarErroEntrada('');
        (b.dataset.aba === 'nova' ? el.inApelido : el.inCodigo).focus();
    }));

    async function enviarEntrada(form, fn, args, aoEntrar) {
        const btn = form.querySelector('button');
        btn.disabled = true;
        mostrarErroEntrada('');
        try {
            const r = await rpc(fn, args);
            token = r.token;
            store.set(LS.token, token);
            aplicarEstado(r.estado);
            mostrarFazenda();
            aoEntrar(r);
        } catch (e) {
            mostrarErroEntrada(e.message);
        } finally {
            btn.disabled = false;
        }
    }

    el.formNova.addEventListener('submit', (e) => {
        e.preventDefault();
        const apelido = el.inApelido.value.trim();
        if (apelido.length < 2) return mostrarErroEntrada(ERROS.apelido_invalido);
        enviarEntrada(el.formNova, 'fazenda_criar', { p_apelido: apelido }, (r) => {
            store.set(LS.codigo, r.codigo);
            // Mostra o código logo de cara para a pessoa anotar
            abrirPainel('conta', false, true);
        });
    });

    el.formCodigo.addEventListener('submit', (e) => {
        e.preventDefault();
        const codigo = el.inCodigo.value.trim().toUpperCase().replace(/\s+/g, '');
        if (!codigo) return;
        enviarEntrada(el.formCodigo, 'fazenda_recuperar', { p_codigo: codigo }, () => {
            store.set(LS.codigo, codigo);
            toast('Bem-vindo(a) de volta!');
        });
    });

    /* ---------- Loop ---------- */
    let ultimoPoll = Date.now();
    setInterval(() => {
        if (!S) return;
        if (document.visibilityState === 'visible' && Date.now() - ultimoPoll > POLL_MS) {
            ultimoPoll = Date.now();
            recarregar();
        }
    }, 1000);

    document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible' && S) {
            ultimoPoll = Date.now();
            recarregar();
        }
    });

    /* ---------- Início ---------- */
    (async function iniciar() {
        try {
            await A.carregar();
        } catch (e) {
            el.entradaCarregando.textContent = e.message;
            return;
        }
        cena.iniciar();
        ajustarMargens();
        if (!token) return mostrarEntrada();
        try {
            aplicarEstado(await rpc('fazenda_carregar', { p_token: token }));
            mostrarFazenda();
        } catch (e) {
            if (e.code === 'token_invalido') sair(false);
            mostrarEntrada();
            mostrarErroEntrada(e.message);
        }
    })();
})();
