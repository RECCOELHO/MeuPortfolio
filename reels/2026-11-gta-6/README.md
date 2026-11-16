# Reels do GTA 6 (semana de 16 a 22/11/2026)

Guardado aqui porque o ambiente da nuvem foi reiniciado em 16/11 e apagou os projetos locais.

- `codigo/`: o motor dos Reels (`motor.py`, receita `reels-jesse`), os roteiros (`roteiros_gta.py`), um arquivo por vídeo (`gta_a.py`, `gta_b.py`, `gta_c.py`), o gravador das telas (`gravar_gta.js`, relógio virtual, 1080x1920) e a voz local (`sintetizar.py`, Kokoro `pm_alex`).
- `voz/`: as falas geradas (provisórias; a voz escolhida pelo Jessé é a Lendário do ElevenLabs).
- `telas/`: as gravações do site e do jogo. A rolagem do site começa em 2018: o topo (crachá com a foto da Elena) nunca entra.
- `codigo-reels-semana/`: os roteiros e configurações dos Reels de serviços, Pedruu e vaquinha (rascunhos de 14/11).

Para montar de novo: copiar `modelo/assets` da skill `reels-jesse` para `<projeto>/assets`, pôr as vozes em `assets/vo` e as telas em `assets/telas`, e rodar `python3 gta_a.py` (idem b, c). Render: `./renderizar.sh gta-a draft|delivery`.
Não usar logo, arte, trailer nem música da Rockstar: só o nome do jogo.
