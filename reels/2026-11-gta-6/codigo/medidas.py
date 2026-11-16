# medidas das telas capturadas (cap/rects.json e o tamanho dos PNGs), para as molduras e a câmera
import json, os
from PIL import Image
AQUI = os.path.dirname(os.path.abspath(__file__))
R = json.load(open(os.path.join(AQUI, 'cap/rects.json')))
ALT_PLANOS = Image.open(os.path.join(AQUI, 'cap/site-planos.png')).height
ALT_CONTATO = Image.open(os.path.join(AQUI, 'cap/site-contato-recorte.png')).height
PL = {k: R['pl-' + k] for k in ('zap', 'banco', 'pag', 'rel', 'sup')}
PAC = {k: R['pac-' + k] for k in ('p1', 'p5', 'p10', 'p20')}
