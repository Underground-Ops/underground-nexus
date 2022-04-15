FROM docker:latest

VOLUME ["/nexus-bucket"]

RUN apk update
#RUN apk upgrade

#RUN apk add bash
#RUN apk add nano
RUN apk add curl
RUN apk add wget

#RUN #!/bin/sh" > deploy-olympiad.sh

#Build Inner-Athena engine
RUN docker swarm init
RUN apk add docker-compose

RUN docker network create -d bridge --subnet=10.20.0.0/24 Inner-Athena
RUN docker run -itd --privileged -p 53:53/tcp -p 53:53/udp -p 67:67 -p 80:80 -p 443:443 -h Inner-DNS-Control --name=Inner-DNS-Control --net=Inner-Athena --ip=10.20.0.20 --restart=always -v pihole_DNS_data:/etc/dnsmasq.d/ -v /var/lib/docker/volumes/pihole_DNS_data/_data/pihole/:/etc/pihole/ pihole/pihole:latest

#Build workbench stack
RUN docker run -itd --name=workbench -h workbench --privileged --init -e PUID=1000 -e PGID=1000 -e TZ=America/Colorado -p 3000:3000 --dns=10.20.0.20 --net=Inner-Athena --ip=10.20.0.15 --restart=always -v workbench0:/config -v /nexus-bucket:/config/Desktop/nexus-bucket -v /var/run/docker.sock:/var/run/docker.sock linuxserver/webtop:ubuntu-mate
#RUN docker exec workbench echo "docker exec workbench echo "#!/bin/sh"" > /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo apt -y update" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo apt install -y wget" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec Security-Operation-Center sudo apt -y update" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec Security-Operation-Center sudo apt install -y wget" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec Security-Operation-Center sudo wget https://release.gitkraken.com/linux/gitkraken-amd64.deb" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec Security-Operation-Center sudo dpkg -i gitkraken-amd64.deb" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo wget -O vscode-amd64.deb  https://go.microsoft.com/fwlink/?LinkID=760868" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo dpkg -i vscode-amd64.deb" >> /nexus-bucket/workbench.sh
#ARM64 Visual Studio Code deploy
RUN docker exec workbench echo "docker exec workbench sudo wget https://aka.ms/linux-arm64-deb -O vscode-arm64.deb" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo dpkg -i vscode-arm64.deb" >> /nexus-bucket/workbench.sh
#GitHub Desktop
RUN docker exec workbench echo "docker exec workbench sudo wget https://github.com/shiftkey/desktop/releases/download/release-2.9.6-linux1/GitHubDesktop-linux-2.9.6-linux1.deb" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo dpkg -i GitHubDesktop-linux-2.9.6-linux1.deb" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo apt install -y apt-transport-https curl" >> /nexus-bucket/workbench.sh
#OPTIONAL - Brave Browser install deploy
#RUN docker exec workbench echo "docker exec workbench sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg" >> /nexus-bucket/workbench.sh
#RUN docker exec workbench echo "docker exec workbench sudo echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main"|sudo tee /etc/apt/sources.list.d/brave-browser-release.list" >> /nexus-bucket/workbench.sh
#RUN docker exec workbench echo "docker exec workbench sudo apt -y update" >> /nexus-bucket/workbench.sh
#RUN docker exec workbench echo "docker exec workbench sudo apt install brave-browser" >> /nexus-bucket/workbench.sh
#Virtual Machine Engineering Suite
RUN docker exec workbench echo "docker exec workbench sudo apt install -y qemu" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo apt install -y virt-manager" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo apt install -y synaptic" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo wget https://raw.githubusercontent.com/rancher/k3d/main/install.sh" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo bash /install.sh" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo wget -O terraform-amd64.zip https://releases.hashicorp.com/terraform/1.1.7/terraform_1.1.7_linux_amd64.zip" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo unzip terraform-amd64.zip" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo mv terraform usr/local/bin" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo touch ~/.bashrc" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo terraform -install-autocomplete" >> /nexus-bucket/workbench.sh
#Alternate Terraform deploy
#RUN docker exec workbench echo "docker exec workbench sudo curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -" >> /nexus-bucket/workbench.sh
#RUN docker exec workbench echo "docker exec workbench sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"" >> /nexus-bucket/workbench.sh
#RUN docker exec workbench echo "docker exec workbench sudo apt-get update && sudo apt-get install -y terraform" >> /nexus-bucket/workbench.sh
#RUN docker exec workbench echo "docker exec workbench terraform -v" >> /nexus-bucket/workbench.sh
#RUN docker exec workbench echo "docker exec workbench which terraform" >> /nexus-bucket/workbench.sh
#RUN docker exec workbench echo "docker exec workbench touch ~/.bashrc" >> /nexus-bucket/workbench.sh
#RUN docker exec workbench echo "docker exec workbench terraform -install-autocomplete" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo apt -y update --fix-missing" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo apt --fix-broken install -y" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo apt -y upgrade" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec workbench sudo apt install -y virt-manager" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec Security-Operation-Center sudo apt -y update --fix-missing" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec Security-Operation-Center sudo apt --fix-broken install -y" >> /nexus-bucket/workbench.sh
RUN docker exec workbench echo "docker exec Security-Operation-Center sudo apt -y upgrade --fix-broken" >> /nexus-bucket/workbench.sh

#Deploy Security Operation Center
RUN docker run -itd --name=Security-Operation-Center -h Security-Operation-Center --privileged --init -e PUID=2000 -e PGID=2000 -e TZ=America/Colorado -p 2000:3000 --dns=10.20.0.20 --net=Inner-Athena --ip=10.20.0.30 --restart=always -v security-operation-center:/config -v /nexus-bucket:/config/Desktop/nexus-bucket linuxserver/webtop:ubuntu-kde

#Build Athena0 stack
RUN docker run -itd -p 22:22 --name=Athena0 -h Athena0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v athena0:/home/ -v /nexus-bucket:/nexus-bucket -v /etc/docker:/etc/docker -v /usr/local/bin/docker:/usr/local/bin/docker -v /var/run/docker.sock:/var/run/docker.sock kalilinux/kali-bleeding-edge
RUN docker exec Athena0 apt -y update
RUN docker exec Athena0 apt install -y nano
RUN docker exec Athena0 apt install -y nmap
RUN docker exec Athena0 apt install -y wireshark
RUN docker exec Athena0 apt install -y git
RUN docker exec Athena0 git clone https://github.com/radareorg/radare2
RUN docker exec Athena0 sh radare2/sys/install.sh
RUN docker exec Athena0 apt-get install -y metasploit-framework
RUN docker exec Athena0 wget -O terraform-amd64.zip https://releases.hashicorp.com/terraform/1.1.7/terraform_1.1.7_linux_amd64.zip
RUN docker exec Athena0 unzip terraform-amd64.zip
RUN docker exec Athena0 mv terraform usr/local/bin
RUN docker exec Athena0 touch ~/.bashrc
RUN docker exec Athena0 terraform -install-autocomplete
RUN docker exec Athena0 apt -y update
RUN docker exec Athena0 apt -y upgrade

#Build Olympiad0 Portainer node
RUN docker volume create portainer_data
RUN docker run -d -p 8000:8000 -p 9443:9443 --name=Olympiad0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data cr.portainer.io/portainer/portainer-ce

#Install Kubernetes kit
RUN curl -s https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash
RUN k3d cluster create KuberNexus -p 8080:80@loadbalancer -p 8443:8443@loadbalancer -p 2222:22@loadbalancer -p 179:179@loadbalancer -p 2375:2376@loadbalancer -p 2378:2379@loadbalancer -p 2381:2380@loadbalancer -p 8472:8472@loadbalancer -p 8843:443@loadbalancer -p 4789:4789@loadbalancer -p 9099:9099@loadbalancer -p 9100:9100@loadbalancer -p 7443:9443@loadbalancer -p 9796:9796@loadbalancer -p 6783:6783@loadbalancer -p 10250:10250@loadbalancer -p 10254:10254@loadbalancer -p 31896:31896@loadbalancer

#Build Cyber Life Torpedo - default username is "minioadmin" and default password is also "minioadmin" (please change, especially before shipping off to Dockerhub or other public cloud repositories!)
RUN docker run -itd --privileged -p 9000:9000 -p 9010:9001 --name=torpedo -h torpedo --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /nexus-bucket:/nexus-bucket -v /nexus-bucket/s3-torpedo:/data quay.io/minio/minio server /data --console-address ":9001"

#Build Development Vault
RUN docker run -itd -p 8200:1234 --name=Nexus-Secret-Vault -h Nexus-Secret-Vault --dns=10.20.0.20 --net=Inner-Athena --restart=always --cap-add=IPC_LOCK -e 'VAULT_DEV_ROOT_TOKEN_ID=myroot' -e 'VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:1234' vault

#Build workbench script
RUN docker exec Athena0 sh /nexus-bucket/workbench.sh
