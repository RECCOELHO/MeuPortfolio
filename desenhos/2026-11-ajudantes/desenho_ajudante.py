#!/usr/bin/env python3
"""Folha do Jessé (4 desenhos no fundo verde: frente, passo 1, passo 2, busto) -> entradas do DESENHO_BICHO.
Uso: desenho_ajudante.py <imagem> <prefixo> [altura_g=69] [fator=3] [altura_busto=79]
Não redesenha: recorta, reduz (média só dos pixels do desenho, sem o verde) e junta as cores em até 14."""
import sys, json
import numpy as np
from PIL import Image

img, pref = sys.argv[1], sys.argv[2]
ALT_G = int(sys.argv[3]) if len(sys.argv) > 3 else 69
F = int(sys.argv[4]) if len(sys.argv) > 4 else 3
ALT_B = int(sys.argv[5]) if len(sys.argv) > 5 else 79
A = np.asarray(Image.open(img).convert('RGB')).astype(np.int32)
r, g, b = A[..., 0], A[..., 1], A[..., 2]
fundo = (g > 120) & (g - np.maximum(r, b) > 45)          # o verde (e a borda esverdeada)
fg = ~fundo
# as 4 figuras: colunas com desenho, separadas por faixas vazias
col = fg.sum(0) > 2
spans, x = [], 0
while x < len(col):
    if col[x]:
        x0 = x
        while x < len(col) and col[x]: x += 1
        spans.append([x0, x])
    else: x += 1
junt = []
for s in spans:
    if junt and s[0] - junt[-1][1] < 6: junt[-1][1] = s[1]
    else: junt.append(s)
junt = [s for s in junt if s[1] - s[0] > 20]
assert len(junt) == 4, ('achei', len(junt), 'figuras', junt)
caixas = []
for x0, x1 in junt:
    linhas = np.where(fg[:, x0:x1].sum(1) > 1)[0]
    caixas.append((x0, linhas[0], x1, linhas[-1] + 1))
print('caixas', caixas, file=sys.stderr)
NC = int(__import__('os').environ.get('CORES', 24))
pxs = A[fg].astype(np.uint8)
qimg = Image.fromarray(pxs.reshape(1, -1, 3)).quantize(colors=NC, method=Image.Quantize.MEDIANCUT)
PAL = np.array(qimg.getpalette()[:3 * NC]).reshape(-1, 3)
IDX = np.full(fg.shape, -1, dtype=np.int32); IDX[fg] = np.asarray(qimg).reshape(-1)

def reduz(x0, y0, x1, y1, w, h):
    """cada pixel novo = a cor (da paleta da folha) que mais aparece no pedaço, se o desenho cobre metade ou mais"""
    idx = IDX[y0:y1, x0:x1]
    H, W = idx.shape
    ys = np.linspace(0, H, h + 1); xs = np.linspace(0, W, w + 1)
    out = np.zeros((h, w, 4))
    for j in range(h):
        a0, a1 = int(round(ys[j])), max(int(round(ys[j])) + 1, int(round(ys[j + 1])))
        for i in range(w):
            b0, b1 = int(round(xs[i])), max(int(round(xs[i])) + 1, int(round(xs[i + 1])))
            blk = idx[a0:a1, b0:b1].ravel(); v = blk[blk >= 0]
            if len(v) * 2 >= blk.size:
                out[j, i, :3] = PAL[np.bincount(v).argmax()]; out[j, i, 3] = 255
    return out

def reduz_rgba(src, f):
    """o grande -> o pequeno (dividido por f): média das cores do pedaço, puxada para a cor mais próxima do próprio desenho
    (fica macio e sem o pontilhado do contorno; o contorno só entra onde ele domina o pedaço)"""
    h, w = src.shape[0] // f, src.shape[1] // f
    cores = np.unique(src[src[..., 3] > 0][:, :3], axis=0).astype(np.float64)
    out = np.zeros((h, w, 4))
    for j in range(h):
        for i in range(w):
            blk = src[j * f:(j + 1) * f, i * f:(i + 1) * f].reshape(-1, 4); v = blk[blk[:, 3] > 0][:, :3]
            if len(v) * 2 < len(blk): continue
            escuro = (v.sum(1) < 150)
            base = v if escuro.mean() > 0.6 else v[~escuro]      # o contorno só se ele for a maior parte
            m = base.mean(0)
            out[j, i, :3] = cores[((cores - m) ** 2).sum(1).argmin()]; out[j, i, 3] = 255
    return out

def paleta(rgba, n=26):
    op = rgba[..., 3] > 0
    px = [tuple(int(c) for c in p) for p in rgba[op][:, :3]]
    usados = sorted(set(px), key=lambda c: -px.count(c))[:n]
    letra = {c: 'abcdefghijklmnopqrstuvwxyz'[k] for k, c in enumerate(usados)}
    lin = np.full(op.shape, '.', dtype='<U1'); lin[op] = [letra.get(c, letra[usados[0]]) for c in px]
    return {letra[c]: '#%02x%02x%02x' % c for c in usados}, [''.join(l) for l in lin]

saida = {}
x0, y0, x1, y1 = caixas[0]
k = ALT_G / (y1 - y0)                       # a mesma escala para os 3 do corpo (pela altura da frente)
for nome, (a0, b0, a1, b1) in zip(['frente', 'passo1', 'passo2'], caixas[:3]):
    w = int(round((a1 - a0) * k)); w += (-w) % F
    h = int(round((b1 - b0) * k)); h += (-h) % F
    g_ = reduz(a0, b0, a1, b1, w, h)
    p_ = reduz_rgba(g_, F)
    for suf, arr in (('_g', g_), ('_p', p_)):
        pal, lin = paleta(arr)
        saida[f'{pref}_{nome}{suf}'] = dict(pal=pal, linhas=lin)
        print(f'{pref}_{nome}{suf}', arr.shape[1], 'x', arr.shape[0], len(pal), 'cores', file=sys.stderr)
a0, b0, a1, b1 = caixas[3]
kb = ALT_B / (b1 - b0)
bb = reduz(a0, b0, a1, b1, int(round((a1 - a0) * kb)), ALT_B)
pal, lin = paleta(bb)
saida[f'{pref}_busto'] = dict(pal=pal, linhas=lin)
print(f'{pref}_busto', bb.shape[1], 'x', bb.shape[0], len(pal), 'cores', file=sys.stderr)
# o trecho para o fazenda-arte.js, no formato das outras entradas
js = []
for nome, d in saida.items():
    pal = ', '.join(f"{k}: '{v}'" for k, v in d['pal'].items())
    lin = ', '.join(f"'{l}'" for l in d['linhas'])
    js.append(f"        {nome}: {{ pal: {{ {pal} }}, linhas: [{lin}] }},")
print('\n'.join(js))
# prévia para conferir (cada sprite ampliado)
prev = []
for nome, d in saida.items():
    h, w = len(d['linhas']), len(d['linhas'][0])
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0)); px = im.load()
    for y, l in enumerate(d['linhas']):
        for x, ch in enumerate(l):
            if ch != '.': c = d['pal'][ch]; px[x, y] = (int(c[1:3], 16), int(c[3:5], 16), int(c[5:7], 16), 255)
    esc = 8 if nome.endswith('_p') else 3
    prev.append(im.resize((w * esc, h * esc), Image.NEAREST))
W = sum(p.width for p in prev) + 10 * len(prev); H = max(p.height for p in prev)
folha = Image.new('RGBA', (W, H), (132, 198, 105, 255)); x = 0
for p in prev: folha.alpha_composite(p, (x, H - p.height)); x += p.width + 10
folha.convert('RGB').save(img.rsplit('.', 1)[0] + f'-{pref}-previa.png')
