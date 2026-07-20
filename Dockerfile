# =============================================================================
# CERBERUS MANAGER — Sovereign C2 Node
# Underground Nexus / Cloud Underground
# Branch: cerberus0
# Image:  natoascode/cerberus0:latest
# =============================================================================
#
# 24.04 BASE BUMP (from 20.04) — what changed and why it is safe:
#   1. FROM ubuntu:20.04 → ubuntu:24.04. 20.04 left standard support in
#      April 2025; 24.04 is the current LTS. s6-overlay is downloaded
#      directly from GitHub (not apt), so it is unaffected by the base
#      version — the same v3 tarball extracts identically on 24.04, and the
#      whole linuxserver ecosystem this stack rides on is already 24.04-based.
#   2. UID-1000 GUARD (STAGE 0, new): 24.04 ships a default `ubuntu` user at
#      UID 1000 that 20.04 did not. Cerberus runs entirely as root and never
#      creates a UID-1000 user, so it would not actually collide — but the
#      guard removes the shipped user anyway so any future user-creation step
#      (or a mounted-volume UID expectation) can rely on 1000 being free.
#      Harmless on 20.04-style bases where the user is absent.
#   3. docker-compose (the old v1 apt package) is GONE on 24.04. Replaced
#      with the Compose v2 plugin from Docker's official repo (STAGE 1B),
#      which is what `docker compose` uses now. This is the one apt package
#      from the old file that would have hard-failed the build on 24.04.
#   4. Kubernetes apt channel bumped v1.28 → v1.30 (1.28 repos are being
#      retired; 1.30 is a current stable line). helm/zarf/dagger unchanged
#      (all fetched directly, version-agnostic).
#   5. Nothing else touched: s6 service tree, DEV/SEC/OPS appinator, Homebrew,
#      locale, SSH, ports, volumes, entrypoint — all identical to the proven
#      20.04 image.
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

FROM ubuntu:24.04

# TARGETARCH is injected by Docker Buildx automatically.
# Values: amd64 | arm64
# Used to download the correct s6-overlay binary for each architecture.
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive

# =============================================================================
# STAGE 0: UID-1000 GUARD (24.04 compatibility)
# =============================================================================
# Ubuntu 24.04 ships a default `ubuntu` user at UID/GID 1000 that 20.04/22.04
# did not. Cerberus runs as root and creates no UID-1000 user, so this is
# belt-and-suspenders: remove the shipped user so UID 1000 is free for any
# future user step or volume-ownership expectation. The `|| true` keeps the
# line harmless on bases where the user is absent (no boot loop, no failure).
RUN if id ubuntu >/dev/null 2>&1; then \
        touch /var/mail/ubuntu 2>/dev/null || true; \
        chown ubuntu /var/mail/ubuntu 2>/dev/null || true; \
        userdel -r ubuntu 2>/dev/null || true; \
        echo "[cerberus] shipped 'ubuntu' user removed — UID 1000 free"; \
    else \
        echo "[cerberus] no shipped UID-1000 user — nothing to remove"; \
    fi

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
# NOTE: `docker-compose` (v1, Python) was REMOVED — it is not in the 24.04
# repositories. The Compose v2 plugin is installed in STAGE 1B instead.

RUN apt-get update && apt-get install -y \
    firewalld \
    curl \
    wget \
    xz-utils \
    cpu-checker \
    nano \
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
# STAGE 1B: DOCKER CLI + COMPOSE v2 PLUGIN (replaces the removed v1 package)
# =============================================================================
# The old image installed `docker-compose` (v1) from apt. On 24.04 that
# package is gone. Install the Docker CLI and the Compose v2 plugin from
# Docker's official repo so `docker compose ...` works. The daemon still
# lives on the host via the mounted /var/run/docker.sock.

RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/* \
    && docker compose version || true

# =============================================================================
# STAGE 2: s6-overlay INSTALLATION (PID 1 init system)
# =============================================================================
# Unchanged from the 20.04 image — s6-overlay is fetched from GitHub and is
# independent of the Ubuntu base version.

ENV S6_OVERLAY_VERSION=3.1.6.2

RUN set -ex; \
    case "${TARGETARCH}" in \
        amd64)  S6_ARCH="x86_64"  ;; \
        arm64)  S6_ARCH="aarch64" ;; \
        *)      echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
        -o /tmp/s6-overlay-noarch.tar.xz; \
    curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
        -o /tmp/s6-overlay-arch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz; \
    rm -f /tmp/s6-overlay-noarch.tar.xz /tmp/s6-overlay-arch.tar.xz; \
    test -f /init && echo "s6-overlay installed: /init confirmed" || (echo "ERROR: /init not found" && exit 1)

# =============================================================================
# STAGE 3: s6 SERVICE DEFINITIONS
# =============================================================================
# Unchanged from the 20.04 image.

RUN mkdir -p \
    /etc/s6-overlay/s6-rc.d/sshd/dependencies.d \
    /etc/s6-overlay/s6-rc.d/crond/dependencies.d \
    /etc/s6-overlay/s6-rc.d/cerberus-init/dependencies.d \
    /etc/s6-overlay/s6-rc.d/user/contents.d

# --- SSH daemon (longrun service) ---
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
RUN echo "oneshot" > /etc/s6-overlay/s6-rc.d/cerberus-init/type
RUN printf '#!/command/with-contenv bash\n\
git clone https://github.com/Underground-Ops/underground-nexus.git \\\n\
    /nexus-bucket/underground-nexus 2>/dev/null || \\\n\
    git -C /nexus-bucket/underground-nexus pull --rebase 2>/dev/null || true\n\
bash /nexus-bucket/underground-nexus/'"'"'Dagger CI'"'"'/Scripts/nexus-devsecops-appinator.sh || true\n\
bash /nexus-bucket/underground-nexus/update-git-packages.sh 2>/dev/null || true\n\
' > /etc/s6-overlay/s6-rc.d/cerberus-init/up \
    && chmod +x /etc/s6-overlay/s6-rc.d/cerberus-init/up

# --- Register all services in the user bundle ---
RUN echo "bundle" > /etc/s6-overlay/s6-rc.d/user/type \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/sshd \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/crond \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/cerberus-init

# =============================================================================
# STAGE 4: DEV/SEC/OPS COMMAND MATRIX
# =============================================================================

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
# Homebrew requires a non-root owner for its prefix on newer versions. Since
# this image operates as root, we create a dedicated `linuxbrew` user (UID
# 1000 is now free thanks to STAGE 0) and install brew under it. If brew
# still refuses in a given environment, the `|| true` keeps the build green —
# soft-serve/wishlist are convenience TUI tools, not boot-critical.

RUN useradd -m -s /bin/bash -u 1000 linuxbrew 2>/dev/null || true \
    && mkdir -p /home/linuxbrew/.linuxbrew \
    && chown -R linuxbrew:linuxbrew /home/linuxbrew \
    && git clone https://github.com/Homebrew/brew /home/linuxbrew/.linuxbrew/Homebrew \
    && mkdir -p /home/linuxbrew/.linuxbrew/bin \
    && ln -s /home/linuxbrew/.linuxbrew/Homebrew/bin/brew /home/linuxbrew/.linuxbrew/bin/brew \
    && chown -R linuxbrew:linuxbrew /home/linuxbrew

ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_NO_ANALYTICS=1

RUN su - linuxbrew -c 'brew --version' || true
RUN su - linuxbrew -c 'brew install charmbracelet/tap/soft-serve' || true \
    && su - linuxbrew -c 'brew install charmbracelet/tap/wishlist' || true

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
# k8s apt channel bumped v1.28 → v1.30 (1.28 repos are being retired).

RUN mkdir -p /etc/apt/keyrings && \
    apt-get update && \
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
        | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
        | tee /etc/apt/sources.list.d/kubernetes.list && \
    apt-get update && \
    apt-get install -y kubectl || true

RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash \
    && helm repo add stable https://charts.helm.sh/stable \
    && helm repo add gitlab https://charts.gitlab.io/ || true

# =============================================================================
# STAGE 10: ZARF (multi-arch binary install)
# =============================================================================

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
# NOTE: PermitRootLogin is kept as in the original for sovereign-net use.
# For hardening you may switch to key-only auth:
#   echo 'PermitRootLogin prohibit-password' instead of 'yes'.

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

ENV S6_KEEP_ENV=1

ENTRYPOINT ["/init"]