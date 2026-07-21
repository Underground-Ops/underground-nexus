#!/usr/bin/env bash
# =============================================================================
# NEXUS0.SH v6.2 — Pure Package Installer + Runtime Hook Writer
# Cloud Underground · Underground Nexus
# =============================================================================
#
# v6.2 CHANGES from v6.1 (bare-metal agnosticism audit):
#   Audited every container-ism against a bare-metal run; the gates held
#   (qemu.conf cgroup fix, STEP 16 s6/cont-init writes: all container-only;
#   bare metal creates the abc operator, grants groups, configures SDDM,
#   enables libvirtd — the appliance design). Closed the real gaps:
#   - STEP 12 group set now includes video+render (GPU/virtio-gpu access).
#   - BARE METAL: SUDO_USER (the human who ran sudo) is also added to
#     kvm/libvirt/video/render so virt-manager works from their own session,
#     not only abc's. Container-skipped; root skipped.
#   - Bare-metal else now enables libvirtd+virtlogd+ollama via systemd
#     (--now, best-effort) — distro-native parity with the container's s6
#     units. Device perms stay udev-native on bare metal by design: group
#     membership is the mechanism there, never chmod-fighting udev.
#   - ${ABC_HOME} used consistently (was one hardcoded /home/abc in cleanup).
#
# v6.1 CHANGES from v5.9 (hypervisor cgroups-v2 fix + SR-IOV/device polish):
#   STEP 5 — CGROUPS-V2 CONTAINER FIX (the qcow "unable to open
#     /sys/fs/cgroup/machine/... No such file or directory" launch failure):
#     writes cgroup_controllers=[] + cgroup_manager="cgroupfs" into
#     /etc/libvirt/qemu.conf. CONTAINER-GATED (CONTAINER_MODE only) — a
#     bare-metal run NEVER touches the host's libvirt config; bare metal has
#     systemd, its machine slice exists, normal placement stays enabled.
#     Also ships an explicit cgroup_device_acl (kvm/tun/vhost/vfio/udmabuf/
#     renderD128) — inert while controllers=[] but authoritative if an
#     operator re-enables the devices controller later.
#   STEP 5 — ACCELERATION EXTRAS (guarded, non-fatal, runs everywhere):
#     qemu-system-gui + libvirglrenderer1 (virtio-gpu GL / VirGL guest
#     acceleration), swtpm + swtpm-tools (TPM 2.0 VMs — Win11 etc.).
#   STEP 16 cont-init 01-kvm-permissions (container-only) — now the full
#     VM device-enablement pass at every boot: re-asserts the qemu.conf fix
#     (mounted-volume shadowing), /dev/kvm perms, /dev/net/tun + vhost-net/
#     vhost-vsock perms (virtio-net acceleration), /dev/vfio/* perms for
#     SR-IOV/PCI passthrough, /dev/udmabuf, libvirt-qemu+abc group
#     membership, IOMMU-group detection with /run/nexus-vfio-tier marker
#     (1-vfio-ready | 2-vfio-partial | 3-no-vfio + host-kernel hints),
#     SR-IOV NIC VF count report, hugepages report. Detection never fails
#     the boot; everything || true.
#   STEP 16 s6 ollama run — additive Golden-Twin serve tuning
#     (OLLAMA_HOST loopback, KEEP_ALIVE=15m, MAX_LOADED_MODELS=2, models
#     dir pinned to installer default). Install path UNCHANGED (the
#     Dockerfile's first-boot runtime installer owns it); still runs as
#     root exactly like the proven v5.x deploy; idle-guard preserved.
#
# v5.9 CHANGES from v5.8:
#   STEP 5B added: Sovereign Hypervisor branding
#     - Installs SovereignHypervisor as a NAMED GTK3 theme at build time
#       (/usr/share/themes/SovereignHypervisor/gtk-3.0/gtk.css)
#     - Sets gtk-theme-name=SovereignHypervisor system-wide so KDE Breeze-GTK
#       is bypassed entirely — our CSS loads at cascade position 2 (the theme slot)
#     - Sets GTK_THEME=SovereignHypervisor in /etc/profile.d/ (nuclear override)
#     - Patches virt-manager desktop entry, Python/UI files, about dialog
#     - Installs CU hexagon icons at 8 sizes (fetches from repo, inline fallback)
#     - Installs KDE Plasma SovereignHypervisor.colors scheme
#   STEP 16 (cont-init hook): adds runtime GTK settings activation
#     - Writes /config/.config/gtk-3.0/settings.ini after /config is created
#     - Writes /config/.xprofile with GTK_THEME=SovereignHypervisor
#
# v5.4 KEY CHANGE:
#   STEP 16 uses printf only — NO heredocs. BuildKit-compatible.
#   Dockerfile contains no heredoc syntax.
#
# What this script does NOT do:
#   - No background daemons during build
#   - No /config writes (doesn't exist until container start)
#   - No appinator
#
# Runtime flow:
#   Container start → /init → PUID/PGID → /config created
#   → /custom-cont-init.d/01-nexus-setup.sh (Desktop, /nexus-bucket, KVM, GTK theme)
#   → s6 services: libvirtd, virtlogd, ollama
#   → KasmVNC → KDE Plasma at :3000
# =============================================================================

set -o pipefail

NX_LOG="/tmp/nexus0-install.log"
mkdir -p /tmp

log()  { echo "[nexus0] $*" | tee -a "${NX_LOG}"; }
ok()   { echo "[nexus0] ✓ $*" | tee -a "${NX_LOG}"; }
warn() { echo "[nexus0] ⚠ $*" | tee -a "${NX_LOG}"; }
err()  { echo "[nexus0] ✗ $*" | tee -a "${NX_LOG}" >&2; }

log "═══════════════════════════════════════════════════"
log "nexus0.sh v6.2 — Pure Package Installer"
log "Started: $(date)"
log "═══════════════════════════════════════════════════"

ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
case "${ARCH}" in
    amd64|x86_64)  ARCH="amd64" ;;
    arm64|aarch64) ARCH="arm64" ;;
    *)             warn "Unknown arch '${ARCH}' — defaulting to amd64"; ARCH="amd64" ;;
esac
log "Architecture: ${ARCH}"

CONTAINER_MODE=false
LINUXSERVER_MODE=false

[ -f /.dockerenv ] && { CONTAINER_MODE=true; log "/.dockerenv → CONTAINER MODE"; }
grep -q 'container=' /proc/1/environ 2>/dev/null && { CONTAINER_MODE=true; log "PID1 environ → CONTAINER MODE"; }

if [ -d /run/s6 ] || [ -d /etc/s6-overlay ] || grep -q 'linuxserver' /etc/os-release 2>/dev/null; then
    LINUXSERVER_MODE=true
    log "s6-overlay → LINUXSERVER MODE"
fi

if [ "${LINUXSERVER_MODE}" = "true" ] && [ "${CONTAINER_MODE}" = "false" ]; then
    CONTAINER_MODE=true
    log "v5.4: LINUXSERVER detected → forcing CONTAINER_MODE=true"
fi

[ "${CONTAINER_MODE}" = "false" ] && log "No container markers → BARE METAL"

ABC_HOME=$( [ "${LINUXSERVER_MODE}" = "true" ] && echo "/config" || echo "/home/abc" )
log "abc home: ${ABC_HOME} (RUNTIME only in linuxserver mode)"

export DEBIAN_FRONTEND=noninteractive

retry() {
    local ATTEMPTS="$1"; shift; local DELAY="$1"; shift; local TRY=1
    while [ "${TRY}" -le "${ATTEMPTS}" ]; do
        "$@" && return 0
        warn "Attempt ${TRY}/${ATTEMPTS} failed: $*"
        TRY=$((TRY + 1)); [ "${TRY}" -le "${ATTEMPTS}" ] && sleep "${DELAY}"
    done
    err "All ${ATTEMPTS} attempts failed: $*"; return 1
}

clear_dpkg_errors() {
    dpkg --configure --force-confold -a 2>/dev/null || true
    apt-get install -f -y 2>/dev/null || true
}

# =============================================================================
# STEP 0: PRE-FLIGHT — NAME_REGEX fix
# =============================================================================

log "STEP 0: Pre-flight — NAME_REGEX fix"

if [ -f /etc/adduser.conf ]; then
    sed -i '/^NAME_REGEX/d' /etc/adduser.conf 2>/dev/null || true
    echo 'NAME_REGEX="^[a-z_][-a-z0-9_]*\$?"' >> /etc/adduser.conf
else
    echo 'NAME_REGEX="^[a-z_][-a-z0-9_]*\$?"' > /etc/adduser.conf
fi

! getent group '_crd_network' >/dev/null 2>&1 && \
    addgroup --system '_crd_network' 2>/dev/null || true
! id '_crd_network' >/dev/null 2>&1 && \
    adduser --system --ingroup '_crd_network' --no-create-home '_crd_network' 2>/dev/null || true

ok "Pre-flight complete"

# =============================================================================
# STEP 1: BASE PACKAGES
# =============================================================================

log "STEP 1: Base packages"

retry 3 5 apt-get update -qq

retry 3 5 apt-get install -y \
    ssh wget curl nano git \
    ca-certificates apt-transport-https gnupg \
    zstd xz-utils software-properties-common \
    iputils-ping lsb-release \
    || warn "Some base packages failed"

ok "Base packages installed"

# =============================================================================
# STEP 2: CHROME REMOTE DESKTOP
# =============================================================================

log "STEP 2: Chrome Remote Desktop"

if [ "${ARCH}" = "amd64" ]; then
    apt-get install -y --no-install-recommends \
        xvfb x11-xserver-utils xbase-clients \
        python3 python3-packaging python3-xdg psmisc xdg-utils \
        2>/dev/null || true

    if dpkg -l chrome-remote-desktop 2>/dev/null | grep -q "^ii"; then
        ok "Chrome Remote Desktop already installed — skipping"
    else
        CRD_DEB="/tmp/chrome-remote-desktop_current_amd64.deb"
        retry 3 10 wget -q --timeout=60 \
            "https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb" \
            -O "${CRD_DEB}" && ok "CRD downloaded" || warn "CRD download failed"

        if [ -f "${CRD_DEB}" ] && [ -s "${CRD_DEB}" ]; then
            dpkg --force-bad-name --force-depends --force-confold -i "${CRD_DEB}" 2>/dev/null || true
            apt-get install -f -y 2>/dev/null || true
            dpkg --configure --force-confold -a 2>/dev/null || true
            apt-get install -f -y 2>/dev/null || true
            if dpkg -l chrome-remote-desktop 2>/dev/null | grep -q "^iF"; then
                warn "CRD postinst failed — purging"
                dpkg --purge --force-all chrome-remote-desktop 2>/dev/null || true
                clear_dpkg_errors
            else
                ok "Chrome Remote Desktop installed"
            fi
            rm -f "${CRD_DEB}"
        fi
    fi
else
    warn "Chrome Remote Desktop: arm64 not supported — skipped"
fi

# =============================================================================
# STEP 3: GITHUB DESKTOP
# =============================================================================

log "STEP 3: GitHub Desktop"

GH_DESKTOP_OK=false

retry 2 5 bash -c '
    wget -qO - https://apt.packages.shiftkey.dev/gpg.key 2>/dev/null \
        | gpg --dearmor | tee /usr/share/keyrings/shiftkey-packages.gpg > /dev/null \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/shiftkey-packages.gpg] https://apt.packages.shiftkey.dev/ubuntu/ any main" \
        > /etc/apt/sources.list.d/shiftkey-packages.list \
    && apt-get update -qq && apt-get install -y github-desktop
' && GH_DESKTOP_OK=true && ok "GitHub Desktop via shiftkey APT" || true

if [ "${GH_DESKTOP_OK}" = "false" ] && [ "${ARCH}" = "amd64" ]; then
    for GH_VER in "3.4.3-linux1" "3.3.9-linux1" "3.3.8-linux1"; do
        GH_URL="https://github.com/shiftkey/desktop/releases/download/release-${GH_VER}/GitHubDesktop-linux-amd64-${GH_VER}.deb"
        wget -q --timeout=60 "${GH_URL}" -O /tmp/github-desktop.deb 2>/dev/null \
            && [ -s /tmp/github-desktop.deb ] \
            && dpkg --force-bad-name --force-depends -i /tmp/github-desktop.deb 2>/dev/null \
            && clear_dpkg_errors \
            && GH_DESKTOP_OK=true && ok "GitHub Desktop v${GH_VER}" && break \
            || warn "GH Desktop ${GH_VER} failed"
        rm -f /tmp/github-desktop.deb
    done
fi

[ "${GH_DESKTOP_OK}" = "false" ] && warn "GitHub Desktop not installed (non-fatal)"

# =============================================================================
# STEP 4: GITKRAKEN
# =============================================================================

log "STEP 4: GitKraken"

if [ "${ARCH}" = "amd64" ]; then
    retry 3 8 wget -q --timeout=60 \
        "https://release.gitkraken.com/linux/gitkraken-amd64.deb" \
        -O /tmp/gitkraken-amd64.deb && ok "GitKraken downloaded" || warn "GitKraken failed"
    if [ -f /tmp/gitkraken-amd64.deb ] && [ -s /tmp/gitkraken-amd64.deb ]; then
        dpkg -i /tmp/gitkraken-amd64.deb 2>/dev/null || true
        clear_dpkg_errors; ok "GitKraken installed"
        rm -f /tmp/gitkraken-amd64.deb
    fi
fi

# =============================================================================
# STEP 5: KVM / QEMU / VIRT-MANAGER — PACKAGES ONLY
# =============================================================================

log "STEP 5: KVM + QEMU + virt-manager (packages only)"

apt-get install -y \
    qemu-kvm qemu-system qemu-system-x86 cpu-checker \
    virt-manager libvirt-daemon-system libvirt-clients \
    bridge-utils ovmf 2>/dev/null || \
apt-get install -y \
    qemu-system-x86 qemu-system cpu-checker \
    virt-manager libvirt-daemon-system libvirt-clients \
    bridge-utils ovmf 2>/dev/null || \
warn "KVM/QEMU install had errors"

# v6.1 — acceleration extras (guarded; each independently non-fatal).
#   qemu-system-gui + libvirglrenderer1 → virtio-gpu GL (VirGL) so guests can
#     use accelerated virtual graphics when the vault has a GPU tier.
#   swtpm + swtpm-tools → TPM 2.0 emulation for modern guests (Win11 needs it).
# Runs on bare metal too — these are standard virt-stack packages there.
apt-get install -y qemu-system-gui libvirglrenderer1 2>/dev/null \
    && ok "VirGL guest-GL stack installed (qemu-system-gui + libvirglrenderer1)" \
    || warn "VirGL extras not installed (non-fatal — guests fall back to non-GL virtio-gpu)"
apt-get install -y swtpm swtpm-tools 2>/dev/null \
    && ok "swtpm installed (TPM 2.0 guests supported)" \
    || warn "swtpm not installed (non-fatal — TPM-requiring guests unavailable)"

clear_dpkg_errors
usermod -aG kvm abc 2>/dev/null || true
usermod -aG libvirt abc 2>/dev/null || true

# -----------------------------------------------------------------------------
# CGROUPS-V2 IN A CONTAINER — the "unable to open
#   /sys/fs/cgroup/machine/qemu-N-<name>.libvirt-qemu/: No such file or
#   directory" fix.
#
# WHY THIS IS NEEDED (and why it appeared without any Dockerfile change):
#   On a host running cgroups v2 with a NON-systemd init inside the container
#   (this webtop base uses s6, not systemd), libvirt tries to place each QEMU
#   domain in /sys/fs/cgroup/machine/qemu-<id>-<name>.libvirt-qemu/ — but in a
#   private cgroup namespace nothing creates that "machine" path, so
#   virDomainCreateXML() fails before the VM ever starts. This is the exact
#   scenario documented for Cirrus CI / podman-cgroupsv2 (see the libvirt
#   cgroups doc). It surfaces now because the HOST moved to cgroups v2, not
#   because the image regressed — the image never configured this.
#
# THE FIX: tell libvirt not to use cgroup CONTROLLERS it cannot place here.
#   Setting cgroup_controllers = [] means QEMU domains are launched WITHOUT
#   libvirt trying to create/manage the machine cgroup dir. VMs run normally;
#   only libvirt's optional per-domain resource-controller placement is
#   skipped (fine for a dev/creator vault — you're not doing per-VM CPU quota
#   partitioning inside the container).
#
# BARE-METAL SAFETY (critical): this build-time write only lands the setting
#   inside THIS image. The RUNTIME re-assert (STEP 16 cont-init) is gilded
#   with a container-only guard, so a bare-metal nexus0 run NEVER edits a
#   host's /etc/libvirt/qemu.conf. On bare metal systemd creates the machine
#   slice and libvirt's normal cgroup placement works — we must not disable it
#   there, and we don't.
# -----------------------------------------------------------------------------
if [ "${CONTAINER_MODE}" = "true" ] && [ -f /etc/libvirt/qemu.conf ]; then
    if ! grep -q '^cgroup_controllers' /etc/libvirt/qemu.conf 2>/dev/null; then
        printf '\n# Nexus: cgroups-v2-in-container fix — no machine cgroup dir to place into.\ncgroup_controllers = [ ]\n' \
            >> /etc/libvirt/qemu.conf
        log "  [cgroup-fix] cgroup_controllers=[] written to qemu.conf (container cgroups-v2)"
    else
        log "  [cgroup-fix] cgroup_controllers already set — left as-is"
    fi
    # A private cgroup namespace also makes the systemd/machined placement
    # unavailable; forcing the session (non-systemd) cgroup layout avoids
    # libvirt reaching for machined. Harmless in the container; only applied
    # in CONTAINER_MODE so bare metal keeps its systemd layout.
    if ! grep -q '^cgroup_manager' /etc/libvirt/qemu.conf 2>/dev/null; then
        printf 'cgroup_manager = "cgroupfs"\n' >> /etc/libvirt/qemu.conf
        log "  [cgroup-fix] cgroup_manager=cgroupfs (avoids machined in container)"
    fi
    # v6.1 — explicit device ACL. With cgroup_controllers=[] the devices
    # controller is OFF, so this list is INERT today (filesystem perms are
    # the only gate — the cont-init below sets those). It is written anyway
    # so that if an operator ever re-enables controllers, passthrough
    # (SR-IOV VFIO), vhost-net acceleration, TUN networking, virtio-gpu
    # render nodes and udmabuf keep working instead of silently breaking.
    if ! grep -q '^cgroup_device_acl' /etc/libvirt/qemu.conf 2>/dev/null; then
        printf 'cgroup_device_acl = [\n    "/dev/null", "/dev/full", "/dev/zero",\n    "/dev/random", "/dev/urandom",\n    "/dev/ptmx", "/dev/kvm",\n    "/dev/rtc", "/dev/hpet",\n    "/dev/net/tun", "/dev/vhost-net", "/dev/vhost-vsock",\n    "/dev/vfio/vfio", "/dev/udmabuf",\n    "/dev/dri/renderD128"\n]\n' >> /etc/libvirt/qemu.conf
        log "  [cgroup-fix] cgroup_device_acl written (SR-IOV/vhost/tun/GL ready if controllers re-enabled)"
    fi
fi

[ -e /dev/kvm ] && VIRT_TIER="1-kvm" || VIRT_TIER="2-tcg"
log "  KVM tier at build: ${VIRT_TIER}"
ok "KVM/QEMU packages installed"

# =============================================================================
# STEP 5B: SOVEREIGN HYPERVISOR — virt-manager Branding (Build Time)
#
# Runs immediately after STEP 5 installs virt-manager.
# Root context during build: /usr/share/ is fully writable.
# Installs the SovereignHypervisor GTK3 named theme — this is the only approach
# that works reliably in KDE Plasma Wayland, where Breeze-GTK is the default
# and would otherwise override /etc/gtk-3.0/gtk.css rules.
#
# Build-time actions (no /config writes — /config doesn't exist yet):
#   1. Fetch Cloud Underground logo (3 URLs → inline SVG fallback)
#   2. Install librsvg2-bin, imagemagick if not present
#   3. Generate PNG icons at 8 sizes via rsvg-convert
#   4. Install /usr/share/themes/SovereignHypervisor/gtk-3.0/gtk.css (named theme)
#   5. Set /etc/gtk-3.0/settings.ini → gtk-theme-name=SovereignHypervisor
#   6. Patch virt-manager .desktop, Python/UI files, About dialog
#   7. Install KDE Plasma color scheme
#
# Runtime actions (written into STEP 16 cont-init hook, runs after /config exists):
#   - /config/.config/gtk-3.0/settings.ini → gtk-theme-name=SovereignHypervisor
#   - /config/.xprofile → export GTK_THEME=SovereignHypervisor
# =============================================================================

log "STEP 5B: Sovereign Hypervisor branding"

# --- Dependencies ---
apt-get install -y -qq librsvg2-bin imagemagick 2>/dev/null || true

# --- Logo acquisition ---
SH_ASSET_DIR="/tmp/sovereign-brand-assets"
mkdir -p "${SH_ASSET_DIR}"
SVG_LOGO="${SH_ASSET_DIR}/cu-logo.svg"
PNG_LOGO="${SH_ASSET_DIR}/cu-logo.png"
LOGO_FOUND=false

for URL in \
    "https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Production%20Artifacts/Wordpress/nexus-creator-vault/images/CU-Logo.svg" \
    "https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Branding/CU-Logo.svg" \
    "https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/branding/cu-logo.svg"; do
    wget -q --timeout=15 "${URL}" -O "${SVG_LOGO}" 2>/dev/null && [ -s "${SVG_LOGO}" ] && \
        LOGO_FOUND=true && ok "SVG logo: ${URL}" && break || true
done

if [ "${LOGO_FOUND}" = "false" ]; then
    for URL in \
        "https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Production%20Artifacts/Wordpress/nexus-creator-vault/images/CU-Logo.png" \
        "https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Branding/CU-Logo.png"; do
        wget -q --timeout=15 "${URL}" -O "${PNG_LOGO}" 2>/dev/null && [ -s "${PNG_LOGO}" ] && \
            LOGO_FOUND=true && ok "PNG logo: ${URL}" && break || true
    done
fi

if [ "${LOGO_FOUND}" = "false" ]; then
    warn "Remote logo unavailable — generating inline CU mark"
    printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">\n' > "${SVG_LOGO}"
    printf '  <rect width="512" height="512" rx="64" fill="#0b1021"/>\n' >> "${SVG_LOGO}"
    printf '  <polygon points="256,40 440,152 440,360 256,472 72,360 72,152" fill="none" stroke="#00e5cc" stroke-width="16" stroke-linejoin="round"/>\n' >> "${SVG_LOGO}"
    printf '  <polygon points="256,96 400,176 400,336 256,416 112,336 112,176" fill="#060913" stroke="#00e5cc" stroke-width="8" stroke-linejoin="round"/>\n' >> "${SVG_LOGO}"
    printf '  <text x="256" y="300" font-family="Courier New,monospace" font-size="160" font-weight="700" text-anchor="middle" fill="#ffffff" letter-spacing="-8">CU</text>\n' >> "${SVG_LOGO}"
    printf '  <rect x="160" y="420" width="192" height="8" rx="4" fill="#ffb300"/>\n' >> "${SVG_LOGO}"
    printf '</svg>\n' >> "${SVG_LOGO}"
    LOGO_FOUND=true
    ok "Inline CU SVG mark generated"
fi

# --- Icon generation ---
ICON_BASE_DIR="/usr/share/icons/hicolor"
_gen_png() {
    local SIZE="$1" OUT="$2"
    mkdir -p "$(dirname "${OUT}")"
    command -v rsvg-convert >/dev/null 2>&1 && [ -f "${SVG_LOGO}" ] && \
        rsvg-convert -w "${SIZE}" -h "${SIZE}" "${SVG_LOGO}" -o "${OUT}" 2>/dev/null && return 0
    command -v convert >/dev/null 2>&1 && [ -f "${SVG_LOGO}" ] && \
        convert -background none -size "${SIZE}x${SIZE}" "${SVG_LOGO}" "${OUT}" 2>/dev/null && return 0
    command -v convert >/dev/null 2>&1 && [ -f "${PNG_LOGO}" ] && \
        convert -resize "${SIZE}x${SIZE}" "${PNG_LOGO}" "${OUT}" 2>/dev/null && return 0
    [ -f "${PNG_LOGO}" ] && cp "${PNG_LOGO}" "${OUT}" 2>/dev/null && return 0
    return 1
}

for SZ in 16 24 32 48 64 128 256 512; do
    _gen_png "${SZ}" "${ICON_BASE_DIR}/${SZ}x${SZ}/apps/virt-manager.png" \
        && log "  icon ${SZ}px ✓" || warn "  icon ${SZ}px failed"
done
_gen_png 256 "/usr/share/pixmaps/virt-manager.png" || true

if [ -f "${SVG_LOGO}" ]; then
    mkdir -p "${ICON_BASE_DIR}/scalable/apps"
    cp "${ICON_BASE_DIR}/scalable/apps/virt-manager.svg" \
       "${ICON_BASE_DIR}/scalable/apps/virt-manager.svg.bak" 2>/dev/null || true
    cp "${SVG_LOGO}" "${ICON_BASE_DIR}/scalable/apps/virt-manager.svg" 2>/dev/null || true
fi
ok "Icons installed (8 sizes)"

# --- Named GTK3 theme ---
SH_THEME_DIR="/usr/share/themes/SovereignHypervisor/gtk-3.0"
mkdir -p "${SH_THEME_DIR}"

printf '[Desktop Entry]\nType=X-GNOME-Metatheme\nName=SovereignHypervisor\nComment=Cloud Underground Sovereign Hypervisor Dark Theme\nEncoding=UTF-8\n\n[X-GNOME-Metatheme]\nGtkTheme=SovereignHypervisor\nMetacityTheme=SovereignHypervisor\nIconTheme=hicolor\nCursorTheme=default\nButtonLayout=close,minimize,maximize:\n' \
    > "/usr/share/themes/SovereignHypervisor/index.theme"

# Write the full GTK3 CSS using printf (no heredoc — BuildKit compatible)
GTK_CSS="${SH_THEME_DIR}/gtk.css"
printf '/* Sovereign Hypervisor GTK3 Theme — Cloud Underground\n' > "${GTK_CSS}"
printf '   Named theme: loads at cascade position 2, before KDE Breeze-GTK.\n' >> "${GTK_CSS}"
printf '   Brand palette: navy #0b1021, cyan #00e5cc, chartreuse #c6ef3b, amber #ffb300 */\n\n' >> "${GTK_CSS}"

# Global reset
printf '* { -gtk-icon-style: regular; outline-color: #00e5cc; }\n' >> "${GTK_CSS}"

# Base window + labels
printf 'window, .background { background-color: #0b1021; color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'label.dim-label, label.secondary { color: #c8d6e5; }\n\n' >> "${GTK_CSS}"

# Header bar
printf 'headerbar, headerbar.titlebar, .titlebar { background-color: #060913; border-bottom: 2px solid #00e5cc; padding: 4px 8px; color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'headerbar label, .titlebar label { color: #ffffff; font-weight: 700; }\n' >> "${GTK_CSS}"
printf 'headerbar .title { color: #ffffff; font-weight: 700; font-size: 13px; }\n' >> "${GTK_CSS}"
printf 'headerbar .subtitle { color: #c8d6e5; font-size: 11px; }\n\n' >> "${GTK_CSS}"

# Toolbar
printf 'toolbar, .toolbar { background-color: #0d1529; border-bottom: 1px solid #1e2d4a; padding: 2px; }\n' >> "${GTK_CSS}"
printf 'toolbar image, toolbar button image, .toolbar image, .toolbar button image, toolbutton image, toolbutton > button > image { color: #ffffff; -gtk-icon-style: regular; }\n' >> "${GTK_CSS}"
printf 'toolbar button, .toolbar button, toolbutton > button { background-color: #1a2540; color: #ffffff; border: 1px solid #1e2d4a; border-radius: 4px; padding: 4px 6px; min-width: 28px; min-height: 28px; box-shadow: none; }\n' >> "${GTK_CSS}"
printf 'toolbar button:hover, toolbutton > button:hover { background-color: #00e5cc; color: #0b1021; border-color: #00e5cc; }\n' >> "${GTK_CSS}"
printf 'toolbar button:hover image { color: #0b1021; }\n\n' >> "${GTK_CSS}"

# Sidebar / treeview
printf 'list, .sidebar, treeview, .view { background-color: #0d1529; color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'treeview:selected, list row:selected, .view:selected { background-color: #00e5cc; color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'treeview:selected label { color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'treeview header button, treeview header { background-color: #060913; color: #c8d6e5; border-bottom: 1px solid #1e2d4a; }\n' >> "${GTK_CSS}"
printf 'treeview header button label { color: #c8d6e5; }\n\n' >> "${GTK_CSS}"

# BUTTONS — the full authoritative block (no !important needed — we ARE the theme)
printf '/* --- BUTTONS --- */\n' >> "${GTK_CSS}"
printf 'button { background-color: #1a2540; color: #ffffff; border: 1px solid #00e5cc; border-radius: 6px; padding: 5px 12px; font-size: 12px; box-shadow: none; text-shadow: none; }\n' >> "${GTK_CSS}"
printf 'button label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'button image { color: #ffffff; -gtk-icon-style: regular; }\n' >> "${GTK_CSS}"
printf 'button:hover { background-color: #00e5cc; color: #0b1021; border-color: #00e5cc; }\n' >> "${GTK_CSS}"
printf 'button:hover label { color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'button:hover image { color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'button:active { background-color: #009e8e; color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'button:focus { outline: 2px solid #c6ef3b; outline-offset: 2px; box-shadow: none; }\n' >> "${GTK_CSS}"
printf 'button:disabled { background-color: #0d1529; color: #4a5568; border-color: #2d3748; opacity: 0.55; }\n' >> "${GTK_CSS}"
printf 'button:disabled label, button:disabled image { color: #4a5568; }\n' >> "${GTK_CSS}"
printf 'button.flat { background-color: #1a2540; color: #ffffff; border: 1px solid #1e2d4a; border-radius: 6px; box-shadow: none; }\n' >> "${GTK_CSS}"
printf 'button.flat label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'button.flat image { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'button.flat:hover { background-color: #00e5cc; color: #0b1021; border-color: #00e5cc; }\n' >> "${GTK_CSS}"
printf 'button.flat:hover label { color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'button.flat:hover image { color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'button.image-button { background-color: #1a2540; border: 1px solid #1e2d4a; border-radius: 6px; padding: 4px 6px; min-width: 28px; min-height: 28px; }\n' >> "${GTK_CSS}"
printf 'button.image-button image { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'button.image-button:hover { background-color: #00e5cc; border-color: #00e5cc; }\n' >> "${GTK_CSS}"
printf 'button.image-button:hover image { color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'button.destructive-action { background-color: #2d0a0a; color: #ff4757; border-color: #ff4757; }\n' >> "${GTK_CSS}"
printf 'button.destructive-action label { color: #ff4757; }\n' >> "${GTK_CSS}"
printf 'button.destructive-action image { color: #ff4757; }\n' >> "${GTK_CSS}"
printf 'button.destructive-action:hover { background-color: #ff4757; color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'button.destructive-action:hover label, button.destructive-action:hover image { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'button.suggested-action { background-color: #003d35; color: #00e5cc; border: 2px solid #00e5cc; }\n' >> "${GTK_CSS}"
printf 'button.suggested-action label { color: #00e5cc; }\n' >> "${GTK_CSS}"
printf 'button.suggested-action:hover { background-color: #00e5cc; color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'button.suggested-action:hover label { color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'button.circular { background-color: #1a2540; border: 1px solid #00e5cc; border-radius: 50%%; padding: 4px; min-width: 28px; min-height: 28px; }\n' >> "${GTK_CSS}"
printf 'button.circular image { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'button.circular:hover { background-color: #00e5cc; }\n' >> "${GTK_CSS}"
printf 'button.circular:hover image { color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'button.link { background: transparent; border: none; color: #00e5cc; box-shadow: none; padding: 2px 4px; }\n' >> "${GTK_CSS}"
printf 'button.link label { color: #00e5cc; }\n' >> "${GTK_CSS}"
printf 'button.link:hover { color: #c6ef3b; }\n' >> "${GTK_CSS}"
printf 'button.link:hover label { color: #c6ef3b; }\n\n' >> "${GTK_CSS}"

# Linked button groups
printf '.linked > button { background-color: #1a2540; color: #ffffff; border: 1px solid #1e2d4a; border-radius: 0; padding: 4px 8px; box-shadow: none; }\n' >> "${GTK_CSS}"
printf '.linked > button + button { border-left: none; }\n' >> "${GTK_CSS}"
printf '.linked > button:first-child { border-radius: 6px 0 0 6px; }\n' >> "${GTK_CSS}"
printf '.linked > button:last-child { border-radius: 0 6px 6px 0; }\n' >> "${GTK_CSS}"
printf '.linked > button:only-child { border-radius: 6px; }\n' >> "${GTK_CSS}"
printf '.linked > button label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf '.linked > button image { color: #ffffff; }\n' >> "${GTK_CSS}"
printf '.linked > button:hover { background-color: #00e5cc; color: #0b1021; border-color: #00e5cc; }\n' >> "${GTK_CSS}"
printf '.linked > button:hover label, .linked > button:hover image { color: #0b1021; }\n' >> "${GTK_CSS}"
printf '.linked > button.destructive-action { background-color: #2d0a0a; border-color: #ff4757; }\n' >> "${GTK_CSS}"
printf '.linked > button.destructive-action image { color: #ff4757; }\n' >> "${GTK_CSS}"
printf '.linked > button.destructive-action:hover { background-color: #ff4757; }\n' >> "${GTK_CSS}"
printf '.linked > button.destructive-action:hover image { color: #ffffff; }\n\n' >> "${GTK_CSS}"

# Actionbar
printf 'actionbar { background-color: #0b1021; border-top: 1px solid #1e2d4a; padding: 4px 8px; }\n' >> "${GTK_CSS}"
printf 'actionbar > revealer > box, actionbar > box { background-color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'actionbar button { background-color: #1a2540; color: #ffffff; border: 1px solid #00e5cc; border-radius: 6px; min-width: 32px; min-height: 32px; padding: 4px 8px; box-shadow: none; }\n' >> "${GTK_CSS}"
printf 'actionbar button label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'actionbar button image { color: #ffffff; -gtk-icon-style: regular; }\n' >> "${GTK_CSS}"
printf 'actionbar button:hover { background-color: #00e5cc; color: #0b1021; border-color: #00e5cc; }\n' >> "${GTK_CSS}"
printf 'actionbar button:hover image, actionbar button:hover label { color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'actionbar button.destructive-action { background-color: #2d0a0a; color: #ff4757; border-color: #ff4757; }\n' >> "${GTK_CSS}"
printf 'actionbar button.destructive-action image { color: #ff4757; }\n' >> "${GTK_CSS}"
printf 'actionbar button.destructive-action:hover { background-color: #ff4757; color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'actionbar button.destructive-action:hover image { color: #ffffff; }\n\n' >> "${GTK_CSS}"

# Dialog action area
printf '.dialog-action-area, .dialog-action-box { background-color: #060913; border-top: 1px solid #1e2d4a; padding: 8px 12px; }\n' >> "${GTK_CSS}"
printf '.dialog-action-area > button, dialog > box > box > button { background-color: #1a2540; color: #ffffff; border: 1px solid #00e5cc; border-radius: 6px; padding: 6px 18px; min-height: 32px; box-shadow: none; }\n' >> "${GTK_CSS}"
printf '.dialog-action-area > button label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf '.dialog-action-area > button image { color: #ffffff; }\n' >> "${GTK_CSS}"
printf '.dialog-action-area > button:hover { background-color: #00e5cc; color: #0b1021; }\n' >> "${GTK_CSS}"
printf '.dialog-action-area > button:hover label { color: #0b1021; }\n' >> "${GTK_CSS}"
printf '.dialog-action-area > button.suggested-action { background-color: #003d35; color: #00e5cc; border: 2px solid #00e5cc; }\n' >> "${GTK_CSS}"
printf '.dialog-action-area > button.suggested-action label { color: #00e5cc; }\n' >> "${GTK_CSS}"
printf '.dialog-action-area > button.suggested-action:hover { background-color: #00e5cc; color: #0b1021; }\n' >> "${GTK_CSS}"
printf '.dialog-action-area > button.destructive-action { background-color: #2d0a0a; color: #ff4757; border-color: #ff4757; }\n\n' >> "${GTK_CSS}"

# Menu bar
printf 'menubar { background-color: #060913; color: #c8d6e5; border-bottom: 1px solid #1e2d4a; }\n' >> "${GTK_CSS}"
printf 'menubar label { color: #c8d6e5; }\n' >> "${GTK_CSS}"
printf 'menubar > menuitem:hover { background-color: #1a2540; color: #00e5cc; }\n' >> "${GTK_CSS}"
printf 'menubar > menuitem:hover label { color: #00e5cc; }\n' >> "${GTK_CSS}"
printf 'menu { background-color: #0d1529; color: #ffffff; border: 1px solid #1e2d4a; box-shadow: 0 4px 16px rgba(0,0,0,0.7); }\n' >> "${GTK_CSS}"
printf 'menuitem { padding: 4px 12px; color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'menuitem label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'menuitem:hover, menuitem:selected { background-color: #00e5cc; color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'menuitem:hover label, menuitem:selected label { color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'menuitem:disabled { color: #4a5568; }\n' >> "${GTK_CSS}"
printf 'separator { background-color: #1e2d4a; min-height: 1px; margin: 2px 8px; }\n\n' >> "${GTK_CSS}"

# Notebook / tabs
printf 'notebook { background-color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'notebook > header { background-color: #0d1529; border-bottom: 1px solid #1e2d4a; }\n' >> "${GTK_CSS}"
printf 'notebook tab { background-color: #0d1529; border: 1px solid #1e2d4a; border-bottom: none; padding: 6px 14px; margin: 0 1px; }\n' >> "${GTK_CSS}"
printf 'notebook tab label { color: #c8d6e5; font-size: 12px; }\n' >> "${GTK_CSS}"
printf 'notebook tab:checked { background-color: #0b1021; border-color: #00e5cc; border-bottom: 2px solid #00e5cc; }\n' >> "${GTK_CSS}"
printf 'notebook tab:checked label { color: #00e5cc; font-weight: 600; }\n' >> "${GTK_CSS}"
printf 'notebook tab:hover { background-color: #1a2540; }\n' >> "${GTK_CSS}"
printf 'notebook tab:hover label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'notebook stack, notebook > stack { background-color: #0b1021; }\n\n' >> "${GTK_CSS}"

# Stackswitcher (Details/XML sub-tabs)
printf 'stackswitcher { background-color: #0d1529; border: 1px solid #1e2d4a; border-radius: 4px; padding: 2px; }\n' >> "${GTK_CSS}"
printf 'stackswitcher button { background-color: transparent; color: #c8d6e5; border: none; border-radius: 3px; padding: 4px 14px; }\n' >> "${GTK_CSS}"
printf 'stackswitcher button label { color: #c8d6e5; }\n' >> "${GTK_CSS}"
printf 'stackswitcher button:checked, stackswitcher button.active { background-color: #00e5cc; color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'stackswitcher button:checked label, stackswitcher button.active label { color: #0b1021; font-weight: 600; }\n' >> "${GTK_CSS}"
printf 'stackswitcher button:hover { background-color: #1a2540; }\n' >> "${GTK_CSS}"
printf 'stackswitcher button:hover label { color: #ffffff; }\n\n' >> "${GTK_CSS}"

# Entries
printf 'entry, spinbutton entry, combobox entry { background-color: #1a2540; color: #ffffff; border: 1px solid #1e2d4a; border-radius: 4px; padding: 4px 8px; caret-color: #00e5cc; box-shadow: none; }\n' >> "${GTK_CSS}"
printf 'entry:focus { border-color: #00e5cc; box-shadow: 0 0 0 1px #00e5cc; }\n' >> "${GTK_CSS}"
printf 'entry:disabled { background-color: #0d1529; color: #4a5568; }\n' >> "${GTK_CSS}"
printf 'combobox button { background-color: #1a2540; border: 1px solid #1e2d4a; border-radius: 4px; color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'combobox button label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'combobox button:hover { border-color: #00e5cc; }\n\n' >> "${GTK_CSS}"

# Textview, scrollbars, containers, frames, checkbuttons
printf 'textview, textview text { background-color: #0d1529; color: #e2e8f0; font-family: monospace; font-size: 12px; }\n' >> "${GTK_CSS}"
printf 'textview text selection { background-color: #00e5cc; color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'scrollbar { background-color: #0d1529; min-width: 8px; }\n' >> "${GTK_CSS}"
printf 'scrollbar trough { background-color: #0d1529; border-radius: 4px; }\n' >> "${GTK_CSS}"
printf 'scrollbar slider { background-color: #2d3748; border-radius: 4px; min-width: 6px; min-height: 24px; margin: 2px; }\n' >> "${GTK_CSS}"
printf 'scrollbar slider:hover { background-color: #00e5cc; }\n' >> "${GTK_CSS}"
printf 'scrolledwindow, scrolledwindow > widget, scrolledwindow > viewport { background-color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'viewport { background-color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'grid { background-color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'grid label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'box { background-color: transparent; }\n' >> "${GTK_CSS}"
printf 'box label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'frame { border: 1px solid #1e2d4a; border-radius: 4px; padding: 8px; }\n' >> "${GTK_CSS}"
printf 'frame > label { color: #00e5cc; font-weight: 600; background-color: #0b1021; padding: 0 4px; }\n' >> "${GTK_CSS}"
printf 'checkbutton { background-color: transparent; padding: 4px; }\n' >> "${GTK_CSS}"
printf 'checkbutton label { color: #ffffff; font-size: 13px; }\n' >> "${GTK_CSS}"
printf 'checkbutton check { background-color: #1a2540; border: 1px solid #4a5568; border-radius: 3px; min-width: 16px; min-height: 16px; }\n' >> "${GTK_CSS}"
printf 'checkbutton check:checked { background-color: #00e5cc; border-color: #00e5cc; }\n' >> "${GTK_CSS}"
printf 'checkbutton:focus { outline: 2px solid #c6ef3b; outline-offset: 2px; }\n' >> "${GTK_CSS}"
printf 'radiobutton { background-color: transparent; padding: 4px; }\n' >> "${GTK_CSS}"
printf 'radiobutton label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'radiobutton radio { background-color: #1a2540; border: 1px solid #4a5568; border-radius: 50%%; }\n' >> "${GTK_CSS}"
printf 'radiobutton radio:checked { background-color: #00e5cc; border-color: #00e5cc; }\n' >> "${GTK_CSS}"
printf 'progressbar trough { background-color: #0d1529; border: 1px solid #1e2d4a; border-radius: 4px; min-height: 8px; }\n' >> "${GTK_CSS}"
printf 'progressbar progress { background-color: #00e5cc; border-radius: 4px; }\n' >> "${GTK_CSS}"
printf 'flowbox, flowboxchild { background-color: #0d1529; color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'flowboxchild label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'flowboxchild:selected { background-color: #00e5cc; color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'flowboxchild:selected label { color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'row { background-color: #0d1529; color: #ffffff; padding: 4px 8px; border-bottom: 1px solid #1e2d4a; }\n' >> "${GTK_CSS}"
printf 'row label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'row:selected { background-color: #00e5cc; color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'row:selected label { color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'row:hover { background-color: #1a2540; }\n' >> "${GTK_CSS}"
printf 'image { color: #c8d6e5; -gtk-icon-style: regular; }\n' >> "${GTK_CSS}"
printf 'tooltip, .tooltip { background-color: #1a2540; color: #ffffff; border: 1px solid #00e5cc; border-radius: 4px; padding: 4px 8px; }\n' >> "${GTK_CSS}"
printf 'tooltip label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf '.success { color: #00e5cc; } .warning { color: #ffb300; } .error { color: #ff4757; }\n' >> "${GTK_CSS}"
printf '.vm-status-running { color: #00e5cc; } .vm-status-shutoff { color: #718096; } .vm-status-error { color: #ff4757; } .vm-status-paused { color: #ffb300; }\n' >> "${GTK_CSS}"
printf 'paned separator { background-color: #1e2d4a; min-width: 4px; min-height: 4px; }\n' >> "${GTK_CSS}"
printf 'paned separator:hover { background-color: #00e5cc; }\n' >> "${GTK_CSS}"
printf 'popover, popover.background { background-color: #0d1529; border: 1px solid #1e2d4a; border-radius: 6px; box-shadow: 0 8px 24px rgba(0,0,0,0.8); }\n' >> "${GTK_CSS}"
printf 'popover label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'dialog { background-color: #0b1021; }\n' >> "${GTK_CSS}"
printf 'dialog label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf '.about-dialog label { color: #ffffff; }\n' >> "${GTK_CSS}"
printf 'scale trough { background-color: #1e2d4a; border-radius: 4px; min-height: 4px; }\n' >> "${GTK_CSS}"
printf 'scale highlight, scale progress { background-color: #00e5cc; border-radius: 4px; }\n' >> "${GTK_CSS}"
printf 'scale slider { background-color: #00e5cc; border-radius: 50%%; min-width: 16px; min-height: 16px; border: 2px solid #0b1021; }\n' >> "${GTK_CSS}"
printf 'scale slider:hover { background-color: #c6ef3b; }\n' >> "${GTK_CSS}"

ok "Named GTK3 theme CSS written: ${SH_THEME_DIR}/gtk.css"

# --- System-wide GTK settings (activates the named theme) ---
mkdir -p /etc/gtk-3.0
printf '[Settings]\ngtk-theme-name=SovereignHypervisor\ngtk-application-prefer-dark-theme=1\ngtk-icon-theme-name=hicolor\ngtk-cursor-theme-name=default\ngtk-font-name=Ubuntu 11\ngtk-button-images=1\ngtk-menu-images=1\ngtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ\n' \
    > /etc/gtk-3.0/settings.ini

# Also write the CSS to /etc for belt-and-suspenders
cp "${GTK_CSS}" /etc/gtk-3.0/gtk.css 2>/dev/null || true

# --- GTK_THEME environment variable (nuclear option — /etc/profile.d) ---
printf '#!/bin/sh\nexport GTK_THEME=SovereignHypervisor\n' \
    > /etc/profile.d/sovereign-gtk-theme.sh
chmod +x /etc/profile.d/sovereign-gtk-theme.sh

# --- KDE Plasma color scheme ---
mkdir -p /usr/share/color-schemes
printf '[ColorEffects:Disabled]\nColor=100,110,130\nColorAmount=0.55\nColorEffect=3\nContrastAmount=0.65\nContrastEffect=1\nIntensityAmount=0.1\nIntensityEffect=2\n\n' \
    > /usr/share/color-schemes/SovereignHypervisor.colors
printf '[Colors:Button]\nBackgroundNormal=26,37,64\nDecorationFocus=0,229,204\nDecorationHover=0,229,204\nForegroundNormal=255,255,255\nForegroundNegative=255,71,87\nForegroundNeutral=255,179,0\nForegroundPositive=0,229,204\n\n' \
    >> /usr/share/color-schemes/SovereignHypervisor.colors
printf '[Colors:Selection]\nBackgroundNormal=0,229,204\nForegroundNormal=11,16,33\n\n' \
    >> /usr/share/color-schemes/SovereignHypervisor.colors
printf '[Colors:View]\nBackgroundNormal=11,16,33\nBackgroundAlternate=13,21,41\nDecorationFocus=0,229,204\nForegroundNormal=255,255,255\nForegroundNegative=255,71,87\nForegroundNeutral=255,179,0\nForegroundPositive=0,229,204\n\n' \
    >> /usr/share/color-schemes/SovereignHypervisor.colors
printf '[Colors:Window]\nBackgroundNormal=11,16,33\nBackgroundAlternate=13,21,41\nDecorationFocus=0,229,204\nForegroundNormal=255,255,255\n\n' \
    >> /usr/share/color-schemes/SovereignHypervisor.colors
printf '[General]\nColorScheme=SovereignHypervisor\nName=Sovereign Hypervisor\nshadeSortColumn=true\n\n[KDE]\ncontrast=4\n' \
    >> /usr/share/color-schemes/SovereignHypervisor.colors

# --- Patch virt-manager .desktop entry (via /tmp to avoid sed permission issue) ---
DESK_SRC="/usr/share/applications/virt-manager.desktop"
if [ -f "${DESK_SRC}" ]; then
    cp "${DESK_SRC}" "${DESK_SRC}.bak" 2>/dev/null || true
    DESK_TMP=$(mktemp /tmp/sovereign-desk.XXXXXX)
    cp "${DESK_SRC}" "${DESK_TMP}"
    sed -i 's/^Name=.*/Name=Sovereign Hypervisor/g'               "${DESK_TMP}"
    sed -i '/^Name\[/d'                                             "${DESK_TMP}"
    sed -i 's/^GenericName=.*/GenericName=Sovereign Hypervisor/g' "${DESK_TMP}"
    sed -i 's/^Comment=.*/Comment=Sovereign Exocortex KVM Engine — Cloud Underground/g' "${DESK_TMP}"
    sed -i '/^Comment\[/d'                                          "${DESK_TMP}"
    cp "${DESK_TMP}" "${DESK_SRC}" 2>/dev/null || true
    rm -f "${DESK_TMP}"
    ok "Desktop entry: Sovereign Hypervisor"
fi

# --- Patch Python/UI files (skip .pyc binary files) ---
_patch_file() {
    local FILE="$1"; shift
    [ -f "${FILE}" ] || { warn "Not found: ${FILE}"; return; }
    case "${FILE}" in *.pyc) return ;; esac
    [ -f "${FILE}.bak" ] || cp "${FILE}" "${FILE}.bak" 2>/dev/null || true
    local TMP; TMP=$(mktemp /tmp/sovereign-patch.XXXXXX)
    cp "${FILE}" "${TMP}"
    while [ $# -ge 2 ]; do
        sed -i "s|${1}|${2}|g" "${TMP}" 2>/dev/null || true; shift 2
    done
    cp "${TMP}" "${FILE}" 2>/dev/null && ok "Patched: ${FILE}" || warn "Write failed: ${FILE}"
    rm -f "${TMP}"
}

_patch_file "/usr/share/virt-manager/ui/about.ui" \
    "Virtual Machine Manager" "Sovereign Hypervisor" \
    "Powered by libvirt" "Powered by Sovereign dRAG" \
    "Red Hat" "Cloud Underground"
_patch_file "/usr/share/virt-manager/ui/manager.ui" \
    "Virtual Machine Manager" "Sovereign Hypervisor"
_patch_file "/usr/share/virt-manager/virtManager/engine.py" \
    "Virtual Machine Manager" "Sovereign Hypervisor"
_patch_file "/usr/share/virt-manager/virtManager/virtmanager.py" \
    "Virtual Machine Manager" "Sovereign Hypervisor"
_patch_file "/usr/share/virt-manager/virtManager/systray.py" \
    "Virtual Machine Manager" "Sovereign Hypervisor"
_patch_file "/usr/share/virt-manager/virtManager/lib/connectauth.py" \
    "Virtual Machine Manager" "Sovereign Hypervisor"

# Sweep any remaining files (excluding .pyc)
grep -rl "Virtual Machine Manager" /usr/share/virt-manager/ 2>/dev/null \
    | grep -v '\.pyc$' | while read -r F; do
    TMP_SW=$(mktemp /tmp/sovereign-sweep.XXXXXX)
    cp "${F}" "${TMP_SW}"
    sed -i 's/Virtual Machine Manager/Sovereign Hypervisor/g' "${TMP_SW}" 2>/dev/null || true
    cp "${TMP_SW}" "${F}" 2>/dev/null || true
    rm -f "${TMP_SW}"
done

# Refresh icon cache
command -v gtk-update-icon-cache >/dev/null 2>&1 && \
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
command -v update-desktop-database >/dev/null 2>&1 && \
    update-desktop-database /usr/share/applications 2>/dev/null || true

ok "Sovereign Hypervisor branding complete"
ok "  Theme: /usr/share/themes/SovereignHypervisor/gtk-3.0/gtk.css"
ok "  GTK:   gtk-theme-name=SovereignHypervisor in /etc/gtk-3.0/settings.ini"
ok "  Env:   GTK_THEME=SovereignHypervisor in /etc/profile.d/"
ok "  Runtime /config activation → written in STEP 16 cont-init hook"

# =============================================================================
# STEP 6: OLLAMA
# =============================================================================

log "STEP 6: Ollama (installed — s6 service starts it at runtime)"

command -v ollama >/dev/null 2>&1 && ok "Ollama already installed" || \
    retry 3 10 bash -c 'curl -fsSL https://ollama.com/install.sh | sh' \
        && ok "Ollama installed" \
        || warn "Ollama install failed"

clear_dpkg_errors
ok "Ollama ready (s6 starts at container boot → localhost:11434)"

# =============================================================================
# STEP 7: CREATIVE SUITE
# =============================================================================

log "STEP 7: Creative Suite"

retry 3 5 apt-get install -y libreoffice && ok "LibreOffice" || warn "LibreOffice failed"
clear_dpkg_errors

add-apt-repository -y ppa:obsproject/obs-studio 2>/dev/null || true
apt-get update -qq 2>/dev/null || true
retry 3 5 apt-get install -y obs-studio && ok "OBS Studio" || warn "OBS Studio failed"
clear_dpkg_errors

retry 3 5 apt-get install -y blender && ok "Blender" \
    || { snap install blender --classic 2>/dev/null && ok "Blender via snap" || warn "Blender failed"; }
clear_dpkg_errors

retry 3 5 apt-get install -y inkscape gimp audacity kdenlive \
    && ok "Inkscape, GIMP, Audacity, Kdenlive" || warn "Some creative tools failed"
clear_dpkg_errors
ok "Creative suite complete"

# =============================================================================
# STEP 8: VISUAL STUDIO CODE — 4-method fallback
# =============================================================================

log "STEP 8: Visual Studio Code"

if command -v code >/dev/null 2>&1; then
    ok "VS Code already installed"
else
    VSCODE_OK=false

    if [ "${VSCODE_OK}" = "false" ]; then
        wget -qO- --timeout=30 https://packages.microsoft.com/keys/microsoft.asc \
                | gpg --dearmor > /tmp/packages.microsoft.gpg 2>/dev/null \
            && install -o root -g root -m 644 /tmp/packages.microsoft.gpg \
                /etc/apt/trusted.gpg.d/ \
            && sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list' \
            && apt-get update -qq 2>/dev/null \
            && apt-get install -y code \
            && VSCODE_OK=true && ok "VS Code via Microsoft APT" \
            || warn "Microsoft APT failed"
        rm -f /tmp/packages.microsoft.gpg
    fi

    if [ "${VSCODE_OK}" = "false" ]; then
        curl -fsSL --retry 3 https://packages.microsoft.com/keys/microsoft.asc \
                | gpg --dearmor > /etc/apt/trusted.gpg.d/packages.microsoft.gpg 2>/dev/null \
            && echo "deb [arch=amd64,arm64,armhf] https://packages.microsoft.com/repos/vscode stable main" \
                > /etc/apt/sources.list.d/vscode.list \
            && apt-get update -qq 2>/dev/null \
            && apt-get install -y code \
            && VSCODE_OK=true && ok "VS Code via curl key" \
            || warn "curl key failed"
    fi

    if [ "${VSCODE_OK}" = "false" ]; then
        retry 2 5 wget -q --timeout=60 \
            "https://raw.githubusercontent.com/Underground-Ops/underground-nexus/refs/heads/main/visual-studio-code.sh" \
            -O /tmp/vscode-install.sh \
            && DEBIAN_FRONTEND=noninteractive bash /tmp/vscode-install.sh \
            && VSCODE_OK=true && ok "VS Code via GitHub script" \
            || warn "GitHub script failed"
        rm -f /tmp/vscode-install.sh
    fi

    if [ "${VSCODE_OK}" = "false" ] && [ "${ARCH}" = "amd64" ]; then
        curl -fsSL --retry 3 --max-time 120 \
            -o /tmp/vscode.deb \
            "https://update.code.visualstudio.com/latest/linux-deb-x64/stable" 2>/dev/null \
            && [ -s /tmp/vscode.deb ] \
            && dpkg -i /tmp/vscode.deb 2>/dev/null && clear_dpkg_errors \
            && VSCODE_OK=true && ok "VS Code via direct .deb" \
            || warn "Direct .deb failed"
        rm -f /tmp/vscode.deb
    fi

    [ "${VSCODE_OK}" = "false" ] && warn "VS Code: all methods failed (non-fatal)"
fi

clear_dpkg_errors

# =============================================================================
# STEP 9: DESKTOP APPLICATIONS
# =============================================================================

log "STEP 9: Desktop apps"

retry 3 5 apt-get install -y terminator firefox gdebi \
    || warn "Some desktop apps failed"
clear_dpkg_errors
ok "Desktop apps installed"

# =============================================================================
# STEP 10: DEVSECOPS CLI TOOLS
# =============================================================================

log "STEP 10: DevSecOps CLI tools"

command -v dagger >/dev/null 2>&1 || \
    retry 2 5 bash -c 'curl -fsSL https://dl.dagger.io/dagger/install.sh | BIN_DIR=/usr/local/bin sh' \
        && ok "Dagger CI" || warn "Dagger failed"

if ! command -v zarf >/dev/null 2>&1; then
    ZARF_VER=$(curl -sIX HEAD https://github.com/zarf-dev/zarf/releases/latest \
        | grep -i '^location:' | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+' 2>/dev/null || echo "")
    [ -n "${ZARF_VER}" ] && retry 3 5 curl -sL \
        "https://github.com/zarf-dev/zarf/releases/download/${ZARF_VER}/zarf_${ZARF_VER}_Linux_${ARCH}" \
        -o /usr/local/bin/zarf && chmod +x /usr/local/bin/zarf \
        && ok "Zarf ${ZARF_VER}" || warn "Zarf failed"
fi

if ! command -v k9s >/dev/null 2>&1; then
    K9S_VER=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest \
        | grep '"tag_name"' | cut -d'"' -f4 2>/dev/null || echo "")
    [ -n "${K9S_VER}" ] && retry 3 5 curl -sL \
        "https://github.com/derailed/k9s/releases/download/${K9S_VER}/k9s_Linux_${ARCH}.tar.gz" \
        | tar -xz -C /usr/local/bin k9s 2>/dev/null \
        && ok "K9s ${K9S_VER}" || warn "K9s failed"
fi

command -v lazydocker >/dev/null 2>&1 || \
    retry 3 5 curl -fsSL \
        https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh \
        | DIR=/usr/local/bin bash 2>/dev/null \
        && ok "Lazydocker" || warn "Lazydocker failed"

ok "DevSecOps CLI tools complete"

# =============================================================================
# STEP 11: SSH
# =============================================================================

log "STEP 11: SSH"
mkdir -p /var/run/sshd
service ssh enable 2>/dev/null || true
service ssh start 2>/dev/null || systemctl enable --now ssh 2>/dev/null || true
ok "SSH configured"

# =============================================================================
# STEP 12: USER SETUP
# =============================================================================

log "STEP 12: User abc"

if [ "${LINUXSERVER_MODE}" = "true" ]; then
    log "Linuxserver: abc UID set at runtime via -e PUID=1000 -e PGID=1000"
else
    if ! id -u abc >/dev/null 2>&1; then
        useradd -m -u 1000 -d "${ABC_HOME}" -s /bin/bash abc 2>/dev/null \
            && ok "User abc created" || warn "useradd failed"
    fi
    mkdir -p "${ABC_HOME}"
fi

for GRP in sudo docker kvm libvirt video render; do
    getent group "${GRP}" >/dev/null 2>&1 && usermod -aG "${GRP}" abc 2>/dev/null || true
done

# v6.2 — BARE METAL: the human who ran `sudo bash nexus0.sh` also gets the
# virt groups, so virt-manager works from THEIR session too, not only abc's.
# Container-skipped (SUDO_USER is meaningless there); root itself skipped.
if [ "${CONTAINER_MODE}" = "false" ] && [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    for GRP in kvm libvirt video render; do
        getent group "${GRP}" >/dev/null 2>&1 && usermod -aG "${GRP}" "${SUDO_USER}" 2>/dev/null || true
    done
    ok "Bare metal: ${SUDO_USER} added to kvm/libvirt/video/render (virt-manager from your own session)"
fi

echo "abc:sovereign" | chpasswd 2>/dev/null || true
ok "Password: sovereign"

grep -q "abc ALL=(ALL) NOPASSWD: ALL" /etc/sudoers 2>/dev/null || \
    echo "abc ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
grep -q "www-data ALL=(ALL) NOPASSWD: ALL" /etc/sudoers 2>/dev/null || \
    echo "www-data ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
ok "Sudoers configured"

# =============================================================================
# STEP 13: /nexus-bucket
# =============================================================================

log "STEP 13: /nexus-bucket"

mkdir -p /nexus-bucket
id abc >/dev/null 2>&1 && chown -R abc:abc /nexus-bucket || \
    chown -R 1000:1000 /nexus-bucket 2>/dev/null || true

if [ ! -d "/nexus-bucket/underground-nexus/.git" ]; then
    retry 3 10 git clone --depth=1 \
        https://github.com/Underground-Ops/underground-nexus.git \
        /nexus-bucket/underground-nexus \
        && ok "Underground Nexus repo cloned" \
        || warn "Clone failed — runtime init will retry"
else
    git -C /nexus-bucket/underground-nexus pull --rebase 2>/dev/null || true
    ok "Repo updated"
fi

id abc >/dev/null 2>&1 && chown -R abc:abc /nexus-bucket 2>/dev/null || \
    chown -R 1000:1000 /nexus-bucket 2>/dev/null || true

# =============================================================================
# STEP 14: WALLPAPERS
# =============================================================================

log "STEP 14: Wallpapers"

WALLPAPER_BASE="https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Wallpapers"

install_wallpapers() {
    local DIR="$1"
    mkdir -p "${DIR}" && cd "${DIR}" || return

    retry 3 5 wget -q --timeout=60 "${WALLPAPER_BASE}/nexus0-sea-space-jelly-highres.jpg" \
        -O "1440x900.jpg" && ok "Highres wallpaper → ${DIR}" || warn "Highres failed"
    [ -f "1440x900.jpg" ] && for SIZE in 1280x800 1366x768 1600x1200 1680x1050 1920x1080 1920x1200 2560x1440; do
        cp "1440x900.jpg" "${SIZE}.jpg" 2>/dev/null || true; done

    retry 3 5 wget -q --timeout=60 "${WALLPAPER_BASE}/nexus0-sea-space-jelly.jpg" \
        -O "1280x1024.jpg" && ok "Standard wallpaper → ${DIR}" || warn "Standard failed"
    [ -f "1280x1024.jpg" ] && cp "1280x1024.jpg" "1024x768.jpg" 2>/dev/null || true

    retry 3 5 wget -q --timeout=60 "${WALLPAPER_BASE}/nexus0-moon-jelly.jpg" \
        -O "1080x1920.jpg" && ok "Portrait wallpaper → ${DIR}" || warn "Portrait failed"
    [ -f "1080x1920.jpg" ] && for SIZE in 360x720 720x1440 1440x2560 2160x3840 1440x2960 5120x2880 7680x2160; do
        cp "1080x1920.jpg" "${SIZE}.jpg" 2>/dev/null || true; done

    rm -f ./*.svg ./*.png 2>/dev/null || true
    cd / || true
}

install_wallpapers "/usr/share/wallpapers/KubuntuLight/contents/images"
install_wallpapers "/usr/share/wallpapers/Next/contents/images"
install_wallpapers "/usr/share/wallpapers/Next/contents/images_dark"

ok "Wallpapers installed"

# =============================================================================
# STEP 15: CONTROL PANEL HTML
# =============================================================================

log "STEP 15: Control panel HTML"

retry 3 5 wget -q --timeout=60 \
    "https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Production%20Artifacts/Wordpress/nexus-creator-vault/nexus-creator-vault-control-panel.html" \
    -O /nexus-creator-vault-control-panel.html \
    && ok "Control panel downloaded" \
    || warn "Control panel download failed"

# =============================================================================
# STEP 16: S6 SERVICE DEFINITIONS + /custom-cont-init.d RUNTIME HOOK
#
# v5.9: Runtime hook now also activates the SovereignHypervisor GTK theme
#   by writing /config/.config/gtk-3.0/settings.ini and /config/.xprofile
#   AFTER /config is created by the linuxserver /init sequence.
# =============================================================================

log "STEP 16: s6 service definitions + runtime hook"

if [ "${CONTAINER_MODE}" = "true" ]; then

    log "CONTAINER MODE — writing s6 services and cont-init hook"

    mkdir -p /etc/s6-overlay/s6-rc.d /etc/s6-overlay/cont-init.d /custom-cont-init.d

    # --- s6: libvirtd ---
    mkdir -p /etc/s6-overlay/s6-rc.d/libvirtd
    printf '#!/usr/bin/with-contenv bash\n[ -x /usr/sbin/libvirtd ] || { echo "[s6-libvirtd] not found"; exit 0; }\nexec /usr/sbin/libvirtd\n' \
        > /etc/s6-overlay/s6-rc.d/libvirtd/run
    printf 'longrun\n' > /etc/s6-overlay/s6-rc.d/libvirtd/type
    ok "s6 service: libvirtd"

    # --- s6: virtlogd ---
    mkdir -p /etc/s6-overlay/s6-rc.d/virtlogd
    printf '#!/usr/bin/with-contenv bash\n[ -x /usr/sbin/virtlogd ] || { echo "[s6-virtlogd] not found"; exit 0; }\nexec /usr/sbin/virtlogd\n' \
        > /etc/s6-overlay/s6-rc.d/virtlogd/run
    printf 'longrun\n' > /etc/s6-overlay/s6-rc.d/virtlogd/type
    ok "s6 service: virtlogd"

    # --- s6: ollama ---
    mkdir -p /etc/s6-overlay/s6-rc.d/ollama
    # Ollama s6 run-script. INSTALL mechanism is unchanged (the Dockerfile's
    # v6.5 runtime-installer cont-init owns getting the binary — proven: the
    # BuildKit sandbox has no CDN network, so install must happen at first
    # boot). This only adds Golden-Twin-tuned SERVE env, which is safe and
    # improves local-twin behavior:
    #   OLLAMA_HOST=127.0.0.1:11434 — bind loopback (rag-api :8001 expects it)
    #   OLLAMA_KEEP_ALIVE=15m       — keep models resident between twin calls
    #                                 (the twin's Planka/cards path cold-starts
    #                                 otherwise; matches the twin's own tuning)
    #   OLLAMA_MAX_LOADED_MODELS=2  — router + executor resident together, no
    #                                 thrash (the twin runs a 2-model split)
    #   OLLAMA_MODELS respected if the operator set a custom model dir.
    # A missing binary still just idles (the guard below), so a not-yet-
    # installed ollama never crash-loops s6 — the run-script waits for the
    # cont-init installer exactly as before.
    printf '#!/usr/bin/with-contenv bash\n' \
        > /etc/s6-overlay/s6-rc.d/ollama/run
    printf 'OLL=/usr/local/bin/ollama\n' \
        >> /etc/s6-overlay/s6-rc.d/ollama/run
    printf '[ -x "$OLL" ] || OLL="$(command -v ollama 2>/dev/null)"\n' \
        >> /etc/s6-overlay/s6-rc.d/ollama/run
    printf 'if [ -z "$OLL" ] || [ -z "$("$OLL" --version 2>/dev/null)" ]; then echo "[s6-ollama] ollama not installed yet (runtime installer pending) — idling"; exec sleep 30; fi\n' \
        >> /etc/s6-overlay/s6-rc.d/ollama/run
    printf 'export OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:11434}"\n' \
        >> /etc/s6-overlay/s6-rc.d/ollama/run
    printf 'export OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-15m}"\n' \
        >> /etc/s6-overlay/s6-rc.d/ollama/run
    printf 'export OLLAMA_MAX_LOADED_MODELS="${OLLAMA_MAX_LOADED_MODELS:-2}"\n' \
        >> /etc/s6-overlay/s6-rc.d/ollama/run
    # Pin the models dir so pulled models are found regardless of which user
    # the installer/serve runs as. IMPORTANT: serve runs as ROOT here — the
    # SAME as the proven v5.x deployment (the original ran `exec ollama serve`
    # with no setuidgid). We deliberately do NOT switch to the abc user: the
    # official installer creates models under root/its own path, and changing
    # the run-user would strand already-pulled models. Env is additive only.
    printf 'export OLLAMA_MODELS="${OLLAMA_MODELS:-/usr/share/ollama/.ollama/models}"\n' \
        >> /etc/s6-overlay/s6-rc.d/ollama/run
    printf 'mkdir -p "$OLLAMA_MODELS" 2>/dev/null || true\n' \
        >> /etc/s6-overlay/s6-rc.d/ollama/run
    printf 'echo "[s6-ollama] serving on $OLLAMA_HOST (keep_alive=$OLLAMA_KEEP_ALIVE, max_loaded=$OLLAMA_MAX_LOADED_MODELS, models=$OLLAMA_MODELS)"\n' \
        >> /etc/s6-overlay/s6-rc.d/ollama/run
    printf 'exec "$OLL" serve\n' \
        >> /etc/s6-overlay/s6-rc.d/ollama/run
    printf 'longrun\n' > /etc/s6-overlay/s6-rc.d/ollama/type
    ok "s6 service: ollama"

    # --- s6: chrome-remote-desktop (amd64 only) ---
    if [ "${ARCH}" = "amd64" ] && [ -f /opt/google/chrome-remote-desktop/chrome-remote-desktop ]; then
        mkdir -p /etc/s6-overlay/s6-rc.d/chrome-remote-desktop
        printf '#!/usr/bin/with-contenv bash\n[ -f /opt/google/chrome-remote-desktop/chrome-remote-desktop ] || { echo "[s6-crd] binary not found"; exit 0; }\nexec s6-setuidgid abc /opt/google/chrome-remote-desktop/chrome-remote-desktop --start\n' \
            > /etc/s6-overlay/s6-rc.d/chrome-remote-desktop/run
        printf 'longrun\n' > /etc/s6-overlay/s6-rc.d/chrome-remote-desktop/type
        chmod +x /etc/s6-overlay/s6-rc.d/chrome-remote-desktop/run
        ok "s6 service: chrome-remote-desktop"
    else
        warn "CRD s6 service skipped (arm64 or binary not found)"
    fi

    # --- cont-init: KVM permissions + cgroups-v2 hypervisor fix (runtime) ---
    # Re-asserts the qemu.conf cgroup fix at every boot (in case /etc/libvirt
    # is on a mounted volume that shadows the image copy), fixes /dev/kvm and
    # the DRI render nodes the VMs use with -v /dev:/dev, and confirms the
    # tier. This whole file is written ONLY in CONTAINER_MODE (STEP 16 gate),
    # so a bare-metal install never ships it — bare-metal libvirt keeps its
    # systemd cgroup placement untouched.
    printf '#!/usr/bin/with-contenv bash\n' \
        > /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '# Nexus KVM + cgroups-v2 runtime assertion (container only)\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    # cgroups-v2 fix re-assert (idempotent; only appends if missing)
    printf 'if [ -f /etc/libvirt/qemu.conf ]; then\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '  grep -q "^cgroup_controllers" /etc/libvirt/qemu.conf 2>/dev/null || printf "\\ncgroup_controllers = [ ]\\n" >> /etc/libvirt/qemu.conf\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '  grep -q "^cgroup_manager" /etc/libvirt/qemu.conf 2>/dev/null || printf "cgroup_manager = \\"cgroupfs\\"\\n" >> /etc/libvirt/qemu.conf\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '  echo "[kvm-init] libvirt cgroups-v2 container fix asserted"\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf 'fi\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    # /dev/kvm perms
    printf 'if [ -e /dev/kvm ]; then\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '  chown root:kvm /dev/kvm 2>/dev/null || true\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '  chmod 660 /dev/kvm 2>/dev/null || true\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '  usermod -aG kvm abc 2>/dev/null || true\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '  echo "[kvm-init] /dev/kvm ready — hardware acceleration"\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf 'else\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '  echo "[kvm-init] no /dev/kvm — TCG software emulation (VMs still run, slower)"\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf 'fi\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    # v6.1 — qemu runs as libvirt-qemu on Debian/Ubuntu; give it (and abc)
    # the device groups it needs. With -v /dev:/dev the nodes are the host's,
    # and with cgroup_controllers=[] filesystem perms are the ONLY gate.
    printf 'for U in libvirt-qemu abc; do for G in kvm video render; do usermod -aG "$G" "$U" 2>/dev/null || true; done; done\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    # v6.1 — virtio-net acceleration + TAP networking device nodes
    printf 'if [ -e /dev/net/tun ]; then chmod 666 /dev/net/tun 2>/dev/null || true; echo "[kvm-init] /dev/net/tun ready (TAP/bridged networking)"; fi\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf 'for V in /dev/vhost-net /dev/vhost-vsock; do [ -e "$V" ] && { chown root:kvm "$V" 2>/dev/null || true; chmod 660 "$V" 2>/dev/null || true; echo "[kvm-init] $V ready (vhost acceleration)"; }; done\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '[ -e /dev/udmabuf ] && { chown root:kvm /dev/udmabuf 2>/dev/null || true; chmod 660 /dev/udmabuf 2>/dev/null || true; echo "[kvm-init] /dev/udmabuf ready (virtio-gpu blob resources)"; } || true\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    # v6.1 — SR-IOV / VFIO PCI passthrough enablement + tiering.
    # VF creation and vfio-pci binding happen on the HOST; with -v /dev:/dev
    # the /dev/vfio/<group> nodes appear here, and we make them usable.
    printf 'VFIO_TIER="3-no-vfio"\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf 'if ls /dev/vfio/* >/dev/null 2>&1; then\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '  for N in /dev/vfio/*; do chown root:kvm "$N" 2>/dev/null || true; chmod 660 "$N" 2>/dev/null || true; done\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '  GROUPS_N=$(ls /dev/vfio/ 2>/dev/null | grep -c "^[0-9]")\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '  IOMMU_N=$(ls /sys/kernel/iommu_groups/ 2>/dev/null | wc -l)\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '  if [ "${GROUPS_N:-0}" -gt 0 ] && [ "${IOMMU_N:-0}" -gt 0 ]; then\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '    VFIO_TIER="1-vfio-ready"\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '    echo "[kvm-init] VFIO ready: ${GROUPS_N} bound group(s), ${IOMMU_N} IOMMU group(s) — SR-IOV/PCI passthrough available"\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '  else\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '    VFIO_TIER="2-vfio-partial"\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '    echo "[kvm-init] /dev/vfio present but no bound device groups yet — on the HOST: enable IOMMU (intel_iommu=on iommu=pt | amd_iommu=on) and bind the VF/device to vfio-pci"\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '  fi\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf 'else\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf '  echo "[kvm-init] no /dev/vfio — passthrough off (fine unless you want SR-IOV/PCI passthrough; see host hints above)"\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf 'fi\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    printf 'printf "%%s\\n" "$VFIO_TIER" > /run/nexus-vfio-tier 2>/dev/null || true\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    # v6.1 — SR-IOV NIC visibility: report VFs the host has created
    printf 'for SR in /sys/class/net/*/device/sriov_numvfs; do [ -f "$SR" ] && { NIC=$(basename "$(dirname "$(dirname "$SR")")"); NV=$(cat "$SR" 2>/dev/null); [ "${NV:-0}" != "0" ] && echo "[kvm-init] SR-IOV: $NIC exposes $NV VF(s) (host-created; bind to vfio-pci on the host to pass through)"; }; done 2>/dev/null || true\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    # v6.1 — hugepages visibility (host-mounted; qemu falls back to memfd fine)
    printf '[ -d /dev/hugepages ] && echo "[kvm-init] /dev/hugepages present — hugepage-backed guests available" || true\n' \
        >> /etc/s6-overlay/cont-init.d/01-kvm-permissions
    chmod +x /etc/s6-overlay/cont-init.d/01-kvm-permissions

    # -------------------------------------------------------------------------
    # /custom-cont-init.d/01-nexus-setup.sh
    # v5.9 additions marked with [v5.9]
    # -------------------------------------------------------------------------
    printf '#!/usr/bin/with-contenv bash\n' \
        > /custom-cont-init.d/01-nexus-setup.sh
    printf '# Nexus Creator Vault runtime setup v5.9 — runs after /config exists\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'echo "[nexus-init] Nexus Creator Vault v5.9 runtime setup"\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh

    # XDG home directories
    printf 'export HOME=/config\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'export XDG_CONFIG_HOME=/config/.config\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'mkdir -p /config/.config\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'command -v xdg-user-dirs-update >/dev/null 2>&1 && xdg-user-dirs-update --force 2>/dev/null || true\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'for D in Desktop Documents Downloads Music Pictures Public Templates Videos; do mkdir -p "/config/${D}"; done\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'chown -R abc:abc /config/Desktop /config/Documents /config/Downloads /config/Music /config/Pictures /config/Public /config/Templates /config/Videos 2>/dev/null || chown -R 1000:1000 /config/Desktop /config/Documents /config/Downloads /config/Music /config/Pictures /config/Public /config/Templates /config/Videos 2>/dev/null || true\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'echo "[nexus-init] XDG home directories ready"\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh

    # [v5.9] Sovereign Hypervisor GTK theme activation at runtime
    # This runs AFTER /config is created — writes user GTK settings and xprofile
    # so the named theme is active for the abc session in KDE Wayland.
    printf '# [v5.9] Sovereign Hypervisor GTK theme — activate for abc user session\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'mkdir -p /config/.config/gtk-3.0\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'printf "[Settings]\ngtk-theme-name=SovereignHypervisor\ngtk-application-prefer-dark-theme=1\ngtk-icon-theme-name=hicolor\ngtk-cursor-theme-name=default\ngtk-font-name=Ubuntu 11\ngtk-button-images=1\ngtk-menu-images=1\ngtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ\n" > /config/.config/gtk-3.0/settings.ini\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    # Copy theme CSS to user config (loads on top of named theme — belt and suspenders)
    printf '[ -f /usr/share/themes/SovereignHypervisor/gtk-3.0/gtk.css ] && cp /usr/share/themes/SovereignHypervisor/gtk-3.0/gtk.css /config/.config/gtk-3.0/gtk.css 2>/dev/null || true\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    # .xprofile sets GTK_THEME env var before KDE session starts
    printf 'printf "export GTK_THEME=SovereignHypervisor\n" > /config/.xprofile\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'chown -R abc:abc /config/.config/gtk-3.0 /config/.xprofile 2>/dev/null || chown -R 1000:1000 /config/.config/gtk-3.0 /config/.xprofile 2>/dev/null || true\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'echo "[nexus-init] Sovereign Hypervisor GTK theme activated for abc"\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh

    # /nexus-bucket
    printf 'mkdir -p /nexus-bucket\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'chown -R abc:abc /nexus-bucket 2>/dev/null || chown -R 1000:1000 /nexus-bucket || true\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh

    # KVM permissions
    printf '[ -e /dev/kvm ] && { chown root:kvm /dev/kvm 2>/dev/null||true; chmod 660 /dev/kvm 2>/dev/null||true; usermod -aG kvm abc 2>/dev/null||true; echo "[nexus-init] KVM Tier 1 active"; } || echo "[nexus-init] /dev/kvm absent"\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'usermod -aG libvirt abc 2>/dev/null || true\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh

    # Wallpaper SVG cleanup
    printf 'rm -f /usr/share/wallpapers/KubuntuLight/contents/images/*.svg /usr/share/wallpapers/KubuntuLight/contents/images/*.png 2>/dev/null || true\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'rm -f /usr/share/wallpapers/Next/contents/images/*.svg /usr/share/wallpapers/Next/contents/images/*.png 2>/dev/null || true\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'rm -f /usr/share/wallpapers/Next/contents/images_dark/*.svg /usr/share/wallpapers/Next/contents/images_dark/*.png 2>/dev/null || true\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'echo "[nexus-init] Wallpaper SVG/PNG overrides cleared"\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh

    # Wallpaper apply
    printf 'WALLPAPER_JPG="/usr/share/wallpapers/KubuntuLight/contents/images/1440x900.jpg"\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf '[ -f "${WALLPAPER_JPG}" ] && command -v plasma-apply-wallpaperimage >/dev/null 2>&1 && (\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf '  for DBUS_TRY in unix:path=/config/.XDG/bus unix:path=/run/user/1000/bus unix:path=/tmp/dbus-session-bus; do\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf '    export DBUS_SESSION_BUS_ADDRESS="${DBUS_TRY}"\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf '    export XDG_RUNTIME_DIR=/config/.XDG\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf '    export WAYLAND_DISPLAY=wayland-1\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf '    plasma-apply-wallpaperimage "${WALLPAPER_JPG}" 2>/dev/null && echo "[nexus-init] Wallpaper applied" && break || true\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf '  done\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf ') || true\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh

    # Git pull
    printf '[ -d "/nexus-bucket/underground-nexus/.git" ] && git -C /nexus-bucket/underground-nexus pull --rebase 2>/dev/null || git clone --depth=1 https://github.com/Underground-Ops/underground-nexus.git /nexus-bucket/underground-nexus 2>/dev/null || true\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'chown -R abc:abc /nexus-bucket 2>/dev/null || true\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh
    printf 'echo "[nexus-init] Runtime setup v5.9 complete"\n' \
        >> /custom-cont-init.d/01-nexus-setup.sh

    chmod +x /custom-cont-init.d/01-nexus-setup.sh
    find /etc/s6-overlay -type f -exec chmod +x {} \; 2>/dev/null || true

    ok "Runtime hook written: /custom-cont-init.d/01-nexus-setup.sh"
    ok "  [v5.9] GTK theme activation added to cont-init"

else

    log "BARE METAL MODE — configuring SDDM"
    mkdir -p /etc/sddm.conf.d
    printf '[Autologin]\nUser=abc\nSession=plasma\nRelogin=false\n' \
        > /etc/sddm.conf.d/autologin.conf
    command -v systemctl >/dev/null 2>&1 && {
        systemctl enable sddm 2>/dev/null || true
        systemctl enable libvirtd 2>/dev/null || true
    }
    ok "SDDM auto-login configured"
    # v6.2 — bare-metal service parity: the container gets s6 units; bare
    # metal gets the distro-native equivalents. Enable now, start best-effort
    # (a build chroot without systemd just no-ops all of these).
    systemctl enable --now libvirtd virtlogd 2>/dev/null || true
    systemctl enable --now ollama 2>/dev/null || true
    # Device-perms doctrine, bare metal: udev owns /dev node modes here —
    # we deliberately do NOT chmod devices (that fights udev and loses on
    # replug). GROUP MEMBERSHIP is the bare-metal mechanism (kvm/libvirt/
    # video/render granted in STEP 12), which is the exact same access the
    # container's boot-time perms pass provides there. Agnostic by design.
    log "Bare metal: virt services enabled via systemd; device access via group membership (udev-native)"
fi

# =============================================================================
# STEP 17: FINAL CLEANUP
# =============================================================================

log "STEP 17: Final cleanup"

clear_dpkg_errors
apt-get upgrade -y --fix-broken 2>/dev/null || true
apt-get clean 2>/dev/null || true
rm -rf /var/lib/apt/lists/* 2>/dev/null || true
rm -rf /tmp/sovereign-brand-assets 2>/dev/null || true

id abc >/dev/null 2>&1 && chown -R abc:abc /nexus-bucket 2>/dev/null || \
    chown -R 1000:1000 /nexus-bucket 2>/dev/null || true

[ "${LINUXSERVER_MODE}" = "false" ] && \
    [ -d "${ABC_HOME}" ] && chown -R abc:abc "${ABC_HOME}" 2>/dev/null || true

ok "Cleanup done"

# =============================================================================
# ARSENAL SUMMARY
# =============================================================================

log ""
log "═══════════════════════════════════════════════════"
log "nexus0.sh v6.2 COMPLETE"
log "═══════════════════════════════════════════════════"
log "Mode:       $([ "${CONTAINER_MODE}" = "true" ] && echo "CONTAINER" || echo "BARE METAL")"
log "LinuxSrv:   ${LINUXSERVER_MODE}"
log "Arch:       ${ARCH}"
log "KVM tier:   ${VIRT_TIER:-unknown}"
log "Password:   sovereign"
log ""
log "INSTALLED ARSENAL:"
command -v code         >/dev/null 2>&1 && log "  ✓ VS Code"       || log "  ✗ VS Code"
command -v dagger       >/dev/null 2>&1 && log "  ✓ Dagger CI"     || log "  ✗ Dagger CI"
command -v zarf         >/dev/null 2>&1 && log "  ✓ Zarf"          || log "  ✗ Zarf"
command -v k9s          >/dev/null 2>&1 && log "  ✓ K9s"           || log "  ✗ K9s"
command -v lazydocker   >/dev/null 2>&1 && log "  ✓ Lazydocker"    || log "  ✗ Lazydocker"
command -v ollama       >/dev/null 2>&1 && log "  ✓ Ollama"        || log "  ✗ Ollama"
command -v blender      >/dev/null 2>&1 && log "  ✓ Blender"       || log "  ✗ Blender"
command -v obs          >/dev/null 2>&1 && log "  ✓ OBS Studio"    || log "  ✗ OBS Studio"
command -v libreoffice  >/dev/null 2>&1 && log "  ✓ LibreOffice"   || log "  ✗ LibreOffice"
command -v inkscape     >/dev/null 2>&1 && log "  ✓ Inkscape"      || log "  ✗ Inkscape"
command -v gimp         >/dev/null 2>&1 && log "  ✓ GIMP"          || log "  ✗ GIMP"
dpkg -l gitkraken >/dev/null 2>&1      && log "  ✓ GitKraken"     || log "  ✗ GitKraken"
dpkg -l github-desktop >/dev/null 2>&1 && log "  ✓ GitHub Desktop" || log "  ✗ GitHub Desktop"
[ -f /opt/google/chrome-remote-desktop/chrome-remote-desktop ] \
    && log "  ✓ Chrome RDP (user-configured post-deploy)" \
    || log "  ✗ Chrome RDP"
command -v virt-manager >/dev/null 2>&1 && log "  ✓ Sovereign Hypervisor (virt-manager)" || log "  ✗ Sovereign Hypervisor"
[ -d /usr/share/themes/SovereignHypervisor ] \
    && log "  ✓ SovereignHypervisor GTK3 theme installed" \
    || log "  ✗ SovereignHypervisor theme missing"
log ""
if [ "${CONTAINER_MODE}" = "true" ]; then
    log "s6 SERVICES (started at container boot):"
    log "  ✓ libvirtd  — /etc/s6-overlay/s6-rc.d/libvirtd/run"
    log "  ✓ virtlogd  — /etc/s6-overlay/s6-rc.d/virtlogd/run"
    log "  ✓ ollama    — /etc/s6-overlay/s6-rc.d/ollama/run"
else
    log "SERVICES (systemd, bare metal):"
    log "  ✓ libvirtd  — systemd (enable --now applied)"
    log "  ✓ virtlogd  — systemd (enable --now applied)"
    log "  ✓ ollama    — systemd (installer unit; enable --now applied)"
fi
log "  ✗ CRD       — NOT s6 (user-configured post-deploy)"
log ""
if [ "${CONTAINER_MODE}" = "true" ]; then
    log "RUNTIME HOOK: /custom-cont-init.d/01-nexus-setup.sh"
    log "  Desktop, /nexus-bucket, KVM, git pull"
    log "  [v5.9] GTK_THEME=SovereignHypervisor activation"
fi
log ""
log "SOVEREIGN HYPERVISOR:"
log "  Theme:  /usr/share/themes/SovereignHypervisor/gtk-3.0/gtk.css"
log "  Active: gtk-theme-name=SovereignHypervisor (system + user)"
log "  Env:    GTK_THEME=SovereignHypervisor (/etc/profile.d/)"
log "  Brand:  CU hexagon icon, 'Sovereign Hypervisor' name, Cloud Underground palette"
log ""
log "Full log: /tmp/nexus0-install.log"
log "═══════════════════════════════════════════════════"