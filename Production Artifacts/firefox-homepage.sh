#!/bin/bash
sudo mkdir /config
sudo mkdir /config/.mozilla
sudo wget https://github.com/Underground-Ops/underground-nexus/raw/main/Production%20Artifacts/firefox.zip -O /config/.mozilla/firefox.zip
sudo unzip /config/.mozilla/firefox.zip
sudo chmod -R a+rwx /config/.mozilla/firefox
