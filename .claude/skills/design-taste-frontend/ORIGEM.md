# De onde veio esta skill

- Repositório: https://github.com/Leonxlnx/taste-skill (pasta `skills/taste-skill`), licença MIT (ver `LICENSE`).
- Commit copiado: 6010f91, em 21/10/2026. A pasta `evals/` ficou de fora (só serve para testar a própria skill).
- Para atualizar: copiar de novo a pasta `skills/taste-skill` do repositório por cima desta.

## Nas sessões na nuvem (claude.ai/code)
O `inspect.mjs` precisa de um Chrome. Aqui ele fica em `/opt/pw-browsers/chromium`:

    CHROME_PATH=.claude/skills/design-taste-frontend/chrome-nuvem.sh node .claude/skills/design-taste-frontend/scripts/inspect.mjs index.html

(`chrome-nuvem.sh` só abre o Chromium com `--no-sandbox`, porque lá tudo roda como root.)

Os arquivos de trabalho da skill ficam em `.taste-skill/` na raiz do projeto (fora do git, ver `.gitignore`).
