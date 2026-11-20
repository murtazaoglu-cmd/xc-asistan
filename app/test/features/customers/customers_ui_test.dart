import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/api/api_client.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/features/customers/data/customer_models.dart';
import 'package:xc_asistan/features/customers/data/customers_repository.dart';
import 'package:xc_asistan/features/customers/presentation/conversation_section.dart';
import 'package:xc_asistan/features/customers/presentation/customer_detail_screen.dart';
import 'package:xc_asistan/features/customers/presentation/customer_form_screen.dart';
import 'package:xc_asistan/features/customers/presentation/customers_screen.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

class FakeCustomersRepo implements CustomersRepository {
  FakeCustomersRepo(this.all);
  List<Customer> all;
  final List<String> queries = [];
  final List<CustomerInput> created = [];
  Object? listError;
  int pageSize = 50;
  Customer? duplicate;

  @override
  Future<Paged<Customer>> list({
    String query = '',
    int limit = 50,
    int offset = 0,
  }) async {
    queries.add(query);
    if (listError != null) throw listError!;
    final f = all
        .where(
          (c) =>
              query.isEmpty ||
              c.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return Paged(f.skip(offset).take(limit).toList(), f.length);
  }

  @override
  Future<Customer> get(String phoneKey) async =>
      all.firstWhere((c) => c.phoneKey == phoneKey);

  @override
  Future<Customer?> findByPhone(String phone) async => duplicate;

  @override
  Future<CustomerHistory> history(String phoneKey) async =>
      const CustomerHistory();

  @override
  Future<Customer> create(CustomerInput input) async {
    created.add(input);
    return Customer(phoneKey: input.phoneKey, name: input.name);
  }

  @override
  Future<void> update(String phoneKey, CustomerInput input) async {}

  @override
  Future<void> delete(String phoneKey) async {}
}

Customer cu(String name, String key, {int projects = 1, String? phone}) =>
    Customer(
      phoneKey: key,
      name: name,
      phone: phone ?? key,
      region: 'Bodrum',
      projectCount: projects,
      offerCount: 1,
    );

void main() {
  group('Müşteri listesi', () {
    testWidgets('alfabetik gruplu: harf başlıkları ve satırlar', (t) async {
      final repo = FakeCustomersRepo([
        cu('Zeynep Arslan', '05360000001'),
        cu('Ali Çelik', '05350000002'),
        cu('Çiğdem Kaya', '05340000003'),
      ]);
      await pumpScreen(
        t,
        const CustomersScreen(),
        overrides: [customersRepositoryProvider.overrideWithValue(repo)],
      );
      await settle(t);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('Ç'), findsOneWidget);
      expect(find.text('Z'), findsOneWidget);
      expect(find.text('Ali Çelik'), findsOneWidget);
      final yA = t.getTopLeft(find.text('Ali Çelik')).dy;
      final yC = t.getTopLeft(find.text('Çiğdem Kaya')).dy;
      final yZ = t.getTopLeft(find.text('Zeynep Arslan')).dy;
      expect(yA < yC && yC < yZ, isTrue);
      expect(find.text('Müşteri ekle'), findsOneWidget); // sözlükten
    });

    testWidgets('arama: gecikmeli ve normalleştirilmiş q gider', (t) async {
      final repo = FakeCustomersRepo([cu('Ali', '1')]);
      await pumpScreen(
        t,
        const CustomersScreen(),
        overrides: [customersRepositoryProvider.overrideWithValue(repo)],
      );
      await settle(t);
      await t.enterText(find.byType(TextField), '+90 532 111');
      await t.pump(const Duration(milliseconds: 100));
      expect(repo.queries.last, '', reason: 'bekleme dolmadan istek yok');
      await t.pump(const Duration(milliseconds: 400));
      await settle(t);
      expect(repo.queries.last, '+90 532 111'); // normalleştirme repository'de
    });

    testWidgets('boş arama sonucu: "Sonuç bulunamadı" + temizle', (t) async {
      final repo = FakeCustomersRepo([cu('Ali', '1')]);
      await pumpScreen(
        t,
        const CustomersScreen(),
        overrides: [customersRepositoryProvider.overrideWithValue(repo)],
      );
      await settle(t);
      await t.enterText(find.byType(TextField), 'xyz');
      await t.pump(const Duration(milliseconds: 450));
      await settle(t);
      expect(find.text('Sonuç bulunamadı'), findsOneWidget);
      await t.tap(find.text('Aramayı temizle').last);
      await settle(t);
      expect(find.text('Ali'), findsOneWidget);
    });

    testWidgets('boş liste: davet + ekle düğmesi', (t) async {
      await pumpScreen(
        t,
        const CustomersScreen(),
        overrides: [
          customersRepositoryProvider.overrideWithValue(FakeCustomersRepo([])),
        ],
      );
      await settle(t);
      expect(find.text('Henüz müşteri yok'), findsOneWidget);
      expect(find.text('İlk müşteriyi ekle'), findsOneWidget);
    });

    testWidgets('hata: Türkçe mesaj + Tekrar dene; sonra veri gelir', (
      t,
    ) async {
      final repo = FakeCustomersRepo([cu('Ali', '1')])
        ..listError = const AppException(
          AppErrorCode.network,
          AppException.networkMessage,
        );
      await pumpScreen(
        t,
        const CustomersScreen(),
        overrides: [customersRepositoryProvider.overrideWithValue(repo)],
      );
      await settle(t);
      expect(find.text(AppException.networkMessage), findsOneWidget);
      repo.listError = null;
      await t.tap(find.text('Tekrar dene'));
      await settle(t);
      expect(find.text('Ali'), findsOneWidget);
    });

    testWidgets('sayfalama: 50 kayıt + "Daha fazla yükle"', (t) async {
      final repo = FakeCustomersRepo([
        for (var i = 0; i < 70; i++)
          cu(
            'Müşteri ${i.toString().padLeft(2, '0')}',
            '0532${i.toString().padLeft(7, '0')}',
          ),
      ]);
      await pumpScreen(
        t,
        const CustomersScreen(),
        overrides: [customersRepositoryProvider.overrideWithValue(repo)],
      );
      await settle(t);
      final container = ProviderScope.containerOf(
        t.element(find.byType(CustomersScreen)),
      );
      expect(container.read(customerListProvider).value!.items.length, 50);
      expect(container.read(customerListProvider).value!.hasMore, isTrue);
      await container.read(customerListProvider.notifier).loadMore();
      await settle(t);
      final s = container.read(customerListProvider).value!;
      expect(s.items.length, 70);
      expect(s.hasMore, isFalse);
    });

    testWidgets(
      'rol görünürlüğü: personel ve saha göremez; admin/muhasebe/ortak görür',
      (t) async {
        for (final role in [UserRole.personel, UserRole.saha]) {
          await pumpScreen(
            t,
            const CustomersScreen(),
            role: role,
            overrides: [
              customersRepositoryProvider.overrideWithValue(
                FakeCustomersRepo([cu('Ali', '1')]),
              ),
            ],
          );
          await settle(t);
          expect(
            find.text('Bu bölüm için yetkiniz yok'),
            findsOneWidget,
            reason: role.api,
          );
          expect(find.text('Ali'), findsNothing);
        }
        for (final role in [
          UserRole.admin,
          UserRole.muhasebe,
          UserRole.ortak,
        ]) {
          await pumpScreen(
            t,
            const CustomersScreen(),
            role: role,
            overrides: [
              customersRepositoryProvider.overrideWithValue(
                FakeCustomersRepo([cu('Ali', '1')]),
              ),
            ],
          );
          await settle(t);
          expect(find.text('Ali'), findsOneWidget, reason: role.api);
        }
      },
    );
  });

  group('Müşteri kartı', () {
    testWidgets('yer tutucu yazışma bölümü ve genişletme noktası', (t) async {
      final repo = FakeCustomersRepo([
        Customer(
          phoneKey: '05321112233',
          name: 'Ayşe Yılmaz',
          phone: '0532 111 22 33',
          address: 'Konacık',
          offerCount: 2,
          projectCount: 1,
        ),
      ]);
      await pumpScreen(
        t,
        const CustomerDetailScreen(phoneKey: '05321112233'),
        size: const Size(400, 3000),
        overrides: [customersRepositoryProvider.overrideWithValue(repo)],
      );
      await settle(t);
      expect(find.text('Yazışma geçmişi'), findsOneWidget);
      expect(find.text('Ara'), findsOneWidget);
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.text('Notlar'), findsOneWidget);
    });

    testWidgets(
      'assistant ajanı sağlayıcıyı geçersiz kılarak bölümü doldurur',
      (t) async {
        final repo = FakeCustomersRepo([cu('Ali', '1')]);
        await pumpScreen(
          t,
          const CustomerDetailScreen(phoneKey: '1'),
          size: const Size(400, 3000),
          overrides: [
            customersRepositoryProvider.overrideWithValue(repo),
            conversationSectionBuilderProvider.overrideWithValue(
              (context, args) => Text('Yazışma: ${args.customer.name}'),
            ),
          ],
        );
        await settle(t);
        expect(find.text('Yazışma: Ali'), findsOneWidget);
        expect(find.text('Yazışma geçmişi'), findsNothing);
      },
    );
  });

  group('Müşteri formu', () {
    testWidgets('boş gönderimde alan hataları, istek yok', (t) async {
      final repo = FakeCustomersRepo([]);
      await pumpScreen(
        t,
        const CustomerFormScreen(),
        overrides: [customersRepositoryProvider.overrideWithValue(repo)],
      );
      await t.tap(find.text('Müşteri ekle'));
      await t.pump();
      expect(find.text('Ad soyad girin.'), findsOneWidget);
      expect(find.text('Telefon numarası girin.'), findsOneWidget);
      expect(repo.created, isEmpty);
    });

    testWidgets('geçersiz telefon / e-posta mesajları', (t) async {
      await pumpScreen(
        t,
        const CustomerFormScreen(),
        overrides: [
          customersRepositoryProvider.overrideWithValue(FakeCustomersRepo([])),
        ],
      );
      await t.enterText(find.byKey(const Key('field-name')), 'Ali');
      await t.enterText(find.byKey(const Key('field-phone')), '0532 11');
      await t.enterText(find.byKey(const Key('field-email')), 'x@y');
      await t.tap(find.text('Müşteri ekle'));
      await t.pump();
      expect(find.text('Telefon en az 10 rakam olmalı.'), findsOneWidget);
      expect(find.text('Geçerli bir e-posta adresi girin.'), findsOneWidget);
    });

    testWidgets('telefon alanı rakam/biçim dışı karakteri kabul etmez', (
      t,
    ) async {
      await pumpScreen(
        t,
        const CustomerFormScreen(),
        overrides: [
          customersRepositoryProvider.overrideWithValue(FakeCustomersRepo([])),
        ],
      );
      await t.enterText(find.byKey(const Key('field-phone')), 'abc0532x');
      final tf = t.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('field-phone')),
          matching: find.byType(TextField),
        ),
      );
      expect(tf.controller!.text, '0532');
      expect(tf.keyboardType, TextInputType.phone);
    });

    testWidgets('geçerli form: create çağrılır ve karta gidilir', (t) async {
      final repo = FakeCustomersRepo([]);
      final router = await pumpScreen(
        t,
        const CustomerFormScreen(),
        overrides: [customersRepositoryProvider.overrideWithValue(repo)],
      );
      await t.enterText(find.byKey(const Key('field-name')), 'Ali Veli');
      await t.enterText(find.byKey(const Key('field-phone')), '0532 111 22 33');
      await t.pump(const Duration(milliseconds: 600));
      await t.tap(find.text('Müşteri ekle'));
      await settle(t);
      expect(repo.created.single.name, 'Ali Veli');
      expect(repo.created.single.phoneKey, '05321112233');
      expect(router.state.uri.toString(), '/customers/05321112233');
    });

    testWidgets('tekrar eden telefon uyarısı gösterilir', (t) async {
      final repo = FakeCustomersRepo([])
        ..duplicate = cu('Ayşe Yılmaz', '05321112233');
      await pumpScreen(
        t,
        const CustomerFormScreen(),
        overrides: [customersRepositoryProvider.overrideWithValue(repo)],
      );
      await t.enterText(find.byKey(const Key('field-phone')), '0532 111 22 33');
      await t.pump(const Duration(milliseconds: 600));
      await t.pump();
      expect(
        find.textContaining('Bu numara zaten kayıtlı: Ayşe Yılmaz'),
        findsOneWidget,
      );
      expect(find.text('Mevcut kartı aç'), findsOneWidget);
    });

    testWidgets(
      'kayıtta tekrar eden numara onay penceresi açar; kaydetmeden önce sorar',
      (t) async {
        final repo = FakeCustomersRepo([])
          ..duplicate = cu('Ayşe Yılmaz', '05321112233');
        await pumpScreen(
          t,
          const CustomerFormScreen(),
          overrides: [customersRepositoryProvider.overrideWithValue(repo)],
        );
        await t.enterText(find.byKey(const Key('field-name')), 'Başka Ad');
        await t.enterText(
          find.byKey(const Key('field-phone')),
          '0532 111 22 33',
        );
        await t.pump(const Duration(milliseconds: 600));
        await t.tap(find.text('Müşteri ekle'));
        await settle(t);
        expect(find.text('Bu numara zaten kayıtlı'), findsOneWidget);
        await t.tap(find.text('Yine de kaydet'));
        await settle(t);
        expect(repo.created.length, 1);
      },
    );
  });
}
