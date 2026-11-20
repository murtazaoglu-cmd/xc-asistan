import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/config/brand_profile.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/finance/data/finance_access.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/features/finance/data/finance_input.dart';
import 'package:xc_asistan/features/finance/data/finance_messages.dart';
import 'package:xc_asistan/features/finance/data/finance_models.dart';

void main() {
  group('Tutar doğrulama', () {
    String? err(String? s) => FinanceValidators.amount(s).error;
    Money? val(String? s) => FinanceValidators.amount(s).value;

    test('geçerli biçimler kuruş doğru çözülür', () {
      expect(val('12.500,50'), Money.fromKurus(1250050));
      expect(val('1250,5'), Money.fromKurus(125050));
      expect(val('12.500'), Money.fromKurus(1250000));
      expect(val('0,01'), Money.fromKurus(1));
      expect(val(' 99 '), Money.fromKurus(9900));
    });

    test('boş, sıfır, negatif, harf ve fazla ondalık engellenir', () {
      expect(err(null), isNotNull);
      expect(err(''), 'Tutarı girin.');
      expect(err('0'), contains('sıfırdan büyük'));
      expect(err('0,00'), contains('sıfırdan büyük'));
      expect(err('-5'), contains('negatif'));
      expect(err('−5'), contains('negatif'));
      expect(err('abc'), contains('Geçerli'));
      expect(err('1,234'), contains('2 ondalık'));
      expect(err('1,2,3'), isNotNull);
      expect(err('99999999999'), contains('çok büyük'));
    });

    test('üst sınır NUMERIC(12,2)', () {
      expect(val('9.999.999.999,99'), isNotNull);
      expect(err('10.000.000.000'), contains('çok büyük'));
    });
  });

  test('kategori ve not doğrulama', () {
    expect(FinanceValidators.category(' '), isNotNull);
    expect(FinanceValidators.category('Yakıt'), isNull);
    expect(FinanceValidators.category('x' * 101), isNotNull);
    expect(FinanceValidators.note('x' * 501), isNotNull);
    expect(FinanceValidators.note(null), isNull);
  });

  group('Kategori seçenekleri', () {
    test('varsayılanlar sektör nötr; proje/kişisel ayrı liste', () {
      final g = BrandProfile.generic.terms;
      final biz = FinanceCategories.options(
        g,
        scope: ScopeView.business,
        hasProject: false,
      );
      expect(biz, contains('Malzeme'));
      expect(biz.any((c) => c.contains('Dükkan')), isFalse);
      final prj = FinanceCategories.options(
        g,
        scope: ScopeView.general,
        hasProject: true,
      );
      expect(prj, contains('Taşeron'));
      final home = FinanceCategories.options(
        g,
        scope: ScopeView.personal,
        hasProject: false,
      );
      expect(home, contains('Ev kirası'));
    });

    test('son kullanılanlar başa gelir (en çok 4, tekrarsız)', () {
      final g = BrandProfile.generic.terms;
      final l = FinanceCategories.options(
        g,
        scope: ScopeView.business,
        hasProject: false,
        recent: ['Yakıt', 'Yakıt', 'Özel A', 'B', 'C', 'D'],
      );
      expect(l.take(4).toList(), ['Yakıt', 'Özel A', 'B', 'C']);
      expect(l.where((c) => c == 'Yakıt').length, 1);
    });

    test('marka sözlüğü varsa onun kategorileri kullanılır', () {
      const terms = Glossary(expenseCategoryLabels: {'Kira': 'Kira bedeli'});
      final l = FinanceCategories.options(
        terms,
        scope: ScopeView.business,
        hasProject: false,
      );
      expect(l, ['Kira']);
      expect(FinanceCategories.label(terms, 'Kira'), 'Kira bedeli');
      expect(FinanceCategories.label(terms, 'Özel'), 'Özel');
    });
  });

  test(
    'ödeme yöntemleri genişletilebilir liste (Havale/Nakit/Kredi Kartı)',
    () {
      expect(PaymentMethodOption.standard.map((e) => e.api), [
        'Havale',
        'Nakit',
        'Kredi Kartı',
      ]);
    },
  );

  group('Rol görünürlüğü', () {
    FinanceAccess a(UserRole r) => FinanceAccess.of(AppCapabilities.forRole(r));

    test('saha finans GÖRMEZ', () {
      final s = a(UserRole.saha);
      expect(s.canView, isFalse);
      expect(s.canManageRecurring, isFalse);
      expect(s.canAddGeneralExpense, isFalse);
      expect(s.canUsePersonalScope, isFalse);
    });

    test('personel kısıtlı: genel gider/sabit gider/kişisel yok', () {
      final p = a(UserRole.personel);
      expect(p.canView, isTrue);
      expect(p.isRestricted, isTrue);
      expect(p.canAddGeneralExpense, isFalse);
      expect(p.canManageRecurring, isFalse);
      expect(p.canUsePersonalScope, isFalse);
    });

    test('admin, muhasebe, ortak tam yetki', () {
      for (final r in [UserRole.admin, UserRole.muhasebe, UserRole.ortak]) {
        final x = a(r);
        expect(x.canView, isTrue, reason: r.api);
        expect(x.canManageRecurring, isTrue, reason: r.api);
        expect(x.canAddGeneralExpense, isTrue, reason: r.api);
        expect(x.canUsePersonalScope, isTrue, reason: r.api);
      }
    });
  });

  test('hatırlatma metni nazik, marka adı ve tutar içerir, UUID yok', () {
    final t = ReminderMessage.build(
      company: 'İşletmem',
      customer: 'Ayşe Yılmaz',
      remaining: Money.fromTl(26046),
      projectCode: 'PRJ-12',
    );
    expect(t, contains('Merhaba Ayşe Yılmaz'));
    expect(t, contains('İşletmem'));
    expect(t, contains('₺26.046,00'));
    expect(t, contains('PRJ-12'));
    expect(t, contains('teşekkür'));
    final noCode = ReminderMessage.build(
      company: 'X',
      customer: '',
      remaining: Money.fromTl(1),
    );
    expect(noCode, startsWith('Merhaba,'));
  });
}
