#!/usr/bin/env python3
"""Puts Carden's Daily puzzle widget on a simulator's Home Screen, or takes the Home Screen back.

There is no simctl command for widgets and no Simulator window to drag one in, so this edits the
simulator's SpringBoard layout (data/Library/SpringBoard/IconState.plist) while the simulator is shut
down: a first page with the widget in the sizes asked for. Install the app first, while the simulator
is booted, and let its icon appear (a layout written right after an install can be dropped). Then
`xcrun simctl io <udid> screenshot` shows the widget, and the widget's own log (archive errors such as
"image being too large") is in
  xcrun simctl spawn <udid> log show --last 5m --predicate 'process == "DailyWidget"'

  tools/dev/sim_home_widget.py add <udid> [small|medium|large ...]   (default: large medium)
  tools/dev/sim_home_widget.py restore <udid>

`add` shuts the simulator down, keeps the original layout next to it (IconState.carden-backup.plist)
and boots it again; `restore` puts the original back the same way.
"""
import os
import plistlib
import shutil
import subprocess
import sys
import uuid


def run(*args):
    subprocess.run(args, check=False, capture_output=True)


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ('add', 'restore'):
        sys.exit(__doc__)
    action, udid, sizes = sys.argv[1], sys.argv[2], sys.argv[3:] or ['large', 'medium']
    folder = os.path.expanduser(f'~/Library/Developer/CoreSimulator/Devices/{udid}/data/Library/SpringBoard')
    path, backup = os.path.join(folder, 'IconState.plist'), os.path.join(folder, 'IconState.carden-backup.plist')
    if not os.path.exists(path):
        sys.exit(f'no Home Screen layout at {path}')
    run('xcrun', 'simctl', 'shutdown', udid)
    if action == 'restore':
        if os.path.exists(backup):
            shutil.move(backup, path)
            print('Home Screen restored')
        else:
            print('nothing to restore')
    else:
        if not os.path.exists(backup):
            shutil.copyfile(path, backup)
        with open(backup, 'rb') as f:
            state = plistlib.load(f)
        page = [{
            'allowsExternalSuggestions': True,
            'allowsSuggestions': True,
            'bundleIdentifier': 'com.matejbaco.cardjigsawworld.DailyWidget',
            'containerBundleIdentifier': 'com.matejbaco.cardjigsawworld',
            'displayIdentifier': str(uuid.uuid4()).upper(),
            'elementType': 'widget',
            'gridSize': size,
            'iconType': 'custom',
            'uniqueIdentifier': str(uuid.uuid4()).upper(),
            'widgetIdentifier': 'DailyWidget',
        } for size in sizes]
        state['iconLists'] = [page] + state.get('iconLists', [])
        if 'listUniqueIdentifiers' in state:
            state['listUniqueIdentifiers'] = [str(uuid.uuid4()).upper()] + state['listUniqueIdentifiers']
        with open(path, 'wb') as f:
            plistlib.dump(state, f, fmt=plistlib.FMT_BINARY)
        print(f'widget on the first page: {", ".join(sizes)}')
    run('xcrun', 'simctl', 'boot', udid)
    run('xcrun', 'simctl', 'bootstatus', udid, '-b')


if __name__ == '__main__':
    main()
