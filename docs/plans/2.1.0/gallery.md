# My gallery: favourites, save and share

Status: planned for 2.1.0, not started. Picked by the owner on 2026-10-20.

## How to work on this task

- Branch: `2.1.0/gallery`, which starts with this brief. Work and push only there (`git push -u origin 2.1.0/gallery`). Never
  merge it into main or push to main: that is the owner's call. This overrides CLAUDE.md's "push to origin main" for this task.
- Check the branch out in its own worktree (`git worktree add <folder> 2.1.0/gallery`): another session may be using the main
  checkout.
- No TestFlight or App Store builds, no web deploys (`tools/dev/deploy-web.sh`), no installs on the owner's iPhone. Pushing the
  branch starts no CI (`.github/workflows/ci.yml` runs on main and pull requests only).
- Changes to the live backend count as deployments: ask the owner before adding `progress.favourite`. Until then the app keeps
  working through `writeWithoutUnknown`, and the suites that check a heart reaching the server wait for that go.
- Everything else in CLAUDE.md applies: the gates (`flutter analyze --fatal-infos --fatal-warnings`, `flutter test`), QA only
  through `tools/dev/qa-run.sh`, commits with the owner's git identity and explicit paths.

## Summary

Profile gets a Gallery: every picture the player has finished, catalogue pictures and My Puzzles photos, newest first,
with All and Favourites. A picture opens full screen with pinch to zoom and its credit, and offers Favourite, Save to
Photos, Share, Play again and Open pack; a heart on the win screen marks a favourite too. Favourites live on the
player's progress rows, so they sync across devices like the rest of the save. Saved and shared copies carry the
picture's author and licence; pictures whose licence allows no copies stay view-only.

## Why

- Evidence: the genre research lists "completed picture vanishing immediately" among recurring player complaints
  ([docs/research-card-jigsaw-and-image-apis.md](../../research-card-jigsaw-and-image-apis.md), 2026-10-11).
  [Jigsawscapes](https://apps.apple.com/us/app/-/id1589762792) advertises a personalised gallery of completed puzzles;
  [Jigsolitaire](https://apps.apple.com/us/app/id6741408932) has a Collection that reveals photos as levels are completed.
- Carden today: a finished picture shows only on the win screen (`_CompletionOverlay` in `game_screen.dart`, View
  picture), then as a small tile with stars on its pack page (`_PuzzleTile` in `pack_screen.dart`) whose tap opens the
  board picker. Nothing keeps or shares it.
- What weakens it:
  - Save needs the add-to-Photos permission: a new system prompt and a purpose string that App Review reads.
  - About three quarters of the catalogue is CC BY or CC BY-SA, so every copy must carry its credit; some licences
    forbid handing out the file at all, and pictures with incomplete licence data stay view-only until fixed.
  - It is a satisfaction feature more than a growth one: a shared link mostly lands on a pack page with a price, and
    2.0.0's View picture already answers part of the "vanishing picture" complaint.

## What the player sees

**Way in.** Profile (`lib/features/profile/profile_screen.dart`) gets a Gallery section between the profile card (and
the guest's Save progress button) and Statistics: `SectionHeader` "Gallery", subtitle "214 pictures · 12 favourites"
(favourites left out at 0), action "See all", and a `Shelf` of the 10 newest pictures as 3:4 tiles; on wide windows in
the left column. With nothing finished, one `SoftCard` line: "Pictures you finish are kept here."

**Gallery page** (`/profile/gallery`): `GlassAppBar` "Gallery" with back, an `AppSegmentedControl` (All, Favourites), a
count line ("214 pictures"), then a 3-column grid (`AdaptiveGridDelegate`, more columns on wide windows) under month
headings ("October 2026", by last finish). Tiles show the picture and, on favourites, a heart chip; no titles, stars or
prices. Tap opens the viewer; holding a tile opens the iOS context menu as in My Puzzles: "Add to favourites" or "Remove
from favourites", "Share", "Save to Photos", "Play again".

| State | What shows |
| --- | --- |
| Save not read yet (a new device after sign-in) | Skeleton tiles, never the empty state |
| No finished pictures | `EmptyState` "No pictures yet" / "Every picture you finish is kept here. Finish a puzzle to start your gallery." / "Play a puzzle" (Home) |
| No favourites | "No favourites yet" / "Tap the heart on a picture to keep it here." |
| A few, or hundreds | The same grid, built lazily, tiles decoded at tile size from their own cache ("App changes"); "1,204 pictures" (`formatCount`) |
| Catalogue never loaded (first launch offline) | "Pictures did not load" / "Check your connection and try again." / "Try again" |
| Offline, catalogue cached | Everything lists; a tile not cached shows its BlurHash |
| Heart removed in the Favourites grid | Toast "Removed from favourites" with "Undo" |

**Viewer** (`/gallery/<puzzleId>`, root navigator, black, light status bar, View picture's fade): the picture fits the
screen; pinch zooms up to 4x, a double tap 2x and back; a sideways swipe moves through the list it came from; a swipe
down closes it; a tap hides or shows the controls. Top: `PhotoButton` back, the title, "Finished 12 October". Bottom:
the win screen's credit line ("<author> · <source>", "Your photo" for My Puzzles; a tap opens Picture credit) over a dark
`Glass` bar of `PhotoButton`s: Share, Favourite, Save to Photos ("Download" on the web), More. More is a
`showAppActionSheet` titled with the picture: "Play again" ("Continue" while a board of it is in progress; it opens
`/play/<id>`, so pack locks apply), "Open pack" ("Open My Puzzles" for a photo), "Picture credit". Wide windows: arrow
keys page, Escape closes.

**Win screen**: a heart `PhotoButton` at the top right of the finished picture and in View picture. Not on the guided
first board (`first`); a Play together guest finishes on `CoopGuestFinish`, which gets none (the guest has no row).

**Save to Photos (iPhone)**

| Situation | What happens |
| --- | --- |
| First tap on Save | iOS asks for add-only access with Carden's purpose string; nothing is asked before a tap |
| Allowed | Saved with the credit inside the file; toast "Saved to Photos" |
| Don't Allow on the prompt | Nothing more that time: the player answered |
| Later taps while denied | `showAppAlert` "Photos access is off" / "Allow Carden to add photos in iOS Settings to save pictures." / "Open Settings" / "Not now" |
| Restricted (Screen Time) | "Saving is turned off" / "This iPhone does not allow apps to add photos." / "Got it" |
| Licence allows no copies | Save dimmed; a tap shows "This picture cannot be saved. Its licence allows it in Carden only." |
| Private pack (pack code) | Save and Share dimmed: "This picture cannot be saved or shared. It belongs to a private pack." |
| Offline, file not cached | "No connection. Try again when you are back online." (My Puzzles' wording) |
| Anything else fails | "Not saved. Try again." |

**Share**: the iOS share sheet through share_plus with the file ("<title>.jpg") and this text (a CC BY-SA picture;
lines without a value are left out):

```
<Title>, finished in Carden
Picture: <author> · Wikimedia Commons, CC BY-SA 4.0
Licence: https://creativecommons.org/licenses/by-sa/4.0/
Source: https://commons.wikimedia.org/wiki/File:<file name>
Play it: https://play.carden.page/play/<puzzle id>
```

A picture that allows no copies shares the text without the file. A My Puzzles photo shares the file and "<title>,
finished in Carden" without a link (the photo is private). Once the Info.plist key is in, iOS also offers "Save Image"
in every share sheet that carries a picture ([Casey Liss](https://www.caseyliss.com/2022/2/9/saving-to-photo-library-via-sharesheet)).

**Web**: the same pages. Save is "Download" (a browser download, toast "Picture downloaded", no permission). Share uses
the browser's share sheet with the file where it can (Web Share API, share_plus's web code), else the text, else copies
the text: toast "Credit and link copied".

## Rules and edge cases

- Listed: a solved progress row (`PuzzleProgress.completed`, which also counts a finish time) whose picture still
  resolves, in `allPuzzlesProvider` (hidden packs only for owners) or among the player's photos; a replay in progress
  keeps it. Order: `completedAt`, newest first; `SyncOp.win` keeps the later finish time (`lib/data/sync/ops.dart`), so
  a replay moves a picture to the top.
- If photo puzzles ship too (branch `2.1.0/photo-puzzle`), a received puzzle the player finished is listed as well, resolved
  through that task's `receivedPuzzlesProvider`, and stays view-only (see "Licences and credit"). Whichever branch merges
  second adds this.
- Pictures the content repair removed and photos the player deleted are left out quietly; their rows stay
  (`UploadRepository.delete` deletes no progress row). The count can differ from Statistics' "Pictures solved", which
  also leaves out photos (`CompletionTotals`, `lib/state/completion.dart`).
- Only finished pictures take a heart; removing one needs no alert. A heart set offline is queued with the other
  progress ops; across devices the last change wins.
- Save and Share use the hosted file (`/view`: about 1,200 px wide, up to 4,096 px for Giant, the player's upload for
  photos), never a third-party address; third-party pages appear only as links in shared text, never loaded by the app.
- Daily and ended event pictures stay; Open pack shows the pack as it is now. The guided start does not gate the
  gallery. Haptics: `Pressable`'s light touch only. Android (CI builds only): Save hidden, Share through share_plus.
- The work stops at "ready for a build": no TestFlight build, web deploy or iPhone install unless the owner asks.

## Data and backend

**Favourites: one new progress column**, `progress.favourite` (boolean, optional, default false). Progress rows are
readable only by their player (`upsertProgress`, `lib/data/sync/backend.dart`), unlike the public profile row, and the
device holds all of them: `SyncController._work` asks for a full read on the first fetch of every run (`!a.fetched`),
`_fetch` reads every row through `listAllRows` (`progressRows`), later reads take rows changed since, and the copy is a
file on the iPhone (`FileSyncRows`) and localStorage on the web (docs/sync.md). The page needs no new catalogue read.

- Write: a new op `SyncOp.favourite(puzzleId, on)` (`OpKind.favourite`, progress target) that `Put`s the one field.
- Other devices: the next progress read (start, resume, tab focus, sign-in) brings it. A row whose only change is
  `favourite` updates the copy quietly: no "Synced from another device" line and no `BoardUpdate` (today any changed row
  can raise "Two boards in progress" when the device holds an unsent board of that picture).
- Sign-in merge: a favourite when either save had it (`mergeProgressRow`, `lib/state/merge.dart`).

| Who | What happens |
| --- | --- |
| Builds up to 2.0.x | Never read or write it. Their upserts send only their own columns, so they never clear it (as with `finishes`, docs/sync.md "Columns"). One holding an unsent board of the same picture can ask "Two boards in progress" when a heart arrives: a rare limit for docs/sync.md "Known limits". |
| 2.1.0 before the column exists | `writeWithoutUnknown` retries without it (add `favourite` to `newProgressColumns`, `lib/data/repositories.dart`): play never stops, the heart stays on the device. |
| Web | Redeployed with every build, so always current. |

Server before build: add the column with the Appwrite CLI as `progress.painting` was (docs/sync.md "Columns") and check
with a QA guest that a heart lands, before the first 2.1.0 TestFlight build. No index: nothing queries by it.
Unchanged: functions, the catalogue snapshot, the integrity sweep. Account deletion already deletes progress rows
(`PLAYER_TABLES`, `functions/api/src/account.js`), as does the QA purge (`PLAYER_TABLES` in `tools/dev/cjw_admin.py`,
used by `tools/dev/purge_test_players.py`).

**Reads**: the player's photos, one `listAllRows` of `my_puzzles` (`Query.equal('userId')`, `Query.select(['$id',
'fileId', 'title'])`) when the gallery opens, never a fixed `Query.limit`. Share or Save of a CC BY or BY-SA picture:
one `getRow` with `Query.select(['sourceUrl'])` for the source link (decision 4); the device's catalogue drops it
(`CatalogSync._drop`; `DROP` in `functions/catalog-snapshot/src/main.js`). Tiles reuse the stored `thumbUrl`
(`/preview?width=600&quality=80`), so no new preview variants; Appwrite bills transformations per origin image a month
([docs](https://appwrite.io/docs/advanced/billing/image-transformations)); whether a CDN-cached preview counts is unverified.

## App changes

| File | Change |
| --- | --- |
| `lib/models/models.dart` | `PuzzleProgress.favourite` (`_b(d['favourite'])`); `toData()` writes it only when true, so code that rebuilds rows never writes false over another device's heart |
| `lib/data/sync/ops.dart` | `OpKind.favourite` (never renamed: queued ops are stored by name), `SyncOp.favourite({puzzleId, on})`, progress target, `_progress` case `{'favourite': Put(on)}`, not in `needsFresh` |
| `lib/data/repositories.dart` | `newProgressColumns = {'finishes', 'favourite'}`; `UploadRepository.all(userId)` (`listAllRows`, select) |
| `lib/state/progress.dart`, `lib/state/merge.dart` | `ProgressNotifier.setFavourite(puzzleId, on)`; `mergeProgressRow` takes `favourite` from either row |
| `lib/state/sync.dart` | `_fetch`: a row that differs from the copy only in `favourite` and `$updatedAt` is stored without notice or `BoardUpdate`; `SyncState.fetched` (first read of the run done) for the loading state |
| `lib/state/gallery.dart` (new) | `GalleryItem` (puzzle, progress, finished at, favourite, own photo, licence); `galleryProvider` joins the rows, a by-id map of `allPuzzlesProvider` built once (`puzzleByIdProvider` scans the list per call) and the photos; months; the Favourites view |
| `lib/core/picture_licence.dart` (new) | `PictureLicence.of(Puzzle)`: kind, version, deed URL, `allowsCopies`, `needsCredit` (the allow-list below); `Credit.line` (the win screen's string), `Credit.shareText`, `Credit.cleanAuthor`, `sourcePageFor(sourceUrl)` |
| `lib/core/jpeg_credit.dart` (new) | `withCredit(bytes, credit)`: one XMP APP1 segment after SOI and APP0; other formats unchanged. Pure Dart, shared by iPhone and web |
| `lib/core/photos.dart` (new) | `PhotoLibrary` on channel `cjw/photos` (`status`, `save` with bytes and file name, `openSettings`), shaped like `AppReviewChannel` (`lib/core/app_review.dart`); iOS only |
| `lib/core/web_page*.dart` | `downloadBytes(name, bytes, mime)`: Blob, object URL, anchor with `download` (package:web, already a dependency) |
| `lib/core/image_files.dart` | `/preview` URLs in their own `CacheManager` (say 1,500 files, 60 days) on the iPhone and a second `RecentPictures` (about 12 MB) on the web. Tiles, covers and board pictures share one `DefaultCacheManager` of 200 files today (flutter_cache_manager 3.4.5 default): hundreds of tiles would push out board pictures, also those of boards in progress offline |
| `lib/widgets/ui.dart` | `NetImage(decodeWidth:)` wraps `CachedUrlImage` in `ResizeImage` |
| `lib/widgets/icons.dart` | `favourite` (`CupertinoIcons.heart_fill`), `favouriteOutline` (`heart`), `saveToPhotos` (`square_arrow_down`); AppIcons has no heart today (only the avatar glyph `Icons.favorite_rounded`) |
| `lib/features/profile/gallery_screen.dart` (new) | The page (in `profile/`: `lib/features/gallery/` holds the Library) |
| `lib/features/profile/gallery_viewer.dart` (new) | `PageView` of `InteractiveViewer`s; each page `Image(ResizeImage(CachedUrlImage(imageUrl)))`, at most 2,048 px on its longer side; never `puzzleImageProvider`, which keeps every 1,400 px decode (about 10 MB) for the session (`lib/game/image_loader.dart`) |
| `lib/features/profile/picture_actions.dart` (new) | `toggleFavourite`, `savePicture`, `sharePicture` for grid, viewer and win screen; share as `lib/features/coop/share_invite.dart` does (`ShareParams` with `files`, `fileNameOverrides`, `text`, `subject`, `sharePositionOrigin`, both fallbacks off) |
| `lib/features/game/picture_credit.dart` (new) | `showPictureCredit` moved out of `_DifficultyScreenState._showCredit`: Author (was "Photographer", wrong for paintings and AI art), Source, Licence with "View licence" (`openLink`, `lib/core/links.dart`), a line on Save and Share; `difficulty_screen.dart` uses it |
| `lib/features/game/game_screen.dart` | `_CompletionOverlay`: the heart (results photo and View picture, not when `first`); the credit line opens Picture credit |
| `lib/features/profile/profile_screen.dart` | The Gallery section in both layouts |
| `lib/router.dart` | `gallery` under `/profile` (`_cupertino`); `/gallery/:puzzleId` on `rootNavigatorKey` (`_fade`, `?in=favourites`); an id not in the gallery opens the Gallery page |
| `lib/core/analytics.dart`, `lib/core/app_links.dart` | `screenNames` `gallery`, `gallery_picture`; links `/gallery` and `/profile/gallery` (page, `?tab=favourites`) for Inbox buttons |
| `lib/features/gallery/pack_screen.dart`, `web/.well-known/apple-app-site-association` | `_gridCodeFor` becomes a shared helper (the viewer's Continue); the association file lists `/gallery`, `/profile/gallery` |
| `ios/Runner/AppDelegate.swift` | `PhotoSaver` (`import Photos`): `authorizationStatus(for: .addOnly)`, `requestAuthorization(for: .addOnly)` when not determined, `PHPhotoLibrary.shared().performChanges` with `PHAssetCreationRequest.forAsset().addResource(with: .photo, data:, options:)` and `originalFilename`; `openSettings` with `UIApplication.openSettingsURLString` (the reminders' one opens notification settings); registered in `didInitializeImplicitFlutterEngine` like `AppReview` |
| `ios/Runner/Info.plist` | `NSPhotoLibraryAddUsageDescription` |

## Apple, privacy and review

- Purpose string: "Carden saves a finished picture to your photo library when you tap Save. It cannot see your photos."
  Apple: "If your app only adds to the library, use the NSPhotoLibraryAddUsageDescription key", request add-only access,
  and ask in response to a direct user action ([PhotoKit privacy](https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app),
  [the key](https://developer.apple.com/documentation/bundleresources/information-property-list/nsphotolibraryaddusagedescription),
  [`addOnly`](https://developer.apple.com/documentation/photos/phaccesslevel/addonly)). My Puzzles' key stays. No
  entitlement; nothing for a privacy manifest (PhotoKit is not on the required-reason list: unverified).
- Channel, not plugin: about 50 lines of Swift in the house style, no new dependency to audit for network use, and the
  file with its XMP reaches Photos unchanged (`addResource(with:data:)`) under its own file name.
- Review: 2.1.0 goes to App Review and its first TestFlight build to Beta App Review, which can hold a build that adds a
  permission prompt (CLAUDE.md). Purpose strings must "clearly and completely describe your use of the data" and consent
  must not be forced ([5.1.1 (ii), (iv)](https://developer.apple.com/app-store/review/guidelines/)); 5.2.1 wants a
  licence for third-party content, which the licence rules give. Review notes:
  "Profile > Gallery lists finished pictures. Save to Photos asks for add-only access on the first tap; the app never
  reads the library. Pictures whose licence allows no copies show Save dimmed, with the reason." What's New: "Gallery:
  every picture you finish, kept on your Profile. Mark favourites, save a picture to Photos or share it with its credit."
- `docs/privacy-policy.md`: progress adds "and whether you marked the picture as a favourite"; usage data adds "a
  picture saved, shared or marked as a favourite (never where it was shared)"; "Pictures" adds "Save to Photos asks iOS
  once for permission to add pictures to your photo library. Carden can only add pictures; it cannot see or change your
  photos. Saved and shared pictures carry their author and licence."; a new "Last updated".
- App Privacy answers: no change expected (owner to confirm): favourites are Gameplay Content, the events Product
  Interaction, both declared; add-only access collects nothing.
- Analytics (`lib/core/analytics.dart`, rows in `docs/analytics.md`; never photo ids: photos count as pack `my-puzzles`):

| Event | Props | When |
| --- | --- | --- |
| `picture_favourited` | `on`, `from` (`finish`, `viewer`, `grid`), `pack` | A heart set or removed |
| `picture_saved` | `from`, `pack`, `licence` (`cc0`, `pd`, `cc_by`, `cc_by_sa`, `unsplash`, `own`, `other`), `result` (`saved`, `downloaded`, `denied`, `restricted`, `unavailable`, `offline`, `failed`) | A save finished or was refused |
| `picture_shared` | `from`, `pack`, `licence`, `file` (the picture went along), `done` (share_plus `ShareResultStatus`) | The share sheet closed |
| `photos_permission` | `result` (`granted`, `denied`) | The iOS prompt answered |

## Licences and credit

Shares come from the content tool's local catalogue cache of 2026-10-14 (about 8,500 pictures, 71 `source` strings),
unverified against the live table, which the content repair keeps changing.

| Licence and sources | Save | Share | Credit on every copy, terms |
| --- | --- | --- | --- |
| CC0, public domain, Public Domain Mark (about a quarter): Commons, NGA, the Met, Cleveland, Rijksmuseum, NASA, StockSnap, rawpixel, WordPress photos and Flickr via Openverse, iNaturalist CC0, Tiny Speck (Glitch), OpenGameArt, public-domain AI pictures | Yes | Yes | Not required; keep author and source anyway. NGA asks for "Courtesy National Gallery of Art, Washington" ([policy](https://nga.gov/imagepolicy)); NASA "should be acknowledged as the source" and must not appear to endorse ([NASA](https://www.nasa.gov/nasa-brand-center/images-and-media/)); PDM is no licence and "moral rights ... may persist" ([PDM](https://creativecommons.org/publicdomain/mark/1.0/)); AI keeps "(AI-generated)" (docs/content-rules.md rule 7) |
| CC BY 2.0 to 4.0 and ports (about a quarter): Commons, iNaturalist, Flickr via Openverse, Blender Foundation (3.0), David Revoy (4.0) | Yes, when version and a clean author are known | Yes, same | Author, title, licence and deed link, source link where practicable, changes noted. Attribution "in any reasonable manner based on the medium, means, and context" ([CC BY 4.0 s. 3(a)](https://creativecommons.org/licenses/by/4.0/legalcode.en)); resizing is a technical change that "never produces Adapted Material" (s. 2(a)(4)); 2.0 and 3.0 want the licence URI "with every copy" ([CC BY 2.0 s. 4](https://creativecommons.org/licenses/by/2.0/legalcode)) |
| CC BY-SA 1.0 to 4.0 and ports (about half): mostly Commons, also Flickr, iNaturalist | As CC BY | As CC BY | As CC BY. ShareAlike binds only adapted material we share ([CC BY-SA 4.0 s. 3(b)](https://creativecommons.org/licenses/by-sa/4.0/legalcode.en)): a saved hosted copy is none; a burned-in credit band or a crop could be one, and would then be BY-SA |
| Commons "Attribution" template (12 pictures) | Yes | Yes | The author: "for any purpose, provided that the copyright holder is properly attributed" ([template](https://commons.wikimedia.org/wiki/Template:Attribution)) |
| Unsplash License (about 2%: the four original featured packs via Lorem Picsum) | Yes (decision 6) | Yes | Not required; "Photo: <name>, Unsplash". Grants "download, copy, modify, distribute"; not "sold without significant modification", not compiled "to replicate a similar or competing service" ([Unsplash](https://unsplash.com/license)) |
| Pexels License (none yet; provider inactive) | No | Text and link only | "Don't redistribute or sell the photos and videos on other stock photo or wallpaper platforms" ([Pexels](https://www.pexels.com/license/)); the pack-making skill: "Never add a wallpaper or save-picture feature for Pexels pictures" |
| Pixabay Content License (none in the cache; provider active since 2026-10-14) | No | Text and link only | No distribution "on a Standalone basis", which includes "using the Content in its original form or solely ... resizing or cropping" ([terms](https://pixabay.com/service/terms/)) |
| All rights reserved, and every file in bucket `private-packs` (`pack-hidden-object-test`, an internal test) | No | No, not even a link | docs/pack-codes.md: never public |
| Anything else (one Commons "No restrictions", one "Copyrighted free use"; NC and ND never pass rule 7) | No | Text and link only | Until the owner reviews the licence |
| My Puzzles photo | Yes | Yes, no link | None: the player's own ("only add photos you have the right to use", docs/terms-of-use.md) |
| A photo puzzle received from someone else (only if the photo puzzle task, branch `2.1.0/photo-puzzle`, ships too; pack `from-others`) | No | No, not even a link | It is the sender's private photo, shared to be played: listed once finished, view-only |

- `PictureLicence.of` is an allow-list: only the Yes rows allow copies; anything it cannot read allows none.
- Data for the content work (not this task's files; content docs and tools stay untouched while a content session
  runs): about 725 CC rows have no licence version ("iNaturalist, CC BY", "flickr via Openverse, CC BY-SA") and about 57
  hold scraped page text instead of an author, most of them CC BY-SA. They stay view-only until fixed (decision 5); the
  catalogue sync takes changed rows, so the rule lifts itself.
- Credit in the app: the line `<author> · <source>` and the Picture credit sheet. In saved and shared files, XMP as
  Creative Commons recommends ([CC XMP](https://wiki.creativecommons.org/wiki/XMP)): `dc:title`, `dc:creator`,
  `dc:rights`, `dc:description` ("<title> by <author>, <licence> (<deed URL>), via <source>. Finished in Carden."),
  `dc:source`, `xmpRights:Marked` (false for public domain), `xmpRights:WebStatement` and `cc:license` (deed),
  `cc:attributionName`, `photoshop:Credit`; whether iOS Photos shows any of it is unverified. Shared text gives title,
  author, source and licence, CC's TASL ([recommended practices](https://wiki.creativecommons.org/wiki/Recommended_practices_for_attribution)).
- Deeds follow the string ("CC BY-SA 3.0 de" is `https://creativecommons.org/licenses/by-sa/3.0/de/`; the same for `by`,
  ports and `igo`); plain "Public domain" and Unsplash have none. Source pages from `sourceUrl`: Commons
  `upload.wikimedia.org/...<file>` to `commons.wikimedia.org/wiki/File:<file>`; iNaturalist `.../photos/<id>/original.jpg`
  to `inaturalist.org/photos/<id>`; Flickr `live.staticflickr.com/<server>/<id>_...` to `flickr.com/photo.gne?id=<id>`
  (unverified); NASA `images-assets.nasa.gov/image/<id>/...` to `images.nasa.gov/details/<id>`; Cleveland
  `openaccess-cdn.clevelandart.org/<accession>/...` to `clevelandart.org/art/<accession>`; our own Storage addresses
  (hand-made packs) and IIIF servers get no link.
- This is a careful reading of the terms, not legal advice; the owner decides (decisions 3, 5 and 6).

## Accessibility

- Text size up to Largest: tiles carry no text, so 3 columns stay; headings and counts wrap; the viewer's title, date
  and credit take up to 2 lines (`A11y.largeText`); bar buttons keep 44 pt targets (`TapTarget`); no layout errors at
  Largest on the SE frame.
- Reduce motion (`A11y.reduceMotionOf`): the viewer fades without the 0.96 scale, a double tap jumps to the zoom, a
  swipe down follows the finger and then fades, the heart does not pop; paging is the player's own drag.
- Increase contrast: `PhotoButton` already darkens its disc; the viewer's date and credit go from 70% to 90% white; the
  tile heart sits on a dark `PhotoChip`. Check light and dark.
- Differentiate without colour: favourite is a filled versus an outlined heart (shape) plus its label; a dimmed Save or
  Share also carries the `noEntry` mark under `A11y.symbolsOf`.
- VoiceOver: a tile reads "<title>, <pack>, favourite, finished 12 October" with `customSemanticsActions` (as Inbox and
  Quests rows): Add to favourites or Remove from favourites, Share, Save to Photos, Play again. The heart names its
  action; the viewer reads "<title>, by <author>", has Next picture and Previous picture actions and closes with the
  escape gesture; toasts are live regions already.

## QA

Gates: `flutter analyze --fatal-infos --fatal-warnings` and `flutter test`. New tests: `test/gallery_test.dart` (join,
order, months, Favourites, removed pictures, deleted photos, hidden packs); `test/picture_licence_test.dart` (every
source string shape in the table, no ids; deed URLs; the unversioned and scraped-author rules; `private-packs`; own
photos); `test/jpeg_credit_test.dart` (XMP after SOI and APP0, still decodes with `instantiateImageCodec`, under 65,502
bytes, `<&"` escaped, other formats unchanged); `test/share_text_test.dart`; `test/gallery_screen_test.dart` (empty
states, segments, semantics, dimmed Save); `test/sync_test.dart` additions (the op offline and sent, two devices, a
heart-only change quiet even with an unsent board, the merge, rows without the column); plus `deep_links_test`,
`analytics_test` and `pagination_test`.

Integration: `integration_test/gallery_test.dart`, run only as `tools/dev/qa-run.sh drive
--driver=test_driver/integration_test.dart --target=integration_test/gallery_test.dart -d
CDD7317C-19D6-486D-B258-8AB8A607297D`, with `FirstSteps.skipFor(store)`, `GameScreen.dealPreview = false` and a fake
`cjw/photos` answer per step (the driver cannot tap iOS prompts or the share sheet). Uninstall before a second run the
same day. Look at every screenshot:

| Path | Screenshot |
| --- | --- |
| Home > a picture > finish a 3x3 > heart on the results; then View picture | `gallery_01_finish_heart.png`, `gallery_02_view_picture.png` |
| A second finish > Profile tab | `gallery_03_profile.png` |
| Profile > See all: All, Favourites, a fresh guest's empty Favourites; hold a tile | `gallery_04_all.png` to `gallery_07_menu.png` |
| Tap a tile: viewer, pinch, More, Picture credit | `gallery_08_viewer.png` to `gallery_11_credit.png` |
| Save answered saved, denied, restricted | `gallery_12_saved.png`, `gallery_13_photos_off.png`, `gallery_14_restricted.png` |
| A picture forced to a no-copy licence (test override) | `gallery_15_unavailable.png` |
| A photo the suite uploads (`UploadRepository.upload`) and finishes | `gallery_16_own_photo.png` |
| An uncached picture with the network failing (a debug hook in `ImageFiles`, like `debugPictureDelay`) | `gallery_17_offline.png` |

- Real iOS parts by hand on the same simulator, with host screenshots (`xcrun simctl io <udid> screenshot`; the prompt
  and the sheet wait): `xcrun simctl privacy <udid> reset photos-add com.matejbaco.cardjigsawworld` (unverified before
  install); Save shows the prompt (`gallery_host_prompt.png`); Allow saves; the newest file in the simulator's
  `data/Media/DCIM/100APPLE/` (unverified path) carries the XMP (read it with a `python3 -I` script); note what Photos >
  Info shows. Revoke: the alert and Open Settings. Share: the sheet (`gallery_host_share.png`).
- Devices: extend `integration_test/sync_devices_test.dart`: a heart set by the laptop sync shows on the iPhone after a
  resume, with no alert (`sync_07_favourite.png`).
- Web: `tools/dev/qa-run.sh run -d web-server --web-port 8461 --release` in the headless browser: Gallery, viewer,
  Download (the file carries the XMP), the copy fallback (`gallery_web_*.png`).
- Design QA harness (`integration_test/design_qa/harness_main.dart`, scene pref `accessibility`): empty, few, 600
  pictures, viewer, unavailable; Largest on the SE frame, Increase contrast in light and dark, Reduce motion.

## Docs to update

- `docs/sync.md` (column, op, quiet heart-only changes, merge, the old-build limit, tests); `docs/analytics.md` and
  `docs/privacy-policy.md` (above); `docs/terms-of-use.md` "Pictures and credits" (a saved or shared picture keeps its
  licence and credit; some are for viewing in Carden only).
- `docs/deep-links.md` and the association file; `docs/native-ui.md` (the viewer pattern); `docs/accessibility.md`;
  `docs/web.md` (Download, Share, the previews memory); `CLAUDE.md` code map (gallery, `cjw/photos`, previews cache).
- `docs/content-sources.md`, `docs/content-rules.md` and the pack-making skill (the copy rule per licence, the data
  fixes), only when no content session is running; the 2.1.0 review notes and What's New through the apple-release skill.

## Open decisions for the owner

1. Name and way in: (a) "Gallery", a Profile section with a shelf and See all; (b) one row on Profile; (c) "My
   Gallery", like My Puzzles. Recommended: (a).
2. Where favourites live: (a) a progress column, private and already synced; (b) a profile list, public to every player
   and adding to a crowded row; (c) a new table with its own reads, writes and deletion. Recommended: (a).
3. Credit on saved copies: (a) XMP in the file and the credit beside Save; (b) also a slim credit band under CC BY,
   BY-SA and Attribution pictures; (c) a band on every saved picture. Recommended: (a); (b) for the stricter reading.
4. Source link in shared text: (a) read `sourceUrl` at share time and map it to its page; (b) none; (c) a `sourcePage`
   column from the content tool's provenance after the repair. Recommended: (a) now, (c) later.
5. Pictures with incomplete licence data: (a) view-only until the data is fixed; (b) assume the provider's usual
   version. Recommended: (a), with the content fix before release.
6. Unsplash pictures via Lorem Picsum: (a) Save and Share with "Photo: <name>, Unsplash"; (b) view-only. Recommended: (a).
7. Share for pictures that allow no copies: (a) text and link only; (b) Share off too. Recommended: (a).
8. Heart on the win screen: (a) yes, except the guided first board; (b) on it too; (c) viewer only. Recommended: (a).
9. Favourites in the Library: (a) not in 2.1.0; (b) a Favourites chip; (c) a Home shelf later. Recommended: (a).
10. Preview cache: (a) every `/preview` URL in its own cache, app-wide; (b) only the gallery's tiles. Recommended: (a),
    which also keeps Library browsing from pushing out the pictures of boards in progress.
11. Link in shared text: (a) "Play it:" with the web link; (b) the Get Carden link (`AppLinks.getCarden`); (c) none.
    Recommended: (a).

## Effort and risks

Effort for one agent, about 9 working days: data and sync 1, page, shelf and viewer 3, licences, credit, XMP and share
1.5, native channel and web download 1, caches 0.5, QA and docs 2.

- Licence data: at the cache's numbers about a tenth of the catalogue is view-only until the content work adds versions
  and authors; Pixabay packs made later are always view-only.
- Review: a new permission prompt can bring a held build or questions about the purpose string.
- Memory: the viewer must bound its decodes (above); the web keeps its 32 MB picture memory for board pictures.
- Old builds: the rare "Two boards in progress" after a heart from a newer device; the web's localStorage copy of the
  rows grows by a few bytes a row (docs/sync.md "Known limits").
- Unverified: what iOS Photos shows of the XMP, Flickr's short page link, the simulator steps, previews billing, Web
  Share support per browser, the iPhone app on Apple silicon Macs and Vision Pro.

## Not in this task

- Albums, search, sorting by pack, deleting from the gallery; other players' galleries.
- A Favourites shelf on Home, Quick play from favourites, a widget with a favourite.
- A per-picture credit page with its own link preview (like the invite pages on `join.carden.page`).
- The content-data fixes (versions, authors, `sourcePage`) and Pexels or Pixabay specs: content work.
- A result card to share (board, stars, time), printing, wallpaper crops; saving on Android builds (MediaStore).
