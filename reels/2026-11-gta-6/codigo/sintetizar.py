# Voz local (Kokoro pm_alex, pt-br): um arquivo por fala. Uso: sintetizar.py <saida_dir> <velocidade> <arquivo.json com {id: texto}>
import sys, json, kokoro_onnx, soundfile as sf, numpy as np
out, vel, falas = sys.argv[1], float(sys.argv[2]), json.load(open(sys.argv[3]))
m = kokoro_onnx.Kokoro('/root/.cache/hyperframes/tts/models/kokoro-v1.0.onnx', '/root/.cache/hyperframes/tts/voices/voices-v1.0.bin')
for k, t in falas.items():
    a, sr = m.create(t, voice='pm_alex', speed=vel, lang='pt-br')
    a = np.asarray(a, dtype='float32')
    # tira o silêncio das pontas (deixa 40 ms) e normaliza o pico em -1,5 dB
    lim = 0.004 * np.abs(a).max(); idx = np.where(np.abs(a) > lim)[0]
    a = a[max(0, idx[0] - int(0.09 * sr)): idx[-1] + int(0.16 * sr)]
    a = a / np.abs(a).max() * 0.84
    sf.write(f'{out}/{k}.wav', a, sr, subtype='PCM_16')
    print(k, round(len(a) / sr, 2), 's', flush=True)