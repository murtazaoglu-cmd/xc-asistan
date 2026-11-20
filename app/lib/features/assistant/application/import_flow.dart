// WhatsApp yazışma içe aktarma akışı (Faz 2):
//   paylaşım/dosya → aydınlatma ve rıza → yükleme → önizleme (sahip, müşteri eşleme, grup)
//   → onay → öneri kartları. Veri yalnız kendi sunucumuzda işlenir; yapay zekâ yok.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../data/assistant_repository.dart';
import '../data/import_models.dart';
import '../data/model_utils.dart';

/// İçe aktarılacak içeriğin kaynağı.
@immutable
class ImportSource {
  const ImportSource({
    this.text,
    this.filePath,
    this.fileName,
    this.customerKey,
  });
  final String? text;
  final String? filePath;
  final String? fileName;

  /// Müşteri kartından başlatıldıysa önceden seçili müşteri.
  final String? customerKey;

  bool get isFile => filePath != null;
  bool get isEmpty =>
      (text == null || text!.trim().isEmpty) && filePath == null;

  ImportSource withCustomer(String? key) => ImportSource(
    text: text,
    filePath: filePath,
    fileName: fileName,
    customerKey: key,
  );
}

enum ImportPhase { idle, consent, uploading, preview, confirming, done }

/// Müşteri seçimi: auto = sunucunun en iyi eşleşmesi · none = bağlama · pick = elle seçildi.
enum CustomerMode { auto, none, pick }

@immutable
class ImportFlow {
  const ImportFlow({
    this.phase = ImportPhase.idle,
    this.source,
    this.notice,
    this.noticeLoading = false,
    this.consentChecked = false,
    this.preview,
    this.owner,
    this.mode = CustomerMode.auto,
    this.picked,
    this.includeGroup = false,
    this.result,
    this.error,
  });
  final ImportPhase phase;
  final ImportSource? source;
  final ConsentNotice? notice;
  final bool noticeLoading;
  final bool consentChecked;
  final ImportPreview? preview;
  final String? owner;
  final CustomerMode mode;
  final CustomerHit? picked;
  final bool includeGroup;
  final ImportConfirmResult? result;
  final String? error;

  bool get busy =>
      phase == ImportPhase.uploading || phase == ImportPhase.confirming;

  /// Müşteri eşleştirme sihirbazı gerekli mi? (sunucu eşleştiremedi, kullanıcı da seçmedi)
  bool get needsCustomerMatch =>
      preview != null && mode == CustomerMode.auto && preview!.customer == null;

  /// Seçili müşteri adı (gösterim).
  String? get customerLabel => switch (mode) {
    CustomerMode.pick => picked?.name,
    CustomerMode.none => null,
    CustomerMode.auto => preview?.customer?.name,
  };

  /// Onay verilebilir mi?
  bool get canConfirm {
    final p = preview;
    if (p == null || busy) return false;
    if (owner == null || owner!.isEmpty) return false;
    if (p.isGroup && !includeGroup) return false;
    if (needsCustomerMatch) return false;
    if (mode == CustomerMode.pick && picked == null) return false;
    return true;
  }

  ImportFlow copyWith({
    ImportPhase? phase,
    ImportSource? source,
    ConsentNotice? notice,
    bool? noticeLoading,
    bool? consentChecked,
    ImportPreview? preview,
    String? owner,
    CustomerMode? mode,
    CustomerHit? picked,
    bool? includeGroup,
    ImportConfirmResult? result,
    String? error,
    bool clearError = false,
  }) => ImportFlow(
    phase: phase ?? this.phase,
    source: source ?? this.source,
    notice: notice ?? this.notice,
    noticeLoading: noticeLoading ?? this.noticeLoading,
    consentChecked: consentChecked ?? this.consentChecked,
    preview: preview ?? this.preview,
    owner: owner ?? this.owner,
    mode: mode ?? this.mode,
    picked: picked ?? this.picked,
    includeGroup: includeGroup ?? this.includeGroup,
    result: result ?? this.result,
    error: clearError ? null : (error ?? this.error),
  );
}

class ImportFlowNotifier extends Notifier<ImportFlow> {
  @override
  ImportFlow build() => const ImportFlow();

  AssistantRepository get _repo => ref.read(assistantRepositoryProvider);

  /// Yeni içerik geldi: rıza adımına geç ve metni yükle. Aynı kaynak tekrar gelirse akış sıfırlanır.
  Future<void> begin(ImportSource source) async {
    state = ImportFlow(
      phase: ImportPhase.consent,
      source: source,
      noticeLoading: true,
    );
    try {
      final n = await _repo.consentNotice();
      state = state.copyWith(notice: n, noticeLoading: false);
    } on Object catch (e) {
      state = state.copyWith(
        noticeLoading: false,
        error: AppException.from(e).message,
      );
    }
  }

  Future<void> retryNotice() async {
    final s = state.source;
    if (s != null) await begin(s);
  }

  void toggleConsent(bool v) => state = state.copyWith(consentChecked: v);

  /// Rıza onaylandı → sunucuya gönder → önizleme.
  Future<bool> upload() async {
    final s = state.source;
    final n = state.notice;
    if (s == null || n == null || !state.consentChecked || state.busy)
      return false;
    state = state.copyWith(phase: ImportPhase.uploading, clearError: true);
    try {
      final p = s.isFile
          ? await _repo.importFile(
              path: s.filePath!,
              name: s.fileName ?? 'sohbet.txt',
              consentVersion: n.version,
              customerKey: s.customerKey,
            )
          : await _repo.importText(
              text: s.text ?? '',
              consentVersion: n.version,
            );
      state = state.copyWith(
        phase: ImportPhase.preview,
        preview: p,
        owner: p.suggestedOwner,
        mode: s.customerKey != null ? CustomerMode.pick : CustomerMode.auto,
        picked: s.customerKey != null
            ? CustomerHit(
                key: s.customerKey!,
                name: p.customer?.name ?? 'Seçili müşteri',
              )
            : null,
      );
      return true;
    } on Object catch (e) {
      state = state.copyWith(
        phase: ImportPhase.consent,
        error: AppException.from(e).message,
      );
      return false;
    }
  }

  void setOwner(String name) => state = state.copyWith(owner: name);
  void setIncludeGroup(bool v) => state = state.copyWith(includeGroup: v);
  void pickCustomer(CustomerHit hit) =>
      state = state.copyWith(mode: CustomerMode.pick, picked: hit);
  void useAutoCustomer() => state = state.copyWith(mode: CustomerMode.auto);
  void noCustomer() => state = state.copyWith(mode: CustomerMode.none);

  Future<bool> confirm() async {
    final p = state.preview;
    if (p == null || !state.canConfirm) return false;
    state = state.copyWith(phase: ImportPhase.confirming, clearError: true);
    try {
      final r = await _repo.confirmImport(
        p.id,
        ownerSender: state.owner!,
        customerKeyGiven: state.mode != CustomerMode.auto,
        customerKey: state.mode == CustomerMode.pick
            ? assistantCustomerKey(state.picked?.key)
            : null,
        includeGroup: state.includeGroup,
      );
      state = state.copyWith(phase: ImportPhase.done, result: r);
      return true;
    } on Object catch (e) {
      state = state.copyWith(
        phase: ImportPhase.preview,
        error: AppException.from(e).message,
      );
      return false;
    }
  }

  /// Önizlemeyi iptal eder (sunucudaki geçici kaydı siler; hata sessiz).
  Future<void> cancel() async {
    final p = state.preview;
    if (p != null && state.phase != ImportPhase.done) {
      try {
        await _repo.deleteImport(p.id);
      } on Object {
        // 24 saat sonra sunucu kendiliğinden siler.
      }
    }
    state = const ImportFlow();
  }

  void reset() => state = const ImportFlow();
}

final importFlowProvider = NotifierProvider<ImportFlowNotifier, ImportFlow>(
  ImportFlowNotifier.new,
);
