#Initiate dagger CI update and patch manager
cd /nexus-bucket/underground-nexus/
git pull https://github.com/Underground-Ops/underground-nexus.git
dagger project init
dagger project update
dagger do build
rm -r /usr/local/bin/underground-nexus-update.sh
cp /nexus-bucket/underground-nexus/underground-nexus-update.sh /usr/local/bin/
rm -r /nexus-bucket/underground-nexus-update.sh
cp /nexus-bucket/underground-nexus/underground-nexus-update.sh /nexus-bucket

#Update Control Panel - powered by Wordpress
docker stack rm underground-wordpress
rm -r /var/lib/docker/volumes/underground-wordpress_db_data/_data
mkdir /var/lib/docker/volumes/underground-wordpress_db_data/_data
cp /nexus-bucket/underground-nexus/'Production Artifacts'/Wordpress/_data.zip /var/lib/docker/volumes/underground-wordpress_db_data/_data/
cd /var/lib/docker/volumes/underground-wordpress_db_data/_data/
unzip _data.zip
rm -r /var/lib/docker/volumes/underground-wordpress_db_data/_data/_data.zip
docker stack deploy -c /nexus-bucket/underground-nexus/wordpress-proxy-deploy.yml underground-wordpress
cd /nexus-bucket/underground-nexus/

#Update Workbench
docker exec workbench apt update -y && docker exec workbench apt upgrade -y && docker exec workbench apt dist-upgrade -y && docker exec workbench apt autoclean -y && docker exec workbench apt clean -y && docker exec workbench apt autoremove

#Update local Kali Linux Athena0 node
docker exec Athena0 apt update -y && docker exec Athena0 apt upgrade -y && docker exec Athena0 apt dist-upgrade -y
docker exec Athena0 apt autoclean -y && docker exec Athena0 apt clean -y
docker exec Athena0 apt autoremove
