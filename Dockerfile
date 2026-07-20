# Use Kali Linux Rolling as the base image
FROM kalilinux/kali-rolling

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive

#Add persistent volumes
VOLUME ["/var/lib/docker/volumes", "/nexus-bucket"]

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

# Now install the main toolset. We pre-create the system groups that packages
# declare via sysusers.d and then chown to during their postinst (cron ->
# "crontab", wireshark -> "wireshark"); this guarantees a clean configure even
# if a package invokes systemd-sysusers in a form the shim doesn't cover. The
# functional shim (installed above and refreshed below) additionally creates
# any other sysusers.d-declared users/groups future Kali package versions add.
RUN set -eux; \
    for grp in crontab wireshark; do \
        getent group "$grp" >/dev/null 2>&1 || groupadd -r "$grp" || true; \
    done; \
    apt-get install -y --no-install-recommends \
        wireshark \
        kubectl \
        curl \
        wget \
        cron \
        cpu-checker \
        terraform \
        nano \
        docker-compose \
        sudo \
        htop \
        nmap \
        iputils-ping \
        metasploit-framework \
        radare2 || true; \
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

# Install dagger for built-in CI/CD
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

#-------------------------------

WORKDIR "/"
RUN curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash || true
RUN apt-get update && apt-get install -y ca-certificates curl && apt-get install -y apt-transport-https && curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg && echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list && apt-get update && apt-get install -y kubectl || true
RUN rm /etc/apt/sources.list.d/kubernetes.list || true && apt-get update && apt-get install -y gpg && apt-get update --fix-missing && rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg && mkdir -p /etc/apt/keyrings && curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list || true && apt-get update && apt-get upgrade --fix-broken -y || true
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && helm repo add stable https://charts.helm.sh/stable && helm repo add gitlab https://charts.gitlab.io/ || true
RUN wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Dagger%20CI/Scripts/enable-weekly-updates.sh
RUN sh enable-weekly-updates.sh || true

# Create a new user 'notitia' with password 'notiaPoint1'
# Intentional honeypot credential for eBPF IAM testing (Hide n Hunt scenario).
RUN useradd -m -s /bin/bash notitia && echo "notitia:notiaPoint1" | chpasswd

# Create startup script to start services
RUN echo -e '#!/bin/bash\nservice cron start\nwget -O /underground-nexus-dagger-ci.sh https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Dagger%20CI/Scripts/underground-nexus-dagger-ci.sh || true\ndocker start Inner-DNS-Control || true\ndocker start workbench || true\ndocker exec workbench service chrome-remote-desktop start || true\nbash /underground-nexus-dagger-ci.sh || true\nexec /bin/bash' > /usr/local/bin/start_services.sh && chmod +x /usr/local/bin/start_services.sh

#-------------------------------

# Maintenance: refresh package metadata and free up space without disturbing
# anything installed above. Safe cleanup only - no package removal.
RUN apt-get update --fix-missing || true
RUN rm -f /install.sh /install.sh.* || true
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* || true

# Set the entrypoint to the startup script
ENTRYPOINT ["/usr/local/bin/start_services.sh"]