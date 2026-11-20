/**
 * Muhasebeci dışa aktarımı: CSV (Türkiye Excel uyumlu) ve XLSX. Saf fonksiyonlar.
 *
 * CSV: UTF-8 BOM (Excel Türkçe karakterleri doğru açsın), ayırıcı ";" (tr-TR Excel liste ayırıcısı), satır sonu CRLF,
 * ondalık VİRGÜL ("1250,50"), binlik ayırıcı YOK (sayı olarak okunsun), tarih gg.aa.yyyy.
 * Metin hücrelerinde formül enjeksiyonuna karşı: "=", "+", "-", "@", TAB, CR ile başlıyorsa başına "'" eklenir.
 */
const { buildXlsx } = require("./xlsxWriter");

const BOM = "﻿";
const SEP = ";";

function csvText(v) {
  let s = String(v);
  if (/^[=+\-@\t\r]/.test(s)) s = "'" + s;
  return /[";\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}
const csvMoney = (kurus) => (kurus === null || kurus === undefined ? "" : `${kurus < 0 ? "-" : ""}${Math.floor(Math.abs(kurus) / 100)},${String(Math.abs(kurus) % 100).padStart(2, "0")}`);
const csvDate = (iso) => { const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || "")); return m ? `${m[3]}.${m[2]}.${m[1]}` : ""; };

/**
 * columns: [{header, type:'text'|'money'|'date'|'int'|'percent', width?}]; rows: değer dizileri.
 * money hücreleri KURUŞ tamsayısıdır (CSV'de "12,50", XLSX'te 12.5 sayısı). percent: ondalıklı yüzde sayısı (20, 10.5).
 */
function toCsv(columns, rows) {
  const lines = [columns.map((c) => csvText(c.header)).join(SEP)];
  for (const row of rows) {
    lines.push(columns.map((c, i) => {
      const v = row[i];
      if (v === null || v === undefined || v === "") return "";
      switch (c.type) {
        case "money": return csvMoney(v);
        case "date": return csvDate(v);
        case "percent": return String(v).replace(".", ",");
        case "int": return String(v);
        default: return csvText(v);
      }
    }).join(SEP));
  }
  return BOM + lines.join("\r\n") + "\r\n";
}

/** sheets: [{name, columns, rows}] — money kuruştan TL'ye (sayı) çevrilir */
function toXlsx(sheets) {
  return buildXlsx(sheets.map((s) => ({
    name: s.name, columns: s.columns,
    rows: s.rows.map((r) => r.map((v, i) => (s.columns[i].type === "money" && Number.isFinite(v) ? v / 100 : v))),
  })));
}

module.exports = { toCsv, toXlsx, csvMoney, csvDate, BOM, SEP };
