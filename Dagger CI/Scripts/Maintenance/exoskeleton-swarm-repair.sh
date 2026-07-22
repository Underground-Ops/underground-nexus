#!/usr/bin/env bash
# =============================================================================
# swarm-repair.sh (v2) — recover a single-node Docker Swarm whose manager TLS
# certificate has EXPIRED ("x509: certificate has expired" /
# "invalid cluster node while attaching to network").
#
# v2 fixes over v1 (from the 2026-07-22 field run):
#   * SELF-ELEVATES: re-executes itself under sudo if not root, so no step
#     can silently fail on root-only paths.
#   * The /var/lib/docker/swarm existence test now runs AS ROOT (v1 tested it
#     unprivileged, saw "not found", and skipped the whole leave/move step —
#     which is why init then said "already part of a swarm").
#   * LEAVE-FIRST strategy: docker swarm leave --force runs unconditionally
#     BEFORE init; if the daemon still thinks it's in a swarm, the broken
#     state directory is moved aside and docker restarted, then init retries.
#   * No associative arrays / no fancy expansions — plain newline lists only,
#     safe under set -u on any bash, and tolerant even if someone pastes it.
#   * HONEST logging: backup paths are only reported if the backup happened.
#
# DATA SAFETY: volumes are never touched. The broken swarm state is tarballed
# and moved aside (swarm.broken-<ts>), never deleted.
#
# RUN IT AS A FILE (do not paste into the terminal):
#   sudo bash swarm-repair.sh
#   DRY_RUN=1 bash swarm-repair.sh     # preview only
# =============================================================================
set -uo pipefail

# --- self-elevate ------------------------------------------------------------
if [ "$(id -u)" != "0" ] && [ "${DRY_RUN:-0}" != "1" ] && [ -z "${REPAIR_DOCKER:-}" ]; then
  echo "[swarm-repair] elevating with sudo..."
  exec sudo -E bash "$0" "$@"
fi

TS=$(date +%Y%m%d-%H%M%S)
DRY="${DRY_RUN:-0}"
DOCKER_LIB="${DOCKER_LIB:-/var/lib/docker}"
BACKUP_DIR="${BACKUP_DIR:-/root}"
D="${REPAIR_DOCKER:-docker}"
DID_BACKUP=0
DID_MOVE=0

log()  { echo "[swarm-repair] $*"; }
warn() { echo "[swarm-repair] WARN: $*"; }
act()  { if [ "$DRY" = 1 ]; then echo "  (dry-run) $*"; else "$@"; fi; }

docker_stop() {
  [ "${SKIP_RESTART:-0}" = "1" ] && return 0
  if command -v systemctl >/dev/null 2>&1 && systemctl stop docker 2>/dev/null; then return 0; fi
  service docker stop 2>/dev/null || warn "could not stop docker automatically"
}
docker_start() {
  [ "${SKIP_RESTART:-0}" = "1" ] && return 0
  if command -v systemctl >/dev/null 2>&1 && systemctl start docker 2>/dev/null; then :;
  else service docker start 2>/dev/null || warn "start docker manually, then rerun"; fi
  local i; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    $D info >/dev/null 2>&1 && return 0; sleep 2
  done
  warn "docker daemon did not come back in time"
}

# -----------------------------------------------------------------------------
# STEP 1 — confirm the failure signature
# -----------------------------------------------------------------------------
INFO=$($D info 2>&1 || true)
if echo "$INFO" | grep -qi "certificate has expired"; then
  log "confirmed: swarm manager TLS certificate is EXPIRED"
elif echo "$INFO" | grep -q "Swarm: error"; then
  log "confirmed: swarm state is in error"
elif [ "${FORCE:-0}" = "1" ]; then
  warn "swarm does not look broken, but FORCE=1 — proceeding"
else
  log "swarm looks healthy. Nothing to repair. (FORCE=1 to override.)"
  exit 0
fi

# -----------------------------------------------------------------------------
# STEP 2 — harvest (BEFORE touching the daemon): every container name, and
# every network name referenced by a container that no longer resolves.
# Plain newline lists only — no arrays.
# -----------------------------------------------------------------------------
EXISTING_NETS=$($D network ls --format '{{.Name}}' 2>/dev/null || true)
ALL_CTS=$($D ps -a --format '{{.Names}}' 2>/dev/null || true)

MISSING_NETS=""
AFFECTED_CTS=""
for ct in $ALL_CTS; do
  refs=$($D inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$ct" 2>/dev/null || true)
  hit=0
  for n in $refs; do
    if ! printf '%s\n' "$EXISTING_NETS" | grep -qx "$n"; then
      hit=1
      printf '%s\n' "$MISSING_NETS" | grep -qx "$n" || MISSING_NETS="${MISSING_NETS}${n}
"
    fi
  done
  [ "$hit" = 1 ] && AFFECTED_CTS="${AFFECTED_CTS}${ct}
"
done

if [ -n "$MISSING_NETS" ]; then
  log "missing networks referenced by containers: $(echo $MISSING_NETS | tr '\n' ' ')"
  log "affected containers: $(echo $AFFECTED_CTS | tr '\n' ' ')"
else
  warn "no container references a missing network — repairing swarm state only."
fi

# -----------------------------------------------------------------------------
# STEP 3 — leave first; if the daemon still claims membership, back up and
# move the broken state aside, restart, and verify it's clean.
# -----------------------------------------------------------------------------
act $D swarm leave --force >/dev/null 2>&1 || true

STILL_IN_SWARM=0
$D info 2>/dev/null | grep -qE "Swarm: (active|pending|error)" && STILL_IN_SWARM=1

if [ "$STILL_IN_SWARM" = 1 ] || $D swarm init 2>&1 | grep -q "already part of a swarm"; then
  log "daemon still holds broken swarm state — moving it aside (root-checked this time)"
  if [ "$DRY" = 1 ] || test -d "${DOCKER_LIB}/swarm"; then
    log "backing up swarm state to ${BACKUP_DIR}/swarm-state-${TS}.tgz"
    act tar czf "${BACKUP_DIR}/swarm-state-${TS}.tgz" -C "$DOCKER_LIB" swarm && DID_BACKUP=1
    docker_stop
    act mv "${DOCKER_LIB}/swarm" "${DOCKER_LIB}/swarm.broken-${TS}" && DID_MOVE=1
    docker_start
  else
    warn "${DOCKER_LIB}/swarm not found even as root — continuing to init"
  fi
fi

# -----------------------------------------------------------------------------
# STEP 4 — fresh swarm init + 1-year cert expiry (prevents recurrence)
# -----------------------------------------------------------------------------
ADDR=$($D info -f '{{.Swarm.NodeAddr}}' 2>/dev/null || true)
[ -z "$ADDR" ] && ADDR=$(hostname -I 2>/dev/null | awk '{print $1}')
log "initializing fresh single-node swarm (advertise ${ADDR:-auto})..."
INIT_OK=0
if [ -n "$ADDR" ] && act $D swarm init --advertise-addr "$ADDR" >/dev/null 2>&1; then INIT_OK=1
elif act $D swarm init >/dev/null 2>&1; then INIT_OK=1
fi
if [ "$INIT_OK" = 1 ]; then
  log "swarm initialized"
  act $D swarm update --cert-expiry 8760h0m0s >/dev/null 2>&1 \
    && log "certificate expiry extended to 1 year" \
    || warn "cert-expiry extension failed (non-fatal)"
else
  warn "swarm init still failing — daemon may need a full restart; run: sudo service docker restart, then rerun this script"
fi

# -----------------------------------------------------------------------------
# STEP 5 — recreate the missing networks (attachable overlay, bridge fallback)
# -----------------------------------------------------------------------------
for n in $MISSING_NETS; do
  log "recreating network: $n"
  if ! act $D network create -d overlay --attachable "$n" >/dev/null 2>&1; then
    warn "overlay create failed for $n — falling back to bridge"
    act $D network create -d bridge "$n" >/dev/null 2>&1 || warn "bridge fallback failed for $n"
  fi
done

# -----------------------------------------------------------------------------
# STEP 6 — start affected containers (connect + one retry on failure)
# -----------------------------------------------------------------------------
PASS=""; FAIL=""
for ct in $AFFECTED_CTS; do
  if act $D start "$ct" >/dev/null 2>&1; then
    PASS="$PASS $ct"
  else
    for n in $MISSING_NETS; do act $D network connect "$n" "$ct" >/dev/null 2>&1 || true; done
    if act $D start "$ct" >/dev/null 2>&1; then PASS="$PASS $ct"; else FAIL="$FAIL $ct"; fi
  fi
done

# -----------------------------------------------------------------------------
# STEP 7 — verify (honest: only report what actually happened)
# -----------------------------------------------------------------------------
log "──────────── verification ────────────"
$D info 2>/dev/null | grep -E "Swarm:|Is Manager|NodeID" | sed 's/^/[swarm-repair]   /' || true
$D node ls 2>/dev/null | sed 's/^/[swarm-repair]   /' || true
[ -n "$PASS" ] && log "recovered containers:$PASS"
[ -n "$FAIL" ] && warn "still failing:$FAIL — check: docker logs <name>"
[ "$DID_BACKUP" = 1 ] && log "backup: ${BACKUP_DIR}/swarm-state-${TS}.tgz"
[ "$DID_MOVE"   = 1 ] && log "old state preserved at: ${DOCKER_LIB}/swarm.broken-${TS}"
[ "$DID_BACKUP" = 0 ] && [ "$DID_MOVE" = 0 ] && log "note: no state files were moved this run"
log "volumes were never touched. DONE."
