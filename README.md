# Underground Nexus Development

**(*NOTE* - This resource is still in BETA!  Expect rough edges until refined.)**

The Underground Nexus is a cloud construction toolkit.  This resource will be receiving dedicated trainings until August of 2022 to teach developer communities how to use this tool for Cloud Native DevSecOps.

Milestones will be added for this resource to present the general release timeline for trainings and features for this kit.

----------------------------------------------------

**Underground Nexus - Cloud Native Server Architecture:**
![Underground_Nexus_Architecture_1__1_](/uploads/87e217dad309d090dbdb6d997de29525/Underground_Nexus_Architecture_1__1_.png)![Underground_Nexus_Architecture_2__2_](/uploads/51c0d29458da401072dfd3269ee8e613/Underground_Nexus_Architecture_2__2_.png)![Underground_Nexus_Architecture_3](/uploads/fe423f51005789e46eb4db87230c20e3/Underground_Nexus_Architecture_3.png)![Underground_Nexus_Architecture_4](/uploads/6535f90cf47b488dbfc574e8fa196519/Underground_Nexus_Architecture_4.png)

**Quick Start Guide:**
[Underground_Nexus_Quick_Guide.pdf](/uploads/637b77f704da8b7144765e6d6a1c39fa/Underground_Nexus_Quick_Guide.pdf)

***How to use the Underground Nexus*** - **Once Deployed**:

**1.** Access the Nexus MATE admin desktop at "http://localhost:1000" - If deployed on ARM, Visual Studio Code will need to be manually installed.  On amd64 builds you will see Visual Studio Code, GitHub Desktop and GitKraken listed in the MATE desktop. (the webtop is a loadbalancer, not just a desktop)

**2.** The Nexus is designed to only need one open port to operate for maximum security (port 1000, also port 9443 is a safe second port to be open due to having `https` and port 2000 can be used for a least privileged Security Operation Center dashboard builder - ports beyond these three need to have purpose).  Every other port opened should be opened with intention and monitoring, which the Pi hole monitors all default apps by default (the recommended open port for primary access is http://localhost:1000, Portainer with https can be made securely available at http://localhost:9443 and the SOC can be made available optionally at http://localhost:2000 - keep in mind that port 1000 is a portal to root access, so keep security in mind for port 1000).

**3.** k3d cannot be ran from inside of any webtop (security reasons), rather k3d must be used directly inside the Underground Nexus Alpine Linux (Docker in Docker) host container that runs the docker engine.  Once a kubernetes cluster has been deployed, webtops can then manage deployed kubernetes clusters.

**4.** To access other Nexus apps, the apps are accessible from inside Firefox or any web browser inside the Nexus MATE admin desktop.

**5.** GitHub makes for an easy to use Single Sign On solution for setting up developer tools to use Nexus.  Visual Studio Code can be integrated from GitHub with Code Spaces for cloud compute scaling to get more power for development.

**6.** The Kali shell is secured behind Portainer's login for security purposes by default, configure Kali Linux for ssh to give ssh access to the entire Nexus through the Kali Athena0 node as a gateway.

**7.** The Athena0 Kali node happens to be a primary monitoring point for Grafana and Loki, and also includes Radare2 (forensics tool used by NSA) for deep analysis that can be monitored with Grafana dashboards.

**8.** Nexus can be turned into an ultra Pi hole if it's DNS server ports are opened when Nexus is deployed (ports 53 and 67).  This would allow the Underground Nexus to be used as a company or home SOC that can have data integrated with Pi hole data using Grafana and Loki)

**9.** Default URL's will show up if Nexus deploys without errors (these will ONLY exist from inside a webtop web browser - Firefox works with these addresses from within the Nexus desktops):
-Portainer: https://10.20.0.1:9443
-Pi hole: http://10.20.0.20 (can change password from within Portainer)
-Cyber Life Torpedo (S3 bucket): http://10.20.0.1:9001 (default `user`:`password` is `minioadmin`:`minioadmin`)
-Ubuntu MATE Admin Desktop: http://10.20.0.1:1000 (runs as root - default `user`:`password` is `abc`:`abc`)
-Ubuntu KDE Security Operation Center Desktop: http://10.20.0.30:2000 (least privilege - default `user`:`password` is `abc`:`abc`)

----------------------------------------------------

**Deploying Virtual Machines in Underground Nexus:**

The Underground Nexus can be configured to run virtual machines inside of it's stack with an application called *Virtual Machine Manager* and configuring it to use *QEMU* which is already pre-installed for immediate use upon being deployed.

Please see the images below to understand the process of setting up Underground Nexus to run virtual machines.

***Using Virtual Machines:***
![Using_Virtual_Machines__1](/uploads/fe4382703be494001fd6b054a812d7f0/Using_Virtual_Machines__1.PNG)![Using_Virtual_Machines__2](/uploads/7f544765f208e50f90f293fa24104589/Using_Virtual_Machines__2.PNG)![Using_Virtual_Machines__3](/uploads/601b3142c7a7738646b83b5bf7563706/Using_Virtual_Machines__3.PNG)
