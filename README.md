# Underground Nexus - Copy/Paste Data Center and DevSecOps Software Factory

**Release Version 1.0.1**

<img style="max-width: 300px; max-height: 300px" src="https://github.com/Underground-Ops/underground-nexus/blob/main/Graphics/SVG/cloud-underground-logo.svg" alt="Cloud Underground Logo"> <img style="max-width: 300px; max-height: 300px" src="https://github.com/Underground-Ops/underground-nexus/blob/main/Graphics/SVG/new-nexus-logo.svg" alt="Underground Nexus Logo">

----------------------------------------------------

### Table of Contents

- <a href="#introduction">Intro & Helpful Links</a>

- <a href="#install-step-1-assuming-docker-is-already-installed---open-a-command-line-windows-or-terminal-linux-or-osx-shell-and-paste-the-appropriate-install-command-for-your-computers-hardware-platform">Install Step 1</a>

- <a href="#install-step-2---paste-activation-command-in-the-same-shell-the-first-command-was-entered-in-and-the-underground-nexus-will-build-and-activate-itself-2-commands-total-to-deploy---this-is-the-second-and-final-command-if-there-are-no-errors--if-the-command-does-not-seem-to-work-try-the-alternative-install-option-below">Install Step 2</a>

- <a href="#how-to-use-the-underground-nexus---once-deployed">How to Use Underground Nexus</a>

- <a href="#deploying-virtual-machines-in-underground-nexus">How to Deploy Virtual Machines in Underground Nexus</a>

- <a href="#underground-nexus-architecture">Underground Nexus Architecture</a>

- <a href="#learn-about-foundational-principles-for-cloud-native-and-devsecops-here-httpsgitlabcomnatoascodenist-draft-regulation-800-204c-comment-notes-and-timestamps">More Resources</a>

----------------------------------------------------

## INTRODUCTION

<img src="https://github.com/Underground-Ops/underground-nexus/blob/cdcb0a3ee862c8c4f029fed6c45fe280786d4173/Graphics/SVG/nexus-software-factory.svg" alt="Underground Nexus Software Factory">

The Underground Nexus is a **hyperconverged data center** that contains a specialized cloud construction toolkit for cloud-native engineering, DevSecOps and all-around general data center needs.

What is a hyperconverged data center? **-->** <a href="https://www.sdxcentral.com/data-center/hyperconverged/definitions/what-is-hyperconverged-data-center/#:~:text=A%20hyperconverged%20data%20center%20is,network%2C%20and%20storage%20commodity%20hardware.">Learn more here!</a>

***The Underground Nexus official repository lives here:*** https://github.com/Underground-Ops/underground-nexus

***Check out how to get started with Underground Nexus quick-start guidance here:*** https://youtu.be/lhzhLCprrYE

### Docker Desktop is recommended for developing with the Underground Nexus - Download Docker Desktop here: https://www.docker.com/products/docker-desktop

## Install Step 1 (assuming Docker is already installed) - Open a command line (Windows) or terminal (Linux or OSX) shell and paste the appropriate install command for your computer's hardware platform.

**Dockerhub *DEVELOPMENT* pull for *Docker Desktop or amd64* systems:** `docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 22:22 -p 53:53/tcp -p 53:53/udp -p 80:80 -p 8080:8080 -p 443:443 -p 1000:1000 -p 2375:2375 -p 2376:2376 -p 2377:2377 -p 9010:9010 -p 9050:9443 -p 18443:18443 -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket natoascode/underground-nexus:amd64`

**Dockerhub *SECURE* pull for *Docker Desktop or amd64* systems:** `docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 1000:1000 -p 9050:9443 -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket natoascode/underground-nexus:amd64`

**Dockerhub *DEVELOPMENT* pull for *Apple M1, Raspberry Pi, NVIDIA Jetson and arm64* systems:** `docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 22:22 -p 53:53/tcp -p 53:53/udp -p 80:80 -p 8080:8080 -p 443:443 -p 1000:1000 -p 2375:2375 -p 2376:2376 -p 2377:2377 -p 9010:9010 -p 9050:9443 -p 18443:18443 -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket natoascode/underground-nexus:arm64`

**Dockerhub *SECURE* pull for *Apple M1, Raspberry Pi, NVIDIA Jetson and arm64* systems:** `docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 1000:1000 -p 9050:9443 -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket natoascode/underground-nexus:arm64`

----------------------------------------------------

**IMPORTANT:** After deploying the Underground Nexus from the appropriate `docker run` command for your system, enter the command below for "**Install Step 2**" in the exact same terminal or console in which the `docker run` command ran. *This script does quite a lot and can take a LONG time to complete - depending on the power of your system and internet speeds it can take anywhere from 15 to 45 minutes to complete activating and initializing the Underground Nexus stack.*

## Install Step 2 - Paste activation command in the same shell the first command was entered in, and the Underground Nexus will build and activate itself (2 commands total to deploy - this is the second and final command if there are no errors).  If the command does not seem to work try the alternative install option below.

***ACTIVATE the Underground Nexus (this is the only necessary command to run IMMEDIATELY after deploying the Underground Nexus to activate it):***
**`docker exec Underground-Nexus bash deploy-olympiad.sh`**

**ALTERNATIVE ACTIVATION** - From inside of either a Docker Desktop shell to the Underground Nexus container or a Portainer shell into the Nexus, enter this command from inside the Underground Nexus container itself for activation:
`bash deploy-olympiad.sh`

**ALTERNATIVE FOR LOW POWERED DEVICES AND "LIGHTWEIGHT" DEPLOYMENT ACTIVATIONS** - *Systems with **under 8GB worth of RAM** will perform best using the light deployment of the Underground Nexus that that lacks KuberNexus, the underground-ops.me domain and non-essential tools. (apps remoed include Vault, the SOC, Traefik, Wordpress, GitLab, collaborator workbenches, k3d/Kubernetes)* -- From inside of either a Docker Desktop shell to the Underground Nexus container or a Portainer shell into the Nexus, enter this command from inside the Underground Nexus container itself for activation:
`bash olympiad-deploy-light.sh`

**Head to Portainer to Log In at - *https://localhost:9050*:**
- Reset Portainer for initial login if locked out using `docker exec Underground-Nexus docker restart Olympiad0`
- Once the install script completes head to *http://localhost:1000* and open **_Firefox_** to find the **_Git-BIOS Control Panel_** to get started using the Underground Nexus resources and tools

----------------------------------------------------

***The minimum recommended hardware for the Underground Nexus is the Raspberry Pi 4 (4GB RAM or more); anything more powerful will also certainly run the Underground Nexus well (compatible with amd64 and arm systems).***

----------------------------------------------------

## ***How to use the Underground Nexus*** **- Once Deployed:**

**1.** Access the Nexus MATE admin desktop at "http://localhost:1000" - If deployed on ARM, Visual Studio Code will need to be manually installed.  On amd64 builds you will see Visual Studio Code, GitHub Desktop and GitKraken listed in the MATE desktop. (The webtop is a loadbalancer, not just a desktop.)

**2.** The Underground Nexus is designed to only need one open port to use, for security purposes (port 1000 is the single access port - alternatively, port 9050 is a safe second port to have open due to having `https`, and optionally port 2000 can be used for a least privileged Security Operation Center dashboard builder - ports beyond these three need to have purpose).  Every other port opened should be opened with intention and monitoring, which the Pi hole monitors all default apps by default (the recommended open port for primary access is http://localhost:1000, Portainer with https can be made securely available at https://localhost:9050 and the SOC can be made available optionally at http://localhost:2000 - keep in mind that port 1000 is a portal to root access, so keep security in mind for port 1000).

**3.** Inside of the Portainer interface, KuberNexus can be found for using Kubernetes.  To modify KuberNexus or to create a custom cluster of your own, the MATE admin desktop's terminal works with the `k3d` command which allows Kubernetes clusters to be built or modifed.

**4.** Nexus apps are accessible from inside Firefox or any web browser inside the Nexus MATE admin desktop.

**5.** GitHub makes for an easy-to-use Single Sign On solution for setting up developer tools to use Nexus.  Visual Studio Code can be integrated from GitHub with Code Spaces for cloud compute scaling to get more power for development.

**6.** The Kali shell is secured behind Portainer's login for security purposes by default.  Configure Kali Linux for ssh to give ssh access to the entire Nexus through the Kali Athena0 node as a gateway.

**7.** The Athena0 Kali node happens to be a primary monitoring point for Grafana and Loki and also includes Radare2 (forensics tool used by NSA) for deep analysis that can be monitored with Grafana dashboards.

**8.** Nexus can be turned into an ultra Pi hole if its DNS server ports are opened when Nexus is deployed (ports 53 and 67).  This would allow the Underground Nexus to be used as a company or home SOC that can have data integrated with Pi hole data using Grafana and Loki).

**9.** Default URLs will show up if Nexus deploys without errors - **the links below can be used from inside the Nexus desktop if accessing this GitHub URL from inside the Firefox browser within the Nexus MATE desktop itself** (these will ONLY exist from inside a webtop web browser - Firefox works with these addresses from within the Nexus desktops):
- Portainer: https://10.20.0.1:9443
- Pi hole: http://10.20.0.20:800 (can change password from within Portainer)
- Grafana: https://grafana.underground-ops.me/ and http://10.20.0.1:3000/
- Wazuh: https://wazuh.underground-ops.me:5601/ and https://10.20.0.1:5601/
- Cyber Life Torpedo (S3 bucket): http://10.20.0.1:9010 (default `user`:`password` is `minioadmin`:`minioadmin`)
- Ubuntu MATE Admin Desktop: `http://10.20.0.1:1000` (runs as root - default `user`:`password` is `abc`:`abc` - don't access this host from inside the Underground Nexus MATE Desktop)
- Ubuntu KDE Security Operation Center Desktop: http://10.20.0.1:2000 (least privilege - default `user`:`password` is `abc`:`abc`)
- Underground Nexus Secret Vault: http://10.20.0.1:8200 (default password is `myroot` - it is recommended to **not** make this port available for access outside of the Underground Nexus)
- **Visual Studio Code** browser-accessible WebApp: http://10.20.0.1:18443 (be aware this VSC version is more locked down than the Visual Studio Code found on the MATE admin desktop)

**10.** Here are the default apps mapped to the **development** ports if opened for access outside of the Underground Nexus
(it's recommended to only open ports 1000 and 9443 unless other ports are being used intentionally - port 22 allows ssh access through a Kali Linux node, and any port being used can be opened as needed, however, Nexus is more securely accessed from inside the Underground Nexus *MATE Admin Desktop*):
- Portainer: 9050 (test https://localhost:9050 for access)
- Kali Linux Athena0: 22 (open this port to turn a machine's ssh port into a Kali Linux-based development, delivery and forensic analysis center powered by `radare2` - must first enable ssh from within Kali Linux to use remote shell access this way)
- Pi hole: 80, 53 (test http://localhost for access - the Underground Nexus can be used as a powerful Pi hole for any device, if the Underground Nexus host IP address is used as a DNS server with port 53 open)
- Cyber Life Torpedo (S3 bucket): 9010 (test http://localhost:9010 for access - this port can be used to move files in and out of the Underground Nexus or to turn the Nexus into a NAS - Network Attached Storage)
- Ubuntu MATE Admin Desktop: 1000 (test http://localhost:1000 for access)
- Ubuntu KDE Security Operation Center Desktop: 2000 (test http://localhost:2000 for access)
- Web-browser accessible version of **Visual Studio Code**: 18443 (test http://localhost:18443 for access - be aware this VSC version is more locked down than the Visual Studio Code found on the MATE admin desktop)

**11.** From inside Portainer there is a *Kali Linux* system titled *Athena0* (access the terminal with Athena0's **>_** icon seen inside of Portainer's menu) - this tool is designed for pentesting and chaos engineering:
- Tools include: Terraform (`terraform`), Metasploit (`msfconsole`), `nmap` and the Kali Linux `Bleeding Edge` repository for extensive resource access
- This Athena0 node is designed as a super admin access gateway that can be configured to port 22 for accessing the Underground Nexus remotely (by default ssh is not configured in Athena0 to be accessible - please ensure the Underground Nexus is behind a firewall before configuring ssh access to the Underground Nexus with this node)
- Both the Underground Nexus root shell and Ubuntu MATE terminal shell are able to send commands to Athena0 using `docker exec Athena0` followed by the desired command (for example, try `docker exec Athena0 terraform -v`)
- Thanks to Terraform being paired with Metasploit, payloads can be distributed at scale from Athena0 for **Chaos Engineering** and general construction.
- This resources is valuable for **bug bounty hunting** with the Underground Nexus

**12.** Terraform comes pre-installed for immediate use from both the Underground Nexus MATE Desktop's terminal and the Athena0 Kali Linux node:
- Use Terraform from the MATE Desktop terminal for general use
- Use Terraform from the Athena0 node for more aggressive use that might require super admin level access and full `root` privileges

----------------------------------------------------

## Deploying Virtual Machines in Underground Nexus:

The Underground Nexus can be configured to emulate and run virtual machines inside of its stack with an application called *Virtual Machine Manager* and can be configured to use *QEMU*, which is already pre-installed for immediate use upon being deployed.

Please see the images found in the repository for examples on how to use virtual machines to begin configuring emulated virtual systems.

### Using Underground Nexus Virtual Machines:
- Walkthrough screenshots

<img src="https://github.com/Underground-Ops/underground-nexus/blob/cdcb0a3ee862c8c4f029fed6c45fe280786d4173/Using_Virtual_Machines__1.PNG" alt="Walkthrough screenshots steps 1-2">

<img src="https://github.com/Underground-Ops/underground-nexus/blob/cdcb0a3ee862c8c4f029fed6c45fe280786d4173/Using_Virtual_Machines__2.PNG" alt="Walkthrough screenshots steps 3-4">

<img src="https://github.com/Underground-Ops/underground-nexus/blob/cdcb0a3ee862c8c4f029fed6c45fe280786d4173/Using_Virtual_Machines__3.PNG" alt="Walkthrough screenshots steps 5">

----------------------------------------------------

## Underground Nexus Architecture

**Underground Nexus - Cloud Native Server Architecture: *https://github.com/Underground-Ops/underground-nexus/blob/main/Underground_Nexus_Architecture.pdf***

**Quick Start Guide (ESPECIALLY pay attention to *STEP 4* - if using the dockerhub pull, skip to *STEP 3* of guide): *https://github.com/Underground-Ops/underground-nexus/blob/main/Underground_Nexus_Quick_Guide.pdf***

<img src="https://github.com/Underground-Ops/underground-nexus/blob/cdcb0a3ee862c8c4f029fed6c45fe280786d4173/Graphics/SVG/super-root-cluster.svg" alt="Underground Nexus Super Roots">

The Underground Nexus allows business owners to grow your #tech organically like a garden - start with what you have and grow it your way. What the heck is the Underground Nexus?!

The Underground Nexus from Cloud Underground is a hyperconverged #datacenter and copy paste #software factory, meaning it is a microservices based and built data center that can scale even across hardware that might not be compatible to orchestrate otherwise.

That was a mouthful, let's break it down a bit more...

- The Underground Nexus is a containerized kernel known as a "super root" system. (DigitalOcean defines kernels here: https://lnkd.in/gcpQvnqZ)
- A "super root" cluster is a cluster of Underground Nexus nodes, in which each node maps to hardware kernel inputs and outputs (IO) based on how the developer designs IO mappings for an Underground Nexus hosted application (can be a Swarm or it can use a rootless orchestrator such as being configured for rootless Kubernetes).
- "Super root" clusters are defined as "super" due to the need to protect super root kernel layers since they possess privileged access to hardware IO, all super roots as a result come heavily equipped with monitoring out of the box alongside SIEM and XDR that's preconfigured for security use.
- Super roots allow Underground Nexus users to start with whatever server infrastructure they currently have available, and scale with very few limits down the road as they grow without needing to build for 3+ years worth of computing costs up front (could start with a budget of $0 or $1,000 and then scale endlessly as you grow).
- The Underground Nexus kernel (referred to as a "Git-BIOS") can be managed via a single source of truth in the form of a Git repository, which means 100% of the Underground Nexus can be managed with CICD runners.
- Underground Nexus is a cloud native kernel, meaning that it can cluster multiple hardware nodes together to run as one single serverless server (even if the hardware isn't all the same or living in the same location).
- The Underground Nexus can run on-premise or with any flavor of public cloud that can run Docker or Kubernetes, it can even make AWS, Azure, GCP, Linode and beyond all run together as one single orchestrated application hosting environment while also being less work than manually configuring one single computing environment.
- GitLab powers the heart of the Underground Nexus, allowing a "super root" cluster to be capable of scaling with serverless functions, rather than exclusively scaling with your chosen container orchestrator.
- Applications look the same on the surface for end users, except the lower hosting costs can mean superior customer service support budgets.

The Underground Nexus is free to use anytime, #build at your own pace.

Grow your glory!

<img src="https://github.com/Underground-Ops/underground-nexus/blob/cdcb0a3ee862c8c4f029fed6c45fe280786d4173/Graphics/SVG/software-factory-pipeline.svg" alt="Underground Nexus Software Factory Pipeline">

<img src="https://github.com/Underground-Ops/underground-nexus/blob/cdcb0a3ee862c8c4f029fed6c45fe280786d4173/Graphics/SVG/cloud-native-git-bios.svg" alt="Cloud Underground's Cloud-native Git-BIOS">

<img src="https://github.com/Underground-Ops/underground-nexus/blob/cdcb0a3ee862c8c4f029fed6c45fe280786d4173/Graphics/SVG/git-bios-engine.svg" alt="The Git-BIOS Engine">

<img src="https://github.com/Underground-Ops/underground-nexus/blob/cdcb0a3ee862c8c4f029fed6c45fe280786d4173/Graphics/SVG/developer-site-architecture.svg" alt="Underground Nexus Developer Site Architecture">

----------------------------------------------------

## Learn about foundational principles for Cloud Native and DevSecOps here: https://gitlab.com/natoascode/nist-draft-regulation-800-204c-comment-notes-and-timestamps

----------------------------------------------------

## Learn about the foundations that the Underground Nexus was built upon here: https://notiapoint.com/pages/the-olympiad

----------------------------------------------------

## Helpful Videos

**Ditch VPN's and go 100% Zero Trust:** https://www.youtube.com/watch?v=IYmXPF3XUwo

**Publish a Zero Trust Wordpress Website directly from Underground Nexus with Cloudflare:** https://youtu.be/ey4u7OUAF3c
