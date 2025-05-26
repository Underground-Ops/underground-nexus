# Underground Nexus Installer

- Learn more about the Underground Nexus: https://github.com/Underground-Ops/underground-nexus

# __Cerberus0 Cloud Native Cloud Package Manager and CICD Pipeline - *Agnostic Cloud CICD*__ (NEW updates on the way!)

- The cloud native VMWare / VSPhere alterntive with a complete DevSecOps pipeline from prototype to production 
------------------------------------------------------------------------------  

Manage virtual machines alongside containers seemlessly with complete infrastructure lifecycle management, this resource is an alternative to VSPhere for cloud native engineering.

This is the master package manager and installer for the Underground Nexus software hypervisor and DevSecOps platform.

This package management pipeline includes Zarf to provide powerful package management for DevSecOps pipelines and airgapping capabilities.

Learn more about Zarf here: https://docs.zarf.dev/

This package manager does more than package management, CICD can be deployed with Dagger and Kubectl is installed by default for managing Kubernetes clusters.

__System Requirements:__

Windows (AMD64): Requires WSL (Ubuntu recommended - Docker must be installed in WSL)

Apple Silicon: ARM support coming soon!

Debian Linux/Ubuntu: Requires Docker

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

__Run Underground Nexus Installer Script in Ubuntu / Debian (or from WSL with Ubuntu if using Windows):__

`wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/refs/heads/cerberus0/underground-nexus-installer.sh && sudo bash underground-nexus-installer.sh`

------------------------------------------------------------------------------ 

__Script Contents:__

`#!/bin/bash`

`# UNDERGROUND NEXUS INSTALLER - This script installs the Cerberus Manager which is the package manager for the Underground Nexus - this also deploys the Underground Nexus Hypervisor Engine`

`# Ensure the script is run with sudo`
`if [ "$EUID" -ne 0 ]; then`
  `echo "This script must be run with sudo. Trying with sudo..."`
  `exec sudo "$0" "$@"`
  `exit`
`fi`

`# UNDERGROUND NEXUS INSTALLER - This script installs the Cerberus Manager...`

`mkdir -p ~/nexus-bucket`

`#chmod 755 ~/nexus-bucket`

`docker run -itd --init --privileged --name=Cerberus-Manager -h Cerberus-Manager --net=host --restart=always -v /root/nexus-bucket:/nexus-bucket -v /var/run/docker.sock:/var/run/docker.sock natoascode/cerberus0:latest sh -c "mkdir -p /root/nexus-bucket && cp /etc/rancher/k3s/k3s.yaml /root/nexus-bucket/k3s.yml && exec bash" && sleep 30 && bash /root/nexus-bucket/underground-nexus/'Dagger CI'/Scripts/install-k3s.sh`

`cp /etc/rancher/k3s/k3s.yaml /root/nexus-bucket/k3s.yml`
`docker exec Cerberus-Manager bash -c "mkdir -p /root/.kube && cp /nexus-bucket/k3s.yml /root/.kube/config"`

`docker exec -it Cerberus-Manager sh -c "`
  `VERSION=\$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt);`
  `wget https://github.com/kubevirt/kubevirt/releases/download/\$VERSION/virtctl-\$VERSION-linux-amd64;`
  `chmod +x virtctl-\$VERSION-linux-amd64;`
  `mv virtctl-\$VERSION-linux-amd64 /usr/local/bin/virtctl;`
  `"`

`bash /root/nexus-bucket/underground-nexus/'Dagger CI'/Scripts/virtual-machine-engine.sh`

`docker exec -it Cerberus-Manager bash`

# Once installed then you can enter the Cerberus-Manager shell to get started using: 

`docker exec -it Cerberus-Manager bash`

# Choose the Underground Nexus install that's right for you.
Once you've activated the Underground Nexus Installer, choose the Underground Nexus install script that matches your use case from the list below. Copy the code below from your chosen install, and paste it into the  Underground Nexus Installer terminal. 

# DEV - Staging Sandbox Desktop [Recommended Install]
- Install a Nexus Creator Vault configured for acceleration with AI powered by Ollama and GitHub Copilot.

`docker run -itd --name=nexus-creator-vault -h nexus-creator-vault -p 1050:3000 -e PUID=1050 -e PGID=1050 -e TZ=America/Colorado --restart unless-stopped -v /dev:/dev -v creator-vault000:/config -v /var/run/docker.sock:/var/run/docker.sock natoascode/zero-trust-cockpit:creator-vault`

Once complete head over to: http://localhost:1050

This is a powerful hardware accellerated virtual desktop space where you can accellerate resources that can be used for AI, blockchain, graphics generation and beyond.

If you need to build a Virtual Machine to test or learn with and do not need the scalability of KubeVirt, this virtual desktop contains a hypervisor engine that allows you to build and manage virtual machines.

The virtual machines built that you decide to scale can be deployed to KubeVirt for production use and increased scalability.

To verify that your hardware has virtualization enabled - type the following command to make sure "accelleration" is enabled:
`sudo kvm-ok`

This virtual desktop is AI powered with Ollama.

Learn more about Ollama: https://ollama.com/ 

To start using AI try opening a terminal such as Konsole and type:
`ollama run mistral`

Learn more about Mistral: https://ollama.com/library/mistral:7b 

Congratulations, you now have a local AI instance running on your hardware that's private just for you!

Don't forget to check out Visual Studio Code and explore the GitHub Copilot integration to get a boost to your coding efforts.

This system may be used as an MCP server if configured to be used as one with Ollama or an alternative for private AI system management.

Since this is open source and based on Ubuntu, you may integrate any other AI resource of choice!

# SEC - Security, CICD, Provisioning
- Install a complete Underground Nexus management pipeline: provision, stage and release to production.

`docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 22:22 -p 80:80 -p 8080:8080 -p 443:443 -p 1000:1000 -p 2375:2375 -p 2376:2376 -p 2377:2377 -p 9010:9010 -p 9050:9443 -p 18080:8080 -p 18443:18443 -v /dev:/dev -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket natoascode/underground-nexus:amd64 && docker exec Underground-Nexus bash deploy-olympiad.sh`

Deploy an entire Underground Nexus containerized engine that can be used to manage security and DevSecOps. This layer can be used for provisioning and debugging, it is also a great place to host fellow engineers in Nexus Creator Vault virtual destktops so they may contribue to projects.

Check out the Underground Nexus to learn more: https://github.com/Underground-Ops/underground-nexus 

# OPS - Compatibility & Scaling Node
- Unactivated underground nexus ready to integrate with an Underground Nexus swarm or run Nexus Creator Vault in compatibility mode.

`docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 1050:1050 -v /dev:/dev -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket natoascode/underground-nexus:amd64`

If the Nexus Creator Vault is not deploying properly, or if you are testing and debugging then this allows you to experience improved compatibility by building containers inside of this docker in docker container.

This docker in docker container can also be used to swarm with Underground Nexus Managers ready to scale.

Try building a Docker Swarm cluster with this to see how it works!

Learn more about buildng Swarm Clusters: https://docs.docker.com/engine/swarm/ 

# *__Congratulations! Now you've installed your first Underground Nexus, and you're ready to start building out your cloud.__*