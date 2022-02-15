FROM docker:dind

EXPOSE 22 53 80 443 1000 2375 2376 2377 9443

VOLUME ["/var/run", "/var/lib/docker/volumes"]

RUN apk update
RUN apk upgrade

RUN apk add bash
RUN apk add nano
RUN apk add curl
RUN apk add wget

RUN curl -fsSL https://get.docker.com -o get-docker.sh
RUN sh get-docker.sh

RUN echo "#!/bin/sh" > deploy-olympiad.sh

RUN echo "docker swarm init" >> deploy-olympiad.sh
RUN echo "apk add docker-compose" >> deploy-olympiad.sh
RUN echo "curl -s https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash" >> deploy-olympiad.sh

RUN echo "docker network create -d bridge --subnet=10.20.0.0/24 Inner-Athena" >> deploy-olympiad.sh
RUN echo "docker run -itd --privileged -p 53:53/tcp -p 53:53/udp -p 67:67 -p 80:80 -p 443:443 -h Inner-DNS-Control --name=Inner-DNS-Control --net=Inner-Athena --ip=10.20.0.20 --restart=always -v pihole_DNS_data:/etc/dnsmasq.d/ -v /var/lib/docker/volumes/pihole_DNS_data/_data/pihole/:/etc/pihole/ pihole/pihole:latest" >> deploy-olympiad.sh
RUN echo "docker run -itd -p 22:22 -h Athena0 --name=Athena0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v athena0:/home/ -v /etc/docker:/etc/docker -v /usr/local/bin/docker:/usr/local/bin/docker -v /var/run/docker.sock:/var/run/docker.sock kalilinux/kali-bleeding-edge" >> deploy-olympiad.sh
RUN echo "docker run -d --name=workbench -h workbench --privileged --init -e PUID=1000 -e PGID=1000 -e TZ=America/Colorado -p 1000:3000 --dns=10.20.0.20 --net=Inner-Athena -v workbench0:/config -v /var/run/docker.sock:/var/run/docker.sock --restart unless-stopped linuxserver/webtop:ubuntu-kde" >> deploy-olympiad.sh

RUN echo "docker volume create portainer_data" >> deploy-olympiad.sh
RUN echo "docker run -d -p 8000:8000 -p 9443:9443 --name Olympiad0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data cr.portainer.io/portainer/portainer-ce" >> deploy-olympiad.sh
