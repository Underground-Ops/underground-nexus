# =============================================================================
# Athena0 - Underground Nexus chaos engine
# Multi-arch: linux/amd64 + linux/arm64
#
# WHY THE LAST TWO BUILDS FAILED (both arches, same step, same cause)
#
#   Err: .../core:/stable:/v1.28/deb InRelease
#     Sub-process /usr/bin/sqv returned an error code (1)
#     Error: Policy rejected packet type
#     Caused by: Signature Packet v3 is not considered secure since 2026-02-01
#
#   Kali's current apt (3.2.0+kali1) verifies repository signatures with sqv
#   (Sequoia) instead of gpgv. Sequoia's policy rejects v3 signature packets
#   from 2026-02-01 onward, and the Kubernetes v1.28 OBS repo is signed with
#   one. So that repo can no longer be verified on Kali at all, on any
#   architecture. My previous block ran it under `set -eux` with a bare
#   `apt-get update`, so the rejection killed the build.
#
#   Your ORIGINAL Dockerfile hit exactly the same rejection. It only appeared
#   to work because that line ended in `|| true`, which swallowed it. The repo
#   was never actually usable; the failure was just silent.
#
# WHY REMOVING IT COSTS NOTHING
#   Both build logs show kubectl already installed one step earlier, from
#   Kali's own repo, on both architectures:
#       Setting up kubectl (1.33.4+ds-1) ...  "installed: kubectl"
#   The dead repo was trying to supply 1.28 for a tool that was already
#   present at 1.33.4. kubectl capability is preserved and newer.
#
# CHANGES FROM THE ORIGINAL (all marked [CHG-n] inline):
#   [CHG-1] NEW  Kali archive keyring refresh before the first apt-get update.
#               Kali lost their signing key in April 2025 and rotated to
#               ED65462EC8D5E4C5. Verified working on both arches.
#   [CHG-2] CHG  Toolset install split into required + optional-per-package.
#               `apt-get install a b c || true` is all-or-nothing: one missing
#               package installs NOTHING and `|| true` hides it. Every optional
#               package did resolve on arm64 this time, so this is insurance
#               rather than a live fix, but it is what makes a future arm64 gap
#               cost you one tool instead of the whole toolset.
#   [CHG-3] CHG  `echo -e` -> `printf` for start_services.sh. RUN executes under
#               /bin/sh (dash), where `echo -e` emits a literal "-e" and
#               corrupts the shebang.
#   [CHG-4] DEL  BOTH Kubernetes third-party repos removed: the legacy
#               apt.kubernetes.io/kubernetes-xenial one (Google retired those
#               endpoints in March 2024, 404s in your logs) and the pkgs.k8s.io
#               v1.28 one (sqv v3-signature rejection, above). kubectl now comes
#               from Kali, with a repo-free arch-aware binary fallback so the
#               capability is guaranteed either way.
#   [CHG-5] MOV  VOLUME moved to the end. Docker discards writes to a path made
#               a VOLUME earlier in the same build, so the underground-nexus
#               clone was being thrown away.
#   [CHG-6] NEW  Build-time inventory so a thin arm64 build is visible in the
#               log instead of at runtime.
#   [CHG-7] NEW  Scrub stale kubernetes.list after the external nexus scripts.
#               underground-nexus-dagger-ci.sh writes the dead xenial repo into
#               /etc/apt/sources.list.d/ (visible in your logs as the 404). Left
#               there it poisons every later apt-get update, at build time AND
#               inside the running container. Removed after the scripts run.
#   [CHG-8] NEW  `unzip` added to the optional list. Your own
#               underground-nexus-update.sh calls it and fails with
#               "unzip: not found" in both logs. One word, restores intended
#               behaviour. Drop it from the list if you want the old gap back.
#
# The systemd-sysusers shim is UNCHANGED and byte-identical to yours.
#
# Build:
#   docker buildx build --platform linux/arm64 -t natoascode/athena0:arm64 --push .
#   docker buildx build --platform linux/amd64,linux/arm64 -t natoascode/athena0:latest --push .
# =============================================================================

# Use Kali Linux Rolling as the base image (multi-arch: amd64, arm64, armhf)
FROM kalilinux/kali-rolling

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# [CHG-1] Kali archive keyring refresh.
#
# Chicken-and-egg: the repo is unsigned to us until the keyring is in place,
# but we need a download tool from that repo. So we allow ONE unauthenticated
# fetch to obtain wget/ca-certificates/gnupg, install the official keyring,
# then verify the 2025 signing key is actually present before trusting
# anything. Every apt operation after this point is fully verified.
# ---------------------------------------------------------------------------
RUN set -eux; \
    apt-get update -o Acquire::AllowInsecureRepositories=true || true; \
    apt-get install -y --no-install-recommends --allow-unauthenticated \
        wget ca-certificates gnupg || true; \
    wget -q https://archive.kali.org/archive-keyring.gpg \
        -O /usr/share/keyrings/kali-archive-keyring.gpg; \
    [ -s /usr/share/keyrings/kali-archive-keyring.gpg ] || \
        { echo "FATAL: kali keyring download was empty"; exit 1; }; \
    gpg --no-default-keyring \
        --keyring /usr/share/keyrings/kali-archive-keyring.gpg -k \
        | grep -q "ED65462EC8D5E4C5" || \
        { echo "FATAL: 2025 Kali signing key not present in the downloaded keyring"; exit 1; }; \
    rm -rf /var/lib/apt/lists/*; \
    apt-get update; \
    echo "kali keyring OK, repo verified"

#Add persistent volumes -> [CHG-5] moved to the end of this file

# ---------------------------------------------------------------------------
# Build-environment compatibility layer.
#
# Docker Hub's old runner kernel (5.4.0-1068-aws, May 2022 Docker engine)
# can't run the real systemd-sysusers postinst path (it fails with
# "Failed to read 'basic.conf'" no matter where basic.conf is staged), so we
# cannot rely on systemd-standalone-sysusers to create the system users and
# groups that packages declare in /usr/lib/sysusers.d/*.conf.
#
# The original workaround replaced /bin/systemd-sysusers with a bare "exit 0"
# no-op. That satisfied the dependency but created NO users or groups, which
# is exactly what broke clean builds once Kali's cron packaging migrated to
# declarative sysusers.d: cron-daemon-common now declares the "crontab" group
# in /usr/lib/sysusers.d/cron-daemon-common.conf and its postinst still runs
# `chown root:crontab /var/spool/cron/crontabs`. With the no-op stub the group
# never exists, chown fails, and `dpkg --configure` aborts the build.
# (Local builds kept working only because they reused a cached toolset layer
# from before this packaging change.)
#
# Fix: instead of a no-op, install a *functional* systemd-sysusers shim that
# parses sysusers.d files and creates the declared groups/users with
# groupadd/useradd. It is guarded and always exits 0, so it can never fail a
# maintainer script, but it now actually produces the crontab/wireshark/etc.
# groups that downstream postinsts depend on. As a belt-and-suspenders
# guarantee we also pre-create the known-required system groups before the
# toolset install.
#
# systemd-tmpfiles stays a no-op stub on purpose: its tmpfiles.d entries only
# create runtime state under /run and /var and are not required at build time,
# and a full tmpfiles reimplementation would add risk for no build benefit.
# We also pre-stage the machine-id, policy-rc.d and the messagebus user that
# dbus's postinst needs.
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p /var/lib/dbus /run/systemd /usr/lib/sysusers.d /usr/sbin /etc/dbus-1; \
    tr -dc 'a-f0-9' < /dev/urandom | head -c 32 > /etc/machine-id; \
    echo "" >> /etc/machine-id; \
    ln -sf /etc/machine-id /var/lib/dbus/machine-id; \
    echo "docker" > /run/systemd/container; \
    echo '#!/bin/sh' > /usr/sbin/policy-rc.d; \
    echo 'exit 101' >> /usr/sbin/policy-rc.d; \
    chmod +x /usr/sbin/policy-rc.d; \
    groupadd -r messagebus 2>/dev/null || true; \
    useradd -r -g messagebus -d /nonexistent -s /usr/sbin/nologin messagebus 2>/dev/null || true

# ---------------------------------------------------------------------------
# Stage the functional systemd-sysusers shim (see rationale above).
# Written with printf so it works on both BuildKit and the classic builder,
# with no heredoc or syntax-directive requirement. `set -eu` (no -x) keeps the
# build log readable. The shim: creates groups/users from sysusers.d, supports
# every form systemd-sysusers is invoked with (no args / bare filename /
# explicit path / --replace=... - via stdin), ignores options and unknown
# directives, and always exits 0.
# ---------------------------------------------------------------------------
RUN set -eu; \
    mkdir -p /usr/local/lib/nexus; \
    printf '%s\n' \
    '#!/bin/sh' \
    '# systemd-sysusers compatibility shim (Underground Nexus / Athena0).' \
    '# Creates users/groups declared in sysusers.d when the real' \
    '# systemd-sysusers cannot run (Docker Hub legacy runner kernel).' \
    '# Guarded and idempotent: it never fails and always exits 0.' \
    'SU_DIRS="/etc/sysusers.d /run/sysusers.d /usr/lib/sysusers.d"' \
    'su_group() {' \
    '  getent group "$1" >/dev/null 2>&1 && return 0' \
    '  case "x$2" in' \
    '    x|x-) groupadd -r "$1" >/dev/null 2>&1 || true ;;' \
    '    *[!0-9]*) groupadd -r "$1" >/dev/null 2>&1 || true ;;' \
    '    *) groupadd -r -g "$2" "$1" >/dev/null 2>&1 || groupadd -r "$1" >/dev/null 2>&1 || true ;;' \
    '  esac' \
    '}' \
    'su_user() {' \
    '  su_group "$1" -' \
    '  getent passwd "$1" >/dev/null 2>&1 && return 0' \
    '  case "x$2" in' \
    '    x|x-|*[!0-9]*) useradd -r -g "$1" -d /nonexistent -s /usr/sbin/nologin "$1" >/dev/null 2>&1 || true ;;' \
    '    *) useradd -r -u "$2" -g "$1" -d /nonexistent -s /usr/sbin/nologin "$1" >/dev/null 2>&1 || useradd -r -g "$1" -d /nonexistent -s /usr/sbin/nologin "$1" >/dev/null 2>&1 || true ;;' \
    '  esac' \
    '}' \
    'su_stream() {' \
    '  while read -r t name id rest; do' \
    '    case "x$t" in' \
    '      x) continue ;;' \
    '      x#*) continue ;;' \
    '    esac' \
    '    case "$t" in' \
    '      u) su_user "$name" "${id%%:*}" ;;' \
    '      g) su_group "$name" "$id" ;;' \
    '      m) su_group "$id" -; getent passwd "$name" >/dev/null 2>&1 && { usermod -a -G "$id" "$name" >/dev/null 2>&1 || true; } ;;' \
    '      *) : ;;' \
    '    esac' \
    '  done' \
    '}' \
    'su_path() {' \
    '  if [ "x$1" = "x-" ]; then su_stream; return 0; fi' \
    '  if [ -r "$1" ]; then su_stream < "$1"; return 0; fi' \
    '  for d in $SU_DIRS; do' \
    '    if [ -r "$d/$1" ]; then su_stream < "$d/$1"; return 0; fi' \
    '  done' \
    '  return 0' \
    '}' \
    'seen=0' \
    'for a in "$@"; do' \
    '  case "$a" in' \
    '    -h|--help|--version) exit 0 ;;' \
    '    --*) : ;;' \
    '    *) seen=1; su_path "$a" ;;' \
    '  esac' \
    'done' \
    'if [ "$seen" = "0" ]; then' \
    '  for d in $SU_DIRS; do' \
    '    [ -d "$d" ] || continue' \
    '    for f in "$d"/*.conf; do' \
    '      [ -e "$f" ] || continue' \
    '      su_stream < "$f"' \
    '    done' \
    '  done' \
    'fi' \
    'exit 0' \
    > /usr/local/lib/nexus/systemd-sysusers; \
    chmod +x /usr/local/lib/nexus/systemd-sysusers; \
    sh -n /usr/local/lib/nexus/systemd-sysusers

# First-pass install: dbus and systemd-standalone-sysusers will fail their
# postinsts. We expect this. Then we install the functional systemd-sysusers
# shim in place of the real (unusable) binary, keep systemd-tmpfiles as a
# no-op stub, and re-run dpkg --configure. After this block those packages are
# marked fully configured and downstream packages can install normally.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends dbus systemd-standalone-sysusers || true; \
    if [ -f /bin/systemd-sysusers ]; then \
        cp /usr/local/lib/nexus/systemd-sysusers /bin/systemd-sysusers; \
        chmod +x /bin/systemd-sysusers; \
    fi; \
    if [ -f /bin/systemd-tmpfiles ]; then \
        echo '#!/bin/sh' > /bin/systemd-tmpfiles; \
        echo 'exit 0' >> /bin/systemd-tmpfiles; \
        chmod +x /bin/systemd-tmpfiles; \
    fi; \
    dpkg --configure --force-all -a; \
    apt-get install -yf --no-install-recommends; \
    dbus-uuidgen --ensure=/etc/machine-id || true

# ---------------------------------------------------------------------------
# [CHG-2] Main toolset, arm64-safe. kubectl is in this list and comes from
# Kali's own repo: verified installing as 1.33.4+ds-1 on BOTH amd64 and arm64.
#
# CORE packages install as one transaction and MUST succeed: if these are
# missing the container is not Athena0 and the build should fail loudly rather
# than ship a hollow image.
#
# OPTIONAL packages install one at a time, so a future arm64 gap costs one
# tool instead of the entire toolset. [CHG-8] adds unzip, which your
# underground-nexus-update.sh calls and currently cannot find.
# ---------------------------------------------------------------------------
RUN set -eux; \
    for grp in crontab wireshark; do \
        getent group "$grp" >/dev/null 2>&1 || groupadd -r "$grp" || true; \
    done; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        curl \
        wget \
        cron \
        nano \
        sudo \
        htop \
        nmap \
        iputils-ping \
        git; \
    echo "--- optional tools, one at a time ---"; \
    for pkg in wireshark kubectl cpu-checker terraform docker-compose \
               metasploit-framework radare2 unzip; do \
        if apt-get install -y --no-install-recommends "$pkg"; then \
            echo "  installed: $pkg"; \
        else \
            echo "  UNAVAILABLE on $(dpkg --print-architecture): $pkg"; \
            apt-get install -yf --no-install-recommends || true; \
        fi; \
    done; \
    if [ -f /bin/systemd-sysusers ]; then \
        cp /usr/local/lib/nexus/systemd-sysusers /bin/systemd-sysusers; \
        chmod +x /bin/systemd-sysusers; \
    fi; \
    if [ -f /bin/systemd-tmpfiles ]; then \
        echo '#!/bin/sh' > /bin/systemd-tmpfiles; \
        echo 'exit 0' >> /bin/systemd-tmpfiles; \
        chmod +x /bin/systemd-tmpfiles; \
    fi; \
    dpkg --configure --force-all -a; \
    apt-get install -yf

# ---------------------------------------------------------------------------
# [CHG-4] kubectl guarantee WITHOUT any third-party apt repo.
#
# Kali ships kubectl and it installed above on both architectures. This is the
# safety net: if a future Kali drops it, fetch the official static binary for
# the running architecture straight from dl.k8s.io. No repo, no signature
# policy to break, correct arch every time. Pin KUBECTL_VER below if you ever
# need a specific version instead of stable.
# ---------------------------------------------------------------------------
RUN set -eux; \
    if command -v kubectl >/dev/null 2>&1; then \
        echo "kubectl present from Kali repo: $(kubectl version --client 2>/dev/null | head -1 || echo installed)"; \
    else \
        echo "kubectl missing from Kali repo, fetching official binary..."; \
        _arch="$(dpkg --print-architecture)"; \
        KUBECTL_VER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"; \
        curl -fsSLo /usr/local/bin/kubectl \
            "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/${_arch}/kubectl"; \
        chmod +x /usr/local/bin/kubectl; \
        kubectl version --client >/dev/null 2>&1 || \
            { echo "FATAL: kubectl fallback did not produce a working binary"; exit 1; }; \
        echo "kubectl ${KUBECTL_VER} installed for ${_arch}"; \
    fi

# Install dagger for built-in CI/CD (publishes linux/amd64 and linux/arm64)
RUN curl -fsSL https://dl.dagger.io/dagger/install.sh | BIN_DIR=/usr/local/bin sh
RUN mkdir -p /root/.local/share/bash-completion/completions
RUN dagger completion bash > /root/.local/share/bash-completion/completions/dagger || true

# Clone the Underground Nexus repository
RUN git clone https://github.com/Underground-Ops/underground-nexus.git /nexus-bucket/underground-nexus || true

#-------------------------------

WORKDIR "/nexus-bucket"
RUN cd /nexus-bucket/ && wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Dagger%20CI/Scripts/underground-nexus-dagger-ci.sh
RUN sh /nexus-bucket/underground-nexus-dagger-ci.sh || true
RUN wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/underground-nexus-update.sh
RUN sh underground-nexus-update.sh || true
RUN sh /nexus-bucket/underground-nexus/'Dagger CI'/Scripts/underground-nexus-dagger-ci.sh || true

# ---------------------------------------------------------------------------
# [CHG-7] Scrub the dead Kubernetes apt source the nexus scripts write.
#
# underground-nexus-dagger-ci.sh adds
#   deb ... https://apt.kubernetes.io/ kubernetes-xenial main
# which Google retired in March 2024 (the 404 in your build logs). Left in
# place it makes every later `apt-get update` return non-zero, at build time
# and inside the running container. kubectl is already installed, so the file
# has no purpose. Removed here rather than in the scripts so this Dockerfile
# stays self-contained.
# ---------------------------------------------------------------------------
RUN set -eux; \
    rm -f /etc/apt/sources.list.d/kubernetes.list; \
    rm -f /usr/share/keyrings/kubernetes-archive-keyring.gpg; \
    rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg; \
    apt-get update; \
    echo "apt sources clean: $(ls /etc/apt/sources.list.d/ 2>/dev/null || echo none)"

#-------------------------------

WORKDIR "/"
# k3d, helm and dagger all publish arm64 binaries; their installers detect it.
RUN curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash || true
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && helm repo add stable https://charts.helm.sh/stable && helm repo add gitlab https://charts.gitlab.io/ || true
RUN wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Dagger%20CI/Scripts/enable-weekly-updates.sh
RUN sh enable-weekly-updates.sh || true

# The weekly-update script can re-add the dead source; scrub again, harmlessly.
RUN rm -f /etc/apt/sources.list.d/kubernetes.list || true

# Create a new user 'notitia' with password 'notiaPoint1'
# Intentional honeypot credential for eBPF IAM testing (Hide n Hunt scenario).
RUN useradd -m -s /bin/bash notitia && echo "notitia:notiaPoint1" | chpasswd

# ---------------------------------------------------------------------------
# [CHG-3] Startup script written with printf, not `echo -e`.
# RUN executes under /bin/sh (dash) where `echo -e` prints a literal "-e",
# which lands as the first two characters of the file and destroys the
# shebang. printf '%s\n' with one argument per line is correct under both
# dash and bash, and the %20 in the URL is safe because it sits in an
# argument rather than in the format string.
# ---------------------------------------------------------------------------
RUN printf '%s\n' \
    '#!/bin/bash' \
    'service cron start' \
    'wget -O /underground-nexus-dagger-ci.sh https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Dagger%20CI/Scripts/underground-nexus-dagger-ci.sh || true' \
    'docker start Inner-DNS-Control || true' \
    'docker start workbench || true' \
    'docker exec workbench service chrome-remote-desktop start || true' \
    'bash /underground-nexus-dagger-ci.sh || true' \
    'exec /bin/bash' \
    > /usr/local/bin/start_services.sh; \
    chmod +x /usr/local/bin/start_services.sh; \
    head -c 2 /usr/local/bin/start_services.sh | grep -q '#!' \
        || { echo "FATAL: start_services.sh shebang is corrupt"; exit 1; }; \
    bash -n /usr/local/bin/start_services.sh

#-------------------------------

# Maintenance: refresh package metadata and free up space without disturbing
# anything installed above. Safe cleanup only - no package removal.
RUN apt-get update --fix-missing || true
RUN rm -f /install.sh /install.sh.* || true

# ---------------------------------------------------------------------------
# [CHG-6] Build-time inventory. Prints what actually landed for this
# architecture so a thin build is visible in the build log instead of being
# discovered at runtime.
# ---------------------------------------------------------------------------
RUN set -eu; \
    echo "=== Athena0 inventory for $(dpkg --print-architecture) ==="; \
    for t in nmap wireshark tshark msfconsole radare2 kubectl helm k3d dagger \
             docker-compose terraform cron git curl wget htop unzip; do \
        if command -v "$t" >/dev/null 2>&1; then \
            printf '  present  %s\n' "$t"; \
        else \
            printf '  MISSING  %s\n' "$t"; \
        fi; \
    done; \
    echo "=== chaos engine core: nmap + msfconsole + dagger + kubectl ==="

RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* || true

# ---------------------------------------------------------------------------
# [CHG-5] Persistent volumes, declared LAST.
# Docker discards any write made to a path after that path becomes a VOLUME in
# the same build. Declared at the top (as before), every file the steps above
# wrote into /nexus-bucket - the underground-nexus clone and the CI scripts -
# was silently dropped from the image. Declaring here keeps the same volumes
# while preserving that content.
# ---------------------------------------------------------------------------
VOLUME ["/var/lib/docker/volumes", "/nexus-bucket"]

# Set the entrypoint to the startup script
ENTRYPOINT ["/usr/local/bin/start_services.sh"]