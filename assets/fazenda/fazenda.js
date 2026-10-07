/* ============================================================
   FAZENDINHA SECRETA — cliente
   Todas as regras (tempo, moedas, nível) são validadas no Supabase
   pelas funções fazenda_* (ver supabase/fazenda.sql). Aqui só
   desenhamos o estado e mandamos as ações.
============================================================ */
(function () {
    'use strict';

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
    const LS = { token: 'fazenda_token', codigo: 'fazenda_codigo', semente: 'fazenda_semente' };
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
        moedas_insuficientes: 'Moedas insuficientes 🪙',
        nada_a_fazer: 'Nada pra fazer aqui.',
        nao_maduro: 'Ainda não está pronto.',
        murchou: 'Essa planta murchou… are o canteiro para limpar.',
        acao_invalida: 'Ação inválida.',
        quantidade_invalida: 'Quantidade inválida.'
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
        hud: $('hud'), cena: $('cena'), barra: $('barra'), campo: $('campo'), status: $('status'),
        apelido: $('hudApelido'), nivel: $('hudNivel'), xpBar: $('hudXpBar'), xp: $('hudXp'),
        moedas: $('hudMoedas'), celeiroCont: $('hudCeleiro'),
        semEmoji: $('semEmoji'), semNome: $('semNome'), btnSemente: $('btnSemente'),
        toasts: $('toasts'), flut: $('flutuantes'),
        entrada: $('telaEntrada'), entradaCarregando: $('entradaCarregando'), entradaAbas: $('entradaAbas'),
        entradaErro: $('entradaErro'), formNova: $('formNova'), formCodigo: $('formCodigo'),
        inApelido: $('inApelido'), inCodigo: $('inCodigo'),
        painel: $('painel'), painelTitulo: $('painelTitulo'), painelCorpo: $('painelCorpo'), painelFechar: $('painelFechar')
    };

    /* ---------- Estado ---------- */
    let token = store.get(LS.token);
    let S = null;                 // último estado vindo do servidor
    let culturas = {};            // id -> cultura
    let offset = 0;               // relógio do servidor - relógio local (ms)
    let semente = store.get(LS.semente) || 'alface';
    let fila = Promise.resolve(); // ações em série para o estado nunca voltar no tempo
    let pendentes = 0;
    let painelAtual = null;
    let ultimoFoco = null;
    const tiles = [];

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

    const PROB = { erva: '☘️', praga: '🐛', seco: '💧' };
    const PROB_NOME = { erva: 'erva daninha', praga: 'praga', seco: 'terra seca' };

    /* ---------- Render ---------- */
    function montarCampo() {
        for (let p = 0; p < TOTAL_CANTEIROS; p++) {
            const b = document.createElement('button');
            b.type = 'button';
            b.className = 'canteiro';
            b.dataset.pos = p;
            b.innerHTML = '<span class="sprite"><span class="planta"></span><span class="brilho" hidden>✨</span><span class="probs" hidden></span><span class="rotulo"></span></span>';
            b.addEventListener('click', () => clicarCanteiro(p));
            b.addEventListener('mouseenter', () => descrever(p));
            b.addEventListener('focus', () => descrever(p));
            el.campo.appendChild(b);
            tiles.push({
                b,
                planta: b.querySelector('.planta'),
                brilho: b.querySelector('.brilho'),
                probs: b.querySelector('.probs'),
                rotulo: b.querySelector('.rotulo'),
                chave: ''
            });
        }
    }

    function canteiro(p) {
        return S && S.canteiros.find((c) => c.posicao === p);
    }

    function desenharCanteiro(p) {
        const t = tiles[p];
        const c = canteiro(p);
        const i = info(c);
        let classe = 'canteiro', planta = '', plantaCls = 'planta', rotulo = '', rotCls = 'rotulo', probs = '', brilho = false, label;

        if (i.fase === 'bloqueado') {
            classe += ' bloqueado';
            planta = '🔒'; plantaCls += ' f2';
            rotulo = `Nv ${nivelParaCanteiro(p)}`;
            label = `Canteiro bloqueado até o nível ${nivelParaCanteiro(p)}`;
        } else if (i.fase === 'vazio') {
            classe += ' vazio';
            label = 'Canteiro vazio: arar';
        } else if (i.fase === 'arado') {
            classe += ' arado';
            label = 'Canteiro arado: plantar';
        } else {
            classe += ' plantado';
            if (c.seco) classe += ' com-seco';
            if (i.fase === 'murcho') {
                planta = '🥀'; plantaCls += ' murcho';
                rotulo = 'Murchou'; rotCls += ' ruim';
                label = `${i.k.nome} murchou: arar para limpar`;
            } else if (i.fase === 'maduro') {
                planta = i.k.emoji; plantaCls += ' maduro';
                rotulo = 'Pronto!'; rotCls += ' pronto';
                brilho = true;
                label = `${i.k.nome} pronto para colher`;
            } else {
                if (i.prog < 0.33) { planta = '🌱'; plantaCls += ' f1'; }
                else if (i.prog < 0.66) { planta = '🌿'; plantaCls += ' f2'; }
                else { planta = i.k.emoji; plantaCls += ' f3'; }
                rotulo = fmtTempo(i.resta);
                label = `${i.k.nome}, faltam ${fmtTempo(i.resta)}`;
            }
            if (i.fase !== 'murcho' && i.probs.length) {
                probs = i.probs.map((x) => PROB[x]).join('');
                label += `. Problemas: ${i.probs.map((x) => PROB_NOME[x]).join(', ')}`;
            }
        }

        // Só mexe no DOM quando algo visual mudou (rótulo de tempo muda todo segundo)
        const chave = [classe, planta, plantaCls, probs, brilho].join('|');
        if (chave !== t.chave) {
            t.chave = chave;
            t.b.className = classe + (t.b.classList.contains('pendente') ? ' pendente' : '');
            t.planta.className = plantaCls;
            t.planta.textContent = planta;
            t.probs.textContent = probs;
            t.probs.hidden = !probs;
            t.brilho.hidden = !brilho;
        }
        if (t.rotulo.textContent !== rotulo) t.rotulo.textContent = rotulo;
        if (t.rotulo.className !== rotCls) t.rotulo.className = rotCls;
        t.b.setAttribute('aria-label', `Canteiro ${p + 1}: ${label}`);
        t.b.disabled = i.fase === 'bloqueado';
    }

    function desenharCampo() {
        for (let p = 0; p < TOTAL_CANTEIROS; p++) desenharCanteiro(p);
    }

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

        const k = culturas[semente];
        el.semEmoji.textContent = k ? k.emoji : '🌱';
        el.semNome.textContent = k ? `${k.nome} · 🪙${k.custo}` : 'Escolher';
    }

    function descrever(p) {
        const c = canteiro(p);
        const i = info(c);
        let txt;
        switch (i.fase) {
            case 'bloqueado': txt = `🔒 Libera no nível ${nivelParaCanteiro(p)}.`; break;
            case 'vazio': txt = '⛏️ Terra batida. Toque para arar (+1 XP).'; break;
            case 'arado': {
                const k = culturas[semente];
                txt = k ? `🌱 Pronto para plantar ${k.emoji} ${k.nome} (🪙${k.custo}).` : '🌱 Pronto para plantar.';
                break;
            }
            case 'murcho': txt = `🥀 ${i.k.nome} murchou. Toque para limpar e arar.`; break;
            case 'maduro': txt = `${i.k.emoji} ${i.k.nome} pronto! Murcha em ${fmtTempo(i.resta)}.`; break;
            default: txt = `${i.k.emoji} ${i.k.nome} · ${Math.floor(i.prog * 100)}% · colhe em ${fmtTempo(i.resta)}.`;
        }
        if (i.probs && i.probs.length && i.fase !== 'murcho') {
            txt += ` Cuide: ${i.probs.map((x) => `${PROB[x]} ${PROB_NOME[x]}`).join(', ')} (−1 cada na colheita).`;
        }
        el.status.textContent = txt;
    }

    /* ---------- Estado vindo do servidor ---------- */
    function aplicarEstado(estado) {
        const antes = S;
        S = estado;
        offset = Date.parse(estado.agora) - Date.now();
        culturas = {};
        for (const k of estado.culturas) culturas[k.id] = k;
        if (!culturas[semente]) semente = 'alface';

        if (antes && estado.jogador.nivel > antes.jogador.nivel) {
            const novas = estado.culturas.filter((k) => k.nivel_min > antes.jogador.nivel && k.nivel_min <= estado.jogador.nivel);
            let msg = `🎉 Nível ${estado.jogador.nivel}!`;
            if (estado.jogador.max_canteiros > antes.jogador.max_canteiros) msg += ' +2 canteiros';
            if (novas.length) msg += ` · Nova semente: ${novas.map((k) => k.emoji + ' ' + k.nome).join(', ')}`;
            toast(msg, 'festa');
        }
        desenharHud();
        desenharCampo();
        if (painelAtual === 'loja' || painelAtual === 'celeiro') abrirPainel(painelAtual, true);
    }

    /* ---------- Feedback visual ---------- */
    function toast(msg, tipo) {
        const t = document.createElement('div');
        t.className = 'toast' + (tipo === 'erro' ? ' erro-t' : tipo === 'festa' ? ' festa' : '');
        t.textContent = msg;
        el.toasts.appendChild(t);
        while (el.toasts.children.length > 3) el.toasts.firstChild.remove();
        setTimeout(() => t.remove(), tipo === 'festa' ? 4600 : 3100);
    }

    function flutuar(p, texto, atraso = 0) {
        const r = tiles[p].planta.getBoundingClientRect();
        setTimeout(() => {
            const f = document.createElement('div');
            f.className = 'flut';
            f.textContent = texto;
            f.style.left = `${r.left + r.width / 2}px`;
            f.style.top = `${r.top}px`;
            el.flut.appendChild(f);
            setTimeout(() => f.remove(), 1400);
        }, atraso);
    }

    /* ---------- Ações ---------- */
    function enfileirar(posicoes, tarefa) {
        posicoes.forEach((p) => tiles[p].b.classList.add('pendente'));
        pendentes++;
        const execucao = fila.then(tarefa).catch(tratarErro).finally(() => {
            pendentes--;
            posicoes.forEach((p) => tiles[p].b.classList.remove('pendente'));
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
        toast(e.message || 'Algo deu errado.', 'erro');
    }

    const FEEDBACK = {
        arar: () => '+1 XP',
        plantar: (k) => `−${k.custo} 🪙`,
        erva: () => '+1 XP +1 🪙',
        praga: () => '+1 XP +1 🪙',
        seco: () => '+1 XP +1 🪙'
    };

    function validarPlantio() {
        const k = culturas[semente];
        if (!k || k.nivel_min > S.jogador.nivel) {
            abrirPainel('loja');
            toast('Escolha uma semente na loja 🛒');
            return null;
        }
        return k;
    }

    function clicarCanteiro(p) {
        if (!S) return;
        const acao = acaoPara(canteiro(p));
        descrever(p);
        if (!acao) return;
        let k = null;
        if (acao === 'plantar') {
            k = validarPlantio();
            if (!k) return;
            if (S.jogador.moedas < k.custo) {
                toast(`Faltam moedas para ${k.nome}. Venda a colheita no celeiro 🛖`, 'erro');
                return;
            }
        }
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
                    flutuar(Number(pos), `+${qtd} ${kc ? kc.emoji : ''}  +${kc ? kc.xp : 0} XP`, n * 80);
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
            toast(`🧺 Colheu ${total} itens de ${r.feitos} canteiro(s)!`);
        } else if (acao === 'plantar') {
            toast(`🌱 Plantou ${r.feitos} × ${k.emoji} ${k.nome}`);
        } else if (acao === 'arar') {
            toast(`⛏️ Arou ${r.feitos} canteiro(s)`);
        }
    }

    function posicoesOnde(filtro) {
        return S.canteiros.filter((c) => filtro(c, info(c))).map((c) => c.posicao);
    }

    async function acaoEmMassa(tipo) {
        if (!S) return;
        if (tipo === 'colher') {
            const ps = posicoesOnde((c, i) => i.fase === 'maduro');
            if (!ps.length) return toast('Nada maduro ainda ⏳');
            executar('colher', ps);
        } else if (tipo === 'arar') {
            const ps = posicoesOnde((c, i) => i.fase === 'vazio' || i.fase === 'murcho');
            if (!ps.length) return toast('Nenhum canteiro precisa ser arado.');
            executar('arar', ps);
        } else if (tipo === 'plantar') {
            const ps = posicoesOnde((c, i) => i.fase === 'arado');
            if (!ps.length) return toast('Nenhum canteiro arado livre.');
            const k = validarPlantio();
            if (!k) return;
            if (S.jogador.moedas < k.custo) return toast(`Faltam moedas para ${k.nome}.`, 'erro');
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
            if (!algum) toast('Tudo em ordem por aqui 🌤️');
            else if (total) toast(`🧑‍🌾 Resolveu ${total} problema(s)!`);
        }
    }

    async function recarregar() {
        if (!token || pendentes) return;
        try {
            aplicarEstado(await rpc('fazenda_carregar', { p_token: token }));
        } catch (e) {
            if (e.code === 'token_invalido') tratarErro(e);
        }
    }

    /* ---------- Painéis ---------- */
    function abrirPainel(nome, soAtualizar) {
        if (!soAtualizar) ultimoFoco = document.activeElement;
        painelAtual = nome;
        const corpo = el.painelCorpo;
        if (nome === 'loja') {
            el.painelTitulo.textContent = '🛒 Loja de sementes';
            corpo.innerHTML = '<div class="lista">' + S.culturas.map((k) => {
                const travada = k.nivel_min > S.jogador.nivel;
                const lucro = k.venda * k.rendimento - k.custo;
                return `<button type="button" class="item${k.id === semente ? ' selecionada' : ''}${travada ? ' travada' : ''}" data-semente="${esc(k.id)}" ${travada ? 'aria-disabled="true"' : ''}>
                    <span class="ico">${travada ? '🔒' : esc(k.emoji)}</span>
                    <span>
                        <span class="nome">${esc(k.nome)}</span>
                        <span class="det">
                            <span>⏱ ${fmtDuracao(k.tempo_seg)}</span>
                            <span>🧺 ${k.rendimento} × 🪙${k.venda}</span>
                            <span>⭐ +${k.xp} XP</span>
                            <span>📈 lucro 🪙${lucro}</span>
                        </span>
                    </span>
                    <span class="preco">${travada ? `Nv ${k.nivel_min}` : `🪙 ${k.custo}`}</span>
                </button>`;
            }).join('') + '</div><p class="aviso" style="margin-top:14px">Toque numa semente para escolher. Depois toque nos canteiros arados (ou em “Plantar tudo”).</p>';
        } else if (nome === 'celeiro') {
            el.painelTitulo.textContent = '🛖 Celeiro';
            const itens = S.culturas.filter((k) => S.celeiro[k.id] > 0);
            if (!itens.length) {
                corpo.innerHTML = '<p class="vazio-msg">Seu celeiro está vazio.<br>Colha algo e volte aqui para vender! 🧺</p>';
            } else {
                const total = itens.reduce((a, k) => a + S.celeiro[k.id] * k.venda, 0);
                corpo.innerHTML = '<div class="lista">' + itens.map((k) => `
                    <div class="item">
                        <span class="ico">${esc(k.emoji)}</span>
                        <span>
                            <span class="nome">${esc(k.nome)} × ${S.celeiro[k.id]}</span>
                            <span class="det"><span>🪙${k.venda} cada</span><span>total 🪙${S.celeiro[k.id] * k.venda}</span></span>
                        </span>
                        <button type="button" class="btn pequeno" data-vender="${esc(k.id)}">Vender</button>
                    </div>`).join('') + `</div>
                    <div class="rodape-painel">
                        <span>Valor total: <b>🪙 ${total}</b></span>
                        <button type="button" class="btn" data-vender="*">Vender tudo</button>
                    </div>`;
            }
        } else if (nome === 'conta') {
            el.painelTitulo.textContent = '⚙️ Sua fazenda';
            const codigo = store.get(LS.codigo);
            corpo.innerHTML = `
                <p>Fazendeiro(a): <b>${esc(S.jogador.apelido)}</b> · Nível ${S.jogador.nivel}</p>
                <h3 class="secao-titulo">🔑 Código de recuperação</h3>
                ${codigo ? `<div class="codigo-box"><code>${esc(codigo)}</code><button type="button" class="btn pequeno secundario" data-copiar>Copiar</button></div>` : '<p class="aviso">O código não está salvo neste aparelho. Se você anotou, ele continua valendo.</p>'}
                <p class="aviso">Guarde esse código: é o único jeito de abrir sua fazenda em outro aparelho ou se o navegador for limpo.</p>
                <h3 class="secao-titulo">📖 Como jogar</h3>
                <ul class="ajuda">
                    <li>Toque num canteiro e ele faz a ação certa: <b>arar</b>, <b>plantar</b>, <b>cuidar</b> ou <b>colher</b>.</li>
                    <li>As plantas crescem em tempo real, mesmo com a página fechada.</li>
                    <li>Aparecem ☘️ ervas, 🐛 pragas e 💧 seca: cada problema deixado custa 1 item na colheita.</li>
                    <li>Depois de madura, a planta <b>murcha</b> se ficar tempo demais sem colher.</li>
                    <li>Venda a colheita no 🛖 celeiro, compre sementes melhores e suba de nível para ganhar canteiros.</li>
                </ul>
                <div class="rodape-painel">
                    <a class="btn secundario" href="indexversao2.html" style="text-decoration:none">↩ Voltar ao portfólio</a>
                    <button type="button" class="btn perigo" data-sair>Sair desta fazenda</button>
                </div>`;
        }
        if (!soAtualizar) {
            el.painel.classList.add('aberto');
            el.painelFechar.focus();
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
            if (k.nivel_min > S.jogador.nivel) return toast(`🔒 ${k.nome} libera no nível ${k.nivel_min}.`);
            semente = k.id;
            store.set(LS.semente, semente);
            desenharHud();
            fecharPainel();
            toast(`Semente escolhida: ${k.emoji} ${k.nome}`);
            return;
        }
        const vend = e.target.closest('[data-vender]');
        if (vend) {
            vend.disabled = true;
            const item = vend.dataset.vender === '*' ? null : vend.dataset.vender;
            enfileirar([], async () => {
                const r = await rpc('fazenda_vender', { p_token: token, p_item: item, p_quantidade: null });
                if (r.ganho > 0) toast(`💰 Vendeu por 🪙 ${r.ganho}!`);
                aplicarEstado(r.estado);
            }).finally(() => { vend.disabled = false; });
            return;
        }
        if (e.target.closest('[data-copiar]')) {
            try {
                await navigator.clipboard.writeText(store.get(LS.codigo));
                toast('Código copiado 📋');
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

    /* ---------- Entrada / sessão ---------- */
    function mostrarEntrada() {
        el.hud.hidden = el.cena.hidden = el.barra.hidden = true;
        el.entrada.classList.add('aberto');
        el.entradaCarregando.hidden = true;
        el.entradaAbas.hidden = false;
        el.inApelido.focus();
    }

    function mostrarFazenda() {
        el.entrada.classList.remove('aberto');
        el.hud.hidden = el.cena.hidden = el.barra.hidden = false;
    }

    function mostrarErroEntrada(msg) {
        el.entradaErro.textContent = msg || '';
    }

    function sair(apagarCodigo) {
        token = null;
        S = null;
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
            aoEntrar(r);
            aplicarEstado(r.estado);
            mostrarFazenda();
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
            setTimeout(() => {
                abrirPainel('conta');
                el.painelTitulo.textContent = '🌻 Bem-vindo(a) à fazenda!';
            }, 50);
        });
    });

    el.formCodigo.addEventListener('submit', (e) => {
        e.preventDefault();
        const codigo = el.inCodigo.value.trim().toUpperCase().replace(/\s+/g, '');
        if (!codigo) return;
        enviarEntrada(el.formCodigo, 'fazenda_recuperar', { p_codigo: codigo }, () => {
            store.set(LS.codigo, codigo);
            toast(`Bem-vindo(a) de volta! 🏡`);
        });
    });

    /* ---------- Loop ---------- */
    let ultimoPoll = Date.now();
    setInterval(() => {
        if (!S) return;
        desenharCampo();
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
    montarCampo();
    (async function iniciar() {
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
