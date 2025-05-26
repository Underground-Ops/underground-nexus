# __Cerberus0 Cloud Native Cloud Package Manager and CICD Pipeline - *Agnostic Cloud CICD*__ (NEW updates on the way!)

------------------------------------------------------------------------------  

Manage virtual machines alongside containers seemlessly with complete infrastructure lifecycle management, this resource is an alternative to VSPhere for cloud native engineering.

This is the master package manager and installer for the Underground Nexus software hypervisor and DevSecOps platform.

This package management pipeline includes Zarf to provide powerful package management for DevSecOps pipelines and airgapping capabilities.

Learn more about Zarf here: https://docs.zarf.dev/

This package manager does more than package management, CICD can be deployed with Dagger and Kubectl is installed by default for managing Kubernetes clusters.

------------------------------------------------------------------------------  

**Tools and Package Management Resources Include:**

*- zarf*

*- git*

*- kubevit hypervisor*

*- helm package manager*

*- homebrew package manager*

*- soft serve git management server*

*- dagger for cicd*

*- nmap network scanner*

*- cron scheduler*

*- wishlist ssh management*

------------------------------------------------------------------------------  

Wishlist is preconfigured to allow this package manager to be used as an ssh server, the startup script at `/usr/local/bin/start_services.sh` can be edited to modify startup services.

Use this command to modify the startup services:
`nano /usr/local/bin/start_services.sh`

To save type `ctrl+x`, next `y` and `enter`

------------------------------------------------------------------------------  

# _INSTALL HYPERVISOR AND DEVSECOPS PACKAGE MANAGER - *Run the following commands to set up the Underground Nexus Package Manager called the Cerberus Manager*_

`sudo mkdir -p ~/nexus-bucket`

`#sudo chmod 755 ~/nexus-bucket`

`sudo docker run -itd --init --privileged --name=Cerberus-Manager -h Cerberus-Manager --net=host --restart=always -v /root/nexus-bucket:/nexus-bucket -v /var/run/docker.sock:/var/run/docker.sock natoascode/cerberus0:latest sh -c "mkdir -p /root/nexus-bucket && cp /etc/rancher/k3s/k3s.yaml /root/nexus-bucket/k3s.yml && exec bash" && sleep 30 && sudo bash /root/nexus-bucket/underground-nexus/'Dagger CI'/Scripts/install-k3s.sh`

`sudo cp /etc/rancher/k3s/k3s.yaml /root/nexus-bucket/k3s.yml`
`sudo docker exec Cerberus-Manager bash -c "mkdir -p /root/.kube && cp /nexus-bucket/k3s.yml /root/.kube/config"`

`sudo docker exec -it Cerberus-Manager sh -c "`
  `VERSION=\$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt);`
  `wget https://github.com/kubevirt/kubevirt/releases/download/\$VERSION/virtctl-\$VERSION-linux-amd64;`
  `chmod +x virtctl-\$VERSION-linux-amd64;`
  `mv virtctl-\$VERSION-linux-amd64 /usr/local/bin/virtctl;`
  `"`

`sudo bash /root/nexus-bucket/underground-nexus/'Dagger CI'/Scripts/virtual-machine-engine.sh`

`sudo docker exec -it Cerberus-Manager bash`

# Once installed then you can enter the Cerberus-Manager shell to get started using: 

`docker exec -it Cerberus-Manager bash`

# Choose the Underground Nexus install that's right for you.
Once you've activated the Underground Nexus Installer, choose the Underground Nexus install script that matches your use case from the list below. Copy the code below from your chosen install, and paste it into the  Underground Nexus Installer terminal. 

# DEV - Staging Sandbox Desktop [Recommended Install]
- Install a Nexus Creator Vault configured for acceleration with AI powered by Ollama and GitHub Copilot.

`docker run -itd --name=nexus-creator-vault -h nexus-creator-vault -p 1050:3000 -e PUID=1050 -e PGID=1050 -e TZ=America/Colorado --restart unless-stopped -v /dev:/dev -v creator-vault000:/config -v /var/run/docker.sock:/var/run/docker.sock natoascode/zero-trust-cockpit:creator-vault`

# SEC - Security, CICD, Provisioning
- Install a complete Underground Nexus management pipeline: provision, stage and release to production.

`docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 22:22 -p 80:80 -p 8080:8080 -p 443:443 -p 1000:1000 -p 2375:2375 -p 2376:2376 -p 2377:2377 -p 9010:9010 -p 9050:9443 -p 18080:8080 -p 18443:18443 -v /dev:/dev -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket natoascode/underground-nexus:amd64 && docker exec Underground-Nexus bash deploy-olympiad.sh`

# OPS - Compatibility & Scaling Node
- Unactivated underground nexus ready to integrate with an Underground Nexus swarm or run Nexus Creator Vault in compatibility mode.

`docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 1050:1050 -v /dev:/dev -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket natoascode/underground-nexus:amd64`

# *__Congratulations! Now you've installed your first Underground Nexus, and you're ready to start building out your cloud.__*