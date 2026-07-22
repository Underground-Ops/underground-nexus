#!/usr/bin/env bash
# =============================================================================
# nexus-gpu-setup.sh — one-shot GPU enablement for the Nexus ecosystem
#
# Run ON THE HOST (native Linux, or inside WSL after typing `wsl` on Windows).
# Root or sudo. Safe to re-run; every step is guarded and non-fatal where the
# environment simply lacks the hardware.
#
# WHAT IT DOES, in order:
#   1. Detects environment: WSL vs native Linux; how to restart docker.
#   2. Detects GPU vendor: NVIDIA (dGPU or eGPU) / AMD / Intel-iGPU / none.
#      WSL truth table is enforced: under WSL only NVIDIA can accelerate
#      Ollama (CUDA via /dev/dxg); AMD-ROCm and Intel-Vulkan need native
#      Linux because WSL exposes no /dev/dri or /dev/kfd.
#   3. NVIDIA: installs the NVIDIA Container Toolkit if missing (apt, with
#      one retry), registers the docker runtime, restarts docker
#      (service/systemctl/Docker-Desktop aware), and VERIFIES by running
#      nvidia-smi in a throwaway container (entrypoint override — no s6 boot).
#      One repair attempt (re-register + re-restart) before giving up.
#   4. Writes the host GPU profile:  /etc/nexus/gpu.env  (fallback ~/.nexus/gpu.env)
#      containing NEXUS_GPU_VENDOR and NEXUS_GPU_DOCKER_ARGS.
#   5. Finds containers named cerberus-manager / Cerberus-Manager (any case,
#      prefix-tolerant), and into each RUNNING one injects:
#         /usr/local/etc/nexus-gpu.env      (the same profile)
#         /usr/local/bin/DEV-gpu            (GPU-aware vault launcher)
#         /usr/local/bin/DEV-rebuild-gpu    (pull + relaunch)
#      Stopped ones get one docker-start attempt, then are skipped politely.
#      Zero matches is fine — the script completes either way.
#
# FLAGS:
#   --dry-run     detect + report only; change nothing
#   NEXUS_DEV_ROOT=/some/path   (tests) probe device nodes under a fake root
# =============================================================================
set -uo pipefail

DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
DEVROOT="${NEXUS_DEV_ROOT:-}"
IMAGE="${DEV_IMAGE:-natoascode/zero-trust-cockpit:creator-vault}"

log()  { echo "[gpu-setup] $*"; }
warn() { echo "[gpu-setup] WARN: $*"; }
err()  { echo "[gpu-setup] ERROR: $*"; }
run()  { if [ "$DRY" = 1 ]; then echo "  (dry-run) $*"; else "$@"; fi; }

# --- sudo shim: use sudo only if not root and sudo exists --------------------
SUDO=""
if [ "$(id -u)" != "0" ]; then
  if command -v sudo >/dev/null 2>&1; then SUDO="sudo"
  else err "not root and no sudo available — rerun as root"; exit 1; fi
fi
DOCKER="${NEXUS_DOCKER:-$SUDO docker}"

# =============================================================================
# STEP 1 — environment
# =============================================================================
IS_WSL=0
if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; then
  IS_WSL=1
fi
log "environment: $([ "$IS_WSL" = 1 ] && echo 'WSL2 (Windows host)' || echo 'native Linux')"

if ! command -v docker >/dev/null 2>&1; then
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
# STEP 2 — GPU detection (vendor truth table)
# =============================================================================
VENDOR="none"; GPU_DOCKER_ARGS=""; NOTES=""

has_dev() { [ -e "${DEVROOT}$1" ]; }

NVIDIA_OK=0
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  NVIDIA_OK=1
fi

if [ "$NVIDIA_OK" = 1 ]; then
  VENDOR="nvidia"; GPU_DOCKER_ARGS="--gpus all"
  GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
  NOTES="NVIDIA '${GPU_NAME:-unknown}' — CUDA path (works on WSL and native; covers eGPUs too)"
elif has_dev /dev/kfd; then
  if [ "$IS_WSL" = 1 ]; then
    VENDOR="none"
    NOTES="AMD /dev/kfd seen under WSL — unsupported for Ollama in WSL; boot native Linux for ROCm. CPU mode for now."
  else
    VENDOR="amd"; GPU_DOCKER_ARGS="--device /dev/kfd:/dev/kfd"
    has_dev /dev/dri && GPU_DOCKER_ARGS="$GPU_DOCKER_ARGS --device /dev/dri:/dev/dri"
    NOTES="AMD ROCm compute node present — Ollama's installer auto-detects ROCm at first boot"
  fi
elif has_dev /dev/dri; then
  if [ "$IS_WSL" = 1 ]; then
    VENDOR="none"
    NOTES="/dev/dri under WSL is unusual and not an Ollama path — CPU mode."
  else
    VENDOR="intel-dri"; GPU_DOCKER_ARGS="--device /dev/dri:/dev/dri"
    NOTES="Render node present (Intel/AMD iGPU) — Ollama's Vulkan backend can use it; modest but real acceleration. NPUs are NOT used by Ollama."
  fi
else
  if [ "$IS_WSL" = 1 ]; then
    NOTES="No NVIDIA visible in WSL. If this machine HAS an NVIDIA GPU/eGPU: update the Windows NVIDIA driver (WSL support), reconnect eGPU BEFORE starting WSL, then rerun. AMD/Intel cannot accelerate Ollama under WSL — CPU mode (still fine for small models)."
  else
    NOTES="No GPU nodes found — CPU mode (small models remain viable)."
  fi
fi
log "GPU verdict: vendor=${VENDOR}  args='${GPU_DOCKER_ARGS:-none}'"
log "  ${NOTES}"

# =============================================================================
# STEP 3 — NVIDIA container toolkit (install, register, restart, verify, repair)
# =============================================================================
toolkit_registered() { $DOCKER info 2>/dev/null | grep -qi 'runtimes:.*nvidia'; }

verify_gpu_container() {
  # entrypoint override = run ONLY nvidia-smi, skip the whole s6 boot
  $DOCKER run --rm --gpus all --entrypoint nvidia-smi "$IMAGE" \
      --query-gpu=name --format=csv,noheader 2>/dev/null | head -1
}

if [ "$VENDOR" = "nvidia" ] && [ "$DRY" = 0 ]; then
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
    else
      warn "non-apt distro — install nvidia-container-toolkit with your package manager, then rerun."
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
fi

# =============================================================================
# STEP 4 — write the host GPU profile
# =============================================================================
PROFILE_DIR="/etc/nexus"; PROFILE="${PROFILE_DIR}/gpu.env"
if [ "$DRY" = 0 ]; then
  if ! $SUDO mkdir -p "$PROFILE_DIR" 2>/dev/null; then
    PROFILE_DIR="${HOME}/.nexus"; PROFILE="${PROFILE_DIR}/gpu.env"; mkdir -p "$PROFILE_DIR"
  fi
  { echo "# written by nexus-gpu-setup.sh $(date -u +%FT%TZ)"
    echo "NEXUS_GPU_VENDOR=${VENDOR}"
    echo "NEXUS_GPU_DOCKER_ARGS=\"${GPU_DOCKER_ARGS}\""
    echo "NEXUS_GPU_WSL=${IS_WSL}"
  } | $SUDO tee "$PROFILE" >/dev/null
  log "profile written: ${PROFILE}"
else
  log "(dry-run) would write ${PROFILE}: vendor=${VENDOR} args='${GPU_DOCKER_ARGS}'"
fi

# =============================================================================
# STEP 5 — inject DEV-gpu / DEV-rebuild-gpu into Cerberus Manager containers
# =============================================================================
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
inject_one() {
  local ct="$1"
  log "  injecting into ${ct}..."
  $DOCKER exec "$ct" mkdir -p /usr/local/etc /usr/local/bin 2>/dev/null || return 1
  { echo "NEXUS_GPU_VENDOR=${VENDOR}"
    echo "NEXUS_GPU_DOCKER_ARGS=\"${GPU_DOCKER_ARGS}\""
  } | $DOCKER exec -i "$ct" sh -c 'cat > /usr/local/etc/nexus-gpu.env' || return 1
  $DOCKER exec -i "$ct" sh -c 'cat > /usr/local/bin/DEV-gpu'         < "${SELF_DIR}/DEV-gpu"         || return 1
  $DOCKER exec -i "$ct" sh -c 'cat > /usr/local/bin/DEV-rebuild-gpu' < "${SELF_DIR}/DEV-rebuild-gpu" || return 1
  $DOCKER exec "$ct" chmod +x /usr/local/bin/DEV-gpu /usr/local/bin/DEV-rebuild-gpu || return 1
  log "  ${ct}: DEV-gpu + DEV-rebuild-gpu installed (profile: vendor=${VENDOR})"
}

if [ ! -f "${SELF_DIR}/DEV-gpu" ] || [ ! -f "${SELF_DIR}/DEV-rebuild-gpu" ]; then
  warn "DEV-gpu / DEV-rebuild-gpu not found next to this script — skipping injection. Keep all three files in one folder."
else
  MATCHES=$($DOCKER ps -a --format '{{.Names}}' 2>/dev/null | grep -iE '^cerberus[-_]?manager' || true)
  if [ -z "$MATCHES" ]; then
    log "no cerberus-manager containers found — nothing to inject (that's fine)."
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
fi

log "DONE. Next: inside a cerberus container run  DEV-gpu   (or here on the host: bash ${SELF_DIR}/DEV-gpu)"
[ "$VENDOR" = "nvidia" ] && log "then prove it end-to-end:  docker exec nexus-creator-vault ollama run llama3.2:3b hi ; docker exec nexus-creator-vault ollama ps"
exit 0
