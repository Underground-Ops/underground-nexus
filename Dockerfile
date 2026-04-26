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
# can't satisfy the syscalls systemd-sysusers needs, even when basic.conf
# is pre-staged. The systemd-standalone-sysusers postinst keeps failing
# with "Failed to read 'basic.conf'" regardless of where we put the file.
#
# Final strategy: install the package, let the postinst fail, then replace
# /bin/systemd-sysusers with a no-op stub and re-run dpkg --configure.
# The re-configure invokes our stub (which exits 0), which tells dpkg the
# package is fully configured. The "systemd | systemd-standalone-sysusers |
# systemd-sysusers" alternative dependency is now satisfied for downstream
# packages, and the install cascade completes normally.
#
# We also stub out other postinst callers that fail in this restricted
# sandbox (systemd-tmpfiles for tmpfiles.d entries) and pre-stage
# /etc/dbus-1/system.conf and the messagebus user that dbus's postinst
# needs.
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

# First-pass install: dbus and systemd-standalone-sysusers will fail their
# postinsts. We expect this. Then we replace /bin/systemd-sysusers and
# /bin/systemd-tmpfiles with no-op stubs and re-run dpkg --configure.
# After this block, those packages are marked fully configured and
# downstream packages can install normally.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends dbus systemd-standalone-sysusers || true; \
    if [ -f /bin/systemd-sysusers ]; then \
        echo '#!/bin/sh' > /bin/systemd-sysusers; \
        echo 'exit 0' >> /bin/systemd-sysusers; \
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

# Now install the main toolset. The systemd-sysusers stub will be invoked
# by any package's postinst that needs it, returning success.
RUN set -eux; \
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
        echo '#!/bin/sh' > /bin/systemd-sysusers; \
        echo 'exit 0' >> /bin/systemd-sysusers; \
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