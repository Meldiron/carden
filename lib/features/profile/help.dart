import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../core/haptics.dart';
import '../../core/links.dart';
import '../../core/platform.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories.dart';
import '../../state/auth.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import 'settings_screen.dart' show appVersionProvider;

/// Where a support email or a feedback message comes from: "iPhone" or "Web".
String get platformName => isWeb
    ? 'Web'
    : switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'iPhone',
        TargetPlatform.android => 'Android',
        TargetPlatform.macOS => 'Mac',
        final p => p.name,
      };

/// Settings > Contact support: an email to contact@almostapps.eu, with the app version and the
/// player id below the message so support can find the account. Without a mail app (a simulator,
/// a browser with no mail client) the address is copied instead.
Future<void> contactSupport(BuildContext context, WidgetRef ref) async {
  final mail = AppLinks.supportMail(version: ref.read(appVersionProvider).value, platform: platformName, playerId: ref.read(currentUserIdProvider));
  if (await openLink(mail)) return;
  await Clipboard.setData(const ClipboardData(text: AppLinks.supportEmail));
  if (context.mounted) showToast(context, 'Email address copied: ${AppLinks.supportEmail}', icon: AppIcons.mail);
}

/// Settings > Send feedback: one text field; the message goes to the `feedback` table, which only
/// the developer reads (`tools/dev/feedback.py`). [via] says what opened it: `settings`, or `shake`
/// (a shake of the iPhone on any screen, lib/features/profile/shake_feedback.dart).
Future<void> showFeedbackSheet(BuildContext context, {String via = 'settings'}) {
  AppAnalytics.event('feedback_opened', {'via': via});
  return showAppSheet(context, builder: (_) => const FeedbackPanel());
}

class FeedbackPanel extends ConsumerStatefulWidget {
  const FeedbackPanel({super.key});

  /// A feedback form is on screen (from Settings or a shake): a shake opens no second one.
  static bool get isOpen => _open > 0;
  static int _open = 0;

  @override
  ConsumerState<FeedbackPanel> createState() => _FeedbackPanelState();
}

class _FeedbackPanelState extends ConsumerState<FeedbackPanel> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    FeedbackPanel._open++;
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    FeedbackPanel._open--;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final message = _controller.text.trim();
    if (message.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final userId = ref.read(currentUserIdProvider);
      if (userId == null) throw StateError('not signed in');
      await ref.read(feedbackRepositoryProvider).send(userId: userId, message: message, appVersion: ref.read(appVersionProvider).value, platform: platformName);
    } catch (e) {
      debugPrint('feedback: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, 'Could not send. Check your connection and try again.', icon: AppIcons.signal);
      return;
    }
    if (!mounted) return;
    Haptics.success();
    showToast(context, 'Thank you. Your feedback was sent.', icon: AppIcons.check);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final length = _controller.text.characters.length;
    final empty = _controller.text.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHeader(title: 'Send feedback', subtitle: 'Ideas, problems, anything you would change. We read every message. To get a reply, use Contact support.'),
          const SizedBox(height: 16),
          CupertinoTextField(
            key: const ValueKey('feedback-field'),
            controller: _controller,
            placeholder: 'Your feedback',
            autofocus: true,
            minLines: 5,
            maxLines: 8,
            maxLength: FeedbackRepository.maxLength,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: TypeSize.callout, height: 1.35, color: c.textPrimary),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.boardBackground, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.stroke)),
          ),
          if (length > FeedbackRepository.maxLength - 200) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text('${formatCount(length)} / ${formatCount(FeedbackRepository.maxLength)}', style: TextStyle(fontSize: TypeSize.caption, color: c.textTertiary, fontFeatures: tabularFigures)),
            ),
          ],
          const SizedBox(height: 16),
          BigButton(key: const ValueKey('feedback-send'), label: 'Send feedback', loading: _busy, onTap: _busy || empty ? null : _send),
        ],
      ),
    );
  }
}
