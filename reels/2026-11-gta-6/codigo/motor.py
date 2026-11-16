#!/usr/bin/env python3
"""Motor dos Reels com o personagem do Jessé (receita reels-jesse), guiado pela voz.

Cada vídeo é uma pasta HyperFrames e um arquivo <nome>.py que chama gerar(raiz, cfg).
Os tempos saem dos arquivos de voz (assets/vo/<id>.wav): trocar a voz (Kokoro -> ElevenLabs) e rodar de novo
reencaixa cenas, legendas, poses e efeitos sozinho.

Âncora de tempo: 3.2 (segundos do filme) | ('vo3', 0.5) = meio da fala vo3 | ('vo3', 1, 0.2) = 0,2 s depois do fim dela.
"""
import json, math, os, wave, struct, subprocess

PASSO = 1 / 15
FOCO = (540, 640)          # onde o ponto de interesse da tela fica no quadro (acima das legendas)


def ler_wav(caminho):
    with wave.open(caminho, 'rb') as w:
        n, sw, fr, nc = w.getnframes(), w.getsampwidth(), w.getframerate(), w.getnchannels()
        dados = w.readframes(n)
    if sw != 2:
        raise SystemExit('wav de %d bytes por amostra' % sw)
    a = struct.unpack('<%dh' % (len(dados) // 2), dados)
    return [s / 32768 for s in a[::nc]], fr


def energia(caminho):
    a, fr = ler_wav(caminho)
    jan = int(fr * PASSO)
    rms = [math.sqrt(sum(x * x for x in a[i:i + jan]) / max(1, len(a[i:i + jan]))) for i in range(0, len(a), jan)]
    topo = max(rms) or 1
    e = [min(1, r / topo) for r in rms]
    fala = [i for i, v in enumerate(e) if v > 0.12]
    ini, fim = (fala[0] * PASSO, (fala[-1] + 1) * PASSO) if fala else (0, len(a) / fr)
    return e, len(a) / fr, ini, fim


def esc(t):
    return t.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')


def marcar(t):
    partes = t.split('*')
    return ''.join(('<b class="acento">%s</b>' % esc(p)) if i % 2 else esc(p) for i, p in enumerate(partes))


FONTE = """@font-face { font-family: 'Jersey 10'; src: url('assets/fonts/jersey10-latin.woff2') format('woff2'); font-weight: 400; font-style: normal; }"""
PLACA_CSS = """
      .placa { position: absolute; background: #fde6c9; color: #3f2631; border: 6px solid #3f2631;
               box-shadow: 0 8px 0 #3f2631, inset 0 -6px 0 #fec99c; padding: 14px 30px 18px; }
      .pixel { font-family: 'Jersey 10', 'Nunito', monospace; font-weight: 400; letter-spacing: 0.01em; line-height: 0.95; }
      .acento { color: #3b7a3a; font-weight: inherit; }
      .mao { position: absolute; width: 156px; height: 156px; image-rendering: pixelated; }
      .moldura { position: absolute; border: 10px solid #3b7a3a; box-shadow: 0 0 0 5px #fde6c9; opacity: 0; }
"""


def gerar(raiz, cfg):
    vo = lambda f: os.path.join(raiz, 'assets/vo', f + '.wav')
    # ---------- a voz manda no relógio ----------
    V, t = {}, cfg.get('inicio', 0.25)
    for fid, _ in cfg['falas']:
        e, dur, f0, f1 = energia(vo(fid))
        V[fid] = dict(ini=round(t, 3), dur=dur, e=e, f0=f0, f1=f1)
        t += dur + cfg.get('pausas', {}).get(fid, cfg.get('pausa', 0.2))
    ultimo = cfg['falas'][-1][0]
    DUR = round(V[ultimo]['ini'] + V[ultimo]['dur'] + cfg.get('fim', 1.5), 2)

    def T(a):
        if isinstance(a, (int, float)): return float(a)
        v = V[a[0]]
        return v['ini'] + v['dur'] * a[1] + (a[2] if len(a) > 2 else 0)

    cenas = cfg['cenas']
    ini_c = [0.0] + [round(T(c['de']), 3) for c in cenas[1:]]
    sfx = []          # (nome, t, vol)

    def cam_xy(cx, cy, z, alt, foco, livre=False):
        x, y = foco[0] - cx * z, foco[1] - cy * z
        if livre: return round(x, 1), round(y, 1)
        x = min(0, max(1080 - 1080 * z, x)); y = min(0, max(1920 - alt * z, y))
        return round(x, 1), round(y, 1)

    def cena_html(k, c):
        cid, ini = c['id'], ini_c[k]
        prox = cenas[k + 1] if k + 1 < len(cenas) else None
        fim = ini_c[k + 1] if prox else DUR
        sobra = 0.34 if prox and prox.get('entra', 'empurra') != 'corta' else 0.0
        dur = round(fim - ini + sobra, 3)
        L = lambda a: round(max(0.0, T(a) - ini), 3)
        shots = c.get('shots', [])
        tem_video = any(s['tipo'] == 'video' for s in shots)
        corpo = [f'    <div id="{cid}-tudo" style="position:absolute;inset:0;overflow:hidden;background:{c.get("fundo", "#1a0a0d")}">']
        js = []
        t_shot = [0.0] + [L(s['em']) for s in shots[1:]]
        for n, s in enumerate(shots):
            sid, t0, alt = f'{cid}-c{n}', t_shot[n], s.get('alt', 1920)
            t1 = (t_shot[n + 1] + 0.22) if n + 1 < len(shots) and not shots[n + 1].get('sobre') else dur
            if s['tipo'] == 'video':
                ms = f' data-media-start="{s["corte"]}"' if s.get('corte') else ''
                midia = (f'<video id="{sid}-v" class="clip" muted playsinline src="assets/telas/{s["src"]}" data-start="{t0}" data-duration="{round(t1 - t0, 3)}" '
                         f'data-track-index="{10 + n}"{ms} style="position:absolute;left:0;top:0;width:1080px;height:1920px;object-fit:cover"></video>')
            else:
                midia = f'<img id="{sid}-i" src="assets/telas/{s["src"]}" alt="{esc(s.get("alt_txt", ""))}" style="position:absolute;left:0;top:0;width:{s.get("larg", 1080)}px;height:{alt}px" />'
            dentro = [midia]
            for m, (a0, src) in enumerate(s.get('estados', [])):       # o mesmo lugar mudando de estado: funde em cima, na mesma câmera
                eid = f'{sid}-e{m}'
                dentro.append(f'<img id="{eid}" src="assets/telas/{src}" alt="" style="position:absolute;left:0;top:0;width:1080px;height:{alt}px;opacity:0" />')
                js.append(f"    tl.to('#{eid}', {{ opacity: 1, duration: 0.1, ease: 'power1.inOut' }}, {L(a0)});")
            for m, (a0, a1, (x, y, w, h)) in enumerate(s.get('molduras', [])):
                mid = f'{sid}-m{m}'
                dentro.append(f'<div id="{mid}" class="moldura" style="left:{x - 16}px;top:{y - 16}px;width:{w + 32}px;height:{h + 32}px" data-layout-allow-overflow></div>')
                js.append(f"    tl.fromTo('#{mid}', {{ opacity: 0, scale: 1.18 }}, {{ opacity: 1, scale: 1, duration: 0.3, ease: 'back.out(1.6)' }}, {L(a0)});")
                js.append(f"    tl.to('#{mid}', {{ opacity: 0, duration: 0.12 }}, {round(dur - 0.14, 3) if a1 == 'fim' else min(L(a1), round(dur - 0.14, 3))});")
                sfx.append(('pop', T(a0) + 0.02, 0.30))
            for m, (a0, (x, y)) in enumerate(s.get('maos', [])):
                hid, th = f'{sid}-h{m}', L(a0)
                dentro.append(f'<img id="{hid}" class="mao" src="assets/img/ico-mao.png" alt="" style="left:{x - 50}px;top:{y - 20}px;opacity:0;z-index:5" data-layout-allow-overflow />')
                js.append(f"    tl.fromTo('#{hid}', {{ x: 380, y: 560, opacity: 1 }}, {{ x: 0, y: 0, opacity: 1, duration: 0.4, ease: 'expo.out', immediateRender: false }}, {th});")
                js.append(f"    tl.to('#{hid}', {{ scale: 0.82, duration: 0.1, ease: 'power2.in' }}, {round(th + 0.42, 3)});")
                js.append(f"    tl.to('#{hid}', {{ scale: 1, duration: 0.12, ease: 'power2.out' }}, {round(th + 0.52, 3)});")
                js.append(f"    tl.to('#{hid}', {{ opacity: 0, duration: 0.12 }}, {round(th + 0.8, 3)});")
                sfx.append(('click', T(a0) + 0.5, 0.5))
            corpo.append(f'      <div id="{sid}" style="position:absolute;left:0;top:0;width:{s.get("larg", 1080)}px;height:{alt}px;transform-origin:0 0;opacity:{0 if n else 1};z-index:{n + 1}" data-layout-allow-overflow>\n        '
                         + '\n        '.join(dentro) + '\n      </div>')
            if n:
                if s.get('entra', 'funde') == 'funde':
                    js.append(f"    tl.to('#{sid}', {{ opacity: 1, duration: 0.16, ease: 'power1.inOut' }}, {round(max(0, t0 - 0.08), 3)});")
                else:
                    js.append(f"    tl.set('#{sid}', {{ opacity: 1 }}, {t0});")
                if not s.get('sobre'):      # 'sobre': um cartão por cima, a tela de baixo continua
                    js.append(f"    tl.set('#{cid}-c{n - 1}', {{ opacity: 0 }}, {round(t0 + 0.2, 3)});")
                else:
                    js.append(f"    tl.fromTo('#{sid}-i', {{ scale: 0.6 }}, {{ scale: 1, duration: 0.34, ease: 'back.out(1.6)' }}, {round(max(0, t0 - 0.08), 3)});")
                    sfx.append(('pop', ini + t0, 0.34))
            # a câmera: nunca parada
            foco = s.get('foco', FOCO)
            qs = s['cam']
            x, y = cam_xy(qs[0][1], qs[0][2], qs[0][3], alt, foco, s.get('livre'))
            js.append(f"    tl.set('#{sid}', {{ x: {x}, y: {y}, scale: {qs[0][3]} }}, 0);")
            ta = t0 if n else 0.0
            for q in qs[1:]:
                tb = L(q[0]) if q[0] != 'fim' else dur
                x, y = cam_xy(q[1], q[2], q[3], alt, foco, s.get('livre'))
                ease = q[4] if len(q) > 4 else 'sine.inOut'
                if tb - ta > 0.05:
                    js.append(f"    tl.to('#{sid}', {{ x: {x}, y: {y}, scale: {q[3]}, duration: {round(tb - ta, 3)}, ease: '{ease}' }}, {round(ta, 3)});")
                ta = tb
        corpo.append('    </div>')
        # as placas de título (fora da câmera)
        for m, p in enumerate(c.get('placas', [])):
            a0, a1, html = p[0], p[1], p[2]
            top, tam = (p[3] if len(p) > 3 else 200), (p[4] if len(p) > 4 else 100)
            pid = f'{cid}-p{m}'
            visivel = (k == 0 and T(a0) <= 0.01)        # o gancho já está no quadro 0
            corpo.append(f'    <div id="{pid}" class="placa pixel" style="left:70px;top:{top}px;width:940px;text-align:center;z-index:30;font-size:{tam}px;opacity:{1 if visivel else 0}">{html}</div>')
            if visivel:
                js.append(f"    tl.fromTo('#{pid}', {{ scale: 1 }}, {{ scale: 1.045, duration: 0.14, ease: 'power2.out', yoyo: true, repeat: 1 }}, 0.9);")
            else:
                js.append(f"    tl.fromTo('#{pid}', {{ opacity: 0, scale: 0.6 }}, {{ opacity: 1, scale: 1, duration: 0.35, ease: 'back.out(1.6)' }}, {L(a0)});")
                sfx.append(('pop', T(a0) + 0.03, 0.34))
            js.append(f"    tl.to('#{pid}', {{ opacity: 0, duration: 0.12 }}, {min(L(a1), dur - 0.13) if a1 != 'fim' else round(dur - 0.13, 3)});")
        if 'extra' in c:
            h, j = c['extra'](L, dur)
            corpo.append(h); js.append(j)
        # a entrada e a saída da cena
        entra = c.get('entra', 'empurra') if k else 'corta'
        if entra == 'empurra':
            borrao = "" if tem_video else ", filter: 'blur(14px)'"
            borrao0 = "" if tem_video else ", filter: 'blur(0px)'"
            js.insert(0, f"    tl.fromTo('#{cid}-tudo', {{ x: 1080{borrao} }}, {{ x: 0{borrao0}, duration: 0.32, ease: 'power3.out' }}, 0);")
            sfx.append(('whoosh', ini - 0.08, 0.34))
        elif entra == 'sobe':
            js.insert(0, f"    tl.fromTo('#{cid}-tudo', {{ y: 1920 }}, {{ y: 0, duration: 0.3, ease: 'power3.out' }}, 0);")
            sfx.append(('whoosh', ini - 0.08, 0.36))
        if sobra:
            pe = prox.get('entra', 'empurra')
            if pe == 'empurra':
                js.append(f"    tl.to('#{cid}-tudo', {{ x: -320, duration: 0.32, ease: 'power3.out' }}, {round(dur - sobra, 3)});")
            elif pe == 'sobe':
                js.append(f"    tl.to('#{cid}-tudo', {{ y: -520, duration: 0.3, ease: 'power3.out' }}, {round(dur - sobra, 3)});")
        html = f"""<template>
  <style>
      {FONTE}
      #root {{ position: absolute; inset: 0; overflow: hidden; font-family: 'Nunito', sans-serif; }}
{PLACA_CSS}
{c.get('css', '')}
  </style>
  <div id="root" data-composition-id="{cid}" data-width="1080" data-height="1920">
{chr(10).join(corpo)}
  </div>
  <script>
    const tl = gsap.timeline({{ paused: true }});
{chr(10).join(js)}
    window.__timelines["{cid}"] = tl;
  </script>
</template>
"""
        return html, ini, dur

    # ---------- o personagem ----------
    POSES_INFO = json.load(open(os.path.join(raiz, 'assets/img/poses/poses.json')))
    ALTURA, TROCA = 1130, 0.1
    G, P = dict(x=820, y=2308, s=2.05), dict(x=905, y=2106, s=1.25)
    POSES_T = [(round(T(a), 3), p) for a, p in cfg['poses']]

    def personagem():
        dados = []
        ordem = [f for f, _ in cfg['falas']]
        for k, f in enumerate(ordem):
            v = V[f]
            prox = V[ordem[k + 1]]['ini'] if k + 1 < len(ordem) else DUR
            fim = v['ini'] + len(v['e']) * PASSO
            dados.append([v['ini'], [round(x * 99) for x in v['e']], round(min(0.18, max(0.02, prox - fim - 0.01)), 3)])
        usadas = list(dict.fromkeys(p for _, p in POSES_T))
        imgs = []
        for p in usadas:
            d = POSES_INFO[p]; kk = ALTURA / d['altura'] / 2
            imgs.append(f'          <img id="ps-{p}" src="assets/img/poses/{p}.webp" alt="Jessé desenhado ({p})" '
                        f'style="position:absolute;left:{-d["pe_x"] * kk:.1f}px;top:{-d["pe_y"] * kk:.1f}px;'
                        f'width:{d["largura"] * kk:.1f}px;height:{d["altura"] * kk:.1f}px;opacity:{1 if p == POSES_T[0][1] else 0}" />')
        trocas = []
        for n, (t, p) in enumerate(POSES_T[1:], 1):
            antes = POSES_T[n - 1][1]
            if antes == p: continue
            trocas += [f"    tl.to('#ps-{antes}', {{ opacity: 0, duration: {TROCA}, ease: 'power1.inOut' }}, {t});",
                       f"    tl.to('#ps-{p}', {{ opacity: 1, duration: {TROCA}, ease: 'power1.inOut' }}, {t});",
                       f"    tl.set('#ps-troca', {{ scaleX: 1.025, scaleY: 0.955, y: 10 }}, {t});",
                       f"    tl.to('#ps-troca', {{ scaleX: 1, scaleY: 1, y: 0, duration: 0.34, ease: 'back.out(2.4)' }}, {round(t + 0.001, 3)});"]
        ciclos = int(DUR / 1.6) + 1
        t_peq, t_gra = round(T(cfg['pequeno_em']) if 'pequeno_em' in cfg else ini_c[1] - 0.15, 3), round(ini_c[-1] - 0.05, 3)
        js = f"""    tl.set('#ps-pos', {{ x: {G['x']}, y: {G['y']}, scale: {G['s']}, transformOrigin: '0 0' }}, 0);
    tl.to('#ps-pos', {{ x: {P['x']}, y: {P['y']}, scale: {P['s']}, duration: 0.55, ease: 'back.out(1.2)' }}, {t_peq});
    tl.to('#ps-pos', {{ x: {G['x']}, y: {G['y']}, scale: {G['s']}, duration: 0.6, ease: 'back.out(1.2)' }}, {t_gra});
    tl.set(['#ps-resp', '#ps-corpo', '#ps-troca'], {{ transformOrigin: '0 0' }}, 0);
    tl.fromTo('#ps-resp', {{ scaleY: 1, rotation: -0.6 }}, {{ scaleY: 1.014, rotation: 0.6, duration: 0.8, ease: 'sine.inOut', yoyo: true, repeat: {ciclos * 2 - 1} }}, 0);
{chr(10).join(trocas)}
    const FALAS = {json.dumps(dados, separators=(',', ':'))};
    const PASSO = 1 / 15;
    let lado = 1;
    for (const [ini, e, descanso] of FALAS) {{
      let ult = 0;
      e.forEach((n, k) => {{
        const v = n / 99, t = ini + k * PASSO;
        if (v > 0.55 && v >= ult && k % 3 === 0) lado = -lado;
        tl.to('#ps-corpo', {{ y: -9 * v, scaleY: 1 + 0.02 * v, rotation: lado * 1.1 * v, duration: PASSO - 0.002, ease: 'sine.inOut' }}, t);
        ult = v;
      }});
      tl.to('#ps-corpo', {{ y: 0, scaleY: 1, rotation: 0, duration: descanso, ease: 'power2.out' }}, ini + e.length * PASSO);
    }}"""
        return f"""<template>
  <style>
      #root {{ position: absolute; inset: 0; overflow: hidden; pointer-events: none; }}
  </style>
  <div id="root" data-composition-id="personagem" data-width="1080" data-height="1920" data-layout-allow-overflow data-layout-allow-occlusion>
    <div id="ps-pos" style="position:absolute;left:0;top:0;width:1px;height:1px" data-layout-allow-overflow>
      <div id="ps-resp" style="position:absolute;left:0;top:0;width:1px;height:1px">
      <div id="ps-corpo" style="position:absolute;left:0;top:0;width:1px;height:1px">
        <div id="ps-troca" style="position:absolute;left:0;top:0;width:1px;height:1px">
{chr(10).join(imgs)}
        </div>
      </div>
      </div>
    </div>
  </div>
  <script>
    const tl = gsap.timeline({{ paused: true }});
{js}
    window.__timelines["personagem"] = tl;
  </script>
</template>
"""

    # ---------- as legendas ----------
    grupos = []
    for fid, texto in cfg['falas']:
        v = V[fid]
        partes = [p.strip() for p in texto.split('/')]
        tam = [len(p.replace('*', '')) for p in partes]
        a = v['ini'] + v['f0']
        for p, n in zip(partes, tam):
            b = a + (v['f1'] - v['f0']) * n / sum(tam)
            grupos.append([a - 0.05, b, p]); a = b
    for k, g in enumerate(grupos):
        prox = grupos[k + 1][0] if k + 1 < len(grupos) else DUR
        g[1] = min(prox - 0.02, max(g[1] + 0.25, g[0] + 0.6))

    def legendas():
        corpo, js = [], []
        for k, (a, b, texto) in enumerate(grupos):
            gid = f'lg{k}'
            corpo.append(f'    <div id="{gid}" class="grupo" style="opacity:0;visibility:hidden"><span class="placa-leg">{marcar(texto)}</span></div>')
            js.append(f"    tl.set('#{gid}', {{ visibility: 'visible' }}, {a:.3f});")
            js.append(f"    tl.fromTo('#{gid}', {{ opacity: 0, filter: 'blur(6px)' }}, {{ opacity: 1, filter: 'blur(0px)', duration: 0.13, ease: 'power4.out' }}, {a:.3f});")
            js.append(f"    tl.to('#{gid}', {{ opacity: 0, duration: 0.12, ease: 'power2.in' }}, {b - 0.12:.3f});")
            js.append(f"    tl.set('#{gid}', {{ opacity: 0, visibility: 'hidden' }}, {b:.3f});")
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

    # ---------- escreve tudo ----------
    os.makedirs(os.path.join(raiz, 'compositions'), exist_ok=True)
    for f in os.listdir(os.path.join(raiz, 'compositions')):
        os.remove(os.path.join(raiz, 'compositions', f))
    hosts = []
    for k, c in enumerate(cenas):
        html, ini, dur = cena_html(k, c)
        open(os.path.join(raiz, f'compositions/{c["id"]}.html'), 'w').write(html)
        hosts.append(f'      <div id="{c["id"]}" data-composition-id="{c["id"]}" data-composition-src="compositions/{c["id"]}.html" data-start="{ini}" data-duration="{dur}" '
                     f'data-track-index="{1 + k % 2}" data-track-kind="graphics" data-width="1080" data-height="1920" style="z-index:{k + 1}"></div>')
    open(os.path.join(raiz, 'compositions/personagem.html'), 'w').write(personagem())
    open(os.path.join(raiz, 'compositions/legendas.html'), 'w').write(legendas())

    audios = [(f'a-{f}', f'assets/vo/{f}.wav', V[f]['ini'], V[f]['dur'], 1.0, 1.0, 20) for f, _ in cfg['falas']]
    sfx += [(n, T(a), v) for n, a, v in cfg.get('sfx', [])]
    VEL = {'whoosh': (1.0, 1.18, 0.88, 1.08), 'pop': (1.0, 1.14, 0.9, 1.07), 'click': (1.0, 1.1), 'key-press': (1.0, 1.15, 0.9)}
    cont = {}
    for k, (nome, t, vol) in enumerate(sorted(sfx, key=lambda s: s[1])):
        if t < 0.02: t = 0.02
        arq = f'assets/sfx/{nome}.mp3'
        d = float(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', os.path.join(raiz, arq)]).decode().strip())
        vs = VEL.get(nome, (1.0,)); vel = vs[cont.get(nome, 0) % len(vs)]; cont[nome] = cont.get(nome, 0) + 1
        if nome == 'riser':
            audios.append((f'sfx{k}-riser', arq, t, 1.3, vol, 1.0, 30 + k % 4, 8.6)); continue
        if t + d / vel > DUR: continue
        audios.append((f'sfx{k}-{nome}', arq, t, d / vel, vol, vel, 30 + k % 4))
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
    <title>{esc(cfg['titulo'])}</title>
    <script src="assets/vendor/gsap.min.js"></script>
    <style>
      * {{ margin: 0; padding: 0; box-sizing: border-box; }}
      html, body {{ margin: 0; width: 1080px; height: 1920px; overflow: hidden; background: #1a0a0d; }}
      #root {{ position: relative; width: 1080px; height: 1920px; overflow: hidden; }}
    </style>
  </head>
  <body>
    <div id="root" data-composition-id="main" data-start="0" data-duration="{DUR}" data-width="1080" data-height="1920">
{chr(10).join(hosts)}
      <div id="personagem" data-composition-id="personagem" data-composition-src="compositions/personagem.html" data-start="0" data-duration="{DUR}" data-track-index="3" data-track-kind="graphics" data-width="1080" data-height="1920" style="z-index:50"></div>
      <div id="legendas" data-composition-id="legendas" data-composition-src="compositions/legendas.html" data-start="0" data-duration="{DUR}" data-track-index="4" data-track-kind="captions" data-width="1080" data-height="1920" style="z-index:60"></div>
{chr(10).join(aud)}
    </div>
    <script>
      window.__timelines["main"] = gsap.timeline({{ paused: true }});
    </script>
  </body>
</html>
"""
    open(os.path.join(raiz, 'index.html'), 'w').write(index)
    json.dump(dict(dur=DUR, falas={f: [V[f]['ini'], round(V[f]['dur'], 2)] for f, _ in cfg['falas']}, cenas=[[c['id'], ini_c[k]] for k, c in enumerate(cenas)]),
              open(os.path.join(raiz, 'tempos.json'), 'w'), indent=1)
    print(f'ok: {DUR} s, {len(cenas)} cenas, {len(grupos)} legendas, {len(audios)} áudios')
    print('  falas:', ' '.join(f'{f}@{V[f]["ini"]:.2f}' for f, _ in cfg['falas']))
    print('  cenas:', ' '.join(f'{c["id"]}@{ini_c[k]:.2f}' for k, c in enumerate(cenas)))
    return DUR


# ---------- o final de sempre: "jessecoelho.com.br · link na bio" ----------
def final_cta(marca=True, nome='Fazendinha Secreta', top=None):
    def extra(L, dur):
        m = f"""    <div id="fim-marca" style="position:absolute;left:0;top:230px;width:1080px;text-align:center;z-index:3">
      <div id="fim-girassol" style="margin:0 auto;width:260px;height:300px;background:url(assets/img/girassol.png) center/contain no-repeat;image-rendering:pixelated"></div>
      <div id="fim-nome" class="pixel" style="font-size:118px;color:#fde6c9;-webkit-text-stroke:10px #3f2631;paint-order:stroke fill;margin-top:10px">{nome}</div>
    </div>""" if marca else ''
        h = f"""{m}
    <div id="fim-cta" class="placa" style="left:90px;top:{top if top is not None else (760 if marca else 380)}px;width:900px;z-index:40;text-align:center;opacity:0">
      <div class="pixel" style="font-size:104px">jessecoelho.com.br</div>
      <div style="font: 900 46px 'Nunito', sans-serif; margin-top:6px" class="acento">link na bio</div>
    </div>"""
        j = ("""    tl.fromTo('#fim-girassol', { y: -500, scale: 0.6 }, { y: 0, scale: 1, duration: 0.5, ease: 'back.out(1.8)' }, 0.15);
    tl.fromTo('#fim-nome', { opacity: 0, filter: 'blur(8px)' }, { opacity: 1, filter: 'blur(0px)', duration: 0.18, ease: 'power4.out' }, 0.42);
""" if marca else '') + """    tl.fromTo('#fim-cta', { opacity: 0, scale: 0.6 }, { opacity: 1, scale: 1, duration: 0.35, ease: 'back.out(1.6)' }, 0.5);
    tl.to('#fim-cta', { scale: 1.03, duration: 0.5, ease: 'sine.inOut', yoyo: true, repeat: %d }, 0.9);""" % max(1, int((dur - 1.0) / 0.5) | 1)
        return h, j
    return extra
