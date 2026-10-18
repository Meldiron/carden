// Friend gifts (owner, 2026-10-17; docs/friend-gifts.md): on a friend's profile a player sends
// that friend 1 ticket or 150 coins. It costs the sender nothing; one gift per friend per day.
// Builds up to 124 call this function; later builds call `/gift/send` on the `api` function. This file
// and src/gift.js are copies of functions/api/src/gift/ (send.js and gift.js): change both and redeploy
// both (functions/api/test/twins.test.mjs checks they match; docs/functions.md).
//
// Routes:
//   POST /send  { friendId, kind: 'tickets' | 'coins', utcOffset }  called by the app
//   GET  /health
//
// Only the caller sends (x-appwrite-user-id, set by Appwrite). In order: the caller has the friend
// in their friends list, neither player blocked the other, and the friend's profile exists; the
// caller has sent fewer than DAILY_SENDS gifts today (`limit` otherwise); the gift row (`gifts`, id
// from sender, friend and the sender's calendar day) is created, which fails when today's gift to
// this friend is already sent; then the friend's inbox message (`messages`, readable only by the
// friend, expiresAt = sentAt + 24 h, the reward claimed through the inbox's own flow) and finally a
// push through Appwrite Messaging to the friend's push targets, whose tap opens that message: only
// when the friend has the sender in their friends list too, and at most PUSHES_PER_DAY in 24 hours
// (`shouldPush`; later gifts arrive quietly). A message that cannot be written takes the gift row
// back, so the sender can try again; a push that fails changes nothing (the inbox still has the gift).
// Names go through the name filter (offensive words, links, @handles, domains show as "Player").
import { Client, TablesDB, Messaging, Users, Query, Permission, Role, ID } from 'node-appwrite';
import { DAILY_SENDS, KINDS, LIFETIME_MS, USER_ID, clampOffset, giftCopy, giftDay, giftRowId, messageLink, shouldPush, shownName } from './gift.js';

const DB = process.env.APPWRITE_DATABASE_ID || 'cjw';

function services(req) {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(req.headers['x-appwrite-key'] ?? '');
  return { tables: new TablesDB(client), messaging: new Messaging(client), users: new Users(client) };
}

const gone = (e) => e?.code === 404;
const exists = (e) => e?.code === 409;

async function getRow(tables, tableId, rowId) {
  try {
    return await tables.getRow({ databaseId: DB, tableId, rowId });
  } catch (e) {
    if (gone(e)) return null;
    throw e;
  }
}

/// Whether any row of [tableId] matches every [pairs] column = value.
async function any(tables, tableId, pairs) {
  const page = await tables.listRows({
    databaseId: DB,
    tableId,
    queries: [...Object.entries(pairs).map(([k, v]) => Query.equal(k, v)), Query.select(['$id']), Query.limit(1)],
    total: false,
  });
  return page.rows.length > 0;
}

/// How many rows of [tableId] match [queries] (Appwrite counts them; one row is read).
async function count(tables, tableId, queries) {
  const page = await tables.listRows({ databaseId: DB, tableId, queries: [...queries, Query.select(['$id']), Query.limit(1)] });
  return page.total;
}

// A device that keeps its push target only for messages from Carden (Settings > Gifts from friends
// off, Messages from Carden on) subscribes that target to this topic, and the gift push leaves it out
// (docs/notifications.md). Builds before 2.0.0 (128) never subscribe: every target of theirs gets gifts.
const GIFTS_OFF_TOPIC = 'gifts-off';

/// Who the gift push goes to: `{ users: [friendId] }` (every push target of the friend), or, when
/// some of the friend's targets turned gift notifications off, `{ targets }` without them (empty: no
/// push). Reading the topic needs the scope subscribers.read and the targets targets.read; a topic
/// that cannot be read sends to every target, as before the topic existed; targets that cannot be
/// read after a target turned gifts off send nothing.
export async function giftRecipients({ messaging, users }, friendId, log) {
  let muted;
  try {
    const page = await messaging.listSubscribers({ topicId: GIFTS_OFF_TOPIC, queries: [Query.equal('userId', [friendId]), Query.limit(100)], total: false });
    muted = new Set(page.subscribers.map((s) => s.targetId));
  } catch (e) {
    log(`${GIFTS_OFF_TOPIC} not read (${e.message}): every target`);
    return { users: [friendId] };
  }
  if (muted.size === 0) return { users: [friendId] };
  try {
    const page = await users.listTargets({ userId: friendId, queries: [Query.equal('providerType', ['push']), Query.limit(100)], total: false });
    return { targets: page.targets.filter((t) => t.providerType === 'push' && !muted.has(t.$id)).map((t) => t.$id) };
  } catch (e) {
    log(`targets of ${friendId} not read (${e.message}): no push`);
    return { targets: [] };
  }
}

/// Appwrite keeps every push it sends (title, body, recipient) in its messaging log. Each send, and
/// the hourly run of `api`, deletes inbox pushes (gifts, and messages from Carden sent by
/// tools/dev/inbox.py) older than a day from it, so the log never holds one for long; other
/// messages (sent from the console) are left alone.
async function cleanupPushLog(messaging, log) {
  try {
    const old = new Date(Date.now() - LIFETIME_MS).toISOString();
    const page = await messaging.listMessages({ queries: [Query.lessThan('$createdAt', old), Query.orderAsc('$createdAt'), Query.limit(100)], total: false });
    let deleted = 0;
    for (const m of page.messages) {
      // An inbox push is recognised by its link.
      if (!String(m.data?.data?.link ?? '').startsWith('/inbox?message=')) continue;
      await messaging.delete({ messageId: m.$id });
      deleted++;
    }
    if (deleted) log(`push log: ${deleted} old inbox push(es) deleted`);
  } catch (e) {
    log(`push log cleanup: ${e.message}`);
  }
}

/// The hourly run's part: old inbox pushes leave the messaging log (cleanupPushLog).
export async function cleanPushLog(req, log) {
  await cleanupPushLog(services(req).messaging, log);
}

function parseBody(req) {
  try {
    return typeof req.body === 'string' && req.body ? JSON.parse(req.body) : (req.bodyJson ?? req.body ?? {});
  } catch (_) {
    return {};
  }
}

async function handleSend(req, res, log, error) {
  const userId = req.headers['x-appwrite-user-id'];
  if (!userId) return res.json({ ok: false, error: 'signin' }, 401);
  const body = parseBody(req) || {};
  const friendId = String(body.friendId ?? '');
  const kind = String(body.kind ?? '');
  if (!USER_ID.test(friendId) || friendId === userId) return res.json({ ok: false, error: 'not-friend' }, 400);
  if (!KINDS[kind]) return res.json({ ok: false, error: 'kind' }, 400);
  const { tables, messaging, users } = services(req);

  if (!(await any(tables, 'friends', { userId, friendId }))) return res.json({ ok: false, error: 'not-friend' }, 403);
  const [blockedByMe, blockedMe] = await Promise.all([
    any(tables, 'blocks', { blockerId: userId, blockedId: friendId }),
    any(tables, 'blocks', { blockerId: friendId, blockedId: userId }),
  ]);
  const [sender, recipient] = await Promise.all([getRow(tables, 'profiles', userId), getRow(tables, 'profiles', friendId)]);
  // A block either way, or a friend who deleted their account: the same calm "could not send".
  if (blockedByMe || blockedMe || !recipient) return res.json({ ok: false, error: 'unavailable' }, 403);

  const friendName = shownName(recipient.displayName);
  const name = shownName(sender?.displayName);
  const now = new Date();
  const offset = clampOffset(body.utcOffset);
  const day = giftDay(now, offset);
  const giftId = giftRowId(userId, friendId, day);
  const messageId = ID.unique();
  const gift = KINDS[kind];
  const isTest = sender?.isTest === true || recipient.isTest === true;

  if ((await count(tables, 'gifts', [Query.equal('senderId', [userId]), Query.equal('day', [day])])) >= DAILY_SENDS) {
    log(`gift limit: ${userId} sent ${DAILY_SENDS} on ${day}`);
    return res.json({ ok: false, error: 'limit', friendName, day }, 429);
  }

  try {
    await tables.createRow({
      databaseId: DB,
      tableId: 'gifts',
      rowId: giftId,
      data: { senderId: userId, recipientId: friendId, day, kind, amount: gift.amount, messageId, sentAt: now.toISOString(), isTest },
      // The sender reads it to show "Next gift tomorrow"; nobody can change it.
      permissions: [Permission.read(Role.user(userId))],
    });
  } catch (e) {
    if (exists(e)) return res.json({ ok: false, error: 'already', friendName, day });
    throw e;
  }

  const copy = giftCopy(kind, name);
  try {
    await tables.createRow({
      databaseId: DB,
      tableId: 'messages',
      rowId: messageId,
      data: {
        userId: friendId,
        subject: copy.subject,
        body: copy.body,
        sentAt: now.toISOString(),
        expiresAt: new Date(now.getTime() + LIFETIME_MS).toISOString(),
        [gift.column]: gift.amount,
        fromUserId: userId,
        fromName: name,
        fromAvatar: String(sender?.avatar ?? '').slice(0, 64) || null,
      },
      permissions: [Permission.read(Role.user(friendId))],
    });
  } catch (e) {
    try {
      await tables.deleteRow({ databaseId: DB, tableId: 'gifts', rowId: giftId });
    } catch (_) {}
    throw e;
  }

  // The friend's iPhones (their push targets that want gifts; the web has none), when they may get one.
  let pushed = false;
  const [mutual, received] = await Promise.all([
    any(tables, 'friends', { userId: friendId, friendId: userId }),
    count(tables, 'gifts', [Query.equal('recipientId', [friendId]), Query.greaterThan('sentAt', new Date(now.getTime() - LIFETIME_MS).toISOString())]),
  ]);
  const to = shouldPush({ mutual, received }) ? await giftRecipients({ messaging, users }, friendId, log) : null;
  if (to && to.targets?.length === 0) {
    log(`no push to ${friendId}: gift notifications are off on every device`);
  } else if (to) {
    try {
      await messaging.createPush({
        messageId: ID.unique(),
        title: copy.pushTitle,
        body: copy.pushBody,
        ...to,
        data: { link: messageLink(messageId) },
        sound: 'default',
      });
      pushed = true;
    } catch (e) {
      log(`push to ${friendId} not sent: ${e.message}`);
    }
    await cleanupPushLog(messaging, log);
  } else {
    log(`no push to ${friendId}: ${mutual ? `${received} gifts in 24 h` : 'not a mutual friend'}`);
  }
  log(`gift ${kind} ${userId} -> ${friendId} day ${day} (offset ${offset}) message ${messageId} pushed ${pushed}${isTest ? ' [test]' : ''}`);
  return res.json({ ok: true, kind, amount: gift.amount, friendName, day, messageId, pushed });
}

export default async ({ req, res, log, error }) => {
  const path = (req.path || '/').replace(/\/+$/, '') || '/';
  try {
    if (req.method === 'GET' && (path === '/health' || path === '/')) return res.json({ ok: true });
    if (req.method === 'POST' && (path === '/send' || path === '/')) return await handleSend(req, res, log, error);
    return res.json({ ok: false, error: 'Not found' }, 404);
  } catch (e) {
    error(e.stack || e.message);
    return res.json({ ok: false, error: 'server' }, 500);
  }
};
