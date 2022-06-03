FROM linuxserver/webtop:ubuntu-kde

RUN apt update
RUN apt install -y wget
RUN apt install -y zip unzip
RUN mkdir /var/lib/docker/volumes/workbench0/_data/.mozilla
RUN wget https://github.com/Underground-Ops/underground-nexus/raw/main/Production%20Artifacts/firefox.zip
RUN unzip firefox.zip
RUN cp -r firefox /var/lib/docker/volumes/workbench0/_data/.mozilla/firefox
RUN chmod -R a+rwx /var/lib/docker/volumes/workbench0/_data/.mozilla
