#!/usr/bin/env python3
"""Gera index.html e compositions/*.html do reels a partir dos tempos abaixo e dos arquivos de voz.

Rodar de novo depois de mudar um tempo, uma frase ou uma voz: python3 gerar.py
(a fala do Jessé e as legendas saem da energia e do tamanho de cada arquivo em assets/vo)."""
import json, math, os, wave, struct, subprocess

RAIZ = os.path.dirname(os.path.abspath(__file__))
DUR = 30.0

# ---------- a voz: arquivo, início no filme e o texto que aparece na legenda ----------
# (o texto da legenda é o escrito certo; o arquivo foi gerado com a pronúncia: "Pi ou vi", "jéssi coelho ponto com...")
# grupos separados por "/"; *palavra* fica verde
VOZ = [
    ('vo1',  0.25, 'POV: você abre / o portfólio de um dev.'),
    ('vo2',  3.05, 'Rola o currículo…'),
    ('vo3',  6.15, 'E no fim tem / uma *fazenda* inteira / escondida!'),
    ('vo4a', 9.05, 'Planta tudo / de uma vez,'),
    ('vo4b', 10.95, 'colhe,'),
    ('vo4c', 12.35, 'ajuda os *vizinhos*,'),
    ('vo4d', 13.95, 'vende na *feira*'),
    ('vo4e', 15.20, 'e ainda pesca / no *alto-mar*.'),
    ('vo5a', 17.00, 'Pra entrar:'),
    ('vo5b', 18.05, '*jessecoelho.com.br*'),
    ('vo5c', 20.55, 'Desce até / *Projetos*'),
    ('vo5d', 22.05, 'e toca em / *Jogar agora*.'),
    ('vo5e', 23.95, 'Escolhe um / *apelido*'),
    ('vo5f', 25.35, 'e guarda / o seu *código*.'),
    ('vo6',  27.60, 'Bora plantar!'),
]

# ---------- os efeitos: arquivo, momento da imagem, volume, velocidade (varia o mesmo arquivo) ----------
SFX_DIR = 'assets/sfx'
SFX = [
    ('whoosh', 1.15, 0.30, 1.15), ('whoosh', 2.95, 0.40, 1.0), ('whoosh', 3.75, 0.32, 1.25), ('whoosh', 4.55, 0.36, 0.85),
    ('whoosh', 5.35, 0.40, 1.1), ('riser', 5.60, 0.30, 1.0), ('click', 6.50, 0.55, 1.0), ('impact-bass-1', 6.90, 0.55, 1.0),
    ('whoosh', 8.95, 0.34, 0.9), ('pop', 9.93, 0.38, 1.0), ('pop', 11.33, 0.34, 1.12), ('pop', 12.93, 0.36, 0.9),
    ('whoosh', 15.05, 0.38, 0.8), ('whoosh', 16.85, 0.34, 1.2), ('pop', 17.30, 0.30, 1.05), ('whoosh', 20.45, 0.36, 1.0),
    ('pop', 20.85, 0.30, 0.95), ('click', 23.10, 0.50, 1.1), ('pop', 23.85, 0.28, 1.1),
    ('key-press', 24.30, 0.45, 1.0), ('key-press', 24.55, 0.40, 1.15), ('key-press', 24.80, 0.45, 0.9),
    ('pop', 25.60, 0.36, 1.0), ('whoosh', 27.35, 0.34, 1.05), ('pop', 28.05, 0.38, 0.95),
]

# ---------- as cenas ----------
CENAS = [('s1', 0.0, 3.0), ('s2', 3.0, 2.4), ('s3', 5.4, 3.6), ('s4', 9.0, 7.9), ('s5', 16.9, 10.9), ('s6', 27.4, 2.6)]


def ler_wav(caminho):
    with wave.open(caminho, 'rb') as w:
        n, sw, fr, nc = w.getnframes(), w.getsampwidth(), w.getframerate(), w.getnchannels()
        dados = w.readframes(n)
    if sw == 2:
        amostras = struct.unpack('<%dh' % (len(dados) // 2), dados)
        amostras = [s / 32768 for s in amostras[::nc]]
    elif sw == 4:
        amostras = struct.unpack('<%di' % (len(dados) // 4), dados)
        amostras = [s / 2147483648 for s in amostras[::nc]]
    else:
        raise SystemExit('wav de %d bytes por amostra' % sw)
    return amostras, fr


def energia(caminho, passo=1 / 15):
    """energia de 0 a 1 a cada 1/15 s (raiz da média dos quadrados, normalizada pelo pico da frase)"""
    a, fr = ler_wav(caminho)
    jan = int(fr * passo)
    rms = []
    for i in range(0, len(a), jan):
        bloco = a[i:i + jan]
        rms.append(math.sqrt(sum(x * x for x in bloco) / max(1, len(bloco))))
    topo = max(rms) or 1
    e = [min(1, r / topo) for r in rms]
    # fala começa e acaba onde a energia passa de 12%
    fala = [i for i, v in enumerate(e) if v > 0.12]
    ini, fim = (fala[0] * passo, (fala[-1] + 1) * passo) if fala else (0, len(a) / fr)
    return e, len(a) / fr, ini, fim


def esc(t):
    return t.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def marcar(t):
    """*palavra* vira o verde do acento"""
    partes = t.split('*')
    return ''.join(('<b class="acento">%s</b>' % esc(p)) if i % 2 else esc(p) for i, p in enumerate(partes))


FONTE = """@font-face { font-family: 'Jersey 10'; src: url('assets/fonts/jersey10-latin.woff2') format('woff2'); font-weight: 400; font-style: normal; }"""
PLACA_CSS = """
      .placa { position: absolute; background: #fde6c9; color: #3f2631; border: 6px solid #3f2631;
               box-shadow: 0 8px 0 #3f2631, inset 0 -6px 0 #fec99c; padding: 14px 30px 18px; }
      .pixel { font-family: 'Jersey 10', 'Nunito', monospace; font-weight: 400; letter-spacing: 0.01em; line-height: 0.95; }
      .acento { color: #3b7a3a; font-weight: inherit; }
      .tela { position: absolute; left: 0; top: 0; width: 1080px; height: 1920px; object-fit: cover; }
      .mao { position: absolute; width: 156px; height: 156px; image-rendering: pixelated; }
"""


def cena(cid, corpo, script, extra_css=''):
    return f"""<template>
  <style>
      {FONTE}
      #root {{ position: absolute; inset: 0; overflow: hidden; background: #1a0a0d; font-family: 'Nunito', sans-serif; }}
{PLACA_CSS}
{extra_css}
  </style>
  <div id="root" data-composition-id="{cid}" data-width="1080" data-height="1920">
{corpo}
  </div>
  <script>
    const tl = gsap.timeline({{ paused: true }});
{script}
    window.__timelines["{cid}"] = tl;
  </script>
</template>
"""


def img(id_, src, z=1, extra=''):
    return f'    <img id="{id_}" class="tela" src="assets/telas/{src}" alt="" style="z-index:{z};opacity:0{extra}" />'


# ---------- cena 1: o gancho ----------
def s1():
    corpo = f"""    <div id="s1-cam" style="position:absolute;inset:0;transform-origin:540px 700px">
      <img id="s1-topo" class="tela" src="assets/telas/port-topo.jpg" alt="Topo do portfólio com o crachá" />
    </div>
    <div id="s1-titulo" class="placa pixel" style="left:70px;top:190px;width:940px;text-align:center;z-index:5">
      <div style="font-size:84px" class="acento">POV:</div>
      <div style="font-size:112px">era só um portfólio…</div>
    </div>"""
    js = """    // o frame 0 já é o gancho: o título está na tela. Soco de câmera no crachá aos 1,2 s
    tl.fromTo('#s1-cam', { scale: 1 }, { scale: 1.12, duration: 0.4, ease: 'expo.out' }, 1.2);
    tl.fromTo('#s1-titulo', { scale: 1 }, { scale: 1.04, duration: 0.12, ease: 'power2.out', yoyo: true, repeat: 1 }, 1.2);
    // saída: chicote para cima (a página rola)
    tl.to('#s1-cam', { y: -700, filter: 'blur(18px)', duration: 0.2, ease: 'power3.in' }, 2.8);
    tl.to('#s1-titulo', { y: -500, opacity: 0, duration: 0.2, ease: 'power3.in' }, 2.8);"""
    return cena('s1', corpo, js)


# ---------- cena 2: o currículo passa ----------
def s2():
    telas = [('s2-senai', 'port-senai.jpg', 0.0), ('s2-exer', 'port-exercito.jpg', 0.8), ('s2-hosp', 'port-hospital.jpg', 1.6)]
    corpo = '\n'.join(f'    <img id="{i}" class="tela" src="assets/telas/{s}" alt="" style="z-index:{k + 1}" />' for k, (i, s, _) in enumerate(telas))
    js = []
    for k, (i, s, t) in enumerate(telas):
        # entra subindo de baixo com o borrão do chicote, assenta em 0,2 s
        js.append(f"    tl.fromTo('#{i}', {{ y: {480 if k == 0 else 1920}, filter: 'blur(18px)' }}, {{ y: 0, filter: 'blur(0px)', duration: 0.22, ease: 'power3.out' }}, {t});")
    js.append("    tl.to('#s2-hosp', { y: -1920, filter: 'blur(18px)', duration: 0.2, ease: 'power3.in' }, 2.2);")
    return cena('s2', corpo, '\n'.join(js))


# ---------- cena 3: Projetos, o toque em "Jogar agora" e o mergulho ----------
def s3():
    # botão: x 35–421, y 1518–1648 (centro 228,1583). A câmera traz o botão para (540, 980) em escala 1.7
    s = 1.7
    tx, ty = 540 - 228 * s, 800 - 1583 * s
    corpo = f"""    <div id="s3-cam" style="position:absolute;inset:0;transform-origin:0 0">
      <img id="s3-proj" class="tela" src="assets/telas/port-projetos.jpg" alt="Projetos: Fazendinha Secreta, Jogar agora" />
      <div id="s3-botao" style="position:absolute;left:35px;top:1518px;width:386px;height:130px;background:#b52a2a;opacity:0;transform-origin:50% 50%"></div>
    </div>
    <img id="s3-porteira" class="tela" src="assets/telas/ent-porteira.jpg" alt="A porteira da Fazendinha Secreta" style="z-index:3;opacity:0" />
    <img id="s3-mao" class="mao" src="assets/img/ico-mao.png" alt="" style="z-index:6;left:0;top:0;opacity:0" data-layout-allow-overflow />"""
    js = f"""    // a página chega rolando
    tl.fromTo('#s3-cam', {{ y: 480, filter: 'blur(18px)' }}, {{ y: 0, filter: 'blur(0px)', duration: 0.22, ease: 'power3.out' }}, 0);
    // a câmera vai até o botão
    tl.to('#s3-cam', {{ x: {tx:.1f}, y: {ty:.1f}, scale: {s}, duration: 0.55, ease: 'power2.inOut' }}, 0.23);
    // a mão entra de fora (embaixo à direita) e para em cima do botão: o botão está em (540, 980) na tela
    tl.fromTo('#s3-mao', {{ x: 1000, y: 1500, opacity: 1 }}, {{ x: 500, y: 780, opacity: 1, duration: 0.4, ease: 'expo.out', immediateRender: false }}, 0.7);
    tl.to('#s3-mao', {{ scale: 0.85, duration: 0.1, ease: 'power2.in' }}, 1.0);
    tl.to('#s3-mao', {{ scale: 1, duration: 0.12, ease: 'power2.out' }}, 1.1);
    // o clique (6,5 s no filme = 1,1 s aqui) faz o botão crescer até virar a próxima tela
    tl.set('#s3-botao', {{ opacity: 1 }}, 1.12);
    tl.to('#s3-mao', {{ opacity: 0, duration: 0.08 }}, 1.15);
    tl.fromTo('#s3-botao', {{ scale: 1 }}, {{ scale: 9, duration: 0.35, ease: 'power3.in' }}, 1.15);
    // a porteira chega um pouco grande e assenta
    tl.fromTo('#s3-porteira', {{ opacity: 0 }}, {{ opacity: 1, duration: 0.08, ease: 'none' }}, 1.46);
    tl.fromTo('#s3-porteira', {{ scale: 1.12 }}, {{ scale: 1, duration: 0.5, ease: 'expo.out', immediateRender: false }}, 1.46);
    // saída: a porteira cresce e vira a fazenda (o mundo novo entra por ela)
    tl.to('#s3-porteira', {{ scale: 2.4, opacity: 0, duration: 0.5, ease: 'power3.in' }}, 3.1);"""
    return cena('s3', corpo, js)


# ---------- cena 4: a prova (o jogo de verdade, cortes na voz) ----------
def s4():
    # tempos locais (filme - 9,0)
    t = lambda x: round(x - 9.0, 3)
    telas = [
        ('s4-arados', 'jogo-arados.jpg', t(9.0)), ('s4-plantando', 'jogo-plantando.jpg', t(9.6)), ('s4-plantou', 'jogo-plantou.jpg', t(9.9)),
        ('s4-maduros', 'jogo-maduros.jpg', t(10.9)), ('s4-colheu', 'jogo-colheu.jpg', t(11.3)),
        ('s4-vizinho', 'jogo-vizinho.jpg', t(12.3)), ('s4-ajudou', 'jogo-ajudou.jpg', t(12.9)),
        ('s4-feira', 'jogo-feira.jpg', t(13.9)), ('s4-mar', 'jogo-mar.jpg', t(15.1)),
    ]
    corpo = '    <div id="s4-cam" style="position:absolute;inset:0;transform-origin:540px 760px">\n'
    corpo += '\n'.join(f'      <img id="{i}" class="tela" src="assets/telas/{s}" alt="" style="z-index:{k + 1};opacity:0" />' for k, (i, s, _) in enumerate(telas))
    corpo += '\n    </div>\n    <div id="s4-azul" style="position:absolute;inset:0;background:#2f7fd1;opacity:0;z-index:20"></div>'
    js = ["    // entra pela porteira: a fazenda chega grande e assenta",
          "    tl.set('#s4-cam', { scale: 1.25, opacity: 1 }, 0);",
          "    tl.to('#s4-cam', { scale: 1, duration: 0.6, ease: 'expo.out' }, 0.001);"]
    for k, (i, s, ti) in enumerate(telas):
        js.append(f"    tl.set('#{i}', {{ opacity: 1 }}, {ti});")
        if k:
            js.append(f"    tl.set('#{telas[k - 1][0]}', {{ opacity: 0 }}, {ti + 0.01:.3f});")
    # socos de câmera nos resultados (o aviso e os números subindo)
    for alvo, ti, orig in [('plantou', t(9.9), '540px 520px'), ('colheu', t(11.3), '420px 640px'), ('ajudou', t(12.9), '600px 700px')]:
        js.append(f"    tl.set('#s4-cam', {{ scale: 1, transformOrigin: '{orig}' }}, {ti});")
        js.append(f"    tl.to('#s4-cam', {{ scale: 1.14, duration: 0.45, ease: 'expo.out' }}, {ti + 0.001:.3f});")
        js.append(f"    tl.set('#s4-cam', {{ scale: 1 }}, {ti + 0.99:.3f});")
    # para o alto-mar: a cor vira o azul do mar e o barco aparece
    js.append(f"    tl.set('#s4-cam', {{ scale: 1, transformOrigin: '540px 760px' }}, {t(14.9)});")
    js.append(f"    tl.fromTo('#s4-azul', {{ opacity: 0 }}, {{ opacity: 1, duration: 0.18, ease: 'power2.in' }}, {t(14.95)});")
    js.append(f"    tl.to('#s4-azul', {{ opacity: 0, duration: 0.3, ease: 'power2.out' }}, {t(15.13)});")
    js.append(f"    tl.set('#s4-mar', {{ transformOrigin: '200px 1900px', scale: 1.32 }}, {t(15.1)});")
    js.append(f"    tl.to('#s4-mar', {{ scale: 1.25, duration: 0.6, ease: 'expo.out' }}, {t(15.1) + 0.001:.3f});")
    # saída: escurece 3 quadros e corta (o corte para o passo a passo)
    js.append(f"    tl.to('#s4-cam', {{ opacity: 0.6, duration: 0.1, ease: 'none' }}, {t(16.8)});")
    return cena('s4', corpo, '\n'.join(js))


# ---------- cena 5: como entrar, em 3 passos ----------
def s5():
    t = lambda x: round(x - 16.9, 3)
    s = 1.7
    tx, ty = 540 - 228 * s, 800 - 1583 * s
    corpo = f"""    <img id="s5-topo" class="tela" src="assets/telas/port-topo.jpg" alt="" style="z-index:1" />
    <img id="s5-senai" class="tela" src="assets/telas/port-senai.jpg" alt="" style="z-index:2;opacity:0" data-layout-allow-overflow />
    <div id="s5-cam" style="position:absolute;inset:0;transform-origin:0 0;z-index:3;opacity:0">
      <img class="tela" src="assets/telas/port-projetos.jpg" alt="" />
    </div>
    <img id="s5-campo" class="tela" src="assets/telas/ent-campo.jpg" alt="" style="z-index:4;opacity:0" />
    <img id="s5-b" class="tela" src="assets/telas/ent-b.jpg" alt="" style="z-index:5;opacity:0" />
    <img id="s5-bi" class="tela" src="assets/telas/ent-bi.jpg" alt="" style="z-index:6;opacity:0" />
    <img id="s5-bia" class="tela" src="assets/telas/ent-bia.jpg" alt="" style="z-index:7;opacity:0" />
    <div id="s5-codcam" style="position:absolute;inset:0;transform-origin:540px 690px;z-index:8;opacity:0">
      <img class="tela" src="assets/telas/ent-codigo.jpg" alt="O código de recuperação" />
      <div id="s5-moldura" style="position:absolute;left:96px;top:566px;width:888px;height:248px;border:10px solid #3b7a3a;opacity:0"></div>
    </div>
    <img id="s5-mao" class="mao" src="assets/img/ico-mao.png" alt="" style="z-index:12;left:0;top:0;opacity:0" data-layout-allow-overflow />
    <div id="s5-p1" class="placa" style="left:70px;top:200px;width:940px;z-index:10;opacity:0;display:flex;align-items:center;gap:26px">
      <span class="pixel acento" style="font-size:150px">1</span>
      <span class="pixel" style="font-size:96px">jessecoelho.com.br</span>
    </div>
    <div id="s5-p2" class="placa" style="left:70px;top:200px;width:940px;z-index:10;opacity:0;display:flex;align-items:center;gap:26px">
      <span class="pixel acento" style="font-size:150px">2</span>
      <span class="pixel" style="font-size:88px">Projetos → Jogar agora</span>
    </div>
    <div id="s5-p3" class="placa" style="left:70px;top:200px;width:940px;z-index:10;opacity:0;display:flex;align-items:center;gap:26px">
      <span class="pixel acento" style="font-size:150px">3</span>
      <span class="pixel" style="font-size:92px">apelido + código</span>
    </div>"""
    js = f"""    // passo 1: o topo do site e o endereço
    tl.fromTo('#s5-topo', {{ scale: 1.08 }}, {{ scale: 1, duration: 0.5, ease: 'expo.out' }}, 0);
    tl.fromTo('#s5-p1', {{ opacity: 0, scale: 0.6 }}, {{ opacity: 1, scale: 1, duration: 0.35, ease: 'back.out(1.6)' }}, {t(17.3)});
    // passo 2: rola até Projetos (chicote pelo currículo) e a câmera vai até o botão
    tl.to('#s5-p1', {{ opacity: 0, duration: 0.12 }}, {t(20.4)});
    tl.fromTo('#s5-senai', {{ opacity: 1, y: 1920, filter: 'blur(18px)' }}, {{ opacity: 1, y: -1920, duration: 0.4, ease: 'none', immediateRender: false }}, {t(20.45)});
    tl.fromTo('#s5-cam', {{ opacity: 1, y: 1920, filter: 'blur(18px)' }}, {{ opacity: 1, y: 0, filter: 'blur(0px)', duration: 0.25, ease: 'power3.out', immediateRender: false }}, {t(20.6)});
    tl.set('#s5-topo', {{ opacity: 0 }}, {t(20.86)});
    tl.fromTo('#s5-p2', {{ opacity: 0, scale: 0.6 }}, {{ opacity: 1, scale: 1, duration: 0.35, ease: 'back.out(1.6)' }}, {t(20.85)});
    tl.to('#s5-cam', {{ x: {tx:.1f}, y: {ty:.1f}, scale: {s}, duration: 0.6, ease: 'power2.inOut' }}, {t(21.9)});
    tl.fromTo('#s5-mao', {{ x: 1000, y: 1500, opacity: 1 }}, {{ x: 500, y: 780, opacity: 1, duration: 0.4, ease: 'expo.out', immediateRender: false }}, {t(22.6)});
    tl.to('#s5-mao', {{ scale: 0.85, duration: 0.1, ease: 'power2.in' }}, {t(23.0)});
    tl.to('#s5-mao', {{ scale: 1, duration: 0.12, ease: 'power2.out' }}, {t(23.1)});
    tl.to('#s5-mao', {{ opacity: 0, duration: 0.1 }}, {t(23.3)});
    // passo 3: a porteira, o apelido letra por letra e o código
    tl.to('#s5-p2', {{ opacity: 0, duration: 0.12 }}, {t(23.4)});
    tl.fromTo('#s5-campo', {{ opacity: 0, scale: 1.1 }}, {{ opacity: 1, scale: 1, duration: 0.4, ease: 'expo.out' }}, {t(23.45)});
    tl.fromTo('#s5-p3', {{ opacity: 0, scale: 0.6 }}, {{ opacity: 1, scale: 1, duration: 0.35, ease: 'back.out(1.6)' }}, {t(23.85)});
    tl.set('#s5-b', {{ opacity: 1 }}, {t(24.3)});
    tl.set('#s5-bi', {{ opacity: 1 }}, {t(24.55)});
    tl.set('#s5-bia', {{ opacity: 1 }}, {t(24.8)});
    tl.fromTo('#s5-codcam', {{ opacity: 0, scale: 1.12 }}, {{ opacity: 1, scale: 1, duration: 0.45, ease: 'expo.out' }}, {t(25.4)});
    tl.fromTo('#s5-moldura', {{ opacity: 0, scale: 1.15 }}, {{ opacity: 1, scale: 1, duration: 0.3, ease: 'back.out(1.6)' }}, {t(25.6)});
    // saída: o verde da grama sobe e o final entra
    tl.to('#s5-p3', {{ opacity: 0, duration: 0.15 }}, {t(27.2)});"""
    return cena('s5', corpo, js)


# ---------- cena 6: o final ----------
def s6():
    corpo = """    <div id="s6-chao" style="position:absolute;inset:0;background:#84c669"></div>
    <div id="s6-marca" style="position:absolute;left:0;top:230px;width:1080px;text-align:center;z-index:3">
      <div id="s6-girassol" style="margin:0 auto;width:260px;height:300px;background:url(assets/img/girassol.png) center/contain no-repeat;image-rendering:pixelated"></div>
      <div id="s6-nome" class="pixel" style="font-size:118px;color:#fde6c9;-webkit-text-stroke:10px #3f2631;paint-order:stroke fill;margin-top:10px">Fazendinha Secreta</div>
    </div>
    <div id="s6-cta" class="placa" style="left:90px;top:760px;width:900px;z-index:4;text-align:center">
      <div class="pixel" style="font-size:104px">jessecoelho.com.br</div>
      <div style="font: 900 46px 'Nunito', sans-serif; margin-top:6px" class="acento">link na bio</div>
    </div>"""
    js = """    // o chão de grama sobe como uma maré (a cor muda, o Jessé fica)
    tl.fromTo('#s6-chao', { clipPath: 'inset(100% 0 0 0)' }, { clipPath: 'inset(0% 0 0 0)', duration: 0.4, ease: 'power2.inOut' }, 0);
    // o girassol cai e quica; o nome entra em cima dele, letra por letra em grupos
    tl.fromTo('#s6-girassol', { y: -500, scale: 0.6 }, { y: 0, scale: 1, duration: 0.5, ease: 'back.out(1.8)' }, 0.15);
    tl.fromTo('#s6-nome', { opacity: 0, filter: 'blur(8px)' }, { opacity: 1, filter: 'blur(0px)', duration: 0.18, ease: 'power4.out' }, 0.42);
    // o CTA chega e fica parado até o fim (2,2 s)
    tl.fromTo('#s6-cta', { opacity: 0, scale: 0.6 }, { opacity: 1, scale: 1, duration: 0.35, ease: 'back.out(1.6)' }, 0.45);"""
    return cena('s6', corpo, js, '      #root { background: transparent; }')


# ---------- o personagem: o Jessé desenhado fala mexendo o corpo e troca de cara a cada frase ----------
# as caras saem da folha de personagem (assets/img/personagem, montadas por scratchpad/personagem/compor.py):
# corpo da folha + a cabeça de cada expressão, espelhado; 836 x 1400 em 2x, mostrado em 418 x 700.
# O braço cortado da folha fica na borda direita do quadro, sempre para fora.
CARAS = ['sorriso', 'desconfiado', 'surpreso', 'sorriso_aberto', 'rindo', 'falando', 'piscando']
EXPRESSOES = [  # momento, cara (presa nas legendas)
    (0.0, 'sorriso'), (3.0, 'desconfiado'), (6.1, 'surpreso'), (8.05, 'sorriso_aberto'), (10.9, 'rindo'),
    (12.3, 'sorriso'), (13.9, 'falando'), (15.15, 'surpreso'), (16.95, 'falando'), (18.0, 'sorriso'),
    (20.5, 'falando'), (22.0, 'sorriso_aberto'), (23.9, 'falando'), (25.3, 'sorriso'), (27.5, 'rindo'), (28.9, 'piscando'),
]
# o gesto: no "Rola o currículo…" a mão sai do bolso e vai ao queixo (pensativo); no "E no fim tem…" volta.
# O antebraço gira no cotovelo (36, 470) e leva a mão junto (scratchpad/personagem/gesto.py).
GESTO = dict(ini=3.35, sobe=0.42, giro=-143.8, volta=6.1, desce=0.3, antes='desconfiado', meio='pensativo', depois='surpreso')


def estado(s):
    # o corte do braço (x 388 de 418) fica em x 1105; a linha y 640 da imagem fica no pé do quadro
    bx, by = 1105 - 179 * s, 1920 + 60 * s
    return dict(x=round(bx - 209, 2), y=round(by - 700, 2), s=s)


def personagem(falas):
    G, P = estado(1.25), estado(0.85)
    passo = 1 / 15
    # cada fala: [início, energias de 0 a 99 a cada 1/15 s, fim do descanso]
    dados = []
    for k, (nome, ini, e) in enumerate(falas):
        prox = falas[k + 1][1] if k + 1 < len(falas) else DUR
        fim = ini + len(e) * passo
        dados.append([round(ini, 3), [round(v * 99) for v in e], round(min(0.18, max(0.02, prox - fim - 0.01)), 3)])
    trocas = []
    g = GESTO
    for k, (t, cara) in enumerate(EXPRESSOES):
        if k == 0 or t == g['volta']:
            continue
        antes = EXPRESSOES[k - 1][1]
        trocas.append(f"    tl.set('#ps-{antes}', {{ opacity: 0 }}, {t});")
        trocas.append(f"    tl.set('#ps-{cara}', {{ opacity: 1 }}, {t});")
        trocas.append(f"    tl.set('#ps-cara', {{ scaleX: 1.03, scaleY: 0.96 }}, {t});")
        trocas.append(f"    tl.to('#ps-cara', {{ scaleX: 1, scaleY: 1, duration: 0.16, ease: 'back.out(2)' }}, {t});")
    sobe_fim, desce_fim = round(g['ini'] + g['sobe'], 3), round(g['volta'] + g['desce'], 3)
    gesto = f"""    // a mão sai do bolso: troca a figura inteira pelas camadas do gesto e gira o antebraço até o queixo
    tl.set('#ps-g-braco', {{ transformOrigin: '36px 470px', rotation: 0 }}, 0);
    tl.set('#ps-{g['antes']}', {{ opacity: 0 }}, {g['ini']});
    tl.set('#ps-gesto', {{ opacity: 1 }}, {g['ini']});
    tl.to('#ps-g-braco', {{ rotation: {g['giro']}, duration: {g['sobe']}, ease: 'power2.inOut' }}, {g['ini']});
    tl.set('#ps-g-{g['antes']}', {{ opacity: 0 }}, {sobe_fim});
    tl.set('#ps-g-{g['meio']}', {{ opacity: 1 }}, {sobe_fim});
    tl.set('#ps-cara', {{ scaleX: 1.03, scaleY: 0.96 }}, {sobe_fim});
    tl.to('#ps-cara', {{ scaleX: 1, scaleY: 1, duration: 0.16, ease: 'back.out(2)' }}, {sobe_fim});
    // e volta para o bolso na surpresa
    tl.set('#ps-g-{g['meio']}', {{ opacity: 0 }}, {g['volta']});
    tl.set('#ps-g-{g['depois']}', {{ opacity: 1 }}, {g['volta']});
    tl.set('#ps-cara', {{ scaleX: 1.03, scaleY: 0.96 }}, {g['volta']});
    tl.to('#ps-cara', {{ scaleX: 1, scaleY: 1, duration: 0.16, ease: 'back.out(2)' }}, {g['volta']});
    tl.to('#ps-g-braco', {{ rotation: 0, duration: {g['desce']}, ease: 'power2.in' }}, {g['volta']});
    tl.set('#ps-gesto', {{ opacity: 0 }}, {desce_fim});
    tl.set('#ps-{g['depois']}', {{ opacity: 1 }}, {desce_fim});"""
    js = f"""    tl.set('#ps-pos', {{ x: {G['x']}, y: {G['y']}, scale: {G['s']} }}, 0);
    tl.to('#ps-pos', {{ x: {P['x']}, y: {P['y']}, scale: {P['s']}, duration: 0.5, ease: 'back.out(1.3)' }}, 2.85);
    tl.to('#ps-pos', {{ x: {G['x']}, y: {G['y']}, scale: {G['s']}, duration: 0.55, ease: 'back.out(1.3)' }}, 27.35);
    // a cara muda a cada frase, com um amassadinho de 0,16 s
{chr(10).join(trocas)}
{gesto}
    // a fala: cada 1/15 s da voz vira um pulo, um esticão e um giro que troca de lado nas sílabas fortes
    // (gerado por gerar.py a partir da energia de cada arquivo em assets/vo)
    const FALAS = {json.dumps(dados, separators=(',', ':'))};
    const PASSO = 1 / 15;
    let lado = 1;
    for (const [ini, e, descanso] of FALAS) {{
      let ult = 0;
      e.forEach((n, k) => {{
        const v = n / 99, t = ini + k * PASSO;
        if (v > 0.55 && v >= ult && k % 3 === 0) lado = -lado;
        tl.to('#ps-corpo', {{ y: -16 * v, scaleY: 1 + 0.035 * v, rotation: lado * 2.5 * v, duration: PASSO - 0.002, ease: 'none' }}, t);
        ult = v;
      }});
      tl.to('#ps-corpo', {{ y: 0, scaleY: 1, rotation: 0, duration: descanso, ease: 'power2.out' }}, ini + e.length * PASSO);
    }}"""
    imgs = '\n'.join(
        f'          <img id="ps-{c}" src="assets/img/personagem/jesse-{c}.webp" alt="Jessé desenhado ({c.replace("_", " ")})" '
        f'style="position:absolute;inset:0;width:418px;height:700px;opacity:{1 if c == EXPRESSOES[0][1] else 0}" />' for c in CARAS)
    def gimg(i, arq, op, alt=700, extra=''):
        return (f'            <img id="ps-g-{i}" src="assets/img/personagem/gesto-{arq}.webp" alt="" '
                f'style="position:absolute;left:0;top:0;width:418px;height:{alt}px;opacity:{op}{extra}" />')
    camadas = '\n'.join([gimg('base', 'base', 1)] + [gimg(c, f'cara-{c}', 1 if c == g['antes'] else 0) for c in (g['antes'], g['meio'], g['depois'])])
    corpo = f"""    <div id="ps-pos" style="position:absolute;left:0;top:0;width:418px;height:700px;transform-origin:50% 100%">
      <div id="ps-corpo" style="position:absolute;inset:0;transform-origin:50% 100%">
        <div id="ps-cara" style="position:absolute;inset:0;transform-origin:50% 100%">
{imgs}
          <div id="ps-gesto" style="position:absolute;inset:0;opacity:0" data-layout-allow-overflow>
{camadas}
            <div id="ps-g-braco" style="position:absolute;left:0;top:0;width:418px;height:780px">
{gimg('antebraco', 'antebraco', 1, 780)}
{gimg('mao', 'mao', 1, 780, f';transform-origin:36px 470px;transform:rotate({-g["giro"]}deg)')}
            </div>
          </div>
        </div>
      </div>
    </div>"""
    return f"""<template>
  <style>
      #root {{ position: absolute; inset: 0; overflow: hidden; pointer-events: none; }}
  </style>
  <div id="root" data-composition-id="personagem" data-width="1080" data-height="1920" data-layout-allow-overflow data-layout-allow-occlusion>
{corpo}
  </div>
  <script>
    const tl = gsap.timeline({{ paused: true }});
{js}
    window.__timelines["personagem"] = tl;
  </script>
</template>
"""


# ---------- as legendas ----------
def legendas(grupos):
    corpo, js = [], []
    for k, (ini, fim, texto) in enumerate(grupos):
        gid = f'lg{k}'
        corpo.append(f'    <div id="{gid}" class="grupo" style="opacity:0;visibility:hidden"><span class="placa-leg">{marcar(texto)}</span></div>')
        js.append(f"    tl.set('#{gid}', {{ visibility: 'visible' }}, {ini:.3f});")
        js.append(f"    tl.fromTo('#{gid}', {{ opacity: 0, filter: 'blur(6px)' }}, {{ opacity: 1, filter: 'blur(0px)', duration: 0.13, ease: 'power4.out' }}, {ini:.3f});")
        js.append(f"    tl.to('#{gid}', {{ opacity: 0, duration: 0.12, ease: 'power2.in' }}, {fim - 0.12:.3f});")
        js.append(f"    tl.set('#{gid}', {{ opacity: 0, visibility: 'hidden' }}, {fim:.3f});")
    return f"""<template>
  <style>
      #root {{ position: absolute; inset: 0; pointer-events: none; }}
      .grupo {{ position: absolute; left: 0; width: 1080px; top: 1010px; text-align: center; }}
      .placa-leg {{ display: inline-block; max-width: 860px; background: #fde6c9; color: #3f2631; border: 6px solid #3f2631;
                    box-shadow: 0 8px 0 #3f2631, inset 0 -6px 0 #fec99c; padding: 10px 28px 14px;
                    font: 900 60px/1.12 'Nunito', sans-serif; }}
      .acento {{ color: #3b7a3a; font-weight: 900; }}
  </style>
  <div id="root" data-composition-id="legendas" data-width="1080" data-height="1920">
{chr(10).join(corpo)}
  </div>
  <script>
    const tl = gsap.timeline({{ paused: true }});
{chr(10).join(js)}
    window.__timelines["legendas"] = tl;
  </script>
</template>
"""


def main():
    os.makedirs(os.path.join(RAIZ, 'compositions'), exist_ok=True)
    falas, grupos, audios = [], [], []
    for nome, ini, texto in VOZ:
        e, dur, f0, f1 = energia(os.path.join(RAIZ, 'assets/vo', nome + '.wav'))
        falas.append((nome, ini, e))
        audios.append((f'a-{nome}', f'assets/vo/{nome}.wav', ini, dur, 1.2, 1.0, 20))
        # legendas: os grupos dividem o tempo de fala pelo tamanho do texto
        partes = [p.strip() for p in texto.split('/')]
        tam = [len(p.replace('*', '')) for p in partes]
        total = sum(tam)
        a = ini + f0
        for p, n in zip(partes, tam):
            b = a + (f1 - f0) * n / total
            grupos.append([a - 0.05, b, p])
            a = b
    # cada grupo fica até o próximo começar (no mínimo 0,6 s), sem passar dele
    for k, g in enumerate(grupos):
        prox = grupos[k + 1][0] if k + 1 < len(grupos) else DUR
        g[1] = min(prox - 0.02, max(g[1] + 0.25, g[0] + 0.6))
    for k, (nome, t, vol, vel) in enumerate(SFX):
        arq = f'{SFX_DIR}/{nome}.mp3'
        dur = float(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', os.path.join(RAIZ, arq)]).decode().strip())
        if nome == 'riser':   # o riser tem 10 s: só o fim dele, terminando no impacto (6,9 s)
            audios.append((f'sfx{k}-riser', arq, t, 1.3, vol, 1.0, 30 + k % 4, 8.6))
            continue
        audios.append((f'sfx{k}-{nome}', arq, t, dur / vel, vol, vel, 30 + k % 4))

    open(os.path.join(RAIZ, 'compositions/s1.html'), 'w').write(s1())
    open(os.path.join(RAIZ, 'compositions/s2.html'), 'w').write(s2())
    open(os.path.join(RAIZ, 'compositions/s3.html'), 'w').write(s3())
    open(os.path.join(RAIZ, 'compositions/s4.html'), 'w').write(s4())
    open(os.path.join(RAIZ, 'compositions/s5.html'), 'w').write(s5())
    open(os.path.join(RAIZ, 'compositions/s6.html'), 'w').write(s6())
    open(os.path.join(RAIZ, 'compositions/personagem.html'), 'w').write(personagem(falas))
    open(os.path.join(RAIZ, 'compositions/legendas.html'), 'w').write(legendas(grupos))

    hosts = '\n'.join(f'      <div id="{c}" data-composition-id="{c}" data-composition-src="compositions/{c}.html" data-start="{a}" data-duration="{d}" data-track-index="1" data-track-kind="graphics" data-width="1080" data-height="1920" style="z-index:{2 if c == "s6" else 1}"></div>' for c, a, d in CENAS)
    aud = []
    for item in audios:
        aid, src, t, dur, vol, vel, trilha = item[:7]
        ms = f' data-media-start="{item[7]}" data-fade-in="0.3"' if len(item) > 7 else ''
        rate = f' data-playback-rate="{vel}"' if vel != 1.0 else ''
        aud.append(f'      <audio id="{aid}" class="clip" src="{src}" data-start="{t:.3f}" data-duration="{dur:.3f}" data-track-index="{trilha}" data-volume="{vol}"{rate}{ms}></audio>')
    index = f"""<!doctype html>
<html lang="pt-BR" data-resolution="portrait"
  data-composition-variables='[
    {{"id":"color-ground","type":"color","label":"Grama","default":"#84c669"}},
    {{"id":"color-ink","type":"color","label":"Contorno e texto","default":"#3f2631"}},
    {{"id":"color-accent","type":"color","label":"Acento","default":"#3b7a3a"}},
    {{"id":"font-display","type":"string","label":"Fonte dos títulos","default":"Jersey 10"}}
  ]'>
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=1080, height=1920" />
    <title>Reels: POV era só um portfólio</title>
    <script src="assets/vendor/gsap.min.js"></script>
    <style>
      * {{ margin: 0; padding: 0; box-sizing: border-box; }}
      html, body {{ margin: 0; width: 1080px; height: 1920px; overflow: hidden; background: #1a0a0d; }}
      #root {{ position: relative; width: 1080px; height: 1920px; overflow: hidden; }}
    </style>
  </head>
  <body>
    <div id="root" data-composition-id="main" data-start="0" data-duration="{DUR}" data-width="1080" data-height="1920">
{hosts}
      <div id="personagem" data-composition-id="personagem" data-composition-src="compositions/personagem.html" data-start="0" data-duration="{DUR}" data-track-index="3" data-track-kind="graphics" data-width="1080" data-height="1920" style="z-index:5"></div>
      <div id="legendas" data-composition-id="legendas" data-composition-src="compositions/legendas.html" data-start="0" data-duration="{DUR}" data-track-index="4" data-track-kind="captions" data-width="1080" data-height="1920" style="z-index:6"></div>
{chr(10).join(aud)}
    </div>
    <script>
      window.__timelines["main"] = gsap.timeline({{ paused: true }});
    </script>
  </body>
</html>
"""
    open(os.path.join(RAIZ, 'index.html'), 'w').write(index)
    print('ok:', len(grupos), 'legendas,', len(audios), 'áudios,', sum(len(e) for _, _, e in falas), 'passos de fala')


if __name__ == '__main__':
    main()
