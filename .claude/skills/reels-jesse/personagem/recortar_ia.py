# Recorta as poses de corpo inteiro com um modelo de IA de remoção de fundo (BiRefNet, via rembg), em 2x.
# Substitui o recorte por cor do poses.py / poses_ela.py, que deixava bolsões do fundo entre braço e corpo
# e cortava cotovelos que passam da borda do quadro.
#
# Uso (num venv com: pip install "rembg[cpu]" pillow numpy; o modelo vem das releases do GitHub do rembg):
#   python recortar_ia.py jesse   ->  poses/<nome>.webp + poses/poses.json
#   python recortar_ia.py ranya   ->  ../personagem-ela/poses/<nome>.webp + poses.json
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from rembg import remove, new_session

AQUI = os.path.dirname(os.path.abspath(__file__))
F = 2
FOLGA = 22   # pixels a mais de cada lado na folha: braços e cabelo passam da borda do quadro

# nome: (caixa do quadro na folha, centro do tronco para escolher a figura certa)
JESSE = ('folha-poses.webp', 'poses', {
    'neutro': ((5, 8, 222, 580), (105, 200)), 'sorriso': ((214, 8, 430, 580), (318, 200)),
    'afirmativo': ((428, 8, 645, 580), (540, 220)), 'pensativo': ((645, 8, 848, 580), (745, 240)),
    'raiva': ((848, 8, 1054, 580), (950, 200)), 'surpreso': ((1040, 8, 1254, 580), (1150, 200)),
    'rindo': ((5, 640, 216, 1172), (105, 820)), 'triste': ((216, 640, 414, 1172), (310, 820)),
    'foto': ((414, 640, 606, 1172), (510, 820)), 'caminhando': ((606, 640, 796, 1172), (700, 820)),
    'cabelo': ((796, 640, 982, 1172), (890, 820)), 'costas': ((982, 640, 1134, 1172), (1058, 820)),
})
_top = [(23, 205), (223, 412), (429, 608), (625, 822), (837, 1033), (1050, 1233)]
_bot = [(23, 180), (192, 345), (351, 508), (520, 674), (686, 831), (844, 997), (1000, 1134)]
RANYA = ('../personagem-ela/folha-poses-ela.webp', '../personagem-ela/poses', {
    **{n: ((a, 4, b, 604), ((a + b) // 2, 300)) for n, (a, b) in zip(['neutro', 'sorriso', 'afirmativo', 'pensativo', 'brava', 'surpresa'], _top)},
    **{n: ((a, 644, b, 1197), ((a + b) // 2, 900)) for n, (a, b) in zip(['triste', 'pensando', 'desconfiada', 'confiante', 'rindo', 'seria', 'de_lado'], _bot)},
})


def recorta(folha, sessao, caixa, centro):
    x0, y0, x1, y1 = caixa
    x0, x1 = max(0, x0 - FOLGA), min(folha.width, x1 + FOLGA)
    im = folha.crop((x0, y0, x1, y1)).resize(((x1 - x0) * F, (y1 - y0) * F), Image.LANCZOS)
    out = remove(im, session=sessao)
    a = np.array(out)
    # fica só a figura ligada ao tronco (a folga pode trazer pedaço da pose vizinha)
    mask = (a[..., 3] > 30).astype(np.uint8) * 255
    m = Image.fromarray(mask).convert('RGB')
    cx, cy = (centro[0] - x0) * F, (centro[1] - y0) * F
    ys, xs = np.where(mask[max(0, cy - 140):cy + 140, max(0, cx - 140):cx + 140] > 0)
    k = np.argmin((xs - 140) ** 2 + (ys - 140) ** 2)
    ImageDraw.floodfill(m, (int(xs[k]) + max(0, cx - 140), int(ys[k]) + max(0, cy - 140)), (255, 0, 255))
    mm = np.array(m); fig = (mm[..., 0] == 255) & (mm[..., 1] == 0)
    perto = np.array(Image.fromarray((fig * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7))) > 0   # guarda a borda suave
    a[..., 3] = np.where(perto, a[..., 3], 0)
    out = Image.fromarray(a, 'RGBA')
    out = out.crop(out.getbbox())
    al = np.array(out)[..., 3] > 40
    pe = int(np.where(al.any(1))[0].max())
    return out, {'largura': out.width, 'altura': out.height, 'pe_y': pe,
                 'pe_x': int(np.where(al[pe - 30 * F:pe].any(0))[0].mean())}


if __name__ == '__main__':
    folha_arq, pasta, poses = {'jesse': JESSE, 'ranya': RANYA}[sys.argv[1]]
    folha = Image.open(os.path.join(AQUI, folha_arq)).convert('RGB')
    pasta = os.path.join(AQUI, pasta); os.makedirs(pasta, exist_ok=True)
    sessao = new_session('birefnet-general-lite')
    info = {}
    for nome, (caixa, centro) in poses.items():
        print(nome, flush=True)
        im, dados = recorta(folha, sessao, caixa, centro)
        im.save(os.path.join(pasta, f'{nome}.webp'), quality=90, method=6)
        info[nome] = dados
    json.dump(info, open(os.path.join(pasta, 'poses.json'), 'w'), indent=1)
    print('ok', len(info))
