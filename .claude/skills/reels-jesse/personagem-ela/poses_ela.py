# Recorta as 13 poses de corpo inteiro da Ranya (folha-poses-ela.webp), com fundo transparente, em 2x.
# Mesmo método do personagem/poses.py do Jessé, com os quadros e caixas desta folha.
# Uso: python3 poses_ela.py  ->  poses/<nome>.webp  +  poses/poses.json (tamanho e onde fica o pé de cada uma)
from PIL import Image, ImageDraw, ImageFilter
import numpy as np, json, os

F = 2
FOLHA = Image.open('folha-poses-ela.webp').convert('RGB')
PAGINA = np.array([238, 230, 222], float)
CONTORNO = np.array([18, 12, 10], float)
# quadro colorido atrás de cada pose (as poses sem quadro ficam direto na página)
# quadro colorido atrás de cada pose (todas as poses da Ranya têm quadro)
QUADROS = {'neutro': (23, 23, 205, 598), 'sorriso': (223, 23, 412, 598), 'afirmativo': (429, 23, 608, 598), 'pensativo': (625, 23, 822, 598), 'brava': (837, 23, 1033, 598), 'surpresa': (1050, 23, 1233, 598), 'triste': (23, 660, 180, 1190), 'pensando': (192, 660, 345, 1190), 'desconfiada': (351, 660, 508, 1190), 'confiante': (520, 660, 674, 1190), 'rindo': (686, 660, 831, 1190), 'seria': (844, 660, 997, 1190), 'de_lado': (1000, 660, 1134, 1190)}
# nome: (caixa do recorte na folha, centro do tronco para achar a figura)
POSES = {'neutro': ((15, 4, 213, 604), (114, 300)), 'sorriso': ((215, 4, 420, 604), (317, 300)), 'afirmativo': ((421, 4, 616, 604), (518, 300)), 'pensativo': ((617, 4, 830, 604), (723, 300)), 'brava': ((829, 4, 1041, 604), (935, 300)), 'surpresa': ((1042, 4, 1241, 604), (1141, 300)), 'triste': ((17, 644, 186, 1197), (101, 900)), 'pensando': ((186, 644, 351, 1197), (268, 900)), 'desconfiada': ((345, 644, 514, 1197), (429, 900)), 'confiante': ((514, 644, 680, 1197), (597, 900)), 'rindo': ((680, 644, 837, 1197), (758, 900)), 'seria': ((838, 644, 1003, 1197), (920, 900)), 'de_lado': ((994, 644, 1140, 1197), (1067, 900))}

def fundo(im, sementes, thresh):
    m = im.copy()
    for s in sementes:
        if m.getpixel(s) != (255, 0, 255):
            ImageDraw.floodfill(m, s, (255, 0, 255), thresh=thresh)
    a = np.array(m)
    return (a[..., 0] == 255) & (a[..., 1] == 0) & (a[..., 2] == 255)

def recorta(nome, caixa, centro):
    x0, y0, x1, y1 = caixa
    im = FOLHA.crop(caixa); im = im.resize((im.width * F, im.height * F), Image.LANCZOS)
    a = np.array(im).astype(float); H, W = a.shape[:2]
    dist = lambda c: np.abs(a - c).sum(2)
    cores = [PAGINA]
    sem = [(x, y) for x in range(0, W, 12) for y in (0, H - 1)] + [(x, y) for y in range(0, H, 12) for x in (0, W - 1)]
    if nome in QUADROS:
        qx0, qy0, qx1, qy1 = QUADROS[nome]
        cor_q = np.array(FOLHA.getpixel((qx0 + 8, qy0 + 8)), float); cores.append(cor_q)
        X0, Y0, X1, Y1 = [(v - o) * F for v, o in zip((qx0 + 6, qy0 + 6, qx1 - 6, qy1 - 6), (x0, y0, x0, y0))]
        sem += [(X, Y) for X in range(max(X0, 0), min(X1, W - 1), 20) for Y in (Y0, Y1) if 0 <= Y < H]
        sem += [(X, Y) for Y in range(max(Y0, 0), min(Y1, H - 1), 20) for X in (X0, X1) if 0 <= X < W]
    perto = lambda p: min(np.abs(a[p[1], p[0]] - c).sum() for c in cores) < 26
    sem = [p for p in sem if 0 <= p[0] < W and 0 <= p[1] < H and perto(p)]
    bg = fundo(im, sem, 70)        # o contorno escuro segura; a sombra do quadro vai junto
    # sombra cinza no chão: segunda passada, mais tolerante, só a partir da borda de baixo
    sem_chao = [(x, H - 1) for x in range(0, W, 8) if dist(PAGINA)[H - 1, x] < 60]
    bg |= fundo(im, sem_chao, 95)
    # bolsões do fundo presos (entre as pernas, entre braço e tronco)
    cand = (np.minimum.reduce([dist(c) for c in cores]) < 20) & ~bg
    cand = np.array(Image.fromarray((cand * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(7))) > 127
    vistos = np.zeros_like(cand)
    while True:
        ys, xs = np.where(cand & ~vistos)
        if not len(ys): break
        m = Image.fromarray((cand * 255).astype(np.uint8)).convert('RGB')
        ImageDraw.floodfill(m, (int(xs[0]), int(ys[0])), (255, 0, 255))
        mm = np.array(m); reg = (mm[..., 0] == 255) & (mm[..., 1] == 0)
        vistos |= reg
        if reg.sum() > 300:   # bolsão grande: enche a partir dele com a mesma tolerância
            bg |= fundo(im, [(int(xs[0]), int(ys[0]))], 70)
    fg = ~bg
    # fica só a figura ligada ao tronco (tira pedaços das vizinhas e linhas do quadro)
    fg = np.array(Image.fromarray((fg * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))) > 127
    m = Image.fromarray((fg * 255).astype(np.uint8)).convert('RGB')
    cx, cy = (centro[0] - x0) * F, (centro[1] - y0) * F
    ys, xs = np.where(fg[max(0, cy - 120):cy + 120, max(0, cx - 120):cx + 120])
    k = np.argmin((xs - 120) ** 2 + (ys - 120) ** 2)
    ImageDraw.floodfill(m, (int(xs[k]) + max(0, cx - 120), int(ys[k]) + max(0, cy - 120)), (255, 0, 255))
    mm = np.array(m); fg = (mm[..., 0] == 255) & (mm[..., 1] == 0)
    # borda: o pixel é mistura do contorno escuro com o fundo daquele ponto
    cor = np.where(bg[..., None], a, np.nan)
    viz = Image.fromarray(np.nan_to_num(cor).astype(np.uint8)).filter(ImageFilter.BoxBlur(6))
    peso = Image.fromarray((bg * 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(6))
    cor_bg = np.array(viz).astype(float) / np.maximum(np.array(peso)[..., None].astype(float) / 255, 1e-3)
    faixa = fg & (np.array(Image.fromarray(((~fg) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7))) > 127)
    v = CONTORNO - cor_bg
    t = ((a - cor_bg) * v).sum(2) / np.maximum((v * v).sum(2), 1)
    alfa = np.where(faixa, np.clip(t * 1.15, 0, 1), fg.astype(float))
    limpa = np.where((faixa & (alfa > 0.02))[..., None], np.clip((a - (1 - alfa[..., None]) * cor_bg) / np.maximum(alfa[..., None], 0.02), 0, 255), a)
    out = Image.fromarray(np.dstack([limpa, alfa * 255]).astype(np.uint8), 'RGBA')
    bb = out.getbbox(); out = out.crop(bb)
    al = np.array(out)[..., 3] > 40
    linhas = np.where(al.any(1))[0]; pe = int(linhas.max())
    return out, {'largura': out.width, 'altura': out.height, 'pe_y': pe,
                 'pe_x': int(np.where(al[pe - 30 * F:pe].any(0))[0].mean())}

if __name__ == '__main__':
    os.makedirs('poses', exist_ok=True)
    info = {}
    for nome, (caixa, centro) in POSES.items():
        print(nome, flush=True)
        im, dados = recorta(nome, caixa, centro)
        im.save(f'poses/{nome}.webp', quality=90, method=6)
        info[nome] = dados
    json.dump(info, open('poses/poses.json', 'w'), indent=1)
    print(json.dumps(info))
