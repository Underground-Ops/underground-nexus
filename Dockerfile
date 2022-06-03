FROM linuxserver/webtop:ubuntu-kde

RUN apt update
RUN apt install -y wget
RUN wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/nexus0.sh
