# SPEC — Reels "POV: era só um portfólio" (roteiro A, aprovado)

GOAL:    quem assiste descobre que o portfólio do Jessé esconde um jogo e sabe entrar em 3 passos
         (jessecoelho.com.br → Projetos → Jogar agora → apelido + código).
OUTPUT:  HyperFrames, 1080 x 1920, 30 fps, MP4 para Reels.
TIME:    30,0 s x 30 = 900 frames. Sem música (o áudio em alta entra no Instagram); a voz é o relógio.

LOOK:    dois mundos com a mesma tipografia do jogo.
         - Mundo 1, o portfólio: as capturas reais (fundo #0e0709, vermelho #d94040, Playfair do site).
         - Mundo 2, o jogo: as capturas reais da Fazendinha na primavera (grama #84c669, madeira #eaa56c).
         - Placas do jogo por cima dos dois: fundo creme #fde6c9, contorno 6 px #3f2631 e sombra dura
           de 6 px para baixo #3f2631; fonte pixel "Jersey 10" (títulos) e Nunito 900 (legendas).
         - Acento: verde #4e974c, numa palavra por legenda no máximo, nos números dos passos e no CTA.
         - Sem brilho, sem partículas, sem vinheta e sem degradê; o pixel é o material: ícones do jogo em
           image-rendering: pixelated, sempre em múltiplos inteiros do tamanho nativo.
OBJECTS: o crachá 3D do portfólio (foto com a filha); o monitor de Projetos com "Fazendinha Secreta" e o
         botão vermelho "Jogar agora" (x 35–421, y 1518–1648); a porteira do jogo (cartão y 391–1529); o
         campo "Seu apelido" (y 1146–1254); o código de recuperação (y 580–800); a mão pixel do jogo
         (ico-mao, 13 px nativos mostrados a 13 x 12 = 156 px); o Jessé desenhado da folha de personagem (corpo da
         folha + a cabeça de cada expressão, espelhado; 418 x 700 em 2x).
CHARACTER: o Jessé desenhado fala mexendo o corpo, sem mexer a boca. A cada 1/15 s da voz, a energia do áudio (0–1) vira:
         y −16 px x energia, escala vertical 1 + 0,035 x energia e giro alternado de ±2,5° nas sílabas fortes.
         A cara troca a cada frase (sorriso, desconfiado, surpreso, sorriso aberto, rindo, falando, piscando no fim),
         com um amassado de 0,16 s (back.out 2). O braço cortado da folha fica sempre fora do quadro, na borda direita.
         - Grande no gancho e no final: escala 1,25, embaixo à direita, topo da cabeça em y ≈ 1140.
         - Pequeno no meio: escala 0,85, topo da cabeça em y ≈ 1390. Entre um e outro, back.out(1.3) em 0,5 s.
CAPTIONS: Nunito 900, 60 px (mínimo 48), texto #3f2631 numa placa creme; 2 a 4 palavras por grupo; um grupo
         por vez; centradas em x 540, largura máxima 860, entre y 1080 e 1240. Entram com blur de 6 para 0 px
         em 0,13 s, sem subir; saem em 0,12 s.
MOTION:  - Entrada: expo.out 0,5 s. Câmera: power2.inOut 0,5 s.
         - Mergulho (zoom pelo botão): power3.in 0,35 s, o botão de 8% a 250% do quadro.
         - Chicote do currículo: 0,2 s, com blur vertical de 18 px no pico.
         - Placas e números: back.out(1.6) 0,35 s.
         - Toque da mão: entra de fora em 0,4 s com expo.out; aperta (escala 0,85) em 3 frames, e o clique causa a próxima tela.
SHOTS:
  01  0,0–3,0    gancho: portfólio no topo (crachá) + placa "POV: era só um portfólio…" já na tela no frame 0;
                 o Jessé grande fala (vo1 em 0,25 s). Soco de câmera 1,0→1,12 no crachá aos 1,2 s (whoosh).
  02  3,0–5,4    currículo: SENAI, Exército e hospital trocam a cada 0,8 s por chicote vertical (3 whooshes);
                 vo2 em 3,05 s.
  03  5,4–9,0    revelação: Projetos; câmera vai até "Jogar agora" (5,5–6,1); a mão entra e toca (6,5, clique);
                 o botão cresce e vira a porteira "Fazendinha Secreta" (6,55–6,9; riser 5,6 → impacto 6,9);
                 vo3 em 6,15 s.
  04  9,0–16,9   prova, cortes na voz:
                 - plantar (9,0: arados → piscando 9,6 → "Plantou 36 × alface" 9,9, pop);
                 - colher (10,9 → "Colheu 175 itens" 11,3, pop);
                 - vizinho (12,3 → "No vizinho: cuidou de 22 canteiros" 12,9, pop);
                 - feira (13,9); alto-mar (15,1, whoosh e a cor vira o azul do mar).
  05  16,9–27,4  como entrar, 3 placas numeradas:
                 1) topo do portfólio + "jessecoelho.com.br" (vo5a 17,0; vo5b 18,05);
                 2) chicote até Projetos (20,5) e a mão toca "Jogar agora" (23,1, clique);
                 3) a porteira com "Bia" digitado letra por letra (24,3 / 24,55 / 24,8, teclas);
                    o código com a moldura verde (25,6, pop).
  06  27,4–30,0  final: fundo grama; o girassol e "Fazendinha Secreta" entram com a mão;
                 CTA "jessecoelho.com.br · link na bio" parado por 2,2 s; o Jessé grande diz "Bora plantar!" (27,6).
BANNED:  fundo escuro vazio com coisas pequenas flutuando; brilho, partículas e degradê; títulos que continuam
         se mexendo depois de chegar; tudo entrando com fade e subindo; três cartões lado a lado; logo no canto;
         argolas de clique; tela inventada (todas as telas são capturas reais do site e do jogo).
QA:      0,0 (frame 0 já é o gancho), 1,3, 4,0, 6,5, 7,5, 9,95, 11,4, 12,95, 15,5, 18,5, 23,1, 24,9, 25,8 e 28,8.
         Em cada um: texto legível, dentro de y 168–1330, nada sob o trilho de botões da direita.
