#!/usr/bin/env bash
# =============================================================================
# sovereign-lima-resize.sh — Cloud Underground · Underground Nexus
# Interactive resizer for the `sovereign` Lima VM on macOS (Apple Silicon
# and Intel Macs). Adjusts CPUs, RAM and disk on an EXISTING VM.
#
#   bash sovereign-lima-resize.sh              # interactive form
#   bash sovereign-lima-resize.sh --show       # just print current sizing
#   bash sovereign-lima-resize.sh --cpus 10 --memory 16 --disk 500   # no prompts
#   bash sovereign-lima-resize.sh --dry-run    # show the plan, change nothing
#
# YOUR DATA IS NOT TOUCHED. This resizes the VM's allocation and grows the
# filesystem. It never reformats, never recreates the VM, and never deletes
# the disk image. Containers, volumes and /config survive.
#
# WHICH WAY EACH KNOB TURNS  ← read this before you type numbers
#   CPUs    ── UP and DOWN freely. Applied on next boot.
#   RAM     ── UP and DOWN freely. Applied on next boot.
#   DISK    ── UP ONLY, PERMANENTLY. A qcow2/raw disk can be grown safely
#              but SHRINKING it truncates the tail of the filesystem and
#              destroys data. This script REFUSES to shrink. If you need a
#              smaller disk, back up and rebuild the VM.
#
# HEADROOM: macOS needs RAM too. A host that swaps is slower than the VM you
# were trying to speed up. This script warns if you leave the host under 8 GB
# and refuses to leave it under 4 GB.
# =============================================================================
set -uo pipefail

VM="${SOVEREIGN_VM:-sovereign}"
LIMA_DIR="${HOME}/.lima/${VM}"
YAML="${LIMA_DIR}/lima.yaml"
MIN_HOST_GB=4          # hard floor left for macOS
WARN_HOST_GB=8         # advisory floor
DRY=0; SHOW_ONLY=0
ARG_CPUS=""; ARG_MEM=""; ARG_DISK=""

C_R=$'\033[0m'; C_B=$'\033[1m'; C_Y=$'\033[33m'; C_G=$'\033[32m'; C_E=$'\033[31m'
say()  { printf '%s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$C_G" "$C_R" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_R" "$*"; }
err()  { printf '  %s✗%s %s\n' "$C_E" "$C_R" "$*"; }
hr()   { printf '%s\n' "──────────────────────────────────────────────────────────"; }
title(){ echo; hr; printf '  %s%s%s\n' "$C_B" "$*" "$C_R"; hr; }

while [ $# -gt 0 ]; do
  case "$1" in
    --show)     SHOW_ONLY=1 ;;
    --dry-run)  DRY=1 ;;
    --cpus)     shift; ARG_CPUS="${1:-}" ;;
    --memory)   shift; ARG_MEM="${1:-}" ;;
    --disk)     shift; ARG_DISK="${1:-}" ;;
    --vm)       shift; VM="${1:-sovereign}"; LIMA_DIR="${HOME}/.lima/${VM}"; YAML="${LIMA_DIR}/lima.yaml" ;;
    -h|--help)  sed -n '2,40p' "$0"; exit 0 ;;
    *)          err "unknown option: $1"; exit 2 ;;
  esac
  shift
done

# -----------------------------------------------------------------------------
title "STEP 1 — is Lima installed and does '${VM}' exist?"
# -----------------------------------------------------------------------------
if ! command -v limactl >/dev/null 2>&1; then
  err "limactl not found."
  say ""
  say "  Lima is not installed, so there is no VM to resize. Install it and"
  say "  provision the Sovereign VM first:"
  say ""
  say "      brew install lima"
  say "      # then run the macOS Sovereign Installer from Underground Nexus:"
  say "      #   Sovereign-Exoskeleton-Engine/Installers/Mac-OS/"
  say "      #     sovereign-installer-mac-arm64   (Apple Silicon)"
  say "      #     sovereign-installer-mac-intel   (Intel Mac)"
  say "      # https://github.com/Underground-Ops/underground-nexus"
  say ""
  say "  Re-run this script after the installer finishes."
  exit 1
fi
ok "limactl present: $(limactl --version 2>/dev/null | head -1)"

if ! limactl list -q 2>/dev/null | grep -qx "${VM}"; then
  err "No Lima VM named '${VM}'."
  say ""
  say "  VMs Lima currently knows about:"
  limactl list 2>/dev/null | sed 's/^/      /' || say "      (none)"
  say ""
  say "  Nothing to resize. Provision the Sovereign VM first with the macOS"
  say "  Sovereign Installer from Underground Nexus:"
  say "      Sovereign-Exoskeleton-Engine/Installers/Mac-OS/sovereign-installer-mac-arm64"
  say "      (or sovereign-installer-mac-intel on an Intel Mac)"
  say "      https://github.com/Underground-Ops/underground-nexus"
  say ""
  say "  Then re-run this script. If your VM has a different name:"
  say "      bash $0 --vm <name>"
  exit 1
fi
ok "VM '${VM}' exists"
[ -f "$YAML" ] || { err "config missing: $YAML"; exit 1; }

# the disk image filename differs across Lima versions
DISK_IMG=""
for cand in "${LIMA_DIR}/diffdisk" "${LIMA_DIR}/disk" "${LIMA_DIR}/basedisk"; do
  [ -f "$cand" ] && { DISK_IMG="$cand"; break; }
done
[ -n "$DISK_IMG" ] || { err "no disk image found under ${LIMA_DIR}"; exit 1; }
ok "disk image: ${DISK_IMG##*/}"

# -----------------------------------------------------------------------------
title "STEP 2 — current sizing"
# -----------------------------------------------------------------------------
yaml_get() { grep -E "^[[:space:]]*$1:" "$YAML" 2>/dev/null | head -1 \
             | sed -E 's/.*:[[:space:]]*"?([^"#]*)"?.*/\1/' | tr -d ' '; }
to_gib()  { printf '%s' "$1" | sed -E 's/GiB|GB|G//I'; }

CUR_CPUS="$(yaml_get cpus)"
CUR_MEM_RAW="$(yaml_get memory)"
CUR_DISK_RAW="$(yaml_get disk)"
CUR_MEM="$(to_gib "${CUR_MEM_RAW:-0}")"
CUR_DISK="$(to_gib "${CUR_DISK_RAW:-0}")"
IMG_BYTES=$(stat -f%z "$DISK_IMG" 2>/dev/null || stat -c%s "$DISK_IMG" 2>/dev/null || echo 0)
IMG_GB=$(( IMG_BYTES / 1024 / 1024 / 1024 ))
STATUS="$(limactl list --format '{{.Status}}' "$VM" 2>/dev/null || echo unknown)"

HOST_CPUS=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 0)
HOST_MEM_GB=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1024 / 1024 / 1024 ))
[ "$HOST_MEM_GB" -eq 0 ] && HOST_MEM_GB=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo 0)

printf "  %-22s %s\n" "VM name"        "$VM"
printf "  %-22s %s\n" "status"         "$STATUS"
printf "  %-22s %s\n" "CPUs"           "${CUR_CPUS:-?}"
printf "  %-22s %s GiB\n" "RAM"        "${CUR_MEM:-?}"
printf "  %-22s %s GiB (config)  ·  %s GiB on disk now\n" "Disk" "${CUR_DISK:-?}" "$IMG_GB"
echo
printf "  %-22s %s cores\n" "HOST has" "$HOST_CPUS"
printf "  %-22s %s GiB\n"   ""         "$HOST_MEM_GB"
if [ "$STATUS" = "Running" ] && command -v limactl >/dev/null; then
  echo
  say "  Filesystem inside the VM:"
  limactl shell "$VM" -- df -h / 2>/dev/null | sed 's/^/      /' || true
fi
[ "$SHOW_ONLY" = 1 ] && exit 0

# -----------------------------------------------------------------------------
title "STEP 3 — what would you like to change?"
# -----------------------------------------------------------------------------
say "  Press ENTER to keep a value unchanged."
say "  Type ${C_B}q${C_R} at any prompt to cancel — nothing is written until you"
say "  confirm the plan at the end, and Ctrl-C is safe at any point."
echo
say "  ${C_B}CPUs and RAM change in BOTH directions.${C_R}"
say "  ${C_B}${C_Y}DISK GROWS ONLY, PERMANENTLY${C_R} — shrinking a disk destroys data, so"
say "  this script will refuse it and tell you why."
echo

ask() {                       # ask <label> <current> <varname> <unit>
  local label="$1" cur="$2" var="$3" unit="$4" input
  while :; do
    printf '  %s [current: %s%s] : ' "$label" "$cur" "$unit"
    IFS= read -r input || { echo; return 1; }
    case "$input" in
      q|Q|quit) return 1 ;;
      "")       eval "$var=\"\$cur\""; return 0 ;;
    esac
    if ! printf '%s' "$input" | grep -qE '^[0-9]+$'; then
      err "\"$input\" is not a whole number. Try again (or q to cancel)."
      continue
    fi
    eval "$var=\"\$input\""; return 0
  done
}

NEW_CPUS="${ARG_CPUS:-}"; NEW_MEM="${ARG_MEM:-}"; NEW_DISK="${ARG_DISK:-}"
if [ -z "$NEW_CPUS$NEW_MEM$NEW_DISK" ]; then
  ask "CPUs  " "${CUR_CPUS:-2}"  NEW_CPUS ""     || { echo; warn "cancelled — nothing changed."; exit 0; }
  ask "RAM   " "${CUR_MEM:-4}"   NEW_MEM  " GiB" || { echo; warn "cancelled — nothing changed."; exit 0; }
  ask "Disk  " "${CUR_DISK:-60}" NEW_DISK " GiB" || { echo; warn "cancelled — nothing changed."; exit 0; }
else
  NEW_CPUS="${NEW_CPUS:-$CUR_CPUS}"; NEW_MEM="${NEW_MEM:-$CUR_MEM}"; NEW_DISK="${NEW_DISK:-$CUR_DISK}"
fi

# -----------------------------------------------------------------------------
title "STEP 4 — validation"
# -----------------------------------------------------------------------------
FATAL=0
# --- CPUs -------------------------------------------------------------------
if [ "$NEW_CPUS" -lt 1 ]; then
  err "CPUs must be at least 1."; FATAL=1
elif [ "$HOST_CPUS" -gt 0 ] && [ "$NEW_CPUS" -gt "$HOST_CPUS" ]; then
  err "CPUs ${NEW_CPUS} exceeds the host's ${HOST_CPUS} cores. Over-committing"
  say "      makes the VM slower, not faster. Pick ${HOST_CPUS} or fewer."
  FATAL=1
elif [ "$HOST_CPUS" -gt 2 ] && [ "$NEW_CPUS" -eq "$HOST_CPUS" ]; then
  warn "CPUs ${NEW_CPUS} = every host core. macOS will contend with the VM."
  say "      $(( HOST_CPUS - 2 )) or fewer leaves the host responsive."
else
  ok "CPUs ${CUR_CPUS} → ${NEW_CPUS}"
fi
# --- RAM --------------------------------------------------------------------
LEFT=$(( HOST_MEM_GB - NEW_MEM ))
if [ "$NEW_MEM" -lt 2 ]; then
  err "RAM must be at least 2 GiB — the Nexus stack will not start below that."
  FATAL=1
elif [ "$HOST_MEM_GB" -gt 0 ] && [ "$LEFT" -lt "$MIN_HOST_GB" ]; then
  err "RAM ${NEW_MEM} GiB would leave macOS only ${LEFT} GiB."
  say "      A swapping host is slower than the VM you are trying to speed up."
  say "      Maximum safe value on this machine: $(( HOST_MEM_GB - WARN_HOST_GB )) GiB"
  say "      (absolute ceiling $(( HOST_MEM_GB - MIN_HOST_GB )) GiB, not recommended)."
  FATAL=1
elif [ "$HOST_MEM_GB" -gt 0 ] && [ "$LEFT" -lt "$WARN_HOST_GB" ]; then
  warn "RAM ${NEW_MEM} GiB leaves macOS ${LEFT} GiB — tight but allowed."
  say "      $(( HOST_MEM_GB - WARN_HOST_GB )) GiB is the comfortable maximum here."
else
  ok "RAM ${CUR_MEM} → ${NEW_MEM} GiB (macOS keeps ${LEFT} GiB)"
fi
# --- Disk -------------------------------------------------------------------
if [ "$NEW_DISK" -lt "${CUR_DISK:-0}" ]; then
  err "Disk ${NEW_DISK} GiB is SMALLER than the current ${CUR_DISK} GiB."
  say ""
  say "      ${C_B}This script will not shrink a disk.${C_R} Truncating a disk image cuts"
  say "      the tail off the filesystem, and everything living there — your"
  say "      containers, volumes and /config — goes with it. There is no undo."
  say ""
  say "      Disk is the one knob that only turns one way. Enter ${CUR_DISK} or"
  say "      higher. If you genuinely need a smaller VM: back up with"
  say "      'manage.sh backup', delete the VM, and re-provision."
  FATAL=1
elif [ "$NEW_DISK" -eq "${CUR_DISK:-0}" ]; then
  ok "Disk unchanged at ${NEW_DISK} GiB"
else
  FREE_GB=$(df -g "${HOME}" 2>/dev/null | awk 'NR==2{print $4}')
  GROW=$(( NEW_DISK - CUR_DISK ))
  if [ -n "${FREE_GB:-}" ] && [ "$FREE_GB" -gt 0 ] && [ "$GROW" -gt "$FREE_GB" ]; then
    warn "Growing by ${GROW} GiB but only ${FREE_GB} GiB free on the Mac."
    say "      Lima disks are sparse, so this usually still works — the space is"
    say "      consumed as it fills. Watch your free space."
  fi
  ok "Disk ${CUR_DISK} → ${NEW_DISK} GiB (grow by ${GROW} GiB, permanent)"
fi

if [ "$FATAL" = 1 ]; then
  echo; hr
  err "Nothing was changed. Fix the values above and run again:"
  say "      bash $0"
  say "  or skip the form entirely:"
  say "      bash $0 --cpus <n> --memory <GiB> --disk <GiB>"
  exit 3
fi

if [ "$NEW_CPUS" = "${CUR_CPUS:-}" ] && [ "$NEW_MEM" = "${CUR_MEM:-}" ] && [ "$NEW_DISK" = "${CUR_DISK:-}" ]; then
  echo; ok "Every value matches the current configuration — nothing to do."
  exit 0
fi

# -----------------------------------------------------------------------------
title "STEP 5 — the plan"
# -----------------------------------------------------------------------------
printf "  CPUs   %s → %s\n"           "${CUR_CPUS:-?}" "$NEW_CPUS"
printf "  RAM    %s → %s GiB\n"       "${CUR_MEM:-?}"  "$NEW_MEM"
printf "  Disk   %s → %s GiB%s\n"     "${CUR_DISK:-?}" "$NEW_DISK" \
       "$( [ "$NEW_DISK" -gt "${CUR_DISK:-0}" ] && echo '   (permanent)' )"
echo
say "  Sequence: stop VM → edit ${YAML##*/} → grow disk image → start VM"
say "            → growpart /dev/vda 1 → resize2fs → report."
say "  A backup of the config is kept as lima.yaml.bak-<timestamp>."
say "  Expect 1–3 minutes. Docker containers restart with the VM."
echo
if [ "$DRY" = 1 ]; then warn "--dry-run: stopping here, nothing changed."; exit 0; fi
printf '  Type %sAPPLY%s to proceed (anything else cancels): ' "$C_B" "$C_R"
IFS= read -r CONFIRM || true
[ "$CONFIRM" = "APPLY" ] || { echo; warn "cancelled — nothing changed."; exit 0; }

# -----------------------------------------------------------------------------
title "STEP 6 — applying"
# -----------------------------------------------------------------------------
TS="$(date +%Y%m%d-%H%M%S)"
cp "$YAML" "${YAML}.bak-${TS}" && ok "config backed up: lima.yaml.bak-${TS}"

say "  stopping ${VM}..."
limactl stop "$VM" 2>/dev/null || true
for i in $(seq 1 30); do
  [ "$(limactl list --format '{{.Status}}' "$VM" 2>/dev/null)" = "Running" ] || break
  sleep 2
done
ok "stopped"

# sed -i '' is BSD/macOS syntax; GNU sed needs -i with no arg
if sed --version >/dev/null 2>&1; then SEDI=(-i); else SEDI=(-i ''); fi
set_yaml() {   # set_yaml <key> <value-with-quotes-or-not>
  local k="$1" v="$2"
  if grep -qE "^[[:space:]]*${k}:" "$YAML"; then
    sed "${SEDI[@]}" -E "s|^([[:space:]]*)${k}:.*|\1${k}: ${v}|" "$YAML"
  else
    printf '%s: %s\n' "$k" "$v" >> "$YAML"
  fi
}
set_yaml cpus   "$NEW_CPUS"          && ok "cpus: ${NEW_CPUS}"
set_yaml memory "\"${NEW_MEM}GiB\""  && ok "memory: ${NEW_MEM}GiB"
set_yaml disk   "\"${NEW_DISK}GiB\"" && ok "disk: ${NEW_DISK}GiB"

if [ "$NEW_DISK" -gt "${CUR_DISK:-0}" ]; then
  say "  growing disk image to ${NEW_DISK}G..."
  if truncate -s "${NEW_DISK}G" "$DISK_IMG" 2>/dev/null; then
    ok "image grown: $(ls -lh "$DISK_IMG" | awk '{print $5}')"
  else
    err "truncate failed — restoring config and aborting."
    cp "${YAML}.bak-${TS}" "$YAML"; limactl start "$VM" >/dev/null 2>&1 &
    exit 4
  fi
fi

say "  starting ${VM}... (this is the slow part)"
if ! limactl start "$VM"; then
  err "VM failed to start. Config backup is at ${YAML}.bak-${TS}."
  say "      Restore it with:  cp ${YAML}.bak-${TS} ${YAML} && limactl start ${VM}"
  exit 5
fi
ok "started"

if [ "$NEW_DISK" -gt "${CUR_DISK:-0}" ]; then
  say "  expanding the filesystem inside the VM..."
  limactl shell "$VM" -- sudo apt-get install -y cloud-guest-utils -qq >/dev/null 2>&1 \
    || warn "cloud-guest-utils install reported an issue (may already be present)"
  limactl shell "$VM" -- sudo growpart /dev/vda 1 2>&1 | sed 's/^/      /' || \
    warn "growpart reported an issue — if the partition was already at full size this is expected"
  limactl shell "$VM" -- sudo resize2fs /dev/vda1 2>&1 | sed 's/^/      /' || \
    warn "resize2fs reported an issue"
fi

# -----------------------------------------------------------------------------
title "RESULT"
# -----------------------------------------------------------------------------
say "  Config now reads:"
grep -E "^[[:space:]]*(cpus|memory|disk):" "$YAML" | sed 's/^/      /'
echo
say "  Inside the VM:"
limactl shell "$VM" -- sh -c 'nproc | sed "s/^/      cores: /"; \
  free -g 2>/dev/null | awk "/^Mem:/{print \"      ram:   \"\$2\" GiB\"}"; \
  df -h / | tail -1 | awk "{print \"      disk:  \"\$2\" total, \"\$4\" free\"}"' 2>/dev/null || true
echo
say "  Docker containers:"
limactl shell "$VM" -- docker ps --format '      {{.Names}}  {{.Status}}' 2>/dev/null \
  || warn "docker not reachable yet — give it a few more seconds"
echo
ok "Done. Nothing was deleted; the old config is at ${YAML}.bak-${TS}."
say ""
say "  If the tier detector still picks a small model set, re-run the Golden"
say "  Twin installer inside the VM so it re-profiles the new sizing:"
say "      limactl shell ${VM}"
say "      sudo bash manage.sh install"
