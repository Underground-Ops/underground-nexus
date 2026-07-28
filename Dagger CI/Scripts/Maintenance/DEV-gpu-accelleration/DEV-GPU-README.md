# DEV-gpu — Master Guide

**Cloud Underground · Underground Nexus · Nexus Creator Vault**
Setup script: `nexus-gpu-setup-for-DEV-gpu.sh` (v2.1.0)

GPU acceleration for the Nexus Creator Vault, on whatever hardware you happen to be sitting at — NVIDIA, AMD, Intel, integrated or discrete, native Linux or WSL2.

---

## TL;DR — the only command you need to remember

```bash
sudo bash nexus-gpu-setup-for-DEV-gpu.sh --provision
```

That detects the GPU, installs the commands, launches the vault, waits for the first-boot Ollama install, installs any driver the chosen path needs, restarts, and prints **ACCELERATED** or **CPU**.

If you remember nothing else on this page, remember that line.

---

## What the script installs

| where | what |
|---|---|
| `/etc/nexus/gpu.env` | the GPU profile (vendor + docker args) |
| `/usr/local/etc/nexus-gpu.env` | the same profile — **this is the one DEV-gpu reads first** |
| `/usr/local/bin/` | `DEV-gpu`, `DEV-rebuild-gpu`, `DEV-restore-gpu` on the host |
| inside `cerberus-manager` | the same three commands, so `DEV-gpu` works from the Cerberus shell too |

Both profiles are written together every run. **Never hand-edit one** — DEV-gpu reads `/usr/local/etc` first and stops there, so editing `/etc/nexus/gpu.env` alone does nothing. Re-run the script instead.

---

## The four commands

| command | launches | pulls a new image | wipes `/config` |
|---|---|---|---|
| `--provision` | yes | no | no |
| `DEV-gpu` | yes | no | no |
| `DEV-restore-gpu` | yes | **yes** | no |
| `DEV-rebuild-gpu` | yes | **yes** | **yes** |

`DEV-rebuild-gpu` asks you to type `REBUILD` before destroying anything. `DEV_YES=1` skips the prompt. `DEV_PURGE_IMAGE=1` also deletes the local image for a true from-scratch pull.

### When to run what

- **First time on a machine** → `--provision`
- **Day to day** → nothing. `docker restart nexus-creator-vault` preserves everything.
- **New vault image, keep my data** → `DEV-restore-gpu`, then `--provision`
- **Clean slate** → `DEV-rebuild-gpu`, then `--provision`
- **It came up on CPU and shouldn't have** → `--provision`
- **Changed GPU hardware** → `--provision`

**The rule:** anything that replaces the container discards driver packages installed inside it, so follow it with `--provision`. On native Linux this rarely matters (see below).

---

## Vendor truth table

| detected | docker args | notes |
|---|---|---|
| `nvidia` | `--gpus all -e OLLAMA_VULKAN=0` | CUDA. Best performance by a wide margin. Works native and under WSL2. Covers eGPUs. Needs compute capability 5.0+ and driver 550+. |
| `amd` | `--device /dev/kfd --device /dev/dri --group-add <gids> -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1` | ROCm first, Vulkan as fallback. Native Linux only. |
| `intel` | `--device /dev/dri/* --group-add <gids> -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1` | Mesa ANV, conformant, already in the vault image. No extra packages. |
| `dxg` | `--device /dev/dxg -v /usr/lib/wsl:/usr/lib/wsl:ro -e LD_LIBRARY_PATH=/usr/lib/wsl/lib -e OLLAMA_VULKAN=1 -e OLLAMA_IGPU_ENABLE=1` | WSL2 + Mesa Dozen. **Experimental.** Auto-selected on WSL when there's no NVIDIA. |
| `cpu` | none | Small models still run fine. |

### Why `OLLAMA_IGPU_ENABLE=1` matters

**Ollama silently discards integrated GPUs by default.** It will find your iGPU, log `dropping integrated GPU`, and fall back to CPU with no visible error. Every integrated path sets this flag. It is deliberately *not* set on the NVIDIA path, so a weak companion iGPU can't get pulled in alongside a good CUDA card.

### What does *not* work, and why

- **ROCm under WSL2** — impossible. WSL2 exposes no `/dev/kfd`. Boot native Linux.
- **Apple Metal** — unreachable from a Linux container. macOS/Lima is CPU-only by design.
- **NPUs** — Ollama doesn't use them. WSL3's DirectML NPU passthrough doesn't change that.

---

## Environment variables

| variable | effect |
|---|---|
| `NEXUS_WSL_DXG=0` | **off switch** for the WSL Dozen route. Forces CPU. (It's ON by default.) |
| `NEXUS_GPU_VENDOR=` | force `nvidia` / `amd` / `intel` / `dxg` / `cpu` |
| `NEXUS_GPU_VULKAN=1` | keep Vulkan enabled alongside CUDA on an NVIDIA box |
| `HSA_OVERRIDE_GFX_VERSION=` | AMD cards outside ROCm's target list, e.g. `10.3.0` |
| `DEV_GPU=` | one-off override at launch: `DEV_GPU=cpu DEV-gpu` |
| `DEV_KEEP=1` | refuse to replace a running vault |
| `DEV_YES=1` | skip the typed `REBUILD` confirmation |
| `DEV_PURGE_IMAGE=1` | delete the local image before pulling |
| `GGML_VK_VISIBLE_DEVICES=` | pick a specific Vulkan device on mixed-GPU systems |

### Flags

| flag | effect |
|---|---|
| `--provision` | the full chain: launch → wait → install → restart → verdict |
| `--dry-run` | detect and report only, change nothing |
| `--verify` | re-run the container GPU proof and exit |
| `--help` | print the header |

---

## WSL2 specifics

Under WSL2 there is no `/dev/dri` — only `/dev/dxg`. A non-NVIDIA GPU is reachable only through Mesa's **Dozen** driver (Vulkan on top of Direct3D 12).

Two things make this awkward, and `--provision` handles both:

1. **Ubuntu's `mesa-vulkan-drivers` deliberately ships without Dozen.** It's built only with the `microsoft-experimental` option, which distro packages omit. `--provision` installs it from `ppa:kisak/kisak-mesa` when the `dxg` path is selected.
2. **The Dozen install lives in the container's writable layer**, so it dies with any container replacement. That's the WSL tax — re-run `--provision` after any `DEV-*` command.

Caveats worth knowing:

- Dozen reports `conformanceVersion = 0.0.0.0` and announces itself as "testing use only."
- There are open upstream `/dev/dxg` sync hangs on Intel Arc under WSL2. If a model loads, offloads layers, and then stalls before the first token, that's the bug — set `NEXUS_WSL_DXG=0` and move on.
- The path sets `LD_LIBRARY_PATH=/usr/lib/wsl/lib` for every process in the container. If the KDE desktop or audio starts misbehaving, this is the first suspect.

**Native Linux has none of this.** `/dev/dri` exists, the script auto-detects `intel` or `amd`, the conformant Mesa ANV driver is already in the vault image, and plain `DEV-gpu` is self-sufficient. If you have the choice, use native.

---

## Verifying it worked

`--provision` prints the verdict for you. To check by hand:

```bash
docker exec nexus-creator-vault ollama ps          # PROCESSOR should not read 100% CPU
docker logs nexus-creator-vault 2>&1 | grep "inference compute" | tail -1
```

What you want to see:

```
inference compute id=0 library=Vulkan name=Vulkan0
  description="Microsoft Direct3D12 (Intel(R) Graphics)"
  libdirs=ollama,vulkan type=iGPU
```

`library=cpu` means it's not accelerated.

To inspect the Vulkan stack directly (no display, so no surface errors):

```bash
docker exec -e DISPLAY= -e XDG_RUNTIME_DIR=/tmp nexus-creator-vault \
  vulkaninfo --summary 2>&1 | grep -iE 'devicename|driverName'
```

---

## Troubleshooting

| symptom | cause | fix |
|---|---|---|
| `accelerator args: none (CPU mode)` when you expect a GPU | profile says `vendor=cpu` | re-run the setup script; check the `effective accelerator args:` line it prints |
| Profile edit had no effect | `/usr/local/etc/nexus-gpu.env` shadows `/etc/nexus/gpu.env` | never hand-edit; re-run the script, which writes both |
| `dropping integrated GPU; to enable, set OLLAMA_IGPU_ENABLE=1` | Ollama's default iGPU policy | you're on an old profile — re-run the setup script |
| `llama-server binary not found` | first-boot Ollama install was interrupted | `docker exec nexus-creator-vault sh -c 'curl -fsSL https://ollama.com/install.sh \| sh'` then `docker restart`. Or just `--provision`. |
| `ollama: executable file not found in $PATH` | first boot hasn't finished | wait — `docker exec nexus-creator-vault test -x /usr/local/lib/ollama/llama-server` |
| `no DRI render node - only /dev/dxg` | normal on WSL2 | expected; the `dxg` path handles it |
| `XCB failed to connect to the X server` from vulkaninfo | it's trying to create a display surface | irrelevant to compute; add `-e DISPLAY= -e XDG_RUNTIME_DIR=/tmp` |
| `dzn is not a conformant Vulkan implementation` | Dozen's own banner | informational — it means Dozen **loaded** |
| `libcuda.so.1: cannot open shared object file` | no NVIDIA card present | harmless noise |
| Model loads, offloads layers, then never produces a token | upstream `/dev/dxg` sync hang | `NEXUS_WSL_DXG=0` and re-provision |
| Desktop or audio broke after enabling `dxg` | `LD_LIBRARY_PATH` affects every process | `NEXUS_WSL_DXG=0` and re-provision |
| `unable to find group render` at launch | shouldn't happen — the script emits numeric GIDs | report it |

---

## What persists, what doesn't

**Survives reboots and restarts:** both profiles, the host commands, the Cerberus injection, and everything in `/config` (models, settings, desktop state).

**Dies when the container is replaced:** anything `apt install`ed inside it — the Dozen ICD, manual Ollama repairs. This is why `--provision` exists.

**Dies only with `DEV-rebuild-gpu`:** the `creator-vault0` volume — your models and all of `/config`.

---

## Known limits

- The Dozen route is experimental and non-conformant. Treat it as a lab capability, not a product promise.
- iGPU acceleration is real but modest. Integrated graphics share system RAM and are bandwidth-bound. Clearly better than CPU, nowhere near a discrete card.
- `--provision` does not pull a new image. Use `DEV-restore-gpu` or `DEV-rebuild-gpu` for that, then `--provision`.

## Fixes owed to the vault image

Two problems live in the vault Dockerfile rather than in this script, and patching containers won't cure them:

1. **`OLLAMA_IGPU_ENABLE=1` belongs in the s6 ollama run script.** Not WSL-specific — every Intel iGPU and AMD APU hits the same silent drop.
2. **The first-boot Ollama installer needs a completion marker.** Its idempotency check tests `command -v ollama`, which goes true early in extraction. A restart mid-install leaves a half-installed Ollama that reports present, passes the health check, and fails only at inference. The check should test `/usr/local/lib/ollama/llama-server`, and `zz-nexus-health` should check it too.

The kisak PPA should **not** go into the image. It's a WSL-only workaround for a non-conformant driver, and native Linux already ships the conformant one.

---

*Cloud Underground · cloud-underground.com*
