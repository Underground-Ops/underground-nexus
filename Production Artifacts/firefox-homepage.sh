#!/bin/bash
#backup and delete existing firefox profiles if they exist
cp -r /var/lib/docker/volumes/workbench0/_data/.mozilla/firefox /var/lib/docker/volumes/workbench0/_data/.mozilla/firefox-backup
rm -r /var/lib/docker/volumes/workbench0/_data/.mozilla/firefox
#create mozilla directory if it does not already exist
mkdir /var/lib/docker/volumes/workbench0/_data/.mozilla
wget https://github.com/Underground-Ops/underground-nexus/raw/main/Production%20Artifacts/firefox.zip
unzip firefox.zip
cp -r firefox /var/lib/docker/volumes/workbench0/_data/.mozilla/firefox
chmod -R a+rwx /var/lib/docker/volumes/workbench0/_data/.mozilla
