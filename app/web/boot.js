// Açılış ekranını Flutter ilk kareyi çizince kaldırır. Harici dosya: CSP `script-src 'self'` ile uyumlu.
(function () {
  function remove() {
    var el = document.getElementById('boot');
    if (el && el.parentNode) el.parentNode.removeChild(el);
  }
  window.addEventListener('flutter-first-frame', remove);
  // Yedek: ilk kare olayı kaçarsa 20 sn sonra yine kaldır.
  setTimeout(remove, 20000);
})();
