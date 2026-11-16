#!/usr/bin/env python3
# Reels C (sex 20/11, feriado), para clientes: "O GTA 6 foi feito por milhares de pessoas. Esse jogo, por uma."
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from motor import gerar, final_cta
from roteiros_gta import ROTEIROS
from medidas import ALT_PLANOS, ALT_CONTATO, PL, PAC
from tipografia import numero_grande
RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gta-c')
cfg = dict(
    titulo='Reels: milhares de pessoas contra uma',
    falas=[(f, leg) for f, _, leg in ROTEIROS['gta-c']],
    poses=[(0.0, 'pensativo'), (('vo2', 0), 'afirmativo'), (('vo2', 0.7), 'rindo'), (('vo3', 0), 'sorriso'), (('vo3', 0.5), 'rindo'),
           (('vo4', 0), 'pensativo'), (('vo4', 0.5), 'sorriso'), (('vo5', 0), 'surpreso'), (('vo6', 0), 'sorriso'), (('vo6', 0.55), 'afirmativo'),
           (('vo7', 0), 'foto'), (('vo7', 0.6), 'afirmativo')],
    pequeno_em=('vo2', 0, -0.2),
    sfx=[('impact-bass-1', ('vo2', 0.62), 0.34)],
    cenas=[
        dict(id='s1', de=0.0, extra=numero_grande('GTA 6', 'UM ESTÚDIO COM MILHARES DE PESSOAS')),
        # esse jogo aqui (uma pessoa): fazenda, ilha, feira, loja com Pix
        dict(id='s2', de=('vo2', 0, -0.1),
             shots=[dict(tipo='img', src='jogo-campo.jpg', cam=[(0, 540, 900, 1.0), (('vo3', 0.3), 540, 880, 1.14)]),
                    dict(tipo='video', src='ilha.mp4', corte=0.5, em=('vo3', 0.3), entra='corta', cam=[(0, 540, 900, 1.1), (('vo3', 0.62), 540, 880, 1.18, 'none')]),
                    dict(tipo='img', src='jogo-feira.jpg', em=('vo3', 0.62), entra='corta', cam=[(0, 540, 900, 1.08), (('vo3', 0.78), 540, 900, 1.14)]),
                    dict(tipo='img', src='loja-pac.png', em=('vo3', 0.78), entra='corta', cam=[(0, 540, 900, 1.06), ('fim', 600, 960, 1.14)],
                         molduras=[(('vo3', 0.82), ('vo4', 0), tuple(PAC['p1']))])],
             placas=[(0, ('vo2', 1, 0.15), 'ESSE JOGO AQUI:<br><span class="acento">UMA PESSOA</span>', 190, 120)]),
        # cada detalhe com cuidado: a ilha de perto
        dict(id='s3', de=('vo4', 0, -0.1),
             shots=[dict(tipo='video', src='viagem.mp4', corte=2.5, cam=[(0, 540, 960, 1.15), ('fim', 540, 960, 1.3, 'none')])],
             placas=[(('vo4', 0.45), 'fim', 'CADA <span class="acento">DETALHE</span>', 200, 130)]),
        # o mesmo cuidado no seu site: o site e os planos
        dict(id='s4', de=('vo5', 0, -0.1),
             shots=[dict(tipo='video', src='site-cenas.mp4', corte=8.2, cam=[(0, 540, 960, 1.0), ('fim', 540, 960, 1.06, 'none')]),
                    dict(tipo='img', src='site-planos.png', alt=ALT_PLANOS, em=('vo6', 0, -0.05), entra='corta', alt_txt='Os planos do site jessecoelho.com.br',
                         cam=[(0, 540, 1300, 1.06), (('vo6', 0.5), 540, PL['banco'][1] + 30, 1.12), ('fim', 540, PL['sup'][1] + 30, 1.16)],
                         molduras=[(('vo6', 0.1), ('vo6', 0.55), tuple(PL['banco'])), (('vo6', 0.6), 'fim', tuple(PL['sup']))])]),
        dict(id='s5', de=('vo7', 0, -0.1), fundo='#e7e3e1',
             shots=[dict(tipo='img', src='site-contato.png', alt=ALT_CONTATO, livre=True, foco=(540, 620), alt_txt='Vamos construir juntos? O contato no site',
                         cam=[(0, 540, 640, 0.75), ('fim', 540, 640, 0.79, 'none')])],
             extra=final_cta(marca=False, top=180)),
    ])
if __name__ == '__main__':
    gerar(RAIZ, cfg)
