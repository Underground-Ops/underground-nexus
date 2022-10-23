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
RUN apt install -y wireshark
#-------------------------------
RUN apt install -y git
RUN apt install -y cron
#-------------------------------
WORKDIR "/usr/local"
RUN curl -L https://dl.dagger.io/dagger/install.sh | sh
RUN wget -O terraform_linux.zip https://releases.hashicorp.com/terraform/1.3.2/terraform_1.3.2_linux_amd64.zip
RUN apt install -y unzip
RUN apt unzip terraform_linux.zip
RUN mv terraform /usr/local/bin/
RUN curl -sSL "https://github.com/buildpacks/pack/releases/download/v0.27.0/pack-v0.27.0-linux.tgz" | tar -C /usr/local/bin/ --no-same-owner -xzv pack
#-------------------------------
RUN apt update --fix-missing
RUN apt -y upgrade