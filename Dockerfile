# =============================================================================
# CERBERUS MANAGER — Sovereign C2 Node
# Underground Nexus / Cloud Underground
# Branch: cerberus0
# Image:  natoascode/cerberus0:latest
# =============================================================================
#
# Build (single arch):
#   docker build -t natoascode/cerberus0:latest .
#
# Build (multi-arch — amd64 + arm64, push to registry):
#   docker buildx create --use --name sovereign-builder
#   docker buildx build \
#     --platform linux/amd64,linux/arm64 \
#     -t natoascode/cerberus0:latest \
#     --push .
#
# Deploy (from installer — exact command used by sovereign-installer):
#   docker run -itd \
#     --restart unless-stopped \
#     --name cerberus-manager \
#     --network sovereign-net \
#     -p 80:80 -p 443:443 \
#     -e SOVEREIGN_TIER=open-source \
#     -e MINIO_ENDPOINT=http://minio:9000 \
#     -e MINIO_ROOT_USER=sovereign \
#     -e MINIO_ROOT_PASSWORD=sovereign2024 \
#     -v /var/run/docker.sock:/var/run/docker.sock \
#     -v cerberus-state:/cerberus/state \
#     natoascode/cerberus0:latest
#
# NOTE on -itd:
#   -i (interactive) + -t (TTY) + -d (detached) are ALL required.
#   s6-overlay's supervision tree needs a TTY to initialize correctly.
#   Without -t the container exits immediately after launch.
#
# =============================================================================
# PID 1 ARCHITECTURE — s6-overlay
# =============================================================================
#
# PROBLEM SOLVED: Without a proper init system, bash runs as PID 1.
# When DEV/SEC/OPS commands run via `docker exec` and their child processes
# finish or crash, Docker's bare bash PID 1 cannot reap zombies. Over time
# these accumulate RAM and eventually crash the host (Surface Pro, CIVO node).
#
# SOLUTION: s6-overlay replaces bash as PID 1.
#   - s6 starts first, reads /etc/s6-overlay/s6-rc.d/ for service definitions
#   - s6 starts SSH, cron, and the keep-alive oneshot as supervised services
#   - s6 sits in background as the grim reaper — instantly cleans any orphan
#   - DEV, SEC, OPS commands run via `docker exec` UNCHANGED — s6 is invisible
#   - DEV/SEC/OPS scripts live in /usr/local/bin/ exactly as before
#   - The container never exits (s6 keeps it alive via the longrun service)
#
# s6-overlay v3.x uses a two-stage init:
#   /init → s6-overlay-supers → reads /etc/s6-overlay/s6-rc.d/
#
# =============================================================================

FROM ubuntu:20.04

# TARGETARCH is injected by Docker Buildx automatically.
# Values: amd64 | arm64
# Used to download the correct s6-overlay binary for each architecture.
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive

# =============================================================================
# PORTS & VOLUMES
# =============================================================================

EXPOSE 22
EXPOSE 80
EXPOSE 443

VOLUME ["/var/lib/docker/volumes", "/nexus-bucket", "/cerberus/state"]

# =============================================================================
# STAGE 1: SYSTEM PACKAGES
# =============================================================================

RUN apt-get update && apt-get install -y \
    firewalld \
    curl \
    wget \
    xz-utils \
    cpu-checker \
    nano \
    docker-compose \
    openssh-server \
    cron \
    sudo \
    htop \
    nmap \
    git \
    iputils-ping \
    build-essential \
    procps \
    file \
    locales \
    ca-certificates \
    apt-transport-https \
    gpg \
    && rm -rf /var/lib/apt/lists/* || true

# =============================================================================
# STAGE 2: s6-overlay INSTALLATION (PID 1 init system)
# =============================================================================
# s6-overlay v3 provides:
#   /init              — the new ENTRYPOINT (replaces bash as PID 1)
#   /command/s6-*      — process supervision utilities
#   zombie reaping     — automatic, built-in
#   service management — via /etc/s6-overlay/s6-rc.d/
#
# We download the correct binary for each architecture using TARGETARCH.
# s6-overlay ships two tarballs:
#   s6-overlay-noarch.tar.xz  — scripts, always required
#   s6-overlay-${arch}.tar.xz — arch-specific binaries
#
# s6-overlay releases: https://github.com/just-containers/s6-overlay/releases

ENV S6_OVERLAY_VERSION=3.1.6.2

RUN set -ex; \
    case "${TARGETARCH}" in \
        amd64)  S6_ARCH="x86_64"  ;; \
        arm64)  S6_ARCH="aarch64" ;; \
        *)      echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac; \
    # Download both required tarballs
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
        -o /tmp/s6-overlay-noarch.tar.xz; \
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
        -o /tmp/s6-overlay-arch.tar.xz; \
    # Extract both into / (s6-overlay must be extracted to root)
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz; \
    # Cleanup
    rm -f /tmp/s6-overlay-noarch.tar.xz /tmp/s6-overlay-arch.tar.xz; \
    # Verify /init exists (s6-overlay entrypoint)
    test -f /init && echo "s6-overlay installed: /init confirmed" || (echo "ERROR: /init not found" && exit 1)

# =============================================================================
# STAGE 3: s6 SERVICE DEFINITIONS
# =============================================================================
# s6-overlay v3 uses a dependency-based service runner called s6-rc.
# Services are defined in /etc/s6-overlay/s6-rc.d/
#
# We define three services:
#   sshd     — longrun (stays alive, respawns if it crashes)
#   crond    — longrun (stays alive, respawns if it crashes)
#   cerberus-init — oneshot (runs once at startup: git sync, appinator)
#
# DEV, SEC, OPS commands are NOT services — they are invoked via docker exec.
# s6 is completely transparent to them.

# --- Directory structure ---
RUN mkdir -p \
    /etc/s6-overlay/s6-rc.d/sshd/dependencies.d \
    /etc/s6-overlay/s6-rc.d/crond/dependencies.d \
    /etc/s6-overlay/s6-rc.d/cerberus-init/dependencies.d \
    /etc/s6-overlay/s6-rc.d/user/contents.d

# --- SSH daemon (longrun service) ---
# s6 will start sshd and respawn it if it exits
RUN echo "longrun" > /etc/s6-overlay/s6-rc.d/sshd/type
RUN printf '#!/command/execlineb -P\n/usr/sbin/sshd -D\n' \
    > /etc/s6-overlay/s6-rc.d/sshd/run \
    && chmod +x /etc/s6-overlay/s6-rc.d/sshd/run

# --- Cron daemon (longrun service) ---
RUN echo "longrun" > /etc/s6-overlay/s6-rc.d/crond/type
RUN printf '#!/command/execlineb -P\n/usr/sbin/cron -f\n' \
    > /etc/s6-overlay/s6-rc.d/crond/run \
    && chmod +x /etc/s6-overlay/s6-rc.d/crond/run

# --- Cerberus init (oneshot — runs once at container start) ---
# This replaces the old start_services.sh startup logic.
# Runs: git sync, appinator refresh, update-git-packages.
# Does NOT block. After completion s6 marks it done and moves on.
RUN echo "oneshot" > /etc/s6-overlay/s6-rc.d/cerberus-init/type
RUN printf '#!/command/with-contenv bash\n\
# Sync Underground Nexus repo into nexus-bucket\n\
git clone https://github.com/Underground-Ops/underground-nexus.git \\\n\
    /nexus-bucket/underground-nexus 2>/dev/null || \\\n\
    git -C /nexus-bucket/underground-nexus pull --rebase 2>/dev/null || true\n\
# Re-run appinator to ensure DEV/SEC/OPS commands are current\n\
bash /nexus-bucket/underground-nexus/'"'"'Dagger CI'"'"'/Scripts/nexus-devsecops-appinator.sh || true\n\
# Run package update script if present\n\
bash /nexus-bucket/underground-nexus/update-git-packages.sh 2>/dev/null || true\n\
' > /etc/s6-overlay/s6-rc.d/cerberus-init/up \
    && chmod +x /etc/s6-overlay/s6-rc.d/cerberus-init/up

# --- Register all services in the user bundle ---
# s6-rc bundles group services. "user" is the default startup bundle.
RUN echo "bundle" > /etc/s6-overlay/s6-rc.d/user/type \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/sshd \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/crond \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/cerberus-init

# =============================================================================
# STAGE 4: DEV/SEC/OPS COMMAND MATRIX
# =============================================================================
# The appinator script writes DEV, SEC, OPS (and -rebuild, -restore variants)
# into /usr/local/bin/ as executable files.
# These are invoked by the operator as: docker exec cerberus-manager DEV
#
# We run the appinator at BUILD TIME so the commands are baked into the image.
# The cerberus-init s6 service also re-runs it at CONTAINER START TIME
# to pick up any upstream changes without requiring a rebuild.

RUN wget -O /nexus-devsecops-appinator.sh \
    "https://raw.githubusercontent.com/Underground-Ops/underground-nexus/refs/heads/main/Dagger%20CI/Scripts/nexus-devsecops-appinator.sh" \
    && bash /nexus-devsecops-appinator.sh || true

# =============================================================================
# STAGE 5: LOCALE SETUP
# =============================================================================

RUN locale-gen en_US.UTF-8

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# =============================================================================
# STAGE 6: HOMEBREW (Linuxbrew)
# =============================================================================
# Homebrew is kept — it provides soft-serve and wishlist (Charm toolchain).
# These are part of the Cerberus CLI/TUI experience.
# NOTE: Homebrew is for LINUX use inside this container only.
# The macOS installer will install Homebrew natively on the host via the
# macOS sovereign-installer binary (coming separately) — NOT via this image.

RUN git clone https://github.com/Homebrew/brew /home/linuxbrew/.linuxbrew/Homebrew && \
    mkdir /home/linuxbrew/.linuxbrew/bin && \
    ln -s /home/linuxbrew/.linuxbrew/Homebrew/bin/brew /home/linuxbrew/.linuxbrew/bin/brew

ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_NO_ANALYTICS=1

RUN brew --version
RUN brew install charmbracelet/tap/soft-serve || true \
    && brew install charmbracelet/tap/wishlist || true

# =============================================================================
# STAGE 7: DAGGER CI
# =============================================================================

RUN curl -fsSL https://dl.dagger.io/dagger/install.sh | BIN_DIR=/usr/local/bin sh

RUN mkdir -p /root/.local/share/bash-completion/completions \
    && dagger completion bash > /root/.local/share/bash-completion/completions/dagger

# =============================================================================
# STAGE 8: UNDERGROUND NEXUS REPO CLONE
# =============================================================================

RUN mkdir -p /nexus-bucket \
    && chmod 755 /nexus-bucket \
    && git clone https://github.com/Underground-Ops/underground-nexus.git \
       /nexus-bucket/underground-nexus || true

# =============================================================================
# STAGE 9: KUBERNETES TOOLS (kubectl + helm)
# =============================================================================

RUN mkdir -p /etc/apt/keyrings && \
    apt-get update && \
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key \
        | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" \
        | tee /etc/apt/sources.list.d/kubernetes.list && \
    apt-get update && \
    apt-get install -y kubectl || true

RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash \
    && helm repo add stable https://charts.helm.sh/stable \
    && helm repo add gitlab https://charts.gitlab.io/ || true

# =============================================================================
# STAGE 10: ZARF (multi-arch binary install)
# =============================================================================
# Zarf version is auto-detected from GitHub releases.
# Architecture is resolved from TARGETARCH (amd64 or arm64).

RUN set -ex; \
    ZARF_VERSION=$(curl -sIX HEAD https://github.com/zarf-dev/zarf/releases/latest | \
        grep -i '^location:' | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+'); \
    echo "Installing Zarf ${ZARF_VERSION} for ${TARGETARCH}"; \
    case "${TARGETARCH}" in \
        amd64)  ZARF_ARCH="amd64" ;; \
        arm64)  ZARF_ARCH="arm64" ;; \
        *)      echo "Unsupported arch: ${TARGETARCH}" && exit 1 ;; \
    esac; \
    curl -sL "https://github.com/zarf-dev/zarf/releases/download/${ZARF_VERSION}/zarf_${ZARF_VERSION}_Linux_${ZARF_ARCH}" \
        -o /tmp/zarf; \
    chmod +x /tmp/zarf; \
    mv -f /tmp/zarf /usr/local/bin/zarf; \
    zarf version

# =============================================================================
# STAGE 11: SSH CONFIGURATION
# =============================================================================

RUN mkdir -p /var/run/sshd \
    && echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config

# =============================================================================
# STAGE 12: CERBERUS STATE DIRECTORY
# =============================================================================

RUN mkdir -p /cerberus/state && chmod 755 /cerberus/state

# =============================================================================
# STAGE 13: FINAL CLEANUP
# =============================================================================

RUN apt-get update --fix-missing -y || true \
    && apt-get upgrade -y || true \
    && apt-get autoremove -y || true \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /install.* 2>/dev/null || true

# =============================================================================
# ENTRYPOINT: s6-overlay /init
# =============================================================================
#
# /init is the s6-overlay PID 1 entrypoint.
# It replaces the old start_services.sh bash script.
#
# Boot sequence:
#   1. /init starts (PID 1, s6-overlay)
#   2. s6 reads /etc/s6-overlay/s6-rc.d/user/contents.d/
#   3. s6 starts sshd (longrun), crond (longrun)
#   4. s6 runs cerberus-init (oneshot) — git sync, appinator, update
#   5. Container stays alive indefinitely under s6 supervision
#   6. DEV/SEC/OPS invoked via `docker exec cerberus-manager DEV`
#      — completely transparent to s6 — no interference whatsoever
#
# S6_KEEP_ENV=1: passes all environment variables from `docker run -e` through
# to supervised services and docker exec sessions (SOVEREIGN_TIER, MINIO_*, etc.)
#
# CMD is empty — s6 keeps the container alive natively via its supervision loop.
# sleep infinity is no longer needed.

ENV S6_KEEP_ENV=1

ENTRYPOINT ["/init"]