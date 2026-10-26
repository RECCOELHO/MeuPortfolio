# Transcreve cada trecho de fala entre as pausas (para achar onde cortar a voz).
# Uso: venv-asr/bin/python voz-transcrever.py <voz-16k.wav> "0.62-1.06 1.62-1.68 ..."   (pausas do silencedetect)
# Modelo: sherpa-onnx-whisper-small (GitHub, releases asr-models); o Hugging Face é bloqueado na nuvem.
import sherpa_onnx, soundfile as sf, numpy as np, sys
import os
M = os.environ.get('WHISPER_DIR', 'modelos-asr/sherpa-onnx-whisper-small') + '/'
rec = sherpa_onnx.OfflineRecognizer.from_whisper(encoder=M + 'small-encoder.int8.onnx', decoder=M + 'small-decoder.onnx',
                                                 tokens=M + 'small-tokens.txt', language='pt', task='transcribe', num_threads=4)
a, sr = sf.read(sys.argv[1], dtype='float32')
# trechos de fala entre as pausas (>= 50 ms a -32 dB)
pausas = [tuple(map(float, p.split('-'))) for p in sys.argv[2].split()]
cortes = [0.0] + [(x + y) / 2 for x, y in pausas] + [len(a) / sr]
cortes = sorted(set(round(c, 3) for c in cortes))
for i in range(len(cortes) - 1):
    t0, t1 = cortes[i], cortes[i + 1]
    if t1 - t0 < 0.12: continue
    s = rec.create_stream(); s.accept_waveform(sr, a[int(t0 * sr):int(t1 * sr)]); rec.decode_stream(s)
    print(f'{t0:6.2f}-{t1:6.2f}  {s.result.text.strip()}')
