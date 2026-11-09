#!/usr/bin/env bash
# install.sh: wire this dot-omp repo into omp's agent dir (~/.omp/agent).
#
#   ./install.sh                 # link models.yml, apply settings.conf + machines/<host>-<os>.conf
#   ./install.sh --copy          # copy models.yml instead of linking it
#   ./install.sh --machine NAME  # use machines/NAME.conf instead of the detected one
#   ./install.sh --dry-run       # show what would happen, change nothing
#
# Also links bin/omp-local.sh to ~/.local/bin/omp-local (Linux/mac): the wrapper that starts
# the on-demand llama-server before omp and stops it afterwards.
#
# models.yml is linked: omp reads it and does not write it. config.yml is omp's own
# file (`omp config set` rewrites it), so settings are APPLIED through omp rather than
# linked, which keeps this checkout clean. Re-run after pulling; it is idempotent.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="${OMP_AGENT_DIR:-$HOME/.omp/agent}"
MODE=link DRY=0 MACHINE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --copy) MODE=copy ;;
    --dry-run) DRY=1 ;;
    --machine) MACHINE="${2:?--machine needs a name}"; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

host="$(hostname -s 2>/dev/null || hostname)"
os="$(uname -s)"
case "$os" in Linux) os=linux ;; Darwin) os=mac ;; MINGW*|MSYS*|CYGWIN*) os=windows ;; esac
MACHINE="${MACHINE:-$(echo "$host-$os" | tr '[:upper:]' '[:lower:]')}"
MFILE="$REPO/machines/$MACHINE.conf"

run() { if [ "$DRY" = 1 ]; then echo "  would run: $*"; else "$@"; fi; }
command -v omp >/dev/null || { echo "omp not found on PATH; install it first (see README)." >&2; exit 1; }

echo "dot-omp -> $AGENT_DIR  (models.yml: $MODE, machine: $MACHINE)"
run mkdir -p "$AGENT_DIR"

# models.yml: back up a real file once, then link or copy.
dst="$AGENT_DIR/models.yml"
if [ -e "$dst" ] && [ ! -L "$dst" ]; then
  if cmp -s "$dst" "$REPO/models.yml"; then run rm -f "$dst"
  else run mv "$dst" "$dst.bak.$(date +%Y%m%d-%H%M%S)"; echo "  backed up existing models.yml"; fi
fi
if [ "$MODE" = copy ]; then run cp "$REPO/models.yml" "$dst"; else run ln -sfn "$REPO/models.yml" "$dst"; fi
echo "  models.yml: $MODE"

# settings: shared first, then the machine file (later lines win).
apply() {
  local file="$1" key val
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    key="${line%%[[:space:]]*}"
    val="${line#"$key"}"; val="${val#"${val%%[![:space:]]*}"}"
    run omp config set "$key" "$val" >/dev/null
    echo "  set $key"
  done < "$file"
}
apply "$REPO/settings.conf"
if [ -f "$MFILE" ]; then
  apply "$MFILE"
else
  echo "  NOTE: no machines/$MACHINE.conf; shared settings only. Copy one of machines/*.conf to start."
fi

# AGENTS.md: the standing rules every session gets, project or not. Linked like models.yml,
# with a one-time backup of any real file already there.
dst="$AGENT_DIR/AGENTS.md"
if [ -e "$dst" ] && [ ! -L "$dst" ]; then
  if cmp -s "$dst" "$REPO/agent/AGENTS.md"; then run rm -f "$dst"
  else run mv "$dst" "$dst.bak.$(date +%Y%m%d-%H%M%S)"; echo "  backed up existing AGENTS.md"; fi
fi
run ln -sfn "$REPO/agent/AGENTS.md" "$dst"
echo "  AGENTS.md: linked"

# Extensions: each file under extensions/ is linked into the agent's extensions dir, where
# omp discovers it at startup. Other tools (herdr) keep their own files beside ours.
run mkdir -p "$AGENT_DIR/extensions"
for ext in "$REPO"/extensions/*.ts; do
  [ -e "$ext" ] || continue
  run ln -sfn "$ext" "$AGENT_DIR/extensions/$(basename "$ext")"
  echo "  extension: $(basename "$ext")"
done

# omp-local wrapper (Linux/mac only; the local tier on Windows is LM Studio, always on).
if [ "$os" != windows ]; then
  BIN_DIR="${OMP_LOCAL_BIN:-$HOME/.local/bin}"
  run mkdir -p "$BIN_DIR"
  run ln -sfn "$REPO/bin/omp-local.sh" "$BIN_DIR/omp-local"
  echo "  omp-local: linked to $BIN_DIR/omp-local"
fi

echo "Done. Check with: omp config get modelRoles; omp config get tools.approvalMode; ls -l $AGENT_DIR/AGENTS.md; omp-local status"
