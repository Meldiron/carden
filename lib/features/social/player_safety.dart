import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/social.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// Player > Report: pick a reason, optionally block too, then Send report. The report goes to the
/// developer (table `reports`) and the player is told it was sent. True when the player was also
/// blocked (the profile then closes, [leaveBlockedProfile]).
Future<bool> showReportSheet(BuildContext context, Profile player) async {
  final choice = await showAppSheet<({ReportReason reason, bool block})>(context, builder: (_) => _ReportPanel(player: player));
  if (choice == null || !context.mounted) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container.read(playerSafetyProvider).report(player, choice.reason);
    if (choice.block) await container.read(playerSafetyProvider).block(player);
    Haptics.success();
    if (context.mounted) showToast(context, choice.block ? 'Report sent and ${player.displayName} blocked.' : 'Report sent. Thank you.', icon: AppIcons.report);
    return choice.block;
  } catch (e) {
    if (context.mounted) showToast(context, 'The report could not be sent. Check your connection and try again.', icon: AppIcons.signal);
    return false;
  }
}

class _ReportPanel extends StatefulWidget {
  const _ReportPanel({required this.player});
  final Profile player;
  @override
  State<_ReportPanel> createState() => _ReportPanelState();
}

class _ReportPanelState extends State<_ReportPanel> {
  ReportReason? _reason;
  bool _block = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = widget.player.displayName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetHeader(title: 'Report $name', subtitle: 'What is wrong? We read every report.'),
          const SizedBox(height: 16),
          // Reasons: a single choice, like a settings list.
          Container(
            decoration: BoxDecoration(color: c.card.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(Radii.md)),
            child: Column(
              children: [
                for (final (i, r) in ReportReason.values.indexed) ...[
                  if (i > 0) Divider(height: 1, thickness: 0.5, indent: 16, color: c.stroke),
                  Pressable(
                    key: ValueKey('report-${r.code}'),
                    scale: 0.99,
                    onTap: () => setState(() => _reason = r),
                    child: SizedBox(
                      height: 48,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Expanded(child: Text(r.label, style: const TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w500))),
                            if (_reason == r) Icon(AppIcons.checkmarkAlt, size: 20, color: context.accent),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 52,
            padding: const EdgeInsets.only(left: 16, right: 8),
            decoration: BoxDecoration(color: c.card.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(Radii.md)),
            child: Row(
              children: [
                Expanded(child: Text('Also block $name', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w500))),
                CupertinoSwitch(key: const ValueKey('report-block'), value: _block, activeTrackColor: context.accent, onChanged: (v) => setState(() => _block = v)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          BigButton(
            key: const ValueKey('report-send'),
            label: 'Send report',
            onTap: _reason == null ? null : () => Navigator.of(context).pop((reason: _reason!, block: _block)),
          ),
        ],
      ),
    );
  }
}

/// Player > Block, after a confirmation. True once the player is blocked (the profile then closes,
/// [leaveBlockedProfile]).
Future<bool> confirmBlock(BuildContext context, Profile player) async {
  final ok = await showAppAlert(
    context,
    title: 'Block ${player.displayName}?',
    message: 'They no longer show on your leaderboard and leave your friends. Unblock them any time in Settings > Blocked players.',
    confirmLabel: 'Block',
    cancelLabel: 'Cancel',
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container.read(playerSafetyProvider).block(player);
    Haptics.success();
    if (context.mounted) showToast(context, 'Blocked ${player.displayName}', icon: AppIcons.block);
    return true;
  } catch (e) {
    if (context.mounted) showToast(context, 'Could not block. Check your connection and try again.', icon: AppIcons.signal);
    return false;
  }
}

/// After a block (owner, 2026-10-18: "After blocking player, go away from their profile"): back to
/// where the player came from (the leaderboard, Friends, a gift in the Inbox), or to Social when the
/// profile opened from a link with nothing under it. The toast stays: it lives on the root overlay.
void leaveBlockedProfile(BuildContext context) {
  if (!context.mounted) return;
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
  } else {
    router.go('/social');
  }
}

Future<void> unblockPlayer(BuildContext context, String playerId, String name) async {
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await container.read(playerSafetyProvider).unblock(playerId);
    if (context.mounted) showToast(context, '$name is unblocked', icon: AppIcons.block);
  } catch (e) {
    if (context.mounted) showToast(context, 'Could not unblock. Check your connection and try again.', icon: AppIcons.signal);
  }
}

/// Settings > Blocked players.
Future<void> showBlockedPlayersSheet(BuildContext context) => showAppSheet(context, builder: (_) => const BlockedPlayersPanel());

class BlockedPlayersPanel extends ConsumerWidget {
  const BlockedPlayersPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedPlayersProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHeader(title: 'Blocked players', subtitle: 'They do not show on your leaderboard.'),
          const SizedBox(height: 12),
          blocked.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Loader()),
            error: (e, _) => EmptyState(
              icon: AppIcons.signal,
              title: 'Blocked players could not load',
              message: 'Check your connection and try again.',
              action: BigButton(label: 'Try again', kind: ButtonKind.secondary, height: 44, expand: false, onTap: () => ref.invalidate(blockedPlayersProvider)),
            ),
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: EmptyState(key: ValueKey('blocked-empty'), icon: AppIcons.block, title: 'Nobody blocked', message: 'Block a player from their profile.'),
                  )
                : Column(
                    children: [
                      for (final b in list)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              AvatarCircle(avatarKey: b.avatar, size: 36),
                              const SizedBox(width: 12),
                              Expanded(child: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: TypeSize.body, fontWeight: FontWeight.w600))),
                              BigButton(
                                key: ValueKey('unblock-${b.playerId}'),
                                label: 'Unblock',
                                kind: ButtonKind.secondary,
                                height: 36,
                                expand: false,
                                onTap: () => unblockPlayer(context, b.playerId, b.name),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
