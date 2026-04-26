# Use Kali Linux Rolling as the base image
FROM kalilinux/kali-rolling

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive

#Add persistent volumes
VOLUME ["/var/lib/docker/volumes", "/nexus-bucket"]

# ---------------------------------------------------------------------------
# Build-environment compatibility layer.
#
# Docker Hub's automated build runners use an old AWS kernel (5.4.0-1068-aws)
# inside a DinD sandbox that does not support systemd's postinst syscalls.
# Kali's official docs explicitly state systemd is not supported in their
# Docker image.
#
# Strategy:
#   - Install systemd-standalone-sysusers (NOT full systemd) to satisfy
#     the systemd-sysusers virtual provide that downstream packages need.
#   - The systemd-standalone-sysusers package in Kali Rolling does not ship
#     /usr/lib/sysusers.d/basic.conf - that file lives in the systemd
#     package, which we deliberately don't install. So we provide
#     basic.conf ourselves with the upstream content.
#   - File creation, verification, and apt install are bundled into a
#     single RUN block so that file existence is provable before the
#     apt-get is allowed to run, and so layer caching cannot cause
#     desynchronization between the file and the install.
#   - All seeded compatibility files (machine-id, container marker,
#     policy-rc.d) are also in this same block.
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p /var/lib/dbus /run/systemd /usr/lib/sysusers.d /usr/sbin; \
    tr -dc 'a-f0-9' < /dev/urandom | head -c 32 > /etc/machine-id; \
    echo "" >> /etc/machine-id; \
    ln -sf /etc/machine-id /var/lib/dbus/machine-id; \
    echo "docker" > /run/systemd/container; \
    echo '#!/bin/sh' > /usr/sbin/policy-rc.d; \
    echo 'exit 101' >> /usr/sbin/policy-rc.d; \
    chmod +x /usr/sbin/policy-rc.d; \
    echo '# Pre-provided basic.conf for systemd-standalone-sysusers postinst' >  /usr/lib/sysusers.d/basic.conf; \
    echo 'g root 0 - -'                                                       >> /usr/lib/sysusers.d/basic.conf; \
    echo 'u root 0:0 "Super User" /root'                                      >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g nogroup 65534 - -'                                                >> /usr/lib/sysusers.d/basic.conf; \
    echo 'u! nobody 65534:65534 "Kernel Overflow User" -'                     >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g adm - - -'                                                        >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g wheel - - -'                                                      >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g utmp - - -'                                                       >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g audio - - -'                                                      >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g cdrom - - -'                                                      >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g dialout - - -'                                                    >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g disk - - -'                                                       >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g input - - -'                                                      >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g kmem - - -'                                                       >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g kvm - - -'                                                        >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g lp - - -'                                                         >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g render - - -'                                                     >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g tape - - -'                                                       >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g tty - - -'                                                        >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g video - - -'                                                      >> /usr/lib/sysusers.d/basic.conf; \
    echo 'g users - - -'                                                      >> /usr/lib/sysusers.d/basic.conf; \
    echo "=== basic.conf written to /usr/lib/sysusers.d/basic.conf ==="; \
    ls -la /usr/lib/sysusers.d/basic.conf; \
    cat /usr/lib/sysusers.d/basic.conf; \
    echo "=== installing systemd-standalone-sysusers ==="; \
    apt-get update; \
    apt-get install -y --no-install-recommends systemd-standalone-sysusers; \
    echo "=== installing dbus ==="; \
    apt-get install -y --no-install-recommends dbus; \
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
    radare2

# Install dagger for built-in CI/CD
RUN curl -fsSL https://dl.dagger.io/dagger/install.sh | BIN_DIR=/usr/local/bin sh
RUN mkdir -p /root/.local/share/bash-completion/completions
RUN dagger completion bash > /root/.local/share/bash-completion/completions/dagger

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