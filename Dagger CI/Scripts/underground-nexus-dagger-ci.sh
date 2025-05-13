#This script builds a portable Dagger CI pipeline that is preconfigured for CICD integration with the Underground Nexus Copy Paste Data Center and Software Factory or any other Docker based deployment (Dagger works with most CI piplines, check out the Dagger website to learn more at https://dagger.io)
#-------------------------------
#apt install git
cd /nexus-bucket/
git clone https://github.com/Underground-Ops/underground-nexus.git /nexus-bucket/underground-nexus || true
cd /nexus-bucket/underground-nexus/

#Install k3d for Kubernetes on Docker when Athena0 is deployed wtih Docker engine access
cd /
wget https://raw.githubusercontent.com/rancher/k3d/main/install.sh
bash install.sh

#Install kubectl
#curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x ./kubectl && mv ./kubectl /usr/local/bin/kubectl
apt-get update
apt-get install -y ca-certificates curl
apt-get install -y apt-transport-https
curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update && upgrade -y
apt-get install -y kubectl

#Install HELM with the standard stable repository and GitLab repository
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && helm repo add stable https://charts.helm.sh/stable && helm repo add gitlab https://charts.gitlab.io/ $$ rm /install.sh

#Update the Pihole by updating the pihole.toml and updating the restore .zip file
cp /nexus-bucket/underground-nexus/'Production Artifacts'/Inner-DNS-Control_teleporter.zip /var/lib/docker/volumes/pihole_DNS_data/_data/Inner-DNS-Control_teleporter.zip || true
docker exec Inner-DNS-Control cp /etc/dnsmasq.d/Inner-DNS-Control_teleporter.zip /Inner-DNS-Control_teleporter.zip || true
cp /nexus-bucket/underground-nexus/'Production Artifacts'/pihole.toml /var/lib/docker/volumes/pihole_DNS_data/_data/pihole.toml || true
docker exec Inner-DNS-Control cp /etc/dnsmasq.d/pihole.toml /etc/pihole/pihole.toml || true

# Get the current KubeVirt version
VERSION=$(kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.observedKubeVirtVersion}")

# Determine system architecture and download file if download can resolve
ARCH=$(uname -s | tr A-Z a-z)-$(uname -m | sed 's/x86_64/amd64/') || windows-amd64.exe
curl -L -o virtctl https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-${ARCH} || true

# If the above commands fail to download then a second determination will be made
ARCH="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m | sed 's/x86_64/amd64/')"

# Download virtctl if this fails then the first download will be used for virtctl
curl -L -o virtctl "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-${ARCH}" || true

# Make it executable
chmod +x virtctl

# Move it to a directory in your PATH
sudo install virtctl /usr/local/bin/


ARCH=$(uname -s | tr A-Z a-z)-$(uname -m | sed 's/x86_64/amd64/') || windows-amd64.exe
curl -L -o virtctl https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-${ARCH} || true


#----------------------------------------------------------------------
#Configure the Underground Nexus automated weekly update scheduling kit
mv -f underground-nexus-dagger-ci.sh old-underground-nexus-dagger-ci.sh
#wget -O re-initialize-dagger-ci.sh https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Dagger%20CI/Scripts/underground-nexus-dagger-ci.sh
#sh re-initialize-dagger-ci.sh
#Cleanup
rm -r /install.*
#Prepare Update Management
sh /nexus-bucket/underground-nexus/underground-nexus-update.sh
#Use crontab to schedule updates for Sundays if Athena0 has a docker socket
echo "0   0   *   *   Sun     /usr/local/bin/underground-nexus-update.sh" > /var/spool/cron/crontabs/root
#Enable, Start and check status of cron service
service cron enable
service cron start
service cron status
