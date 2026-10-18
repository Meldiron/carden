import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics.dart';
import '../data/repositories.dart';
import 'auth.dart';
import 'first_steps.dart';
import 'merge_flow.dart';
import 'profile.dart';
import 'progress.dart';
import 'reminders.dart';
import 'settings.dart';
import 'social.dart';
import 'sync.dart';

/// Account > Delete account (App Store guideline 5.1.1(v)). Two steps so the screen can tell the
/// player before the app starts over: [deleteOnServer] removes the account and everything stored
/// for it (`/account/delete` on the `api` function), [startOver] gives this device a fresh start as a new
/// guest on the welcome screens.
class AccountDeletion {
  AccountDeletion(this._ref);
  final Ref _ref;

  /// The account's save as the sync stores it on the device (`SyncController._key`).
  static List<String> deviceSaveKeys(String userId) => ['sync.v1.$userId.ops', 'sync.v1.$userId.rows'];

  /// Deletes the signed-in player's account on the server. [appleAuthorizationCode] (a fresh Sign in
  /// with Apple authorization) lets the server revoke the player's Apple tokens. Throws when the
  /// server could not delete it; nothing on the device has changed then.
  Future<AccountDeletionResult> deleteOnServer({String? appleAuthorizationCode}) =>
      _ref.read(accountDeletionRepositoryProvider).delete(appleAuthorizationCode: appleAuthorizationCode);

  /// After [deleteOnServer]: a new guest, the deleted player's save and device flags gone, and the
  /// welcome screens next (the router follows `onboarded`). Device settings (theme, sound) stay.
  Future<void> startOver() async {
    AppAnalytics.event('account_deleted');
    final deletedId = _ref.read(currentUserIdProvider);
    final store = _ref.read(localStoreProvider);
    await _ref.read(remindersProvider).disable();
    final guest = await _ref.read(authProvider.notifier).startOverAfterDeletion();
    // The sync stores the old save once more when it switches to the guest; drop it after that.
    await _ref.read(syncProvider.notifier).attach(guest);
    if (deletedId != null) {
      for (final key in deviceSaveKeys(deletedId)) {
        await store.remove(key);
      }
      // On the iPhone the copy of the rows is a file (lib/data/sync/device_copy.dart).
      await _ref.read(syncRowsProvider).remove(deletedId);
    }
    await store.remove(SaveMerge.pendingKey);
    await store.remove(FirstSteps.storeKey);
    store
      ..onboarded = false
      ..tutorialSeen = false
      ..giftClaimDays = 0
      ..reminderOfferShown = false
      ..lifetimeCompletions = 0
      ..completionsSinceAd = 0
      ..lastInterstitialAt = null
      ..lastRewardedAt = null;
    _ref
      ..invalidate(firstStepsProvider)
      ..invalidate(profileProvider)
      ..invalidate(progressProvider)
      ..invalidate(friendsProvider)
      ..invalidate(myPuzzlesProvider)
      ..invalidate(myPuzzleCountProvider)
      ..invalidate(eventProgressProvider)
      ..invalidate(leaderboardProvider)
      ..invalidate(leaderboardRankProvider)
      ..invalidate(settingsProvider);
  }
}

final accountDeletionProvider = Provider<AccountDeletion>((ref) => AccountDeletion(ref));
