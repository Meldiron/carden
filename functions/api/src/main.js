// The one Appwrite Function the app calls (owner, 2026-10-17): every feature in one function, which
// stays warm with everyone's calls, instead of a function per feature that each start cold (4-7 s).
// docs/functions.md has which function serves which builds.
//
// Routes (the caller is x-appwrite-user-id, set by Appwrite; bodies are JSON):
//   POST /purchase/verify          purchase.js      a StoreKit transaction (was verify-purchase /verify)
//   POST /purchase/notifications   purchase.js      App Store Server Notifications V2, for Apple without a
//                                                   session at https://cjw-api.fra.appwrite.run once execute
//                                                   is `any` (docs/functions.md; until then verify-purchase)
//   POST /account/delete           account.js       Account > Delete account (was delete-account /delete)
//   POST /code/redeem              code.js          a pack code, on the web (was redeem-code /redeem)
//   POST /coop/<action>            coop/game.js     Play together: create, join, leave, remove, end, next
//                                                   (was coop-game /<action>)
//   POST /gift/send                gift/send.js     a friend gift (was send-gift /send)
//   POST /coop/cleanup             coop/cleanup.js  the hourly co-op cleanup on demand; only for a console
//                                                   user (the owner's CLI), never a player or a call without a user
//   POST /admin/sweep              sweep/run.js     the integrity sweep on demand, same callers:
//                                                   { dryRun = true, full, qaOnly }
//   GET  /health                   { ok, environment, maxPlayers, appleSignIn }
//   GET  /<code>, /join/<code>     invite/page.js   a Play together invite's page and link preview, for
//                                                   anyone at https://join.carden.page (no session; it shows
//                                                   only the shared card), and its association file
//
// A scheduled execution (trigger `schedule`: the function's hourly `0 * * * *`) runs the co-op cleanup
// (it was the coop-cleanup function), the integrity sweep and the push log cleanup, whatever its path; the sweep changes
// rows only when the variable SWEEP_APPLY is `true` (else it reports), and reads everything once a
// day (FULL_HOUR). An event execution for a new `blocks` row (trigger `event`) checks that row at
// once. Appwrite sets x-appwrite-trigger and x-appwrite-event itself.
//
// Every feature is its own module, loaded on its first call, so a cold start loads only what that
// call needs (the App Store library only for purchases). Each module answers its own failures as its
// old function did, so the app reads the same answers.
import { MAX_PLAYERS } from './coop/rules.js';
import { isInviteRequest, onJoinHost } from './invite/paths.js';

const purchase = () => import('./purchase.js');
const account = () => import('./account.js');
const code = () => import('./code.js');
const coop = () => import('./coop/game.js');
const cleanup = () => import('./coop/cleanup.js');
const gift = () => import('./gift/send.js');
const sweeper = () => import('./sweep/run.js');
const invite = () => import('./invite/page.js');
const inviteCards = () => import('./invite/store.js');

/// Whether the sweep may change rows when it runs by itself (schedule, events).
const sweepApplies = () => process.env.SWEEP_APPLY === 'true';

/// The co-op actions (COOP_ACTIONS in coop/game.js, listed here so routing loads nothing).
const COOP = ['create', 'join', 'leave', 'remove', 'end', 'next'];

const ROUTES = {
  'POST /purchase/verify': async (c) => (await purchase()).verify(c),
  'POST /purchase/notifications': async (c) => (await purchase()).notifications(c),
  'POST /account/delete': async (c) => (await account()).deleteAccount(c),
  'POST /code/redeem': async (c) => (await code()).redeemCode(c),
  'POST /gift/send': async (c) => (await gift()).sendGift(c),
  ...Object.fromEntries(COOP.map((name) => [`POST /coop/${name}`, async (c) => (await coop()).coopAction(name, c)])),
  'POST /coop/cleanup': async (c) => {
    if (!(await notAPlayer(c.req))) return notFound(c);
    return (await cleanup()).coopCleanup(c);
  },
  'POST /admin/sweep': async (c) => {
    if (!(await notAPlayer(c.req))) return notFound(c);
    const body = parseBody(c.req);
    const s = await sweeper();
    const report = await s.sweep(s.services(c.req), { apply: body.dryRun === false, full: body.full === true, qaOnly: body.qaOnly === true, log: c.log });
    return c.res.json({ ok: true, ...report });
  },
  'GET /health': async ({ res }) => {
    const [p, a] = await Promise.all([purchase(), account()]);
    return res.json({ ok: true, environment: p.environmentName(), maxPlayers: MAX_PLAYERS, appleSignIn: a.appleKeyState() });
  },
};

const notFound = ({ res }) => res.json({ ok: false, error: 'Not found' }, 404);

function parseBody(req) {
  try {
    const body = typeof req.body === 'string' && req.body ? JSON.parse(req.body) : (req.bodyJson ?? req.body ?? {});
    return body && typeof body === 'object' ? body : {};
  } catch (_) {
    return {};
  }
}

/// The hourly run: the co-op cleanup, then the integrity sweep; one failing does not stop the other.
async function scheduled({ req, res, log, error }) {
  const out = { ok: true };
  try {
    out.coop = await (await cleanup()).runCleanup(req, log);
  } catch (e) {
    error(`coop cleanup: ${e?.stack ?? e}`);
    out.ok = false;
  }
  try {
    const s = await sweeper();
    const report = await s.sweep(s.services(req), { apply: sweepApplies(), full: new Date().getUTCHours() === s.FULL_HOUR, log });
    out.sweep = { apply: report.apply, full: report.full, counts: report.counts };
  } catch (e) {
    error(`integrity sweep: ${e?.stack ?? e}`);
    out.ok = false;
  }
  try {
    out.inviteCards = await (await inviteCards()).cleanCards(req, log);
  } catch (e) {
    error(`invite cards: ${e?.stack ?? e}`);
  }
  try {
    // Inbox pushes older than a day (friend gifts, messages from Carden) leave Messaging's log.
    await (await gift()).cleanPushLog(req, log);
  } catch (e) {
    error(`push log: ${e?.stack ?? e}`);
  }
  return res.json(out, out.ok ? 200 : 500);
}

/// An event execution: a new row of `blocks` is checked at once (sweep/run.js, sweepNewRow).
async function event({ req, res, log }) {
  const name = String(req.headers['x-appwrite-event'] ?? '');
  // Appwrite names it `tablesdb.<db>.tables.<table>.rows.<id>.create` (`databases.` in older events).
  const m = /^(?:tablesdb|databases)\.[^.]+\.tables\.([^.]+)\.rows\.[^.]+\.create$/.exec(name);
  if (!m || m[1] !== 'blocks') {
    log(`event ignored: ${name}`);
    return res.json({ ok: true, ignored: name });
  }
  const s = await sweeper();
  const row = parseBody(req);
  const result = await s.sweepNewRow(s.services(req), 'blocks', row, { apply: sweepApplies(), log });
  log(`event ${name}: ${result.verdict ?? 'the owner\'s row'}${row.$permissions ? '' : ' (no permissions in the event)'}`);
  return res.json({ ok: true, ...result });
}

/// Whether the caller is not one of the game's players but a console user (the owner's CLI, whose id
/// Appwrite passes too but is no user of this project). A call without a user is refused: once anyone
/// may execute `api` (execute `any`, for Apple's notifications at its domain), it may come from anywhere.
async function notAPlayer(req) {
  const userId = req.headers['x-appwrite-user-id'];
  if (!userId) return false;
  const { Client, Users } = await import('node-appwrite');
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(req.headers['x-appwrite-key'] ?? '');
  try {
    await new Users(client).get({ userId });
    return false;
  } catch (e) {
    if (e?.code === 404) return true;
    throw e;
  }
}

/// The route of a request: method and path without trailing slashes (`POST /coop/join`).
export function routeOf(req) {
  const path = (req.path || '/').replace(/\/+$/, '') || '/';
  return `${String(req.method || 'GET').toUpperCase()} ${path}`;
}

export default async (context) => {
  const { req, error } = context;
  try {
    const trigger = req.headers?.['x-appwrite-trigger'];
    if (trigger === 'schedule') return await scheduled(context);
    if (trigger === 'event') return await event(context);
    if (isInviteRequest(req)) return await (await invite()).serve(context);
    if (onJoinHost(req)) return notFound(context);
    const handler = ROUTES[routeOf(req)];
    if (!handler) return notFound(context);
    return await handler(context);
  } catch (e) {
    error(`${routeOf(req)}: ${e?.stack ?? e}`);
    return context.res.json({ ok: false, error: 'Server error' }, 500);
  }
};
