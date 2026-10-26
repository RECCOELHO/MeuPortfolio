# REVIEW — Reels "POV: era só um portfólio" (versão final)

## Decisões de criação
- **Roteiro:** A, "O segredo no fim do portfólio", escolhido pelo Jessé. Os roteiros B e C de `STORYLINES.md` não foram feitos.
- **Voz:** do ElevenLabs ("Lendário — Cheerful, Vibrant and Fun"). O Jessé gerou e mandou.
  - Cortada em 15 falas (`../ferramentas/cortes-fazenda.txt`), com ganho de +3 dB nos arquivos.
  - O `volume` do `<audio>` fica em 1.0, porque acima de 1 ele não aumenta o som.
- **Personagem:** as poses de corpo inteiro da `folha-poses`, uma por frase, de `POSES_T` no `gerar.py`.
  - Cada pose é alinhada pelo pé, com a mesma altura, e aparece do joelho para cima.
  - A troca de pose tem uma fusão de 0,1 s, um amassado e um quique.
  - Ele respira e balança o tempo todo, e o corpo mexe com a energia da voz. A boca nunca abre e fecha.
- **Telas sem cara de print:**
  - a câmera nunca para: a página rola e o jogo vai chegando perto (`#s4-deriva`);
  - estados do mesmo lugar do jogo se fundem;
  - um lugar novo (vizinho, feira) entra empurrando a tela anterior.
- **Som:** sem música, porque o áudio em alta entra no Instagram. Cada ação tem um efeito sonoro.

## O que foi medido e o que foi só olhado
- `check --json`: ok.
- Final (`render -q delivery`): −16,5 LUFS integrado e pico de −1,4 dBFS em 30,0 s. **O som foi medido, não ouvido.**
- Só olhado: uma folha de 14 quadros-chave, as trocas de pose e os empurrões.

## Plano mais fraco
- A feira (13,9–15,1 s) ainda é um formulário parado; só a câmera anda.
- As poses foram ampliadas cerca de 2× da folha e ficam um pouco moles. Uma folha em resolução maior resolve.

## Avisos mantidos de propósito
- O código de recuperação aparece quebrado em duas linhas, porque a tela do jogo é real.
- Na troca de pose, as duas poses ficam sobrepostas por 3 quadros. Isso faz a vez de um borrão de movimento.
