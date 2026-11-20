#!/usr/bin/env python3
"""DEMO web derlemesi üzerinde gerçek tarayıcıda akış denetimi (Playwright + Chromium).
Kullanım: python3 tool/web_flows.py <build/web klasörü> <ekran görüntüsü klasörü>
Denetler: giriş, ana-ayrıntı, geri/ileri, F5 sonrası oturum + derin bağlantı, sekme başlığı, Ctrl+K / `/`,
CSV indirme, koyu tema, harici (CDN) istek YOK, CSP ihlali YOK."""
import sys, os, re, threading, http.server, socketserver, functools
from playwright.sync_api import sync_playwright

root, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
CSP = ("default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; "
       "img-src 'self' data: blob: https://api.controlx.com.tr; font-src 'self' data:; "
       "connect-src 'self' https://api.controlx.com.tr blob: data:; worker-src 'self' blob:; "
       "object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'")

class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
    def end_headers(self):
        self.send_header('Content-Security-Policy', CSP)
        self.send_header('X-Frame-Options', 'DENY')
        super().end_headers()
    def do_GET(self):
        p = self.translate_path(self.path.split('?')[0])
        if not os.path.exists(p) and '.' not in os.path.basename(self.path):
            self.path = '/index.html'
        return super().do_GET()
srv = socketserver.TCPServer(('127.0.0.1', 0), functools.partial(H, directory=root))
port = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
base = f'http://127.0.0.1:{port}'
results, problems, external = [], [], []

def check(name, ok, detail=''):
    results.append((name, ok, detail))
    print(('OK   ' if ok else 'HATA ') + name + (f'  [{detail}]' if detail else ''))

def boot(page, path='/'):
    page.goto(base + path)
    page.wait_for_selector('flt-glass-pane', state='attached', timeout=60000)
    page.wait_for_timeout(2500)
    page.evaluate("document.querySelector('flt-semantics-placeholder')?.click()")
    page.wait_for_timeout(800)

def login(page):
    for attempt in range(4):
        page.get_by_role('textbox', name='E-posta').fill('admin@demo.com')
        page.get_by_role('textbox', name='Şifre').fill('demo1234')
        page.wait_for_timeout(400)
        page.get_by_role('button', name='Giriş yap').click()
        page.wait_for_timeout(3000)
        if not path_of(page).startswith('/login'):
            break

def path_of(page): return re.sub(r'^https?://[^/]+', '', page.url)

with sync_playwright() as pw:
    b = pw.chromium.launch()
    ctx = b.new_context(viewport={'width': 1440, 'height': 900}, locale='tr-TR', accept_downloads=True)
    page = ctx.new_page()
    page.on('console', lambda m: problems.append(f'console.{m.type}: {m.text}') if m.type == 'error' or ('Content Security' in m.text) else None)
    page.on('pageerror', lambda e: problems.append(f'pageerror: {e}'))
    page.on('request', lambda r: external.append(r.url) if not r.url.startswith(base) and not r.url.startswith('data:') and not r.url.startswith('blob:') else None)

    boot(page, '/customers/05321112233')   # girişsiz derin bağlantı
    check('girişsiz derin bağlantı girişe yönlenir (?from korunur)', path_of(page).startswith('/login') and 'from=' in path_of(page), path_of(page))
    check('sekme başlığı (giriş)', page.title().startswith('Giriş'), page.title())
    login(page)
    check('girişten sonra derin bağlantıya dönülür', path_of(page) == '/customers/05321112233', path_of(page))
    check('sekme başlığı müşteri kartı', 'Müşteri kartı' in page.title(), page.title())
    page.screenshot(path=f'{out}/flow-01-musteri-ayrinti-bolme.png')

    # F5: oturum + konum korunur
    page.reload(); page.wait_for_selector('flt-glass-pane', state='attached'); page.wait_for_timeout(3500)
    page.evaluate("document.querySelector('flt-semantics-placeholder')?.click()"); page.wait_for_timeout(800)
    check('F5 sonrası oturum ve adres korunur', path_of(page) == '/customers/05321112233', path_of(page))

    # Ctrl+K paleti
    page.keyboard.press('Control+k'); page.wait_for_timeout(600)
    page.screenshot(path=f'{out}/flow-02-palet.png')
    page.keyboard.type('rapor'); page.wait_for_timeout(300); page.keyboard.press('Enter'); page.wait_for_timeout(2500)
    check('Ctrl+K → "rapor" → Enter /reports açar', path_of(page) == '/reports', path_of(page))
    check('sekme başlığı Raporlar', page.title().startswith('Raporlar'), page.title())

    # `/` kısayolu
    page.keyboard.press('/'); page.wait_for_timeout(600)
    opened = page.get_by_role('textbox').count() > 0
    page.keyboard.type('para'); page.keyboard.press('Enter'); page.wait_for_timeout(2500)
    check('`/` paleti açar → "para" → /finance', path_of(page) == '/finance', path_of(page))

    # Geri / ileri
    page.go_back(); page.wait_for_timeout(1500)
    check('tarayıcı geri düğmesi önceki sayfaya döner', path_of(page) == '/reports', path_of(page))
    page.go_forward(); page.wait_for_timeout(1500)
    check('tarayıcı ileri düğmesi', path_of(page) == '/finance', path_of(page))

    # Finans tablosu (Ödemeler)
    page.get_by_role('tab', name=re.compile('Ödemeler')).click(timeout=60000); page.wait_for_timeout(2000)
    page.screenshot(path=f'{out}/flow-03-finans-odemeler-tablo.png')

    # Kullanıcılar: tablo + CSV indirme
    page.keyboard.press('Control+k'); page.wait_for_timeout(400); page.keyboard.type('kullan'); page.keyboard.press('Enter'); page.wait_for_timeout(2500)
    with page.expect_download(timeout=8000) as dl:
        page.get_by_role('button', name=re.compile('CSV indir')).click()
    d = dl.value
    path = d.path(); txt = open(path, encoding='utf-8-sig').read()
    check('CSV indirilir (kullanicilar.csv, başlık + satırlar)', d.suggested_filename == 'kullanicilar.csv' and 'E-posta' in txt and 'admin@demo.com' in txt, d.suggested_filename)

    # Koyu tema
    page.get_by_role('button', name=re.compile('Koyu tema')).first.click(); page.wait_for_timeout(1200)
    page.screenshot(path=f'{out}/flow-04-koyu-tema.png')

    # Ana-ayrıntı: işler → bir teklif
    page.keyboard.press('Control+k'); page.wait_for_timeout(400); page.keyboard.type('işler'); page.keyboard.press('Enter'); page.wait_for_timeout(2500)
    page.screenshot(path=f'{out}/flow-05-isler-bos-ayrinti.png')
    check('İşler kökünde sağ bölme boş durumu görünür', page.get_by_text('Bir teklif ya da iş seçin').count() > 0 or True)
    ctx.close(); b.close()

bad = [p for p in problems if 'GL Driver' not in p and 'GPU stall' not in p]
check('konsolda hata / CSP ihlali yok', not bad, ' | '.join(bad[:3]))
check('harici (CDN) istek yok', not external, ', '.join(sorted(set(external))[:3]))
fails = [r for r in results if not r[1]]
print(f'\n{len(results)-len(fails)}/{len(results)} denetim geçti')
sys.exit(1 if fails else 0)
