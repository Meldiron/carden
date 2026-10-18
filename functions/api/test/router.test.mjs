// The router (src/main.js): every route reaches its module, nothing runs at the root, a scheduled
// execution runs the co-op cleanup, the manual cleanup and sweep refuse players and calls without a
// user, and calls without a user are refused as the old functions refused them.
//
//   cd functions/api && npm install && npm test
import { test, mock } from 'node:test';
import assert from 'node:assert/strict';

// An empty project: every list is empty, so the cleanup has nothing to do. Its only user is `u1`
// (Users.get of anyone else is 404, as for the owner's console account).
const calls = [];
const empty = new Proxy({}, {
  get: (_, method) => async (args) => {
    calls.push(method);
    if (method === 'get' && args?.userId !== 'u1') throw Object.assign(new Error('User not found'), { code: 404 });
    return { total: 0, rows: [], teams: [], memberships: [], files: [], messages: [], users: [] };
  },
});
class Service { constructor() { return empty; } }

mock.module('node-appwrite', {
  namedExports: {
    Client: class { setEndpoint() { return this; } setProject() { return this; } setKey() { return this; } },
    TablesDB: Service,
    Teams: Service,
    Users: Service,
    Storage: Service,
    Messaging: Service,
    ID: { unique: () => 'id' },
    Query: new Proxy({}, { get: (_, name) => (...args) => ({ [name]: args }) }),
    Permission: { read: (r) => `read(${r})` },
    Role: { user: (id) => `user:${id}`, team: (id) => `team:${id}` },
    Operator: { increment: (n) => ({ increment: n }) },
  },
});
mock.module('@apple/app-store-server-library', {
  namedExports: {
    SignedDataVerifier: class {},
    Environment: { SANDBOX: 'Sandbox', PRODUCTION: 'Production' },
  },
});

const { default: handler, routeOf } = await import('../src/main.js');
const { COOP_ACTIONS } = await import('../src/coop/game.js');

async function run(method, path, { headers = {}, body, host } = {}) {
  let out;
  await handler({
    req: { method, path, headers, host, body: body === undefined ? '' : JSON.stringify(body) },
    res: {
      json: (b, status = 200) => (out = { status, body: b }),
      text: (t, status = 200) => (out = { status, text: t }),
      redirect: (url, status = 301) => (out = { status, redirect: url }),
    },
    log: () => {},
    error: () => {},
  });
  return out;
}

const player = { 'x-appwrite-user-id': 'u1', 'x-appwrite-trigger': 'http' };

test('routes are method and path, trailing slashes ignored', () => {
  assert.equal(routeOf({ method: 'post', path: '/coop/join/' }), 'POST /coop/join');
  assert.equal(routeOf({ method: 'GET', path: '' }), 'GET /');
});

test('every co-op action of the module is routed', async () => {
  assert.deepEqual([...COOP_ACTIONS].sort(), ['create', 'end', 'join', 'leave', 'next', 'remove']);
  for (const a of COOP_ACTIONS) {
    // Reaching the module without a user gives its own refusal, not the router's 404.
    const r = await run('POST', `/coop/${a}`, { headers: { 'x-appwrite-trigger': 'http' }, body: {} });
    assert.equal(r.body.reason, 'auth', a);
  }
});

test('GET /health', async () => {
  const r = await run('GET', '/health', { headers: player });
  assert.deepEqual(r, { status: 200, body: { ok: true, environment: 'Sandbox', maxPlayers: 5, appleSignIn: 'missing' } });
});

test('nothing runs at the root or on an unknown path', async () => {
  for (const [method, path] of [['POST', '/'], ['GET', '/'], ['POST', '/delete'], ['POST', '/verify'], ['POST', '/send'], ['POST', '/join'], ['GET', '/coop/join'], ['POST', '/coop/nope'], ['GET', '/account/delete']]) {
    const r = await run(method, path, { headers: player });
    assert.deepEqual(r, { status: 404, body: { ok: false, error: 'Not found' } }, `${method} ${path}`);
  }
});

test('calls without a user are refused, each as its old function did', async () => {
  const anon = { 'x-appwrite-trigger': 'http' };
  assert.deepEqual(await run('POST', '/coop/join', { headers: anon, body: { code: 'ABCDEFGH' } }), { status: 401, body: { ok: false, reason: 'auth', error: 'Sign in required' } });
  assert.deepEqual(await run('POST', '/gift/send', { headers: anon, body: {} }), { status: 401, body: { ok: false, error: 'signin' } });
  assert.deepEqual(await run('POST', '/code/redeem', { headers: anon, body: {} }), { status: 401, body: { ok: false, error: 'signin' } });
  assert.deepEqual(await run('POST', '/account/delete', { headers: anon, body: {} }), { status: 401, body: { ok: false, error: 'Sign in required' } });
  assert.deepEqual(await run('POST', '/purchase/verify', { headers: anon, body: {} }), { status: 401, body: { ok: false, error: 'Sign in required' } });
});

test('a co-op refusal keeps its reason', async () => {
  const r = await run('POST', '/coop/join', { headers: player, body: { code: 'nope' } });
  assert.deepEqual(r, { status: 404, body: { ok: false, reason: 'ended', error: 'This invite link does not work.' } });
});

test('a scheduled execution runs the co-op cleanup and the integrity sweep, whatever its path', async () => {
  calls.length = 0;
  const r = await run('POST', '/', { headers: { 'x-appwrite-trigger': 'schedule' } });
  assert.equal(r.status, 200);
  assert.equal(r.body.ok, true);
  assert.deepEqual(r.body.coop, { ended: 0, deleted: 0, oldBoards: 0, teams: 0 });
  assert.deepEqual([r.body.sweep.apply, r.body.sweep.counts], [false, {}], 'without SWEEP_APPLY the sweep only reports');
  assert.ok(calls.includes('listRows') && calls.includes('list') && calls.includes('listFiles'), 'it read the games, the teams, the rows and the photos');
  assert.ok(calls.includes('listMessages'), 'it looked for inbox pushes older than a day in the push log');
});

test('a new blocks row is checked by its create event; other events are ignored', async () => {
  const squat = { $id: 'a'.repeat(32), blockerId: 'u1', blockedId: 'u2', $permissions: ['read("user:u2")', 'update("user:u2")'] };
  const headers = { 'x-appwrite-trigger': 'event', 'x-appwrite-event': `tablesdb.cjw.tables.blocks.rows.${squat.$id}.create` };
  const r = await run('POST', '/', { headers, body: squat });
  assert.deepEqual(r.body, { ok: true, checked: true, verdict: 'permissions' });
  const other = await run('POST', '/', { headers: { 'x-appwrite-trigger': 'event', 'x-appwrite-event': 'databases.cjw.tables.friends.rows.x.create' }, body: squat });
  assert.equal(other.body.ignored, 'databases.cjw.tables.friends.rows.x.create');
});

test('the manual sweep is for callers who are not players, and a dry run unless asked', async () => {
  assert.equal((await run('POST', '/admin/sweep', { headers: player, body: { dryRun: false } })).status, 404);
  const r = await run('POST', '/admin/sweep', { headers: { 'x-appwrite-trigger': 'http', 'x-appwrite-user-id': 'console-owner' }, body: { full: true } });
  assert.deepEqual([r.status, r.body.ok, r.body.apply, r.body.full], [200, true, false, true]);
});

test('the manual cleanup is for console users only', async () => {
  assert.deepEqual(await run('POST', '/coop/cleanup', { headers: player }), { status: 404, body: { ok: false, error: 'Not found' } });
  const r = await run('POST', '/coop/cleanup', { headers: { 'x-appwrite-trigger': 'http', 'x-appwrite-user-id': 'console-owner' } });
  assert.equal(r.status, 200);
  assert.equal(r.body.ok, true);
});

// Anyone may execute `api` (execute `any`, for Apple's notifications at its domain and the invites at
// join.carden.page): a call without a user reaches the function, so every route must refuse it
// itself, except the notifications (Apple's signature), the health check and an invite's page.
test('a caller without a user gets nothing but the health check, the notifications route and invite pages', async () => {
  const anon = { 'x-appwrite-trigger': 'http' };
  const notFound = { status: 404, body: { ok: false, error: 'Not found' } };
  assert.deepEqual(await run('POST', '/coop/cleanup', { headers: anon }), notFound);
  assert.deepEqual(await run('POST', '/admin/sweep', { headers: anon, body: { dryRun: false, full: true } }), notFound);
  for (const a of COOP_ACTIONS) assert.equal((await run('POST', `/coop/${a}`, { headers: anon, body: {} })).status, 401, a);
  for (const path of ['/gift/send', '/code/redeem', '/account/delete', '/purchase/verify']) {
    assert.equal((await run('POST', path, { headers: anon, body: {} })).status, 401, path);
  }
  assert.deepEqual(await run('POST', '/purchase/notifications', { headers: anon, body: {} }), { status: 400, body: { ok: false, error: 'Missing signedPayload' } });
  assert.equal((await run('GET', '/health', { headers: anon })).status, 200);
  // An invite's page (an unknown code here: the empty project has no games) is HTML with the site's
  // card; every other GET on the invites' domain goes to the web game.
  const page = await run('GET', '/K7QH2MXP', { headers: anon });
  assert.equal(page.status, 200);
  assert.match(page.text, /<meta property="og:image" content="https:\/\/play\.carden\.page\/invite-card\.jpg">/);
  assert.deepEqual(await run('GET', '/', { headers: anon, host: 'join.carden.page' }), { status: 302, redirect: 'https://play.carden.page/' });
  assert.deepEqual(await run('GET', '/coop/join', { headers: anon }), notFound, 'not on another domain');
  assert.equal((await run('POST', '/K7QH2MXP', { headers: anon })).status, 404, 'GET only');
  // The invites' domain opens nothing else, not even for a signed-in caller.
  for (const [method, path] of [['POST', '/coop/join'], ['POST', '/purchase/notifications'], ['POST', '/gift/send']]) {
    assert.deepEqual(await run(method, path, { headers: player, host: 'join.carden.page', body: {} }), notFound, `${method} ${path}`);
  }
});
