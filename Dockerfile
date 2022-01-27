FROM ubuntu

EXPOSE 22 53 80 443 1000 2375 2376 2377 9443

VOLUME ["/var/run", "/var/lib/docker/volumes"]

RUN apt -y update
RUN apt -y upgrade

RUN apt install -y nano
RUN apt install -y curl
RUN apt install -y wget

RUN curl -fsSL https://get.docker.com -o get-docker.sh
RUN sh get-docker.sh

RUN echo "#!/bin/sh" > deploy-olympiad.sh

RUN echo "service docker enable" >> deploy-olympiad.sh
RUN echo "service docker start" >> deploy-olympiad.sh
RUN echo "docker swarm init" >> deploy-olympiad.sh
RUN echo "apt install -y docker-compose" >> deploy-olympiad.sh
RUN echo "curl -s https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash" >> deploy-olympiad.sh

RUN echo "docker network create -d bridge --subnet=10.20.0.0/24 Inner-Athena" >> deploy-olympiad.sh
RUN echo "docker run -itd --privileged -p 53:53/tcp -p 53:53/udp -p 67:67 -p 80:80 -p 443:443 -h Inner-DNS-Control --name=Inner-DNS-Control --net=Inner-Athena --ip=10.20.0.20 --restart=always -v pihole_DNS_data:/etc/dnsmasq.d/ -v /var/lib/docker/volumes/pihole_DNS_data/_data/pihole/:/etc/pihole/ pihole/pihole:latest" >> deploy-olympiad.sh
RUN echo "docker run -itd -p 22:22 -h Athena0 --name=Athena0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v athena0:/home/ -v /etc/docker:/etc/docker -v /usr/local/bin/docker:/usr/local/bin/docker -v /var/run/docker.sock:/var/run/docker.sock kalilinux/kali-bleeding-edge" >> deploy-olympiad.sh
RUN echo "docker run -d --name=workbench -h workbench --privileged --init -e PUID=1000 -e PGID=1000 -e TZ=America/Colorado -p 1000:3000 --dns=10.20.0.20 --net=Inner-Athena -v workbench0:/config -v /var/run/docker.sock:/var/run/docker.sock --restart unless-stopped linuxserver/webtop:ubuntu-kde" >> deploy-olympiad.sh

RUN echo "docker volume create portainer_data" >> deploy-olympiad.sh
RUN echo "docker run -d -p 8000:8000 -p 9443:9443 --name Olympiad0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data cr.portainer.io/portainer/portainer-ce" >> deploy-olympiad.sh

#RUN chmod +x deploy-olympiad.sh
#ENTRYPOINT ["deploy-olympiad.sh"]

#----------

#RUN echo "docker exec workbench echo "#!/bin/sh" >> visual-studio-code.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg" > visual-studio-code.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/" >> visual-studio-code.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'" >> visual-studio-code.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "rm -f packages.microsoft.gpg" >> visual-studio-code.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "sudo apt install apt-transport-https" >> visual-studio-code.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "sudo apt update" >> visual-studio-code.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "sudo apt install code # or code-insiders" >> visual-studio-code.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "sudo apt -y update" >> visual-studio-code.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "sudo apt -y upgrade" >> visual-studio-code.sh" >> deploy-olympiad.sh

#----------

#RUN service docker enable
#RUN service docker start
#RUN docker swarm init
#RUN apt install -y docker-compose
#RUN curl -s https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash

#RUN docker network create -d bridge --subnet=10.20.0.0/24 Inner-Athena
#RUN docker run -itd --privileged -p 53:53/tcp -p 53:53/udp -p 67:67 -p 80:80 -p 443:443 -h Inner-DNS-Control --name=Inner-DNS-Control --net=Inner-Athena --ip=10.20.0.20 --restart=always -v pihole_DNS_data:/etc/dnsmasq.d/ -v /var/lib/docker/volumes/pihole_DNS_data/_data/pihole/:/etc/pihole/ pihole/pihole:latest
#RUN docker run -itd -p 22:22 -h Athena0 --name=Athena0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v athena0:/home/ -v /etc/docker:/etc/docker -v /usr/local/bin/docker:/usr/local/bin/docker -v /var/run/docker.sock:/var/run/docker.sock kalilinux/kali-bleeding-edge
#RUN docker run -d --name=workbench -h workbench --privileged --init -e PUID=1000 -e PGID=1000 -e TZ=America/Colorado -p 1000:3000 --dns=10.20.0.20 --net=Inner-Athena -v /home/workbench/:/config -v /var/run/docker.sock:/var/run/docker.sock --restart unless-stopped linuxserver/webtop:ubuntu-kde

#RUN docker volume create portainer_data
#RUN docker run -d -p 8000:8000 -p 9443:9443 --name Nexus0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data cr.portainer.io/portainer/portainer-ce


#----------

#RUN echo "#!/bin/sh" > deploy-olympiad.sh

#RUN echo "service docker enable" >> deploy-olympiad.sh
#RUN echo "service docker start" >> deploy-olympiad.sh
#RUN echo "docker swarm init" >> deploy-olympiad.sh
#RUN echo "apt install -y docker-compose" >> deploy-olympiad.sh
#RUN echo "curl -s https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash" >> deploy-olympiad.sh

#RUN echo "docker network create -d bridge --subnet=10.20.0.0/24 Inner-Athena" >> deploy-olympiad.sh
#RUN echo "docker run -itd --privileged -p 53:53/tcp -p 53:53/udp -p 67:67 -p 80:80 -p 443:443 -h Inner-DNS-Control --name=Inner-DNS-Control --net=Inner-Athena --ip=10.20.0.20 --restart=always -v pihole_DNS_data:/etc/dnsmasq.d/ -v /var/lib/docker/volumes/pihole_DNS_data/_data/pihole/:/etc/pihole/ pihole/pihole:latest" >> deploy-olympiad.sh
#RUN echo "docker run -itd -p 22:22 -h Athena0 --name=Athena0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v athena0:/home/ -v /etc/docker:/etc/docker -v /usr/local/bin/docker:/usr/local/bin/docker -v /var/run/docker.sock:/var/run/docker.sock kalilinux/kali-bleeding-edge" >> deploy-olympiad.sh
#RUN echo "docker run -d --name=workbench -h workbench --privileged --init -e PUID=1000 -e PGID=1000 -e TZ=America/Colorado -p 1000:3000 --dns=10.20.0.20 --net=Inner-Athena -v /home/workbench/:/config -v /var/run/docker.sock:/var/run/docker.sock --restart unless-stopped linuxserver/webtop:ubuntu-kde" >> deploy-olympiad.sh

#RUN echo "docker volume create portainer_data" >> deploy-olympiad.sh
#RUN echo "docker run -d -p 8000:8000 -p 9443:9443 --name Olympiad0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data cr.portainer.io/portainer/portainer-ce" >> deploy-olympiad.sh
