# REVIEW — Reels "POV: era só um portfólio" (rascunho)

## Decisões de criação
- Roteiro A ("O segredo no fim do portfólio"), escolhido pelo Jessé. Os roteiros B e C de `STORYLINES.md` não foram feitos.
- Voz do ElevenLabs ("Lendário — Cheerful, Vibrant and Fun"), que o Jessé gerou e mandou; cortada em 15 falas (`../ferramentas/cortes-fazenda.txt`), cada uma no mesmo início da fala antiga do Kokoro. A primeira versão usava pm_alex (Kokoro, local). Legendas em placas creme do jogo, um grupo por vez, uma palavra de acento verde.
- Sem música: o áudio em alta entra no próprio Instagram. Os efeitos marcam cada ação: whoosh nos chicotes, clique e impacto no "Jogar agora", pop nos avisos do jogo e teclas no apelido.
- Todas as telas são capturas reais do site e do jogo (banco de teste local, primavera, fazenda de vitrine do Jessé no nível 35).
- O Jessé agora é o personagem desenhado da folha que ele mandou: o corpo da folha com a cabeça de cada expressão encaixada pela gola (`scratchpad/personagem/compor.py`), espelhado para o braço cortado da folha ficar fora do quadro, na borda direita. Fala mexendo o corpo, guiado pela energia da voz, e troca de cara a cada frase, sem abrir e fechar a boca. Usa 7 das 12 expressões; bravo, bravo de boca aberta, triste e pensativo ficaram de fora como cara solta. No "Rola o currículo…" (3,35 s) a mão sai do bolso e vai ao queixo (pensativo), e volta na surpresa (6,1 s).

## O que foi medido e o que foi só olhado
- `check --json`: ok, sem erros.
- Áudio do rascunho com a voz antiga: −16,3 LUFS integrado, LRA 6,8 LU, pico verdadeiro −1,5 dBFS, 30,0 s. Com a voz do ElevenLabs e o gesto, o rascunho ainda não foi renderizado nem medido. **O som foi medido, não ouvido.**
- Só olhado: as folhas `snapshot --review` (beats, celular a 360 px e os seis cortes) e os quadros do QA do SPEC.
- Corrigido nesta passada: um quadro preto inteiro nos cortes de 3,0 s e 5,4 s. A primeira tela agora entra já a 1/4 do quadro, borrada. Conferido com snapshot em 3,0 / 3,05 / 5,4 / 5,45.

## Plano mais fraco
- 13,9–15,1 s, a feira: é um formulário cheio de texto miúdo. Lê como "tela do jogo", mas não mostra nada acontecendo.
- Com mais tempo: trocaria por uma venda saindo, com o toast de moedas, ou cortaria direto para o alto-mar.

## Avisos mantidos de propósito
- No tamanho pequeno, a orelha do personagem fica perto da coluna de botões do Instagram (x > 975). Para afastar, o braço cortado apareceria.
- A placa "POV: era só um portfólio…" e a legenda "POV: você abre…" dizem quase o mesmo nos 3 primeiros segundos. É o gancho: a placa é o título fixo, e a legenda é a voz.
- O código de recuperação aparece quebrado em duas linhas ("…Z8X / S"). É assim que o jogo mostra em telas de 432 px; não foi editado porque a tela é real.
- Aos 27,6 s, o girassol do final aparece um instante antes de o verde cobrir o cartão da cena 5. É P2.
