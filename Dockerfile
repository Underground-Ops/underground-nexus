FROM kalilinux/kali-rolling

EXPOSE 22

VOLUME ["/var/run", "/var/lib/docker/volumes", "/nexus-bucket"]

RUN apt update
#-------------------------------
RUN apt install -y bash
RUN apt install -y nano
RUN apt install -y curl
RUN apt install -y wget
RUN apt install -y sudo
#-------------------------------
RUN apt install -y nmap
#-------------------------------
RUN apt install -y git
RUN apt install -y cron
#-------------------------------
RUN wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Dagger%20CI/Scripts/underground-nexus-dagger-ci.sh
#-------------------------------
WORKDIR "/usr/local"
RUN curl -L https://dl.dagger.io/dagger/install.sh | sh
#RUN wget -O terraform_linux.zip https://github.com/Underground-Ops/underground-nexus/raw/4343b3091667bd8779c2cbf27e9b261d89a757f8/Terraform%20Master/terraform_amd64_deployment.zip
#RUN apt install -y unzip
#RUN unzip terraform_linux.zip
#RUN mv terraform /usr/local/bin/
RUN curl -sSL "https://github.com/buildpacks/pack/releases/download/v0.27.0/pack-v0.27.0-linux.tgz" | tar -C /usr/local/bin/ --no-same-owner -xzv pack
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
#-------------------------------
RUN apt -y update --fix-missing
RUN apt -y upgrade
RUN rm -r install.*; exit 0
