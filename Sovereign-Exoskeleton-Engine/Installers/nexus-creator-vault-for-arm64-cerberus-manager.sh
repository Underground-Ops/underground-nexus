#!/usr/bin/env bash
# =============================================================================
# nexus-creator-vault-arm64.sh — Cloud Underground · Underground Nexus
# Standalone arm64 deployer for the Nexus Creator Vault.
# Replaces nexus-creator-vault-for-arm64-cerberus-manager.sh.
#
# On macOS, run it INSIDE the VM:
#     limactl shell sovereign -- sudo bash nexus-creator-vault-arm64.sh
# On a Raspberry Pi 5 / Jetson AGX / any arm64 Linux, run it directly:
#     sudo bash nexus-creator-vault-arm64.sh
#
#   --keep-config     keep the creator-vault0 volume (default: keep)
#   --wipe-config     DESTROY creator-vault0 — full clean rebuild
#   --no-cerberus     do not check for or deploy cerberus-manager
#   --force-rebuild   rebuild the image even if a local one exists
#   --verify          report state and exit, change nothing
#
# WHY THIS SCRIPT BUILDS INSTEAD OF PULLING
#   natoascode/zero-trust-cockpit:creator-vault is published for linux/amd64
#   ONLY (checked on the Hub, July 2026). On arm there is nothing to pull, so
#   the image is built locally from the v5.8-arm64 Dockerfile. First build is
#   20-40 minutes. After that it is cached and redeploys are seconds.
#
# SINGLE SOURCE OF TRUTH
#   The Dockerfile and the docker-run line below are the SAME ones the DEV
#   command uses in nexus-devsecops-appinator-arm.sh. Change one, change both,
#   or you will end up debugging two vaults that are not the same vault.
# =============================================================================
set -uo pipefail

IMAGE="${VAULT_IMAGE:-natoascode/zero-trust-cockpit:creator-vault}"
CONTAINER="${VAULT_CONTAINER:-nexus-creator-vault}"
BUILD_DIR="${BUILD_DIR:-/tmp/ncv-arm64-build}"
BUILDER="${VAULT_BUILDER:-sovereign-builder}"
NET="${SOVEREIGN_NET:-sovereign-net}"
CERB_NAME="${CERB_NAME:-cerberus-manager}"
CERB_IMAGE="${CERB_IMAGE:-natoascode/cerberus0:latest}"
TZ_SET="${TZ:-America/Denver}"
WIPE=0; NO_CERB=0; FORCE=0; VERIFY=0

C_R=$'\033[0m'; C_B=$'\033[1m'; C_Y=$'\033[33m'; C_G=$'\033[32m'; C_E=$'\033[31m'
ok()   { printf '  %s✓%s %s\n' "$C_G" "$C_R" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_R" "$*"; }
err()  { printf '  %s✗%s %s\n' "$C_E" "$C_R" "$*"; }
say()  { printf '%s\n' "$*"; }
hr()   { printf '%s\n' "══════════════════════════════════════════════════════════"; }
sec()  { echo; hr; printf '  %s%s%s\n' "$C_B" "$*" "$C_R"; hr; }

while [ $# -gt 0 ]; do
  case "$1" in
    --keep-config)   WIPE=0 ;;
    --wipe-config)   WIPE=1 ;;
    --no-cerberus)   NO_CERB=1 ;;
    --force-rebuild) FORCE=1 ;;
    --verify)        VERIFY=1 ;;
    -h|--help)       sed -n '2,32p' "$0"; exit 0 ;;
    *) err "unknown option: $1"; exit 2 ;;
  esac
  shift
done
[ "$(id -u)" = "0" ] || { err "run me as root: sudo bash $0"; exit 1; }

# =============================================================================
sec "STEP 1 — preflight"
# =============================================================================
ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|arm64) ok "arch: ${ARCH}" ;;
  *) warn "arch is ${ARCH}, not arm64 — this script builds for linux/arm64."
     warn "On amd64, plain 'docker pull ${IMAGE}' works and is much faster."
     printf '  Continue? [y/N] '; IFS= read -r a; case "$a" in y|Y) ;; *) exit 0 ;; esac ;;
esac

command -v docker >/dev/null 2>&1 || { err "docker not found"; exit 1; }
docker info >/dev/null 2>&1 || { err "docker daemon not reachable"; exit 1; }
ok "docker: $(docker --version | sed 's/Docker version //')"

# --- buildx. Ubuntu's docker.io package does NOT ship it; that omission is
# --- the original root cause of "DEV pulled amd64 instead of building arm64".
HAVE_BUILDX=0
if docker buildx version >/dev/null 2>&1; then
  HAVE_BUILDX=1; ok "buildx: $(docker buildx version | awk '{print $2}')"
elif [ "$VERIFY" = 1 ]; then
  warn "buildx missing (would be installed)"
else
  say "  buildx missing — installing docker-buildx-plugin from Docker's repo"
  install -m 0755 -d /etc/apt/keyrings 2>/dev/null || true
  [ -f /etc/apt/keyrings/docker.asc ] || {
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      -o /etc/apt/keyrings/docker.asc 2>/dev/null && chmod a+r /etc/apt/keyrings/docker.asc; } || true
  . /etc/os-release 2>/dev/null || true
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu ${VERSION_CODENAME:-noble} stable" \
    > /etc/apt/sources.list.d/docker.list 2>/dev/null || true
  apt-get update -qq >/dev/null 2>&1 || true
  apt-get install -y docker-buildx-plugin >/dev/null 2>&1 || true
  if docker buildx version >/dev/null 2>&1; then
    HAVE_BUILDX=1; ok "buildx installed: $(docker buildx version | awk '{print $2}')"
  else
    err "buildx unavailable. Without it there is NOTHING to pull for arm64 —"
    say "      the creator-vault tag is amd64-only. Install it manually:"
    say "        sudo apt-get install -y docker-buildx-plugin"
    exit 3
  fi
fi

if docker network inspect "$NET" >/dev/null 2>&1; then
  ok "network ${NET} present"
elif [ "$VERIFY" = 1 ]; then warn "network ${NET} absent (would be created)"
else
  docker network create -d overlay --attachable "$NET" >/dev/null 2>&1 && ok "network ${NET} created (overlay)" \
    || { docker network create -d bridge "$NET" >/dev/null 2>&1 && ok "network ${NET} created (bridge)" \
         || warn "could not create ${NET}"; }
fi

AVAIL=$(df -BG / 2>/dev/null | awk 'NR==2{gsub("G","",$4);print $4}')
if [ -n "${AVAIL:-}" ] && [ "$AVAIL" -lt 25 ]; then
  warn "only ${AVAIL} GiB free on / — the build needs roughly 20-25 GiB."
  say "      On macOS grow the VM first:  bash sovereign-lima-resize.sh"
else
  ok "disk space: ${AVAIL:-?} GiB free"
fi

# =============================================================================
sec "STEP 2 — cerberus-manager"
# =============================================================================
if [ "$NO_CERB" = 1 ]; then
  warn "--no-cerberus: skipping"
elif [ -n "$(docker ps -q -f "name=^${CERB_NAME}$" 2>/dev/null)" ]; then
  ok "${CERB_NAME} running — the vault will sit alongside it"
elif [ -n "$(docker ps -aq -f "name=^${CERB_NAME}$" 2>/dev/null)" ]; then
  [ "$VERIFY" = 1 ] && warn "${CERB_NAME} exists but stopped" || {
    docker start "$CERB_NAME" >/dev/null 2>&1 && ok "${CERB_NAME} started" || warn "could not start ${CERB_NAME}"; }
else
  warn "${CERB_NAME} not present."
  say "      The vault does not require it, but DEV/SEC/OPS are meant to be"
  say "      runnable from inside it. Deploy both together with:"
  say "        sudo bash nexus-devsecops-appinator-arm.sh"
  say "      (that script builds cerberus0 for arm64 — its Hub tag is amd64-only)"
fi

# =============================================================================
sec "STEP 3 — current state"
# =============================================================================
HAVE_IMG=0; docker image inspect "$IMAGE" >/dev/null 2>&1 && HAVE_IMG=1
HAVE_CT=0;  [ -n "$(docker ps -aq -f "name=^${CONTAINER}$" 2>/dev/null)" ] && HAVE_CT=1
HAVE_VOL=0; docker volume inspect creator-vault0 >/dev/null 2>&1 && HAVE_VOL=1
printf "  %-26s %s\n" "local image"      "$( [ $HAVE_IMG = 1 ] && docker image inspect "$IMAGE" --format '{{.Id}}' | cut -c8-19 || echo 'absent' )"
printf "  %-26s %s\n" "container"        "$( [ $HAVE_CT  = 1 ] && docker ps -a --format '{{.Status}}' -f "name=^${CONTAINER}$" || echo 'absent' )"
printf "  %-26s %s\n" "creator-vault0"   "$( [ $HAVE_VOL = 1 ] && echo 'present (your /config lives here)' || echo 'absent' )"
printf "  %-26s %s\n" "config on rebuild" "$( [ $WIPE = 1 ] && echo 'WIPED (--wipe-config)' || echo 'KEPT' )"
[ "$VERIFY" = 1 ] && { echo; ok "--verify: nothing changed."; exit 0; }

if [ "$WIPE" = 1 ] && [ "$HAVE_VOL" = 1 ]; then
  echo; warn "--wipe-config will DESTROY creator-vault0. Everything in the"
  warn "  vault's /config — Golden Twin state, corpus, chats — is lost."
  printf '  Type %sWIPE%s to confirm: ' "$C_B" "$C_R"; IFS= read -r c
  [ "$c" = "WIPE" ] || { warn "cancelled."; exit 0; }
fi

# =============================================================================
sec "STEP 4 — build"
# =============================================================================
if [ "$HAVE_IMG" = 1 ] && [ "$FORCE" = 0 ]; then
  ok "local arm64 image already present — skipping the 20-40 minute build"
  say "      (use --force-rebuild to build it again)"
else
  say "  freeing build cache..."
  docker buildx prune -f >/dev/null 2>&1 || true
  docker builder prune -f >/dev/null 2>&1 || true
  ok "cache pruned"

  # Recreate the builder from scratch. A stale builder is the most common
  # cause of a build that fails 30 minutes in for no visible reason.
  docker buildx rm "$BUILDER" 2>/dev/null || true
  docker buildx create --name "$BUILDER" --driver docker-container --use >/dev/null 2>&1
  docker buildx inspect --bootstrap "$BUILDER" >/dev/null 2>&1
  ok "builder ${BUILDER} ready (docker-container driver)"

  rm -rf "${BUILD_DIR}" && mkdir -p "${BUILD_DIR}"
  # ---- IDENTICAL to the DEV command's Dockerfile. Keep them in step. -------
  cat > "${BUILD_DIR}/Dockerfile" << 'DF'
FROM lscr.io/linuxserver/webtop:ubuntu-kde
LABEL maintainer="Cloud Underground"
LABEL version="5.8-arm64"
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq 2>/dev/null || true \
    && apt-get install -y --no-install-recommends wget curl ca-certificates 2>/dev/null || true \
    && curl -fsSL --retry 3 --max-time 120 \
       "https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/nexus0.sh" \
       -o /nexus0.sh \
    || wget -q --tries=3 --timeout=120 \
       "https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/nexus0.sh" \
       -O /nexus0.sh \
    && test -s /nexus0.sh && chmod +x /nexus0.sh
RUN bash /nexus0.sh || true
RUN rm -f /usr/share/wallpapers/KubuntuLight/contents/images/*.svg \
          /usr/share/wallpapers/KubuntuLight/contents/images/*.png \
          /usr/share/wallpapers/Next/contents/images/*.svg \
          /usr/share/wallpapers/Next/contents/images/*.png \
          /usr/share/wallpapers/Next/contents/images_dark/*.svg \
          /usr/share/wallpapers/Next/contents/images_dark/*.png 2>/dev/null || true
RUN rm -f /etc/s6-overlay/s6-rc.d/user/contents.d/svc-docker 2>/dev/null || true \
    && if [ -f /etc/s6-overlay/s6-rc.d/svc-docker/run ]; then \
        printf '#!/bin/sh\nexec sleep infinity\n' > /etc/s6-overlay/s6-rc.d/svc-docker/run \
        && chmod +x /etc/s6-overlay/s6-rc.d/svc-docker/run; fi \
    && if [ -f /usr/bin/dockerd ]; then \
        mv /usr/bin/dockerd /usr/bin/dockerd.disabled \
        && printf '#!/bin/sh\necho "dockerd masked"\nexit 0\n' > /usr/bin/dockerd \
        && chmod +x /usr/bin/dockerd; fi
RUN mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/libvirtd \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/virtlogd \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/ollama
RUN apt-get clean && rm -rf /var/lib/apt/lists/* \
    && find /etc/s6-overlay -type f -exec chmod +x {} \; 2>/dev/null || true \
    && find /custom-cont-init.d -type f -exec chmod +x {} \; 2>/dev/null || true
DF
  ok "Dockerfile staged (v5.8-arm64)"
  say ""
  say "  Building linux/arm64. First run is 20-40 minutes — the KDE base and"
  say "  nexus0.sh are the slow parts. Progress is printed in full so you can"
  say "  see exactly where it is."
  say ""
  if ! docker buildx build \
        --builder "$BUILDER" \
        --platform linux/arm64 \
        --tag "$IMAGE" \
        --load \
        --progress plain \
        "$BUILD_DIR"; then
    err "build failed. The existing container (if any) was NOT touched."
    say "      Common causes: out of disk (see STEP 1), a transient mirror"
    say "      failure (just re-run), or a stale builder (this script already"
    say "      recreates it, so re-running is the fix)."
    exit 4
  fi
  ok "image built: $(docker image inspect "$IMAGE" --format '{{.Id}}' | cut -c8-19)"
fi

# =============================================================================
sec "STEP 5 — deploy"
# =============================================================================
docker stop "$CONTAINER" 2>/dev/null && ok "stopped old container" || true
docker rm   "$CONTAINER" 2>/dev/null && ok "removed old container" || true
if [ "$WIPE" = 1 ]; then
  docker volume rm creator-vault0 2>/dev/null && ok "volume removed: creator-vault0" \
    || warn "creator-vault0 not removed (in use or absent)"
fi

# ---- IDENTICAL to the DEV command's run line. Keep them in step. -----------
if docker run -itd \
    --name="$CONTAINER" -h "$CONTAINER" \
    --privileged --net="$NET" \
    -p 1050:3000 \
    -e PUID=1050 -e PGID=1050 -e TZ="$TZ_SET" \
    --restart unless-stopped \
    -v /dev:/dev -v creator-vault0:/config \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "$IMAGE" >/dev/null; then
  ok "${CONTAINER} deployed → http://localhost:1050"
else
  err "deploy failed. The image is built, so just re-run this script."
  exit 5
fi

# =============================================================================
sec "STEP 6 — install the DEV family"
# =============================================================================
# PATTERN, stated plainly so the two scripts never fight:
#   nexus-devsecops-appinator-arm.sh  is the AUTHORITY. It OVERWRITES all 12
#       commands every run (keeping *.prev copies) because it is the single
#       place that defines the command surface.
#   this script is DEFERENTIAL. It installs ONLY what is missing and never
#       overwrites anything. If the appinator has run, this is a no-op.
#
# It installs the whole DEV family rather than just DEV-restore. An earlier
# draft installed DEV-restore alone, whose failure path told the operator to
# "run DEV" — a command this script had not installed. On a fresh box that was
# a dead end. Either install the thing you point at, or do not point at it.
DEV_FAMILY_ADDED=""
if [ -x /usr/local/bin/DEV ]; then
  ok "DEV already present — appinator is the authority, leaving all of it alone"
else
  cat > /usr/local/bin/DEV << 'DEVEOF'
#!/bin/bash
IMAGE="natoascode/zero-trust-cockpit:creator-vault"
CONTAINER="nexus-creator-vault"
BUILD_DIR="/tmp/ncv-arm64-build"
echo "[DEV] Building arm64 NCV image locally..."
if docker buildx version >/dev/null 2>&1; then
  docker buildx rm sovereign-builder 2>/dev/null || true
  docker buildx create --name sovereign-builder --driver docker-container --use 2>/dev/null
  docker buildx inspect --bootstrap sovereign-builder 2>/dev/null
  rm -rf "${BUILD_DIR}" && mkdir -p "${BUILD_DIR}"
  cat > "${BUILD_DIR}/Dockerfile" << 'DF'
FROM lscr.io/linuxserver/webtop:ubuntu-kde
LABEL maintainer="Cloud Underground"
LABEL version="5.8-arm64"
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq 2>/dev/null || true \
    && apt-get install -y --no-install-recommends wget curl ca-certificates 2>/dev/null || true \
    && curl -fsSL --retry 3 --max-time 120 \
       "https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/nexus0.sh" \
       -o /nexus0.sh \
    || wget -q --tries=3 --timeout=120 \
       "https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/nexus0.sh" \
       -O /nexus0.sh \
    && test -s /nexus0.sh && chmod +x /nexus0.sh
RUN bash /nexus0.sh || true
RUN rm -f /usr/share/wallpapers/KubuntuLight/contents/images/*.svg \
          /usr/share/wallpapers/KubuntuLight/contents/images/*.png \
          /usr/share/wallpapers/Next/contents/images/*.svg \
          /usr/share/wallpapers/Next/contents/images/*.png \
          /usr/share/wallpapers/Next/contents/images_dark/*.svg \
          /usr/share/wallpapers/Next/contents/images_dark/*.png 2>/dev/null || true
RUN rm -f /etc/s6-overlay/s6-rc.d/user/contents.d/svc-docker 2>/dev/null || true \
    && if [ -f /etc/s6-overlay/s6-rc.d/svc-docker/run ]; then \
        printf '#!/bin/sh\nexec sleep infinity\n' > /etc/s6-overlay/s6-rc.d/svc-docker/run \
        && chmod +x /etc/s6-overlay/s6-rc.d/svc-docker/run; fi \
    && if [ -f /usr/bin/dockerd ]; then \
        mv /usr/bin/dockerd /usr/bin/dockerd.disabled \
        && printf '#!/bin/sh\necho "dockerd masked"\nexit 0\n' > /usr/bin/dockerd \
        && chmod +x /usr/bin/dockerd; fi
RUN mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/libvirtd \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/virtlogd \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/ollama
RUN apt-get clean && rm -rf /var/lib/apt/lists/* \
    && find /etc/s6-overlay -type f -exec chmod +x {} \; 2>/dev/null || true \
    && find /custom-cont-init.d -type f -exec chmod +x {} \; 2>/dev/null || true
DF
  echo "[DEV] Building arm64 image (20-40 min first run)..."
  docker buildx build \
    --builder sovereign-builder \
    --platform linux/arm64 \
    --tag "${IMAGE}" \
    --load \
    --progress plain \
    "${BUILD_DIR}"
else
  echo "[DEV] buildx not available — falling back to docker pull..."
  docker pull "${IMAGE}"
fi
docker network inspect sovereign-net >/dev/null 2>&1 || \
  docker network create -d overlay --attachable sovereign-net 2>/dev/null || \
  docker network create -d bridge sovereign-net 2>/dev/null || true
docker stop "${CONTAINER}" 2>/dev/null || true
docker rm "${CONTAINER}" 2>/dev/null || true
docker run -itd \
  --name=nexus-creator-vault -h nexus-creator-vault \
  --privileged --net=sovereign-net \
  -p 1050:3000 \
  -e PUID=1050 -e PGID=1050 -e TZ=America/Denver \
  --restart unless-stopped \
  -v /dev:/dev -v creator-vault0:/config \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "${IMAGE}"
echo "[DEV] nexus-creator-vault deployed → http://localhost:1050"
DEVEOF
  chmod 755 /usr/local/bin/DEV
  DEV_FAMILY_ADDED="DEV"
  ok "DEV installed (builds arm64, then deploys)"
fi

if [ ! -x /usr/local/bin/DEV-rebuild ]; then
  cat > /usr/local/bin/DEV-rebuild << 'RBEOF'
#!/bin/bash
# Destroys the container, its writable layer AND creator-vault0, then rebuilds.
echo "[DEV-rebuild] tearing down nexus-creator-vault and creator-vault0..."
docker stop nexus-creator-vault 2>/dev/null || true
docker rm   nexus-creator-vault 2>/dev/null || true
docker volume rm creator-vault0 2>/dev/null && echo "  volume removed: creator-vault0" || true
docker image rm natoascode/zero-trust-cockpit:creator-vault 2>/dev/null || true
docker buildx prune -f >/dev/null 2>&1 || true
exec /usr/local/bin/DEV
RBEOF
  chmod 755 /usr/local/bin/DEV-rebuild
  DEV_FAMILY_ADDED="${DEV_FAMILY_ADDED} DEV-rebuild"
  ok "DEV-rebuild installed (destroys /config, full rebuild)"
fi

if [ ! -x /usr/local/bin/DEV-restore ]; then
  cat > /usr/local/bin/DEV-restore << 'RSEOF'
#!/bin/bash
# Replaces the CONTAINER, keeps creator-vault0 so /config survives. The
# container's writable layer does NOT survive — anything installed inside the
# container but outside /config is discarded.
IMAGE="natoascode/zero-trust-cockpit:creator-vault"
echo "[DEV-restore] replacing the container, keeping creator-vault0..."
docker stop nexus-creator-vault 2>/dev/null || true
docker rm   nexus-creator-vault 2>/dev/null || true
docker image inspect "${IMAGE}" >/dev/null 2>&1 || { \
  echo "[DEV-restore] no local image — handing off to DEV to build it"; \
  exec /usr/local/bin/DEV; }
docker network inspect sovereign-net >/dev/null 2>&1 || \
  docker network create -d bridge sovereign-net 2>/dev/null || true
docker run -itd \
  --name=nexus-creator-vault -h nexus-creator-vault \
  --privileged --net=sovereign-net \
  -p 1050:3000 \
  -e PUID=1050 -e PGID=1050 -e TZ=America/Denver \
  --restart unless-stopped \
  -v /dev:/dev -v creator-vault0:/config \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "${IMAGE}"
echo "[DEV-restore] nexus-creator-vault restored → http://localhost:1050"
RSEOF
  chmod 755 /usr/local/bin/DEV-restore
  DEV_FAMILY_ADDED="${DEV_FAMILY_ADDED} DEV-restore"
  ok "DEV-restore installed (fast redeploy, keeps /config)"
fi

[ -n "$DEV_FAMILY_ADDED" ] && ok "added:${DEV_FAMILY_ADDED}" || true
warn "SEC / OPS / SEC-exoskeleton are NOT installed by this script."
say  "      For the full 12-command surface, and copies inside"
say  "      cerberus-manager:  sudo bash nexus-devsecops-appinator-arm.sh"

# =============================================================================
sec "RESULT"
# =============================================================================
docker ps --format '  {{.Names}}  {{.Status}}  {{.Ports}}' -f "name=^${CONTAINER}$"
echo
ok "Open the vault:  http://localhost:1050"
say "     On macOS that is reachable from the Mac browser directly — Lima"
say "     forwards it. If not, check:  limactl list"
echo
say "  Next steps inside the vault:"
say "     · Golden Twin:  sudo bash manage.sh install"
say "     · Full command surface:  sudo bash nexus-devsecops-appinator-arm.sh"
say "     · Grow the VM first if disk is tight:  bash sovereign-lima-resize.sh"
