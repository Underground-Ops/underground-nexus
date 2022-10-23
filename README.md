# Underground Nexus - nexus0 Portable Cloud VPS Desktop (Chrome RDP READY)

Enjoy glorious Ubuntu KDE browser-based Desktops with optional Google Chrome RDP Terminal access on Docker or Kubernetes!

**(This Virtual Private Desktop Server can be deployed inside of the Underground Nexus k3d KuberNexus version of Kubernetes or any other flavor of Kubernetes, this may be used as a standalone VPS or for inviting collaborators through the use of Chrome RDP - *nexus0 is a standalone VPS solution that can deploy independently from the Underground Nexus*)**

## A nexus0 VPS can be deployed on an amd64 docker system with two commands:
- `docker run -itd --name=nexus0 -h nexus0 --privileged -e PUID=1050 -e PGID=1050 -e TZ=America/Colorado -p 1000:3000 --restart=always -v nexus0:/config -v /var/run/docker.sock:/var/run/docker.sock natoascode/nexus0`
- `docker exec nexus0 sh nexus0.sh`
- Once the install completes **access your browser desktop at:** http://localhost:1000

**NOTE** that the nexus0 can be deployed on both arm64 and amd64 platforms when using the the nexus0 dockerfile found on GitHub.

To get the nexus0 set up with Chrome RDP access (whether nexus0 is being configured for personal remote access or for inviting guests to collaborator desktops), follow the guidance in the commented sections of the nexus0 script found below.

**Nexus0 GitHub - Underground Nexus Branch:**
- https://github.com/Underground-Ops/underground-nexus/tree/nexus0

## Use the nexus0 script guidance to deploy to any flavor of Kubernetes

**Nexus0's deploy script - `nexus0.sh` script file and guidance:**
# <a href="https://raw.githubusercontent.com/Underground-Ops/underground-nexus/24067a3817a0d33495bdffbaaced7a7f5b4f28c1/nexus0.sh">*Review nexus0 Script and Guidance Here*</a>

**Enjoy using the nexus0, check out the DevSecOps Dojo (from Cloud Underground) for learning or assistance!**
- https://cloudunderground.dev/devsecops-dojo/

# Deploy Underground Nexus to use k3d KuberNexus to Host a VPS (OPTIONAL)

The Underground Nexus is a cloud construction toolkit.  This resource will be receiving dedicated trainings until August of 2022 to teach developer communities how to use this tool for Cloud Native DevSecOps.

Milestones will be added to this resource to present the general release timeline for trainings and features for this kit.

***The Underground Nexus official repository lives here:*** https://github.com/Underground-Ops/underground-nexus

***Learn how to get started with Underground Nexus quick-start guidance here:*** https://youtu.be/sCL8d0uiV3Y?t=284

## Docker Desktop is recommended for developing with the Underground Nexus - Download Docker Desktop here: https://www.docker.com/products/docker-desktop

### Install Step 1 (assuming Docker is already installed) - Open a command line (Windows) or terminal (Linux or OSX) shell and paste the appropriate install command for your computer's hardware platform.

**Dockerhub *DEVELOPMENT* pull for *Docker Desktop or amd64* systems:** `docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 22:22 -p 53:53/tcp -p 53:53/udp -p 80:80 -p 443:443 -p 1000:1000 -p 2375:2375 -p 2376:2376 -p 2377:2377 -p 9010 -p 9050:9443 -p 18443:18443 -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket natoascode/underground-nexus:amd64`

**Dockerhub *SECURE* pull for *Docker Desktop or amd64* systems:** `docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 1000:1000 -p 9050:9443 -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket natoascode/underground-nexus:amd64`

**Dockerhub *DEVELOPMENT* pull for *Raspberry Pi, NVIDIA Jetson and arm64* systems:** `docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 22:22 -p 53:53/tcp -p 53:53/udp -p 80:80 -p 443:443 -p 1000:1000 -p 2375:2375 -p 2376:2376 -p 2377:2377 -p 9010 -p 9050:9443 -p 18443:18443 -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket natoascode/underground-nexus:arm64`

**Dockerhub *SECURE* pull for *Raspberry Pi, NVIDIA Jetson and arm64* systems:** `docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 1000:1000 -p 9050:9443 -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket natoascode/underground-nexus:arm64`

----------------------------------------------------

**IMPORTANT:** After deploying the Underground Nexus from the appropriate `docker run` command for your system, enter the command below for "**Install Step 2**" in the exact same terminal or console in which the `docker run` command ran. *This script does quite a lot and can take a LONG time to complete - depending on the power of your system and internet speeds it can take anywhere from 15 to 45 minutes to complete activating and initializing the Underground Nexus stack.*

### Install Step 2 - Paste activation command in the same shell the first command was entered in, and the Underground Nexus will build and activate itself (2 commands total to deploy - this is the second and final command if there are no errors).  If the command does not seem to work try the alternative install option below.

***ACTIVATE the Underground Nexus (this is the only necessary command to run IMMEDIATELY after deploying the Underground Nexus to activate it):***
**`docker exec Underground-Nexus sh deploy-olympiad.sh`**

**ALTERNATIVE** - From inside of either a Docker Desktop shell to the Underground Nexus container or a Portainer shell into the Nexus, enter this command from inside the Underground Nexus container itself for activation:
`sh deploy-olympiad.sh`

----------------------------------------------------

***The minimum recommended hardware for the Underground Nexus is the Raspberry Pi 4; anything more powerful will also certainly run the Underground Nexus well (compatible with amd64 and arm systems).***

----------------------------------------------------

**Underground Nexus - Cloud Native Server Architecture: *https://github.com/Underground-Ops/underground-nexus/blob/main/Underground_Nexus_Architecture.pdf***

**Quick Start Guide (ESPECIALLY pay attention to *STEP 4* - if using the dockerhub pull, skip to *STEP 3* of guide): *https://github.com/Underground-Ops/underground-nexus/blob/main/Underground_Nexus_Quick_Guide.pdf***

***How to use the Underground Nexus*** **- Once Deployed:**

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
- Pi hole: http://10.20.0.20 (can change password from within Portainer)
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

**Deploying Virtual Machines in Underground Nexus:**

The Underground Nexus can be configured to emulate and run virtual machines inside of its stack with an application called *Virtual Machine Manager* and can be configured to use *QEMU*, which is already pre-installed for immediate use upon being deployed.

Please see the images found in the repository for examples on how to use virtual machines to begin configuring emulated virtual systems.

**Using Underground Nexus Virtual Machines:**
- Walkthrough screenshots steps 1-2: https://github.com/Underground-Ops/underground-nexus/blob/main/Using_Virtual_Machines__1.PNG
- Walkthrough screenshots steps 3-4: https://github.com/Underground-Ops/underground-nexus/blob/main/Using_Virtual_Machines__2.PNG
- Walkthrough screenshot step 5: https://github.com/Underground-Ops/underground-nexus/blob/main/Using_Virtual_Machines__3.PNG

----------------------------------------------------

## Learn about foundational principles for Cloud Native and DevSecOps here: https://gitlab.com/natoascode/nist-draft-regulation-800-204c-comment-notes-and-timestamps

----------------------------------------------------

## Learn about the foundations that the Underground Nexus was built upon here: https://notiapoint.com/pages/the-olympiad
