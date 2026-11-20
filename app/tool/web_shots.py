#!/usr/bin/env python3
"""DEMO web derlemesinin ekran görüntülerini alır (Playwright + Chromium).
Kullanım: python3 tool/web_shots.py <build/web klasörü> <çıktı klasörü> [genişlik,yükseklik ...]
Konsol hataları ve sayfa hataları `console.log` dosyasına yazılır."""
import sys, os, re, threading, http.server, socketserver, functools, time
from playwright.sync_api import sync_playwright

root, out = sys.argv[1], sys.argv[2]
sizes = [tuple(map(int, s.split('x'))) for s in sys.argv[3:]] or [(1440, 900), (390, 844)]
os.makedirs(out, exist_ok=True)

class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        p = self.translate_path(self.path.split('?')[0])
        if not os.path.exists(p) and '.' not in os.path.basename(self.path):
            self.path = '/index.html'          # SPA geri dönüşü
        return super().do_GET()
handler = functools.partial(H, directory=root)
srv = socketserver.TCPServer(('127.0.0.1', 0), handler)
port = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
base = f'http://127.0.0.1:{port}'

PAGES = [('today', 'Bugün'), ('jobs', 'İşler'), ('customers', 'Müşteriler'), ('finance', 'Para'),
         ('reports', 'Raporlar'), ('assistant', 'Asistan'), ('users', 'Kullanıcılar')]
errors = []

def settle(page, ms=1200): page.wait_for_timeout(ms)

with sync_playwright() as pw:
    b = pw.chromium.launch()
    for (w, h) in sizes:
        ctx = b.new_context(viewport={'width': w, 'height': h}, locale='tr-TR', device_scale_factor=1)
        page = ctx.new_page()
        page.on('console', lambda m, s=(w, h): errors.append(f'{s} console.{m.type}: {m.text}') if m.type == 'error' else None)
        page.on('pageerror', lambda e, s=(w, h): errors.append(f'{s} pageerror: {e}'))
        page.goto(base + '/')
        page.wait_for_selector('flt-glass-pane', state='attached', timeout=60000)
        settle(page, 2500)
        page.evaluate("document.querySelector('flt-semantics-placeholder')?.click()")
        settle(page, 800)
        tag = f'{w}x{h}'
        page.screenshot(path=f'{out}/{tag}-00-giris.png')
        for attempt in range(4):           # Flutter anlamsal ağacı geç oturabilir: doğrulayıp yeniden dener
            page.get_by_role('textbox', name='E-posta').fill('admin@demo.com')
            page.get_by_role('textbox', name='Şifre').fill('demo1234')
            settle(page, 400)
            page.get_by_role('button', name='Giriş yap').click()
            settle(page, 3000)
            if page.get_by_role('button', name='Bugün', exact=True).count() > 0:
                break
        for i, (slug, label) in enumerate(PAGES, 1):
            try:
                if w >= 900:
                    page.get_by_role('button', name=label, exact=True).first.click()
                else:
                    btn = page.get_by_role('button', name=label, exact=True)
                    if btn.count() == 0 or not btn.first.is_visible():
                        page.get_by_role('button', name='Menü').click(); settle(page, 500)
                        page.get_by_role('button', name=label, exact=True).first.click()
                    else:
                        btn.first.click()
                settle(page, 2000)
            except Exception as e:
                errors.append(f'{tag} {slug}: gezinme hatası {e}')
            page.screenshot(path=f'{out}/{tag}-{i:02d}-{slug}.png')
        # Ek görünümler: müşteri ayrıntısı (geniş: ana-ayrıntı), para → ödemeler tablosu, faturalar
        extra = [('musteri-ayrinti', 'Müşteriler', lambda: page.get_by_role('button', name=re.compile('Ayşe Yılmaz')).first.click()),
                 ('para-odemeler', 'Para', lambda: page.get_by_role('tab', name=re.compile('Ödemeler')).click()),
                 ('faturalar', None, None)]
        for j, (slug, nav, act) in enumerate(extra, len(PAGES) + 1):
            try:
                if slug == 'faturalar':
                    if w >= 900:
                        page.get_by_role('button', name='Fatura / KDV', exact=True).first.click()
                    else:
                        page.get_by_role('button', name='Menü').click(); settle(page, 500)
                        page.get_by_role('button', name='Fatura / KDV', exact=True).first.click()
                else:
                    btn = page.get_by_role('button', name=nav, exact=True).first
                    btn.click(); settle(page, 1500)
                    act()
                settle(page, 2200)
            except Exception as e:
                errors.append(f'{tag} {slug}: gezinme hatası {str(e)[:120]}')
            page.screenshot(path=f'{out}/{tag}-{j:02d}-{slug}.png')
        ctx.close()
    b.close()
open(os.path.join(out, 'console.log'), 'w').write('\n'.join(errors) + '\n')
print('konsol/sayfa hataları:', len(errors))
for e in errors[:30]: print(' ', e)
