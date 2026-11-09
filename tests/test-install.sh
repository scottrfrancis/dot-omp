#!/usr/bin/env bash
# Tests for install.sh with a stubbed `omp` on PATH and a throwaway agent dir.
# Run: tests/test-install.sh   (exit 0 = all pass)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
STUB="$T/stub"; mkdir -p "$STUB"
LOG="$T/calls.log"; export STUB_LOG="$LOG"
cat > "$STUB/omp" <<'S'
#!/usr/bin/env bash
echo "omp $*" >> "$STUB_LOG"
S
chmod +x "$STUB/omp"
export PATH="$STUB:$PATH"

pass=0 fail=0
check() { # check NAME CONDITION...
  local name="$1"; shift
  if "$@"; then pass=$((pass+1)); echo "ok   $name"; else fail=$((fail+1)); echo "FAIL $name"; sed 's/^/     /' "$LOG"; fi
}
logged()    { grep -qF -- "$1" "$LOG"; }
notlogged() { ! grep -qF -- "$1" "$LOG"; }
linked_to() { [ -L "$1" ] && [ "$(readlink -f "$1")" = "$(readlink -f "$2")" ]; }

echo "# fresh agent dir: links models.yml, AGENTS.md and the side-effect gate, applies settings"
A="$T/agent1"; : > "$LOG"
OMP_AGENT_DIR="$A" OMP_LOCAL_BIN="$T/bin" "$REPO/install.sh" --machine bladerunner14-linux >/dev/null 2>&1
check "links models.yml"                 linked_to "$A/models.yml" "$REPO/models.yml"
check "links AGENTS.md"                  linked_to "$A/AGENTS.md" "$REPO/agent/AGENTS.md"
check "links the side-effect gate"       linked_to "$A/extensions/side-effect-gate.ts" "$REPO/extensions/side-effect-gate.ts"
check "sets approval mode to write"      logged "omp config set tools.approvalMode write"
check "saves compaction handoffs to disk" logged "omp config set compaction.handoffSaveToDisk true"
check "applies the machine file"         logged "omp config set modelRoles"

echo "# an existing real AGENTS.md is backed up, not clobbered"
A="$T/agent2"; mkdir -p "$A"; echo "mine" > "$A/AGENTS.md"; : > "$LOG"
OMP_AGENT_DIR="$A" OMP_LOCAL_BIN="$T/bin" "$REPO/install.sh" --machine bladerunner14-linux >/dev/null 2>&1
check "replaces with a link"             linked_to "$A/AGENTS.md" "$REPO/agent/AGENTS.md"
check "backup holds the old text"        bash -c "cat '$A'/AGENTS.md.bak.* | grep -qx mine"

echo "# dry run changes nothing"
A="$T/agent3"; : > "$LOG"
OMP_AGENT_DIR="$A" OMP_LOCAL_BIN="$T/bin" "$REPO/install.sh" --machine bladerunner14-linux --dry-run >/dev/null 2>&1
check "creates no agent dir"             test ! -e "$A"
check "calls omp config set for nothing" notlogged "omp config set"

echo "# the gate source is well formed enough to be an extension"
check "gate has a default export"        grep -q '^export default' "$REPO/extensions/side-effect-gate.ts"
check "gate hooks tool_call"             grep -q '"tool_call"' "$REPO/extensions/side-effect-gate.ts"
check "AGENTS.md names the print rule"   grep -qi 'print job' "$REPO/agent/AGENTS.md"

echo; echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
