# Web build

Carden runs in the browser as the same Flutter app, built with
`flutter build web`. The web version is deliberately limited to what works
without native plugins; everything else is the iPhone app.

## What is limited on web, and why

| Feature | Web | Why |
| --- | --- | --- |
| Coin, ticket and booster bundles, VIP subscription | Not sold. The store shows a notice card, the free sources (bonus video, quests, piggy bank, Lucky Wheel) and the VIP benefits with an "Available on iPhone" label. | Purchases go through StoreKit and are verified by the server (`/purchase/verify` on the `api` Appwrite Function) with a StoreKit 2 JWS. `in_app_purchase` has no web implementation. A VIP bought on iPhone is active on web too (it lives on the profile). |
| Gift codes ("Redeem a gift code", "Have a gift code?") | Hidden. | App Store offer codes are redeemed through the StoreKit sheet. |
| Restore purchases | Hidden. | StoreKit only. |
| House ads | Shown. The rewarded "Watch" card still pays coins; CTAs that lead to a purchase show "Purchases are available in the iPhone app." instead of opening the store. | The ads are in-app promotions, not an ad network. |
| Daily reminders switch | Hidden. | No notification plugin is wired on web. |
| Home Screen widgets, quick actions | Not present. | WidgetKit and `quick_actions` are native. |
| Sign in with Apple | OAuth token flow through Appwrite: full-page redirect to `/account/tokens/oauth2/apple` (`createOAuth2Token`), back to `/auth/callback`, then `account.createSession` (stores the third-party-cookie fallback). Never `createOAuth2Session`. | The native `sign_in_with_apple` sheet needs an app. Handled in `account_screen.dart` / `state/auth.dart`. |
| Sound, music, haptics | Sound and music work (`audioplayers` web). Haptics are a no-op. | Browsers block autoplay until the first tap; the music starts on the first interaction. |
| My Puzzles uploads | Work (`image_picker` web uses a file chooser). | |

Every one of these is gated by `lib/core/platform.dart`:

- `isWeb`, `supportsPurchases`, `supportsGiftCodes`, `supportsQuickActions`,
  `supportsWidgets`, `supportsNotifications`, `supportsNativeAppleSignIn`
  for services.
- `platformCapsProvider` (a `PlatformCaps` snapshot) for widgets, so tests
  can pump the web and iOS layouts on the VM (`test/platform_guards_test.dart`).

`PurchaseService` never reads `InAppPurchase.instance` on web: `start()` is a
no-op, `isAvailable()` is false, `queryProducts()` is empty,
`presentCodeRedemptionSheet()` is false and `restorePurchases()` reports zero.

## Storage in the browser

SharedPreferences is localStorage on the web (`flutter.<key>`), about 5 MB per site and shared by
the save, the sync queue and the settings. The catalogue copy (`CatalogSync`, docs/catalog-sync.md)
is about 5.6 million characters, so it lives in IndexedDB instead (`lib/data/catalog_cache_web.dart`:
database `carden`, store `cache`, key `catalog`; through `package:web`, no new package and nothing
leaves the browser). Before 2026-10-17 it was written to localStorage, which refused it
(`QuotaExceededError`), and every launch downloaded the snapshot again. A copy an earlier build left
in localStorage moves to IndexedDB on the first launch and leaves localStorage; where IndexedDB
cannot be opened, localStorage is used as before. The iPhone keeps SharedPreferences.

## Memory

A player's Opera tab on an 8 GB MacBook Neo crashed on a 22x22 giant board (2026-10-19). Measured
in headless Chromium on a Retina window (`footprint` of the GPU and renderer processes; an empty
page with one WebGL canvas takes 240 MB in the GPU process, almost none of it graphics):

| Screen (build of 2026-10-18) | GPU process | Page | Together |
| --- | --- | --- | --- |
| Difficulty screen | 447 MB | 190 MB | 0.64 GB |
| Normal board, 7x7 | 602 MB | 259 MB | 0.86 GB |
| Giant picture, 13x13 | 736 MB | 344 MB | 1.08 GB |
| Giant picture, 22x22, dealt and played 12 min (539 moves, 11 Peeks) | 718-740 MB | 358-490 MB | 1.1-1.2 GB |

Memory stayed level while playing (no leak), and a 13x13 board of a giant picture cost about what
a 22x22 one did: the picture, more than the number of cards. A browser holds it more than once (the
decode, its GPU texture with mipmaps), and the web engine decodes the whole file before it scales.
Since then:

- **Giant pictures are decoded at most 2048 px on their longer side on the web** (`webGiantSide`
  in `lib/game/image_loader.dart`; the size comes from the file's header, `encodedSize`, because
  the web cannot read an `ImageDescriptor`). A quarter of the pixels of a 3072x4096 picture; a
  card at the zoom limit still shows about 70 picture pixels across on the biggest boards. The
  iPhone keeps the full size. A freshly dealt 22x22 board with 40 moves and 2 Peeks: 1.20-1.26 GB
  before, 1.10-1.15 GB after (frame rate unchanged).
- **Pictures are kept in `RecentPictures`** (`lib/core/image_files.dart`, 32 MB, the one used
  longest ago goes first) instead of `DefaultCacheManager`, whose web version keeps every file it
  fetched in memory for the whole session. The browser's HTTP cache keeps the files (Storage sends
  `cache-control: private, max-age=3888000`), so a picture read again comes from the disk.

Skia's GPU cache on the web (256 MB by default) fills up to its limit whatever is drawn, so the
GPU process stays near the same size on any busy screen. Measured, not shipped: a 128 MB limit
(`SystemChannels.skia`, `Skia.setResourceCacheMaxBytes`) took the same board to 1.00-1.02 GB with
the same frame rate; 64 MB saved nothing more.

Tests: `test/web_pictures_test.dart`.

## Known gap: images without CORS headers

The browser only lets Flutter decode an image into a puzzle board when the
host sends `Access-Control-Allow-Origin`. Probed on 2026-10-11 against the
catalog hosts:

| Host | CORS | Puzzles |
| --- | --- | --- |
| live.staticflickr.com (Openverse) | yes | 5,117 |
| openaccess-cdn.clevelandart.org (Masterpieces) | **no** | 2,432 |
| picsum.photos | yes | 1,816 |
| images.rawpixel.com | yes | 406 |
| images-assets.nasa.gov (Deep Space) | **no** | 339 |
| cdn.stocksnap.io | 403 to the probe, unverified | 304 |
| inaturalist-open-data.s3.amazonaws.com, pd.w.org | yes | 106 |

This is resolved: since 1.7.0 every picture and cover is served from our
Appwrite Storage bucket `puzzle-images`, which sends CORS headers for the
registered web platforms, so the web build loads all pictures directly. The
former `image-proxy` function was removed (2026-10-13).

## Layout

The web build lays itself out like a website on wider windows
(`lib/widgets/adaptive.dart`); a phone-width window, and the iPhone app (portrait
only, at most 440 pt), get the phone layout exactly as before. Two breakpoints:

| Window | Layout |
| --- | --- |
| Under 600 px (compact) | The phone layout. |
| 600 px and up (medium) | Still the floating tab bar, at a phone's width in the middle. Pages centre their content (`SliverPage`, `PageColumn`), grids add columns (`AdaptiveGridDelegate`), home shelves get arrow buttons and mouse drag (`Shelf`), sheets open as centred panels. |
| 900 px and up (expanded) | The website layout: a full-width glass top bar (`WideTopBar` in `lib/features/home/header_bar.dart`: the Carden mark, the five tabs in a capsule, balances and avatar) instead of the floating tab bar, content centred at up to 1200 px (`PageWidth.wide`) or 720 px for lists and forms (`PageWidth.reading`), and two columns where a page has two parts. |

What each screen does on an expanded window:

- Home: a dashboard. Today's picture beside Quick play and the streak, the Wheel and the piggy
  bank beside the level, then the shelves and Featured in two full rows.
- Library: the search beside the title, every chip in view (they wrap), as many pack columns as fit.
- A pack: the cover runs across the window as a banner, the way in (price, gate) beside the
  description, the pictures in as many columns as fit.
- Quests: daily and weekly side by side, live events beside "Coming up".
- Profile: the profile card and its links beside the statistics, achievements in two columns.
- Social, a player, Settings: one reading column; the lists still scroll anywhere in the window.
- Difficulty: the preview large on the left, the mode, board and Play beside it.
- A game: the HUD and the tools keep a phone's width over a board that uses the window; the
  results put the finished picture beside a results sidebar.
- Store, Wheel and Account open as a centred page sheet (`PanelRoute`, 580 px, so the screen inside
  keeps its phone layout); every `showAppSheet` as a centred panel (520 px); action sheets in the
  middle. A tap outside or Escape closes them.
- Onboarding: the art on the left, the page's text and the buttons on the right.

Everything tappable shows the hand cursor (`Pressable`). New screens: put the page's slivers in a
`SliverPage` (the pinned header stays outside, so its glass runs edge to edge), use
`AdaptiveGridDelegate` for card grids and `Shelf` for sideways rows, and gate a two-column layout
on `context.isExpanded`. Keep every wide change behind `context.isWide` / `context.isExpanded` so
the phone layout does not move. `test/adaptive_layout_test.dart` covers the helpers and the panels.

## Routing

`main.dart` calls `usePathUrlStrategy()` on web, so links are plain paths:
`/play/<puzzleId>`, `/library/pack/<packId>`, `/store`, `/redeem?code=...`,
`/auth/callback`. Every link the app knows, and how a visit that starts on one
is shown (Home beneath a picture or the store, sheets for codes), is in
[deep-links.md](deep-links.md). Unknown paths fall back to Home (`onException`
in `lib/router.dart`) instead of the framework's error page.

The host must serve `index.html` for every path (single-page fallback), or
deep links and the OAuth callback return a 404. The site also serves
`/.well-known/apple-app-site-association` (from `web/`), which lets the same
addresses open the iPhone app where it is installed.

## Build

```sh
export PATH="$HOME/flutter/bin:$PATH"
flutter build web --release --base-href /
```

Output: `build/web` (about 36 MB with CanvasKit; the renderer is Flutter's
default, CanvasKit). `web/index.html` carries `<base href="$FLUTTER_BASE_HREF">`,
which the build replaces with `/`.

Text is drawn by the engine with its bundled Roboto fallback (fetched from
fonts.gstatic.com on first load); the loading splash uses the system font
stack. The splash disappears on Flutter's `flutter-first-frame` event.

Icons: `web/icons/Icon-192.png`, `Icon-512.png`, maskable variants and
`web/favicon.png` are generated from the 1024 px app icon
(`ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`)
with Pillow. Regenerate them if the icon changes.

## Run locally

```sh
tools/dev/qa-run.sh run -d chrome   # silent QA run, test player purged afterwards
tools/dev/qa-run.sh run -d web-server --web-port 8461 --release   # no Chrome on this Mac: a headless browser opens it
```

Stopping the run (Ctrl-C, or TERM to qa-run.sh) stops the server and purges the guest.

`CJW_MUTE=true` silences music and effects; `CJW_QA=true` keeps the guest out of the league
(both passed by `tools/dev/qa-run.sh`). To test the release bundle with
path routing, serve `build/web` with any static server that falls back to
`index.html`.

## Tests

```sh
flutter test                                                   # VM, all suites
flutter test --platform chrome test/platform_guards_test.dart  # in Chrome, kIsWeb = true
```

## Deploy (Appwrite Sites)

The main session deploys to Appwrite Sites (project `6acb4de5003e38d5ebd9`,
Frankfurt). The site must have the single-page fallback file set to
`index.html`, and the site's hostname must be registered as a Web platform on
the Appwrite project (the OAuth redirect and session cookies depend on it).

```sh
tools/dev/deploy-web.sh            # build + deploy + wait until live
```

Every build gets a deploy id compiled in (`CJW_WEB_BUILD`) and published as `app-version.json`;
open tabs look at it every 5 minutes and offer "Update available" (`docs/app-updates.md`). Deploy
with the script, not by hand, or open tabs never hear about the new build.

The web store lists every bundle and VIP with "Available on iPhone" and shows no price anywhere
(store tiles, VIP card, house ads).

Nothing in `build/web` is secret: the Appwrite endpoint and project id are
public, and all writes are protected by Appwrite permissions and the
server-side functions.
