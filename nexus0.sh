#!/bin/bash
#------------------------------------
#Nexus0 is a "copy paste" Cloud Native server node that may be deployed to container orchestrators (such as Kubernetes and Docker) - *Though Nexus0 is a component of the Underground Nexus "copy paste" datacenter environment, it __may run as a standalone server__ node even without the Underground Nexus*
#------------------------------------
#--*Copy paste* this "nexus0" template inside of a Kubernetes (or KuberNexus) cluster to test: `kubectl run my-nexus0 -i --tty --image linuxserver/webtop:ubuntu-kde`
#------------------------------------
#name a file "nexus0.sh" and paste this script inside with "sudo apt update" then "sudo apt install nano" to ubild a script -- ctrl + x , y, enter (to save inside nano)
#------------------------------------
apt update
apt install -y ssh
apt install -y wget
wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
sudo dpkg -i chrome-remote-desktop_current_amd64.deb
apt install -y -f
apt update
wget https://release.gitkraken.com/linux/gitkraken-amd64.deb
sudo dpkg -i gitkraken-amd64.deb
apt -y upgrade --fix-broken
#manually enable ssh - service ssh enable
#start ssh - service ssh start
#get ip address - hostname -i
#ssh into user to launch chrome rdp - ssh abc@ipaddressfromlastcommand
#password - "abc"
#Use the chrome RDP application to get an "install via ssh" authentication string for "linux"
#copy paste the authentication string into the "abc" ssh shell (don't use sudo - must be using ssh with "abc" or the chrome rdp setup will fail)

#------------------------------------
#Change kde background
#KDE wallpaper location: /usr/share/wallpapers/Next/contents/images/1440x900.jpg
#------------------------------------

#sea-space-jelly for kde ubuntu
cd /usr/share/wallpapers/Next/contents/images/
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

service ssh enable
service ssh start
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

#From portainer’s my-workbench shell you want to use:
#`hostname -i`

#To get your host’s IP address, then ssh to the host with the ip:
#`ssh abc@(ipaddress)`

#Say yes, then the password is “abc”

#------------------------------------
#From the computer you are accessing things from, install chrome rdp, or go to the URL:
#-https://remotedesktop.google.com/headless

#*(the ssh **"Authorize"** key is __temporary__, so start over again if the Authorize string errors when ran inside the **Nexus0 shell** while **ssh'd as "abc" via Portainer**)*

#In chrome rdp, choose access my computer, then choose install via ssh.

#Follow the prompts till one says “Authorize”

#Copy the Linux string it gives you

#Paste that into the cloud Nexus0 node
#------------------------------------
#Access the Nexus0 from here once Chrome RDP is set up:
#-https://remotedesktop.google.com/access
#------------------------------------
