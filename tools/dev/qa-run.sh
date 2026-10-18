#!/usr/bin/env bash
# Every app run made while working on the game goes through here (simulator, browser, integration
# tests): silent (CJW_MUTE) and flagged as a QA run (CJW_QA), so the guest it plays on the live
# backend is a test player that never shows in the league; when the run ends, the test players it
# created are purged (user, rows, photos; backup in secrets/purged/).
#
#   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
#       --target=integration_test/screenshots_test.dart -d <udid>
#   tools/dev/qa-run.sh run -d <udid>             interactive run, purged when you quit
#   tools/dev/qa-run.sh run -d web-server --web-port 8123    web (a headless browser opens it)
#   QA_KEEP=1 tools/dev/qa-run.sh ...             keep the run's players (purge them later)
#
# The run id reaches the app as CJW_QA_RUN and is stored on the guest, so the purge deletes only
# this run's players and runs in other sessions keep theirs. The purge runs once on every way out
# that can be caught: a normal end, Ctrl-C (INT), TERM, HUP (the terminal or the parent went away)
# and any other exit of this script; a signal to this script stops flutter too. Only a hard kill
# (KILL) skips it; leftovers:
#   python3 tools/dev/purge_test_players.py purge --apply
set -uo pipefail
cd "$(dirname "$0")/../.."
export PATH="$HOME/flutter/bin:$PATH"
if [ $# -lt 1 ]; then sed -n '2,18p' "$0"; exit 2; fi
cmd=$1; shift
case "$cmd" in
  run|drive|test) ;;
  *) echo "qa-run.sh: the first argument is the flutter command (run, drive or test)" >&2; exit 2 ;;
esac
RUN_ID="qa-$(date +%Y%m%d-%H%M%S)-$$"
PY=python3
[ -x .venv/bin/python ] && PY=.venv/bin/python

# Messages may have nowhere to go (the parent and its pipe are gone): a failed write must not
# stop the purge.
say() { echo "qa-run: $*" 2>/dev/null; }

purged=
purge() {
  # Once only: a signal's trap purges, then its exit runs the EXIT trap, which must not purge again.
  [ -n "$purged" ] && return
  purged=1
  # A closed output pipe must not kill the script halfway through the purge.
  trap '' PIPE
  # flutter drive logs every driver command, screenshots included, to build/ and never trims the
  # file; it reached 17 GB and filled the disk (2026-10-18).
  rm -f build/flutter_driver_commands_*.log
  if [ -n "${QA_KEEP:-}" ]; then
    say "kept the test players of $RUN_ID (QA_KEEP); purge later with tools/dev/purge_test_players.py purge --apply"
    return
  fi
  if [ ! -f secrets/appwrite-users-key.txt ]; then
    say "secrets/appwrite-users-key.txt missing, test players of $RUN_ID not purged" >&2
    return
  fi
  # The purge writes to a log first and the log is shown afterwards, so a closed terminal or pipe
  # cannot stop it partway; the log stays when the purge fails.
  local log="${TMPDIR:-/tmp}/qa-run-$RUN_ID.log"
  if "$PY" tools/dev/purge_test_players.py purge --run "$RUN_ID" --apply --quiet >"$log" 2>&1; then
    cat "$log" 2>/dev/null
    rm -f "$log"
  else
    cat "$log" 2>/dev/null
    say "purge failed (log: $log); run tools/dev/purge_test_players.py purge --apply later" >&2
  fi
}

# A signal stops the run: flutter gets a moment to end on its own (Ctrl-C and a closed terminal
# reach it too), then TERM (a signal sent to this script alone, say by a parent stopping it, does
# not), and the players are purged once flutter is gone.
child=
stop() {
  if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then
    for _ in 1 2 3 4; do
      kill -0 "$child" 2>/dev/null || break
      sleep 0.5
    done
    kill -TERM "$child" 2>/dev/null
    wait "$child" 2>/dev/null
  fi
  purge
  exit "$1"
}
trap 'purge' EXIT
trap 'stop 129' HUP
trap 'stop 130' INT
trap 'stop 143' TERM

say "$RUN_ID (silent, test player, purged afterwards)"
# In the background so a signal is handled at once (bash runs traps only between commands); stdin
# stays the terminal's, for flutter run's keys.
flutter "$cmd" --dart-define=CJW_MUTE=true --dart-define=CJW_QA=true --dart-define=CJW_QA_RUN="$RUN_ID" "$@" <&0 &
child=$!
wait "$child"
code=$?
purge
exit $code
