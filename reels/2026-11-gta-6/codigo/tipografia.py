# fundos só de tipografia (nada de arte da Rockstar): um número grande vazado, no estilo dos anos do site
def numero_grande(texto, sub=''):
    def extra(L, dur):
        h = f"""    <div id="tg-fundo" style="position:absolute;inset:0;background:radial-gradient(circle at 50% 38%, #4a1f2a 0%, #1a0a0d 70%);z-index:0"></div>
    <div id="tg-num" style="position:absolute;left:0;top:560px;width:1080px;text-align:center;font:400 380px/1 'Jersey 10';color:#2c1118;-webkit-text-stroke:6px #fde6c9;opacity:.9;z-index:1">{texto}</div>
    <div id="tg-sub" style="position:absolute;left:0;top:930px;width:1080px;text-align:center;font:900 44px/1.2 'Nunito', sans-serif;color:#fde6c9;letter-spacing:.06em;z-index:1;opacity:0">{sub}</div>"""
        j = f"""    tl.fromTo('#tg-num', {{ scale: 1.12, opacity: 0.4 }}, {{ scale: 1, opacity: 0.9, duration: 0.5, ease: 'expo.out' }}, 0);
    tl.to('#tg-num', {{ scale: 1.06, duration: {round(max(0.6, dur - 0.5), 2)}, ease: 'none' }}, 0.5);
    tl.fromTo('#tg-sub', {{ opacity: 0, y: 20 }}, {{ opacity: 1, y: 0, duration: 0.4, ease: 'power2.out' }}, 0.35);"""
        return h, j
    return extra
