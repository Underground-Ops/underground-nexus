#Initiate Swarm mode if not already running in swarm mode
docker swarm init --advertise-addr 127.0.0.1

#Build the traefik-public network
docker network create --attachable --driver=overlay --subnet=10.15.0.0/16 --gateway=10.15.0.1 traefik-public

#Attach management and state resoruces to the traefik network (Pihole manages the DNS for the stack)
docker network connect traefik-public workbench
docker network connect traefik-public Athena0
docker network connect --ip 10.15.0.200 traefik-public Inner-DNS-Control
docker network connect traefik-public torpedo

#Define system variables
export DOMAIN=underground-ops.me
bash -c "NODE_ID=$(docker info -f '{{.Swarm.NodeID}}'); EMAIL=me@underground-ops.me; DOMAIN=underground-ops.me"

#Apply docker lables
docker node update --label-add traefik-public.traefik-public-certificates=true Underground-Nexus
docker node update --label-add traefik-public.traefik-public-certificates=true underground-nexus

#Build collaborator stack, GitLab and Traefik loadbalancer
docker stack deploy -c /nexus-bucket/underground-nexus/traefik-api-proxy.yml traefik
docker stack deploy -c /nexus-bucket/underground-nexus/gitlab-proxy-deploy.yml gitlab
docker stack deploy -c /nexus-bucket/underground-nexus/workbench-proxy-deploy.yml collaborator-workbench

#Set up "Control Panel" stack - powered by Wordpress
docker network create -d overlay --subnet=172.16.32.0/24 underground-wordpress_internal
mkdir /var/lib/docker/volumes/underground-wordpress_db_data
cp /nexus-bucket/underground-nexus/'Production Artifacts'/Wordpress/_data.zip /var/lib/docker/volumes/underground-wordpress_db_data/
cd /var/lib/docker/volumes/underground-wordpress_db_data/
unzip _data.zip
rm -r /var/lib/docker/volumes/underground-wordpress_db_data/_data.zip
docker stack deploy -c /nexus-bucket/underground-nexus/wordpress-proxy-deploy.yml underground-wordpress

#Build the Cloud Knowledge Base Stack
cd /nexus-bucket/underground-nexus/'Cloud Knowledge Base Stack'/
docker stack deploy -c ./knowledge-base-proxy-deploy.yml underground-knowledge
docker stack deploy -c ./nextcloud-proxy-deploy.yml underground-cloud

#Build the Underground Observability Stack
cd /nexus-bucket/underground-nexus/'Observability Stack'/
docker stack deploy -c ./docker-stack.yml underground-observability

#-------------------------------------------------------------------------
# CRITICAL PIHOLE CONFIGURATIONS - NOTHING WORKS WITHOUT THIS
#Set up DNS and CNAME Records to make underground-ops.me available
cd /
cp /nexus-bucket/underground-nexus/'Production Artifacts'/Inner-DNS-Control_teleporter.zip /var/lib/docker/volumes/pihole_DNS_data/_data/Inner-DNS-Control_teleporter.zip
docker exec Inner-DNS-Control cp /etc/dnsmasq.d/Inner-DNS-Control_teleporter.zip /Inner-DNS-Control_teleporter.zip
cp /nexus-bucket/underground-nexus/'Production Artifacts'/pihole.toml /var/lib/docker/volumes/pihole_DNS_data/_data/pihole.toml
docker exec Inner-DNS-Control cp /etc/dnsmasq.d/pihole.toml /etc/pihole/pihole.toml
# add a restore command once ready to use from inside the pihole itself, or deploy a script from the nexus bucket to work wtih /Inner-DNS-Control_teleporter.zip from inside Inner-DNS-Control
# Check for Pi hole backup file with this command: docker exec Inner-DNS-Control ls /

cd /var/lib/docker/volumes/pihole_config/_data/
echo "10.20.0.1 underground-ops.me" >> custom.list

sort custom.list | uniq > NEWcustom.list
rm custom.list
mv NEWcustom.list custom.list

cd /var/lib/docker/volumes/pihole_DNS_data/_data/
echo "cname=api.underground-ops.me,underground-ops.me" >> 05-pihole-custom-cname.conf
echo "cname=gitlab.underground-ops.me,underground-ops.me" >> 05-pihole-custom-cname.conf
echo "cname=workbench.underground-ops.me,underground-ops.me" >> 05-pihole-custom-cname.conf
echo "cname=grafana.underground-ops.me,underground-ops.me" >> 05-pihole-custom-cname.conf
echo "cname=alertmanager.underground-ops.me,underground-ops.me" >> 05-pihole-custom-cname.conf
echo "cname=indexer.underground-ops.me,underground-ops.me" >> 05-pihole-custom-cname.conf
echo "cname=prometheus.underground-ops.me,underground-ops.me" >> 05-pihole-custom-cname.conf
echo "cname=wazuh.underground-ops.me,underground-ops.me" >> 05-pihole-custom-cname.conf
echo "cname=knowledge.underground-ops.me,underground-ops.me" >> 05-pihole-custom-cname.conf
echo "cname=cloud.underground-ops.me,underground-ops.me" >> 05-pihole-custom-cname.conf

sort 05-pihole-custom-cname.conf | uniq > NEW05-pihole-custom-cname.conf
rm 05-pihole-custom-cname.conf
mv NEW05-pihole-custom-cname.conf 05-pihole-custom-cname.conf

#-------------------------------------------------------------------------

#Build SIEM and EDR Wazuh stack
cd /
rm -r /wazuh-docker
cp -r /nexus-bucket/underground-nexus/'Observability Stack'/wazuh-docker /
cd /wazuh-docker/single-node/
chmod 644 ./config/wazuh_indexer_ssl_certs/*.pem
chmod 644 ./config/wazuh_indexer_ssl_certs/*.key
#cp generate-certs.yml generate-indexer-certs.yml || true
apt install -y docker-compose
apk add docker-cli-compose
apk add docker-compose
#docker-compose -f /wazuh-docker/single-node/generate-indexer-certs.yml run --rm generator
#docker-compose up -d
echo "docker-compose -f generate-indexer-certs.yml run --rm generator && docker-compose up -d" > build-wazuh.sh
bash build-wazuh.sh

#Deploy EDR agent to admin workbench
#echo "curl -so wazuh-agent-4.3.10.deb https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.3.10-1_amd64.deb && sudo WAZUH_MANAGER='wazuh.manager' WAZUH_AGENT_GROUP='default' dpkg -i ./wazuh-agent-4.3.10.deb && update-rc.d wazuh-agent defaults 95 10 && service wazuh-agent start" > wazuh-agent.sh
#docker cp wazuh-agent.sh workbench:/
#docker exec -it workbench bash
#bash /wazuh-agent.sh
#exit

#Update the Cloud Knowledge Base Stack
#docker service update underground-knowledge_db
#docker service update underground-knowledge_app