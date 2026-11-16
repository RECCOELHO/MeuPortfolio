#!/usr/bin/env python3
# Reels A (qua 18/11): "Meu site parece abertura de GTA 6"
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from motor import gerar, final_cta
from roteiros_gta import ROTEIROS
from medidas import ALT_PLANOS, ALT_CONTATO, PL, PAC
RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gta-a')
cfg = dict(
    titulo='Reels: meu site parece abertura de GTA 6',
    falas=[(f, leg) for f, _, leg in ROTEIROS['gta-a']],
    poses=[(0.0, 'surpreso'), (('vo1', 0.55), 'rindo'), (('vo2', 0), 'pensativo'), (('vo2', 0.45), 'sorriso'), (('vo2', 0.75), 'afirmativo'),
           (('vo3', 0), 'cabelo'), (('vo4', 0), 'sorriso'), (('vo4', 0.6), 'rindo'), (('vo5', 0), 'pensativo'), (('vo5', 0.5), 'afirmativo'),
           (('vo6', 0), 'sorriso'), (('vo7', 0), 'foto'), (('vo7', 0.6), 'afirmativo')],
    pequeno_em=('vo1', 1, 0.05),
    sfx=[('impact-bass-1', ('vo4', 0.72), 0.32)],
    cenas=[
        # o próprio site rolando: 2018, a farda, 2025
        dict(id='s1', de=0.0,
             shots=[dict(tipo='video', src='site-cenas.mp4', cam=[(0, 540, 960, 1.0), ('fim', 540, 960, 1.04, 'none')])],
             placas=[(0, ('vo1', 1, 0.1), 'MEU SITE PARECE<br>ABERTURA DE <span class="acento">GTA 6</span>', 190, 112),
                     (('vo3', 0.05), ('vo3', 1, 0.05), 'ROLA ATÉ O <span class="acento">FIM</span>', 200, 130)]),
        # os projetos: o monitor com o jogo
        dict(id='s2', de=('vo4', 0, -0.1),
             shots=[dict(tipo='video', src='site-projetos.mp4', cam=[(0, 540, 960, 1.0), ('fim', 540, 900, 1.12, 'none')])]),
        # os planos
        dict(id='s3', de=('vo5', 0, -0.1), fundo='#2a0f13',
             shots=[dict(tipo='img', src='site-planos.png', alt=ALT_PLANOS, alt_txt='Os planos do site jessecoelho.com.br',
                         cam=[(0, 540, 420, 1.0), (('vo5', 0.9), 540, 640, 1.06), (('vo6', 0.1), 540, PL['zap'][1] + 30, 1.12), (('vo6', 0.42), 540, PL['banco'][1] + 30, 1.14),
                              (('vo6', 0.75), 540, PL['pag'][1] + 30, 1.14), ('fim', 540, PL['pag'][1] + 60, 1.16)],
                         molduras=[(('vo6', 0.05), ('vo6', 0.4), tuple(PL['zap'])), (('vo6', 0.42), ('vo6', 0.72), tuple(PL['banco'])), (('vo6', 0.74), 'fim', tuple(PL['pag']))])]),
        dict(id='s4', de=('vo7', 0, -0.1), fundo='#e7e3e1',
             shots=[dict(tipo='img', src='site-contato.png', alt=ALT_CONTATO, livre=True, foco=(540, 620), alt_txt='Vamos construir juntos? O contato no site',
                         cam=[(0, 540, 640, 0.75), ('fim', 540, 640, 0.79, 'none')])],
             extra=final_cta(marca=False, top=180)),
    ])
if __name__ == '__main__':
    gerar(RAIZ, cfg)
