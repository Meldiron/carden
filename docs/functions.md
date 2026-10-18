# Appwrite Functions

Owner, 2026-10-17: every server call of the app goes to **one** function, `api`, with a path per
feature. A function that is called often stays warm; seven functions that are each called now and
then each start cold (4 to 5 s before the function's own work; 7.4 s for a co-op create). One function
shares everyone's calls, so a player meets a cold start far less often.

## `api` (functions/api)

| Path | Module | What | Was |
| --- | --- | --- | --- |
| `POST /purchase/verify` | `src/purchase.js` | a StoreKit transaction, granted once (docs/purchases.md) | `verify-purchase` `/verify` |
| `POST /purchase/notifications` | `src/purchase.js` | App Store Server Notifications V2, each applied once ("Apple's notifications", below); Apple still sends them to `verify-purchase` until `api` may be executed without a session | `verify-purchase` `/notifications` |
| `POST /account/delete` | `src/account.js` | Account > Delete account | `delete-account` `/delete` |
| `POST /code/redeem` | `src/code.js` | a pack code, on the web (docs/pack-codes.md) | `redeem-code` `/redeem` |
| `POST /coop/create`, `/join`, `/leave`, `/remove`, `/end`, `/next` | `src/coop/game.js` (+ `rules.js`) | Play together (docs/multiplayer.md) | `coop-game` `/<action>` |
| `POST /gift/send` | `src/gift/send.js` (+ `gift.js`) | friend gifts (docs/friend-gifts.md); the push leaves out targets in the Messaging topic `gifts-off` (docs/notifications.md; needs the scopes `subscribers.read` and `targets.read`, without them every target gets it) | `send-gift` `/send` |
| `POST /coop/cleanup` | `src/coop/cleanup.js` | the co-op cleanup on demand, for a caller who is not a player (the owner's CLI) | `coop-cleanup` `/run` |
| `POST /admin/sweep` | `src/sweep/run.js` | the integrity sweep on demand, same callers: `{dryRun = true, full, qaOnly}` (below) | new |
| `GET /health` | `src/main.js` | `{ok, environment, maxPlayers, appleSignIn}`; the app's warm-up call | every function's `/health` |
| `GET /<code>`, `/join/<code>`, `/.well-known/apple-app-site-association` | `src/invite/` | a Play together invite's page and link preview at `https://join.carden.page/<code>`, for anyone ("Invite pages", below) | new |
| schedule `0 * * * *` | `src/coop/cleanup.js`, `src/sweep/run.js`, `src/gift/send.js` | every hour: the co-op cleanup, then the integrity sweep, then inbox pushes older than a day leave Messaging's log (`cleanPushLog`) (an execution with trigger `schedule`, whatever its path) | `coop-cleanup` |
| event `tablesdb.cjw.tables.blocks.rows.*.create` | `src/sweep/run.js` | a new `blocks` row is checked at once (subscribed as `databases.cjw.tables.blocks.rows.*.create`) | new |

Each module answers as its old function did (same bodies, same status codes), so the app reads the
same answers; only the router (`src/main.js`) is new. Modules load on their first call, so a cold
start loads only what that call needs (the App Store library only for purchases). Nothing runs at the
root path or at the old paths (`POST /` used to delete the caller's account on `delete-account`).

Settings: Node 22, entrypoint `src/main.js`, build `npm install`, execute `users` (guests too), timeout
300 s (the cleanup; a synchronous call from the app is cut at 30 s by Appwrite anyway), scopes `rows.read
rows.write users.read users.write files.read files.write teams.read teams.write messages.read
messages.write` (the union of the old functions'). Variables: `APPLE_BUNDLE_ID`, `APPLE_APP_ID`,
`APPLE_ENVIRONMENT` (`Production`), `APPWRITE_DATABASE_ID` (`cjw`), `APPLE_SIGNIN_KEY` (the contents of
`secrets/AuthKey_2QJPJFW8JW.p8`; `/health` says `appleSignIn: "set"` when it reads), all secret, and
`SWEEP_APPLY` (`true`: the scheduled and event sweeps change rows; anything else: they only report).
A changed variable reaches the function with its next deployment. Domain `https://cjw-api.fra.appwrite.run`
(proxy rule, 2026-10-17, for Apple's notifications); it follows the active deployment and answers 403
`router_unauthorized_execution` to every caller while execute is `users`. Domain `https://join.carden.page`
(proxy rule `2bde7e62412563d6f56a0542b454d9ab`, 2026-10-17, the invites' own address; the DNS record
came with it, carden.page being on Appwrite): there the router answers invite pages and nothing else
(any other path 404, `/` goes to the web game). Both domains need execute `any`.

Deploy with the Appwrite CLI signed in as the owner, from a folder holding an `appwrite.config.json`
with `{"projectId": "6acb4de5003e38d5ebd9", "endpoint": "https://fra.cloud.appwrite.io/v1"}`: copy
`functions/api` without `node_modules`, then `appwrite functions create-deployment --function-id api
--code <copy> --activate --entrypoint src/main.js --commands "npm install"`. A deployment changes only the
code; the variables stay. Then `node tools/dev/api_check.mjs`: every route as QA players on the live
backend (purchase and notification refusals, every route without a session through the REST API and
the domain, a pack code made for the run, gifts, a co-op game, an account deletion), answers and
timings, everything cleaned up afterwards; `node tools/dev/security_check.mjs` for the sweep and the
gift limits (below). Tests: `cd functions/api && npm install && npm test` (router and callers without a
user, purchases, notifications, co-op rules, gifts and their limits, the sweep, the twins below).

Deployments: `6ad3928e2403472dffb0` (2026-10-17, the first live one), `6ad39945ee63affa160d` (2026-10-17:
the integrity sweep with `SWEEP_APPLY`, the `blocks` event, gift limits, names without links),
`6ad3b2b2b1585e1b9f4e` (2026-10-17: Play together's live rows, `coop_drags`, docs/multiplayer.md, "Live
picks and drags": made on `/coop/create` and `/coop/join`, deleted on leave, remove, the cleanup,
account deletion and by the sweep; `delete-account` holds the same account code, redeploying it is
optional since builds up to 124 never get live rows), `6ad3e5a1ef69e35d38a6` (2026-10-17: Apple's
notifications applied once, `/coop/cleanup` and `/admin/sweep` refuse calls without a user),
`6ad3f4f8d10fa43ea7be` (2026-10-18: invite pages and cards, below; first live as `6ad3eb9d92b6534bf740` on 2026-10-17).

### Invite pages

`https://join.carden.page/<code>` is the address the app shares for Play together from build 127
(docs/multiplayer.md, "Invite links"). Messages, WhatsApp, Messenger and the rest read a link's preview
from the page's static meta tags, so this page is made per invite, for crawlers and people alike (no
redirect, no user-agent test): "Mia invites you to play Red Panda", "Play together in Carden · Cards
7x7 · 2 of 5 players" and the game's own card as `og:image`. It reads three rows (the game by its code,
the picture, the host's display name through the name filter) and shows nothing else: no player id, no
game id. An ended or unknown code gets the site's own card and words ("This game has ended" on the page).

- `src/invite/paths.js` decides, without loading anything, which requests are the page's (a GET on
  `join.carden.page`, `/<code>` or `/join/<code>` on any domain, the association file); `page.js` makes
  the page and the association file (`/????????` and `/join/*` open the app; the root stays in the browser).
- The card (`card.js`, 1200 x 630 JPEG, 50-140 KB): the picture dealt in the board's real shapes and size
  (`tiling.js`, a port of `lib/game/tiling.dart`: piece counts and shapes are the game's), a few pieces of
  the same shape swapped and one lifted, the picture blurred and zoomed behind, the logo and the board in
  words ("Cards 7x7", "49 cards", "Painting"). The words come from an atlas set in SF Pro Rounded
  (`assets/invite/`, made by `tools/brand/invite_card.py`), so only words listed there can be drawn.
  Drawing is plain JavaScript (`raster.js`: PNG decode with Node's zlib, resampling, blurs, rounded pieces
  by signed distance; `jpeg.js`: a 4:2:0 baseline encoder). A native library was tried first: Skia
  (`@napi-rs/canvas`, an 18 MB build) made every cold start of `api` about 1.2 s slower (measured on a probe
  function: 5.4-6.1 s against 3.7-5.6 s), for every call of the app; this adds 0.1 MB.
- Cards live in the public bucket `invite-cards` (read `any`, written only by `api`), keyed by picture,
  board, Painting and week (`store.js`, `cardId`), so games on the same picture and board share one. A new
  game's card is drawn right after `/coop/create` answers (`prepareCard`, not awaited), in a worker thread
  so the function's other calls keep their event loop; a next board's card is drawn when its page is first
  asked for. Drawing takes about 2 s of the runtime's half CPU (a worker cannot lower its share inside the
  container's CPU quota: measured, `setPriority` changes nothing), so calls on the same instance run slower
  for those seconds. The page waits for a card being drawn up to 8 s, then shows the site's card (and is
  not kept). The hourly run deletes cards older than ten days (`cleanCards`; a page names only this week's).
- Appwrite's edge keeps a page as `Cache-Control` says (`s-maxage=600`; measured: later readers get it in
  20-30 ms without an execution), so the friend who taps a link after its preview was read never waits for
  the function, cold or not.
- Checked by `functions/api/test/invite.test.mjs` (piece counts and coverage against the game, the words,
  the page's tags and what it leaves out, the association file, the card's size, the bucket) and live by
  `tools/dev/api_check.mjs` (the page as Messages, WhatsApp, Facebook and Safari read it, the card, the
  domain answering nothing else, an ended and an unknown code).

### Apple's notifications

App Store Server Notifications V2 (renewals, expiries, refunds, Family Sharing changes; docs/purchases.md)
are applied once each. A notification's `notificationUUID` is the id of its row in `apple_notifications`
(server only: no permissions, no row security), created before anything changes, as a purchase claims its
transaction. Apple sends a notification again when it did not get a 200 (five more tries, 1, 12, 24, 48
and 72 hours after the one before: about 6.5 days in all); a second delivery answers `{ ok: true, alreadyApplied: true }` and changes nothing. A failure half
way deletes the row (Apple's next try applies it); a row still `pending` after 10 minutes belongs to a call
that died and is taken over. Columns: `type`, `subtype`, `environment`, `signedAt`, `claimedAt`, `result`
(`pending`, `applied`, `nothing`, `unmatched`, `ignored`, `test`), `profiles` (how many were updated) and
`via` (the function that took it). No transaction id and no player, so nothing in it outlives an account
deletion. `api` and `verify-purchase` share the table, so a notification is applied once whichever
function gets it. Signatures are checked against Apple Root CA G3 in the configured environment
(Production), then Sandbox (TestFlight, App Review); a payload Apple did not sign gets 401 and leaves no row.

Moved 2026-10-17: `api` has execute `any`; Apple's production and sandbox URLs point at
`https://cjw-api.fra.appwrite.run/purchase/notifications` (`asc_publish.py app-info`, read back from Apple).
Apple kept delivering to the old address for about 25 minutes after the change (two TEST notifications
`via verify-purchase`); the third arrived `via api` (`b1f167f7-...`). `verify-purchase` stays for builds up to
124's `/verify` and for Apple's retries of older notifications (about a week).

`.venv/bin/python tools/dev/apple_notifications.py test` asks Apple for a TEST notification to the
Sandbox URL, waits for Apple's delivery result and reads its row (`test via <function>`); `history
--days N` lists what Apple sent and the row each left. The App Store Connect key in `secrets/` works for
Sandbox; Production needs an In-App Purchase key (the tool's docstring).

Checked live (2026-10-17): Apple's Sandbox TEST notifications `2a24ee87-...` and `dc4ddda7-...` arrived
at `verify-purchase` (delivery `SUCCESS`, row `test via verify-purchase`). A real Apple-signed Sandbox
notification from Apple's history (`ONE_TIME_CHARGE`, `tickets_5`, no matching profile) was sent to
`api`'s `/purchase/notifications` (as a QA player: verified with the Sandbox fallback, `unmatched`, row
`via api`), then to `verify-purchase`'s `/notifications` and to `api` again: both answered
`alreadyApplied`.

## Which function serves which builds

| Function | Called by | Status |
| --- | --- | --- |
| `api` | builds after 124 and the web game from its next deploy | live |
| `verify-purchase` | builds up to 124 (`/verify`, `/health`); Apple's App Store Server Notifications for every build until their URL moves to `api` (`https://cjw-verify-purchase.fra.appwrite.run/notifications`, also in `tools/store/asc_publish.py`; below) | frozen, deployed, the same purchase and notification code as `api`: `6ad3e5a28fffd15bb600` |
| `delete-account` | builds up to 124 | frozen, deployed |
| `redeem-code` | builds up to 124 (the web game until its next deploy; iPhone builds from before 2026-10-16 had code entry too) | frozen, deployed |
| `coop-game` | builds up to 124 that have Play together | frozen, deployed |
| `send-gift` | builds up to 124 that have friend gifts | deployed, kept equal to `api`'s gift code (the gift limits must hold for every caller): `6ad3970c70f2bbcfaa22` |
| `catalog-snapshot` | its own daily schedule (03:00 UTC); every build reads the file it writes | stays apart (below) |
| `coop-cleanup` | its hourly schedule | deleted 2026-10-17 once `api`'s scheduled run had run |

`catalog-snapshot` stays its own function: it runs once a day for up to 5 minutes, reads the whole
catalogue and nobody waits for it, so it gains nothing from being warm, and inside `api` it would hold
an instance busy for minutes while players' calls queue behind it.

### Retiring an old function

Delete an old function only when no build that calls it can still be used:

- A TestFlight build expires 90 days after its upload, so the frozen functions can go 90 days after
  the last build that calls them (build 124) was uploaded (`asc_publish.py status` lists the
  dates), and not before the web game has been redeployed with `api`.
- No App Store version has shipped yet. If one ships with a build up to 124, its functions stay until a
  minimum build ("Update required", docs/app-updates.md) moves its players on.
- `verify-purchase` also stays while Apple's notification URL points at it. Once the URL points at
  `api`, it only serves `/verify` for builds up to 124 (and notifications Apple may still send again to
  the old address, for about a week) and goes with the other frozen functions (the first rule).

Moving Apple's notifications to `api` (2026-10-17). Done: `api` applies them as `verify-purchase` does
(twins), both record each one in `apple_notifications` ("Apple's notifications", above), `api` has the
domain `cjw-api.fra.appwrite.run`, `/coop/cleanup` and `/admin/sweep` refuse calls without a user, and
`api_check.mjs` calls every route without a session. Left, for the owner (widening who may execute `api`
on the live backend is the owner's call; the agent's run was not allowed to):

1. Give `api` execute `any`. `functions update` puts every setting it is not given back to its default
   (schedule, events, scopes, timeout), so pass them all, from a folder with the project's
   `appwrite.config.json`:
   `appwrite functions update --function-id api --name api --runtime node-22 --execute any --events
   'databases.cjw.tables.blocks.rows.*.create' --schedule '0 * * * *' --timeout 300 --enabled --logging
   --entrypoint src/main.js --commands 'npm install' --scopes rows.read --scopes rows.write --scopes
   users.read --scopes users.write --scopes files.read --scopes files.write --scopes teams.read --scopes
   teams.write --scopes messages.read --scopes messages.write --build-specification s-2vcpu-2gb
   --runtime-specification s-0.5vcpu-512mb`, then `appwrite functions get --function-id api` and compare.
   Only with a deployment that refuses calls without a user on the admin routes (`6ad3e5a1ef69e35d38a6` or
   later; `router.test.mjs`): before it, a call without a user counted as the owner.
2. `node tools/dev/api_check.mjs`: the no-session checks then expect each route's own refusal (only
   `/health` and the notifications route answer), and that `x-appwrite-*` headers sent to the domain do
   not count.
3. Set `NOTIFICATIONS_URL` in `tools/store/asc_publish.py` to
   `https://cjw-api.fra.appwrite.run/purchase/notifications` and run `.venv/bin/python
   tools/store/asc_publish.py app-info --dry-run`, then without `--dry-run` (Production and Sandbox URLs;
   it also syncs categories, name, subtitle and privacy URL, so read the dry run).
4. `.venv/bin/python tools/dev/apple_notifications.py test`: the row must say `test via api`. Production
   cannot be tested without an In-App Purchase key; it runs the same route.

Back: point the URLs at `verify-purchase` again (step 3) and set execute back to `users` (step 1).

### Twins while old builds are in use

The frozen functions are copies of the modules. A change that old builds must get too goes into both,
and the old function is redeployed. Anything that limits players goes into both: the old functions are
callable by any signed-in client, whatever build it is.

- What an account deletion removes: `src/account.js` and `functions/delete-account/src/main.js` must
  hold the same code (`functions/api/test/twins.test.mjs`).
- Friend gifts: `src/gift/` and `functions/send-gift/src/` hold the same code (the daily limit, the
  notification rules, the name filter; `twins.test.mjs`, and `test/friend_gifts_test.dart` for the
  app's side).
- Purchases and Apple's notifications: `src/purchase.js` and `functions/verify-purchase/src/main.js`
  hold the same code from the imports to `environmentName` (the grants, the checks, the notification
  record; `twins.test.mjs`; `GRANTS` also `test/economy_test.dart`).
- Co-op: builds up to 124 (`coop-game`) and later builds (`api`) play in the same games (same rows and
  teams), so a change to the rules in `src/coop` must keep games made by either working.

## Security (review of 2026-10-17)

### Integrity sweep (`src/sweep/`)

Players write their own rows, and the app gives some of them a predictable id, md5 of
`<owner>:<key>` (progress, event_progress, friends, blocks). Another player can create a row at that
id first: the owner's write is then refused (401) and their read finds nothing (404); checked live.
Appwrite lets a client grant only roles it holds, so such a row names the wrong player in its
permissions, or carries an id that is not its owner's. The sweep, every hour over rows changed in the
last two hours and once a day (04:00 UTC) over everything:

| What | Rule | Action |
| --- | --- | --- |
| progress, event_progress, friends, blocks | the owner (`userId`, or `blockerId`) lacks `update`, another player is named, or a 32-character id is not md5 of owner and key | delete (the owner's app writes it again). Rows with a 20-character `ID.unique()` id (older rows, rows the app makes when its id is taken) are checked by permissions only |
| profiles | no user has the id (an hour after it was made); another player named in the permissions | delete |
| profiles | only the owner named, but not `read(any) update(user) delete(user)` | permissions put back (QA players' rows, `isTest`, are left to `purge_test_players.py`) |
| user-uploads | no My Puzzles row of a player the file belongs to, an hour after the upload | delete |
| user-uploads | readable or changeable by anyone but its owner | made `read(user) delete(user)` of the owner |
| user-uploads | more than 500 photos of one player (`FILES_PER_PLAYER`; "no limit with VIP" in the app, far above real use) | the newest past 500 go, row and file |
| names | `profiles.displayName`, `friends.friendName`, `blocks.blockedName` refused by the name filter (offensive, a link, an @handle or e-mail, a domain) | `Player` |

A new `blocks` row is checked by its create event at once, so nobody is kept from blocking a player
for an hour. Reads are paged, deletes go 100 at a time, the run logs its counts. On demand, as the
owner: `appwrite functions create-execution --function-id api --path /admin/sweep --method POST
--body '{"full":true}'` (a dry run; `"dryRun":false` applies; `"qaOnly":true` touches only rows of QA
players). The first full dry run on the live backend (2026-10-17: 122 users, 101 profiles, 333 progress
rows, 1 photo) found nothing to change; the rules were then checked live with QA players
(`tools/dev/security_check.mjs`: a squatted block and progress row, a name with a link, a public photo;
dry run, then the run; the victim blocks and saves again) and `SWEEP_APPLY` was set to `true`.

The app (builds after 124) also copes on its own: a row write refused with 401 while the session holds
is parked, not retried in a loop (docs/sync.md), and a friend or block row goes under a unique id when
its predictable one is taken (`SocialRepository._ownRow`).

### Friend gifts

20 gifts a day per sender (`limit`); a notification only between friends who added each other, and at
most 5 a day per recipient (later gifts land in the inbox quietly); names with a link, an @handle or a
domain show as "Player" in the message and the notification (docs/friend-gifts.md).

### Callers without a session

Apple calls the notifications route without a session, so `api` is meant to be executable by anyone
(execute `any`; still `users` until the owner's step above). Every route must then refuse such a caller
itself: the player routes answer 401 (`x-appwrite-user-id` is empty), `/coop/cleanup` and `/admin/sweep`
answer 404 unless the caller is a console user (the owner's CLI: a user id that is no user of the
project; before deployment `6ad3e5a1ef69e35d38a6` a call without any user counted too), the notifications
route needs Apple's signature, and only `/health` and the invite pages answer (a GET; they show only what
an invite shares, "Invite pages" above). Appwrite sets `x-appwrite-*` itself: the REST
API refuses such headers from a caller (400, checked live), and `api_check.mjs` checks that the domain
ignores them (a player's id, the `event` trigger) once it is open.

### Project settings

The app signs in only as a guest (anonymous), with e-mail and password, with Apple (OAuth and native
ID token) and uses JWT; memberships of co-op teams are made by the server. Turning off what it never
uses was approved by the owner and done on 2026-10-17 (run from a directory with the project's
appwrite.config.json):

```
appwrite project update-auth-method --method-id magic-url --enabled=false
appwrite project update-auth-method --method-id email-otp --enabled=false
appwrite project update-auth-method --method-id phone --enabled=false
appwrite project update-auth-method --method-id invites --enabled=false   # then play a co-op game (node tools/dev/api_check.mjs); if joining fails, turn it back on
appwrite project update-protocol --protocol-id graphql --enabled=false
```

Before (2026-10-17): every auth method on except passkey; protocols REST, GraphQL and WebSocket on.
Now: email-password, anonymous and JWT on (Apple is an OAuth provider); magic URL, email OTP, phone, invites
and passkey off; GraphQL off, REST and WebSocket on. `node tools/dev/api_check.mjs` passed afterwards (co-op
create, join, rejoin, leave, remove, next board and end; account deletion): server-made team memberships do
not need the invites method. To turn a method back on, run the same command with `--enabled=true`.

## Timings (live, 2026-10-17)

Wall time of a call from this Mac (Appwrite's execution duration includes the cold start):

| | cold | warm |
| --- | --- | --- |
| old functions, `GET /health` | 4.0-5.1 s (`coop-game` 4.0, `send-gift` 4.9, `redeem-code` 5.1, `delete-account` 4.4) | 0.1-0.2 s |
| `coop-game` create (docs/multiplayer.md) | 7.4 s | 0.1-1.2 s |
| `api`, `GET /health` (loads the purchase and account modules) | 5.2 s | 0.16-0.44 s |
| `api`, every route (`tools/dev/api_check.mjs`) | | 0.1-1.5 s; a pack code 2.8 s (its first claim grants 7 files); an account deletion 4.6 s |
| invite page, first reader 1.5 s after `/coop/create` (it waits for the card being drawn) | | 1.6-2.7 s (7 boards, 9 to 666 pieces) |
| invite page, a card already kept / the edge's copy | | 0.25-0.35 s / 0.02-0.03 s |
| invite card (Storage, 50-140 KB) | | 0.2-0.3 s |

A cold start costs the same as before (it is mostly Appwrite starting the runtime); what changes is
how often a player meets one. A runtime stays warm for about ten minutes after its last call
(`redeem-code` measured warm after 8 minutes idle, cold after 12; once still warm after 13), so with
every call on `api`, one player's call keeps it warm for the next.
