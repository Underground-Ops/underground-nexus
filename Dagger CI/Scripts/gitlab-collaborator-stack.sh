#Build the traefik-public network
docker network create --attachable --driver=overlay --subnet=10.15.0.0/16 --gateway=10.15.0.1 traefik-public

#Attach management and state resoruces to the traefik network (Pihole manages the DNS for the stack)
docker network connect traefik-public workbench
docker network connect traefik-public Athena0
docker network connect traefik-public Inner-DNS-Control
docker network connect traefik-public torpedo

#Define system variables
bash -c "NODE_ID=$(docker info -f '{{.Swarm.NodeID}}'); EMAIL=me@underground-ops.me; DOMAIN=localhost"

#Apply docker lables
docker node update --label-add traefik-public.traefik-public-certificates=true Underground-Nexus

#Build collaborator stack, GitLab and traefik loadbalancer
docker stack deploy -c /nexus-bucket/underground-nexus/traefik-api-proxy.yml traefik
docker stack deploy -c /nexus-bucket/underground-nexus/gitlab-proxy-deploy.yml gitlab
docker stack deploy -c /nexus-bucket/underground-nexus/workbench-proxy-deploy.yml collaborator-workbench

#Set up DNS and CNAME Records to make underground-ops.me available
docker exec Inner-DNS-Control sudo echo "10.20.0.1 underground-ops.me" >> /etc/pihole/custom.list
docker exec Inner-DNS-Control sudo echo "cname=api.underground-ops.me,underground-ops.me" >> /etc/dnsmasq.d/05-pihole-custom-cname.conf
docker exec Inner-DNS-Control sudo echo "cname=gitlab.underground-ops.me,underground-ops.me" >> /etc/dnsmasq.d/05-pihole-custom-cname.conf
docker exec Inner-DNS-Control sudo echo "cname=workbench.underground-ops.me,underground-ops.me" >> /etc/dnsmasq.d/05-pihole-custom-cname.conf
