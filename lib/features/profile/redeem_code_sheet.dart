import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/appwrite.dart';
import '../../core/haptics.dart';
import '../../core/theme/tokens.dart';
import '../../data/pack_codes.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../../state/sync.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// Settings > Redeem a pack code: a code from a giveaway or a special post opens a pack that is
/// otherwise hidden (`packs.hidden`). The server checks the code and unlocks the pack (function
/// `redeem-code`); the app then pulls the player's save and the catalogue and opens the pack.
Future<void> showRedeemCodeSheet(BuildContext context, {String? code}) =>
    showAppSheet(context, builder: (ctx) => RedeemCodePanel(initialCode: code));

class RedeemCodePanel extends ConsumerStatefulWidget {
  const RedeemCodePanel({super.key, this.initialCode});
  final String? initialCode;

  @override
  ConsumerState<RedeemCodePanel> createState() => _RedeemCodePanelState();
}

class _RedeemCodePanelState extends ConsumerState<RedeemCodePanel> {
  late final _controller = TextEditingController(text: widget.initialCode == null ? '' : PackCodes.format(widget.initialCode!));
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await PackCodes.redeem(ref.read(appwriteClientProvider), _controller.text);
    if (!mounted) return;
    if (!result.ok || result.packId == null) {
      Haptics.light();
      setState(() {
        _busy = false;
        _error = result.message;
      });
      return;
    }
    // The server unlocked the pack: pull the save (unlocked packs) and the catalogue (a pack added
    // since the last catalogue sync), then open the pack once it shows.
    await ref.read(syncProvider.notifier).sync(silent: true);
    ref.invalidate(catalogProvider);
    final packId = result.packId!;
    Pack? pack;
    for (var i = 0; i < 20 && pack == null; i++) {
      final packs = await ref.read(packsProvider.future);
      pack = packs.where((p) => p.id == packId).firstOrNull;
      if (pack == null) await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (!mounted) return;
    Haptics.success();
    final router = GoRouter.of(context);
    showToast(context, '${result.packName ?? 'The pack'} is in your Library', icon: AppIcons.unlock);
    Navigator.of(context).pop();
    router.push('/library/pack/$packId');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: double.infinity, child: SheetHeader(title: 'Redeem a pack code', subtitle: 'Enter the code you received. It opens a special pack in your Library.', center: false)),
          const SizedBox(height: 16),
          CupertinoTextField(
            key: const ValueKey('redeem-code-field'),
            controller: _controller,
            placeholder: 'XXXX-XXXX-XXXX-XXXX',
            autofocus: widget.initialCode == null,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            onSubmitted: (_) => _redeem(),
            style: TextStyle(fontFamily: 'Menlo', fontSize: TypeSize.headline, letterSpacing: 1.2, color: c.textPrimary),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: c.boardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _error == null ? c.stroke : Brand.danger),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, key: const ValueKey('redeem-code-error'), style: const TextStyle(fontSize: TypeSize.footnote, color: Brand.danger, fontWeight: FontWeight.w500)),
          ],
          const SizedBox(height: 16),
          BigButton(
            key: const ValueKey('redeem-code-button'),
            label: 'Redeem',
            loading: _busy,
            onTap: _busy ? null : _redeem,
          ),
        ],
      ),
    );
  }
}
