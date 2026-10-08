/* ============================================================
   TERMINAL SECRETO — easter egg do portfólio (versão 2, PC e celular)
   Carregado sob demanda pelo indexversao2.html no 5º clique/toque no ">_"
   do rodapé. Expõe window.TERMINAL.abrir().

   Tem um sistema de arquivos de mentira (ls, cd, cat, open), comandos
   sobre o Carlos (lidos da própria página: projetos, skills, links),
   joguinhos e segredos para achar (comando "segredos"). "farm" leva para
   a Fazendinha; o Pong fica escondido (ls -a, .arcade/pong.exe).
============================================================ */
(function () {
    'use strict';

    const guardar = {
        get(k) { try { return JSON.parse(localStorage.getItem(k)); } catch { return null; } },
        set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* ignora */ } }
    };
    const LS = { tema: 'terminal_tema', segredos: 'terminal_segredos', historico: 'terminal_historico' };

    const SEGREDOS = {
        fazenda: 'Achou a fazenda escondida',
        arcade: 'Entrou no fliperama abandonado',
        pong: 'Ligou o PONG.EXE',
        historico: 'Leu o histórico de outra pessoa',
        sudo: 'Tentou apagar tudo',
        matrix: 'Entrou na Matrix',
        adivinhe: 'Acertou o número secreto',
        konami: 'Digitou o código Konami'
    };
    const TEMAS = { verde: '#3dff7a', ambar: '#ffb641', azul: '#5ec8ff', rosa: '#ff6bd6', branco: '#e8e8f0' };
    const PIADAS = [
        'Meu código não tem bugs. Tem funcionalidades surpresa.',
        'Funciona na minha máquina. Então a gente manda a minha máquina pro cliente.',
        'Eu e o CSS temos um acordo: eu centralizo a div e ela finge que obedeceu.',
        'Deploy sexta às 18h não é coragem, é falta de amor-próprio.',
        'Testei em produção. Agora os usuários são o meu time de QA.',
        'Café é o compilador do programador: transforma sono em código.',
        'O PHP não morreu. Ele só está carregando a página.',
        'A diferença entre bug e feature é quem escreveu a documentação.',
        'Tenho 99 problemas e 98 são ponto e vírgula.',
        'Programar é 10% escrever código e 90% entender por que ele não funciona.',
        'Comentei o código tão bem que agora ele precisa de terapia.',
        '"É só uma alteraçãozinha" — frase que precede 3 dias de trabalho.'
    ];
    const KONAMI = ['ArrowUp', 'ArrowUp', 'ArrowDown', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'ArrowLeft', 'ArrowRight', 'b', 'a'];

    // dados do portfólio, lidos da própria página (assim o terminal nunca fica desatualizado)
    function dadosPagina() {
        const txt = (el) => (el ? el.textContent.replace(/\s+/g, ' ').trim() : '');
        const link = (re) => {
            const a = [...document.querySelectorAll('a[href]')].find((x) => re.test(x.href));
            return a ? a.href : '';
        };
        const projetos = [...document.querySelectorAll('.proj-card')].map((c) => ({
            nome: txt(c.querySelector('.proj-name')),
            desc: txt(c.querySelector('.proj-desc')),
            tags: [...c.querySelectorAll('.proj-tag')].map(txt),
            link: (c.querySelector('.proj-link') || {}).href || ''
        })).filter((p) => p.nome);
        const skills = [...document.querySelectorAll('.skills-grid .skill-item')].map((s) => ({
            nome: txt(s.querySelector('.skill-name')), nivel: txt(s.querySelector('.skill-level'))
        })).filter((s) => s.nome);
        return {
            projetos, skills,
            sobre: txt(document.querySelector('.hero-desc')),
            linkedin: link(/linkedin\.com/), github: link(/github\.com/),
            whatsapp: link(/wa\.me/).split('?')[0], cv: link(/cv-[^/]*\.pdf/)
        };
    }
    const slug = (s) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

    // distância de edição (para o "você quis dizer...?")
    function distancia(a, b) {
        const d = Array.from({ length: a.length + 1 }, (_, i) => [i]);
        for (let j = 1; j <= b.length; j++) d[0][j] = j;
        for (let i = 1; i <= a.length; i++) {
            for (let j = 1; j <= b.length; j++) {
                d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
            }
        }
        return d[a.length][b.length];
    }

    function abrir() {
        if (document.querySelector('.term-tela')) return;
        const dados = dadosPagina();
        let tema = TEMAS[guardar.get(LS.tema)] ? guardar.get(LS.tema) : 'verde';
        let cwd = '~';
        let modo = null;        // joguinho em andamento (adivinhe)
        let ocupado = true;     // animação rodando: não aceita comando
        const historico = guardar.get(LS.historico) || [];
        let posHist = historico.length;
        const achados = new Set(guardar.get(LS.segredos) || []);
        let konami = 0;

        const tela = document.createElement('div');
        tela.className = 'term-tela';
        tela.setAttribute('role', 'dialog');
        tela.setAttribute('aria-label', 'Terminal secreto');
        tela.setAttribute('data-lenis-prevent', '');
        tela.innerHTML = '<button type="button" class="term-fechar" aria-label="Fechar">x</button><div class="term-saida"></div>' +
            '<label class="term-prompt" hidden><span></span>' +
            '<input type="text" autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false" enterkeyhint="go" aria-label="Comando"></label>' +
            '<div class="term-chips" hidden></div>';
        document.body.appendChild(tela);
        document.body.style.overflow = 'hidden';
        const saida = tela.querySelector('.term-saida');
        const prompt = tela.querySelector('.term-prompt');
        const rotulo = prompt.querySelector('span');
        const entrada = prompt.querySelector('input');
        const chips = tela.querySelector('.term-chips');

        function aplicarTema() {
            tela.style.setProperty('--term-cor', TEMAS[tema]);
            tela.style.setProperty('--term-brilho', TEMAS[tema] + '73');
        }
        aplicarTema();
        const textoPrompt = () => (modo ? modo.prompt : `visitante@portfolio:${cwd}$`);
        const atualizarPrompt = () => { rotulo.textContent = textoPrompt(); };

        const fechar = () => {
            tela.remove();
            document.body.style.overflow = '';
            document.removeEventListener('keydown', teclas);
        };
        function teclas(e) {
            if (e.key === 'Escape') { fechar(); return; }
            // código Konami (setas + B + A) com o terminal aberto
            const esperado = KONAMI[konami];
            if (e.key === esperado || e.key.toLowerCase() === esperado) {
                konami++;
                if (konami === KONAMI.length) {
                    konami = 0;
                    linha('↑↑↓↓←→←→BA — modo trapaça ativado: +30 vidas (que não servem pra nada).', 'ok');
                    achar('konami');
                }
            } else {
                konami = e.key === KONAMI[0] ? 1 : 0;
            }
        }
        document.addEventListener('keydown', teclas);
        tela.querySelector('.term-fechar').addEventListener('click', fechar);
        tela.addEventListener('click', (e) => { if (e.target === tela || e.target === saida) entrada.focus(); });

        /* ---------- saída ---------- */
        const rolar = () => { tela.scrollTop = tela.scrollHeight; };
        // partes: texto, { texto, href } (link), { texto, cmd } (comando clicável) ou { texto, classe }
        function linha(partes, classe) {
            const l = document.createElement('div');
            l.className = 'term-linha' + (classe ? ' ' + classe : '');
            (Array.isArray(partes) ? partes : [partes]).forEach((p) => {
                if (typeof p === 'string') { l.append(p); return; }
                let el;
                if (p.href) {
                    el = document.createElement('a');
                    el.href = p.href;
                    el.target = '_blank';
                    el.rel = 'noopener';
                } else if (p.cmd) {
                    el = document.createElement('button');
                    el.type = 'button';
                    el.className = 'term-cmd';
                    el.addEventListener('click', () => { executar(p.cmd).then(atualizarChips); entrada.focus(); });
                } else {
                    el = document.createElement('span');
                }
                if (p.classe) el.classList.add(p.classe);
                el.textContent = p.texto;
                l.appendChild(el);
            });
            saida.appendChild(l);
            rolar();
            return l;
        }
        const pausa = (ms) => new Promise((ok) => setTimeout(ok, ms));
        async function digitar(texto, classe, velocidade = 18) {
            const l = linha('', classe);
            for (const ch of texto) { l.textContent += ch; await pausa(velocidade); }
            rolar();
            return l;
        }
        // várias opções clicáveis na mesma linha
        const comandosClicaveis = (lista) => lista.flatMap((c, i) => (i ? ['  ', { texto: c, cmd: c }] : [{ texto: c, cmd: c }]));

        function achar(id) {
            if (achados.has(id)) return;
            achados.add(id);
            guardar.set(LS.segredos, [...achados]);
            linha(`★ segredo encontrado: ${SEGREDOS[id]} (${achados.size}/${Object.keys(SEGREDOS).length}) — veja em "segredos"`, 'ok');
        }

        /* ---------- sistema de arquivos de mentira ---------- */
        const PASTAS = {
            '~': ['projetos/', 'fazenda/', 'curriculo.pdf', 'segredo.txt', 'contato.txt', '.arcade/', '.bash_history'],
            '~/projetos': dados.projetos.map((p) => slug(p.nome) + '.txt'),
            '~/.arcade': ['pong.exe', 'LEIAME.txt']
        };
        // junta o caminho digitado com a pasta atual ("..", "~", "./x", "pasta/arquivo")
        function resolver(caminho) {
            const partes = caminho.startsWith('~') ? [] : cwd.split('/').slice(1);
            caminho.replace(/^~\/?/, '').split('/').filter(Boolean).forEach((p) => {
                if (p === '.') return;
                if (p === '..') partes.pop();
                else partes.push(p);
            });
            return ['~', ...partes].join('/');
        }
        const ehPasta = (c) => c in PASTAS || c === '~/fazenda';
        function existe(c) {
            if (ehPasta(c)) return true;
            const pai = c.slice(0, c.lastIndexOf('/')), nome = c.slice(c.lastIndexOf('/') + 1);
            return (PASTAS[pai] || []).includes(nome);
        }
        function itemClicavel(nome, pasta) {
            const caminho = pasta === cwd ? nome : `${pasta}/${nome}`.replace(/^~\//, '');
            if (nome.endsWith('/')) return { texto: nome, cmd: `cd ${caminho}` };
            if (nome.endsWith('.exe')) return { texto: nome, cmd: pasta === cwd ? `./${nome}` : caminho };
            return { texto: nome, cmd: `cat ${caminho}` };
        }

        const ARQUIVOS = {
            '~/segredo.txt': () => ['"algo cresce escondido no campo deste portfólio."', 'dica: em inglês, 4 letras.'],
            '~/contato.txt': () => [['quer falar com o Carlos? digite ', { texto: 'contato', cmd: 'contato' }, '.']],
            '~/curriculo.pdf': () => ['%PDF-1.7 ¤§¶•ª… (binário ilegível)', [{ texto: 'open curriculo.pdf', cmd: 'open curriculo.pdf' }, ' para abrir de verdade.']],
            '~/.bash_history': () => {
                achar('historico');
                return ['ls -a', 'cd .arcade', 'cat LEIAME.txt', 'sudo rm -rf /   # quase', 'clear', '# alguém esqueceu de apagar isso...'];
            },
            '~/.arcade/LEIAME.txt': () => ['FLIPERAMA ABANDONADO — 1987', 'só uma máquina ainda liga.', [{ texto: './pong.exe', cmd: './pong.exe' }, ' para jogar.']],
            '~/.arcade/pong.exe': () => ['binário. para rodar: ./pong.exe']
        };

        /* ---------- comandos ---------- */
        const GRUPOS = [
            ['navegar', ['ls', 'cd', 'cat', 'open', 'pwd']],
            ['sobre o carlos', ['sobre', 'skills', 'projetos', 'contato', 'social', 'cv', 'neofetch']],
            ['diversão', ['piada', 'adivinhe', 'matrix', 'hack', 'moeda', 'dado', 'vaca', 'tema']],
            ['terminal', ['help', 'history', 'segredos', 'data', 'echo', 'clear', 'exit']]
        ];
        const PUBLICOS = GRUPOS.flatMap((g) => g[1]);

        const COMANDOS = {
            help() {
                linha('comandos (toque/clique para usar):');
                GRUPOS.forEach(([nome, lista]) => linha([{ texto: nome.padEnd(15), classe: 'dim' }, ...comandosClicaveis(lista)]));
                linha('dica: nem tudo aparece aqui. arquivos escondidos começam com ponto.', 'dim');
            },
            ls(args) {
                const todos = args.some((a) => /^-\w*a/.test(a));
                const alvo = args.find((a) => !a.startsWith('-'));
                const pasta = alvo ? resolver(alvo) : cwd;
                if (pasta === '~/fazenda') return linha('ls: permissão negada. essa pasta só abre com o comando secreto.', 'erro');
                if (!(pasta in PASTAS)) return linha(`ls: ${alvo}: não existe`, 'erro');
                const itens = PASTAS[pasta].filter((n) => todos || !n.startsWith('.'));
                if (!itens.length) return linha('(vazio)', 'dim');
                linha(itens.flatMap((n, i) => (i ? ['   ', itemClicavel(n, pasta)] : [itemClicavel(n, pasta)])));
            },
            cd(args) {
                const alvo = args[0] || '~';
                const destino = resolver(alvo);
                if (destino === '~/fazenda') return linha('cd: permissão negada. dica: o comando secreto tem a ver com plantar...', 'erro');
                if (!(destino in PASTAS)) return linha(`cd: ${alvo}: pasta não encontrada`, 'erro');
                cwd = destino;
                atualizarPrompt();
                if (cwd === '~/.arcade') {
                    linha('*poeira* luzes piscando... um fliperama antigo.', 'dim');
                    achar('arcade');
                }
            },
            pwd() { linha('/home/visitante' + cwd.slice(1)); },
            cat(args) {
                if (!args[0]) return linha('uso: cat <arquivo>', 'erro');
                const c = resolver(args[0]);
                if (ehPasta(c)) return linha(`cat: ${args[0]}: é uma pasta (use cd)`, 'erro');
                if (c.startsWith('~/projetos/')) {
                    const p = dados.projetos.find((x) => slug(x.nome) + '.txt' === c.slice(11));
                    if (p) {
                        linha(p.nome.toUpperCase(), 'ok');
                        linha(p.desc);
                        if (p.tags.length) linha('stack: ' + p.tags.join(', '), 'dim');
                        if (p.link) linha([{ texto: 'abrir o projeto ↗', href: p.link }]);
                        return;
                    }
                }
                const f = ARQUIVOS[c];
                if (!f) return linha(`cat: ${args[0]}: arquivo não encontrado`, 'erro');
                f().forEach((l) => linha(l));
            },
            open(args) {
                const alvo = (args[0] || '').toLowerCase();
                const p = dados.projetos.find((x) => slug(x.nome) === alvo.replace(/\.txt$/, '').replace(/^projetos\//, ''));
                const url = alvo.includes('curriculo') || alvo === 'cv' ? dados.cv
                    : alvo === 'linkedin' ? dados.linkedin : alvo === 'github' ? dados.github
                    : alvo === 'whatsapp' ? dados.whatsapp : p ? p.link : '';
                if (!url) return linha(alvo ? `open: não sei abrir "${args[0]}"` : 'uso: open <curriculo.pdf | linkedin | github | whatsapp | projeto>', 'erro');
                linha('abrindo ' + url.replace(/^https?:\/\//, '') + ' ...', 'dim');
                window.open(url, '_blank', 'noopener');
            },
            sobre() {
                linha('CARLOS JESSÉ', 'ok');
                linha(dados.sobre || 'Desenvolvedor Full-Stack.');
                linha(['veja também: ', ...comandosClicaveis(['skills', 'projetos', 'contato'])], 'dim');
            },
            skills() {
                if (!dados.skills.length) return linha('nenhuma skill encontrada na página.', 'dim');
                const barra = (nivel) => (/avan/i.test(nivel) ? '██████████' : /inter/i.test(nivel) ? '███████░░░' : '██████░░░░');
                const larg = Math.max(...dados.skills.map((s) => s.nome.length), 6) + 2;
                dados.skills.forEach((s) => linha(`${s.nome.padEnd(larg)}${barra(s.nivel)}  ${s.nivel}`, 'term-pre'));
            },
            projetos() {
                if (!dados.projetos.length) return linha('nenhum projeto encontrado na página.', 'dim');
                dados.projetos.forEach((p, i) => linha([
                    { texto: String(i + 1).padStart(3, '0') + ' ', classe: 'dim' },
                    { texto: p.nome, cmd: `cat projetos/${slug(p.nome)}.txt` },
                    p.tags.length ? ` — ${p.tags.slice(0, 3).join(', ')}` : '',
                    ...(p.link ? ['  ', { texto: '↗', href: p.link }] : [])
                ]));
                linha('toque no nome para ver os detalhes.', 'dim');
            },
            contato() {
                if (dados.whatsapp) linha(['whatsapp  ', { texto: dados.whatsapp.replace('https://', ''), href: dados.whatsapp }]);
                if (dados.linkedin) linha(['linkedin  ', { texto: 'linkedin.com/in/carlos-jessé', href: dados.linkedin }]);
                if (dados.github) linha(['github    ', { texto: dados.github.replace('https://', ''), href: dados.github }]);
                if (typeof window.abrirContato === 'function') linha([{ texto: 'abrir o formulário de contato', cmd: 'formulario' }]);
            },
            social() {
                if (dados.linkedin) linha(['linkedin  ', { texto: 'abrir ↗', href: dados.linkedin }]);
                if (dados.github) linha(['github    ', { texto: 'abrir ↗', href: dados.github }]);
            },
            cv() {
                if (!dados.cv) return linha('currículo não encontrado.', 'erro');
                linha(['currículo do Carlos: ', { texto: 'baixar o PDF ↗', href: dados.cv }]);
            },
            neofetch() {
                const logo = ['   ____     _ ', '  / ___|   | |', ' | |    _  | |', ' | |___| |_| |', '  \\____|\\___/ ', '', ''];
                const min = Math.max(1, Math.round(performance.now() / 60000));
                const info = [
                    'visitante@carlos-portfolio',
                    '--------------------------',
                    'dono:      Carlos Jessé',
                    'cargo:     Dev Full-Stack',
                    'stack:     ' + (dados.skills.slice(0, 4).map((s) => s.nome).join(', ') || 'web'),
                    'projetos:  ' + dados.projetos.length,
                    `uptime:    ${min} min nesta página · tema ${tema}`
                ];
                logo.forEach((l, i) => linha(l.padEnd(16) + (info[i] || ''), 'term-pre'));
                linha([...Object.keys(TEMAS).map((t) => ({ texto: '███', classe: 'term-cor-' + t })), '  ',
                    { texto: 'segredos: ' + achados.size + '/' + Object.keys(SEGREDOS).length, classe: 'dim' }], 'term-pre');
            },
            async piada() {
                ocupado = true;
                await digitar(PIADAS[Math.floor(Math.random() * PIADAS.length)], null, 14);
                ocupado = false;
            },
            async moeda() {
                ocupado = true;
                const l = linha('girando', 'dim');
                for (let i = 0; i < 6; i++) { await pausa(120); l.textContent += '.'; }
                linha(Math.random() < 0.5 ? 'CARA!' : 'COROA!', 'ok');
                ocupado = false;
            },
            dado() {
                const n = 1 + Math.floor(Math.random() * 6);
                const F = { 1: ['     ', '  o  ', '     '], 2: ['o    ', '     ', '    o'], 3: ['o    ', '  o  ', '    o'],
                    4: ['o   o', '     ', 'o   o'], 5: ['o   o', '  o  ', 'o   o'], 6: ['o   o', 'o   o', 'o   o'] };
                linha('+-------+', 'term-pre');
                F[n].forEach((l) => linha('| ' + l + ' |', 'term-pre'));
                linha('+-------+  tirou ' + n, 'term-pre');
            },
            vaca(args) {
                const texto = (args.join(' ') || 'muuu').slice(0, 40);
                const borda = '-'.repeat(texto.length + 2);
                [' ' + borda, `< ${texto} >`, ' ' + borda, '      \\', '       \\   _.._', '        \\ (o  o)___', '          (__)     )~', '            ||--||', '            ^^  ^^']
                    .forEach((l) => linha(l, 'term-pre'));
            },
            tema(args) {
                const nome = (args[0] || '').toLowerCase().replace('âmbar', 'ambar');
                if (!TEMAS[nome]) return linha(['temas: ', ...comandosClicaveis(Object.keys(TEMAS).map((t) => `tema ${t}`))]);
                tema = nome;
                guardar.set(LS.tema, tema);
                aplicarTema();
                linha(`tema ${tema} aplicado.`, 'ok');
            },
            history() {
                const ult = historico.slice(-15);
                if (!ult.length) return linha('(vazio)', 'dim');
                ult.forEach((c, i) => linha([{ texto: String(historico.length - ult.length + i + 1).padStart(3) + '  ', classe: 'dim' }, { texto: c, cmd: c }]));
            },
            segredos() {
                const total = Object.keys(SEGREDOS).length;
                linha(`segredos encontrados: ${achados.size}/${total}`, 'ok');
                Object.entries(SEGREDOS).forEach(([id, nome]) => linha(achados.has(id) ? '★ ' + nome : '☆ ??????', achados.has(id) ? null : 'dim'));
                if (achados.size === total) linha('você achou tudo. o Carlos tá impressionado.', 'ok');
                else linha('dica: explore as pastas, leia os arquivos e teste comandos de hacker.', 'dim');
            },
            data() { linha(new Date().toLocaleString('pt-BR', { dateStyle: 'full', timeStyle: 'short' })); },
            echo(args) { linha(args.join(' ')); },
            clear() { saida.innerHTML = ''; },
            exit() { fechar(); },
            adivinhe() {
                const alvo = 1 + Math.floor(Math.random() * 100);
                let tentativas = 0;
                modo = {
                    prompt: 'palpite (1-100)>',
                    receber(t) {
                        if (/^(sair|exit|desisto)$/i.test(t)) {
                            linha(`era ${alvo}. fica pra próxima!`, 'dim');
                            modo = null;
                            return;
                        }
                        const n = parseInt(t, 10);
                        if (!(n >= 1 && n <= 100)) return linha('digite um número de 1 a 100 (ou "sair").', 'erro');
                        tentativas++;
                        if (n === alvo) {
                            linha(`ACERTOU! era ${alvo}, em ${tentativas} tentativa${tentativas > 1 ? 's' : ''}.${tentativas <= 7 ? ' mandou bem!' : ''}`, 'ok');
                            achar('adivinhe');
                            modo = null;
                        } else {
                            linha(n < alvo ? 'mais alto ↑' : 'mais baixo ↓');
                        }
                    }
                };
                linha('pensei num número de 1 a 100. tente adivinhar! (digite "sair" para desistir)');
            },
            async hack() {
                ocupado = true;
                const passos = ['conectando no mainframe', 'quebrando o firewall', 'baixando a internet inteira', 'descriptografando senhas', 'invadindo a NASA'];
                for (const p of passos) {
                    const l = linha(`[          ] ${p}`, 'term-pre');
                    for (let i = 1; i <= 10; i++) {
                        await pausa(35 + Math.random() * 60);
                        l.textContent = `[${'#'.repeat(i)}${' '.repeat(10 - i)}] ${p}`;
                    }
                    linha('  0x' + Math.random().toString(16).slice(2, 10).toUpperCase() + ' ok', 'dim');
                }
                await digitar('ACESSO NEGADO. brincadeira: o único sistema que o Carlos invade é o seu coração ❤', 'ok', 16);
                ocupado = false;
            },
            matrix() {
                ocupado = true;
                const c = document.createElement('canvas');
                c.className = 'term-matrix';
                tela.appendChild(c);
                const g = c.getContext('2d');
                c.width = innerWidth; c.height = innerHeight;
                const tam = 16, gotas = Array(Math.ceil(c.width / tam)).fill(0).map(() => Math.random() * -40);
                const letras = 'アイウエオカキクケコサシスセソ01JESSE<>/{}#$';
                let quadro;
                const fim = () => {
                    cancelAnimationFrame(quadro);
                    c.remove();
                    ocupado = false;
                    linha('você acordou. foi só um sonho... ou não.', 'dim');
                    achar('matrix');
                    entrada.focus();
                };
                function passo() {
                    g.fillStyle = 'rgba(5,10,6,.12)';
                    g.fillRect(0, 0, c.width, c.height);
                    g.fillStyle = TEMAS[tema];
                    g.font = tam + 'px monospace';
                    gotas.forEach((y, i) => {
                        g.fillText(letras[Math.floor(Math.random() * letras.length)], i * tam, y * tam);
                        gotas[i] = y * tam > c.height && Math.random() > 0.97 ? 0 : y + 1;
                    });
                    quadro = requestAnimationFrame(passo);
                }
                passo();
                const t = setTimeout(fim, 6000);
                c.addEventListener('click', () => { clearTimeout(t); fim(); });
            },
            async sudo(args, bruto) {
                if (!/rm\s+-rf/.test(bruto)) return linha('visitante não está no arquivo sudoers. este incidente será reportado. 👮', 'erro');
                ocupado = true;
                for (const p of ['/bin', '/home/carlos/projetos', '/home/carlos/cafe', '/portfolio', '/internet']) {
                    linha('removendo ' + p + ' ...', 'erro');
                    await pausa(260);
                }
                await pausa(400);
                linha('brincadeira! nada foi apagado. o Carlos tem backup (e senso de humor).', 'ok');
                achar('sudo');
                ocupado = false;
            }
        };
        // apelidos e comandos escondidos (não aparecem no help)
        const ESCONDIDOS = {
            ajuda: () => COMANDOS.help(), limpar: () => COMANDOS.clear(), sair: () => COMANDOS.exit(),
            dir: (a) => COMANDOS.ls(a), cls: () => COMANDOS.clear(), curriculo: () => COMANDOS.cv(),
            formulario: () => { fechar(); window.abrirContato(); },
            whoami: () => linha('visitante (por enquanto)'),
            oi: () => linha(['oi! 👋 digite ', { texto: 'sobre', cmd: 'sobre' }, ' para conhecer o Carlos.']),
            ola: () => ESCONDIDOS.oi(),
            hello: () => linha('hello, world! (todo dev começa assim)'),
            cafe: () => linha('☕ erro 418: eu sou um bule de chá.'),
            coffee: () => ESCONDIDOS.cafe(),
            xyzzy: () => linha('nada acontece.', 'dim'),
            42: () => linha('então você já sabe a resposta.'),
            rm: () => linha('rm: permissão negada. (tente com sudo... ou melhor, não tente)', 'erro'),
            konami: () => linha('não é assim que se digita esse código ;)', 'dim'),
            senha: () => linha('a senha é: ********. (achou mesmo que eu ia mostrar?)'),
            pong: () => {
                linha('comando não encontrado: pong', 'erro');
                linha('hmm... esse nome não é estranho. talvez esteja escondido em algum lugar.', 'dim');
            }
        };

        async function abrirFazenda() {
            ocupado = true;
            prompt.hidden = true;
            chips.hidden = true;
            achar('fazenda');
            await digitar('> ACESSO CONCEDIDO', 'ok', 40);
            await digitar('> carregando fazenda_secreta.exe [##########] 100%', null, 22);
            await pausa(350);
            window.location.href = 'fazenda.html';
        }
        async function abrirPong() {
            if (!window.abrirPong) return linha('a máquina não liga... (o Pong só roda na página do portfólio)', 'erro');
            ocupado = true;
            achar('pong');
            await digitar('> iniciando PONG.EXE ...', 'ok', 25);
            await pausa(300);
            fechar();
            window.abrirPong();
        }

        /* ---------- executar ---------- */
        async function executar(bruto) {
            bruto = String(bruto).trim();
            if (ocupado) return;
            if (modo) {
                linha([{ texto: modo.prompt, classe: 'term-p' }, ' ' + bruto]);
                modo.receber(bruto);
                atualizarPrompt();
                return;
            }
            linha([{ texto: textoPrompt(), classe: 'term-p' }, ' ' + bruto]);
            if (!bruto) return;
            if (historico[historico.length - 1] !== bruto) {
                historico.push(bruto);
                if (historico.length > 30) historico.shift();
                guardar.set(LS.historico, historico);
            }
            posHist = historico.length;

            const [nome, ...args] = bruto.split(/\s+/);
            const cmd = nome.toLowerCase();
            if (['farm', 'fazenda', './farm'].includes(cmd)) return abrirFazenda();
            // rodar um programa pelo caminho (./pong.exe, .arcade/pong.exe)
            if (cmd.includes('/') || cmd.endsWith('.exe')) {
                const c = resolver(cmd.replace(/^\.\//, ''));
                if (c === '~/.arcade/pong.exe') return abrirPong();
                if (existe(c)) return linha(`${nome}: não é um programa (tente cat ou cd)`, 'erro');
                return linha(`${nome}: arquivo não encontrado`, 'erro');
            }
            const f = COMANDOS[cmd] || ESCONDIDOS[cmd];
            if (f) {
                await f(args, bruto);
                atualizarPrompt();
                return;
            }
            linha('comando não encontrado: ' + nome, 'erro');
            const parecido = PUBLICOS.find((c) => distancia(cmd, c) <= (c.length > 4 ? 2 : 1));
            if (parecido) linha(['você quis dizer ', { texto: parecido, cmd: parecido }, '?'], 'dim');
            else linha(['digite ', { texto: 'help', cmd: 'help' }, ' para ver os comandos.'], 'dim');
        }

        /* ---------- teclado: Enter, histórico (↑ ↓) e Tab ---------- */
        entrada.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') {
                const v = entrada.value;
                entrada.value = '';
                executar(v).then(atualizarChips);
            } else if (e.key === 'ArrowUp' && !modo) {
                e.preventDefault();
                if (posHist > 0) entrada.value = historico[--posHist] || '';
            } else if (e.key === 'ArrowDown' && !modo) {
                e.preventDefault();
                posHist = Math.min(historico.length, posHist + 1);
                entrada.value = historico[posHist] || '';
            } else if (e.key === 'Tab') {
                e.preventDefault();
                completar();
            }
        });
        entrada.addEventListener('input', () => atualizarChips());

        // completa o comando ou o nome do arquivo/pasta
        function completar() {
            const partes = entrada.value.split(' ');
            const ultimo = partes[partes.length - 1];
            let opcoes;
            if (partes.length === 1) {
                opcoes = PUBLICOS.filter((c) => c.startsWith(ultimo.toLowerCase()));
            } else {
                const base = ultimo.includes('/') ? ultimo.slice(0, ultimo.lastIndexOf('/') + 1) : '';
                const pasta = resolver(base || '.');
                opcoes = (PASTAS[pasta] || []).filter((n) => n.startsWith(ultimo.slice(base.length))).map((n) => base + n);
            }
            if (opcoes.length === 1) {
                partes[partes.length - 1] = opcoes[0];
                entrada.value = partes.join(' ') + (opcoes[0].endsWith('/') ? '' : ' ');
            } else if (opcoes.length > 1) {
                linha(opcoes.join('   '), 'dim');
            }
        }

        // sugestões tocáveis (no celular digitar é chato)
        function atualizarChips() {
            const v = entrada.value.trim().toLowerCase();
            let lista;
            if (modo) lista = ['sair'];
            else if (!v) lista = cwd === '~/.arcade' ? ['ls', 'cat LEIAME.txt', 'cd ..'] : ['help', 'sobre', 'projetos', 'neofetch', 'piada', 'segredos'];
            else lista = PUBLICOS.filter((c) => c.startsWith(v) && c !== v).slice(0, 6);
            chips.innerHTML = '';
            lista.forEach((c) => {
                const b = document.createElement('button');
                b.type = 'button';
                b.className = 'term-chip';
                b.textContent = c;
                b.addEventListener('click', () => { entrada.value = ''; executar(c).then(atualizarChips); entrada.focus(); });
                chips.appendChild(b);
            });
            chips.hidden = !lista.length || prompt.hidden;
        }

        /* ---------- abertura ---------- */
        (async () => {
            await digitar('> conectando em carlos@portfolio ...');
            await pausa(250);
            await digitar('> handshake ok. canal criptografado.');
            await digitar('> ACESSO RESTRITO. existem segredos aqui dentro.', 'erro');
            linha(['> comece por ', { texto: 'help', cmd: 'help' }, ' (ou toque nas sugestões lá embaixo).']);
            ocupado = false;
            atualizarPrompt();
            prompt.hidden = false;
            atualizarChips();
            entrada.focus();
        })();
    }

    window.TERMINAL = { abrir };
})();
