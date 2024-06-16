#!/bin/bash
## Direct copy-paste from official instrubtions
## Github Desktop for Ubuntu
## Get the @shiftkey package feed
wget -qO - https://apt.packages.shiftkey.dev/gpg.key | gpg --dearmor | sudo tee /usr/share/keyrings/shiftkey-packages.gpg > /dev/null
sudo sh -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/shiftkey-packages.gpg] https://apt.packages.shiftkey.dev/ubuntu/ any main" > /etc/apt/sources.list.d/shiftkey-packages.list'
## Install Github Desktop for Ubuntu
sudo apt update && sudo apt install github-desktop -y

#-------------------------------------------
#OLD SCRIPT
#sudo wget https://github.com/shiftkey/desktop/releases/download/release-3.2.0-linux1/GitHubDesktop-linux-3.2.0-linux1.deb
#sudo apt-get install gdebi-core 
#sudo gdebi GitHubDesktop-linux-3.2.0-linux1.deb
#sudo dpkg -i GitHubDesktop-linux-3.2.0-linux1.deb

#find the latest download at the following link
#https://github.com/shiftkey/desktop/releases/latest
