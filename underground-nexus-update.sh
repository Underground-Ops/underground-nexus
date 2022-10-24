cd /nexus-bucket/underground-nexus/
git pull https://github.com/Underground-Ops/underground-nexus.git
dagger project init
dagger project update
dagger do build
rm -r /usr/local/bin/underground-nexus-update.sh
cp /nexus-bucket/underground-nexus/underground-nexus-update.sh /usr/local/bin/
cp /nexus-bucket/underground-nexus/underground-nexus-update.sh /nexus-bucket
apt-get update -y && apt-get upgrade -y && apt-get dist-upgrade -y
apt-get autoclean -y && apt-get clean -y
apt-get autoremove
