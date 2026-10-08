/* ============================================================
   TERMINAL SECRETO — easter egg do portfólio (versão 2, PC e celular)
   Carregado sob demanda pelo indexversao2.html no 5º clique/toque no ">_"
   do rodapé. Expõe window.TERMINAL.abrir().
   Comandos: "farm"/"fazenda" leva para a Fazendinha; "pong" abre o
   Pong (window.abrirPong, do carregador da página).
============================================================ */
(function () {
    'use strict';

    const COMANDOS = {
        help: () => ['comandos: help, ls, cat <arquivo>, whoami, pong, clear, exit', 'o comando secreto tem a ver com plantar...'],
        ls: () => ['projetos/   curriculo.pdf   segredo.txt   fazenda/'],
        whoami: () => ['visitante (por enquanto)'],
        sudo: () => [['boa tentativa.', 'erro']],
        'cat segredo.txt': () => ['"algo cresce escondido no campo deste portfólio."', 'dica: em inglês, 4 letras.'],
        'cat curriculo.pdf': () => ['%PDF-1.7 ... binário. melhor abrir pelo menu, rs'],
        'cd fazenda': () => ['permissão negada: use o comando secreto.']
    };

    function abrir() {
        const tela = document.createElement('div');
        tela.className = 'term-tela';
        tela.setAttribute('role', 'dialog');
        tela.setAttribute('aria-label', 'Terminal secreto');
        tela.setAttribute('data-lenis-prevent', '');
        tela.innerHTML = '<button type="button" class="term-fechar">x</button><div class="term-saida"></div>' +
            '<label class="term-prompt" hidden><span>visitante@portfolio:~$</span>' +
            '<input type="text" autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false" enterkeyhint="go" aria-label="Comando"></label>';
        document.body.appendChild(tela);
        document.body.style.overflow = 'hidden';
        const saida = tela.querySelector('.term-saida');
        const prompt = tela.querySelector('.term-prompt');
        const entrada = prompt.querySelector('input');

        const fechar = () => { tela.remove(); document.body.style.overflow = ''; document.removeEventListener('keydown', esc); };
        const esc = (e) => { if (e.key === 'Escape') fechar(); };   // no PC, Esc fecha
        document.addEventListener('keydown', esc);
        tela.querySelector('.term-fechar').addEventListener('click', fechar);
        tela.addEventListener('click', (e) => { if (e.target === tela || e.target === saida) entrada.focus(); });

        const escrever = (texto, classe) => {
            const l = document.createElement('div');
            l.className = 'term-linha' + (classe ? ' ' + classe : '');
            l.textContent = texto;
            saida.appendChild(l);
            tela.scrollTop = tela.scrollHeight;
        };
        const pausa = (ms) => new Promise((ok) => setTimeout(ok, ms));
        async function digitar(texto, classe, velocidade = 18) {
            const l = document.createElement('div');
            l.className = 'term-linha' + (classe ? ' ' + classe : '');
            saida.appendChild(l);
            for (const ch of texto) { l.textContent += ch; await pausa(velocidade); }
            tela.scrollTop = tela.scrollHeight;
        }

        (async () => {
            await digitar('> conectando em carlos@portfolio ...');
            await pausa(250);
            await digitar('> handshake ok. canal criptografado.');
            await digitar('> ACESSO RESTRITO. digite o comando secreto.', 'erro');
            await digitar('> não sabe? tente "help".');
            prompt.hidden = false;
            entrada.focus();
        })();

        entrada.addEventListener('keydown', async (e) => {
            if (e.key !== 'Enter') return;
            const bruto = entrada.value.trim();
            const cmd = bruto.toLowerCase();
            entrada.value = '';
            escrever('visitante@portfolio:~$ ' + bruto);
            if (!cmd) return;
            if (cmd === 'clear') { saida.innerHTML = ''; return; }
            if (cmd === 'exit') { fechar(); return; }
            if (cmd === 'pong' && window.abrirPong) {
                await digitar('> iniciando PONG.EXE ...', 'ok', 25);
                await pausa(300);
                fechar();
                window.abrirPong();
                return;
            }
            if (cmd === 'farm' || cmd === 'fazenda' || cmd === './farm') {
                prompt.hidden = true;
                await digitar('> ACESSO CONCEDIDO', 'ok', 40);
                await digitar('> carregando fazenda_secreta.exe [##########] 100%', null, 22);
                await pausa(350);
                window.location.href = 'fazenda.html';
                return;
            }
            const resposta = COMANDOS[cmd] || (cmd.startsWith('sudo') ? COMANDOS.sudo : null);
            if (resposta) resposta().forEach((r) => Array.isArray(r) ? escrever(r[0], r[1]) : escrever(r));
            else escrever('comando não encontrado: ' + bruto, 'erro');
        });
    }

    window.TERMINAL = { abrir };
})();
