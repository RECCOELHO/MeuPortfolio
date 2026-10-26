---
name: reels-jesse
description: Receita dos Reels do Jessé com o personagem desenhado dele (camiseta vermelha, corrente, calça preta), feitos em HyperFrames, 9:16 e ~30 s, com voz de IA, legendas em placas do jogo e telas reais do portfólio e da Fazendinha. Use quando ele pedir um vídeo, Reels, TikTok ou Shorts novo com o personagem, ou quiser mudar o Reels da Fazendinha.
---

# Reels com o personagem do Jessé

Leia antes `/hyperframes` (contrato e ciclo de trabalho). Esta receita guarda o que já foi decidido com o Jessé e onde está cada peça.

## O que tem aqui

| Pasta | O que é |
| --- | --- |
| `modelo/` | O Reels "POV: era só um portfólio" (Fazendinha), pronto para copiar. `gerar.py` gera `index.html` e `compositions/*`. Também traz SPEC, STORYBOARD, STORYLINES, REVIEW e os assets (telas, voz, efeitos, fontes, GSAP). |
| `personagem/` | As duas folhas que ele mandou (`folha-expressoes.webp`, `folha-poses.webp`) e os scripts que montam o personagem. |
| `personagem/final/` | As 8 caras prontas (`jesse-<cara>.webp`) e as camadas do gesto "mão no queixo" (`gesto-*.webp`). |
| `personagem/poses/` | As 12 poses de corpo inteiro, com fundo transparente. `poses.json` dá a largura, a altura e o pé de cada uma. |
| `ferramentas/` | Scripts para cortar e conferir a voz (`voz-*`) e para capturar as telas (`captura/`). |

## O que ele já decidiu

- **Formato:** 1080×1920, 30 fps, de 25 a 30 s.
- **Som:** sem música, porque ele põe um áudio em alta no próprio Instagram. Cada ação tem um efeito sonoro: whoosh no corte, clique, pop no aviso, teclas na digitação.
- **Personagem:** é o Jessé desenhado, de corpo inteiro (as poses da `folha-poses`). **Nunca abre e fecha a boca.** Ele fala mexendo o corpo com a energia da voz e troca de pose a cada frase.
- **Nada parado:** ele reclamou que parecia "só tirando print". Então:
  - toda tela tem câmera andando (rolagem ou aproximação lenta);
  - estados do mesmo lugar se fundem em 0,16 s;
  - um lugar novo entra empurrando a tela anterior (x 1080 → 0 com borrão, em 0,32 s);
  - o personagem respira e balança o tempo todo.
- **Visual:** o do próprio jogo.
  - Placa: fundo `#fde6c9`, contorno 6 px `#3f2631` e sombra dura `0 8px 0 #3f2631`.
  - Títulos em 'Jersey 10' (`assets/fonts/jersey10-latin.woff2`).
  - Legendas em Nunito 900, 60 px, um grupo por vez, centradas em `top: 1010px`.
  - Verde de acento `#3b7a3a`, só numa palavra por legenda (`*palavra*` no texto).
  - Fundo das cenas `#1a0a0d`.
- **Telas:** sempre reais, capturadas do site e do jogo. Nunca invente uma tela.
- **Final:** "jessecoelho.com.br · link na bio".
- **Aprovação:** ele aprova o plano antes de montar.
  1. Mostre 3 roteiros em palavras e espere ele escolher.
  2. Escreva o SPEC.md e o storyboard.
  3. Mande o rascunho (`render -q draft`) e espere a aprovação.
  4. Só então faça o render final (`render -q delivery`).
- **Voz:** a que ele escolheu é do ElevenLabs.
  - Voz "Lendário — Cheerful, Vibrant and Fun", velocidade 1.00, estabilidade 50, similaridade 75, modelo v4.
  - Ele gera no site e manda o MP3, porque a rede da nuvem bloqueia o ElevenLabs.
  - Plano B, local: Kokoro `pm_alex`.

## Um vídeo novo, passo a passo

1. **Copiar o modelo:** copie `modelo/` para o scratchpad e rode `git init` lá, para poder desfazer.
2. **Roteiro:** escreva as 3 storylines (`/hyperframes` → `references/story.md`). Com a escolha dele, escreva `SPEC.md` com números e `STORYBOARD.md`.
3. **Telas:** capture com `ferramentas/captura/` (veja a seção da nuvem). Viewport 432×768 com `deviceScaleFactor: 2.5` dá 1080×1920.
4. **Voz:**
   - **Pedir:** mande o texto para ele gerar num arquivo só, de cerca de 27 s. Escreva "POV" como "Pí-ou-ví" e o site como "jessecoelho ponto com ponto br".
   - **Achar as pausas:** `ffmpeg -i voz.mp3 -af silencedetect=noise=-32dB:d=0.05 -f null -`
   - **Ver o que é dito em cada trecho:** `voz-transcrever.py voz16k.wav "<pausas>"`. O arquivo `voz16k.wav` sai de `ffmpeg -i voz.mp3 -ar 16000 -ac 1 voz16k.wav`.
   - **Achar o corte dentro de uma palavra:** use a curva de energia de 20 ms. O vale entre "feira" e "e ainda", por exemplo, estava a −41 dB.
   - **Cortar:** escreva `cortes.txt` com "nome início fim" (exemplo: `ferramentas/cortes-fazenda.txt`) e rode `bash ferramentas/voz-cortar.sh voz.mp3 cortes.txt assets/vo <ganho_dB>`.
   - **Ganho:** ponha o ganho nos próprios arquivos (no modelo foi +3 dB). O `volume` acima de 1 no `<audio>` não aumenta o som. Mire em cerca de −16 LUFS no filme final (no modelo deu −16,5 LUFS).
   - **Conferir:** rode `voz-conferir.py assets/vo/*.wav`. Cada arquivo precisa ter a frase inteira, sem palavra partida.
   - **Encaixar:** cada fala entra em `VOZ` no `gerar.py` com arquivo, início no filme e texto da legenda. No texto, `/` separa os grupos. Uma fala precisa terminar antes do início da próxima. Se não terminar, mude os tempos das cenas.
5. **Montar:**
   - Edite em `gerar.py` as listas `VOZ`, `SFX`, `CENAS`, `EXPRESSOES` e `GESTO` e as funções `s1()` a `s6()`.
   - Rode `python3 gerar.py` e depois `npx hyperframes@0.8.197 check --json`.
6. **Revisar:**
   - Rode `snapshot --review` e siga `references/review.md`, terminando no `REVIEW.md`.
   - Renderize o rascunho, mande com SendUserFile e espere a resposta dele.

## O personagem

### Como o modelo usa as poses (o jeito atual)

- **Lista:** `POSES_T` no `gerar.py` diz a pose de cada frase, como uma lista `[(tempo, pose)]`.
  - Exemplos: mão no cabelo no "Rola o currículo…", surpreso de mãos abertas na revelação, joinha, rindo gesticulando, pensativo, selfie no "Desce até Projetos" e joinha no fim.
- **Alinhamento:** cada pose é alinhada pelo pé (`poses.json`), com a altura igualada a 1130 px (2×). O pé fica abaixo do quadro, e ele aparece do joelho para cima.
- **Tamanho e posição:**
  - grande (gancho e final): `G` = pé em (820, 2308), escala 2.05;
  - pequeno (meio): `P` = pé em (905, 2106), escala 1.25.
- **Troca de pose:**
  - fusão de 0,1 s (`TROCA`); mais longa que isso, aparece um fantasma de duas poses;
  - `#ps-troca` vai de scaleX 1.025 / scaleY 0.955 / y 10 até 1 em 0,34 s, com `back.out(2.4)`.
- **Respiração:** `#ps-resp` faz scaleY 1→1.014 e um giro de ±0,6° em 0,8 s, com yoyo e repetição finita.
- **Fala:** em `#ps-corpo`, a energia da voz vira `y −9·e`, `scaleY 1+0.02·e` e um giro de `±1.1°·e`.
- **Caras e gesto:** as caras soltas e o gesto da mão no queixo continuam no kit (seções abaixo). São da versão anterior e servem para um vídeo em close no rosto.

### As caras

- **Arquivos:** `personagem/final/jesse-<cara>.webp`, com 836×1400 (2× de 418×700). As caras são sorriso, desconfiado, surpreso, sorriso_aberto, rindo, falando, piscando e neutro.
- **Como foram montadas:** `compor.py` junta o corpo da folha de expressões com a cabeça de cada quadrinho, encaixada pela gola. O registro usa a faixa da gola, com S 1.06, TX 96.6 e TY 12.1.
- **Espelhadas:** na folha, o braço esquerdo é cortado pela borda. Espelhado, o corte fica na borda direita do quadro. A borda direita da imagem é esticada 30 px, para o giro da fala não mostrar o corte.
- **Caras que ficaram de fora:** bravo, bravo_aberto, triste e pensativo, porque a cabeça inclinada ou a mão no queixo deixam emenda. O pensativo só entra pelo gesto.
- **Trocar de cara:** cada cara é uma imagem empilhada, e um `tl.set` liga a opacidade dela.
  - Cada troca tem um amassado: `#ps-cara` vai de scaleX 1.03 / scaleY 0.96 a 1 em 0,16 s, com `back.out(2)`.
  - `EXPRESSOES` é uma lista `[(tempo, cara)]`. Ponha cada troca no início de um grupo de legenda.

### Posição e fala

- **Posição:** vem de `estado(s)` no `gerar.py`. O corte do braço fica em x 1105, e a linha y 640 da imagem fica no pé do quadro.
  - Grande (gancho e final): escala 1.25, cabeça em y ≈ 1140 e x ≈ 855.
  - Pequeno (meio): escala 0.85, cabeça em y ≈ 1390. Ali a orelha encosta na coluna de botões do Instagram.
- **Fala:** a energia da voz é medida a cada 1/15 s (e). Ela vira `y −16·e`, `scaleY 1+0.035·e` e um giro de `±2.5°·e`, que troca de lado nas sílabas fortes. O movimento é em `#ps-corpo`, com a origem no pé.

### O gesto "mão sai do bolso e vai ao queixo"

- **Onde está:** `gesto.py` monta as camadas, e `GESTO` no `gerar.py` diz quando ele acontece.
- **Camadas:**
  - a base, sem cabeça e sem antebraço;
  - a cabeça;
  - o antebraço, que gira no cotovelo (36, 470) até −143.8° e leva a mão do pensativo junto.
- **Detalhe da mão:** a mão tem `rotate(143.8deg)` fixo dentro do braço, então chega reta ao queixo. Ao chegar, a cabeça troca para pensativo.
- **Volta:** o braço gira de volta a 0 e a figura inteira reaparece.
- **Prévia sem render:** `previa_gesto.py`.

### Poses de corpo inteiro

- **Arquivos:** `personagem/poses/*.webp`, em 2× e com fundo transparente: neutro, sorriso, afirmativo (joinha), pensativo, raiva, surpreso (mãos abertas), rindo (gesticulando), triste, foto (selfie), caminhando, cabelo (mão no cabelo) e costas.
- **Alinhar:** `poses.json` traz `pe_x` e `pe_y`, para alinhar uma pose na outra pelo pé.
- **Usos:** joinha no "Bora plantar!", selfie, ou ele indo embora de costas.
- **Não misture com as caras:** as poses vêm de outra folha, e o rosto e a escala não batem com as caras. Troque de uma vez, com um corte ou um chicote, e nunca misture as duas no mesmo trecho.
- **Sombras nos pés:** sobram sombras claras nos pés de algumas poses (sorriso, afirmativo, rindo, triste e foto). Enquadre acima do joelho ou limpe antes de mostrar os pés.
- **Mais poses:** peça para ele gerar outra folha no mesmo estilo (mesmo personagem, fundo liso, uma pose por quadro). Depois rode `poses.py` com as caixas novas.

## A nuvem: o que já deu errado

- **jsdelivr bloqueado:**
  - o GSAP está em `modelo/assets/vendor/gsap.min.js`;
  - o portfólio (`index-v4.html`) puxa bibliotecas do jsdelivr. Sirva essas bibliotecas de um `node_modules` local com `Access-Control-Allow-Origin` (veja `cap-port.js`).
- **Hugging Face bloqueado:** `npx hyperframes transcribe` falha. Transcreva com sherpa-onnx e o whisper-small que vem do GitHub:
  ```
  python3 -m venv venv-asr && venv-asr/bin/pip install sherpa-onnx soundfile numpy
  mkdir -p modelos-asr && curl -L https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.tar.bz2 | tar xj -C modelos-asr
  ```
  Os scripts leem o modelo de `WHISPER_DIR` (padrão `modelos-asr/sherpa-onnx-whisper-small`).
- **Kokoro (plano B):** crie um venv com `pip install kokoro-onnx soundfile` e rode `HYPERFRAMES_PYTHON=<venv>/bin/python npx hyperframes tts --voice pm_alex --lang pt-br`.
- **download.pytorch.org bloqueado:** não há upscaler de IA. Os desenhos aguentam cerca de 1,3× com Lanczos.
- **ffmpeg num `while read`:** use `-nostdin`, senão ele come o começo da próxima linha. Decodifique o MP3 para WAV antes de cortar.
- **Pillow 12:** `ImageDraw.floodfill` não funciona numa imagem "L". Converta a máscara para RGB.
- **Capturas do jogo (`captura/cap-*.js`):**
  - os scripts servem o repositório em localhost:8154 e respondem as RPCs do Supabase com um Postgres local (porta 5499, socket `/var/lib/postgresql/teste-fazenda`);
  - o banco `dreels` tem `supabase/fazenda.sql` carregado, a fazenda de vitrine do Jessé no nível 35 e `alter database dreels set fazenda.estacao_teste='primavera'`;
  - numa sessão nova o cluster não existe: crie com `initdb` e carregue `supabase/fazenda.sql`. Para ligar:
    ```
    su postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/teste-fazenda/data -o '-p 5499 -k /var/lib/postgresql/teste-fazenda' -l /var/lib/postgresql/teste-fazenda/log.txt start"
    ```
  - nunca rode nada no Supabase de verdade: ele roda o SQL na mão.
