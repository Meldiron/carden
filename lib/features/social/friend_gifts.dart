import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../core/haptics.dart';
import '../../core/platform.dart';
import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/friend_gifts.dart';
import '../../state/push.dart';
import '../../state/social.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// Player > Send a gift (owner, 2026-10-17; docs/friend-gifts.md): on a friend's profile, 1 ticket
/// or 150 coins, free for the sender, once a day per friend. After today's gift the button says
/// when the next one can go. Shown only for players in the viewer's friends list.
class SendGiftButton extends ConsumerStatefulWidget {
  const SendGiftButton({super.key, required this.friend});
  final Profile friend;

  @override
  ConsumerState<SendGiftButton> createState() => _SendGiftButtonState();
}

class _SendGiftButtonState extends ConsumerState<SendGiftButton> {
  bool _sending = false;

  ({String friendId, String day}) get _key => (friendId: widget.friend.userId, day: FriendGifts.dayOf(DateTime.now()));

  Future<void> _send() async {
    final p = widget.friend;
    final kind = await showAppActionSheet<GiftKind>(
      context,
      title: 'Send ${p.displayName} a gift',
      message: 'Free for you, one gift a day. ${p.displayName} has 24 hours to claim it.',
      actions: [
        AppAction(GiftKind.tickets.label, GiftKind.tickets, key: const ValueKey('gift-tickets'), leading: const TicketIcon(size: 20)),
        AppAction(GiftKind.coins.label, GiftKind.coins, key: const ValueKey('gift-coins'), leading: const CoinIcon(size: 20)),
      ],
    );
    if (kind == null || !mounted) return;
    setState(() => _sending = true);
    final result = await ref.read(friendGiftRepositoryProvider).send(p.userId, kind);
    if (!mounted) return;
    setState(() => _sending = false);
    // Sent now or earlier today (another device): the button turns to "Next gift tomorrow".
    if (result.ok || result.error == 'already') ref.invalidate(giftSentProvider(_key));
    final name = result.friendName ?? p.displayName;
    if (result.ok) {
      Haptics.success();
      AppAnalytics.event('gift_sent', {'kind': kind == GiftKind.tickets ? 'ticket' : 'coins'});
    }
    showToast(context, result.message(name), icon: result.ok || result.error == 'already' ? AppIcons.gift : AppIcons.signal);
    if (result.ok) await offerGiftNotifications(context, ProviderScope.containerOf(context, listen: false));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.friend;
    final isFriend = ref.watch(friendsProvider).value?.any((f) => f.friendId == p.userId) ?? false;
    if (!isFriend) return const SizedBox.shrink();
    final sent = ref.watch(giftSentProvider(_key));
    final c = context.colors;
    final done = sent.value == true;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BigButton(
            key: ValueKey(done ? 'gift-sent' : 'gift-send'),
            label: done ? 'Next gift tomorrow' : 'Send a gift',
            icon: done ? AppIcons.checkmarkAlt : AppIcons.gift,
            kind: ButtonKind.secondary,
            height: 48,
            loading: _sending || (sent.isLoading && !sent.hasValue),
            onTap: done || _sending || !sent.hasValue ? null : _send,
          ),
          const SizedBox(height: 6),
          Text(
            done ? 'You sent ${p.displayName} a gift today.' : '1 ticket or 150 coins, free for you, once a day.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// A gift sent or claimed, or a friend added: the moments gift notifications used to be offered in
/// an alert of their own. The one notification question (lib/features/notifications/
/// notification_prompt.dart, after the second finished picture) asks about every kind now, so here a
/// player whom iOS already allows is only registered at once.
Future<void> offerGiftNotifications(BuildContext context, ProviderContainer container) async {
  if (!container.read(platformCapsProvider).notifications || !supportsNotifications) return;
  await container.read(pushRegistrationProvider).refresh();
}
