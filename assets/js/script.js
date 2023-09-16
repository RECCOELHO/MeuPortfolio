
const meuTexto = document.getElementById('meuTexto');

meuTexto.addEventListener('dragenter', () => {
meuTexto.classList.add('estilo-de-arraste');
});

meuTexto.addEventListener('dragleave', () => {
meuTexto.classList.remove('estilo-de-arraste');
});

