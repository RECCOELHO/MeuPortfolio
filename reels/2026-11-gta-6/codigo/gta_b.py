#!/usr/bin/env python3
# Reels B (qui 19/11, dia do lançamento): "O GTA 6 chegou e seus clientes sumiram pro videogame"
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from motor import gerar, final_cta
from roteiros_gta import ROTEIROS
from medidas import ALT_PLANOS, ALT_CONTATO, PL, PAC
from tipografia import numero_grande
RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gta-b')
cfg = dict(
    titulo='Reels: o GTA 6 chegou e seus clientes sumiram',
    falas=[(f, leg) for f, _, leg in ROTEIROS['gta-b']],
    poses=[(0.0, 'surpreso'), (('vo1', 0.5), 'cabelo'), (('vo2', 0), 'pensativo'), (('vo2', 0.55), 'foto'), (('vo3', 0), 'surpreso'), (('vo3', 0.5), 'pensativo'),
           (('vo4', 0), 'sorriso'), (('vo4', 0.6), 'afirmativo'), (('vo5', 0), 'rindo'), (('vo6', 0), 'sorriso'), (('vo7', 0), 'foto'), (('vo7', 0.55), 'afirmativo')],
    pequeno_em=('vo2', 0, -0.2),
    sfx=[('impact-bass-1', ('vo1', 0, 0.1), 0.34)],
    cenas=[
        dict(id='s1', de=0.0, extra=numero_grande('19/11', 'PS5 · XBOX SERIES'),
             placas=[(0, 'fim', 'O <span class="acento">GTA 6</span><br>CHEGOU', 170, 140)]),
        # o cliente pega o celular: um site de verdade rolando
        dict(id='s2', de=('vo2', 0, -0.1),
             shots=[dict(tipo='video', src='site-cenas.mp4', corte=8.2, cam=[(0, 540, 960, 1.04), ('fim', 540, 960, 1.1, 'none')])],
             placas=[(('vo3', 0.5), ('vo3', 1, 0.15), 'SEU NEGÓCIO<br><span class="acento">APARECE?</span>', 190, 124)]),
        # um site bom: Conexão (WhatsApp) e Checkout Pro (cartão, Pix e boleto)
        dict(id='s3', de=('vo4', 0, -0.1), fundo='#2a0f13',
             shots=[dict(tipo='img', src='site-planos.png', alt=ALT_PLANOS, alt_txt='Os planos do site jessecoelho.com.br',
                         cam=[(0, 540, 1250, 1.06), (('vo4', 0.55), 540, PL['zap'][1] + 30, 1.14), (('vo5', 0.15), 540, PL['pag'][1] + 40, 1.14), ('fim', 540, PL['pag'][1] + 60, 1.18)],
                         molduras=[(('vo4', 0.6), ('vo4', 1, 0.1), tuple(PL['zap'])), (('vo5', 0.3), ('vo5', 1, 0.15), tuple(PL['pag']))])]),
        # funciona enquanto você joga
        dict(id='s4', de=('vo6', 0, -0.1),
             shots=[dict(tipo='video', src='ilha.mp4', corte=1.0, cam=[(0, 540, 900, 1.08), ('fim', 540, 860, 1.18, 'none')])],
             placas=[(('vo6', 0.1), 'fim', 'ENQUANTO<br><span class="acento">VOCÊ JOGA</span>', 190, 124)]),
        dict(id='s5', de=('vo7', 0, -0.1), fundo='#e7e3e1',
             shots=[dict(tipo='img', src='site-contato.png', alt=ALT_CONTATO, livre=True, foco=(540, 620), alt_txt='Vamos construir juntos? O contato no site',
                         cam=[(0, 540, 640, 0.75), ('fim', 540, 640, 0.79, 'none')])],
             extra=final_cta(marca=False, top=180)),
    ])
if __name__ == '__main__':
    gerar(RAIZ, cfg)
