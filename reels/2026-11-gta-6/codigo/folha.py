import sys, glob, os, re
from PIL import Image
proj = sys.argv[1]; por = int(sys.argv[2]) if len(sys.argv) > 2 else 10
d = max(glob.glob(proj + '/.hyperframes/artifacts/snapshots/*/'), key=os.path.getmtime)
fs = sorted(glob.glob(d + 'frame-*.png'), key=lambda f: int(re.search(r'frame-(\d+)', f).group(1)))
ims = [Image.open(f).convert('RGB').resize((216, 384)) for f in fs]
lin = (len(ims) + por - 1) // por
s = Image.new('RGB', (216 * por, 384 * lin), (20, 20, 20))
for i, im in enumerate(ims): s.paste(im, ((i % por) * 216, (i // por) * 384))
s.save(proj + '/folha.jpg', quality=86); print(len(ims), 'quadros →', proj + '/folha.jpg')
