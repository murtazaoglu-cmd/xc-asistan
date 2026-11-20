import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/auth/biometric.dart';
import 'package:xc_asistan/core/auth/session.dart';
import 'package:xc_asistan/core/storage/token_store.dart';

import '../helpers/fakes.dart';

void main() {
  Future<(ProviderContainer, FakeBiometric, FakeAuthRepository)> make({
    bool lockOn = true,
    bool signedIn = true,
  }) async {
    final bio = FakeBiometric();
    final repo = FakeAuthRepository();
    final c = ProviderContainer(
      overrides: await baseOverrides(
        repo: repo,
        bio: bio,
        store: MemoryTokenStore()..token = signedIn ? 'tok' : null,
        prefsValues: {'pref.biometric_lock': lockOn},
      ),
    );
    addTearDown(c.dispose);
    c.read(appLockProvider); // dinleyiciyi kur
    await c.read(sessionProvider.notifier).bootstrap();
    return (c, bio, repo);
  }

  test(
    'soğuk açılışta oturum + kilit açık → kilitli; kapalıysa değil',
    () async {
      final (c, _, _) = await make();
      expect(c.read(appLockProvider).locked, isTrue);
      final (c2, _, _) = await make(lockOn: false);
      expect(c2.read(appLockProvider).locked, isFalse);
    },
  );

  test('unlock başarılı → açılır; başarısız → kilitli kalır', () async {
    final (c, bio, _) = await make();
    bio.result = false;
    expect(await c.read(appLockProvider.notifier).unlock(), isFalse);
    expect(c.read(appLockProvider).locked, isTrue);
    bio.result = true;
    expect(await c.read(appLockProvider.notifier).unlock(), isTrue);
    expect(c.read(appLockProvider).locked, isFalse);
  });

  test('arka plan: 30 sn altında kilitlenmez, üstünde kilitlenir', () async {
    final (c, _, _) = await make();
    final n = c.read(appLockProvider.notifier);
    await n.unlock();
    var now = DateTime(2026, 11, 20, 10);
    n.clock = () => now;
    n.onBackgrounded();
    now = now.add(const Duration(seconds: 10));
    n.onResumed();
    expect(c.read(appLockProvider).locked, isFalse);
    n.onBackgrounded();
    now = now.add(const Duration(seconds: 31));
    n.onResumed();
    expect(c.read(appLockProvider).locked, isTrue);
  });

  test('runUnlocked: seçici dönüşünde kilit istenmez', () async {
    final (c, _, _) = await make();
    final n = c.read(appLockProvider.notifier);
    await n.unlock();
    var now = DateTime(2026, 11, 20, 10);
    n.clock = () => now;
    await n.runUnlocked(() async {
      n.onBackgrounded();
      now = now.add(const Duration(minutes: 5));
      n.onResumed();
    });
    expect(c.read(appLockProvider).locked, isFalse);
  });

  test('setEnabled: desteklenmiyorsa false; açarken doğrulama ister', () async {
    final (c, bio, _) = await make(lockOn: false);
    final n = c.read(appLockProvider.notifier);
    bio.supported = false;
    expect(await n.setEnabled(true), isFalse);
    bio.supported = true;
    bio.result = false;
    expect(await n.setEnabled(true), isFalse);
    expect(c.read(appLockProvider).enabled, isFalse);
    bio.result = true;
    expect(await n.setEnabled(true), isTrue);
    expect(c.read(appLockProvider).enabled, isTrue);
    expect(await n.setEnabled(false), isTrue);
    expect(c.read(appLockProvider).enabled, isFalse);
  });

  test('çıkış yapınca kilit kalkar', () async {
    final (c, _, _) = await make();
    await c.read(sessionProvider.notifier).logout();
    expect(c.read(appLockProvider).locked, isFalse);
  });
}
