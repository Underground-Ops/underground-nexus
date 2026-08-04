#!/usr/bin/env bash
# =============================================================================
# gitbios-panel-uninstall.sh — remove the Git-BIOS Control Panel
# Cloud Underground · v1.0 · July 2026
#
# The panel is an UNDERGROUND NEXUS app, not a Golden Twin one. Golden Twin's
# own `manage.sh uninstall` deliberately leaves it alone: your buttons are your
# work, and the panel keeps working without the Twin. This script is the
# separate, deliberate removal.
#
# It undoes exactly what build-gitbios-hypervisor-panel.sh created:
#   · the app directory (wherever it landed — container or bare metal)
#   · the systemd unit  gitbios-control-panel.service  (stopped, disabled, removed)
#   · the s6 service    /etc/s6-overlay/s6-rc.d/gitbios (+ user/contents.d entry)
#
# It deliberately does NOT remove rofi / terminator / x11-xserver-utils /
# xdg-utils. Those are general desktop tools other things may now depend on.
#
# MODES
#   (default)         remove services + app directory
#   --restore-stock   undo ONLY Golden Twin's customisation and KEEP a working
#                     upstream panel: restores the .orig landing page and the
#                     newest .bak profiles. Nothing is deleted.
#   --services-only   stop and remove the services, leave every file in place
#   --dry-run         print the plan, change nothing
#   --keep-profiles   skip the profile rescue archive (default: it saves one)
#   --yes             skip the typed confirmation (unattended)
#   --app-dir <path>  point at a non-standard install
# =============================================================================
set -uo pipefail

C_R=$'\033[0m'; C_B=$'\033[1m'; C_Y=$'\033[33m'; C_G=$'\033[32m'; C_E=$'\033[31m'
say()  { printf '%s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$C_G" "$C_R" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_R" "$*"; }
err()  { printf '  %s✗%s %s\n' "$C_E" "$C_R" "$*" >&2; }
hr()   { printf '%s\n' "──────────────────────────────────────────────────────────"; }
sec()  { printf '\n%s%s%s\n' "$C_B" "$*" "$C_R"; hr; }

DRY=0; YES=0; MODE=full; KEEP_PROFILES=0; APP_DIR_OVERRIDE=""
FAILS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)       DRY=1; shift ;;
    --yes|-y)        YES=1; shift ;;
    --restore-stock) MODE=restore; shift ;;
    --services-only) MODE=services; shift ;;
    --keep-profiles) KEEP_PROFILES=1; shift ;;
    --app-dir)       APP_DIR_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help)       sed -n '2,40p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) err "unknown flag: $1"; exit 1 ;;
  esac
done

run() {  # run <description> <cmd...>   — honours --dry-run, never aborts
  local d="$1"; shift
  if [ "$DRY" = "1" ]; then printf '  would: %s\n' "$d"; return 0; fi
  if "$@" 2>/dev/null; then ok "$d"; else
    warn "failed (continuing): $d"; FAILS=$((FAILS + 1)); fi
}

[ "$(id -u)" -eq 0 ] || [ "$DRY" = "1" ] || {
  err "Run as root: sudo bash $0 $*"; exit 1; }

# -----------------------------------------------------------------------------
sec "Locating the Git-BIOS Control Panel"
# -----------------------------------------------------------------------------
# The build script installs to ${NEXUS_ROOT}/Jelly-Apps/Git-BIOS-Control-Panel;
# NEXUS_ROOT differs between a bare-metal clone and the Creator Vault's
# Desktop bucket. Check every location the kit is known to use.
CANDIDATES=(
  "/underground-nexus/Jelly-Apps/Git-BIOS-Control-Panel"
  "/config/Desktop/nexus-bucket/underground-nexus/Jelly-Apps/Git-BIOS-Control-Panel"
  "/nexus-bucket/underground-nexus/Jelly-Apps/Git-BIOS-Control-Panel"
  "$HOME/Desktop/nexus-bucket/underground-nexus/Jelly-Apps/Git-BIOS-Control-Panel"
)
APP_DIR=""
if [ -n "$APP_DIR_OVERRIDE" ]; then
  APP_DIR="$APP_DIR_OVERRIDE"
  [ -d "$APP_DIR" ] || { err "--app-dir does not exist: $APP_DIR"; exit 1; }
  ok "using override: $APP_DIR"
else
  for c in "${CANDIDATES[@]}"; do
    if [ -d "$c" ]; then APP_DIR="$c"; ok "found: $APP_DIR"; break; fi
  done
  # last resort: a filesystem search, bounded so it cannot run away
  if [ -z "$APP_DIR" ]; then
    APP_DIR="$(find / -maxdepth 7 -type d -name 'Git-BIOS-Control-Panel' \
               -not -path '*/proc/*' 2>/dev/null | head -1)"
    [ -n "$APP_DIR" ] && ok "found by search: $APP_DIR"
  fi
fi
[ -z "$APP_DIR" ] && warn "no app directory found — services will still be cleaned"

PORT="$(grep -rhoE 'PORT[= ]+[0-9]{2,5}' "$APP_DIR" 2>/dev/null | grep -oE '[0-9]{2,5}' | head -1)"
PORT="${PORT:-5000}"
if command -v curl >/dev/null 2>&1 && curl -sf -m 2 "localhost:${PORT}" >/dev/null 2>&1; then
  warn "panel is currently RUNNING on port ${PORT}"
else
  ok "panel not responding on port ${PORT} (already stopped, or a different port)"
fi

# -----------------------------------------------------------------------------
if [ "$MODE" = "restore" ]; then
sec "RESTORE STOCK — undo Golden Twin's customisation, keep the panel"
# -----------------------------------------------------------------------------
  # The build script preserves what it replaced: the landing page as
  # <name>.orig, and every profile it overwrote as <name>.bak.<epoch>.
  # Restoring those returns the upstream app without deleting anything.
  [ -z "$APP_DIR" ] && { err "need an app directory for --restore-stock"; exit 1; }
  restored=0
  while IFS= read -r orig; do
    [ -n "$orig" ] || continue
    run "restored $(basename "${orig%.orig}")" cp -a "$orig" "${orig%.orig}"
    restored=$((restored + 1))
  done < <(find "$APP_DIR" -name '*.orig' 2>/dev/null)

  # newest .bak.<epoch> per profile — an operator may have several generations
  while IFS= read -r base; do
    [ -n "$base" ] || continue
    newest="$(ls -1t "${base}".bak.* 2>/dev/null | head -1)"
    [ -n "$newest" ] || continue
    run "restored profile $(basename "$base")" cp -a "$newest" "$base"
    restored=$((restored + 1))
  done < <(find "$APP_DIR/profiles" -name '*.json' -not -name '*.bak.*' 2>/dev/null)

  if [ "$restored" = "0" ]; then
    warn "no .orig or .bak files found — either the kit was never applied here,"
    warn "  or this install was built fresh rather than over a stock panel."
  else
    ok "${restored} file(s) restored"
    say ""
    say "  Restart the panel to pick them up:"
    say "    sudo systemctl restart gitbios-control-panel   # bare metal"
    say "    sudo s6-svc -r /run/service/gitbios            # container"
  fi
  say ""
  ok "Done — nothing was deleted."
  exit 0
fi

# -----------------------------------------------------------------------------
sec "Plan"
# -----------------------------------------------------------------------------
say "  Mode          : $([ "$MODE" = services ] && echo 'services only' || echo 'full removal')"
say "  App directory : ${APP_DIR:-<none found>}"
say "  systemd unit  : gitbios-control-panel.service"
say "  s6 service    : /etc/s6-overlay/s6-rc.d/gitbios"
say ""
say "  NOT removed: rofi, terminator, x11-xserver-utils, xdg-utils"
say "               (general desktop tools other software may rely on)"
if [ "$MODE" = "full" ] && [ -n "$APP_DIR" ]; then
  say ""
  say "  ${C_Y}Your button profiles live in ${APP_DIR}/profiles${C_R}"
  [ "$KEEP_PROFILES" = "0" ] \
    && say "  A rescue archive will be written before anything is deleted." \
    || say "  --keep-profiles: NO rescue archive will be written."
fi

if [ "$DRY" = "0" ] && [ "$YES" = "0" ] && [ "$MODE" = "full" ]; then
  say ""
  printf '  Type %sREMOVE%s to proceed (anything else cancels): ' "$C_B" "$C_R"
  IFS= read -r ans || ans=""
  [ "$ans" = "REMOVE" ] || { say ""; warn "Cancelled — nothing changed."; exit 0; }
fi

# -----------------------------------------------------------------------------
sec "Stopping services"
# -----------------------------------------------------------------------------
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files 2>/dev/null | grep -q '^gitbios-control-panel'; then
    run "stopped gitbios-control-panel.service"    systemctl stop gitbios-control-panel.service
    run "disabled gitbios-control-panel.service"   systemctl disable gitbios-control-panel.service
    run "removed unit file"                        rm -f /etc/systemd/system/gitbios-control-panel.service
    run "systemd daemon-reload"                    systemctl daemon-reload
    run "cleared failed units"                     systemctl reset-failed
  else
    ok "no systemd unit installed"
  fi
else
  ok "systemd not present (container)"
fi

if [ -d /etc/s6-overlay/s6-rc.d/gitbios ] || [ -e /run/service/gitbios ]; then
  [ -e /run/service/gitbios ] && run "stopped s6 service" s6-svc -wD -d -T 5000 /run/service/gitbios
  run "removed s6 service definition" rm -rf /etc/s6-overlay/s6-rc.d/gitbios
  run "removed s6 user bundle entry"  rm -f  /etc/s6-overlay/s6-rc.d/user/contents.d/gitbios
else
  ok "no s6 service installed"
fi

# a process may survive a missing supervisor (started by hand, desktop icon)
if command -v pgrep >/dev/null 2>&1; then
  pids="$(pgrep -f 'Git-BIOS-Control-Panel.*server\.py' 2>/dev/null || true)"
  if [ -n "$pids" ]; then
    warn "panel process still running (pid: $(echo "$pids" | tr '\n' ' '))"
    for p in $pids; do run "stopped pid $p" kill "$p"; done
  fi
fi

[ "$MODE" = "services" ] && { say ""; sec "SERVICES REMOVED"
  say "  Files left in place at: ${APP_DIR:-<none>}"; exit 0; }

# -----------------------------------------------------------------------------
sec "Removing files"
# -----------------------------------------------------------------------------
if [ -n "$APP_DIR" ] && [ -d "$APP_DIR" ]; then
  if [ "$KEEP_PROFILES" = "0" ] && [ -d "$APP_DIR/profiles" ]; then
    RESCUE="/root/gitbios-profiles-rescue-$(date +%Y%m%d-%H%M%S).tar.gz"
    [ -d /root ] || RESCUE="/tmp/$(basename "$RESCUE")"
    if [ "$DRY" = "1" ]; then
      printf '  would: save profiles to %s\n' "$RESCUE"
    elif tar -czf "$RESCUE" -C "$APP_DIR" profiles 2>/dev/null; then
      ok "profiles saved: $RESCUE"
      say "     (restore later: tar -xzf '$RESCUE' -C <new-app-dir>)"
    else
      warn "could not write the rescue archive — profiles will be lost"
      FAILS=$((FAILS + 1))
    fi
  fi
  # ${APP_DIR:?} — a guard against an empty variable becoming `rm -rf /`
  run "removed $APP_DIR" rm -rf "${APP_DIR:?}"
else
  ok "no app directory to remove"
fi

for d in "$HOME/Desktop" /config/Desktop /root/Desktop /usr/share/applications; do
  [ -d "$d" ] || continue
  while IFS= read -r f; do
    [ -n "$f" ] && run "removed desktop entry $(basename "$f")" rm -f "$f"
  done < <(grep -rlsi 'git-bios\|gitbios' "$d"/*.desktop 2>/dev/null)
done

# -----------------------------------------------------------------------------
sec "DONE"
# -----------------------------------------------------------------------------
if [ "$DRY" = "1" ]; then
  say "  Dry run — nothing was changed. Re-run without --dry-run to apply."
elif [ "$FAILS" -gt 0 ]; then
  warn "$FAILS step(s) failed. Re-running this script is safe and will retry."
else
  ok "Git-BIOS Control Panel removed."
fi
say ""
say "  Golden Twin is untouched — its MCP tools will simply report the panel"
say "  as absent. Reinstall the panel any time with:"
say "    sudo bash build-gitbios-hypervisor-panel.sh"
say ""
