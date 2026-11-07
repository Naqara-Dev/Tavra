#!/bin/bash
# End to end, without touching the desktop or a single real click: the app starts in the background,
# with no menu bar item, against a throwaway folder. A scripted finger goes into the router, and a
# logging stand-in says what it would have done.
set -u
cd "$(dirname "$0")/.."
APP="$(pwd)/build/Build/Products/Debug/Tavra.app"
BIN="$APP/Contents/MacOS/Tavra"
T="$(mktemp -d)"
export TAVRA_HOME="$T/home"
mkdir -p "$TAVRA_HOME"
FAILED=0; PASSED=0
stop_app() { pkill -f "$BIN" 2>/dev/null; sleep 0.8; }
trap 'stop_app; rm -rf "$T"' EXIT
pass() { PASSED=$((PASSED + 1)); }
fail() { FAILED=$((FAILED + 1)); echo "✗ $1"; }
expect() { if eval "$2"; then pass; else fail "$1"; fi; }
config() { # extra JSON on top of a quiet setup
  local extra="{}"
  [[ $# -ge 1 ]] && extra="$1"
  python3 - "$TAVRA_HOME/config.json" "$extra" <<'PY'
import json, sys
c = {"showInMenuBar": False, "showInDock": False, "onboarded": True}
c.update(json.loads(sys.argv[2]))
json.dump(c, open(sys.argv[1], "w"))
PY
}
start_app() { : > "$T/log"; open -g -n "$APP" --stdout "$T/log" --stderr "$T/err" --env TAVRA_HOME="$TAVRA_HOME" --args -ApplePersistenceIgnoreState YES "$@"; }
wait_for() { for _ in $(seq 1 $(($1 * 2))); do grep -q -- "$2" "$T/log" 2>/dev/null && return 0; sleep 0.5; done; return 1; }
has() { grep -qF -- "$1" "$T/log"; }

echo "› Gestures, from a scripted finger"
config; start_app -TavraFake YES -TavraDemo YES -TavraPage trackpad
expect "it starts" 'wait_for 8 "TAVRA_READY onboarding=false"'
expect "the script runs to the end" 'wait_for 15 "TAVRA_DEMO done"'
expect "a click in the middle goes through" 'has "TAVRA_CLICK middle passed"'
expect "and its release" 'has "TAVRA_CLICK middle-up passed"'
expect "a click on the right edge is taken" 'has "TAVRA_CLICK right taken"'
expect "the pointer is held" 'has "TAVRA_DO pointer held"'
expect "sliding up raises the volume" 'has "TAVRA_DO step Volume up"'
expect "sliding back lowers it" 'has "TAVRA_DO step Volume down"'
expect "the pointer is let go" 'has "TAVRA_DO pointer free"'
expect "the bottom edge starts a seek" 'has "TAVRA_DO timeline start"'
expect "and jumps on letting go" 'grep -q "TAVRA_DO timeline jump [1-9]" "$T/log"'
expect "the corner plays or pauses" 'has "TAVRA_DO tap Play or pause"'
HELD=$(grep -c "pointer held" "$T/log"); FREE=$(grep -c "pointer free" "$T/log")
expect "every time the pointer was held, it was let go" '[[ "$HELD" == "$FREE" && "$HELD" -ge 1 ]]'
stop_app

echo "› Your settings"
config '{"bindings":{"slides":{"right":{"brightness":{}}},"taps":{}}}'; start_app -TavraFake YES -TavraDemo YES -TavraPage trackpad
wait_for 15 "TAVRA_DEMO done"
expect "the right edge does what it was given" 'has "TAVRA_DO step Brightness up"'
expect "the corner that was cleared does nothing" '! has "TAVRA_DO tap"'
stop_app
config '{"paused":true}'; start_app -TavraFake YES -TavraDemo YES -TavraPage trackpad
wait_for 15 "TAVRA_DEMO done"
expect "paused, the edge click goes through" 'has "TAVRA_CLICK right passed"'
expect "paused, nothing happens" '! has "TAVRA_DO"'
stop_app

echo "› First run"
rm -f "$TAVRA_HOME/config.json"; python3 -c "import json; json.dump({'showInMenuBar': False}, open('$TAVRA_HOME/config.json', 'w'))"
start_app -TavraFake YES -TavraUntrusted YES
expect "a new Mac gets the welcome" 'wait_for 8 "TAVRA_READY onboarding=true"'
stop_app
config '{"onboarded":false}'; start_app -TavraFake YES -TavraStep check -TavraCheckDemo 4
expect "the check finds the right edge" 'wait_for 10 "TAVRA_GESTURE CHECK right"'
expect "and the left" 'wait_for 5 "TAVRA_GESTURE CHECK left"'
expect "and the bottom" 'wait_for 5 "TAVRA_GESTURE CHECK bottom"'
expect "and the top" 'wait_for 5 "TAVRA_GESTURE CHECK top"'
expect "touching doesn't start a gesture or do anything" '! has "TAVRA_DO"'
stop_app

echo "› The real thing, reading only"
config; start_app -TavraPage trackpad
sleep 6
PID="$(pgrep -f "$BIN" | head -1)"
expect "it runs with the real trackpad feed" '[[ -n "$PID" ]]'
if [[ -n "$PID" ]]; then
  CPU="$(ps -o %cpu= -p "$PID" | tr -d " ")"
  echo "  CPU ${CPU}%, $(ps -o rss= -p "$PID" | awk '{print int($1/1024)}') MB, with its window showing"
fi
expect "without Accessibility it holds no clicks" '! has "TAVRA_DO"'
stop_app

pgrep -f "$BIN" >/dev/null && fail "a test instance is still running"
if [[ $FAILED -eq 0 ]]; then echo "✓ $PASSED end-to-end checks passed"; else echo "✗ $FAILED failed, $PASSED passed"; exit 1; fi
