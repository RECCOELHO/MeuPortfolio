/* ============================================================
   INSTALAR OS JOGOS COMO APP (PWA)
   Uso na página do jogo:
     <script src="assets/app/instalar.js?v=..." data-escopo="/fazenda"></script>
   Registra o jogos-sw.js no escopo dado e expõe window.INSTALAR:
     estado()   → 'instalado' | 'pronto' (Android/PC: dá para abrir
                  o pedido de instalação) | 'ios' | 'manual'
     instalar() → abre o pedido de instalação (precisa de um toque)
     dica()     → texto de como instalar quando não dá pelo botão
     aoMudar(fn)→ avisa quando o estado muda
============================================================ */
(function () {
    'use strict';

    const script = document.currentScript;
    const escopo = script && script.dataset.escopo;
    if ('serviceWorker' in navigator && escopo) {
        navigator.serviceWorker.register('/jogos-sw.js', { scope: escopo }).catch(() => { /* sem app, joga no navegador */ });
    }

    let pedido = null, instalou = false;
    const ouvintes = [];
    const avisar = () => ouvintes.forEach((fn) => fn(estado()));

    window.addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); pedido = e; avisar(); });
    window.addEventListener('appinstalled', () => { pedido = null; instalou = true; avisar(); });

    const ios = /iphone|ipad|ipod/i.test(navigator.userAgent)
        || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

    function estado() {
        const app = window.matchMedia('(display-mode: standalone), (display-mode: fullscreen)').matches || navigator.standalone;
        if (instalou || app) return 'instalado';
        if (pedido) return 'pronto';
        return ios ? 'ios' : 'manual';
    }

    async function instalar() {
        if (!pedido) return estado();
        pedido.prompt();
        const escolha = await pedido.userChoice;
        pedido = null;
        if (escolha.outcome === 'accepted') instalou = true;
        avisar();
        return estado();
    }

    function dica() {
        if (estado() === 'ios') return 'No Safari, toque em Compartilhar (o quadrado com a seta para cima) e depois em "Adicionar à Tela de Início".';
        return 'Abra o menu do navegador (⋮) e toque em "Instalar app" ou "Adicionar à tela inicial".';
    }

    window.INSTALAR = { estado, instalar, dica, aoMudar: (fn) => ouvintes.push(fn) };
})();
