// Sekme başlığı: rotaya göre "Sayfa · Uygulama adı". Web'de tarayıcı sekmesi/geçmiş listesi ve
// ekran okuyucu için anlamlı başlık; mobilde görev değiştirici etiketi olur (zararsız).
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../config/brand_profile.dart';

/// Yola göre sayfa adı (saf; testlenir). Bilinmeyen yol: null.
String? pageNameFor(String path, Glossary g) {
  final segs = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return null;
  final root = segs.first;
  final rest = segs.skip(1).toList();
  final isNew = rest.isNotEmpty && rest.first == 'new';
  final isEdit = rest.isNotEmpty && rest.last == 'edit';
  switch (root) {
    case 'login':
      return 'Giriş';
    case 'splash':
      return null;
    case 'update-required':
      return 'Güncelleme gerekli';
    case 'today':
      return 'Bugün';
    case 'jobs':
      if (rest.isEmpty) return g.jobs;
      if (isNew)
        return rest.length > 1
            ? 'Yeni ${g.job.toLowerCase()}'
            : 'Yeni ${g.offer.toLowerCase()}';
      if (rest.first == 'offers')
        return rest.contains('quote')
            ? 'Teklif düzenleyici'
            : (isEdit ? '${g.offer} düzenle' : g.offer);
      if (rest.first == 'projects')
        return isEdit ? '${g.job} düzenle' : '${g.job} ayrıntısı';
      return g.jobs;
    case 'assistant':
      if (rest.isEmpty) return 'Asistan';
      return switch (rest.first) {
        'briefing' => 'Günün brifingi',
        'insights' => 'İçgörüler',
        'closure' => 'Gün sonu',
        'inbox' => 'Gelen kutusu',
        'prefs' => 'Bildirim tercihleri',
        'consents' => 'İzinler',
        'suggestions' => 'Öneriler',
        'share' => 'Paylaşılan içerik',
        _ => 'Asistan',
      };
    case 'customers':
      if (rest.isEmpty) return g.customers;
      if (isNew) return 'Yeni ${g.customer.toLowerCase()}';
      return isEdit ? '${g.customer} düzenle' : '${g.customer} kartı';
    case 'finance':
      if (rest.isEmpty) return g.money;
      if (rest.first == 'receivables') return 'Alacaklar';
      return isNew ? 'Yeni kayıt · ${g.money}' : '${g.money} kaydı';
    case 'appointments':
      if (rest.isEmpty) return g.appointments;
      if (isNew) return 'Yeni ${g.appointment.toLowerCase()}';
      return isEdit ? '${g.appointment} düzenle' : '${g.appointment} ayrıntısı';
    case 'stock':
      return rest.isEmpty ? g.stock : (isNew ? 'Yeni kalem' : 'Stok kalemi');
    case 'reports':
      return 'Raporlar';
    case 'invoices-vat':
      if (rest.isEmpty) return 'Fatura / KDV';
      return isNew
          ? 'Yeni fatura'
          : (rest.first == 'plan' ? 'Ödeme planı' : 'Fatura');
    case 'settings':
      return rest.isNotEmpty && rest.first == 'password'
          ? 'Şifre değiştir'
          : 'Ayarlar';
    case 'users':
      return isNew ? 'Yeni kullanıcı' : 'Kullanıcılar';
    case 'more':
      return 'Daha fazla';
  }
  return null;
}

String documentTitleFor(String path, Glossary g, String appName) {
  final name = pageNameFor(path, g);
  return name == null ? appName : '$name · $appName';
}

/// Yönlendirici konumunu dinleyip sekme başlığını günceller.
class PageTitleSync extends StatefulWidget {
  const PageTitleSync({
    super.key,
    required this.router,
    required this.glossary,
    required this.appName,
    required this.child,
  });
  final GoRouter router;
  final Glossary glossary;
  final String appName;
  final Widget child;

  @override
  State<PageTitleSync> createState() => _PageTitleSyncState();
}

class _PageTitleSyncState extends State<PageTitleSync> {
  String? _last;

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_update);
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void didUpdateWidget(covariant PageTitleSync old) {
    super.didUpdateWidget(old);
    if (old.router != widget.router) {
      old.router.routerDelegate.removeListener(_update);
      widget.router.routerDelegate.addListener(_update);
    }
    _last = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (!mounted) return;
    final path = widget.router.routerDelegate.currentConfiguration.uri.path;
    final title = documentTitleFor(path, widget.glossary, widget.appName);
    if (title == _last) return;
    _last = title;
    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(
        label: title,
        primaryColor: Theme.of(context).colorScheme.primary.toARGB32(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
