#!/bin/bash

# UNDERGROUND NEXUS INSTALLER - This script installs the Cerberus Manager which is the package manager for the Underground Nexus - this also deploys the Underground Nexus Hypervisor Engine

# Ensure the script is run as sudo
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as sudo. Trying with sudo..."
  exec sudo "$0" "$@"
  exit
fi

# UNDERGROUND NEXUS INSTALLER - This script installs the Cerberus Manager...

mkdir -p ~/nexus-bucket
chmod 755 ~/nexus-bucket

docker run -itd --init --privileged --name=Cerberus-Manager -h Cerberus-Manager --net=host --restart=always -v /root/nexus-bucket:/nexus-bucket -v /var/run/docker.sock:/var/run/docker.sock natoascode/cerberus0:latest sh -c "mkdir -p /root/nexus-bucket && cp /etc/rancher/k3s/k3s.yaml /root/nexus-bucket/k3s.yml && exec bash" && sleep 30 && sudo bash /root/nexus-bucket/underground-nexus/'Dagger CI'/Scripts/install-k3s.sh

cp /etc/rancher/k3s/k3s.yaml /root/nexus-bucket/k3s.yml
docker exec Cerberus-Manager bash -c "mkdir -p /root/.kube && cp /nexus-bucket/k3s.yml /root/.kube/config"

docker exec -it Cerberus-Manager sh -c "
  VERSION=\$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt);
  wget https://github.com/kubevirt/kubevirt/releases/download/\$VERSION/virtctl-\$VERSION-linux-amd64;
  chmod +x virtctl-\$VERSION-linux-amd64;
  mv virtctl-\$VERSION-linux-amd64 /usr/local/bin/virtctl;
"

bash /root/nexus-bucket/underground-nexus/'Dagger CI'/Scripts/virtual-machine-engine.sh

docker exec Cerberus-Manager bash /nexus-devsecops-appinator.sh

docker restart Cerberus-Manager

docker exec -it Cerberus-Manager bash