"""Catalogue audit against the content rules."""
import datetime as dt, json, re, time, calendar as cal
from .paths import REPORTS
from . import catalog, imagecache, filters, state
from .pool import HashIndex
from .writer import daily_month_label

def _twin(a, b):
    """evpack-<slug>-2026 and evpack-<slug>-2027 are the same event in different years."""
    ma, mb = re.match(r'^(evpack-.+)-(\d{4})$', a), re.match(r'^(evpack-.+)-(\d{4})$', b)
    return bool(ma and mb and ma.group(1) == mb.group(1))

def audit(snap, only=None, write=True):
    by_pack = catalog.by_pack(snap)
    packs = sorted(snap['packs'], key=lambda p: (p['category'], p.get('sortOrder') or 0, p['$id']))
    metas = {p['imageUrl']: imagecache.load_meta(p['imageUrl']) for p in snap['puzzles']}
    entries = [(p['$id'], p['packId'], metas[p['imageUrl']]) for p in snap['puzzles'] if metas[p['imageUrl']] and metas[p['imageUrl']].get('ok')]
    index = HashIndex(entries)
    rejected = state.rejects()
    report, summary = {}, {'packs': 0, 'violating': 0, 'count': 0, 'landscape': 0, 'dup_pairs': 0, 'people_kw': 0, 'text_kw': 0, 'small': 0, 'unscanned': 0, 'cross_dups': 0, 'rejected_pending': 0}
    url_packs = {}
    for p in snap['puzzles']:
        url_packs.setdefault(p['imageUrl'], set()).add(p['packId'])
    for pack in packs:
        pid = pack['$id']
        if only and pid not in only: continue
        puzzles = by_pack.get(pid, [])
        r = {'name': pack['name'], 'category': pack['category'], 'count': len(puzzles), 'issues': []}
        try:
            from . import specs as _specs
            allow = set(w.lower() for w in _specs.load(pid).get('allow_words', [])) if _specs.spec_path(pid).exists() else set()
        except SystemExit:
            allow = set()
        if len(puzzles) < filters.MIN_COUNT:
            r['issues'].append(f'count {len(puzzles)} < {filters.MIN_COUNT}'); summary['count'] += 1
        if pack['category'] == 'Daily' or pid.startswith('daily-'):
            label = daily_month_label(pid)
            if label and pack.get('name') != label:
                r['issues'].append(f"name {pack.get('name')!r} is not {label!r} (finalize the pack, or tools/dev/fix_daily_pack_names.py)")
            dates = [ (p.get('date') or '')[:10] for p in puzzles]
            y, m = map(int, pid.split('-')[1:3])
            days = cal.monthrange(y, m)[1]
            want = {f'{y:04d}-{m:02d}-{d:02d}' for d in range(1, days + 1)}
            missing = sorted(want - set(dates)); extra = sorted(set(dates) - want)
            if missing: r['issues'].append(f'missing dates {missing[:5]}')
            if len(dates) != len(set(dates)): r['issues'].append('duplicate dates')
            if extra: r['issues'].append(f'extra dates {extra[:5]}')
        seen_local = []
        for p in puzzles:
            m = metas.get(p['imageUrl'])
            tag = p['$id']
            if state.is_rejected(p['imageUrl'], pid, rejected):
                r['issues'].append(f'{tag}: rejected ({rejected[p["imageUrl"]]["reason"]}) not yet replaced'); summary['rejected_pending'] += 1
            if not m or not m.get('ok'):
                r['issues'].append(f'{tag}: not scanned/unreadable ({(m or {}).get("err", "no meta")})'); summary['unscanned'] += 1
                continue
            sf = filters.size_flags(m['w'], m['h'])
            if 'landscape' in sf:
                r['issues'].append(f'{tag}: landscape {m["w"]}x{m["h"]}'); summary['landscape'] += 1
            if 'too-small' in sf:
                r['issues'].append(f'{tag}: too small {m["w"]}x{m["h"]}'); summary['small'] += 1
            # keyword hits on titles are hints for the visual review, not violations (warnings only)
            kw = filters.keyword_flags((p.get('title') or '') + ' ' + (p.get('author') or ''), allow=allow)
            for k in kw:
                if k.startswith('people'): summary['people_kw'] += 1
                if k.startswith('text'): summary['text_kw'] += 1
                r.setdefault('warnings', []).append(f'{tag}: keyword {k}')
            for (sid, sm) in seen_local:
                sim, why = imagecache.similar(m, sm)
                if sim:
                    r['issues'].append(f'{tag} ~ {sid}: {why}'); summary['dup_pairs'] += 1
            seen_local.append((tag, m))
            others = url_packs.get(p['imageUrl'], set()) - {pid}
            others = {o for o in others if not _twin(pid, o)}     # a world day cloned into another year shares its pictures
            if others:
                r['issues'].append(f'{tag}: same URL also in {sorted(others)}')
            # cross-pack near duplicates (report once, as a warning)
            for (oid, opack, ph, dh, md) in index.near(m):
                if opack != pid and oid != p['$id'] and not _twin(pid, opack):
                    r.setdefault('cross', []).append(f'{tag} ~ {oid} ({opack})'); summary['cross_dups'] += 1
        report[pid] = r
        summary['packs'] += 1
        if r['issues']: summary['violating'] += 1
    if write:
        stamp = time.strftime('%Y-%m-%d-%H%M')
        (REPORTS / f'audit-{stamp}.json').write_text(json.dumps({'summary': summary, 'packs': report}, indent=1))
        lines = [f'# Catalogue audit {stamp}', '', f'Summary: {json.dumps(summary)}', '']
        for pid, r in report.items():
            if not r['issues'] and not r.get('cross') and not r.get('warnings'): continue
            lines.append(f"## {pid} — {r['name']} ({r['category']}, {r['count']} puzzles)")
            lines += [f'- {i}' for i in r['issues']]
            if r.get('cross'): lines.append(f"- cross-pack near-duplicates: {len(r['cross'])} (e.g. {r['cross'][0]})")
            if r.get('warnings'): lines.append(f"- title keyword hints (check visually): {len(r['warnings'])} (e.g. {r['warnings'][0]})")
            lines.append('')
        (REPORTS / f'audit-{stamp}.md').write_text('\n'.join(lines))
        print('wrote', REPORTS / f'audit-{stamp}.md')
    return summary, report
