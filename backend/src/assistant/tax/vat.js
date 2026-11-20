/**
 * KDV hesapları — SAF fonksiyonlar, kuruş tamsayısı, yarım yukarı yuvarlama.
 *
 * KDV ORANLARI BU DOSYADA SABİT DEĞİLDİR: `vat_rates` tablosundan (veri) gelir; fonksiyonlar oranı parametre alır.
 * Oran, yüzde olarak 2 ondalığa kadar kabul edilir (ör. 20, 10, 1, 0, 18.5) ve "baz puan"a (yüzde×100) çevrilip
 * tamsayı aritmetiğiyle uygulanır.
 *
 * quotes.js `computeTotals` ile tutarlılık: %20 için
 *   KDV hariç satır:  kdv = round(matrah × 0,20)       (computeTotals: Math.round(line*0.2))
 *   KDV dahil satır:  matrah = round(tutar × 100/120)  (computeTotals: Math.round(line*100/120)); kdv = tutar − matrah
 * ile birebir aynı sonucu verir (test/api_test_v18.js bunu API üzerinden doğrular).
 *
 * Hukuki/mali yorum içermez: tevkifat oranı kullanıcı/mali müşavir verisidir.
 */
const { MAX_KURUS, isKurus, mulDiv } = require("./money");

/** Yüzde (ör. 20 ya da "10.5") → baz puan tamsayısı (2000, 1050). Geçersizse null. 0 ≤ oran ≤ 100 */
function rateToBp(rate) {
  const n = typeof rate === "string" ? Number(rate.trim().replace(",", ".")) : rate;
  if (typeof n !== "number" || !Number.isFinite(n) || n < 0 || n > 100) return null;
  const bp = Math.round(n * 100);
  if (Math.abs(bp / 100 - n) > 1e-9) return null; // en çok 2 ondalık
  return bp;
}

/** Tevkifat: {pay, payda} ya da "4/10" metni ya da 0..1 arası oran (ör. 0.4 → 4/10) → {pay, payda} | null (=yok) | undefined (=geçersiz) */
function parseWithholding(w) {
  if (w === null || w === undefined || w === "" || w === false) return null;
  let pay, payda;
  if (typeof w === "string") {
    const m = /^\s*(\d{1,3})\s*\/\s*(\d{1,3})\s*$/.exec(w);
    if (!m) return undefined;
    pay = Number(m[1]); payda = Number(m[2]);
  } else if (typeof w === "number") {
    if (!(w > 0 && w <= 1)) return undefined;
    payda = 10; pay = Math.round(w * 10);
    if (Math.abs(pay / payda - w) > 1e-9) { payda = 100; pay = Math.round(w * 100); if (Math.abs(pay / payda - w) > 1e-9) return undefined; }
  } else if (typeof w === "object") {
    pay = Number(w.pay); payda = Number(w.payda);
  } else return undefined;
  if (!Number.isInteger(pay) || !Number.isInteger(payda) || pay < 1 || payda < 1 || pay > payda || payda > 100) return undefined;
  return { pay, payda };
}

/** "4/10" gösterimi */
const withholdingLabel = (w) => (w ? `${w.pay}/${w.payda}` : null);

/**
 * Fatura tutarlarını hesaplar.
 *  mode "haric": amountKurus = matrah (KDV hariç)         → kdv = round(matrah × oran)
 *  mode "dahil": amountKurus = genel toplam (KDV dahil)   → matrah = round(toplam × 10000 / (10000 + oranBp)); kdv = toplam − matrah
 * Tevkifat (kısmi): KDV tam hesaplanır; tevkifat = round(kdv × pay/payda); satıcının tahsil edeceği = toplam − tevkifat.
 * @returns {{matrahKurus, kdvKurus, tutarKurus, tevkifatKurus, odenecekKurus, rateBp}} | {error}
 */
function computeInvoiceAmounts({ mode, amountKurus, rate, withholding }) {
  if (mode !== "haric" && mode !== "dahil") return { error: "mode 'haric' ya da 'dahil' olmalıdır." };
  if (!isKurus(amountKurus)) return { error: "Tutar 0 ile 10 milyar TL arasında kuruş tamsayısı olmalıdır." };
  const rateBp = rateToBp(rate);
  if (rateBp === null) return { error: "KDV oranı 0 ile 100 arasında (en çok 2 ondalık) olmalıdır." };
  const w = parseWithholding(withholding);
  if (w === undefined) return { error: "Geçersiz tevkifat oranı (örn. 4/10)." };
  let matrahKurus, kdvKurus, tutarKurus;
  if (mode === "haric") {
    matrahKurus = amountKurus;
    kdvKurus = mulDiv(matrahKurus, rateBp, 10000);
    tutarKurus = matrahKurus + kdvKurus;
  } else {
    tutarKurus = amountKurus;
    matrahKurus = mulDiv(tutarKurus, 10000, 10000 + rateBp);
    kdvKurus = tutarKurus - matrahKurus;
  }
  if (tutarKurus > MAX_KURUS) return { error: "Tutar çok büyük." };
  const tevkifatKurus = w ? mulDiv(kdvKurus, w.pay, w.payda) : 0;
  return { matrahKurus, kdvKurus, tutarKurus, tevkifatKurus, odenecekKurus: tutarKurus - tevkifatKurus, rateBp };
}

/** Belgedeki değerler esastır (araştırma §1.6): matrah × oran ile beyan edilen KDV arasındaki fark (kuruş). Tolerans varsayılan 5 kuruş (toplam). */
const VAT_TOLERANCE_KURUS = 5;
function checkDeclaredVat({ matrahKurus, kdvKurus, rate }) {
  const rateBp = rateToBp(rate);
  if (rateBp === null) return { ok: false, diff: null };
  const expected = mulDiv(matrahKurus, rateBp, 10000);
  const diff = kdvKurus - expected;
  return { ok: Math.abs(diff) <= VAT_TOLERANCE_KURUS, diff, expected };
}

/**
 * Kalem listesinden toplam (quotes.js computeTotals ile aynı satır-bazlı yuvarlama): her kalem {qty, price(TL), vatIncluded, rate?}.
 * rate verilmezse defaultRate kullanılır. Teklif ↔ fatura karşılaştırmalarında kullanılır.
 */
function sumLines(lines, defaultRate) {
  let net = 0, gross = 0;
  for (const it of lines) {
    const line = Math.round(Number(it.qty) * Number(it.price) * 100);
    const rate = it.rate === undefined ? defaultRate : it.rate;
    const r = computeInvoiceAmounts({ mode: it.vatIncluded ? "dahil" : "haric", amountKurus: line, rate });
    if (r.error) return { error: r.error };
    net += r.matrahKurus; gross += r.tutarKurus;
  }
  return { matrahKurus: net, kdvKurus: gross - net, tutarKurus: gross };
}

/** VKN (10 hane) / TCKN (11 hane) biçim denetimi; sağlama (checksum) ayrıca raporlanır (uyarı düzeyi). */
function validateTaxId(id) {
  if (id === null || id === undefined || id === "") return { ok: true, empty: true };
  const s = String(id).trim();
  if (!/^\d{10}$|^\d{11}$/.test(s)) return { ok: false, reason: "format" };
  const d = [...s].map(Number);
  let checksumOk;
  if (s.length === 11) {
    if (s === "11111111111") checksumOk = true; // e-Arşiv'de nihai tüketici için kullanılan sabit değer (TÜRMOB duyurusu, araştırma §1.6)
    else if (d[0] === 0) checksumOk = false;
    else {
      const odd = d[0] + d[2] + d[4] + d[6] + d[8], even = d[1] + d[3] + d[5] + d[7];
      const d10 = (((odd * 7 - even) % 10) + 10) % 10;
      const d11 = d.slice(0, 10).reduce((a, b) => a + b, 0) % 10;
      checksumOk = d[9] === d10 && d[10] === d11;
    }
  } else {
    let sum = 0;
    for (let i = 0; i < 9; i++) {
      const t = (d[i] + 10 - (i + 1)) % 10;
      const p = (t * 2 ** (10 - (i + 1))) % 9;
      sum += t !== 0 && p === 0 ? 9 : p;
    }
    checksumOk = (10 - (sum % 10)) % 10 === d[9];
  }
  return { ok: true, value: s, kind: s.length === 10 ? "VKN" : "TCKN", checksumOk };
}

module.exports = { rateToBp, parseWithholding, withholdingLabel, computeInvoiceAmounts, checkDeclaredVat, VAT_TOLERANCE_KURUS, sumLines, validateTaxId };
