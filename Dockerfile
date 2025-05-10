# Use Kali Linux Rolling as the base image
FROM kalilinux/kali-rolling

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive

# Install necessary tools and dependencies
RUN apt-get update && apt-get install -y \
    firewalld \
    wireshark \
    kubectl \
    curl \
    wget \
    cpu-checker \
    terraform \
    nano \
    docker-compose \
    openssh-server \
    cron \
    sudo \
    htop \
    nmap

RUN curl -fsSL https://dl.dagger.io/dagger/install.sh | BIN_DIR=/usr/local/bin sh
RUN mkdir -p /root/.local/share/bash-completion/completions
RUN dagger completion bash > /root/.local/share/bash-completion/completions/dagger

#-------------------------------

WORKDIR "/nexus-bucket"
RUN cd /nexus-bucket/ && wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Dagger%20CI/Scripts/underground-nexus-dagger-ci.sh
RUN sh /nexus-bucket/underground-nexus-dagger-ci.sh; exit 0    
RUN wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/underground-nexus-update.sh
RUN sh underground-nexus-update.sh; exit 0
RUN sh /nexus-bucket/underground-nexus/'Dagger CI'/Scripts/underground-nexus-dagger-ci.sh; exit 0

#-------------------------------

WORKDIR "/"
RUN curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash; exit 0
RUN apt-get update && apt-get install -y ca-certificates curl && apt-get install -y apt-transport-https && curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg && echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list && apt-get update && apt-get install -y kubectl; exit 0
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && helm repo add stable https://charts.helm.sh/stable && helm repo add gitlab https://charts.gitlab.io/; exit 0
RUN wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Dagger%20CI/Scripts/enable-weekly-updates.sh
RUN sh enable-weekly-updates.sh; exit 0

# Create a new user 'notitia' with password 'notiaPoint1'
RUN useradd -m -s /bin/bash notitia && echo "notitia:notiaPoint1" | chpasswd

# Configure SSH
RUN mkdir /var/run/sshd; exit 0 && echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config

# Create startup script to start services
RUN echo '#!/bin/bash\nservice ssh start\nservice cron start' > /usr/local/bin/start_services.sh && chmod +x /usr/local/bin/start_services.sh

#-------------------------------

RUN apt -y update --fix-missing; exit 0
RUN apt -y upgrade
RUN rm -r install.*; exit 0

# Expose SSH port
EXPOSE 22

#Add persistent volumes
VOLUME ["/var/lib/docker/volumes", "/nexus-bucket"]

# Set the entrypoint to the startup script
ENTRYPOINT ["/usr/local/bin/start_services.sh"]