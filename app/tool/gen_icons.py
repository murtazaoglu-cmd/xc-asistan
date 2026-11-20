#!/usr/bin/env python3
"""XC Asistan uygulama simgesi: tasarımdaki mavi çarpı "X" (yer tutucu vektör; BrandLogo ile aynı geometri).
Android (adaptif + yuvarlak + tek renkli), iOS (alfasız) ve web simgelerini üretir.
Kullanım: python3 tool/gen_icons.py   (Pillow gerekir)"""
import json, os
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
BG = (245, 247, 251)        # #F5F7FB
BLUE = (59, 130, 246)       # #3B82F6 ana
BLUE_LIGHT = (96, 165, 250) # #60A5FA açık ana
SS = 4                      # aşırı örnekleme (pürüzsüz kenar)

def x_mark(size, span, c1=BLUE, c2=BLUE_LIGHT):
    """size x size saydam tuval; X işareti ortada, `span` tuvalin oranı."""
    big = size * SS
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = big * span                     # X'in kapladığı kare
    o = (big - w) / 2
    sw = w * 0.30                      # çubuk kalınlığı (yuvarlak uçlu)
    m = sw / 2
    def bar(p, q, col):
        d.line([p, q], fill=col, width=int(sw))
        for (x, y) in (p, q):
            d.ellipse([x - m, y - m, x + m, y + m], fill=col)
    a, b = o + m, o + w - m
    bar((b, a), (a, b), c2 + (255,))   # arkadaki çubuk (açık ton)
    bar((a, a), (b, b), c1 + (255,))   # öndeki çubuk (ana ton)
    return img.resize((size, size), Image.LANCZOS)

def with_bg(size, span, shape='square', bg=BG):
    base = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    m = Image.new('L', (size * SS, size * SS), 0)
    md = ImageDraw.Draw(m)
    full = size * SS - 1
    if shape == 'round':
        md.ellipse([0, 0, full, full], fill=255)
    elif shape == 'square':
        md.rounded_rectangle([0, 0, full, full], radius=int(size * SS * 0.22), fill=255)
    else:
        md.rectangle([0, 0, full, full], fill=255)
    m = m.resize((size, size), Image.LANCZOS)
    base.paste(Image.new('RGBA', (size, size), bg + (255,)), (0, 0), m)
    base.alpha_composite(x_mark(size, span))
    return base

res = os.path.join(ROOT, 'android/app/src/main/res')
densities = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
for name, px in densities.items():
    d = os.path.join(res, f'mipmap-{name}')
    os.makedirs(d, exist_ok=True)
    with_bg(px, 0.56).save(os.path.join(d, 'ic_launcher.png'))
    with_bg(px, 0.52, 'round').save(os.path.join(d, 'ic_launcher_round.png'))
    fpx = int(px * 108 / 48)   # adaptif: 108dp tuval, güvenli alan ortadaki %61
    x_mark(fpx, 0.40).save(os.path.join(d, 'ic_launcher_foreground.png'))
    mono = x_mark(fpx, 0.40, (0, 0, 0), (0, 0, 0))
    mono.save(os.path.join(d, 'ic_launcher_monochrome.png'))

anydpi = os.path.join(res, 'mipmap-anydpi-v26')
os.makedirs(anydpi, exist_ok=True)
adaptive = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
'''
for n in ('ic_launcher.xml', 'ic_launcher_round.xml'):
    open(os.path.join(anydpi, n), 'w').write(adaptive)
open(os.path.join(res, 'values/ic_launcher_background.xml'), 'w').write(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#F5F7FB</color>\n</resources>\n')

# iOS (alfa kanalı OLMAMALI)
ios = os.path.join(ROOT, 'ios/Runner/Assets.xcassets/AppIcon.appiconset')
contents = json.load(open(os.path.join(ios, 'Contents.json')))
for im in contents['images']:
    size = float(im['size'].split('x')[0]) * int(im['scale'].rstrip('x'))
    px = int(round(size))
    with_bg(px, 0.56, 'full').convert('RGB').save(os.path.join(ios, im['filename']))

# Web
web = os.path.join(ROOT, 'web')
if os.path.isdir(web):
    os.makedirs(os.path.join(web, 'icons'), exist_ok=True)
    for px in (192, 512):
        with_bg(px, 0.56).save(os.path.join(web, 'icons', f'Icon-{px}.png'))
        with_bg(px, 0.46, 'full').save(os.path.join(web, 'icons', f'Icon-maskable-{px}.png'))
    with_bg(32, 0.62).save(os.path.join(web, 'favicon.png'))
print('simgeler uretildi')
