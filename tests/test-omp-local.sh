#!/usr/bin/env bash
# Tests for bin/omp-local.sh with stubbed systemctl, curl and omp on PATH.
# Run: tests/test-omp-local.sh   (exit 0 = all pass)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAP="$REPO/bin/omp-local.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
STUB="$T/stub"; mkdir -p "$STUB"
LOG="$T/calls.log"; export STUB_LOG="$LOG" STUB_STATE="$T/state"

# curl: /health succeeds once the service is "active"; the Nth poll after start flips it.
cat > "$STUB/curl" <<'S'
#!/usr/bin/env bash
echo "curl $*" >> "$STUB_LOG"
if [ -f "$STUB_STATE/active" ]; then
  n=$(cat "$STUB_STATE/polls-until-healthy" 2>/dev/null || echo 0)
  if [ "$n" -gt 0 ]; then echo $((n-1)) > "$STUB_STATE/polls-until-healthy"; exit 7; fi
  exit 0
fi
exit 7
S
cat > "$STUB/systemctl" <<'S'
#!/usr/bin/env bash
echo "systemctl $*" >> "$STUB_LOG"
case "$*" in
  *" start "*) [ -f "$STUB_STATE/refuse-start" ] && exit 1; touch "$STUB_STATE/active" ;;
  *" stop "*)  rm -f "$STUB_STATE/active" ;;
  *" is-active "*) [ -f "$STUB_STATE/active" ] ;;
esac
S
cat > "$STUB/omp" <<'S'
#!/usr/bin/env bash
echo "omp $*" >> "$STUB_LOG"
exit "${STUB_OMP_EXIT:-0}"
S
chmod +x "$STUB"/*
export PATH="$STUB:$PATH" OMP_LOCAL_SLEEP=0 OMP_LOCAL_TIMEOUT=5

pass=0 fail=0
reset() { rm -rf "$STUB_STATE"; mkdir -p "$STUB_STATE"; : > "$LOG"; unset OMP_LOCAL_KEEP STUB_OMP_EXIT; }
check() { # check NAME CONDITION...
  local name="$1"; shift
  if "$@"; then pass=$((pass+1)); echo "ok   $name"; else fail=$((fail+1)); echo "FAIL $name"; sed 's/^/     /' "$LOG"; fi
}
logged()    { grep -q -- "$1" "$LOG"; }
notlogged() { ! grep -q -- "$1" "$LOG"; }

echo "# server already up: no start, no stop, args passed through"
reset; touch "$STUB_STATE/active"
"$WRAP" -p "hello world" >/dev/null 2>&1
check "passes args to omp"       logged "\-p hello world"
check "binds the local model"    logged "omp --model llama.cpp/qwen3.6-35b-a3b-mtp -p hello world"
check "does not start"           notlogged "systemctl --user start"
check "does not stop"            notlogged "systemctl --user stop"

echo "# server down: start, wait for health, run omp, stop afterwards"
reset; echo 2 > "$STUB_STATE/polls-until-healthy"
"$WRAP" -p hi >/dev/null 2>&1; rc=$?
check "starts the unit"          logged "systemctl --user start llama-qwen36"
check "polls health before omp"  bash -c "grep -n 'curl.*health' '$LOG' | tail -1 | cut -d: -f1 | xargs -I{} test {} -lt \$(grep -n '^omp' '$LOG' | cut -d: -f1)"
check "runs omp"                 logged "\-p hi"
check "stops the unit after"     logged "systemctl --user stop llama-qwen36"
check "exit code 0"              test "$rc" -eq 0

echo "# an explicit --model wins; OMP_LOCAL_MODEL overrides the default"
reset; touch "$STUB_STATE/active"
"$WRAP" --model dev-ai/workhorse -p hi >/dev/null 2>&1
check "explicit --model kept"    logged "omp --model dev-ai/workhorse -p hi"
check "no second --model"        bash -c "[ \"\$(grep -o -- '--model' '$LOG' | wc -l)\" -eq 1 ]"
reset; touch "$STUB_STATE/active"
"$WRAP" --model=foo/bar -p hi >/dev/null 2>&1
check "--model=value kept"       notlogged "llama.cpp/"
reset; touch "$STUB_STATE/active"
OMP_LOCAL_MODEL=llama.cpp/other "$WRAP" -p hi >/dev/null 2>&1
check "env override used"        logged "omp --model llama.cpp/other -p hi"

echo "# OMP_LOCAL_KEEP=1 leaves the server running"
reset; export OMP_LOCAL_KEEP=1
"$WRAP" -p hi >/dev/null 2>&1
check "keeps the unit"           notlogged "systemctl --user stop"

echo "# omp's exit code is propagated"
reset; touch "$STUB_STATE/active"; export STUB_OMP_EXIT=3
"$WRAP" -p hi >/dev/null 2>&1; rc=$?
check "exit code 3"              test "$rc" -eq 3

echo "# unit refuses to start: fail fast, never run omp"
reset; touch "$STUB_STATE/refuse-start"
"$WRAP" -p hi >/dev/null 2>&1; rc=$?
check "nonzero exit"             test "$rc" -ne 0
check "omp not run"              notlogged "^omp"

echo "# unit starts but never becomes healthy within the timeout"
reset; echo 999 > "$STUB_STATE/polls-until-healthy"; export OMP_LOCAL_TIMEOUT=1
"$WRAP" -p hi >/dev/null 2>&1; rc=$?
check "times out nonzero"        test "$rc" -ne 0
check "omp not run on timeout"   notlogged "^omp"
check "stops what it started"    logged "systemctl --user stop"
export OMP_LOCAL_TIMEOUT=5

echo "# subcommands: up / down / status, without launching omp"
reset
"$WRAP" up >/dev/null 2>&1; rc=$?
check "up starts"                logged "systemctl --user start"
check "up leaves it running"     notlogged "systemctl --user stop"
check "up never runs omp"        notlogged "^omp"
check "up exit 0"                test "$rc" -eq 0
reset; touch "$STUB_STATE/active"
"$WRAP" down >/dev/null 2>&1
check "down stops"               logged "systemctl --user stop"
reset; touch "$STUB_STATE/active"
"$WRAP" status >/dev/null 2>&1; rc=$?
check "status up -> 0"           test "$rc" -eq 0
reset
"$WRAP" status >/dev/null 2>&1; rc=$?
check "status down -> nonzero"   test "$rc" -ne 0
check "status never starts"      notlogged "systemctl --user start"

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
