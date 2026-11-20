/** Aydınlatma / rıza onay metni (KVKK). Sürüm değişirse istemci yeniden onay almak zorundadır. */
const VERSION = "2026-11-v1";
const NOTICE = {
  version: VERSION,
  title: "Müşteri yazışmasının içe aktarılması — bilgilendirme ve onay",
  text: [
    "Bu işlem, müşterinizle yaptığınız WhatsApp yazışmasından notlar, hatırlatma ve randevu önerileri çıkarmak içindir.",
    "Yazışma yalnızca bu uygulamanın kendi sunucusunda işlenir; yapay zekâ dahil hiçbir üçüncü taraf servise gönderilmez, dışarıya aktarılmaz.",
    "Kişisel veri sorumlusu işletmenizdir. Yazışmadaki kişilerin KVKK m.10 kapsamında aydınlatıldığından (aydınlatma metni / işletme politikası) emin olmanız sizin sorumluluğunuzdadır.",
    "Yalnızca işle ilgili (teklif, randevu, ödeme, ölçü, adres) bilgiler öneri olarak çıkarılır; önerileri siz onaylarsınız, hiçbiri kendiliğinden uygulanmaz.",
    "Grup sohbetleri varsayılan olarak içe aktarılmaz. Ham mesaj metni varsayılan olarak belirli bir süre sonra silinir (kabul ettiğiniz notlar kalır); yazışmayı ve notları istediğiniz an silebilirsiniz.",
    "Onay kaydınız (kim, ne zaman, hangi metin sürümü) ispat amacıyla saklanır.",
  ],
  checkbox: "Yazışmadaki kişilerin aydınlatıldığını ve bu verilerin yukarıdaki koşullarla işlenmesini onaylıyorum.",
};
module.exports = { VERSION, NOTICE };
