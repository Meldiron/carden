#!/usr/bin/env python3
"""Names every daily month pack after its month ("October 2024") on the live `packs` table.

The content tool's shared specs daily-2023.json and daily-2024.json carried "name": "Daily", and
finalize_pack copied a spec's name and description onto every pack it finished, so the 24 months of
2023 and 2024 were called "Daily" in the Library (owner, 2026-10-18). The specs no longer carry a name
and finalize_pack now keeps a daily month's own name (tools/content/cjw/writer.py); this script repairs
the rows: a daily month (id daily-YYYY-MM) whose name is not "<Month> <Year>" gets that name, and the
standard month description when its description does not name the month.

Devices see the change with their next catalogue delta sync: the update moves the row's $updatedAt,
which is what the delta reads (docs/catalog-sync.md); the daily snapshot takes it in at its next run.
Other packs with an empty or bare generic name are listed, never changed.

Dry run by default; --apply writes. Key: secrets/appwrite-api-key.txt (rows.read, rows.write), or --key.
"""
import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cjw_admin as aw  # noqa: E402

MONTHS = ('January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December')
# Names that say nothing on their own (the app shows a daily month's month in place of these too:
# Pack.nameFor in lib/models/models.dart).
BARE = {'', 'daily', 'dailies', 'daily pack', 'daily puzzle', 'daily puzzles', 'daily picture', 'daily pictures', 'month', 'pack', 'untitled', 'new pack', 'event'}


def month_label(pack_id):
    m = re.fullmatch(r'daily-(\d{4})-(\d{2})', pack_id)
    if not m or not 1 <= int(m.group(2)) <= 12:
        return None
    return f'{MONTHS[int(m.group(2)) - 1]} {m.group(1)}'


def description(label):
    # The content tool's own wording for a new month (tools/content/cjw/writer.py, daily_description).
    return f"One fresh picture for every day of {label}. Solve today's for a bonus."


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--apply', action='store_true', help='write the changes (default: dry run)')
    ap.add_argument('--key', default=os.path.join(aw.ROOT, 'secrets', 'appwrite-api-key.txt'), help='API key file (rows.read, rows.write)')
    args = ap.parse_args()
    c = aw.Client(aw.load_key(args.key))

    packs = c.rows('packs', [aw.q('select', values=['$id', 'name', 'category', 'description'])])
    print(f'{len(packs)} packs read')
    fixes, odd = [], []
    for p in sorted(packs, key=lambda p: p['$id']):
        pid, name = p['$id'], p.get('name') or ''
        label = month_label(pid) if (p.get('category') == 'Daily' or pid.startswith('daily-')) else None
        if label:
            data = {}
            if name != label:
                data['name'] = label
            if label not in (p.get('description') or ''):
                data['description'] = description(label)
            if data:
                fixes.append((pid, name, data))
        elif ' '.join(name.lower().split()) in BARE or name.strip().lower() == (p.get('category') or '').lower():
            odd.append((pid, name, p.get('category')))

    for pid, name, data in fixes:
        what = f"{name!r} -> {data['name']!r}" if 'name' in data else f'{name!r} (name kept)'
        print(f"  {pid}: {what}{'  + description' if 'description' in data else ''}")
    print(f'{len(fixes)} daily month pack(s) to fix')
    for pid, name, cat in odd:
        print(f'  NOTE {pid} ({cat}): bare name {name!r}, not changed by this script')

    if not args.apply:
        print('dry run: nothing written (add --apply)')
        return
    for pid, _, data in fixes:
        c.update_row('packs', pid, data)
    print(f'{len(fixes)} pack(s) updated')
    # Read back, so a write that did not land is seen here and not in the Library.
    left = [p['$id'] for p in c.rows('packs', [aw.q('select', values=['$id', 'name', 'category'])])
            if month_label(p['$id']) and p.get('name') != month_label(p['$id'])]
    print('every daily month is named after its month' if not left else f'still wrong: {left}')
    if left:
        sys.exit(1)


if __name__ == '__main__':
    main()
