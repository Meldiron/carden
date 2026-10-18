import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics.dart';
import '../../core/app_links.dart';
import '../../core/haptics.dart';
import '../../core/sfx.dart';
import '../../core/theme/tokens.dart';
import '../../state/inbox.dart';
import '../../state/profile.dart';
import '../../widgets/glass.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';
import '../links/deep_links.dart';
import 'friend_gifts.dart';

/// Social > Inbox (owner, 2026-10-16): messages from Carden to this player, newest first. A row
/// shows the subject, when it came, the start of the text and a reward still waiting; an unopened
/// message has a dot (and the Social tab too). A row swipes left to delete it, after asking (VoiceOver:
/// the row's "Delete message" action); the message sheet itself has no delete or close buttons
/// (owner, 2026-10-18).
class InboxList extends ConsumerWidget {
  const InboxList({super.key});

  static const _dividerIndent = 30.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final loaded = ref.watch(inboxMessagesProvider);
    final items = ref.watch(inboxProvider);
    final side = 20 + pageInsetOf(context, maxWidth: PageWidth.reading);
    final Widget body;
    if (!loaded.hasValue && loaded.isLoading) {
      body = const Padding(padding: EdgeInsets.all(30), child: Loader());
    } else if (loaded.hasError && !loaded.hasValue) {
      body = EmptyState(
        icon: AppIcons.signal,
        title: 'Messages could not load',
        message: 'Check your connection and try again.',
        action: BigButton(label: 'Try again', kind: ButtonKind.secondary, height: 44, expand: false, onTap: () => ref.invalidate(inboxMessagesProvider)),
      );
    } else if (items.isEmpty) {
      body = const EmptyState(icon: AppIcons.mail, title: 'No messages', message: 'Messages from Carden show here, now and then with a small gift.');
    } else {
      body = SoftCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final (i, item) in items.indexed) ...[
              if (i > 0) Divider(height: 1, thickness: 1, indent: _dividerIndent, color: c.stroke),
              Dismissible(
                key: ValueKey('message-${item.message.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: c.danger,
                  child: const Icon(AppIcons.trash, color: Colors.white),
                ),
                confirmDismiss: (_) => confirmDeleteMessage(context, item),
                onDismissed: (_) => ref.read(profileProvider.notifier).deleteMessage(item.message.id),
                child: _MessageRow(
                  item: item,
                  onDelete: () async {
                    if (!await confirmDeleteMessage(context, item)) return;
                    ref.read(profileProvider.notifier).deleteMessage(item.message.id);
                  },
                ),
              ),
            ],
          ],
        ),
      );
    }
    return RefreshIndicator.adaptive(
      onRefresh: () => ref.refresh(inboxMessagesProvider.future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(side, 0, side, GlassTabBar.scrollEndPadding(context)),
        children: [body],
      ),
    );
  }
}

/// Asks before a message is deleted (it leaves the inbox on every device).
Future<bool> confirmDeleteMessage(BuildContext context, InboxItem item) => showAppAlert(
      context,
      title: 'Delete message?',
      message: item.claimable ? 'Its gift has not been claimed yet. The message leaves your inbox on every device.' : 'It leaves your inbox on every device.',
      confirmLabel: 'Delete',
      destructive: true,
    );

/// "Today, 21:05" in the device's own clock format.
String _when(BuildContext context, DateTime local) => formatMessageDate(local, TimeOfDay.fromDateTime(local).format(context));

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.item, required this.onDelete});
  final InboxItem item;

  /// VoiceOver's "Delete message" (asks first), what the swipe does.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = item.message;
    final unseen = !item.seen;
    return Semantics(
      button: true,
      label: [if (unseen) 'New', m.subject, _when(context, m.sentAt), if (item.claimable) 'Gift to claim'].join(', '),
      customSemanticsActions: {const CustomSemanticsAction(label: 'Delete message'): onDelete},
      excludeSemantics: true,
      child: Pressable(
        key: ValueKey('message-row-${m.id}'),
        scale: 0.99,
        onTap: () => showMessageSheet(context, m.id),
        child: Container(
          color: c.card,
          padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // The dot of a message not opened yet (with the bold subject, so it never rests on colour).
              SizedBox(
                width: 20,
                child: unseen ? Center(child: Container(width: 9, height: 9, decoration: BoxDecoration(color: context.accent, shape: BoxShape.circle))) : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(m.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: TypeSize.body, fontWeight: unseen ? FontWeight.w700 : FontWeight.w500, color: c.textPrimary)),
                        ),
                        const SizedBox(width: 8),
                        // A gift still waiting: a small gift mark before the time.
                        if (item.claimable) ...[Icon(AppIcons.gift, size: 13, color: context.accent), const SizedBox(width: 4)],
                        Text(_when(context, m.sentAt), style: TextStyle(fontSize: TypeSize.caption, color: c.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(m.body, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: TypeSize.footnote, color: c.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(AppIcons.chevronRight, size: 15, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// A message's gift, in the sheet's grouped style (owner, 2026-10-17: the cobalt box with chips and
/// a green tick looked heavy): who it is from (Carden's gift mark or the friend's avatar) and the
/// amounts, each with its currency mark. The Claim button under it is the sheet's main action;
/// once claimed, the card ends in a quiet check and "Claimed".
class _GiftCard extends StatelessWidget {
  const _GiftCard({required this.item});
  final InboxItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final claimed = item.claimed;
    final m = item.message;
    return SoftCard(
      key: const ValueKey('message-gift'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              children: [
                // A friend's gift shows the friend's avatar; Carden's, the gift mark.
                if (m.fromFriend)
                  AvatarCircle(key: const ValueKey('message-gift-avatar'), avatarKey: m.fromAvatar ?? 'fox', size: IconTile.medium)
                else
                  const IconTile(icon: AppIcons.gift, size: IconTile.medium),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('A gift from ${m.sender}', style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w500, color: c.textSecondary)),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: [
                          for (final (currency, amount) in m.reward)
                            Amount(currency: currency, value: amount, size: 18, fontSize: TypeSize.title3, weight: FontWeight.w700),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (claimed) ...[
            Divider(height: 1, thickness: 0.5, indent: 14, color: c.stroke),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
              child: Row(
                key: const ValueKey('message-claimed'),
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c.accentTint),
                    child: Icon(AppIcons.checkmarkAlt, size: 13, color: context.accent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Claimed · in your balance', style: TextStyle(fontSize: TypeSize.footnote, fontWeight: FontWeight.w600, color: c.textSecondary))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A message on its own: subject, when it came, the whole text, its gift and one main action:
/// Claim while the gift waits, else the message's button (a place in the app), pinned under the text
/// while a long message scrolls. No buttons in the header (owner, 2026-10-18): the sheet closes with a
/// drag down or a tap above it, and a message is deleted by swiping its row in the list. Opening it
/// marks it seen.
Future<void> showMessageSheet(BuildContext context, String id) => showAppSheet(context, scrollable: true, builder: (_) => _MessageSheet(id: id));

class _MessageSheet extends ConsumerStatefulWidget {
  const _MessageSheet({required this.id});
  final String id;

  @override
  ConsumerState<_MessageSheet> createState() => _MessageSheetState();
}

class _MessageSheetState extends ConsumerState<_MessageSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(profileProvider.notifier).markMessageSeen(widget.id);
    });
    AppAnalytics.event('inbox_message_opened');
  }

  Future<void> _claim(InboxMessage m) async {
    // A gift past its time is gone (the sheet closes it a moment later on its own).
    if (m.expiredAt(DateTime.now())) {
      showToast(context, 'This gift has expired', icon: AppIcons.clock);
      ref.invalidate(inboxProvider);
      return;
    }
    final paid = ref.read(profileProvider.notifier).claimMessage(m.id, coins: m.coins, tickets: m.tickets, hints: m.hints, peeks: m.peeks, magics: m.magics);
    if (!paid) return;
    AppAnalytics.event('inbox_message_claimed', {'coins': m.coins, 'tickets': m.tickets, 'hints': m.hints, 'peeks': m.peeks, 'magics': m.magics});
    if (m.fromFriend) AppAnalytics.event('gift_claimed', {'kind': m.tickets > 0 ? 'ticket' : 'coins'});
    Sfx.instance.coin();
    Haptics.success();
    showToast(context, 'Added ${_words(m)}', icon: AppIcons.gift);
    // A friend's gift: the moment to offer gift notifications (asked once).
    if (m.fromFriend) await offerGiftNotifications(context, ProviderScope.containerOf(context, listen: false));
  }

  /// "500 coins, 2 tickets".
  static String _words(InboxMessage m) => [for (final (currency, amount) in m.reward) '${formatCount(amount)} ${_unit(currency, amount)}'].join(', ');

  static String _unit(Currency c, int n) => switch (c) {
        Currency.coins => n == 1 ? 'coin' : 'coins',
        Currency.tickets => n == 1 ? 'ticket' : 'tickets',
        Currency.hints => n == 1 ? 'hint' : 'hints',
        Currency.peeks => n == 1 ? 'Peek' : 'Peeks',
        Currency.magics => 'Magic',
      };

  void _openLink(AppLink link) {
    final deepLinks = ref.read(deepLinksProvider);
    Navigator.of(context).pop();
    AppAnalytics.event('inbox_button_tapped', {'to': DeepLinks.linkTarget(link.path)});
    deepLinks.show(link);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final item = ref.watch(inboxProvider).where((i) => i.message.id == widget.id).firstOrNull;
    // Deleted or expired meanwhile: nothing left to show.
    if (item == null) {
      return const SheetScrollBody(
        child: Padding(padding: EdgeInsets.all(30), child: EmptyState(icon: AppIcons.mail, title: 'Message not available', message: 'It may have expired or been deleted.')),
      );
    }
    final m = item.message;
    final link = m.ctaLink == null ? null : AppLink.parse(Uri.parse(m.ctaLink!));
    // One gift kind claims with its amount ("Claim [coin] 500"); several say "Claim gift".
    final reward = m.reward;
    final claim = !item.claimable
        ? null
        : reward.length == 1
            ? BigButton.cost(key: const ValueKey('message-claim'), label: 'Claim', currency: reward.first.$1, amount: reward.first.$2, onTap: () => _claim(m))
            : BigButton(key: const ValueKey('message-claim'), label: 'Claim gift', icon: AppIcons.gift, onTap: () => _claim(m));
    return SheetScrollBody(
      key: ValueKey('message-sheet-${m.id}'),
      // One main action: Claim while the gift waits (the message's button under it, tinted), then the
      // message's button. They stay in view under a long message.
      footer: claim == null && link == null
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?claim,
                  if (link != null) ...[
                    if (claim != null) const SizedBox(height: 10),
                    BigButton(key: const ValueKey('message-cta'), label: m.ctaLabel ?? 'Open', kind: claim == null ? ButtonKind.primary : ButtonKind.secondary, onTap: () => _openLink(link)),
                  ],
                ],
              ),
            ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, claim == null && link == null ? 20 : 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHeader(title: m.subject, subtitle: _when(context, m.sentAt)),
            const SizedBox(height: 14),
            Text(m.body, style: TextStyle(fontSize: TypeSize.callout, height: 1.45, color: c.textPrimary)),
            if (m.expiresAt != null) ...[
              const SizedBox(height: 10),
              Text('In your inbox until ${_when(context, m.expiresAt!)}', style: TextStyle(fontSize: TypeSize.footnote, color: c.textTertiary)),
            ],
            if (m.hasReward) ...[
              const SizedBox(height: 18),
              _GiftCard(item: item),
            ],
          ],
        ),
      ),
    );
  }
}
