"""Create / replace puzzles and keep pack rows consistent (imageCount, cover, blurhash, accent)."""
import hashlib, time
from datetime import datetime, timezone
from . import host, api, catalog, imagecache, state, filters, checkpoint
from .pool import load_pool, save_pool, nice_title, HashIndex

_MONTHS = ('January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December')

def daily_month_label(pack_id):
    """'October 2024' for a daily month pack (daily-YYYY-MM), else None. Daily months are always named
    after their month (the app shows it in the Library, on the pack page, Home and the completion overlay)."""
    import re
    m = re.fullmatch(r'daily-(\d{4})-(\d{2})', pack_id or '')
    if not m or not 1 <= int(m.group(2)) <= 12: return None
    return f'{_MONTHS[int(m.group(2)) - 1]} {m.group(1)}'

def daily_description(label):
    return f"One fresh picture for every day of {label}. Solve today's for a bonus."

def puzzle_id_for(url, pack_id=''):
    return 'p-' + hashlib.sha1((pack_id + '|' + url).encode()).hexdigest()[:12]

# Extra attribution fields some opt-in providers carry (photographer page, Unsplash download_location, ...).
_EXTRA_PROV = ('author_url', 'photo_page', 'download_location', 'object_id')

def _prov_extra(c):
    return {k: c[k] for k in _EXTRA_PROV if c.get(k)}

def _on_used(c):
    """Provider hook when a candidate becomes a puzzle (Unsplash download ping); never fails the apply."""
    if c.get('provider') not in ('unsplash',): return
    try:
        from . import sources
        sources.on_used(c)
    except Exception as e:
        print('  provider hook failed:', str(e)[:80])

def _meta_ok(url):
    m = imagecache.fetch(url)
    return m if m.get('ok') else None

def select_candidates(pool, spec, kept_metas, kept_authors, need, picks=(), auto=True, rejected=None, taken=frozenset()):
    # picks are always honoured first; auto-fill round-robins over topics
    """Return ordered candidate list honouring explicit picks, topic round-robin, dup and author caps."""
    rejected = rejected or {}
    by_key = {c['key']: c for c in pool['candidates']}
    chosen, chosen_metas, authors = [], list(kept_metas), dict(kept_authors)
    reason = ['']
    def ok_to_add(c):
        def no(why):
            reason[0] = why
            return False
        if state.is_rejected(c['url'], spec['id'], rejected): return no('rejected earlier')
        if c['url'] in taken: return no('already used in another pack')
        # Appwrite string columns are 512 chars; such URLs would abort apply mid-run.
        if len(c['url']) > 2000: return no('source URL longer than 2000 characters')   # rows store our own URLs; sourceUrl holds 2000
        if c.get('status') != 'ok': return no(f"candidate status {c.get('status')}")
        if c.get('hotlink') is False: return no('host forbids hotlinking (re-host first)')      # e.g. Pixabay
        m = _meta_ok(c['url'])
        if not m: return no('image could not be downloaded or read')
        if m['w'] > m['h']: return no(f"landscape {m['w']}x{m['h']}")
        if min(m['w'], m['h']) < filters.MIN_SHORT_HARD: return no(f"too small {m['w']}x{m['h']}")
        for km in chosen_metas:
            sim, why = imagecache.similar(m, km)
            if sim: return no(f'too similar to a picture already chosen ({why})')
        if authors.get(c['author'], 0) >= spec['author_cap'] and spec['author_cap'] > 0:
            return no(f"photographer limit: {spec['author_cap']} per pack for {c['author']}")
        return m
    for k in picks:
        c = by_key.get(k)
        if not c: print('  unknown pick', k); continue
        m = ok_to_add(c)
        if not m: print('  pick rejected by checks', k, '-', reason[0]); continue
        chosen.append(c); chosen_metas.append(m); authors[c['author']] = authors.get(c['author'], 0) + 1
    if auto:
        topics = []
        for c in pool['candidates']:
            if c.get('topic') not in topics: topics.append(c.get('topic'))
        # shared pools (daily years, ai-all): start the round-robin at a pack-specific point so successive
        # packs draw from different topics instead of all taking the first ones in spec order
        import random
        random.Random(spec['id']).shuffle(topics)
        per_topic = {t: [c for c in pool['candidates'] if c.get('topic') == t and c not in chosen] for t in topics}
        progress = True
        while len(chosen) < need and progress:
            progress = False
            for t in topics:
                if len(chosen) >= need: break
                while per_topic[t]:
                    c = per_topic[t].pop(0)
                    m = ok_to_add(c)
                    if m:
                        chosen.append(c); chosen_metas.append(m); authors[c['author']] = authors.get(c['author'], 0) + 1
                        progress = True; break
    return chosen

def apply(spec, snap, target=None, picks=(), auto=True, dry=False, daily=False):
    pack_id = spec['id']
    target = target or spec['target']
    snap = catalog.refresh_pack(snap, pack_id)
    packs = catalog.pack_index(snap)
    pack = packs.get(pack_id)
    if not pack: raise SystemExit(f'pack {pack_id} does not exist; run newpack first')
    puzzles = catalog.by_pack(snap).get(pack_id, [])
    rejected = state.rejects()
    pool = load_pool(spec['pool'])
    removed, kept = [], []
    for p in puzzles:
        if state.is_rejected(p['imageUrl'], pack_id, rejected):
            removed.append(p)
        else:
            kept.append(p)
    kept_metas = [m for m in (imagecache.load_meta(p['imageUrl']) for p in kept) if m and m.get('ok')]
    kept_authors = {}
    for p in kept: kept_authors[p.get('author') or ''] = kept_authors.get(p.get('author') or '', 0) + 1
    if daily:
        need = len(removed)
    else:
        need = max(0, target - len(kept))
    # pictures used anywhere else in the catalogue (twin event years share theirs on purpose via clone)
    taken = {p['imageUrl'] for p in catalog.sync()['puzzles'] if p['packId'] != pack_id}
    chosen = select_candidates(pool, spec, kept_metas, kept_authors, need, picks, auto, rejected, taken)
    print(f'{pack_id}: {len(puzzles)} puzzles, remove {len(removed)}, keep {len(kept)}, need {need}, chosen {len(chosen)}')
    if dry:
        for c in chosen: print('   +', c['key'], c.get('topic'), c['author'], c['url'])
        for p in removed: print('   -', p['$id'], rejected[p['imageUrl']]['reason'])
        return
    accent = spec.get('accent') or pack.get('accent') or '#475569'
    created = []
    if daily:
        # replace in place: keep ids, dates and sort order
        for p, c in zip(removed, chosen):
            m = _meta_ok(c['url'])
            data = dict(title=nice_title(c, c.get('topic', 'Daily picture')), **host.puzzle_urls(c['url'], spec.get('host_max_px')),
                        author=c['author'][:96], source=c['source'][:128], accent=m['accent'], blurhash=m['blurhash'])
            api.update_row('puzzles', p['$id'], data)
            state.add_provenance(p['$id'], dict(url=c['url'], author=c['author'], licence=c['licence'], source=c['source'], page=c.get('page', ''), provider=c['provider'], packId=pack_id, replaced=p['imageUrl'], at=time.strftime('%Y-%m-%d'), **_prov_extra(c)))
            _on_used(c)
            state.log('replace', pack=pack_id, puzzle=p['$id'], old=p['imageUrl'], new=c['url'], reason=rejected[p['imageUrl']]['reason'])
            c['status'] = 'used'; created.append(p['$id'])
        leftover = removed[len(chosen):]
        if leftover:
            print(f'  WARNING {len(leftover)} daily puzzles still violate (no candidates): ' + ', '.join(p['$id'] for p in leftover))
    else:
        for p in removed:
            api.delete_row('puzzles', p['$id'])
            state.log('delete', pack=pack_id, puzzle=p['$id'], url=p['imageUrl'], reason=rejected[p['imageUrl']]['reason'])
        order = max([p.get('sortOrder') or 0 for p in kept] + [-1]) + 1
        taken = {p.get('title') for p in kept}
        for c in chosen:
            m = _meta_ok(c['url'])
            pid = puzzle_id_for(c['url'], pack_id)
            title = nice_title(c, pack['name'] if str(c.get('topic', '')).startswith('cat:') else c.get('topic', pack['name']), taken); taken.add(title)
            data = dict(packId=pack_id, title=title, **host.puzzle_urls(c['url'], spec.get('host_max_px')),
                        author=c['author'][:96], source=c['source'][:128], sortOrder=order, accent=accent, blurhash=m['blurhash'])
            try:
                api.create_row('puzzles', data, row_id=pid)
            except RuntimeError as e:
                if '409' in str(e):
                    api.update_row('puzzles', pid, data)
                else:
                    raise
            state.add_provenance(pid, dict(url=c['url'], author=c['author'], licence=c['licence'], source=c['source'], page=c.get('page', ''), provider=c['provider'], packId=pack_id, topic=c.get('topic', ''), at=time.strftime('%Y-%m-%d'), **_prov_extra(c)))
            _on_used(c)
            state.log('create', pack=pack_id, puzzle=pid, url=c['url'], topic=c.get('topic', ''))
            c['status'] = 'used'; created.append(pid); order += 1
    save_pool(pool)
    snap = catalog.refresh_pack(snap, pack_id)
    finalize_pack(spec, snap, accent)
    n = len(catalog.by_pack(snap).get(pack_id, []))
    checkpoint.update(pack_id, status='fixed', step='apply', removed=len(removed), added=len(created), puzzles=n)
    print(f'  done: {len(removed)} removed, {len(created)} added, pack now has {n} puzzles')
    if n < filters.MIN_COUNT and not daily:
        print(f'  WARNING pack below {filters.MIN_COUNT}; build more candidates (cli.py pool {pack_id} --more)')
    return snap

def finalize_pack(spec, snap, accent=None):
    """Sync imageCount, cover, blurhash and accent on the pack (and its event row).

    Always sets puzzlesUpdatedAt: the app and the catalogue snapshot read a pack's puzzles again when
    its row changes, which is how they see puzzles removed or replaced. Appwrite leaves $updatedAt
    alone on an update that changes nothing, so imageCount alone is not enough."""
    pack_id = spec['id']
    pack = catalog.pack_index(snap)[pack_id]
    puzzles = catalog.by_pack(snap).get(pack_id, [])
    urls = [p['imageUrl'] for p in puzzles]
    cover = spec.get('cover') if spec.get('cover') in urls else None
    if not cover:
        cover = pack.get('coverUrl') if pack.get('coverUrl') in urls else (urls[0] if urls else '')
    data = {'imageCount': len(puzzles), 'puzzlesUpdatedAt': datetime.now(timezone.utc).isoformat()}
    # covers are always served from our storage; re-host a cover that still points elsewhere
    if cover and (cover != pack.get('coverUrl') or not host.is_hosted(pack.get('hostedCoverUrl') or '')):
        data.update(host.cover_fields(cover))
    m = imagecache.load_meta(cover) if cover else None
    if m and m.get('ok'):
        if m['blurhash'] != pack.get('blurhash'): data['blurhash'] = m['blurhash']
        if not pack.get('accent') or spec.get('accent_from_cover'):
            data['accent'] = m['accent']
    if accent and accent != pack.get('accent') and 'accent' not in data and spec.get('accent'):
        data['accent'] = accent
    label = daily_month_label(pack_id)
    if label:
        # A daily month keeps its month name and never takes a shared daily spec's name or description:
        # daily-2023.json and daily-2024.json said "Daily", which named all 24 months of those years
        # "Daily" until 2026-10-18 (tools/dev/fix_daily_pack_names.py repaired the rows).
        if pack.get('name') != label: data['name'] = label
        if label not in (pack.get('description') or ''): data['description'] = daily_description(label)
    else:
        for k in ('name', 'description'):
            if spec.get(k) and spec[k] != pack.get(k): data[k] = spec[k][:256 if k == 'description' else 64]
    if data:
        api.update_row('packs', pack_id, data)
        state.log('pack-update', pack=pack_id, fields=sorted(data))
    if pack.get('eventId') and ('coverUrl' in data or 'accent' in data):
        try:
            ev = {k: v for k, v in data.items() if k in ('coverUrl', 'coverSourceUrl', 'accent')}
            api.update_row('events', pack['eventId'], ev)
        except RuntimeError as e:
            print('  event update failed', str(e)[:100])

def new_daily(spec, snap, month, picks=(), dry=False):
    """Create a daily month pack (daily-YYYY-MM): the pack row and one dated puzzle per day, filled from
    the spec's pool. Idempotent: existing day rows are kept, only missing days are created. Review the
    sheet afterwards and fix rejects with `apply` (daily packs replace in place)."""
    import calendar
    y, mo = (int(x) for x in month.split('-'))
    pack_id = f'daily-{y:04d}-{mo:02d}'
    label = daily_month_label(pack_id)
    spec = dict(spec, id=pack_id)
    packs = catalog.pack_index(snap)
    if pack_id not in packs:
        if dry:
            print(f'{pack_id}: pack row would be created ({label})')
        else:
            # standard tier of tools/store/apply_pack_prices.py: 100 coins per day (2,800 to 3,100)
            data = dict(name=label, category='Daily', description=daily_description(label),
                        priceCoins=100 * calendar.monthrange(y, mo)[1], priceTickets=0, isFree=False, isPremium=False, isSeasonal=False, sortOrder=100,
                        accent='', emoji='', coverUrl='', imageCount=0)
            api.create_row('packs', data, row_id=pack_id)
            state.log('pack-create', pack=pack_id, category='Daily')
            checkpoint.update(pack_id, status='pending', step='newdaily', kind='new', name=label, category='Daily', puzzles=0)
    snap = catalog.refresh_pack(snap, pack_id) if not dry or pack_id in packs else snap
    puzzles = catalog.by_pack(snap).get(pack_id, [])
    have = {p['$id'] for p in puzzles}
    days = [d for d in range(1, calendar.monthrange(y, mo)[1] + 1) if f'{pack_id}-{d:02d}' not in have]
    kept_metas = [m for m in (imagecache.load_meta(p['imageUrl']) for p in puzzles) if m and m.get('ok')]
    kept_authors = {}
    for p in puzzles: kept_authors[p.get('author') or ''] = kept_authors.get(p.get('author') or '', 0) + 1
    pool = load_pool(spec['pool'])
    taken = {p['imageUrl'] for p in catalog.sync()['puzzles'] if p['packId'] != pack_id}
    chosen = select_candidates(pool, spec, kept_metas, kept_authors, len(days), picks, True, state.rejects(), taken)
    print(f'{pack_id}: {len(puzzles)} days exist, {len(days)} missing, chosen {len(chosen)}')
    if dry:
        for d, c in zip(days, chosen): print(f'   {d:02d}', c['key'], c.get('topic'), c['author'])
        return snap
    titles = {p.get('title') for p in puzzles}
    for d, c in zip(days, chosen):
        m = _meta_ok(c['url'])
        pid = f'{pack_id}-{d:02d}'
        title = nice_title(c, c.get('topic', 'Daily picture'), titles); titles.add(title)
        data = dict(packId=pack_id, title=title, **host.puzzle_urls(c['url'], spec.get('host_max_px')), author=c['author'][:96], source=c['source'][:128],
                    sortOrder=d, accent=m['accent'], date=f'{y:04d}-{mo:02d}-{d:02d}T00:00:00.000+00:00', blurhash=m['blurhash'])
        try:
            api.create_row('puzzles', data, row_id=pid)
        except RuntimeError as e:
            if '409' in str(e): api.update_row('puzzles', pid, data)
            else: raise
        state.add_provenance(pid, dict(url=c['url'], author=c['author'], licence=c['licence'], source=c['source'], page=c.get('page', ''), provider=c['provider'], packId=pack_id, topic=c.get('topic', ''), at=time.strftime('%Y-%m-%d'), **_prov_extra(c)))
        _on_used(c)
        state.log('create', pack=pack_id, puzzle=pid, url=c['url'], topic=c.get('topic', ''))
        c['status'] = 'used'
    save_pool(pool)
    missing = days[len(chosen):]
    if missing:
        print(f'  WARNING {len(missing)} days still empty ({", ".join(f"{d:02d}" for d in missing)}): grow the pool (pool {pack_id} --more) and run newdaily again')
    snap = catalog.refresh_pack(snap, pack_id)
    finalize_pack(spec, snap)
    n = len(catalog.by_pack(snap).get(pack_id, []))
    checkpoint.update(pack_id, status='fixed' if not missing else 'pending', step='newdaily', puzzles=n)
    print(f'  done: {pack_id} has {n} days')
    return snap


def new_pack(spec, snap, sort_order=None):
    """Create (or update metadata of) a pack row from a spec. Idempotent."""
    packs = catalog.pack_index(snap)
    price = spec.get('price', 'coins')
    data = dict(name=spec['name'][:64], category=spec['category'][:32], description=spec.get('description', '')[:256],
                priceCoins=spec.get('priceCoins', 400 if price == 'coins' else 0), priceTickets=spec.get('priceTickets', 3 if price == 'tickets' else 0),
                isFree=price == 'free', isPremium=bool(spec.get('premium', False)), isSeasonal=False,
                sortOrder=spec.get('sortOrder', sort_order if sort_order is not None else 500), accent=spec.get('accent') or '#475569', emoji='')
    if spec['id'] in packs:
        # prices of existing packs belong to the economy (app side); only set them on create
        api.update_row('packs', spec['id'], {k: v for k, v in data.items() if k in ('name', 'category', 'description', 'sortOrder')})
        state.log('pack-meta', pack=spec['id'])
    else:
        data.update(coverUrl='', imageCount=0)
        api.create_row('packs', data, row_id=spec['id'])
        state.log('pack-create', pack=spec['id'], category=spec['category'])
        checkpoint.update(spec['id'], status='pending', step='newpack', kind='new', name=spec['name'], category=spec['category'], puzzles=0)
    return catalog.refresh_pack(snap, spec['id'])


def clone(src_id, dst_id, snap):
    """Replace every puzzle of dst with copies of src's puzzles (used for the same world day in another year)."""
    snap = catalog.refresh_pack(snap, src_id); snap = catalog.refresh_pack(snap, dst_id)
    packs = catalog.pack_index(snap)
    if src_id not in packs or dst_id not in packs: raise SystemExit('both packs must exist')
    src = catalog.by_pack(snap).get(src_id, []); old = catalog.by_pack(snap).get(dst_id, [])
    if len(src) < filters.MIN_COUNT: raise SystemExit(f'{src_id} has only {len(src)} puzzles; fix it first')
    for p in old:
        api.delete_row('puzzles', p['$id']); state.log('delete', pack=dst_id, puzzle=p['$id'], url=p['imageUrl'], reason=f'replaced by clone of {src_id}')
    prov = state.provenance()
    from . import specs as _specs
    src_px = _specs.load(src_id).get('host_max_px') if _specs.spec_path(src_id).exists() else None   # a giant source stays giant
    for i, p in enumerate(src):
        pid = puzzle_id_for(p['imageUrl'], dst_id)
        data = {k: p.get(k) for k in ('title', 'author', 'source', 'accent', 'blurhash')}
        data.update(host.puzzle_urls(p['imageUrl'], src_px), packId=dst_id, sortOrder=i)
        try:
            api.create_row('puzzles', data, row_id=pid)
        except RuntimeError as e:
            if '409' in str(e): api.update_row('puzzles', pid, data)
            else: raise
        rec = dict(prov.get(p['$id'], {'url': p['imageUrl'], 'author': p.get('author'), 'source': p.get('source')}))
        rec.update(packId=dst_id, clonedFrom=src_id, at=time.strftime('%Y-%m-%d'))
        state.add_provenance(pid, rec)
    state.log('clone', src=src_id, dst=dst_id, count=len(src))
    snap = catalog.refresh_pack(snap, dst_id)
    spec = {'id': dst_id, 'cover': packs[src_id].get('coverUrl'), 'accent': packs[src_id].get('accent')}
    finalize_pack(spec, snap)
    checkpoint.update(dst_id, status='fixed', step=f'clone from {src_id}', removed=len(old), added=len(src), puzzles=len(src))
    print(f'cloned {len(src)} puzzles {src_id} -> {dst_id}')
