#!/usr/bin/env python3
# Reels de serviços (seg 16/11): "Eu fiz um jogo inteiro sozinho" -> o site do seu negócio
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from motor import gerar, final_cta
from roteiros import ROTEIROS
RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'servicos')
cfg = dict(
    titulo='Reels: fiz um jogo inteiro sozinho (serviços)',
    falas=[(f, leg) for f, _, leg in ROTEIROS['servicos']],
    poses=[(0.0, 'sorriso'), (('vo1', 0.45), 'afirmativo'), (('vo2', 0), 'rindo'), (('vo2', 0.38), 'surpreso'), (('vo2', 0.78), 'sorriso'),
           (('vo3', 0), 'pensativo'), (('vo3', 0.34), 'cabelo'), (('vo3', 0.64), 'afirmativo'), (('vo4', 0), 'surpreso'),
           (('vo5', 0), 'pensativo'), (('vo5', 0.4), 'sorriso'), (('vo6', 0), 'cabelo'), (('vo6', 0.35), 'rindo'), (('vo6', 0.72), 'afirmativo'),
           (('vo7', 0), 'foto'), (('vo7', 0.58), 'afirmativo')],
    sfx=[('key-press', ('vo3', 0.40), 0.4), ('key-press', ('vo3', 0.46), 0.36), ('key-press', ('vo3', 0.52), 0.4), ('impact-bass-1', ('vo4', 0, 0.02), 0.34)],
    cenas=[
        dict(id='s1', de=0.0,
             shots=[dict(tipo='video', src='fazenda.mp4', cam=[(0, 540, 760, 1.0), ('fim', 540, 780, 1.08, 'none')])],
             placas=[(0, 'fim', 'FIZ UM JOGO INTEIRO<br><span class="acento">SOZINHO</span>', 190, 108)]),
        dict(id='s2', de=('vo2', 0, -0.1),
             shots=[dict(tipo='video', src='fazenda2.mp4', corte=1.0, cam=[(0, 540, 900, 1.1), (('vo2', 0.57), 540, 1000, 1.2, 'none')]),
                    dict(tipo='video', src='viagem.mp4', corte=1.4, em=('vo2', 0.57), entra='corta', cam=[(0, 540, 1050, 1.32), (('vo2', 0.78), 540, 1050, 1.12, 'power2.out')]),
                    dict(tipo='img', src='evento.png', em=('vo2', 0.78), entra='corta', cam=[(0, 540, 420, 1.22), ('fim', 540, 600, 1.32, 'none')])],
             placas=[(('vo2', 0.37), ('vo2', 0.57), '<span class="acento">60</span> NÍVEIS', 200, 150)]),
        dict(id='s3', de=('vo3', 0, -0.1),
             shots=[dict(tipo='img', src='loja-pac.png', cam=[(0, 540, 800, 1.0), (('vo3', 0.31), 760, 900, 1.3)]),
                    dict(tipo='img', src='ent-campo.jpg', em=('vo3', 0.33), entra='corta', cam=[(0, 540, 1120, 1.22), (('vo3', 0.63), 540, 1170, 1.36, 'none')],
                         estados=[(('vo3', 0.40), 'ent-b.jpg'), (('vo3', 0.46), 'ent-bi.jpg'), (('vo3', 0.52), 'ent-bia.jpg')]),
                    dict(tipo='img', src='loja-pac.png', em=('vo3', 0.63), entra='corta', cam=[(0, 760, 900, 1.3), (('vo3', 0.84), 720, 960, 1.24), ('fim', 540, 1640, 1.22)],
                         molduras=[(('vo3', 0.66), ('vo3', 0.84), (744, 525, 212, 876)), (('vo3', 0.9), 'fim', (100, 1508, 880, 278))])]),
        dict(id='s4', de=('vo4', 0, -0.1), fundo='#2a0f13',
             shots=[dict(tipo='img', src='site-planos.png', alt=4370, alt_txt='A seção Planos do site jessecoelho.com.br',
                         cam=[(0, 540, 420, 1.0), (('vo4', 0.95), 540, 520, 1.1), (('vo5', 0.14), 540, 1270, 1.22), (('vo5', 0.5), 540, 1560, 1.3), (('vo5', 0.95), 540, 1840, 1.42),
                              (('vo6', 0.14), 540, 2860, 1.22), (('vo6', 0.5), 540, 3130, 1.42), ('fim', 540, 3230, 1.5)],
                         molduras=[(('vo5', 0.62), ('vo5', 1, 0.1), (98, 1842, 884, 64)), (('vo6', 0.36), ('vo6', 0.7), (98, 3136, 884, 64)), (('vo6', 0.74), 'fim', (98, 3220, 884, 64))])]),
        dict(id='s5', de=('vo7', 0, -0.1), fundo='#e7e3e1',
             shots=[dict(tipo='img', src='site-contato.png', alt=1688, foco=(540, 520), alt_txt='Vamos construir juntos? O contato no site',
                         cam=[(0, 540, 456, 1.14), ('fim', 540, 456, 1.2, 'none')])],
             extra=final_cta(marca=False, top=190)),
    ])
if __name__ == '__main__':
    gerar(RAIZ, cfg)