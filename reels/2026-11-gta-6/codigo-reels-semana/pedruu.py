#!/usr/bin/env python3
# Reels do Pedruu (qua 18/11): a primeira live da Fazendinha e o selo "1ª live"
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from motor import gerar, final_cta
from roteiros import ROTEIROS
RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pedruu')
cfg = dict(
    titulo='Reels: a 1ª live da Fazendinha (Pedruu)',
    falas=[(f, leg) for f, _, leg in ROTEIROS['pedruu']],
    poses=[(0.0, 'surpreso'), (('vo2', 0), 'afirmativo'), (('vo3', 0), 'sorriso'), (('vo3', 0.55), 'rindo'), (('vo4', 0), 'pensativo'), (('vo4', 0.45), 'sorriso'),
           (('vo5', 0), 'surpreso'), (('vo5', 0.5), 'rindo'), (('vo6', 0), 'afirmativo'), (('vo6', 0.3), 'foto'), (('vo6', 0.72), 'sorriso'), (('vo7', 0), 'afirmativo')],
    sfx=[('impact-bass-1', ('vo3', 0.58), 0.36)],
    cenas=[
        dict(id='s1', de=0.0,
             shots=[dict(tipo='video', src='fazenda2.mp4', corte=1.5, cam=[(0, 540, 820, 1.0), ('fim', 540, 860, 1.08, 'none')])],
             placas=[(0, 'fim', 'A <span class="acento">1ª LIVE</span><br>DA FAZENDINHA', 190, 124)]),
        # o ranking: a linha do Pedruu e depois o selo
        dict(id='s2', de=('vo2', 0, -0.1),
             shots=[dict(tipo='img', src='ranking.png', alt_txt='O ranking da Fazendinha com o Pedruu e o selo 1ª live',
                         cam=[(0, 540, 640, 1.0), (('vo2', 0.55), 520, 610, 1.7, 'power2.inOut'), (('vo3', 0.3), 520, 608, 1.8, 'none'), (('vo3', 0.62), 538, 575, 2.6, 'power3.inOut'), ('fim', 538, 575, 2.72, 'none')],
                         molduras=[(('vo3', 0.64), 'fim', (470, 540, 136, 38))])]),
        # as Novidades do jogo dizem onde o selo aparece
        dict(id='s3', de=('vo4', 0, -0.1),
             shots=[dict(tipo='img', src='novidades.png', alt_txt='Novidades do jogo: homenagem ao Pedruu',
                         cam=[(0, 540, 880, 1.05), (('vo4', 0.4), 565, 958, 1.3), ('fim', 565, 958, 1.42, 'none')],
                         molduras=[(('vo4', 0.3), 'fim', (150, 846, 830, 225))])]),
        # o Churros na ilha
        dict(id='s4', de=('vo5', 0, -0.1),
             shots=[dict(tipo='video', src='ilha.mp4', corte=3.0, cam=[(0, 540, 760, 1.12), (('vo5', 0.52), 540, 700, 1.22, 'none')]),
                    dict(tipo='img', src='cao.png', em=('vo5', 0.52), entra='corta', alt_txt='O Churros, o corgi marrom da ilha',
                         cam=[(0, 540, 960, 1.1), ('fim', 420, 980, 1.5)], molduras=[(('vo5', 0.66), 'fim', (118, 740, 210, 250))])],
             placas=[(('vo5', 0.2), ('vo5', 0.5), 'O <span class="acento">CHURROS</span>', 200, 140)]),
        dict(id='s5', de=('vo6', 0, -0.1),
             shots=[dict(tipo='video', src='fazenda.mp4', corte=2.0, cam=[(0, 540, 800, 1.05), ('fim', 540, 860, 1.16, 'none')])],
             placas=[(('vo6', 0.02), ('vo6', 0.3), 'VALEU, <span class="acento">PEDRUU!</span>', 200, 130),
                     (('vo6', 0.33), 'fim', 'FAZ LIVE TAMBÉM?<br><span class="acento">ME MARCA!</span>', 190, 112)]),
        dict(id='s6', de=('vo7', 0, -0.1), entra='sobe', fundo='#84c669', extra=final_cta(marca=True)),
    ])
if __name__ == '__main__':
    gerar(RAIZ, cfg)