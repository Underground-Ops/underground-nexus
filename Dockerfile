FROM linuxserver/webtop:ubuntu-kde

RUN apt update
RUN apt install -y wget
RUN apt install -y zip unzip
RUN wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Production%20Artifacts/firefox-homepage.sh
RUN sh firefox-homepage.sh
