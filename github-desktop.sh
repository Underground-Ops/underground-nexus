#!/bin/bash
sudo wget https://github.com/shiftkey/desktop/releases/download/release-3.2.0-linux1/GitHubDesktop-linux-3.2.0-linux1.deb
sudo apt-get install gdebi-core 
sudo gdebi GitHubDesktop-linux-3.2.0-linux1.deb

#find the latest download at the following link
#https://github.com/shiftkey/desktop/releases/latest
