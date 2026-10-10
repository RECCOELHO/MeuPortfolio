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
    // Anúncio premiado (AdSense, anúncios para jogos H5). ligado: false até o Google aprovar o
    // site e liberar os anúncios para jogos; teste: true mostra só anúncios de teste do Google
    // (troque para false depois de conferir que funciona).
    const ANUNCIO = { cliente: 'ca-pub-9193438749452073', ligado: false, teste: true };

    // Em localhost dá pra apontar para um backend de teste: fazenda.html?api=http://localhost:8787
    let API = SUPABASE_URL;
    try {
        const alt = new URLSearchParams(location.search).get('api');
        if (alt && /^(localhost|127\.0\.0\.1)$/.test(location.hostname)) API = alt;
    } catch { /* ignora */ }

    const POLL_MS = 30000;

    /* ---------- Armazenamento local (protegido) ---------- */
    const LS = {
        token: 'fazenda_token', codigo: 'fazenda_codigo', semente: 'fazenda_semente',
        diarioVisto: 'fazenda_diario_visto', mudo: 'fazenda_mudo', tutorial: 'fazenda_tutorial', avisos: 'fazenda_avisos', convite: 'fazenda_convite'
    };
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
        terreno_max: 'Você já comprou todos os terrenos.',
        nivel_maximo: 'Esse ajudante já está no nível máximo.',
        sem_ingredientes: 'Faltam ingredientes no celeiro (a ração reservada não entra na receita).',
        estoque_cheio: 'O estoque dessa oficina está cheio (10 receitas).',
        sem_visita: 'A visita já foi embora. Outra chega daqui a pouco.',
        avatar_invalido: 'Não deu para salvar esse avatar.',
        falta_pedido: 'Ainda não tem o bastante no celeiro para esse pedido.',
        sem_canteiros_crescendo: 'Não tem canteiro crescendo para adubar: plante primeiro.',
        estoque_vazio: 'Não tem nada no estoque para tirar.',
        fora_de_estacao: 'Essa semente é de outra estação. Espere a época dela (ou plante perto de uma estufa elétrica).',
        sem_energia: 'Sem energia nas baterias. Construa geradores (painel solar, turbina...) e espere carregar.',
        sem_milho: 'O gerador a biomassa queima milho: colha milho e tente de novo.',
        anuncio_cedo: 'Calma! Espere uns segundos entre um anúncio e outro.',
        sem_lago: 'Compre o Vale do sudeste (aba Terrenos da loja) para liberar o lago.',
        cesto_vazio: 'O cesto ainda está vazio: o Bira tira um peixe a cada 30 minutos.',
        limite_canteiros: 'Você já usou todos os seus canteiros. Suba de nível ou compre terrenos para ter mais.',
        limite_maquina: 'Você já tem essa máquina (uma basta para a fazenda toda).',
        limite_terreno: 'Seu pomar está cheio: compre outro terreno para plantar mais (2 árvores frutíferas por terreno).',
        alarme: 'O alarme disparou! Esse canteiro está protegido.',
        item_invalido: 'Item inválido.',
        lugar_reservado: 'Esse lugar é reservado (celeiro, casa, pasto, galinheiro) ou fica na mata fora do seu terreno.',
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
        apelido: $('hudApelido'), nivel: $('hudNivel'), xpBar: $('hudXpBar'), xp: $('hudXp'), premio: $('hudPremio'),
        moedas: $('hudMoedas'), celeiroCont: $('hudCeleiro'),
        semIcone: $('semIcone'), semNome: $('semNome'), btnSemente: $('btnSemente'),
        toasts: $('toasts'), flut: $('flutuantes'),
        entrada: $('telaEntrada'), entradaCarregando: $('entradaCarregando'), entradaAbas: $('entradaAbas'), conviteFaixa: $('conviteFaixa'),
        entradaErro: $('entradaErro'), formNova: $('formNova'), formCodigo: $('formCodigo'),
        inApelido: $('inApelido'), inCodigo: $('inCodigo'),
        painel: $('painel'), painelTitulo: $('painelTitulo'), painelCorpo: $('painelCorpo'), painelFechar: $('painelFechar'),
        faixaVisita: $('faixaVisita'), visitaApelido: $('visitaApelido'), visitaNivel: $('visitaNivel'),
        btnVoltarCasa: $('btnVoltarCasa'), acoesVisita: $('acoesVisita'), acoesCasa: $('acoesCasa'),
        diarioCont: $('hudDiario'), missoesCont: $('hudMissoes'),
        barraConstr: $('barraConstr'), constrAbas: $('constrAbas'), constrItens: $('constrItens'),
        constrFerramentas: $('constrFerramentas'), btnConstruir: $('btnConstruir'), construirCont: $('hudConstruir'),
        hudPerfil: $('hudPerfil'), btnMenu: $('btnMenu'), menuCont: $('hudMenu'), celeiroContDock: $('hudCeleiroDock'),
        acoesGrupo: $('acoesGrupo'), btnAcoes: $('btnAcoes'), clima: $('hudClima'), energia: $('hudEnergia'), anuncio: $('btnAnuncio')
    };

    /* ---------- Ícones (pixel art) ---------- */
    const ico = (nome, px) => A.htmlIcone(nome, px);
    const spr = (i, px, pacote) => A.htmlTile(i, px, pacote);
    const moeda = (n) => `${ico('moeda', 14)}${n}`;
    const itemDe = (k, px = 22) => spr(A.cultura(k.id).item, px);

    document.querySelectorAll('[data-spr]').forEach((s) => { s.outerHTML = spr(Number(s.dataset.spr), Number(s.dataset.px) || 32, s.dataset.pack || 'farm'); });
    document.querySelectorAll('[data-ico]').forEach((s) => { s.outerHTML = ico(s.dataset.ico, Number(s.dataset.px) || 18); });

    /* ---------- Sons 8-bit (sintetizados na hora, sem arquivos) ---------- */
    const som = (() => {
        let ctx = null;
        let mudo = store.get(LS.mudo) === '1';
        let pausado = false;   // durante o anúncio
        function audio() {
            if (!ctx) {
                const C = window.AudioContext || window.webkitAudioContext;
                if (!C) return null;
                ctx = new C();
            }
            if (ctx.state === 'suspended') ctx.resume();
            return ctx;
        }
        function nota(freq, ini, dur, tipo = 'square', vol = 0.05) {
            const c = audio();
            if (!c) return;
            const o = c.createOscillator(), g = c.createGain(), t = c.currentTime + ini;
            o.type = tipo;
            o.frequency.setValueAtTime(freq, t);
            g.gain.setValueAtTime(vol, t);
            g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
            o.connect(g).connect(c.destination);
            o.start(t);
            o.stop(t + dur + 0.02);
        }
        const SONS = {
            arar: () => { nota(180, 0, 0.08, 'triangle', 0.09); nota(130, 0.06, 0.09, 'triangle', 0.07); },
            plantar: () => { nota(523, 0, 0.07); nota(784, 0.06, 0.1); },
            colher: () => { nota(523, 0, 0.06); nota(659, 0.06, 0.06); nota(784, 0.12, 0.12); },
            cuidar: () => { nota(880, 0, 0.06, 'triangle', 0.07); nota(1175, 0.05, 0.08, 'triangle', 0.06); },
            moeda: () => { nota(988, 0, 0.06); nota(1319, 0.06, 0.16); },
            construir: () => { nota(220, 0, 0.05, 'square', 0.05); nota(330, 0.05, 0.07, 'square', 0.05); },
            erro: () => { nota(170, 0, 0.12, 'sawtooth', 0.035); nota(120, 0.1, 0.16, 'sawtooth', 0.035); },
            festa: () => { [523, 659, 784, 1047].forEach((f, n) => nota(f, n * 0.09, 0.14)); }
        };
        return {
            tocar(nome) { if (!mudo && !pausado && SONS[nome]) { try { SONS[nome](); } catch { /* sem áudio */ } } },
            pausar(p) { pausado = p; },
            alternar() { mudo = !mudo; store.set(LS.mudo, mudo ? '1' : '0'); return mudo; },
            get mudo() { return mudo; }
        };
    })();
    const SOM_DA_ACAO = { arar: 'arar', plantar: 'plantar', colher: 'colher', erva: 'cuidar', praga: 'cuidar', seco: 'cuidar' };

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
        if (seg < 86400) {
            const h = Math.floor(seg / 3600), m = Math.round((seg % 3600) / 60);
            return m ? `${h} h ${m} min` : `${h} h`;
        }
        return `${Math.round(seg / 86400)} dia`;
    }

    /* ---------- Terrenos: áreas da mata compradas para a fazenda crescer ---------- */
    const zonasDaTela = () => (visita ? visita.zonas : S && S.jogador.zonas) || 0;
    const zonasVenda = () => (S && S.zonas_venda) || [];
    // próximo terreno à venda (só na sua fazenda; null quando acabou ou o banco ainda não tem o SQL)
    const proximaZona = () => (S && !visita ? zonasVenda().find((z) => z.n === (S.jogador.zonas || 0) + 1) || null : null);
    function atualizarTerreno() {
        const z = proximaZona();
        cena.definirTerreno({ zonas: zonasDaTela(), venda: z ? z.n : null });
    }
    /* ---------- Estação e clima (vêm do servidor: o mesmo dia para todo mundo) ---------- */
    const NOME_ESTACAO = { primavera: 'primavera', verao: 'verão', outono: 'outono', inverno: 'inverno' };
    // o que cada clima faz (vale no servidor: fazenda_clima_em, tick e colheita)
    const CLIMA = {
        sol: { nome: 'Sol', efeito: 'a colheita rende +1 item.' },
        nublado: { nome: 'Nublado', efeito: 'nenhum problema novo aparece nos canteiros.' },
        // no inverno a chuva cai como neve (mesmo efeito)
        chuva: {
            get nome() { return S && S.estacao === 'inverno' ? 'Neve' : 'Chuva'; },
            get efeito() { return S && S.estacao === 'inverno' ? 'a neve rega tudo, nenhum canteiro seca.' : 'rega tudo, nenhum canteiro seca.'; }
        },
        calor: { nome: 'Onda de calor', efeito: 'a terra seca mais rápido, fique de olho nos canteiros.' },
        vento: { nome: 'Ventania', efeito: 'espalha pragas pelos canteiros (e a turbina gira forte).' }
    };
    const ORDEM_ESTACOES = ['primavera', 'verao', 'outono', 'inverno'];
    const naEstacao = (e) => (e === 'primavera' ? 'na ' : 'no ') + NOME_ESTACAO[e];   // "na primavera", "no verão"
    const hora = (iso) => new Date(iso).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
    const climaAgora = () => S && S.clima && (S.clima.agora || S.clima.hoje);
    // quanto falta para a estação e começar (0 = já é ela); 42 h cada, sempre na mesma ordem
    function faltaParaEstacao(e) {
        if (!S || !S.estacao_fim || e === S.estacao) return 0;
        const passos = (ORDEM_ESTACOES.indexOf(e) - ORDEM_ESTACOES.indexOf(S.estacao) + 4) % 4;
        return Date.parse(S.estacao_fim) - agora() + (passos - 1) * 42 * 3600e3;
    }
    const iconeClima = (c) => (c === 'nublado' ? 'nuvem' : CLIMA[c] ? c : 'sol');
    const daEstacao = (k) => !k.estacao || !S || k.estacao === S.estacao;
    function desenharClima() {
        if (!el.clima) return;
        if (S && S.estacao) cena.definirEstacao(S.estacao);
        const c = climaAgora();
        el.clima.hidden = !CLIMA[c];
        if (!CLIMA[c]) return;
        el.clima.innerHTML = ico(iconeClima(c), 22) + `<span>${CLIMA[c].nome}</span>`;
        const prox = CLIMA[S.clima.proximo || S.clima.amanha];
        el.clima.title = `${CLIMA[c].nome}${S.clima.ate ? ' até ' + hora(S.clima.ate) : ''}: ${CLIMA[c].efeito}${prox ? ' Depois: ' + prox.nome.toLowerCase() + '.' : ''}`;
        cena.definirClima(visita ? null : c);
    }
    function descreverClima() {
        const c = climaAgora();
        if (!CLIMA[c]) return;
        const prox = S.clima.proximo || S.clima.amanha;
        const fimEst = S.estacao_fim ? Date.parse(S.estacao_fim) - agora() : 0;
        mostrarStatus(`${ico(iconeClima(c), 18)} <b>${CLIMA[c].nome}</b>${S.clima.ate ? ' até ' + hora(S.clima.ate) : ''}: ${CLIMA[c].efeito}` +
            (CLIMA[prox] ? ` Depois: ${ico(iconeClima(prox), 16)} ${CLIMA[prox].nome.toLowerCase()}.` : '') +
            (S.estacao ? ` É ${NOME_ESTACAO[S.estacao]}${fimEst > 0 && S.estacao_proxima ? `, vira ${NOME_ESTACAO[S.estacao_proxima]} em ${fmtTempo(fimEst)}` : ''}.` : ''));
    }

    /* ---------- Energia (nível 16+) ----------
       Geradores enchem as baterias; máquinas elétricas gastam ao trabalhar. O servidor
       manda a carga e quanto entra por hora; aqui só se adianta o que entrou desde então. */
    let energiaEm = 0;
    const eletrico = (c) => (tipoItem(c.tipo) || {}).categoria === 'energia';
    const temEletrico = () => !visita && !!S && !!S.energia && (S.construcoes || []).some(eletrico);
    function cargaAgora() {
        const en = S && S.energia;
        if (!en) return 0;
        return Math.min(en.capacidade, Number(en.carga) + Number(en.por_hora) * Math.max(0, agora() - energiaEm) / 3600000);
    }
    function desenharEnergia() {
        if (!el.energia) return;
        const mostra = temEletrico();
        el.energia.hidden = !mostra;
        if (!mostra) return;
        const c = Math.floor(cargaAgora()), cap = S.energia.capacidade;
        cena.definirEnergia(cap ? c / cap : 0);
        el.energia.innerHTML = `${ico('raio', 16)}<b>${c}</b><small>/${cap}</small>`;
        el.energia.classList.toggle('vazia', c < 5);
        el.energia.title = `Energia: ${c} de ${cap} ⚡`;
    }
    function descreverEnergia() {
        if (!temEletrico()) return;
        if (!painelAtual) abrirPainel('energia');
        const ph = Math.round(Number(S.energia.por_hora));
        const temSol = (S.construcoes || []).some((c) => c.tipo === 'painel_solar');
        const h = new Date(agora()).getHours();
        mostrarStatus(`${ico('raio', 18)} <b>Energia</b>: ${Math.floor(cargaAgora())} de ${S.energia.capacidade} ⚡. ` +
            (ph > 0 ? `Entrando ${ph} ⚡/h agora.` : `Nada entrando agora${temSol && (h < 6 || h >= 18) ? ' (o painel solar só gera de dia)' : ''}.`) +
            ' Baterias guardam mais; as máquinas elétricas gastam ao trabalhar.');
    }
    // Energia e máquinas: o que você tem, quanto gera e gasta, e o que vem nos próximos níveis
    function htmlEnergia() {
        const itens = (S.itens || []).filter((i) => i.categoria === 'energia').sort((a, b) => a.nivel_min - b.nivel_min);
        const tenho = (id) => (S.construcoes || []).filter((c) => c.tipo === id).length;
        const gera = new Set(['solar', 'eolica', 'biomassa', 'reator']), guarda = new Set(['bateria']);
        const linha = (i) => {
            const n = tenho(i.id), trava = i.nivel_min > S.jogador.nivel;
            return `<div class="item${trava ? ' travado' : ''}">
                <span class="ico">${trava ? ico('cadeado', 26) : A.htmlItem(i.id, 40)}</span>
                <span><span class="nome">${esc(i.nome)}${n ? ` <small>(você tem ${n})</small>` : ''}</span>
                    <span class="det"><span>${esc(i.descricao || '')}</span></span>
                    <span class="det"><span>Nível ${i.nivel_min} · ${moeda(i.custo)}${i.limite ? ` · até ${i.limite}` : ''}</span></span></span>
            </div>`;
        };
        const grupo = (titulo, lista) => lista.length ? `<h3 class="secao-titulo">${titulo}</h3><div class="lista">${lista.map(linha).join('')}</div>` : '';
        const en = S.energia || {}, carga = Math.floor(cargaAgora()), cap = en.capacidade || 50;
        return `
            ${temEletrico() ? `<p>${ico('raio', 16)} Agora: <b>${carga}</b> de ${cap} ⚡ · entrando <b>${Math.round(Number(en.por_hora) || 0)}</b> ⚡ por hora.</p>
                <span class="estoque-barra"><i style="width:${Math.round(carga / cap * 100)}%"></i></span>` : ''}
            <p class="aviso">Do nível 16 em diante a fazenda vira indústria: <b>geradores</b> enchem as <b>baterias</b>, e as <b>máquinas elétricas</b> gastam essa energia para trabalhar sozinhas por você. Sem energia elas só param; o resto da fazenda continua igual.</p>
            ${grupo('Geram energia', itens.filter((i) => gera.has(i.efeito)))}
            ${grupo('Guardam energia', itens.filter((i) => guarda.has(i.efeito)))}
            ${grupo('Trabalham por você (gastam energia)', itens.filter((i) => !gera.has(i.efeito) && !guarda.has(i.efeito)))}
            <div class="rodape-painel"><span></span><button type="button" class="botao verde" data-fechar>Entendi</button></div>`;
    }

    function alternarGerador(c) {
        const ligar = !c.iniciado_em;
        if (ligar && naCeleiro('milho') - reservaDe('milho') < 1) return toast(ERROS.sem_milho, 'erro');
        c.iniciado_em = ligar ? new Date(agora()).toISOString() : null;   // a fumaça aparece na hora
        som.tocar('construir');
        enfileirar([], async () => {
            const r = await rpc('fazenda_gerador', { p_token: token, p_x: c.x, p_y: c.y });
            aplicarEstado(r.estado);
            toast(r.ligado ? `${A.htmlItem(c.tipo, 20)} Gerador ligado: 1 milho a cada 30 min vira 25 ⚡.` : `${A.htmlItem(c.tipo, 20)} Gerador desligado.`);
            descreverConstrucao(c.x, c.y);
        });
    }
    // estufa elétrica: semente de outra estação só cresce no alcance dela
    const temEstufa = () => !!S && (S.construcoes || []).some((m) => (tipoItem(m.tipo) || {}).efeito === 'estufa');
    const naEstufa = (c) => !!c && (S.construcoes || []).some((m) => {
        const it = tipoItem(m.tipo);
        return it && it.efeito === 'estufa' && Math.abs(m.x - c.x) <= it.raio && Math.abs(m.y - c.y) <= it.raio;
    });
    const podeEscolher = (k) => daEstacao(k) || temEstufa();

    /* ---------- Convites: link ?convite=CODIGO; quem entra e quem chamou ganham moedas ----------
       O código chega pelo link e fica guardado até a pessoa criar a fazenda (o link some da
       barra de endereço). Os valores do prêmio vêm do servidor (estado.convites.premio). */
    let conviteDoLink = false;
    try {
        const url = new URL(location.href);
        const cod = (url.searchParams.get('convite') || '').trim().toUpperCase();
        if (/^[A-Z0-9]{6}$/.test(cod)) { store.set(LS.convite, cod); conviteDoLink = true; }
        if (url.searchParams.has('convite')) {
            url.searchParams.delete('convite');
            history.replaceState(null, '', url.pathname + url.search + url.hash);
        }
    } catch { /* ignora */ }
    const linkConvite = () => (S && S.convites && S.convites.codigo
        ? `${location.origin}${location.pathname}?convite=${S.convites.codigo}` : '');
    const premioConvite = () => (S && S.convites && S.convites.premio) || { amigo: 200, dono: 300 };
    const textoConvite = () => `Vem jogar a Fazendinha Secreta comigo! 🌻 Entrando pelo meu link você ganha ${premioConvite().amigo} moedas de presente: ${linkConvite()}`;
    async function compartilharConvite() {
        const link = linkConvite();
        if (!link) return;
        if (navigator.share) {
            try {
                await navigator.share({ title: 'Fazendinha Secreta', text: textoConvite().replace(link, '').trim(), url: link });
                return;
            } catch (e) {
                if (e && e.name === 'AbortError') return;   // a pessoa fechou o menu de compartilhar
            }
        }
        copiarConvite();
    }
    async function copiarConvite() {
        if (await copiarTexto(textoConvite())) toast('Convite copiado! Cole no WhatsApp ou onde quiser.');
        else toast('Não deu para copiar. Segure no link para copiar.', 'erro');
    }
    // copia para a área de transferência; se o navegador negar o jeito novo, tenta o antigo
    async function copiarTexto(txt) {
        try {
            await navigator.clipboard.writeText(txt);
            return true;
        } catch {
            const t = document.createElement('textarea');
            t.value = txt;
            t.setAttribute('readonly', '');
            t.style.cssText = 'position:fixed;opacity:0;top:0;left:0';
            document.body.appendChild(t);
            t.select();
            let ok = false;
            try { ok = document.execCommand('copy'); } catch { /* sem jeito */ }
            t.remove();
            return ok;
        }
    }
    function htmlConvite() {
        const link = linkConvite();
        if (!link) return '';
        const p = premioConvite(), total = S.convites.total || 0;
        return `<h3 class="secao-titulo">Convide amigos</h3>
            <p>Quem criar uma fazenda pelo seu link ganha <b>${p.amigo}</b> ${ico('moeda', 14)}, e você ganha <b>${p.dono}</b> ${ico('moeda', 14)}.</p>
            <div class="codigo-box convite-box"><code>${esc(link)}</code></div>
            <p class="convite-botoes">
                ${navigator.share ? '<button type="button" class="botao verde" data-convite-compartilhar>Compartilhar</button>'
                    : `<a class="botao verde" href="https://wa.me/?text=${encodeURIComponent(textoConvite())}" target="_blank" rel="noopener">Mandar no WhatsApp</a>`}
                <button type="button" class="botao creme" data-convite-copiar>Copiar convite</button>
            </p>
            <p class="det">${total ? `${total} amigo(s) já entraram pelo seu convite.` : 'Ninguém entrou pelo seu convite ainda: chama a galera!'}</p>`;
    }
    // amigos que entraram pelo seu link desde a última vez (o servidor manda uma vez só)
    function avisarConvites(estado) {
        const novos = (estado.convites && estado.convites.novos) || [];
        if (!novos.length) return;
        const com = novos.filter((n) => n.premiado), sem = novos.filter((n) => !n.premiado);
        const nomes = (l) => l.map((n) => esc(n.apelido)).join(', ');
        if (com.length) toast(`${ico('coracao', 16)} ${nomes(com)} entrou pelo seu convite: +${com.length * premioConvite().dono} ${ico('moeda', 14)}!`, 'festa');
        if (sem.length) toast(`${nomes(sem)} entrou pelo seu convite (os prêmios de hoje já acabaram, volta amanhã).`);
    }
    // tela de entrada aberta por um convite: mostra de quem é e o presente
    async function mostrarFaixaConvite() {
        const cod = store.get(LS.convite);
        if (!cod || !el.conviteFaixa) return;
        try {
            const info = await rpc('fazenda_convite_info', { p_codigo: cod });
            if (!info) { store.del(LS.convite); return; }
            el.conviteFaixa.innerHTML = `${ico('coracao', 16)} <b>${esc(info.apelido)}</b> te convidou! Crie sua fazenda e ganhe <b>${info.moedas}</b> ${ico('moeda', 14)} de presente.`;
            el.conviteFaixa.hidden = false;
        } catch { /* sem faixa, sem problema */ }
    }

    /* ---------- O lago (terreno 3): o Bira enche o cesto, 1 peixe a cada 30 min ----------
       O servidor manda desde quando o cesto enche, o ritmo, o máximo e as chances. */
    function infoLago() {
        const l = S && S.lago;
        if (!l || !l.desde) return null;
        const passou = agora() - Date.parse(l.desde), passo = l.intervalo * 1000;
        const prontos = Math.max(0, Math.min(l.max, Math.floor(passou / passo)));
        return { ...l, prontos, proximo: prontos >= l.max ? 0 : (prontos + 1) * passo - passou };
    }
    function atualizarLago() {
        const i = !visita && infoLago();
        cena.definirLago(i ? { prontos: i.prontos, max: i.max } : null);
    }
    function descreverLago() {
        const i = infoLago();
        const peixinho = spr(A.cultura('lambari').item, 22);
        if (!i) return mostrarStatus(visita ? `${peixinho} O lago do vizinho.` : `${peixinho} O lago do Vale do sudeste: compre esse terreno e o Bira pesca para você.`);
        const chico = (i.peixes || []).find((p) => p.id === 'velho_chico');
        mostrarStatus(`${peixinho} <b>Bira, o pescador</b>: ` + (i.prontos
            ? `${i.prontos} peixe(s) no cesto${i.prontos >= i.max ? ' (cheio!)' : ''}. Toque para pegar.`
            : `o cesto está vazio; o próximo peixe sai em ${fmtTempo(i.proximo)}.`) +
            (chico ? ` Chance do lendário Peixe do Velho Chico: ${chico.chance}%.` : ''));
    }
    function pescar() {
        const i = infoLago();
        if (!i || !i.prontos) return descreverLago();
        cena.definirLago({ prontos: 0, max: i.max });   // o balão some na hora
        som.tocar('colher');
        enfileirar([], async () => {
            const r = await rpc('fazenda_pescar', { p_token: token });
            aplicarEstado(r.estado);
            const lista = Object.entries(r.peixes || {})
                .sort((a, b) => (culturas[b[0]] || {}).venda - (culturas[a[0]] || {}).venda)
                .map(([id, n]) => `${n} ${itemDe(culturas[id] || { id }, 18)}`).join(' ');
            toast(`O Bira tirou ${r.qtd} peixe(s): ${lista} +${r.xp} ${ico('xp', 14)}`, r.lendario ? 'festa' : undefined);
            if (r.lendario) {
                som.tocar('festa');
                abrirPainel('lendario');
            } else {
                descreverLago();
            }
        });
    }

    /* ---------- Anúncio premiado: assiste até o fim e tudo anda 30 minutos ----------
       API de anúncios para jogos H5 do AdSense (adBreak do tipo 'reward'): ela avisa quando
       tem anúncio pronto (beforeReward) e o botão aparece; o tempo só vem com o anúncio
       visto até o fim (adViewed). Com ANUNCIO.ligado false não aparece nada; no localhost dá
       para testar com um anúncio de mentira. */
    const ehLocal = ['localhost', '127.0.0.1'].includes(location.hostname);
    let mostrarAnuncio = null;   // chamar mostra o vídeo (só existe quando tem anúncio pronto)
    let timerAnuncio = null;
    function iniciarAnuncios() {
        if (ANUNCIO.ligado) {
            window.adsbygoogle = window.adsbygoogle || [];
            window.adBreak = window.adConfig = (o) => { window.adsbygoogle.push(o); };
            const sc = document.createElement('script');
            sc.async = true;
            sc.crossOrigin = 'anonymous';
            sc.dataset.adClient = ANUNCIO.cliente;
            if (ANUNCIO.teste) sc.dataset.adbreakTest = 'on';
            sc.src = 'https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=' + encodeURIComponent(ANUNCIO.cliente);
            document.head.appendChild(sc);
            window.adConfig({ preloadAdBreaks: 'on', sound: 'on' });
            prepararAnuncio();
        } else if (ehLocal) {
            mostrarAnuncio = simularAnuncio;
        }
        atualizarBotaoAnuncio();
    }
    function prepararAnuncio() {
        clearTimeout(timerAnuncio);
        if (!ANUNCIO.ligado || mostrarAnuncio) return;
        window.adBreak({
            type: 'reward',
            name: 'adiantar_30min',
            beforeAd: () => som.pausar(true),
            afterAd: () => som.pausar(false),
            beforeReward: (mostrar) => { mostrarAnuncio = mostrar; atualizarBotaoAnuncio(); },
            adDismissed: () => toast('Anúncio fechado antes do fim: sem os 30 minutos desta vez.'),
            adViewed: ganharRecompensa,
            adBreakDone: (info) => {
                mostrarAnuncio = null;
                atualizarBotaoAnuncio();
                // depois de um anúncio já prepara o próximo; sem anúncio agora, tenta daqui a 1 min
                const st = info && info.breakStatus;
                timerAnuncio = setTimeout(prepararAnuncio, st === 'viewed' || st === 'dismissed' ? 2000 : 60000);
            }
        });
    }
    // tem algo em andamento para os 30 minutos valerem alguma coisa?
    function algoEmAndamento() {
        return (S.canteiros || []).some((c) => info(c).fase === 'crescendo')
            || (S.animais || []).some((a) => infoAnimal(a).estado === 'produzindo')
            || (S.construcoes || []).some((c) => {
                const o = infoOficina(c), p = infoProducao(c);
                return (o && o.estado === 'trabalhando') || (p && p.falta > 0);
            });
    }
    function atualizarBotaoAnuncio() {
        if (!el.anuncio) return;
        el.anuncio.hidden = !(mostrarAnuncio && S && !visita && !constr.ativo && algoEmAndamento());
    }
    function assistirAnuncio() {
        if (!mostrarAnuncio) return;
        const mostrar = mostrarAnuncio;
        mostrarAnuncio = null;     // um toque, um anúncio
        el.anuncio.hidden = true;
        mostrar();
    }
    function ganharRecompensa() {
        enfileirar([], async () => {
            const r = await rpc('fazenda_anuncio', { p_token: token });
            aplicarEstado(r.estado);
            const partes = [r.canteiros && `${r.canteiros} canteiro(s)`, r.animais && `${r.animais} animal(is)`, r.oficinas && `${r.oficinas} oficina(s)`].filter(Boolean);
            som.tocar('colher');
            toast(`${ico('brilho', 14)} Tudo adiantou 30 minutos${partes.length ? ': ' + partes.join(', ') : ''}!`, 'festa');
        });
    }
    // só no localhost: um "anúncio" de 5 segundos para testar o caminho todo
    function simularAnuncio() {
        const tela = document.createElement('div');
        tela.className = 'anuncio-teste';
        tela.innerHTML = `<div class="caixa"><p><b>Anúncio de teste</b></p><p>No site de verdade, aqui passa o vídeo do Google.</p>
            <p class="anuncio-conta">5</p><button type="button" class="botao creme" data-pular>Fechar sem assistir</button></div>`;
        document.body.appendChild(tela);
        som.pausar(true);
        let n = 5;
        const fim = (viu) => {
            clearInterval(iv);
            tela.remove();
            som.pausar(false);
            if (viu) ganharRecompensa();
            else toast('Anúncio fechado antes do fim: sem os 30 minutos desta vez.');
            setTimeout(() => { mostrarAnuncio = simularAnuncio; atualizarBotaoAnuncio(); }, 1000);
        };
        const iv = setInterval(() => {
            n -= 1;
            tela.querySelector('.anuncio-conta').textContent = n;
            if (n <= 0) fim(true);
        }, 1000);
        tela.querySelector('[data-pular]').addEventListener('click', () => fim(false));
    }

    /* ---------- Avisos no celular ----------
       Com a fazenda aberta ou minimizada, avisa quando algo fica pronto
       (plantação, animais, oficinas, amoreira). Liga e desliga no Perfil. */
    const podeAvisar = () => 'Notification' in window;
    const avisosLigados = () => podeAvisar() && store.get(LS.avisos) === '1' && Notification.permission === 'granted';
    let timerAvisos = null;
    const jaAvisado = new Set();
    // tudo que fica (ou já ficou) pronto, com a hora exata; a chave muda a cada novo ciclo
    function proximosEventos() {
        const ev = [];
        for (const c of S.canteiros || []) {
            const i = info(c);
            if (i.fase === 'crescendo' || i.fase === 'maduro') ev.push({ quando: i.maduro, chave: 'c' + c.posicao + c.plantado_em, texto: `${i.k.nome} pronto para colher` });
        }
        const lg = !visita && infoLago();
        if (lg) ev.push({ quando: Date.parse(lg.desde) + lg.max * lg.intervalo * 1000, chave: 'lago' + lg.desde, texto: 'o cesto de peixes do Bira está cheio' });
        for (const a of S.animais || []) {
            const t = tipoAnimal(a.tipo);
            if (t && a.alimentado_em) ev.push({ quando: Date.parse(a.alimentado_em) + t.tempo_seg * 1000, chave: 'a' + a.id + a.alimentado_em, texto: `${t.nome} com ${((culturas[t.produto] || {}).nome || 'produto').toLowerCase()} pronto` });
        }
        for (const c of S.construcoes || []) {
            const it = tipoItem(c.tipo);
            if (!it || !it.produz) continue;
            if (it.entradas && c.iniciado_em) {
                const o = infoOficina(c);
                const fim = o.termina || Date.parse(c.iniciado_em) + it.produz_seg * 1000;
                ev.push({ quando: fim, chave: 'o' + c.x + ',' + c.y + c.iniciado_em + ':' + c.estoque, texto: `${it.nome} terminou o estoque` });
            }
            if (!it.entradas && c.colhido_em) ev.push({ quando: Date.parse(c.colhido_em) + it.produz_seg * 1000, chave: 'p' + c.x + ',' + c.y + c.colhido_em, texto: `${it.nome} com frutas prontas` });
        }
        return ev.filter((e) => !jaAvisado.has(e.chave)).sort((a, b) => a.quando - b.quando);
    }
    function agendarAvisos() {
        clearTimeout(timerAvisos);
        if (!S || visita || !avisosLigados()) return;
        const lista = proximosEventos();
        // com a tela à vista, o que já está pronto você está vendo: não vira aviso
        if (!document.hidden) lista.filter((e) => e.quando <= agora()).forEach((e) => jaAvisado.add(e.chave));
        const prox = lista.find((e) => !jaAvisado.has(e.chave));
        if (!prox) return;
        const espera = Math.min(Math.max(1000, prox.quando - agora() + 1500), 2147483000);
        timerAvisos = setTimeout(() => {
            const prontos = proximosEventos().filter((e) => e.quando <= agora() + 1000);
            prontos.forEach((e) => jaAvisado.add(e.chave));
            if (prontos.length && document.hidden) notificar(prontos);
            agendarAvisos();
        }, espera);
    }
    async function notificar(lista, titulo) {
        titulo = titulo || (lista.length === 1 ? 'Fazendinha: tem coisa pronta!' : `Fazendinha: ${lista.length} coisas prontas!`);
        const opcoes = { body: lista.slice(0, 3).map((e) => e.texto).join(' · '), icon: 'assets/fazenda/app/icone-192.png', tag: 'fazenda', renotify: true };
        try {
            const reg = 'serviceWorker' in navigator && await Promise.race([navigator.serviceWorker.ready, new Promise((ok) => setTimeout(() => ok(null), 1500))]);
            if (reg) await reg.showNotification(titulo, opcoes);
            else new Notification(titulo, opcoes);
        } catch { /* sem aviso, sem problema */ }
    }
    function htmlAvisos() {
        if (!podeAvisar()) return '<h3 class="secao-titulo">Avisos</h3><p class="aviso">Este navegador não mostra avisos.</p>';
        const negado = Notification.permission === 'denied';
        return `<h3 class="secao-titulo">Avisos no celular</h3>
            <p>Avisa quando a plantação, os animais ou as oficinas ficam prontos, mesmo com a fazenda minimizada.</p>
            <p>${negado ? '<span class="aviso">Os avisos estão bloqueados nas configurações do navegador.</span>'
                : `<button type="button" class="botao ${avisosLigados() ? 'creme' : 'verde'}" data-avisos>${avisosLigados() ? 'Desligar avisos' : 'Ligar avisos'}</button>`}</p>`;
    }

    /* ---------- Caminho dos níveis: o que cada nível libera ----------
       Os níveis de cada coisa vêm do servidor (nivel_min / nivel); as duas
       contas abaixo precisam bater com fazenda_presente_nivel e
       fazenda_limite_canteiros no SQL. */
    const NIVEL_MAX = 30;
    const presenteNivel = (n) => (n > 10 ? 100 : 50) * n;   // do 10 em diante sobe devagar, e o presente dobra
    const limiteCanteirosNivel = (n) => Math.min(6 + (n - 1) * 2, 54);
    const ORDEM_TIPO = { Terreno: 0, Ajudante: 1, Oficina: 1, 'Máquina': 1, Energia: 1, Animal: 2, Cercado: 2, 'Árvore': 2, Semente: 3, Casa: 4, Enfeite: 5 };
    function liberaNoNivel(n) {
        if (!S) return [];
        const r = [];
        for (const z of zonasVenda()) if (z.nivel === n) r.push({ html: spr(39, 24), nome: z.lago ? `${z.nome} (com lago)` : z.nome, tipo: 'Terreno' });
        for (const a of S.animais_tipos || []) if (a.nivel_min === n) r.push({ html: spr(A.ANIMAL[a.id], 24), nome: a.nome, tipo: 'Animal' });
        for (const t of S.ajudantes_tipos || []) if (t.nivel_min === n) r.push({ html: retratoAjudante(t.id, 24), nome: `${t.nome} (${t.papel.toLowerCase()})`, tipo: 'Ajudante' });
        for (const k of S.culturas) if (k.tipo === 'cultura' && k.nivel_min === n) r.push({ html: itemDe(k, 24), nome: k.estacao ? `${k.nome} (${NOME_ESTACAO[k.estacao]})` : k.nome, tipo: 'Semente' });
        for (const i of S.itens || []) {
            if (i.nivel_min !== n) continue;
            const tipo = i.categoria === 'maquina' ? 'Máquina' : i.categoria === 'energia' ? 'Energia' : i.categoria === 'oficina' ? 'Oficina' : i.categoria === 'construcao' ? 'Casa' : i.categoria === 'bichos' ? 'Cercado' : i.categoria === 'pomar' ? 'Árvore' : 'Enfeite';
            r.push({ html: A.htmlItem(i.id, 24), nome: i.nome, tipo });
        }
        return r.sort((a, b) => ORDEM_TIPO[a.tipo] - ORDEM_TIPO[b.tipo]);
    }
    // extras de todo nível: canteiros a mais e o presente de moedas
    function extrasDoNivel(n) {
        const mais = n > 1 ? limiteCanteirosNivel(n) - limiteCanteirosNivel(n - 1) : limiteCanteirosNivel(1);
        return { canteiros: mais, moedas: n > 1 ? presenteNivel(n) : 0 };
    }
    const chipsHtml = (lista) => lista.map((x) => `<span class="chip" title="${esc(x.tipo)}">${x.html}<span>${esc(x.nome)}</span></span>`).join('');
    let nivelComemorar = null;   // { de, ate } da última subida de nível

    // canteiros que ainda dá para colocar (o limite cresce com o nível e os terrenos)
    const canteirosLivres = () => (S ? Math.max(0, S.jogador.max_canteiros - S.canteiros.length) : 0);

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
    // canteiro do vizinho no alcance de um alarme antiladrão?
    function protegidoAlarme(c) {
        if (!visita) return false;
        return (visita.construcoes || []).some((m) => {
            const it = tipoItem(m.tipo);
            return it && it.efeito === 'alarme' && Math.abs(m.x - c.x) <= it.raio && Math.abs(m.y - c.y) <= it.raio;
        });
    }
    function podePegar(c, i) {
        return i.fase === 'maduro' && !c.ja_peguei && c.roubado < limitePegar(i.k) && !protegidoAlarme(c);
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

    const DEMO_CANTEIROS = Array.from({ length: 18 }, (_, p) => ({ posicao: p, x: 9 + (p % 6), y: 4 + Math.floor(p / 6) }));

    function visualCanteiro(p) {
        if (!S) return DEMO[p] || { solo: 'vazio' };
        const c = canteiro(p);
        const i = info(c);
        const pendente = pendentesPos.has(p);
        if (i.fase === 'bloqueado') return null;
        if (i.fase === 'vazio' || i.fase === 'arado') return { solo: i.fase, pendente };
        const arte = A.cultura(i.k.id);
        const v = { solo: 'arado', seco: c.seco && i.fase !== 'murcho', adubado: !!c.adubado && i.fase !== 'murcho', pendente };
        if (i.fase === 'murcho') {
            v.planta = arte.murcho;
        } else {
            v.probs = i.probs;
            if (i.fase === 'maduro') { v.planta = arte.fases[2]; v.maduro = true; }
            else { v.planta = i.prog < 0.5 ? arte.fases[0] : arte.fases[1]; v.progresso = i.prog; }
        }
        if (visita && i.fase === 'maduro') {
            if (podePegar(c, i)) v.pegar = true;
            else { v.cinza = true; v.check = !!c.ja_peguei; v.alarme = !c.ja_peguei && protegidoAlarme(c); }
        }
        return v;
    }

    /* ---------- Animais e construções ---------- */
    const tipoAnimal = (id) => S && S.animais_tipos && S.animais_tipos.find((t) => t.id === id);
    const ITEM_CANTEIRO = { id: 'canteiro', nome: 'Canteiro', categoria: 'plantacao', custo: 0, nivel_min: 1, largura: 1, altura: 1 };
    const tipoItem = (id) => (id === 'canteiro' ? ITEM_CANTEIRO : S && S.itens && S.itens.find((t) => t.id === id));
    const meusAnimais = () => (visita ? visita.animais : S && S.animais) || [];
    const naCeleiro = (item) => (S && S.celeiro[item]) || 0;

    /* ---------- Ajudantes: pessoas contratadas que trabalham sozinhas ---------- */
    const tipoAjudante = (id) => S && (S.ajudantes_tipos || []).find((t) => t.id === id);
    const meuAjudante = (id) => S && (S.ajudantes || []).find((h) => h.tipo === id);
    const RITMO = [0, 12, 30, 90];                                 // tarefas por hora (igual a fazenda_ritmo)
    const custoAjudante = (t, nivel) => t.custo * [1, 2, 4][nivel || 0];   // contratar, nível 2, nível 3
    const retratoAjudante = (id, px) => {
        const a = A.AJUDANTE_ARTE[id] || { p: 'factory', i: 120 };
        return spr(a.i, px, a.p);
    };
    function areaAjudante(t) {
        return t.funcao === 'animal' ? t.alvo : 'campo';
    }
    function visualAjudantes() {
        if (!S || visita) return [];
        return (S.ajudantes || []).map((h) => {
            const t = tipoAjudante(h.tipo);
            return t ? { id: 'h:' + h.tipo, tipo: h.tipo, area: areaAjudante(t) } : null;
        }).filter(Boolean);
    }
    function descreverAjudante(id) {
        const t = tipoAjudante(id), h = meuAjudante(id);
        if (!t || !h) return;
        mostrarStatus(`${retratoAjudante(id, 22)} <b>${esc(t.nome)}</b>, ${esc(t.papel.toLowerCase())} nível ${h.nivel}: ${esc(t.descricao)} (${RITMO[h.nivel]} por hora)`);
    }
    // o que os ajudantes fizeram desde a última olhada (vem uma vez só do servidor)
    function avisarAjudantes(estado) {
        const UNIDADE = { colher: ['colheu', 'canteiros'], arar: ['arou ou adubou', 'canteiros'], plantar: ['plantou', 'canteiros'], cuidar: ['resolveu', 'problemas'], animal: ['fez', 'tarefas'] };
        const partes = (estado.ajudantes || []).filter((h) => h.relatorio > 0).map((h) => {
            const t = (estado.ajudantes_tipos || []).find((x) => x.id === h.tipo);
            if (!t) return '';
            const [verbo, coisa] = UNIDADE[t.funcao];
            return `${esc(t.nome)} ${verbo} ${h.relatorio} ${h.relatorio === 1 ? coisa.replace(/s$/, '') : coisa}`;
        }).filter(Boolean);
        if (partes.length) toast(`${retratoAjudante((estado.ajudantes.find((h) => h.relatorio > 0) || {}).tipo, 20)} Seus ajudantes trabalharam: ${partes.join(' · ')}`);
    }

    // compara o estado antigo com o novo e manda cada ajudante até o que mudou por conta dele
    function trabalhoDosAjudantes(antes, novo) {
        if (!antes || visita || !(novo.ajudantes || []).length) return;
        const quem = (funcao, alvo) => (novo.ajudantes || []).find((h) => {
            const t = (novo.ajudantes_tipos || []).find((x) => x.id === h.tipo);
            return t && t.funcao === funcao && (!alvo || t.alvo === alvo);
        });
        const obras = {};
        const anotar = (h, alvo) => { if (h) (obras[h.tipo] = obras[h.tipo] || []).push(alvo); };
        const velhos = new Map((antes.canteiros || []).map((c) => [c.posicao, c]));
        for (const c of novo.canteiros || []) {
            const a = velhos.get(c.posicao);
            if (!a) continue;
            let f = null;
            if (a.estado === 'plantado' && c.estado !== 'plantado') f = info(a).fase === 'murcho' ? 'arar' : 'colher';
            else if (a.estado === 'vazio' && c.estado === 'arado') f = 'arar';
            else if (a.estado === 'arado' && c.estado === 'plantado') f = 'plantar';
            else if (c.estado === 'plantado' && a.estado === 'plantado' && ['erva', 'praga', 'seco'].some((p) => a[p] && !c[p])) f = 'cuidar';
            else if (c.adubado && !a.adubado) f = 'arar';
            if (f) anotar(quem(f), { x: c.x, y: c.y });
        }
        const bichos = new Map((antes.animais || []).map((b) => [b.id, b]));
        for (const b of novo.animais || []) {
            const a = bichos.get(b.id);
            if (a && a.alimentado_em !== b.alimentado_em) anotar(quem('animal', b.tipo), { animal: b.id });
        }
        for (const [tipo, alvos] of Object.entries(obras)) cena.ajudanteTrabalhou(tipo, alvos);
    }

    /* ---------- Avatar: chapéu e cores (fazenda_avatar); o desenho sai de A.htmlAvatar ---------- */
    let rascunhoAvatar = null;
    const precoAvatar = (tipo) => ((S.jogador.avatar_precos || {})[tipo]) || 0;
    const temAvatar = (tipo) => !precoAvatar(tipo) || (S.jogador.avatares || []).includes(tipo);
    function htmlEditorAvatar() {
        const a = rascunhoAvatar, tipo = A.AVATAR_TIPOS[a.tipo], cores = A.AVATAR_CORES;
        const bolinha = (cor) => `<span class="av-cor" style="background:${cor}"></span>`;
        const linha = (regiao) => {
            const r = tipo.regioes[regiao];
            const opcoes = [A.corOriginal(a.tipo, regiao), ...cores[regiao].map((t) => t[t.length === 2 ? 1 : 1])];
            return `<div class="av-linha"><span class="av-titulo">${r.nome || A.NOME_REGIAO[regiao]}</span><div class="av-opcoes">${opcoes.map((cor, i) =>
                `<button type="button" class="av-op${(a[regiao] | 0) === i ? ' ativa' : ''}" data-av="${regiao}:${i}" aria-label="${r.nome || A.NOME_REGIAO[regiao]} ${i ? i + 1 : 'original'}">${bolinha(cor)}</button>`).join('')}</div></div>`;
        };
        return `
            <div class="av-preview">${A.htmlAvatar(a, 112)}</div>
            <div class="av-linha"><span class="av-titulo">Personagem</span><div class="av-opcoes">${Object.entries(A.AVATAR_TIPOS).map(([id, t]) =>
                `<button type="button" class="av-op chapeu${a.tipo === id ? ' ativa' : ''}" data-av="tipo:${id}">${A.htmlAvatar({ ...a, tipo: id }, 40)}<small>${t.nome}</small><small class="av-preco">${temAvatar(id) ? (precoAvatar(id) ? 'seu' : 'grátis') : `${ico('moeda', 11)} ${precoAvatar(id).toLocaleString('pt-BR')}`}</small></button>`).join('')}</div></div>
            ${['chapeu', 'cabelo', 'pele', 'roupa', 'calca'].filter((r) => tipo.regioes[r]).map(linha).join('')}
            <p class="det">A primeira bolinha de cada linha é a cor original do personagem. Seus vizinhos veem esse avatar no ranking e quando visitam a sua fazenda.</p>
            <div class="rodape-painel">
                <button type="button" class="botao creme" data-painel-ir="conta">Cancelar</button>
                ${temAvatar(a.tipo)
                    ? '<button type="button" class="botao verde" data-av-salvar>Salvar</button>'
                    : `<button type="button" class="botao verde" data-av-salvar${S.jogador.moedas >= precoAvatar(a.tipo) ? '' : ' disabled'}>Comprar ${esc(tipo.nome.toLowerCase())} por ${ico('moeda', 14)} ${precoAvatar(a.tipo).toLocaleString('pt-BR')}</button>`}
            </div>`;
    }

    /* ---------- Visitas na porteira: a cada 3 horas chega alguém (fazenda_visitante) ---------- */
    const VISITAS = {
        feirante: { nome: 'Seu Tonico', papel: 'o feirante', sprite: 86,
            fala: (q, item, paga) => `Bom dia! Tô precisando de <b>${q} ${item}</b> pra banca da feira. Pago <b>${paga}</b>, bem mais que no celeiro!` },
        doceira: { nome: 'Dona Benta', papel: 'a doceira', sprite: 99,
            fala: (q, item, paga) => `Ô de casa! Vou fazer uma fornada e me faltam <b>${q} ${item}</b>. Te pago <b>${paga}</b>, combinado?` },
        caminhoneiro: { nome: 'Zeca', papel: 'do caminhão', sprite: 112,
            fala: (q, item, paga) => `E aí! O caminhão tá vazio: levo <b>${q} ${item}</b> de uma vez só. Pago <b>${paga}</b> e ainda dou um bônus de XP.` },
        mascate: { nome: 'Dona Fia', papel: 'a mascate', sprite: 100 }
    };
    const visitaAgora = () => (!visita && S && S.visitante) || null;
    const nomeQtd = (k, n) => { const nome = (k.nome || k.id).toLowerCase(); return n === 1 || /s$/.test(nome) ? nome : nome.replace(/(ão)$/, 'ões').replace(/([^s])$/, '$1s'); };
    let visitaVista = null;
    function atualizarVisitante() {
        const v = visitaAgora();
        cena.definirVisitante(v ? { tipo: v.tipo, item: v.item ? A.cultura(v.item).item : null } : null);
        if (v && visitaVista !== null && visitaVista !== v.slot) {
            const p = VISITAS[v.tipo];
            toast(`${spr(p.sprite, 22, 'dungeon')} Chegou visita na porteira: <b>${p.nome}</b>, ${p.papel}! Toque nela para conversar.`);
        }
        visitaVista = v ? v.slot : (visitaVista === null ? 0 : visitaVista);
    }
    function descreverVisitante() {
        const v = visitaAgora();
        if (!v) return;
        const p = VISITAS[v.tipo], k = v.item && culturas[v.item];
        mostrarStatus(`${spr(p.sprite, 22, 'dungeon')} <b>${p.nome}</b>, ${p.papel}: ` + (v.tipo === 'mascate'
            ? `vende adubo para ${v.canteiros} canteiros por ${moeda(v.preco)}.`
            : `quer ${v.qtd} ${k ? itemDe(k, 16) + esc(nomeQtd(k, v.qtd)) : ''} e paga ${moeda(v.paga)}.`) + ' Toque para conversar.');
    }
    // canteiros que a mascate aduba agora (crescendo e ainda sem adubo)
    const canteirosParaAdubo = () => (S.canteiros || []).filter((c) => !c.adubado && info(c).fase === 'crescendo').length;
    function htmlVisitante(v) {
        const p = VISITAS[v.tipo], ate = hora(v.ate);
        const cabeca = `<div class="visita-topo">${spr(p.sprite, 64, 'dungeon')}<div><b>${p.nome}</b>, ${p.papel}<small>fica até ${ate}</small></div></div>`;
        if (v.tipo === 'mascate') {
            const n = Math.min(v.canteiros, canteirosParaAdubo()), preco = Math.ceil(v.preco * n / v.canteiros);
            return `${cabeca}
                <p class="fala">Psiu! Adubo da boa, direto da serra: aduba até <b>${v.canteiros} canteiros</b> que estão crescendo, e cada um dá <b>+1 item</b> na colheita. Sai por <b>${v.preco}</b> ${ico('moeda', 14)} os ${v.canteiros}.</p>
                <p class="det">${n ? `Agora dá para adubar ${n} canteiro(s): você paga ${moeda(preco)}.` : 'Você não tem canteiro crescendo sem adubo agora: plante e volte a falar com ela.'}</p>
                <div class="rodape-painel">
                    <button type="button" class="botao creme" data-atender="0">Agora não</button>
                    <button type="button" class="botao verde" data-atender="1"${n && S.jogador.moedas >= preco ? '' : ' disabled'}>${spr(1040, 18)} Comprar adubo</button>
                </div>`;
        }
        const k = culturas[v.item] || { id: v.item, nome: v.item, venda: 0 }, tem = Math.max(0, naCeleiro(v.item) - reservaDe(v.item));
        const valeCeleiro = v.qtd * (k.venda || 0), mais = valeCeleiro ? Math.round((v.paga / valeCeleiro - 1) * 100) : 0;
        return `${cabeca}
            <p class="fala">${p.fala(v.qtd, `${itemDe(k, 18)} ${esc(nomeQtd(k, v.qtd))}`, `${v.paga} ${ico('moeda', 14)}`)}</p>
            <div class="oficina-conta">
                <span>No celeiro valeria ${moeda(valeCeleiro)}</span>
                <span class="lucro">Paga ${moeda(v.paga)} (+${mais}%) e ${v.xp} ${ico('xp', 12)}</span>
            </div>
            <p class="det">Você tem ${tem} ${itemDe(k, 16)}${reservaDe(v.item) ? ' (fora o reservado para os bichos)' : ''}${tem < v.qtd ? `: faltam ${v.qtd - tem}.` : '.'}</p>
            <div class="rodape-painel">
                <button type="button" class="botao creme" data-atender="0">Agora não</button>
                <button type="button" class="botao verde" data-atender="1"${tem >= v.qtd ? '' : ' disabled'}>Entregar ${v.qtd} ${itemDe(k, 18)}</button>
            </div>`;
    }
    function atender(entregar) {
        const v = visitaAgora();
        if (!v) return fecharPainel();
        fecharPainel();
        S.visitante = null;        // ela já vai embora andando; o servidor confirma
        atualizarVisitante();
        enfileirar([], async () => {
            const r = await rpc('fazenda_atender', { p_token: token, p_entregar: entregar });
            const p = VISITAS[v.tipo];
            if (r.resposta === 'entregou') {
                som.tocar(v.tipo === 'mascate' ? 'cuidar' : 'moeda');
                toast(v.tipo === 'mascate'
                    ? `${spr(1040, 20)} ${p.nome} adubou ${r.adubados} canteiro(s): +1 item na colheita de cada.`
                    : `${spr(p.sprite, 20, 'dungeon')} ${p.nome} levou o pedido: +${v.paga} ${ico('moeda', 14)} +${v.xp} ${ico('xp', 14)}`, 'festa');
            } else {
                toast(`${spr(p.sprite, 20, 'dungeon')} ${p.nome} foi embora. Daqui a pouco chega outra visita.`);
            }
            aplicarEstado(r.estado);
        });
    }

    /* ---------- Galinheiro: cresce com os bichos pequenos (igual a fazenda_galinheiro_linhas) ---------- */
    function linhasGalinheiro(fonte) {
        const n = (fonte.animais || []).filter((a) => ['galinha', 'pato', 'coelho'].includes(a.tipo)
            && !(fonte.construcoes || []).some((c) => c.tipo === 'cercado_' + a.tipo)).length;
        const quer = n >= 9 ? 4 : n >= 6 ? 3 : 2;
        let linhas = 2;
        while (linhas < quer) {
            const y = 7 + linhas;
            const ocupado = (fonte.canteiros || []).some((c) => c.y === y && c.x >= 0 && c.x <= 6)
                || (fonte.construcoes || []).some((c) => { const t = tamanhoItem(c.tipo); return c.x <= 6 && c.x + t.w > 0 && c.y <= y && c.y + t.h > y; });
            if (ocupado) break;
            linhas++;
        }
        return { linhas, quer };
    }
    let avisouGalinheiro = false;
    function atualizarGalinheiro() {
        const fonte = visita || S;
        if (!fonte) return;
        const g = !visita && S.galinheiro ? S.galinheiro : linhasGalinheiro(fonte);
        cena.definirGalinheiro(g.linhas);
        if (!visita && g.quer > g.linhas && !avisouGalinheiro) {
            avisouGalinheiro = true;
            toast(`${spr(A.ANIMAL.galinha, 20)} Os bichos estão apertados! Em Construir → Bichos tem um cercado para cada um (galinhas, coelhos, patos...): coloque onde quiser e eles se mudam para lá.`);
        }
    }

    /* ---------- Ração reservada no celeiro (o "vender" não leva) ---------- */
    const reservaDe = (item) => (S && S.reservas && S.reservas[item]) || 0;
    const MAX_REFEICOES = 10;
    // quais dos seus animais comem esse item, e quanto vai numa refeição de todos eles
    function quemCome(item) {
        const tipos = (S.animais_tipos || []).filter((t) => t.racao === item && S.animais.some((a) => a.tipo === t.id));
        if (!tipos.length) return null;
        const qtd = (t) => S.animais.filter((a) => a.tipo === t.id).length;
        return {
            nomes: tipos.map((t) => `${qtd(t)} ${t.nome.toLowerCase()}${qtd(t) > 1 ? 's' : ''}`).join(' e '),
            porRefeicao: tipos.reduce((soma, t) => soma + qtd(t) * t.racao_qtd, 0),
            sprite: A.ANIMAL[tipos[0].id]
        };
    }
    function htmlReserva(k, come) {
        const res = reservaDe(k.id);
        if (!res) {
            return `<button type="button" class="botao pequeno creme reserva-btn" data-reserva="${esc(k.id)}:2">${spr(come.sprite, 18)} Reservar para ${esc(come.nomes)}</button>`;
        }
        const ref = Math.floor(res / come.porRefeicao);
        return `<span class="reserva">${spr(come.sprite, 18)} Guardando <b>${res}</b> para ${esc(come.nomes)} (${ref} refeiç${ref === 1 ? 'ão' : 'ões'})
            <button type="button" class="botao mini creme" data-reserva="${esc(k.id)}:${ref - 1}" aria-label="Guardar menos">−</button>
            <button type="button" class="botao mini creme" data-reserva="${esc(k.id)}:${ref + 1}" aria-label="Guardar mais"${ref >= MAX_REFEICOES ? ' disabled' : ''}>+</button></span>`;
    }

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

    // item que produz sozinho (amoreira): pronto quando passou o tempo desde a última colheita
    function infoProducao(c) {
        const it = tipoItem(c.tipo);
        if (!it || !it.produz || it.entradas) return null;   // oficina tem regra própria
        const pronto = !c.colhido_em ? agora() : Date.parse(c.colhido_em) + it.produz_seg * 1000;
        return { it, falta: pronto - agora(), produto: culturas[it.produz] };
    }
    /* ---------- Oficinas: transformam o que você colhe em produtos mais caros ---------- */
    // Cada oficina guarda até 10 receitas no estoque e trabalha sozinha: termina uma, começa a
    // próxima. O servidor só faz a conta quando a fazenda carrega; aqui ela anda até agora.
    const temEfeito = (ef) => !!S && (S.construcoes || []).some((m) => (tipoItem(m.tipo) || {}).efeito === ef);
    function infoOficina(c) {
        const it = tipoItem(c.tipo);
        if (!it || !it.entradas) return null;
        const produto = culturas[it.produz] || { id: it.produz, nome: it.produz, xp: 0, venda: 0 };
        const dur = it.produz_seg * 1000, ligada = oficinaLigada(c), auto = temEfeito('automatico') || ligada;
        let t = c.iniciado_em ? Date.parse(c.iniciado_em) : null, estoque = c.estoque || 0, prontos = c.prontos || 0;
        for (let n = 0; t != null && agora() >= t + dur && n < 48; n++) {
            if (!auto) prontos += it.produz_qtd;   // com a fábrica automática vai direto para o celeiro
            t = estoque > 0 ? (estoque--, t + dur) : null;
        }
        const base = { it, produto, estoque, prontos, auto, ligada };
        if (t == null) return { ...base, estado: 'parada' };
        const falta = t + dur - agora();
        return { ...base, estado: 'trabalhando', falta, progresso: 1 - falta / dur, termina: t + dur + estoque * dur };
    }
    // ingredientes que faltam (a ração reservada não conta)
    const faltaParaReceita = (it) => Object.entries(it.entradas)
        .map(([item, qtd]) => ({ item, falta: qtd - Math.max(0, naCeleiro(item) - reservaDe(item)) }))
        .filter((f) => f.falta > 0);
    const nomeItem = (id) => esc(((culturas[id] || {}).nome || id).toLowerCase());
    const receitaHtml = (it) => Object.entries(it.entradas).map(([item, qtd]) => `${qtd} ${itemDe(culturas[item] || { id: item }, 16)}`).join(' + ') +
        ` → ${itemDe(culturas[it.produz] || { id: it.produz }, 16)} (${fmtDuracao(it.produz_seg)})`;

    function visualConstrucoes() {
        if (!S) return DEMO_CONSTRUCOES;
        if (visita) return visita.construcoes || [];
        return (S.construcoes || []).map((c) => {
            const o = infoOficina(c);
            if (o) {
                const cam = o.ligada && o.estado === 'trabalhando' && redeCanos().caminhos.get(c.x + ',' + c.y);
                const fluxo = cam ? { caminho: cam, entra: A.cultura(Object.keys(o.it.entradas)[0]).item, sai: A.cultura(o.it.produz).item } : null;
                return { ...c, oficina: { estado: o.prontos > 0 ? 'pronta' : o.estado, trabalhando: o.estado === 'trabalhando', progresso: o.progresso, produto: A.cultura(o.it.produz).item, fluxo } };
            }
            if (c.tipo === 'cano') return { ...c, cano: redeCanos().lados.get(c.x + ',' + c.y) };
            if (c.iniciado_em && (tipoItem(c.tipo) || {}).efeito === 'biomassa') return { ...c, ligado: true };
            const p = infoProducao(c);
            return p && p.falta <= 0 ? { ...c, pronto: true, produto: A.cultura(p.it.produz).item } : c;
        });
    }

    // o que os itens em volta fazem por um canteiro (aparece ao passar/tocar nele)
    const NOME_EFEITO = {
        seco: 'sem seca', praga: 'sem pragas', erva: 'sem ervas', crescer: 'cresce 10% mais rápido',
        adubo: '+1 item', xp: '+1 XP', sorte: 'sorte (colheita em dobro às vezes)', cerca: 'vizinho pega no máximo 1',
        alarme: 'protegido do vizinho', estufa: 'estufa: qualquer estação e +25% rápido (5 ⚡)',
        robo: 'o robô colhe e replanta', aspersor: 'sem nenhum problema (aspersor, 1 ⚡)'
    };
    function bonusDoCanteiro(c, fonte) {
        const vistos = new Set();
        for (const m of (fonte.construcoes || [])) {
            const it = tipoItem(m.tipo);
            if (!it || !it.efeito || !NOME_EFEITO[it.efeito] || !it.raio) continue;
            if (Math.abs(m.x - c.x) <= it.raio && Math.abs(m.y - c.y) <= it.raio) vistos.add(it.efeito);
        }
        return [...vistos].map((e) => NOME_EFEITO[e]);
    }

    /* ---------- Canos de vidro: ligam oficinas a canteiros, a um baú ou ao celeiro ----------
       (igual a fazenda_oficina_ligada no SQL). Guarda a rede até as construções ou os canteiros mudarem. */
    const VIZINHOS = [[1, 0], [-1, 0], [0, 1], [0, -1]];   // leste, oeste, sul, norte
    let cacheCanos = {};
    function redeCanos() {
        const cons = (S && S.construcoes) || [], cant = (S && S.canteiros) || [];
        if (cacheCanos.cons === cons && cacheCanos.cant === cant) return cacheCanos;
        const canos = new Set(cons.filter((c) => c.tipo === 'cano').map((c) => c.x + ',' + c.y));
        const fonte = (x, y) => (x >= 1 && x <= 3 && y >= 1 && y <= 6) || cant.some((k) => k.x === x && k.y === y)
            || cons.some((c) => c.tipo === 'bau' && c.x === x && c.y === y);
        const oficinas = cons.filter((c) => (tipoItem(c.tipo) || {}).entradas);
        const naOficina = (x, y) => oficinas.some((o) => { const t = tamanhoItem(o.tipo); return x >= o.x && y >= o.y && x < o.x + t.w && y < o.y + t.h; });
        const lados = new Map();
        for (const k of canos) {
            const [x, y] = k.split(',').map(Number);
            lados.set(k, VIZINHOS.map(([dx, dy]) => canos.has((x + dx) + ',' + (y + dy)) || naOficina(x + dx, y + dy) || fonte(x + dx, y + dy)));
        }
        const caminhos = new Map();   // oficina → canos da oficina até a fonte
        for (const o of oficinas) {
            const t = tamanhoItem(o.tipo);
            const inicio = [...canos].filter((k) => {
                const [x, y] = k.split(',').map(Number);
                return ((x === o.x - 1 || x === o.x + t.w) && y >= o.y && y < o.y + t.h) || ((y === o.y - 1 || y === o.y + t.h) && x >= o.x && x < o.x + t.w);
            });
            const veio = new Map(inicio.map((k) => [k, null]));
            const fila = [...inicio];
            let achou = null;
            while (fila.length) {
                const k = fila.shift(), [x, y] = k.split(',').map(Number);
                if (VIZINHOS.some(([dx, dy]) => fonte(x + dx, y + dy))) { achou = k; break; }
                for (const [dx, dy] of VIZINHOS) {
                    const v = (x + dx) + ',' + (y + dy);
                    if (canos.has(v) && !veio.has(v)) { veio.set(v, k); fila.push(v); }
                }
            }
            if (achou) {
                const cam = [];
                for (let k = achou; k; k = veio.get(k)) cam.push(k.split(',').map(Number));
                caminhos.set(o.x + ',' + o.y, cam.reverse());
            }
        }
        cacheCanos = { cons, cant, lados, caminhos };
        return cacheCanos;
    }
    const oficinaLigada = (c) => !!S && redeCanos().caminhos.has(c.x + ',' + c.y);

    let oficinaAberta = null;   // { x, y } da oficina com o painel aberto
    const oficinaDoPainel = () => oficinaAberta && S && (S.construcoes || []).find((k) => k.x === oficinaAberta.x && k.y === oficinaAberta.y);
    function acaoOficina(c, o) {
        oficinaAberta = { x: c.x, y: c.y };
        if (o.prontos > 0) pegarOficina(c, o);
        abrirPainel('oficina');
    }
    // leva os produtos prontos para o celeiro (o balão some na hora; o servidor confirma)
    function pegarOficina(c, o) {
        c.prontos = 0;
        c.estoque = o.estoque;
        c.iniciado_em = o.estado === 'trabalhando' ? new Date(agora() + o.falta - o.it.produz_seg * 1000).toISOString() : null;
        som.tocar('colher');
        enfileirar([], async () => {
            const r = await rpc('fazenda_oficina', { p_token: token, p_x: c.x, p_y: c.y });
            if (r.acao === 'coletou') flutuarTile(c.x, c.y, `+${r.qtd} ${itemDe(o.produto, 20)} +${r.xp} ${ico('xp', 14)}`);
            aplicarEstado(r.estado);
        });
    }
    // o painel da oficina: a receita, a conta do lucro, o que está fazendo, o estoque
    const valorReceita = (it) => Object.entries(it.entradas).reduce((a, [item, qtd]) => a + qtd * ((culturas[item] || {}).venda || 0), 0);
    function htmlOficinaAgora(o) {
        const p = (n) => `${n} ${itemDe(o.produto, 18)}`;
        const linhas = [];
        if (o.prontos) linhas.push(`<b>${p(o.prontos)} pronto(s)</b> esperando você pegar.`);
        if (o.estado === 'trabalhando') {
            linhas.push(`Fazendo ${nomeItem(o.it.produz)}: pronto em <b>${fmtTempo(o.falta)}</b>
                <span class="barrinha"><i style="width:${Math.round(o.progresso * 100)}%"></i></span>`);
            linhas.push(o.estoque ? `Depois faz mais ${o.estoque} sozinha: termina tudo em ${fmtTempo(o.termina - agora())}.` : 'Depois dessa, para: o estoque está vazio.');
        } else {
            linhas.push(o.auto ? 'Parada: falta ingrediente no celeiro (ou energia para a fábrica automática).' : 'Parada: guarde ingredientes no estoque e ela começa na hora.');
        }
        return linhas.map((l) => `<p>${l}</p>`).join('');
    }
    function htmlOficina(c, o) {
        const it = o.it, max = (S && S.estoque_max) || 10;
        const entra = valorReceita(it), sai = it.produz_qtd * (o.produto.venda || 0), lucro = sai - entra;
        const porDia = Math.floor(86400 / it.produz_seg);
        const ocupado = o.estoque + (o.estado === 'trabalhando' ? 1 : 0);
        const cabe = Math.max(0, max - ocupado);
        const temNoCeleiro = Math.min(...Object.entries(it.entradas).map(([item, qtd]) => Math.floor(Math.max(0, naCeleiro(item) - reservaDe(item)) / qtd)));
        const pode = Math.min(cabe, temNoCeleiro);
        const falta = faltaParaReceita(it);
        return `
            <p class="receita-linha">${receitaHtml(it)}</p>
            <div class="oficina-conta">
                <span>Os ingredientes valem <b>${moeda(entra)}</b></span>
                <span>${itemDe(o.produto, 18)} vale <b>${moeda(sai)}</b></span>
                <span class="${lucro > 0 ? 'lucro' : 'prejuizo'}">Lucro: <b>${lucro > 0 ? '+' : ''}${lucro}</b> ${ico('moeda', 14)} por receita (${entra ? Math.round(lucro / entra * 100) : 0}%)</span>
            </div>
            <p class="det">Sem parar, faz até <b>${porDia * it.produz_qtd}</b> ${itemDe(o.produto, 16)} por dia: <b>+${lucro * porDia}</b> ${ico('moeda', 12)} a mais do que vender os ingredientes, e cada um ainda dá ${o.produto.xp || 0} ${ico('xp', 12)}.</p>
            <h3 class="secao-titulo">Agora</h3>
            <div class="oficina-agora" data-oficina-agora>${htmlOficinaAgora(o)}</div>
            <h3 class="secao-titulo">Estoque: ${o.estoque} receita${o.estoque === 1 ? '' : 's'} guardada${o.estoque === 1 ? '' : 's'}${o.estado === 'trabalhando' ? ' + 1 fazendo' : ''} (cabem ${max})</h3>
            <span class="estoque-barra"><i style="width:${Math.round(ocupado / max * 100)}%"></i></span>
            <p class="det">Guardar tira os ingredientes do celeiro agora (a ração reservada fica). Ela trabalha sozinha até o estoque acabar.</p>
            <div class="estoque-botoes">
                <button type="button" class="botao pequeno creme" data-estoque="1"${pode >= 1 ? '' : ' disabled'}>+1</button>
                <button type="button" class="botao pequeno creme" data-estoque="5"${pode >= 5 ? '' : ' disabled'}>+5</button>
                <button type="button" class="botao pequeno verde" data-estoque="${pode}"${pode >= 1 ? '' : ' disabled'}>Encher${pode ? ` (+${pode})` : ''}</button>
                <button type="button" class="botao pequeno creme" data-estoque="-${o.estoque}"${o.estoque ? '' : ' disabled'}>Tirar tudo</button>
            </div>
            ${!cabe ? '<p class="aviso">Estoque cheio.</p>'
                : falta.length ? `<p class="aviso">Para mais uma receita faltam no celeiro: ${falta.map((f) => `${f.falta} ${itemDe(culturas[f.item] || { id: f.item }, 16)}`).join(', ')}.</p>` : ''}
            ${o.ligada ? `<p class="aviso">${A.htmlItem('cano', 18)} Ligada por cano: quando o estoque acaba, ela busca os ingredientes no celeiro sozinha (2 ${ico('raio', 12)} por receita) e os produtos voltam pelo cano direto para o celeiro.</p>`
                : o.auto ? `<p class="aviso">${A.htmlItem('fabrica_auto', 18)} Com a fábrica automática, quando o estoque acaba ela busca ingredientes no celeiro sozinha (8 ${ico('raio', 12)} por receita) e os produtos vão direto para o celeiro.</p>`
                : S.jogador.nivel >= 16 ? `<p class="det">${A.htmlItem('cano', 16)} Dica: ligue esta oficina com <b>canos de vidro</b> (Construir → Energia) a um canteiro, a um baú ou ao celeiro, e ela se abastece sozinha.</p>` : ''}
            <div class="rodape-painel">
                ${o.prontos ? `<button type="button" class="botao verde" data-oficina-pegar>Pegar ${o.prontos} ${itemDe(o.produto, 18)}</button>` : '<span></span>'}
                <button type="button" class="botao creme" data-fechar>Fechar</button>
            </div>`;
    }

    function coletarItem(x, y) {
        const c = (S.construcoes || []).find((k) => k.x === x && k.y === y);
        if (c && (tipoItem(c.tipo) || {}).efeito === 'biomassa') return alternarGerador(c);
        const o = c && infoOficina(c);
        if (o) return acaoOficina(c, o);
        const p = c && infoProducao(c);
        if (!p) return;
        if (p.falta > 0) return mostrarStatus(`${A.htmlItem(c.tipo, 22)} ${esc(p.it.nome)}: as próximas ${esc(p.produto.nome.toLowerCase())}s ficam prontas em ${fmtTempo(p.falta)}.`);
        c.colhido_em = new Date(agora()).toISOString();   // some o balão na hora
        som.tocar('colher');
        enfileirar([], async () => {
            const r = await rpc('fazenda_coletar', { p_token: token, p_x: x, p_y: y });
            flutuarTile(x, y, `+${r.qtd} ${itemDe(p.produto, 20)}`);
            aplicarEstado(r.estado);
            descreverConstrucao(x, y);   // agora mostra quando fica pronta de novo
        });   // erro (ex.: ainda não está pronta) vai para tratarErro, que recarrega
    }

    // o alcance de um item colocado aparece marcado no chão por uns segundos
    function mostrarAlcanceDe(x, y) {
        const c = ((visita ? visita.construcoes : S.construcoes) || []).find((k) => k.x === x && k.y === y);
        const it = c && tipoItem(c.tipo);
        cena.mostrarAlcance(it && it.raio > 0 ? { x: c.x, y: c.y, raio: it.raio } : null);
    }
    const dicaItem = (it) => (it.raio > 0 ? ' O alcance aparece marcado no chão.' : '') + (visita ? '' : ' Segure 3 s para mudar de lugar.');

    // segurar 3 s num item ou canteiro (fora do modo construir): já pega para levar a outro lugar
    function segurarParaMover(alvo) {
        if (!S || visita || painelAtual || constr.ativo) return;
        let pego = null;
        if (typeof alvo === 'number') {
            const c = S.canteiros.find((k) => k.posicao === alvo);
            if (c) pego = { x: c.x, y: c.y, tipo: 'canteiro', w: 1, h: 1 };
        } else if (alvo && alvo.construcao) {
            const c = construcaoEm(alvo.construcao.x, alvo.construcao.y);
            if (c) pego = { x: c.x, y: c.y, tipo: c.tipo, ...tamanhoItem(c.tipo) };
        }
        if (!pego) return;
        if (navigator.vibrate) navigator.vibrate(30);
        abrirConstrucao();
        constr.modo = 'mover';
        constr.rapido = true;   // depois de soltar no lugar novo, o modo construir fecha sozinho
        constr.movendo = pego;
        desenharPaleta();
        atualizarModo();
        som.tocar('construir');
        mostrarStatus(`${A.htmlItem(pego.tipo, 22)} Pegou! Agora toque no lugar novo (ou no mesmo lugar para desistir).`);
    }

    function descreverConstrucao(x, y) {
        const c = ((visita ? visita.construcoes : S.construcoes) || []).find((k) => k.x === x && k.y === y);
        const it = c && tipoItem(c.tipo);
        if (!it) return;
        const o = !visita && infoOficina(c);
        if (o) {
            const partes = [];
            if (o.prontos) partes.push(`${o.prontos} ${itemDe(o.produto, 16)} pronto(s)`);
            partes.push(o.estado === 'trabalhando' ? `fazendo ${nomeItem(o.it.produz)} (pronto em ${fmtTempo(o.falta)})` : 'parada');
            partes.push(`estoque: ${o.estoque} receita(s)`);
            return mostrarStatus(`${A.htmlItem(c.tipo, 22)} <b>${esc(it.nome)}</b>: ${partes.join(' · ')}. Toque para abrir.`);
        }
        if (!visita) {
            const p = infoProducao(c);
            if (p) {
                return mostrarStatus(p.falta <= 0
                    ? `${A.htmlItem(c.tipo, 22)} ${esc(it.nome)}: ${esc(p.produto.nome.toLowerCase())}s prontas! Toque para colher.`
                    : `${A.htmlItem(c.tipo, 22)} ${esc(it.nome)}: próximas ${esc(p.produto.nome.toLowerCase())}s em ${fmtTempo(p.falta)}.`);
            }
        }
        if (!visita && it.categoria === 'energia') {
            const extra = it.efeito === 'biomassa' ? (c.iniciado_em ? ' <b>Ligado.</b> Toque para desligar.' : ' <b>Desligado.</b> Toque para ligar.')
                : it.efeito === 'bateria' ? ` Agora: ${Math.floor(cargaAgora())} de ${S.energia.capacidade} ⚡.` : '';
            return mostrarStatus(`${A.htmlItem(c.tipo, 22)} <b>${esc(it.nome)}</b>: ${esc(it.descricao)}${extra}${dicaItem(it)}`);
        }
        mostrarStatus(`${A.htmlItem(c.tipo, 22)} <b>${esc(it.nome)}</b>${it.descricao ? ': ' + esc(it.descricao) : ''}${dicaItem(it)}`);
    }

    const cena = A.criarCena(el.canvas, {
        aoCanteiro: (p) => clicarCanteiro(p),
        aoAnimal: (id) => clicarAnimal(id),
        aoTile: (x, y) => tocarTile(x, y),
        aoCeleiro: () => { if (S && !painelAtual) abrirPainel('celeiro'); },
        aoVenda: () => { if (S && !painelAtual) { abaLoja = 'terrenos'; abrirPainel('loja'); } },
        aoLago: () => { if (S && !painelAtual && !visita) pescar(); },
        aoVisitante: () => { if (S && !painelAtual && visitaAgora()) abrirPainel('visitante'); },
        aoConstrucao: (x, y) => {
            if (!S || painelAtual) return;
            descreverConstrucao(x, y);
            mostrarAlcanceDe(x, y);
            if (!visita) coletarItem(x, y);
        },
        aoSegurar: (alvo) => segurarParaMover(alvo),
        aoPassar: (alvo) => {
            if (!S || alvo == null) return;
            if (alvo === 'celeiro') mostrarStatus(`${spr(11, 22)} Celeiro: toque para ver e vender a colheita.`);
            else if (alvo === 'venda') descreverVenda();
            else if (alvo === 'lago') descreverLago();
            else if (alvo === 'visitante') descreverVisitante();
            else if (typeof alvo === 'object' && alvo.construcao) descreverConstrucao(alvo.construcao.x, alvo.construcao.y);
            else if (typeof alvo === 'object' && 'tx' in alvo) descreverTile(alvo.tx, alvo.ty);
            else if (typeof alvo === 'object') descreverAnimal(alvo.animal);
            else descrever(alvo);
        }
    });
    cena.definirVisual(visualCanteiro);
    cena.definirAnimais(visualAnimais);
    cena.definirAjudantes(visualAjudantes);
    cena.definirConstrucoes(visualConstrucoes);
    cena.definirCanteiros(() => ((visita || S) ? (visita || S).canteiros : DEMO_CANTEIROS));

    function descreverVenda() {
        const z = proximaZona();
        if (!z) return;
        mostrarStatus(S.jogador.nivel < z.nivel
            ? `${ico('cadeado', 12)} ${esc(z.nome)}: terreno à venda a partir do nível ${z.nivel}.`
            : `${ico('moeda', 14)} ${esc(z.nome)} à venda por ${moeda(z.custo)}: ${z.w}×${z.h} quadrados e +${z.canteiros || 6} canteiros${z.lago ? ', e um lago com o Bira pescando para você' : ''}. Toque para ver.`);
    }

    /* ---------- Modo construir (abre e fecha pelo botão) ---------- */
    const constr = { ativo: false, modo: 'colocar', tipo: null, movendo: null, aba: 'plantacao' };
    // a cena desenha o alcance da máquina escolhida (irrigador, alarme...)
    const atualizarModo = () => cena.definirModoConstrucao({ ...constr, raio: (tipoItem(constr.tipo) || {}).raio || 0 });
    const NOME_AREA = (x, y) => {
        const dentro = (r) => x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h;
        const [cel, casa, gal, pasto] = A.MAPA.reservas;
        if (!A.noTerreno(x, y)) return 'a mata (compre o terreno na loja)';
        if (dentro(cel)) return 'o celeiro';
        if (dentro(casa)) return 'a casa';
        if (dentro(gal)) return 'o galinheiro';
        if (dentro(pasto)) return 'o pasto';
        if (dentro(A.MAPA.lago)) return 'o lago';
        return 'fora do terreno';
    };
    const canteiroEm = (x, y) => (S.canteiros || []).find((c) => c.x === x && c.y === y);
    const tamanhoItem = (tipo) => {
        const it = tipoItem(tipo);
        return { w: (it && it.largura) || 1, h: (it && it.altura) || 1 };
    };
    // construção que ocupa o quadrado (x, y) — casas ocupam 3x3 a partir do canto
    const construcaoEm = (x, y) => (S.construcoes || []).find((c) => {
        const t = tamanhoItem(c.tipo);
        return x >= c.x && y >= c.y && x < c.x + t.w && y < c.y + t.h;
    });
    function cabeAqui(x, y, w, h, ignorar) {
        for (let dy = 0; dy < h; dy++) {
            for (let dx = 0; dx < w; dx++) {
                if (!A.livre(x + dx, y + dy)) return false;
                const o = construcaoEm(x + dx, y + dy) || canteiroEm(x + dx, y + dy);
                if (o && o !== ignorar) return false;
            }
        }
        return true;
    }
    // quantos dá para ter: limite fixo, ou por terreno (amoreira: 4 na fazenda inicial + 4 por terreno comprado)
    const maxItem = (it) => it.limite || (it.por_terreno ? it.por_terreno * (1 + ((S && S.jogador.zonas) || 0)) : null);
    // quantos já tem (itens do mesmo grupo dividem o limite: o pomar conta todas as árvores frutíferas)
    const quantosTem = (it) => (S.construcoes || []).filter((c) => c.tipo === it.id || (it.grupo && (tipoItem(c.tipo) || {}).grupo === it.grupo)).length;
    const descricaoItem = (it) => (it.id === 'canteiro'
        ? `Lugar de plantar. Você tem ${S.canteiros.length} de ${S.jogador.max_canteiros}.`
        : it.descricao || '');

    function descreverTile(x, y) {
        if (!A.livre(x, y)) return mostrarStatus(`${ico('cadeado', 12)} Aqui fica ${NOME_AREA(x, y)}: não dá para construir.`);
        const ct = canteiroEm(x, y);
        if (ct) {
            if (constr.modo === 'guardar') {
                return mostrarStatus(ct.estado === 'plantado' ? 'Tem planta nesse canteiro: colha ou limpe antes de guardar.' : `${A.htmlItem('canteiro', 22)} Toque para guardar o canteiro (ele volta para o seu limite).`);
            }
            return mostrarStatus(`${A.htmlItem('canteiro', 22)} Canteiro. ${constr.modo === 'mover' ? 'Toque para escolher e depois no lugar novo (a planta vai junto).' : 'Use Mover para mudar de lugar.'}`);
        }
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
        if (c) return mostrarStatus(`${A.htmlItem(c.tipo, 22)} ${esc(it ? it.nome : c.tipo)}. ${it && it.descricao ? esc(it.descricao) + ' ' : ''}Use Mover ou Guardar para mudar.`);
        if (sel && sel.id === 'canteiro') return mostrarStatus(`${A.htmlItem('canteiro', 22)} Toque para colocar um canteiro (sobram ${canteirosLivres()}).`);
        mostrarStatus(sel ? `${A.htmlItem(sel.id, 22)} Toque para colocar ${esc(sel.nome.toLowerCase())} (${moeda(sel.custo)}).` : 'Escolha um item na barra de baixo.');
    }

    function abrirConstrucao() {
        if (!S || visita) return;
        constr.ativo = true;
        constr.modo = 'colocar';
        constr.movendo = null;
        constr.rapido = false;
        document.body.classList.add('construindo');
        el.barraConstr.hidden = false;
        el.barra.hidden = true;
        desenharPaleta();
        atualizarModo();
        mostrarStatus('Modo construir: escolha um item e toque nos quadrados livres. Arraste para ver o terreno.');
        ajustarMargens(true);
    }

    function fecharConstrucao(msg) {
        constr.ativo = false;
        constr.movendo = null;
        constr.rapido = false;
        document.body.classList.remove('construindo');
        el.barraConstr.hidden = true;
        el.barra.hidden = false;
        atualizarModo();
        mostrarStatus(typeof msg === 'string' ? msg : 'Fazenda salva do seu jeito!');
        ajustarMargens(true);
    }

    function desenharPaleta() {
        if (!S || !S.itens) return;
        const abas = [['plantacao', 'Plantação'], ['pomar', 'Pomar'], ['bichos', 'Bichos'], ['oficina', 'Oficinas'], ['maquina', 'Máquinas'], ['energia', 'Energia'], ['caminho', 'Cercas e caminhos'], ['natureza', 'Natureza'], ['objeto', 'Objetos'], ['construcao', 'Casas']];
        el.constrAbas.innerHTML = abas.map(([id, txt]) =>
            `<button type="button" data-constr-aba="${id}" class="${constr.aba === id ? 'ativa' : ''}">${txt}</button>`).join('');
        const lista = constr.aba === 'plantacao' ? [ITEM_CANTEIRO] : S.itens.filter((i) => i.categoria === constr.aba);
        el.constrItens.innerHTML = lista.map((i) => {
            const travado = i.nivel_min > S.jogador.nivel;
            const sel = constr.modo === 'colocar' && constr.tipo === i.id;
            const max = maxItem(i), tem = max ? quantosTem(i) : 0;
            const preco = i.id === 'canteiro' ? `${S.canteiros.length}/${S.jogador.max_canteiros}`
                : max && tem >= max ? (i.por_terreno ? `${tem}/${max}` : 'Já tem') : `${ico('moeda', 11)}${i.custo}`;
            return `<button type="button" class="paleta-item${sel ? ' selecionado' : ''}${travado ? ' travado' : ''}" data-item="${esc(i.id)}" title="${esc(i.nome)}${i.descricao ? ': ' + esc(i.descricao) : ''}">
                ${travado ? ico('cadeado', 18) : A.htmlItem(i.id, 32)}
                <small>${travado ? `Nv ${i.nivel_min}` : preco}</small>
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
        const cant = canteiroEm(x, y);

        if (constr.modo === 'colocar' && constr.tipo === 'canteiro') {
            if (ocupado || cant) return toast(ERROS.lugar_ocupado, 'erro');
            if (!canteirosLivres()) return toast(ERROS.limite_canteiros, 'erro');
            // aparece na hora (com um número provisório); o servidor confirma em seguida
            S.canteiros.push({ posicao: 1000 + S.canteiros.length, x, y, estado: 'vazio' });
            desenharHud();
            som.tocar('construir');
            enfileirar([], async () => {
                const r = await rpc('fazenda_construir', { p_token: token, p_tipo: 'canteiro', p_x: x, p_y: y });
                aplicarEstado(r.estado);
            }).then(() => { desenharPaleta(); if (!S.canteiros.some((c) => c.x === x && c.y === y)) recarregar(); });
            return;
        }

        if (constr.modo === 'colocar') {
            const it = tipoItem(constr.tipo);
            if (!it) return toast('Escolha um item na barra de baixo.');
            const max = maxItem(it), tem = quantosTem(it);
            if (max && tem >= max) return toast(it.por_terreno ? `Seu pomar está cheio (${tem} de ${max} árvores): compre outro terreno (Loja → Terrenos) para plantar mais. São ${it.por_terreno} árvores frutíferas por terreno.` : ERROS.limite_maquina, 'erro');
            const tam = tamanhoItem(it.id);
            if (!cabeAqui(x, y, tam.w, tam.h)) {
                return toast(tam.w > 1 ? `Não cabe aqui: ${esc(it.nome.toLowerCase())} precisa de ${tam.w}×${tam.h} quadrados livres.` : ERROS.lugar_ocupado, 'erro');
            }
            if (it.nivel_min > S.jogador.nivel) return toast(`${esc(it.nome)} libera no nível ${it.nivel_min}.`);
            if (S.jogador.moedas < it.custo) return toast(ERROS.moedas_insuficientes, 'erro');
            // aparece na hora; o servidor confirma em seguida
            S.construcoes.push({ x, y, tipo: it.id });
            S.jogador.moedas -= it.custo;
            desenharHud();
            som.tocar('construir');
            flutuarTile(x, y, `−${it.custo} ${ico('moeda', 16)}`);
            enfileirar([], async () => {
                const r = await rpc('fazenda_construir', { p_token: token, p_tipo: it.id, p_x: x, p_y: y });
                aplicarEstado(r.estado);
            }).then(() => { if (!S.construcoes.some((c) => c.x === x && c.y === y)) recarregar(); });
        } else if (constr.modo === 'mover') {
            if (!constr.movendo) {
                if (cant) {
                    constr.movendo = { x, y, tipo: 'canteiro', w: 1, h: 1 };
                    atualizarModo();
                    return mostrarStatus('Agora toque no lugar novo do canteiro.');
                }
                if (!ocupado) return toast('Toque num item ou canteiro para mover.');
                constr.movendo = { x: ocupado.x, y: ocupado.y, tipo: ocupado.tipo, ...tamanhoItem(ocupado.tipo) };
                atualizarModo();
                return mostrarStatus('Agora toque no lugar novo.');
            }
            const de = constr.movendo;
            const c = de.tipo === 'canteiro' ? canteiroEm(de.x, de.y) : construcaoEm(de.x, de.y);
            if (de.x === x && de.y === y) {
                constr.movendo = null;
                if (constr.rapido) return fecharConstrucao('Ficou no mesmo lugar.');
                return atualizarModo();
            }
            if (!cabeAqui(x, y, de.w, de.h, c)) {
                if (!constr.rapido) { constr.movendo = null; atualizarModo(); }   // no rápido continua na mão
                return toast(ERROS.lugar_ocupado, 'erro');
            }
            constr.movendo = null;
            atualizarModo();
            if (c) { c.x = x; c.y = y; }
            if (constr.rapido) fecharConstrucao(`${A.htmlItem(de.tipo, 22)} Mudou de lugar!`);
            som.tocar('construir');
            enfileirar([], async () => {
                const r = await rpc('fazenda_mover', { p_token: token, p_x: de.x, p_y: de.y, p_nx: x, p_ny: y });
                aplicarEstado(r.estado);
            });
        } else if (constr.modo === 'guardar' && cant) {
            if (cant.estado === 'plantado') return toast('Tem planta nesse canteiro: colha (ou limpe) antes de guardar.', 'erro');
            S.canteiros = S.canteiros.filter((c) => c !== cant);
            som.tocar('construir');
            enfileirar([], async () => {
                const r = await rpc('fazenda_demolir', { p_token: token, p_x: x, p_y: y });
                aplicarEstado(r.estado);
            }).then(() => desenharPaleta());
        } else if (constr.modo === 'guardar') {
            if (!ocupado) return;
            const ax = ocupado.x, ay = ocupado.y;
            S.construcoes = S.construcoes.filter((c) => c !== ocupado);
            enfileirar([], async () => {
                const r = await rpc('fazenda_demolir', { p_token: token, p_x: ax, p_y: ay });
                flutuarTile(ax, ay, `+${r.devolvido} ${ico('moeda', 16)}`);
                som.tocar('moeda');
                aplicarEstado(r.estado);
            });
        }
    }

    const barraDeBaixo = () => (!el.barraConstr.hidden ? el.barraConstr : el.barra.hidden ? null : el.barra);
    const alturaDe = (barra) => (barra ? window.innerHeight - barra.getBoundingClientRect().top : 0);
    function ajustarMargens(manter) {
        const topo = el.hud.hidden ? 24 : el.hud.getBoundingClientRect().bottom + 8;
        const barra = barraDeBaixo();
        cena.definirMargens(Math.round(topo), Math.round(barra ? alturaDe(barra) + 44 : 24), manter === true);
        posicionarStatus();
    }
    // o balão de mensagem fica sempre logo acima da barra de baixo, seja qual for a altura dela
    function posicionarStatus() {
        const barra = barraDeBaixo();
        document.documentElement.style.setProperty('--status-fundo', `${Math.round(barra ? alturaDe(barra) + 10 : 24)}px`);
    }
    window.addEventListener('resize', ajustarMargens);
    // a barra muda de altura (abas que quebram linha, visita...): só o balão acompanha (a câmera fica)
    if ('ResizeObserver' in window) {
        const ro = new ResizeObserver(posicionarStatus);
        ro.observe(el.barra);
        ro.observe(el.barraConstr);
    }

    /* ---------- HUD e status ---------- */
    function desenharHud() {
        const j = S.jogador;
        if (el.construirCont) {
            el.construirCont.textContent = canteirosLivres();
            el.construirCont.hidden = !canteirosLivres();
            el.construirCont.title = 'Canteiros para colocar';
        }
        el.apelido.textContent = j.apelido;
        el.nivel.textContent = j.nivel;
        const faixa = j.xp_proximo - j.xp_nivel;
        const prog = (j.xp - j.xp_nivel) / faixa;
        el.xpBar.style.width = `${Math.min(100, prog * 100)}%`;
        el.xp.textContent = `${j.xp}/${j.xp_proximo}`;
        // a isca: o que vem no próximo nível fica sempre à vista, e a barra brilha quando falta pouco
        const hudAvatar = document.getElementById('hudAvatar');
        if (hudAvatar) hudAvatar.innerHTML = A.htmlAvatar(j.avatar, 40);
        const premio = j.nivel < NIVEL_MAX ? liberaNoNivel(j.nivel + 1)[0] : null;
        if (el.premio) {
            el.premio.hidden = !premio;
            el.premio.innerHTML = premio ? premio.html : '';
        }
        el.xpBar.parentElement.classList.toggle('quase', j.nivel < NIVEL_MAX && prog >= 0.8);
        if (el.hudPerfil) {
            const prox = j.nivel < NIVEL_MAX ? liberaNoNivel(j.nivel + 1).slice(0, 3).map((x) => x.nome).join(', ') : '';
            el.hudPerfil.title = j.nivel < NIVEL_MAX
                ? `Faltam ${j.xp_proximo - j.xp} XP para o nível ${j.nivel + 1}${prox ? ': ' + prox : ''}. Toque para abrir o seu perfil.`
                : 'Nível máximo! Toque para abrir o seu perfil.';
        }
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
        if (el.celeiroContDock) {
            el.celeiroContDock.textContent = totalCeleiro;
            el.celeiroContDock.hidden = !totalCeleiro;
        }
        const prontas = (S.missoes || []).filter((m) => !m.resgatada && m.progresso >= m.alvo).length;
        el.missoesCont.textContent = prontas;
        el.missoesCont.hidden = !prontas;
        atualizarAlertaMenu();

        const k = culturas[semente];
        el.semIcone.innerHTML = k ? spr(A.cultura(k.id).item, 32) : '';
        el.semNome.innerHTML = k ? `${esc(k.nome)} · ${moeda(k.custo)}` : 'Escolher';
    }

    let statusTimer = null;
    function mostrarStatus(html) {
        el.status.innerHTML = html;
        el.status.classList.remove('apagado');
        clearTimeout(statusTimer);
        statusTimer = setTimeout(() => el.status.classList.add('apagado'), 6000);   // não fica tampando a fazenda
    }

    function descreverVisita(c, i) {
        if (i.fase === 'bloqueado') return `${ico('cadeado', 12)} Canteiro bloqueado do vizinho.`;
        if (i.fase === 'vazio' || i.fase === 'arado') return 'Canteiro livre. Nada pra fazer aqui.';
        const item = itemDe(i.k);
        if (i.fase === 'murcho') return `O ${esc(i.k.nome.toLowerCase())} do vizinho murchou.`;
        let txt;
        if (i.fase === 'maduro') {
            if (c.ja_peguei) txt = `${item} Você já pegou desse ${esc(i.k.nome.toLowerCase())}.`;
            else if (protegidoAlarme(c)) txt = `${item} ${esc(i.k.nome)} protegido pelo alarme antiladrão do vizinho.`;
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
        if (!c) return;
        const i = info(c);
        if (visita) return mostrarStatus(descreverVisita(c, i));
        let txt;
        switch (i.fase) {
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
        const bonus = bonusDoCanteiro(c, S);
        if (c.adubado && i.fase !== 'murcho') bonus.push('adubado pelo Seu Zé: +1 item');
        if (bonus.length) txt += ` <span class="bonus-txt">✦ ${bonus.join(' · ')}</span>`;
        mostrarStatus(txt);
    }

    function descreverAnimal(id) {
        if (typeof id === 'string' && id.startsWith('h:')) return descreverAjudante(id.slice(2));
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
            const res = reservaDe(i.t.racao);
            mostrarStatus(`${spr(A.ANIMAL[a.tipo], 22)} ${nome} produzindo ${produto ? esc(produto.nome.toLowerCase()) : ''} · pronto em ${fmtTempo(i.resta)}. Come ${i.t.racao_qtd} ${racao ? itemDe(racao, 16) + esc(nomeRacao(racao, i.t.racao_qtd)) : ''}${res ? ` (guardando ${res})` : ' (reserve na Loja → Animais)'}.`);
        }
    }

    function clicarAnimal(id) {
        if (!S || painelAtual || visita) return;
        if (typeof id === 'string' && id.startsWith('h:')) return descreverAjudante(id.slice(2));
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
            if (r.feitos) som.tocar(acao === 'coletar' ? 'colher' : 'cuidar');
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
    let ultimoEstadoEm = 0;
    function aplicarEstado(estado) {
        const antes = S;
        // longe = primeira carga ou voltou depois de um tempo: aí o relatório dos ajudantes vira aviso
        const longe = !antes || Date.now() - ultimoEstadoEm > 5 * 60 * 1000;
        ultimoEstadoEm = Date.now();
        if (!estado.diario) estado.diario = []; // banco ainda sem o SQL da fase 2
        if (!estado.construcoes) estado.construcoes = [];
        S = estado;
        offset = Date.parse(estado.agora) - Date.now();
        culturas = {};
        for (const k of estado.culturas) culturas[k.id] = k;
        if (!culturas[semente] || culturas[semente].tipo !== 'cultura') semente = 'alface';   // (amora deixou de ser semente)

        if (antes && antes.conquistas && estado.conquistas) {
            const velhas = new Set(antes.conquistas.map((c) => c.id));
            estado.conquistas.filter((c) => !velhas.has(c.id)).forEach((c) => {
                const t = (estado.conquistas_tipos || []).find((x) => x.id === c.id);
                if (!t) return;
                toast(`${ico('medalha', 22)} Conquista: <b>${esc(t.nome)}</b>! +${moeda(t.recompensa)}`, 'festa');
                som.tocar('festa');
            });
        }
        if (antes && estado.jogador.nivel > antes.jogador.nivel) som.tocar('festa');
        if (antes && estado.jogador.nivel > antes.jogador.nivel) {
            nivelComemorar = { de: antes.jogador.nivel, ate: estado.jogador.nivel };
            // abre depois da animação da colheita; com outro painel aberto, só avisa
            if (!painelAtual) setTimeout(() => { if (!painelAtual) abrirPainel('nivel'); }, 700);
            else toast(`${ico('xp', 20)} Nível ${estado.jogador.nivel}! Toque no seu perfil (lá em cima) para ver o que liberou.`, 'festa');
        }
        avisarDiario();
        if (longe) avisarAjudantes(estado);
        else trabalhoDosAjudantes(antes, estado);
        avisarConvites(estado);
        desenharClima();
        agendarAvisos();
        energiaEm = agora();
        desenharEnergia();
        atualizarBotaoAnuncio();
        atualizarLago();
        atualizarGalinheiro();
        atualizarVisitante();
        if (!visita) cena.definirAvatar(estado.jogador.avatar);
        atualizarTerreno();
        desenharHud();
        if (constr.ativo) desenharPaleta();
        if (['loja', 'celeiro', 'missoes', 'oficina', 'energia'].includes(painelAtual)) abrirPainel(painelAtual, true);
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

    // celular: o ☰ mostra a soma dos avisos que ficaram dentro dele (missões e diário)
    function atualizarAlertaMenu() {
        if (!el.menuCont) return;
        const n = [el.missoesCont, el.diarioCont].reduce((soma, b) => soma + (b && !b.hidden ? Number(b.textContent) || 0 : 0), 0);
        el.menuCont.textContent = n;
        el.menuCont.hidden = !n;
    }

    function avisarDiario() {
        const novos = diarioNovos();
        el.diarioCont.textContent = novos.length;
        el.diarioCont.hidden = !novos.length;
        atualizarAlertaMenu();
        // Só avisa por toast o que ainda não foi avisado nesta visita à página
        const ineditos = novos.filter((d) => quando(d) > ultimoAvisoDiario);
        if (!ineditos.length) return;
        ultimoAvisoDiario = Math.max(...ineditos.map(quando));
        const d = ineditos[0];
        toast((d.tipo === 'roubo' ? ico('guaxinim', 20) : ico('coracao', 16)) + ' ' + textoDiario(d) + (ineditos.length > 1 ? ` (+${ineditos.length - 1} no diário)` : ''));
    }

    function marcarDiarioVisto() {
        if (!S || !S.diario.length) return;
        store.set(LS.diarioVisto, String(Math.max(...S.diario.map(quando))));
        avisarDiario();
    }

    /* ---------- Feedback visual ---------- */
    // html: monte com esc() em qualquer texto vindo de jogadores ou do servidor
    function toast(html, tipo) {
        if (tipo === 'erro') som.tocar('erro');
        const t = document.createElement('div');
        t.className = 'toast' + (tipo === 'erro' ? ' erro-t' : tipo === 'festa' ? ' festa' : '');
        t.innerHTML = html;
        el.toasts.appendChild(t);
        while (el.toasts.children.length > (window.innerWidth <= 760 ? 2 : 3)) el.toasts.firstChild.remove();
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
        if (k && !podeEscolher(k)) {
            abrirPainel('loja');
            toast(`${esc(k.nome)} saiu de época. Escolha outra semente.`);
            return null;
        }
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
        if (!acao) return pedirParaArrancar(p);
        let k = null;
        if (acao === 'plantar') {
            k = validarPlantio();
            if (!k) return;
            if (!daEstacao(k) && !naEstufa(canteiro(p))) {
                toast(`${esc(k.nome)} está fora de época: só cresce perto da estufa elétrica.`, 'erro');
                return;
            }
            if (S.jogador.moedas < k.custo) {
                toast(`Faltam moedas para ${esc(k.nome.toLowerCase())}. Venda a colheita no celeiro.`, 'erro');
                return;
            }
        }
        cena.irAte(p);
        executar(acao, [p], k);
    }

    // canteiro crescendo e outra semente escolhida: o 1º toque pergunta, o 2º (em até 3 s) arranca e planta a nova
    let arrancarPendente = null;
    function pedirParaArrancar(p) {
        const c = canteiro(p), i = info(c), k = culturas[semente];
        if (i.fase !== 'crescendo' || !k || k.tipo !== 'cultura' || k.id === c.cultura) return;
        if (!arrancarPendente || arrancarPendente.p !== p || agora() > arrancarPendente.ate) {
            arrancarPendente = { p, ate: agora() + 3000 };
            return mostrarStatus(`${itemDe(i.k)} ${esc(i.k.nome)} crescendo. <b>Toque de novo</b> para arrancar e plantar ${itemDe(k)} ${esc(k.nome.toLowerCase())} no lugar (o que está plantado se perde).`);
        }
        arrancarPendente = null;
        const nova = validarPlantio();
        if (!nova) return;
        if (!daEstacao(nova) && !naEstufa(c)) return toast(`${esc(nova.nome)} está fora de época: só cresce perto da estufa elétrica.`, 'erro');
        if (S.jogador.moedas < nova.custo) return toast(`Faltam moedas para ${esc(nova.nome.toLowerCase())}.`, 'erro');
        cena.irAte(p);
        som.tocar('cuidar');
        executar('arrancar', [p]).then(() => executar('plantar', [p], nova));
    }

    function executar(acao, posicoes, k) {
        return enfileirar(posicoes, async () => {
            const antes = acao === 'colher' ? Object.fromEntries(posicoes.map((p) => [p, { ...canteiro(p) }])) : null;
            let perdas = '';
            const r = await rpc('fazenda_acao', {
                p_token: token,
                p_acao: acao,
                p_posicoes: posicoes,
                p_cultura: acao === 'plantar' ? k.id : null
            });
            if (acao === 'colher') {
                const sol = climaAgora() === 'sol';
                Object.entries(r.colhido).forEach(([pos, qtd], n) => {
                    const c = canteiro(Number(pos));
                    const kc = c && culturas[c.cultura];
                    if (kc) flutuar(Number(pos), `+${qtd} ${itemDe(kc, 20)}${sol ? ` (+1 ${ico('sol', 14)})` : ''} +${kc.xp} ${ico('xp', 16)}`, n * 80);
                });
                perdas = textoPerdas(antes, r.colhido);
            } else if (r.feitos > 0) {
                const fb = FEEDBACK[acao](k);
                const feitos = posicoes.length === 1 ? posicoes : posicoes.filter((p) => !mesmoEstado(p, r.estado));
                feitos.forEach((p, n) => flutuar(p, fb, n * 60));
            }
            if (r.feitos > 0 || Object.keys(r.colhido || {}).length) som.tocar(SOM_DA_ACAO[acao]);
            aplicarEstado(r.estado);
            tutorialEvento(acao);
            if (posicoes.length > 1) resumoMassa(acao, r, k, perdas);
            else {
                descrever(posicoes[0]);
                if (perdas) toast(perdas);
            }
            return r;
        });
    }

    // colheu menos que o normal? diz por quê (problemas deixados e o que vizinhos pegaram)
    function textoPerdas(antes, colhido) {
        let probs = 0, pegos = 0;
        for (const pos of Object.keys(colhido || {})) {
            const c = antes && antes[pos], kc = c && culturas[c.cultura];
            if (!kc) continue;
            const p = (c.erva ? 1 : 0) + (c.praga ? 1 : 0) + (c.seco ? 1 : 0);
            const perdeu = Math.min(p + (c.roubado || 0), kc.rendimento - 1);   // sempre sobra 1
            const doProb = Math.min(p, perdeu);
            probs += doProb;
            pegos += perdeu - doProb;
        }
        if (!probs && !pegos) return '';
        return `Veio ${probs + pegos} a menos: ${[probs && `${probs} por erva, praga ou seca`, pegos && `${pegos} que vizinhos pegaram`].filter(Boolean).join(' e ')}.${probs ? ' Cuide dos canteiros antes de colher!' : ''}`;
    }

    function mesmoEstado(p, novo) {
        const a = canteiro(p), b = novo.canteiros.find((c) => c.posicao === p);
        return a && b && a.estado === b.estado && a.cultura === b.cultura && a.erva === b.erva && a.praga === b.praga && a.seco === b.seco;
    }

    function resumoMassa(acao, r, k, perdas) {
        if (!r.feitos) return;
        if (acao === 'colher') {
            const total = Object.values(r.colhido).reduce((a, b) => a + b, 0);
            toast(`${spr(35, 22)} Colheu ${total} itens de ${r.feitos} canteiro(s)!${perdas ? ' ' + perdas : ''}`);
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
            let ps = posicoesOnde((c, i) => i.fase === 'arado');
            if (!ps.length) return toast('Nenhum canteiro arado livre.');
            const k = validarPlantio();
            if (!k) return;
            if (!daEstacao(k)) {   // fora de época: só os canteiros da estufa
                ps = ps.filter((p) => naEstufa(canteiro(p)));
                if (!ps.length) return toast(`${esc(k.nome)} está fora de época: nenhum canteiro arado perto da estufa elétrica.`);
            }
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
        atualizarTerreno();
        atualizarGalinheiro();
        atualizarVisitante();
        cena.definirAvatar(v.avatar);
        const va = document.getElementById('visitaAvatar');
        if (va) va.innerHTML = A.htmlAvatar(v.avatar, 28);
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
        atualizarTerreno();
        atualizarGalinheiro();
        if (S) cena.definirAvatar(S.jogador.avatar);
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
            if (r.feitos) som.tocar(acao === 'pegar' ? 'colher' : 'cuidar');
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
    /* ---------- Instalar como app (assets/app/instalar.js) ---------- */
    const instalador = window.INSTALAR;
    function htmlInstalar() {
        if (!instalador || instalador.estado() === 'instalado') return '';
        return `<h3 class="secao-titulo">Jogar como app</h3>
                <p>Instale a fazenda: ela ganha um ícone na tela inicial e abre em tela cheia, sem a barra do navegador.</p>
                <p><button type="button" class="botao verde" data-instalar>${spr(109, 22)} Instalar a fazenda</button></p>
                <p class="aviso" data-instalar-dica hidden></p>`;
    }
    if (instalador) instalador.aoMudar(() => { if (painelAtual === 'conta') abrirPainel('conta', true); });

    function abrirPainel(nome, soAtualizar, boasVindas) {
        if (!soAtualizar) ultimoFoco = document.activeElement;
        painelAtual = nome;
        const corpo = el.painelCorpo;
        if (nome === 'loja') {
            if (!soAtualizar) tutorialEvento('loja');
            el.painelTitulo.innerHTML = `${spr(9, 32)} Loja`;
            const abas = `<div class="painel-abas" role="tablist">
                ${[['sementes', 'Sementes'], ['animais', 'Animais'], ['ajudantes', 'Ajudantes'], ['terrenos', 'Terrenos']].map(([id, txt]) =>
                    `<button type="button" role="tab" data-aba-loja="${id}" class="${abaLoja === id ? 'ativa' : ''}">${txt}</button>`).join('')}
            </div>`;
            if (abaLoja === 'animais') corpo.innerHTML = abas + htmlLojaAnimais();
            else if (abaLoja === 'terrenos') corpo.innerHTML = abas + htmlLojaTerrenos();
            else if (abaLoja === 'ajudantes') corpo.innerHTML = abas + htmlLojaAjudantes();
            else corpo.innerHTML = abas + htmlLojaSementes();
        } else if (nome === 'missoes') {
            el.painelTitulo.innerHTML = `${ico('missao', 26)} Missões do dia`;
            corpo.innerHTML = htmlMissoes();
        } else if (nome === 'celeiro') {
            el.painelTitulo.innerHTML = `${spr(11, 32)} Celeiro`;
            // o que tem no celeiro + a ração dos seus animais (mesmo zerada, para dar para reservar antes)
            const itens = S.culturas.filter((k) => S.celeiro[k.id] > 0 || quemCome(k.id));
            if (!itens.some((k) => S.celeiro[k.id] > 0)) {
                corpo.innerHTML = `<p class="vazio-msg">${spr(76, 48)}<br>Seu celeiro está vazio.<br>Colha algo e volte aqui para vender!</p>`;
            } else {
                const bonusVenda = S.jogador.bonus_venda || 0;
                const livreDe = (k) => Math.max(0, naCeleiro(k.id) - reservaDe(k.id));
                const total = Math.floor(itens.reduce((a, k) => a + livreDe(k) * k.venda, 0) * (100 + bonusVenda) / 100);
                corpo.innerHTML = '<div class="lista">' + itens.map((k) => {
                    const livre = livreDe(k), come = quemCome(k.id);
                    return `<div class="item">
                        <span class="ico">${spr(A.cultura(k.id).item, 44)}</span>
                        <span>
                            <span class="nome">${esc(k.nome)} × ${naCeleiro(k.id)}</span>
                            <span class="det"><span>${moeda(k.venda)} cada</span><span>${!reservaDe(k.id) ? `total ${moeda(livre * k.venda)}` : livre ? `vende ${livre}: ${moeda(livre * k.venda)}` : 'tudo guardado'}</span></span>
                            ${k.tipo === 'cultura' ? `<span class="conta-semente">1 semente (${moeda(k.custo)}) rende ${k.rendimento} = ${moeda(k.rendimento * k.venda)}</span>` : ''}
                            ${come ? htmlReserva(k, come) : ''}
                        </span>
                        <button type="button" class="botao pequeno verde" data-vender="${esc(k.id)}"${livre ? '' : ' disabled'}>${livre || !naCeleiro(k.id) ? 'Vender' : 'Guardado'}</button>
                    </div>`;
                }).join('') + `</div>
                    <div class="rodape-painel">
                        <span class="preco">Valor total: ${ico('moeda', 16)} ${total}${bonusVenda ? ` <small class="bonus-txt">(+${bonusVenda}% de bônus)</small>` : ''}</span>
                        <button type="button" class="botao verde" data-vender="*"${total ? '' : ' disabled'}>Vender tudo</button>
                    </div>`;
            }
        } else if (nome === 'conta') {
            el.painelTitulo.innerHTML = boasVindas ? `${spr(83, 32)} Bem-vindo(a) à fazenda!` : `${A.htmlAvatar(S.jogador.avatar, 32)} Perfil`;
            const codigo = store.get(LS.codigo);
            const minhas = (S.conquistas || []).map((c) => c.id);
            corpo.innerHTML = `
                <div class="perfil-avatar">
                    ${A.htmlAvatar(S.jogador.avatar, 64)}
                    <div>
                        <p>Fazendeiro(a): <b>${esc(S.jogador.apelido)}</b> · Nível ${S.jogador.nivel}${S.criado_em ? ` · desde ${desde(S.criado_em)}` : ''}</p>
                        <button type="button" class="botao pequeno verde" data-avatar-editar>Personalizar avatar</button>
                    </div>
                </div>
                ${boasVindas ? '' : `<p><button type="button" class="botao pequeno creme" data-painel-ir="niveis">${ico('xp', 14)} Ver o caminho dos níveis</button></p>
                <p>${spr(83, 18)} Beleza da fazenda: <b>${S.jogador.beleza || 0}</b> · bônus nas vendas: <b>+${S.jogador.bonus_venda || 0}%</b></p>`}
                ${boasVindas ? '' : `
                <h3 class="secao-titulo">Conquistas (${minhas.length}/${(S.conquistas_tipos || []).length})</h3>
                ${htmlConquistas(minhas)}
                <h3 class="secao-titulo">Seus números</h3>
                ${htmlEstatisticas(S.estatisticas)}`}
                <h3 class="secao-titulo">Código de recuperação</h3>
                ${codigo ? `<div class="codigo-box"><code>${esc(codigo)}</code><button type="button" class="botao pequeno creme" data-copiar>Copiar</button></div>` : '<p class="aviso">O código não está salvo neste aparelho. Se você anotou, ele continua valendo.</p>'}
                <p class="aviso">Guarde esse código: é o único jeito de abrir sua fazenda em outro aparelho ou se o navegador for limpo.</p>
                ${htmlInstalar()}
                ${boasVindas ? '' : htmlAvisos()}
                ${boasVindas ? '' : htmlConvite()}
                ${boasVindas ? `<p class="aviso">${ico('ajuda', 14)} Ficou com dúvida? No menu tem <b>Ajuda</b>, com tudo o que dá para fazer na fazenda.</p>` : ''}
                <p class="aviso"><a href="privacidade.html" target="_blank" rel="noopener">Política de privacidade</a>: o que a fazenda guarda e como funcionam os anúncios.</p>
                <div class="rodape-painel">
                    ${boasVindas
                        ? '<span></span><button type="button" class="botao verde" data-fechar>Começar a jogar</button>'
                        : `<button type="button" class="botao creme" data-painel-ir="ajuda">${ico('ajuda', 16)} Como jogar</button>
                    <button type="button" class="botao creme" data-som>${som.mudo ? 'Ligar sons' : 'Desligar sons'}</button>
                    <a class="botao creme" href="indexversao2.html">Voltar ao portfólio</a>
                    <button type="button" class="botao vermelho" data-sair>Sair desta fazenda</button>`}
                </div>`;
        } else if (nome === 'avatar') {
            el.painelTitulo.innerHTML = `${A.htmlAvatar(rascunhoAvatar, 32)} Seu avatar`;
            corpo.innerHTML = htmlEditorAvatar();
        } else if (nome === 'visitante') {
            const v = visitaAgora();
            if (!v) { fecharPainel(); return; }
            el.painelTitulo.innerHTML = `${spr(VISITAS[v.tipo].sprite, 32, 'dungeon')} Visita na porteira`;
            corpo.innerHTML = htmlVisitante(v);
        } else if (nome === 'oficina') {
            const c = oficinaDoPainel(), o = c && infoOficina(c);
            if (!o) { fecharPainel(); return; }
            el.painelTitulo.innerHTML = `${A.htmlItem(c.tipo, 32)} ${esc(o.it.nome)}`;
            corpo.innerHTML = htmlOficina(c, o);
        } else if (nome === 'energia') {
            el.painelTitulo.innerHTML = `${ico('raio', 26)} Energia e máquinas`;
            corpo.innerHTML = htmlEnergia();
        } else if (nome === 'ajuda') {
            el.painelTitulo.innerHTML = `${ico('ajuda', 26)} Como jogar`;
            corpo.innerHTML = `
                <ul class="ajuda">
                    <li>Toque num canteiro e ele faz a ação certa: <b>arar</b>, <b>plantar</b>, <b>cuidar</b> ou <b>colher</b>. Para trocar o que está crescendo, escolha outra semente e toque duas vezes no canteiro: ele arranca e planta a nova.</li>
                    <li>As plantas crescem em tempo real, mesmo com a página fechada.</li>
                    <li>Aparecem ${ico('erva', 14)} ervas, ${ico('praga', 14)} pragas e ${ico('seco', 12)} seca: cada problema deixado custa 1 item na colheita.</li>
                    <li>Depois de madura, a planta <b>murcha</b> se ficar tempo demais sem colher.</li>
                    <li>Toque no <b>celeiro</b> para vender a colheita, compre sementes melhores e suba de nível para ganhar canteiros.</li>
                    <li>Os canteiros ficam onde você quiser: <b>Construir → Plantação</b> para colocar, <b>Mover</b> para mudar de lugar. Lado a lado eles viram fileiras.</li>
                    <li>Na loja, aba <b>Terrenos</b>, compre pedaços da mata em volta para a fazenda crescer (e ganhar mais canteiros). São 6 terrenos, e os três últimos são grandes.</li>
                    <li>Todo item do Construir faz alguma coisa: evita seca, praga ou erva, adianta o crescimento, dá itens e XP extras, protege dos vizinhos ou aumenta a <b>beleza</b> (bônus nas vendas). Toque num item para ver o que ele faz.</li>
                    <li>Na loja, aba <b>Ajudantes</b>: contrate pessoas que aram, plantam, cuidam, colhem e tratam dos animais sozinhas (12 tarefas por hora no nível 1, 30 no 2 e 90 no 3). O <b>Seu Zé</b> também aduba os canteiros crescendo: +1 item na colheita. Com a fazenda aberta, dá para ver cada um indo até onde trabalhou.</li>
                    <li>Em <b>Construir → Oficinas</b> tem padaria, queijaria, pipocaria e outras. Toque nela para abrir o painel: guarde ingredientes no <b>estoque</b> (até 10 receitas) e ela trabalha sozinha, uma receita atrás da outra. O painel mostra quanto valem os ingredientes, quanto vale o produto e o <b>lucro</b>. Quando aparecer o balão, toque para pegar.</li>
                    <li>Fruta só dá no pé: em <b>Construir → Pomar</b> tem amoreira, laranjeira, limoeiro, goiabeira e, do nível 26 ao 29, mangueira, abacateiro, cacaueiro e jabuticabeira. Cada árvore dá frutas sozinha: quando aparecer o balão, toque nela para colher. São 2 árvores frutíferas por terreno: quanto mais terreno, maior o pomar.</li>
                    <li>Em <b>Construir → Máquinas</b>: irrigador, pulverizador e robô capinador evitam seca, pragas e ervas por perto; o alarme protege dos vizinhos; trator e colheitadeira ajudam na fazenda toda.</li>
                    <li>Na loja tem <b>animais</b> (até 5 de cada; cada um sai 50% mais caro que o anterior). Em <b>Construir → Bichos</b> tem um cercado para cada espécie: coloque onde quiser e eles se mudam para lá. Dê ração (sai do celeiro) e colete ovos, leite e lã. No celeiro, <b>Reservar</b> guarda a ração deles para não ir junto no "Vender tudo".</li>
                    <li>No botão <b>Construir</b> você coloca cercas, caminhos, árvores, flores e objetos onde quiser. Toque em <b>Pronto</b> para fechar.</li>
                    <li>Toque num item já colocado para ver o que ele faz; o <b>alcance</b> dele (irrigador, alarme, estufa...) aparece marcado no chão. <b>Segure o dedo 3 segundos</b> num item ou canteiro para pegar e levar para outro lugar.</li>
                    <li>A semana tem as 4 <b>estações</b> (42 horas cada), e cada uma muda a cara da fazenda (pétalas na primavera, grama quente no verão, folhas caindo no outono, neve no inverno) e tem uma semente só dela: morango, melancia, abóbora e repolho. O <b>clima</b> muda várias vezes por dia: sol dá +1 na colheita, chuva rega tudo, onda de calor seca mais, nublado não traz problema novo e ventania espalha pragas. Toque no clima, lá em cima, para ver até quando ele vai.</li>
                    <li>No nível 16 chegam os <b>canos de vidro</b> (Construir → Energia, 5 cada): ligue uma oficina com canos a um canteiro, a um baú ou ao celeiro e ela busca os ingredientes sozinha (2 ⚡ por receita); dá para ver os itens passando dentro do cano. O <b>baú</b> encostado num bloco de canteiros colhe sozinho o que amadurece, e encostado num cercado coleta e alimenta os bichos (1 ⚡ cada): com baú, canos e oficinas a produção fica toda automática.</li>
                    <li>Do nível 16 em diante vem a <b>energia</b> ${ico('raio', 14)}: painel solar, turbina, gerador a biomassa e reator enchem as baterias, e as máquinas elétricas (estufa, triturador, fábrica automática, robô, aspersor) trabalham sozinhas gastando energia. Toque no ${ico('raio', 12)} lá em cima (ou no botão abaixo) para ver o que cada uma faz.</li>
                    ${ANUNCIO.ligado || ehLocal ? `<li>Quando aparecer o botão <b>+30 min</b>, assista a um anúncio até o fim e tudo o que está em andamento (plantas, animais, oficinas, ajudantes e energia) adianta 30 minutos.</li>` : ''}
                    <li>No Perfil (ou em Vizinhos) tem o seu <b>link de convite</b>: quem criar uma fazenda por ele ganha moedas, e você também.</li>
                    <li>No <b>Vale do sudeste</b> (terreno 3) tem um lago: o pescador <b>Bira</b> tira um peixe a cada 30 minutos, até 16 no cesto. Toque no lago para pegar. Quanto mais raro, mais vale, e o lendário <b>Peixe do Velho Chico</b> sai em 1% das vezes (2% com a estátua do nível 30).</li>
                    <li>A cada 3 horas chega uma <b>visita na porteira</b>, do lado da casa (do nível 3 em diante): o feirante, a doceira e o caminhoneiro compram algo da fazenda pagando bem mais que o celeiro, e a mascate vende adubo. Toque nela para conversar.</li>
                    <li>Cumpra as <b>missões do dia</b> para ganhar moedas e XP extras.</li>
                    <li>Cada nível libera coisas novas e dá um presente de moedas. Toque no seu nome, lá em cima, para abrir o <b>Perfil</b>: lá estão o <b>caminho dos níveis</b>, as conquistas, o seu convite e o botão de <b>personalizar o avatar</b> (fazendeiro, fazendeira, rapaz, mago, viking ou cavaleiro, com as cores que quiser).</li>
                    <li>Em <b>Vizinhos</b> você visita outras fazendas: <b>pega</b> um pouco da colheita madura ou <b>ajuda</b> com os problemas e ganha XP.</li>
                </ul>
                <div class="rodape-painel">
                    <button type="button" class="botao creme" data-tutorial>Ver o tutorial</button>
                    <button type="button" class="botao creme" data-painel-ir="energia">${ico('raio', 14)} Energia e máquinas</button>
                    <button type="button" class="botao verde" data-fechar>Entendi</button>
                </div>`;
        } else if (nome === 'nivel' && nivelComemorar) {
            const { de, ate } = nivelComemorar;
            el.painelTitulo.innerHTML = `${ico('xp', 26)} Nível ${ate}!`;
            let novos = [], canteiros = 0, moedas = 0;
            for (let n = de + 1; n <= ate; n++) {
                novos = novos.concat(liberaNoNivel(n));
                const x = extrasDoNivel(n);
                canteiros += x.canteiros; moedas += x.moedas;
            }
            const proximo = ate < NIVEL_MAX ? liberaNoNivel(ate + 1) : [];
            corpo.innerHTML = `
                <div class="nivel-festa"><span class="nivel-numero">${ate}</span><p>Sua fazenda subiu de nível!</p></div>
                <div class="nivel-ganhos">
                    ${moedas ? `<span class="ganho">${ico('moeda', 18)} Presente: <b>+${moedas}</b> moedas</span>` : ''}
                    ${canteiros ? `<span class="ganho">${A.htmlItem('canteiro', 20)} <b>+${canteiros}</b> canteiros para colocar (Construir → Plantação)</span>` : ''}
                </div>
                ${novos.length ? `<h3 class="secao-titulo">Liberado agora</h3><div class="chips">${chipsHtml(novos)}</div>` : ''}
                ${proximo.length ? `<h3 class="secao-titulo">No nível ${ate + 1}</h3><div class="chips chips-futuro">${chipsHtml(proximo)}</div>` : ''}
                <div class="rodape-painel">
                    <button type="button" class="botao creme" data-painel-ir="niveis">Ver todos os níveis</button>
                    <button type="button" class="botao verde" data-fechar>Bora jogar!</button>
                </div>`;
        } else if (nome === 'lendario') {
            const k = culturas.velho_chico || { id: 'velho_chico', nome: 'Peixe do Velho Chico', venda: 2500 };
            el.painelTitulo.innerHTML = `${itemDe(k, 32)} Peixe do Velho Chico!`;
            corpo.innerHTML = `
                <div class="lendario">
                    <div class="lendario-peixe">${itemDe(k, 96)}</div>
                    <p><b>LENDÁRIO!</b> O peixe dourado do Velho Chico caiu no anzol do Bira. Só 1 em cada ${S.lago && S.lago.estatua ? 50 : 100} peixes é ele.</p>
                    <p>Ele já está no celeiro e vale ${moeda(k.venda)}.</p>
                </div>
                <div class="rodape-painel"><span></span><button type="button" class="botao verde" data-fechar>Que pescaria!</button></div>`;
        } else if (nome === 'niveis') {
            const j = S.jogador;
            el.painelTitulo.innerHTML = `${ico('xp', 26)} Caminho dos níveis`;
            const falta = j.xp_proximo - j.xp;
            corpo.innerHTML = `
                <p>Você está no nível <b>${j.nivel}</b>${j.nivel < NIVEL_MAX ? `: faltam <b>${falta}</b> ${ico('xp', 14)} para o próximo.` : '. Fazenda completa!'}</p>
                <p class="aviso">Colher, cuidar dos canteiros, os animais e as missões dão XP. Cada nível traz um presente de moedas. Do nível 10 em diante cada nível pede mais XP que o anterior, e o presente dobra.</p>
                <ol class="caminho">${Array.from({ length: NIVEL_MAX }, (_, i) => i + 1).map((n) => {
                    const x = extrasDoNivel(n);
                    const lista = liberaNoNivel(n);
                    const estado = n < j.nivel ? 'feito' : n === j.nivel ? 'atual' : 'futuro';
                    return `<li class="degrau ${estado}">
                        <span class="degrau-nv">${n < j.nivel ? ico('check', 14) : n}</span>
                        <div class="chips">${chipsHtml(lista)}
                            ${x.canteiros ? `<span class="chip extra">${A.htmlItem('canteiro', 18)}<span>+${x.canteiros} canteiros</span></span>` : ''}
                            ${x.moedas ? `<span class="chip extra">${ico('moeda', 14)}<span>+${x.moedas}</span></span>` : ''}
                        </div>
                    </li>`;
                }).join('')}</ol>`;
            // começa mostrando o nível atual
            requestAnimationFrame(() => {
                const a = corpo.querySelector('.degrau.atual'), cartao = corpo.closest('.cartao');
                if (a && cartao) cartao.scrollTop += a.getBoundingClientRect().top - cartao.getBoundingClientRect().top - cartao.clientHeight / 3;
            });
        } else if (nome === 'perfilVizinho' && visita) {
            const p = visita.perfil || {};
            el.painelTitulo.innerHTML = `${A.htmlAvatar(visita.avatar, 32)} ${esc(visita.apelido)}`;
            corpo.innerHTML = `
                <p>Nível <b>${visita.nivel}</b>${p.criado_em ? ` · fazendeiro(a) desde ${desde(p.criado_em)}` : ''}</p>
                <h3 class="secao-titulo">Conquistas (${(p.conquistas || []).length}/${(S.conquistas_tipos || []).length})</h3>
                ${htmlConquistas(p.conquistas || [])}
                <h3 class="secao-titulo">Números</h3>
                ${htmlEstatisticas(p.estatisticas)}`;
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
                    <button type="button" class="botao creme" data-convite-abrir>Convidar amigos</button>
                    <button type="button" class="botao verde" data-visitar="">Visitar alguém</button>
                </div>`;
            preencherVizinhos();
        }
        if (!soAtualizar) {
            el.painel.classList.add('aberto');
            el.painelFechar.focus();
        }
    }

    /* ---- perfil: conquistas e números ---- */
    function htmlConquistas(obtidas) {
        const tipos = (S && S.conquistas_tipos) || [];
        if (!tipos.length) return '<p class="det">As conquistas aparecem quando o banco estiver atualizado.</p>';
        // as já obtidas aparecem primeiro
        const ordenadas = [...tipos].sort((a, b) => obtidas.includes(b.id) - obtidas.includes(a.id));
        return '<div class="medalhas">' + ordenadas.map((t) => {
            const ok = obtidas.includes(t.id);
            return `<div class="medalha${ok ? '' : ' trancada'}">
                ${ico(ok ? 'medalha' : 'medalha_off', 24)}
                <span><b>${esc(t.nome)}</b><small>${esc(t.descricao)}${ok ? '' : ` · prêmio ${moeda(t.recompensa)}`}</small></span>
            </div>`;
        }).join('') + '</div>';
    }

    function htmlEstatisticas(e) {
        e = e || {};
        const linhas = [
            ['colher', 'itens colhidos'], ['plantar', 'sementes plantadas'], ['cuidar', 'problemas resolvidos'],
            ['vender', 'moedas em vendas'], ['animal', 'produtos dos animais'], ['ajudar', 'ajudas a vizinhos'],
            ['pegar', 'itens pegos de vizinhos'], ['anuncios', 'anúncios assistidos']
        ].filter(([k]) => k !== 'anuncios' || e.anuncios);
        return '<div class="estatisticas">' + linhas.map(([k, txt]) => `<div><b>${e[k] || 0}</b><span>${txt}</span></div>`).join('') + '</div>';
    }

    const desde = (iso) => iso ? new Date(iso).toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' }) : '';

    /* ---- conteúdo da loja e das missões ---- */
    function htmlLojaSementes() {
        return '<div class="lista">' + S.culturas.filter((k) => k.tipo !== 'produto').map((k) => {
            const travada = k.nivel_min > S.jogador.nivel || !podeEscolher(k);
            const lucro = k.venda * k.rendimento - k.custo;
            return `<button type="button" class="item${k.id === semente ? ' selecionada' : ''}${travada ? ' travada' : ''}" data-semente="${esc(k.id)}" ${travada ? 'aria-disabled="true"' : ''}>
                <span class="ico${k.nivel_min <= S.jogador.nivel && travada ? ' fora' : ''}">${k.nivel_min > S.jogador.nivel ? ico('cadeado', 28) : spr(A.cultura(k.id).item, 44)}</span>
                <span>
                    <span class="nome">${esc(k.nome)}${k.estacao ? ` <small class="tag-estacao${daEstacao(k) ? ' agora' : temEstufa() ? ' estufa' : ''}">${daEstacao(k) ? 'da estação!' : temEstufa() ? 'só na estufa' : 'só ' + naEstacao(k.estacao) + (faltaParaEstacao(k.estacao) ? ' · em ' + fmtTempo(faltaParaEstacao(k.estacao)) : '')}</small>` : ''}</span>
                    <span class="det">
                        <span>cresce em ${fmtDuracao(k.tempo_seg)}</span>
                        <span>+${k.xp} ${ico('xp', 13)} por colheita</span>
                    </span>
                    <span class="conta-semente">1 semente (${moeda(k.custo)}) → colhe ${k.rendimento} × ${moeda(k.venda)} = ${moeda(k.rendimento * k.venda)} → <b>lucro +${lucro}</b></span>
                </span>
                <span class="preco">${k.nivel_min > S.jogador.nivel ? `Nível ${k.nivel_min}` : !podeEscolher(k) ? 'Fora de época' : `${ico('moeda', 16)} ${k.custo}`}</span>
            </button>`;
        }).join('') + '</div><p class="aviso">Uma semente planta um canteiro, que colhe vários. Cada erva, praga ou seca deixada no canteiro tira 1 da colheita. Escolha uma semente e toque nos canteiros arados (ou em “Plantar tudo”).</p>';
    }

    // cada bicho da mesma espécie sai 50% mais caro que o anterior (igual a fazenda_comprar)
    const precoAnimal = (t, tem) => Math.round(t.custo * Math.pow(1.5, tem));
    const cercadoDe = (bicho) => Object.keys(A.CERCADOS).find((id) => A.CERCADOS[id].bicho === bicho);
    const temCercado = (bicho) => (S.construcoes || []).some((c) => c.tipo === cercadoDe(bicho));
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
                        <span>come ${t.racao_qtd} ${racao ? itemDe(racao, 16) + esc(nomeRacao(racao, t.racao_qtd)) : ''}</span>
                        <span>dá ${produto ? itemDe(produto, 16) + esc(produto.nome.toLowerCase()) : ''} a cada ${fmtDuracao(t.tempo_seg)}</span>
                        <span>vende ${moeda(produto ? produto.venda : 0)}</span>
                    </span>
                    ${travado ? '' : `<span class="det"><span>${temCercado(t.id) ? `${A.htmlItem(cercadoDe(t.id), 16)} tem cercado próprio` : `sem cercado: coloque o ${esc(((tipoItem(cercadoDe(t.id)) || {}).nome || 'cercado').toLowerCase())} em Construir → Bichos`}</span>${tem && !cheio ? `<span>o próximo sai 50% mais caro</span>` : ''}</span>`}
                </span>
                ${travado ? `<span class="preco">Nível ${t.nivel_min}</span>`
                    : cheio ? '<span class="preco">Completo</span>'
                    : `<button type="button" class="botao pequeno verde" data-comprar="animal:${esc(t.id)}">${ico('moeda', 14)} ${precoAnimal(t, tem).toLocaleString('pt-BR')}</button>`}
            </div>`;
        }).join('') + '</div>' + htmlRacoes() + '<p class="aviso">Toque no animal com fome para dar a ração (sai do seu celeiro) e volte para coletar o produto. Cada bicho pode ter o seu cercado (Construir → Bichos): quem tem cercado sai do galinheiro e do pasto. Até 5 de cada; cada um sai 50% mais caro que o anterior.</p>';
    }
    // "1 alface", "2 alfaces", "2 beterrabas"...
    const nomeRacao = (k, n) => { const nome = k.nome.toLowerCase(); return n === 1 || /s$/.test(nome) ? nome : nome + 's'; };
    // a comida dos seus bichos: quanto tem no celeiro e quanto está guardado só para eles
    function htmlRacoes() {
        const itens = [...new Set((S.animais_tipos || []).filter((t) => S.animais.some((a) => a.tipo === t.id)).map((t) => t.racao))];
        if (!itens.length) return '';
        return `<h3 class="secao-titulo">Comida dos seus bichos</h3>
            <p class="det">Reservar guarda a comida no celeiro só para eles: o "Vender tudo" e as oficinas não levam.</p>
            <div class="lista">${itens.map((id) => {
                const k = culturas[id], come = quemCome(id);
                if (!k || !come) return '';
                return `<div class="item">
                    <span class="ico">${spr(A.cultura(id).item, 40)}</span>
                    <span><span class="nome">${esc(k.nome)} <small class="qtd">${naCeleiro(id)} no celeiro</small></span>
                        <span class="det"><span>${esc(come.nomes)} ${/^1 /.test(come.nomes) && !come.nomes.includes(' e ') ? 'come' : 'comem'} ${come.porRefeicao} por refeição</span></span>
                        ${htmlReserva(k, come)}</span>
                </div>`;
            }).join('')}</div>`;
    }

    function htmlLojaAjudantes() {
        const tipos = S.ajudantes_tipos || [];
        if (!tipos.length) return '<p class="vazio-msg">Os ajudantes chegam em breve.</p>';
        return '<div class="lista">' + tipos.map((t) => {
            const h = meuAjudante(t.id), nivel = h ? h.nivel : 0;
            const travado = !h && t.nivel_min > S.jogador.nivel;
            const estrelas = [1, 2, 3].map((n) => (n <= nivel ? '★' : '☆')).join('');
            const ritmo = nivel ? `${RITMO[nivel]} por hora${nivel < 3 ? ` (nível ${nivel + 1}: ${RITMO[nivel + 1]})` : ''}` : `${RITMO[1]} por hora`;
            const acao = travado ? `<span class="preco">Nível ${t.nivel_min}</span>`
                : nivel >= 3 ? '<span class="preco">Nível máximo</span>'
                : `<button type="button" class="botao pequeno verde" data-contratar="${esc(t.id)}">${nivel ? 'Evoluir' : 'Contratar'}<br>${ico('moeda', 14)} ${custoAjudante(t, nivel)}</button>`;
            return `<div class="item${travado ? ' travada' : ''}">
                <span class="ico">${travado ? ico('cadeado', 28) : retratoAjudante(t.id, 44)}</span>
                <span>
                    <span class="nome">${esc(t.nome)} <small class="qtd">${esc(t.papel)}</small></span>
                    <span class="det"><span>${esc(t.descricao)}</span></span>
                    <span class="det"><span class="estrelas">${nivel ? estrelas : ''}</span><span>${ritmo}</span></span>
                </span>
                ${acao}
            </div>`;
        }).join('') + '</div><p class="aviso">Ajudantes trabalham sozinhos, até com a fazenda fechada (guardam até 8 h de trabalho). Não dão XP: o XP é seu. Quem cuida de animais precisa de ração no celeiro.</p>';
    }

    function htmlLojaTerrenos() {
        const lista = zonasVenda();
        if (!lista.length) return '<p class="vazio-msg">Os terrenos chegam em breve.</p>';
        const tem = S.jogador.zonas || 0;
        return '<div class="lista">' + lista.map((z) => {
            const comprado = z.n <= tem;
            const proximo = z.n === tem + 1;
            const travado = !comprado && (!proximo || S.jogador.nivel < z.nivel);
            return `<div class="item${travado ? ' travada' : ''}">
                <span class="ico">${travado ? ico('cadeado', 28) : spr(comprado ? 1 : 39, 44)}</span>
                <span>
                    <span class="nome">${esc(z.nome)}</span>
                    <span class="det"><span>${z.w}×${z.h} quadrados</span><span>+${z.canteiros || 6} canteiros</span>${z.lago ? '<span>com lago e pescador!</span>' : ''}</span>
                </span>
                ${comprado ? '<span class="preco">Comprado</span>'
                    : !proximo ? `<span class="preco">Depois do ${z.n - 1}</span>`
                    : S.jogador.nivel < z.nivel ? `<span class="preco">Nível ${z.nivel}</span>`
                    : `<button type="button" class="botao pequeno verde" data-comprar="terreno:${z.n}">${ico('moeda', 14)} ${z.custo}</button>`}
            </div>`;
        }).join('') + '</div><p class="aviso">Cada terreno abre um pedaço da mata em volta: mais espaço para canteiros, cercados, máquinas e enfeites, e mais canteiros no seu limite. Os três últimos são grandes. Também dá para tocar na placa no mapa.</p>';
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
                        <span>${d.tipo === 'roubo' ? ico('guaxinim', 24) : ico('coracao', 20)}</span>
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
                            <span class="nome">${A.htmlAvatar(j.avatar, 24)} ${esc(j.apelido)}${j.eu ? ' (você)' : ''}</span>
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
            if (!podeEscolher(k)) return toast(`${itemDe(k, 18)} ${esc(k.nome)} só dá ${naEstacao(k.estacao)}, que começa em ${fmtTempo(faltaParaEstacao(k.estacao))}.`);
            if (!daEstacao(k)) toast(`${itemDe(k, 18)} Fora de época: ${esc(k.nome.toLowerCase())} só cresce perto da estufa elétrica.`);
            semente = k.id;
            store.set(LS.semente, semente);
            desenharHud();
            fecharPainel();
            toast(`Semente escolhida: ${itemDe(k)} ${esc(k.nome)}`);
            return;
        }
        if (e.target.closest('[data-avatar-editar]')) {
            rascunhoAvatar = { tipo: 'fazendeiro', pele: 0, cabelo: 0, roupa: 0, calca: 0, chapeu: 0, ...A.normalizarAvatar(S.jogador.avatar) };
            abrirPainel('avatar');
            return;
        }
        const av = e.target.closest('[data-av]');
        if (av && rascunhoAvatar) {
            const [chave, valor] = av.dataset.av.split(':');
            rascunhoAvatar[chave] = chave === 'tipo' ? valor : Number(valor);
            abrirPainel('avatar', true);
            return;
        }
        if (e.target.closest('[data-av-salvar]') && rascunhoAvatar) {
            const novo = { ...rascunhoAvatar };
            const preco = temAvatar(novo.tipo) ? 0 : precoAvatar(novo.tipo);
            if (preco > S.jogador.moedas) return toast(ERROS.moedas_insuficientes, 'erro');
            if (preco) { S.jogador.moedas -= preco; S.jogador.avatares = [...(S.jogador.avatares || []), novo.tipo]; som.tocar('moeda'); }
            S.jogador.avatar = novo;       // aparece na hora; o servidor confirma
            cena.definirAvatar(novo);
            desenharHud();
            abrirPainel('conta');
            enfileirar([], async () => {
                const r = await rpc('fazenda_avatar', { p_token: token, p_avatar: novo });
                aplicarEstado(r.estado);
                toast(r.pagou ? `${A.htmlAvatar(novo, 22)} Comprou o personagem por ${ico('moeda', 14)} ${r.pagou.toLocaleString('pt-BR')}! Agora ele é seu para sempre.` : `${A.htmlAvatar(novo, 22)} Avatar salvo! Os vizinhos já veem o novo visual.`, r.pagou ? 'festa' : undefined);
            });
            return;
        }
        const at = e.target.closest('[data-atender]');
        if (at) { atender(at.dataset.atender === '1'); return; }
        const est = e.target.closest('[data-estoque]');
        if (est && oficinaAberta) {
            const n = Number(est.dataset.estoque);
            if (!n) return;
            est.disabled = true;
            const { x, y } = oficinaAberta;
            enfileirar([], async () => {
                const r = await rpc('fazenda_estoque', { p_token: token, p_x: x, p_y: y, p_receitas: n });
                som.tocar(n > 0 ? 'construir' : 'moeda');
                toast(r.receitas > 0 ? `Guardou ${r.receitas} receita(s) no estoque.` : `${-r.receitas} receita(s) voltaram para o celeiro.`);
                aplicarEstado(r.estado);
            });
            return;
        }
        if (e.target.closest('[data-oficina-pegar]')) {
            const c = oficinaDoPainel(), o = c && infoOficina(c);
            if (o && o.prontos) pegarOficina(c, o);
            return;
        }
        const resv = e.target.closest('[data-reserva]');
        if (resv) {
            const [item, ref] = resv.dataset.reserva.split(':');
            const come = quemCome(item);
            const qtd = come ? Math.max(0, Math.min(MAX_REFEICOES, Number(ref))) * come.porRefeicao : 0;
            // aparece na hora; o servidor confirma
            S.reservas = { ...(S.reservas || {}), [item]: qtd };
            if (!qtd) delete S.reservas[item];
            abrirPainel(painelAtual || 'celeiro', true);
            enfileirar([], async () => {
                const r = await rpc('fazenda_reservar', { p_token: token, p_item: item, p_quantidade: qtd });
                aplicarEstado(r.estado);
            });
            return;
        }
        const vend = e.target.closest('[data-vender]');
        if (vend) {
            vend.disabled = true;
            const item = vend.dataset.vender === '*' ? null : vend.dataset.vender;
            enfileirar([], async () => {
                const r = await rpc('fazenda_vender', { p_token: token, p_item: item, p_quantidade: null });
                const guardou = Object.keys(S.reservas || {}).length ? ' A ração dos animais ficou guardada.' : '';
                if (r.ganho > 0) { toast(`Vendeu por ${ico('moeda', 16)} ${r.ganho}!${guardou}`); som.tocar('moeda'); tutorialEvento('vender'); }
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
        const contr = e.target.closest('[data-contratar]');
        if (contr) {
            const t = tipoAjudante(contr.dataset.contratar), h = meuAjudante(t.id);
            if (S.jogador.moedas < custoAjudante(t, h ? h.nivel : 0)) return toast(ERROS.moedas_insuficientes, 'erro');
            contr.disabled = true;
            enfileirar([], async () => {
                const r = await rpc('fazenda_contratar', { p_token: token, p_tipo: t.id });
                aplicarEstado(r.estado);
                toast(r.nivel === 1
                    ? `${retratoAjudante(t.id, 22)} ${esc(t.nome)} começou a trabalhar na sua fazenda!`
                    : `${retratoAjudante(t.id, 22)} ${esc(t.nome)} subiu para o nível ${r.nivel}: agora faz ${RITMO[r.nivel]} por hora.`, 'festa');
                som.tocar('festa');
                if (painelAtual === 'loja') abrirPainel('loja', true);
            }).finally(() => { contr.disabled = false; });
            return;
        }
        const comp = e.target.closest('[data-comprar]');
        if (comp) {
            const [categoria, tipo] = comp.dataset.comprar.split(':');
            comp.disabled = true;
            enfileirar([], async () => {
                const r = await rpc('fazenda_comprar', { p_token: token, p_categoria: categoria, p_tipo: tipo });
                aplicarEstado(r.estado);
                if (categoria === 'terreno') {
                    const z = A.ZONAS.find((k) => k.n === Number(tipo));
                    const nome = (zonasVenda().find((k) => k.n === Number(tipo)) || {}).nome || 'Terreno novo';
                    toast(`${spr(39, 22)} ${esc(nome)} é seu! A fazenda cresceu e ganhou +${(zonasVenda().find((k) => k.n === Number(tipo)) || {}).canteiros || 6} canteiros.`, 'festa');
                    som.tocar('festa');
                    fecharPainel();
                    if (z) cena.focarTile(z.x + Math.floor(z.w / 2), z.y + Math.floor(z.h / 2));
                    mostrarStatus(`${A.htmlItem('canteiro', 22)} Use o botão Construir para pôr canteiros, máquinas e enfeites no terreno novo.`);
                    return;
                } else {
                    const nome = (tipoAnimal(tipo) || {}).nome;
                    toast(`${esc(nome || 'Item')} chegou na fazenda!`);
                }
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
                som.tocar('festa');
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
        const ir = e.target.closest('[data-painel-ir]');
        if (ir) { abrirPainel(ir.dataset.painelIr); return; }
        if (e.target.closest('[data-fechar]')) {
            fecharPainel();
            if (store.get(LS.tutorial) === null) iniciarTutorial();
            return;
        }
        if (e.target.closest('[data-tutorial]')) {
            fecharPainel();
            iniciarTutorial();
            return;
        }
        const bSom = e.target.closest('[data-som]');
        if (bSom) {
            som.alternar();
            bSom.textContent = som.mudo ? 'Ligar sons' : 'Desligar sons';
            atualizarBotaoSom();
            return;
        }
        if (e.target.closest('[data-avisos]')) {
            if (avisosLigados()) {
                store.set(LS.avisos, '0');
                clearTimeout(timerAvisos);
                toast('Avisos desligados.');
                abrirPainel('conta', true);
                return;
            }
            Notification.requestPermission().then((p) => {
                if (p !== 'granted') return toast('Sem permissão, sem avisos. Dá para liberar nas configurações do navegador.', 'erro');
                store.set(LS.avisos, '1');
                toast('Avisos ligados! Vou te chamar quando algo ficar pronto.', 'festa');
                notificar([{ texto: 'Vou te chamar quando algo ficar pronto. Bom plantio!' }], 'Fazendinha: avisos ligados!');
                agendarAvisos();
                if (painelAtual === 'conta') abrirPainel('conta', true);
            });
            return;
        }
        if (e.target.closest('[data-instalar]')) {
            if (instalador.estado() === 'pronto') {
                instalador.instalar().then((st) => { if (st === 'instalado') toast(`${spr(83, 22)} Fazenda instalada! Procure o ícone na tela inicial.`, 'festa'); });
            } else {
                const dica = el.painelCorpo.querySelector('[data-instalar-dica]');
                dica.textContent = instalador.dica();
                dica.hidden = false;
            }
            return;
        }
        if (e.target.closest('[data-convite-compartilhar]')) {
            compartilharConvite();
            return;
        }
        if (e.target.closest('[data-convite-abrir]')) {
            // no celular abre o compartilhar; no computador, o cartão do convite no Perfil
            if (navigator.share) return compartilharConvite();
            abrirPainel('conta');
            requestAnimationFrame(() => { const c = el.painelCorpo.querySelector('.convite-box'); if (c) c.scrollIntoView({ block: 'center' }); });
            return;
        }
        if (e.target.closest('[data-convite-copiar]')) {
            copiarConvite();
            return;
        }
        if (e.target.closest('[data-copiar]')) {
            if (await copiarTexto(store.get(LS.codigo))) toast('Código copiado!');
            else toast('Não deu para copiar. Anote o código.', 'erro');
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
    document.querySelectorAll('[data-massa]').forEach((b) => b.addEventListener('click', () => { fecharMenus(); acaoEmMassa(b.dataset.massa); }));

    /* ---------- celular: menu ☰ (topo) e menuzinho de ações (barra) ---------- */
    function fecharMenus() {
        el.hud.classList.remove('menu-aberto');
        if (el.btnMenu) el.btnMenu.setAttribute('aria-expanded', 'false');
        if (el.acoesGrupo) el.acoesGrupo.classList.remove('aberto');
        if (el.btnAcoes) el.btnAcoes.setAttribute('aria-expanded', 'false');
    }
    if (el.btnMenu) {
        el.btnMenu.addEventListener('click', (e) => {
            e.stopPropagation();
            const abrir = !el.hud.classList.contains('menu-aberto');
            fecharMenus();
            el.hud.classList.toggle('menu-aberto', abrir);
            el.btnMenu.setAttribute('aria-expanded', String(abrir));
        });
    }
    if (el.btnAcoes) {
        el.btnAcoes.addEventListener('click', (e) => {
            e.stopPropagation();
            const abrir = !el.acoesGrupo.classList.contains('aberto');
            fecharMenus();
            el.acoesGrupo.classList.toggle('aberto', abrir);
            el.btnAcoes.setAttribute('aria-expanded', String(abrir));
        });
    }
    // escolher algo no menu ou tocar fora fecha
    document.addEventListener('click', (e) => {
        if (e.target.closest('#hudBotoes .botao') || !e.target.closest('#hudBotoes, #acoesLista')) fecharMenus();
    });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') fecharMenus(); });
    document.querySelectorAll('[data-visita]').forEach((b) => b.addEventListener('click', () => acaoVisitaEmMassa(b.dataset.visita)));
    el.btnVoltarCasa.addEventListener('click', voltarCasa);
    $('btnPerfilVizinho').addEventListener('click', () => { if (visita) abrirPainel('perfilVizinho'); });

    /* ---------- botão de som no topo ---------- */
    const btnSom = $('btnSom');
    function atualizarBotaoSom() {
        btnSom.innerHTML = ico(som.mudo ? 'mudo' : 'som', 22) + `<em>${som.mudo ? 'Sem som' : 'Som'}</em>`;
        btnSom.setAttribute('aria-label', som.mudo ? 'Ligar sons' : 'Desligar sons');
    }
    btnSom.addEventListener('click', () => { som.alternar(); atualizarBotaoSom(); som.tocar('moeda'); });
    atualizarBotaoSom();

    /* ---------- tutorial (primeira vez na fazenda) ---------- */
    const TUTORIAL = [
        { texto: 'Bem-vindo(a)! Toque num canteiro de <b>terra escura</b> (já arado) para plantar alface.', ate: ['plantar'] },
        { texto: 'Plantou! A alface fica pronta em 2 minutos, mesmo com a página fechada. Enquanto isso, espie a <b>Loja</b> lá em cima.', ate: ['loja', 'colher'] },
        { texto: 'Quando a planta brilhar, toque nela para <b>colher</b>. Apareceu erva, praga ou seca? Toque para resolver antes.', ate: ['colher'] },
        { texto: 'Colheu! Agora toque no <b>celeiro</b> (o prédio vermelho) e venda a colheita para ganhar moedas.', ate: ['vender'] },
        { texto: 'Mandou bem! Cumpra as <b>Missões</b> do dia, compre animais na Loja e use <b>Construir</b> para deixar a fazenda do seu jeito.', ate: [] }
    ];
    let passoTutorial = -1;
    const elTut = $('tutorial');
    function mostrarPasso() {
        const p = TUTORIAL[passoTutorial];
        if (!p) return encerrarTutorial();
        elTut.hidden = false;
        elTut.style.top = (el.hud.getBoundingClientRect().bottom + 8) + 'px';   // logo abaixo do topo
        $('tutTexto').innerHTML = `<small>Passo ${passoTutorial + 1} de ${TUTORIAL.length}</small>${p.texto}`;
        $('tutProximo').textContent = passoTutorial === TUTORIAL.length - 1 ? 'Começar' : 'Próximo';
    }
    function iniciarTutorial() {
        passoTutorial = 0;
        store.set(LS.tutorial, '0');
        mostrarPasso();
    }
    function encerrarTutorial() {
        passoTutorial = -1;
        elTut.hidden = true;
        store.set(LS.tutorial, 'feito');
    }
    function tutorialEvento(evento) {
        const p = TUTORIAL[passoTutorial];
        if (!p || !p.ate.includes(evento)) return;
        passoTutorial++;
        store.set(LS.tutorial, String(passoTutorial));
        mostrarPasso();
    }
    $('tutProximo').addEventListener('click', () => { passoTutorial++; mostrarPasso(); });
    $('tutPular').addEventListener('click', encerrarTutorial);

    el.btnConstruir.addEventListener('click', abrirConstrucao);
    if (el.clima) el.clima.addEventListener('click', descreverClima);
    if (el.energia) el.energia.addEventListener('click', descreverEnergia);
    if (el.anuncio) el.anuncio.addEventListener('click', assistirAnuncio);
    if (el.hudPerfil) {
        const abrirPerfil = () => { if (S && !painelAtual) abrirPainel('conta'); };
        el.hudPerfil.addEventListener('click', abrirPerfil);
        el.hudPerfil.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); abrirPerfil(); } });
    }
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
            mostrarStatus(it.id === 'canteiro'
                ? `${A.htmlItem('canteiro', 22)} Canteiro: toque nos quadrados livres (sobram ${canteirosLivres()}). Lado a lado eles viram fileiras.`
                : `${A.htmlItem(it.id, 22)} ${esc(it.nome)} (${moeda(it.custo)})${it.descricao ? ': ' + esc(it.descricao) : ''} Toque nos quadrados livres.`);
            return;
        }
        const ferr = e.target.closest('[data-ferramenta]');
        if (ferr) {
            if (ferr.dataset.ferramenta === 'pronto') return fecharConstrucao();
            constr.modo = ferr.dataset.ferramenta;
            constr.movendo = null;
            desenharPaleta();
            atualizarModo();
            mostrarStatus(constr.modo === 'mover' ? 'Mover: toque num item ou canteiro e depois no lugar novo.' : 'Guardar: toque num item para tirar (volta metade do valor) ou num canteiro vazio.');
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
        mostrarFaixaConvite();
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
        atualizarTerreno();
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
        enviarEntrada(el.formNova, 'fazenda_criar', { p_apelido: apelido, p_convite: store.get(LS.convite) }, (r) => {
            store.set(LS.codigo, r.codigo);
            store.del(LS.convite);
            el.conviteFaixa.hidden = true;
            // Mostra o código logo de cara para a pessoa anotar
            abrirPainel('conta', false, true);
            if (r.convite) toast(`${ico('coracao', 16)} Presente do convite de ${esc(r.convite.apelido)}: +${r.convite.moedas} ${ico('moeda', 14)}!`, 'festa');
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
        desenharEnergia();
        atualizarBotaoAnuncio();
        atualizarLago();
        if (painelAtual === 'oficina') {
            const c = oficinaDoPainel(), o = c && infoOficina(c), alvo = el.painelCorpo.querySelector('[data-oficina-agora]');
            if (o && alvo) alvo.innerHTML = htmlOficinaAgora(o);
        }
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
        iniciarAnuncios();
        if (!token) return mostrarEntrada();
        try {
            aplicarEstado(await rpc('fazenda_carregar', { p_token: token }));
            mostrarFazenda();
            if (conviteDoLink) {
                store.del(LS.convite);
                toast('Esse convite é para quem ainda não tem fazenda. Você pode chamar os seus amigos pelo Perfil!');
            }
            const salvo = store.get(LS.tutorial);
            if (salvo !== null && salvo !== 'feito') { passoTutorial = Number(salvo) || 0; mostrarPasso(); }
        } catch (e) {
            if (e.code === 'token_invalido') sair(false);
            mostrarEntrada();
            mostrarErroEntrada(e.message);
        }
    })();
})();
