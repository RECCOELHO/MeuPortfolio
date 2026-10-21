# De onde vieram as skills desta pasta

| Skill | Repositório | Licença | Commit |
|---|---|---|---|
| design-taste-frontend | https://github.com/Leonxlnx/taste-skill (skills/taste-skill) | MIT | 6010f91 |
| agent-browser | https://github.com/vercel-labs/agent-browser (skills/agent-browser) | Apache-2.0 | fd93075 |
| find-skills | https://github.com/vercel-labs/skills (skills/find-skills) | MIT | a80e4c9 |
| hyperframes e as outras 21 de vídeo (hyperframes-*, embedded-captions, faceless-explainer, figma, general-video, media-use, motion-graphics, music-to-video, pr-to-video, product-launch-video, remotion-to-hyperframes, slideshow, talking-head-recut) | https://github.com/heygen-com/hyperframes (skills/) | Apache-2.0 | 32ebdde |

O "grilling" (Matt Pocock) não está aqui: ele vem pelo plugin "Skills For Real Engineers" do catálogo do Claude.

## Nas sessões na nuvem
- **agent-browser** precisa do programa: `npm i -g agent-browser`, e aqui usa o Chromium que já existe: `export AGENT_BROWSER_EXECUTABLE_PATH=/opt/pw-browsers/chromium AGENT_BROWSER_ARGS=--no-sandbox` (sites de fora não abrem por causa do proxy da nuvem; arquivos locais e servidor local abrem).
- **hyperframes** usa `npx hyperframes` (baixa na hora) e, para render de vídeo, o ffmpeg.
- **design-taste-frontend**: ver `design-taste-frontend/ORIGEM.md` (Chrome com `--no-sandbox`).
- **find-skills** usa `npx skills find`: nesta nuvem a busca voltou vazia (o site de busca deve estar bloqueado pela rede da sessão); no seu computador funciona normal.
