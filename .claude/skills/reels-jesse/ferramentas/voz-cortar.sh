#!/usr/bin/env bash
# Corta a voz inteira (um arquivo só, ex.: o MP3 do ElevenLabs) numa fala por arquivo.
# Uso: bash voz-cortar.sh <voz.mp3> <cortes.txt> <pasta-de-saída> [ganho_dB]
# cortes.txt: uma fala por linha, "nome início fim" em segundos no arquivo original (ex.: "vo1 0.00 2.68").
# Ache os cortes com as pausas (ffmpeg silencedetect) e confira cada pedaço com voz-conferir.py.
set -euo pipefail
SRC=$1; LISTA=$2; OUT=$3; GANHO=${4:-0}
mkdir -p "$OUT"
TMP=$(mktemp --suffix=.wav)
ffmpeg -nostdin -y -loglevel error -i "$SRC" -ac 1 -ar 44100 "$TMP"   # mp3 -> wav: o corte fica exato na amostra
while read -r n a b; do
  [ -z "${n:-}" ] && continue
  d=$(python3 -c "print(round($b-$a,3))"); f=$(python3 -c "print(round($b-$a-0.03,3))")
  # -nostdin: sem ele o ffmpeg come o começo da próxima linha da lista
  ffmpeg -nostdin -y -loglevel error -i "$TMP" \
    -af "atrim=start=$a:end=$b,asetpts=PTS-STARTPTS,afade=t=in:d=0.012,afade=t=out:st=$f:d=0.03,volume=${GANHO}dB,alimiter=limit=0.85:level=false" \
    "$OUT/$n.wav"
  echo "$n ${d}s"
done < "$LISTA"
rm -f "$TMP"
