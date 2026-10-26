from PIL import Image
import sys
G = -143.8
L = lambda n: Image.open(f'final/{n}.webp').convert('RGBA')
base, ante, mao = L('gesto-base'), L('gesto-antebraco'), L('gesto-mao')
caras = {n: L(f'gesto-cara-{n}') for n in ['desconfiado', 'pensativo', 'surpreso']}
P = (72, 940)
def gira(im, ang):  # ângulo em graus no sentido do CSS (horário positivo)
    return im.rotate(-ang, center=P, resample=Image.BICUBIC)
def pose(t, cara, fundo=(26, 10, 13, 255)):
    c = Image.new('RGBA', (836, 1560), fundo)
    c.alpha_composite(base, (0, 0)); c.alpha_composite(caras[cara], (0, 0))
    c.alpha_composite(gira(ante, t)); c.alpha_composite(gira(mao, t - G))
    return c.crop((0, 0, 836, 1400)).convert('RGB')
if __name__ == '__main__':
    ts = [(0, 'desconfiado'), (-40, 'desconfiado'), (-90, 'desconfiado'), (-130, 'desconfiado'), (G, 'pensativo')]
    ims = [pose(t, c).resize((418, 700)) for t, c in ts]
    s = Image.new('RGB', (418 * len(ims), 700)); [s.paste(im, (418 * i, 0)) for i, im in enumerate(ims)]; s.save('gesto-teste.png')
    pose(G, 'pensativo').crop((100, 350, 560, 900)).save('gesto-zoom.png')
