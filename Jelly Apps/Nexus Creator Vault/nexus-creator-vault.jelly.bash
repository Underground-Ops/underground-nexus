#Using this file from inside of an Underground Nexus environment will deploy a Nexus Creator Vault with improved security, easier collaboration and automation support
sudo docker exec Athena0 docker run -itd --privileged --name=nexus-creator-vault -h nexus-creator-vault --net=Inner-Athena --dns=10.20.0.20 -e PUID=1050 -e PGID=1050 -e TZ=America/Colorado -p 1050:3000 --restart unless-stopped -v creator-vault000:/config -v /var/run/docker.sock:/var/run/docker.sock -v /dev:/dev natoascode/zero-trust-cockpit:creator-vault
sudo docker exec Athena0 docker start nexus-creator-vault
sleep 10
xdg-mime default firefox.desktop x-scheme-handler/https x-scheme-handler/http
xdg-open http://10.20.0.1:1050 &

#Running this script once deploys a Nexus Creator Vault with administator access to Docker

#To add additional users with the Nexus Creator Vault who are not administrators - run this instead:
#sudo docker exec Athena0 docker run -itd --name=(user's name)-creator-vault -h (user's name)-creator-vault --net=Inner-Athena --dns=10.20.0.20 -e PUID=1051 -e PGID=1051 -e TZ=America/Colorado -p 1051:3000 --restart unless-stopped -v creator-vault001:/config natoascode/zero-trust-cockpit:creator-vault
#sudo docker exec Athena0 docker start (user's name)-creator-vault
#sleep 10
#xdg-open http://10.20.0.1:1051 &

#The non-administrator strings above must be edited incrementally and labeled accordingly for each additional end user
#If adding a number of end users it can make sense to write a script or .yml file
#If not using a .yml file - pay close attention to where the non-administrator deployment example differs from the administrator deployment strings at the top
#(AI tools like Google's Gemini or Chat GPT can help write scripts for less technical users)

#Add any additional custom commands to customize the nexus-creator-vault to include any additional default features or applications
#sudo docker exec nexus-creator-vault <add your command here>

#Use the code below to deploy nexus-creator-vault in kiosk mode to take over a device's desktop
#xdg-mime default firefox.desktop x-scheme-handler/https x-scheme-handler/http
#firefox --kiosk http://10.20.0.1.1050 &
#xdg-open http://10.20.0.1:1050

#Add a custom time limit to kiosk mode if the desktop is supposed to appear temporarily
#sleep 120
#sudo docker stop nexus-creator-vault
#sudo docker rm nexus-creator-vault
#Display placeholder "timeout" image from a free online image source
#xdg-open https://images.pexels.com/photos/1198264/pexels-photo-1198264.jpeg
#sleep 15
#optionally minimize browser (by removing comment) then close the two kiosk tabs that were generated
#xdotool search "Mozilla Firefox" windowminimize
#wmctrl -a firefox; xdotool key Ctrl+w;
#wmctrl -a firefox; xdotool key Ctrl+w;
#wmctrl -a firefox; xdotool key Alt+F4;

exit
