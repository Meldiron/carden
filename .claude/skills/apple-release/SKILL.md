---
name: apple-release
description: Ship Carden to TestFlight and the App Store without triggering extra Apple reviews. Use for any request to release, push a build, cut a version, submit for review, or get a build to public or internal testers.
---

# Apple release workflow for Carden

## The one rule
Apple reviews TestFlight builds for **external testers once per version string**
(CFBundleShortVersionString). A new version string always starts a full Beta App Review (1 to 7
days). The App Store version record must match the version string of the build you attach to it.
Therefore: **one version string per App Store release cycle; TestFlight iterates by build number
only** (the version is what customers see, the build number is a sub-version that must only go up:
1.7.0 (117), 1.7.0 (118), ...; the App Store can take any of them without a new version).

Later builds of an approved version still get a beta review submission (the workflow files it), and
Apple usually approves those within minutes. But Apple may hold **any** external build for a real
review, most often when it adds a permission prompt (a new `NS...UsageDescription`, a new
entitlement or capability) or a large change. Ship such changes early in a cycle, name them in the
build's "What to Test", and do not promise testers a time.

## What may change without a build
Server-side changes (catalogue, prices, events, pack rows, the `releases` table, function code) are
fine as content and configuration. A switch may turn on or off only what the reviewed binary already
contains; a feature that reviewers never saw must ship in a build and be described in the review
notes (guideline 2.3.1 hidden features; no downloaded code, 2.5.2). Pack codes and hidden packs are
such a feature: say so in `store/metadata/en-US/review_notes.txt`.

## Old builds stay in use
Assume the client is outdated, the network unreliable and releases slow (Apple processing, beta
review, testers who do not update; a TestFlight build lives 90 days). Every backend change must keep
every build still in testers' hands working:
- Add columns with defaults; never rename or remove a column, enum value or row id that a live build
  reads or writes (the ledger enum stayed `coins, tickets, hints` for this reason).
- Deploy the server first (functions, tables), then the build that needs it.
- A change that cannot stay compatible needs a minimum build ("Update required", see
  `docs/app-updates.md`; only "Update available" exists today). Example: the 2026-10-14 starter
  packs locked formerly free packs for testers on build 115 until they updated.

## Tooling
No fastlane: `tools/store/asc_publish.py` (metadata, screenshots, products, TestFlight, review),
`tools/store/install_profiles.py` + `ci_manual_signing.py` (signing in CI) and the workflows cover what
fastlane's deliver/match/pilot would. Keep it that way unless the owner asks; the scripts are
readable and do exactly what the docs say.

## Commands
| Goal | Command | Effect |
| --- | --- | --- |
| Install on the phone (only when the owner asks) | `tools/dev/device.sh [--wipe] [--no-build]` | release build, installs on the paired iPhone |
| Next TestFlight build of the current version (only when the owner asks) | `tools/dev/testflight.sh` | runs the `Release to TestFlight` workflow; build = 100 + run number; waits for processing, adds to internal + public groups, submits beta review only if the version has none; then announces the build to the in-app update prompt (`publish_release.py testflight`) |
| Announce a build to the update prompt by hand | `.venv/bin/python tools/dev/publish_release.py testflight --build N` / `appstore --version X.Y.Z` / `show` | writes `releases/ios-testflight` or `ios-appstore` (`docs/app-updates.md`) |
| Start a new version cycle | `tools/dev/release.sh X.Y.Z` | bumps pubspec, commits, pushes, first build; only after the previous version shipped to the store or was abandoned |
| Submit to App Review | Actions → `Submit to App Store` (version, optional build) | `asc_publish.py release` + `submit --yes`; always human-started |
| Record a store release | `tools/dev/tag-store-release.sh X.Y.Z` | tag + GitHub release + `releases/ios-appstore` for the update prompt; never for TestFlight cuts |
| State of everything on Apple | `tools/store/asc_publish.py audit` / `status` | builds, review states, metadata gaps |
| Tester feedback | `asc_publish.py feedback` / `--resolve ID,ID --note ...` | list, then delete on Apple + local ledger after fixing |

Run scripts with the venv python that has pyjwt/requests (see tools/store/README.md)
or plain python3 with those packages installed. Credentials live in `secrets/`.

## Every build also updates the web site
After `tools/dev/testflight.sh` always run `tools/dev/deploy-web.sh` so https://play.carden.page ships the same commit (owner rule, 2026-10-12). Both can run in parallel only if the Flutter builds do not overlap; run the web deploy after the device/TestFlight build finishes.

## Per-build "What to Test"
Before each build rewrite `store/metadata/en-US/testflight_build_notes.txt` with a TL;DR of what
changed since the previous build (2-4 plain bullets, one "Please try:" line); the workflow sends it as
that build's TestFlight "What to Test". `release_notes.txt` stays the App Store "What's New" for the
whole version. `asc_publish.py --build N build-notes` rewrites one existing build's text.

## Before an App Store submission
On top of the TestFlight checks below (the guideline review of 2026-10-15 found these gaps):
1. Retake the store screenshots from the build you submit (the store-screenshots skill: captures,
   `tools/store/compose_glass.py`, then `asc_publish.py screenshots`). They must show the current
   app; the 2026-10-13 set still showed a seasonal league that no longer exists.
2. Rewrite `store/metadata/en-US/review_notes.txt` so every feature is described specifically
   (purchases and how to test them, pack codes, the Lucky Wheel odds, sources of the pictures).
3. Check `docs/privacy-policy.md`, the App Privacy answers in App Store Connect and the age rating
   (`store/metadata/en-US/age_rating.json`) against what the build does.
4. Attach the final build (`asc_publish.py release --build N`) and submit the products and the VIP
   plans together with the version.
5. Do not ship a newer TestFlight build while the version is in review.
6. Take any In-App Event whose publish date has passed out of the draft first (DELETE its
   `reviewSubmissionItems/{id}`; the event stays a draft). Apple refuses the whole submission with 409
   `appEvents with id ... is not in valid state` otherwise (2.0.0, 2026-10-18: UN Day).

## Before every upload
1. `git status` clean, main pushed, analyzer and tests green, QA runs silent and flagged
   (`tools/dev/qa-run.sh`: `CJW_MUTE=true`, `CJW_QA=true`, test players purged), and no test players
   left: `python3 tools/dev/purge_test_players.py purge` lists none (`--apply` removes them).
2. Check builds: if a build of the **current** version is already in or past beta
   review, keep it (its approval covers the new build). Do not upload an older
   version string than the one in review.
3. Expire superseded builds of other version strings (`PATCH /v1/builds/{id}` with
   `expired: true`); this also cancels their pending review so they do not compete.
4. Never expire the build that is attached to the App Store version while it is
   the only approved one.

## When the user says
- Never start a build, submission or web deploy on your own: only these explicit requests do.
- "release", "push a build", "ship to testers" → `testflight.sh`, keep the version.
- "new version", "bump", "App Store release" → `release.sh X.Y.Z`, then later the
  `Submit to App Store` workflow, then `tag-store-release.sh` after it is live.
- "cancel the review" → expire that build only if another build of the same version
  is not needed; otherwise leave it, the review carries over.

## Groups
- Internal testers (`hasAccessToAllBuilds`): see every processed build at once.
- Public testers: public link https://testflight.apple.com/join/7nPCfg6A, only
  builds of a version that passed Beta App Review.

## Related docs
`docs/release-flow.md`, `docs/release-checklist.md` (its last section lists possible pipeline
improvements: notes only, not started without the owner's go), `tools/store/README.md`.

## Renaming in-app purchases while they sit in a review draft
If products were added to the app's open review submission ("Submit for Review" on the products in App
Store Connect), their en-GB localization (customer name and description) is locked: PATCH and DELETE
fail with 409 "version is not editable", even though the localization says PREPARE_FOR_SUBMISSION.
`asc_publish.py iap` still updates reference names and review notes. To change the customer text:
for each product, DELETE its `reviewSubmissionItems/{id}` (the item that points at its
`inAppPurchaseVersion`), PATCH the `inAppPurchaseLocalizations/{id}`, then POST a new
`reviewSubmissionItems` with relationships `reviewSubmission` + `inAppPurchaseVersion`. The draft is
never submitted by this. Done this way for the 2026-10-12 amount change (all 8 consumables).
The review screenshots of products and VIP plans are locked the same way (DELETE answers 409
MEDIA_ASSET_DELETE_NOT_ALLOWED). On 2026-10-15 the items were taken out (item ids are base64 of
`submission|type|resource`: 17 = inAppPurchaseVersion, 18 = subscriptionVersion, 19 =
subscriptionGroupVersion; save them first), `asc_publish.py iap` and `subscriptions` replaced the
changed screenshots (they swap a file whose checksum changed), and the 10 items went back in.

## "expected 2 profiles, installed 1" in the workflow
Editing an App ID on the developer portal (its name, capabilities) turns its App Store profile
INVALID, and `tools/store/install_profiles.py` only installs ACTIVE ones. Recreate it under the same
name: `GET /v1/profiles?include=bundleId,certificates` to find the invalid one, its bundle id and the
distribution certificate, `DELETE /v1/profiles/{id}` (Apple refuses a second profile with the same
name), then `POST /v1/profiles` with `name` (`CJW AppStore cardjigsawworld` or `CJW AppStore
DailyWidget`), `profileType: IOS_APP_STORE` and relationships `bundleId` + `certificates`. Then
`gh run rerun <run id>`: nothing was uploaded, so the build number stays. Happened 2026-10-13 after the
App ID description was renamed.

## Payment function deploys
Purchases are checked by `api` (`/purchase/verify`, builds after 124) and by `verify-purchase` (builds up
to 124, and Apple's notifications); both hold `GRANTS` (docs/functions.md). The repo's API keys cannot
deploy functions: use the Appwrite CLI signed in as the owner (docs/functions.md has the command), the
Appwrite MCP (`functions_create_deployment`, base64 content of
`COPYFILE_DISABLE=1 tar --exclude node_modules -czf verify-purchase.tar.gz -C functions/verify-purchase .`,
`activate: true`, entrypoint `src/main.js`, commands `npm install`) or the console. Then check
`https://cjw-verify-purchase.fra.appwrite.run/health` and run `node tools/dev/api_check.mjs`. Deploy both
before a build that shows new amounts, so the server never credits less than the app displays.
