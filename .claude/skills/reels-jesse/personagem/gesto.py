# O gesto "mão no queixo": separa o antebraço do corpo para ele girar no cotovelo e subir até o queixo.
# Saída em final/ (mesma tela 836 x 1400 das caras, já espelhada e com a borda direita esticada):
#   gesto-base.webp       corpo sem cabeça e sem antebraço (lugar do braço preenchido, cotovelo arredondado)
#   gesto-antebraco.webp  só o antebraço, na posição de descanso (gira em PIVO)
#   gesto-cara-<nome>.webp só a cabeça (pensativo traz a mão no queixo)
from PIL import Image, ImageDraw, ImageFilter
import numpy as np, json
from compor import FOLHA, TILES, S, TX, TY, F, corpo, cabeca, registrar

W1 = 388                                    # largura do corpo em 1x (antes de espelhar)
PIVO = (352, 470)                           # cotovelo, em coordenadas do corpo sem espelhar (1x)
# contorno do antebraço (por dentro segue a linha do braço; por fora o recorte do fundo resolve)
BRACO = [(316, 470), (311, 500), (308, 540), (308, 600), (311, 640), (318, 680), (326, 710), (338, 745), (348, 757),
         (398, 757), (398, 470)]

def poligono(pts, tam):
    m = Image.new('L', tam, 0); ImageDraw.Draw(m).polygon([(x * F, y * F) for x, y in pts], fill=255)
    return np.array(m) > 127

def finalizar(im, espelhar=True, alt=1400):
    im = im.crop((0, 0, W1 * F, alt))
    if espelhar: im = im.transpose(Image.FLIP_LEFT_RIGHT)
    a = np.pad(np.array(im), ((0, 0), (0, 60), (0, 0)), mode='edge')
    return Image.fromarray(a, 'RGBA')

def main():
    base = corpo()                               # 2x, sem a cabeça
    a = np.array(base).copy()
    H, W = a.shape[:2]
    braco = poligono(BRACO, (W, H)) & (a[..., 3] > 0)
    # 1) o antebraço sozinho
    ante = np.zeros_like(a); ante[braco] = a[braco]
    # 2) a base: tira o antebraço e preenche com o lado do tronco
    yy, xx = np.mgrid[0:H, 0:W]
    borda = (318 + (yy / F - 470) * 8 / 230) * F          # linha do tronco atrás do braço (1x: 318 -> 326)
    tirar = braco.copy()
    b = a.copy(); b[tirar] = 0
    fonte = np.roll(a, 40 * F, axis=1)                      # textura da camisa 40 px à esquerda
    camisa = tirar & (xx < borda - 2 * F)
    b[camisa] = fonte[camisa]; b[camisa, 3] = 255
    linha = tirar & (xx >= borda - 2 * F) & (xx < borda + 1.5 * F)
    b[linha] = [20, 12, 10, 255]
    # cotovelo arredondado: o braço de cima termina num meio círculo com contorno
    cx, cy, rx, ry = PIVO[0] * F, PIVO[1] * F, 40 * F, 30 * F
    dentro = (((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 <= 1) & (yy >= cy) & braco
    b[dentro] = a[dentro]
    anel = (((xx - cx) / (rx + 2.5 * F)) ** 2 + ((yy - cy) / (ry + 2.5 * F)) ** 2 <= 1) & ~dentro & (yy >= cy) & braco & (xx > borda)
    b[anel] = [20, 12, 10, 255]
    Image.fromarray(b, 'RGBA').filter(ImageFilter.SMOOTH_MORE)
    finalizar(Image.fromarray(b, 'RGBA')).save('final/gesto-base.webp', quality=90, method=6)
    fade = np.clip((730 * F - yy) / (18 * F), 0, 1)
    ante[..., 3] = (ante[..., 3] * fade).astype(np.uint8)
    finalizar(Image.fromarray(ante, 'RGBA'), alt=1560).save('final/gesto-antebraco.webp', quality=90, method=6)
    # 3) as cabeças sozinhas
    ref = FOLHA.crop(TILES['neutro'])
    for nome in ['desconfiado', 'surpreso', 'pensativo']:
        e, dx, dy = registrar(FOLHA.crop(TILES[nome]), ref)
        cab, (px, py) = cabeca(nome, (dx, dy))
        tela = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        if nome == 'pensativo':
            # sem espelhar, para a mão cair no braço inteiro; corta o pedaço de antebraço do quadrinho
            c = np.array(cab); hh = c.shape[0]
            corte = Image.new('L', (c.shape[1], c.shape[0]), 0)
            ImageDraw.Draw(corte).polygon([(x * F * S, y * F * S) for x, y in [(40, 224), (106, 219), (113, 247), (36, 247)]], fill=255)
            c[np.array(corte) > 127, 3] = 0
            cab = Image.fromarray(c, 'RGBA')
            pxf = round(F * ((W1 - 201) - 98.5 * S - dx * S))
            tela.alpha_composite(cab, (pxf, py))
            tela = tela.transpose(Image.FLIP_LEFT_RIGHT)   # desfaz o espelho do finalizar
        else:
            tela.alpha_composite(cab, (px, py))
        finalizar(tela).save(f'final/gesto-cara-{nome}.webp', quality=90, method=6)
    # a mão do pensativo sozinha, no lugar final (coordenadas finais), para andar com o antebraço
    e, dx, dy = registrar(FOLHA.crop(TILES['pensativo']), ref)
    tile = np.array(FOLHA.crop(TILES['pensativo']).resize((197 * F, 245 * F), Image.LANCZOS).convert('RGBA'))
    MAO = [(40, 155), (50, 143), (62, 136), (75, 135), (88, 142), (98, 160), (101, 180), (103, 205), (104, 230),
           (60, 238), (50, 229), (38, 219), (29, 204), (28, 188), (32, 172)]
    m = Image.new('L', (197 * F, 245 * F), 0); ImageDraw.Draw(m).polygon([(x * F, y * F) for x, y in MAO], fill=255)
    m = np.array(m.filter(ImageFilter.GaussianBlur(1.2 * F))).astype(float)
    # fora da mão: o fundo do quadrinho e a barba (escura, em cima dos dedos)
    rgb = tile[..., :3].astype(float); cor_bg = rgb[20:40, 20:40].reshape(-1, 3).mean(0)
    lum = rgb @ [0.3, 0.59, 0.11]
    yy_t = np.mgrid[0:tile.shape[0], 0:tile.shape[1]][0] / F
    fora = (np.abs(rgb - cor_bg).sum(2) < 60) | ((lum < 70) & (yy_t < 172))
    fora = np.array(Image.fromarray((fora * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.8))) / 255
    tile[..., 3] = (m * (1 - fora)).astype(np.uint8)
    mao_img = Image.fromarray(tile, 'RGBA'); mao_img = mao_img.resize((round(mao_img.width * S), round(mao_img.height * S)), Image.LANCZOS)
    ox = (W1 - 201) - 98.5 * S - dx * S; oy = TY - dy * S          # canto do quadrinho em coordenadas finais (1x)
    tela = Image.new('RGBA', (W, 1560), (0, 0, 0, 0)); tela.alpha_composite(mao_img, (round(ox * F), round(oy * F)))
    tela = tela.transpose(Image.FLIP_LEFT_RIGHT)
    finalizar(tela, alt=1560).save('final/gesto-mao.webp', quality=90, method=6)
    mao = (ox + S * 80, oy + S * 222)                                  # onde o pulso some, por baixo da mão
    pivo_f = (W1 - PIVO[0], PIVO[1])
    fim_rep = (W1 - 343, 725)
    v0 = np.subtract(fim_rep, pivo_f); v1 = np.subtract(mao, pivo_f)
    ang = np.degrees(np.arctan2(v1[1], v1[0]) - np.arctan2(v0[1], v0[0]))
    if ang > 180: ang -= 360
    if ang < -180: ang += 360
    print(json.dumps({'pivo': pivo_f, 'mao': [round(m, 1) for m in mao], 'giro': round(float(ang), 1),
                      'escala': round(float(np.hypot(*v1) / np.hypot(*v0)), 3)}))

if __name__ == '__main__':
    main()
