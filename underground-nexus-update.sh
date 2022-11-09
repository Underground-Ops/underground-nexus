#Initiate dagger CI update and patch manager
cd /nexus-bucket/underground-nexus/
git pull https://github.com/Underground-Ops/underground-nexus.git
dagger project init
dagger project update
dagger do build
rm -r /usr/local/bin/underground-nexus-update.sh
cp /nexus-bucket/underground-nexus/underground-nexus-update.sh /usr/local/bin/
cp /nexus-bucket/underground-nexus/underground-nexus-update.sh /nexus-bucket

#Update Control Panel - powered by Wordpress
docker stack rm underground-wordpress
rm -r /var/lib/docker/volumes/underground-wordpress_db_data/_data
cp /nexus-bucket/underground-nexus/'Production Artifacts'/Wordpress/_data.zip /var/lib/docker/volumes/underground-wordpress_db_data/
unzip /var/lib/docker/volumes/underground-wordpress_db_data/_data.zip
rm -r /var/lib/docker/volumes/underground-wordpress_db_data/_data.zip
docker stack deploy -c /nexus-bucket/underground-nexus/wordpress-proxy-deploy.yml underground-wordpress

#Update Workbench
docker exec workbench apt-get update -y && apt-get upgrade -y && apt-get dist-upgrade -y && apt-get autoclean -y && apt-get clean -y && apt-get autoremove

#Update local Kali Linux node (Athena0)
apt-get update -y && apt-get upgrade -y && apt-get dist-upgrade -y
apt-get autoclean -y && apt-get clean -y
apt-get autoremove
