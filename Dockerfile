FROM docker:dind

EXPOSE 22 53 80 443 1000 2375 2376 2377 9010 9443 18443

VOLUME ["/var/run", "/var/lib/docker/volumes", "/nexus-bucket"]

RUN apk update
RUN apk upgrade

RUN apk add bash
RUN apk add nano
RUN apk add curl
RUN apk add wget

#-------------------------------
#Configure kubectl, helm and k3d
RUN curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash; exit 0
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x ./kubectl && mv ./kubectl /usr/local/bin/kubectl; exit 0
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl" && chmod +x ./kubectl && mv ./kubectl /usr/local/bin/kubectl; exit 0
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && helm repo add stable https://charts.helm.sh/stable && helm repo add gitlab https://charts.gitlab.io/; exit 0
#RUN wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list && apk update && apk add terraform; exit 0
#-------------------------------

RUN echo "#!/bin/sh" > deploy-olympiad.sh

#Build Inner-Athena engine
RUN echo "docker swarm init" >> deploy-olympiad.sh
RUN echo "apk add docker-compose" >> deploy-olympiad.sh

RUN echo "docker network create -d bridge --subnet=10.20.0.0/24 Inner-Athena" >> deploy-olympiad.sh
RUN echo "docker run -itd -p 53:53/tcp -p 53:53/udp -p 67:67 -p 800:80 -h Inner-DNS-Control --name=Inner-DNS-Control --net=Inner-Athena --ip=10.20.0.20 --restart=always -v pihole_DNS_data:/etc/dnsmasq.d/ -v pihole_config:/etc/pihole/ pihole/pihole:latest" >> deploy-olympiad.sh

#Build Olympiad0 Portainer node
RUN echo "docker volume create portainer_data" >> deploy-olympiad.sh
RUN echo "docker run -d -p 8000:8000 -p 9443:9443 --name=Olympiad0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest" >> deploy-olympiad.sh

#Build workbench stack
RUN echo "docker run -itd --name=workbench -h workbench --privileged -e PUID=1000 -e PGID=1000 -e TZ=America/Colorado -p 1000:3000 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v workbench0:/config -v /nexus-bucket:/config/Desktop/nexus-bucket -v /var/run/docker.sock:/var/run/docker.sock linuxserver/webtop:ubuntu-mate" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench echo "#!/bin/sh"" > /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt -y update" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt install -y wget" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec Security-Operation-Center sudo apk update" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec Security-Operation-Center sudo apk add wget" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec Security-Operation-Center sudo apk add dpkg" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec Security-Operation-Center sudo apk upgrade" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#Visual Studio Code installs
#RUN echo "docker exec workbench echo "docker exec workbench sudo wget -O vscode-amd64.deb  https://go.microsoft.com/fwlink/?LinkID=760868" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo dpkg -i vscode-amd64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#ARM64 Visual Studio Code deploy
#RUN echo "docker exec workbench echo "docker exec workbench sudo wget https://aka.ms/linux-arm64-deb -O vscode-arm64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo dpkg -i vscode-arm64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#GitHub Desktop
RUN echo "docker exec workbench echo "docker exec workbench sudo wget https://github.com/shiftkey/desktop/releases/download/release-3.1.1-linux1/GitHubDesktop-linux-3.1.1-linux1.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo dpkg -i GitHubDesktop-linux-2.9.6-linux1.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt install -y apt-transport-https curl" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#Chrome RDP and GitKraken
RUN echo "docker exec workbench echo "docker exec workbench wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo dpkg -i chrome-remote-desktop_current_amd64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench wget https://release.gitkraken.com/linux/gitkraken-amd64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo dpkg -i gitkraken-amd64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#Virtual Machine Engineering Suite
RUN echo "docker exec workbench echo "docker exec workbench sudo apt install -y qemu" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt install -y virt-manager" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt install -y synaptic" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#Deploy KuberNexus ETCD Kubernetes Cluster from Athena0
RUN echo "docker exec workbench echo "docker exec Athena0 wget https://raw.githubusercontent.com/rancher/k3d/main/install.sh" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec Athena0 bash /install.sh" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec Athena0 k3d cluster create KuberNexus -p 8080:8080@loadbalancer -p 8443:8443@loadbalancer -p 2222:22@loadbalancer -p 179:179@loadbalancer -p 2375:2376@loadbalancer -p 2378:2379@loadbalancer -p 2381:2380@loadbalancer -p 8472:8472@loadbalancer -p 8843:443@loadbalancer -p 4789:4789@loadbalancer -p 9099:9099@loadbalancer -p 9100:9100@loadbalancer -p 7443:9443@loadbalancer -p 9796:9796@loadbalancer -p 6783:6783@loadbalancer -p 10250:10250@loadbalancer -p 10254:10254@loadbalancer -p 31896:31896@loadbalancer -v /nexus-bucket:/nexus-bucket --registry-create KuberNexus-registry --kubeconfig-update-default" >> /nexus-bucket/build-kubernexus.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec Athena0 export KUBECONFIG=$(k3d kubeconfig write KuberNexus)" >> /nexus-bucket/build-kubernexus.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec Athena0 #cp /root/.k3d/kubeconfig-KuberNexus.yaml /nexus-bucket/" >> /nexus-bucket/build-kubernexus.sh" >> deploy-olympiad.sh; exit 0
RUN echo "docker exec workbench echo "docker exec Athena0 #mkdir /root/.kube && cp /root/.k3d/kubeconfig-KuberNexus.yaml /root/.kube/config" >> /nexus-bucket/build-kubernexus.sh" >> deploy-olympiad.sh; exit 0
RUN echo "docker exec workbench echo "docker exec Athena0 sh /nexus-bucket/build-kubernexus.sh" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec Athena0 sh /enable-weekly-updates.sh" >> /nexus-bucket/enable-weekly-updates.sh" >> deploy-olympiad.sh

#Terraform
RUN echo "docker exec workbench echo "docker exec workbench sudo wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Terraform%20Master/terraform-workbench-install.sh" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo sh terraform-workbench-install.sh" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo mv /terraform-workbench-install.sh /config/Desktop/nexus-bucket" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo mv terraform usr/local/bin" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo touch ~/.bashrc" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo terraform -install-autocomplete" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#Alternate Terraform deploy
#RUN echo "docker exec workbench echo "docker exec workbench sudo curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo apt-get update && sudo apt-get install -y terraform" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench terraform -v" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench which terraform" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench touch ~/.bashrc" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench terraform -install-autocomplete" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt -y update --fix-missing" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt --fix-broken install -y" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt -y upgrade" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt install -y virt-manager" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#------------------------------------
#Change MATE Default Desktop
RUN echo "docker exec workbench echo "docker exec workbench sudo rm /usr/share/backgrounds/ubuntu-mate-jammy/Jammy-Jellyfish_WP_4096x2304_Green.png" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Wallpapers/underground-nexus-scifi-space-jelly.png -O /usr/share/backgrounds/ubuntu-mate-jammy/Jammy-Jellyfish_WP_4096x2304_Green.png" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#------------------------------------

#Deploy Security Operation Center
RUN echo "docker run -itd --name=Security-Operation-Center -h Security-Operation-Center --privileged -e PUID=2000 -e PGID=2000 -e TZ=America/Colorado -p 2000:3000 --dns=10.20.0.20 --net=Inner-Athena --ip=10.20.0.30 --restart=always -v security-operation-center:/config -v /nexus-bucket:/config/Desktop/nexus-bucket linuxserver/webtop:alpine-kde" >> deploy-olympiad.sh

#Build Athena0 stack
RUN echo "docker run -itd --init -p 22:22 --name=Athena0 -h Athena0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v athena0:/home/ -v /nexus-bucket:/nexus-bucket -v /etc/docker:/etc/docker -v /usr/local/bin/docker:/usr/local/bin/docker -v /var/run/docker.sock:/var/run/docker.sock natoascode/athena0:latest" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 apt -y update" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 git clone https://github.com/radareorg/radare2" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 sh radare2/sys/install.sh" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 apt-get install -y metasploit-framework" >> deploy-olympiad.sh
#RUN echo "docker exec Athena0 wget -O terraform-amd64.zip https://releases.hashicorp.com/terraform/1.1.7/terraform_1.1.7_linux_amd64.zip" >> deploy-olympiad.sh
#RUN echo "docker exec Athena0 unzip terraform-amd64.zip" >> deploy-olympiad.sh
#RUN echo "docker exec Athena0 mv terraform usr/local/bin" >> deploy-olympiad.sh
#RUN echo "docker exec Athena0 touch ~/.bashrc" >> deploy-olympiad.sh
#RUN echo "docker exec Athena0 terraform -install-autocomplete" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 apt -y update" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 apt -y upgrade" >> deploy-olympiad.sh

#Build Cyber Life Torpedo - default username is "minioadmin" and default password is also "minioadmin" (please change, especially before shipping off to Dockerhub or other public cloud repositories!)
RUN echo "docker run -itd --privileged -p 9000:9000 -p 9010:9001 --name=torpedo -h torpedo --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /nexus-bucket:/nexus-bucket -v /nexus-bucket/s3-torpedo:/data quay.io/minio/minio server /data --console-address ":9001"" >> deploy-olympiad.sh

#Deploy OPEN Visual Studio Code Container
RUN echo "docker run -d --name=code-server -e PUID=1050 -e PGID=1050 -p 18443:3000 --dns=10.20.0.20 --net=Inner-Athena -v /nexus-bucket:/nexus-bucket -v /nexus-bucket/visual-studio-code:/config -v /etc/docker:/etc/docker -v /usr/local/bin/docker:/usr/local/bin/docker -v /var/run/docker.sock:/var/run/docker.sock --restart unless-stopped lscr.io/linuxserver/openvscode-server" >> deploy-olympiad.sh

#Build Development Vault
RUN echo "docker run -itd -p 8200:1234 --name=Nexus-Secret-Vault -h Nexus-Secret-Vault --dns=10.20.0.20 --net=Inner-Athena --restart=always --cap-add=IPC_LOCK -e 'VAULT_DEV_ROOT_TOKEN_ID=myroot' -e 'VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:1234' vault" >> deploy-olympiad.sh


#Deploy Dagger CI Cyber Life Building Beaver and Update Scheduling Manager Update script
RUN echo "docker exec Athena0 sh /old-underground-nexus-dagger-ci.sh" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 sh /nexus-bucket/underground-nexus/'Dagger CI'/Scripts/enable-weekly-updates.sh" >> deploy-olympiad.sh

#Visual Studio Code for workbench desktop
RUN echo "docker exec workbench echo "docker exec workbench bash /config/Desktop/nexus-bucket/underground-nexus/visual-studio-code.sh" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh

#Build workbench script
RUN echo "docker exec Athena0 sh /nexus-bucket/workbench.sh" >> deploy-olympiad.sh

#Install KuberNexus ETCD Kubernetes Cluster Backup Process if first KuberNexus deployment fails
RUN echo "curl -s https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash" >> deploy-olympiad.sh
RUN echo "k3d cluster create KuberNexus -p 8080:8080@loadbalancer -p 8443:8443@loadbalancer -p 2222:22@loadbalancer -p 179:179@loadbalancer -p 2375:2376@loadbalancer -p 2378:2379@loadbalancer -p 2381:2380@loadbalancer -p 8472:8472@loadbalancer -p 8843:443@loadbalancer -p 4789:4789@loadbalancer -p 9099:9099@loadbalancer -p 9100:9100@loadbalancer -p 7443:9443@loadbalancer -p 9796:9796@loadbalancer -p 6783:6783@loadbalancer -p 10250:10250@loadbalancer -p 10254:10254@loadbalancer -p 31896:31896@loadbalancer -v /nexus-bucket:/nexus-bucket --registry-create KuberNexus-registry --kubeconfig-update-default" >> deploy-olympiad.sh
RUN echo "curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x ./kubectl && mv ./kubectl /usr/local/bin/kubectl" >> deploy-olympiad.sh; exit 0
RUN echo "curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/arm64/kubectl" && chmod +x ./kubectl && mv ./kubectl /usr/local/bin/kubectl" >> deploy-olympiad.sh; exit 0
RUN echo "k3d kubeconfig merge KuberNexus --kubeconfig-merge-default" >> deploy-olympiad.sh; exit 0

#Deploy Traefik loadbalancer, GitLab for Git-BIOS alongside the collaborator-workbench service - build "underground-ops.me" domain proxy gateway
RUN echo "curl https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Dagger%20CI/Scripts/gitlab-collaborator-stack.sh | sh" >> deploy-olympiad.sh

#Configure firefox browser defaults
RUN echo "wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Production%20Artifacts/firefox-homepage.sh" >> deploy-olympiad.sh
RUN echo "sh firefox-homepage.sh" >> deploy-olympiad.sh

RUN echo "docker restart Inner-DNS-Control" >> deploy-olympiad.sh

RUN echo "docker exec -it workbench bash && bash /config/Desktop/nexus-bucket/terraform-workbench-install.sh && terraform -v" >> deploy-olympiad.sh

RUN apk upgrade
