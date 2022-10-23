FROM kalilinux/kali-rolling

EXPOSE 22

VOLUME ["/var/run", "/var/lib/docker/volumes", "/nexus-bucket"]

RUN apt update
RUN apt upgrade

RUN apt install bash
RUN apt install nano
RUN apt install curl
RUN apt install wget
RUN apt install nmap
RUN apt install git
WORKDIR "/usr/local"
RUN curl -L https://dl.dagger.io/dagger/install.sh | sh
