# -- Underground Nexus Installer -- Virtual Machine and Container Orchestration Engine --

## Learn to master cloud skills with Underground Nexus. Check out Cloud Jam: https://cloudunderground.dev/products/cloud-jam

- Learn more about the Underground Nexus: https://github.com/Underground-Ops/underground-nexus

# __Cerberus0 Cloud Native Cloud Package Manager and CICD Pipeline - *Agnostic Cloud CICD*__ (NEW updates on the way!)

- The cloud native VMWare / VSPhere alterntive with a complete DevSecOps pipeline from prototype to production 
------------------------------------------------------------------------------  

Manage virtual machines alongside containers seemlessly with complete infrastructure lifecycle management. This resource is an alternative to VSPhere for cloud-native engineering.

This is the master package manager and installer for the Underground Nexus software hypervisor and DevSecOps platform.

This package-management pipeline includes Zarf to provide powerful package management for DevSecOps pipelines and airgapping capabilities. (pre-installed)

Learn more about Zarf here: https://docs.zarf.dev/

Upgrade the Cerberus Manager to operate as a CICD pipeline with Dagger. (pre-installed)

Learn more about Dagger here: https://docs.dagger.io/

This package manager does more than package management: CICD can also be deployed with Dagger and Kubectl is installed by default for managing Kubernetes clusters.

__System Requirements:__

- Windows (AMD64): Requires WSL (Ubuntu recommended - Docker must be installed in WSL)

- Apple Silicon: ARM support coming soon!

- Debian Linux/Ubuntu: Requires Docker

__- CPU: 4cpu minimum (8 recommended)__

__- RAM: 8gb minimum (32gb recommended)__

__- Storage: 50gb minimum (200gb recommended)__

*Since this technology includes a full hypervisor and infrastructure management / development focussed ecosystem, the more resources you have the more you can do with this technology.*

------------------------------------------------------------------------------  

**Tools and Package Management Resources Include:**

*- complete underground pipeline support:*

*-- DEV - launch the DEV option for a virtual desktop*

*-- SEC - deploy the SEC option for a full provisioning environment*

*-- OPS - use OPS to add compatibility and emulation support to a production pipeline (OPS can also be used to scale SEC provisioning environments or solve compatibility challenges for DEV environments)*

*- zarf*

*- git*

*- k3s Kubernetes*

*- kubevit hypervisor*

*- helm package manager*

*- homebrew package manager*

*- soft serve git management server*

*- dagger for cicd*

*- nmap network scanner*

*- cron scheduler*

*- wishlist ssh management*

------------------------------------------------------------------------------

Wishlist is preconfigured to allow this package manager to be used as an ssh server; the startup script at `/usr/local/bin/start_services.sh` can be edited to modify startup services.

Use this command to modify the startup services:
`nano /usr/local/bin/start_services.sh`

To save type `ctrl+x`, next `y` and `enter`
  
------------------------------------------------------------------------------  

# Get started quickly with Ubuntu - Build a hypervisor in minutes (on fast networks)!

- hypervisor resources work best on bare metal installs or virtual machines with nested virtualization - works best with at least 50mbps download speeds though 100mbps download speed is recommended
- test network speeds at [speedtest.net](https://www.speedtest.net/)

__Fastest way to get started - download Ubuntu Server LTS (works with Ubuntu 18 and newer):__

- https://ubuntu.com/download/server

__Fastest way to install Docker so you can get started:__

`#make sure wget and curl are installed`

`apt update && apt install wget curl sudo -y`

`curl -fsSL https://get.docker.com | sudo bash`

------------------------------------------------------------------------------  

# _RECOMMENDED INSTALL `ACCELERATED VIRTUAL MACHINE ENGINE` AND DEVSECOPS PACKAGE MANAGER - *Run the following commands to set up the Underground Nexus Package Manager, called the Cerberus Manager*_

__Run Underground Nexus Installer Script in Ubuntu / Debian (or from WSL with Ubuntu if using Windows):__

`curl -fsSL https://raw.githubusercontent.com/Underground-Ops/underground-nexus/refs/heads/cerberus0/underground-nexus-installer.sh | sudo bash`

------------------------------------------------------------------------------ 
------------------------------------------------------------------------------ 

__Alternate Lighter Weight Install - Deploy with NO Virtual Machine Engine (best option for **Docker Desktop** or Colima):__

`docker run -itd --init --privileged --name=Cerberus-Manager -h Cerberus-Manager --net=host --restart=always -v /root/nexus-bucket:/nexus-bucket -v /var/run/docker.sock:/var/run/docker.sock natoascode/cerberus0:latest sh -c "mkdir -p /root/nexus-bucket && bash /nexus-devsecops-appinator.sh || true && exec bash"`

# ACCESS THE CERBERUS MANAGER CLI -- Once installed you can enter the Cerberus-Manager CLI shell to get started -- Use: 

`docker exec -it Cerberus-Manager bash`

# Choose the Underground Nexus installs that are right for your server build.
Once you've activated the Underground Nexus Installer, choose the Underground Nexus install script that matches your use case from the list below. Copy the code below from your chosen install, and paste it into the Underground Nexus Installer terminal. 

## NOTICE: The `DEV` and `SEC` commands can take a VERY long time - these commands may take 20+ minutes to complete (don't be surprised if these commands take a while)

# DEV - Staging Sandbox Desktop [Recommended Install]
- Install a Nexus Creator Vault configured for acceleration with AI, powered by Ollama and GitHub Copilot.

To deploy DEV mode type: `docker exec Cerberus-Manager DEV`

(typing `DEV` in the Cerberus Manager CLI deploys the command below)

`docker run -itd --name=nexus-creator-vault -h nexus-creator-vault -p 1050:3000 -e PUID=1050 -e PGID=1050 -e TZ=America/Colorado --restart unless-stopped -v /dev:/dev -v creator-vault000:/config -v /var/run/docker.sock:/var/run/docker.sock natoascode/zero-trust-cockpit:creator-vault`

Once complete head over to: http://localhost:1050

This is a powerful, hardware-accellerated virtual desktop space where you can accellerate resources that can be used for AI, blockchain, graphics generation, and beyond.

If you need to build a Virtual Machine to test or learn with, and if you do not need the scalability of KubeVirt, this virtual desktop contains a hypervisor engine that allows you to build and manage virtual machines.

The virtual machines that you build and decide to scale can be deployed to KubeVirt for production use and increased scalability.

Verify that your hardware has virtualization enabled - Type the following command to make sure "accelleration" is enabled:
`sudo kvm-ok`

This virtual desktop is AI-powered with Ollama.

Learn more about Ollama: https://ollama.com/ 

To start using the AI, try opening a terminal (such as Konsole) and type:
`ollama run mistral`

Learn more about Mistral: https://ollama.com/library/mistral:7b 

Congratulations! You now have a local AI instance running on your local hardware that's private just for you!

Don't forget to check out Visual Studio Code and explore the GitHub Copilot integration to get a boost to your coding efforts.

This system may be used as an MCP server if configured to be used as one with Ollama (or an alternative) for private AI system management.

Since this is open-source and based on Ubuntu, you may integrate any other AI resource of choice!

# SEC - Security, CICD, Provisioning
- Install a complete Underground Nexus management pipeline: provision, stage, and release to production (THIS AUTOMATICALLY DEPLOYS THE `STANDARD VIRTUAL MACHINE ENGINE` - use the `ACCELLERATED VIRTUAL MACHINE ENGINE` for maximum virtual machine performance).

To deploy SEC mode type: `docker exec Cerberus-Manager SEC`

(typing `SEC` in the Cerberus Manager CLI deploys the command below)

`docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 22:22 -p 80:80 -p 8080:8080 -p 443:443 -p 1000:1000 -p 2375:2375 -p 2376:2376 -p 2377:2377 -p 9010:9010 -p 9050:9443 -p 18080:8080 -p 18443:18443 -v /dev:/dev -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket natoascode/underground-nexus:amd64 && docker exec Underground-Nexus bash deploy-olympiad.sh`

Deploy an entire Underground Nexus containerized engine that can be used to manage security and DevSecOps. This layer can be used for provisioning and debugging. It is also a great place to host fellow engineers in their own Nexus Creator Vault virtual destktops so they may contribue to projects.

Access the Underground Nexus workbench at: http://localhost:1000

Access Portainer for an Underground Nexus container UI at: https://localhost:9050

Check out the Underground Nexus to learn more: https://github.com/Underground-Ops/underground-nexus 

# OPS - Compatibility & Scaling Node
- Unactivated Underground Nexus ready to integrate with an Underground Nexus swarm or run Nexus Creator Vault in compatibility mode.

To deploy OPS mode type: `docker exec Cerberus-Manager OPS`

(typing `OPS` in the Cerberus Manager CLI deploys the command below)

`docker run -itd --name=Underground-Ops -h Underground-Ops --privileged --init -p 1060:1050 -v /dev:/dev -v underground-ops-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket natoascode/underground-nexus:amd64`

If the Nexus Creator Vault is not deploying properly, or if you are testing and debugging, then this allows you to experience improved compatibility by building containers inside of this Docker-in-Docker container.

This Docker-in-Docker container can also be used to swarm with Underground Nexus Managers ready to scale.

Try building a Docker Swarm cluster with this to see how it works!

This is also the a great place to deploy CICD (Continuous Integration and Continuous Deployment) runners that need their own Docker socket, especially quality assurance runners focussed on testing code before a project is sent to production.

Learn more about buildng Swarm Clusters: https://docs.docker.com/engine/swarm/ 

Use the following rebuild commands from `Cerberus-Manager` to automatically delete and rebuild any of the `DEV`, `SEC` or `OPS` instances:

- `DEV-rebuild`

- `SEC-rebuild`

- `OPS-rebuild`

**WARNING: These rebuild commands will completely *DELETE* all volumes and data stored in these intances! (only use these commands if you wish to fully wipe and reload the `DEV`, `SEC` or `OPS` environments)**

# *__Congratulations! Now you've installed your first Underground Nexus, and you're ready to start building out your cloud.__*

------------------------------------------------------------------------------  

# Here is your first virtual machine template that can be used to workshop with Ollama, GitLab Duo, and GitHub Copilot

Refer to the official documentation for how to make custom virtual machine configurations and execute helpful commands:

- https://kubevirt.io/user-guide/user_workloads/accessing_virtual_machines/

1. __Download and run the lubuntu virtual machine template - use nano to make any edits to resources incuding but not limited to CPU, RAM, and any other virtual machine configuration:__

`wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/refs/heads/cerberus0/Virtual%20Machine%20Templates/lubuntu-vm/deploy-lubuntu-vm-template.sh`

(This script downloads a lubuntu .iso image, configures persistent storage, and deploys a virtual machine.)

2. Review and edit the script using `nano` before running (optional):

`nano deploy-lubuntu-vm-template.sh`

(This file allows you to adjust the cpu and ram, alongside any other setting for the virtual machine, before executing the script - share this with an AI LLM helper of choice to get support to make desired changes.)

3. Run the command below then head to the virtual machine at the KubeVirt Manager UI to manage the virtual machine and access its desktop:

`bash deploy-lubuntu-vm-template.sh`

- __Access Virtual Machine Manager UI:__ http://localhost:8080 

(If using the Undergrond Nexus SEC container instead of the default k3s kubernetes configuration depoyed from the Cerberus Manager then the default port is instead: http://localhost:18080)

4. Install the lubuntu iso image and then once the virtual machine asks to eject the iso disk - run this command:

`wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/refs/heads/cerberus0/Virtual%20Machine%20Templates/lubuntu-vm/eject-vm-iso-disk.sh && bash eject-vm-iso-disk.sh`

(Head back to the virtual machine manager to access your fully prepared ready-to-use lubuntu virtual machine.)

__Provide these templates to your favorite AI code helper to configure your next virtual machine!__

------------------------------------------------------------------------------  

# **__Use AI in the DEV desktop to configure a VSPhere (from VMWare) alternative__**

The Underground Nexus ecosystem is completely open-source and vendor agnostic, making it an incredibly economic cloud-native technology for managing production resources at scale.

Use the DEV desktop (configured to http://localhost:1050 by default) to use GitHub Copilot, GitLab Duo, and Ollama to upgrade your Kubernetes cluster to be a full enterprise-grade VSPhere alternative.

__--Gatekeeper - Policy Enforcement--__

https://github.com/open-policy-agent/gatekeeper

__--Velero - Backup Management--__

https://github.com/vmware-tanzu/velero

__--Harvester - Virtual Machine Engine Upgrade for Storage Management and a Complete Orchestration Management UI--__

https://docs.harvesterhci.io/v1.3/vm/index/

__--Rancher - UI for Production Infrastructure Management--__

https://ranchermanager.docs.rancher.com/getting-started/installation-and-upgrade/install-upgrade-on-a-kubernetes-cluster

__--Harvetster Rancher Integration - Integrate wtih Rancher for Master UI - Manager Containers and VM's Together--__

https://docs.harvesterhci.io/v1.2/rancher/index/

*Provide these links to an AI to use `kubectl` from the Cerbereus Manager's shell to build out a complete Harvester configuration that uses Rancher to allow virtual machines and containers to be managed together seemlessly at scale.*

**To get started - enter the Underground Nexus Cerberus-Manager (package manager) CLI shell with this commmand:** 
`docker exec -it Cerberus-Manager bash`

*After running the command above, test Kubernetes by typing `kubectl get nodes` from the Cerberus-Manager shell.*

## Learn to master cloud skills with Underground Nexus. Check out Cloud Jam: https://cloudunderground.dev/products/cloud-jam