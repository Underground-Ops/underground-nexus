#!/usr/bin/env bash
# =============================================================================
# nexus-gpu-setup.sh v2.0 — multi-vendor GPU enablement for the Nexus ecosystem
#
# Run ON THE HOST (native Linux, or inside WSL after typing `wsl` on Windows).
# Root or sudo. Safe to re-run; every step is guarded and non-fatal where the
# environment simply lacks the hardware.
#
# WHAT CHANGED IN v2.0
#   * DEV-rebuild-gpu now matches the real DEV-rebuild contract: stop -> rm
#     container -> REMOVE THE VOLUME(S) -> pull -> relaunch. v1 only pulled and
#     re-ran, so nothing was ever actually cleared.
#   * DEV-restore-gpu ADDED: stop -> rm container -> pull -> relaunch, volume
#     PRESERVED. This is the non-destructive twin, same as DEV-restore.
#   * All three commands are now EMBEDDED in this file. No more "keep all three
#     files in one folder." A sibling DEV-gpu still wins if you have one you
#     like — v1's DEV-gpu works, so it is preserved when present.
#   * Vendor coverage widened well past NVIDIA. Ollama now ships a Vulkan
#     backend enabled by default, so AMD and Intel GPUs (including iGPUs) are
#     real acceleration targets, not CPU-fallback consolation prizes.
#   * Container matching now also catches compose-prefixed names
#     (cerberus_cerberus-manager) as well as cerberus-manager / Cerberus-Manager.
#   * Host install: the three commands are also placed in /usr/local/bin so
#     bare-metal Forge OS hosts get them without a Cerberus container.
#
# THE ACCELERATION TRUTH TABLE (researched, current as of this build)
#
#   NVIDIA, native Linux or WSL2 ....... CUDA via nvidia-container-toolkit.
#                                        `--gpus all`. Best path by a wide
#                                        margin. Covers eGPUs. Needs compute
#                                        capability 5.0+ and driver 550+.
#                                        In WSL the driver is the WINDOWS one —
#                                        never install a Linux NVIDIA driver
#                                        inside WSL, it breaks passthrough.
#
#   AMD, native Linux ................. ROCm via /dev/kfd + /dev/dri. Ollama
#                                        wants the ROCm v7 driver stack. Cards
#                                        outside the supported LLVM targets can
#                                        often be forced with
#                                        HSA_OVERRIDE_GFX_VERSION (e.g. an
#                                        RX 5400 is gfx1034, run it as 10.3.0).
#                                        Anything ROCm refuses still gets the
#                                        Vulkan path below.
#
#   Intel / AMD iGPU / anything with a . Vulkan via /dev/dri alone. No /dev/kfd
#   render node, native Linux           needed — omitting it is harmless and
#                                        correct. This is the path that makes
#                                        Iris Xe, Radeon 680M/Vega, Arc, and
#                                        similar actually accelerate. Modest
#                                        next to CUDA, clearly better than CPU.
#
#   Non-NVIDIA under WSL2 ............. /dev/dxg + Mesa's Dozen driver
#                                        (Vulkan-on-D3D12). This DOES work now —
#                                        Ollama detects e.g. "Microsoft
#                                        Direct3D12 (Intel Arc 140T) (Dozen)"
#                                        and offloads layers. It is also still
#                                        flaky (upstream has open /dev/dxg sync
#                                        hangs), and enabling it means putting
#                                        /usr/lib/wsl/lib on the container's
#                                        library path, which can disturb a
#                                        desktop image. So it is OPT-IN:
#                                        NEXUS_WSL_DXG=1. ROCm still cannot work
#                                        under WSL2 — there is no /dev/kfd.
#
#   Apple Silicon ...................... Metal is not reachable from a Linux
#                                        container. On macOS/Lima the vault is
#                                        CPU-only by design; Metal needs a
#                                        native macOS Ollama.
#
#   NPUs ............................... Not used by Ollama. WSL3's NPU
#                                        passthrough (Build 2026, DirectML 2.0)
#                                        does not change that yet.
#
# FLAGS / ENV:
#   --dry-run                    detect + report only; change nothing
#   --verify                     re-run the container GPU proof and exit
#   --help
#   NEXUS_GPU_VENDOR=nvidia|amd|intel|dxg|cpu   force the verdict
#   NEXUS_GPU_VULKAN=1           keep Vulkan on even when CUDA is present
#   NEXUS_WSL_DXG=1              opt in to the WSL Dozen/Vulkan path
#   HSA_OVERRIDE_GFX_VERSION=x.y.z   passed through to the container for AMD
#   DEV_IMAGE=...                override the vault image
#   NEXUS_DEV_ROOT=/some/path    (tests) probe device nodes under a fake root
#   NEXUS_DOCKER="..."           (tests) substitute the docker command
# =============================================================================
set -uo pipefail

VERSION="2.0.0"
DRY=0; VERIFY_ONLY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --verify)  VERIFY_ONLY=1 ;;
    --help|-h) sed -n '2,80p' "$0"; exit 0 ;;
  esac
done

DEVROOT="${NEXUS_DEV_ROOT:-}"
IMAGE="${DEV_IMAGE:-natoascode/zero-trust-cockpit:creator-vault}"
VAULT_NAME="${DEV_NAME:-nexus-creator-vault}"
VAULT_VOLUMES="${DEV_VOLUMES:-creator-vault0}"
VAULT_PORT="${DEV_PORT:-1050}"

log()  { echo "[gpu-setup] $*"; }
warn() { echo "[gpu-setup] WARN: $*"; }
err()  { echo "[gpu-setup] ERROR: $*"; }

# --- sudo shim: use sudo only if not root and sudo exists --------------------
SUDO=""
if [ "$(id -u)" != "0" ]; then
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"
  else err "not root and no sudo available — rerun as root"; exit 1; fi
fi
DOCKER="${NEXUS_DOCKER:-$SUDO docker}"

log "nexus-gpu-setup v${VERSION}"

# =============================================================================
# STEP 1 — environment
# =============================================================================
IS_WSL=0
if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; then
  IS_WSL=1
fi
log "environment: $([ "$IS_WSL" = 1 ] && echo 'WSL2 (Windows host)' || echo 'native Linux')"

if ! command -v docker >/dev/null 2>&1 && [ -z "${NEXUS_DOCKER:-}" ]; then
  err "docker not found on this host — install docker first, then rerun."
  exit 1
fi

restart_docker() {
  # Docker Desktop's daemon lives on the Windows side — we cannot restart it
  # from here; detect and instruct instead of failing.
  if docker context show 2>/dev/null | grep -qi 'desktop'; then
    warn "Docker Desktop detected — restart it from the Windows tray (Quit + reopen), then rerun this script."
    return 1
  fi
  if command -v systemctl >/dev/null 2>&1 && $SUDO systemctl restart docker 2>/dev/null; then
    log "docker restarted via systemctl"; return 0
  fi
  if $SUDO service docker restart 2>/dev/null; then
    log "docker restarted via service"; return 0
  fi
  warn "could not restart docker automatically — restart it manually, then rerun."
  return 1
}

# =============================================================================
# STEP 2 — GPU detection (multi-vendor, inventory first, then a verdict)
# =============================================================================
has_dev() { [ -e "${DEVROOT}$1" ]; }
gid_of()  { getent group "$1" 2>/dev/null | cut -d: -f3; }

VENDOR="none"; GPU_ARGS=""; NOTES=""; SECONDARY=""

HAS_NVIDIA=0; HAS_KFD=0; HAS_DRI=0; HAS_DXG=0
command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1 && HAS_NVIDIA=1
has_dev /dev/kfd && HAS_KFD=1
has_dev /dev/dri && HAS_DRI=1
has_dev /dev/dxg && HAS_DXG=1

INVENTORY=""
[ "$HAS_NVIDIA" = 1 ] && INVENTORY="${INVENTORY} nvidia-smi"
[ "$HAS_KFD"    = 1 ] && INVENTORY="${INVENTORY} /dev/kfd"
[ "$HAS_DRI"    = 1 ] && INVENTORY="${INVENTORY} /dev/dri"
[ "$HAS_DXG"    = 1 ] && INVENTORY="${INVENTORY} /dev/dxg"
log "device inventory:${INVENTORY:- none}"

# render/video GIDs must be numeric — a container image that has no "render"
# group would make `--group-add render` fail the whole launch.
GID_RENDER="$(gid_of render)"; GID_VIDEO="$(gid_of video)"
GROUP_ARGS=""
[ -n "$GID_RENDER" ] && GROUP_ARGS="${GROUP_ARGS} --group-add ${GID_RENDER}"
[ -n "$GID_VIDEO"  ] && GROUP_ARGS="${GROUP_ARGS} --group-add ${GID_VIDEO}"

dri_devices() {
  # pass the render node(s) explicitly; harmless under --privileged, required
  # if anyone ever drops it
  local out=""
  for d in "${DEVROOT}"/dev/dri/renderD* "${DEVROOT}"/dev/dri/card*; do
    [ -e "$d" ] || continue
    out="${out} --device ${d#$DEVROOT}:${d#$DEVROOT}"
  done
  [ -z "$out" ] && out=" --device /dev/dri:/dev/dri"
  echo "$out"
}

decide() {
  # ---- forced verdict -----------------------------------------------------
  case "${NEXUS_GPU_VENDOR:-auto}" in
    nvidia|amd|intel|dxg|cpu) VENDOR="${NEXUS_GPU_VENDOR}"
      log "verdict FORCED by NEXUS_GPU_VENDOR=${VENDOR}" ;;
    *) VENDOR="" ;;
  esac

  if [ -z "$VENDOR" ]; then
    if [ "$HAS_NVIDIA" = 1 ]; then VENDOR="nvidia"
    elif [ "$HAS_KFD" = 1 ] && [ "$IS_WSL" = 0 ]; then VENDOR="amd"
    elif [ "$HAS_DRI" = 1 ] && [ "$IS_WSL" = 0 ]; then VENDOR="intel"
    elif [ "$HAS_DXG" = 1 ] && [ "${NEXUS_WSL_DXG:-0}" = 1 ]; then VENDOR="dxg"
    else VENDOR="cpu"; fi
  fi

  case "$VENDOR" in
    nvidia)
      GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
      GPU_ARGS="--gpus all"
      # CUDA is authoritative. Leaving Vulkan on invites the scheduler to pick a
      # flaky iGPU next to a perfectly good CUDA card. Override if you want both.
      if [ "${NEXUS_GPU_VULKAN:-0}" = 1 ]; then
        GPU_ARGS="${GPU_ARGS} -e OLLAMA_VULKAN=1"
        [ "$HAS_DRI" = 1 ] && GPU_ARGS="${GPU_ARGS}$(dri_devices)${GROUP_ARGS}"
        SECONDARY="Vulkan kept ON alongside CUDA (NEXUS_GPU_VULKAN=1) — set GGML_VK_VISIBLE_DEVICES if the wrong device gets picked"
      else
        GPU_ARGS="${GPU_ARGS} -e OLLAMA_VULKAN=0"
        [ "$HAS_DRI" = 1 ] && SECONDARY="a render node is also present; Vulkan left OFF so CUDA stays authoritative (NEXUS_GPU_VULKAN=1 to change)"
      fi
      NOTES="NVIDIA '${GPU_NAME:-unknown}' — CUDA path (native + WSL2, covers eGPUs)"
      ;;
    amd)
      GPU_ARGS="--device /dev/kfd:/dev/kfd$(dri_devices)${GROUP_ARGS} -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1"
      [ -n "${HSA_OVERRIDE_GFX_VERSION:-}" ] && \
        GPU_ARGS="${GPU_ARGS} -e HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION}"
      NOTES="AMD ROCm compute node present — ROCm first, Vulkan left enabled as the fallback for cards ROCm does not target"
      SECONDARY="if Ollama reports no ROCm device, find your gfx target and re-run with HSA_OVERRIDE_GFX_VERSION=10.3.0 (or the nearest supported target)"
      ;;
    intel)
      GPU_ARGS="$(dri_devices)${GROUP_ARGS} -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1"
      NOTES="Render node present (Intel/AMD iGPU or dGPU without ROCm) — Ollama's Vulkan backend uses it. Real acceleration, modest next to CUDA."
      SECONDARY="NPUs are NOT used by Ollama; the render node is the accelerator here"
      ;;
    dxg)
      GPU_ARGS="-v /usr/lib/wsl:/usr/lib/wsl:ro -e LD_LIBRARY_PATH=/usr/lib/wsl/lib -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1"
      [ "$HAS_DXG" = 1 ] && GPU_ARGS="--device /dev/dxg:/dev/dxg ${GPU_ARGS}"
      [ "$HAS_DRI" = 1 ] && GPU_ARGS="${GPU_ARGS}$(dri_devices)${GROUP_ARGS}"
      NOTES="WSL2 /dev/dxg + Mesa Dozen (Vulkan on D3D12) — EXPERIMENTAL, opted in via NEXUS_WSL_DXG=1"
      SECONDARY="upstream has open /dev/dxg sync hangs; if generation stalls after model load, unset NEXUS_WSL_DXG and rerun for CPU mode"
      ;;
    cpu)
      GPU_ARGS=""
      if [ "$IS_WSL" = 1 ] && [ "$HAS_KFD" = 1 ]; then
        NOTES="WSL2 with an AMD compute node visible. ROCm still cannot work under WSL2 — the /dev/kfd you see is not a usable ROCm path. Boot native Linux (Forge OS) for ROCm, or rerun with NEXUS_WSL_DXG=1 to try the Dozen/Vulkan route."
      elif [ "$IS_WSL" = 1 ] && { [ "$HAS_DXG" = 1 ] || [ "$HAS_DRI" = 1 ]; }; then
        NOTES="WSL2 with no NVIDIA. Your GPU is reachable only through the D3D12 route (Dozen/Vulkan) — rerun with NEXUS_WSL_DXG=1 to try it. ROCm cannot work under WSL2."
      elif [ "$IS_WSL" = 1 ]; then
        NOTES="WSL2, no GPU nodes visible. If this machine HAS an NVIDIA GPU/eGPU: update the WINDOWS NVIDIA driver, reconnect the eGPU BEFORE starting WSL, then rerun."
      else
        NOTES="No GPU nodes found — CPU mode (small models remain viable)."
      fi
      ;;
  esac
}
decide

# a forced verdict can name devices this host does not have; docker run would
# fail outright, so say so here rather than at launch time
case "$VENDOR" in
  amd)   [ "$HAS_KFD" = 1 ] || warn "forced/assumed AMD but /dev/kfd is absent — docker run will reject the --device flag" ;;
  intel) [ "$HAS_DRI" = 1 ] || warn "forced/assumed Intel but /dev/dri is absent — docker run will reject the --device flag" ;;
  dxg)   [ "$HAS_DXG" = 1 ] || warn "forced/assumed dxg but /dev/dxg is absent — docker run will reject the --device flag" ;;
esac

log "GPU verdict: vendor=${VENDOR}  args='${GPU_ARGS:-none}'"
log "  ${NOTES}"
[ -n "$SECONDARY" ] && log "  note: ${SECONDARY}"

# =============================================================================
# STEP 3 — NVIDIA container toolkit (install, register, restart, verify, repair)
# =============================================================================
toolkit_registered() { $DOCKER info 2>/dev/null | grep -qi 'runtimes:.*nvidia'; }

verify_gpu_container() {
  # entrypoint override = run ONLY the probe, skip the whole s6 boot
  case "$VENDOR" in
    nvidia) $DOCKER run --rm --gpus all --entrypoint nvidia-smi "$IMAGE" \
              --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 ;;
    amd|intel|dxg)
      # shellcheck disable=SC2086
      $DOCKER run --rm $GPU_ARGS --entrypoint sh "$IMAGE" -c \
        'ls /dev/dri 2>/dev/null | tr "\n" " "; [ -e /dev/kfd ] && printf "kfd "; [ -e /dev/dxg ] && printf "dxg "' 2>/dev/null | head -1 ;;
    *) echo "" ;;
  esac
}

nvidia_enable() {
  if ! command -v nvidia-ctk >/dev/null 2>&1; then
    log "installing NVIDIA Container Toolkit..."
    if command -v apt-get >/dev/null 2>&1; then
      curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
        && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
        | $SUDO tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null \
        && $SUDO apt-get update -qq \
        && { $SUDO apt-get install -y nvidia-container-toolkit \
             || { warn "install failed — one retry with --fix-missing"; \
                  $SUDO apt-get install -y --fix-missing nvidia-container-toolkit; }; }
    elif command -v dnf >/dev/null 2>&1; then
      $SUDO dnf install -y nvidia-container-toolkit || warn "dnf install failed — install nvidia-container-toolkit manually."
    elif command -v zypper >/dev/null 2>&1; then
      $SUDO zypper --non-interactive install nvidia-container-toolkit || warn "zypper install failed — install nvidia-container-toolkit manually."
    else
      warn "unrecognised package manager — install nvidia-container-toolkit yourself, then rerun."
    fi
  fi
  if command -v nvidia-ctk >/dev/null 2>&1 && ! toolkit_registered; then
    log "registering nvidia runtime with docker..."
    $SUDO nvidia-ctk runtime configure --runtime=docker >/dev/null 2>&1 || warn "nvidia-ctk configure reported an issue"
    restart_docker || true
  fi
  if toolkit_registered; then
    log "docker nvidia runtime: registered"
    RES="$(verify_gpu_container || true)"
    if [ -n "$RES" ]; then
      log "VERIFIED — container sees GPU: ${RES}"
    else
      warn "verification failed — one repair attempt (re-register + restart)..."
      $SUDO nvidia-ctk runtime configure --runtime=docker >/dev/null 2>&1 || true
      restart_docker || true
      RES="$(verify_gpu_container || true)"
      if [ -n "$RES" ]; then log "VERIFIED after repair — ${RES}"
      else warn "still unverified — DEV-gpu will attach --gpus all anyway; check 'docker info' for the nvidia runtime."; fi
    fi
  else
    warn "nvidia runtime not registered — docker restart may be pending (Docker Desktop needs a tray restart)."
  fi
}

amd_intel_checks() {
  # These paths need no toolkit — the devices are the interface. What they DO
  # need is a Vulkan/ROCm userspace inside the image, which the vault already
  # ships (Mesa VA-API/Vulkan + the /dev/kfd handling in 02-gpu-detect).
  [ -z "$GID_RENDER" ] && warn "no 'render' group on this host — GPU nodes may be root-only; check 'ls -l /dev/dri'"
  if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
    warn "SELinux is enforcing — containers may be blocked from GPU devices."
    warn "  fix: sudo setsebool -P container_use_devices=1"
  fi
  if [ "$VENDOR" = "amd" ] && ! command -v rocminfo >/dev/null 2>&1; then
    log "  (rocminfo not installed on the host — not required; Ollama carries its own ROCm libs. Install it only if you want to read gfx targets.)"
  fi
  RES="$(verify_gpu_container || true)"
  if [ -n "$RES" ]; then log "VERIFIED — container sees devices: ${RES}"
  else warn "device probe returned nothing — DEV-gpu will still attach the devices; check 'ls -l /dev/dri' on the host."; fi
}

if [ "$DRY" = 0 ]; then
  case "$VENDOR" in
    nvidia)        nvidia_enable ;;
    amd|intel|dxg) amd_intel_checks ;;
    *)             log "no accelerator to enable — skipping vendor setup" ;;
  esac
fi

if [ "$VERIFY_ONLY" = 1 ]; then
  log "verify-only run complete."; exit 0
fi

# =============================================================================
# STEP 4 — write the host GPU profile
# =============================================================================
PROFILE_DIR="/etc/nexus"; PROFILE="${PROFILE_DIR}/gpu.env"
profile_body() {
  echo "# written by nexus-gpu-setup.sh v${VERSION} $(date -u +%FT%TZ)"
  echo "NEXUS_GPU_VENDOR=${VENDOR}"
  echo "NEXUS_GPU_DOCKER_ARGS=\"${GPU_ARGS}\""
  echo "NEXUS_GPU_WSL=${IS_WSL}"
  # the profile is SOURCED by DEV-gpu, so no command substitution may survive
  echo "NEXUS_GPU_NOTES=\"${NOTES//[\`\$]/}\""
}
if [ "$DRY" = 0 ]; then
  if ! $SUDO mkdir -p "$PROFILE_DIR" 2>/dev/null; then
    PROFILE_DIR="${HOME}/.nexus"; PROFILE="${PROFILE_DIR}/gpu.env"; mkdir -p "$PROFILE_DIR"
  fi
  profile_body | $SUDO tee "$PROFILE" >/dev/null
  log "profile written: ${PROFILE}"
else
  log "(dry-run) would write ${PROFILE}: vendor=${VENDOR} args='${GPU_ARGS}'"
fi

# =============================================================================
# STEP 5 — materialize DEV-gpu / DEV-rebuild-gpu / DEV-restore-gpu
#
# CONTRACT (mirrors the appinator's DEV family exactly):
#   DEV-gpu          run the vault with the detected accelerator attached
#   DEV-rebuild-gpu  stop -> rm container -> RM VOLUME(S) -> pull -> DEV-gpu
#   DEV-restore-gpu  stop -> rm container -> pull -> DEV-gpu   (volume kept)
# =============================================================================
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT

write_dev_gpu() {
cat > "${STAGE}/DEV-gpu" <<'DEVGPU'
#!/usr/bin/env bash
# DEV-gpu — launch the Nexus Creator Vault with whatever accelerator this host has.
# Profile order: /usr/local/etc/nexus-gpu.env -> /etc/nexus/gpu.env -> ~/.nexus/gpu.env
# Override anything: DEV_GPU=nvidia|amd|intel|dxg|cpu  DEV_IMAGE=...  DEV_KEEP=1
set -uo pipefail
NAME="${DEV_NAME:-nexus-creator-vault}"
IMAGE="${DEV_IMAGE:-natoascode/zero-trust-cockpit:creator-vault}"
VOLUME="${DEV_VOLUME:-creator-vault0}"
PORT="${DEV_PORT:-1050}"
TZ_="${DEV_TZ:-America/Colorado}"
log() { echo "[DEV-gpu] $*"; }

GPU_ARGS=""
for p in /usr/local/etc/nexus-gpu.env /etc/nexus/gpu.env "${HOME}/.nexus/gpu.env"; do
  if [ -r "$p" ]; then . "$p"; GPU_ARGS="${NEXUS_GPU_DOCKER_ARGS:-}"; log "profile: $p (vendor=${NEXUS_GPU_VENDOR:-?})"; break; fi
done

# explicit override wins over the profile
case "${DEV_GPU:-}" in
  nvidia) GPU_ARGS="--gpus all -e OLLAMA_VULKAN=0" ;;
  amd)    GPU_ARGS="--device /dev/kfd:/dev/kfd --device /dev/dri:/dev/dri -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1" ;;
  intel)  GPU_ARGS="--device /dev/dri:/dev/dri -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1" ;;
  dxg)    GPU_ARGS="--device /dev/dxg:/dev/dxg -v /usr/lib/wsl:/usr/lib/wsl:ro -e LD_LIBRARY_PATH=/usr/lib/wsl/lib -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1" ;;
  cpu)    GPU_ARGS="" ;;
esac

# last-resort probe if there is no profile and no override
if [ -z "${GPU_ARGS}" ] && [ -z "${DEV_GPU:-}" ]; then
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then GPU_ARGS="--gpus all -e OLLAMA_VULKAN=0"
  elif [ -e /dev/kfd ]; then GPU_ARGS="--device /dev/kfd:/dev/kfd --device /dev/dri:/dev/dri -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1"
  elif [ -e /dev/dri ]; then GPU_ARGS="--device /dev/dri:/dev/dri -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1"
  fi
  [ -n "$GPU_ARGS" ] && log "no profile found — probed: ${GPU_ARGS}"
fi
log "accelerator args: ${GPU_ARGS:-none (CPU mode)}"

if docker container inspect "$NAME" >/dev/null 2>&1; then
  if [ "${DEV_KEEP:-0}" = "1" ]; then
    log "refusing to replace the existing ${NAME} (DEV_KEEP=1)"; exit 0
  fi
  log "replacing existing ${NAME}..."
  docker container stop "$NAME" >/dev/null 2>&1 || true
  docker container rm -f "$NAME" >/dev/null 2>&1 || true
fi

# shellcheck disable=SC2086
docker run -itd --name="$NAME" -h "$NAME" --privileged \
  -p "${PORT}:3000" -e PUID=1050 -e PGID=1050 -e TZ="$TZ_" \
  --restart unless-stopped \
  -v /dev:/dev -v "${VOLUME}:/config" -v /var/run/docker.sock:/var/run/docker.sock \
  ${GPU_ARGS} "$IMAGE" || { echo "[DEV-gpu] ERROR: launch failed"; exit 1; }

log "started. http://localhost:${PORT}"
sleep 3
case "${GPU_ARGS}" in
  *--gpus*) docker exec "$NAME" nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null \
              && log "GPU visible inside the vault" || log "nvidia-smi not answering yet — give s6 a moment, then: docker exec ${NAME} nvidia-smi" ;;
  *dri*|*dxg*)
    R=$(docker exec "$NAME" sh -c 'ls /dev/dri 2>/dev/null | tr "\n" " "' 2>/dev/null)
    D=$(docker exec "$NAME" sh -c '[ -e /dev/dxg ] && echo yes' 2>/dev/null)
    [ -n "$R" ] && log "DRI render nodes inside the vault: $R"
    [ -z "$R" ] && [ -n "$D" ] && log "no DRI render node - only /dev/dxg (WSL D3D12 route; needs the Dozen ICD)"
    [ -z "$R" ] && [ -z "$D" ] && log "no render nodes visible inside the vault" ;;
esac
if docker exec "$NAME" test -x /usr/local/lib/ollama/llama-server >/dev/null 2>&1; then
  log "prove inference: docker exec ${NAME} ollama run llama3.2:3b hi ; docker exec ${NAME} ollama ps"
else
  log "ollama runner not installed yet - first boot is still fetching it."
  log "  wait for: docker exec ${NAME} test -x /usr/local/lib/ollama/llama-server"
  log "  then:     docker exec ${NAME} ollama run llama3.2:3b hi ; docker exec ${NAME} ollama ps"
fi
DEVGPU
}

write_dev_rebuild() {
cat > "${STAGE}/DEV-rebuild-gpu" <<'DEVREBUILD'
#!/usr/bin/env bash
# DEV-rebuild-gpu — DESTRUCTIVE refresh, the GPU twin of DEV-rebuild.
#   stop -> rm container -> REMOVE THE VOLUME(S) -> pull -> DEV-gpu
# Everything in /config is destroyed. Use DEV-restore-gpu to keep it.
# DEV_PURGE_IMAGE=1 also deletes the local image before pulling (full re-download).
set -uo pipefail
NAME="${DEV_NAME:-nexus-creator-vault}"
IMAGE="${DEV_IMAGE:-natoascode/zero-trust-cockpit:creator-vault}"
VOLUMES="${DEV_VOLUMES:-creator-vault0}"
log() { echo "[DEV-rebuild-gpu] $*"; }

if [ "${DEV_YES:-0}" != "1" ] && [ -t 0 ]; then
  printf "[DEV-rebuild-gpu] This DELETES the vault volume(s): %s\n" "$VOLUMES"
  printf "[DEV-rebuild-gpu] Type REBUILD to continue: "
  read -r reply
  [ "$reply" = "REBUILD" ] || { log "aborted."; exit 1; }
fi

log "stopping ${NAME}..."
docker container stop "$NAME" >/dev/null 2>&1 || log "  (not running)"
log "removing container..."
docker container rm -f "$NAME" >/dev/null 2>&1 || log "  (no container)"

for v in $VOLUMES; do
  if docker volume inspect "$v" >/dev/null 2>&1; then
    if docker volume rm "$v" >/dev/null 2>&1; then
      log "volume removed: $v"
    else
      log "volume $v still in use — finding holders..."
      holders=$(docker ps -aq --filter "volume=$v" 2>/dev/null)
      for h in $holders; do docker rm -f "$h" >/dev/null 2>&1 || true; done
      docker volume rm "$v" >/dev/null 2>&1 && log "volume removed after clearing holders: $v" \
        || log "WARN: could not remove volume $v — rebuild will reuse it"
    fi
  else
    log "volume absent (nothing to clear): $v"
  fi
done

if [ "${DEV_PURGE_IMAGE:-0}" = "1" ]; then
  log "purging local image ${IMAGE}..."
  docker image rm -f "$IMAGE" >/dev/null 2>&1 || log "  (image not present)"
fi

n=0
until docker pull "$IMAGE"; do
  n=$((n+1)); [ "$n" -ge 3 ] && { log "pull failed 3x — continuing with whatever is local"; break; }
  log "pull retry ${n}/3..."; sleep 5
done

for c in "$(dirname "$0")/DEV-gpu" /usr/local/bin/DEV-gpu; do
  [ -x "$c" ] && { log "relaunching via $c"; exec "$c"; }
done
command -v DEV-gpu >/dev/null 2>&1 && exec DEV-gpu
log "ERROR: DEV-gpu not found — run it manually to bring the vault back up."; exit 1
DEVREBUILD
}

write_dev_restore() {
cat > "${STAGE}/DEV-restore-gpu" <<'DEVRESTORE'
#!/usr/bin/env bash
# DEV-restore-gpu — NON-destructive refresh, the GPU twin of DEV-restore.
#   stop -> rm container -> pull -> DEV-gpu        (the volume is PRESERVED)
# Use this to pick up a new image without losing anything in /config.
set -uo pipefail
NAME="${DEV_NAME:-nexus-creator-vault}"
IMAGE="${DEV_IMAGE:-natoascode/zero-trust-cockpit:creator-vault}"
VOLUMES="${DEV_VOLUMES:-creator-vault0}"
log() { echo "[DEV-restore-gpu] $*"; }

log "stopping ${NAME}..."
docker container stop "$NAME" >/dev/null 2>&1 || log "  (not running)"
log "removing container (volume kept)..."
docker container rm -f "$NAME" >/dev/null 2>&1 || log "  (no container)"

for v in $VOLUMES; do
  docker volume inspect "$v" >/dev/null 2>&1 && log "preserving volume: $v" || log "note: volume $v does not exist yet — it will be created fresh"
done

n=0
until docker pull "$IMAGE"; do
  n=$((n+1)); [ "$n" -ge 3 ] && { log "pull failed 3x — continuing with whatever is local"; break; }
  log "pull retry ${n}/3..."; sleep 5
done

for c in "$(dirname "$0")/DEV-gpu" /usr/local/bin/DEV-gpu; do
  [ -x "$c" ] && { log "relaunching via $c"; exec "$c"; }
done
command -v DEV-gpu >/dev/null 2>&1 && exec DEV-gpu
log "ERROR: DEV-gpu not found — run it manually to bring the vault back up."; exit 1
DEVRESTORE
}

# DEV-gpu: a sibling copy wins (v1's works, don't replace what works).
if [ -f "${SELF_DIR}/DEV-gpu" ]; then
  cp "${SELF_DIR}/DEV-gpu" "${STAGE}/DEV-gpu"
  log "DEV-gpu: using the copy next to this script"
else
  write_dev_gpu
  log "DEV-gpu: using the built-in template"
fi
# rebuild/restore are ALWAYS written from the corrected templates
write_dev_rebuild
write_dev_restore
chmod +x "${STAGE}"/DEV-gpu "${STAGE}"/DEV-rebuild-gpu "${STAGE}"/DEV-restore-gpu
profile_body > "${STAGE}/nexus-gpu.env"

# =============================================================================
# STEP 6 — install on the host, then inject into Cerberus Manager containers
# =============================================================================
install_host() {
  local dest="/usr/local/bin"
  if [ "$DRY" = 1 ]; then log "(dry-run) would install DEV-gpu / DEV-rebuild-gpu / DEV-restore-gpu into ${dest}"; return 0; fi
  $SUDO mkdir -p "$dest" /usr/local/etc 2>/dev/null || { warn "cannot write ${dest} — skipping host install"; return 1; }
  for f in DEV-gpu DEV-rebuild-gpu DEV-restore-gpu; do
    $SUDO cp "${STAGE}/$f" "${dest}/$f" && $SUDO chmod +x "${dest}/$f" || warn "host install failed for $f"
  done
  $SUDO cp "${STAGE}/nexus-gpu.env" /usr/local/etc/nexus-gpu.env 2>/dev/null || true
  log "host commands installed: ${dest}/DEV-gpu, DEV-rebuild-gpu, DEV-restore-gpu"
}
install_host

inject_one() {
  ct="$1"
  log "  injecting into ${ct}..."
  $DOCKER exec "$ct" mkdir -p /usr/local/etc /usr/local/bin 2>/dev/null || return 1
  $DOCKER exec -i "$ct" sh -c 'cat > /usr/local/etc/nexus-gpu.env'   < "${STAGE}/nexus-gpu.env"    || return 1
  $DOCKER exec -i "$ct" sh -c 'cat > /usr/local/bin/DEV-gpu'         < "${STAGE}/DEV-gpu"          || return 1
  $DOCKER exec -i "$ct" sh -c 'cat > /usr/local/bin/DEV-rebuild-gpu' < "${STAGE}/DEV-rebuild-gpu"  || return 1
  $DOCKER exec -i "$ct" sh -c 'cat > /usr/local/bin/DEV-restore-gpu' < "${STAGE}/DEV-restore-gpu"  || return 1
  $DOCKER exec "$ct" chmod +x /usr/local/bin/DEV-gpu /usr/local/bin/DEV-rebuild-gpu /usr/local/bin/DEV-restore-gpu || return 1
  log "  ${ct}: DEV-gpu + DEV-rebuild-gpu + DEV-restore-gpu installed (vendor=${VENDOR})"
}

# cerberus-manager, Cerberus-Manager, cerberus_manager, cerberus_cerberus-manager
MATCHES=$($DOCKER ps -a --format '{{.Names}}' 2>/dev/null | grep -iE '(^|[-_])cerberus[-_]?manager' || true)
if [ -z "$MATCHES" ]; then
  log "no cerberus-manager containers found — host install above is all you need."
else
  echo "$MATCHES" | while IFS= read -r ct; do
    [ -z "$ct" ] && continue
    if [ "$DRY" = 1 ]; then log "  (dry-run) would inject into ${ct}"; continue; fi
    state=$($DOCKER inspect -f '{{.State.Running}}' "$ct" 2>/dev/null)
    if [ "$state" != "true" ]; then
      log "  ${ct} is stopped — attempting start..."
      $DOCKER start "$ct" >/dev/null 2>&1 || { warn "  ${ct} would not start — skipped."; continue; }
      sleep 2
    fi#!/usr/bin/env bash
# =============================================================================
# nexus-gpu-setup.sh v2.0 — multi-vendor GPU enablement for the Nexus ecosystem
#
# Run ON THE HOST (native Linux, or inside WSL after typing `wsl` on Windows).
# Root or sudo. Safe to re-run; every step is guarded and non-fatal where the
# environment simply lacks the hardware.
#
# WHAT CHANGED IN v2.0
#   * DEV-rebuild-gpu now matches the real DEV-rebuild contract: stop -> rm
#     container -> REMOVE THE VOLUME(S) -> pull -> relaunch. v1 only pulled and
#     re-ran, so nothing was ever actually cleared.
#   * DEV-restore-gpu ADDED: stop -> rm container -> pull -> relaunch, volume
#     PRESERVED. This is the non-destructive twin, same as DEV-restore.
#   * All three commands are now EMBEDDED in this file. No more "keep all three
#     files in one folder." A sibling DEV-gpu still wins if you have one you
#     like — v1's DEV-gpu works, so it is preserved when present.
#   * Vendor coverage widened well past NVIDIA. Ollama now ships a Vulkan
#     backend enabled by default, so AMD and Intel GPUs (including iGPUs) are
#     real acceleration targets, not CPU-fallback consolation prizes.
#   * Container matching now also catches compose-prefixed names
#     (cerberus_cerberus-manager) as well as cerberus-manager / Cerberus-Manager.
#   * Host install: the three commands are also placed in /usr/local/bin so
#     bare-metal Forge OS hosts get them without a Cerberus container.
#
# THE ACCELERATION TRUTH TABLE (researched, current as of this build)
#
#   NVIDIA, native Linux or WSL2 ....... CUDA via nvidia-container-toolkit.
#                                        `--gpus all`. Best path by a wide
#                                        margin. Covers eGPUs. Needs compute
#                                        capability 5.0+ and driver 550+.
#                                        In WSL the driver is the WINDOWS one —
#                                        never install a Linux NVIDIA driver
#                                        inside WSL, it breaks passthrough.
#
#   AMD, native Linux ................. ROCm via /dev/kfd + /dev/dri. Ollama
#                                        wants the ROCm v7 driver stack. Cards
#                                        outside the supported LLVM targets can
#                                        often be forced with
#                                        HSA_OVERRIDE_GFX_VERSION (e.g. an
#                                        RX 5400 is gfx1034, run it as 10.3.0).
#                                        Anything ROCm refuses still gets the
#                                        Vulkan path below.
#
#   Intel / AMD iGPU / anything with a . Vulkan via /dev/dri alone. No /dev/kfd
#   render node, native Linux           needed — omitting it is harmless and
#                                        correct. This is the path that makes
#                                        Iris Xe, Radeon 680M/Vega, Arc, and
#                                        similar actually accelerate. Modest
#                                        next to CUDA, clearly better than CPU.
#
#   Non-NVIDIA under WSL2 ............. /dev/dxg + Mesa's Dozen driver
#                                        (Vulkan-on-D3D12). This DOES work now —
#                                        Ollama detects e.g. "Microsoft
#                                        Direct3D12 (Intel Arc 140T) (Dozen)"
#                                        and offloads layers. It is also still
#                                        flaky (upstream has open /dev/dxg sync
#                                        hangs), and enabling it means putting
#                                        /usr/lib/wsl/lib on the container's
#                                        library path, which can disturb a
#                                        desktop image. So it is OPT-IN:
#                                        NEXUS_WSL_DXG=1. ROCm still cannot work
#                                        under WSL2 — there is no /dev/kfd.
#
#   Apple Silicon ...................... Metal is not reachable from a Linux
#                                        container. On macOS/Lima the vault is
#                                        CPU-only by design; Metal needs a
#                                        native macOS Ollama.
#
#   NPUs ............................... Not used by Ollama. WSL3's NPU
#                                        passthrough (Build 2026, DirectML 2.0)
#                                        does not change that yet.
#
# FLAGS / ENV:
#   --dry-run                    detect + report only; change nothing
#   --verify                     re-run the container GPU proof and exit
#   --help
#   NEXUS_GPU_VENDOR=nvidia|amd|intel|dxg|cpu   force the verdict
#   NEXUS_GPU_VULKAN=1           keep Vulkan on even when CUDA is present
#   NEXUS_WSL_DXG=1              opt in to the WSL Dozen/Vulkan path
#   HSA_OVERRIDE_GFX_VERSION=x.y.z   passed through to the container for AMD
#   DEV_IMAGE=...                override the vault image
#   NEXUS_DEV_ROOT=/some/path    (tests) probe device nodes under a fake root
#   NEXUS_DOCKER="..."           (tests) substitute the docker command
# =============================================================================
set -uo pipefail

VERSION="2.1.0"
DRY=0; VERIFY_ONLY=0; PROVISION=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --provision) PROVISION=1 ;;
    --verify)  VERIFY_ONLY=1 ;;
    --help|-h) sed -n '2,80p' "$0"; exit 0 ;;
  esac
done

DEVROOT="${NEXUS_DEV_ROOT:-}"
IMAGE="${DEV_IMAGE:-natoascode/zero-trust-cockpit:creator-vault}"
VAULT_NAME="${DEV_NAME:-nexus-creator-vault}"
VAULT_VOLUMES="${DEV_VOLUMES:-creator-vault0}"
VAULT_PORT="${DEV_PORT:-1050}"

log()  { echo "[gpu-setup] $*"; }
warn() { echo "[gpu-setup] WARN: $*"; }
err()  { echo "[gpu-setup] ERROR: $*"; }

# --- sudo shim: use sudo only if not root and sudo exists --------------------
SUDO=""
if [ "$(id -u)" != "0" ]; then
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"
  else err "not root and no sudo available — rerun as root"; exit 1; fi
fi
DOCKER="${NEXUS_DOCKER:-$SUDO docker}"

log "nexus-gpu-setup v${VERSION}"

# =============================================================================
# STEP 1 — environment
# =============================================================================
IS_WSL=0
if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; then
  IS_WSL=1
fi
log "environment: $([ "$IS_WSL" = 1 ] && echo 'WSL2 (Windows host)' || echo 'native Linux')"

if ! command -v docker >/dev/null 2>&1 && [ -z "${NEXUS_DOCKER:-}" ]; then
  err "docker not found on this host — install docker first, then rerun."
  exit 1
fi

restart_docker() {
  # Docker Desktop's daemon lives on the Windows side — we cannot restart it
  # from here; detect and instruct instead of failing.
  if docker context show 2>/dev/null | grep -qi 'desktop'; then
    warn "Docker Desktop detected — restart it from the Windows tray (Quit + reopen), then rerun this script."
    return 1
  fi
  if command -v systemctl >/dev/null 2>&1 && $SUDO systemctl restart docker 2>/dev/null; then
    log "docker restarted via systemctl"; return 0
  fi
  if $SUDO service docker restart 2>/dev/null; then
    log "docker restarted via service"; return 0
  fi
  warn "could not restart docker automatically — restart it manually, then rerun."
  return 1
}

# =============================================================================
# STEP 2 — GPU detection (multi-vendor, inventory first, then a verdict)
# =============================================================================
has_dev() { [ -e "${DEVROOT}$1" ]; }
gid_of()  { getent group "$1" 2>/dev/null | cut -d: -f3; }

VENDOR="none"; GPU_ARGS=""; NOTES=""; SECONDARY=""

HAS_NVIDIA=0; HAS_KFD=0; HAS_DRI=0; HAS_DXG=0
command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1 && HAS_NVIDIA=1
has_dev /dev/kfd && HAS_KFD=1
has_dev /dev/dri && HAS_DRI=1
has_dev /dev/dxg && HAS_DXG=1

INVENTORY=""
[ "$HAS_NVIDIA" = 1 ] && INVENTORY="${INVENTORY} nvidia-smi"
[ "$HAS_KFD"    = 1 ] && INVENTORY="${INVENTORY} /dev/kfd"
[ "$HAS_DRI"    = 1 ] && INVENTORY="${INVENTORY} /dev/dri"
[ "$HAS_DXG"    = 1 ] && INVENTORY="${INVENTORY} /dev/dxg"
log "device inventory:${INVENTORY:- none}"

# render/video GIDs must be numeric — a container image that has no "render"
# group would make `--group-add render` fail the whole launch.
GID_RENDER="$(gid_of render)"; GID_VIDEO="$(gid_of video)"
GROUP_ARGS=""
[ -n "$GID_RENDER" ] && GROUP_ARGS="${GROUP_ARGS} --group-add ${GID_RENDER}"
[ -n "$GID_VIDEO"  ] && GROUP_ARGS="${GROUP_ARGS} --group-add ${GID_VIDEO}"

dri_devices() {
  # pass the render node(s) explicitly; harmless under --privileged, required
  # if anyone ever drops it
  local out=""
  for d in "${DEVROOT}"/dev/dri/renderD* "${DEVROOT}"/dev/dri/card*; do
    [ -e "$d" ] || continue
    out="${out} --device ${d#$DEVROOT}:${d#$DEVROOT}"
  done
  [ -z "$out" ] && out=" --device /dev/dri:/dev/dri"
  echo "$out"
}

decide() {
  # ---- forced verdict -----------------------------------------------------
  case "${NEXUS_GPU_VENDOR:-auto}" in
    nvidia|amd|intel|dxg|cpu) VENDOR="${NEXUS_GPU_VENDOR}"
      log "verdict FORCED by NEXUS_GPU_VENDOR=${VENDOR}" ;;
    *) VENDOR="" ;;
  esac

  if [ -z "$VENDOR" ]; then
    if [ "$HAS_NVIDIA" = 1 ]; then VENDOR="nvidia"
    elif [ "$HAS_KFD" = 1 ] && [ "$IS_WSL" = 0 ]; then VENDOR="amd"
    elif [ "$HAS_DRI" = 1 ] && [ "$IS_WSL" = 0 ]; then VENDOR="intel"
    elif [ "$HAS_DXG" = 1 ] && [ "${NEXUS_WSL_DXG:-1}" = 1 ]; then VENDOR="dxg"
    else VENDOR="cpu"; fi
  fi

  case "$VENDOR" in
    nvidia)
      GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
      GPU_ARGS="--gpus all"
      # CUDA is authoritative. Leaving Vulkan on invites the scheduler to pick a
      # flaky iGPU next to a perfectly good CUDA card. Override if you want both.
      if [ "${NEXUS_GPU_VULKAN:-0}" = 1 ]; then
        GPU_ARGS="${GPU_ARGS} -e OLLAMA_VULKAN=1"
        [ "$HAS_DRI" = 1 ] && GPU_ARGS="${GPU_ARGS}$(dri_devices)${GROUP_ARGS}"
        SECONDARY="Vulkan kept ON alongside CUDA (NEXUS_GPU_VULKAN=1) — set GGML_VK_VISIBLE_DEVICES if the wrong device gets picked"
      else
        GPU_ARGS="${GPU_ARGS} -e OLLAMA_VULKAN=0"
        [ "$HAS_DRI" = 1 ] && SECONDARY="a render node is also present; Vulkan left OFF so CUDA stays authoritative (NEXUS_GPU_VULKAN=1 to change)"
      fi
      NOTES="NVIDIA '${GPU_NAME:-unknown}' — CUDA path (native + WSL2, covers eGPUs)"
      ;;
    amd)
      GPU_ARGS="--device /dev/kfd:/dev/kfd$(dri_devices)${GROUP_ARGS} -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1"
      [ -n "${HSA_OVERRIDE_GFX_VERSION:-}" ] && \
        GPU_ARGS="${GPU_ARGS} -e HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION}"
      NOTES="AMD ROCm compute node present — ROCm first, Vulkan left enabled as the fallback for cards ROCm does not target"
      SECONDARY="if Ollama reports no ROCm device, find your gfx target and re-run with HSA_OVERRIDE_GFX_VERSION=10.3.0 (or the nearest supported target)"
      ;;
    intel)
      GPU_ARGS="$(dri_devices)${GROUP_ARGS} -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1"
      NOTES="Render node present (Intel/AMD iGPU or dGPU without ROCm) — Ollama's Vulkan backend uses it. Real acceleration, modest next to CUDA."
      SECONDARY="NPUs are NOT used by Ollama; the render node is the accelerator here"
      ;;
    dxg)
      GPU_ARGS="-v /usr/lib/wsl:/usr/lib/wsl:ro -e LD_LIBRARY_PATH=/usr/lib/wsl/lib -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1"
      [ "$HAS_DXG" = 1 ] && GPU_ARGS="--device /dev/dxg:/dev/dxg ${GPU_ARGS}"
      [ "$HAS_DRI" = 1 ] && GPU_ARGS="${GPU_ARGS}$(dri_devices)${GROUP_ARGS}"
      NOTES="WSL2 /dev/dxg + Mesa Dozen (Vulkan on D3D12) — selected automatically; this is the only GPU route WSL2 offers a non-NVIDIA card"
      SECONDARY="EXPERIMENTAL: needs the Dozen ICD in the image (--provision installs it) and upstream has open /dev/dxg sync hangs. Turn it off with NEXUS_WSL_DXG=0."
      ;;
    cpu)
      GPU_ARGS=""
      if [ "$IS_WSL" = 1 ] && [ "$HAS_KFD" = 1 ]; then
        NOTES="WSL2 with an AMD compute node visible. ROCm still cannot work under WSL2 — the /dev/kfd you see is not a usable ROCm path. Boot native Linux (Forge OS) for ROCm, or rerun with NEXUS_WSL_DXG=1 to try the Dozen/Vulkan route."
      elif [ "$IS_WSL" = 1 ] && { [ "$HAS_DXG" = 1 ] || [ "$HAS_DRI" = 1 ]; }; then
        NOTES="WSL2 D3D12 route available but turned OFF by NEXUS_WSL_DXG=0 — CPU mode. Unset it to use the GPU."
      elif [ "$IS_WSL" = 1 ]; then
        NOTES="WSL2, no GPU nodes visible. If this machine HAS an NVIDIA GPU/eGPU: update the WINDOWS NVIDIA driver, reconnect the eGPU BEFORE starting WSL, then rerun."
      else
        NOTES="No GPU nodes found — CPU mode (small models remain viable)."
      fi
      ;;
  esac
}
decide

# a forced verdict can name devices this host does not have; docker run would
# fail outright, so say so here rather than at launch time
case "$VENDOR" in
  amd)   [ "$HAS_KFD" = 1 ] || warn "forced/assumed AMD but /dev/kfd is absent — docker run will reject the --device flag" ;;
  intel) [ "$HAS_DRI" = 1 ] || warn "forced/assumed Intel but /dev/dri is absent — docker run will reject the --device flag" ;;
  dxg)   [ "$HAS_DXG" = 1 ] || warn "forced/assumed dxg but /dev/dxg is absent — docker run will reject the --device flag" ;;
esac

log "GPU verdict: vendor=${VENDOR}  args='${GPU_ARGS:-none}'"
log "  ${NOTES}"
[ -n "$SECONDARY" ] && log "  note: ${SECONDARY}"

# =============================================================================
# STEP 3 — NVIDIA container toolkit (install, register, restart, verify, repair)
# =============================================================================
toolkit_registered() { $DOCKER info 2>/dev/null | grep -qi 'runtimes:.*nvidia'; }

verify_gpu_container() {
  # entrypoint override = run ONLY the probe, skip the whole s6 boot
  case "$VENDOR" in
    nvidia) $DOCKER run --rm --gpus all --entrypoint nvidia-smi "$IMAGE" \
              --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 ;;
    amd|intel|dxg)
      # shellcheck disable=SC2086
      $DOCKER run --rm $GPU_ARGS --entrypoint sh "$IMAGE" -c \
        'ls /dev/dri 2>/dev/null | tr "\n" " "; [ -e /dev/kfd ] && printf "kfd "; [ -e /dev/dxg ] && printf "dxg "' 2>/dev/null | head -1 ;;
    *) echo "" ;;
  esac
}

nvidia_enable() {
  if ! command -v nvidia-ctk >/dev/null 2>&1; then
    log "installing NVIDIA Container Toolkit..."
    if command -v apt-get >/dev/null 2>&1; then
      curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
        | $SUDO gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
        && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
        | $SUDO tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null \
        && $SUDO apt-get update -qq \
        && { $SUDO apt-get install -y nvidia-container-toolkit \
             || { warn "install failed — one retry with --fix-missing"; \
                  $SUDO apt-get install -y --fix-missing nvidia-container-toolkit; }; }
    elif command -v dnf >/dev/null 2>&1; then
      $SUDO dnf install -y nvidia-container-toolkit || warn "dnf install failed — install nvidia-container-toolkit manually."
    elif command -v zypper >/dev/null 2>&1; then
      $SUDO zypper --non-interactive install nvidia-container-toolkit || warn "zypper install failed — install nvidia-container-toolkit manually."
    else
      warn "unrecognised package manager — install nvidia-container-toolkit yourself, then rerun."
    fi
  fi
  if command -v nvidia-ctk >/dev/null 2>&1 && ! toolkit_registered; then
    log "registering nvidia runtime with docker..."
    $SUDO nvidia-ctk runtime configure --runtime=docker >/dev/null 2>&1 || warn "nvidia-ctk configure reported an issue"
    restart_docker || true
  fi
  if toolkit_registered; then
    log "docker nvidia runtime: registered"
    RES="$(verify_gpu_container || true)"
    if [ -n "$RES" ]; then
      log "VERIFIED — container sees GPU: ${RES}"
    else
      warn "verification failed — one repair attempt (re-register + restart)..."
      $SUDO nvidia-ctk runtime configure --runtime=docker >/dev/null 2>&1 || true
      restart_docker || true
      RES="$(verify_gpu_container || true)"
      if [ -n "$RES" ]; then log "VERIFIED after repair — ${RES}"
      else warn "still unverified — DEV-gpu will attach --gpus all anyway; check 'docker info' for the nvidia runtime."; fi
    fi
  else
    warn "nvidia runtime not registered — docker restart may be pending (Docker Desktop needs a tray restart)."
  fi
}

amd_intel_checks() {
  # These paths need no toolkit — the devices are the interface. What they DO
  # need is a Vulkan/ROCm userspace inside the image, which the vault already
  # ships (Mesa VA-API/Vulkan + the /dev/kfd handling in 02-gpu-detect).
  [ -z "$GID_RENDER" ] && warn "no 'render' group on this host — GPU nodes may be root-only; check 'ls -l /dev/dri'"
  if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
    warn "SELinux is enforcing — containers may be blocked from GPU devices."
    warn "  fix: sudo setsebool -P container_use_devices=1"
  fi
  if [ "$VENDOR" = "amd" ] && ! command -v rocminfo >/dev/null 2>&1; then
    log "  (rocminfo not installed on the host — not required; Ollama carries its own ROCm libs. Install it only if you want to read gfx targets.)"
  fi
  RES="$(verify_gpu_container || true)"
  if [ -n "$RES" ]; then log "VERIFIED — container sees devices: ${RES}"
  else warn "device probe returned nothing — DEV-gpu will still attach the devices; check 'ls -l /dev/dri' on the host."; fi
}

if [ "$DRY" = 0 ]; then
  case "$VENDOR" in
    nvidia)        nvidia_enable ;;
    amd|intel|dxg) amd_intel_checks ;;
    *)             log "no accelerator to enable — skipping vendor setup" ;;
  esac
fi

if [ "$VERIFY_ONLY" = 1 ]; then
  log "verify-only run complete."; exit 0
fi

# =============================================================================
# STEP 4 — write the host GPU profile
# =============================================================================
PROFILE_DIR="/etc/nexus"; PROFILE="${PROFILE_DIR}/gpu.env"
profile_body() {
  echo "# written by nexus-gpu-setup.sh v${VERSION} $(date -u +%FT%TZ)"
  echo "NEXUS_GPU_VENDOR=${VENDOR}"
  echo "NEXUS_GPU_DOCKER_ARGS=\"${GPU_ARGS}\""
  echo "NEXUS_GPU_WSL=${IS_WSL}"
  # the profile is SOURCED by DEV-gpu, so no command substitution may survive
  echo "NEXUS_GPU_NOTES=\"${NOTES//[\`\$]/}\""
}
if [ "$DRY" = 0 ]; then
  if ! $SUDO mkdir -p "$PROFILE_DIR" 2>/dev/null; then
    PROFILE_DIR="${HOME}/.nexus"; PROFILE="${PROFILE_DIR}/gpu.env"; mkdir -p "$PROFILE_DIR"
  fi
  profile_body | $SUDO tee "$PROFILE" >/dev/null
  log "profile written: ${PROFILE}"
  # DEV-gpu reads /usr/local/etc first, so keep the two in lockstep and prove it
  $SUDO mkdir -p /usr/local/etc 2>/dev/null && profile_body | $SUDO tee /usr/local/etc/nexus-gpu.env >/dev/null 2>&1 || true
  EFF=$(grep -h NEXUS_GPU_DOCKER_ARGS /usr/local/etc/nexus-gpu.env "$PROFILE" 2>/dev/null | head -1 | cut -d= -f2-)
  log "effective accelerator args: ${EFF:-none}"
else
  log "(dry-run) would write ${PROFILE}: vendor=${VENDOR} args='${GPU_ARGS}'"
fi

# =============================================================================
# STEP 5 — materialize DEV-gpu / DEV-rebuild-gpu / DEV-restore-gpu
#
# CONTRACT (mirrors the appinator's DEV family exactly):
#   DEV-gpu          run the vault with the detected accelerator attached
#   DEV-rebuild-gpu  stop -> rm container -> RM VOLUME(S) -> pull -> DEV-gpu
#   DEV-restore-gpu  stop -> rm container -> pull -> DEV-gpu   (volume kept)
# =============================================================================
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT

write_dev_gpu() {
cat > "${STAGE}/DEV-gpu" <<'DEVGPU'
#!/usr/bin/env bash
# DEV-gpu — launch the Nexus Creator Vault with whatever accelerator this host has.
# Profile order: /usr/local/etc/nexus-gpu.env -> /etc/nexus/gpu.env -> ~/.nexus/gpu.env
# Override anything: DEV_GPU=nvidia|amd|intel|dxg|cpu  DEV_IMAGE=...  DEV_KEEP=1
set -uo pipefail
NAME="${DEV_NAME:-nexus-creator-vault}"
IMAGE="${DEV_IMAGE:-natoascode/zero-trust-cockpit:creator-vault}"
VOLUME="${DEV_VOLUME:-creator-vault0}"
PORT="${DEV_PORT:-1050}"
TZ_="${DEV_TZ:-America/Colorado}"
log() { echo "[DEV-gpu] $*"; }

GPU_ARGS=""
for p in /usr/local/etc/nexus-gpu.env /etc/nexus/gpu.env "${HOME}/.nexus/gpu.env"; do
  if [ -r "$p" ]; then . "$p"; GPU_ARGS="${NEXUS_GPU_DOCKER_ARGS:-}"; log "profile: $p (vendor=${NEXUS_GPU_VENDOR:-?})"; break; fi
done

# explicit override wins over the profile
case "${DEV_GPU:-}" in
  nvidia) GPU_ARGS="--gpus all -e OLLAMA_VULKAN=0" ;;
  amd)    GPU_ARGS="--device /dev/kfd:/dev/kfd --device /dev/dri:/dev/dri -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1" ;;
  intel)  GPU_ARGS="--device /dev/dri:/dev/dri -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1" ;;
  dxg)    GPU_ARGS="--device /dev/dxg:/dev/dxg -v /usr/lib/wsl:/usr/lib/wsl:ro -e LD_LIBRARY_PATH=/usr/lib/wsl/lib -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1" ;;
  cpu)    GPU_ARGS="" ;;
esac

# last-resort probe if there is no profile and no override
if [ -z "${GPU_ARGS}" ] && [ -z "${DEV_GPU:-}" ]; then
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then GPU_ARGS="--gpus all -e OLLAMA_VULKAN=0"
  elif [ -e /dev/kfd ]; then GPU_ARGS="--device /dev/kfd:/dev/kfd --device /dev/dri:/dev/dri -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1"
  elif [ -e /dev/dri ]; then GPU_ARGS="--device /dev/dri:/dev/dri -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1"
  fi
  [ -n "$GPU_ARGS" ] && log "no profile found — probed: ${GPU_ARGS}"
fi
log "accelerator args: ${GPU_ARGS:-none (CPU mode)}"

if docker container inspect "$NAME" >/dev/null 2>&1; then
  if [ "${DEV_KEEP:-0}" = "1" ]; then
    log "refusing to replace the existing ${NAME} (DEV_KEEP=1)"; exit 0
  fi
  log "replacing existing ${NAME}..."
  docker container stop "$NAME" >/dev/null 2>&1 || true
  docker container rm -f "$NAME" >/dev/null 2>&1 || true
fi

# shellcheck disable=SC2086
docker run -itd --name="$NAME" -h "$NAME" --privileged \
  -p "${PORT}:3000" -e PUID=1050 -e PGID=1050 -e TZ="$TZ_" \
  --restart unless-stopped \
  -v /dev:/dev -v "${VOLUME}:/config" -v /var/run/docker.sock:/var/run/docker.sock \
  ${GPU_ARGS} "$IMAGE" || { echo "[DEV-gpu] ERROR: launch failed"; exit 1; }

log "started. http://localhost:${PORT}"
sleep 3
case "${GPU_ARGS}" in
  *--gpus*) docker exec "$NAME" nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null \
              && log "GPU visible inside the vault" || log "nvidia-smi not answering yet — give s6 a moment, then: docker exec ${NAME} nvidia-smi" ;;
  *dri*|*dxg*)
    R=$(docker exec "$NAME" sh -c 'ls /dev/dri 2>/dev/null | tr "\n" " "' 2>/dev/null)
    D=$(docker exec "$NAME" sh -c '[ -e /dev/dxg ] && echo yes' 2>/dev/null)
    [ -n "$R" ] && log "DRI render nodes inside the vault: $R"
    [ -z "$R" ] && [ -n "$D" ] && log "no DRI render node - only /dev/dxg (WSL D3D12 route; needs the Dozen ICD)"
    [ -z "$R" ] && [ -z "$D" ] && log "no render nodes visible inside the vault" ;;
esac
if docker exec "$NAME" test -x /usr/local/lib/ollama/llama-server >/dev/null 2>&1; then
  log "prove inference: docker exec ${NAME} ollama run llama3.2:3b hi ; docker exec ${NAME} ollama ps"
else
  log "ollama runner not installed yet - first boot is still fetching it."
  log "  wait for: docker exec ${NAME} test -x /usr/local/lib/ollama/llama-server"
  log "  then:     docker exec ${NAME} ollama run llama3.2:3b hi ; docker exec ${NAME} ollama ps"
fi
DEVGPU
}

write_dev_rebuild() {
cat > "${STAGE}/DEV-rebuild-gpu" <<'DEVREBUILD'
#!/usr/bin/env bash
# DEV-rebuild-gpu — DESTRUCTIVE refresh, the GPU twin of DEV-rebuild.
#   stop -> rm container -> REMOVE THE VOLUME(S) -> pull -> DEV-gpu
# Everything in /config is destroyed. Use DEV-restore-gpu to keep it.
# DEV_PURGE_IMAGE=1 also deletes the local image before pulling (full re-download).
set -uo pipefail
NAME="${DEV_NAME:-nexus-creator-vault}"
IMAGE="${DEV_IMAGE:-natoascode/zero-trust-cockpit:creator-vault}"
VOLUMES="${DEV_VOLUMES:-creator-vault0}"
log() { echo "[DEV-rebuild-gpu] $*"; }

if [ "${DEV_YES:-0}" != "1" ] && [ -t 0 ]; then
  printf "[DEV-rebuild-gpu] This DELETES the vault volume(s): %s\n" "$VOLUMES"
  printf "[DEV-rebuild-gpu] Type REBUILD to continue: "
  read -r reply
  [ "$reply" = "REBUILD" ] || { log "aborted."; exit 1; }
fi

log "stopping ${NAME}..."
docker container stop "$NAME" >/dev/null 2>&1 || log "  (not running)"
log "removing container..."
docker container rm -f "$NAME" >/dev/null 2>&1 || log "  (no container)"

for v in $VOLUMES; do
  if docker volume inspect "$v" >/dev/null 2>&1; then
    if docker volume rm "$v" >/dev/null 2>&1; then
      log "volume removed: $v"
    else
      log "volume $v still in use — finding holders..."
      holders=$(docker ps -aq --filter "volume=$v" 2>/dev/null)
      for h in $holders; do docker rm -f "$h" >/dev/null 2>&1 || true; done
      docker volume rm "$v" >/dev/null 2>&1 && log "volume removed after clearing holders: $v" \
        || log "WARN: could not remove volume $v — rebuild will reuse it"
    fi
  else
    log "volume absent (nothing to clear): $v"
  fi
done

if [ "${DEV_PURGE_IMAGE:-0}" = "1" ]; then
  log "purging local image ${IMAGE}..."
  docker image rm -f "$IMAGE" >/dev/null 2>&1 || log "  (image not present)"
fi

n=0
until docker pull "$IMAGE"; do
  n=$((n+1)); [ "$n" -ge 3 ] && { log "pull failed 3x — continuing with whatever is local"; break; }
  log "pull retry ${n}/3..."; sleep 5
done

for c in "$(dirname "$0")/DEV-gpu" /usr/local/bin/DEV-gpu; do
  [ -x "$c" ] && { log "relaunching via $c"; exec "$c"; }
done
command -v DEV-gpu >/dev/null 2>&1 && exec DEV-gpu
log "ERROR: DEV-gpu not found — run it manually to bring the vault back up."; exit 1
DEVREBUILD
}

write_dev_restore() {
cat > "${STAGE}/DEV-restore-gpu" <<'DEVRESTORE'
#!/usr/bin/env bash
# DEV-restore-gpu — NON-destructive refresh, the GPU twin of DEV-restore.
#   stop -> rm container -> pull -> DEV-gpu        (the volume is PRESERVED)
# Use this to pick up a new image without losing anything in /config.
set -uo pipefail
NAME="${DEV_NAME:-nexus-creator-vault}"
IMAGE="${DEV_IMAGE:-natoascode/zero-trust-cockpit:creator-vault}"
VOLUMES="${DEV_VOLUMES:-creator-vault0}"
log() { echo "[DEV-restore-gpu] $*"; }

log "stopping ${NAME}..."
docker container stop "$NAME" >/dev/null 2>&1 || log "  (not running)"
log "removing container (volume kept)..."
docker container rm -f "$NAME" >/dev/null 2>&1 || log "  (no container)"

for v in $VOLUMES; do
  docker volume inspect "$v" >/dev/null 2>&1 && log "preserving volume: $v" || log "note: volume $v does not exist yet — it will be created fresh"
done

n=0
until docker pull "$IMAGE"; do
  n=$((n+1)); [ "$n" -ge 3 ] && { log "pull failed 3x — continuing with whatever is local"; break; }
  log "pull retry ${n}/3..."; sleep 5
done

for c in "$(dirname "$0")/DEV-gpu" /usr/local/bin/DEV-gpu; do
  [ -x "$c" ] && { log "relaunching via $c"; exec "$c"; }
done
command -v DEV-gpu >/dev/null 2>&1 && exec DEV-gpu
log "ERROR: DEV-gpu not found — run it manually to bring the vault back up."; exit 1
DEVRESTORE
}

# DEV-gpu: a sibling copy wins (v1's works, don't replace what works).
if [ -f "${SELF_DIR}/DEV-gpu" ]; then
  cp "${SELF_DIR}/DEV-gpu" "${STAGE}/DEV-gpu"
  log "DEV-gpu: using the copy next to this script"
else
  write_dev_gpu
  log "DEV-gpu: using the built-in template"
fi
# rebuild/restore are ALWAYS written from the corrected templates
write_dev_rebuild
write_dev_restore
chmod +x "${STAGE}"/DEV-gpu "${STAGE}"/DEV-rebuild-gpu "${STAGE}"/DEV-restore-gpu
profile_body > "${STAGE}/nexus-gpu.env"

# =============================================================================
# STEP 6 — install on the host, then inject into Cerberus Manager containers
# =============================================================================
install_host() {
  local dest="/usr/local/bin"
  if [ "$DRY" = 1 ]; then log "(dry-run) would install DEV-gpu / DEV-rebuild-gpu / DEV-restore-gpu into ${dest}"; return 0; fi
  $SUDO mkdir -p "$dest" /usr/local/etc 2>/dev/null || { warn "cannot write ${dest} — skipping host install"; return 1; }
  for f in DEV-gpu DEV-rebuild-gpu DEV-restore-gpu; do
    $SUDO cp "${STAGE}/$f" "${dest}/$f" && $SUDO chmod +x "${dest}/$f" || warn "host install failed for $f"
  done
  $SUDO cp "${STAGE}/nexus-gpu.env" /usr/local/etc/nexus-gpu.env 2>/dev/null || true
  log "host commands installed: ${dest}/DEV-gpu, DEV-rebuild-gpu, DEV-restore-gpu"
}
install_host

inject_one() {
  ct="$1"
  log "  injecting into ${ct}..."
  $DOCKER exec "$ct" mkdir -p /usr/local/etc /usr/local/bin 2>/dev/null || return 1
  $DOCKER exec -i "$ct" sh -c 'cat > /usr/local/etc/nexus-gpu.env'   < "${STAGE}/nexus-gpu.env"    || return 1
  $DOCKER exec -i "$ct" sh -c 'cat > /usr/local/bin/DEV-gpu'         < "${STAGE}/DEV-gpu"          || return 1
  $DOCKER exec -i "$ct" sh -c 'cat > /usr/local/bin/DEV-rebuild-gpu' < "${STAGE}/DEV-rebuild-gpu"  || return 1
  $DOCKER exec -i "$ct" sh -c 'cat > /usr/local/bin/DEV-restore-gpu' < "${STAGE}/DEV-restore-gpu"  || return 1
  $DOCKER exec "$ct" chmod +x /usr/local/bin/DEV-gpu /usr/local/bin/DEV-rebuild-gpu /usr/local/bin/DEV-restore-gpu || return 1
  log "  ${ct}: DEV-gpu + DEV-rebuild-gpu + DEV-restore-gpu installed (vendor=${VENDOR})"
}

# cerberus-manager, Cerberus-Manager, cerberus_manager, cerberus_cerberus-manager
MATCHES=$($DOCKER ps -a --format '{{.Names}}' 2>/dev/null | grep -iE '(^|[-_])cerberus[-_]?manager' || true)
if [ -z "$MATCHES" ]; then
  log "no cerberus-manager containers found — host install above is all you need."
else
  echo "$MATCHES" | while IFS= read -r ct; do
    [ -z "$ct" ] && continue
    if [ "$DRY" = 1 ]; then log "  (dry-run) would inject into ${ct}"; continue; fi
    state=$($DOCKER inspect -f '{{.State.Running}}' "$ct" 2>/dev/null)
    if [ "$state" != "true" ]; then
      log "  ${ct} is stopped — attempting start..."
      $DOCKER start "$ct" >/dev/null 2>&1 || { warn "  ${ct} would not start — skipped."; continue; }
      sleep 2
    fi
    inject_one "$ct" || { warn "  ${ct}: injection failed once — retrying..."; sleep 2; inject_one "$ct" || warn "  ${ct}: injection failed twice — skipped."; }
  done
fi

# =============================================================================
# STEP 6.5 — --provision: launch, wait, install what the path needs, verify
#            One command instead of six remembered ones.
# =============================================================================
provision() {
  DG="/usr/local/bin/DEV-gpu"; [ -x "$DG" ] || DG="${STAGE}/DEV-gpu"
  log "provision: launching the vault via ${DG}..."
  "$DG" || { err "DEV-gpu failed — stopping provision"; return 1; }

  log "provision: waiting for the ollama runner (first boot fetches it, up to 10 min)..."
  i=0
  while [ "$i" -lt 120 ]; do
    $DOCKER exec "$VAULT_NAME" test -x /usr/local/lib/ollama/llama-server >/dev/null 2>&1 && break
    i=$((i+1)); [ $((i % 12)) -eq 0 ] && log "  still installing... ($((i*5))s)"; sleep 5
  done
  if $DOCKER exec "$VAULT_NAME" test -x /usr/local/lib/ollama/llama-server >/dev/null 2>&1; then
    log "provision: ollama runner ready"
  else
    warn "provision: runner still missing after 10 min — repairing"
    $DOCKER exec "$VAULT_NAME" sh -c 'curl -fsSL https://ollama.com/install.sh | sh' >/dev/null 2>&1 \
      && log "provision: ollama repaired" || warn "provision: ollama repair failed"
  fi

  # the dxg route is useless without Mesa's Dozen ICD, which Ubuntu omits
  if [ "$VENDOR" = "dxg" ]; then
    if $DOCKER exec "$VAULT_NAME" test -f /usr/share/vulkan/icd.d/dzn_icd.json >/dev/null 2>&1; then
      log "provision: Dozen ICD already present"
    else
      log "provision: installing the Dozen ICD (kisak-mesa; Ubuntu's mesa omits it)..."
      $DOCKER exec "$VAULT_NAME" sh -c '
        apt-get update -qq &&
        apt-get install -y -qq software-properties-common vulkan-tools &&
        add-apt-repository -y ppa:kisak/kisak-mesa &&
        apt-get update -qq &&
        apt-get install -y -qq --reinstall mesa-vulkan-drivers' >/dev/null 2>&1
      $DOCKER exec "$VAULT_NAME" test -f /usr/share/vulkan/icd.d/dzn_icd.json >/dev/null 2>&1 \
        && log "provision: Dozen ICD installed" \
        || warn "provision: Dozen ICD still missing — the GPU route will fall back to CPU"
    fi
  fi

  log "provision: restarting (restart preserves the layer; DEV-gpu would discard it)..."
  $DOCKER restart "$VAULT_NAME" >/dev/null 2>&1; sleep 30

  log "provision: verdict —"
  RES=$($DOCKER logs "$VAULT_NAME" 2>&1 | grep "inference compute" | tail -1)
  if echo "$RES" | grep -qi "library=cpu"; then
    warn "  running on CPU: ${RES:-no discovery line yet}"
    [ "$VENDOR" = "dxg" ] && warn "  if it also says 'dropping integrated GPU', the profile did not carry OLLAMA_IGPU_ENABLE=1"
  elif [ -n "$RES" ]; then
    log "  ACCELERATED: ${RES}"
  else
    warn "  no discovery line yet — check: $DOCKER logs ${VAULT_NAME} | grep 'inference compute'"
  fi
  log "provision: try it — $DOCKER exec ${VAULT_NAME} ollama run llama3.2:3b hi ; $DOCKER exec ${VAULT_NAME} ollama ps"
}
if [ "$PROVISION" = 1 ] && [ "$DRY" = 0 ]; then provision; fi

# =============================================================================
# STEP 7 — summary
# =============================================================================
echo
log "DONE — vendor=${VENDOR}"
log "  DEV-gpu          launch the vault with the accelerator attached"
log "  DEV-restore-gpu  refresh the image, KEEP /config"
log "  DEV-rebuild-gpu  refresh the image, WIPE ${VAULT_VOLUMES} (asks for confirmation; DEV_YES=1 to skip)"
[ "$PROVISION" = 0 ] && log "  (re-run with --provision to launch, wait, install what this path needs, and verify in one go)"
case "$VENDOR" in
  nvidia) log "prove it: docker exec ${VAULT_NAME} nvidia-smi ; docker exec ${VAULT_NAME} ollama run llama3.2:3b hi ; docker exec ${VAULT_NAME} ollama ps" ;;
  amd|intel|dxg) log "prove it: docker exec ${VAULT_NAME} ollama run llama3.2:3b hi ; docker exec ${VAULT_NAME} ollama ps" ;;
  cpu) log "CPU mode — small models still run; ${NOTES}" ;;
esac
exit 0
    inject_one "$ct" || { warn "  ${ct}: injection failed once — retrying..."; sleep 2; inject_one "$ct" || warn "  ${ct}: injection failed twice — skipped."; }
  done
fi

# =============================================================================
# STEP 7 — summary
# =============================================================================
echo
log "DONE — vendor=${VENDOR}"
log "  DEV-gpu          launch the vault with the accelerator attached"
log "  DEV-restore-gpu  refresh the image, KEEP /config"
log "  DEV-rebuild-gpu  refresh the image, WIPE ${VAULT_VOLUMES} (asks for confirmation; DEV_YES=1 to skip)"
case "$VENDOR" in
  nvidia) log "prove it: docker exec ${VAULT_NAME} nvidia-smi ; docker exec ${VAULT_NAME} ollama run llama3.2:3b hi ; docker exec ${VAULT_NAME} ollama ps" ;;
  amd|intel|dxg) log "prove it: docker exec ${VAULT_NAME} ollama run llama3.2:3b hi ; docker exec ${VAULT_NAME} ollama ps" ;;
  cpu) log "CPU mode — small models still run; ${NOTES}" ;;
esac
exit 0