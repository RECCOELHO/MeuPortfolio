/* ============================================================
   PONG SECRETO — easter egg do portfólio (versão 2)
   Carregado sob demanda pelo indexversao2.html (5 cliques no logo
   "CJ." ou o comando "pong" no terminal secreto). Expõe window.PONG.
   Também roda sozinho em pong.html (versão instalável, PWA): lá a
   página define window.PONG_APP e o ✕ volta ao menu em vez de fechar.
============================================================ */
(function () {
    'use strict';

    const APP = !!window.PONG_APP;

    // HTML do jogo (antes ficava escondido dentro da página)
    document.body.insertAdjacentHTML('beforeend', `
<!-- ===== EASTER EGG: PONG GAME ===== -->
<div id="hack-overlay" data-lenis-prevent role="dialog" aria-modal="true" aria-label="Pong Game">
    <div class="hack-terminal" id="hackTerminal">
        <div class="hack-bar">
            <span class="hack-dot r"></span>
            <span class="hack-dot y"></span>
            <span class="hack-dot g"></span>
            <span class="hack-bar-title">PONG.EXE — ARCADE SYSTEM v1.0</span>
            <button class="hack-close" id="hackClose" aria-label="Fechar">✕</button>
        </div>
        <div class="hack-body">

            <!-- INTRO -->
            <div class="hack-screen active" id="screenIntro">
                <div class="hack-intro-logo">PING<br><em>PONG.</em></div>
                <div class="hack-intro-sub">// EASTER EGG DESBLOQUEADO</div>
                <div class="hack-intro-lines">
                    <div class="hack-intro-line">> Modo: <span class="acc">Jogador vs CPU</span></div>
                    <div class="hack-intro-line">> Controles: <span class="acc">W / S</span> ou <span class="acc">↑
                            / ↓</span></div>
                    <div class="hack-intro-line">> Celular: <span class="acc2">jogue deitado</span> e deslize o polegar na trilha ao lado do campo</div>
                    <div class="hack-intro-line">> Pause: <span class="acc">ESPAÇO</span></div>
                    <div class="hack-intro-line">> Primeiro a <span class="acc">7 pontos</span> vence.</div>
                </div>
                <div style="display:flex;gap:0.8rem;align-items:center;margin-top:1.5rem;flex-wrap:wrap;">
                    <button class="hack-start-btn" id="hackStartBtn">INICIAR PARTIDA →</button>
                    <button class="hack-result-btn" id="hackRankingBtnIntro"
                        style="margin:0;padding:0.75rem 1.4rem;border-color:rgba(200,240,68,0.25);color:#c8f044;font-size:0.72rem;">🏆
                        VER RANKING</button>
                    <button class="hack-result-btn" id="hackInstalarBtn"
                        style="margin:0;padding:0.75rem 1.4rem;border-color:rgba(68,240,200,0.25);color:#44f0c8;font-size:0.72rem;">📲
                        INSTALAR APP</button>
                </div>
                <div class="hack-intro-line" id="hackInstalarDica" style="margin-top:0.9rem;" hidden></div>
            </div>

            <!-- GAME -->
            <div class="hack-screen" id="screenGame">
                <div class="pong-scoreboard">
                    <div class="pong-score-side">
                        <div class="pong-score-num player" id="pScoreEl">0</div>
                        <div class="pong-score-lbl">Você</div>
                    </div>
                    <div class="pong-center">
                        <div class="pong-to-win">Primeiro a <span>7</span></div>
                        <button type="button" class="pong-pause" id="pongPauseBtn" aria-label="Pausar">II</button>
                    </div>
                    <div class="pong-score-side">
                        <div class="pong-score-num ai" id="aScoreEl">0</div>
                        <div class="pong-score-lbl">CPU</div>
                    </div>
                </div>
                <div class="pong-campo" id="pongCampo">
                    <!-- celular: trilhas fora do campo para o dedo não tampar a bola (arraste como um touchpad) -->
                    <div class="pong-joy" data-lado="esq" aria-label="Controle da raquete (esquerda)">
                        <div class="pong-joy-trilho"><div class="pong-joy-botao"></div></div>
                    </div>
                    <canvas id="pongCanvas" width="600" height="300"></canvas>
                    <div class="pong-joy" data-lado="dir" aria-label="Controle da raquete">
                        <div class="pong-joy-trilho"><div class="pong-joy-botao"></div></div>
                    </div>
                </div>
                <div class="pong-controls-bar">
                    <div class="pong-key-hint so-teclado"><span class="pong-key">W</span><span class="pong-key">S</span> mover
                    </div>
                    <div class="pong-key-hint so-teclado"><span class="pong-key">↑</span><span class="pong-key">↓</span> mover
                    </div>
                    <div class="pong-key-hint so-teclado"><span class="pong-key">ESPAÇO</span> pausar</div>
                    <div class="pong-key-hint so-toque">use a trilha fora do campo (ou arraste no campo) para mover a raquete</div>
                </div>
            </div>

            <!-- RESULT -->
            <div class="hack-screen" id="screenResult">
                <div class="hack-result">
                    <div class="hack-result-title success glitch" id="resultTitle" data-text="VITÓRIA!">VITÓRIA!
                    </div>
                    <div class="hack-result-sub" id="resultSub">PLACAR FINAL</div>
                    <div class="hack-result-grid">
                        <div class="hack-result-stat"><span class="num" id="rPlayer">0</span><span
                                class="lbl">Você</span></div>
                        <div class="hack-result-stat"><span class="num" id="rCpu">0</span><span
                                class="lbl">CPU</span></div>
                        <div class="hack-result-stat"><span class="num" id="rTime">0s</span><span
                                class="lbl">Tempo</span></div>
                    </div>
                    <div class="hack-result-grade" id="rGrade" style="color:#c8f044">S</div>
                    <!-- Campo de nome para salvar -->
                    <div class="hack-name-group">
                        <span class="hack-name-label">// seu nome para o ranking</span>
                        <input class="hack-name-input" id="playerNameInput" type="text" maxlength="20"
                            placeholder="Digite seu nome..." autocomplete="off">
                    </div>
                    <div class="hack-save-status" id="saveStatus"></div>
                    <div class="hack-result-btns">
                        <button class="hack-result-btn primary" id="hackRetry">JOGAR NOVAMENTE</button>
                        <button class="hack-result-btn primary" id="hackSaveBtn">SALVAR NO RANKING</button>
                        <button class="hack-result-btn" id="hackRankingBtn">🏆 VER RANKING</button>
                        <button class="hack-result-btn" id="hackShareBtn">COMPARTILHAR</button>
                    </div>
                </div>
            </div>

            <!-- LEADERBOARD -->
            <div class="hack-screen" id="screenLeaderboard">
                <div class="lb-wrap">
                    <div class="lb-header">
                        <span class="lb-title">🏆 RANKING — TOP 20</span>
                        <button class="hack-result-btn" id="lbBackBtn"
                            style="padding:0.28rem 0.75rem;font-size:0.6rem;white-space:nowrap;">← VOLTAR</button>
                    </div>
                    <div class="lb-body">
                        <div class="lb-row lb-head">
                            <span style="text-align:center">#</span>
                            <span>NOME</span>
                            <span style="text-align:center">PLACAR</span>
                            <span style="text-align:center">NOTA</span>
                            <span style="text-align:right">TEMPO</span>
                        </div>
                        <div id="leaderboardRows">
                            <div class="lb-loading">
                                <div class="lb-spinner"></div> Carregando...
                            </div>
                        </div>
                    </div>
                </div>
            </div>

        </div>
    </div>
</div>
`);

    /* ============================================================
       SUPABASE CONFIG
       → Preencha com seus dados em supabase.com > Project Settings > API
    ============================================================ */
    // em localhost dá pra apontar para um backend de teste: indexversao2.html?api=http://localhost:8787
    const SUPABASE_URL = (/^(localhost|127\.0\.0\.1)$/.test(location.hostname) && new URLSearchParams(location.search).get('api'))
        || 'https://vhdjqppzylxdksgjzvsh.supabase.co';
    const SUPABASE_KEY = 'sb_publishable_y-rrBFvf0QRFG3WL3P0kxQ_gItonE2U';

    /* Ranking do Pong: funções pong_salvar / pong_ranking (ver supabase/pong.sql).
       A nota é recalculada no servidor a partir do placar. */
    async function pongRpc(fn, args) {
        const res = await fetch(SUPABASE_URL + '/rest/v1/rpc/' + fn, {
            method: 'POST',
            headers: {
                'apikey': SUPABASE_KEY,
                'Authorization': 'Bearer ' + SUPABASE_KEY,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(args || {})
        });
        const data = await res.json().catch(() => null);
        if (!res.ok) throw new Error((data && data.message) || 'erro');
        return data;
    }

    async function saveScore(nome, jogador, cpu, tempoSeg) {
        try {
            return await pongRpc('pong_salvar', { p_nome: nome, p_jogador: jogador, p_cpu: cpu, p_tempo: tempoSeg });
        } catch (e) { return { erro: e.message }; }
    }

    async function loadLeaderboard() {
        try { return await pongRpc('pong_ranking'); } catch { return null; }
    }

    (function () {
        /* --- DOM refs --- */
        const overlay = document.getElementById('hack-overlay');
        const closeBtn = document.getElementById('hackClose');
        const startBtn = document.getElementById('hackStartBtn');
        const retryBtn = document.getElementById('hackRetry');
        const shareBtn = document.getElementById('hackShareBtn');
        const saveBtn = document.getElementById('hackSaveBtn');
        const rankingBtn = document.getElementById('hackRankingBtn');
        const rankingBtnIntro = document.getElementById('hackRankingBtnIntro');
        const lbBackBtn = document.getElementById('lbBackBtn');
        const nameInput = document.getElementById('playerNameInput');
        const saveStatus = document.getElementById('saveStatus');
        const lbRows = document.getElementById('leaderboardRows');
        const screenIntro = document.getElementById('screenIntro');
        const screenGame = document.getElementById('screenGame');
        const screenResult = document.getElementById('screenResult');
        const screenLeaderboard = document.getElementById('screenLeaderboard');
        const pScoreEl = document.getElementById('pScoreEl');
        const aScoreEl = document.getElementById('aScoreEl');

        /* Estado interno para saber de onde o ranking foi aberto */
        let lbPreviousScreen = screenResult;

        /* --- Game constants --- */
        const CW = 600, CH = 300;
        const PW = 12, PH = 72;
        const BR = 7;
        const PX_L = 18;
        const PX_R = CW - PX_L - PW;
        const WINNING = 7;
        const P_SPEED = 380;
        const AI_BASE = 170;
        const BALL_BASE = 260;
        const TRAIL_LEN = 10;

        /* --- State --- */
        let canvas, ctx;
        let playerY, aiY, ballX, ballY, ballVX, ballVY;
        let pScore, aScore, rally, gameStartTime;
        let running, paused, resetting, gameOver;
        let animId, lastTimestamp;
        let keyUp = false, keyDown = false;
        let trail = [];
        let flashAlpha = 0, flashSide = null;
        let countdownTimer = null;

        const hackBody = document.querySelector('.hack-body');

        /* --- Screen management --- */
        const allScreens = [screenIntro, screenGame, screenResult, screenLeaderboard];
        function showScreen(el) {
            allScreens.forEach(s => s.classList.remove('active'));
            el.classList.add('active');
            // Toggle padding-free mode for leaderboard
            if (el === screenLeaderboard) {
                hackBody.classList.add('lb-mode');
            } else {
                hackBody.classList.remove('lb-mode');
            }
        }

        /* --- Overlay controls --- */
        function openGame() {
            overlay.classList.add('open');
            document.body.classList.add('game-active');
            document.body.style.overflow = 'hidden';
            showScreen(screenIntro);
        }
        window.PONG = { abrir: openGame };   // o carregador da página chama isto
        function closeGame() {
            if (APP) { stopLoop(); showScreen(screenIntro); return; }   // no app não tem "fora" para onde fechar
            overlay.classList.remove('open');
            document.body.classList.remove('game-active');
            document.body.style.overflow = '';
            stopLoop();
        }

        closeBtn.addEventListener('click', closeGame);
        overlay.addEventListener('click', (e) => { if (e.target === overlay && !APP) closeGame(); });

        /* --- Instalar como app (PWA) ---
           No portfólio o botão leva para pong.html, a página instalável;
           lá ele abre o pedido de instalação (ou explica como fazer). */
        const instalarBtn = document.getElementById('hackInstalarBtn');
        const instalarDica = document.getElementById('hackInstalarDica');
        const instalador = window.INSTALAR;
        function atualizarInstalar() {
            instalarBtn.hidden = APP && (!instalador || instalador.estado() === 'instalado');
        }
        atualizarInstalar();
        if (instalador) instalador.aoMudar(atualizarInstalar);
        instalarBtn.addEventListener('click', () => {
            if (!APP) { stopLoop(); window.location.href = 'pong.html'; return; }
            if (instalador.estado() === 'pronto') { instalador.instalar(); return; }
            instalarDica.textContent = '> ' + instalador.dica();
            instalarDica.hidden = false;
        });

        document.addEventListener('keydown', (e) => {
            if (!overlay.classList.contains('open')) return;
            if (e.key === 'Escape') { closeGame(); return; }
            if (e.key === 'Enter' && screenIntro.classList.contains('active')) startGame();
            if (e.key === ' ' && screenGame.classList.contains('active')) { alternarPausa(); e.preventDefault(); }
            if (e.key === 'ArrowUp' || e.key === 'w' || e.key === 'W') { keyUp = true; e.preventDefault(); }
            if (e.key === 'ArrowDown' || e.key === 's' || e.key === 'S') { keyDown = true; e.preventDefault(); }
        });
        document.addEventListener('keyup', (e) => {
            if (e.key === 'ArrowUp' || e.key === 'w' || e.key === 'W') keyUp = false;
            if (e.key === 'ArrowDown' || e.key === 's' || e.key === 'S') keyDown = false;
        });

        startBtn.addEventListener('click', startGame);
        retryBtn.addEventListener('click', () => { stopLoop(); startGame(); });

        /* --- Salvar no ranking --- */
        if (saveBtn) {
            saveBtn.addEventListener('click', async () => {
                const nome = nameInput.value.trim();
                if (!nome) {
                    saveStatus.textContent = '⚠ Digite seu nome primeiro!';
                    saveStatus.className = 'hack-save-status err';
                    nameInput.focus();
                    return;
                }
                saveBtn.disabled = true;
                saveBtn.textContent = 'SALVANDO...';
                saveStatus.textContent = '';
                saveStatus.className = 'hack-save-status';

                const r = await saveScore(nome, pScore, aScore, ultimoTempo);
                if (r && !r.erro) {
                    saveStatus.textContent = `✓ SALVO! VOCÊ É O ${r.posicao}º DO RANKING.`;
                    saveStatus.className = 'hack-save-status ok';
                    saveBtn.textContent = 'SALVO ✓';
                } else {
                    const motivos = {
                        nome_invalido: 'NOME INVÁLIDO (1 A 20 LETRAS).',
                        muitos_envios: 'MUITOS ENVIOS AGORA. ESPERE UM POUCO.',
                        placar_invalido: 'PLACAR INVÁLIDO.',
                        tempo_invalido: 'TEMPO INVÁLIDO.'
                    };
                    saveStatus.textContent = '✕ ' + (motivos[r && r.erro] || 'FALHA AO SALVAR. TENTE NOVAMENTE.');
                    saveStatus.className = 'hack-save-status err';
                    saveBtn.disabled = false;
                    saveBtn.textContent = 'SALVAR NO RANKING';
                }
            });
        }

        /* --- Ver Ranking (da tela de resultado) --- */
        if (rankingBtn) {
            rankingBtn.addEventListener('click', () => {
                lbPreviousScreen = screenResult;
                openLeaderboard();
            });
        }

        /* --- Ver Ranking (da tela de intro) --- */
        if (rankingBtnIntro) {
            rankingBtnIntro.addEventListener('click', () => {
                lbPreviousScreen = screenIntro;
                openLeaderboard();
            });
        }

        /* --- Voltar do ranking --- */
        if (lbBackBtn) {
            lbBackBtn.addEventListener('click', () => showScreen(lbPreviousScreen));
        }

        async function openLeaderboard() {
            showScreen(screenLeaderboard);
            lbRows.innerHTML = '<div class="lb-loading"><div class="lb-spinner"></div> Carregando...</div>';
            const data = await loadLeaderboard();
            if (data === null) {
                lbRows.innerHTML = '<div class="lb-empty">Não deu para carregar o ranking.<br>Tente de novo em instantes.</div>';
                return;
            }
            if (!data.length) {
                lbRows.innerHTML = '<div class="lb-empty">Nenhuma partida registrada ainda.<br>Seja o primeiro! 🏆</div>';
                return;
            }
            // Os dados vêm de um banco em que qualquer visitante grava: escapa tudo antes de montar o HTML
            const esc = v => String(v == null ? '' : v).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
            const gradeColors = { S: '#c8f044', A: '#44f0c8', B: '#e8e8f0', C: '#febc2e', D: '#febc2e', F: '#ff5f57' };
            const medals = ['🥇', '🥈', '🥉'];
            const rankClass = ['gold', 'silver', 'bronze'];
            lbRows.innerHTML = data.map((r, i) => {
                const rk = i < 3
                    ? `<span class="lb-rank ${rankClass[i]}">${medals[i]}</span>`
                    : `<span class="lb-rank">${i + 1}</span>`;
                const notaRaw = String(r.nota || '').replace(/[^A-Za-z]/g, '') || '?';
                const gc = gradeColors[notaRaw] || '#e8e8f0';
                return `
            <div class="lb-row">
                ${rk}
                <span class="lb-nome">${esc(r.nome)}</span>
                <span class="lb-placar"><b class="lb-p">${esc(r.jogador)}</b><i>×</i><b class="lb-c">${esc(r.cpu)}</b></span>
                <span class="lb-nota" style="color:${gc}">${notaRaw}</span>
                <span class="lb-tempo">${esc(r.tempo)}s</span>
            </div>`;
            }).join('');
        }

        /* --- Tamanho do campo ---
           A lógica do jogo é sempre "deitada" (600 x 300). Com o celular em pé
           o campo é desenhado girado: você embaixo, a CPU em cima. */
        let vertical = false, dpr = 1, ultimoTempo = 0;
        const pauseBtn = document.getElementById('pongPauseBtn');
        const ehToque = window.matchMedia('(hover: none) and (pointer: coarse)');
        const campo = document.getElementById('pongCampo');
        const trilhas = [...document.querySelectorAll('.pong-joy')];

        // celular deitado: tela cheia; em pé: campo vertical com a trilha embaixo
        function atualizarModoTela() {
            const toque = ehToque.matches;
            overlay.classList.toggle('toque', toque);
            overlay.classList.toggle('toque-deitado', toque && window.innerWidth > window.innerHeight);
        }
        atualizarModoTela();

        function ajustarCanvas() {
            if (!canvas) return;
            atualizarModoTela();
            vertical = window.innerHeight > window.innerWidth && window.innerWidth <= 820;
            dpr = Math.min(window.devicePixelRatio || 1, 3);
            canvas.classList.toggle('vertical', vertical);
            campo.classList.toggle('retrato', vertical);
            canvas.width = (vertical ? CH : CW) * dpr;
            canvas.height = (vertical ? CW : CH) * dpr;
            // deitado no celular: o campo inteiro cabe na altura que sobra (nada fica fora da tela)
            if (overlay.classList.contains('toque-deitado')) {
                const area = campo.getBoundingClientRect();
                // trilhas estreitas (64–96 px); o campo fica com todo o resto
                const lateral = Math.round(Math.min(96, Math.max(64, area.width * 0.1)));
                campo.style.setProperty('--joy-largura', lateral + 'px');
                const h = Math.floor(Math.min(area.height - 6, (area.width - lateral * 2 - 12) / 2));
                if (h < 60) return;   // tela ainda montando; o observador chama de novo
                canvas.style.height = h + 'px';
                canvas.style.width = (h * 2) + 'px';
            } else {
                canvas.style.height = '';
                canvas.style.width = '';
            }
        }
        function atualizarJoy() {
            const p = playerY / (CH - PH);   // 0 = começo da trilha, 1 = fim
            for (const t of trilhas) {
                const b = t.querySelector('.pong-joy-botao');
                // a bolinha (46px) fica sempre dentro da trilha
                const r = (b.offsetWidth || 46) / 2;
                const pos = 'calc(' + r + 'px + ' + p.toFixed(4) + ' * (100% - ' + (2 * r) + 'px))';
                if (vertical) { b.style.left = pos; b.style.top = ''; }
                else { b.style.top = pos; b.style.left = ''; }
            }
        }
        const aoGirar = () => { atualizarModoTela(); if (running) requestAnimationFrame(ajustarCanvas); };
        if (window.ResizeObserver) new ResizeObserver(() => { if (running) ajustarCanvas(); }).observe(campo);
        window.addEventListener('resize', aoGirar);
        window.addEventListener('orientationchange', aoGirar);

        /* --- Start / Stop --- */
        function startGame() {
            canvas = document.getElementById('pongCanvas');
            ctx = canvas.getContext('2d');
            showScreen(screenGame);
            ajustarCanvas();
            requestAnimationFrame(ajustarCanvas);   // de novo depois do layout da tela de jogo

            pScore = 0; aScore = 0;
            rally = 0;
            running = true; paused = false; resetting = false; gameOver = false;
            gameStartTime = Date.now();
            trail = [];
            flashAlpha = 0;
            pauseBtn.textContent = 'II';

            playerY = CH / 2 - PH / 2;
            aiY = CH / 2 - PH / 2;
            updateScoreDisplay();

            screenGame.addEventListener('pointerdown', onPointer);
            screenGame.addEventListener('pointermove', onPointer);
            screenGame.addEventListener('pointerup', soltarJoy);
            screenGame.addEventListener('pointercancel', soltarJoy);
            serveBall(Math.random() > 0.5 ? 1 : -1, true);
            lastTimestamp = performance.now();
            animId = requestAnimationFrame(loop);
        }
        function stopLoop() {
            running = false;
            if (animId) cancelAnimationFrame(animId);
            clearTimeout(countdownTimer);
            screenGame.removeEventListener('pointerdown', onPointer);
            screenGame.removeEventListener('pointermove', onPointer);
            screenGame.removeEventListener('pointerup', soltarJoy);
            screenGame.removeEventListener('pointercancel', soltarJoy);
            keyUp = false; keyDown = false;
            arraste = null;
        }

        /* --- Controle ---
           Trilha: arraste relativo, como um touchpad. O polegar pode começar em
           qualquer ponto; a raquete anda o quanto o dedo desliza (com ganho, para
           não precisar percorrer a trilha toda). No campo: a raquete vai até o dedo. */
        const GANHO = 1.5;
        let arraste = null;   // { id, inicio, base, tamanho }
        function soltarJoy(e) { if (arraste && (!e || e.pointerId === arraste.id)) arraste = null; }

        function onPointer(e) {
            if (e.target.closest('button')) return;
            if (e.cancelable) e.preventDefault();
            const zona = e.target.closest('.pong-joy');
            if (e.type === 'pointerdown' && zona) {
                const r = zona.getBoundingClientRect();
                arraste = {
                    id: e.pointerId,
                    inicio: vertical ? e.clientX : e.clientY,
                    base: playerY,
                    tamanho: vertical ? r.width : r.height
                };
                try { zona.setPointerCapture(e.pointerId); } catch { /* ignora */ }
                return;
            }
            if (arraste) {
                if (e.pointerId !== arraste.id) return;
                const d = (vertical ? e.clientX : e.clientY) - arraste.inicio;
                playerY = Math.max(0, Math.min(CH - PH, arraste.base + d * (CH / arraste.tamanho) * GANHO));
                return;
            }
            if (zona || (e.type === 'pointermove' && e.pointerType !== 'mouse' && e.buttons === 0)) return;
            const rect = canvas.getBoundingClientRect();
            // em pé, a raquete anda na horizontal (eixo x da tela)
            const pos = vertical
                ? (e.clientX - rect.left) * (CH / rect.width)
                : (e.clientY - rect.top) * (CH / rect.height);
            playerY = Math.max(0, Math.min(CH - PH, pos - PH / 2));
        }

        function alternarPausa() {
            if (!running || gameOver) return;
            paused = !paused;
            pauseBtn.textContent = paused ? '▶' : 'II';
        }
        pauseBtn.addEventListener('click', alternarPausa);

        /* --- Ball serve --- */
        function serveBall(dir, immediate) {
            resetting = true;
            ballX = CW / 2; ballY = CH / 2;
            ballVX = 0; ballVY = 0;
            trail = [];
            const delay = immediate ? 400 : 800;
            countdownTimer = setTimeout(() => {
                if (!running || gameOver) return;
                const angle = (Math.random() * 30 - 15) * Math.PI / 180;
                const spd = BALL_BASE + rally * 8;
                ballVX = dir * spd * Math.cos(angle);
                ballVY = spd * Math.sin(angle);
                resetting = false;
            }, delay);
        }

        function updateScoreDisplay() {
            pScoreEl.textContent = pScore;
            aScoreEl.textContent = aScore;
        }

        /* --- Main Loop --- */
        function loop(ts) {
            if (!running) return;
            const dt = Math.min((ts - lastTimestamp) / 1000, 0.05);
            lastTimestamp = ts;
            if (!paused && !resetting) update(dt);
            draw();
            atualizarJoy();
            animId = requestAnimationFrame(loop);
        }

        /* --- Update --- */
        function update(dt) {
            if (keyUp) playerY = Math.max(0, playerY - P_SPEED * dt);
            if (keyDown) playerY = Math.min(CH - PH, playerY + P_SPEED * dt);

            const aiSpd = Math.min(AI_BASE + rally * 14, 320) * dt;
            const diff = (ballY - PH / 2) - aiY;
            aiY += Math.sign(diff) * Math.min(Math.abs(diff), aiSpd);
            aiY = Math.max(0, Math.min(CH - PH, aiY));

            trail.push({ x: ballX, y: ballY });
            if (trail.length > TRAIL_LEN) trail.shift();

            ballX += ballVX * dt;
            ballY += ballVY * dt;

            if (ballY - BR < 0) { ballY = BR; ballVY = Math.abs(ballVY); }
            if (ballY + BR > CH) { ballY = CH - BR; ballVY = -Math.abs(ballVY); }

            if (ballVX < 0 && ballX - BR <= PX_L + PW && ballX - BR >= PX_L - 5) {
                if (ballY + BR >= playerY && ballY - BR <= playerY + PH) {
                    ballX = PX_L + PW + BR + 1;
                    const rel = (ballY - (playerY + PH / 2)) / (PH / 2);
                    const angle = rel * 65 * Math.PI / 180;
                    const spd = Math.min(Math.hypot(ballVX, ballVY) + 18, 700);
                    ballVX = Math.abs(Math.cos(angle)) * spd;
                    ballVY = Math.sin(angle) * spd;
                    rally++;
                }
            }

            if (ballVX > 0 && ballX + BR >= PX_R && ballX + BR <= PX_R + PW + 5) {
                if (ballY + BR >= aiY && ballY - BR <= aiY + PH) {
                    ballX = PX_R - BR - 1;
                    const rel = (ballY - (aiY + PH / 2)) / (PH / 2);
                    const angle = rel * 65 * Math.PI / 180;
                    const spd = Math.min(Math.hypot(ballVX, ballVY) + 18, 700);
                    ballVX = -Math.abs(Math.cos(angle)) * spd;
                    ballVY = Math.sin(angle) * spd;
                    rally++;
                }
            }

            if (ballX + BR < 0) {
                aScore++; updateScoreDisplay();
                flashAlpha = 1; flashSide = 'ai';
                if (aScore >= WINNING) { gameOver = true; running = false; setTimeout(showResult, 900); }
                else { rally = 0; serveBall(1, false); }
            }
            if (ballX - BR > CW) {
                pScore++; updateScoreDisplay();
                flashAlpha = 1; flashSide = 'player';
                if (pScore >= WINNING) { gameOver = true; running = false; setTimeout(showResult, 900); }
                else { rally = 0; serveBall(-1, false); }
            }

            if (flashAlpha > 0) flashAlpha = Math.max(0, flashAlpha - 0.04);
        }

        /* --- Draw --- */
        function draw() {
            // em pé: gira o campo (x lógico vira o eixo vertical, você embaixo)
            if (vertical) ctx.setTransform(0, -dpr, dpr, 0, 0, CW * dpr);
            else ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
            ctx.clearRect(0, 0, CW, CH);
            ctx.fillStyle = '#0a0a0f';
            ctx.fillRect(0, 0, CW, CH);

            if (flashAlpha > 0) {
                ctx.globalAlpha = flashAlpha * 0.15;
                ctx.fillStyle = flashSide === 'player' ? '#c8f044' : '#44f0c8';
                ctx.fillRect(flashSide === 'player' ? 0 : CW / 2, 0, CW / 2, CH);
                ctx.globalAlpha = 1;
            }

            // paredes de cima e de baixo visíveis (antes a bola batia numa linha que não aparecia)
            ctx.fillStyle = 'rgba(200,240,68,0.35)';
            ctx.fillRect(0, 0, CW, 3);
            ctx.fillRect(0, CH - 3, CW, 3);

            ctx.setLineDash([8, 10]);
            ctx.strokeStyle = 'rgba(255,255,255,0.04)';
            ctx.lineWidth = 1;
            ctx.beginPath(); ctx.moveTo(CW / 2, 0); ctx.lineTo(CW / 2, CH); ctx.stroke();
            ctx.setLineDash([]);

            if (paused) {
                // texto sempre "em pé", mesmo com o campo girado
                ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
                const W = vertical ? CH : CW, H = vertical ? CW : CH;
                ctx.fillStyle = 'rgba(10,10,15,0.75)';
                ctx.fillRect(0, 0, W, H);
                ctx.fillStyle = '#c8f044';
                ctx.font = '700 20px Syne, sans-serif';
                ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
                ctx.fillText('PAUSADO', W / 2, H / 2 - 14);
                ctx.fillStyle = '#6b6b80';
                ctx.font = '400 10px DM Mono, monospace';
                ctx.fillText(ehToque.matches ? 'toque em ▶ para continuar' : 'ESPAÇO para continuar', W / 2, H / 2 + 12);
                return;
            }

            trail.forEach((pos, i) => {
                const t = i / TRAIL_LEN;
                ctx.globalAlpha = t * 0.35;
                ctx.fillStyle = '#c8f044';
                ctx.beginPath();
                ctx.arc(pos.x, pos.y, BR * t, 0, Math.PI * 2);
                ctx.fill();
            });
            ctx.globalAlpha = 1;

            if (!resetting) {
                ctx.shadowColor = '#c8f044';
                ctx.shadowBlur = 18;
                ctx.fillStyle = '#ffffff';
                ctx.beginPath();
                ctx.arc(ballX, ballY, BR, 0, Math.PI * 2);
                ctx.fill();
                ctx.shadowBlur = 0;
            } else {
                ctx.fillStyle = 'rgba(200,240,68,0.18)';
                ctx.beginPath();
                ctx.arc(CW / 2, CH / 2, BR + 4, 0, Math.PI * 2);
                ctx.fill();
            }

            ctx.shadowColor = '#c8f044';
            ctx.shadowBlur = 14;
            ctx.fillStyle = '#c8f044';
            ctx.beginPath();
            ctx.roundRect(PX_L, playerY, PW, PH, 3);
            ctx.fill();

            ctx.shadowColor = '#44f0c8';
            ctx.fillStyle = '#44f0c8';
            ctx.beginPath();
            ctx.roundRect(PX_R, aiY, PW, PH, 3);
            ctx.fill();
            ctx.shadowBlur = 0;
        }

        /* --- Result --- */
        function showResult() {
            /* Reset campos de salvar */
            nameInput.value = '';
            saveBtn.disabled = false;
            saveBtn.textContent = 'SALVAR NO RANKING';
            saveStatus.textContent = '';
            saveStatus.className = 'hack-save-status';

            const elapsed = Math.max(1, Math.round((Date.now() - gameStartTime) / 1000));
            ultimoTempo = elapsed;
            const won = pScore >= WINNING;

            const title = document.getElementById('resultTitle');
            title.textContent = won ? 'VITÓRIA!' : 'DERROTA!';
            title.setAttribute('data-text', won ? 'VITÓRIA!' : 'DERROTA!');
            title.className = 'hack-result-title glitch ' + (won ? 'success' : 'fail');
            document.getElementById('resultSub').textContent = won
                ? 'SISTEMA DOMINADO COM SUCESSO'
                : 'FIREWALL RESISTIU À INVASÃO';

            document.getElementById('rPlayer').textContent = pScore;
            document.getElementById('rCpu').textContent = aScore;
            document.getElementById('rTime').textContent = elapsed + 's';

            /* Botão salvar aparece sempre */
            saveBtn.style.display = '';

            let grade, gradeColor;
            if (won) {
                if (aScore === 0) { grade = 'S'; gradeColor = '#c8f044'; }
                else if (aScore <= 2) { grade = 'A'; gradeColor = '#44f0c8'; }
                else if (aScore <= 4) { grade = 'B'; gradeColor = '#e8e8f0'; }
                else if (aScore <= 5) { grade = 'C'; gradeColor = '#febc2e'; }
                else { grade = 'D'; gradeColor = '#febc2e'; }
            } else {
                grade = 'F'; gradeColor = '#ff5f57';
            }
            document.getElementById('rGrade').textContent = grade;
            document.getElementById('rGrade').style.color = gradeColor;
            showScreen(screenResult);
        }

        /* --- Share --- */
        if (shareBtn) {
            shareBtn.addEventListener('click', () => {
                const grade = document.getElementById('rGrade').textContent;
                const won = pScore >= WINNING;
                const text = `${won ? '🏓 Venci' : '💀 Perdi'} o Pong secreto do portfólio do @CarlosJesse!\n🎮 Placar: ${pScore} × ${aScore} · Grade ${grade}\nAche o Easter Egg em: carlosjessecoelho.vercel.app`;
                if (navigator.share) {
                    navigator.share({ text }).catch(() => { });
                } else if (navigator.clipboard) {
                    navigator.clipboard.writeText(text).then(() => {
                        shareBtn.textContent = 'COPIADO! ✓';
                        setTimeout(() => shareBtn.textContent = 'COMPARTILHAR', 2000);
                    });
                }
            });
        }
    })();
})();
