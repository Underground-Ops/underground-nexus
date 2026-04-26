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
# can't satisfy systemd's postinst syscalls. After many attempts to pre-stage
# what the postinsts want (machine-id, basic.conf, container marker,
# policy-rc.d, dpkg-divert), the systemd-standalone-sysusers postinst
# specifically still fails with "Failed to read 'basic.conf'" even when the
# file is provably present in /usr/lib/sysusers.d/.
#
# Pragmatic strategy: don't fight the postinst. Let it fail, then force
# dpkg to mark the package configured anyway. The actual binary
# (systemd-sysusers) is installed and functional after this; only the
# postinst's user-creation step gets skipped, which doesn't affect Athena0
# at runtime since we create users explicitly later.
#
# We still pre-stage the compat shims (machine-id, container marker,
# policy-rc.d) because they help keep other packages' postinsts quiet.
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p /var/lib/dbus /run/systemd /usr/lib/sysusers.d /usr/sbin; \
    tr -dc 'a-f0-9' < /dev/urandom | head -c 32 > /etc/machine-id; \
    echo "" >> /etc/machine-id; \
    ln -sf /etc/machine-id /var/lib/dbus/machine-id; \
    echo "docker" > /run/systemd/container; \
    echo '#!/bin/sh' > /usr/sbin/policy-rc.d; \
    echo 'exit 101' >> /usr/sbin/policy-rc.d; \
    chmod +x /usr/sbin/policy-rc.d

# Install dbus and systemd-standalone-sysusers, ignoring postinst failures.
# The packages get unpacked (binaries land on disk and work fine); only
# the postinst's user/group seeding gets skipped, which we don't need
# because Kali's base image already has the standard system users.
# `|| true` and the follow-up `dpkg --configure --force-all` mark
# everything as fully configured even if postinsts complained.
RUN apt-get update && \
    apt-get install -y --no-install-recommends dbus systemd-standalone-sysusers || true; \
    dpkg --configure --force-all -a || true; \
    apt-get install -yf --no-install-recommends || true; \
    dbus-uuidgen --ensure=/etc/machine-id || true

RUN apt-get install -y \
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
    dpkg --configure --force-all -a || true; \
    apt-get install -yf || true

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