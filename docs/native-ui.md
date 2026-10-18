# Native UI on iOS 26 and 27

How the app's chrome (tab bar, headers, dialogs, sheets) is built so it reads
as native on iOS 26+ while still working on iOS 15 and on the simulator.

## Decision

**First-party Cupertino widgets for every modal, plus a small in-house glass
material (`lib/widgets/glass.dart`) for bars and sheets. No package.**

What is used where:

| Component | Implementation |
| --- | --- |
| Confirmations, destructive prompts, text-entry prompts (rename, friend code) | `showAppAlert` in `lib/widgets/ui.dart`: the iOS 26 alert drawn in Flutter. A glass card (28pt radius; in dark mode the elevated tint, one level above sheets, with a 50% dim) with a centred title and message and capsule actions (48pt): Cancel neutral, the action tinted cobalt, or red when destructive (never the default look). Side by side when both labels fit, otherwise stacked with the action on top. Every label names its action (never "OK"). Text fields inside use `AlertTextField`. |
| Menus of actions (a player's ..., Add a photo, a photo's ...) | `showAppActionSheet` in `lib/widgets/ui.dart`: the alert's glass card at the bottom of the screen, an optional title, the choices as capsules (cobalt, red when destructive) and Cancel last. |
| Content-sized sheets (pause menu, daily gift, piggy bank, tier unlock, pack access, avatar picker, credits) | `showAppSheet` in `lib/widgets/ui.dart`: a modal bottom sheet rendered on `GlassSheet` (28pt top radius, grabber, 32% dim, blur + saturation + tint, home-indicator inset). This is what iOS 26 partial-height sheets look like. Every sheet starts with `SheetHeader` (20pt title, 15pt subtitle): left-aligned for lists and choices, centred for sheets that lead with a picture or an icon. |
| Full-height modals (Store, Wheel, Account) | `CupertinoSheetRoute` via `_SheetPage` in `lib/router.dart`: the real stacked-sheet presentation. The sheet stops below the status bar, the page behind scales back, drag down to dismiss. |
| Bottom tab bar | `GlassTabBar`: floating capsule inset 16pt from the edges, hovering above the home indicator, blurred content underneath, soft tinted pill behind the selected tab (iOS 26 shape). Icons and labels unchanged. `Scaffold.extendBody: true` so pages scroll beneath it. |
| Tab headers (Home, Library, Events, Profile) | `GlassSliverHeader` / `HeaderBar`: pinned, transparent while the list is at the top, glass with a hairline once content scrolls under. Same rule as `CupertinoNavigationBar.automaticBackgroundVisibility`. |
| App bars on pushed pages (Settings, Store, Account, My Puzzles, Difficulty, Wheel) | `GlassAppBar` with `extendBodyBehindAppBar: true`. Transparent at rest, glass when scrolled under. |
| Pack cover | `SliverAppBar` whose collapsed state turns into glass over the blurred top of the cover. |
| Segmented switches (Social tabs, Account form, Settings > Theme) | `AppSegmentedControl` in `lib/widgets/ui.dart`: the iOS 26 shape drawn in Flutter. Capsule track in the system tertiary fill, glass thumb (white in light, light grey in dark, brighter rim on its upper edge) that springs to the segment, stretches while it travels, lifts under the finger and can be dragged. Use it for every new switch. |
| Wide windows (the web on a tablet or desktop) | `lib/widgets/adaptive.dart`: from 900 px the floating tab bar becomes `WideTopBar` (the iPadOS 26 top tab bar: tabs in a glass capsule in the middle of a glass bar), `showAppSheet` opens a centred panel (an iPad form sheet) and the full-height modals a centred page sheet (`PanelRoute`). Details in `docs/web.md`, "Layout". |
| Toasts | `showToast` in `lib/widgets/ui.dart`: a glass capsule that drops in under the status bar, above every screen, sheet and alert; one at a time, tap or swipe up to close. |

## Why not a package

Evaluated on 2026-10-11:

- **`cupertino_native`** (serverpod, 0.1.1): three releases, all 13 months old,
  self-described "more of a proof of concept than a full package", built
  against the Xcode 26 beta. Provides a tab bar, buttons, slider, switch,
  segmented control and popup button through platform views; no navigation
  bar, no sheets, scroll-view integration "still under investigation".
  A platform-view tab bar would also sit outside the Flutter tree: no
  go_router shell integration, the daily-gift badge and press feedback would
  have to be rebuilt in Swift, and the simulator screenshot flow could not
  drive it through `WidgetTester`.
- **`liquid_glass_native`** (0.3.1, unverified publisher, ~180 downloads):
  SwiftUI glass tab bar, nav bar, buttons and sheets via platform views with
  fallbacks below iOS 26. Same platform-view objections; too young to pin a
  shipping app to.
- **`liquid_glass_renderer`** (0.2.0-dev.4): pure-Flutter refraction shader.
  Marked "EXPERIMENTAL - USE WITH CAUTION", Impeller only, re-renders every
  frame when anything under it moves, known memory spikes while animating.
  The board animates constantly, so the bars would pay that cost on every
  frame.
- **Flutter 3.47 Cupertino**: `CupertinoAlertDialog`, `CupertinoActionSheet`,
  `CupertinoSheetRoute`, `CupertinoNavigationBar` and `CupertinoTabBar` all
  blur a translucent background (`BackdropFilter`), which is the pre-26
  system material. Core Cupertino has no Liquid Glass material yet
  (tracked in flutter/flutter#170310), so a bar built from first-party parts
  and a bar built from `GlassSurface` look the same; ours keeps the app's
  layout (avatar, level, currency pills) and tokens.

## What "glass" means here

`GlassSurface` = `BackdropFilter(blur 24, saturation 1.35)` + surface tint
(white 72% in light, `#1C1C22` 62% in dark) + 0.5pt hairline. That is the
recipe of `UIBlurEffect.systemChromeMaterial`: the look of bars up to iOS 18
and what iOS 26 falls back to when Reduce Transparency is on. True Liquid
Glass refraction and specular edges are not reachable from Dart; if that
ever matters, the tab bar is the one place where a platform view would pay
off, and `GlassTabBar` can be swapped without touching the pages.

The material degrades to exactly the same pixels on iOS 15 and on the
simulator, because it is all drawn by Flutter.

## Rules kept

- No emoji, no gradients; the only colour in chrome is the cobalt accent on
  the selected tab and default buttons.
- Alerts keep platform order: Cancel left, confirm right; stacked, the action on top and Cancel last.
- Pages that scroll under a bar pad their first item with
  `MediaQuery.paddingOf(context).top`. Every scrollable page ends with
  `GlassTabBar.scrollEndPadding(context)`: the floating tab bar's height plus
  a margin under the tab bar, otherwise the home-indicator inset plus a
  margin, so the last row is never hidden.

## Haptics

Gentle and few, iOS kinds only, through `Haptics` in `lib/core/haptics.dart` (owner, 2026-10-18:
"subtle, gentle, but in more places"). Never `HapticFeedback` directly, never a heavy impact, never a
long pattern. Settings > Haptics turns them off (`Haptics.enabled`), iOS's System Haptics switch
silences them too, and the web gets none. Every touch passes one gate (`HapticGate`): never two
within 70 ms, at most 10 a second, so a giant board or a shared game's changes never buzz; a success
always plays. A run of ticks along an animation (`Haptics.run`) is at most 5, at least 70 ms apart.

| Where | Kind |
| --- | --- |
| Every button, card, row and alert action (`Pressable`: `BigButton`, `RoundIconButton`, `PhotoButton`, `ListRow`, `SoftCard`) | light |
| Tab bar, `AppSegmentedControl`, pickers, View picture and back, a tap on the giant board's map | selection |
| Picking a card up (tap or drag), a Hint showing a card | selection |
| Putting a card down, a refused move (a locked card), a claim lost in Play together | light |
| Cards joining or locking (a Magic too) | medium |
| A double lock | success |
| The deal after the picture: ticks as the sweep takes cards off the picture, a light touch as they land (Reduce motion: one tick) | selection run, light |
| Shuffle and Gather: three ticks while the cards slide, a light touch as they settle | selection run, light |
| Peek | light |
| Picture complete | success, then a tick as each earned star pops in |
| The picture that finishes its pack | success once more after the stars |
| Rewards claimed, purchases, the Lucky Wheel's prize | success |

## Shake to send feedback

A shake of the iPhone on any screen opens Send feedback (the Settings > Help form) as a sheet on the
root navigator (owner, 2026-10-18). Native side: `ShakeToFeedback` in `ios/Runner/AppDelegate.swift`
(`motionEnded` on `UIWindow`, which every shake reaches through the responder chain; the app delegate
never hears one, UIApplication keeps them for shake-to-undo) sends `shake` on channel `cjw/shake`,
only while nothing native (a system alert, the share sheet) is over the game. Dart side: `ShakeChannel` (`lib/core/shake.dart`) and `ShakeFeedbackHost`
(`lib/features/profile/shake_feedback.dart`, in `app.dart`): one form at a time, never over one of
the app's alerts or action sheets, only while the app is in front. Settings > Help > Shake to send
feedback (on by default, `shakeFeedback` on the device) turns it off; the web has neither the row
nor the listener. Analytics: `feedback_opened` with `via: shake`. On the simulator: Device > Shake
(ctrl+cmd+z), or from a script `xcrun simctl spawn <udid> notifyutil -p com.apple.UIKit.SimulatorShake`
(QA: `integration_test/shake_feedback_test.dart`).
