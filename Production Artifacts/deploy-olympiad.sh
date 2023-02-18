#!/bin/sh
docker swarm init
apk add docker-compose
docker network create -d bridge --subnet=10.20.0.0/24 Inner-Athena
docker run -itd -p 800:80 -h Inner-DNS-Control --name=Inner-DNS-Control --net=Inner-Athena --ip=10.20.0.20 --restart=always -v pihole_DNS_data:/etc/dnsmasq.d/ -v pihole_config:/etc/pihole/ pihole/pihole:latest
docker volume create portainer_data
docker run -d -p 8000:8000 -p 9443:9443 --name=Olympiad0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
docker run -itd --name=workbench -h workbench --privileged -e PUID=1000 -e PGID=1000 -e TZ=America/Colorado -p 1000:3000 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v workbench0:/config -v /nexus-bucket:/config/Desktop/nexus-bucket -v /var/run/docker.sock:/var/run/docker.sock linuxserver/webtop:ubuntu-mate
docker exec workbench echo docker exec workbench sudo apt -y update >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo apt install -y wget >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec Security-Operation-Center sudo apk update >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec Security-Operation-Center sudo apk add wget >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec Security-Operation-Center sudo apk add dpkg >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec Security-Operation-Center sudo apk upgrade >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo apt install -y git >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo apt install -y iputils-ping >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo wget https://github.com/shiftkey/desktop/releases/download/release-3.1.1-linux1/GitHubDesktop-linux-3.1.1-linux1.deb >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo dpkg -i GitHubDesktop-linux-2.9.6-linux1.deb >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo apt install -y apt-transport-https curl >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo dpkg -i chrome-remote-desktop_current_amd64.deb >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench wget https://release.gitkraken.com/linux/gitkraken-amd64.deb >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo dpkg -i gitkraken-amd64.deb >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo dpkg -i discord.deb >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo apt install -y qemu >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils qemu-system qemu-system-x86 qemu-system-arm >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo apt install -y virt-manager >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo apt install -y synaptic >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec Athena0 wget https://raw.githubusercontent.com/rancher/k3d/main/install.sh >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec Athena0 bash /install.sh >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec Athena0 k3d cluster create KuberNexus -p 18080:8080@loadbalancer -p 8443:8443@loadbalancer -p 2222:22@loadbalancer -p 179:179@loadbalancer -p 2375:2376@loadbalancer -p 2378:2379@loadbalancer -p 2381:2380@loadbalancer -p 8472:8472@loadbalancer -p 8843:443@loadbalancer -p 4789:4789@loadbalancer -p 9099:9099@loadbalancer -p 9100:9100@loadbalancer -p 7443:9443@loadbalancer -p 9796:9796@loadbalancer -p 6783:6783@loadbalancer -p 10250:10250@loadbalancer -p 10254:10254@loadbalancer -p 31896:31896@loadbalancer -v /nexus-bucket:/nexus-bucket --registry-create KuberNexus-registry --kubeconfig-update-default >> /nexus-bucket/build-kubernexus.sh
docker exec workbench echo docker exec Athena0 export KUBECONFIG= >> /nexus-bucket/build-kubernexus.sh
docker exec workbench echo docker exec Athena0 sh /nexus-bucket/build-kubernexus.sh >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec Athena0 sh /enable-weekly-updates.sh >> /nexus-bucket/enable-weekly-updates.sh
docker exec workbench echo docker exec workbench sudo wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Terraform%20Master/terraform-workbench-install.sh >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo sh terraform-workbench-install.sh >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo mv /terraform-workbench-install.sh /config/Desktop/nexus-bucket >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo apt -y update --fix-missing >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo apt --fix-broken install -y >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo apt -y upgrade >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo apt install -y virt-manager >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo rm /usr/share/backgrounds/ubuntu-mate-jammy/Jammy-Jellyfish_WP_4096x2304_Green.png >> /nexus-bucket/workbench.sh
docker exec workbench echo docker exec workbench sudo wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Wallpapers/underground-nexus-scifi-space-jelly.png -O /usr/share/backgrounds/ubuntu-mate-jammy/Jammy-Jellyfish_WP_4096x2304_Green.png >> /nexus-bucket/workbench.sh
docker run -itd --name=Security-Operation-Center -h Security-Operation-Center --privileged -e PUID=2000 -e PGID=2000 -e TZ=America/Colorado -p 2000:3000 --dns=10.20.0.20 --net=Inner-Athena --ip=10.20.0.30 --restart=always -v security-operation-center:/config -v /nexus-bucket:/config/Desktop/nexus-bucket linuxserver/webtop:alpine-kde
docker run -itd --init --privileged --name=Athena0 -h Athena0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v athena0:/home/ -v /nexus-bucket:/nexus-bucket -v /usr/bin/docker:/usr/bin/docker -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/docker/volumes/:/var/lib/docker/volumes/ natoascode/athena0:latest
docker exec Athena0 apt -y update
docker exec Athena0 apt install -y iputils-ping
docker exec Athena0 git clone https://github.com/radareorg/radare2
docker exec Athena0 sh radare2/sys/install.sh
docker exec Athena0 apt-get install -y metasploit-framework
docker exec Athena0 apt -y update
docker exec Athena0 apt -y upgrade
docker run -itd --privileged -p 9000:9000 -p 9010:9001 --name=torpedo -h torpedo --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /nexus-bucket:/nexus-bucket -v /nexus-bucket/s3-torpedo:/data quay.io/minio/minio server /data --console-address :9001
docker run -d --name=code-server -e PUID=1050 -e PGID=1050 -p 18443:3000 --dns=10.20.0.20 --net=Inner-Athena -v /nexus-bucket:/nexus-bucket -v /nexus-bucket/visual-studio-code:/config -v /etc/docker:/etc/docker -v /usr/local/bin/docker:/usr/local/bin/docker -v /var/run/docker.sock:/var/run/docker.sock --restart unless-stopped lscr.io/linuxserver/openvscode-server
docker run -itd -p 8200:1234 --name=Nexus-Secret-Vault -h Nexus-Secret-Vault --dns=10.20.0.20 --net=Inner-Athena --restart=always --cap-add=IPC_LOCK -e 'VAULT_DEV_ROOT_TOKEN_ID=myroot' -e 'VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:1234' vault
docker exec Athena0 sh /old-underground-nexus-dagger-ci.sh
docker exec Athena0 sh /nexus-bucket/underground-nexus/'Dagger CI'/Scripts/enable-weekly-updates.sh
docker exec workbench echo docker exec workbench bash /config/Desktop/nexus-bucket/underground-nexus/visual-studio-code.sh >> /nexus-bucket/workbench.sh
docker exec Athena0 sh /nexus-bucket/workbench.sh
curl -s https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash
k3d cluster create KuberNexus -p 8080:8080@loadbalancer -p 8443:8443@loadbalancer -p 2222:22@loadbalancer -p 179:179@loadbalancer -p 2375:2376@loadbalancer -p 2378:2379@loadbalancer -p 2381:2380@loadbalancer -p 8472:8472@loadbalancer -p 8843:443@loadbalancer -p 4789:4789@loadbalancer -p 9099:9099@loadbalancer -p 9100:9100@loadbalancer -p 7443:9443@loadbalancer -p 9796:9796@loadbalancer -p 6783:6783@loadbalancer -p 10250:10250@loadbalancer -p 10254:10254@loadbalancer -p 31896:31896@loadbalancer -v /nexus-bucket:/nexus-bucket --registry-create KuberNexus-registry --kubeconfig-update-default
curl -LO https://dl.k8s.io/release/v1.26.0/bin/linux/amd64/kubectl && chmod +x ./kubectl && mv ./kubectl /usr/local/bin/kubectl
curl -LO https://dl.k8s.io/release/v1.26.0/bin/linux/arm64/kubectl && chmod +x ./kubectl && mv ./kubectl /usr/local/bin/kubectl
k3d kubeconfig merge KuberNexus --kubeconfig-merge-default
wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Dagger%20CI/Scripts/gitlab-collaborator-stack.sh
sh gitlab-collaborator-stack.sh
wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Production%20Artifacts/firefox-homepage.sh
sh firefox-homepage.sh
docker exec workbench bash /config/Desktop/nexus-bucket/terraform-workbench-install.sh && docker exec workbench terraform -v
docker exec Athena0 curl https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/underground-nexus-update.sh | bash
docker restart Inner-DNS-Control
