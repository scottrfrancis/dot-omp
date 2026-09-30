#!/usr/bin/env bash
# install.sh: wire this dot-omp repo into omp's agent dir (~/.omp/agent).
#
#   ./install.sh                 # link models.yml, apply settings.conf + machines/<host>-<os>.conf
#   ./install.sh --copy          # copy models.yml instead of linking it
#   ./install.sh --machine NAME  # use machines/NAME.conf instead of the detected one
#   ./install.sh --dry-run       # show what would happen, change nothing
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

echo "Done. Check with: omp config get modelRoles; omp config get edit.mode"
