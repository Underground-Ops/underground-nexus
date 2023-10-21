sudo apt-get install curl
curl -sSLf https://raw.githubusercontent.com/openziti/ziti-tunnel-sdk-c/main/package-repos.gpg \
| gpg --dearmor \
| sudo tee /usr/share/keyrings/openziti.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/openziti.gpg] https://packages.openziti.org/zitipax-openziti-deb-stable jammy main' \
| sudo tee /etc/apt/sources.list.d/openziti.list >/dev/null
sudo apt update
sudo apt install ziti-edge-tunnel
