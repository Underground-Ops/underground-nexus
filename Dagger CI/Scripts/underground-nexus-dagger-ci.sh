#This script builds a portable Dagger CI pipeline that is preconfigured for CICD integration with the Underground Nexus Copy Paste Data Center and Software Factory or any other Docker based deployment (Dagger works with most CI piplines, check out the Dagger website to learn more at https://dagger.io)
#-------------------------------
#apt install git
git clone https://github.com/Underground-Ops/underground-nexus.git
cd /nexus-bucket/underground-nexus/
dagger project init
dagger project update
dagger do build
sh /nexus-bucket/underground-nexus/underground-nexus-update.sh
