import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics.dart';
import '../core/appwrite.dart';
import '../core/platform.dart';
import '../core/push.dart';
import '../core/reminders.dart';
import 'auth.dart';
import 'settings.dart';

/// The Appwrite Messaging providers (Apple key 2QJPJFW8JW, team C24QP73SQM): `apns` sends through
/// Apple's production service (TestFlight and App Store builds), `apns-sandbox` through the
/// development one (simulators, debug and device builds signed for development). A device token
/// works only with the service of its build's `aps-environment`.
class PushProviders {
  PushProviders._();
  static const production = 'apns';
  static const sandbox = 'apns-sandbox';

  /// The provider for a build whose provisioning profile says [environment].
  static String forEnvironment(String? environment) => environment == 'development' ? sandbox : production;
}

/// Appwrite Messaging topics this iPhone's push target joins (docs/notifications.md). Both have
/// `subscribe: users`, so a player subscribes their own target; builds before 2.0.0 (128) never
/// subscribe, so they get no message notifications and every gift notification.
class PushTopics {
  PushTopics._();

  /// Settings > Messages from Carden: `tools/dev/inbox.py` pushes a message to the subscribers of
  /// this topic (everyone), or to the subscribed targets of its players (one player, a label).
  static const messages = 'carden-messages';

  /// A target that stays only for messages from Carden (Settings > Gifts from friends off): the
  /// gift push (`/gift/send` on `api`) leaves out the targets in this topic.
  static const giftsOff = 'gifts-off';

  /// The topics a target belongs in for these switches (a target exists only when one is on).
  static Set<String> wanted({required bool gifts, required bool messages}) => {
        if (messages) PushTopics.messages,
        if (messages && !gifts) giftsOff,
      };

  /// One subscription per target and topic, so its id comes from both: a second try answers 409,
  /// and turning a switch off deletes it without a lookup (the client cannot list subscribers).
  static String subscriberId(String topic, String targetId) => '${topic == messages ? 'm' : 'g'}$targetId';
}

/// What a tapped or received notification is about, from its link: `message` for a message from
/// Carden (`tools/dev/inbox.py` adds `from=carden` to its `/inbox?message=` link), `gift` otherwise.
String pushKindOf(String? link) => link != null && Uri.tryParse(link)?.queryParameters['from'] == 'carden' ? 'message' : 'gift';

/// Settings > Gifts from friends: notifications when a friend sends a gift, stored on the device.
/// On unless the player turned it off; nothing arrives until iOS allows notifications.
class GiftNotificationsNotifier extends Notifier<bool> {
  static const _key = 'giftNotifications';

  @override
  bool build() => ref.watch(localStoreProvider).getText(_key) != 'off';

  void set(bool on) {
    ref.read(localStoreProvider).setText(_key, on ? 'on' : 'off');
    state = on;
  }
}

final giftNotificationsProvider = NotifierProvider<GiftNotificationsNotifier, bool>(GiftNotificationsNotifier.new);

/// Settings > Messages from Carden: a notification when Carden sends the player a message (Social >
/// Inbox), stored on the device. Messages can carry news and offers, so this is off until the player
/// turns it on: the switch, or Allow in the notification question, which names it (guideline 4.5.4).
class MessageNotificationsNotifier extends Notifier<bool> {
  static const _key = 'messageNotifications';

  @override
  bool build() => ref.watch(localStoreProvider).getText(_key) == 'on';

  void set(bool on) {
    ref.read(localStoreProvider).setText(_key, on ? 'on' : 'off');
    state = on;
  }
}

final messageNotificationsProvider = NotifierProvider<MessageNotificationsNotifier, bool>(MessageNotificationsNotifier.new);

/// Whether iOS allows Carden's notifications (read again when the app comes back to the front).
final notificationsAllowedProvider = FutureProvider<bool>((ref) async => supportsNotifications && await ReminderChannel.status() == ReminderPermission.granted);

/// The iOS permission, asked at most once (the real prompt; quietly in integration runs, see
/// [ReminderChannel.quietNow]). [from] names the place that asked, for `push_permission`.
class NotificationPermission {
  NotificationPermission._();

  static Future<bool> ask({required String from}) async {
    if (!supportsNotifications) return false;
    final status = await ReminderChannel.status();
    if (status != ReminderPermission.notDetermined) return status == ReminderPermission.granted;
    final granted = await ReminderChannel.request(quiet: ReminderChannel.quietNow);
    AppAnalytics.event('push_permission', {'result': granted ? 'granted' : 'denied', 'from': from});
    return granted;
  }
}

/// Push targets of the signed-in Appwrite user. A target made through the account belongs to the
/// session (Appwrite deletes it with the session, and a session keeps one per provider, so a new
/// token updates it); a device token belongs to one user at a time.
abstract class PushTargets {
  /// Registers [token] for the current session and returns the target's id.
  Future<String> create(String token, String providerId);
  Future<void> update(String targetId, String token);
  Future<void> delete(String targetId);
}

class AccountPushTargets implements PushTargets {
  AccountPushTargets(this._account);
  final Account _account;

  @override
  Future<String> create(String token, String providerId) async =>
      (await _account.createPushTarget(targetId: ID.unique(), identifier: token, providerId: providerId)).$id;

  @override
  Future<void> update(String targetId, String token) => _account.updatePushTarget(targetId: targetId, identifier: token);

  @override
  Future<void> delete(String targetId) => _account.deletePushTarget(targetId: targetId);
}

final pushTargetsProvider = Provider<PushTargets>((ref) => AccountPushTargets(ref.watch(accountProvider)));

/// This iPhone's target in Appwrite Messaging topics ([PushTopics]). Deleting a target deletes
/// its subscriptions with it.
abstract class PushSubscriptions {
  Future<void> subscribe(String topicId, String subscriberId, String targetId);
  Future<void> unsubscribe(String topicId, String subscriberId);
}

class MessagingPushSubscriptions implements PushSubscriptions {
  MessagingPushSubscriptions(this._messaging);
  final Messaging _messaging;

  @override
  Future<void> subscribe(String topicId, String subscriberId, String targetId) =>
      _messaging.createSubscriber(topicId: topicId, subscriberId: subscriberId, targetId: targetId);

  @override
  Future<void> unsubscribe(String topicId, String subscriberId) => _messaging.deleteSubscriber(topicId: topicId, subscriberId: subscriberId);
}

final pushSubscriptionsProvider = Provider<PushSubscriptions>((ref) => MessagingPushSubscriptions(Messaging(ref.watch(appwriteClientProvider))));

/// Keeps this iPhone registered for server notifications (docs/notifications.md): the device token
/// from iOS becomes an Appwrite push target of the signed-in player, again whenever the token or the
/// player changes (sign-in, another account, a guest save merged into an account: each of those
/// starts a new session, and Appwrite dropped the old session's target with it). Only while iOS
/// allows notifications and Settings > Gifts from friends or Messages from Carden is on; the target
/// then joins the topics those switches ask for ([PushTopics.wanted]).
class PushRegistration {
  PushRegistration(this._ref);
  final Ref _ref;

  static const _storeKey = 'pushTarget';

  String? _token;
  String? _environment;

  /// `<user>|<token>|<provider>` last registered by this process: one request per change.
  String? _registered;

  bool get _wanted => _ref.read(giftNotificationsProvider) || _ref.read(messageNotificationsProvider);

  /// Starts listening for tokens and taps; [onOpen] gets the link of a tapped notification and
  /// [onReceive] a notification that arrived while the game was open.
  Future<void> start({required void Function(String link) onOpen, required void Function(PushNote note) onReceive}) async {
    if (!supportsNotifications) return;
    _environment = await PushChannel.environment();
    await PushChannel.listen(onToken: onToken, onOpen: onOpen, onReceive: onReceive);
    await refresh();
  }

  /// Asks iOS for the token when notifications are allowed and wanted (start, resume, after the
  /// permission question, a switch turned on). Without permission nothing is asked and nothing is
  /// registered. A token this process already has is registered at once (the topics may have changed).
  Future<void> refresh() async {
    if (!supportsNotifications || !_wanted) return;
    if (await ReminderChannel.status() != ReminderPermission.granted) return;
    await PushChannel.register();
    if (_token != null) await sync();
  }

  /// A device token from iOS (also the same one again on every launch).
  Future<void> onToken(String token, {String? environment}) async {
    _token = token;
    if (environment != null) _environment = environment;
    await sync();
  }

  /// Registrations run one after another (a token and a sign-in can arrive together).
  Future<void> _queue = Future.value();

  /// Registers the current token for the current player, unless that is already done, and puts the
  /// target in the topics the switches ask for.
  Future<void> sync() => _queue = _queue.then((_) => _syncOnce());

  Future<void> _syncOnce() async {
    final userId = _ref.read(currentUserIdProvider);
    final token = _token;
    if (userId == null || userId == 'local' || token == null || !_wanted) return;
    final provider = PushProviders.forEnvironment(_environment);
    final key = '$userId|$token|$provider';
    final store = _ref.read(localStoreProvider);
    if (_registered != key) {
      final targets = _ref.read(pushTargetsProvider);
      try {
        final targetId = await targets.create(token, provider);
        // A new target is in no topic yet.
        await store.setJson(_storeKey, {'userId': userId, 'targetId': targetId, 'topics': <String>[]});
        _registered = key;
      } on AppwriteException catch (e) {
        // 409: the token is already a target, of an earlier session of this player (update it) or
        // of a player whose session this device lost (nothing to do until that session ends).
        final saved = store.getJson(_storeKey);
        if (e.code == 409 && saved?['userId'] == userId && saved?['targetId'] is String) {
          try {
            await targets.update(saved!['targetId'] as String, token);
            _registered = key;
          } catch (e2) {
            debugPrint('push target update failed: $e2');
            return;
          }
        } else {
          debugPrint('push target failed: ${e.code} ${e.message}');
          return;
        }
      } catch (e) {
        debugPrint('push target failed: $e');
        return;
      }
    }
    await _syncTopics(userId);
  }

  /// Joins and leaves topics until the saved target is in exactly [PushTopics.wanted]. What is
  /// done is saved with the target, so a launch with nothing changed sends nothing.
  Future<void> _syncTopics(String userId) async {
    final store = _ref.read(localStoreProvider);
    final saved = store.getJson(_storeKey);
    final targetId = saved?['targetId'];
    if (saved == null || saved['userId'] != userId || targetId is! String) return;
    final have = {for (final t in (saved['topics'] as List?) ?? const []) '$t'};
    final want = PushTopics.wanted(gifts: _ref.read(giftNotificationsProvider), messages: _ref.read(messageNotificationsProvider));
    if (have.length == want.length && have.containsAll(want)) return;
    final subscriptions = _ref.read(pushSubscriptionsProvider);
    for (final topic in want.difference(have)) {
      try {
        await subscriptions.subscribe(topic, PushTopics.subscriberId(topic, targetId), targetId);
        have.add(topic);
      } on AppwriteException catch (e) {
        // 409: already subscribed (an earlier run whose answer was lost).
        if (e.code == 409) {
          have.add(topic);
        } else {
          debugPrint('push topic $topic failed: ${e.code} ${e.message}');
        }
      } catch (e) {
        debugPrint('push topic $topic failed: $e');
      }
    }
    for (final topic in have.difference(want).toList()) {
      try {
        await subscriptions.unsubscribe(topic, PushTopics.subscriberId(topic, targetId));
        have.remove(topic);
      } on AppwriteException catch (e) {
        if (e.code == 404) {
          have.remove(topic);
        } else {
          debugPrint('push topic $topic leave failed: ${e.code} ${e.message}');
        }
      } catch (e) {
        debugPrint('push topic $topic leave failed: $e');
      }
    }
    await store.setJson(_storeKey, {...saved, 'topics': have.toList()..sort()});
  }

  /// Settings > Gifts from friends.
  Future<bool> setGifts(bool on) => _set(() => _ref.read(giftNotificationsProvider.notifier).set(on), on, from: 'settings_gifts');

  /// Settings > Messages from Carden.
  Future<bool> setMessages(bool on) => _set(() => _ref.read(messageNotificationsProvider.notifier).set(on), on, from: 'settings_messages');

  /// Gifts from friends on.
  Future<bool> enable() => setGifts(true);

  /// Gifts from friends off.
  Future<void> disable() => setGifts(false);

  /// A switch on: asks iOS the first time and registers; false when iOS does not allow
  /// notifications. A switch off: the target leaves the topic, or goes when nothing wants it.
  Future<bool> _set(void Function() write, bool on, {required String from}) async {
    write();
    if (!on) {
      if (_wanted) {
        await sync();
      } else {
        await _removeTarget();
      }
      return true;
    }
    final granted = await NotificationPermission.ask(from: from);
    _ref.invalidate(notificationsAllowedProvider);
    if (!granted) return false;
    await refresh();
    return true;
  }

  /// The notification question's answer: both switches at once, without asking iOS (the question
  /// asks it). Registers when iOS allows notifications.
  Future<void> apply({required bool gifts, required bool messages}) async {
    _ref.read(giftNotificationsProvider.notifier).set(gifts);
    _ref.read(messageNotificationsProvider.notifier).set(messages);
    if (_wanted) {
      await refresh();
    } else {
      await _removeTarget();
    }
  }

  /// Neither switch is on: this device's target goes (and its topics with it), so no notification
  /// from the server reaches it.
  Future<void> _removeTarget() async {
    await _queue;
    _registered = null;
    final store = _ref.read(localStoreProvider);
    final saved = store.getJson(_storeKey);
    if (saved == null) return;
    if (saved['userId'] == _ref.read(currentUserIdProvider) && saved['targetId'] is String) {
      try {
        await _ref.read(pushTargetsProvider).delete(saved['targetId'] as String);
      } on AppwriteException catch (e) {
        if (e.code != 404) debugPrint('push target delete failed: $e');
      } catch (e) {
        debugPrint('push target delete failed: $e');
      }
    }
    await store.remove(_storeKey);
  }
}

final pushRegistrationProvider = Provider<PushRegistration>((ref) {
  final registration = PushRegistration(ref);
  // Sign-in, another account, a merge: the new session gets this device's token.
  ref.listen<String?>(currentUserIdProvider, (previous, next) {
    if (previous != next) registration.sync();
  });
  return registration;
});
