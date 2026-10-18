# Usage analytics

Owner, 2026-10-17: the game sends usage analytics to **Appwrite Analytics**, and only there. No
third-party analytics, crash or ad SDK: events go through the app's one Appwrite client to our own
project (`fra.cloud.appwrite.io`, project `6acb4de5003e38d5ebd9`), Analytics property **Carden**
(tracking id `6ad3426500307dfae727`, domain carden.page). Players can turn it off in Settings >
Privacy > **Share usage data**.

Code: `lib/core/analytics.dart` (`AppAnalytics`, `ScreenObserver`, `screenNameFor`), wired in
`lib/app.dart` (attach), `lib/router.dart` (observers, page names) and
`lib/features/home/home_shell.dart` (tab switches). SDK: `appwrite` 27.2.0, the first release with
`Analytics`, `Tracking` and `TrackingObserver`.

## When nothing is sent

| Case | Why |
| --- | --- |
| Settings > Privacy > Share usage data is off | The player's choice. Off stops every event at once, the lifecycle events too, and stays off on every later launch (stored on the device with the other settings, `shareUsage`, on by default). |
| Debug and profile builds | Only release builds send (`kReleaseMode`), so development runs never reach the property. |
| QA runs (`CJW_QA=true`, every `tools/dev/qa-run.sh` run) | QA players stay out of the numbers as they stay out of the league. |

`--dart-define=CJW_ANALYTICS=true` sends from any build, QA runs and debug builds included. Use it
only for a deliberate check that events arrive (see "Verify"), never in a build for players.

## What an event carries

- A name in snake_case and at most 16 small props (Appwrite's limit), sent as text.
- Its page: the screen the player is on (`app://ios/game` on iPhone,
  `https://play.carden.page/game` on the web), so every event says where it happened. Screen names
  are readable and never contain ids (below).
- Never: names, emails, anything the player typed, friend codes, player or friend ids, message ids,
  pack codes or photo ids. Catalogue ids are fine (packs, live events, achievement families): they
  are the same for everyone. A player's own photos count as the pack `my-puzzles`.

Appwrite adds, on its side: country, region and city from the connection's IP address, the device,
operating system or browser from the user agent, and the session. Requests go out with the game's
session like every other call the app makes.

Call sites are one line through the helper:

```dart
AppAnalytics.event('pack_unlocked', {'pack': pack.id, 'paid': 'coins', 'price': 400});
```

## Screen views

`screen_view` with props `screen`, `trigger` (`push`, `pop`, `remove`, `replace`, `tab`) and
`previous`. Every navigator has its own `ScreenObserver` (a `TrackingObserver`): the root navigator
(`GoRouter(observers:)`) and each tab's (`StatefulShellBranch(observers:)`, with
`notifyRootObserver: false` so the root's observer sees only the root navigator). A tab that comes
back into view reports its top screen from `HomeShell` (`AppAnalytics.showTab`), because its
navigator does not change. Sheets, alerts, menus and the house ad screen are not screens: opening or
closing one sends nothing, and the screen under it is not counted again (their own events say
what happened in them).

| Path | Screen |
| --- | --- |
| `/welcome` | `welcome` |
| `/home` | `home` |
| `/library` | `library` |
| `/library/pack/:packId` | `pack` |
| `/events` | `quests` |
| `/social` | `social` |
| `/profile` | `profile` |
| `/profile/settings` | `settings` |
| `/profile/my-puzzles` | `my_puzzles` |
| `/play/:puzzleId` | `play_setup` |
| `/game/:puzzleId/:grid` | `game` |
| `/store` | `store` |
| `/wheel` | `wheel` |
| `/account` | `account` |
| `/auth/callback` | `sign_in_return` |
| `/player/:userId` | `player` |

A route added later is named after its last fixed part (`/join/:code` is `join`); add it to
`screenNames` in `lib/core/analytics.dart` when another name reads better.

## Automatic events

| Event | Props | When |
| --- | --- | --- |
| `screen_view` | `screen`, `trigger`, `previous` | A screen comes into view (above). |
| `app_backgrounded` | engagement time (seconds in the foreground since the last resume) | The app goes to the background (iPhone), the tab is hidden (web). |
| `app_foregrounded` | | Back in the foreground. |

## Game events

| Event | Props | Where it fires |
| --- | --- | --- |
| `onboarding_completed` | `firstBoard` (straight into the first board) | Welcome pages, Start playing (`onboarding_screen.dart`) |
| `first_board_completed` | `moves`, `seconds`, `stars` | The guided start's first board finished (`game_screen.dart`) |
| `feature_unlocked` | `feature` (`library`, `quickPlay`, `daily`, `streak`, `wheel`, `quests`, `promos`, `achievements`, `piggy`, `liveEvents`, `social`, `everything`, or a level unlock: `squares`, `triangles`, `hexagons`, `painting`, `giant`), `by` (`play`, `unlock_anyway`, `level`), `pictures` (pictures counted so far) | Guided start: what the picture just finished opened (`home_shell.dart`; a save loading with many pictures does not count), Unlock anyway (`guided_start.dart`); level unlocks on the finish card (`game_screen.dart`) |
| `settings_changed` | `setting` (`text_size`, `reduce_motion`, `increase_contrast`, `differentiate_without_colour`, `guided_start`), `value` | Settings > Accessibility (`SettingsNotifier.setAccessibility`), Settings > Guided start |
| `sign_up` | `method` (`email`, `apple`), `fromGuest` | Account created (or a guest linked to Apple) (`state/auth.dart`) |
| `sign_in` | `method` (`email`, `apple`, `apple_web`) | Signed in to an existing account |
| `sign_out` | | Signed out |
| `account_deleted` | | After the server deleted the account (`account_deletion.dart`) |
| `guest_merge` | `kept` (`guest`, `account`) | A guest save combined into an account (`merge_flow.dart`) |
| `puzzle_started` | `mode`, `board` (`4x5`), `cards`, `painting`, `giant`, `expand`, `daily`, `pack`, `resumed`, `first` | The board is dealt or resumed for the picture (`game_screen.dart`) |
| `puzzle_completed` | the board props, `stars`, `moves`, `par`, `seconds`, `hints`, `resumed`, `firstTime` | The last card locks |
| `puzzle_restarted` | the board props, `from` (`pause`, `replay`), `moves` (pause) | Pause > Shuffle and restart, or Replay on the finish card |
| `puzzle_discarded` | `from` (`game`, `setup`), `mode`, `board`, `cards`, `moves` (the game's adds the other board props) | Pause > Discard and pick a board, or Discard progress on the board picker |
| `quick_play` | `from` (`home`, `another`, `store`), `pool` (`fresh`, `improve`, `any`) | Home's Quick play, the board picker's Another picture, Store > Play a puzzle (a `/quick` link is a `link_opened`) |
| `daily_puzzle_opened` | `from` (`home`) | Home's picture of the day (a `/daily` link is a `link_opened`) |
| `tool_used` | `tool` (`hint`, `magic`, `peek`, `shuffle`, `gather`, `gather_undo`), `paid` (`stock`, `coins`, `free`), `cards` (cards moved), `giant` | The tool did something (`game_screen.dart`) |
| `level_up` | `level` | A finish took the player up a level |
| `pack_opened` | `pack` | A pack's page opens (once per visit) |
| `pack_unlocked` | `pack`, `paid` (`coins`, `tickets`, `early_giant`), `price`, `levelsToGo` (early giant) | Unlock on the pack page, or a Giant pack opened early (`giant_gate.dart`) |
| `store_opened` | `from` (the screen before), `vip` (opened at VIP) | The store opens (`store_screen.dart`) |
| `purchase_started` | `product`, `bundle` (`coins`, `tickets`, `helpers`, `vip`) | A bundle or VIP plan tapped: the App Store sheet opens (`state/purchases.dart`) |
| `purchase_completed` | `product`, `bundle`, `followed` (the player was watching; false for a renewal or a purchase finished in the background), and what it gave: `coins`, `tickets`, `hints`, `peeks`, `magics` (zeros left out) | The server added the purchase (once per transaction). The helper bundles keep their product ids `hints_5` / `hints_15` and give Peeks, Hints and Magic together, so `bundle` says `helpers` |
| `purchase_failed` | `product`, `paid` (paid but not added yet) | The App Store or the server failed |
| `purchase_canceled` | `product` | The App Store sheet was closed without paying |
| `purchase_restored` | `count` | Settings > Restore purchases finished |
| `vip_started` | `product` | A purchase made the player VIP |
| `daily_gift_claimed` | `day` (1-7), `streakRestored` | The daily gift (`daily_reward_sheet.dart`) |
| `achievement_claimed` | `achievement` (`family:tier`), `claimAll` | Profile > achievements |
| `quest_claimed` | `period` (`daily`, `weekly`), `quest` (its kind, the last part of its key), `claimAll` | Quests (`events_screen.dart`, `quest_rewards.dart`) |
| `quest_swapped` | `period`, `quest` (the kind swapped away), `to` (the kind it became), `swapsBefore` (swaps already made in that slot this period), `tickets` | A quest swapped for a ticket (Quests) |
| `wheel_spun` | `spin` (`x1`, `x5`), `tickets` (spent), `prize` (`coins`, `hints`, `peeks`, `magics`), `amount` (paid, the ×5 spin's five times over), `jackpot` | A spin of the Lucky Wheel, as the prize is drawn (`wheel_screen.dart`) |
| `wheel_odds_opened` | | Lucky Wheel > See odds |
| `piggy_opened` | `coins` (taken out), `capacity`, `full` | The piggy bank broken open (`piggy_sheet.dart`) |
| `piggy_upgraded` | `level` (the new size's step), `capacity` (the new size), `price` | A bigger piggy bank bought |
| `event_reward_claimed` | `event` | A live event's reward (Quests, Claim all) |
| `friend_added` | `fromLink` | Add friend by code, typed or from an `/add-friend` link |
| `inbox_opened` | | Social > Inbox shown (the segment, or a link to it) |
| `inbox_message_opened` | | A message opened |
| `inbox_message_claimed` | `coins`, `tickets`, `hints`, `peeks`, `magics` | A message's gift claimed |
| `inbox_button_tapped` | `to` (where its link leads) | A message's button |
| `house_ad_shown` | `creative`, `kind`, `rewarded` | A break offer or the rewarded card (`house_ads.dart`) |
| `house_ad_tapped` | `creative`, `rewarded`, `countdownDone`, or `banner` | Its button, or the VIP banner's Go VIP |
| `house_ad_rewarded` | `coins` | The rewarded card paid out |
| `review_prompt_shown` | `solved` | The app asked iOS for the rating prompt (iOS decides whether it shows) |
| `update_prompt_shown` | | "Update available" shown (`update_host.dart`) |
| `update_accepted` | | Its Update tapped |
| `link_opened` | `kind` (`page`, `overlay`, `action`), `to` (`pack`, `play`, `daily`, `quick`, `gift`, `add_friend`, ...) | A link from outside the app: iPhone links and the widget, a web visit's start address, a path the router has no page for |
| `shortcut_opened` | `daily` | The Home Screen quick action |
| `reminder_opened` | `daily` | A daily reminder tapped |
| `my_puzzle_uploaded` | `source` (`gallery`, `camera`) | A photo added in My Puzzles |
| `gift_sent` | `kind` (`ticket`, `coins`) | A friend gift the server accepted (Player > Send a gift, `friend_gifts.dart`; docs/friend-gifts.md) |
| `gift_claimed` | `kind` (`ticket`, `coins`) | A friend's gift claimed in the inbox (after its `inbox_message_claimed`) |
| `notification_prompt_shown` | `pictures` (finished so far) | The notification question shown (`notification_prompt.dart`; docs/notifications.md) |
| `notification_prompt_allowed` | `daily`, `events`, `gifts`, `messages` (the switches as left), `granted` (iOS's answer) | Its Allow, with at least one switch on |
| `notification_prompt_declined` | `allOff` (Allow with every switch off) | Its Not now, or Allow with every switch off |
| `push_permission` | `result` (`granted`, `denied`), `from` (`prompt`, `settings_reminders`, `settings_events`, `settings_gifts`, `settings_messages`) | The iOS notification prompt answered (`NotificationPermission.ask`) |
| `push_opened` | `kind` (`gift`, `message`: a message from Carden) | A notification from the server tapped (`app.dart`; its `/inbox?message=` link follows) |
| `coop_game_created` | `mode`, `board` (`4x5`), `cards`, `painting`, `giant` | Pause > Play together started a game on the board (`join_flow.dart`) |
| `coop_invite_shared` | `via` (`sheet`, `copy`), `players` | The invite went to the share sheet, or the link was copied (a browser without one) (`share_invite.dart`) |
| `coop_game_joined` | `freshInstall` (opened before the welcome pages), `platform` (`app`, `web`), `players` (with this one), `cards` | An invite link joined a game (`join_flow.dart`) |
| `coop_game_left` | `role` (`guest`, `host`), `players` | Leave game (`coop_controller.dart`) |
| `coop_game_ended` | `by` (`host`: the host's own End game for everyone; heard by the others: `host`, `host-left`, `idle`, `replaced`, `gone`), `players`, `board` (the game's board number) | The host ended it (`coop_controller.dart`), or a player's app heard it ended (`coop_host.dart`) |
| `coop_player_removed` | `players` (left after) | The host's Remove (`coop_controller.dart`) |
| `coop_next_board` | `board` (the game's board number), `cards`, `players` | The host handed the next board to the game (`coop_controller.dart`) |
| `coop_returned` | `from` (`launch`: the toast after a restart; `board`: the toast after leaving the board), `players` | Return to game (`coop_host.dart`, `game_screen.dart`) |

Play together's events (`coop_*`) never carry a game code, a game id or a player id.

## Adding an event

1. One line where the action really happens (after it succeeded), through
   `AppAnalytics.event('name_in_snake_case', {...})`.
2. Props: small values, at most 16, nothing personal (see "What an event carries").
3. Nothing that is already automatic: a new screen reports itself.
4. A row in the table above, and a line in `docs/privacy-policy.md` if it collects a new kind of
   data.

## Verify

1. Boot the QA simulator and run once with the force flag (a QA run, so the guest is purged):

   ```sh
   tools/dev/qa-run.sh run -d <udid> --dart-define=CJW_ANALYTICS=true
   tools/dev/qa-run.sh run -d chrome --dart-define=CJW_ANALYTICS=true
   # without Chrome: serve it and open http://localhost:8137 in any Chromium browser
   tools/dev/qa-run.sh run -d web-server --web-port 8137 --dart-define=CJW_ANALYTICS=true
   ```

   Play a few screens (Home, the Library, a picture), then quit (`q`), so the wrapper purges the
   guest. A scripted path works too: `tools/dev/qa-run.sh drive ... --dart-define=CJW_ANALYTICS=true`
   with any integration suite (`first_steps_test.dart` sends most of the game events).
2. Read the property with the Appwrite CLI from a folder holding an `appwrite.config.json` with
   `{"projectId":"6acb4de5003e38d5ebd9","endpoint":"https://fra.cloud.appwrite.io/v1"}`:

   ```sh
   appwrite analytics list-metrics --property-id 6ad3426500307dfae727 --date-range 1d --dimensions eventName --json
   appwrite analytics list-metrics --property-id 6ad3426500307dfae727 --date-range 1d --dimensions page --json
   appwrite analytics list-metrics --property-id 6ad3426500307dfae727 --date-range 1d --dimensions hostname --json
   ```

   Events appear within seconds. `hostname` is `ios` for the iPhone and the site's host for the web.
   The dimensions are country, region, city, browser, operatingSystem, device, screenSize, page,
   hostname, entryPage, exitPage and eventName; props are stored with each event but are not a
   dimension of `list-metrics`.

Unit tests: `test/analytics_test.dart` (the switch, debug builds, the QA rule, props, and screen
views from every navigator of a router shaped like the app's).
