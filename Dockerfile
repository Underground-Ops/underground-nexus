FROM kalilinux/kali-rolling

EXPOSE 22

VOLUME ["/var/run", "/var/lib/docker/volumes", "/nexus-bucket"]

RUN apt update
#-------------------------------
RUN apt install -y bash
RUN apt install -y nano
RUN apt install -y curl
RUN apt install -y wget
#-------------------------------
RUN apt install -y nmap
#-------------------------------
RUN apt install -y git
RUN apt install -y cron
#-------------------------------
WORKDIR "/usr/local"
RUN curl -L https://dl.dagger.io/dagger/install.sh | sh
RUN wget -O terraform_linux.zip https://github.com/Underground-Ops/underground-nexus/raw/4343b3091667bd8779c2cbf27e9b261d89a757f8/Terraform%20Master/terraform_amd64_deployment.zip
RUN apt install -y unzip
RUN unzip terraform_linux.zip
RUN mv terraform /usr/local/bin/
RUN curl -sSL "https://github.com/buildpacks/pack/releases/download/v0.27.0/pack-v0.27.0-linux.tgz" | tar -C /usr/local/bin/ --no-same-owner -xzv pack
#-------------------------------
WORKDIR "/nexus-bucket"
RUN wget -O /nexus-bucket/underground-nexus-dagger-ci.sh https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Dagger%20CI/Scripts/underground-nexus-dagger-ci.sh
RUN sh /nexus-bucket/underground-nexus-dagger-ci.sh; exit 0
#-------------------------------
RUN apt -y update --fix-missing
RUN apt -y upgrade
