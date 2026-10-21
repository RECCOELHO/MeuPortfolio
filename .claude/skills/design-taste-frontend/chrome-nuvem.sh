#!/bin/sh
# sessões na nuvem rodam como root: o Chromium só abre com --no-sandbox (ver ORIGEM.md)
exec /opt/pw-browsers/chromium --no-sandbox "$@"
