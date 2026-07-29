#!/usr/bin/env bash
# =============================================================================
# nexus-devsecops-appinator-arm.sh — Cloud Underground · Underground Nexus
# The definitive arm64 appinator. Installs the full DEV / SEC / OPS command
# surface into BOTH places an operator might be standing:
#
#     1. the host shell   (the `sovereign` Lima VM on macOS, or a
#                          Raspberry Pi 5 / Jetson AGX / any arm64 Linux)
#     2. inside cerberus-manager
#
# ...so it does not matter which shell you are in. Same 12 commands, same
# behaviour, both places.
#
#   sudo bash nexus-devsecops-appinator-arm.sh              # host + cerberus
#   sudo bash nexus-devsecops-appinator-arm.sh --host-only  # skip cerberus
#   sudo bash nexus-devsecops-appinator-arm.sh --no-deploy  # never pull/build cerberus
#   sudo bash nexus-devsecops-appinator-arm.sh --verify     # report, install nothing
#
# WHY CERBERUS GETS ITS OWN COPY
#   `docker exec -it cerberus-manager bash` does not hold a shell open in the
#   Lima environment, so a command that assumes an interactive session inside
#   the manager will not survive. Every command written here is fully
#   self-contained: it resolves its own image, network, volumes and
#   dependencies at run time and needs nothing from the calling shell.
#
# WHAT THE HUB ACTUALLY HAS (checked, July 2026) — this is why DEV is special:
#   natoascode/underground-nexus:arm64          arm64 IS published  → SEC/OPS pull
#   natoascode/zero-trust-cockpit:creator-vault linux/amd64 ONLY    → DEV BUILDS
#   natoascode/cerberus0:latest                 linux/amd64 ONLY    → see below
#
#   Because cerberus0 has no arm64 tag, deploying it on arm has two routes:
#     (a) build it for arm64 from the cerberus0 branch, whose Dockerfile is
#         already multi-arch (it resolves TARGETARCH → S6_ARCH/ZARF_ARCH), or
#     (b) run the amd64 image under emulation, which works and is slow.
#   This script tries (a) and falls back to (b) with a loud warning.
# =============================================================================
set -uo pipefail

REPO_RAW="https://raw.githubusercontent.com/Underground-Ops/underground-nexus"
REPO_GIT="https://github.com/Underground-Ops/underground-nexus.git"
NEXUS_IMAGE="${NEXUS_IMAGE:-natoascode/underground-nexus:arm64}"
VAULT_IMAGE="${VAULT_IMAGE:-natoascode/zero-trust-cockpit:creator-vault}"
CERB_IMAGE="${CERB_IMAGE:-natoascode/cerberus0:latest}"
CERB_NAME="${CERB_NAME:-cerberus-manager}"
NET="${SOVEREIGN_NET:-sovereign-net}"
TZ_DEFAULT="${TZ:-America/Denver}"
HOST_ONLY=0; NO_DEPLOY=0; VERIFY=0

C_R=$'\033[0m'; C_B=$'\033[1m'; C_Y=$'\033[33m'; C_G=$'\033[32m'; C_E=$'\033[31m'
log()  { printf '[appinator] %s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$C_G" "$C_R" "$*"; }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_R" "$*"; }
err()  { printf '  %s✗%s %s\n' "$C_E" "$C_R" "$*"; }
hr()   { printf '%s\n' "══════════════════════════════════════════════════════════"; }
sec()  { echo; hr; printf '  %s%s%s\n' "$C_B" "$*" "$C_R"; hr; }

while [ $# -gt 0 ]; do
  case "$1" in
    --host-only) HOST_ONLY=1 ;;
    --no-deploy) NO_DEPLOY=1 ;;
    --verify)    VERIFY=1 ;;
    -h|--help)   sed -n '2,45p' "$0"; exit 0 ;;
    *) err "unknown option: $1"; exit 2 ;;
  esac
  shift
done

[ "$(id -u)" = "0" ] || { err "run me as root: sudo bash $0"; exit 1; }

# =============================================================================
sec "PREFLIGHT"
# =============================================================================
ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|arm64) ok "arch: ${ARCH} — correct appinator for this machine" ;;
  x86_64|amd64)
      warn "arch is ${ARCH}, not arm64."
      warn "This appinator pulls :arm64 images and builds the vault for arm64."
      warn "On amd64 use nexus-devsecops-appinator.sh instead."
      printf '  Continue anyway? [y/N] '; IFS= read -r a
      case "$a" in y|Y) ;; *) exit 0 ;; esac ;;
  *)  warn "unrecognised arch '${ARCH}' — proceeding, arm paths assumed" ;;
esac

# where are we? Lima VM, a Pi, a Jetson, or generic arm64 Linux
PLATFORM="arm64 Linux"
if [ -d /Users ] && grep -qi lima /proc/1/environ 2>/dev/null; then PLATFORM="Lima VM (macOS host)"
elif [ -f /etc/hostname ] && grep -qi '^lima-' /etc/hostname 2>/dev/null; then PLATFORM="Lima VM (macOS host)"
elif grep -qi raspberry /proc/device-tree/model 2>/dev/null; then PLATFORM="Raspberry Pi"
elif grep -qi jetson /proc/device-tree/model 2>/dev/null; then PLATFORM="NVIDIA Jetson"
fi
ok "platform: ${PLATFORM}"

command -v docker >/dev/null 2>&1 || { err "docker not found — install Docker first."; exit 1; }
docker info >/dev/null 2>&1 || { err "docker daemon not reachable. Is it running?"; exit 1; }
ok "docker: $(docker --version | sed 's/Docker version //')"

# --- buildx: DEV cannot work without it on arm, so install if missing --------
HAVE_BUILDX=0
if docker buildx version >/dev/null 2>&1; then
  HAVE_BUILDX=1; ok "buildx: $(docker buildx version | awk '{print $2}')"
else
  warn "buildx MISSING. DEV builds the vault image locally on arm because"
  warn "  ${VAULT_IMAGE} is published for amd64 only — without buildx, DEV"
  warn "  falls back to pulling an amd64 image and runs it under emulation."
  if [ "$VERIFY" = 0 ] && [ "$NO_DEPLOY" = 0 ]; then
    log "installing docker-buildx-plugin from Docker's official repo..."
    # Ubuntu's docker.io package does NOT ship buildx — this is the actual
    # root cause behind "DEV pulled amd64 instead of building arm64".
    install -m 0755 -d /etc/apt/keyrings 2>/dev/null || true
    if [ ! -f /etc/apt/keyrings/docker.asc ]; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc 2>/dev/null \
        && chmod a+r /etc/apt/keyrings/docker.asc || true
    fi
    . /etc/os-release 2>/dev/null || true
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu ${VERSION_CODENAME:-noble} stable" \
      > /etc/apt/sources.list.d/docker.list 2>/dev/null || true
    apt-get update -qq >/dev/null 2>&1 || true
    apt-get install -y docker-buildx-plugin >/dev/null 2>&1 || true
    if docker buildx version >/dev/null 2>&1; then
      HAVE_BUILDX=1; ok "buildx installed: $(docker buildx version | awk '{print $2}')"
    else
      warn "buildx install did not take — DEV will use its pull fallback."
    fi
  fi
fi

# --- sovereign-net ----------------------------------------------------------
if docker network inspect "$NET" >/dev/null 2>&1; then
  ok "network ${NET} present"
elif [ "$VERIFY" = 1 ]; then
  warn "network ${NET} absent (would be created)"
else
  if docker network create -d overlay --attachable "$NET" >/dev/null 2>&1; then
    ok "network ${NET} created (overlay, attachable)"
  elif docker network create -d bridge "$NET" >/dev/null 2>&1; then
    ok "network ${NET} created (bridge — no swarm on this host)"
  else
    warn "could not create ${NET}; commands will still run on the default bridge"
  fi
fi

# =============================================================================
sec "COMMAND BODIES"
# =============================================================================
# Written once to a staging dir, then copied to the host AND into cerberus.
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT

# ---------------------------------------------------------------------------
# DEV — FIELD-PROVEN. This body is the operator's working version, byte for
# byte. buildx-first with a docker-pull fallback, because the creator-vault
# tag on the Hub is amd64-only. DO NOT "simplify" this: the builder is torn
# down and recreated deliberately so a stale builder cannot poison the build,
# and every apt/curl step is `|| true` so a mirror hiccup does not abort a
# 40-minute build.
# ---------------------------------------------------------------------------
cat > "${STAGE}/DEV" << 'DEVCMD'
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
DEVCMD

cat > "${STAGE}/DEV-rebuild" << 'DEVCMD'
#!/bin/bash
# Discards the container AND its writable layer AND creator-vault0, then
# rebuilds from scratch. Everything in /config is lost — that is the point.
echo "[DEV-rebuild] tearing down nexus-creator-vault and creator-vault0..."
docker stop nexus-creator-vault 2>/dev/null || true
docker rm   nexus-creator-vault 2>/dev/null || true
docker volume rm creator-vault0 2>/dev/null && echo "  volume removed: creator-vault0" || true
docker image rm natoascode/zero-trust-cockpit:creator-vault 2>/dev/null || true
docker buildx prune -f >/dev/null 2>&1 || true
exec /usr/local/bin/DEV
DEVCMD

cat > "${STAGE}/DEV-restore" << 'DEVCMD'
#!/bin/bash
# Replaces the CONTAINER but keeps creator-vault0, so /config survives.
# Note the writable layer does NOT survive — anything installed inside the
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
DEVCMD

# ---------------------------------------------------------------------------
# SEC / OPS — arm64 wave bodies, carried across unchanged from the tested
# arm64 appinator. SEC-exoskeleton forwards ONLY 1000 and 2000 by design.
# ---------------------------------------------------------------------------
SEC_RUN='docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 22 -p 80:80 -p 8080:8080 -p 443:443 -p 1000:1000 -p 2000:2000 -p 2375:2375 -p 2376:2376 -p 2377:2377 -p 18080:18080 -p 18443:18443 -v /dev:/dev -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket '"${NEXUS_IMAGE}"' && docker exec Underground-Nexus bash deploy-olympiad.sh'
EXO_RUN='docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 1000:1000 -p 2000:2000 -v /dev:/dev -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket '"${NEXUS_IMAGE}"' && docker exec Underground-Nexus bash deploy-olympiad.sh'
OPS_RUN='docker run -itd --name=Underground-Ops -h Underground-Ops --privileged --init -p 1060:1050 -v /dev:/dev -v underground-ops-docker-socket:/var/run '"${NEXUS_IMAGE}"''
# TEARDOWN vs SOFT — semantics carried across from the tested arm64 appinator,
# volume for volume:
#   *-rebuild  wipes the socket volume AND the data/bucket volumes  (total loss)
#   *-restore  wipes ONLY the socket volume, keeps data + bucket     (state kept)
# The socket volume MUST go in both cases: a stale underground-nexus-docker-socket
# left behind by a dead container breaks the new container's inner dockerd, which
# is why the original removed it even on the "gentle" path. Both also re-pull.
#
# One deliberate change from the original: the teardown steps are joined with ';'
# instead of '&&'. The original chained everything with '&&', so when the
# container was NOT already running, `docker container stop` returned non-zero
# and the ENTIRE command aborted before the run step — the command only worked
# on an already-running stack. Semicolons make it idempotent. The run→deploy
# chain still uses '&&' so deploy-olympiad only fires on a successful run.
SEC_TEARDOWN='docker container stop Underground-Nexus 2>/dev/null; docker container rm Underground-Nexus 2>/dev/null; docker volume rm underground-nexus-docker-socket underground-nexus-data nexus-bucket 2>/dev/null; docker pull '"${NEXUS_IMAGE}"';'
OPS_TEARDOWN='docker container stop Underground-Ops 2>/dev/null; docker container rm Underground-Ops 2>/dev/null; docker volume rm underground-ops-docker-socket nexus-bucket 2>/dev/null; docker pull '"${NEXUS_IMAGE}"';'
SEC_SOFT='docker container stop Underground-Nexus 2>/dev/null; docker container rm Underground-Nexus 2>/dev/null; docker volume rm underground-nexus-docker-socket 2>/dev/null; docker pull '"${NEXUS_IMAGE}"';'
OPS_SOFT='docker container stop Underground-Ops 2>/dev/null; docker container rm Underground-Ops 2>/dev/null; docker volume rm underground-ops-docker-socket 2>/dev/null; docker pull '"${NEXUS_IMAGE}"';'

wr() { printf '#!/bin/bash\n%s\n' "$2" > "${STAGE}/$1"; }
wr SEC                       "$SEC_RUN"
wr SEC-exoskeleton           "$EXO_RUN"
wr OPS                       "$OPS_RUN"
wr SEC-rebuild               "${SEC_TEARDOWN} ${SEC_RUN}"
wr SEC-exoskeleton-rebuild   "${SEC_TEARDOWN} ${EXO_RUN}"
wr OPS-rebuild               "${OPS_TEARDOWN} ${OPS_RUN}"
wr SEC-restore               "${SEC_SOFT} ${SEC_RUN}"
wr SEC-exoskeleton-restore   "${SEC_SOFT} ${EXO_RUN}"
wr OPS-restore               "${OPS_SOFT} ${OPS_RUN}"

CMDS="DEV DEV-rebuild DEV-restore SEC SEC-rebuild SEC-restore SEC-exoskeleton SEC-exoskeleton-rebuild SEC-exoskeleton-restore OPS OPS-rebuild OPS-restore"
chmod +x "${STAGE}"/* 2>/dev/null || true
for c in $CMDS; do bash -n "${STAGE}/$c" || { err "generated $c has a syntax error"; exit 6; }; done
ok "12 commands generated and syntax-checked"

# =============================================================================
sec "INSTALL — HOST (${PLATFORM})"
# =============================================================================
if [ "$VERIFY" = 1 ]; then
  for c in $CMDS; do
    if [ -x "/usr/local/bin/$c" ]; then ok "present: /usr/local/bin/$c"
    else warn "absent:  /usr/local/bin/$c"; fi
  done
else
  mkdir -p /usr/local/bin
  for c in $CMDS; do
    [ -f "/usr/local/bin/$c" ] && cp "/usr/local/bin/$c" "/usr/local/bin/${c}.prev" 2>/dev/null || true
    install -m 0755 "${STAGE}/$c" "/usr/local/bin/$c"
  done
  ok "12 commands installed to /usr/local/bin (previous copies kept as *.prev)"
fi

# =============================================================================
sec "CERBERUS MANAGER"
# =============================================================================
cerb_running() { [ -n "$(docker ps -q -f "name=^${CERB_NAME}$" 2>/dev/null)" ]; }
cerb_exists()  { [ -n "$(docker ps -aq -f "name=^${CERB_NAME}$" 2>/dev/null)" ]; }

if [ "$HOST_ONLY" = 1 ]; then
  warn "--host-only: skipping cerberus-manager entirely"
elif cerb_running; then
  ok "${CERB_NAME} already running — reusing it, not touching it"
elif cerb_exists; then
  log "${CERB_NAME} exists but is stopped — starting it"
  docker start "$CERB_NAME" >/dev/null 2>&1 && ok "started" || warn "could not start it"
elif [ "$VERIFY" = 1 ] || [ "$NO_DEPLOY" = 1 ]; then
  warn "${CERB_NAME} absent (would be deployed; --verify/--no-deploy set)"
else
  log "${CERB_NAME} absent — deploying it"
  # arm64 has no cerberus0 tag on the Hub, so try a local multi-arch build
  # from the cerberus0 branch first. Its Dockerfile already resolves
  # TARGETARCH → S6_ARCH/ZARF_ARCH, so an arm64 build is supported upstream.
  BUILT=0
  if [ "$HAVE_BUILDX" = 1 ] && [ "$ARCH" != "x86_64" ]; then
    CB="$(mktemp -d)"
    log "building ${CERB_IMAGE} for arm64 from the cerberus0 branch..."
    if git clone --depth 1 --branch cerberus0 "$REPO_GIT" "${CB}/src" >/dev/null 2>&1 \
       && [ -f "${CB}/src/Dockerfile" ]; then
      docker buildx rm cerberus-arm-builder 2>/dev/null || true
      docker buildx create --name cerberus-arm-builder --driver docker-container --use >/dev/null 2>&1
      docker buildx inspect --bootstrap cerberus-arm-builder >/dev/null 2>&1
      if docker buildx build --builder cerberus-arm-builder --platform linux/arm64 \
           --tag "$CERB_IMAGE" --load --progress plain "${CB}/src"; then
        BUILT=1; ok "cerberus0 built natively for arm64"
      else
        warn "arm64 build failed — falling back to the amd64 image"
      fi
    else
      warn "could not clone the cerberus0 branch — falling back to the amd64 image"
    fi
    rm -rf "$CB"
  fi
  if [ "$BUILT" = 0 ]; then
    warn "${CERB_IMAGE} is published for linux/amd64 ONLY."
    warn "  Pulling it with --platform linux/amd64 means it runs under"
    warn "  EMULATION on this machine: it works, but it is slow. Build it"
    warn "  natively when you can (install buildx, then re-run this script)."
    docker pull --platform linux/amd64 "$CERB_IMAGE" 2>/dev/null || \
      docker pull "$CERB_IMAGE" 2>/dev/null || warn "pull failed"
  fi
  mkdir -p /root/nexus-bucket
  docker run -itd --init --privileged \
    --name="$CERB_NAME" -h "$CERB_NAME" \
    --net=host --restart=always \
    -v /root/nexus-bucket:/nexus-bucket \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "$CERB_IMAGE" sh -c "mkdir -p /root/nexus-bucket && exec bash" >/dev/null 2>&1 \
    && ok "${CERB_NAME} deployed" || err "${CERB_NAME} deploy failed"
  sleep 5
fi

# --- push the same 12 commands INTO cerberus ---------------------------------
if [ "$HOST_ONLY" = 0 ] && [ "$VERIFY" = 0 ] && cerb_running; then
  log "installing the same 12 commands inside ${CERB_NAME}..."
  FAILED=""
  for c in $CMDS; do
    if docker cp "${STAGE}/$c" "${CERB_NAME}:/usr/local/bin/$c" >/dev/null 2>&1 \
       && docker exec "$CERB_NAME" chmod 755 "/usr/local/bin/$c" >/dev/null 2>&1; then :
    else FAILED="$FAILED $c"; fi
  done
  if [ -z "$FAILED" ]; then ok "12 commands installed inside ${CERB_NAME}"
  else warn "could not install inside ${CERB_NAME}:${FAILED}"; fi
elif [ "$HOST_ONLY" = 0 ] && [ "$VERIFY" = 1 ] && cerb_running; then
  for c in $CMDS; do
    if docker exec "$CERB_NAME" test -x "/usr/local/bin/$c" >/dev/null 2>&1; then
      ok "present in ${CERB_NAME}: $c"; else warn "absent in ${CERB_NAME}:  $c"; fi
  done
fi

# =============================================================================
sec "VERIFY"
# =============================================================================
HOST_N=0; CERB_N=0
for c in $CMDS; do [ -x "/usr/local/bin/$c" ] && HOST_N=$((HOST_N+1)); done
if cerb_running; then
  for c in $CMDS; do
    docker exec "$CERB_NAME" test -x "/usr/local/bin/$c" >/dev/null 2>&1 && CERB_N=$((CERB_N+1))
  done
fi
printf "  host (%s): %s/12 commands\n" "$PLATFORM" "$HOST_N"
printf "  %s: %s/12 commands%s\n" "$CERB_NAME" "$CERB_N" \
       "$(cerb_running || echo '   (not running)')"
echo
say_cmds() { printf '      %s\n' "$@"; }
say_cmds "DEV       DEV-rebuild       DEV-restore" \
         "SEC       SEC-rebuild       SEC-restore" \
         "SEC-exoskeleton  SEC-exoskeleton-rebuild  SEC-exoskeleton-restore" \
         "OPS       OPS-rebuild       OPS-restore"
echo
if [ "$HOST_N" = 12 ] && { [ "$CERB_N" = 12 ] || [ "$HOST_ONLY" = 1 ]; }; then
  ok "Appinator complete. Run any command from either shell."
else
  warn "Partial install — see the warnings above."
fi
echo
printf '  %sWhat to run first%s\n' "$C_B" "$C_R"
say_cmds "DEV   → Nexus Creator Vault at http://localhost:1050" \
         "        first run builds the arm64 image, 20-40 min" \
         "SEC   → Underground Nexus chaos test / golden appliance" \
         "OPS   → scaling node at http://localhost:1060"
echo
printf '  %sNotes for this platform%s\n' "$C_B" "$C_R"
say_cmds "· DEV BUILDS rather than pulls: creator-vault is amd64-only on the Hub." \
         "· *-rebuild destroys volumes. *-restore keeps them. DEV-restore keeps" \
         "  /config but not the container's writable layer." \
         "· Every command is self-contained, so 'docker exec cerberus-manager DEV'" \
         "  works even though an interactive shell there does not persist."
