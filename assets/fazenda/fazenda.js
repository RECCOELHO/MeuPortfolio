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
    // Login com Google para ligar a fazenda e abrir ela em outro aparelho. É o ID do cliente OAuth
    // (público; o mesmo da Edge Function fazenda-diamantes). Vazio = sem Google.
    const GOOGLE_CLIENT_ID = '399889578261-33gg9c2uq7d40v6nba2qf1g3b87qfugj.apps.googleusercontent.com';

    // Em localhost dá pra apontar para um backend de teste: fazenda.html?api=http://localhost:8787
    let API = SUPABASE_URL;
    try {
        const alt = new URLSearchParams(location.search).get('api');
        if (alt && /^(localhost|127\.0\.0\.1)$/.test(location.hostname)) API = alt;
    } catch { /* ignora */ }

    const POLL_MS = 60000;   // de quanto em quanto a fazenda aberta busca o estado (cada busca grava no banco)
    const POLL_PARADO_MS = 300000;   // aba aberta e ninguém mexe há 5 min: busca de 5 em 5 min

    /* ---------- Armazenamento local (protegido) ---------- */
    const LS = {
        token: 'fazenda_token', codigo: 'fazenda_codigo', semente: 'fazenda_semente',
        diarioVisto: 'fazenda_diario_visto', mudo: 'fazenda_mudo', tutorial: 'fazenda_tutorial', avisos: 'fazenda_avisos', convite: 'fazenda_convite',
        historico: 'fazenda_historico', historicoVisto: 'fazenda_historico_visto',
        volMusica: 'fazenda_vol_musica', volEfeitos: 'fazenda_vol_efeitos', faixaMusica: 'fazenda_faixa_musica',
        novidades: 'fazenda_novidades', chatVisto: 'fazenda_chat_visto', chatSilencio: 'fazenda_chat_silencio',
        calendarioVisto: 'fazenda_calendario_visto'
    };
    const store = {
        get(k) { try { return localStorage.getItem(k); } catch { return null; } },
        set(k, v) { try { localStorage.setItem(k, v); } catch { /* ignora */ } },
        del(k) { try { localStorage.removeItem(k); } catch { /* ignora */ } }
    };

    /* ---------- Mensagens de erro do servidor ---------- */
    const ERROS = {
        token_invalido: 'Sessão expirada. Entre de novo com seu código.',
        conta_banida: 'Esta fazenda foi suspensa por desrespeitar as regras do jogo.',
        sem_permissao: 'Só os admins do jogo podem fazer isso.',
        // fase 69: o calendário
        calendario_hoje: 'Você já pegou o prêmio de hoje. Volte amanhã!',
        ja_dourado: 'A trilha dourada já está liberada neste ciclo.',
        avatar_exclusivo: 'Esse personagem só sai no dia 28 do calendário dourado.',
        // fase 67: o chat
        chat_nivel: 'Você já lê o chat; escrever libera no nível 5.',
        chat_vazio: 'Escreva alguma coisa antes de enviar.',
        chat_longo: 'Mensagem muito comprida: até 120 letras.',
        chat_link: 'Link não pode no chat (protege todo mundo de golpe).',
        chat_palavrao: 'Essa mensagem tem palavra que não pode no chat.',
        chat_rapido: 'Calma! Uma mensagem a cada 8 segundos.',
        chat_repetida: 'Você acabou de mandar essa mesma mensagem.',
        chat_limite: 'Você já mandou muitas mensagens nesta hora (30, ou 6 pedidos). Espere um pouco.',
        mensagem_sumiu: 'Essa mensagem já sumiu.',
        pedido_seu: 'Esse pedido é seu.',
        pedido_sumiu: 'Esse pedido já sumiu do chat (passou de 1 hora ou foi apagado).',
        pedido_atendido: 'Esse pedido já foi atendido.',
        anuncio_reservado: 'Esse lote está separado para quem pediu no chat. Daqui a pouco, se a pessoa não comprar, ele fica livre.',
        admin_propria_conta: 'Isso não vale para a sua própria conta (nem para a do dono).',
        admin_alvo_admin: 'Essa conta é admin: o dono tira o admin antes de banir.',
        admin_motivo: 'Escreva o motivo do banimento.',
        admin_banido: 'Conta banida não pode ser admin.',
        admin_codigo_banido: 'Conta banida não entra nem com código novo: desbana antes.',
        lento: 'A fazenda está demorando para responder (o servidor está lento agora). Tente de novo daqui a pouco.',
        servidor: 'O servidor da fazenda está sobrecarregado agora. Tente de novo daqui a pouco.',
        apelido_invalido: 'O apelido precisa ter de 2 a 20 letras.',
        codigo_invalido: 'Código não encontrado. Confira e tente de novo.',
        canteiro_bloqueado: 'Esse canteiro ainda está bloqueado.',
        ja_arado: 'Esse canteiro já está arado.',
        canteiro_ocupado: 'Tem uma planta crescendo aí.',
        precisa_arar: 'Are o canteiro antes de plantar.',
        cultura_invalida: 'Semente inválida.',
        nivel_insuficiente: 'Você ainda não tem nível para essa semente.',
        moedas_insuficientes: 'Moedas insuficientes.',
        diamantes_insuficientes: 'Faltam diamantes. Você ganha 5 a cada nível.',
        limite_diario: 'Hoje já foram os 3 pacotes de XP. Amanhã tem mais!',
        xp_maximo: 'Você já está no nível máximo.',
        energia_cheia: 'As baterias já estão cheias.',
        sem_maquinas: 'Você ainda não tem nada de energia (painel solar, bateria...).',
        sem_ajudantes: 'Contrate um ajudante primeiro (Loja → Ajudantes).',
        oficina_parada: 'Essa oficina está parada: não tem receita para terminar.',
        pacote_invalido: 'Pacote de diamantes inválido.',
        muitas_compras: 'Muitas compras abertas na última hora. Espere um pouco e tente de novo.',
        loja_fechada: 'A loja de diamantes ainda não abriu.',
        compra_invalida: 'Compra não encontrada.',
        erro_pagamento: 'O Mercado Pago não respondeu agora. Tente daqui a pouco.',
        google_invalido: 'Não deu para confirmar o login do Google. Tente de novo.',
        google_em_uso: 'Essa conta Google já está ligada a outra fazenda.',
        google_sem_fazenda: 'Nenhuma fazenda ligada a essa conta Google. Entre com o código e ligue ao Google no Perfil.',
        google_fechado: 'O login com Google ainda não está ligado.',
        google_indisponivel: 'O Google não respondeu agora. Tente daqui a pouco.',
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
        ja_salvou: 'Você já salvou duas plantas nessa fazenda hoje. Volte amanhã!',
        preco_invalido: 'Preço fora da faixa da feira para esse item (a faixa aparece embaixo do preço).',
        limite_anuncios: 'Os seus lugares na feira estão todos ocupados. Cada barraca nova (no painel da Feira, até 4) dá mais 2; ou espere vender ou cancele um.',
        limite_barracas: 'A sua feira já tem as 4 barracas.',
        sem_itens: 'Não tem tudo isso livre no celeiro (a ração reservada fica).',
        anuncio_invalido: 'Esse lote já foi vendido, cancelado ou acabou.',
        anuncio_seu: 'Esse anúncio é seu.',
        limite_compras: 'Hoje você já comprou 40 lotes na feira. Amanhã tem mais!',
        limite_bichos: 'Você já deu ração a 10 bichos nessa fazenda hoje.',
        ja_alimentado: 'Esse bicho já comeu.',
        nao_pronto: 'Ainda não tem nada pra coletar.',
        animal_invalido: 'Esse animal não está mais aqui.',
        limite_animais: 'Você já tem o máximo desse animal.',
        sem_cercado: 'Esse bicho precisa do cercado dele primeiro (Construir → Bichos).',
        cercado_com_bichos: 'Esse cercado tem bichos morando: dá para mudar ele de lugar, mas não desmanchar.',
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
        anuncio_cedo: 'Calma! Espere uns minutos entre um anúncio e outro.',
        anuncio_limite: 'Por hoje chega de anúncio. Volte amanhã!',   // fase 70
        sem_lago: 'Compre o Vale do sudeste (aba Terrenos da loja) para liberar o lago.',
        cesto_vazio: 'O cesto ainda está vazio: o Bira tira um peixe a cada 30 minutos.',
        limite_canteiros: 'Você já usou todos os seus canteiros. Suba de nível ou compre terrenos para ter mais.',
        limite_maquina: 'Você já tem essa máquina (uma basta para a fazenda toda).',
        melhoria_max: 'Essa melhoria já está no máximo.',
        ajudante_descansando: 'Esse ajudante já está descansando (ou não precisa).',
        pier_pronto: 'O seu píer já está pronto.',
        sem_litoral: 'Compre o terreno do Litoral (Loja → Terrenos, nível 31) para construir o píer.',
        faltam_pecas: 'Ainda faltam peças do píer. Veja na tela do píer o que falta.',
        peca_nao_falta: 'Essa peça você já tem para o píer.',
        peca_comprada: 'Com diamantes, só dá para comprar as peças que a receita do píer pede.',   // fase 70
        muitas_fazendas_ip: 'Já criaram muitas fazendas daqui hoje. Tente mais tarde ou entre na sua com o código.',
        muitas_tentativas: 'Muitas tentativas de código. Espere uma hora e tente de novo.',
        sem_pier: 'Construa o píer primeiro (no Litoral, do nível 31 em diante).',   // fase 62: o alto-mar
        cardume_vazio: 'O cardume acabou: ele enche sozinho com o tempo.',
        sem_lance: 'A linha não estava na água. Lance de novo.',
        sem_marinheiro: 'Contrate o marinheiro primeiro (Alto-mar → Melhorar, nível 33).',
        cesto_mar_vazio: 'O cesto do Seu Nonato ainda está vazio.',
        faltam_materiais: 'Faltam materiais no celeiro para essa peça (o que está guardado para o píer não conta).',   // fase 65: a tunagem
        sem_luva: 'Acabaram as luvas do Perks.',   // fase 66
        ajudante_disposto: 'Ele ainda está bem disposto: só dá para mandar descansar com menos de 75% de energia.',
        barco_pequeno: 'O kit de expedição só cabe no barco oceânico.',
        nada_mudou: 'Escolha uma cor ou bandeira diferente da que o barco já tem.',
        cor_invalida: 'Essa cor não existe.',
        sem_cama: 'Todas as camas estão ocupadas: construa mais casinhas (Construir → Casas) para mais ajudantes descansarem ao mesmo tempo.',
        limite_terreno: 'Já tem o máximo dessa árvore: cada fruta tem 1 pé, +1 a cada 2 terrenos comprados (até 4).',
        alarme: 'O alarme disparou! Esse canteiro está protegido.',
        item_invalido: 'Item inválido.',
        lugar_reservado: 'Esse lugar é reservado (celeiro, casa, pasto, galinheiro) ou fica na mata fora do seu terreno.',
        lugar_ocupado: 'Já tem algo nesse lugar.',
        so_na_areia: 'Isso é da praia: só vai na areia do Litoral.',
        limite_construcoes: 'Sua fazenda chegou ao limite de construções. Cada terreno comprado dá espaço para mais 150; ou guarde algumas que não usa.',
        missao_invalida: 'Missão não encontrada.',
        ja_resgatada: 'Você já pegou essa recompensa.',
        missao_incompleta: 'Termine a missão antes de resgatar.'
    };

    // Com o servidor lento, desiste depois de 25 s (senão a fila de ações trava esperando). Criar
    // fazenda espera o quanto for: o código de recuperação só vem nessa resposta.
    const RPC_ESPERA_MS = 25000;
    async function rpc(fn, args) {
        let res;
        const parar = new AbortController();
        const relogio = fn === 'fazenda_criar' ? null : setTimeout(() => parar.abort(), RPC_ESPERA_MS);
        try {
            res = await fetch(`${API}/rest/v1/rpc/${fn}`, {
                method: 'POST',
                headers: {
                    apikey: SUPABASE_KEY,
                    Authorization: 'Bearer ' + SUPABASE_KEY,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify(args),
                signal: parar.signal
            });
        } catch {
            clearTimeout(relogio);
            if (parar.signal.aborted) throw Object.assign(new Error(ERROS.lento), { code: 'lento' });
            throw Object.assign(new Error('Sem conexão com a fazenda. Tente de novo.'), { code: 'rede' });
        }
        clearTimeout(relogio);
        const data = await res.json().catch(() => null);
        if (!res.ok) {
            let code = data && data.message;
            if (res.status >= 500 && !ERROS[code]) code = 'servidor';   // banco sobrecarregado, tempo esgotado...
            throw Object.assign(new Error(ERROS[code] || 'Algo deu errado na fazenda.'), { code });
        }
        return data;
    }

    /* ---------- DOM ---------- */
    const $ = (id) => document.getElementById(id);
    const el = {
        canvas: $('cena'), hud: $('hud'), barra: $('barra'), status: $('status'),
        apelido: $('hudApelido'), nivel: $('hudNivel'), xpBar: $('hudXpBar'), xp: $('hudXp'), premio: $('hudPremio'),
        moedas: $('hudMoedas'), diamantes: $('hudDiamantes'), celeiroCont: $('hudCeleiro'),
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

    /* ---------- Sons 8-bit e Trilha Sonora ---------- */
    const som = (() => {
        let ctx = null;
        let mudo = store.get(LS.mudo) === '1';
        let pausado = false;   // durante o anúncio
        let volMusica = store.get(LS.volMusica) !== null ? Math.max(0, Math.min(100, Number(store.get(LS.volMusica)))) : 35;
        let volEfeitos = store.get(LS.volEfeitos) !== null ? Math.max(0, Math.min(100, Number(store.get(LS.volEfeitos)))) : 80;
        let faixaAtual = Number(store.get(LS.faixaMusica)) || 0; // 0: Tema da Roça 1, 1: Tema da Roça 2

        const FAIXAS = [
            { nome: 'Fazenda Secreta (Tema 1)', src: 'assets/music/fazenda-tema-1.mp3' },
            { nome: 'Fazenda Secreta (Tema 2)', src: 'assets/music/fazenda-tema-2.mp3' }
        ];

        let musicaAudio = null;
        let desbloqueado = false;

        function audio() {
            if (!ctx) {
                const C = window.AudioContext || window.webkitAudioContext;
                if (!C) return null;
                ctx = new C();
            }
            if (ctx.state === 'suspended') ctx.resume();
            return ctx;
        }

        function aplicarVolumeMusica() {
            if (!musicaAudio) return;
            musicaAudio.volume = (mudo || pausado) ? 0 : (volMusica / 100);
        }

        function tocarMusica() {
            if (!musicaAudio) {
                musicaAudio = new Audio();
                musicaAudio.loop = true;
                musicaAudio.preload = 'auto';
            }
            const faixa = FAIXAS[faixaAtual] || FAIXAS[0];
            const srcAtual = musicaAudio.getAttribute('src');
            if (srcAtual !== faixa.src) {
                musicaAudio.src = faixa.src;
            }
            aplicarVolumeMusica();
            if (!mudo && !pausado && volMusica > 0) {
                const prom = musicaAudio.play();
                if (prom && typeof prom.catch === 'function') {
                    prom.catch(() => { /* aguarda interação do usuário */ });
                }
            }
        }

        function desbloquearAudio() {
            if (desbloqueado) return;
            desbloqueado = true;
            try { audio(); } catch {}
            if (!mudo && !pausado && volMusica > 0) {
                tocarMusica();
            }
        }

        // Tenta iniciar a música na primeira interação do jogador com a página
        ['click', 'keydown', 'touchstart'].forEach((ev) => {
            window.addEventListener(ev, desbloquearAudio, { once: true, passive: true });
        });

        function nota(freq, ini, dur, tipo = 'square', vol = 0.05) {
            const c = audio();
            if (!c || mudo || pausado || volEfeitos <= 0) return;
            const o = c.createOscillator(), g = c.createGain(), t = c.currentTime + ini;
            const ganhoReal = vol * (volEfeitos / 100);
            o.type = tipo;
            o.frequency.setValueAtTime(freq, t);
            g.gain.setValueAtTime(ganhoReal, t);
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
            pausar(p) {
                pausado = p;
                aplicarVolumeMusica();
                if (musicaAudio) {
                    if (pausado) musicaAudio.pause();
                    else if (!mudo && volMusica > 0) musicaAudio.play().catch(() => {});
                }
            },
            alternar() {
                mudo = !mudo;
                store.set(LS.mudo, mudo ? '1' : '0');
                aplicarVolumeMusica();
                if (!mudo && volMusica > 0 && musicaAudio) {
                    musicaAudio.play().catch(() => {});
                }
                return mudo;
            },
            definirVolMusica(v) {
                volMusica = Math.max(0, Math.min(100, Number(v) || 0));
                store.set(LS.volMusica, String(volMusica));
                aplicarVolumeMusica();
                if (!mudo && !pausado && volMusica > 0 && musicaAudio && musicaAudio.paused) {
                    musicaAudio.play().catch(() => {});
                }
            },
            definirVolEfeitos(v) {
                volEfeitos = Math.max(0, Math.min(100, Number(v) || 0));
                store.set(LS.volEfeitos, String(volEfeitos));
            },
            trocarFaixa(idx) {
                faixaAtual = (idx >= 0 && idx < FAIXAS.length) ? idx : 0;
                store.set(LS.faixaMusica, String(faixaAtual));
                if (musicaAudio) {
                    musicaAudio.src = FAIXAS[faixaAtual].src;
                    aplicarVolumeMusica();
                    if (!mudo && !pausado && volMusica > 0) {
                        musicaAudio.play().catch(() => {});
                    }
                }
            },
            desbloquear: desbloquearAudio,
            get mudo() { return mudo; },
            get volMusica() { return volMusica; },
            get volEfeitos() { return volEfeitos; },
            get faixaAtual() { return faixaAtual; },
            get faixas() { return FAIXAS; }
        };
    })();
    const SOM_DA_ACAO = { arar: 'arar', plantar: 'plantar', colher: 'colher', agora: 'colher', erva: 'cuidar', praga: 'cuidar', seco: 'cuidar' };

    /* ---------- Estado ---------- */
    let token = store.get(LS.token);
    let S = null;                 // último estado vindo do servidor
    let visita = null;            // fazenda do vizinho sendo visitada (null = em casa)
    let abaVizinhos = 'ranking';
    let abaLoja = 'sementes';
    let abaCeleiro = 'tudo';
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
        cena.definirPier(!visita && !!(S && S.pier && S.pier.pronto));   // fase 61
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
    let noiteMostrada = null;   // para redesenhar o clima do topo quando vira o dia ou a noite
    function desenharClima() {
        if (!el.clima) return;
        if (S && S.estacao) cena.definirEstacao(S.estacao);
        const c = climaAgora();
        el.clima.hidden = !CLIMA[c];
        if (!CLIMA[c]) return;
        const dia = A.faseDoDia(agora());
        noiteMostrada = dia.noite;
        // de noite "sol" vira céu limpo (só a lua); os outros climas aparecem ao lado dela
        const ceuLimpo = dia.noite && c === 'sol';
        el.clima.innerHTML = (dia.noite ? ico('lua', 22) : '') + (ceuLimpo ? '' : ico(iconeClima(c), 22)) +
            `<span>${dia.noite ? 'Noite · ' : ''}${ceuLimpo ? 'céu limpo' : CLIMA[c].nome}</span>`;
        const prox = CLIMA[S.clima.proximo || S.clima.amanha];
        el.clima.title = `${dia.noite ? `Noite até ${hora(dia.fim)}. ` : `Dia até ${hora(dia.fim)}. `}${CLIMA[c].nome}${S.clima.ate ? ' até ' + hora(S.clima.ate) : ''}: ${CLIMA[c].efeito}${prox ? ' Depois: ' + prox.nome.toLowerCase() + '.' : ''}`;
        cena.definirClima(visita ? null : c);
    }
    function descreverClima() {
        const c = climaAgora();
        if (!CLIMA[c]) return;
        const prox = S.clima.proximo || S.clima.amanha;
        const fimEst = S.estacao_fim ? Date.parse(S.estacao_fim) - agora() : 0;
        const dia = A.faseDoDia(agora());
        mostrarStatus((dia.noite
            ? `${ico('lua', 18)} <b>Noite</b> até ${hora(dia.fim)}: o painel solar descansa e as luzes acendem. `
            : `${ico('sol', 18)} <b>Dia</b> até ${hora(dia.fim)}. `) +
            `${ico(iconeClima(c), 18)} <b>${CLIMA[c].nome}</b>${S.clima.ate ? ' até ' + hora(S.clima.ate) : ''}: ${CLIMA[c].efeito}` +
            (CLIMA[prox] ? ` Depois: ${ico(iconeClima(prox), 16)} ${CLIMA[prox].nome.toLowerCase()}.` : '') +
            (S.estacao ? ` É ${NOME_ESTACAO[S.estacao]}${fimEst > 0 && S.estacao_proxima ? `, vira ${NOME_ESTACAO[S.estacao_proxima]} em ${fmtTempo(fimEst)}` : ''}.` : ''));
    }

    /* ---------- Energia (nível 16+) ----------
       Geradores enchem as baterias; máquinas elétricas gastam ao trabalhar. O servidor
       manda a carga e quanto entra por hora; aqui só se adianta o que entrou desde então. */
    let energiaEm = 0;
    const eletrico = (c) => (tipoItem(c.tipo) || {}).categoria === 'energia';
    const temEletrico = () => !visita && !!S && !!S.energia && (S.construcoes || []).some(eletrico);
    // fase 48: a calmaria (sem vento a turbina cai para 3 ⚡/h): agora até quando, ou a próxima
    function textoVento() {
        const v = S && S.energia && S.energia.vento;
        if (!v || !(S.construcoes || []).some((c) => c.tipo === 'turbina')) return '';
        if (v.calmo) return ` <b>Calmaria</b> até ${hora(v.muda_em)}: sem vento, a turbina gera só 3 ⚡/h.`;
        return v.proxima ? ` Próxima calmaria às ${hora(v.proxima)}.` : '';
    }
    function cargaAgora() {
        const en = S && S.energia;
        if (!en) return 0;
        // (pode cair: à noite, sem sol, os alarmes gastam 1 ⚡ por hora cada)
        return Math.max(0, Math.min(en.capacidade, Number(en.carga) + Number(en.por_hora) * Math.max(0, agora() - energiaEm) / 3600000));
    }
    function desenharEnergia() {
        if (!el.energia) return;
        const mostra = temEletrico();
        el.energia.hidden = !mostra;
        if (!mostra) return;
        const c = Math.floor(cargaAgora()), cap = S.energia.capacidade;
        cena.definirEnergia(cap ? c / cap : 0);
        const conta = S.energia.conta;   // fase 75: o saldo da conta (▲ sobra, ▼ falta)
        const sinal = conta && conta.gasta > 0 ? `<i class="saldo-energia ${conta.saldo >= 0 ? 'sobra' : 'falta'}" style="font-style:normal;font-size:10px;margin-left:2px;color:${conta.saldo >= 0 ? '#3e8948' : '#c34b35'}">${conta.saldo >= 0 ? '▲' : '▼'}</i>` : '';
        el.energia.innerHTML = `${ico('raio', 16)}<b>${c}</b><small>/${cap}</small>${sinal}`;
        el.energia.classList.toggle('vazia', c < 5);
        el.energia.title = `Energia: ${c} de ${cap} ⚡${conta ? ` · gera ${conta.gera}/h, gasta até ${conta.gasta}/h` : ''}`;
    }
    function descreverEnergia() {
        if (!temEletrico()) return;
        if (!painelAtual) abrirPainel('energia');
        const ph = Math.round(Number(S.energia.por_hora));
        const temSol = (S.construcoes || []).some((c) => c.tipo === 'painel_solar');
        const dia = A.faseDoDia(agora());
        mostrarStatus(`${ico('raio', 18)} <b>Energia</b>: ${Math.floor(cargaAgora())} de ${S.energia.capacidade} ⚡. ` +
            (ph > 0 ? `Entrando ${ph} ⚡/h agora.` : ph < 0 ? `Saindo ${-ph} ⚡/h agora (os alarmes gastam 1 ⚡ por hora cada)${temSol && dia.noite ? `; o painel solar volta a gerar às ${hora(dia.fim)}` : ''}.` : `Nada entrando agora${temSol && dia.noite ? ` (é noite no jogo: o painel solar volta a gerar às ${hora(dia.fim)})` : ''}.`) +
            textoVento() +
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
            ${temEletrico() ? htmlContaEnergia(en.conta) : ''}
            ${temEletrico() ? `<p>${ico('raio', 16)} Agora: <b>${carga}</b> de ${cap} ⚡ · entrando <b>${Math.round(Number(en.por_hora) || 0)}</b> ⚡ por hora.${textoVento()}</p>
                <p class="det">Bateria cheia: o que sobrar do sol, do vento e do reator é vendido sozinho, 1 ${ico('moeda', 12)} a cada 5 ⚡.</p>
                <span class="estoque-barra"><i style="width:${Math.round(carga / cap * 100)}%"></i></span>
                ${precoEnergiaDiamantes() > 0 ? `<p class="det">Com pressa? ${botaoDiamante('energia', precoEnergiaDiamantes(), 'Encher agora')} O <b>eletricista</b> (Loja → Ajudantes) faz tudo gastar menos.</p>` : ''}` : ''}
            <p class="aviso">Do nível 16 em diante a fazenda vira indústria: <b>geradores</b> enchem as <b>baterias</b>, e as <b>máquinas elétricas</b> gastam essa energia para trabalhar sozinhas por você. Sem energia elas só param; o resto da fazenda continua igual.</p>
            ${grupo('Geram energia', itens.filter((i) => gera.has(i.efeito)))}
            ${grupo('Guardam energia', itens.filter((i) => guarda.has(i.efeito)))}
            ${grupo('Trabalham por você (gastam energia)', itens.filter((i) => !gera.has(i.efeito) && !guarda.has(i.efeito)))}
            <div class="rodape-painel"><span></span><button type="button" class="botao verde" data-fechar>Entendi</button></div>`;
    }

    /* ---------- Fase 75: a conta da energia, como no Cities: Skylines ----------
       O servidor manda quanto a fazenda gera em média por hora e quanto gasta no máximo por hora, com tudo
       trabalhando sem parar (estado.energia.conta). */
    const NOME_GASTO = { oficinas: 'Oficinas na rede (puxar e entregar)', triturador: 'Triturador', robo_colheita: 'Robôs de colheita',
        bau: 'Baús', aspersor: 'Aspersores', estufa: 'Estufas', alarme: 'Alarmes' };
    function htmlContaEnergia(c) {
        if (!c) return '';
        const maior = Math.max(c.gera, c.gasta, 1), saldo = c.saldo;
        const barra = (v, cor) => `<span class="estoque-barra" style="--cor:${cor}"><i style="width:${Math.round(v / maior * 100)}%;background:${cor}"></i></span>`;
        const nome = (t) => NOME_GASTO[t] || ((tipoItem(t) || {}).nome || t);
        const lista = (l, sinal) => (l || []).map((k) => `<span>${esc(nome(k.tipo))}${k.n ? ` (${k.n})` : ''}: ${sinal}${k.h} ⚡/h</span>`).join('');
        return `<h3 class="secao-titulo">A conta da energia</h3>
            <p>Gera em média <b style="color:#3e8948">${c.gera} ⚡/h</b></p>${barra(c.gera, '#5fae4a')}
            <p class="det">${lista(c.gera_itens, '+') || '<span>Nenhum gerador ainda.</span>'}</p>
            <p>Gasta no máximo <b style="color:#c34b35">${c.gasta} ⚡/h</b>${c.desconto ? ` <small>(já com ${c.desconto}% de desconto${meuAjudante('eletricista') ? ', com o eletricista' : ''})</small>` : ''}</p>${barra(c.gasta, '#d9654a')}
            <p class="det">${lista(c.gasta_itens, '−') || '<span>Nada gastando ainda.</span>'}</p>
            <p class="${saldo >= 0 ? 'det' : 'aviso'}"><b>${saldo >= 0 ? `Sobram ${saldo} ⚡/h` : `Faltam ${-saldo} ⚡/h`}</b> com tudo trabalhando sem parar.
                ${saldo < 0 ? 'Construa mais painéis, turbinas, geradores a biomassa ou o reator (o 2º libera no nível 40), ou contrate e evolua o <b>eletricista</b>.' : 'No dia a dia gasta menos: as máquinas só trabalham quando tem o que fazer.'}</p>`;
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
    // volta do Mercado Pago: fazenda.html?compra=ID (mais os parâmetros dele, que saem da barra de endereço)
    let compraDoLink = null;
    try {
        const url = new URL(location.href);
        const id = url.searchParams.get('compra') || '';
        if (/^[0-9a-f-]{36}$/i.test(id)) compraDoLink = id;
        if (url.searchParams.has('compra')) {
            ['compra', 'collection_id', 'collection_status', 'payment_id', 'status', 'external_reference', 'payment_type',
                'merchant_order_id', 'preference_id', 'site_id', 'processing_mode', 'merchant_account_id'].forEach((k) => url.searchParams.delete(k));
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
        if (com.length) toast(`${ico('coracao', 16)} ${nomes(com)} entrou pelo seu convite: +${com.length * premioConvite().dono} ${ico('moeda', 14)}!`, 'festa', 'importante');
        if (sem.length) toast(`${ico('coracao', 16)} ${nomes(sem)} entrou pelo seu convite (os prêmios de hoje já acabaram, volta amanhã).`, undefined, 'importante');
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
    const NIVEL_MAX = 45;   // fase 61: o litoral e o alto-mar vão do 31 ao 45
    const presenteNivel = (n) => (n > 10 ? 100 : 50) * n;   // do 10 em diante sobe devagar, e o presente dobra
    const limiteCanteirosNivel = (n) => Math.min(6 + (n - 1) * 2, 94);   // fase 69: +2 por nível até o 45 (parava no 25)
    // Colher dá o XP cheio da planta, mas o mesmo canteiro no máximo 1 vez a cada 8 min (igual a
    // fazenda_aplicar: canteiros.xp_em). Vender dá 1 XP a cada 25 moedas, só dos produtos.
    const XP_PAUSA = 8 * 60000, XP_VENDA = 25;
    const xpDaColheita = (c, k) => (!c || !c.xp_em || agora() - Date.parse(c.xp_em) >= XP_PAUSA ? k.xp : 0);
    const xpVendaDe = (k) => (k.tipo === 'produto' ? 1 : 0);   // (fase 60: raro não vende para o jogo)
    const ORDEM_TIPO = { Terreno: 0, Mar: 1, Melhoria: 1, Ajudante: 1, Oficina: 1, 'Máquina': 1, Energia: 1, Animal: 2, Cercado: 2, 'Árvore': 2, Semente: 3, Casa: 4, Enfeite: 5 };
    function liberaNoNivel(n) {
        if (!S) return [];
        const r = [];
        for (const z of zonasVenda()) if (z.nivel === n) r.push({ html: spr(39, 24), nome: z.lago ? `${z.nome} (com lago)` : z.nome, tipo: 'Terreno' });
        for (const a of S.animais_tipos || []) if (a.nivel_min === n) r.push({ html: spr(A.ANIMAL[a.id], 24), nome: a.nome, tipo: 'Animal' });
        for (const t of S.ajudantes_tipos || []) if (t.nivel_min === n) r.push({ html: retratoAjudante(t.id, 24), nome: `${t.nome} (${t.papel.toLowerCase()})`, tipo: 'Ajudante' });
        for (const m of S.melhorias_tipos || []) m.niveis.forEach((k, ix) => {   // fase 62 (fase 70: e as da fazenda, que não apareciam)
            if (k.nivel !== n) return;
            r.push(m.mar ? { html: iconeMar(m.id, 24), nome: k.nome, tipo: 'Mar' }
                : { html: A.htmlItem(m.id === 'adubo' ? 'canteiro' : 'laranjeira', 24), nome: `${m.nome}${m.niveis.length > 1 ? ' ' + (ix + 1) : ''}`, tipo: 'Melhoria' });
        });
        for (const k of S.culturas) if (k.tipo === 'cultura' && k.nivel_min === n) r.push({ html: itemDe(k, 24), nome: k.estacao ? `${k.nome} (${NOME_ESTACAO[k.estacao]})` : k.nome, tipo: 'Semente' });
        for (const i of S.itens || []) {
            if (i.nivel_min !== n) continue;
            const tipo = i.categoria === 'maquina' ? 'Máquina' : i.categoria === 'energia' ? 'Energia' : i.categoria === 'oficina' ? 'Oficina' : i.categoria === 'construcao' ? 'Casa' : i.categoria === 'bichos' ? 'Cercado' : i.categoria === 'pomar' ? 'Árvore' : i.categoria === 'praia' ? 'Praia' : 'Enfeite';
            r.push({ html: A.htmlItem(i.id, 24), nome: i.nome, tipo });
        }
        return r.sort((a, b) => ORDEM_TIPO[a.tipo] - ORDEM_TIPO[b.tipo]);
    }
    // extras de todo nível: canteiros a mais, o presente de moedas e 5 diamantes (10 no começo)
    function extrasDoNivel(n) {
        const mais = n > 1 ? limiteCanteirosNivel(n) - limiteCanteirosNivel(n - 1) : limiteCanteirosNivel(1);
        return { canteiros: mais, moedas: n > 1 ? presenteNivel(n) : 0, diamantes: n > 1 ? 5 : 10 };
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
    const limitePegar = (k) => Math.floor(k.rendimento * 0.5);
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
    // fase 66: a luva do Perks passa pelo alarme (1 luva por canteiro protegido)
    const luvas = () => (S ? livreFeira('luva_perks') : 0);
    const podeLuva = (c, i) => i.fase === 'maduro' && !c.ja_peguei && c.roubado < limitePegar(i.k) && protegidoAlarme(c) && luvas() > 0;
    function acaoVisita(c) {
        const i = info(c);
        if (i.fase === 'murcho' && visita && visita.pode_salvar !== false && 'pode_salvar' in visita) return 'salvar';   // fase 48
        if ((i.fase === 'crescendo' || i.fase === 'maduro') && i.probs.length) return 'ajudar';
        if (podePegar(c, i)) return 'pegar';
        if (podeLuva(c, i)) return 'pegar_luva';
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
    // fase 74: até o nível 5 (o 4 pede o nível 35 do jogador e o 5, o 42: igual a fazenda_contratar)
    const NIVEL_MAX_AJUDANTE = 5, EVOLUIR_NIVEL = { 4: 35, 5: 42 };
    const RITMO = [0, 12, 30, 90, 150, 240];
    const DESCONTO_ELETRICISTA = ['', '−20%', '−35%', '−50%', '−60%', '−67%'];   // igual a fazenda_energia_preco
    // fase 54: cuidador de bicho (no máximo 5 de cada, então o ritmo não importa): quanto ele adianta
    // a espécie dele no tempo de produção (igual a fazenda_cuidador_adianta)
    const ADIANTA_CUIDADOR = ['', '−10%', '−20%', '−30%', '−40%', '−50%'];
    // o que o nível do ajudante faz, em texto
    const efeitoAjudante = (t, nivel) => t.funcao === 'energia' ? DESCONTO_ELETRICISTA[nivel] + ' de energia'
        : t.funcao === 'animal' ? ADIANTA_CUIDADOR[nivel] + ' no tempo dos bichos'
        : RITMO[nivel] + ' por hora';
    const custoAjudante = (t, nivel) => t.custo * [1, 4, 8, 16, 32][nivel || 0];   // contratar e evoluir até o 5 (fase 72: eram 2x e 4x; fase 74: 4 e 5)

    /* ---------- Fase 59: a tela do ajudante ----------
       O que ele fez hoje e ontem (estado.ajudantes[].hoje/ontem), a barra de energia (a cheia dura 8 h de
       trabalho; vazia, ele descansa 2 h sozinho) e o botão de mandar descansar (1 h). */
    let ajudanteAberto = null;
    const FEITO_AJUDANTE = {
        colheu: ['colheu', 'canteiro'], frutas: ['colheu', 'árvore do pomar', 'árvores do pomar'],
        arou: ['arou', 'canteiro'], adubou: ['adubou', 'canteiro'], plantou: ['plantou', 'canteiro'],
        erva: ['tirou', 'erva daninha', 'ervas daninhas'], praga: ['tirou', 'praga'], seco: ['regou', 'canteiro seco', 'canteiros secos'],
        coletou: ['coletou', 'vez dos bichos', 'vezes dos bichos'], alimentou: ['deu ração', 'vez', 'vezes'],
        levou: ['levou ao celeiro', 'produto'], encheu: ['encheu', 'receita']
    };
    const descansando = (h) => !!h.descanso_ate && Date.parse(h.descanso_ate) > agora();
    function listaFeito(feito) {
        const itens = Object.entries(feito || {}).filter(([, n]) => n > 0).map(([k, n]) => {
            const [verbo, um, varios] = FEITO_AJUDANTE[k] || [k, 'vez', 'vezes'];
            return `<li>${esc(verbo)} <b>${n}</b> ${esc(n === 1 ? um : varios || um + 's')}</li>`;
        });
        return itens.length ? `<ul class="feito-ajudante">${itens.join('')}</ul>` : '<p class="det">Nada ainda.</p>';
    }
    function htmlAjudante(t, h) {
        const estrelas = [1, 2, 3, 4, 5].map((n) => (n <= h.nivel ? '★' : '☆')).join('');
        const topo = `<div class="perfil-avatar">${retratoAjudante(t.id, 64)}<div>
                <p><b>${esc(t.papel)}</b> · <span class="estrelas">${estrelas}</span> nível ${h.nivel} · ${efeitoAjudante(t, h.nivel)}</p>
                <p class="det"><span class="txt">${esc(t.descricao)}</span></p></div></div>`;
        if (t.funcao === 'energia') {
            return topo + '<p class="aviso">O Faísca não faz tarefas: ele deixa tudo o que é elétrico gastar menos, o tempo todo. Por isso não cansa.</p>';
        }
        const e = Math.max(0, Math.min(100, Number(h.energia) || 0));
        const horas = Math.round((e / 100) * 8 * 10) / 10;
        const parado = descansando(h);
        const camas = S.camas || { total: 1, ocupadas: 0 }, livres = Math.max(0, camas.total - camas.ocupadas);
        const onde = h.descanso_casa === false ? 'na sombra, porque não tinha cama livre' : 'numa cama da casinha';
        const status = parado
            ? `${ico('lua', 14)} <b>Descansando</b> ${onde} até ${hora(h.descanso_ate)} (${h.descanso_motivo === 'mandado' ? 'você mandou' : 'cansou depois de muito trabalho'}). Volta com a energia cheia.`
            : `Energia para mais ${String(horas).replace('.', ',')} h de trabalho sem parar. Quando acabar, ele descansa sozinho: 2 h numa cama livre ou 4 h na sombra.`;
        const linhaCamas = `<p class="det"><span class="txt"><b>Camas:</b> ${camas.ocupadas} de ${camas.total} ocupada${camas.ocupadas === 1 ? '' : 's'}. A casa da fazenda tem 1; cada casinha vermelha dá mais 1 e cada azul mais 2 (Construir → Casas).</span></p>`;
        return topo + `
            <h3 class="secao-titulo">Energia</h3>
            <div class="barra-energia${parado ? ' parado' : e < 20 ? ' pouca' : ''}" title="${Math.round(e)}%"><i style="width:${parado ? 0 : e}%"></i></div>
            <p class="det"><span class="txt">${status}</span></p>
            ${linhaCamas}
            <h3 class="secao-titulo">Hoje ele</h3>${listaFeito(h.hoje)}
            <h3 class="secao-titulo">Ontem</h3>${listaFeito(h.ontem)}
            <div class="rodape-painel">
                <span></span>
                ${parado ? '<span class="preco">Descansando</span>'
                    : e >= 75 ? `<span class="preco" title="Só dá para mandar descansar com menos de 75% de energia">Bem disposto (${Math.round(e)}%)</span>`
                    : livres ? `<button type="button" class="botao creme" data-ajudante-descansar="${esc(t.id)}">${ico('lua', 16)} Mandar descansar (1 h)</button>`
                    : '<span class="preco">Sem cama livre</span>'}
            </div>
            ${t.funcao === 'colher' ? htmlMurchasJuca() : ''}
            <p class="aviso">Descansar recupera a energia toda. Descansando, ele não trabalha nem junta tarefas para depois. Só dá para mandar descansar com <b>menos de 75%</b> de energia, e precisa de uma cama livre: mais casinhas, mais ajudantes descansando ao mesmo tempo. Ele dorme na casa (tocar nela mostra quem está lá).</p>`;
    }
    /* ---- fase 66: por que a planta murchou (o servidor registra o motivo de cada uma) ---- */
    const DICA_MURCHA = {
        sem_colhedor: 'Contrate o Juca, o colhedor (Loja → Ajudantes, nível 10): ele colhe sozinho antes de murchar.',
        descansando: 'Construa casinhas (Construir → Casas): com cama livre ele descansa só 2 h, em vez de 4 h na sombra.',
        fechada: 'O Juca guarda no máximo 8 h de trabalho: volte antes disso ou plante o que demora mais para murchar.',
        nao_deu_conta: 'Evolua o Juca (Loja → Ajudantes) ou sirva o café dos ajudantes (diamantes): ele colhe mais por hora.'
    };
    function textoMurcha(motivo, d, n) {
        const plantas = n == null ? 'A planta murchou' : n > 1 ? `${n} plantas murcharam` : '1 planta murchou';
        d = d || {};
        if (motivo === 'sem_colhedor') return `${plantas} porque você ainda não tem colhedor.`;
        if (motivo === 'descansando') return `${plantas} enquanto o Juca dormia ${d.como === 'sombra' ? `na sombra (${d.horas || 4} h: não tinha cama livre)` : d.como === 'mandado' ? '(você mandou descansar)' : `na cama (${d.horas || 2} h)`}.`;
        if (motivo === 'fechada') return `${plantas} com a fazenda fechada há mais de 8 h: o Juca só cobre 8 horas.`;
        return `${plantas} porque o Juca não deu conta: no nível ${d.nivel || 1} ele colhe ${d.ritmo || 12} por hora, e tinha mais canteiro maduro que isso.`;
    }
    function htmlMurchas(lista) {
        return '<div class="lista">' + lista.map((m) => `<div class="item"><span class="ico">${ico(m.motivo === 'descansando' ? 'lua' : m.motivo === 'sem_colhedor' ? 'ajuda' : 'sino', 28)}</span>
            <span><span class="nome">${textoMurcha(m.motivo, m.detalhe, m.qtd)}</span><span class="det"><span class="txt">${DICA_MURCHA[m.motivo] || ''}</span></span></span></div>`).join('') + '</div>';
    }
    function htmlMurchasJuca() {
        const dia = (S.murchas && S.murchas.dia) || {}, total = Object.values(dia).reduce((a, b) => a + b, 0);
        return `<h3 class="secao-titulo">Nas últimas 24 h</h3>` + (total
            ? htmlMurchas(Object.entries(dia).map(([motivo, qtd]) => ({ motivo, qtd })))
            : '<p class="det">Nenhuma planta murchou sem ele colher. Bom trabalho, Juca!</p>');
    }
    let murchasNovas = [];
    /* ---- fase 67: novidades. A cada atualização do jogo entra uma no começo da lista: quem abre o jogo
       vê uma vez o resumo do que mudou desde a última vez (o que já viu fica guardado no aparelho).
       Quem acabou de criar a fazenda não vê as antigas. Dá para reler em Ajuda → Novidades. ---- */
    const NOVIDADES = [
        { id: '2026-10-18-agua2', data: '18/10', titulo: 'A água refeita', itens: [
            'A água do lago, do laguinho dos patos e do <b>mar</b> foi refeita: brilhinhos que acendem e apagam, <b>peixes nadando</b> de um lado para o outro, a espuma da onda indo e voltando na areia e, de vez em quando, um peixe pulando.',
            'Os <b>patos</b> nadando ficam com metade do corpo dentro da água; fora dela, aparecem inteiros.',
            'O laguinho dos patos ficou menor, com chão em volta: o cuidador anda à direita e embaixo dele.'] },
        { id: '2026-10-18-energia', data: '18/10', titulo: 'A conta da energia e o reator forte', itens: [
            'No painel da <b>energia</b> (toque no ⚡ lá em cima) aparece a conta, como no Cities: Skylines: quanto a fazenda <b>gera</b> em média por hora e quanto <b>gasta no máximo</b>, com tudo trabalhando. Ao lado do ⚡, um ▲ verde quando sobra e um ▼ vermelho quando falta.',
            'O <b>reator</b> agora dá <b>700 ⚡/h</b> (500 na onda de calor; eram 120), e no <b>nível 40</b> libera o 2º reator. Com tudo no máximo, a fazenda fica no positivo até sem o eletricista.',
            'A radiação do reator é sorteada a cada <b>30 minutos</b>: mais bichos radioativos dando produto de 2 em 2 minutos.'] },
        { id: '2026-10-18-agua', data: '18/10', titulo: 'Vender rápido e água de verdade', itens: [
            '<b>Vender produtos</b> agora vai tudo de uma vez: o jogo não fica mais parado alguns segundos.',
            'Ninguém mais anda em cima da água: o fazendeiro, os ajudantes e as visitas contornam o lago e o laguinho dos patos (os patos continuam nadando).',
            'A água do lago e do laguinho dos patos <b>mexe</b>: ondinhas, brilhos e, de vez em quando, um peixe pulando.',
            'Os <b>baús da sorte</b> não dão mais moedas: só itens, diamantes e, bem raramente, um item raro.'] },
        { id: '2026-10-17-conteudo2', data: '17/10', titulo: 'Cabra, búfala, peixes do mar e ajudantes 5 estrelas', itens: [
            '<b>Cabra</b> (nível 33) e <b>búfala</b> (38), com o capril e o curral delas e as cuidadoras <b>Dona Zefa</b> e <b>Seu Badu</b>. A <b>queijaria de búfala</b> (40) faz mussarela.',
            'Os peixes do mar viram receita: <b>enlatados</b> (33, sardinha em lata), <b>sushi</b> (39, sashimi) e <b>caldeirada</b> (42).',
            '<b>Ajudantes nos níveis 4 e 5</b>: o 4 libera no nível 35 e o 5 no 42. Trabalham 150 e 240 tarefas por hora; o eletricista economiza 60% e 67%; os cuidadores deixam os bichos 40% e 50% mais rápidos.',
            'Melhorias novas: <b>adubo 4</b> (36), <b>pomar fértil 3</b> (39) e <b>mais pés 3</b> (41).'] },
        { id: '2026-10-17-viagens', data: '17/10', titulo: 'Itens pelo cano', itens: [
            'Depois de mudar uma oficina ou um baú de lugar, os itens não aparecem mais voando por cima da fazenda: só passam pelo cano.'] },
        { id: '2026-10-17-tocar-mover', data: '17/10', titulo: 'Mudar de lugar com um toque', itens: [
            'No <b>Construir</b>, toque numa oficina, casa, máquina ou enfeite que já está na fazenda para pegar e mudar de lugar, mesmo com outro item escolhido na barra (antes aparecia "não cabe aqui"). Se o lugar novo não couber, ele continua na mão até você escolher outro.'] },
        { id: '2026-10-17-mover', data: '17/10', titulo: 'Mover ficou mais leve', itens: [
            'Mover oficinas e outros itens de lugar não trava mais o jogo, mesmo movendo várias coisas seguidas: o item vai para o lugar novo na hora e os canos já mostram a ligação nova.'] },
        { id: '2026-10-17-conteudo', data: '17/10', titulo: 'Árvores, praia e o baú da sorte', itens: [
            'Do <b>nível 31 ao 45</b> tem árvore nova a cada 3 níveis: <b>coqueiro</b> (31), <b>cajueiro</b> (34), <b>açaizeiro</b> (37), <b>cupuaçuzeiro</b> (40) e <b>castanheira</b> (43). Cada uma tem a sua oficina no nível seguinte: cocada, cajuína, açaí na tigela, creme de cupuaçu e paçoca.',
            '<b>Sementes de estação</b> novas: maracujá (verão, 33), mexerica (inverno, 36), caqui (outono, 39) e lichia (primavera, 42). Fora da estação, só na estufa.',
            '<b>Praia</b> (Construir → Praia): guarda-sol, cadeira, castelo de areia, barraca de coco e coqueiro, só na areia do Litoral.',
            '<b>Baú da sorte</b> (Loja → Baús): madeira por 50 mil, prata por 250 mil e ouro por 1 milhão. Vem de tudo, até item raro, mas é sorte: quase sempre volta menos do que custou.'] },
        { id: '2026-10-17-numeros', data: '17/10', titulo: 'Preços novos e diamantes rendendo mais', itens: [
            'Do <b>nível 20 em diante</b> as moedas estavam sobrando: o que libera do 20 para cima (construções, oficinas, árvores do pomar e os terrenos 6 e 7) ficou <b>2,5 vezes mais caro</b>, e as <b>melhorias</b> e <b>evoluir ajudante</b>, 2 vezes. As sementes continuam com o mesmo preço.',
            'Guardar uma construção devolve a metade do que <b>você pagou</b> por ela.',
            '<b>Triturador</b>: agora custa 40 mil e gasta 15 ⚡ por receita, e dá +50% (uma receita sim, outra não, sai 1 produto a mais) em vez do dobro.',
            'O que os <b>ajudantes, robôs e baús colhem dá metade do XP</b> (antes não dava nada). <b>Missões</b> e <b>visitas</b> dão bem mais XP no fim do jogo, e a mascate aduba mais canteiros.',
            '<b>Alface</b> cresce em 5 min. Adega e vinícola ficaram em 2 h, geleia em 1 h e queijo em 1 h 30.',
            '<b>Diamantes</b>: 1 enche 150 ⚡, o café dos ajudantes dura 4 h, salvar murchas custa 1 a cada 25 plantas e colher agora custa 1 a cada 4 h que faltam.',
            '<b>Conquistas dão diamantes</b>: os níveis 10, 15, 20, 25, 30, 35 e 40 dão o número do nível; o 45, 100; o Velho Chico, 20; o marlim, 50. Quem já tinha ganhou agora.'] },
        { id: '2026-10-17-leve', data: '17/10', titulo: 'Servidor mais leve', itens: [
            'O aviso de <b>servidor sobrecarregado</b> deve aparecer bem menos: o trabalho dos ajudantes, dos robôs e dos baús ficou de 2 a 5 vezes mais rápido no servidor, principalmente quando você volta depois de horas fora.',
            'Nada muda no que eles fazem: colhem, plantam e cuidam igual a antes.',
            'O placar do evento atualiza de minuto em minuto, e o chat busca mensagens novas de 10 em 10 segundos.',
            'A virada da semana do evento (sexta às 22h) não trava mais o jogo de ninguém.'] },
        { id: '2026-10-17-seguranca', data: '17/10', titulo: 'Jogo mais justo e seguro', itens: [
            'Fechamos brechas que davam diamantes, itens e XP de graça para quem mexia no jogo por fora. Quem joga normal não perde nada.',
            '<b>Evento da semana</b>: o XP comprado com diamantes não conta mais no ranking, o convite conta quando o amigo chega ao <b>nível 10</b> e, na barraca, a mesma pessoa do outro lado vale no máximo 25% do total.',
            '<b>Fazenda completa</b> (do 20 em diante): o XP de arar e plantar agora vem junto na colheita (+2).',
            '<b>Calendário</b>: as moedas ficaram bem maiores (crescem com o presente do nível) e a trilha dourada troca a luva do Perks por peças do píer.',
            'A <b>doceira</b> volta a pedir os produtos novos das oficinas, tem <b>conquista nova nos níveis 15, 30, 35 e 40</b> (quem já passou ganha na hora) e o caminho dos níveis mostra também as melhorias da fazenda.'] },
        { id: '2026-10-17-calendario', data: '17/10', titulo: 'Calendário de prêmios e mais canteiros', itens: [
            'No menu tem o <b>Calendário</b>: um prêmio por dia, 28 dias. Faltou um dia? Não perde: pega o seguinte. Os dias 7, 14, 21 e 28 dão diamantes.',
            'A <b>trilha dourada</b> (com diamantes) dá um prêmio a mais todo dia e, no dia 28, o <b>Fazendeiro de ouro</b>, que só sai lá.',
            'Agora você ganha <b>+2 canteiros a cada nível até o 45</b> (antes parava no 25).',
            'No caminho dos níveis, as melhorias do mar ganharam figuras de verdade: barco, vara, motor, sonar, caixa de gelo, rede e bússola.',
            'O <b>Faísca</b> saiu do meio da plantação: agora com um alicate na mão, ele fica no meio dos painéis solares, turbinas e baterias, mexendo neles. Sem nenhum deles, anda pela estradinha.'] },
        { id: '2026-10-17-luzes', data: '17/10', titulo: 'Luzes da noite', itens: [
            'Postes perto um do outro agora juntam a luz numa área só, sem encolher e sem ficar estourado.',
            'A luz dos canos ficou bem mais discreta: é só um sinal da rede.'] },
        { id: '2026-10-17-ordem', data: '17/10', titulo: 'Construir em ordem e a luz dos canos', itens: [
            'No <b>Construir</b>, as oficinas (e o resto) agora aparecem por nível: o que você já pode construir vem primeiro, e o que ainda está travado fica no fim.',
            'A luz dos <b>canos</b> mostra o que a rede está fazendo: a onda verde corre quando uma oficina da rede está trabalhando; ligada mas parada, fica só uma luzinha fraca.'] },
        { id: '2026-10-17-reator', data: '17/10', titulo: 'As ajudantes, o eletricista e o reator', itens: [
            'As <b>ajudantes</b> agora são cada uma de um jeito: a granjeira de chapéu de palha, a coelheira de lenço, a semeadora de avental, a pastora de lenço na cabeça e a operária de capacete.',
            'O <b>eletricista</b> solta faíscas: 1 raiozinho por nível.',
            'O <b>reator</b> pode deixar um bicho <b>radioativo</b> (1 em 200 por hora para cada bicho): por meia hora ele brilha verde e dá o produto a cada 2 minutos, direto no celeiro. No fim, 1 em 200 de ele não resistir.'] },
        { id: '2026-10-17-chat', data: '17/10', titulo: 'Chat de todos os jogadores', itens: [
            'No menu tem <b>Chat</b>: converse com todo mundo (as mensagens somem em 1 hora). Escreve do nível 5; ler, todo mundo lê.',
            '<b>Pedir item</b>: diga o que você procura, quantos e quanto paga cada. Quem tiver toca em <b>Vender</b> e o lote vai para a barraca dele, <b>separado para você por 2 horas</b>.',
            'Sem palavrão e sem link. Dá para silenciar alguém e visitar a fazenda de quem escreveu.'] },
        { id: '2026-10-17-praia', data: '17/10', titulo: 'A praia, as luzes da noite e as novidades', itens: [
            'A <b>praia</b> agora aparece no celular também: arraste até lá embaixo para ver a areia e o mar.',
            'Na areia não tem mais mata: são <b>coqueiros, dunas, pedras e conchas</b>. Enquanto a praia não é sua, uma duna fecha a passagem; a placa mostra onde comprar.',
            'As <b>luzes da noite</b> não fazem mais aquela sombra entre os lampiões, e os <b>canos</b> brilham redondinho.',
            'Toda atualização agora aparece aqui, uma vez, com o resumo do que mudou.'] },
        { id: '2026-10-17-perks', data: '17/10', titulo: 'O Perks, o relatório das murchas e os ajudantes', itens: [
            'O <b>Perks</b> (homenagem ao 1º do ranking) aparece na porteira de vez em quando, pede muita planta fácil e paga com a <b>Luva do Perks</b>: cada luva passa por 1 canteiro com alarme quando você visita um vizinho.',
            'Quando uma planta <b>murcha</b> sem ninguém colher, o jogo conta o porquê: sem colhedor, o Juca descansando, a fazenda fechada mais de 8 h ou canteiro demais para o nível dele.',
            '<b>Mandar descansar</b> só com menos de 75% de energia. O ajudante vai até a casa e sai zzz do telhado; toque na casa para ver quem dorme.',
            'A <b>fazendeira</b> e as <b>ajudantes</b> agora têm cabelo comprido.'] }
    ];
    let novidadesVer = null, novidadesChecadas = false;
    const paineisDepois = [];   // painéis que abrem sozinhos quando fechar o que está aberto (novidades, calendário)
    function checarNovidades(estado) {
        if (novidadesChecadas) return;
        novidadesChecadas = true;
        const visto = store.get(LS.novidades), nova = Date.now() - new Date(estado.criado_em || 0).getTime() < 86400e3;
        if (visto === null && nova) { store.set(LS.novidades, NOVIDADES[0].id); return; }   // fazenda nova: as antigas não interessam
        const ate = NOVIDADES.findIndex((n) => n.id === visto);
        const lista = ate === -1 ? NOVIDADES.slice(0, visto === null ? 2 : 1) : NOVIDADES.slice(0, ate);
        if (!lista.length) return;
        novidadesVer = lista;
        if (!painelAtual) abrirPainel('novidades');
        else paineisDepois.push('novidades');   // abre quando fechar o que está aberto (o relatório das murchas, o prêmio...)
    }
    const retratoAjudante = (id, px) => {
        const a = A.AJUDANTE_ARTE[id] || { p: 'factory', i: 120 };
        return (A.htmlAjudante && A.htmlAjudante(id, px)) || spr(a.i, px, a.p);   // fase 68: as moças, cada uma de um jeito
    };
    function areaAjudante(t) {
        if (t.funcao === 'energia') return 'energia';   // fase 69: o Faísca não mexe na roça: anda no meio dos painéis e turbinas (sem eles, na estradinha)
        return t.funcao === 'animal' ? t.alvo : 'campo';
    }
    /* ---- fase 66: quem dorme onde ----
       As camas: 1 na casa da fazenda, 1 em cada casinha vermelha e 2 em cada azul (igual a fazenda_camas).
       Quem descansa numa cama vai até a porta da casa e entra (da casa saem os zzz); quem descansa na
       sombra fica parado onde está. Tocar na casa diz quem está dormindo nela. */
    const DURACAO_DESCANSO = (h) => (h.descanso_motivo === 'mandado' ? 1 : h.descanso_casa === false ? 4 : 2) * 3600e3;
    function camasDaFazenda() {
        const casas = [{ chave: 'casa', nome: 'Casa da fazenda', x: A.MAPA.casa.x, y: A.MAPA.casa.y, camas: 1 }];
        for (const c of S.construcoes || []) {
            if (c.tipo === 'casa_vermelha' || c.tipo === 'casa_azul') {
                casas.push({ chave: c.x + ',' + c.y, nome: c.tipo === 'casa_azul' ? 'Casinha azul' : 'Casinha vermelha', x: c.x, y: c.y, camas: c.tipo === 'casa_azul' ? 2 : 1 });
            }
        }
        return casas;
    }
    function quemDormeOnde() {
        const camas = [];
        for (const c of camasDaFazenda()) for (let k = 0; k < c.camas; k++) camas.push(c);
        const ordem = (S.ajudantes_tipos || []).map((t) => t.id);
        const dormindo = (S.ajudantes || []).filter((h) => descansando(h) && h.descanso_casa !== false)
            .sort((a, b) => ordem.indexOf(a.tipo) - ordem.indexOf(b.tipo));
        const onde = new Map();
        dormindo.forEach((h, k) => { if (camas[k]) onde.set(h.tipo, camas[k]); });
        return onde;
    }
    function visualAjudantes() {
        if (!S || visita) return [];
        const onde = quemDormeOnde();
        return (S.ajudantes || []).map((h) => {
            const t = tipoAjudante(h.tipo);
            if (!t) return null;
            let dormir = null;
            if (descansando(h)) {
                const casa = onde.get(h.tipo), comecou = Date.parse(h.descanso_ate) - DURACAO_DESCANSO(h);
                dormir = casa ? { casa: casa.chave, x: casa.x + 1, y: casa.y + 2, telhadoX: casa.x + 1, telhadoY: casa.y, ja: comecou < agora() - 30000 }
                    : { sombra: true };
            }
            return { id: 'h:' + h.tipo, tipo: h.tipo, area: areaAjudante(t), dormir, nivel: h.nivel };
        }).filter(Boolean);
    }
    function descreverCasa(chave) {
        const casa = camasDaFazenda().find((c) => c.chave === chave);
        if (!casa) return false;
        const quem = [...quemDormeOnde().entries()].filter(([, c]) => c.chave === chave).map(([tipo]) => {
            const t = tipoAjudante(tipo), h = meuAjudante(tipo);
            return `${retratoAjudante(tipo, 18)} <b>${esc(t ? t.nome : tipo)}</b> dormindo até ${hora(h.descanso_ate)}`;
        });
        mostrarStatus(`${ico('lua', 16)} <b>${casa.nome}</b> (${casa.camas} cama${casa.camas > 1 ? 's' : ''}): ` + (quem.length ? quem.join(' · ') + '. Zzz…' : 'ninguém dormindo agora.'));
        return true;
    }
    function descreverAjudante(id) {
        const t = tipoAjudante(id), h = meuAjudante(id);
        if (!t || !h) return;
        mostrarStatus(`${retratoAjudante(id, 22)} <b>${esc(t.nome)}</b>, ${esc(t.papel.toLowerCase())} nível ${h.nivel}: ${esc(t.descricao)} (${efeitoAjudante(t, h.nivel)})`);
    }
    // o que os ajudantes fizeram desde a última olhada (vem uma vez só do servidor)
    function avisarAjudantes(estado) {
        const UNIDADE = { colher: ['fez', 'colheitas'], arar: ['arou ou adubou', 'canteiros'], plantar: ['plantou', 'canteiros'], cuidar: ['resolveu', 'problemas'], animal: ['fez', 'tarefas'],
            oficina: ['levou ou guardou', 'receitas'] };
        const partes = (estado.ajudantes || []).filter((h) => h.relatorio > 0).map((h) => {
            const t = (estado.ajudantes_tipos || []).find((x) => x.id === h.tipo);
            if (!t || !UNIDADE[t.funcao]) return '';
            const [verbo, coisa] = UNIDADE[t.funcao];
            return `${esc(t.nome)} ${verbo} ${h.relatorio} ${h.relatorio === 1 ? coisa.replace(/s$/, '') : coisa}`;
        }).filter(Boolean);
        if (partes.length) toast(`${retratoAjudante((estado.ajudantes.find((h) => h.relatorio > 0) || {}).tipo, 20)} Seus ajudantes trabalharam: ${partes.join(' · ')}`, undefined, 'importante');
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
    const diamAvatar = (tipo) => ((S.jogador.avatar_diamantes || {})[tipo]) || 0;   // fase 43: os de diamante
    const exclusivoAvatar = (tipo) => tipo in (S.jogador.avatar_exclusivos || {});   // fase 69: só ganhando (calendário dourado)
    const temAvatar = (tipo) => (S.jogador.avatares || []).includes(tipo) || (!exclusivoAvatar(tipo) && !precoAvatar(tipo) && !diamAvatar(tipo));
    // o servidor ainda sem a fase 43 não vende os de diamante: eles nem aparecem
    const avatarAVenda = (id) => id in (S.jogador.avatar_precos || {}) || id in (S.jogador.avatar_diamantes || {}) || exclusivoAvatar(id) || !S.jogador.avatar_precos;
    const etiquetaAvatar = (id) => exclusivoAvatar(id) ? (temAvatar(id) ? 'seu' : `${ico('calendario', 11)} dourado`)
        : temAvatar(id) ? (precoAvatar(id) || diamAvatar(id) ? 'seu' : 'grátis')
        : diamAvatar(id) ? `${ico('diamante', 11)} ${diamAvatar(id)}` : `${ico('moeda', 11)} ${precoAvatar(id).toLocaleString('pt-BR')}`;
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
            <div class="av-linha"><span class="av-titulo">Personagem</span><div class="av-opcoes">${Object.entries(A.AVATAR_TIPOS).filter(([id]) => avatarAVenda(id)).map(([id, t]) =>
                `<button type="button" class="av-op chapeu${a.tipo === id ? ' ativa' : ''}" data-av="tipo:${id}">${A.htmlAvatar({ ...a, tipo: id }, 40)}<small>${t.nome}</small><small class="av-preco">${etiquetaAvatar(id)}</small></button>`).join('')}</div></div>
            ${['chapeu', 'cabelo', 'pele', 'roupa', 'calca'].filter((r) => tipo.regioes[r]).map(linha).join('')}
            <p class="det">A primeira bolinha de cada linha é a cor original do personagem. Seus vizinhos veem esse avatar no ranking e quando visitam a sua fazenda.</p>
            <div class="rodape-painel">
                <button type="button" class="botao creme" data-painel-ir="conta">Cancelar</button>
                ${temAvatar(a.tipo)
                    ? '<button type="button" class="botao verde" data-av-salvar>Salvar</button>'
                    : exclusivoAvatar(a.tipo)
                    ? `<button type="button" class="botao creme" data-painel-ir="calendario">${ico('calendario', 14)} Só no dia 28 do calendário dourado</button>`
                    : diamAvatar(a.tipo)
                    ? `<button type="button" class="botao verde" data-av-salvar${(S.jogador.diamantes || 0) >= diamAvatar(a.tipo) ? '' : ' disabled'}>Comprar ${esc(tipo.nome.toLowerCase())} por ${ico('diamante', 14)} ${diamAvatar(a.tipo)}</button>`
                    : `<button type="button" class="botao verde" data-av-salvar${S.jogador.moedas >= precoAvatar(a.tipo) ? '' : ' disabled'}>Comprar ${esc(tipo.nome.toLowerCase())} por ${ico('moeda', 14)} ${precoAvatar(a.tipo).toLocaleString('pt-BR')}</button>`}
            </div>`;
    }

    /* ---------- Fase 60: materiais raros do píer ----------
       Só servem no píer (nível 31, no litoral), mas já aparecem desde o nível 1: vêm do mercador (1 em
       cada 100 visitas) e dá para vender na feira, de k.venda (o mínimo) até o triplo. */
    const ehRaro = (k) => !!k && k.tipo === 'raro';
    // de onde vem cada raro (fase 62: a pérola, do alto-mar; fase 63: os prêmios do evento da semana)
    function origemRaro(id) {
        if (id === 'perola_negra') return 'Do alto-mar: 1 em cada 200 peixes vem com uma.';
        if (id === 'leme_dourado') return 'Peça do píer e prêmio do evento da semana (para quem mais convidou).';
        if (ITENS_EVENTO.includes(id)) return 'Prêmio do evento da semana: só sai de lá.';
        return 'Material do píer (nível 31, no terreno do litoral).';
    }
    function htmlRaroCeleiro(k) {
        return `<div class="item raro">
            <span class="ico">${spr(A.cultura(k.id).item, 44)}</span>
            <span>
                <span class="nome">${esc(k.nome)} × ${naCeleiro(k.id)} <small class="tag-raro">raro</small></span>
                <span class="det"><span class="txt">${origemRaro(k.id)} Não vende no celeiro: na feira, de ${moeda(k.venda)} a ${moeda(k.venda * 3)} cada.</span></span>
            </span>
            <button type="button" class="botao pequeno creme" data-raro-feira="${esc(k.id)}">Na feira</button>
        </div>`;
    }

    /* ---------- Fase 61: o píer, no litoral ----------
       Receita de 9 peças difíceis (estado.pier.receita): 5 do mercador, o peixe do Velho Chico (lago) e
       o leme dourado (ranking da semana). Peça que falta dá para comprar com diamantes, caro. O guardado
       conta; o peixe dá para guardar para o píer (reserva) para não ir no "Vender tudo". */
    const ONDE_PECA = {
        madeira_nobre: 'do mercador ou da feira', corda_naval: 'do mercador ou da feira', pedra_cantaria: 'do mercador ou da feira',
        ferro_forjado: 'do mercador ou da feira', ancora: 'do mercador ou da feira',
        velho_chico: 'do lago (bem raro) ou da feira', leme_dourado: 'do evento da semana (quem mais convidou) ou da feira'
    };
    const ehPecaPier = (id) => !!(S && S.pier && S.pier.receita && S.pier.receita.itens && S.pier.receita.itens[id]);
    // no celeiro: guardar a peça para o píer (ou soltar), para ela não ir no "Vender tudo"
    function htmlGuardarPier(k) {
        const g = reservaDe(k.id);
        return g ? `<span class="det"><span class="txt">${g} guardado para o píer. <button type="button" class="link-botao" data-pier-soltar="${esc(k.id)}">Soltar</button></span></span>`
            : `<span class="det"><button type="button" class="botao pequeno creme" data-pier-guardar="${esc(k.id)}">Guardar para o píer</button></span>`;
    }
    function htmlPier() {
        const p = S.pier || {}, r = p.receita || { itens: {}, diamantes: {}, moedas: 0, nivel: 31 };
        if (p.pronto) {   // fase 62: o barco leva para o alto-mar
            const b = (S.mar && S.mar.barco) || { nome: 'Bote' };
            return `<p class="fala">O píer está pronto, com o seu barco (${esc(b.nome.toLowerCase())}) atracado do lado. Toque no barco, no mapa, ou aqui embaixo para ir para o <b>alto-mar</b>.</p>
                <div class="rodape-painel">
                    <button type="button" class="botao creme" data-mar-painel>Melhorias do mar</button>
                    <button type="button" class="botao verde" data-mar-ir>Ir para o alto-mar</button>
                </div>
                <p class="aviso">No mar: toque na água para lançar, espere a boia <b>afundar de verdade</b> e toque de novo na hora para fisgar. Cada lançada usa 1 peixe do cardume, que enche sozinho com o tempo. Barco, vara e marinheiro melhoram do nível 32 ao 43.</p>`;
        }
        const linhas = Object.entries(r.itens).map(([id, n]) => {
            const k = culturas[id] || { id, nome: id }, tem = naCeleiro(id), falta = Math.max(0, n - tem);
            const guardado = reservaDe(id), podeGuardar = k.tipo !== 'raro' && tem > 0 && guardado < Math.min(tem, n);
            return `<div class="item${falta ? '' : ' meta-feita'}">
                <span class="ico">${spr(A.cultura(id).item, 36)}</span>
                <span>
                    <span class="nome">${esc(k.nome)} <small class="qtd">${Math.min(tem, n)} de ${n}</small></span>
                    <span class="det"><span class="txt">${falta ? `Falta ${falta}: ${esc(ONDE_PECA[id] || 'da feira')}.` : 'Pronto.'}${guardado ? ` ${guardado} guardado para o píer.` : ''}</span></span>
                </span>
                <span class="admin-botoes">
                    ${falta ? `<button type="button" class="botao pequeno creme" data-pier-comprar="${esc(id)}"${(S.jogador.diamantes || 0) >= (r.diamantes[id] || 0) ? '' : ' disabled'}>${ico('diamante', 14)} ${r.diamantes[id] || '?'}</button>` : ''}
                    ${podeGuardar ? `<button type="button" class="botao pequeno creme" data-pier-guardar="${esc(id)}">Guardar</button>` : ''}
                </span>
            </div>`;
        }).join('');
        const faltam = Object.entries(r.itens).some(([id, n]) => naCeleiro(id) < n);
        const nivelOk = S.jogador.nivel >= r.nivel, moedasOk = S.jogador.moedas >= r.moedas;
        return `<p class="fala">Aqui vai o píer: tábuas entrando pelo mar e um barco atracado. Precisa de peças difíceis de juntar, e de ${moeda(r.moedas)}.</p>
            <div class="lista">${linhas}</div>
            <div class="rodape-painel">
                <span class="preco">${ico('moeda', 16)} ${r.moedas.toLocaleString('pt-BR')}</span>
                <button type="button" class="botao verde" data-pier-construir${!faltam && nivelOk && moedasOk ? '' : ' disabled'}>Construir o píer</button>
            </div>
            <p class="aviso">${!nivelOk ? `O píer libera no nível ${r.nivel}. ` : ''}Peça que falta dá para comprar com ${ico('diamante', 12)} (só até completar). O peixe do Velho Chico você pode <b>guardar para o píer</b>: guardado, ele não vai no "Vender tudo" nem na feira. Os materiais raros não vendem no celeiro.</p>`;
    }

    /* ---------- Fase 62: o alto-mar ----------
       Tocar no barco do píer abre a cena do mar (fazenda-mar.js) por cima da fazenda, que para de
       desenhar. O servidor manda em estado.mar o barco, a vara e o marinheiro de agora, o cardume e o
       cesto do marinheiro (desde, intervalo e máximo: contados pelo tempo, como o cesto do Bira) e as
       chances dos peixes. Lançar e fisgar vão na fila das ações, uma por vez. */
    let mar = null, ultimoMarinheiro = null;
    const melhoriaMar = (id) => (S.melhorias_tipos || []).find((m) => m.id === id && m.mar);
    function contarMar(c, vazio) {
        if (!c) return { n: 0, max: 0, proximo: 0 };
        const passo = c.intervalo * 1000;
        const desde = c.desde ? Date.parse(c.desde) : vazio ? agora() : agora() - c.max * passo;   // sem data: o cardume cheio, o cesto vazio
        const passou = agora() - desde, n = Math.max(0, Math.min(c.max, Math.floor(passou / passo)));
        return { n, max: c.max, proximo: n >= c.max ? 0 : (n + 1) * passo - passou };
    }
    const cardumeMar = () => contarMar(S && S.mar && S.mar.cardume);
    const cestoMar = () => (S && S.mar && S.mar.cesto ? { ...contarMar(S.mar.cesto, true), ultimo: ultimoMarinheiro } : null);
    const minutos = (seg) => Math.round(seg / 60);
    function htmlTopoMar() {
        if (!S || !S.mar) return '';
        const m = S.mar, j = S.jogador, c = cardumeMar(), cesto = cestoMar(), peixe = spr(A.cultura('sardinha').item, 18);
        const pct = j.nivel >= NIVEL_MAX ? 100 : Math.floor(100 * (j.xp - j.xp_nivel) / Math.max(1, j.xp_proximo - j.xp_nivel));
        return `<button type="button" class="botao pequeno creme" data-mar-sair>← Fazenda</button>
            <span class="chip" title="O cardume enche sozinho: 1 peixe a cada ${minutos(m.cardume.intervalo)} min, até ${c.max}">${peixe} ${c.n}/${c.max}${c.n < c.max ? ` · +1 em ${fmtTempo(c.proximo)}` : ' · cheio'}</span>
            <button type="button" class="botao pequeno verde mar-direita" data-mar-melhorar>Melhorar</button>
            <span class="mar-linha">
                <span class="chip">${ico('xp', 14)} Nível ${j.nivel}${j.nivel < NIVEL_MAX ? ` · ${pct}%` : ''}</span>
                <span class="chip">${esc((m.barco || {}).nome || 'Bote')} · ${esc((m.vara || {}).nome || 'Vara de bambu')}</span>
                ${melhoriaNivel('expedicao') ? `<span class="chip" title="O kit de expedição está no barco: as ilhas abrem no nível 46">${itemDe(culturas.leme_dourado || { id: 'leme_dourado' }, 16)} Pronto para as ilhas · nível 46</span>` : ''}
                ${cesto ? `<span class="chip" title="O Seu Nonato pesca sozinho: 1 peixe a cada ${minutos(m.cesto.intervalo)} min, até ${cesto.max}">${A.htmlTile(120, 18, 'factory')} ${cesto.n}/${cesto.max}</span>${cesto.n ? '<button type="button" class="botao pequeno creme" data-mar-recolher>Recolher</button>' : ''}` : ''}
            </span>`;
    }
    function abrirMar() {
        if (!S || visita || mar) return;
        if (!S.mar) { abrirPainel('pier'); return; }
        if (!window.FazendaMar) { toast('O alto-mar ainda está carregando. Tente de novo.', 'erro'); return; }
        fecharPainel();
        if (constr.ativo) fecharConstrucao();
        cena.pausar(true);
        document.body.classList.add('no-mar');
        mar = window.FazendaMar.criar({
            dados: () => S && S.mar,
            agora,
            avatar: () => S && S.jogador.avatar,
            sprite: (id) => A.cultura(id).item,
            pecas: pecasMar,   // fase 65: as peças aparecem no barco
            cardume: cardumeMar,
            cesto: cestoMar,
            proximo: () => fmtTempo(cardumeMar().proximo),
            htmlTopo: htmlTopoMar,
            painelAberto: () => !!painelAtual,
            som: (n) => som.tocar(n),
            lancar: () => chamadaMar('fazenda_mar_lancar', (r) => { if (r.mar) S.mar = r.mar; }),
            fisgar: () => chamadaMar('fazenda_mar_fisgar', (r) => { if (r.estado) aplicarEstado(r.estado); else if (r.mar) S.mar = r.mar; }),
            textoPeixe: (r) => {
                const k = culturas[r.peixe] || { nome: r.peixe, venda: 0 };
                return `${r.qtd > 1 ? `${r.qtd}× ` : ''}${k.nome}! +${r.xp} XP · vale ${k.venda.toLocaleString('pt-BR')} moedas${r.qtd > 1 ? ' cada (porão!)' : ''}${r.perola ? ' · e veio uma pérola negra!' : ''}`;
            },
            pegou: (r) => {
                const k = culturas[r.peixe] || { id: r.peixe, nome: r.peixe };
                if (r.perola || r.peixe === 'marlim') {
                    som.tocar('festa');
                    toast(`${itemDe(k, 22)} <b>${esc(k.nome)}</b>!${r.perola ? ` E veio junto uma ${itemDe(culturas.perola_negra || { id: 'perola_negra' }, 22)} <b>pérola negra</b>: na feira ela vale de 50 a 150 mil.` : ' O lendário do alto-mar!'}`, 'festa');
                } else som.tocar('colher');
            },
            recolher: recolherMarinheiro,
            melhorar: () => abrirPainel('mar'),
            sair: fecharMar
        });
    }
    function fecharMar() {
        if (!mar) return;
        mar.fechar();
        mar = null;
        cena.pausar(false);
        document.body.classList.remove('no-mar');
        if (painelAtual === 'mar') fecharPainel();
    }
    // lançar e fisgar: na fila das ações (a busca de 60 s não passa por cima); o erro vira aviso
    // (tratarErro) e a cena volta a esperar o toque
    function chamadaMar(fn, aplicar) {
        return new Promise((ok, falhou) => {
            enfileirar([], async () => {
                try {
                    const r = await rpc(fn, { p_token: token });
                    aplicar(r);
                    ok(r);
                    return r;
                } catch (e) { falhou(e); throw e; }
            });
        });
    }
    function recolherMarinheiro() {
        const c = cestoMar();
        if (!c) return toast('Contrate o marinheiro (Melhorar → Marinheiro, nível 33) para ele pescar sozinho.');
        if (!c.n) return toast(`O cesto do Seu Nonato está vazio: ele tira 1 peixe a cada ${minutos(S.mar.cesto.intervalo)} minutos, até ${c.max}.`);
        som.tocar('colher');
        enfileirar([], async () => {
            const r = await rpc('fazenda_mar_recolher', { p_token: token });
            aplicarEstado(r.estado);
            const lista = Object.entries(r.peixes || {}).sort((a, b) => (culturas[b[0]] || {}).venda - (culturas[a[0]] || {}).venda);
            if (lista.length) ultimoMarinheiro = lista[0][0];
            const perola = culturas.perola_negra || { id: 'perola_negra' };
            toast(`O Seu Nonato pescou ${r.qtd} peixe(s): ${lista.map(([id, n]) => `${n} ${itemDe(culturas[id] || { id }, 18)}`).join(' ')} +${r.xp} ${ico('xp', 14)}`
                + (r.perolas ? ` e ${r.perolas} ${itemDe(perola, 18)} pérola negra!` : ''), r.perolas || (r.peixes || {}).marlim ? 'festa' : undefined);
            if (r.perolas || (r.peixes || {}).marlim) som.tocar('festa');
            if (mar) mar.atualizar();
        });
    }
    // as melhorias do mar (barco, vara e marinheiro): o que tem agora, o próximo e os peixes de agora
    function efeitoMar(id, k) {
        if (id === 'barco') return `cardume de ${k.max}, 1 peixe a cada ${minutos(k.intervalo)} min`;
        if (id === 'vara') return `${(k.janela / 1000).toLocaleString('pt-BR')} s para fisgar`;
        // fase 65: as peças da tunagem
        if (id === 'motor') return `o cardume enche ${Math.round(k.valor * 100)}% mais rápido`;
        if (id === 'sonar') return `mais peixe grande (como +${k.valor} na vara) e 1 pérola a cada ${k.perola} peixes`;
        if (id === 'porao') return `${Math.round(k.valor * 100)}% de chance de vir 2 peixes numa fisgada`;
        if (id === 'rede') return `o marinheiro pesca ${Math.round(k.valor * 100)}% mais rápido`;
        if (id === 'expedicao') return 'o barco fica pronto para viajar às ilhas (nível 46, na próxima expansão)';
        return `pesca 1 peixe a cada ${minutos(k.intervalo)} min, até ${k.max} no cesto`;
    }
    // fase 69: cada melhoria do mar com a figura dela (antes eram itens que não tinham nada a ver: um peixe
    // para a vara, uma barra de ferro para o motor, a pérola para o sonar...)
    const ICONE_MAR = { barco: 1113, vara: 1114, motor: 1115, sonar: 1116, porao: 1117, rede: 1118, expedicao: 1119 };
    const iconeMar = (id, px) => (id === 'marinheiro' ? A.htmlTile(120, px, 'factory') : spr(ICONE_MAR[id] || 1114, px));
    const PECAS_MAR = ['motor', 'sonar', 'porao', 'rede', 'expedicao'];
    const pecasMar = () => Object.fromEntries(PECAS_MAR.map((id) => [id, S ? melhoriaNivel(id) : 0]));
    // a pintura (o rascunho, até apertar "Pintar"); as cores e bandeiras são as de fazenda_barco_cores
    const CORES_PINTURA = ['padrao', 'branco', 'azul', 'vermelho', 'verde', 'amarelo', 'preto', 'roxo', 'rosa', 'dourado'];
    const BANDEIRAS_PINTURA = { padrao: 'Padrão', brasil: 'Brasil', pirata: 'Pirata', xadrez: 'Xadrez', coracao: 'Coração', estrela: 'Estrela', sertao: 'Sertão' };
    const PRECO_PINTURA = 20000;
    let pinturaBarco = null;
    const visualBarco = () => ({ casco: 'padrao', faixa: 'padrao', bandeira: 'padrao', ...((S && S.mar && S.mar.visual) || {}) });
    function htmlMateriais(itens) {
        return Object.entries(itens || {}).map(([id, n]) => {
            const k = culturas[id] || { id, nome: id }, tem = livreFeira(id);
            return `<span class="chip${tem < n ? ' falta' : ''}" title="${esc(k.nome)}">${itemDe(k, 16)} ${Math.min(tem, n)}/${n}</span>`;
        }).join('');
    }
    function htmlPintura() {
        const p = pinturaBarco || visualBarco(), atual = visualBarco();
        const mud = ['casco', 'faixa', 'bandeira'].filter((k) => p[k] !== atual[k]);
        const perolas = mud.filter((k) => p[k] === 'dourado').length;
        const cores = (campo) => CORES_PINTURA.map((c) => {
            const cor = (window.FazendaMar && window.FazendaMar.CORES[c]) || '';
            return `<button type="button" class="cor${p[campo] === c ? ' ativa' : ''}" data-pintar="${campo}:${c}" title="${c === 'padrao' ? 'A cor do próprio barco' : c === 'dourado' ? 'Dourado (pede 1 pérola negra)' : c}"${cor ? ` style="background:${cor}"` : ''}>${c === 'padrao' ? 'P' : c === 'dourado' ? '★' : ''}</button>`;
        }).join('');
        const bandeiras = Object.entries(BANDEIRAS_PINTURA).map(([b, nome]) => {
            const url = b !== 'padrao' && window.FazendaMar ? window.FazendaMar.bandeiraUrl(b) : '';
            return `<button type="button" class="botao pequeno ${p.bandeira === b ? 'verde' : 'creme'}" data-pintar="bandeira:${b}">${url ? `<img src="${url}" alt="" width="18" height="12" class="px">` : ''}${nome}</button>`;
        }).join('');
        return `<h3 class="secao-titulo">Pintura</h3>
            <div class="previa-barco"><canvas data-barco-previa aria-label="Prévia do barco"></canvas></div>
            <p class="det">Casco</p><div class="pintura-cores">${cores('casco')}</div>
            <p class="det">Faixa</p><div class="pintura-cores">${cores('faixa')}</div>
            <p class="det">Bandeira</p><div class="pintura-bandeiras">${bandeiras}</div>
            <div class="rodape-painel">
                <span class="preco">${mud.length ? `${moeda(numero(mud.length * PRECO_PINTURA))}${perolas ? ` + ${perolas} ${itemDe(culturas.perola_negra || { id: 'perola_negra' }, 16)}` : ''}` : 'Sem mudança'}</span>
                <button type="button" class="botao verde" data-pintar-salvar${mud.length ? '' : ' disabled'}>Pintar</button>
            </div>
            <p class="aviso">Cada mudança custa ${numero(PRECO_PINTURA)} moedas. O dourado pede 1 pérola negra.</p>`;
    }
    function htmlMarMelhorias() {
        if (!S.mar) return '<p class="vazio-msg">Construa o píer (no Litoral) para ir para o alto-mar.</p>';
        const linhas = ['barco', 'vara', 'marinheiro'].map((id) => {
            const m = melhoriaMar(id);
            if (!m) return '';
            const tem = melhoriaNivel(id), atual = tem ? m.niveis[tem - 1] : m.base, prox = m.niveis[tem];
            const travado = prox && S.jogador.nivel < prox.nivel;
            return `<div class="item">
                <span class="ico">${iconeMar(id, 40)}</span>
                <span>
                    <span class="nome">${esc(m.nome)}: ${atual ? esc(atual.nome) : 'ainda não contratado'}</span>
                    <span class="det"><span class="txt">${atual ? `Agora: ${efeitoMar(id, atual)}. ` : ''}${esc(m.descricao)}</span></span>
                    ${prox ? `<span class="det"><span class="txt">Próximo: <b>${esc(prox.nome)}</b> (nível ${prox.nivel}): ${efeitoMar(id, prox)}.</span></span>` : ''}
                </span>
                ${!prox ? '<span class="preco">No máximo</span>'
                    : travado ? `<span class="preco">Nível ${prox.nivel}</span>`
                    : `<button type="button" class="botao pequeno verde" data-comprar="melhoria:${id}">${ico('moeda', 14)} ${prox.custo.toLocaleString('pt-BR')}</button>`}
            </div>`;
        }).join('');
        const peixes = (S.mar.peixes || []).map((p) => {
            const k = culturas[p.id] || { id: p.id, nome: p.id, venda: 0 };
            return `<li class="chip" title="${esc(k.nome)}: vale ${k.venda.toLocaleString('pt-BR')} moedas">${itemDe(k, 20)} ${esc(k.nome)} · ${Number(p.chance).toLocaleString('pt-BR')}%</li>`;
        }).join('');
        // fase 65: as peças da tunagem (moedas + materiais raros) e a pintura
        const pecas = PECAS_MAR.map((id) => {
            const m = melhoriaMar(id);
            if (!m) return '';
            const tem = melhoriaNivel(id), atual = tem ? m.niveis[tem - 1] : null, prox = m.niveis[tem];
            const travado = prox && S.jogador.nivel < prox.nivel;
            const pede = id === 'rede' && !(S.mar && S.mar.marinheiro) ? 'Precisa do marinheiro. '
                : id === 'expedicao' && melhoriaNivel('barco') < 4 ? 'Precisa do barco oceânico. ' : '';
            return `<div class="item${!tem && travado ? ' travada' : ''}">
                <span class="ico">${iconeMar(id, 40)}</span>
                <span>
                    <span class="nome">${esc(m.nome)}${atual ? `: ${esc(atual.nome)}` : ''}${tem ? ` · ${tem}/${m.niveis.length}` : ''}</span>
                    <span class="det"><span class="txt">${atual ? `Agora: ${efeitoMar(id, atual)}. ` : ''}${pede}${esc(m.descricao)}</span></span>
                    ${prox ? `<span class="det"><span class="txt">${atual ? 'Próximo' : 'Primeiro'}: <b>${esc(prox.nome)}</b> (nível ${prox.nivel}): ${efeitoMar(id, prox)}.</span></span>
                    <span class="det materiais">${htmlMateriais(prox.itens)}</span>` : ''}
                </span>
                ${!prox ? '<span class="preco">No máximo</span>'
                    : travado ? `<span class="preco">Nível ${prox.nivel}</span>`
                    : `<button type="button" class="botao pequeno verde" data-comprar="melhoria:${id}">${ico('moeda', 14)} ${prox.custo.toLocaleString('pt-BR')}</button>`}
            </div>`;
        }).join('');
        return `<div class="lista">${linhas}</div>
            <h3 class="secao-titulo">Tunagem do barco</h3>
            <div class="lista">${pecas}</div>
            ${htmlPintura()}
            <h3 class="secao-titulo">Peixes que dá para pegar agora</h3>
            <ul class="mar-peixes">${peixes}</ul>
            <p class="aviso">Barco maior vai mais longe e acha peixes novos; vara melhor (e o sonar) puxa os maiores. 1 em cada ${S.mar.perola || 200} peixes vem com uma <b>pérola negra</b> (na feira, de 50 a 150 mil). As peças pedem materiais raros: os do mercador, a pérola negra e o marlim-azul. Os peixes do mar vendem no celeiro e dão XP na pesca e de novo na venda. As ilhas chegam no nível 46: o kit de expedição deixa o barco pronto.</p>
            <div class="rodape-painel"><button type="button" class="botao verde" data-mar-ir>${mar ? 'Voltar para o mar' : 'Ir para o alto-mar'}</button></div>`;
    }

    /* ---------- Fase 63: o evento da semana ----------
       Fecha toda sexta às 22h (Brasília) e premia o top 3 de cada categoria: o servidor fecha sozinho,
       na primeira chamada depois da virada (fazenda_semana_fechar). O painel busca o placar de agora
       (fazenda_evento); o estado traz o fim da semana, os prêmios novos (uma vez só) e os troféus. */
    let eventoDados = null, eventoPremios = [];
    const CAT_ICONE = { ranking: 'trofeu_ouro', niveis: 'ampulheta_dourada', moedas: 'cofrinho_ouro', vendeu: 'balanca_ouro', comprou: 'sacola_ouro', convites: 'leme_dourado' };
    const ITENS_EVENTO = ['trofeu_ouro', 'trofeu_prata', 'trofeu_bronze', 'ampulheta_dourada', 'cofrinho_ouro', 'balanca_ouro', 'sacola_ouro'];
    const LUGAR = ['1º', '2º', '3º'];
    const regrasEvento = () => (S && S.evento && S.evento.regras) || { categorias: [], diamantes: [30, 18, 10], convite_nivel: 10 };
    const fimEvento = () => (S && S.evento && S.evento.fim ? Date.parse(S.evento.fim) : 0);
    const iconeCat = (cat, px) => itemDe(culturas[CAT_ICONE[cat]] || { id: CAT_ICONE[cat] }, px);
    const numero = (v) => Number(v || 0).toLocaleString('pt-BR');
    function valorEvento(cat, v) {
        if (cat === 'ranking') return `${numero(v)} ${ico('xp', 13)}`;
        if (cat === 'niveis') return `${v} ${Number(v) === 1 ? 'nível' : 'níveis'}`;
        if (cat === 'convites') return `${v} ${Number(v) === 1 ? 'amigo' : 'amigos'}`;
        return moeda(numero(v));   // moedas, vendeu e comprou
    }
    function carregarEvento() {
        enfileirar([], async () => {
            eventoDados = await rpc('fazenda_evento', { p_token: token });
            if (painelAtual === 'evento') abrirPainel('evento', true);
        });
    }
    function htmlEvento() {
        const reg = regrasEvento(), d = eventoDados;
        const falta = (d ? Date.parse(d.fim) : fimEvento()) - agora();
        const chance = reg.chance_item == null ? 100 : reg.chance_item;   // fase 64: o item vem na sorte
        let html = `<p class="fala">Toda semana, de sexta às 22h até a sexta seguinte às 22h, os 3 primeiros de cada categoria ganham diamantes${chance < 100 ? ` e têm ${chance}% de chance de levar um item raro` : ', e o 1º leva um item que só sai daqui'}. Esta semana fecha ${falta > 0 ? `em <b>${fmtTempo(falta)}</b>` : '<b>agora</b>'}.</p>`;
        if (!d) return html + '<p class="vazio-msg">Carregando o placar…</p>';
        html += '<div class="evento-cats">' + reg.categorias.map((c) => {
            const p = (d.placar || {})[c.id] || { top: [], eu: null, total: 0 };
            const premios = [0, 1, 2].map((i) => {
                const id = c.itens[i], k = id && (culturas[id] || { id, nome: id }), sorte = chance < 100 ? `${chance}%: ` : '';
                const item = k ? ` + ${sorte}${itemDe(k, 18)} ${esc(k.nome)}`
                    : chance < 100 ? ` + ${sorte}${itemDe(culturas.madeira_nobre || { id: 'madeira_nobre' }, 18)} material do píer` : '';
                return `<span class="chip">${LUGAR[i]} ${ico('diamante', 12)} ${reg.diamantes[i]}${item}</span>`;
            }).join('');
            const top = p.top.length
                ? '<ol class="evento-top">' + p.top.map((t, i) => `<li${t.eu ? ' class="eu"' : ''}><span class="pos">${LUGAR[i]}</span>${A.htmlAvatar(t.avatar, 20)}<b>${esc(t.apelido)}${t.eu ? ' (você)' : ''}</b><span class="val">${valorEvento(c.id, t.valor)}</span></li>`).join('') + '</ol>'
                : '<p class="det">Ninguém pontuou ainda: quem pontuar primeiro já fica em 1º.</p>';
            return `<div class="evento-cat">
                <h3>${iconeCat(c.id, 28)} ${esc(c.nome)}</h3>
                <p class="det">Conta: ${esc(c.conta)}.</p>
                <div class="evento-premios">${premios}</div>
                ${top}
                <p class="evento-eu">${p.eu ? `Você: <b>${p.eu.posicao}º</b> de ${p.total} · ${valorEvento(c.id, p.eu.valor)}` : 'Você ainda não pontuou aqui.'}</p>
            </div>`;
        }).join('') + '</div>';
        const pas = d.passada;
        if (pas && pas.premios && pas.premios.length) {
            html += '<h3 class="secao-titulo">Semana passada</h3><div class="lista">' + reg.categorias.map((c) => {
                const ps = pas.premios.filter((x) => x.categoria === c.id);
                if (!ps.length) return '';
                return `<div class="item"><span class="ico">${iconeCat(c.id, 32)}</span><span><span class="nome">${esc(c.nome)}</span>
                    <span class="det">${ps.map((x) => `<span>${LUGAR[x.posicao - 1]} ${esc(x.apelido)}${x.eu ? ' (você)' : ''}</span>`).join('')}</span></span></div>`;
            }).join('') + '</div>';
        }
        return html + `<p class="aviso">Convite só conta quando o amigo chega ao nível ${reg.convite_nivel || 10}. Nas moedas, gastar não desconta, e o que entra pela barraca fica só em "vendeu". O XP comprado com diamantes (pacote de XP, trilha dourada e a metade a mais do XP em dobro) não conta no ranking nem em níveis. Na barraca, uma mesma pessoa do outro lado vale no máximo 25% do seu total. ${chance < 100 ? `Cada lugar do pódio tira a sorte: com ${chance}% de chance vem o item (o material do píer é sorteado). ` : ''}Os itens do evento não vendem no celeiro: na feira valem de 60 mil para cima. Quem mais convidou pode levar o <b>leme dourado</b>, a peça do píer. As conquistas do evento aparecem no seu perfil.</p>`;
    }
    function htmlEventoPremio() {
        const reg = regrasEvento(), nomeCat = (id) => (reg.categorias.find((c) => c.id === id) || { nome: id }).nome;
        return '<p class="fala">O evento da semana fechou e você subiu ao pódio!</p><div class="lista">' + eventoPremios.map((p) => {
            const k = p.item && (culturas[p.item] || { id: p.item, nome: p.item });
            return `<div class="item"><span class="ico">${k ? itemDe(k, 40) : iconeCat(p.categoria, 40)}</span><span>
                <span class="nome">${LUGAR[p.posicao - 1]} lugar: ${esc(nomeCat(p.categoria))}</span>
                <span class="det"><span class="txt">${valorEvento(p.categoria, p.valor)} · +${p.diamantes} ${ico('diamante', 12)}${k ? ` e <b>${esc(k.nome)}</b> (está no celeiro)` : ''}</span></span></span></div>`;
        }).join('') + `</div><div class="rodape-painel"><button type="button" class="botao creme" data-painel-ir="evento">Ver o evento</button><button type="button" class="botao verde" data-fechar>Oba!</button></div>`;
    }
    // no perfil (o seu e o dos vizinhos): quantas vezes ficou em 1º, 2º e 3º em cada categoria
    function htmlTrofeus(t) {
        t = t || {};
        const linhas = regrasEvento().categorias.filter((c) => t[c.id]).map((c) => {
            const [o, p, b] = t[c.id];
            return `<span class="chip">${iconeCat(c.id, 18)}<span>${esc(c.nome)}: ${[o && `${o}× 1º`, p && `${p}× 2º`, b && `${b}× 3º`].filter(Boolean).join(' · ')}</span></span>`;
        });
        return linhas.length ? `<div class="chips">${linhas.join('')}</div>` : '<p class="det">Ainda sem pódio no evento da semana. Ele fecha toda sexta às 22h.</p>';
    }

    /* ---------- Visitas na porteira: a cada 3 horas chega alguém (fazenda_visitante) ---------- */
    const VISITAS = {
        feirante: { nome: 'Seu Tonico', papel: 'o feirante', sprite: 86,
            fala: (q, item, paga) => `Bom dia! Tô precisando de <b>${q} ${item}</b> pra banca da feira. Pago <b>${paga}</b>, bem mais que no celeiro!` },
        doceira: { nome: 'Dona Benta', papel: 'a doceira', sprite: 99,
            fala: (q, item, paga) => `Ô de casa! Vou fazer uma fornada e me faltam <b>${q} ${item}</b>. Te pago <b>${paga}</b>, combinado?` },
        caminhoneiro: { nome: 'Zeca', papel: 'do caminhão', sprite: 112,
            fala: (q, item, paga) => `E aí! O caminhão tá vazio: levo <b>${q} ${item}</b> de uma vez só. Pago <b>${paga}</b> e ainda dou um bônus de XP.` },
        mascate: { nome: 'Dona Fia', papel: 'a mascate', sprite: 100 },
        mercador: { nome: 'Seu Jacó', papel: 'o mercador', sprite: 111 },   // fase 60: 1 em cada 100 visitas
        perks: { nome: 'Perks', papel: 'o 1º do ranking', sprite: 97 }   // fase 66: 1 em cada 30 visitas
    };
    const visitaAgora = () => (!visita && S && S.visitante) || null;
    const nomeQtd = (k, n) => { const nome = (k.nome || k.id).toLowerCase(); return n === 1 || /s$/.test(nome) ? nome : nome.replace(/(ão)$/, 'ões').replace(/([^s])$/, '$1s'); };
    let visitaVista = null;
    function atualizarVisitante() {
        const v = visitaAgora();
        cena.definirVisitante(v ? { tipo: v.tipo, item: v.tipo === 'perks' ? A.cultura('luva_perks').item : v.raro ? A.cultura(v.raro).item : v.item ? A.cultura(v.item).item : null } : null);
        if (v && visitaVista !== null && visitaVista !== v.slot) {
            const p = VISITAS[v.tipo];
            toast(v.tipo === 'mercador'
                ? `${spr(p.sprite, 22, 'dungeon')} Visita rara na porteira: <b>${p.nome}</b>, ${p.papel}, trouxe ${itemDe(culturas[v.raro] || { id: v.raro }, 16)} <b>${esc((culturas[v.raro] || {}).nome || 'um material raro')}</b>!`
                : v.tipo === 'perks' ? `${spr(p.sprite, 22, 'dungeon')} Visita rara na porteira: o <b>Perks</b>, ${p.papel}, com ${itemDe(culturas.luva_perks || { id: 'luva_perks' }, 16)} luvas que passam pelo alarme!`
                : `${spr(p.sprite, 22, 'dungeon')} Chegou visita na porteira: <b>${p.nome}</b>, ${p.papel}! Toque nela para conversar.`, v.tipo === 'mercador' || v.tipo === 'perks' ? 'festa' : undefined);
        }
        visitaVista = v ? v.slot : (visitaVista === null ? 0 : visitaVista);
    }
    function descreverVisitante() {
        const v = visitaAgora();
        if (!v) return;
        const p = VISITAS[v.tipo], k = v.item && culturas[v.item];
        const r = v.raro && culturas[v.raro];
        mostrarStatus(`${spr(p.sprite, 22, 'dungeon')} <b>${p.nome}</b>, ${p.papel}: ` + (v.tipo === 'mascate'
            ? `vende adubo para ${v.canteiros} canteiros por ${moeda(v.preco)}.`
            : v.tipo === 'mercador' ? `troca 1 ${r ? itemDe(r, 16) + esc(r.nome.toLowerCase()) : 'material raro'} por ${v.qtd} ${k ? itemDe(k, 16) + esc(nomeQtd(k, v.qtd)) : ''} fora de época.`
            : v.tipo === 'perks' ? `troca ${v.luvas} ${itemDe(culturas.luva_perks || { id: 'luva_perks' }, 16)} luvas (passam pelo alarme do vizinho) por ${v.qtd} ${k ? itemDe(k, 16) + esc(nomeQtd(k, v.qtd)) : ''}.`
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
        if (v.tipo === 'perks') {   // fase 66: o Perks troca luvas por uma planta fácil em número grande
            const luva = culturas.luva_perks || { id: 'luva_perks', nome: 'Luva do Perks', venda: 50000 };
            return `${cabeca}
                <p class="fala">E aí! Sou o <b>Perks</b>, o 1º do ranking. Quer saber como passo pelo alarme dos vizinhos? Com estas luvas. Me traz <b>${v.qtd} ${itemDe(k, 18)} ${esc(nomeQtd(k, v.qtd))}</b> e eu te dou <b>${v.luvas} ${itemDe(luva, 18)} luvas</b>.</p>
                <div class="oficina-conta">
                    <span>Cada luva pega 1 canteiro com alarme</span>
                    <span class="lucro">Na feira, de ${moeda(numero(luva.venda))} a ${moeda(numero(luva.venda * 3))}</span>
                </div>
                <p class="det"><span class="txt">Você tem ${numero(tem)} ${esc(nomeQtd(k, tem))}${tem < v.qtd ? `: faltam ${numero(v.qtd - tem)}` : ''}. Ele é raro: aparece mais ou menos 1 vez em cada 30 visitas.</span></p>
                <div class="rodape-painel">
                    <button type="button" class="botao creme" data-atender="0">Agora não</button>
                    <button type="button" class="botao verde" data-atender="1"${tem >= v.qtd ? '' : ' disabled'}>Trocar ${numero(v.qtd)} ${itemDe(k, 18)}</button>
                </div>`;
        }
        if (v.tipo === 'mercador') {   // fase 60: troca 1 material raro por frutos fora de época
            const r = culturas[v.raro] || { id: v.raro, nome: v.raro, venda: 0 };
            return `${cabeca}
                <p class="fala">Ô de casa! Venho de longe e trago uma coisa rara: <b>1 ${itemDe(r, 18)} ${esc(r.nome.toLowerCase())}</b>, das boas para o píer. Não quero moeda não: troco por <b>${v.qtd} ${itemDe(k, 18)} ${esc(nomeQtd(k, v.qtd))}</b>, que agora não é época e lá de onde eu venho ninguém tem.</p>
                <div class="oficina-conta">
                    <span>Na feira, ${esc(r.nome.toLowerCase())} vai de ${moeda(r.venda)} a ${moeda(r.venda * 3)}</span>
                    <span class="lucro">Serve no píer (nível 31)</span>
                </div>
                <p class="det"><span class="txt">Você tem ${tem} ${esc(nomeQtd(k, tem))}${tem < v.qtd ? `: faltam ${v.qtd - tem}. Fruta fora de época só tem quem guardou da estação dela ou plantou na estufa` : ''}. Ele é raro: aparece mais ou menos 1 vez em cada 100 visitas.</span></p>
                <div class="rodape-painel">
                    <button type="button" class="botao creme" data-atender="0">Agora não</button>
                    <button type="button" class="botao verde" data-atender="1"${tem >= v.qtd ? '' : ' disabled'}>Trocar ${v.qtd} ${itemDe(k, 18)}</button>
                </div>`;
        }
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
                const raro = v.raro && culturas[v.raro];
                toast(v.tipo === 'mascate'
                    ? `${spr(1040, 20)} ${p.nome} adubou ${r.adubados} canteiro(s): +1 item na colheita de cada.`
                    : v.tipo === 'mercador' ? `${itemDe(raro || { id: v.raro }, 20)} ${p.nome} deixou 1 <b>${esc(raro ? raro.nome.toLowerCase() : 'material raro')}</b> no celeiro! Guarde para o píer (nível 31) ou venda na feira.`
                    : v.tipo === 'perks' ? `${itemDe(culturas.luva_perks || { id: 'luva_perks' }, 20)} O Perks deixou <b>${v.luvas} luvas</b> no celeiro! Visitando um vizinho, toque num canteiro com alarme para usar.`
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
        const quer = n >= 9 ? 4 : n >= 6 ? 3 : n >= 1 ? 2 : 0;   // fase 45: sem bicho pequeno fora de cercado, não tem galinheiro
        if (!quer) return { linhas: 0, quer: 0 };
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
        // fase 45: o pasto do começo só fica enquanto tiver bicho grande sem cercado (igual a fazenda_pasto)
        cena.definirPasto(!visita && S.galinheiro && 'pasto' in S.galinheiro ? S.galinheiro.pasto
            : (fonte.animais || []).some((a) => ['vaca', 'ovelha', 'porco'].includes(a.tipo) && !(fonte.construcoes || []).some((c) => c.tipo === 'cercado_' + a.tipo)));
        if (!visita && g.quer > g.linhas && !avisouGalinheiro) {
            avisouGalinheiro = true;
            toast(`${spr(A.ANIMAL.galinha, 20)} Os bichos estão apertados! Em Construir → Bichos tem um cercado para cada um (galinhas, coelhos, patos...): coloque onde quiser e eles se mudam para lá.`);
        }
    }

    /* ---------- Ração reservada no celeiro (o "vender" não leva) ---------- */
    const reservaDe = (item) => (S && S.reservas && S.reservas[item]) || 0;
    const MAX_REFEICOES = 10;
    // o que sai das oficinas (as que têm receita de entrada)
    const produtosFinais = () => (S.itens || []).filter((it) => it.entradas && it.produz).map((it) => it.produz);
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

    // fase 68: o reator deixou o bicho radioativo (meia hora dando o produto a cada 2 min, direto no celeiro)
    const radioativo = (a) => !!(a && a.radioativo_ate && Date.parse(a.radioativo_ate) > agora());
    const FEMEA = new Set(['galinha', 'vaca', 'ovelha', 'cabra', 'bufala']);   // para os textos: "a vaca radioativa", "o porco radioativo"
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
                radioativo: radioativo(a),   // fase 68: brilha verde e solta o produto
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
        // na rede, o produto sai sozinho se tiver para onde ir (celeiro, baú ou oficina que usa ele)
        const rede = S && !visita ? vizinhosNaRede(c.x, c.y) : null;
        const ligada = !!rede && (rede.baus.length + rede.oficinas.length > 0 || rede.celeiro);
        const auto = !!rede && (rede.celeiro || rede.baus.length > 0 || rede.oficinas.some((k) => (tipoItem(k.tipo).entradas || {})[it.produz]));
        const dur = it.produz_seg * 1000;
        let t = c.iniciado_em ? Date.parse(c.iniciado_em) : null, estoque = c.estoque || 0, prontos = c.prontos || 0;
        for (let n = 0; t != null && agora() >= t + dur && n < 48; n++) {
            if (!auto) prontos += it.produz_qtd;   // com a fábrica automática vai direto para o celeiro
            t = estoque > 0 ? (estoque--, t + dur) : null;
        }
        const base = { x: c.x, y: c.y, it, produto, estoque, prontos, auto, ligada, rede };
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

    let cacheVisitaCons = {};
    function visualConstrucoes() {
        if (!S) return DEMO_CONSTRUCOES;
        if (visita) {   // na fazenda do vizinho os canos também ligam uns nos outros (sem a luz: a energia é dele)
            const cons = visita.construcoes || [];
            if (cacheVisitaCons.cons !== cons) {
                const r = cons.some((c) => c.tipo === 'cano') ? redeCanos(cons) : null;
                cacheVisitaCons = { cons, lista: r ? cons.map((c) => (c.tipo === 'cano' ? { ...c, cano: r.lados.get(c.x + ',' + c.y) } : c)) : cons };
            }
            return cacheVisitaCons.lista;
        }
        // sinal da rede: luz verde pulsando = ligada e com energia; vermelha piscando = sem energia.
        // A onda verde só corre na rede com oficina trabalhando; ligada mas parada, a luzinha fica fraca
        const sinal = cargaAgora() >= 2 ? 'ok' : 'sem_energia';
        const cons = S.construcoes || [], ativas = new Set();
        const rc = cons.some((c) => c.tipo === 'cano') ? redeCanos() : null;
        if (rc) for (const k of rc.coisas) {
            if (k.papel !== 'oficina' || !k.redes.size) continue;
            const o = infoOficina(cons.find((c) => c.x === k.x && c.y === k.y && c.tipo === k.tipo));
            if (o && o.estado === 'trabalhando') k.redes.forEach((n) => ativas.add(n));
        }
        return cons.map((c) => {
            const o = infoOficina(c);
            if (o) {   // (os itens andando nos canos agora vêm das viagens: visualViagens)
                return { ...c, oficina: { estado: o.prontos > 0 ? 'pronta' : o.estado, trabalhando: o.estado === 'trabalhando', progresso: o.progresso, produto: A.cultura(o.it.produz).item, rede: o.ligada ? sinal : null } };
            }
            if (c.tipo === 'cano') {
                const r = redeCanos(), k = c.x + ',' + c.y;
                return { ...c, cano: r.lados.get(k), rede: (r.membros.get(r.redeDoCano.get(k)) || 0) >= 2 ? sinal : null, ativa: ativas.has(r.redeDoCano.get(k)) };
            }
            // fase 47: com energia elétrica, o alarme gasta 1 ⚡/h; bateria zerada = desligado (a luz para)
            if (c.tipo === 'alarme' && temEletrico() && cargaAgora() < 1) return { ...c, desligado: true };
            if (c.tipo === 'bau') {
                const total = Object.values((S.baus || {})[c.x + ',' + c.y] || {}).reduce((a, n) => a + n, 0);
                return total > 0 ? { ...c, bau: { frac: total / BAU_MAX } } : c;
            }
            if (c.iniciado_em && (tipoItem(c.tipo) || {}).efeito === 'biomassa') return { ...c, ligado: true };
            const p = infoProducao(c);
            return p && p.falta <= 0 ? { ...c, pronto: true, produto: A.cultura(p.it.produz).item } : c;
        });
    }

    // o que os itens em volta fazem por um canteiro (aparece ao passar/tocar nele)
    const NOME_EFEITO = {
        seco: 'sem seca', praga: 'sem pragas', erva: 'sem ervas', crescer: 'cresce 10% mais rápido',
        adubo: '+1 item', xp: '+1 XP', sorte: 'sorte (colheita em dobro às vezes)', cerca: 'vizinho pega no máximo 1',
        alarme: 'protegido do vizinho', estufa: 'estufa: qualquer estação e +25% rápido (4 ⚡)',
        robo: 'o robô colhe e replanta', aspersor: 'sem nenhum problema (aspersor, 1,6 ⚡)'
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

    /* ---------- A rede de canos (fase 39; igual a fazenda_rede no SQL) ----------
       Canos encostados uns nos outros formam uma rede; baús, oficinas, o celeiro (x 1..3, y 1..6)
       e a fábrica automática encostados num cano dela fazem parte dela. A oficina busca os
       ingredientes nos baús e no celeiro da rede; o produto vai para outra oficina da rede que usa
       ele, para o celeiro ou para um baú. Guarda tudo até as construções mudarem. */
    const VIZINHOS = [[1, 0], [-1, 0], [0, 1], [0, -1]];   // leste, oeste, sul, norte
    const CELEIRO_PEGADA = { x: 1, y: 1, w: 3, h: 6, papel: 'celeiro', tipo: 'celeiro' };
    // (a fazenda de quem você visita também tem a dela: cons = as construções de lá)
    let cacheCanos = {}, cacheCanosVisita = {};
    function redeCanos(consVisita) {
        const cons = consVisita || (S && S.construcoes) || [];
        if (consVisita && cacheCanosVisita.cons === cons) return cacheCanosVisita;
        if (!consVisita && cacheCanos.cons === cons) return cacheCanos;
        const set = new Set(cons.filter((c) => c.tipo === 'cano').map((c) => c.x + ',' + c.y));
        const redeDoCano = new Map();   // "x,y" do cano → número da rede
        let n = 0;
        for (const k0 of set) {
            if (redeDoCano.has(k0)) continue;
            n++;
            const fila = [k0];
            redeDoCano.set(k0, n);
            while (fila.length) {
                const [x, y] = fila.pop().split(',').map(Number);
                for (const [dx, dy] of VIZINHOS) {
                    const v = (x + dx) + ',' + (y + dy);
                    if (set.has(v) && !redeDoCano.has(v)) { redeDoCano.set(v, n); fila.push(v); }
                }
            }
        }
        const coisas = cons.filter((c) => { const it = tipoItem(c.tipo) || {}; return c.tipo === 'bau' || it.entradas || it.efeito === 'automatico'; })
            .map((c) => { const t = tamanhoItem(c.tipo), it = tipoItem(c.tipo) || {}; return { x: c.x, y: c.y, w: t.w, h: t.h, tipo: c.tipo, papel: c.tipo === 'bau' ? 'bau' : it.entradas ? 'oficina' : 'celeiro' }; });
        coisas.push(CELEIRO_PEGADA);
        const dentro = (k, x, y) => x >= k.x && y >= k.y && x < k.x + k.w && y < k.y + k.h;
        for (const k of coisas) {
            k.redes = new Set();
            for (const [ck, r] of redeDoCano) {
                const [x, y] = ck.split(',').map(Number);
                if (VIZINHOS.some(([dx, dy]) => dentro(k, x + dx, y + dy))) k.redes.add(r);
            }
        }
        const lados = new Map();   // braços de cada cano: para outro cano ou para algo da rede
        for (const ck of set) {
            const [x, y] = ck.split(',').map(Number);
            lados.set(ck, VIZINHOS.map(([dx, dy]) => set.has((x + dx) + ',' + (y + dy)) || coisas.some((k) => dentro(k, x + dx, y + dy))));
        }
        const membros = new Map();   // rede → quantas coisas ela liga (com 2 ou mais ela trabalha)
        for (const k of coisas) for (const r of k.redes) membros.set(r, (membros.get(r) || 0) + 1);
        const r = { cons, set, redeDoCano, coisas, lados, membros, caminhos: new Map() };
        if (consVisita) cacheCanosVisita = r; else cacheCanos = r;
        return r;
    }
    // o que está na mesma rede que a coisa em (x, y) (fora ela mesma)
    function vizinhosNaRede(x, y) {
        const r = redeCanos(), eu = r.coisas.find((k) => k.x === x && k.y === y && k.tipo !== 'celeiro');
        if (!eu || !eu.redes.size) return null;
        const outros = r.coisas.filter((k) => k !== eu && [...k.redes].some((n) => eu.redes.has(n)));
        return { baus: outros.filter((k) => k.papel === 'bau'), oficinas: outros.filter((k) => k.papel === 'oficina'), celeiro: outros.some((k) => k.papel === 'celeiro') };
    }
    const oficinaLigada = (c) => { const v = !!S && vizinhosNaRede(c.x, c.y); return !!v && (v.baus.length + v.oficinas.length > 0 || v.celeiro); };
    // caminho pelos canos de uma pegada até outra (para desenhar a viagem); [] se não achar
    function caminhoCanos(de, para) {
        const r = redeCanos(), chave = `${de.x},${de.y}>${para.x},${para.y}`;
        if (r.caminhos.has(chave)) return r.caminhos.get(chave);
        const dentro = (k, x, y) => x >= k.x && y >= k.y && x < k.x + k.w && y < k.y + k.h;
        const encosta = (k, ck) => { const [x, y] = ck.split(',').map(Number); return VIZINHOS.some(([dx, dy]) => dentro(k, x + dx, y + dy)); };
        const inicio = [...r.set].filter((ck) => encosta(de, ck));
        const veio = new Map(inicio.map((k) => [k, null]));
        const fila = [...inicio];
        let achou = null;
        while (fila.length) {
            const k = fila.shift();
            if (encosta(para, k)) { achou = k; break; }
            const [x, y] = k.split(',').map(Number);
            for (const [dx, dy] of VIZINHOS) {
                const v = (x + dx) + ',' + (y + dy);
                if (r.set.has(v) && !veio.has(v)) { veio.set(v, k); fila.push(v); }
            }
        }
        const cam = [];
        for (let k = achou; k; k = veio.get(k)) cam.push(k.split(',').map(Number));
        cam.reverse();
        r.caminhos.set(chave, cam);
        return cam;
    }
    // viagens dos itens (estado.viagens): o jogo só desenha cada uma enquanto ela acontece
    const pegada = (p) => {
        if (!p) return CELEIRO_PEGADA;
        const c = (S.construcoes || []).find((k) => k.x === p[0] && k.y === p[1]);
        const t = c ? tamanhoItem(c.tipo) : { w: 1, h: 1 };
        return { x: p[0], y: p[1], w: t.w, h: t.h };
    };
    const centro = (k) => [k.x + k.w / 2 - 0.5, k.y + Math.min(k.h, 3) / 2 - 0.5];
    /* Fase 44: cada unidade anda sozinha, em fila: 10 girassóis são 10 girassóis passando
       pelo cano, um atrás do outro (e o produto voltando para o celeiro do mesmo jeito). A viagem
       entra na fila quando o jogo a recebe pela primeira vez (o servidor manda as criadas nos
       últimos 2 minutos); quem vai pelo mesmo caminho espera o anterior sair. */
    const MS_POR_QUADRADO = 390;   // dá para acompanhar com o olho sem ficar parado (0,39 s por quadrado)
    const ESPACO_MS = 290;         // um logo atrás do outro: 10 itens viram uma fileira passando
    const MAX_POR_VIAGEM = 20, MAX_NA_TELA = 200;
    let viagensVistas = new Set(), listaVista = null, itensAndando = [];
    const filaRota = new Map();    // caminho → quando ele fica livre para o próximo item
    function agendarViagens(lista) {
        const t0 = agora();
        itensAndando = itensAndando.filter((v) => v.inicio + v.dur > t0);
        for (const [k, livre] of filaRota) if (livre < t0) filaRota.delete(k);
        for (const g of lista) {
            if (viagensVistas.has(g.id) || itensAndando.length >= MAX_NA_TELA) continue;
            const de = pegada(g.de), para = pegada(g.para);
            // pelo cano: sem caminho (a oficina ou o baú mudou de lugar, ou o cano saiu depois que a
            // viagem foi feita), não desenha; antes o item voava em linha reta por cima da fazenda
            const cam = g.direto ? [] : caminhoCanos(de, para);
            if (!g.direto && !cam.length) continue;
            const pontos = [centro(de), ...cam, centro(para)];
            const dur = Math.max(900, (pontos.length - 1) * MS_POR_QUADRADO);
            const rota = `${g.de}>${g.para}`;
            // a hora marcada só vale se for daqui a pouco (o servidor espalha as viagens em até 15 s)
            const marcada = Date.parse(g.em);
            let inicio = Math.max(filaRota.get(rota) || 0, t0, marcada > t0 && marcada < t0 + 20000 ? marcada : 0);
            for (let n = Math.min(g.qtd || 1, MAX_POR_VIAGEM); n > 0 && itensAndando.length < MAX_NA_TELA; n--) {
                itensAndando.push({ pontos, icone: A.cultura(g.item).item, inicio, dur, direto: g.direto });
                inicio += ESPACO_MS;
            }
            filaRota.set(rota, inicio);
        }
        viagensVistas = new Set(lista.map((g) => g.id));   // as que saem da lista não voltam
    }
    function visualViagens() {
        if (!S || visita) return [];
        const lista = S.viagens || [];
        if (lista !== listaVista) { listaVista = lista; agendarViagens(lista); }
        return itensAndando;
    }

    let oficinaAberta = null;   // { x, y } da oficina com o painel aberto
    let bauAberto = null;       // { x, y } do baú com o painel aberto
    const BAU_MAX = 200;        // igual a fazenda_bau_livre no SQL
    // painel do baú: o que ele guardou, de onde recolhe e para onde a rede leva
    function htmlBau(b) {
        const itens = Object.entries((S.baus || {})[b.x + ',' + b.y] || {}).filter(([, n]) => n > 0).sort((a, z) => z[1] - a[1]);
        const total = itens.reduce((a, [, n]) => a + n, 0);
        const rede = vizinhosNaRede(b.x, b.y);
        const usam = rede ? new Set(rede.oficinas.flatMap((k) => Object.keys(tipoItem(k.tipo).entradas || {}))) : new Set();
        const txtRede = !rede || (!rede.oficinas.length && !rede.celeiro)
            ? `Sem cano até uma oficina ou o celeiro: o que ele recolhe fica guardado aqui. Ligue com <b>canos de vidro</b> (Construir → Energia).`
            : `Na rede${rede.oficinas.length ? ` com ${rede.oficinas.length} oficina(s)` : ''}${rede.celeiro ? `${rede.oficinas.length ? ' e' : ' com'} o celeiro` : ''}: manda pelo cano o que as oficinas usam${rede.celeiro ? ' e leva o resto para o celeiro (1,6 ⚡ por viagem)' : ''}.`;
        return `
            <p>${total} de ${BAU_MAX} itens guardados</p>
            <span class="estoque-barra"><i style="width:${Math.min(100, Math.round(total / BAU_MAX * 100))}%"></i></span>
            ${itens.length ? '<div class="bau-itens">' + itens.map(([item, n]) => `<span class="chip" title="${nomeItem(item)}${usam.has(item) ? ' (uma oficina da rede usa)' : ''}">${itemDe(culturas[item] || { id: item }, 20)}<span>${n}${usam.has(item) ? ` ${A.htmlItem('cano', 12)}` : ''}</span></span>`).join('') + '</div>'
                : '<p class="vazio-msg">Vazio por enquanto.</p>'}
            <p class="aviso">${A.htmlItem('cano', 16)} ${txtRede}</p>
            <p class="det">Com energia, recolhe sozinho o que estiver encostado nele: o bloco de canteiros, um cercado (coleta e dá ração), uma árvore do pomar e o cesto do lago (1,6 ⚡ cada). Cheio, ele para de recolher.</p>
            <div class="rodape-painel">
                <button type="button" class="botao verde" data-bau-esvaziar${total ? '' : ' disabled'}>Levar tudo para o celeiro</button>
                <button type="button" class="botao creme" data-fechar>Fechar</button>
            </div>`;
    }
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
    // o que falta na rede para mais uma receita: conta o que já chegou na oficina pelo cano, os baús
    // da rede e o celeiro, se a rede chega nele (igual a fazenda_rede_puxar no SQL)
    function faltaNaRede(o) {
        const chegou = (S.oficina_itens || {})[o.x + ',' + o.y] || {};
        return Object.entries(o.it.entradas).map(([item, qtd]) => {
            let tem = chegou[item] || 0;
            for (const b of o.rede.baus) tem += ((S.baus || {})[b.x + ',' + b.y] || {})[item] || 0;
            if (o.rede.celeiro) tem += Math.max(0, naCeleiro(item) - reservaDe(item));
            return { item, falta: qtd - tem };
        }).filter((f) => f.falta > 0);
    }
    const listaFalta = (falta) => falta.map((f) => `${f.falta} ${itemDe(culturas[f.item] || { id: f.item }, 16)}`).join(', ');
    // por que a rede não manda mais (ou que ela está mandando)
    function motivoRede(o) {
        const falta = faltaNaRede(o);
        const onde = `nos baús${o.rede.celeiro ? ' ou no celeiro' : ''}`;
        // o que outra oficina da rede faz chega sozinho pelo cano quando ela terminar
        const quemFaz = (item) => o.rede.oficinas.find((k) => tipoItem(k.tipo).produz === item);
        const semFonte = falta.filter((f) => !quemFaz(f.item));
        if (falta.length && !semFonte.length) {
            const nomes = [...new Set(falta.map((f) => esc(tipoItem(quemFaz(f.item).tipo).nome.toLowerCase())))].join(' e ');
            return `esperando ${listaFalta(falta)} chegar pelo cano (quem faz na rede: ${nomes}).`;
        }
        if (falta.length) return `falta na rede ${listaFalta(semFonte)}. Guarde ${onde} da rede e ela enche o estoque sozinha.`;
        if (cargaAgora() < 2) return `a rede está sem energia (2 ${ico('raio', 12)} por receita).`;
        return null;
    }
    function htmlOficinaAgora(o) {
        const p = (n) => `${n} ${itemDe(o.produto, 18)}`;
        const abastece = o.ligada && (o.rede.baus.length > 0 || o.rede.celeiro);   // a rede tem de onde trazer ingrediente
        const linhas = [];
        if (o.prontos) linhas.push(`<b>${p(o.prontos)} pronto(s)</b> esperando você pegar.`);
        if (o.estado === 'trabalhando') {
            linhas.push(`Fazendo ${nomeItem(o.it.produz)}: pronto em <b>${fmtTempo(o.falta)}</b>
                <span class="barrinha"><i style="width:${Math.round(o.progresso * 100)}%"></i></span>`);
            if (o.estoque) linhas.push(`Depois faz mais ${o.estoque} sozinha: termina tudo em ${fmtTempo(o.termina - agora())}.`);
            else if (abastece) { const m = motivoRede(o); linhas.push(m ? `Depois dessa, para: ${m}` : `${A.htmlItem('cano', 16)} A rede está mandando mais ingredientes: o estoque enche sozinho.`); }
            else linhas.push('Depois dessa, para: o estoque está vazio.');
        } else if (abastece) {
            const m = motivoRede(o);
            linhas.push(m ? `Parada: ${m}` : `${A.htmlItem('cano', 16)} Os ingredientes já estão a caminho pelo cano: ela começa em instantes.`);
        } else {
            linhas.push('Parada: guarde ingredientes no estoque e ela começa na hora.');
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
            <p class="det">${o.ligada && (o.rede.baus.length || o.rede.celeiro)
                ? `${A.htmlItem('cano', 14)} <b>A rede enche este estoque sozinha</b> (até ${max} receitas, 2 ${ico('raio', 12)} cada) com o que tem nos baús${o.rede.celeiro ? ' e no celeiro' : ''} da rede. Você também pode guardar do celeiro aqui.`
                : 'Guardar tira os ingredientes do celeiro agora (a ração reservada fica). Ela trabalha sozinha até o estoque acabar.'}</p>
            <div class="estoque-botoes">
                <button type="button" class="botao pequeno creme" data-estoque="1"${pode >= 1 ? '' : ' disabled'}>+1</button>
                <button type="button" class="botao pequeno creme" data-estoque="5"${pode >= 5 ? '' : ' disabled'}>+5</button>
                <button type="button" class="botao pequeno verde" data-estoque="${pode}"${pode >= 1 ? '' : ' disabled'}>Encher${pode ? ` (+${pode})` : ''}</button>
                <button type="button" class="botao pequeno creme" data-estoque="-${o.estoque}"${o.estoque ? '' : ' disabled'}>Tirar tudo</button>
            </div>
            ${!cabe ? '<p class="aviso">Estoque cheio.</p>'
                : falta.length ? `<p class="aviso">Para mais uma receita faltam no celeiro: ${falta.map((f) => `${f.falta} ${itemDe(culturas[f.item] || { id: f.item }, 16)}`).join(', ')}.</p>` : ''}
            ${o.ligada ? `<p class="aviso">${A.htmlItem('cano', 18)} Na rede: ${o.rede.baus.length} baú(s)${o.rede.oficinas.length ? `, ${o.rede.oficinas.length} oficina(s)` : ''}${o.rede.celeiro ? ' e o celeiro' : ''}. O produto sai pelo cano para a oficina que usa ele, o celeiro ou um baú. Luz verde nos canos: a rede está trabalhando; vermelha piscando: falta energia.</p>
                ${o.rede.celeiro ? '' : `<p class="det">O celeiro não está nesta rede: ela só pega o que está nos baús. Para usar o que está no celeiro, encoste um cano no próprio celeiro (o prédio grande no canto de cima, à esquerda).</p>`}`
                : S.jogador.nivel >= 16 ? `<p class="det">${A.htmlItem('cano', 16)} Dica: ligue esta oficina com <b>canos de vidro</b> (Construir → Energia) a baús, a outras oficinas e ao celeiro: tudo o que está na mesma rede de canos trabalha junto.</p>` : ''}
            ${lojaD() && o.ligada && cargaAgora() < 2 && precoEnergiaDiamantes() > 0
                ? `<p class="det">${ico('raio', 14)} Sem energia a rede para. ${botaoDiamante('energia', precoEnergiaDiamantes(), 'Encher a energia')}</p>` : ''}
            <div class="rodape-painel">
                ${o.prontos ? `<button type="button" class="botao verde" data-oficina-pegar>Pegar ${o.prontos} ${itemDe(o.produto, 18)}</button>` : '<span></span>'}
                ${lojaD() && o.estado === 'trabalhando' ? botaoDiamante('oficina', precoOficinaDiamantes(o), 'Terminar agora', ` data-x="${c.x}" data-y="${c.y}"`) : ''}
                <button type="button" class="botao creme" data-fechar>Fechar</button>
            </div>`;
    }

    function coletarItem(x, y) {
        const c = (S.construcoes || []).find((k) => k.x === x && k.y === y);
        if (c && (tipoItem(c.tipo) || {}).efeito === 'biomassa') return alternarGerador(c);
        const o = c && infoOficina(c);
        if (o) return acaoOficina(c, o);
        if (c && c.tipo === 'bau' && !visita) { bauAberto = { x, y }; return abrirPainel('bau'); }
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
        if (!visita && (c.tipo === 'casa_vermelha' || c.tipo === 'casa_azul') && descreverCasa(c.x + ',' + c.y)) return;   // fase 66
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
        aoCasa: () => { if (S && !painelAtual && !visita) descreverCasa('casa'); },   // fase 66: quem dorme na casa da fazenda
        aoVenda: () => { if (S && !painelAtual) { abaLoja = 'terrenos'; abrirPainel('loja'); } },
        aoFeira: () => {   // fase 51: a pracinha da feira, na mata
            if (!S || painelAtual) return;
            abaFeira = !visita && S.feira && S.feira.meus.length ? 'meus' : 'comprar';
            abrirPainel('feira');
        },
        aoLago: () => { if (S && !painelAtual && !visita) pescar(); },
        aoVisitante: () => { if (S && !painelAtual && visitaAgora()) abrirPainel('visitante'); },
        aoPier: () => { if (S && !painelAtual && !visita) abrirPainel('pier'); },   // fase 61
        aoBarco: () => { if (S && !painelAtual && !visita) abrirMar(); },   // fase 62: o barco atracado leva para o alto-mar
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
            else if (alvo === 'feira') mostrarStatus(visita ? `${A.htmlItem('barraca', 22)} <b>Feira</b>: toque para comprar dos outros jogadores.`
                : `${A.htmlItem('barraca', 22)} <b>Feira</b>: ${barracas()} barraca${barracas() > 1 ? 's' : ''}, até ${limiteFeira()} anúncios. Toque para comprar e vender com outros jogadores.`);
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
    cena.definirRelogio(agora);   // a noite do jogo segue o relógio do servidor
    cena.definirViagens(visualViagens);   // os itens andando pela rede de canos
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
    // (fase 47: no pomar, cada fruta tem 1 pé e +1 a cada 2 terrenos, até 4; igual a fazenda_construir)
    const melhoriaNivel = (id) => (S && S.melhorias && S.melhorias[id]) || 0;
    const melhoriaValor = (id) => { const m = ((S && S.melhorias_tipos) || []).find((k) => k.id === id); const n = melhoriaNivel(id); return m && n ? m.niveis[n - 1].valor : 0; };
    // fase 57: painel solar e turbina sobem com o nível, um de cada vez (igual a fazenda_limite_maquina);
    // o limite de agora já vem do servidor em S.itens, isto serve para dizer quando sobe de novo
    const limiteMaquina = (id, base, n) => (id === 'painel_solar' ? base + Math.max(0, Math.floor((n - 16) / 2))
        : id === 'turbina' ? base + Math.max(0, Math.floor((n - 17) / 2)) : base);
    const proximoNivelMaquina = (it) => {
        if (it.id !== 'painel_solar' && it.id !== 'turbina') return null;
        const base = (it.limite || 0) - limiteMaquina(it.id, 0, S.jogador.nivel);
        for (let n = S.jogador.nivel + 1; n <= S.jogador.nivel + 2; n++) if (limiteMaquina(it.id, base, n) > it.limite) return n;
        return null;
    };
    const maxItem = (it) => it.limite || (it.por_terreno ? it.por_terreno * (1 + (it.categoria === 'pomar' ? Math.floor(((S && S.jogador.zonas) || 0) / 2) : ((S && S.jogador.zonas) || 0)))
        + (it.categoria === 'pomar' ? melhoriaValor('pes') : 0) : null);   // fase 57: + os pés da melhoria
    // quantos já tem (itens do mesmo grupo dividem o limite; desde a fase 43 cada árvore frutífera conta só ela)
    const quantosTem = (it) => (S.construcoes || []).filter((c) => c.tipo === it.id || (it.grupo && (tipoItem(c.tipo) || {}).grupo === it.grupo)).length;
    // fase 45: quem já tinha o bicho antes do cercado obrigatório ganha o primeiro cercado dele
    const cercadoGratis = (it) => !!it && (it.id || '').startsWith('cercado_') && ((S && S.jogador.cercado_gratis) || []).includes(it.id.slice(8));
    const custoItem = (it) => (cercadoGratis(it) ? 0 : it.custo);
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
            return mostrarStatus(it ? `${A.htmlItem(c.tipo, 22)} Toque para guardar ${esc(it.nome.toLowerCase())} (volta ${moeda(Math.floor((c.pago != null ? c.pago : it.custo) / 2))}, metade do que pagou).` : 'Nada para guardar aqui.');
        }
        if (constr.modo === 'mover') {
            if (constr.movendo) return mostrarStatus(c ? 'Esse lugar está ocupado.' : 'Toque para levar o item para cá.');
            return mostrarStatus(it ? `${A.htmlItem(c.tipo, 22)} Toque para escolher ${esc(it.nome.toLowerCase())} e depois o novo lugar.` : 'Toque num item para mover.');
        }
        const sel = tipoItem(constr.tipo);
        if (c) return mostrarStatus(`${A.htmlItem(c.tipo, 22)} ${esc(it ? it.nome : c.tipo)}. ${it && it.descricao ? esc(it.descricao) + ' ' : ''}Toque nele para mudar de lugar, ou use Guardar.`);
        if (sel && sel.id === 'canteiro') return mostrarStatus(`${A.htmlItem('canteiro', 22)} Toque para colocar um canteiro (sobram ${canteirosLivres()}).`);
        mostrarStatus(sel ? `${A.htmlItem(sel.id, 22)} Toque para colocar ${esc(sel.nome.toLowerCase())} (${cercadoGratis(sel) ? 'de graça' : moeda(sel.custo)}).` : 'Escolha um item na barra de baixo.');
    }

    function abrirConstrucao() {
        if (!S || visita) return;
        constr.ativo = true;
        constr.modo = 'colocar';
        constr.movendo = null;
        constr.rapido = false;
        constr.voltar = null;
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
        constr.voltar = null;
        document.body.classList.remove('construindo');
        el.barraConstr.hidden = true;
        el.barra.hidden = false;
        atualizarModo();
        mostrarStatus(typeof msg === 'string' ? msg : 'Fazenda salva do seu jeito!');
        ajustarMargens(true);
    }

    function desenharPaleta() {
        if (!S || !S.itens) return;
        const abas = [['plantacao', 'Plantação'], ['pomar', 'Pomar'], ['bichos', 'Bichos'], ['oficina', 'Oficinas'], ['maquina', 'Máquinas'], ['energia', 'Energia'], ['caminho', 'Cercas e caminhos'], ['natureza', 'Natureza'], ['objeto', 'Objetos'], ['construcao', 'Casas'], ['praia', 'Praia']];
        el.constrAbas.innerHTML = abas.map(([id, txt]) =>
            `<button type="button" data-constr-aba="${id}" class="${constr.aba === id ? 'ativa' : ''}">${txt}</button>`).join('');
        // por nível (o que já libera primeiro); no mesmo nível, a ordem do catálogo. A ordem do catálogo
        // segue a fase em que cada item entrou, e deixava oficina liberada no fim da lista
        const lista = constr.aba === 'plantacao' ? [ITEM_CANTEIRO]
            : S.itens.filter((i) => i.categoria === constr.aba).sort((a, b) => a.nivel_min - b.nivel_min || a.ordem - b.ordem);
        el.constrItens.innerHTML = lista.map((i) => {
            const travado = i.nivel_min > S.jogador.nivel;
            const sel = constr.modo === 'colocar' && constr.tipo === i.id;
            const max = maxItem(i), tem = max ? quantosTem(i) : 0;
            const preco = i.id === 'canteiro' ? `${S.canteiros.length}/${S.jogador.max_canteiros}`
                : max && tem >= max ? (i.por_terreno ? `${tem}/${max}` : 'Já tem') : cercadoGratis(i) ? 'Grátis' : `${ico('moeda', 11)}${i.custo}`;
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

        // fase 73c: com um item escolhido para colocar, tocar numa oficina, casa, máquina ou enfeite que já
        // está lá pega ele para mudar de lugar (quem tocava na oficina para mover ouvia "não cabe aqui").
        // Caminhos e cercas ficam de fora (pintando caminho, tocar num que já existe não pega nada).
        const itOcupado = ocupado && tipoItem(ocupado.tipo);
        if (constr.modo === 'colocar' && ocupado && !(itOcupado && itOcupado.categoria === 'caminho')) {
            constr.voltar = constr.tipo;   // depois de soltar, volta a colocar o que estava escolhido
            constr.modo = 'mover';
            constr.movendo = { x: ocupado.x, y: ocupado.y, tipo: ocupado.tipo, ...tamanhoItem(ocupado.tipo) };
            atualizarModo();
            som.tocar('construir');
            return mostrarStatus(`${A.htmlItem(ocupado.tipo, 22)} Pegou ${esc(itOcupado ? itOcupado.nome.toLowerCase() : 'o item')}! Agora toque no lugar novo (ou nele mesmo para desistir).`);
        }

        if (constr.modo === 'colocar' && constr.tipo === 'canteiro') {
            if (ocupado || cant) return toast(ERROS.lugar_ocupado, 'erro');
            if (!canteirosLivres()) return toast(ERROS.limite_canteiros, 'erro');
            // aparece na hora (com um número provisório); o servidor confirma em seguida
            const novo = (s) => { if (!s.canteiros.some((c) => c.x === x && c.y === y)) s.canteiros.push({ posicao: 1000 + s.canteiros.length, x, y, estado: 'vazio' }); };
            novo(S);
            desenharHud();
            som.tocar('construir');
            enfileirarOtimista(novo, () => rpc('fazenda_construir', { p_token: token, p_tipo: 'canteiro', p_x: x, p_y: y }))
                .then(() => { desenharPaleta(); if (!S.canteiros.some((c) => c.x === x && c.y === y)) recarregar(); });
            return;
        }

        if (constr.modo === 'colocar') {
            const it = tipoItem(constr.tipo);
            if (!it) return toast('Escolha um item na barra de baixo.', undefined, 'leve');
            const max = maxItem(it), tem = quantosTem(it);
            const proxMaq = max && tem >= max ? proximoNivelMaquina(it) : null;
            if (max && tem >= max) return toast(it.por_terreno ? `Já tem ${tem} de ${max} ${esc(it.nome.toLowerCase())}s: compre mais terrenos (Loja → Terrenos) para plantar mais: cada fruta tem 1 pé, +1 a cada 2 terrenos (até 4), e mais na Loja → Melhorias. As outras frutas têm o limite delas.`
                : proxMaq ? `Já tem ${tem} de ${max} (${esc(it.nome.toLowerCase())}). No nível ${proxMaq} libera mais um.` : ERROS.limite_maquina, 'erro');            const tam = tamanhoItem(it.id);
            if (!cabeAqui(x, y, tam.w, tam.h)) {
                return toast(tam.w > 1 ? `Não cabe aqui: ${esc(it.nome.toLowerCase())} precisa de ${tam.w}×${tam.h} quadrados livres.` : ERROS.lugar_ocupado, 'erro');
            }
            if (it.nivel_min > S.jogador.nivel) return toast(`${esc(it.nome)} libera no nível ${it.nivel_min}.`);
            const custo = custoItem(it);
            if (S.jogador.moedas < custo) return toast(ERROS.moedas_insuficientes, 'erro');
            // aparece na hora; o servidor confirma em seguida
            const gratis = cercadoGratis(it);
            const colocar = (s) => {
                if (s.construcoes.some((c) => c.x === x && c.y === y)) return;
                s.construcoes.push({ x, y, tipo: it.id });
                s.jogador.moedas -= custo;
                if (gratis) s.jogador.cercado_gratis = (s.jogador.cercado_gratis || []).filter((b) => b !== it.id.slice(8));
            };
            colocar(S);
            desenharHud();
            som.tocar('construir');
            flutuarTile(x, y, custo ? `−${custo} ${ico('moeda', 16)}` : 'De graça!');
            enfileirarOtimista(colocar, () => rpc('fazenda_construir', { p_token: token, p_tipo: it.id, p_x: x, p_y: y }))
                .then(() => { if (!S.construcoes.some((c) => c.x === x && c.y === y)) recarregar(); });
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
            // fase 73c: quem pegou tocando no item com outro escolhido volta a colocar aquele depois
            const voltarColocar = () => { if (constr.voltar) { constr.modo = 'colocar'; constr.tipo = constr.voltar; constr.voltar = null; } };
            if (de.x === x && de.y === y) {
                constr.movendo = null;
                if (constr.rapido) return fecharConstrucao('Ficou no mesmo lugar.');
                voltarColocar();
                return atualizarModo();
            }
            if (!cabeAqui(x, y, de.w, de.h, c)) {
                if (!constr.rapido && !constr.voltar) { constr.movendo = null; atualizarModo(); }   // no rápido (e pego tocando) continua na mão
                return toast(de.w > 1 ? `Não cabe aqui: precisa de ${de.w}×${de.h} quadrados livres. Continua na mão: toque em outro lugar (ou nele mesmo para desistir).` : ERROS.lugar_ocupado, 'erro');
            }
            constr.movendo = null;
            voltarColocar();
            atualizarModo();
            const mover = (s) => {
                const m = (de.tipo === 'canteiro' ? s.canteiros : s.construcoes).find((k) => k.x === de.x && k.y === de.y);
                if (m) { m.x = x; m.y = y; }
            };
            mover(S);
            cacheCanos = {};   // (a posição mudou no lugar: a rede de canos se refaz com ela)
            if (constr.rapido) fecharConstrucao(`${A.htmlItem(de.tipo, 22)} Mudou de lugar!`);
            som.tocar('construir');
            // fase 73b: o servidor só confirma (p_leve), sem mandar a fazenda inteira de volta: refazer
            // tudo a cada movimento travava quem movia várias oficinas seguidas. Se ele recusar, a
            // fazenda volta a ser a do servidor.
            const o = { refazer: (s) => { mover(s); cacheCanos = {}; } };
            otimistas.add(o);
            enfileirar([], async () => {
                try {
                    await rpc('fazenda_mover', { p_token: token, p_x: de.x, p_y: de.y, p_nx: x, p_ny: y, p_leve: true });
                } catch (e) {
                    otimistas.delete(o);
                    try { aplicarEstado(await rpc('fazenda_carregar', { p_token: token })); } catch (e2) { /* a próxima busca acerta */ }
                    throw e;
                }
                otimistas.delete(o);
            });
        } else if (constr.modo === 'guardar' && cant) {
            if (cant.estado === 'plantado') return toast('Tem planta nesse canteiro: colha (ou limpe) antes de guardar.', 'erro');
            const tirar = (s) => { s.canteiros = s.canteiros.filter((c) => c.x !== x || c.y !== y); };
            tirar(S);
            som.tocar('construir');
            enfileirarOtimista(tirar, () => rpc('fazenda_demolir', { p_token: token, p_x: x, p_y: y }))
                .then(() => desenharPaleta());
        } else if (constr.modo === 'guardar') {
            if (!ocupado) return;
            const ax = ocupado.x, ay = ocupado.y;
            const tirar = (s) => { s.construcoes = s.construcoes.filter((c) => c.x !== ax || c.y !== ay); };
            tirar(S);
            enfileirarOtimista(tirar, async () => {
                const r = await rpc('fazenda_demolir', { p_token: token, p_x: ax, p_y: ay });
                flutuarTile(ax, ay, `+${r.devolvido} ${ico('moeda', 16)}`);
                som.tocar('moeda');
                return r;
            });
        }
    }

    const barraDeBaixo = () => (!el.barraConstr.hidden ? el.barraConstr : el.barra.hidden ? null : el.barra);
    const alturaDe = (barra) => (barra ? window.innerHeight - barra.getBoundingClientRect().top : 0);
    function ajustarMargens(manter) {
        const topo = el.hud.hidden ? 24 : el.hud.getBoundingClientRect().bottom + 8;
        // o que fica logo abaixo do topo (mensagens, faixa de visita, tutorial) acompanha a altura dele
        if (!el.hud.hidden) document.documentElement.style.setProperty('--hud-fundo', `${Math.round(el.hud.getBoundingClientRect().bottom)}px`);
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
        let alturaHud = 0;
        new ResizeObserver(() => {
            const h = Math.round(el.hud.getBoundingClientRect().height);
            if (h && h !== alturaHud) { alturaHud = h; ajustarMargens(true); }
        }).observe(el.hud);
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
        const btnAdmin = document.getElementById('btnAdmin');
        if (btnAdmin) btnAdmin.hidden = !j.admin;
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
        // XP em dobro ligado (diamantes): a barra fica dourada e o texto ganha um ×2
        const dobro = j.xp2_ate && Date.parse(j.xp2_ate) > agora();
        el.xpBar.parentElement.classList.toggle('dobro', !!dobro);
        const bonusM = j.bonus_nivel != null && j.bonus_nivel === j.nivel;   // fase 49: metas em dia
        const completa = bonusM && j.nivel >= 20;   // fase 57: fazenda completa: +75% e arar/plantar dão XP (fase 70: na colheita)
        el.xpBar.parentElement.classList.toggle('bonus', bonusM);
        el.xpBar.parentElement.title = [dobro ? `XP em dobro até ${hora(j.xp2_ate)}` : '',
            completa ? 'Fazenda completa: +75% de XP até o próximo nível, e cada colheita sua dá +2 XP (o de arar e plantar)'
                : bonusM ? 'Metas em dia: +50% de XP até o próximo nível' : ''].filter(Boolean).join(' · ') || 'Experiência';
        if (dobro) el.xp.textContent += ' ×2';
        if (bonusM) el.xp.textContent += completa ? ' +75%' : ' +50%';
        const cm = $('hudMetas'), fm = metasDoNivelFaltando();
        if (cm) { cm.textContent = fm; cm.hidden = !fm; }
        const ce = $('hudEvento'), fe = fimEvento() - agora();   // fase 63: faltam menos de 6 horas para o evento fechar
        if (ce) ce.hidden = !(fe > 0 && fe < 6 * 3600e3);
        const hc = $('hudChat');   // fase 67: mensagem nova no chat
        if (hc) { hc.hidden = !chatNaoLido(); atualizarAlertaMenu(); }
        const hcal = $('hudCalendario');   // fase 69: prêmio do dia esperando
        if (hcal) { hcal.hidden = !calendarioPronto(); atualizarAlertaMenu(); }
        if (el.hudPerfil) {
            const prox = j.nivel < NIVEL_MAX ? liberaNoNivel(j.nivel + 1).slice(0, 3).map((x) => x.nome).join(', ') : '';
            el.hudPerfil.title = j.nivel < NIVEL_MAX
                ? `Faltam ${j.xp_proximo - j.xp} XP para o nível ${j.nivel + 1}${prox ? ': ' + prox : ''}. Toque para abrir o seu perfil.`
                : 'Nível máximo! Toque para abrir o seu perfil.';
        }
        desenharContadorHistorico();
        const diam = String(j.diamantes || 0);
        if (el.diamantes && el.diamantes.textContent !== diam) el.diamantes.textContent = diam;
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
        if (i.fase === 'murcho') return 'pode_salvar' in visita
            ? (visita.pode_salvar ? `${ico('coracao', 14)} O ${esc(i.k.nome.toLowerCase())} do vizinho murchou. Toque para <b>salvar</b> (até 2 por dia em cada fazenda): ela volta madura e você ganha +${3 * (visita.premio_ajuda || 1)} ${ico('xp', 14)}.`
                : `O ${esc(i.k.nome.toLowerCase())} do vizinho murchou. Você já salvou duas plantas aqui hoje.`)
            : `O ${esc(i.k.nome.toLowerCase())} do vizinho murchou.`;
        let txt;
        if (i.fase === 'maduro') {
            if (c.ja_peguei) txt = `${item} Você já pegou desse ${esc(i.k.nome.toLowerCase())}.`;
            else if (protegidoAlarme(c)) txt = `${item} ${esc(i.k.nome)} protegido pelo alarme antiladrão do vizinho.${luvas() ? ` Você tem ${luvas()} ${itemDe(culturas.luva_perks || { id: 'luva_perks' }, 16)} luva(s) do Perks: toque para passar (gasta 1).` : ''}`;
            else if (c.roubado >= limitePegar(i.k)) txt = `${item} Já pegaram bastante desse ${esc(i.k.nome.toLowerCase())}.`;
            else txt = `${item} ${esc(i.k.nome)} maduro! Toque para pegar até 3 ${ico('mao', 16)}`;
        } else {
            txt = `${item} ${esc(i.k.nome)} do vizinho · pronto em ${fmtTempo(i.resta)}.`;
        }
        if (i.probs.length) txt += ` Ajude com ${probsHtml(i.probs)} e ganhe +${i.probs.length * (visita.premio_ajuda || 1)} ${ico('xp', 14)}.`;
        return txt;
    }

    function descrever(p) {
        const c = canteiro(p);
        if (!c) return;
        const i = info(c);
        if (visita) return mostrarStatus(descreverVisita(c, i));
        let txt;
        switch (i.fase) {
            case 'vazio': txt = `${spr(86, 22)} Terra batida. Toque para arar${S.jogador.nivel <= 5 ? ` (+1 ${ico('xp', 14)})` : ''}.`; break;
            case 'arado': {
                const k = culturas[semente];
                txt = k ? `${itemDe(k)} Toque para plantar ${esc(k.nome.toLowerCase())} (${moeda(k.custo)}).` : 'Pronto para plantar.';
                break;
            }
            case 'murcho': txt = `${spr(A.cultura(i.k.id).murcho, 22)} ${esc(i.k.nome)} murchou. ${(S.jogador.diamantes || 0) >= precoMurchas() ? `Toque para salvar (${precoMurchas()} ${ico('diamante', 12)} salva${precoMurchas() === 1 ? '' : 'm'} todas as murchas) ou arar.` : 'Toque para limpar.'}`; break;
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
        if (radioativo(a)) {   // fase 68
            const resta = Date.parse(a.radioativo_ate) - agora(), dados = Math.min(15, Math.floor((30 * 60000 - resta) / 120000));
            return mostrarStatus(`${spr(A.ANIMAL[a.tipo], 22)} ${nome}${visita ? ' do vizinho' : ''} <b>radioativ${FEMEA.has(a.tipo) ? 'a' : 'o'}</b> (o reator!): dá 1 ${produto ? esc(produto.nome.toLowerCase()) : 'produto'} a cada 2 minutos, direto no celeiro, até ${hora(a.radioativo_ate)} (já deu ${dados} de 15). No fim, 1 em 200 de não resistir.`);
        }
        if (visita) {
            if (i.estado === 'fome' && 'bichos_hoje' in visita) {
                return mostrarStatus(visita.bichos_hoje < 10
                    ? `${spr(A.ANIMAL[a.tipo], 22)} ${nome} do vizinho com fome: toque para dar ração (do celeiro dele) e ganhe +${visita.premio_ajuda || 1} ${ico('xp', 14)}.`
                    : `${spr(A.ANIMAL[a.tipo], 22)} ${nome} do vizinho com fome. Você já deu ração a 10 bichos aqui hoje.`);
            }
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
        if (!S || painelAtual) return;
        if (visita) {   // fase 48: na visita, toque no bicho com fome dá ração
            if (typeof id === 'string') return;
            descreverAnimal(id);
            const a = (visita.animais || []).find((x) => x.id === id);
            if (a && infoAnimal(a).estado === 'fome' && 'bichos_hoje' in visita && visita.bichos_hoje < 10) alimentarBichosVizinho([id]);
            return;
        }
        if (typeof id === 'string' && id.startsWith('h:')) { ajudanteAberto = id.slice(2); return abrirPainel('ajudante'); }   // fase 59
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
    // Fase 59: o servidor já tem itens que este jogo aberto não conhece (o SQL novo entrou antes de
    // a página recarregar): tudo novo aparecia como pedra. Recarrega uma vez para pegar a versão nova;
    // se mesmo assim faltar (arte ainda não publicada), não fica recarregando.
    function versaoNova(estado) {
        if (!A.conhece) return false;
        const faltam = (estado.itens || []).filter((i) => !A.conhece(i.id)).map((i) => i.id)
            .concat((estado.culturas || []).filter((k) => !A.conhece(k.id, true)).map((k) => k.id));
        if (!faltam.length) return false;
        let tentou = null;
        try { tentou = sessionStorage.getItem('fazenda_versao'); } catch { /* ignora */ }
        if (tentou === faltam.join(',')) return false;
        try { sessionStorage.setItem('fazenda_versao', faltam.join(',')); } catch { return false; }
        location.reload();
        return true;
    }

    function aplicarEstado(estado) {
        const antes = S;
        // longe = primeira carga ou voltou depois de um tempo: aí o relatório dos ajudantes vira aviso
        const longe = !antes || Date.now() - ultimoEstadoEm > 5 * 60 * 1000;
        ultimoEstadoEm = Date.now();
        if (!estado.diario) estado.diario = []; // banco ainda sem o SQL da fase 2
        if (!estado.construcoes) estado.construcoes = [];
        S = estado;
        cacheCanos = {};   // fase 73b
        if (versaoNova(estado)) return;
        otimistas.forEach((o) => o.refazer(S));   // fase 56: o que ainda está na fila continua na tela
        offset = Date.parse(estado.agora) - Date.now();
        culturas = {};
        for (const k of estado.culturas) culturas[k.id] = k;
        if (!culturas[semente] || culturas[semente].tipo !== 'cultura') semente = 'alface';   // (amora deixou de ser semente)

        if (antes && antes.conquistas && estado.conquistas) {
            const velhas = new Set(antes.conquistas.map((c) => c.id));
            estado.conquistas.filter((c) => !velhas.has(c.id)).forEach((c) => {
                const t = (estado.conquistas_tipos || []).find((x) => x.id === c.id);
                if (!t) return;
                toast(`${ico('medalha', 22)} Conquista: <b>${esc(t.nome)}</b>! +${moeda(t.recompensa)}${t.diamantes ? ` +${t.diamantes} ${ico('diamante', 16)}` : ''}`, 'festa');
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
        avisarFeira(estado);
        avisarReservas(estado);   // fase 67
        avisarRadiacao(estado);   // fase 68
        desenharClima();
        agendarAvisos();
        energiaEm = agora();
        desenharEnergia();
        atualizarBotaoAnuncio();
        atualizarLago();
        atualizarGalinheiro();
        atualizarFeiraMapa();
        atualizarVisitante();
        if (!visita) cena.definirAvatar(estado.jogador.avatar);
        atualizarTerreno();
        desenharHud();
        if (constr.ativo) desenharPaleta();
        // fase 66: o que murchou sem ninguém colher desde a última vez (o servidor manda uma vez só)
        const novasM = (estado.murchas && estado.murchas.novas) || [];
        if (novasM.length) {
            murchasNovas = novasM;
            if (!painelAtual) abrirPainel('murchas');
            else toast(`${ico('sino', 18)} ${textoMurcha(novasM[0].motivo, novasM[0].detalhe, novasM[0].qtd)} Toque numa murcha para ver o motivo.`, undefined, 'importante');
        }
        if (!visita) checarNovidades(estado);   // fase 67
        if (!visita) checarCalendario(estado);   // fase 69: o prêmio de hoje (abre sozinho uma vez por dia)
        // fase 63: prêmio novo do evento da semana (o servidor manda uma vez só)
        const novosEv = (estado.evento && estado.evento.novos) || [];
        if (novosEv.length) {
            eventoPremios = novosEv;
            som.tocar('festa');
            if (!painelAtual) abrirPainel('eventoPremio');
            else toast(`${itemDe(culturas.trofeu_ouro || { id: 'trofeu_ouro' }, 20)} Evento da semana: você subiu ao pódio em ${novosEv.length === 1 ? '1 categoria' : novosEv.length + ' categorias'}! Os prêmios já estão com você.`, 'festa', 'importante');
        }
        if (['loja', 'celeiro', 'missoes', 'oficina', 'energia', 'canteiro', 'bau', 'ajudante', 'pier', 'mar'].includes(painelAtual)) abrirPainel(painelAtual, true);
        if (mar) { if (!S.mar || visita) fecharMar(); else mar.atualizar(); }   // fase 62
    }

    /* ---------- Diário: quem passou pela sua fazenda ---------- */
    const quando = (d) => Date.parse(d.em);
    const diarioNovos = () => (S ? S.diario.filter((d) => quando(d) > (Number(store.get(LS.diarioVisto)) || 0)) : []);

    function textoDiario(d) {
        const k = culturas[d.cultura];
        const item = k ? `${itemDe(k, 18)}${esc(k.nome.toLowerCase())}` : esc(d.cultura);
        if (d.tipo === 'salvar') return `<b>${esc(d.apelido)}</b> salvou o seu ${item} que tinha murchado!`;
        if (d.tipo === 'bicho') return `<b>${esc(d.apelido)}</b> deu ração (${item}) para um bicho seu.`;
        return d.tipo === 'roubo'
            ? `<b>${esc(d.apelido)}</b> pegou ${d.qtd} ${item} da sua fazenda!${d.luva ? ' Passou pelo alarme com a luva do Perks.' : ''}`
            : `<b>${esc(d.apelido)}</b> cuidou do seu ${item} (${d.qtd} problema${d.qtd > 1 ? 's' : ''}).`;
    }

    // celular: o ☰ mostra a soma dos avisos que ficaram dentro dele (missões e diário)
    function atualizarAlertaMenu() {
        if (!el.menuCont) return;
        const n = [el.missoesCont, el.diarioCont].reduce((soma, b) => soma + (b && !b.hidden ? Number(b.textContent) || 0 : 0), 0)
            + (chatNaoLido() ? 1 : 0) + (calendarioPronto() ? 1 : 0);   // fase 67 e 69
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
        const linha = (x) => (x.tipo === 'roubo' ? ico('guaxinim', 20) : ico('coracao', 16)) + ' ' + textoDiario(x);
        // cada visita fica no histórico (Importantes); na tela aparece só a mais nova
        for (const x of ineditos.slice(1).reverse()) guardarAviso(linha(x), undefined, true);
        toast(linha(d) + (ineditos.length > 1 ? ` (+${ineditos.length - 1} no diário)` : ''), undefined, 'importante');
    }

    function marcarDiarioVisto() {
        if (!S || !S.diario.length) return;
        store.set(LS.diarioVisto, String(Math.max(...S.diario.map(quando))));
        avisarDiario();
    }

    /* ---------- Feedback visual ---------- */
    // html: monte com esc() em qualquer texto vindo de jogadores ou do servidor
    /* ---------- Histórico dos avisos ----------
       Todo aviso (toast) fica guardado neste aparelho (os últimos 60) para ler com calma no
       painel Histórico; o contador do menu mostra quantos chegaram desde a última vez. */
    const HIST_MAX = 60;
    let historico = [];
    // (os avisos leves de antes, como "Semente escolhida", saem: o histórico é para o que importa)
    const LEVES = /^(Semente escolhida|Nada pronto ainda|Nenhum canteiro (precisa ser arado|arado livre)|Tudo em ordem por aqui|Escolha um item)/;
    try { historico = JSON.parse(store.get(LS.historico) || '[]').filter((h) => h && h.html && !LEVES.test(h.html)).slice(0, HIST_MAX); } catch { historico = []; }
    let histVisto = Number(store.get(LS.historicoVisto)) || 0;
    const histNovos = () => historico.filter((h) => h.em > histVisto).length;
    // importante = o que aconteceu com você sem você fazer nada: visitas, convites, ajudantes
    function guardarAviso(html, tipo, importante) {
        historico.unshift({ em: Date.now(), html, tipo: tipo || '', ...(importante ? { imp: true } : {}) });
        if (historico.length > HIST_MAX) historico.length = HIST_MAX;
        store.set(LS.historico, JSON.stringify(historico));
        if (painelAtual === 'historico') marcarHistoricoVisto();
        desenharContadorHistorico();
    }
    function marcarHistoricoVisto() {
        histVisto = Date.now();
        store.set(LS.historicoVisto, String(histVisto));
        desenharContadorHistorico();
    }
    function desenharContadorHistorico() {
        const n = histNovos(), c = $('hudHistorico');
        if (c) { c.textContent = n > 99 ? '99+' : n; c.hidden = !n; }
    }
    let abaHistorico = 'importantes';
    function htmlHistorico() {
        if (!historico.length) return '<p class="vazio-msg">Nenhum aviso ainda. Tudo o que aparecer no topo da tela fica guardado aqui.</p>';
        const hoje = new Date().toDateString();
        const imp = historico.filter((h) => h.imp);
        const lista = abaHistorico === 'importantes' ? imp : historico;
        const abas = `<div class="painel-abas" role="tablist">${[['importantes', `Importantes${imp.length ? ` (${imp.length})` : ''}`], ['tudo', 'Tudo']].map(([id, txt]) =>
            `<button type="button" role="tab" data-aba-historico="${id}" class="${abaHistorico === id ? 'ativa' : ''}">${txt}</button>`).join('')}</div>`;
        if (!lista.length) return abas + '<p class="vazio-msg">Nada importante por enquanto. Aqui ficam quem visitou a sua fazenda, quem entrou pelo seu convite e o que os ajudantes fizeram enquanto você estava fora.</p>';
        return abas + '<ul class="historico">' + lista.map((h) => {
            const d = new Date(h.em);
            const quando = d.toDateString() === hoje
                ? d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })
                : d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }) + ' ' + d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
            return `<li class="${h.tipo === 'erro' ? 'erro-t' : h.tipo === 'festa' ? 'festa' : ''}"><time>${quando}</time><span>${h.html}</span></li>`;
        }).join('') + '</ul>';
    }

    // extra: 'leve' = só aparece (não vai para o histórico); 'importante' = vai para a aba Importantes
    function toast(html, tipo, extra) {
        if (tipo === 'erro') som.tocar('erro');
        if (extra !== 'leve') guardarAviso(html, tipo, extra === 'importante');
        const t = document.createElement('div');
        t.className = 'toast' + (tipo === 'erro' ? ' erro-t' : tipo === 'festa' ? ' festa' : '');
        t.innerHTML = html;
        t.title = 'Toque para ver o histórico de avisos';
        t.addEventListener('click', () => { if (S && !painelAtual) abrirPainel('historico'); });
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
        acoesFeitas++;
        clearTimeout(voltaFazendeiro);
        const execucao = fila.then(tarefa).catch(tratarErro).finally(() => {
            pendentes--;
            posicoes.forEach((p) => pendentesPos.delete(p));
            if (!pendentes) voltaFazendeiro = setTimeout(() => cena.voltarParaCasa(), 6000);
        });
        fila = execucao;
        return execucao;
    }

    // Fase 56: colocar, mover e guardar aparecem na hora, mas o servidor confirma um por vez. Cada
    // estado que chega no meio (a resposta do item anterior) é de antes dos que ainda estão na fila:
    // trocar a fazenda por ele fazia o item sumir e voltar. Agora o que ainda não foi confirmado é
    // refeito em cima de cada estado novo (aplicarEstado) até a resposta dele chegar.
    let acoesFeitas = 0;
    const otimistas = new Set();
    function enfileirarOtimista(refazer, chamada) {
        const o = { refazer };
        otimistas.add(o);
        return enfileirar([], async () => {
            let r;
            try { r = await chamada(); } finally { otimistas.delete(o); }
            aplicarEstado(r.estado);
            return r;
        });
    }

    const saiuDoJogo = (e) => e && (e.code === 'token_invalido' || e.code === 'conta_banida');
    function tratarErro(e) {
        if (saiuDoJogo(e)) {
            sair(false);
            mostrarEntrada();
            mostrarErroEntrada(e.message);
            return;
        }
        toast(esc(e.message || 'Algo deu errado.'), 'erro');
    }

    // cuidar dá 1 moeda e o XP segue a regra da planta (inteiro: só sai XP com a planta valendo cheio)
    const textoCuidar = () => `+1 ${ico('xp', 16)} +1 ${ico('moeda', 16)}`;
    const FEEDBACK = {
        arar: () => (S.jogador.nivel <= 5 ? `+1 ${ico('xp', 16)}` : ''),   // arar só dá XP até o nível 5
        plantar: (k) => `−${k.custo} ${ico('moeda', 16)}`,
        erva: (k, c) => textoCuidar(c),
        praga: (k, c) => textoCuidar(c),
        seco: (k, c) => textoCuidar(c),
        arrancar: () => 'arrancou'
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
            if (av === 'pegar_luva' && !confirm(`Esse canteiro tem alarme. Usar 1 luva do Perks para passar? (você tem ${luvas()})`)) return;
            if (av) { cena.irAte(p); executarVisita(av, [p]); }
            return;
        }
        const acao = acaoPara(canteiro(p));
        if (!acao) return abrirMenuCanteiro(p);
        // fase 48: murcha e com diamante: pergunta se salva (todas por 1 💎) antes de arar
        if (info(canteiro(p)).fase === 'murcho' && lojaD() && lojaD().murchas && (S.jogador.diamantes || 0) >= precoMurchas()) return abrirMenuCanteiro(p);
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

    // planta crescendo: o toque abre o menu dela (quanto falta, colher agora com diamante, arrancar)
    let menuCanteiro = null;
    function abrirMenuCanteiro(p) {
        if (!['crescendo', 'murcho'].includes(info(canteiro(p)).fase)) return;
        menuCanteiro = p;
        abrirPainel('canteiro');
    }
    const htmlCanteiroAgora = (i) => `<span class="barra-prog"><i style="width:${Math.round(i.prog * 100)}%"></i></span>
        <p class="canteiro-falta">${Math.floor(i.prog * 100)}% · pronto em <b>${fmtTempo(i.resta)}</b></p>`;
    // a semente escolhida dá para plantar no lugar? (null = não mostra o botão de trocar)
    function sementeParaTrocar(c) {
        const k = culturas[semente];
        return k && k.tipo === 'cultura' && k.id !== c.cultura && podeEscolher(k) && k.nivel_min <= S.jogador.nivel ? k : null;
    }
    function trocarPlanta(p) {
        const c = canteiro(p), nova = validarPlantio();
        if (!c || !nova) return;
        if (!daEstacao(nova) && !naEstufa(c)) return toast(`${esc(nova.nome)} está fora de época: só cresce perto da estufa elétrica.`, 'erro');
        if (S.jogador.moedas < nova.custo) return toast(`Faltam moedas para ${esc(nova.nome.toLowerCase())}.`, 'erro');
        cena.irAte(p);
        som.tocar('cuidar');
        executar('arrancar', [p]).then(() => executar('plantar', [p], nova));
    }

    function executar(acao, posicoes, k) {
        const colhe = acao === 'colher' || acao === 'agora';   // agora = colher na hora com diamante
        return enfileirar(posicoes, async () => {
            const antes = colhe ? Object.fromEntries(posicoes.map((p) => [p, { ...canteiro(p) }])) : null;
            let perdas = '';
            const r = await rpc('fazenda_acao', {
                p_token: token,
                p_acao: acao,
                p_posicoes: posicoes,
                p_cultura: acao === 'plantar' ? k.id : null
            });
            if (colhe) {
                const sol = climaAgora() === 'sol';
                Object.entries(r.colhido).forEach(([pos, qtd], n) => {
                    const c = canteiro(Number(pos));
                    const kc = c && culturas[c.cultura];
                    const ia = antes[pos] && info(antes[pos]);
                    const diam = acao === 'agora' && ia && ia.fase === 'crescendo' ? ` −${precoAgora(ia)} ${ico('diamante', 14)}` : '';
                    const xp = kc ? xpDaColheita(c, kc) : 0;
                    if (kc) flutuar(Number(pos), `+${qtd} ${itemDe(kc, 20)}${sol ? ` (+1 ${ico('sol', 14)})` : ''}${xp ? ` +${xp} ${ico('xp', 16)}` : ''}${diam}`, n * 80);
                });
                perdas = textoPerdas(antes, r.colhido);
            } else if (r.feitos > 0) {
                const feitos = posicoes.length === 1 ? posicoes : posicoes.filter((p) => !mesmoEstado(p, r.estado));
                feitos.forEach((p, n) => {   // (o canteiro ainda é o de antes: dá para saber a planta)
                    const fb = FEEDBACK[acao](k, canteiro(p));
                    if (fb) flutuar(p, fb, n * 60);
                });
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
        if (acao === 'colher' || acao === 'agora') {
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

    // Colher tudo com diamantes: cada planta crescendo pelo preço dela (fase 72: 1 a cada 4 h que
    // faltam) fica pronta na hora e já colhe; as maduras vão junto, de graça. Se os diamantes não dão
    // para todas, vão as que mais demoram (as que não cabem ficam, e as mais baratas ainda entram).
    function planoColherTudo() {
        const lista = S.canteiros.map((c) => ({ c, i: info(c) }));
        const maduros = lista.filter((x) => x.i.fase === 'maduro').map((x) => x.c.posicao);
        const cresc = lista.filter((x) => x.i.fase === 'crescendo').sort((a, b) => b.i.resta - a.i.resta);
        let sobra = S.jogador.diamantes || 0, da = 0, custoTodas = 0;
        const escolhidos = [];
        cresc.forEach((x) => {
            const p = precoAgora(x.i);
            custoTodas += p;
            if (p <= sobra) { sobra -= p; da += p; escolhidos.push(x.c.posicao); }
        });
        return { maduros, crescendo: cresc.map((x) => x.c.posicao), da, custoTodas, escolhidos };
    }
    function htmlColherTudo() {
        const p = planoColherTudo(), d = S.jogador.diamantes || 0, n = p.crescendo.length;
        if (!n) return `<p>Nenhuma planta crescendo agora.</p>
            <div class="rodape-painel"><span></span><button type="button" class="botao creme" data-fechar>Fechar</button></div>`;
        return `<p><b>${n}</b> planta${n === 1 ? '' : 's'} ainda crescendo. Com diamante, cada uma fica pronta na hora (sem erva, praga ou seca) e já vai para o celeiro: ${horasAgora() ? `1 ${ico('diamante', 14)} a cada ${horasAgora()} h que faltam (pelo menos 1 por planta); todas custam <b>${p.custoTodas}</b>` : `1 ${ico('diamante', 14)} por planta`}${p.maduros.length ? `; as ${p.maduros.length} maduras vão junto, de graça` : ''}.</p>
            <p>Você tem <b>${d}</b> ${ico('diamante', 14)}.${p.escolhidos.length && p.escolhidos.length < n ? ` Dá para <b>${p.escolhidos.length}</b>: vão as que mais demoram, e as outras continuam crescendo.` : ''}</p>
            ${p.da ? `<p class="aviso">Quer mesmo colher tudo agora? Vai gastar <b>${p.da} diamante${p.da === 1 ? '' : 's'}</b>.</p>` : `<p class="aviso">Sem diamantes para isso agora.</p>`}
            <div class="rodape-painel">
                <button type="button" class="botao creme" data-fechar>Não, deixa crescer</button>
                ${p.da ? `<button type="button" class="botao verde" data-colher-tudo-agora>Sim, gastar ${ico('diamante', 16)} ${p.da}</button>`
                    : (S.pacotes_diamantes || []).length ? `<button type="button" class="botao verde" data-ir-diamantes>${ico('diamante', 16)} Comprar diamantes</button>` : '<span></span>'}
            </div>`;
    }
    function colherTudoAgora() {
        const p = planoColherTudo();
        fecharPainel();
        if (!p.da) return;
        const todas = [...p.escolhidos, ...p.maduros];
        for (let n = 0; n < todas.length; n += 100) executar('agora', todas.slice(n, n + 100));   // (o servidor aceita até 100 por vez)
    }

    async function acaoEmMassa(tipo) {
        if (!S) return;
        if (tipo === 'agora') return abrirPainel('colherTudo');   // colher tudo com diamantes (pergunta antes)
        if (tipo === 'colher') {
            // colhe os canteiros maduros e coleta os produtos dos animais
            const ps = posicoesOnde((c, i) => i.fase === 'maduro');
            const prontos = (S.animais || []).filter((a) => infoAnimal(a).estado === 'pronto').map((a) => a.id);
            // nada pronto, mas tem planta crescendo e diamante: pergunta se quer colher tudo agora
            if (!ps.length && !prontos.length && planoColherTudo().crescendo.length && (S.jogador.diamantes || 0) > 0) return abrirPainel('colherTudo');
            if (!ps.length && !prontos.length) return toast('Nada pronto ainda.', undefined, 'leve');
            if (ps.length) executar('colher', ps);
            if (prontos.length) {
                const r = await executarAnimal('coletar', prontos);
                if (r && r.coletado) toast(`Coletou ${r.coletado} produto(s) dos animais!`);
            }
        } else if (tipo === 'arar') {
            const ps = posicoesOnde((c, i) => i.fase === 'vazio' || i.fase === 'murcho');
            if (!ps.length) return toast('Nenhum canteiro precisa ser arado.', undefined, 'leve');
            executar('arar', ps);
        } else if (tipo === 'plantar') {
            let ps = posicoesOnde((c, i) => i.fase === 'arado');
            if (!ps.length) return toast('Nenhum canteiro arado livre.', undefined, 'leve');
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
            if (!algum) toast('Tudo em ordem por aqui.', undefined, 'leve');
            else if (total) toast(`${spr(84, 22)} Resolveu ${total} problema(s)!`);
        }
    }

    /* ---------- Visitas aos vizinhos ---------- */
    function mostrarVisita(v) {
        if (constr.ativo) fecharConstrucao();
        visita = v;
        atualizarTerreno();
        atualizarGalinheiro();
        atualizarFeiraMapa();
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
        atualizarFeiraMapa();
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
            const pegando = acao === 'pegar' || acao === 'pegar_luva';   // fase 66: com a luva é pegar também
            if (r.feitos) som.tocar(pegando ? 'colher' : 'cuidar');
            if (acao === 'pegar_luva' && r.feitos) toast(`${itemDe(culturas.luva_perks || { id: 'luva_perks' }, 18)} Passou pelo alarme com ${r.feitos === 1 ? '1 luva' : `${r.feitos} luvas`} do Perks!`);
            Object.entries(r.resultado).forEach(([pos, qtd], n) => {
                const c = canteiro(Number(pos));
                const k = c && culturas[c.cultura];
                flutuar(Number(pos), pegando
                    ? `+${qtd} ${k ? itemDe(k, 20) : ''}`
                    : acao === 'salvar' ? `Salvou! ${qtd ? `+${qtd} ${ico('xp', 16)}` : ''}`
                    : qtd ? `+${qtd} ${ico('xp', 16)}` : `${ico('coracao', 16)}`, n * 70);   // (fase 48: o XP de ajudar vem do servidor)
            });
            aplicarEstado(r.estado);
            if (visita && visita.id === dono) mostrarVisita(r.vizinho);
            if (posicoes.length > 1 && r.feitos) {
                const total = Object.values(r.resultado).reduce((a, b) => a + b, 0);
                toast(pegando
                    ? `${ico('mao', 18)} Pegou ${total} itens de ${r.feitos} canteiro(s)!`
                    : acao === 'salvar'
                    ? `${ico('coracao', 16)} Salvou ${r.feitos} planta(s) murcha(s) do vizinho: +${total} ${ico('xp', 14)}`
                    : `${ico('coracao', 16)} Ajudou em ${r.feitos} canteiro(s) do vizinho: +${total} ${ico('xp', 14)}`);
            } else if (posicoes.length === 1) {
                descrever(posicoes[0]);
            }
            return r;
        });
    }

    // fase 48: o visitante dá ração aos bichos com fome (sai do celeiro do dono; até 10 por dia em cada fazenda)
    function alimentarBichosVizinho(ids) {
        const dono = visita.id;
        return enfileirar([], async () => {
            const r = await rpc('fazenda_vizinho_bicho', { p_token: token, p_vizinho: dono, p_animais: ids });
            if (r.feitos) {
                som.tocar('cuidar');
                toast(`${ico('coracao', 16)} Deu ração a ${r.feitos} bicho(s) do vizinho: +${r.xp} ${ico('xp', 14)}`);
            }
            aplicarEstado(r.estado);
            if (visita && visita.id === dono) mostrarVisita(r.vizinho);
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
        if (tipo === 'ajudar') {   // fase 48: ajudar tudo também salva as murchas do dia (até 2) e dá ração aos bichos
            const salvos = visita.salvos_hoje != null ? visita.salvos_hoje : (visita.pode_salvar ? 0 : 2);
            const vagasSalvar = Math.max(0, 2 - salvos);
            const murchas = vagasSalvar > 0 && visita.pode_salvar !== false ? visita.canteiros.filter((c) => info(c).fase === 'murcho').slice(0, vagasSalvar) : [];
            const famintos = 'bichos_hoje' in visita && visita.bichos_hoje < 10 ? (visita.animais || []).filter((a) => infoAnimal(a).estado === 'fome').map((a) => a.id) : [];
            if (!ps.length && !murchas.length && !famintos.length) return toast('A fazenda do vizinho está em ordem.', undefined, 'leve');
            if (ps.length) executarVisita('ajudar', ps);
            if (murchas.length) executarVisita('salvar', murchas.map((c) => c.posicao));
            if (famintos.length) alimentarBichosVizinho(famintos);
            return;
        }
        // fase 66: os canteiros com alarme, se tiver luva do Perks (pergunta antes de gastar)
        const comAlarme = tipo === 'pegar' ? visita.canteiros.filter((c) => podeLuva(c, info(c))).map((c) => c.posicao) : [];
        const usar = comAlarme.length && confirm(`${comAlarme.length} canteiro(s) com alarme. Usar ${Math.min(comAlarme.length, luvas())} luva(s) do Perks para pegar deles também? (você tem ${luvas()})`)
            ? comAlarme.slice(0, luvas()) : [];
        if (!ps.length && !usar.length) return toast('Nada pra pegar aqui agora.', undefined, 'leve');
        if (ps.length) executarVisita(tipo, ps);
        if (usar.length) executarVisita('pegar_luva', usar);
    }

    // Uma busca de cada vez (com o servidor lento elas se acumulavam) e, com ele falhando, cada vez
    // mais devagar; parada há 5 min, a aba busca de 5 em 5 min (mexeu, volta ao normal na hora).
    let buscando = false, buscasFalhas = 0, mexeuEm = Date.now();
    function intervaloBusca() {
        const base = Date.now() - mexeuEm > 5 * 60000 ? POLL_PARADO_MS : POLL_MS;
        return base * 2 ** Math.min(buscasFalhas, 3);
    }
    ['pointerdown', 'keydown'].forEach((ev) => document.addEventListener(ev, () => { mexeuEm = Date.now(); }, { passive: true }));
    async function recarregar() {
        if (!token || pendentes || buscando) return;
        buscando = true;
        const acoesAntes = acoesFeitas;
        try {
            const estado = await rpc('fazenda_carregar', { p_token: token });
            if (acoesFeitas !== acoesAntes) return;   // fase 56: chegou depois de uma ação: é de antes dela
            aplicarEstado(estado);
            if (visita) mostrarVisita(await rpc('fazenda_visitar', { p_token: token, p_vizinho: visita.id }));
            buscasFalhas = 0;
        } catch (e) {
            if (saiuDoJogo(e)) tratarErro(e);
            else if (e.code === 'vizinho_invalido') voltarCasa();
            else buscasFalhas++;
        } finally {
            buscando = false;
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
                ${[['sementes', 'Sementes'], ['animais', 'Animais'], ['ajudantes', 'Ajudantes'], ['terrenos', 'Terrenos'], ['melhorias', 'Melhorias'], ['baus', 'Baús'], ['diamantes', 'Diamantes']].map(([id, txt]) =>
                    `<button type="button" role="tab" data-aba-loja="${id}" class="${abaLoja === id ? 'ativa' : ''}">${txt}</button>`).join('')}
            </div>`;
            if (abaLoja === 'animais') corpo.innerHTML = abas + htmlLojaAnimais();
            else if (abaLoja === 'terrenos') corpo.innerHTML = abas + htmlLojaTerrenos();
            else if (abaLoja === 'melhorias') corpo.innerHTML = abas + htmlLojaMelhorias();
            else if (abaLoja === 'ajudantes') corpo.innerHTML = abas + htmlLojaAjudantes();
            else if (abaLoja === 'diamantes') corpo.innerHTML = abas + htmlLojaDiamantes();
            else if (abaLoja === 'baus') corpo.innerHTML = abas + htmlLojaBaus();
            else corpo.innerHTML = abas + htmlLojaSementes();
        } else if (nome === 'missoes') {
            el.painelTitulo.innerHTML = `${ico('missao', 26)} Missões do dia`;
            corpo.innerHTML = htmlMissoes();
        } else if (nome === 'celeiro') {
            el.painelTitulo.innerHTML = `${spr(11, 32)} Celeiro`;
            // o que tem no celeiro + a ração dos seus animais (mesmo zerada, para dar para reservar antes)
            const todos = S.culturas.filter((k) => S.celeiro[k.id] > 0 || quemCome(k.id));
            // produtos finais = o que sai das oficinas (salada, queijo, bolo...)
            const finais = new Set(produtosFinais());
            const nFinais = todos.filter((k) => finais.has(k.id) && S.celeiro[k.id] > 0).length;
            const abas = `<div class="painel-abas" role="tablist">
                <button type="button" role="tab" data-aba-celeiro="tudo" class="${abaCeleiro === 'tudo' ? 'ativa' : ''}">Tudo</button>
                <button type="button" role="tab" data-aba-celeiro="finais" class="${abaCeleiro === 'finais' ? 'ativa' : ''}">Produtos finais${nFinais ? ` (${nFinais})` : ''}</button>
            </div>`;
            const soFinais = abaCeleiro === 'finais';
            const itens = soFinais ? todos.filter((k) => finais.has(k.id)) : todos;
            if (!todos.some((k) => S.celeiro[k.id] > 0)) {
                corpo.innerHTML = `<p class="vazio-msg">${spr(76, 48)}<br>Seu celeiro está vazio.<br>Colha algo e volte aqui para vender!</p>`;
            } else if (!itens.some((k) => S.celeiro[k.id] > 0)) {
                corpo.innerHTML = abas + `<p class="vazio-msg">${spr(76, 48)}<br>Nenhum produto final no celeiro.<br>As oficinas transformam a colheita em salada, queijo, bolo, geleia...</p>`;
            } else {
                const bonusVenda = S.jogador.bonus_venda || 0;
                const livreDe = (k) => Math.max(0, naCeleiro(k.id) - reservaDe(k.id));
                const vende = itens.filter((k) => k.tipo !== 'raro');   // fase 60: material raro só vende na feira
                const total = Math.floor(vende.reduce((a, k) => a + livreDe(k) * k.venda, 0) * (100 + bonusVenda) / 100);
                const xpTotal = Math.floor(vende.reduce((a, k) => a + livreDe(k) * k.venda * xpVendaDe(k), 0) / XP_VENDA);
                corpo.innerHTML = abas + '<div class="lista">' + itens.map((k) => {
                    const livre = livreDe(k), come = quemCome(k.id);
                    if (k.tipo === 'raro') return htmlRaroCeleiro(k);
                    return `<div class="item">
                        <span class="ico">${spr(A.cultura(k.id).item, 44)}</span>
                        <span>
                            <span class="nome">${esc(k.nome)} × ${naCeleiro(k.id)}</span>
                            <span class="det"><span>${moeda(k.venda)} cada</span><span>${!reservaDe(k.id) ? `total ${moeda(livre * k.venda)}` : livre ? `vende ${livre}: ${moeda(livre * k.venda)}` : 'tudo guardado'}</span></span>
                            ${k.tipo === 'cultura' ? `<span class="conta-semente">1 semente (${moeda(k.custo)}) rende ${k.rendimento} = ${moeda(k.rendimento * k.venda)}</span>` : ''}
                            ${come ? htmlReserva(k, come) : ''}
                            ${!come && ehPecaPier(k.id) && !(S.pier && S.pier.pronto) ? htmlGuardarPier(k) : ''}
                        </span>
                        <button type="button" class="botao pequeno verde" data-vender="${esc(k.id)}"${livre ? '' : ' disabled'}>${livre || !naCeleiro(k.id) ? 'Vender' : 'Guardado'}</button>
                    </div>`;
                }).join('') + `</div>
                    <div class="rodape-painel">
                        <span class="preco">Valor total: ${ico('moeda', 16)} ${total}${bonusVenda ? ` <small class="bonus-txt">(+${bonusVenda}% de bônus)</small>` : ''}${xpTotal ? ` · +${xpTotal} ${ico('xp', 14)}` : ''}</span>
                        <button type="button" class="botao verde" data-vender="${soFinais ? 'finais' : '*'}"${total ? '' : ' disabled'}>${soFinais ? 'Vender produtos finais' : 'Vender tudo'}</button>
                    </div>`;
            }
        } else if (nome === 'feira') {
            el.painelTitulo.innerHTML = `${ico('moeda', 26)} Feira`;
            corpo.innerHTML = htmlFeira();
            if (abaFeira === 'comprar' && !soAtualizar) carregarFeira();
        } else if (nome === 'admin') {
            el.painelTitulo.innerHTML = `${ico('escudo', 26)} Admin`;
            corpo.innerHTML = htmlAdmin();
            if (!soAtualizar) carregarAdmin();
        } else if (nome === 'metas') {
            el.painelTitulo.innerHTML = `${ico('medalha', 26)} Metas de nível`;
            corpo.innerHTML = htmlMetas();
        } else if (nome === 'colherTudo') {
            el.painelTitulo.innerHTML = `${ico('diamante', 26)} Colher tudo agora?`;
            corpo.innerHTML = htmlColherTudo();
        } else if (nome === 'canteiro') {
            const c = canteiro(menuCanteiro), i = info(c);
            const diam = S.jogador.diamantes || 0;
            el.painelTitulo.innerHTML = i.k ? `${itemDe(i.k, 32)} ${esc(i.k.nome)}` : 'Canteiro';
            if (i.fase === 'crescendo') {
                const troca = sementeParaTrocar(c), pa = precoAgora(i);
                corpo.innerHTML = `
                    <div data-canteiro-agora>${htmlCanteiroAgora(i)}</div>
                    <div class="menu-canteiro">
                        <button type="button" class="botao verde" data-canteiro="agora"${diam < pa ? ' disabled' : ''}>${ico('diamante', 18)} Colher agora · ${pa} diamante${pa === 1 ? '' : 's'}</button>
                        ${planoColherTudo().crescendo.length > 1 ? `<button type="button" class="botao creme" data-colher-tudo${diam < 1 ? ' disabled' : ''}>${ico('diamante', 18)} Colher todas as ${planoColherTudo().crescendo.length} crescendo</button>` : ''}
                        <p class="aviso">Fica pronta na hora, sem erva, praga ou seca, e já vai para o celeiro${horasAgora() ? `: 1 ${ico('diamante', 14)} a cada ${horasAgora()} h que faltam` : ''}. Você tem <b>${diam}</b> ${ico('diamante', 14)} e ganha 5 a cada nível.</p>
                        ${diam < 1 && (S.pacotes_diamantes || []).length ? `<button type="button" class="botao creme" data-ir-diamantes>${ico('diamante', 18)} Comprar diamantes</button>` : ''}
                        ${troca ? `<button type="button" class="botao creme" data-canteiro="trocar">Arrancar e plantar ${itemDe(troca, 18)} ${esc(troca.nome.toLowerCase())} (${moeda(troca.custo)})</button>` : ''}
                        <button type="button" class="botao creme" data-canteiro="arrancar">Arrancar (a planta se perde)</button>
                    </div>`;
            } else if (i.fase === 'murcho') {
                const n = S.canteiros.filter((x) => info(x).fase === 'murcho').length;
                const pq = S.murchas && S.murchas.canteiros && S.murchas.canteiros[String(c.posicao)];   // fase 66: o motivo
                corpo.innerHTML = `${pq ? `<p class="aviso"><b>Por que murchou:</b> ${textoMurcha(pq.motivo, pq.detalhe)} ${DICA_MURCHA[pq.motivo] || ''}</p>` : ''}
                    <p>${esc(i.k.nome)} murchou${n > 1 ? ` (e mais ${n - 1} murcha${n > 2 ? 's' : ''})` : ''}. Com ${precoMurchas(n)} ${ico('diamante', 14)} ${n > 1 ? `as ${n} voltam` : 'ela volta'} madura${n > 1 ? 's' : ''}, sem erva, praga ou seca, pronta${n > 1 ? 's' : ''} para colher${lojaD() && lojaD().murchas && lojaD().murchas.por ? ` (1 ${ico('diamante', 14)} a cada ${lojaD().murchas.por} plantas)` : ''}.</p>
                    <div class="menu-canteiro">
                        ${botaoDiamante('murchas', precoMurchas(n), n > 1 ? `Salvar as ${n} murchas` : 'Salvar a murcha')}
                        <button type="button" class="botao creme" data-canteiro="arar">Arar (a planta se perde)</button>
                    </div>`;
            } else if (i.fase === 'maduro') {
                corpo.innerHTML = `<p>${esc(i.k.nome)} pronto para colher!</p>
                    <div class="rodape-painel"><span></span><button type="button" class="botao verde" data-canteiro="colher">Colher</button></div>`;
            } else {
                corpo.innerHTML = '<p>Esse canteiro não tem nada crescendo agora.</p>';
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
                <h3 class="secao-titulo">Evento da semana</h3>
                ${htmlTrofeus(S.evento && S.evento.trofeus)}
                <h3 class="secao-titulo">Seus números</h3>
                ${htmlEstatisticas(S.estatisticas)}`}
                <h3 class="secao-titulo">Código de recuperação</h3>
                ${codigo ? `<div class="codigo-box"><code>${esc(codigo)}</code><button type="button" class="botao pequeno creme" data-copiar>Copiar</button></div>` : '<p class="aviso">O código não está salvo neste aparelho. Se você anotou, ele continua valendo.</p>'}
                <p class="aviso">Guarde esse código: ${GOOGLE_CLIENT_ID ? 'com ele, ou com a conta Google aqui embaixo, você abre' : 'é o único jeito de abrir'} sua fazenda em outro aparelho ou se o navegador for limpo.</p>
                ${htmlGoogle()}
                ${htmlInstalar()}
                ${boasVindas ? '' : htmlAvisos()}
                ${boasVindas ? '' : htmlConvite()}
                ${boasVindas ? `<p class="aviso">${ico('ajuda', 14)} Ficou com dúvida? No menu tem <b>Ajuda</b>, com tudo o que dá para fazer na fazenda.</p>` : ''}
                <p class="aviso"><a href="privacidade.html" target="_blank" rel="noopener">Política de privacidade</a>: o que a fazenda guarda e como funcionam os anúncios.</p>
                <div class="rodape-painel">
                    ${boasVindas
                        ? '<span></span><button type="button" class="botao verde" data-fechar>Começar a jogar</button>'
                        : `<button type="button" class="botao creme" data-painel-ir="ajuda">${ico('ajuda', 16)} Como jogar</button>
                    <button type="button" class="botao creme" data-painel-ir="som">${ico('som', 16)} Som e Música</button>
                    <a class="botao creme" href="indexversao2.html">Voltar ao portfólio</a>
                    <button type="button" class="botao vermelho" data-sair>Sair desta fazenda</button>`}
                </div>`;
            botaoGoogle(corpo.querySelector('[data-google-botao]'), 'ligar');
        } else if (nome === 'pier') {   // fase 61
            el.painelTitulo.innerHTML = `${itemDe(culturas.ancora || { id: 'ancora' }, 30)} Píer`;
            corpo.innerHTML = htmlPier();
        } else if (nome === 'evento') {   // fase 63: o evento da semana
            el.painelTitulo.innerHTML = `${itemDe(culturas.trofeu_ouro || { id: 'trofeu_ouro' }, 30)} Evento da semana`;
            corpo.innerHTML = htmlEvento();
            if (!soAtualizar) carregarEvento();
        } else if (nome === 'chat') {   // fase 67: o chat global
            const txt = ($('chatTexto') || {}).value || '';
            el.painelTitulo.innerHTML = `${ico('chat', 26)} Chat`;
            corpo.innerHTML = htmlChat();
            if ($('chatTexto')) $('chatTexto').value = txt;
            desenharChat(true);
            if (!soAtualizar) { carregarChat(true); agendarChat(); }
        } else if (nome === 'calendario') {   // fase 69: o calendário de resgate diário
            el.painelTitulo.innerHTML = `${ico('calendario', 26)} Calendário`;
            corpo.innerHTML = htmlCalendario();
        } else if (nome === 'novidades') {   // fase 67: o que mudou no jogo
            const lista = novidadesVer || NOVIDADES;
            novidadesVer = null;
            store.set(LS.novidades, NOVIDADES[0].id);
            el.painelTitulo.innerHTML = `${ico('brilho', 26)} Novidades`;
            corpo.innerHTML = lista.map((n) => `<h3 class="secao-titulo">${esc(n.titulo)} <small class="qtd">${esc(n.data)}</small></h3>
                <ul class="ajuda">${n.itens.map((t) => `<li>${t}</li>`).join('')}</ul>`).join('')
                + `<div class="rodape-painel">${lista === NOVIDADES ? '<span></span>' : '<button type="button" class="botao creme" data-painel-ir="novidades">Ver todas</button>'}<button type="button" class="botao verde" data-fechar>Entendi</button></div>`;
        } else if (nome === 'murchas') {   // fase 66: o relatório
            const total = murchasNovas.reduce((a, m) => a + m.qtd, 0);
            el.painelTitulo.innerHTML = `${ico('sino', 28)} Plantas murchas`;
            corpo.innerHTML = `<p class="fala">Enquanto você estava fora, ${total === 1 ? '1 planta murchou' : `${total} plantas murcharam`} sem ninguém colher. O porquê:</p>
                ${htmlMurchas(murchasNovas)}
                <div class="rodape-painel"><span></span><button type="button" class="botao verde" data-fechar>Entendi</button></div>`;
        } else if (nome === 'eventoPremio') {
            el.painelTitulo.innerHTML = `${itemDe(culturas.trofeu_ouro || { id: 'trofeu_ouro' }, 30)} Você ganhou!`;
            corpo.innerHTML = htmlEventoPremio();
        } else if (nome === 'mar') {   // fase 62: as melhorias do alto-mar
            el.painelTitulo.innerHTML = `${itemDe(culturas.marlim || { id: 'marlim' }, 30)} Alto-mar`;
            if (!soAtualizar) pinturaBarco = null;
            corpo.innerHTML = htmlMarMelhorias();
            const cv = corpo.querySelector('[data-barco-previa]');   // fase 65: a prévia da pintura
            if (cv && window.FazendaMar && window.FazendaMar.previa) {
                window.FazendaMar.previa(cv, { nivel: (S.mar && S.mar.barco && S.mar.barco.valor) || 1, visual: pinturaBarco || visualBarco(), pecas: pecasMar() });
            }
        } else if (nome === 'ajudante') {   // fase 59
            const t = tipoAjudante(ajudanteAberto), h = meuAjudante(ajudanteAberto);
            if (!t || !h) { fecharPainel(); return; }
            el.painelTitulo.innerHTML = `${retratoAjudante(t.id, 32)} ${esc(t.nome)}`;
            corpo.innerHTML = htmlAjudante(t, h);
        } else if (nome === 'som') {
            el.painelTitulo.innerHTML = `${ico('som', 26)} Som e Música`;
            corpo.innerHTML = `
                <div class="painel-som">
                    <div class="som-bloco">
                        <div class="som-linha-titulo">
                            <b>Música de Fundo</b>
                            <span id="txtVolMusica">${som.volMusica}%</span>
                        </div>
                        <p class="det">Trilha sonora relaxante da sua fazenda.</p>
                        <div class="som-controle-range">
                            <input type="range" id="rngVolMusica" min="0" max="100" value="${som.volMusica}" aria-label="Volume da música">
                        </div>
                    </div>

                    <div class="som-bloco">
                        <div class="som-linha-titulo">
                            <b>Efeitos Sonoros (SFX)</b>
                            <span id="txtVolEfeitos">${som.volEfeitos}%</span>
                        </div>
                        <p class="det">Sons 8-bit de colheita, arar, plantar e moedas.</p>
                        <div class="som-controle-range">
                            <input type="range" id="rngVolEfeitos" min="0" max="100" value="${som.volEfeitos}" aria-label="Volume dos efeitos">
                        </div>
                    </div>

                    <div class="som-bloco">
                        <b>Escolher Música</b>
                        <div class="som-faixas">
                            ${som.faixas.map((f, idx) => `
                                <button type="button" class="botao pequeno ${som.faixaAtual === idx ? 'verde' : 'creme'}" data-faixa="${idx}">
                                    ${som.faixaAtual === idx ? '▶ ' : ''}${esc(f.nome)}
                                </button>
                            `).join('')}
                        </div>
                    </div>

                    <div class="som-bloco som-linha-mudo">
                        <button type="button" class="botao ${som.mudo ? 'vermelho' : 'verde'}" data-som-silenciar>
                            ${ico(som.mudo ? 'mudo' : 'som', 20)} ${som.mudo ? 'Áudio Mudo (Ativar Som)' : 'Silenciar Tudo'}
                        </button>
                    </div>
                </div>
                <div class="rodape-painel">
                    <span></span>
                    <button type="button" class="botao verde" data-fechar>Pronto</button>
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
        } else if (nome === 'bau') {
            const b = bauAberto && (S.construcoes || []).find((k) => k.x === bauAberto.x && k.y === bauAberto.y && k.tipo === 'bau');
            el.painelTitulo.innerHTML = `${A.htmlItem('bau', 32)} Baú`;
            corpo.innerHTML = b ? htmlBau(b) : '<p class="vazio-msg">Esse baú não está mais aqui.</p>';
        } else if (nome === 'historico') {
            el.painelTitulo.innerHTML = `${ico('sino', 26)} Histórico de avisos`;
            corpo.innerHTML = htmlHistorico() + (historico.length ? `<div class="rodape-painel">
                    <span class="aviso">Os últimos ${HIST_MAX} avisos ficam guardados neste aparelho.</span>
                    <button type="button" class="botao creme" data-historico-limpar>Limpar</button>
                </div>` : '');
            marcarHistoricoVisto();
        } else if (nome === 'ajuda') {
            el.painelTitulo.innerHTML = `${ico('ajuda', 26)} Como jogar`;
            corpo.innerHTML = `
                <p><button type="button" class="botao pequeno creme" data-painel-ir="novidades">${ico('brilho', 14)} Novidades do jogo</button></p>
                <ul class="ajuda">
                    <li>Toque num canteiro e ele faz a ação certa: <b>arar</b>, <b>plantar</b>, <b>cuidar</b> ou <b>colher</b>.</li>
                    <li><b>XP das plantas:</b> colher dá o XP de cada planta (aparece na loja), em qualquer nível. O mesmo canteiro dá XP de colheita no máximo uma vez a cada 8 minutos: a alface, que cresce em 5, dá XP de 2 em 2 colheitas. O que os ajudantes, robôs e baús colhem dá metade do XP. Cuidar dá +1 XP. Arar dá XP só até o nível 5.</li>
                    <li>No <b>Calendário</b> (no menu) tem um prêmio por dia, por 28 dias: moedas, XP, café dos ajudantes, XP em dobro e diamantes nos dias 7, 14, 21 e 28. Faltou um dia? Não perde nada: pega o seguinte. A <b>trilha dourada</b>, liberada com diamantes, dá um prêmio a mais todo dia e, no dia 28, o Fazendeiro de ouro.</li>
                    <li>No <b>Chat</b> (no menu) você conversa com todos os jogadores; as mensagens somem em 1 hora. Do nível 5 em diante dá para escrever e <b>pedir um item</b> (quantos e quanto paga cada): quem tiver toca em <b>Vender</b> e o lote vai para a barraca dele, separado para você por 2 horas (depois vira anúncio normal). Sem palavrão e sem link; dá para silenciar alguém.</li>
                    <li>Na <b>Feira</b> (no menu) os jogadores vendem uns para os outros: anuncie um lote do celeiro com o seu preço (entre metade e o triplo da venda normal) e compre de outros o que falta para as suas receitas. Quem vende recebe tudo; o anúncio dura 2 dias. Toda fazenda já tem uma <b>barraca na feira</b>, na clareira da mata à esquerda do celeiro: cada barraca dá 2 anúncios e mostra em cima o que você vende. Do nível 5 em diante dá para comprar mais 3 no painel da Feira.</li>
                    <li>Em <b>Metas</b> (no menu) está tudo o que o seu nível libera: construir cada oficina, máquina e cercado, ter cada bicho, contratar cada ajudante, comprar os terrenos e ocupar os canteiros. Com tudo em dia, <b>+50% de XP</b> até o próximo nível (do nível 20 em diante, a <b>fazenda completa</b>: <b>+75%</b>, e cada colheita sua dá +2 XP, o de arar e plantar); o que ficou dos níveis de trás também aparece lá.</li>
                    <li>Na loja, aba <b>Melhorias</b> (do nível 23 em diante): compras caras que valem para sempre. Adubo premium (plantas mais rápidas), pomar fértil (árvores mais rápidas) e mais pés de fruta.</li>
                    <li>Toque numa planta crescendo para abrir o menu dela: quanto falta, <b>colher agora</b> com diamante (1 ${ico('diamante', 14)} a cada 4 h que faltam, pelo menos 1; fica pronta na hora e vai para o celeiro), <b>arrancar</b>, ou arrancar e plantar a semente escolhida. Você começa com 10 diamantes e ganha 5 a cada nível. Em <b>Loja → Diamantes</b> eles também compram <b>XP em dobro</b> por 1 hora, um <b>pacote de XP</b> (até 3 por dia), o <b>café dos ajudantes</b> (em dobro por 2 horas), <b>energia</b> cheia na hora, uma <b>oficina terminando agora</b> e <b>personagens especiais</b> para o avatar.</li>
                    <li>As plantas crescem em tempo real, mesmo com a página fechada.</li>
                    <li>Aparecem ${ico('erva', 14)} ervas, ${ico('praga', 14)} pragas e ${ico('seco', 12)} seca: cada problema deixado custa 1 item na colheita.</li>
                    <li>Depois de madura, a planta <b>murcha</b> se ficar tempo demais sem colher.</li>
                    <li>Toque no <b>celeiro</b> para vender a colheita, compre sementes melhores e suba de nível para ganhar canteiros. <b>Vender produtos também dá XP</b>: 1 a cada 25 moedas (o que sai das oficinas, dos bichos, do lago e do pomar). A planta vendida não dá XP: ela já deu na colheita.</li>
                    <li>Os canteiros ficam onde você quiser: <b>Construir → Plantação</b> para colocar, <b>Mover</b> para mudar de lugar. Lado a lado eles viram fileiras.</li>
                    <li>Na loja, aba <b>Terrenos</b>, compre pedaços da mata em volta para a fazenda crescer (e ganhar mais canteiros). São 7 terrenos, e os últimos são grandes (o 7º é o Litoral, com a praia).</li>
                    <li>Todo item do Construir faz alguma coisa: evita seca, praga ou erva, adianta o crescimento, dá itens e XP extras, protege dos vizinhos ou aumenta a <b>beleza</b> (bônus nas vendas). Toque num item para ver o que ele faz.</li>
                    <li>Na loja, aba <b>Ajudantes</b>: contrate pessoas que aram, plantam, cuidam, colhem e tratam dos animais sozinhas (12 tarefas por hora no nível 1, 30 no 2, 90 no 3, 150 no 4 e 240 no 5; o 4 libera no nível 35 e o 5 no 42). Os cuidadores de bicho (Dona Cida, Nina, Bento, Pedrinho, Lia e Tonho) deixam a espécie deles mais rápida: −10% no tempo por nível, somando com o fardo de feno. O <b>Seu Zé</b> também aduba os canteiros crescendo: +1 item na colheita; o <b>Juca</b> colhe também o pomar. A <b>Dona Lurdes</b> (operária, nível 12) cuida das oficinas: leva o que ficou pronto para o celeiro e enche o estoque delas; o <b>Faísca</b> (eletricista, nível 17) faz tudo o que é elétrico gastar menos. Ajudante não gasta energia. Com a fazenda aberta, dá para ver cada um indo até onde trabalhou.</li>
                    <li>Em <b>Construir → Oficinas</b> tem uma oficina para cada matéria-prima: padaria, queijaria, conservas, prensa de óleo, peixaria, defumadouro, casa de sucos, sorveteria, ateliê de penas, cozinha de moqueca, empório (que usa o óleo da prensa), adega e outras. Toque nela para abrir o painel: guarde ingredientes no <b>estoque</b> (até 10 receitas) e ela trabalha sozinha, uma receita atrás da outra. O painel mostra quanto valem os ingredientes, quanto vale o produto e o <b>lucro</b>. Quando aparecer o balão, toque para pegar.</li>
                    <li>Fruta só dá no pé: em <b>Construir → Pomar</b> tem amoreira, laranjeira, limoeiro, goiabeira e, do nível 26 ao 29, mangueira, abacateiro, cacaueiro e jabuticabeira. Cada árvore dá frutas sozinha: quando aparecer o balão, toque nela para colher. Cada fruta tem <b>1 pé</b>, e mais 1 a cada 2 terrenos comprados (até 4 de cada; com a melhoria <b>Mais pés de fruta</b>, até 6): quanto mais terreno, maior o pomar. Para colher sozinho: um <b>baú</b> encostado na árvore, com energia, colhe e guarda (e manda pela rede de canos); ou o <b>Juca</b> (colhedor) colhe as que não têm baú e leva para o celeiro.</li>
                    <li>Em <b>Construir → Máquinas</b>: irrigador, pulverizador e robô capinador evitam seca, pragas e ervas por perto; o alarme protege dos vizinhos; trator e colheitadeira ajudam na fazenda toda.</li>
                    <li>Na loja tem <b>animais</b> (até 5 de cada; cada um sai 50% mais caro que o anterior). Cada bicho mora no <b>cercado</b> dele: construa o cercado da espécie em <b>Construir → Bichos</b> antes de comprar (quem já tinha bicho sem cercado ganha o primeiro de graça, e os bichos ficam no galinheiro ou no pasto antigo até ele ficar pronto). Cercado com bicho dentro não dá para desmanchar, só mudar de lugar. Dê ração (sai do celeiro) e colete ovos, leite e lã. No celeiro, <b>Reservar</b> guarda a ração deles para não ir junto no "Vender tudo".</li>
                    <li>No botão <b>Construir</b> você coloca cercas, caminhos, árvores, flores e objetos onde quiser. Toque em <b>Pronto</b> para fechar.</li>
                    <li>Toque num item já colocado para ver o que ele faz; o <b>alcance</b> dele (irrigador, alarme, estufa...) aparece marcado no chão. <b>Segure o dedo 3 segundos</b> num item ou canteiro para pegar e levar para outro lugar.</li>
                    <li>A semana tem as 4 <b>estações</b> (42 horas cada), e cada uma muda a cara da fazenda (pétalas na primavera, grama quente no verão, folhas caindo no outono, neve no inverno) e tem uma semente só dela: morango, melancia, abóbora e repolho. O <b>clima</b> muda várias vezes por dia: sol dá +1 na colheita, chuva rega tudo, onda de calor seca mais, nublado não traz problema novo e ventania espalha pragas. Toque no clima, lá em cima, para ver até quando ele vai.</li>
                    <li>O jogo tem o próprio <b>dia e noite</b>: eles se revezam a cada 2 horas (12 horas de dia e 12 de noite em cada dia de verdade). De noite o mapa escurece, as janelas, os lampiões e as oficinas acendem, aparecem vaga-lumes, e o painel solar não gera energia. Toque no clima para ver quando amanhece.</li>
                    <li>O <b>baú</b> guarda em si (até 200 itens) o que recolhe sozinho, com energia, do que estiver encostado nele: o bloco de canteiros, um cercado (coleta e dá ração), uma árvore do pomar e o cesto do lago (1,6 ⚡ cada). Toque no baú para ver o que tem.</li>
                    <li>No nível 16 chegam os <b>canos de vidro</b> (Construir → Energia, 25 cada). Canos encostados formam uma <b>rede</b>, e tudo o que encosta num cano dela (baús, oficinas, o celeiro, a fábrica automática) trabalha junto: a rede <b>enche sozinha o estoque das oficinas</b> (até 10 receitas, 1,6 ⚡ cada) com o que tem nos baús e no celeiro da rede, dividindo entre todas; o produto vai para outra oficina que usa ele (o óleo da prensa vai para o empório), para o celeiro ou para um baú; e o que nenhuma oficina usa sai do baú para o celeiro (1,6 ⚡ por viagem). Para o celeiro fazer parte, o cano tem que encostar no próprio prédio do celeiro. Nada anda sem estar ligado. Como saber se está funcionando: a <b>luz no meio do cano</b> fica verde pulsando quando a rede liga duas coisas ou mais (vermelha piscando = sem energia), a oficina na rede ganha um selinho de cano no balão, o baú mostra uma barrinha de quanto está cheio, e cada item aparece passando pelo cano quando viaja.</li>
                    <li>Do nível 16 em diante vem a <b>energia</b> ${ico('raio', 14)}: painel solar, turbina, gerador a biomassa e reator enchem as baterias, e as máquinas elétricas (estufa, triturador, fábrica automática, robô, aspersor, baús e a rede de canos) trabalham sozinhas gastando energia. O <b>eletricista</b> (ajudante, nível 17) faz tudo gastar menos, e dá para encher as baterias com diamantes. Toque no ${ico('raio', 12)} lá em cima (ou no botão abaixo) para ver o que cada uma faz.</li>
                    ${ANUNCIO.ligado || ehLocal ? `<li>Quando aparecer o botão <b>+30 min</b>, assista a um anúncio até o fim e tudo o que está em andamento (plantas, animais, oficinas, ajudantes e energia) adianta 30 minutos. Cada anúncio também dá 1 ${ico('diamante', 14)} diamante.</li>` : ''}
                    <li>No Perfil (ou em Vizinhos) tem o seu <b>link de convite</b>: quem criar uma fazenda por ele ganha moedas, e você também.</li>
                    <li>No <b>Vale do sudeste</b> (terreno 3) tem um lago: o pescador <b>Bira</b> tira um peixe a cada 30 minutos, até 16 no cesto. Toque no lago para pegar. Quanto mais raro, mais vale, e o lendário <b>Peixe do Velho Chico</b> sai em 1% das vezes (2% com a estátua do nível 30).</li>
                    <li>A cada 3 horas chega uma <b>visita na porteira</b>, do lado da casa (do nível 3 em diante): o feirante, a doceira e o caminhoneiro compram algo da fazenda pagando bem mais que o celeiro, e a mascate vende adubo. Toque nela para conversar. Bem de vez em quando (1 em cada 100 visitas) vem o <b>mercador</b>, que troca um material raro do píer por frutos fora de época.</li>
                    <li>No nível 31 chega o <b>Litoral</b> (Loja → Terrenos): areia para construir e plantar e o mar. Na areia fica o lugar do <b>píer</b>: toque nele para ver a receita (9 peças difíceis e 100 mil moedas). Peça que falta dá para comprar com diamantes. Guarde o peixe do Velho Chico para o píer, no celeiro, para ele não ir no "Vender tudo".</li>
                    <li>Com o píer pronto, toque no <b>barco</b> para ir para o <b>alto-mar</b>: toque na água para lançar a linha, espere a boia <b>afundar de verdade</b> (às vezes o peixe só belisca) e toque de novo na hora para fisgar. Cada lançada usa 1 peixe do <b>cardume</b>, que enche sozinho com o tempo. Em <b>Melhorar</b>: barco maior (cardume maior e peixes novos), vara melhor (mais tempo para fisgar e peixes maiores) e o marinheiro <b>Seu Nonato</b>, que pesca sozinho por até 8 horas (toque no barquinho dele para recolher). 1 em cada 200 peixes vem com uma <b>pérola negra</b>.</li>
                    <li>Bem de vez em quando (1 em cada 30 visitas) aparece o <b>Perks</b>, o 1º do ranking: ele pede muita planta fácil (tipo 1000 milhos) e paga com 4 <b>luvas do Perks</b>. Visitando um vizinho, cada luva pega 1 canteiro mesmo com alarme (só gasta no canteiro protegido). E quando uma planta murcha sem ninguém colher, o jogo diz por quê: sem colhedor, o Juca dormindo, a fazenda fechada mais de 8 h ou canteiro demais para o nível dele.</li>
                    <li>Em <b>Melhorar</b>, no alto-mar, também dá para <b>tunar o barco</b> com peças que pedem moedas e materiais raros (os do mercador, a pérola negra e o marlim-azul): <b>motor</b> (o cardume enche mais rápido), <b>sonar</b> (mais peixe grande e mais pérola), <b>porão</b> (às vezes 2 peixes numa fisgada), <b>rede de arrasto</b> (o marinheiro pesca mais rápido) e o <b>kit de expedição</b>, que deixa o barco oceânico pronto para as ilhas do nível 46. A <b>pintura</b> muda a cor do casco, da faixa e a bandeira.</li>
                    <li>Toda semana tem o <b>evento</b> (no menu): de sexta às 22h até a sexta seguinte às 22h, os 3 primeiros de cada categoria ganham diamantes (30, 18 e 10) e cada um tem 50% de chance de levar um item raro: o 1º, o item que só sai do evento; o 2º e o 3º, um material do píer (no ranking, os troféus de prata e bronze). As categorias: XP ganho na semana (troféus de ouro, prata e bronze), níveis subidos, moedas ganhas, vendas e compras na barraca da feira e amigos convidados que chegaram ao nível 10 (o 1º pode levar o <b>leme dourado</b>, a peça do píer). O XP comprado com diamantes não conta no ranking nem em níveis, e na barraca uma mesma pessoa do outro lado vale no máximo 25% do total. Os troféus e as conquistas do evento ficam no perfil.</li>
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
            let novos = [], canteiros = 0, moedas = 0, diamantes = 0;
            for (let n = de + 1; n <= ate; n++) {
                novos = novos.concat(liberaNoNivel(n));
                const x = extrasDoNivel(n);
                canteiros += x.canteiros; moedas += x.moedas; diamantes += x.diamantes;
            }
            const proximo = ate < NIVEL_MAX ? liberaNoNivel(ate + 1) : [];
            corpo.innerHTML = `
                <div class="nivel-festa"><span class="nivel-numero">${ate}</span><p>Sua fazenda subiu de nível!</p></div>
                <div class="nivel-ganhos">
                    ${moedas ? `<span class="ganho">${ico('moeda', 18)} Presente: <b>+${moedas}</b> moedas</span>` : ''}
                    ${diamantes ? `<span class="ganho">${ico('diamante', 18)} <b>+${diamantes}</b> diamantes (toque numa planta crescendo para colher na hora)</span>` : ''}
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
                <p class="aviso">Colher, cuidar dos canteiros, os animais, as missões e vender produtos dão XP. Cada nível traz um presente de moedas e 5 diamantes. Do nível 10 em diante cada nível pede mais XP que o anterior (do 16 ao 25, 35% a mais a cada nível; do 25 em diante, 7%), e do 11 em diante o presente dobra. O 45 é o último nível.</p>
                <ol class="caminho">${Array.from({ length: NIVEL_MAX }, (_, i) => i + 1).map((n) => {
                    const x = extrasDoNivel(n);
                    const lista = liberaNoNivel(n);
                    const estado = n < j.nivel ? 'feito' : n === j.nivel ? 'atual' : 'futuro';
                    return `<li class="degrau ${estado}">
                        <span class="degrau-nv">${n < j.nivel ? ico('check', 14) : n}</span>
                        <div class="chips">${chipsHtml(lista)}
                            ${x.canteiros ? `<span class="chip extra">${A.htmlItem('canteiro', 18)}<span>+${x.canteiros} canteiros</span></span>` : ''}
                            ${x.moedas ? `<span class="chip extra">${ico('moeda', 14)}<span>+${x.moedas}</span></span>` : ''}
                            ${x.diamantes ? `<span class="chip extra">${ico('diamante', 14)}<span>+${x.diamantes}</span></span>` : ''}
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
                <h3 class="secao-titulo">Evento da semana</h3>
                ${htmlTrofeus(p.trofeus)}
                <h3 class="secao-titulo">Números</h3>
                ${htmlEstatisticas(p.estatisticas)}
                ${S.jogador.admin ? `<p><button type="button" class="botao pequeno creme" data-admin-perfil="${esc(visita.id)}" data-apelido="${esc(visita.apelido)}">${ico('escudo', 14)} Banir esta fazenda</button></p>` : ''}`;
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
                <span><b>${esc(t.nome)}</b><small>${esc(t.descricao)}${ok ? '' : ` · prêmio ${moeda(t.recompensa)}${t.diamantes ? ` e ${t.diamantes} ${ico('diamante', 12)}` : ''}`}</small></span>
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
        return '<div class="lista">' + S.culturas.filter((k) => k.tipo === 'cultura').map((k) => {   // (fase 60: nem produto nem raro)
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
                    ${travado ? '' : `<span class="det"><span${temCercado(t.id) ? '' : ' class="txt"'}>${temCercado(t.id) ? `${A.htmlItem(cercadoDe(t.id), 16)} tem cercado próprio` : `<b>precisa do cercado primeiro</b>: ${esc(((tipoItem(cercadoDe(t.id)) || {}).nome || 'cercado').toLowerCase())} (${cercadoGratis(tipoItem(cercadoDe(t.id))) ? 'o seu sai de graça' : moeda((tipoItem(cercadoDe(t.id)) || {}).custo || 0)}) em Construir → Bichos`}</span>${tem && !cheio ? `<span>o próximo sai 50% mais caro</span>` : ''}</span>`}
                </span>
                ${travado ? `<span class="preco">Nível ${t.nivel_min}</span>`
                    : cheio ? '<span class="preco">Completo</span>'
                    : !temCercado(t.id) ? `<button type="button" class="botao pequeno creme" data-construir-cercado="${esc(cercadoDe(t.id))}">Construir<br>o cercado</button>`
                    : `<button type="button" class="botao pequeno verde" data-comprar="animal:${esc(t.id)}">${ico('moeda', 14)} ${precoAnimal(t, tem).toLocaleString('pt-BR')}</button>`}
            </div>`;
        }).join('') + '</div>' + htmlRacoes() + '<p class="aviso">Toque no animal com fome para dar a ração (sai do seu celeiro) e volte para coletar o produto. Cada bicho mora no cercado dele: construa o cercado (Construir → Bichos) antes de comprar. Até 5 de cada; cada um sai 50% mais caro que o anterior.</p>';
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
            const estrelas = [1, 2, 3, 4, 5].map((n) => (n <= nivel ? '★' : '☆')).join('');
            const ritmo = efeitoAjudante(t, nivel || 1) + (nivel && nivel < NIVEL_MAX_AJUDANTE ? ` (nível ${nivel + 1}: ${efeitoAjudante(t, nivel + 1).split(' ')[0]})` : '');
            const precisa = nivel && EVOLUIR_NIVEL[nivel + 1] > S.jogador.nivel ? EVOLUIR_NIVEL[nivel + 1] : 0;   // fase 74
            const ver = h ? `<button type="button" class="botao pequeno creme" data-ajudante-ver="${esc(t.id)}">Ver</button>` : '';   // fase 59
            const botao = nivel >= NIVEL_MAX_AJUDANTE ? '<span class="preco">Nível máximo</span>'
                : precisa ? `<span class="preco">Nível ${nivel + 1} no ${precisa}</span>`
                : `<button type="button" class="botao pequeno verde" data-contratar="${esc(t.id)}">${nivel ? 'Evoluir' : 'Contratar'}<br>${ico('moeda', 14)} ${custoAjudante(t, nivel)}</button>`;
            const acao = travado ? `<span class="preco">Nível ${t.nivel_min}</span>` : ver ? `<span class="admin-botoes">${botao}${ver}</span>` : botao;
            return `<div class="item${travado ? ' travada' : ''}">
                <span class="ico">${travado ? ico('cadeado', 28) : retratoAjudante(t.id, 44)}</span>
                <span>
                    <span class="nome">${esc(t.nome)} <small class="qtd">${esc(t.papel)}</small></span>
                    <span class="det"><span>${esc(t.descricao)}</span></span>
                    <span class="det"><span class="estrelas">${nivel ? estrelas : ''}</span><span>${ritmo}</span></span>
                </span>
                ${acao}
            </div>`;
        }).join('') + '</div><p class="aviso">Ajudantes trabalham sozinhos, até com a fazenda fechada (guardam até 8 h de trabalho), e não gastam energia elétrica: são a mão de obra de graça ao lado das máquinas. Eles têm a própria energia: a barra cheia dura 8 h de trabalho; acabou, descansam 2 h numa cama (cada casinha dá camas) ou 4 h na sombra. Toque num ajudante (ou em Ver) para ver o que ele fez e mandar descansar. O que eles colhem dá metade do XP. Quem cuida de animais precisa de ração no celeiro.</p>'
            + (lojaD() && (S.ajudantes || []).length ? `<p class="det">${ativoAte(S.jogador.cafe_ate) ? `<b>Café servido:</b> trabalhando em dobro até ${hora(S.jogador.cafe_ate)}. ` : `Café dos ajudantes: todos em dobro por ${lojaD().cafe.horas} horas. `}${botaoDiamante('cafe', lojaD().cafe.preco, ativoAte(S.jogador.cafe_ate) ? `+${lojaD().cafe.horas} horas` : 'Servir café')}</p>` : '');
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
                    <span class="det"><span>${z.w}×${z.h} quadrados</span><span>+${z.canteiros || 6} canteiros</span>${z.lago ? '<span>com lago e pescador!</span>' : ''}${z.mar ? '<span>praia e mar: o lugar do píer!</span>' : ''}</span>
                </span>
                ${comprado ? '<span class="preco">Comprado</span>'
                    : !proximo ? `<span class="preco">Depois do ${z.n - 1}</span>`
                    : S.jogador.nivel < z.nivel ? `<span class="preco">Nível ${z.nivel}</span>`
                    : `<button type="button" class="botao pequeno verde" data-comprar="terreno:${z.n}">${ico('moeda', 14)} ${z.custo}</button>`}
            </div>`;
        }).join('') + '</div><p class="aviso">Cada terreno abre um pedaço da mata em volta: mais espaço para canteiros, cercados, máquinas e enfeites, e mais canteiros no seu limite. Os três últimos são grandes. Também dá para tocar na placa no mapa.</p>';
    }

    /* ---------- Baús da sorte (fase 73): para gastar as moedas que sobram ----------
       O servidor sorteia (fazenda_abrir_bau_sorte); vem de tudo, mas o que é bom vem pouco. */
    const ICONE_BAU = { madeira: 1143, prata: 1144, ouro: 1145 };
    let ultimoBau = null;   // o que saiu no último baú (aparece em cima da lista)
    function textoPremioBau(p) {
        if (!p) return '';
        if (p.tipo === 'moedas' || p.tipo === 'grande') return `${ico('moeda', 18)} <b>${p.moedas.toLocaleString('pt-BR')}</b> moedas${p.tipo === 'grande' ? ': o prêmio grande!' : ''}`;
        if (p.tipo === 'diamantes') return `${ico('diamante', 18)} <b>${p.diamantes}</b> diamantes`;
        const k = culturas[p.item] || { id: p.item, nome: p.item };
        return `${itemDe(k, 22)} <b>${p.qtd}</b> ${esc(k.nome.toLowerCase())}${p.tipo === 'raro' ? ': item raro!' : ''}`;
    }
    function htmlLojaBaus() {
        const b = S.baus_sorte;
        if (!b) return '<p class="vazio-msg">Os baús chegam em breve.</p>';
        return (ultimoBau ? `<p class="aviso">Saiu do ${esc(ultimoBau.nome.toLowerCase())}: ${textoPremioBau(ultimoBau.premio)}.</p>` : '')
            + '<div class="lista">' + Object.entries(b).sort((x, y) => x[1].preco - y[1].preco).map(([id, t]) => {
                const travado = S.jogador.nivel < t.nivel;
                return `<div class="item${travado ? ' travada' : ''}">
                    <span class="ico">${travado ? ico('cadeado', 28) : spr(ICONE_BAU[id] || 1143, 44)}</span>
                    <span><span class="nome">${esc(t.nome)}</span>
                        <span class="det"><span>De tudo um pouco; raro é difícil</span></span></span>
                    ${travado ? `<span class="preco">Nível ${t.nivel}</span>`
                        : `<button type="button" class="botao pequeno verde" data-bau-sorte="${id}"${S.jogador.moedas < t.preco ? ' disabled' : ''}>Abrir<br>${ico('moeda', 14)} ${t.preco.toLocaleString('pt-BR')}</button>`}
                </div>`;
            }).join('') + `</div><p class="aviso">Um jeito de gastar as moedas que sobram, sem limite. É sorte: quase sempre volta menos do que custou, e só de vez em quando vem algo bem bom. O que vem dos baús não conta nas moedas do evento, e vendido no celeiro dá as moedas, mas não o XP.</p>`;
    }

    /* ---------- Melhorias (fase 57): compras caras e permanentes para o fim de jogo ----------
       O catálogo vem do servidor (estado.melhorias_tipos); cada uma tem níveis, comprados em ordem. */
    function htmlLojaMelhorias() {
        const tipos = (S.melhorias_tipos || []).filter((m) => !m.mar);   // fase 62: as do mar ficam na tela do alto-mar
        if (!tipos.length) return '<p class="vazio-msg">As melhorias chegam em breve.</p>';
        const fmt = (v) => v.toLocaleString('pt-BR');
        return '<div class="lista">' + tipos.map((m) => {
            const tem = melhoriaNivel(m.id), prox = m.niveis[tem];
            const travado = prox && S.jogador.nivel < prox.nivel;
            const cadeado = travado && !tem;   // já tem um nível: o cartão fica normal, só o próximo espera
            const passos = m.niveis.map((k, i) => `<span${i < tem ? ' class="feito"' : ''}>${i < tem ? '✓' : ''}${m.id === 'pes' ? '+' + k.valor + ' pé' + (k.valor > 1 ? 's' : '') : Math.round(k.valor * 100) + '%'} (nível ${k.nivel})</span>`).join('');
            return `<div class="item${cadeado ? ' travada' : ''}">
                <span class="ico">${cadeado ? ico('cadeado', 28) : A.htmlItem(m.id === 'adubo' ? 'canteiro' : 'laranjeira', 40)}</span>
                <span>
                    <span class="nome">${esc(m.nome)}${tem ? ` · ${tem}/${m.niveis.length}` : ''}</span>
                    <span class="det"><span class="txt">${esc(m.descricao)}</span></span>
                    <span class="det">${passos}</span>
                </span>
                ${!prox ? '<span class="preco">Completa</span>'
                    : travado ? `<span class="preco">${tem ? 'Próximo no n' : 'N'}ível ${prox.nivel}</span>`
                    : `<button type="button" class="botao pequeno verde" data-comprar="melhoria:${esc(m.id)}">${ico('moeda', 14)} ${fmt(prox.custo)}</button>`}
            </div>`;
        }).join('') + '</div><p class="aviso">Melhorias valem para sempre e para a fazenda toda. Cada uma tem níveis, comprados um depois do outro.</p>';
    }

    /* ---------- Diamantes à venda (Mercado Pago) ----------
       A Edge Function fazenda-diamantes cria a compra e devolve a página de pagamento; o
       Mercado Pago traz a pessoa de volta em fazenda.html?compra=ID e avisa a função, que
       credita os diamantes. Os pacotes e preços vêm do servidor (estado.pacotes_diamantes). */
    const reais = (v) => 'R$ ' + Number(v).toFixed(2).replace('.', ',');
    /* ---------- O que fazer com os diamantes (fase 43; preços vêm de estado.loja_diamantes) ---------- */
    const lojaD = () => (S && S.loja_diamantes) || null;
    const ativoAte = (iso) => (iso && Date.parse(iso) > agora() ? iso : null);
    // encher a energia: 1 diamante a cada 150 ⚡ que faltam (null = sem nada de energia; 0 = cheia)
    function precoEnergiaDiamantes() {
        const l = lojaD();
        if (!l || !temEletrico()) return null;
        const falta = (S.energia.capacidade || 50) - cargaAgora();
        return falta < 1 ? 0 : Math.max(1, Math.ceil(falta / l.energia.por));
    }
    const precoOficinaDiamantes = (o) => Math.max(1, Math.ceil(o.falta / 3600000) * (lojaD() ? lojaD().oficina.por_hora : 1));
    // fase 72: colher agora, 1 diamante a cada 4 h que faltam; salvar murchas, 1 a cada 25 plantas
    const horasAgora = () => (lojaD() && lojaD().agora && lojaD().agora.horas) || 0;
    const precoAgora = (i) => (horasAgora() ? Math.max(1, Math.ceil(i.resta / (horasAgora() * 3600000))) : 1);
    const nMurchas = () => S.canteiros.filter((x) => info(x).fase === 'murcho').length;
    const precoMurchas = (n = nMurchas()) => {
        const m = lojaD() && lojaD().murchas;
        return !m ? 1 : m.por ? m.preco * Math.ceil(n / m.por) : m.preco;
    };
    // botão de gastar diamantes (o primeiro toque pede para confirmar)
    const botaoDiamante = (item, preco, texto, xy = '') => `<button type="button" class="botao pequeno verde" data-usar-diamante="${item}" data-preco="${preco}"${xy}${(S.jogador.diamantes || 0) >= preco ? '' : ' disabled'}>${texto}<br>${ico('diamante', 14)} ${preco}</button>`;
    function htmlUsarDiamantes() {
        const l = lojaD();
        if (!l) return '';
        const j = S.jogador;
        const xp2 = ativoAte(j.xp2_ate), cafe = ativoAte(j.cafe_ate);
        const pacoteXp = Math.ceil(((j.xp_proximo || 0) - (j.xp_nivel || 0)) * l.xp.pct / 100);
        const hoje = j.xp_compras_hoje || 0;
        const pe = precoEnergiaDiamantes();
        const info = (txt) => `<span class="preco">${txt}</span>`;
        const linha = (icone, nome, det, acao) => `<div class="item"><span class="ico">${icone}</span>
            <span><span class="nome">${nome}</span><span class="det"><span class="txt">${det}</span></span></span>${acao || '<span></span>'}</div>`;
        return `<h3 class="secao-titulo">Usar diamantes</h3><div class="lista">
            ${linha(ico('xp', 36), 'XP em dobro', xp2 ? `<b>Ligado até ${hora(xp2)}</b>: todo XP vem dobrado. Comprar de novo soma mais ${l.xp2.horas} hora.`
                : `Por ${l.xp2.horas} hora, todo XP que você ganha (colher, bichos, vender, missões) vem dobrado.`, botaoDiamante('xp2', l.xp2.preco, xp2 ? '+1 hora' : 'Ligar'))}
            ${linha(ico('xp', 36), `Pacote de XP: +${pacoteXp}`, `${l.xp.pct}% do seu nível, na hora. Até ${l.xp.por_dia} por dia (hoje: ${hoje}).`,
                j.nivel >= NIVEL_MAX ? info('Nível máximo') : hoje >= l.xp.por_dia ? info('Amanhã tem mais') : botaoDiamante('xp', l.xp.preco, 'Pegar'))}
            ${linha(retratoAjudante('colhedor', 36), 'Café dos ajudantes', cafe ? `<b>Em dobro até ${hora(cafe)}</b>. Comprar de novo soma mais ${l.cafe.horas} horas.`
                : `Por ${l.cafe.horas} horas, todos os seus ajudantes trabalham em dobro.`, (S.ajudantes || []).length ? botaoDiamante('cafe', l.cafe.preco, cafe ? `+${l.cafe.horas} horas` : 'Servir') : info('Sem ajudantes'))}
            ${linha(ico('raio', 36), 'Encher a energia', `Baterias cheias na hora: 1 ${ico('diamante', 12)} a cada ${l.energia.por} ⚡ que faltam.`,
                pe == null ? info('Sem energia ainda') : pe === 0 ? info('Já está cheia') : botaoDiamante('energia', pe, 'Encher'))}
            ${linha(A.htmlItem('prensa_oleo', 36), 'Oficina na hora', `Na oficina trabalhando, toque em <b>Terminar agora</b>: ${l.oficina.por_hora} ${ico('diamante', 12)} por hora que falta.`)}
            ${l.murchas ? linha(ico('diamante', 36), 'Salvar as plantas murchas', `Todas as murchas voltam maduras, sem erva, praga ou seca: ${l.murchas.por ? `${l.murchas.preco} ${ico('diamante', 12)} a cada ${l.murchas.por} plantas` : `${l.murchas.preco} ${ico('diamante', 12)} por todas`}.`,
                nMurchas() ? botaoDiamante('murchas', precoMurchas(), 'Salvar') : info('Nada murcho')) : ''}
            ${linha(itemDe(culturas.tomate || { id: 'tomate' }, 36), 'Colher agora', `Toque numa planta crescendo e ela fica pronta na hora: ${horasAgora() ? `1 ${ico('diamante', 12)} a cada ${horasAgora()} h que faltam (pelo menos 1)` : `1 ${ico('diamante', 12)} por planta`}. Ou colha todas de uma vez.`,
                planoColherTudo().crescendo.length ? `<button type="button" class="botao pequeno verde" data-colher-tudo${j.diamantes > 0 ? '' : ' disabled'}>Colher todas<br>${ico('diamante', 14)} ${planoColherTudo().custoTodas}</button>` : info('Nada crescendo'))}
            ${linha(A.htmlAvatar({ tipo: 'fantasma' }, 36), 'Personagens especiais', 'Soldado, bárbaro, guarda, feiticeiro, fantasma, ciclope, diabinho e morcego: só com diamantes.',
                '<button type="button" class="botao pequeno creme" data-avatar-editar>Ver</button>')}
        </div>`;
    }
    /* ---------- A feira entre jogadores (fase 50) ----------
       Anunciar tira o lote do celeiro na hora; outro jogador compra o lote inteiro e você recebe na
       hora, tudo (fase 51: sem taxa). Preço por unidade entre metade e o triplo do preço de venda; o
       anúncio vale 2 dias (vencido, volta para o celeiro). Quantos anúncios: 2 por barraca; as
       barracas ficam numa pracinha na mata (A.MAPA.feira): 1 de saída, compra até 4. As ofertas vêm
       de fazenda_feira_lista. */
    let abaFeira = 'comprar', feiraDados = null, feiraFiltro = null, feiraItem = null;
    const regrasFeira = () => (S && S.feira && S.feira.regras)
        || { taxa: 0, min: 0.5, max: 3, horas: 48, por_barraca: 2, barracas_max: 4, barraca_nivel: 5, barraca_precos: [800, 1600, 2400], compras_dia: 40, qtd_max: 99 };
    const limiteFeira = () => (S.feira && S.feira.limite) || 2;
    const barracas = () => (S.feira && S.feira.barracas) || 1;
    // comprar mais uma barraca na feira (até 4)
    function dicaBarraca() {
        const r = regrasFeira(), n = barracas(), max = r.barracas_max || 4;
        if (n >= max) return '';
        const preco = (r.barraca_precos || [])[n - 1] || 0, nivel = r.barraca_nivel || 5;
        return S.jogador.nivel < nivel
            ? `<p class="det"><span class="txt">${A.htmlItem('barraca', 16)} No nível ${nivel} dá para comprar mais barracas na feira: cada uma dá mais ${r.por_barraca || 2} anúncios.</span></p>`
            : `<p class="det"><span class="txt">${A.htmlItem('barraca', 16)} Você tem ${n} de ${max} barracas na feira. Cada barraca nova dá mais ${r.por_barraca || 2} anúncios e mostra o que você vende.</span></p>
               <button type="button" class="botao pequeno verde" data-feira-barraca${S.jogador.moedas >= preco ? '' : ' disabled'}>Comprar barraca (${ico('moeda', 14)} ${preco})</button>`;
    }
    // fase 51: as barracas na pracinha da mata (na visita, só a primeira, sem o que está à venda)
    function atualizarFeiraMapa() {
        const f = !visita && S && S.feira;
        cena.definirFeira({ barracas: f ? f.barracas || 1 : 1, vende: f ? (f.meus || []).map((a) => A.cultura(a.item).item) : [], vagas: !!f });
    }
    // a peça do píer que também vende no celeiro (o peixe do Velho Chico) tem preço de peça na feira
    const precoPecaFeira = (id) => (S && S.pier && S.pier.receita && S.pier.receita.feira && S.pier.receita.feira[id]) || 0;
    const faixaFeira = (k) => {
        if (k.tipo === 'raro') return [k.venda, k.venda * 3];   // fase 60: igual a fazenda_feira_faixa
        if (precoPecaFeira(k.id)) return [precoPecaFeira(k.id), precoPecaFeira(k.id) * 3];   // fase 61 (a tela não sabia: só o servidor)
        const r = regrasFeira(); return [Math.max(1, Math.floor(k.venda * r.min)), Math.max(1, Math.ceil(k.venda * r.max))];
    };
    // o que dá para anunciar: o que tem no celeiro (fora a ração reservada) e vale alguma coisa
    const livreFeira = (id) => Math.max(0, naCeleiro(id) - reservaDe(id));
    const itensFeira = () => Object.keys(S.celeiro || {}).filter((id) => culturas[id] && culturas[id].venda > 0 && livreFeira(id) > 0)
        .sort((a, b) => culturas[a].nome.localeCompare(culturas[b].nome));
    function carregarFeira() {
        enfileirar([], async () => {
            feiraDados = await rpc('fazenda_feira_lista', { p_token: token, p_item: feiraFiltro });
            if (painelAtual === 'feira') abrirPainel('feira', true);
        });
    }
    function htmlFeira() {
        const r = regrasFeira();
        const abas = `<div class="painel-abas" role="tablist">${[['comprar', 'Comprar'], ['vender', 'Vender'], ['meus', `Meus anúncios (${(S.feira && S.feira.meus.length) || 0}/${limiteFeira()})`]].map(([id, txt]) =>
            `<button type="button" role="tab" data-aba-feira="${id}" class="${abaFeira === id ? 'ativa' : ''}">${txt}</button>`).join('')}</div>`;
        const nomeK = (id) => esc((culturas[id] || { nome: id }).nome);
        const resta = (ate) => fmtTempo(Date.parse(ate) - agora());
        let corpo = '';
        if (abaFeira === 'comprar') {
            if (!feiraDados) corpo = '<p class="vazio-msg">Abrindo a feira…</p>';
            else {
                const filtros = feiraDados.itens.length ? `<div class="feira-filtros">${[null, ...feiraDados.itens].map((id) =>
                    `<button type="button" class="botao pequeno ${feiraFiltro === id ? 'verde' : 'creme'}" data-feira-filtro="${id || ''}">${id ? `${itemDe(culturas[id] || { id }, 16)} ${nomeK(id)}` : 'Tudo'}</button>`).join('')}</div>` : '';
                corpo = filtros + (feiraDados.ofertas.length ? '<div class="lista">' + feiraDados.ofertas.map((o) => {
                    const total = o.qtd * o.preco, k = culturas[o.item] || { id: o.item, nome: o.item, venda: 0 };
                    return `<div class="item"><span class="ico">${itemDe(k, 36)}</span>
                        <span><span class="nome">${o.qtd} × ${nomeK(o.item)}</span>
                            <span class="det"><span>${moeda(o.preco)} cada (na venda normal, ${k.venda})</span><span>de ${A.htmlAvatar(o.avatar, 16)} ${esc(o.vendedor)}</span><span>acaba em ${resta(o.ate)}</span>${o.reservado_ate ? `<span class="feira-reservado">separado pra você até ${hora(o.reservado_ate)}</span>` : ''}</span></span>
                        <button type="button" class="botao pequeno verde" data-feira-comprar="${o.id}"${S.jogador.moedas >= total ? '' : ' disabled'}>Comprar<br>${ico('moeda', 14)} ${total}</button></div>`;
                }).join('') + '</div>' : '<p class="vazio-msg">Ninguém está vendendo isso agora. Volte daqui a pouco!</p>');
            }
        } else if (abaFeira === 'vender') {
            const itens = itensFeira();
            if (!itens.length) corpo = '<p class="vazio-msg">O seu celeiro não tem nada para anunciar agora (a ração reservada fica).</p>';
            else if (((S.feira && S.feira.meus) || []).length >= limiteFeira()) {
                corpo = `<p class="vazio-msg">Os seus ${limiteFeira() === 1 ? 'lugar' : `${limiteFeira()} lugares`} na feira ${limiteFeira() === 1 ? 'está ocupado' : 'estão ocupados'}. Espere vender ou cancele um em Meus anúncios.</p>` + dicaBarraca();
            } else {
                if (!itens.includes(feiraItem)) feiraItem = itens[0];
                const k = culturas[feiraItem], [min, max] = faixaFeira(k), livre = livreFeira(feiraItem);
                corpo = `<div class="feira-form">
                    <label>Item <select data-feira-item>${itens.map((id) => `<option value="${esc(id)}"${id === feiraItem ? ' selected' : ''}>${nomeK(id)} (${livreFeira(id)})</option>`).join('')}</select></label>
                    <label>Quantidade <input type="number" id="feiraQtd" min="1" max="${Math.min(livre, r.qtd_max)}" value="${Math.min(livre, 10)}"></label>
                    <label>Preço de cada <input type="number" id="feiraPreco" min="${min}" max="${max}" value="${Math.min(max, Math.max(min, Math.round(k.venda * 1.2)))}"></label>
                    <p class="det"><span class="txt">${itemDe(k, 16)} ${ehRaro(k) ? `Item raro: não vende no celeiro. Na feira, entre ${numero(min)} e ${numero(max)}, e você recebe tudo.`
                        : precoPecaFeira(k.id) ? `Na venda normal, ${moeda(k.venda)} cada. Na feira tem preço de peça do píer: entre ${numero(min)} e ${numero(max)}, e você recebe tudo.`
                        : `Na venda normal, ${moeda(k.venda)} cada. Na feira, entre ${numero(min)} e ${numero(max)}, e você recebe tudo.`}</span></p>
                    <button type="button" class="botao verde" data-feira-anunciar>Anunciar</button>
                </div>`;
            }
        } else {
            const meus = (S.feira && S.feira.meus) || [], vendidos = (S.feira && S.feira.vendidos) || [];
            corpo = meus.length ? '<div class="lista">' + meus.map((a) => `<div class="item"><span class="ico">${itemDe(culturas[a.item] || { id: a.item }, 36)}</span>
                <span><span class="nome">${a.qtd} × ${nomeK(a.item)}</span><span class="det"><span>${moeda(a.preco)} cada · total ${a.qtd * a.preco}</span><span>acaba em ${resta(a.ate)}</span>${a.para ? `<span class="feira-reservado">separado para ${esc(a.para)} até ${hora(a.reservado_ate)}</span>` : ''}</span></span>
                <button type="button" class="botao pequeno creme" data-feira-cancelar="${a.id}">Cancelar</button></div>`).join('') + '</div>'
                : '<p class="vazio-msg">Nenhum anúncio aberto. Na aba Vender você coloca um lote do celeiro à venda.</p>';
            corpo += dicaBarraca();
            // fase 51: quem comprou (os últimos 7 dias)
            if (vendidos.length) corpo += '<h3 class="secao-titulo">Vendidos</h3><div class="lista">' + vendidos.map((v) => `<div class="item"><span class="ico">${itemDe(culturas[v.item] || { id: v.item }, 28)}</span>
                <span><span class="nome"><b>${esc(v.comprador || 'Alguém')}</b> comprou ${v.qtd} × ${nomeK(v.item)}</span><span class="det"><span>+${moeda(v.total)}</span><span>há ${fmtTempo(agora() - Date.parse(v.em))}</span></span></span></div>`).join('') + '</div>';
        }
        const lim = limiteFeira();
        return abas + corpo + `<p class="aviso">Na feira você compra de outros jogadores o que falta para as suas receitas e vende o que sobra, recebendo tudo. Preço entre metade e o triplo da venda normal (os itens raros vão do mínimo deles, de 50 mil para cima, até o triplo; o peixe do Velho Chico, peça do píer, de 50 a 150 mil); o anúncio dura ${r.horas / 24} dias (vencido, volta para o celeiro). O que você compra aqui serve para receitas, entregas e missões; revendido ao jogo, dá as moedas mas não o XP. Você pode ter ${lim} anúncios: ${r.por_barraca || 2} por barraca (as suas ficam na mata, à esquerda do celeiro).</p>`;
    }
    /* ---------- Calendário de resgate diário (fase 69) ----------
       28 dias: um resgate por dia (de Brasília); faltou, não perde (pega o seguinte). A trilha dourada
       (com diamantes) dá um prêmio a mais por dia e, no dia 28, o Fazendeiro de ouro. */
    const calendarioPronto = () => !!(S && S.calendario && S.calendario.pode);
    const hojeBrasilia = () => new Date(agora() - 3 * 3600e3).toISOString().slice(0, 10);
    let calendarioChecado = false;
    function checarCalendario(estado) {
        if (calendarioChecado || !estado.calendario) return;
        calendarioChecado = true;
        if (!estado.calendario.pode || store.get(LS.calendarioVisto) === hojeBrasilia()) return;
        store.set(LS.calendarioVisto, hojeBrasilia());   // abre sozinho uma vez por dia
        if (!painelAtual) abrirPainel('calendario');
        else paineisDepois.push('calendario');
    }
    const tempoCal = (m) => (m % 60 ? `${m} min` : `${m / 60} h`);
    // um prêmio da tabela (moedas por nível): a figura, o texto curto (na casinha) e o longo
    function premioCal(p) {
        const n = (S && S.jogador.nivel) || 1;
        if ((p.tipo === 'xp' || p.tipo === 'xp2') && n >= NIVEL_MAX) p = { tipo: 'moedas', qtd: 50 };   // igual ao servidor
        const k = p.item ? culturas[p.item] || { id: p.item, nome: p.item } : null;
        switch (p.tipo) {
            case 'moedas': { const m = p.qtd * Math.max(Math.floor(presenteNivel(n) / 10), 1);   // fase 70: um décimo do presente do nível
                return { html: ico('moeda', 16), curto: numero(m), longo: `${numero(m)} moedas` }; }
            case 'diamantes': return { html: ico('diamante', 16), curto: String(p.qtd), longo: `${p.qtd} diamantes` };
            case 'xp': return { html: ico('xp', 16), curto: `${p.qtd}%`, longo: `${p.qtd}% do XP do nível` };
            case 'xp2': return { html: ico('xp', 16), curto: `×2 ${tempoCal(p.qtd)}`, longo: `XP em dobro por ${tempoCal(p.qtd)}` };
            case 'cafe': return { html: itemDe(culturas.cafe || { id: 'cafe' }, 16), curto: tempoCal(p.qtd), longo: `café dos ajudantes por ${tempoCal(p.qtd)}` };
            case 'item': return { html: itemDe(k, 16), curto: String(p.qtd), longo: `${p.qtd} ${nomeQtd(k, p.qtd)}` };
            case 'avatar': return { html: A.htmlAvatar({ tipo: p.avatar }, 18), curto: 'novo!', longo: `o ${(A.AVATAR_TIPOS[p.avatar] || {}).nome || 'personagem'} (exclusivo)` };
            default: return { html: '', curto: '', longo: '' };
        }
    }
    // o que o servidor entregou de fato (moedas já vezes o nível)
    function textoGanho(g) {
        if (!g) return '';
        const k = g.item ? culturas[g.item] || { id: g.item, nome: g.item } : null;
        return g.tipo === 'moedas' ? `${ico('moeda', 14)} ${numero(g.qtd)}`
            : g.tipo === 'diamantes' ? `${ico('diamante', 14)} ${g.qtd}`
            : g.tipo === 'xp' ? `+${numero(g.qtd)} ${ico('xp', 14)}`
            : g.tipo === 'xp2' ? `XP em dobro por ${tempoCal(g.qtd)}`
            : g.tipo === 'cafe' ? `café dos ajudantes por ${tempoCal(g.qtd)}`
            : g.tipo === 'item' ? `${g.qtd} ${itemDe(k, 14)} ${esc(nomeQtd(k, g.qtd))}`
            : g.tipo === 'avatar' ? `${A.htmlAvatar({ tipo: g.avatar }, 16)} ${esc((A.AVATAR_TIPOS[g.avatar] || {}).nome || 'personagem novo')}!` : '';
    }
    function htmlCalendario() {
        const c = S.calendario;
        if (!c) return '<p class="vazio-msg">O calendário chega com a próxima atualização do servidor.</p>';
        const total = c.regras.dias, proximo = c.dia + 1;
        const casa = (dia) => {
            const p = c.premios[dia - 1], g = p.g.map(premioCal), d = p.d.map(premioCal);
            const estado = dia <= c.dia ? 'feito' : dia === proximo && c.pode ? 'hoje' : 'futuro';
            const titulo = `Dia ${dia}: ${g.map((x) => x.longo).join(' + ')}. Dourada: ${d.map((x) => x.longo).join(' + ')}`;
            return `<div class="cal-dia ${estado}${dia % 7 === 0 ? ' grande' : ''}" title="${esc(titulo)}" data-cal-dia="${dia}">
                <span class="cal-num">${dia}</span>
                <span class="cal-g">${g.map((x) => x.html).join('')}<span class="cal-q">${g.map((x) => esc(x.curto)).join(' ')}</span></span>
                <span class="cal-d${c.dourado ? '' : ' trancado'}">${d.map((x) => x.html).join('')}</span>
            </div>`;
        };
        const meiaNoite = () => { const b = new Date(agora() - 3 * 3600e3); return Date.UTC(b.getUTCFullYear(), b.getUTCMonth(), b.getUTCDate() + 1) + 3 * 3600e3 - agora(); };
        const acao = c.pode
            ? `<button type="button" class="botao verde" data-cal-resgatar>Pegar o prêmio do dia ${proximo}</button>`
            : `<p class="det">Prêmio de hoje já pego. O dia ${proximo > total ? 1 : proximo} libera em ${fmtTempo(meiaNoite())}.</p>`;
        const preco = c.regras.dourado, tem = (S.jogador.diamantes || 0) >= preco;
        const dourado = c.dourado
            ? `<p class="cal-dourado-ok">${ico('brilho', 14)} Trilha dourada liberada neste ciclo: você ganha os dois prêmios todo dia.</p>`
            : `<div class="cal-dourado"><span><b>Trilha dourada</b>: um prêmio a mais todo dia (XP em dobro, café dos ajudantes, pacotes de XP, raros e 50 ${ico('diamante', 12)} de volta) e, no dia 28, o <b>Fazendeiro de ouro</b>, que só sai aqui.${c.dia ? ` Liberando agora, já ganha os prêmios dourados dos ${c.dia} dias que você pegou.` : ''}</span>
                <button type="button" class="botao ${tem ? 'verde' : 'creme'}" data-cal-dourado>${tem ? `Liberar por ${ico('diamante', 14)} ${preco}` : `Faltam ${ico('diamante', 14)} ${preco - (S.jogador.diamantes || 0)}: comprar diamantes`}</button></div>`;
        return `<p class="det">Ciclo ${c.ciclo} · ${c.dia} de ${total} dias pegos. Um prêmio por dia; se faltar um dia, não perde: pega o seguinte.</p>
            <div class="cal-grade">${Array.from({ length: total }, (_, k) => casa(k + 1)).join('')}</div>
            <p class="det">Em cima, o grátis; embaixo, o da trilha dourada. Toque numa casinha para ver o prêmio.</p>
            <div class="rodape-painel"><span></span>${acao}</div>
            ${dourado}`;
    }

    /* ---------- Chat (fase 67) ----------
       As mensagens da última hora (fazenda_chat). Com o painel aberto, busca só as novas de 5 em 5 s
       (direto no rpc, sem a fila das ações), e só redesenha a lista (o que você digita fica). */
    const chat = { msgs: [], ultimo: 0, regras: null, pode: false, admin: false, atendidos: {} };
    let chatTimer = null, chatBuscando = false, chatEnviando = false, chatPedindo = false, chatPedidoItem = null, chatAssinatura = '';
    const silenciados = () => { try { return JSON.parse(store.get(LS.chatSilencio) || '[]'); } catch { return []; } };
    function chatNaoLido() { return painelAtual !== 'chat' && !!(S && S.chat && S.chat.ultimo) && S.chat.ultimo > (Number(store.get(LS.chatVisto)) || 0); }
    function marcarChatLido() {
        const ult = Math.max(chat.ultimo || 0, (S && S.chat && S.chat.ultimo) || 0);
        if (ult > (Number(store.get(LS.chatVisto)) || 0)) store.set(LS.chatVisto, String(ult));
        const b = $('hudChat');
        if (b) b.hidden = true;
        atualizarAlertaMenu();
    }
    async function carregarChat(completo) {
        if (chatBuscando) return;
        chatBuscando = true;
        try {
            const tudo = completo || !chat.msgs.length;
            const r = await rpc('fazenda_chat', { p_token: token, p_depois: tudo ? null : chat.ultimo });
            const primeira = !chat.regras;
            Object.assign(chat, { regras: r.regras, pode: r.pode_escrever, admin: r.admin, atendidos: r.atendidos || {} });
            if (tudo) chat.msgs = r.mensagens || [];
            else {
                const fora = new Set(r.apagadas || []);
                chat.msgs = chat.msgs.filter((m) => !fora.has(m.id)).concat(r.mensagens || []);
            }
            const desde = agora() - (chat.regras.minutos || 60) * 60000;   // passou de 1 hora, some daqui também
            chat.msgs = chat.msgs.filter((m) => Date.parse(m.em) >= desde).slice(-120);
            chat.ultimo = chat.msgs.reduce((a, m) => Math.max(a, m.id), chat.ultimo || 0);
            if (painelAtual !== 'chat') return;
            marcarChatLido();
            if (primeira) abrirPainel('chat', true);   // agora sabe se pode escrever: monta o formulário
            else desenharChat();
        } catch (e) {
            if (completo && painelAtual === 'chat') { const l = $('chatLista'); if (l && !chat.msgs.length) l.innerHTML = `<p class="vazio-msg">${esc(e.message)}</p>`; }
        } finally {
            chatBuscando = false;
        }
    }
    function agendarChat() {
        clearTimeout(chatTimer);
        chatTimer = setTimeout(async () => {
            if (painelAtual !== 'chat') return;   // fechou: para de buscar
            if (!document.hidden && Date.now() - mexeuEm < 5 * 60000) await carregarChat(false);
            agendarChat();
        }, 10000);   // fase 71: de 10 em 10 s (eram 5: pesava no servidor)
    }
    function htmlPedidoChat(m, eu) {
        const p = m.pedido, k = culturas[p.item] || { id: p.item, nome: p.item };
        const quem = chat.atendidos[m.id] || [], ja = quem.reduce((a, x) => a + x.qtd, 0), falta = p.qtd - ja;
        const pode = Math.min(livreFeira(p.item), falta);
        let acao;
        if (eu) acao = ja ? `<button type="button" class="botao pequeno verde" data-chat-feira="${esc(p.item)}">Ver na feira</button>` : '<small>esperando alguém</small>';
        else if (falta <= 0) acao = '<small>pedido completo</small>';
        else if (pode > 0) acao = `<input type="number" min="1" max="${pode}" value="${pode}" data-chat-qtd="${m.id}" aria-label="Quantos vender"><button type="button" class="botao pequeno verde" data-chat-vender="${m.id}">Vender pra ${esc(m.apelido)}</button>`;
        else acao = `<small>você não tem ${esc(nomeQtd(k, 2))} sobrando</small>`;
        return `<div class="chat-pedido">${itemDe(k, 28)}<span class="txt">Procuro <b>${p.qtd} ${esc(nomeQtd(k, p.qtd))}</b>, pago ${moeda(p.preco)} cada${quem.length
            ? `<br><small>atendido por ${quem.map((x) => `${esc(x.apelido)} (${x.qtd})`).join(', ')}</small>` : ''}</span><span class="acao">${acao}</span></div>`;
    }
    function htmlMsgChat(m) {
        const eu = m.jogador === S.jogador.id, acoes = [];
        if (!eu) acoes.push(`<button type="button" data-visitar="${esc(m.jogador)}">visitar</button>`, `<button type="button" data-chat-silenciar="${esc(m.jogador)}">silenciar</button>`);
        if (eu || chat.admin) acoes.push(`<button type="button" data-chat-apagar="${m.id}">apagar</button>`);
        return `<div class="chat-msg${eu ? ' eu' : ''}">
            <div class="chat-quem">${A.htmlAvatar(m.avatar, 20)} <b>${esc(m.apelido)}</b><small>nv ${m.nivel}${m.admin ? ' · admin' : ''} · ${tempoAtras(m.em)}</small><span class="chat-acoes">${acoes.join('')}</span></div>
            ${m.texto ? `<div class="chat-texto">${esc(m.texto)}</div>` : ''}${m.pedido ? htmlPedidoChat(m, eu) : ''}
        </div>`;
    }
    // redesenha a lista só quando muda alguma coisa (e uma vez por minuto, pelo "há N min"), guardando as quantidades digitadas
    function desenharChat(forca) {
        const lista = $('chatLista');
        if (!lista || !S) return;
        const sil = silenciados(), msgs = chat.msgs.filter((m) => !sil.includes(m.jogador));
        const assinatura = JSON.stringify([msgs.map((m) => m.id), chat.atendidos, sil, Math.floor(agora() / 60000), chat.regras ? 1 : 0]);
        if (!forca && assinatura === chatAssinatura) return;
        chatAssinatura = assinatura;
        const perto = lista.scrollHeight - lista.scrollTop - lista.clientHeight < 80;
        const digitado = {};
        lista.querySelectorAll('[data-chat-qtd]').forEach((i) => { digitado[i.dataset.chatQtd] = i.value; });
        lista.innerHTML = msgs.length ? msgs.map(htmlMsgChat).join('')
            : `<p class="vazio-msg">${chat.regras ? 'Ninguém falou nada na última hora. Puxe assunto!' : 'Abrindo o chat…'}</p>`;
        lista.querySelectorAll('[data-chat-qtd]').forEach((i) => { if (digitado[i.dataset.chatQtd] != null) i.value = digitado[i.dataset.chatQtd]; });
        if (perto || forca) lista.scrollTop = lista.scrollHeight;
    }
    // o que dá para pedir: tudo que tem preço na feira
    const nomePedido = (id) => esc((culturas[id] || { nome: id }).nome);
    const itensPedido = () => Object.values(culturas).filter((k) => k.venda > 0).map((k) => k.id).sort((a, b) => nomePedido(a).localeCompare(nomePedido(b)));
    function htmlPedirChat() {
        const itens = itensPedido();
        if (!itens.includes(chatPedidoItem)) chatPedidoItem = itens.includes('tomate') ? 'tomate' : itens[0];
        const k = culturas[chatPedidoItem], [min, max] = faixaFeira(k);
        return `<div class="chat-pedir">
            <label>O que você procura <select data-chat-item>${itens.map((id) => `<option value="${esc(id)}"${id === chatPedidoItem ? ' selected' : ''}>${nomePedido(id)}</option>`).join('')}</select></label>
            <label>Quantos <input type="number" id="chatQtd" min="1" max="99" value="10"></label>
            <label>Pago cada <input type="number" id="chatPreco" min="${min}" max="${max}" value="${Math.min(max, Math.max(min, k.venda))}"></label>
            <p class="det">${itemDe(k, 16)} Na venda normal, ${moeda(k.venda)}. Pode oferecer de ${numero(min)} a ${numero(max)} cada.</p>
        </div>`;
    }
    function htmlChat() {
        const r = chat.regras || {}, sil = silenciados().length;
        const escrever = !chat.regras ? ''
            : !chat.pode ? `<p class="aviso">${ico('cadeado', 14)} Você já lê o chat; para escrever, chegue ao nível ${r.nivel}.</p>`
            : `${chatPedindo ? htmlPedirChat() : ''}
               <form class="chat-form" data-chat-form autocomplete="off">
                   <input type="text" id="chatTexto" maxlength="${r.letras || 120}" enterkeyhint="send" placeholder="${chatPedindo ? 'Um recado junto (opcional)' : 'Escreva para todo mundo…'}">
                   <button type="submit" class="botao pequeno verde">${chatPedindo ? 'Pedir' : 'Enviar'}</button>
                   <button type="button" class="botao pequeno creme" data-chat-pedir>${chatPedindo ? 'Só texto' : `${ico('moeda', 14)} Pedir item`}</button>
               </form>`;
        return `<div class="chat-lista" id="chatLista"></div>${escrever}
            <p class="det">As mensagens somem em 1 hora. Sem palavrão e sem link. Quem atende o seu pedido põe o lote na barraca dele, separado para você por ${r.reserva_horas || 2} h.${sil
                ? ` <button type="button" class="botao pequeno creme" data-chat-dessilenciar>Mostrar ${sil === 1 ? 'quem silenciei' : `os ${sil} silenciados`}</button>` : ''}</p>`;
    }
    async function enviarChat() {
        const inp = $('chatTexto'), texto = ((inp && inp.value) || '').trim();
        const args = { p_token: token, p_texto: texto };
        if (chatPedindo) {
            const k = culturas[chatPedidoItem], [min, max] = faixaFeira(k);
            const qtd = Number(($('chatQtd') || {}).value), preco = Number(($('chatPreco') || {}).value);
            if (!(qtd >= 1 && qtd <= 99)) return toast('Quantidade entre 1 e 99.', 'erro');
            if (!(preco >= min && preco <= max)) return toast(`Preço de cada entre ${numero(min)} e ${numero(max)}.`, 'erro');
            Object.assign(args, { p_item: chatPedidoItem, p_qtd: qtd, p_preco: preco });
        } else if (!texto) return;
        if (chatEnviando) return;
        chatEnviando = true;
        try {
            await rpc('fazenda_chat_enviar', args);
            if (inp) inp.value = '';
            if (chatPedindo) { chatPedindo = false; abrirPainel('chat', true); }
            await carregarChat(false);
            const l = $('chatLista');
            if (l) l.scrollTop = l.scrollHeight;
        } catch (e) {
            tratarErro(e);
        } finally {
            chatEnviando = false;
        }
    }
    // fase 68: o que a radiação do reator fez (o servidor manda uma vez só)
    function avisarRadiacao(estado) {
        for (const r of estado.radiacao || []) {
            const t = tipoAnimal(r.animal), nome = esc(t ? t.nome.toLowerCase() : r.animal), k = culturas[r.produto] || { id: r.produto, nome: r.produto || '' };
            const fem = FEMEA.has(r.animal), o = fem ? 'a' : 'o';
            if (r.evento === 'radioativo') {
                const ainda = Date.parse(r.em) + 30 * 60000 > agora();
                toast(`${ico('raio', 16)} O reator deixou ${fem ? 'a sua' : 'o seu'} ${nome} <b>radioativ${o}</b>: ${ainda ? `por meia hora ${fem ? 'ela' : 'ele'} dá 1 ${esc(k.nome.toLowerCase())} a cada 2 minutos` : `${fem ? 'ela' : 'ele'} deu ${r.qtd} ${esc(nomeQtd(k, r.qtd))} em meia hora`}, direto no celeiro!`, 'festa', 'importante');
            } else {
                som.tocar('erro');
                toast(`${spr(A.ANIMAL[r.animal] || 122, 18)} ${fem ? 'A' : 'O'} ${nome} radioativ${o} não resistiu à radiação do reator. Compre ${fem ? 'outra' : 'outro'} na loja.`, undefined, 'importante');
            }
        }
    }
    function avisarReservas(estado) {
        for (const rv of ((estado.chat && estado.chat.reservas) || []).filter((x) => x.nova)) {
            const k = culturas[rv.item] || { id: rv.item, nome: rv.item };
            toast(`${itemDe(k, 18)} <b>${esc(rv.vendedor)}</b> separou ${rv.qtd} ${esc(nomeQtd(k, rv.qtd))} pra você na feira, até ${hora(rv.ate)}. Abra a Feira para comprar.`, 'festa', 'importante');
        }
    }
    function avisarFeira(estado) {
        for (const v of (estado.feira && estado.feira.vendas_novas) || []) {
            toast(`${ico('moeda', 16)} <b>${esc(v.comprador || 'Alguém')}</b> comprou na feira os seus ${v.qtd} ${itemDe(culturas[v.item] || { id: v.item }, 16)}: +${v.recebeu} ${ico('moeda', 14)}`, 'festa', 'importante');
        }
    }

    /* ---------- Metas de nível (fase 49) ----------
       Tudo o que cada nível libera vira meta (estado.metas, montado no servidor): construir cada
       oficina, máquina, coisa de energia, cercado e árvore do pomar; ter cada bicho; contratar cada
       ajudante; comprar cada terreno; ocupar os canteiros. Com tudo em dia até o nível de agora,
       +50% de XP até o próximo (jogador.bonus_nivel). */
    const bonusMetas = () => !!S && S.jogador.bonus_nivel != null && S.jogador.bonus_nivel === S.jogador.nivel;
    const metasDoNivelFaltando = () => (S && S.metas ? S.metas.filter((m) => m.nivel === S.jogador.nivel && !m.feito).length : 0);
    function descreverMeta(m) {
        if (m.tipo === 'construir') { const it = tipoItem(m.id) || { nome: m.id }; return { icone: A.htmlItem(m.id, 32), txt: `Construa: <b>${esc(it.nome)}</b>`, ir: `data-meta-construir="${esc(m.id)}"` }; }
        if (m.tipo === 'bicho') { const t = tipoAnimal(m.id) || { nome: m.id }; return { icone: spr(A.ANIMAL[m.id], 32), txt: `Tenha: <b>${esc(t.nome)}</b> (precisa do cercado)`, ir: 'data-meta-loja="animais"' }; }
        if (m.tipo === 'ajudante') { const h = tipoAjudante(m.id) || { nome: m.id, papel: '' }; return { icone: retratoAjudante(m.id, 32), txt: `Contrate: <b>${esc(h.nome)}</b> ${h.papel ? `(${esc(h.papel.toLowerCase())})` : ''}`, ir: 'data-meta-loja="ajudantes"' }; }
        if (m.tipo === 'terreno') { const z = zonasVenda().find((x) => String(x.n) === String(m.id)) || { nome: `Terreno ${m.id}` }; return { icone: spr(39, 32), txt: `Compre o terreno: <b>${esc(z.nome)}</b>`, ir: 'data-meta-loja="terrenos"' }; }
        return { icone: A.htmlItem('canteiro', 32), txt: `Use todos os canteiros do nível: <b>${m.tem} de ${m.max}</b>`, ir: 'data-meta-construir="canteiro"' };
    }
    function htmlMetas() {
        const metas = S.metas || [], n = S.jogador.nivel;
        if (!metas.length) return '<p class="vazio-msg">As metas chegam em breve.</p>';
        const linha = (m) => {
            const d = descreverMeta(m);
            return `<div class="item${m.feito ? ' meta-feita' : ''}"><span class="ico">${d.icone}</span>
                <span><span class="nome">${d.txt}</span><span class="det"><span>Nível ${m.nivel}</span></span></span>
                ${m.feito ? '<span class="preco">✓ Feito</span>' : `<button type="button" class="botao pequeno verde" ${d.ir}>Ir</button>`}</div>`;
        };
        const doNivel = metas.filter((m) => m.nivel === n);
        const deTras = metas.filter((m) => m.nivel < n && !m.feito);
        const feitas = metas.filter((m) => m.nivel < n && m.feito).length;
        const faltam = metas.filter((m) => !m.feito).length;
        return `${bonusMetas()
                ? (n >= 20   // fase 57: fazenda completa
                    ? `<p class="aviso"><b>Fazenda completa!</b> Até o nível ${n + 1}, todo XP vem com <b>+75%</b>, e cada colheita sua dá <b>+2 XP</b> a mais (o de arar e plantar). No próximo nível chegam metas novas: cumpra de novo para manter o bônus.</p>`
                    : `<p class="aviso"><b>Tudo em dia!</b> Até o nível ${n + 1}, todo XP vem com <b>+50%</b>. No próximo nível chegam metas novas: cumpra de novo para manter o bônus.</p>`)
                : `<p class="aviso">Faltam <b>${faltam}</b> meta${faltam === 1 ? '' : 's'}. Com tudo o que o seu nível libera em dia, você ganha <b>${n >= 20 ? '+75% de XP e +2 XP em cada colheita' : '+50% de XP'}</b> até o próximo nível.</p>`}
            <h3 class="secao-titulo">Nível ${n}</h3><div class="lista">${doNivel.map(linha).join('')}</div>
            ${deTras.length ? `<h3 class="secao-titulo">Ficaram para trás (${deTras.length})</h3><div class="lista">${deTras.map(linha).join('')}</div>` : ''}
            ${feitas ? `<p class="det">${feitas} meta${feitas === 1 ? '' : 's'} dos níveis anteriores já cumprida${feitas === 1 ? '' : 's'}.</p>` : ''}`;
    }
    // leva direto ao modo construir com o item escolhido
    function irConstruir(id) {
        const it = tipoItem(id);
        if (!it) return;
        if (it.nivel_min > S.jogador.nivel) return toast(`${esc(it.nome)} libera no nível ${it.nivel_min}.`);
        fecharPainel();
        abrirConstrucao();
        constr.aba = id === 'canteiro' ? 'plantacao' : it.categoria;
        constr.tipo = it.id;
        desenharPaleta();
        atualizarModo();
        mostrarStatus(id === 'canteiro'
            ? `${A.htmlItem('canteiro', 22)} Canteiro: toque nos quadrados livres (sobram ${canteirosLivres()}).`
            : `${A.htmlItem(it.id, 22)} ${esc(it.nome)} (${cercadoGratis(it) ? 'o seu sai de graça' : moeda(it.custo)}): toque num lugar livre para colocar.`);
    }

    function usarDiamantes(item, x, y) {
        const num = (v) => (v == null || v === '' ? null : Number(v));
        return enfileirar([], async () => {
            const r = await rpc('fazenda_usar_diamantes', { p_token: token, p_item: item, p_x: num(x), p_y: num(y) });
            aplicarEstado(r.estado);
            som.tocar('moeda');
            const j = r.estado.jogador;
            const msg = {
                xp2: `XP em dobro até ${hora(j.xp2_ate)}!`, xp: `+${r.xp} ${ico('xp', 14)}!`,
                cafe: `Café servido: os ajudantes trabalham em dobro até ${hora(j.cafe_ate)}!`,
                energia: 'Baterias cheias!', oficina: 'Receita pronta na hora!', murchas: 'As plantas murchas voltaram, prontas para colher!'
            }[item];
            toast(`${ico('diamante', 16)} −${r.diamantes} · ${msg}`, 'festa');
            if (painelAtual) abrirPainel(painelAtual, true);
        });
    }

    function htmlLojaDiamantes() {
        const pacotes = S.pacotes_diamantes || [];
        const usar = htmlUsarDiamantes();
        if (!pacotes.length && !usar) return '<p class="vazio-msg">Os diamantes chegam em breve.</p>';
        return `<p>Você tem <b>${S.jogador.diamantes || 0}</b> ${ico('diamante', 14)}. Ganha 5 a cada nível${ANUNCIO.ligado ? ' e 1 por anúncio' : ''}.</p>
            ${usar}${pacotes.length ? `<h3 class="secao-titulo">Comprar diamantes</h3>` : ''}
            <div class="lista">` + pacotes.map((p) => `<div class="item">
                <span class="ico">${ico('diamante', 36)}</span>
                <span><span class="nome">${p.diamantes} diamantes</span><span class="det">${p.bonus ? `<span class="bonus-txt">+${p.bonus} de bônus</span>` : ''}<span>${lojaD() ? `dá para ${Math.floor(p.diamantes / lojaD().cafe.preco)} cafés dos ajudantes (${lojaD().cafe.horas} h cada)` : ''}</span></span></span>
                <button type="button" class="botao pequeno verde" data-diamantes="${esc(p.id)}">${reais(p.valor)}</button>
            </div>`).join('') + `</div>
            <p class="aviso">O pagamento é no Mercado Pago (Pix, cartão ou saldo): a fazenda não vê os dados do seu cartão. Os diamantes caem assim que o pagamento é aprovado. Também dá para ganhar: 5 a cada nível${ANUNCIO.ligado ? ' e 1 por anúncio' : ''}. <a href="privacidade.html" target="_blank" rel="noopener">Como funciona a compra</a></p>`;
    }
    async function comprarDiamantes(pacote) {
        let res, data;
        try {
            res = await fetch(`${API}/functions/v1/fazenda-diamantes`, {
                method: 'POST',
                headers: { apikey: SUPABASE_KEY, 'Content-Type': 'application/json' },
                body: JSON.stringify({ token, pacote })
            });
            data = await res.json().catch(() => null);
        } catch {
            return toast('Sem conexão com a loja de diamantes. Tente de novo.', 'erro');
        }
        if (!res.ok || !data || !data.url) return toast(ERROS[data && data.message] || 'A loja de diamantes não respondeu. Tente daqui a pouco.', 'erro');
        location.href = data.url;   // página do Mercado Pago
    }
    // voltou do Mercado Pago: espera a aprovação (Pix costuma ser na hora) e avisa quando os diamantes caírem
    async function acompanharCompra(id) {
        for (let n = 0; n < 20; n++) {
            let r;
            try { r = await rpc('fazenda_compra_status', { p_token: token, p_compra: id }); } catch { return; }
            aplicarEstado(r.estado);
            if (r.status === 'aprovada') {
                toast(`${ico('diamante', 16)} Compra aprovada: +${r.diamantes} diamantes!`, 'festa');
                som.tocar('moeda');
                return;
            }
            if (r.status !== 'pendente') return toast('O pagamento não foi aprovado, então nenhum diamante entrou.', 'erro');
            if (n === 0) toast('Esperando o Mercado Pago aprovar o pagamento...');
            await new Promise((ok) => setTimeout(ok, 3000));
        }
        toast('O pagamento ainda está em análise. Os diamantes caem sozinhos assim que o Mercado Pago aprovar.');
    }

    /* ---------- Conta Google: ligar a fazenda e abrir ela num aparelho novo ----------
       O botão é o oficial do Google (Google Identity Services, carregado só quando aparece).
       A credencial vai para a Edge Function (rota /google), que confere a assinatura antes de
       ligar a conta à fazenda ou abrir a fazenda ligada a ela. */
    let googleScript = null, googleAcao = null;
    function carregarGoogle() {
        if (!googleScript) googleScript = new Promise((ok, falha) => {
            const s = document.createElement('script');
            s.src = 'https://accounts.google.com/gsi/client';
            s.async = true;
            s.onload = () => {
                window.google.accounts.id.initialize({ client_id: GOOGLE_CLIENT_ID, callback: (r) => respostaGoogle(r.credential), cancel_on_tap_outside: true });
                ok();
            };
            s.onerror = () => { googleScript = null; falha(new Error('Não deu para abrir o login do Google agora.')); };
            document.head.appendChild(s);
        });
        return googleScript;
    }
    async function botaoGoogle(alvo, acao) {
        if (!GOOGLE_CLIENT_ID || !alvo) return;
        try { await carregarGoogle(); } catch (e) { alvo.textContent = e.message; return; }
        googleAcao = acao;
        alvo.innerHTML = '';
        window.google.accounts.id.renderButton(alvo, {
            theme: 'outline', size: 'large', shape: 'pill', locale: 'pt-BR',
            text: acao === 'entrar' ? 'signin_with' : 'continue_with'
        });
    }
    async function respostaGoogle(credencial) {
        const acao = googleAcao;
        let res = null, data = null;
        try {
            res = await fetch(`${API}/functions/v1/fazenda-diamantes/google`, {
                method: 'POST',
                headers: { apikey: SUPABASE_KEY, 'Content-Type': 'application/json' },
                body: JSON.stringify({ credencial, acao, token: acao === 'ligar' ? token : undefined })
            });
            data = await res.json().catch(() => null);
        } catch { /* sem conexão: cai na mensagem abaixo */ }
        if (!res || !res.ok || !data) {
            const msg = ERROS[data && data.message] || 'O login com Google não funcionou agora. Tente de novo.';
            return acao === 'entrar' ? mostrarErroEntrada(msg) : toast(msg, 'erro');
        }
        if (acao === 'entrar') {
            token = data.token;
            store.set(LS.token, token);
            aplicarEstado(data.estado);
            mostrarFazenda();
            toast('Bem-vindo(a) de volta!');
        } else {
            aplicarEstado(data.estado);
            toast(`${ico('check', 14)} Fazenda ligada ao Google: agora dá para abrir ela em qualquer aparelho.`, 'festa');
            if (painelAtual === 'conta') abrirPainel('conta', true);
        }
    }
    function htmlGoogle() {
        if (!GOOGLE_CLIENT_ID) return '';
        const conta = S.jogador.google;
        return `<h3 class="secao-titulo">Conta Google</h3>
            ${conta
                ? `<p>${ico('check', 14)} Ligada a <b>${esc(conta)}</b>. Em outro aparelho, toque em <b>Já tenho fazenda → Entrar com Google</b>.</p>
                   <p><button type="button" class="botao pequeno creme" data-google-desligar>Desligar do Google</button></p>`
                : `<p>Ligue a fazenda à sua conta Google: se perder o código ou trocar de celular, é só entrar com o Google.</p>
                   <div class="google-botao" data-google-botao></div>`}`;
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
            alvo.innerHTML = `<p class="det" style="margin:0 0 12px">Você está em <b>${r.minha_posicao}º</b> de ${r.total} fazendas.${r.ranking.length < r.total ? ` Mostrando as ${r.ranking.length} primeiras.` : ''}</p>
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

    /* ---------- Admin (fase 53) ----------
       O dono (cjesse) escolhe quem é admin; os admins banem (com motivo) e desbanem. Conta banida não
       entra mais, some do ranking, das visitas e da feira. Tudo fica no log do painel.
       Fase 55: o dono gera um código de recuperação novo para quem perdeu o seu (aparece uma vez só). */
    let adminDados = null, adminBusca = '', adminBanindo = null, adminCodigo = null;
    function carregarAdmin() {
        enfileirar([], async () => {
            adminDados = await rpc('fazenda_admin_jogadores', { p_token: token, p_busca: adminBusca || null });
            if (painelAtual === 'admin') abrirPainel('admin', true);
        });
    }
    const ACAO_ADMIN = { banir: 'baniu', desbanir: 'desbaniu', dar_admin: 'deu admin para', tirar_admin: 'tirou o admin de', novo_codigo: 'gerou um código novo para' };
    function htmlAdmin() {
        const dono = S.jogador.admin === 'dono';
        const busca = `<form class="admin-busca" data-admin-busca>
                <input type="search" id="adminBusca" placeholder="Buscar pelo apelido" value="${esc(adminBusca)}" autocomplete="off">
                <button type="submit" class="botao pequeno verde">Buscar</button>
            </form>`;
        if (!adminDados) return busca + '<p class="vazio-msg">Carregando…</p>';
        const d = adminDados;
        const lista = d.jogadores.length ? '<div class="lista">' + d.jogadores.map((j) => {
            const tags = [j.admin === 'dono' ? 'dono' : j.admin ? 'admin' : '', j.banido_em ? 'banido' : ''].filter(Boolean)
                .map((t) => `<small class="tag-admin ${t}">${t}</small>`).join(' ');
            const botoes = j.eu || j.admin === 'dono' ? '' : [
                j.admin ? '' : j.banido_em
                    ? `<button type="button" class="botao pequeno creme" data-admin-desbanir="${esc(j.id)}" data-apelido="${esc(j.apelido)}">Desbanir</button>`
                    : `<button type="button" class="botao pequeno vermelho" data-admin-banir="${esc(j.id)}">Banir</button>`,
                dono && !j.banido_em ? `<button type="button" class="botao pequeno creme" data-admin-cargo="${esc(j.id)}" data-apelido="${esc(j.apelido)}" data-dar="${j.admin ? '' : '1'}">${j.admin ? 'Tirar admin' : 'Tornar admin'}</button>` : '',
                dono && !j.banido_em ? `<button type="button" class="botao pequeno creme" data-admin-codigo="${esc(j.id)}" data-apelido="${esc(j.apelido)}">Novo código</button>` : ''
            ].join('');
            const codigo = adminCodigo && adminCodigo.id === j.id ? `<div class="admin-motivo">
                    <div class="codigo-box"><code>${esc(adminCodigo.codigo)}</code><button type="button" class="botao pequeno creme" data-admin-copiar>Copiar</button></div>
                    <p class="aviso">Código novo de <b>${esc(j.apelido)}</b>. Ele só aparece agora: passe para o jogador entrar em "Já tenho uma fazenda". O antigo não vale mais.</p>
                </div>` : '';
            const banindo = adminBanindo === j.id ? `<div class="admin-motivo">
                    <input type="text" id="adminMotivo" maxlength="200" placeholder="Motivo (ex.: apelido ofensivo)">
                    <button type="button" class="botao pequeno vermelho" data-admin-confirmar="${esc(j.id)}" data-apelido="${esc(j.apelido)}">Banir</button>
                    <button type="button" class="botao pequeno creme" data-admin-cancelar>Cancelar</button>
                </div>` : '';
            return `<div class="item admin-linha${j.banido_em ? ' banido' : ''}">
                <span class="ico">${A.htmlAvatar(j.avatar, 32)}</span>
                <span style="min-width:0"><span class="nome">${esc(j.apelido)}${j.eu ? ' (você)' : ''} ${tags}</span>
                    <span class="det"><span>Nível ${j.nivel}</span><span>desde ${desde(j.criado_em)}</span><span>visto há ${fmtTempo(agora() - Date.parse(j.visto_em))}</span></span>
                    ${j.banido_em ? `<span class="det"><span class="txt">Banido há ${fmtTempo(agora() - Date.parse(j.banido_em))}${j.banido_motivo ? ': ' + esc(j.banido_motivo) : ''}</span></span>` : ''}
                </span>
                <span class="admin-botoes">${botoes}</span>
                ${banindo}${codigo}
            </div>`;
        }).join('') + '</div>' : `<p class="vazio-msg">Ninguém com "${esc(adminBusca)}" no apelido.</p>`;
        const log = d.log.length ? '<h3 class="secao-titulo">Últimas ações</h3><div class="admin-log">' + d.log.map((l) =>
            `<p><b>${esc(l.admin || '?')}</b> ${ACAO_ADMIN[l.acao] || esc(l.acao)} <b>${esc(l.alvo || '?')}</b>${l.motivo ? ` · ${esc(l.motivo)}` : ''} <small>há ${fmtTempo(agora() - Date.parse(l.em))}</small></p>`).join('') + '</div>' : '';
        return busca + `<p class="det"><span class="txt">${d.total} fazendas, ${d.banidos} banida${d.banidos === 1 ? '' : 's'}. ${adminBusca ? 'Mostrando a busca.' : 'Sem busca: as banidas primeiro, depois as mais novas.'}</span></p>`
            + lista + log
            + `<p class="aviso">Conta banida não entra mais no jogo (nem com o código ou o Google), some do ranking, das visitas e da feira. Desbanir devolve tudo como estava.${dono ? ' Como dono, você escolhe quem é admin: admin bane e desbane, mas não mexe em outros admins. Quem perdeu o código de recuperação ganha um novo em "Novo código": o antigo para de valer e a fazenda sai dos aparelhos onde estava aberta.' : ''}</p>`;
    }

    function fecharPainel() {
        el.painel.classList.remove('aberto');
        painelAtual = null;
        if (ultimoFoco && ultimoFoco.focus) ultimoFoco.focus();
        if (paineisDepois.length) { const prox = paineisDepois.shift(); setTimeout(() => { if (!painelAtual) abrirPainel(prox); else paineisDepois.unshift(prox); }, 350); }   // fase 67/69
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
            toast(`Semente escolhida: ${itemDe(k)} ${esc(k.nome)}`, undefined, 'leve');
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
            const diam = temAvatar(novo.tipo) ? 0 : diamAvatar(novo.tipo);
            if (diam > (S.jogador.diamantes || 0)) return toast(ERROS.diamantes_insuficientes, 'erro');
            if (!diam && preco > S.jogador.moedas) return toast(ERROS.moedas_insuficientes, 'erro');
            if (diam) { S.jogador.diamantes -= diam; S.jogador.avatares = [...(S.jogador.avatares || []), novo.tipo]; som.tocar('moeda'); }
            else if (preco) { S.jogador.moedas -= preco; S.jogador.avatares = [...(S.jogador.avatares || []), novo.tipo]; som.tocar('moeda'); }
            S.jogador.avatar = novo;       // aparece na hora; o servidor confirma
            cena.definirAvatar(novo);
            desenharHud();
            abrirPainel('conta');
            enfileirar([], async () => {
                const r = await rpc('fazenda_avatar', { p_token: token, p_avatar: novo });
                aplicarEstado(r.estado);
                toast(r.pagou_diamantes ? `${A.htmlAvatar(novo, 22)} Comprou o personagem por ${ico('diamante', 14)} ${r.pagou_diamantes}! Agora ele é seu para sempre.`
                    : r.pagou ? `${A.htmlAvatar(novo, 22)} Comprou o personagem por ${ico('moeda', 14)} ${r.pagou.toLocaleString('pt-BR')}! Agora ele é seu para sempre.`
                    : `${A.htmlAvatar(novo, 22)} Avatar salvo! Os vizinhos já veem o novo visual.`, r.pagou || r.pagou_diamantes ? 'festa' : undefined);
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
            const qual = vend.dataset.vender;
            // "finais" vende só o que saiu das oficinas, um produto por vez
            const lista = qual === 'finais' ? produtosFinais().filter((id) => naCeleiro(id) > reservaDe(id))
                : [qual === '*' ? null : qual];
            enfileirar([], async () => {
                let ganho = 0, xp = 0, semXp = 0, estado = null;
                // fase 74b: os produtos todos numa chamada só (um por vez travava o jogo uns segundos)
                if (lista.length) {
                    const r = await rpc('fazenda_vender', qual === 'finais'
                        ? { p_token: token, p_item: null, p_quantidade: null, p_itens: lista }
                        : { p_token: token, p_item: lista[0], p_quantidade: null });
                    ganho = r.ganho; xp = r.xp || 0; semXp = r.sem_xp || 0; estado = r.estado;
                }
                const guardou = qual !== 'finais' && Object.keys(S.reservas || {}).length ? ' A ração dos animais ficou guardada.' : '';
                // fase 56: o que veio da feira vende pelas moedas de sempre, mas sem XP
                const daFeira = semXp ? ` ${semXp} ${semXp === 1 ? 'item veio' : 'itens vieram'} da feira: esses não dão XP.` : '';
                if (ganho > 0) { toast(`Vendeu por ${ico('moeda', 16)} ${ganho}${xp ? ` e ganhou +${xp} ${ico('xp', 16)}` : ''}!${guardou}${daFeira}`); som.tocar('moeda'); tutorialEvento('vender'); }
                if (estado) aplicarEstado(estado);
            }).finally(() => { vend.disabled = false; });
            return;
        }
        if (e.target.closest('[data-mar-ir]')) { if (mar) fecharPainel(); else abrirMar(); return; }   // fase 62: o alto-mar
        if (e.target.closest('[data-mar-painel]')) { abrirPainel('mar'); return; }
        const pt = e.target.closest('[data-pintar]');   // fase 65: a pintura do barco (o rascunho)
        if (pt) {
            const [campo, valor] = pt.dataset.pintar.split(':');
            pinturaBarco = { ...(pinturaBarco || visualBarco()), [campo]: valor };
            abrirPainel('mar', true);
            return;
        }
        if (e.target.closest('[data-pintar-salvar]')) {
            const visual = pinturaBarco || visualBarco();
            enfileirar([], async () => {
                const r = await rpc('fazenda_barco_pintar', { p_token: token, p_visual: visual });
                pinturaBarco = null;
                aplicarEstado(r.estado);
                som.tocar('construir');
                toast(`${iconeMar('barco', 20)} Barco pintado!`, 'festa');
            });
            return;
        }
        if (e.target.closest('[data-pier-construir]')) {   // fase 61
            if (!confirm(`Construir o píer? Usa as 9 peças e ${moeda((S.pier.receita || {}).moedas || 0).replace(/<[^>]+>/g, '')} moedas.`)) return;
            enfileirar([], async () => {
                const r = await rpc('fazenda_construir_pier', { p_token: token });
                aplicarEstado(r.estado);
                toast(`${itemDe(culturas.ancora || { id: 'ancora' }, 20)} O píer está pronto! O barco já está atracado.`, 'festa');
                som.tocar('festa');
                abrirPainel('pier', true);
            });
            return;
        }
        const pc = e.target.closest('[data-pier-comprar]');
        if (pc) {
            const id = pc.dataset.pierComprar, k = culturas[id] || { nome: id }, preco = ((S.pier.receita || {}).diamantes || {})[id];
            if (!confirm(`Comprar 1 ${k.nome.toLowerCase()} por ${preco} diamantes?`)) return;
            pc.disabled = true;
            enfileirar([], async () => {
                const r = await rpc('fazenda_pier_comprar_peca', { p_token: token, p_item: id });
                aplicarEstado(r.estado);
                toast(`${itemDe(k, 18)} Comprou 1 ${esc(k.nome.toLowerCase())} para o píer.`);
            }).finally(() => { pc.disabled = false; });
            return;
        }
        const ps = e.target.closest('[data-pier-soltar]');
        if (ps) {
            const id = ps.dataset.pierSoltar;
            S.reservas = { ...(S.reservas || {}) }; delete S.reservas[id];
            abrirPainel(painelAtual || 'celeiro', true);
            enfileirar([], async () => {
                const r = await rpc('fazenda_reservar', { p_token: token, p_item: id, p_quantidade: 0 });
                aplicarEstado(r.estado);
            });
            return;
        }
        const pg = e.target.closest('[data-pier-guardar]');
        if (pg) {   // guarda para o píer (a mesma reserva da ração): sai do "Vender tudo" e da feira
            const id = pg.dataset.pierGuardar, n = Math.min(naCeleiro(id), ((S.pier.receita || {}).itens || {})[id] || 1);
            S.reservas = { ...(S.reservas || {}), [id]: n };
            abrirPainel(painelAtual || 'pier', true);
            enfileirar([], async () => {
                const r = await rpc('fazenda_reservar', { p_token: token, p_item: id, p_quantidade: n });
                aplicarEstado(r.estado);
                toast(`${itemDe(culturas[id] || { id }, 18)} Guardado para o píer: não vai mais no "Vender tudo".`);
            });
            return;
        }
        const rf = e.target.closest('[data-raro-feira]');   // fase 60: do celeiro direto para vender na feira
        if (rf) { abaFeira = 'vender'; feiraItem = rf.dataset.raroFeira; abrirPainel('feira'); return; }
        const af = e.target.closest('[data-aba-feira]');
        if (af) { abaFeira = af.dataset.abaFeira; abrirPainel('feira', true); if (abaFeira === 'comprar') carregarFeira(); return; }
        const ff = e.target.closest('[data-feira-filtro]');
        if (ff) { feiraFiltro = ff.dataset.feiraFiltro || null; carregarFeira(); return; }
        const fc = e.target.closest('[data-feira-comprar]');
        if (fc) {
            fc.disabled = true;
            enfileirar([], async () => {
                const r = await rpc('fazenda_feira_comprar', { p_token: token, p_id: Number(fc.dataset.feiraComprar) });
                som.tocar('moeda');
                toast(`${itemDe(culturas[r.item] || { id: r.item }, 18)} Comprou ${r.qtd} de <b>${esc(r.vendedor || 'alguém')}</b> na feira por ${r.total} ${ico('moeda', 14)}: já está no celeiro.`, 'festa', 'importante');
                aplicarEstado(r.estado);
                carregarFeira();
            });
            return;
        }
        const fb = e.target.closest('[data-feira-barraca]');
        if (fb) {   // fase 51: mais uma barraca na feira
            fb.disabled = true;
            enfileirar([], async () => {
                const r = await rpc('fazenda_feira_barraca', { p_token: token });
                som.tocar('moeda');
                aplicarEstado(r.estado);
                toast(`${A.htmlItem('barraca', 18)} Barraca nova na feira! Agora você pode ter ${limiteFeira()} anúncios.`, 'festa');
                abrirPainel('feira', true);
            });
            return;
        }
        // fase 53: admin
        const ab = e.target.closest('[data-admin-banir]');
        if (ab) { adminBanindo = ab.dataset.adminBanir; abrirPainel('admin', true); const m = $('adminMotivo'); if (m) m.focus(); return; }
        if (e.target.closest('[data-admin-cancelar]')) { adminBanindo = null; abrirPainel('admin', true); return; }
        const ac = e.target.closest('[data-admin-confirmar]');
        if (ac) {
            const motivo = (($('adminMotivo') || {}).value || '').trim();
            if (!motivo) return toast(ERROS.admin_motivo, 'erro');
            ac.disabled = true;
            enfileirar([], async () => {
                await rpc('fazenda_admin_banir', { p_token: token, p_jogador: ac.dataset.adminConfirmar, p_banir: true, p_motivo: motivo });
                adminBanindo = null;
                toast(`${ico('escudo', 14)} <b>${esc(ac.dataset.apelido)}</b> foi banido(a).`, '', 'importante');
                carregarAdmin();
            });
            return;
        }
        const ad = e.target.closest('[data-admin-desbanir]');
        if (ad) {
            if (!confirm(`Desbanir ${ad.dataset.apelido}? A conta volta a entrar no jogo.`)) return;
            enfileirar([], async () => {
                await rpc('fazenda_admin_banir', { p_token: token, p_jogador: ad.dataset.adminDesbanir, p_banir: false, p_motivo: null });
                toast(`${ico('escudo', 14)} <b>${esc(ad.dataset.apelido)}</b> foi desbanido(a).`, '', 'importante');
                carregarAdmin();
            });
            return;
        }
        const ag = e.target.closest('[data-admin-cargo]');
        if (ag) {
            const dar = ag.dataset.dar === '1';
            if (!confirm(dar ? `Tornar ${ag.dataset.apelido} admin? Admin pode banir e desbanir jogadores.` : `Tirar o admin de ${ag.dataset.apelido}?`)) return;
            enfileirar([], async () => {
                await rpc('fazenda_admin_definir', { p_token: token, p_jogador: ag.dataset.adminCargo, p_admin: dar });
                toast(`${ico('escudo', 14)} ${dar ? 'Agora' : 'Não é mais'} admin: <b>${esc(ag.dataset.apelido)}</b>.`, '', 'importante');
                carregarAdmin();
            });
            return;
        }
        const an = e.target.closest('[data-admin-codigo]');
        if (an) {
            if (!confirm(`Gerar um código de recuperação novo para ${an.dataset.apelido}? O código antigo para de valer e a fazenda sai dos aparelhos onde estiver aberta.`)) return;
            an.disabled = true;
            enfileirar([], async () => {
                const r = await rpc('fazenda_admin_novo_codigo', { p_token: token, p_jogador: an.dataset.adminCodigo });
                adminCodigo = { id: an.dataset.adminCodigo, codigo: r.codigo };
                toast(`${ico('escudo', 14)} Código novo para <b>${esc(r.apelido)}</b>. Copie e passe para ele(a).`, '', 'importante');
                carregarAdmin();
            });
            return;
        }
        if (e.target.closest('[data-admin-copiar]')) {
            if (adminCodigo && await copiarTexto(adminCodigo.codigo)) toast('Código copiado!');
            else toast('Não deu para copiar. Anote o código.', 'erro');
            return;
        }
        const ap = e.target.closest('[data-admin-perfil]');
        if (ap) {   // do perfil de quem você visita: abre o painel já com essa fazenda e o motivo para escrever
            adminBusca = ap.dataset.apelido;
            adminBanindo = ap.dataset.adminPerfil;
            adminDados = null;
            abrirPainel('admin');
            return;
        }
        const fx = e.target.closest('[data-feira-cancelar]');
        if (fx) {
            fx.disabled = true;
            enfileirar([], async () => {
                const r = await rpc('fazenda_feira_cancelar', { p_token: token, p_id: Number(fx.dataset.feiraCancelar) });
                aplicarEstado(r.estado);
                toast('Anúncio cancelado: os itens voltaram para o celeiro.', undefined, 'leve');
                abrirPainel('feira', true);
            });
            return;
        }
        if (e.target.closest('[data-feira-anunciar]')) {
            const qtd = Number(($('feiraQtd') || {}).value), preco = Number(($('feiraPreco') || {}).value);
            const k = culturas[feiraItem], [min, max] = faixaFeira(k);
            if (!(qtd >= 1 && qtd <= livreFeira(feiraItem))) return toast(`Quantidade entre 1 e ${livreFeira(feiraItem)}.`, 'erro');
            if (!(preco >= min && preco <= max)) return toast(`Preço de cada entre ${numero(min)} e ${numero(max)}.`, 'erro');
            enfileirar([], async () => {
                const r = await rpc('fazenda_feira_anunciar', { p_token: token, p_item: feiraItem, p_qtd: qtd, p_preco: preco });
                aplicarEstado(r.estado);
                som.tocar('moeda');
                toast(`${itemDe(k, 18)} ${qtd} × ${esc(k.nome.toLowerCase())} na feira por ${preco} cada.`);
                abaFeira = 'meus';
                abrirPainel('feira', true);
            });
            return;
        }
        const mc = e.target.closest('[data-meta-construir]');
        if (mc) { irConstruir(mc.dataset.metaConstruir); return; }
        const ml = e.target.closest('[data-meta-loja]');
        if (ml) { abaLoja = ml.dataset.metaLoja; abrirPainel('loja'); return; }
        if (e.target.closest('[data-colher-tudo]')) { abrirPainel('colherTudo'); return; }
        if (e.target.closest('[data-colher-tudo-agora]')) { colherTudoAgora(); return; }
        const ud = e.target.closest('[data-usar-diamante]');
        if (ud) {
            if (!ud.dataset.confirmar) {   // o primeiro toque só pede para confirmar (diamante vale dinheiro)
                ud.dataset.confirmar = '1';
                ud.dataset.texto = ud.innerHTML;
                ud.innerHTML = `Confirmar?<br>${ico('diamante', 14)} ${esc(ud.dataset.preco)}`;
                setTimeout(() => { if (ud.isConnected && ud.dataset.confirmar) { delete ud.dataset.confirmar; ud.innerHTML = ud.dataset.texto; } }, 4000);
                return;
            }
            ud.disabled = true;
            usarDiamantes(ud.dataset.usarDiamante, ud.dataset.x, ud.dataset.y);
            return;
        }
        const dia = e.target.closest('[data-diamantes]');
        if (dia) {
            dia.disabled = true;
            comprarDiamantes(dia.dataset.diamantes).finally(() => { dia.disabled = false; });
            return;
        }
        const esv = e.target.closest('[data-bau-esvaziar]');
        if (esv && bauAberto) {
            esv.disabled = true;
            const { x, y } = bauAberto;
            enfileirar([], async () => {
                const r = await rpc('fazenda_bau_esvaziar', { p_token: token, p_x: x, p_y: y });
                if (r.qtd) toast(`${A.htmlItem('bau', 16)} Levou ${r.qtd} itens do baú para o celeiro.`);
                aplicarEstado(r.estado);
            }).finally(() => { esv.disabled = false; });
            return;
        }
        const abaH = e.target.closest('[data-aba-historico]');
        if (abaH) { abaHistorico = abaH.dataset.abaHistorico; abrirPainel('historico', true); return; }
        if (e.target.closest('[data-historico-limpar]')) {
            historico = [];
            store.del(LS.historico);
            abrirPainel('historico', true);
            return;
        }
        if (e.target.closest('[data-google-desligar]')) {
            enfileirar([], async () => {
                const r = await rpc('fazenda_google_desligar', { p_token: token });
                aplicarEstado(r.estado);
                toast('A fazenda não está mais ligada ao Google. Guarde bem o código de recuperação.');
                if (painelAtual === 'conta') abrirPainel('conta', true);
            });
            return;
        }
        if (e.target.closest('[data-ir-diamantes]')) {
            abaLoja = 'diamantes';
            abrirPainel('loja');
            return;
        }
        const menuC = e.target.closest('[data-canteiro]');   // (fase 48: 'arar' vem do menu da murcha)
        if (menuC) {
            const p = menuCanteiro, o = menuC.dataset.canteiro;
            fecharPainel();
            if (o === 'trocar') return trocarPlanta(p);
            cena.irAte(p);
            if (o === 'arrancar') som.tocar('cuidar');
            executar(o, [p]);
            return;
        }
        const abaC = e.target.closest('[data-aba-celeiro]');
        if (abaC) {
            abaCeleiro = abaC.dataset.abaCeleiro;
            abrirPainel('celeiro', true);
            return;
        }
        const abaL = e.target.closest('[data-aba-loja]');
        if (abaL) {
            abaLoja = abaL.dataset.abaLoja;
            abrirPainel('loja', true);
            return;
        }
        const ajVer = e.target.closest('[data-ajudante-ver]');   // fase 59
        if (ajVer) { ajudanteAberto = ajVer.dataset.ajudanteVer; abrirPainel('ajudante'); return; }
        const ajDesc = e.target.closest('[data-ajudante-descansar]');
        if (ajDesc) {
            ajDesc.disabled = true;
            enfileirar([], async () => {
                const r = await rpc('fazenda_ajudante_descansar', { p_token: token, p_tipo: ajDesc.dataset.ajudanteDescansar });
                aplicarEstado(r.estado);
                const t = tipoAjudante(ajDesc.dataset.ajudanteDescansar);
                toast(`${retratoAjudante(ajDesc.dataset.ajudanteDescansar, 20)} ${esc(t ? t.nome : 'O ajudante')} foi descansar. Volta em 1 h com a energia cheia.`);
            }).finally(() => { ajDesc.disabled = false; });
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
                    : `${retratoAjudante(t.id, 22)} ${esc(t.nome)} subiu para o nível ${r.nivel}: agora ${t.funcao === 'animal' ? 'os bichos dele(a) ficam ' + ADIANTA_CUIDADOR[r.nivel] + ' no tempo' : t.funcao === 'energia' ? 'é ' + DESCONTO_ELETRICISTA[r.nivel] + ' de energia' : 'faz ' + RITMO[r.nivel] + ' por hora'}.`, 'festa');
                som.tocar('festa');
                if (painelAtual === 'loja') abrirPainel('loja', true);
            }).finally(() => { contr.disabled = false; });
            return;
        }
        // fase 45: o bicho sem cercado na loja leva direto ao modo construir com o cercado dele escolhido
        const cerc = e.target.closest('[data-construir-cercado]');
        if (cerc) {
            irConstruir(cerc.dataset.construirCercado);
            return;
        }
        const bs = e.target.closest('[data-bau-sorte]');
        if (bs) {   // fase 73: baú da sorte (é caro: pergunta antes)
            const t = S.baus_sorte && S.baus_sorte[bs.dataset.bauSorte];
            if (!t || !confirm(`Abrir o ${t.nome.toLowerCase()} por ${t.preco.toLocaleString('pt-BR')} moedas? É sorte: quase sempre volta menos do que custou.`)) return;
            bs.disabled = true;
            enfileirar([], async () => {
                const r = await rpc('fazenda_abrir_bau_sorte', { p_token: token, p_tipo: bs.dataset.bauSorte });
                aplicarEstado(r.estado);
                ultimoBau = { nome: t.nome, premio: r.premio };
                const bom = r.premio.tipo === 'raro' || r.premio.tipo === 'grande';
                toast(`${spr(ICONE_BAU[bs.dataset.bauSorte] || 1143, 22)} ${textoPremioBau(r.premio)}`, bom ? 'festa' : undefined);
                som.tocar(bom ? 'festa' : 'moeda');
                if (painelAtual === 'loja') abrirPainel('loja', true);
            }).finally(() => { bs.disabled = false; });
            return;
        }
        const comp = e.target.closest('[data-comprar]');
        if (comp) {
            const [categoria, tipo] = comp.dataset.comprar.split(':');
            if (categoria === 'melhoria') {   // fase 57: é caro: pergunta antes
                const m = (S.melhorias_tipos || []).find((k) => k.id === tipo), prox = m && m.niveis[melhoriaNivel(tipo)];
                const mats = prox && prox.itens ? Object.entries(prox.itens).map(([id, n]) => `${n} ${((culturas[id] || {}).nome || id).toLowerCase()}`).join(', ') : '';   // fase 65
                if (prox && !confirm(`Comprar ${prox.nome || m.nome} (nível ${melhoriaNivel(tipo) + 1}) por ${prox.custo.toLocaleString('pt-BR')} moedas${mats ? ` e ${mats}` : ''}?`)) return;
            }
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
                } else if (categoria === 'melhoria') {   // fase 57
                    const m = (S.melhorias_tipos || []).find((k) => k.id === tipo) || { nome: 'Melhoria' };
                    const k = m.mar && m.niveis[melhoriaNivel(tipo) - 1];   // fase 62: as do mar têm nome em cada nível
                    toast(k ? `${iconeMar(tipo, 22)} <b>${esc(k.nome)}</b>! Já vale no alto-mar.` : `${ico('xp', 18)} <b>${esc(m.nome)}</b> nível ${melhoriaNivel(tipo)}! Vale para a fazenda toda.`, 'festa');
                    som.tocar('festa');
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
        // fase 69: o calendário
        const cdia = e.target.closest('[data-cal-dia]');
        if (cdia) { mostrarStatus(`${ico('calendario', 16)} ${esc(cdia.title)}`); return; }
        if (e.target.closest('[data-cal-resgatar]')) {
            e.target.closest('[data-cal-resgatar]').disabled = true;
            enfileirar([], async () => {
                const r = await rpc('fazenda_calendario_resgatar', { p_token: token });
                aplicarEstado(r.estado);
                som.tocar('festa');
                toast(`${ico('calendario', 18)} Dia ${r.dia}: ${[...r.gratis, ...r.dourado].map(textoGanho).join(' + ')}`, 'festa');
            }).finally(() => { if (painelAtual === 'calendario') abrirPainel('calendario', true); });
            return;
        }
        if (e.target.closest('[data-cal-dourado]')) {
            const preco = (S.calendario && S.calendario.regras.dourado) || 120;
            if ((S.jogador.diamantes || 0) < preco) { abaLoja = 'diamantes'; abrirPainel('loja'); return; }
            if (!confirm(`Liberar a trilha dourada deste ciclo por ${preco} diamantes?`)) return;
            enfileirar([], async () => {
                const r = await rpc('fazenda_calendario_dourado', { p_token: token });
                aplicarEstado(r.estado);
                som.tocar('festa');
                toast(`${ico('calendario', 18)} Trilha dourada liberada!${r.dourado.length ? ` Dos dias que você já pegou: ${r.dourado.map(textoGanho).join(' + ')}` : ''}`, 'festa', 'importante');
            }).finally(() => { if (painelAtual === 'calendario') abrirPainel('calendario', true); });
            return;
        }
        // fase 67: o chat
        if (e.target.closest('[data-chat-pedir]')) { chatPedindo = !chatPedindo; abrirPainel('chat', true); return; }
        const chf = e.target.closest('[data-chat-feira]');
        if (chf) { abaFeira = 'comprar'; feiraFiltro = chf.dataset.chatFeira; abrirPainel('feira'); return; }
        const chv = e.target.closest('[data-chat-vender]');
        if (chv) {
            const id = Number(chv.dataset.chatVender), m = chat.msgs.find((x) => x.id === id);
            const qtd = Number((el.painelCorpo.querySelector(`[data-chat-qtd="${id}"]`) || {}).value);
            if (!m || !(qtd >= 1)) return;
            chv.disabled = true;
            enfileirar([], async () => {
                const r = await rpc('fazenda_chat_vender', { p_token: token, p_id: id, p_qtd: qtd });
                aplicarEstado(r.estado);
                som.tocar('moeda');
                toast(`${itemDe(culturas[m.pedido.item] || { id: m.pedido.item }, 18)} Separado na sua barraca para <b>${esc(r.para)}</b> até ${hora(r.ate)}. Se não comprar até lá, vira anúncio normal.`, 'festa');
                await carregarChat(false);
            }).finally(() => desenharChat(true));   // de novo com o botão (deu certo ou não)
            return;
        }
        const cha = e.target.closest('[data-chat-apagar]');
        if (cha) {
            const id = Number(cha.dataset.chatApagar), m = chat.msgs.find((x) => x.id === id);
            if (!m || !confirm(m.jogador === S.jogador.id ? 'Apagar a sua mensagem?' : `Apagar a mensagem de ${m.apelido} para todo mundo?`)) return;
            rpc('fazenda_chat_apagar', { p_token: token, p_id: id })
                .then(() => { chat.msgs = chat.msgs.filter((x) => x.id !== id); desenharChat(true); })
                .catch(tratarErro);
            return;
        }
        const chs = e.target.closest('[data-chat-silenciar]');
        if (chs) {
            const quem = chs.dataset.chatSilenciar, m = chat.msgs.find((x) => x.jogador === quem);
            store.set(LS.chatSilencio, JSON.stringify([...new Set([...silenciados(), quem])]));
            toast(`Você não vai mais ver as mensagens de <b>${esc(m ? m.apelido : 'quem você silenciou')}</b> (só neste aparelho).`);
            abrirPainel('chat', true);
            return;
        }
        if (e.target.closest('[data-chat-dessilenciar]')) { store.del(LS.chatSilencio); abrirPainel('chat', true); return; }
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
        const bSomSilenciar = e.target.closest('[data-som-silenciar]');
        if (bSomSilenciar) {
            som.alternar();
            atualizarBotaoSom();
            abrirPainel('som', true);
            return;
        }
        const bFaixa = e.target.closest('[data-faixa]');
        if (bFaixa) {
            som.trocarFaixa(Number(bFaixa.dataset.faixa));
            abrirPainel('som', true);
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

    el.painelCorpo.addEventListener('submit', (e) => {   // fase 53: busca do painel de admin
        if (!e.target.closest('[data-admin-busca]')) return;
        e.preventDefault();
        adminBusca = (($('adminBusca') || {}).value || '').trim();
        adminBanindo = null;
        adminCodigo = null;
        carregarAdmin();
    });
    el.painelCorpo.addEventListener('change', (e) => {   // fase 50: trocar o item a anunciar na feira
        const sel = e.target.closest('[data-feira-item]');
        if (sel) { feiraItem = sel.value; abrirPainel('feira', true); }
        const ci = e.target.closest('[data-chat-item]');   // fase 67: o item do pedido no chat
        if (ci) { chatPedidoItem = ci.value; abrirPainel('chat', true); }
    });
    el.painelCorpo.addEventListener('submit', (e) => {   // fase 67: enviar no chat
        if (!e.target.closest('[data-chat-form]')) return;
        e.preventDefault();
        enviarChat();
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
        btnSom.setAttribute('aria-label', som.mudo ? 'Ligar sons ou ajustar volume' : 'Ajustar som e música');
    }
    btnSom.addEventListener('click', () => {
        som.desbloquear();
        abrirPainel('som');
    });
    atualizarBotaoSom();

    // Controles de volume em tempo real (arrastar o slider)
    el.painelCorpo.addEventListener('input', (e) => {
        if (e.target.id === 'rngVolMusica') {
            const val = Number(e.target.value) || 0;
            som.definirVolMusica(val);
            const txt = $('txtVolMusica');
            if (txt) txt.textContent = val + '%';
        } else if (e.target.id === 'rngVolEfeitos') {
            const val = Number(e.target.value) || 0;
            som.definirVolEfeitos(val);
            const txt = $('txtVolEfeitos');
            if (txt) txt.textContent = val + '%';
        }
    });
    el.painelCorpo.addEventListener('change', (e) => {
        if (e.target.id === 'rngVolEfeitos') {
            som.tocar('moeda');
        }
    });

    /* ---------- tutorial (primeira vez na fazenda) ---------- */
    const TUTORIAL = [
        { texto: 'Bem-vindo(a)! Toque num canteiro de <b>terra escura</b> (já arado) para plantar alface.', ate: ['plantar'] },
        { texto: 'Plantou! A alface fica pronta em 5 minutos, mesmo com a página fechada. Enquanto isso, espie a <b>Loja</b> lá em cima.', ate: ['loja', 'colher'] },
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
    $('hudDiamantesBtn').addEventListener('click', () => {
        if (!S || visita) return;
        abaLoja = 'diamantes';
        abrirPainel('loja');
    });
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
            constr.voltar = null;
            desenharPaleta();
            atualizarModo();
            mostrarStatus(it.id === 'canteiro'
                ? `${A.htmlItem('canteiro', 22)} Canteiro: toque nos quadrados livres (sobram ${canteirosLivres()}). Lado a lado eles viram fileiras.`
                : `${A.htmlItem(it.id, 22)} ${esc(it.nome)} (${cercadoGratis(it) ? 'o seu sai de graça' : moeda(it.custo)})${it.descricao ? ': ' + esc(it.descricao) : ''} Toque nos quadrados livres.`);
            return;
        }
        const ferr = e.target.closest('[data-ferramenta]');
        if (ferr) {
            if (ferr.dataset.ferramenta === 'pronto') return fecharConstrucao();
            constr.modo = ferr.dataset.ferramenta;
            constr.movendo = null;
            constr.voltar = null;
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
        const g = $('googleEntrar');
        if (g && GOOGLE_CLIENT_ID) { g.hidden = false; botaoGoogle($('googleEntrarBotao'), 'entrar'); }
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
        fecharMar();   // fase 62
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
        // o botão do Google é desenhado de novo com a aba à mostra (escondido ele pode sair sem largura)
        if (b.dataset.aba === 'codigo' && GOOGLE_CLIENT_ID) botaoGoogle($('googleEntrarBotao'), 'entrar');
    }));

    async function enviarEntrada(form, fn, args, aoEntrar) {
        const btn = form.querySelector('button');
        btn.disabled = true;
        clearTimeout(tentarDeNovo);
        mostrarErroEntrada('');
        try {
            const r = await rpc(fn, args);
            if (!r || !r.token) throw Object.assign(new Error(ERROS[r && r.message] || 'Algo deu errado na fazenda.'), { code: r && r.message });
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
        if (S.clima && A.faseDoDia(agora()).noite !== noiteMostrada) desenharClima();   // virou o dia ou a noite
        if (painelAtual === 'oficina') {
            const c = oficinaDoPainel(), o = c && infoOficina(c), alvo = el.painelCorpo.querySelector('[data-oficina-agora]');
            if (o && alvo) alvo.innerHTML = htmlOficinaAgora(o);
        }
        if (painelAtual === 'canteiro') {   // menu da planta: a barra anda e, quando amadurece, vira "Colher"
            const i = info(canteiro(menuCanteiro)), alvo = el.painelCorpo.querySelector('[data-canteiro-agora]');
            if (alvo && i.fase === 'crescendo') alvo.innerHTML = htmlCanteiroAgora(i);
            else if (alvo) abrirPainel('canteiro', true);
        }
        if (document.visibilityState === 'visible' && Date.now() - ultimoPoll > intervaloBusca()) {
            ultimoPoll = Date.now();
            recarregar();
        }
    }, 1000);

    document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible' && S) {
            ultimoPoll = mexeuEm = Date.now();
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
        abrirFazendaSalva(0);
    })();

    // Abre a fazenda do token salvo. Servidor lento ou fora do ar não é sessão expirada: fica na
    // porteira tentando de novo (10 s, 20 s, 40 s, depois de minuto em minuto) em vez de cair na
    // tela de entrada, que parecia "deslogou".
    let tentarDeNovo = null;
    async function abrirFazendaSalva(tentativa) {
        clearTimeout(tentarDeNovo);
        el.entradaCarregando.hidden = false;
        el.entradaCarregando.textContent = tentativa ? 'Tentando de novo…' : 'Abrindo a porteira…';
        try {
            aplicarEstado(await rpc('fazenda_carregar', { p_token: token }));
        } catch (e) {
            if (saiuDoJogo(e) || !token) {
                if (token) sair(false);
                mostrarEntrada();
                return mostrarErroEntrada(e.message);
            }
            const espera = Math.min(60, 10 * 2 ** tentativa);
            el.entradaCarregando.innerHTML = `<p>${esc(e.message)}</p><p>Sua fazenda está guardada. Tentando de novo em ${espera} s…</p>
                <p><button type="button" class="botao pequeno verde" data-tentar-agora>Tentar agora</button>
                <button type="button" class="botao pequeno creme" data-entrar-codigo>Entrar com o código</button></p>`;
            tentarDeNovo = setTimeout(() => abrirFazendaSalva(tentativa + 1), espera * 1000);
            return;
        }
        mostrarFazenda();
        if (compraDoLink) acompanharCompra(compraDoLink);
        if (conviteDoLink) {
            store.del(LS.convite);
            toast('Esse convite é para quem ainda não tem fazenda. Você pode chamar os seus amigos pelo Perfil!');
        }
        const salvo = store.get(LS.tutorial);
        if (salvo !== null && salvo !== 'feito') { passoTutorial = Number(salvo) || 0; mostrarPasso(); }
    }
    el.entradaCarregando.addEventListener('click', (e) => {
        if (e.target.closest('[data-tentar-agora]')) abrirFazendaSalva(0);
        else if (e.target.closest('[data-entrar-codigo]')) { clearTimeout(tentarDeNovo); mostrarEntrada(); }
    });
})();
