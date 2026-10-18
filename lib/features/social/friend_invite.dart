import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/analytics.dart';
import '../../core/app_links.dart';
import '../../core/theme/tokens.dart';
import '../../state/auth.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// The link that adds the player with [code] as a friend (`/add-friend?code=<id>`, Social > Friends >
/// Add friend by code with the code filled in), in the app where it is installed and on the web
/// elsewhere.
String friendInviteLink(String code) => '${AppLink.webOrigin}/add-friend?code=${Uri.encodeQueryComponent(code)}';

/// The invite's words, before the link.
const friendInviteText = 'Add me as a friend in Carden';

/// Shares the friend invite (owner, 2026-10-18: "Change copy link button to share"): the iPhone's
/// share sheet (Copy, Messages, WhatsApp, Messenger, Instagram, Snapchat...) or the browser's (Web
/// Share API). Where a browser has none, the link is copied instead, as before. The same approach
/// as Play together's invite (`lib/features/coop/share_invite.dart`, where share_plus was checked
/// for network use: none of its own, and its mailto and download fallbacks stay off).
Future<void> shareFriendInvite(BuildContext context, String code) async {
  final box = context.findRenderObject();
  // The iPad (and the Mac) anchor the share sheet's popover on the button.
  final origin = box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
  try {
    await SharePlus.instance.share(ShareParams(
      text: '$friendInviteText\n${friendInviteLink(code)}',
      subject: friendInviteText,
      sharePositionOrigin: origin,
      mailToFallbackEnabled: false,
      downloadFallbackEnabled: false,
    ));
    AppAnalytics.event('friend_invite_shared', {'via': 'sheet'});
  } catch (_) {
    if (context.mounted) await copyFriendInvite(context, code);
  }
}

/// Copies the friend invite link (a browser without a share sheet).
Future<void> copyFriendInvite(BuildContext context, String code) async {
  await Clipboard.setData(ClipboardData(text: friendInviteLink(code)));
  AppAnalytics.event('friend_invite_shared', {'via': 'copy'});
  if (context.mounted) showToast(context, 'Copied your invite link', icon: AppIcons.copy);
}

/// Social > Friends, on top: Invite friends (Share) and Add friend (by code).
class FriendInviteCard extends ConsumerWidget {
  const FriendInviteCard({super.key, required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final me = ref.watch(currentUserIdProvider);
    return SoftCard(
      padding: Insets.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Invite friends', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Your link lets friends add you in one tap.', style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                // Its own context: the share sheet's popover points at this button on an iPad.
                child: Builder(
                  builder: (button) => BigButton(
                    key: const ValueKey('share-invite'),
                    label: 'Share',
                    icon: AppIcons.share,
                    kind: ButtonKind.secondary,
                    height: 44,
                    onTap: me == null ? null : () => shareFriendInvite(button, me),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: BigButton(key: const ValueKey('add-friend-open'), label: 'Add friend', kind: ButtonKind.secondary, height: 44, onTap: onAdd)),
            ],
          ),
        ],
      ),
    );
  }
}
