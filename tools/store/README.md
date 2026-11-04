# App Store Connect automation

`asc_publish.py` pushes the metadata in `store/metadata/` to App Store Connect
through the official API, idempotently: it reads what exists, creates what is
missing and updates what differs, so it can be rerun after a partial failure.
`upload_build.sh` archives and uploads the iOS build. `compose_screenshots.py`
(separate tool) renders the screenshots the publisher uploads.

## Credentials

| What | Where |
| --- | --- |
| Team API key `9QC72A5QMN` (role App Manager or Admin) | `secrets/AuthKey_9QC72A5QMN.p8` (never committed); env vars `ASC_KEY_ID` and `ASC_KEY_PATH` override the id and the path (used by CI) |
| Issuer ID | env var `ASC_ISSUER_ID`, or the file `secrets/app-store-connect-issuer-id.txt` |

To find the Issuer ID: App Store Connect > Users and Access > Integrations >
App Store Connect API. It is shown at the top of the page as "Issuer ID"
(a UUID), above the list of team keys. Copy it:

```bash
echo "<issuer id>" > secrets/app-store-connect-issuer-id.txt
# or, per shell session
export ASC_ISSUER_ID=<issuer id>
```

The script exits with a message if neither is present. `secrets/` is
git-ignored; nothing in it is printed by the tools.

## Python

The script needs `pyjwt`, `cryptography` and `requests`:

```bash
python3 -m venv .venv && .venv/bin/pip install pyjwt cryptography requests
```

Below, `asc` stands for `.venv/bin/python tools/store/asc_publish.py`.

## What each subcommand does

| Subcommand | App Store Connect resources |
| --- | --- |
| `app-info` | `apps` (content rights = uses third-party content, App Store Server Notification URLs), `appInfos` categories (`categories.json`), `appInfoLocalizations` for the app's primary locale: name, subtitle, privacy policy URL |
| `version` | the editable `appStoreVersions` record renamed to 1.7.0 (or created), copyright, and the `appStoreVersionLocalizations`: description, keywords, promotional text, support and marketing URL, what's new |
| `age-rating` | `ageRatingDeclarations` from `age_rating.json` |
| `price-free` | `appPriceSchedules` with the free USA price point (Apple equalises the rest) and `appAvailabilities` (v2) for every territory |
| `screenshots` | one `appScreenshotSets` of type `APP_IPHONE_67` and every PNG in `store/screenshots/iphone-6.9/` in file order (reserve, upload, commit with MD5). The folder is the source of truth: an unchanged file is skipped, a changed one (MD5 differs) is replaced, and an uploaded screenshot with no file of its name is deleted |
| `iap` | the eight consumables from `subscriptions/consumables.json` (`/v2/inAppPurchases`), localizations, USD price equalised to all territories through `inAppPurchasePricePoints/{id}/equalizations`, availability, the review screenshot (`reviewScreenshot`: the file's default, `store/review/iap-review.png`, the top of the store, for the coins; a product's own replaces it: `store/review/iap-review-boosters.png`, the store scrolled to Tickets and Boosters, for `tickets_*` and `hints_*`; a changed file replaces the uploaded one) |
| `subscriptions` | group `VIP` and its localization, `vip_monthly` / `vip_yearly` attributes (Family Sharing on) and localizations, one `subscriptionPrices` per territory from `subscriptionPricePoints/{id}/equalizations`, one `subscriptionIntroductoryOffers` (1 week free) per territory, the `winBackOffers` from each file (only once the subscription is APPROVED: Apple refuses offers before), review screenshot, promotional image (one per plan: a missing or shared image stops the command; an image with another file name or checksum is replaced), availability. A field Apple refuses to change while the subscription sits in the open review draft (Family Sharing did) is patched by lifting the subscription's item out of the draft and putting it back |
| `review-info` | `appStoreReviewDetails`: contact from `review_contact.json` and `review_notes.txt` |
| `events` | In-App Event drafts (`appEvents`, their `appEventLocalizations` and the two `appEventScreenshots`) from `store/metadata/app_events.json`: the next world-day events (`--window N`, default 10) and the next major holidays after them (`--primary N`, default 5). Never submits. See "In-App Events" below |
| `platforms` | TestFlight on Macs and Apple Vision Pro for every beta group (`iosBuildsAvailableForAppleSiliconMac`, `iosBuildsAvailableForAppleVision`), then prints the App Store availability steps (no API for those) |
| `testflight` | `betaAppLocalizations` (feedback email, what to test, URLs), `betaAppReviewDetails`, `betaLicenseAgreements`, the build's `usesNonExemptEncryption=false` and what-to-test text, the build added to the external `betaGroups` "Public testers" (public link) and to every internal group that does not already get all builds, then a `betaAppReviewSubmissions` for the build. `--build N` waits for build N to appear and finish processing (30 s polls, `--timeout` minutes, default 40; fails on INVALID/FAILED); without it the latest build is used. `--whats-new-file PATH` replaces `release_notes.txt` as the what-to-test text (an empty file leaves it untouched). `ASC_BUILD_NUMBER` is the env fallback for `--build` |
| `build-notes` | Only the "What to Test" text (`betaBuildLocalizations.whatsNew`) of one build: `--build N` (default the latest), text from `--whats-new-file` or `store/metadata/en-US/testflight_build_notes.txt`. The release workflow sends that file for every new build, so rewrite it before each build with a TL;DR of what changed since the previous one. Visible to testers. |
| `release` | the `appStoreVersions` record for `--version X.Y.Z` (default: `pubspec.yaml`): found, renamed from the one editable version, or created when the newest version is already in review or live; `releaseType` MANUAL (approved versions wait for a click in App Store Connect; `--auto-release` for AFTER_APPROVAL); the build attached (`--build N`, else the newest processed build of that version); the primary-locale localization with what's new from `release_notes.txt` or `--whats-new-file` (a new localization gets description, keywords, URLs too; Apple's refusal of what's new on a first version is tolerated) |
| `submit` | the review submission: reuses the app's open `reviewSubmissions` (the one App Store Connect fills when a product is "submitted for review") or creates one, adds the `appStoreVersion` item, checks that every READY_TO_SUBMIT in-app purchase and subscription is an item, then sets `submitted: true`. Without `--yes` it only prints what would be submitted. Refuses while the audit lists a missing store item or a ready product is not in the submission (`--without-iap` to override the latter) |
| `status` | prints what exists; `--categories` also lists the category ids |
| `audit` | read-only checklist (OK / MISSING / N/A) for submission and for a public TestFlight link; exit code 1 while something is missing |
| `all` | `app-info`, `version`, `age-rating`, `price-free`, `screenshots`, `iap`, `subscriptions`, `review-info`, `testflight`, in that order (never `release` or `submit`) |

Every subcommand accepts `--dry-run`, which prints each request (method, URL,
JSON body) instead of sending it, and `-v` to also print GET requests.

Note on products in review submissions: the API links a submission item to an
`inAppPurchaseVersions` / `subscriptionVersions` record, but nothing links a
product to its version record. `submit` can therefore tell which products are
already in the open submission (they get there when "Submit for Review" is
pressed on the product's page in App Store Connect, which is what happened for
the eight consumables and the VIP group) but cannot add a missing one itself;
it names the missing products and stops.

Locale: the app's `primaryLocale` in App Store Connect is `en-GB`. The script
reads it from the app record and writes every localization to that locale; the
text itself lives in `store/metadata/en-US/` (the folder name is just where the
copy is kept).

## Before running

1. Fill in `store/metadata/en-US/review_contact.json` (name, phone, email).
   Placeholders in square brackets are skipped with a warning, and `audit`
   reports them as missing.
2. Generate the screenshots and the subscription images:
   `python tools/store/compose_screenshots.py` (writes
   `store/screenshots/iphone-6.9/*.png`, `store/review/subscription-review.png`) and
   `python tools/store/make_promo.py` (writes `store/promo/vip-monthly-promotional-1024.png`
   and `vip-yearly-promotional-1024.png`; needs node and a Chromium). Each plan has its own
   promotional image with no text, price or trial words (Guideline 2.3.2); `subscriptions`
   refuses two plans that share one.
3. Check the prices in `store/metadata/subscriptions/consumables.json` against
   `docs/purchases.md` and `lib/features/store/store_screen.dart`.

## Commands, in order

```bash
asc status                       # confirms the key works and shows what exists
asc all --dry-run                # review every request
asc app-info
asc version
asc age-rating
asc price-free
asc screenshots
asc iap
asc subscriptions
asc review-info
tools/store/upload_build.sh      # archive, export, upload (10 to 30 min of processing follows)
asc testflight                   # after the build shows up as processed
asc audit                        # everything should be OK or N/A
```

`asc all` runs the same steps without the upload. Rerunning any step is safe.

## Release flow

1. **Local device**: develop and test with `tools/dev/qa-run.sh run -d <simulator>` (QA runs) or
   `tools/dev/device.sh` (the owner's iPhone); bump `version:` in
   `pubspec.yaml` (the `+N` build number only matters for hand uploads).
2. **GitHub release**: publish a release with tag `vX.Y.Z` (the release body
   becomes the TestFlight "what to test" text).
3. **TestFlight, automatic**: the `Release to TestFlight` workflow archives,
   uploads the build as `100 + run number`, waits for Apple to process it,
   runs `asc testflight --build N --whats-new-file <release body>`: export
   compliance, what to test, the build in "Public testers" and the internal
   groups, Beta App Review submitted. Internal testers can install at once;
   the public link works once Beta App Review passes.
4. **Submit to App Store, manual**: run the `Submit to App Store` workflow
   (Actions > Submit to App Store > Run workflow) with the version and,
   optionally, the build number. It runs `asc release --version X.Y.Z
   [--build N]` then `asc submit --yes`. Nothing else ever submits the app for
   review. Locally the same is `asc release --version X.Y.Z --build N`, then
   `asc submit` to preview and `asc submit --yes` to send.
5. **Approve**: Apple reviews the version together with the products in the
   same submission.
6. **Release, manual**: the version is created with `releaseType` MANUAL, so
   after approval it sits in Pending Developer Release until someone presses
   "Release this version" in App Store Connect. Pass `--auto-release` to
   `release` (locally) if a version should go live by itself.

## Uploading a build

`tools/store/upload_build.sh` runs `flutter build ios --release --no-codesign`
(so the Flutter assets exist), then `xcodebuild archive` and
`xcodebuild -exportArchive` with `ios/ExportOptions.plist`
(method `app-store-connect`, automatic signing through the API key), then
`xcrun altool --upload-app` with the same key. The build number comes from
`pubspec.yaml` (`1.7.0+10`).

Export compliance: the app only uses HTTPS, which is exempt. Add
`ITSAppUsesNonExemptEncryption` = `NO` to `ios/Runner/Info.plist` so every
upload is marked exempt automatically; `asc testflight` also sets
`usesNonExemptEncryption=false` on the latest build for builds uploaded before
the key was added.

## Done in App Store Connect by hand

- **App Store Server Notifications**: the production and sandbox URLs are
  app attributes (`subscriptionStatusUrl`, `subscriptionStatusUrlForSandbox`,
  version V2) and `app-info` sets both to
  `https://cjw-verify-purchase.fra.appwrite.run/notifications`. If the console
  shows something else, set it under App > App Information > App Store Server
  Notifications.
- **App Privacy** (data collection questionnaire) has no public API: fill in
  App Store Connect > App Privacy. The honest answers for this app are in
  `docs/privacy-policy.md` (account id, email if given, purchase history,
  gameplay content; usage data and coarse location for analytics, see
  `docs/analytics.md`; no tracking, no third-party advertising).
- **Agreements**: Paid Applications agreement, banking and tax forms
  (App Store Connect > Business).
- **Products in the review submission**: press "Submit for Review" on each
  in-app purchase and subscription page once, which puts it into the app's
  open review submission; `asc submit` then submits them with the version
  (the API cannot add them, see the note above).
- **Releasing**: after approval, press "Release this version" (the version
  uses manual release).
- **Sandbox tester** for verifying purchases on a device:
  Users and Access > Sandbox.

- **Macs and Apple Vision Pro**: App Store Connect > Pricing and Availability >
  "iPhone and iPad Apps on Apple Silicon Mac" and "iPhone and iPad Apps on Apple
  Vision Pro": tick "Make this app available" in both, Save (no API; `platforms`
  prints the same steps and keeps TestFlight on both platforms switched on).
- **Submitting In-App Events**: the drafts `events` creates go to App Review
  with the first App Store version (add them to that submission in App Store
  Connect > In-App Events, or after the app is live submit them on their own).

## In-App Events

Every world-day event (table `events` with its free event pack) can be an
In-App Event card on the App Store and in search, opening the pack
(`carden://library/pack/<packId>`; every link the app reads is in
`docs/deep-links.md`).

1. `.venv/bin/python tools/store/make_app_events.py` writes
   `store/metadata/app_events.json` from the live catalogue (one billed read:
   the snapshot pointer). Per event: reference name = event id, badge Special
   Event, purpose "appropriate for all users", priority normal, no purchase
   needed (event packs are free), the event window as the event dates, publish
   3 days before it opens (`PUBLISH_DAYS_BEFORE`: the day the app starts
   listing the event pack, `Pack.soonWindow`; an earlier card would link to a
   pack the app does not show yet), the event's name (30 characters), "24
   pictures for World Food Day" (50) and the pack's subjects (120). Hand edits
   survive a re-run when the entry has `"locked": true` (three long names are
   shortened that way; the Thanksgiving, Christmas 2026 and New Year's Eve 2026
   cards avoid pictures with a watermark, a brand logo or the wrong occasion;
   the entry's `note` says why); a locked entry's publish date still follows
   the 3-day rule. Major holidays (`PRIMARY` in the script:
   Christmas, New Year's Eve, Lunar New Year, Valentine's Day, Easter,
   Mother's Day, Father's Day, Halloween, Diwali, Thanksgiving) are marked
   `"primary": true`.
2. `make_app_events.py --media-next 10` builds the images for the events the
   next step drafts (the next 10 and the next 5 major holidays after them;
   `--primary N` changes the 5): the event card (1920x1080, three of the
   pack's pictures with the cover in the middle) and the details page
   (1080x1920, the cover), JPEG, no text. They live in
   `~/.local/share/card-jigsaw-world/app-events/` (outside git;
   `CJW_APP_EVENT_MEDIA` overrides), built from our hosted pictures. Look at
   every new card before uploading: pack pictures can carry logos,
   watermarks or a frame edge that reads as a border.
3. `asc_publish.py events` creates or updates the drafts for the next 10
   events that start at least two days from now, plus the next 5 major
   holidays after them (`pick` in `make_app_events.py`; `--window`,
   `--primary`). Apple publishes at most 10 events at a time and keeps 15
   approved, so the 5 extra slots let the big days be reviewed months ahead.
   Accepted, published or past events are left alone. Nothing is ever
   submitted: an unreleased app must send its first events with its first
   version; afterwards events can go to review on their own. Re-run both
   steps every few weeks to roll the window forward.

Apple's rules (2026): event at most 31 days, shown up to 14 days before it
starts, no prices or app name in the text, no text or borders on the art.

## Files the script reads

```
store/metadata/en-US/
  name.txt subtitle.txt promotional_text.txt description.txt keywords.txt
  release_notes.txt support_url.txt marketing_url.txt privacy_url.txt
  copyright.txt review_notes.txt review_contact.json age_rating.json
  categories.json testflight_what_to_test.txt beta_license_agreement.txt
store/metadata/subscriptions/
  group.json vip_monthly.json vip_yearly.json consumables.json
store/metadata/app_events.json   (make_app_events.py; media in ~/.local/share/card-jigsaw-world/app-events/)
store/screenshots/iphone-6.9/*.png
store/review/subscription-review.png
store/review/iap-review.png            (coins_*: the top of the store, raw/11_store)
store/review/iap-review-boosters.png   (tickets_*, hints_*: raw/35_store_boosters_light, by make_promo.py)
store/promo/vip-monthly-promotional-1024.png, vip-yearly-promotional-1024.png   (make_promo.py)
```

## VIP gift codes (subscription offer codes)

`tools/store/offer_codes.py` manages Apple's native subscription offer codes.
Two free offers exist in App Store Connect: "VIP Monthly gift" (1 month free)
and "VIP Yearly gift" (1 year free), open to new, existing and expired
subscribers. Codes are *custom codes* with a redemption limit of 1 and no end
date, which makes each one single-use and valid until redeemed or deactivated.
(One-time-use codes were ruled out: Apple requires batches of at least 500,
caps them at six months and only allows them once the app is Ready for Sale.)

Apple refuses to create codes while the app is not live and the subscriptions
are not approved (`OFFER_CODE_APP_STATE_INVALID`). Once version 1.7.0 and the
VIP subscriptions are approved, run:

```
venv/bin/python tools/store/offer_codes.py codes monthly 10
venv/bin/python tools/store/offer_codes.py codes yearly 10
venv/bin/python tools/store/offer_codes.py list
```

Codes and their redemption links are saved to `secrets/vip-offer-codes.json`
(git-ignored). Players redeem them in the app (Store > "Have a gift code?" or
Settings > "Redeem a gift code"), through the App Store app, or by opening
`https://apps.apple.com/redeem?ctx=offercodes&id=6821644423&code=<CODE>`.
Codes take up to an hour to become redeemable after creation.

App Store Connect pages: monthly offers at
https://appstoreconnect.apple.com/apps/6821644423/distribution/subscriptions/6821645754
and yearly at https://appstoreconnect.apple.com/apps/6821644423/distribution/subscriptions/6821646642
(section "Offer Codes").
