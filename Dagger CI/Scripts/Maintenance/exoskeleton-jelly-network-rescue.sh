#!/usr/bin/env bash
# =============================================================================
# jelly-network-rescue.sh — restore jelly-app networking after a swarm repair
# (companion to exoskeleton-swarm-repair.sh; run second if containers still
#  fail to attach with "network <id> not found")
#
# THE REMAINING FAILURE after the swarm itself was fixed:
#   docker start planka →
#     Could not attach to network mw4g5joamwnm2nt7vnx3cj27p: … not found
#   The containers' stored endpoints are pinned to the DEAD overlay's ID.
#   Docker 29.x resolves stored endpoints by ID, not name — so recreating a
#   network with the same name is not enough; the stale endpoint must be
#   stripped from each container, then the container reconnected.
#
# WHAT THIS DOES (data-preserving; volumes never touched):
#   1. Requires an ACTIVE swarm (run swarm-repair.sh first).
#   2. sovereign-net restoration to its ORIGINAL capability class:
#      it was a swarm-scope overlay; if a plain bridge now squats the name
#      (and nothing is attached to it), it is removed and recreated as
#        docker network create -d overlay --attachable sovereign-net
#      — same class as before: swarm-scoped, multi-host-capable, attachable.
#      (Cilium/eBPF was NEVER at the docker layer — it lives inside the SEC
#      k3d kits via Calico's eBPF dataplane and is unaffected.)
#   3. For each jelly container: every stored endpoint whose network ID no
#      longer exists is force-disconnected (by name, then by ID as fallback).
#   4. Reconnects each to sovereign-net (+ its *-internal net is untouched,
#      those endpoints are healthy), then starts it, one retry.
#   5. Reattaches the always-up core (cerberus-manager, nexus-creator-vault,
#      edge-router) to sovereign-net so the manager and vault can reach the
#      jelly apps exactly like the original layout. The compose-owned
#      cerberus_cerberus-net is NOT touched.
#   6. Verifies and prints a status table.
#
# RUN AS A FILE (never paste):   sudo bash jelly-network-rescue.sh
#                                DRY_RUN=1 bash jelly-network-rescue.sh
# =============================================================================
set -uo pipefail

if [ "$(id -u)" != "0" ] && [ "${DRY_RUN:-0}" != "1" ] && [ -z "${RESCUE_DOCKER:-}" ]; then
  echo "[rescue] elevating with sudo..."
  exec sudo -E bash "$0" "$@"
fi

DRY="${DRY_RUN:-0}"
D="${RESCUE_DOCKER:-docker}"
NET="sovereign-net"
JELLY="planka bookstack uptime-kuma n8n vaultwarden portainer"
CORE="cerberus-manager nexus-creator-vault edge-router"

log()  { echo "[rescue] $*"; }
warn() { echo "[rescue] WARN: $*"; }
act()  { if [ "$DRY" = 1 ]; then echo "  (dry-run) $*"; else "$@"; fi; }

# ---------------------------------------------------------------- STEP 1 ----
if ! $D info 2>/dev/null | grep -q "Swarm: active"; then
  echo "[rescue] ERROR: swarm is not active — run swarm-repair.sh first."
  exit 1
fi
log "swarm active — proceeding"

# ---------------------------------------------------------------- STEP 2 ----
DRIVER=$($D network inspect -f '{{.Driver}}' "$NET" 2>/dev/null || true)
if [ "$DRIVER" = "overlay" ]; then
  log "$NET already an overlay — keeping it"
elif [ "$DRIVER" = "bridge" ]; then
  ATTACHED=$($D network inspect -f '{{len .Containers}}' "$NET" 2>/dev/null || echo 0)
  if [ "${ATTACHED:-0}" = "0" ]; then
    log "$NET exists as a plain bridge with nothing attached — recreating as attachable overlay (original class)"
    act $D network rm "$NET" >/dev/null 2>&1 || warn "could not remove bridge $NET"
    act $D network create -d overlay --attachable "$NET" >/dev/null 2>&1 \
      && log "$NET recreated: swarm-scope overlay, attachable" \
      || { warn "overlay create failed — recreating as bridge fallback"; act $D network create -d bridge "$NET" >/dev/null 2>&1 || true; }
  else
    warn "$NET is a bridge but has ${ATTACHED} attached container(s) — leaving driver as-is"
  fi
else
  log "$NET missing — creating as attachable overlay"
  act $D network create -d overlay --attachable "$NET" >/dev/null 2>&1 || warn "overlay create failed"
fi

# ---------------------------------------------------------------- STEP 3+4 --
PASS=""; FAIL=""
for ct in $JELLY; do
  $D inspect "$ct" >/dev/null 2>&1 || { warn "$ct: not found — skipping"; continue; }
  log "── $ct ──"
  PAIRS=$($D inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}={{$v.NetworkID}}
{{end}}' "$ct" 2>/dev/null || true)
  for pair in $PAIRS; do
    name="${pair%%=*}"; nid="${pair#*=}"
    [ -z "$name" ] && continue
    if ! $D network inspect "$nid" >/dev/null 2>&1; then
      log "  stale endpoint: $name (id ${nid:0:12}… no longer exists) — stripping"
      if ! act $D network disconnect -f "$name" "$ct" >/dev/null 2>&1; then
        act $D network disconnect -f "$nid" "$ct" >/dev/null 2>&1 \
          || warn "  could not strip $name from $ct by name or id"
      fi
    fi
  done
  # ensure membership: only a RESOLVABLE sovereign-net endpoint counts
  # (a stale same-named endpoint must not fool the check)
  HAS_GOOD=0
  NOWP=$($D inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}={{$v.NetworkID}}
{{end}}' "$ct" 2>/dev/null || true)
  for pair in $NOWP; do
    name="${pair%%=*}"; nid="${pair#*=}"
    if [ "$name" = "$NET" ] && $D network inspect "$nid" >/dev/null 2>&1; then HAS_GOOD=1; fi
  done
  if [ "$HAS_GOOD" = 0 ]; then
    act $D network connect "$NET" "$ct" >/dev/null 2>&1 \
      && log "  connected to $NET" || warn "  connect to $NET failed"
  fi
  # start with one retry
  if act $D start "$ct" >/dev/null 2>&1; then
    PASS="$PASS $ct"; log "  started ✓"
  else
    sleep 2
    if act $D start "$ct" >/dev/null 2>&1; then PASS="$PASS $ct"; log "  started ✓ (retry)"
    else FAIL="$FAIL $ct"; warn "  still failing — check: docker logs $ct"; fi
  fi
done

# ---------------------------------------------------------------- STEP 5 ----
for ct in $CORE; do
  $D inspect "$ct" >/dev/null 2>&1 || continue
  NOW=$($D inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$ct" 2>/dev/null || true)
  if printf '%s' "$NOW" | grep -qw "$NET"; then
    log "core $ct: already on $NET"
  else
    act $D network connect "$NET" "$ct" >/dev/null 2>&1 \
      && log "core $ct: attached to $NET (manager/vault reach jelly apps as before)" \
      || warn "core $ct: could not attach to $NET"
  fi
done

# ---------------------------------------------------------------- STEP 6 ----
log "──────────── verification ────────────"
log "$NET: driver=$($D network inspect -f '{{.Driver}}' "$NET" 2>/dev/null) scope=$($D network inspect -f '{{.Scope}}' "$NET" 2>/dev/null)"
MEMBERS=$($D network inspect -f '{{range $k,$v := .Containers}}{{$v.Name}} {{end}}' "$NET" 2>/dev/null || true)
log "$NET members: ${MEMBERS:-<none>}"
[ -n "$PASS" ] && log "recovered:$PASS"
[ -n "$FAIL" ] && warn "still down:$FAIL"
log "cerberus_cerberus-net untouched (compose-owned); eBPF (Calico) lives in the SEC k3d kits and is unaffected."
log "volumes were never touched. DONE."
