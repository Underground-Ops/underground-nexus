# __Athena0 Pentesting Toolbox - *Agnostic Cloud Brute Forcer*__ (NEW updates on the way!)
------------------------------------------------------------------------------  
**(THIS PROJECT IS UNDER MAJOR CONSTRUCTION AND MAY HAVE SIGNIFICANT CHANGES OVER THE NEXT FEW MONTHS)**

Athena0 is a tool dedicated to agnostic cloud brute force testing, alongside payload construction and delivery.

Are you looking for an easy way to practice ethical hacking or do you simply want a set of professional pentesting tools with a simple container __toolkit__  you can easily pull and run from a Docker container using *Docker Desktop* (on **ANY** system that can run Docker Desktop), a *Raspberry Pi* or another *ARM* system like a *Jetson Nano*?  
  
------------------------------------------------------------------------------  
**If this is being used for professional payload construction, scripts should be written in the `/home/` directory.  In the home directory, a sample payload that builds the Olympiad package can be found as a review sample - the sample payload found in `/home/` is `olympiad.sh`, and additional payloads may be constructed and added to the directory for use.**  
------------------------------------------------------------------------------  
**To test the sample `olympiad.sh` payload, or build an Olympiad tool suite for *Docker* and *Kubernetes* in general, follow the guidance found here => https://hub.docker.com/repository/docker/natoascode/olympiad-dev**  
------------------------------------------------------------------------------  
  
For *educators* and *learners*, this image can be used to learn **Ethical Hacking** skills!
    
------------------------------------------------------------------------------  
💻 __*Start HACKING*__ 👇  
------------------------------------------------------------------------------  
**--Hide n' Hunt - Ethical Hacking Game & Simulation Setup Guide--**  
  
__How to use Athena0 to pentest or practice hacking:__ 
https://www.youtube.com/watch?v=aZt7BTgK3Fo

__See Athena0 in action with a PVP hacking game called Hide n' Hunt:__ 
https://www.youtube.com/watch?v=UZ2X-wP2djI&t=5s

*Use the guidance here to set up Hide'n Hunt, then provide this guide to every player for instruction on how to play for practicing cloud hacking skills.*
  
__Hide n’ Hunt Lesson and Game Guide - How to Play:__ 
https://docs.google.com/document/d/1mCmjDDgVYk3bNftiGV_xIctOoRlq8tv4xmuECbL6Y-A/edit?usp=sharing
  
(Email nato@natoascode.com to learn more about Hide n’ Hunt for pentesting simulations. -- Thank you __Tony Huynh__ for helping create this game!)

This Athena0 container is one part of an open-source platform called the __Olympiad__, built by the notiaSquad development community, managed by Nato Riley.  This node is configured with ssh for anyone to practice brute force attacks against clones generated from this container.

Athena0 is a payload engineering, recon and delivery toolkit that changes MAC addresses everytime the Athena0 container is restarted.  Tools such as the metasploit framework can be used in conjunction with beEF for building vulnerability payload packages for pentests.  As part of the delivery architecture, nmap and ZAP can be used for __recon__ while tools like Hydra and hashcat can be used independently or together for __brute force__ tests for establishing access for __payload delivery__.
  
__—*Read further to learn how to host ethical hacking DEATH MATCH and Hide n' Hunt tournaments with this for pentest practice* 😈💻👿—__
  
__Default Pentesting Tools (Currently under revision - tool suite is changing):  
Firewalld
| Wireshark
| John the Ripper (offline password cracker)
| Hydra (online password cracker)
| OWASP - ZAP
| Nmap
| Sqlmap
| Metasploit Open Source Framework
| netcat
| hashcat
| beEF (browser exploitation framework)
| macchanger (enabled to automatically change the mac address by default, must uninstall or reinstall to disable this feature)__
  
If you want to practice or deploy brute force attacks (or any other pentesting-related attack), you will need to build at least two of these nodes.  The default name of each node is "Athena0," but nothing will be disrupted if the hostname is set to some other preferred name; title and name the pulled containers whatever you want.

If secured with your own RSA ssh key, the ssh connection on this node can also be used as a means for extra secure remote access to a Raspberry Pi as an access gateway if the host system's port 22 is only open for ssh use internally to localhost.

__Generate Master Athena0 Admin Node:__  

*Be aware that the Athena0 admin nodes are for professional pentesting, while player nodes (Athena1, Athena2, Athena3, etc.) are for practicing pentesting.*

__[STANDARD ADMIN NODE INSTALL]__  
-- --Standard Pull => docker run -itd -p 2222:22 -h Athena0 --name=Athena0 --restart=always -v /home:/home natoascode/athena0

__[STANDARD PLAYER NODE INSTALL TO PRACTICE HACKING]__  
*Configure the Inner-Athena Docker network first*  
-- --docker network create --subnet=172.20.0.0/20 Inner-Athena

*(only the admin node will be named "Athena0" and player nodes should be named according to the number of players - example: Athena1, Athena2, Athena3, etc.)*  
-- --Standard Pull => docker run -itd -p 22 -h Athena1 --name=Athena1 --net=Inner-Athena natoascode/athena0

*Use Portainer to configure user access - read further for more portainer guidance.*

__[ALTERNATE INSTALL WITH PI HOLE]__  
*Configure the Inner-Athena Docker network first*  
-- --docker network create --subnet=172.20.0.0/20 Inner-Athena
  
*Build the Athena0 master node*  
-- --Pull For Pairing With a Pi-Hole Container => docker run -itd -p 2222:22 -h Athena0 --name=Athena0 --net=Inner-Athena --dns=172.20.0.20 --restart=always -v /home:/home -v /var/log:/var/log natoascode/athena0
  
*Run this on the Docker host before installing Pi Hole*  
sudo systemctl disable systemd-resolved.service  
  
*If the above command was successful, the Pi Hole container should run with no errors*  
-- --sudo docker run -itd -p 53:53/tcp -p 53:53/udp -p 67:67 -p 80:80 -p 443:443 -h Inner-DNS-Control --name=Inner-DNS-Control --net=Inner-Athena --ip=172.20.0.20 --restart=always -v /home:/home -v /var/log/pihole.log:/var/log/pihole.log -v /etc/pihole:/etc/pihole pihole/pihole
  
*--(be aware that this "Standard Pull" is not going to work for the tournament since it only opens up port 2222:22 in the docker engine and -v makes the host running Docker more vulnerable)--*
  
-- --If you prefer having a GUI for accessing these containers, we recommend a Docker GUI called Portainer.
Installation guidance is here => https://www.portainer.io/installation/
  
*--(__Portainer__ is __HIGHLY recommended for__ setting up and hosting __hacking tournaments__)--*
  
__*Note that if you want multiple people to connect to a single Raspberry Pi for ethical hacking tournaments, installing Portainer will allow you to set up independent Athena containers and create Portainer user accounts for each participant.  Users can then each access the Raspberry Pi through Portainer via a web browser. Note that even a cell phone can connect to Portainer if not all users have access to a computer.*__

--(keep it consensual)--

*Use the default user account for practicing things like brute-force.*  
Default Username: notitia  
Default Password: notiaPoint!1

------------------------------------------------------------------------------  
------------------HERE IS AN ADDITIONAL MORE ADVANCED ETHICAL HACKING GAME!----------------------
------------------------------------------------------------------------------  
__-- --*OLYMPIAD ASSAULT GRID*-- --__

Pentesting Game Resources (only for those wanting to practice brute force) - [DEATH MATCH TOURNAMENT]:  

__WHEN CLONING Athena0 FOR PARTICIPANTS__  
-- -- Be aware that playing this game may require more ports to be opened to allow the containers to communicate.  Port ranges can be used to simplify this if the user knows how to configure entire open port ranges in the Docker engine.  
__*Athena0 is both the master and admin node meant for cloning or Swarming, clones made from Athena0 for tournament use and play are called “Attack Nodes.”*__

1.  First, you will want to be aware of the scripts you may use with this container (see list below).  Setting up iptables and randomizing passwords is the first thing to do before practicing brute force attacks.  *RANDOMIZE THE PORT USED BY SSH BETWEEN EVERY MATCH ON EVERY ATHENA ATTACK NODE*
-- --Setup Scripts - https://github.com/notiaPoint/notiaSquad-Projects/tree/master/Scripts

2.  Next, you need to configure Hydra between every brute force test or match on every Athena Attack Node.
-- -- Configure Hydra - https://github.com/notiaPoint/notiaSquad-Projects/blob/master/Directions/hydra.md

3.  *BEGIN BATTLE* Now you are ready to begin a hacker death match between all containers running on your Raspberry Pi (4gb Pi can run at least 6 Athenas at once).  After Hydra commands have been run on all hosts, you will want to run an nmap scan to detect the available ports running SSH on every Attack Node.
-- -- Nmap Recon - https://github.com/notiaPoint/notiaSquad-Projects/blob/master/Directions/nmap.md

4.  *FINISH OFF YOUR OPPONENT* Once you identify on which port your opponent is using ssh, you will finally get to brute force your way into your opponent's Athena container and shut them down (remember to randomize the ssh port with scripts between every match). The player with the last Athena Attack Node standing wins!
-- -- Finish Them - __(instead of using shutdown with containers, knock opponents out using the command "*kill pid 1*" - test before playing)__ https://github.com/notiaPoint/notiaSquad-Projects/blob/master/Directions/shutdown.md
  

--(keep it consensual)--
  
__Default Pentesting Tools:  
Firewalld
| Wireshark
| John the Ripper (offline password cracker)
| Hydra (online password cracker)
| OWASP - ZAP
| Nmap
| Sqlmap
| Metasploit Open Source Framework
| netcat
| hashcat
| beEF (browser exploitation framework)
| macchanger (enabled to automatically change the mac address by default, must uninstall or reinstall to disable this feature)__
  
Enable Port in Docker Pull:  
2222:22

System Recommendations:  
Hardware - Raspberry Pi 4B (4gb or 8gb)
| Host OS Running Docker - Raspberry Pi OS with Docker installed

----------------------------------------------------

## Learn about foundational principles for Cloud Native and DevSecOps here: https://gitlab.com/natoascode/nist-draft-regulation-800-204c-comment-notes-and-timestamps

----------------------------------------------------

## Learn about the ongoing Olympiad Project here: https://notiapoint.com/pages/the-olympiad
