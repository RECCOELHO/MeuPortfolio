#!/usr/bin/env python3
# Reels da vaquinha (qui 19/11): "Quero colocar a Fazendinha na Play Store"
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from motor import gerar, final_cta
from roteiros import ROTEIROS
RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vaquinha')
cfg = dict(
    titulo='Reels: a Fazendinha na Play Store (vaquinha)',
    falas=[(f, leg) for f, _, leg in ROTEIROS['vaquinha']],
    poses=[(0.0, 'pensativo'), (('vo1', 0.5), 'sorriso'), (('vo2', 0), 'cabelo'), (('vo2', 0.38), 'pensativo'), (('vo3', 0), 'surpreso'), (('vo3', 0.55), 'afirmativo'),
           (('vo4', 0), 'rindo'), (('vo4', 0.55), 'sorriso'), (('vo5', 0), 'afirmativo'), (('vo5', 0.75), 'rindo'), (('vo6', 0), 'pensativo'), (('vo6', 0.6), 'sorriso'), (('vo7', 0), 'afirmativo')],
    sfx=[('impact-bass-1', ('vo3', 0.56), 0.34)],
    cenas=[
        dict(id='s1', de=0.0,
             shots=[dict(tipo='video', src='fazenda.mp4', cam=[(0, 540, 760, 1.0), ('fim', 540, 780, 1.08, 'none')])],
             placas=[(0, 'fim', 'A FAZENDINHA NA<br><span class="acento">PLAY STORE?</span>', 190, 112)]),
        dict(id='s2', de=('vo2', 0, -0.1),
             shots=[dict(tipo='video', src='fazenda2.mp4', corte=1.0, cam=[(0, 540, 900, 1.08), ('fim', 540, 980, 1.18, 'none')])],
             placas=[(('vo2', 0.04), ('vo2', 0.34), 'jessecoelho.com.br', 200, 104)]),
        # a loja de diamantes: o aviso do Google Play, a barra da vaquinha, os pacotes e o selo
        dict(id='s3', de=('vo2', 0.36),
             shots=[dict(tipo='img', src='loja-vaq.png', alt_txt='A vaquinha na loja de diamantes: R$ 42 de R$ 150',
                         cam=[(0, 540, 760, 1.0), (('vo2', 0.62), 540, 1010, 1.2), (('vo2', 1), 540, 1016, 1.26, 'none'), (('vo3', 0.25), 540, 740, 1.12), (('vo3', 0.6), 540, 765, 1.3), (('vo3', 1, 0.1), 540, 768, 1.36, 'none')],
                         molduras=[(('vo2', 0.64), ('vo2', 1, 0.05), (135, 850, 810, 325)), (('vo3', 0.58), ('vo3', 1, 0.05), (135, 735, 810, 100))]),
                    dict(tipo='img', src='loja-pac.png', em=('vo4', 0, -0.05), entra='funde', alt_txt='Os pacotes de diamantes, a partir de R$ 1',
                         cam=[(0, 540, 760, 1.02), (('vo4', 0.5), 620, 800, 1.2), (('vo4', 0.95), 760, 600, 1.5), ('fim', 760, 600, 1.54, 'none')],
                         molduras=[(('vo4', 0.66), 'fim', (765, 539, 177, 63))]),
                    dict(tipo='img', src='loja-vaq.png', em=('vo5', 0, -0.05), entra='funde',
                         cam=[(0, 540, 1000, 1.2), (('vo5', 0.45), 616, 1087, 2.0, 'power2.inOut'), ('fim', 616, 1087, 2.12, 'none')],
                         molduras=[(('vo5', 0.42), 'fim', (530, 1068, 173, 38))])]),
        # o caminho: Loja -> Diamantes
        dict(id='s4', de=('vo6', 0, -0.1),
             shots=[dict(tipo='video', src='toque.mp4', corte=0.6, cam=[(0, 540, 960, 1.0), (('vo6', 0.25), 540, 1100, 1.05), ('fim', 540, 760, 1.12)],
                         maos=[(('vo6', 0, 0.08), (277, 1825)), (('vo6', 0, 1.68), (864, 435))],
                         molduras=[(('vo6', 0.86), 'fim', (135, 660, 810, 170))])]),
        dict(id='s5', de=('vo7', 0, -0.1), entra='sobe', fundo='#84c669', extra=final_cta(marca=True)),
    ])
if __name__ == '__main__':
    gerar(RAIZ, cfg)