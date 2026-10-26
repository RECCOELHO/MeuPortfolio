# Monta o Jessé desenhado: o corpo da folha + a cabeça de cada expressão, encaixada pela gola.
# Uso: python3 compor.py [nomes...]  ->  final/jesse-<nome>.webp (836 x 1400 = 2x de 418 x 700, fundo transparente,
# espelhado para o braço cortado da folha ficar na borda direita, que é esticada 30 px para o giro da fala não mostrar o corte)
# As caras boas: sorriso desconfiado surpreso sorriso_aberto rindo falando piscando neutro.
# Bravo, bravo_aberto, triste e pensativo têm a cabeça inclinada ou a mão no queixo e saem com emendas.
from PIL import Image, ImageDraw, ImageFilter
import numpy as np, sys, json

F = 2                                  # trabalha em 2x
FOLHA = Image.open('folha-expressoes.webp').convert('RGB')
TILES = {'neutro':(390,41,593,300),'sorriso':(610,41,808,300),'sorriso_aberto':(825,41,1022,300),'rindo':(1039,41,1236,300),
         'falando':(406,358,598,616),'surpreso':(614,358,810,616),'bravo':(827,358,1023,616),'bravo_aberto':(1039,358,1236,616),
         'triste':(396,678,594,923),'desconfiado':(611,678,808,923),'piscando':(825,678,1022,923),'pensativo':(1039,678,1236,923)}
S, TX, TY = 1.06, 96.6, 12.1           # neutro -> corpo (1x)
Y_OMBRO, X0, X1 = 196, 46, 152         # no neutro: acima do ombro tudo é cabeça; abaixo, só a faixa do pescoço
CONTORNO = np.array([18, 12, 10], float)

def up(im): return im.resize((im.width * F, im.height * F), Image.LANCZOS)
def filtro(m, f): return np.array(Image.fromarray((m * 255).astype(np.uint8)).filter(f)) > 127

def fundo(im, sementes, thresh):
    m = im.copy()
    for s in sementes:
        if m.getpixel(s) != (255, 0, 255):
            ImageDraw.floodfill(m, s, (255, 0, 255), thresh=thresh)
    a = np.array(m)
    return (a[..., 0] == 255) & (a[..., 1] == 0) & (a[..., 2] == 255)

def alfa_borda(a, bg, cor_bg):
    # perto do fundo, o pixel é mistura do contorno escuro com o fundo: separa os dois
    c = a.astype(float); v = CONTORNO - cor_bg
    t = ((c - cor_bg) @ v) / (v @ v)
    faixa = ~bg & filtro(bg, ImageFilter.MaxFilter(7))
    alfa = np.where(faixa, np.clip(t * 1.15, 0, 1), (~bg).astype(float))
    limpa = np.where(faixa[..., None] & (alfa[..., None] > 0.02),
                     np.clip((c - (1 - alfa[..., None]) * cor_bg) / np.maximum(alfa[..., None], 0.02), 0, 255), c)
    return alfa, limpa

def vermelho(a):
    a = a.astype(int); g, b = a[..., 1], a[..., 2]
    r = (g < 42) & (a[..., 0] > 70) & (a[..., 0] - g > 50) & (b >= g * 0.75 - 3)
    # só conta como camisa se continuar vermelho logo abaixo
    c = np.cumsum(np.vstack([np.zeros((1, r.shape[1]), int), r.astype(int)]), 0)
    k = 8
    seguido = np.zeros_like(r)
    seguido[:-k] = (c[k:-1] - c[:-k - 1]) == k
    return r, seguido

def registrar(t, ref):
    ga = np.array(t.convert('L')).astype(float); gb = np.array(ref.convert('L')).astype(float)
    y0, y1, x0, x1 = 196, 244, 25, 175
    melhor = None
    for dy in range(-22, 23):
        for dx in range(-22, 23):
            ya, yb = y0 + dy, y1 + dy; xa, xb = x0 + dx, x1 + dx
            if ya < 0 or yb > ga.shape[0] or xa < 0 or xb > ga.shape[1]: continue
            e = np.abs(ga[ya:yb, xa:xb] - gb[y0:y1, x0:x1]).mean()
            if melhor is None or e < melhor[0]: melhor = (e, dx, dy)
    return melhor

def cabeca(nome, d):
    t = FOLHA.crop(TILES[nome]); W, H = t.size
    tu = up(t); a = np.array(tu)
    cor_bg = a[20:40, 20:40].reshape(-1, 3).mean(0)
    bg = fundo(tu, [(0, 0), (W * F - 1, 0), (24, 24), (W * F - 25, 24), (8, 200), (W * F - 9, 200), (8, 300), (W * F - 9, 300), (0, H * F - 1), (W * F - 1, H * F - 1)], 38)
    # bolsões do fundo presos entre os cachos
    bg |= (np.abs(a.astype(float) - cor_bg).sum(2) < 30) & (np.mgrid[0:H * F, 0:W * F][0] < 110 * F)
    alfa, limpa = alfa_borda(a, bg, cor_bg)
    red, seguido = vermelho(a)
    hh, ww = bg.shape
    yy, xx = np.mgrid[0:hh, 0:ww]
    dx, dy = d
    xn = xx / F - dx; yn = yy / F - dy
    primeiro = np.full(ww, hh)
    for x in range(ww):
        col = np.where(seguido[:, x] & (yy[:, x] / F > 170 + dy))[0]
        if len(col): primeiro[x] = col[0]
    # a corrente cruza a gola: mediana dos vizinhos
    primeiro = np.array([np.median(primeiro[max(0, x - 8):x + 9]) for x in range(ww)])
    perto = filtro(red, ImageFilter.MaxFilter(9)) & (yn > Y_OMBRO - 20)
    fora = (xn < X0) | (xn > X1)
    borda = (xx >= 3 * F) & (xx < ww - 3 * F) & (yy >= 2 * F) & (yy < hh - 4 * F)
    corte = borda & ~(fora & perto) & ((yn < Y_OMBRO) | (~fora & (yy < primeiro[None, :])))
    corte = np.array(Image.fromarray((corte * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7))) / 255
    out = np.dstack([limpa, np.clip(alfa * corte, 0, 1) * 255]).astype(np.uint8)
    rgba = Image.fromarray(out, 'RGBA')
    novo = rgba.resize((round(rgba.width * S), round(rgba.height * S)), Image.LANCZOS)
    return novo, (round(F * (TX - dx * S)), round(F * (TY - dy * S)))

def corpo():
    b = FOLHA.crop((0, 0, 388, 950)); bu = up(b); a = np.array(bu)
    cor_bg = np.array([243, 237, 233], float)
    bg = fundo(bu, [(bu.width - 1, 0), (bu.width - 1, 1000), (bu.width - 1, 1890), (300, 0), (700, 0), (10, 10), (10, 1800)], 34)
    alfa, limpa = alfa_borda(a, bg, cor_bg)
    alfa[: int(216 * F), :] = 0        # tira a cabeça original
    return Image.fromarray(np.dstack([limpa, alfa * 255]).astype(np.uint8), 'RGBA')

if __name__ == '__main__':
    ref = FOLHA.crop(TILES['neutro'])
    nomes = sys.argv[1:] or ['sorriso', 'desconfiado', 'surpreso', 'sorriso_aberto', 'rindo', 'falando', 'piscando', 'neutro']
    base = corpo()
    reg = {}
    for n in nomes:
        e, dx, dy = registrar(FOLHA.crop(TILES[n]), ref) if n != 'neutro' else (0, 0, 0)
        reg[n] = (dx, dy, round(e, 1))
        cab, (px, py) = cabeca(n, (dx, dy))
        out = base.copy()
        out.paste(cab, (px, py), cab) if (px < 0 or py < 0) else out.alpha_composite(cab, (px, py))
        im = out.crop((0, 0, 776, 1400)).transpose(Image.FLIP_LEFT_RIGHT)
        a = np.pad(np.array(im), ((0, 0), (0, 60), (0, 0)), mode='edge')
        Image.fromarray(a, 'RGBA').save(f'final/jesse-{n}.webp', quality=90, method=6)
    print(json.dumps(reg))
