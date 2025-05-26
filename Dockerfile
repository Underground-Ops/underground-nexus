FROM ubuntu:20.04

ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive

#-------------------------------

# Expose SSH port
EXPOSE 22

#Add persistent volumes
VOLUME ["/var/lib/docker/volumes", "/nexus-bucket"]

# Install necessary tools and dependencies
RUN apt-get update
RUN apt-get install -y \
    firewalld \
    curl \
    wget \
    cpu-checker \
    nano \
    docker-compose \
    openssh-server \
    cron \
    sudo \
    htop \
    nmap \
    iputils-ping \
    build-essential \
    procps \
    file \
    locales && \
    rm -rf /var/lib/apt/lists/* || true

# Set locale (Homebrew needs this)
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Install Homebrew
RUN git clone https://github.com/Homebrew/brew /home/linuxbrew/.linuxbrew/Homebrew && \
    mkdir /home/linuxbrew/.linuxbrew/bin && \
    ln -s /home/linuxbrew/.linuxbrew/Homebrew/bin/brew /home/linuxbrew/.linuxbrew/bin/brew

# Set up environment variables
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH}"
ENV HOMEBREW_NO_ANALYTICS=1

# Verify brew works
RUN brew --version

RUN brew install charmbracelet/tap/soft-serve || true && brew install charmbracelet/tap/wishlist || true

# Install dagger for built-in CI/CD
RUN curl -fsSL https://dl.dagger.io/dagger/install.sh | BIN_DIR=/usr/local/bin sh
RUN mkdir -p /root/.local/share/bash-completion/completions
RUN dagger completion bash > /root/.local/share/bash-completion/completions/dagger

# Clone the Underground Nexus repository
RUN mkdir -p /nexus-bucket || true && chmod 755 /nexus-bucket || true
RUN git clone https://github.com/Underground-Ops/underground-nexus.git /nexus-bucket/underground-nexus || true

#-------------------------------

# Ensure necessary directories exist
RUN mkdir -p /etc/apt/keyrings && \
    apt-get update && \
    apt-get install -y ca-certificates curl apt-transport-https gpg && \
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list && \
    apt-get update && \
    apt-get install -y kubectl || true

# Clean up unnecessary files and fix potential package issues
RUN rm -f /etc/apt/sources.list.d/kubernetes.list && \
    apt-get update && \
    apt-get install -y gpg && \
    apt-get update --fix-missing && \
    rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list && \
    apt-get update && \
    apt-get upgrade --fix-broken -y || true

RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && helm repo add stable https://charts.helm.sh/stable && helm repo add gitlab https://charts.gitlab.io/ || true

# Configure SSH
RUN mkdir /var/run/sshd || true && echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config


#-------------------------------

RUN apt-get update && \
    apt-get install -y curl ca-certificates && \
    rm -rf /var/lib/apt/lists/* || true

# Dynamically fetch the latest Zarf release and install it
RUN set -ex; \
    ZARF_VERSION=$(curl -sIX HEAD https://github.com/zarf-dev/zarf/releases/latest | \
        grep -i '^location:' | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+'); \
    echo "Detected Zarf version: $ZARF_VERSION"; \
    TARGETARCH=$(dpkg --print-architecture); \
    case "$TARGETARCH" in \
        amd64|x86_64) arch="amd64" ;; \
        arm64|aarch64) arch="arm64" ;; \
        *) echo "Unsupported architecture: $TARGETARCH" && exit 1 ;; \
    esac; \
    curl -sL "https://github.com/zarf-dev/zarf/releases/download/${ZARF_VERSION}/zarf_${ZARF_VERSION}_Linux_${arch}" -o zarf; \
    chmod +x zarf; \
    mv -f zarf /usr/local/bin/zarf

#-------------------------------

# Create startup script to start services
RUN echo '#!/bin/bash\nservice ssh start\nservice cron start\nbash -c "git clone https://github.com/Underground-Ops/underground-nexus.git /nexus-bucket/underground-nexus || true"\n/bin/bash -c "/nexus-bucket/underground-nexus/update-git-packages.sh || true"\nbash -c "wishlist serve &"\nexec /bin/bash' > /usr/local/bin/start_services.sh && chmod +x /usr/local/bin/start_services.sh

#-------------------------------

RUN apt -y update --fix-missing || true
RUN apt -y upgrade
RUN rm -r install.* || true

# Set the entrypoint to the startup script
ENTRYPOINT ["/usr/local/bin/start_services.sh"]

# Use cmd with sleep infinity if the container does not stay running after it starts
CMD ["/bin/sh", "-c", "sleep infinity"]