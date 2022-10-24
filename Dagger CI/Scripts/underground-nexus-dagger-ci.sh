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
