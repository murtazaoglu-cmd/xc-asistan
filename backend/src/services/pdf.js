const PDFDocument = require("pdfkit");
const fs = require("fs");
const path = require("path");

const BRAND = {
  graphite: "#1C1F24",
  steel: "#5C6B7A",
  bronze: "#C97A2E",
  line: "#E5E1D8",
};

// Kullanıcı kaynaklı metinler PDF'e girmeden önce kırpılır/temizlenir: pdfkit boşluksuz çok uzun metinde yavaşlar (DoS) ve
// kontrol karakterleri çıktıyı bozar. (Eski, doğrulanmamış kayıtlar için de koruma sağlar.)
function clip(v, max) {
  return String(v ?? "").replace(/[\u0000-\u001f\u007f]+/g, " ").slice(0, max);
}

function money(n) {
  return Number(n).toLocaleString("tr-TR", { minimumFractionDigits: 0, maximumFractionDigits: 2 }) + " ₺";
}

// Standart PDF yazı tipleri (Helvetica) ş, ğ, İ, ı, ₺ gibi Türkçe karakterleri gösteremez;
// bu yüzden Türkçe destekli DejaVu Sans gömülür. Dosya yoksa Helvetica'ya düşülür.
const FONT_DIR = path.join(__dirname, "../assets/fonts");
const REG = path.join(FONT_DIR, "DejaVuSans.ttf");
const BOLD = path.join(FONT_DIR, "DejaVuSans-Bold.ttf");
const HAS_FONTS = fs.existsSync(REG) && fs.existsSync(BOLD);

/**
 * Bir teklif için PDF üretir ve dosya yolunu döner.
 * @param {object} offer - {code, name, phone, email, region, tracking_code}
 * @param {object} quote - {items, subtotal, tax, total, created_at}
 * @param {string} outputDir - PDF'in kaydedileceği klasör
 * @returns {Promise<string>} oluşturulan dosyanın tam yolu
 */
function generateQuotePDF(offer, quote, outputDir) {
  return new Promise((resolve, reject) => {
    const fileName = `teklif-${offer.code}-${Date.now()}.pdf`;
    const filePath = path.join(outputDir, fileName);
    const doc = new PDFDocument({ size: "A4", margin: 50 });
    const stream = fs.createWriteStream(filePath);
    doc.pipe(stream);
    if (HAS_FONTS) { doc.registerFont("Body", REG); doc.registerFont("Body-Bold", BOLD); }
    else { doc.registerFont("Body", "Helvetica"); doc.registerFont("Body-Bold", "Helvetica-Bold"); }

    // Üst bilgi
    doc.fontSize(20).fillColor(BRAND.graphite).font("Body-Bold")
      .text("X CONTROL YAPI", 50, 50);
    doc.fontSize(9).fillColor(BRAND.steel).font("Body")
      .text("Bitez, Palamut Cd. No:21, 48470 Bodrum/Muğla", 50, 74)
      .text("0530 393 18 40 · info@controlx.com.tr", 50, 87);

    doc.fontSize(10).fillColor(BRAND.steel)
      .text("TEKLİF", 400, 50, { width: 145, align: "right" })
      .fillColor(BRAND.graphite)
      .text(offer.code, 400, 64, { width: 145, align: "right" })
      .fillColor(BRAND.steel)
      .text(new Date(quote.created_at || Date.now()).toLocaleDateString("tr-TR"), 400, 78, { width: 145, align: "right" });

    doc.moveTo(50, 110).lineTo(545, 110).lineWidth(2).strokeColor(BRAND.bronze).stroke();

    // Müşteri bilgisi
    doc.fontSize(9).fillColor(BRAND.steel).text("MÜŞTERİ", 50, 130);
    doc.fontSize(11).fillColor(BRAND.graphite).font("Body-Bold").text(clip(offer.name, 120), 50, 144, { width: 495, lineBreak: false });
    doc.fontSize(9).fillColor(BRAND.steel).font("Body")
      .text(`${clip(offer.phone, 40)}${offer.email && String(offer.email).length <= 254 ? " · " + clip(offer.email, 120) : ""}`, 50, 160, { width: 495, lineBreak: false })
      .text(clip(offer.region, 120), 50, 173, { width: 495, lineBreak: false });

    // Kalem tablosu
    let y = 210;
    doc.rect(50, y, 495, 22).fill("#F5F3EE");
    doc.fillColor(BRAND.graphite).fontSize(9).font("Body-Bold")
      .text("Açıklama", 60, y + 7)
      .text("Adet", 330, y + 7, { width: 50, align: "center" })
      .text("Birim Fiyat", 380, y + 7, { width: 80, align: "right" })
      .text("Tutar", 460, y + 7, { width: 75, align: "right" });
    y += 30;

    doc.font("Body").fontSize(9.5);
    quote.items.forEach((item) => {
      const lineTotal = item.qty * item.price;
      doc.fillColor(BRAND.graphite).text(clip(item.desc, 500), 60, y, { width: 260 });
      doc.fillColor(BRAND.steel)
        .text(String(item.qty), 330, y, { width: 50, align: "center" })
        .text(money(item.price), 380, y, { width: 80, align: "right" })
        .fillColor(BRAND.graphite)
        .text(money(lineTotal), 460, y, { width: 75, align: "right" });
      y += 22;
      doc.moveTo(50, y - 4).lineTo(545, y - 4).lineWidth(0.5).strokeColor(BRAND.line).stroke();
    });

    // Toplamlar
    y += 15;
    const totalsX = 380;
    doc.fontSize(9.5).fillColor(BRAND.steel)
      .text("Ara Toplam", totalsX, y, { width: 80 })
      .text(money(quote.subtotal), 460, y, { width: 75, align: "right" });
    y += 16;
    doc.text("KDV (%20)", totalsX, y, { width: 80 })
      .text(money(quote.tax), 460, y, { width: 75, align: "right" });
    y += 6;
    doc.moveTo(380, y + 14).lineTo(545, y + 14).lineWidth(1.5).strokeColor(BRAND.graphite).stroke();
    y += 20;
    doc.fontSize(13).fillColor(BRAND.graphite).font("Body-Bold")
      .text("Genel Toplam", totalsX, y, { width: 80 })
      .text(money(quote.total), 460, y, { width: 75, align: "right" });

    // Alt bilgi
    doc.fontSize(8).fillColor(BRAND.steel).font("Body")
      .text(
        `Bu teklif belge tarihinden itibaren 15 gün geçerlidir. Takip kodunuz: ${offer.tracking_code}`,
        50, 720, { width: 495 }
      );

    doc.end();
    stream.on("finish", () => resolve(filePath));
    stream.on("error", reject);
  });
}

module.exports = { generateQuotePDF };
