FROM docker:dind

EXPOSE 22 53 80 443 1000 2375 2376 2377 9001 9443

VOLUME ["/var/run", "/var/lib/docker/volumes", "/nexus-bucket"]

RUN apk update
RUN apk upgrade

RUN apk add bash
RUN apk add nano
RUN apk add curl
RUN apk add wget

RUN echo "#!/bin/sh" > deploy-olympiad.sh

#Build Inner-Athena engine
RUN echo "docker swarm init" >> deploy-olympiad.sh
RUN echo "apk add docker-compose" >> deploy-olympiad.sh

RUN echo "docker network create -d bridge --subnet=10.20.0.0/24 Inner-Athena" >> deploy-olympiad.sh
RUN echo "docker run -itd --privileged -p 53:53/tcp -p 53:53/udp -p 67:67 -p 80:80 -p 443:443 -h Inner-DNS-Control --name=Inner-DNS-Control --net=Inner-Athena --ip=10.20.0.20 --restart=always -v pihole_DNS_data:/etc/dnsmasq.d/ -v /var/lib/docker/volumes/pihole_DNS_data/_data/pihole/:/etc/pihole/ pihole/pihole:latest" >> deploy-olympiad.sh

#Build workbench stack
RUN echo "docker run -d --name=workbench -h workbench --privileged --init -e PUID=1000 -e PGID=1000 -e TZ=America/Colorado -p 1000:3000 --dns=10.20.0.20 --net=Inner-Athena -v workbench0:/config -v /nexus-bucket:/config/Desktop/nexus-bucket -v /var/run/docker.sock:/var/run/docker.sock --restart unless-stopped linuxserver/webtop:ubuntu-kde" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench echo "#!/bin/sh"" > /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt -y update" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt -y upgrade" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt install -y wget" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo wget https://release.gitkraken.com/linux/gitkraken-amd64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo dpkg -i gitkraken-amd64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench wget -O vscode-amd64.deb  https://go.microsoft.com/fwlink/?LinkID=760868" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench dpkg -i vscode-amd64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#OPTIONAL - alternative Visual Studio Code deploy
#RUN echo "docker exec workbench echo "docker exec workbench wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench rm -f packages.microsoft.gpg" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo apt install -y apt-transport-https" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo apt update" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo apt install code # or code-insiders" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo wget https://github.com/shiftkey/desktop/releases/download/release-2.9.3-linux3/GitHubDesktop-linux-2.9.3-linux3.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt-get install -y gdebi-core" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo gdebi GitHubDesktop-linux-2.9.3-linux3.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt install -y apt-transport-https curl" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#OPTIONAL - Brave Browser install deploy
#RUN echo "docker exec workbench echo "docker exec workbench sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main"|sudo tee /etc/apt/sources.list.d/brave-browser-release.list" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo apt -y update" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo apt install brave-browser" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt -y update" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt -y upgrade" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh

#Build Athena0 stack
RUN echo "docker run -itd -p 22:22 --name=Athena0 -h Athena0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v athena0:/home/ -v /nexus-bucket:/nexus-bucket -v /etc/docker:/etc/docker -v /usr/local/bin/docker:/usr/local/bin/docker -v /var/run/docker.sock:/var/run/docker.sock kalilinux/kali-bleeding-edge" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 apt -y update" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 apt install -y nmap" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 apt install -y wireshark" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 apt install -y git" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 git clone https://github.com/radareorg/radare2" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 sh radare2/sys/install.sh" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 apt -y update" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 apt -y upgrade" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 sh /nexus-bucket/workbench.sh" >> deploy-olympiad.sh

#Build Olympiad0 Portainer node
RUN echo "docker volume create portainer_data" >> deploy-olympiad.sh
RUN echo "docker run -d -p 8000:8000 -p 9443:9443 --name=Olympiad0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data cr.portainer.io/portainer/portainer-ce" >> deploy-olympiad.sh

#Install Kubernetes kit
RUN echo "curl -s https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash" >> deploy-olympiad.sh

#Build Cyber Life Torpedo - default username is "minioadmin" and default password is also "minioadmin" (please change, especially before shipping off to Dockerhub or other public cloud repositories!)
RUN echo "docker run -itd --privileged -p 9000:9000 -p 9001:9001 --name=torpedo -h torpedo --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /nexus-bucket:/nexus-bucket -v /nexus-bucket/s3-torpedo:/data quay.io/minio/minio server /data --console-address ":9001"" >> deploy-olympiad.sh
