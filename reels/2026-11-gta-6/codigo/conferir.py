import sherpa_onnx, soundfile as sf, sys, os, numpy as np
M = os.environ.get('WHISPER_DIR') + '/'
rec = sherpa_onnx.OfflineRecognizer.from_whisper(encoder=M + 'small-encoder.int8.onnx', decoder=M + 'small-decoder.onnx', tokens=M + 'small-tokens.txt', language='pt', task='transcribe', num_threads=4)
for f in sys.argv[1:]:
    a, sr = sf.read(f, dtype='float32')
    if sr != 16000:
        n = int(len(a) * 16000 / sr); a = np.interp(np.linspace(0, len(a) - 1, n), np.arange(len(a)), a).astype('float32'); sr = 16000
    a = np.concatenate([np.zeros(8000, 'float32'), a, np.zeros(12000, 'float32')])
    s = rec.create_stream(); s.accept_waveform(sr, a); rec.decode_stream(s)
    print(os.path.basename(f), '→', s.result.text.strip(), flush=True)