#!/bin/bash
#------------------------------------
#Nexus0 is a "copy paste" Cloud Native server node that may be deployed to container orchestrators (such as Kubernetes and Docker) - *Though Nexus0 is a component of the Underground Nexus "copy paste" datacenter environment, it __may run as a standalone server__ node even without the Underground Nexus*
#------------------------------------
#--*Copy paste* this "nexus0" template inside of a Kubernetes (or KuberNexus) cluster to test: `kubectl run nexus0 -i --tty --image natoascode/nexus0:latest`
#------------------------------------
#name a file "nexus0.sh" and paste this script inside with "sudo apt update" then "sudo apt install nano" to ubild a script -- ctrl + x , y, enter (to save inside nano)
#------------------------------------
#alternatively this script may be pulled with `wget` or `curl` (install wget example: `apt update && apt install -y wget`)
#download example string with `wget` to pull this script to a computer: `wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/nexus0.sh`
#------------------------------------
#the following command can be used to enter the nexus0 shell using kubectl: `kubectl exec -it nexus0 -- /bin/bash`
#------------------------------------
apt update
apt install -y ssh
apt install -y wget
wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
sudo dpkg -i chrome-remote-desktop_current_amd64.deb
apt install -y -f
wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/github-desktop.sh
bash github-desktop.sh
apt update
wget https://release.gitkraken.com/linux/gitkraken-amd64.deb
sudo dpkg -i gitkraken-amd64.deb
apt -y upgrade --fix-broken
#to manually enable ssh - `service ssh enable`
#to start ssh - `service ssh start`
#get ip address - `hostname -i`
#ssh into user to launch chrome rdp - ssh abc@ipaddressfromlastcommand
#password - "notiaPoint1"
#change terminal CLI user from "root" to "abc" in the >_ Console without using ssh to switch from "root" to "abc" - `su - abc`
#Use the chrome RDP application to get an "install via ssh" authentication string for "linux"
#copy paste the authentication string into the "abc" ssh shell (don't use sudo - must be using ssh with "abc" or the chrome rdp setup will fail)

#------------------------------------
#Change kde background
#KDE wallpaper location: /usr/share/wallpapers/KubuntuLight/contents/images/1440x900.jpg
#Old version wallpaper location: /usr/share/wallpapers/Next/contents/images/1440x900.jpg
#------------------------------------

#sea-space-jelly wallpaper for kde ubuntu
cd /usr/share/wallpapers/KubuntuLight/contents/images
sudo rm 1440x900.jpg
sudo wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Wallpapers/nexus0-sea-space-jelly-highres.jpg -O 1440x900.jpg
sudo rm 1280x800.jpg
sudo cp 1440x900.jpg 1280x800.jpg
sudo rm 1366x768.jpg
sudo cp 1440x900.jpg 1366x768.jpg
sudo rm 1600x1200.jpg
sudo cp 1440x900.jpg 1600x1200.jpg
sudo rm 1680x1050.jpg
sudo cp 1440x900.jpg 1680x1050.jpg
sudo rm 1920x1080.jpg
sudo cp 1440x900.jpg 1920x1080.jpg
sudo rm 1920x1200.jpg
sudo cp 1440x900.jpg 1920x1200.jpg
sudo rm 2560x1440.jpg
sudo cp 1440x900.jpg 2560x1440.jpg
sudo rm 1280x1024.jpg
sudo wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Wallpapers/nexus0-sea-space-jelly.jpg -O 1280x1024.jpg
sudo rm 1024x768.jpg
sudo cp 1280x1024.jpg 1024x768.jpg
sudo rm 1080x1920.jpg
sudo wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Wallpapers/nexus0-moon-jelly.jpg -O 1080x1920.jpg
sudo rm 360x720.jpg
sudo cp 1080x1920.jpg 360x720.jpg
sudo rm 720x1440.jpg
sudo cp 1080x1920.jpg 720x1440.jpg
sudo rm -r *.png

#service ssh enable
#service ssh start

echo "abc:notiaPoint1" | chpasswd

## Set up firefox homepage
#cd /config/.mozilla
#sudo apt install -y zip unzip
#sudo rm -r firefox
#sudo rm firefox.zip
## Pull firefox files from repository containing homepage configuration
#sudo wget https://github.com/Underground-Ops/underground-nexus/raw/main/Production%20Artifacts/firefox.zip
#sudo unzip firefox.zip
#sudo chmod -R a+rwx firefox

#add nexus-creator-vault-control-panel site
sudo wget -O /nexus-creator-vault-control-panel.html https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Production%20Artifacts/Wordpress/nexus-creator-vault/nexus-creator-vault-control-panel.html

su - abc
#------------------------------------
#run "sh nexus0.sh" to execute
#------------------------------------

#------------------------------------
#**How to configure Nexus0 for access:**
#------------------------------------

#------------------------------------
#__*It is expected that you have already run `sh nexus0.sh` before doing this*__
#------------------------------------
#This goes over how to install chrome RDP via ssh to get to the webtop workbench.

#From portainer’s "nexus0" terminal shell (>_ Console) OR **alternatively** from `kubectl exec -it nexus0 -- /bin/bash` use:
#`su - abc`

#The default password for the user named "abc" is “notiaPoint1” - change the default password with - `passwd abc`

#CHROME RDP WILL ONLY INSTALL IF THE CONSOLE IS LOGGED INTO THE "abc" USER - DO NOT USE "sudo" (the `su - abc` command above will log the terminal into "abc," which is *REQUIRED*)

#------------------------------------
#From the computer you are accessing resources remotely from, install Chrome RDP, or go to the URL:
#-https://remotedesktop.google.com/headless

#*(the ssh **"Authorize"** key is __temporary__, so start over again if the Authorize string errors when ran inside the **Nexus0 shell** while **ssh'd as "abc" via Portainer**)*

#In chrome rdp, choose access my computer, then choose install via ssh.
#Follow the prompts till one says “Authorize”
#Copy the Linux string it provides
#Paste that into the cloud nexus0 node console while the terminal is logged as "abc"

#------------------------------------
#Access the Nexus0 from here once Chrome RDP is set up:
#-https://remotedesktop.google.com/access
#------------------------------------
#The Google Chrome RDP "Authroize" script may be run when this script completes or the Chrome RDP "Authorize" string may be added to this script directly to automate setting up Chrome RDP - you will need to enter the PIN still when the script completes even if the Chrome RDP "Authorize" string is pasted to the bottom of this script before running.
#Here is an example string: DISPLAY= /opt/google/chrome-remote-desktop/start-host --code="thisisanexamplestringthatisnotrealandDOESNOTWORK" --redirect-url="https://remotedesktop.google.com/_/oauthredirect" --name=$(hostname)
#------------------------------------
#(paste your modified Chrome RDP "Authorize" string once this script completes - the string pasted after running this script should look like the example above)
#THE CHROME RDP AUTHORIZE STRING WILL ONLY WORK WHILE THE TERMINAL IS LOGGED IN AS "abc" - IF THE LINUX COMMAND TERMINAL DIES OR CRASHES AFTER RUNNING THIS SCRIPT THE FOLLOWING COMMAND WILL LOG THE CLI TERMINAL IN AS "abc": "su - abc"
#------------------------------------
#Default password to Desktop once in Chrome RDP is "notiaPoint1" - change the password using `sudo passwd abc`
#Configure two factor authentication: https://www.tecmint.com/enable-two-factor-authentication-in-ubuntu/
