// Asistan sekmesi: sohbet biçiminde Türkçe KOMUT ÇUBUĞU. Yanıtlar sunucudaki kural tabanlı ayrıştırıcıdan
// gelir (yapay zekâ yok): sayı kartları, Onay kartı ya da "ne demek istediniz?" seçenekleri.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/brand_profile.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../application/access.dart';
import '../application/assistant_routes_paths.dart';
import '../application/chat_controller.dart';
import '../application/dictation_service.dart';
import 'briefing_summary_card.dart';
import 'inbox_screen.dart';
import 'widgets/assistant_ui.dart';
import 'widgets/chat_widgets.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _submit([String? text]) async {
    final t = (text ?? _input.text).trim();
    if (t.isEmpty) return;
    _input.clear();
    await ref.read(chatControllerProvider.notifier).send(t);
  }

  void _prefill(String text) {
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    _focus.requestFocus();
  }

  Future<void> _mic() async {
    final d = ref.read(dictationServiceProvider);
    if (!d.available) {
      toast(
        context,
        'Klavyenizdeki mikrofon düğmesine dokunarak sesle yazabilirsiniz.',
      );
      return;
    }
    final said = await d.listen();
    if (said != null && said.trim().isNotEmpty && mounted)
      _prefill(said.trim());
  }

  Future<void> _menu(String v) async {
    switch (v) {
      case 'closure':
        context.push(AssistantPaths.closure);
      case 'history':
        context.push(AssistantPaths.briefingHistory);
      case 'prefs':
        context.push(AssistantPaths.prefs);
      case 'import':
        context.push(AssistantPaths.share);
      case 'consents':
        context.push(AssistantPaths.consents);
      case 'clear':
        final ok = await ConfirmDialog.show(
          context,
          title: 'Sohbeti temizle',
          message:
              'Bu cihazdaki sohbet geçmişi silinir. Kayıtlarınız etkilenmez.',
          confirmLabel: 'Temizle',
          destructive: true,
        );
        if (ok) await ref.read(chatControllerProvider.notifier).clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    final access = ref.watch(assistantAccessProvider);
    final terms = context.terms;
    if (chat.messages.length != _lastCount) {
      _lastCount = chat.messages.length;
      _toEnd();
    }

    final quick = <({String label, VoidCallback run})>[
      (
        label: '${terms.appointment} ekle',
        run: () => _prefill('${terms.appointment} ekle '),
      ),
      if (access.showFinance)
        (label: 'Ödeme ekle', run: () => _prefill('Ödeme ekle ')),
      (label: 'Bugün ne var?', run: () => _submit('Bugün ne var?')),
      if (access.showFinance)
        (
          label: 'Bu ay ne kadar tahsilat?',
          run: () => _submit('Bu ay ne kadar tahsilat?'),
        ),
      (
        label: 'Gün sonu raporu',
        run: () => context.push(AssistantPaths.closure),
      ),
      if (access.showSales)
        (label: '${terms.offer} hazırla', run: () => context.go(Routes.jobs)),
    ];

    return AppScaffold(
      title: 'Asistan',
      actions: [
        const InboxBellButton(),
        IconButton(
          tooltip: 'Günün özeti',
          icon: const Icon(Icons.wb_sunny_outlined),
          onPressed: () => context.push(AssistantPaths.briefing),
        ),
        if (access.showManager)
          IconButton(
            tooltip: 'Müdür önerileri',
            icon: const Icon(Icons.tips_and_updates_outlined),
            onPressed: () => context.push(AssistantPaths.insights),
          ),
        PopupMenuButton<String>(
          tooltip: 'Diğer',
          onSelected: _menu,
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'closure',
              child: Text('Gün sonu raporu'),
            ),
            const PopupMenuItem(
              value: 'history',
              child: Text('Geçmiş özetler'),
            ),
            const PopupMenuItem(
              value: 'prefs',
              child: Text('Bildirim tercihleri'),
            ),
            if (access.canImport)
              const PopupMenuItem(
                value: 'import',
                child: Text('Yazışma içe aktar'),
              ),
            if (access.canImport)
              const PopupMenuItem(value: 'consents', child: Text('Rızalar')),
            const PopupMenuItem(value: 'clear', child: Text('Sohbeti temizle')),
          ],
        ),
      ],
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(Space.lg),
              children: [
                const BriefingSummaryCard(),
                const SizedBox(height: Space.md),
                if (chat.messages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.lg),
                    child: Column(
                      children: [
                        Text(
                          'Ne yapmamı istersiniz?',
                          style: context.text.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: Space.sm),
                        Text(
                          'Kısa Türkçe komutlar yazın; örneğin "Yarın 10\'da randevu ekle". '
                          'Anlamazsam seçenek sunarım. Hiçbir şey sizin onayınız olmadan kaydedilmez.',
                          style: context.text.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                for (var i = 0; i < chat.messages.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.md),
                    child: ChatBubble(
                      message: chat.messages[i],
                      isLast: i == chat.messages.length - 1,
                    ),
                  ),
                if (chat.sending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.md),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(width: Space.sm),
                        Text('Düşünüyorum…', style: context.text.bodySmall),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (chat.notice != null)
            Material(
              color: context.xc.warningContainer,
              child: ListTile(
                dense: true,
                title: Text(chat.notice!),
                trailing: IconButton(
                  tooltip: 'Kapat',
                  icon: const Icon(Icons.close),
                  onPressed: ref
                      .read(chatControllerProvider.notifier)
                      .dismissNotice,
                ),
              ),
            ),
          SizedBox(
            key: const ValueKey('quick-chips'),
            height: Sizes.minTouch + Space.sm,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              itemCount: quick.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
              itemBuilder: (_, i) => Center(
                child: ActionChip(
                  label: Text(quick[i].label),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onPressed: chat.sending ? null : quick[i].run,
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.xs,
                Space.sm,
                Space.sm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 3,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(maxCommandLength),
                      ],
                      onSubmitted: _submit,
                      decoration: const InputDecoration(
                        hintText: 'Komut yazın…',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sesle yaz',
                    constraints: const BoxConstraints(
                      minWidth: Sizes.minTouch,
                      minHeight: Sizes.minTouch,
                    ),
                    icon: const Icon(Icons.mic_none),
                    onPressed: _mic,
                  ),
                  IconButton.filled(
                    tooltip: 'Gönder',
                    constraints: const BoxConstraints(
                      minWidth: Sizes.minTouch,
                      minHeight: Sizes.minTouch,
                    ),
                    icon: const Icon(Icons.send),
                    onPressed: chat.sending ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
