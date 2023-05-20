docker exec workbench sudo apt -y update
docker exec workbench sudo apt install -y wget
docker exec Security-Operation-Center sudo apk update
docker exec Security-Operation-Center sudo apk add wget
docker exec Security-Operation-Center sudo apk add dpkg
docker exec Security-Operation-Center sudo apk upgrade
docker exec workbench sudo apt install -y git
docker exec workbench sudo apt install -y iputils-ping
docker exec workbench sudo wget https://github.com/shiftkey/desktop/releases/download/release-3.1.1-linux1/GitHubDesktop-linux-3.1.1-linux1.deb
docker exec workbench sudo dpkg -i GitHubDesktop-linux-2.9.6-linux1.deb
docker exec workbench sudo apt install -y apt-transport-https curl
docker exec workbench wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
docker exec workbench sudo dpkg -i chrome-remote-desktop_current_amd64.deb
docker exec workbench wget https://release.gitkraken.com/linux/gitkraken-amd64.deb
docker exec workbench sudo dpkg -i gitkraken-amd64.deb
docker exec workbench sudo dpkg -i discord.deb
docker exec workbench sudo apt install -y qemu
docker exec workbench sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils qemu-system qemu-system-x86 qemu-system-arm
docker exec workbench sudo apt install -y virt-manager
docker exec workbench sudo apt install -y synaptic
docker exec Athena0 wget https://raw.githubusercontent.com/rancher/k3d/main/install.sh
docker exec Athena0 bash /install.sh
docker exec Athena0 sh /nexus-bucket/build-kubernexus.sh
docker exec workbench sudo wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Terraform%20Master/terraform-workbench-install.sh
docker exec workbench sudo sh terraform-workbench-install.sh
docker exec workbench sudo mv /terraform-workbench-install.sh /config/Desktop/nexus-bucket
docker exec workbench sudo apt -y update --fix-missing
docker exec workbench sudo apt --fix-broken install -y
docker exec workbench sudo apt -y upgrade
docker exec workbench sudo apt install -y virt-manager
docker exec workbench sudo rm /usr/share/backgrounds/ubuntu-mate-jammy/Jammy-Jellyfish_WP_4096x2304_Green.png
docker exec workbench sudo wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Wallpapers/underground-nexus-scifi-space-jelly.png -O /usr/share/backgrounds/ubuntu-mate-jammy/Jammy-Jellyfish_WP_4096x2304_Green.png
docker exec workbench bash /config/Desktop/nexus-bucket/underground-nexus/visual-studio-code.sh
#Deploy EDR agent to admin workbench
echo "curl -so wazuh-agent-4.3.10.deb https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.3.10-1_amd64.deb && sudo WAZUH_MANAGER='wazuh.manager' WAZUH_AGENT_GROUP='default' dpkg -i ./wazuh-agent-4.3.10.deb && update-rc.d wazuh-agent defaults 95 10 && service wazuh-agent start" > wazuh-agent.sh
docker cp wazuh-agent.sh workbench:/
bash /wazuh-agent.sh