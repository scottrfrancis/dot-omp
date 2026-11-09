#!/usr/bin/env bash
# omp-local.sh: run omp against the local llama.cpp tier, starting llama-server first.
#
#   omp-local [omp args...]   # ensure the server is up, run omp, stop the server after
#   omp-local up              # just start the server and wait until it answers /health
#   omp-local down            # stop it (frees the dGPU and about 23 GB of RAM)
#   omp-local status          # is it answering? exit 0 = yes
#
# The server is a user service that is stopped by default (on-demand by design: battery,
# VRAM, RAM). This wrapper is the switch. If it started the server it stops it again when
# omp exits, unless OMP_LOCAL_KEEP=1. A server that was already running is left alone.
#
# Environment:
#   OMP_LOCAL_UNIT     systemd user unit            (default llama-qwen36)
#   OMP_LOCAL_URL      server base URL              (default http://127.0.0.1:8080)
#   OMP_LOCAL_TIMEOUT  seconds to wait for /health  (default 120; a warm start takes ~10 s)
#   OMP_LOCAL_KEEP     1 = leave the server running after omp exits
set -euo pipefail

UNIT="${OMP_LOCAL_UNIT:-llama-qwen36}"
URL="${OMP_LOCAL_URL:-http://127.0.0.1:8080}"
TIMEOUT="${OMP_LOCAL_TIMEOUT:-120}"
SLEEP="${OMP_LOCAL_SLEEP:-1}"   # poll interval; tests set 0

log() { printf 'omp-local: %s\n' "$*" >&2; }
healthy() { curl -sf --max-time 2 "$URL/health" >/dev/null 2>&1; }
unit_stop() { systemctl --user stop "$UNIT"; }

wait_healthy() {
  local deadline=$(( $(date +%s) + TIMEOUT ))
  until healthy; do
    if ! systemctl --user is-active --quiet "$UNIT"; then
      log "$UNIT is not running; see: journalctl --user -u $UNIT -n 40"; return 1
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      log "$UNIT did not answer $URL/health within ${TIMEOUT}s"; return 1
    fi
    sleep "$SLEEP"
  done
}

# Start the unit and wait. Returns 0 when the server answers.
unit_up() {
  if healthy; then log "server already up at $URL"; return 0; fi
  log "starting $UNIT ..."
  systemctl --user start "$UNIT" || { log "systemctl --user start $UNIT failed"; return 1; }
  wait_healthy || { unit_stop 2>/dev/null || true; return 1; }
  log "server up at $URL"
}

case "${1:-}" in
  up)     unit_up; exit ;;
  down)   log "stopping $UNIT"; unit_stop; exit ;;
  status) if healthy; then log "up at $URL"; exit 0; else log "down ($URL not answering)"; exit 1; fi ;;
esac

command -v omp >/dev/null || { log "omp not found on PATH"; exit 127; }

started=0
if healthy; then
  log "server already up at $URL; leaving it running afterwards"
else
  unit_up || exit 1
  started=1
fi

cleanup() {
  if [ "$started" = 1 ] && [ "${OMP_LOCAL_KEEP:-0}" != 1 ]; then
    log "stopping $UNIT (set OMP_LOCAL_KEEP=1 to leave it running)"
    unit_stop || true
  fi
}
trap cleanup EXIT

set +e
omp "$@"
rc=$?
set -e
exit "$rc"
