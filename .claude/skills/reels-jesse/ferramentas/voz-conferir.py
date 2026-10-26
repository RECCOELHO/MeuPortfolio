# Transcreve cada arquivo cortado para conferir que a fala está inteira (sem palavra partida no meio).
# Uso: venv-asr/bin/python voz-conferir.py assets/vo/*.wav
import sherpa_onnx, soundfile as sf, numpy as np, sys, subprocess, io
import os
M = os.environ.get('WHISPER_DIR', 'modelos-asr/sherpa-onnx-whisper-small') + '/'
rec = sherpa_onnx.OfflineRecognizer.from_whisper(encoder=M + 'small-encoder.int8.onnx', decoder=M + 'small-decoder.onnx',
                                                 tokens=M + 'small-tokens.txt', language='pt', task='transcribe', num_threads=4)
for f in sys.argv[1:]:
    raw = subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-i', f, '-ar', '16000', '-ac', '1', '-f', 'f32le', '-'], capture_output=True).stdout
    a = np.frombuffer(raw, dtype=np.float32)
    a = np.concatenate([np.zeros(4000, np.float32), a, np.zeros(8000, np.float32)])
    s = rec.create_stream(); s.accept_waveform(16000, a); rec.decode_stream(s)
    print(f.split('/')[-1], '|', s.result.text.strip())
