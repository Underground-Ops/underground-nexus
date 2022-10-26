#This script builds a portable Dagger CI pipeline that is preconfigured for CICD integration with the Underground Nexus Copy Paste Data Center and Software Factory or any other Docker based deployment (Dagger works with most CI piplines, check out the Dagger website to learn more at https://dagger.io)
#-------------------------------
#apt install git
git clone https://github.com/Underground-Ops/underground-nexus.git
cd /nexus-bucket/underground-nexus/
dagger project init
dagger project update
dagger do build
#Configure the Underground Nexus automated weekly update scheduling kit
sh /nexus-bucket/underground-nexus/underground-nexus-update.sh
#Use crontab to schedule updates for Sundays if Athena0 has a docker socket
echo "0   0   *   *   Sun     /usr/local/bin/underground-nexus-update.sh" > /var/spool/cron/crontabs/root
#Enable, Start and check status of cron service
service cron enable
service cron start
service cron status
#Install k3d for Kubernetes on Docker when Athena0 is deployed wtih Docker engine access
wget https://raw.githubusercontent.com/rancher/k3d/main/install.sh
bash install.sh
#Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl