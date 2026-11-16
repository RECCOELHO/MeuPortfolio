#!/bin/bash
# renderiza um projeto e acerta o volume em -16 LUFS. Uso: renderizar.sh <projeto> [draft|delivery]
set -e
R=$(dirname "$(readlink -f "$0")"); P=$R/$1; Q=${2:-draft}
cd $P && mkdir -p renders
npx --yes hyperframes@0.8.197 render -q $Q --video-frame-format png -o renders/bruto-$Q.mp4 --skill hyperframes > renders/render-$Q.log 2>&1
J=$(ffmpeg -nostdin -i renders/bruto-$Q.mp4 -af "loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json" -f null - 2>&1 | sed -n '/^{/,/^}/p')
MI=$(echo "$J" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"measured_I={d['input_i']}:measured_TP={d['input_tp']}:measured_LRA={d['input_lra']}:measured_thresh={d['input_thresh']}:offset={d['target_offset']}\")")
ffmpeg -nostdin -v error -y -i renders/bruto-$Q.mp4 -af "loudnorm=I=-16:TP=-1.5:LRA=11:$MI:linear=true,aresample=48000" -c:v copy -c:a aac -b:a 192k -movflags +faststart renders/reels-$1-$Q.mp4
echo "$1 $Q: $(ffprobe -v error -show_entries format=duration,size -of csv=p=0 renders/reels-$1-$Q.mp4) $(ffmpeg -nostdin -i renders/reels-$1-$Q.mp4 -af ebur128=peak=true:framelog=quiet -f null - 2>&1 | grep -E '^\s+I:|^\s+Peak:' | tr -s ' ' | tr '\n' ' ')"
