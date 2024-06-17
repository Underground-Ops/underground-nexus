#Using this file from inside of an Underground Nexus environment will deploy a Nexus Creator Vault with improved security, easier collaboration and automation support
sudo docker exec Athena0 docker run -itd --name=nexus-creator-vault -h nexus-creator-vault --net=Inner-Athena --dns=10.20.0.20 -e PUID=1050 -e PGID=1050 -e TZ=America/Colorado -p 1050:3000 --restart unless-stopped -v creator-vault000:/config -v /var/run/docker.sock:/var/run/docker.sock natoascode/zero-trust-cockpit:creator-vault
sudo docker exec Athena0 docker start nexus-creator-vault
xdg-open http://10.20.0.1:1050

#Running this script once deploys a Nexus Creator Vault with administator access to Docker

#To add additional users with the Nexus Creator Vault who are not administrators - run this instead:
#sudo docker exec Athena0 docker run -itd --name=(user's name)-creator-vault -h (user's name)-creator-vault --net=Inner-Athena --dns=10.20.0.20 -e PUID=1051 -e PGID=1051 -e TZ=America/Colorado -p 1051:3000 --restart unless-stopped -v creator-vault001:/config natoascode/zero-trust-cockpit:creator-vault
#sudo docker exec Athena0 docker start (user's name)-creator-vault
#xdg-open http://10.20.0.1:1051

#The non-administrator strings above must be edited accordingly for each additional end user
#If adding a number of end users it can make sense to write a script or .yml file
#If not using a .yml file - pay close attention to where the non-administrator deployment example differs from the administrator deployment strings at the top
#(AI tools like Google's Gemini or Chat GPT can help write scripts for less technical users)