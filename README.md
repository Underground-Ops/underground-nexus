# __Cerberus0 Cloud Native Cloud Package Manager and CICD Pipeline - *Agnostic Cloud CICD*__ (NEW updates on the way!)
------------------------------------------------------------------------------  

# __INSTALL HYPERVISOR AND DEVSECOPS PACKAGE MANAGER - *Run the following commands to set up the Underground Nexus Package Manager called the Cerberus Manager*__

`sudo mkdir -p ~/nexus-bucket`
`#sudo chmod 755 ~/nexus-bucket`

`sudo docker run -itd --init --privileged --name=Cerberus-Manager -h Cerberus-Manager --net=host --restart=always -v /root/nexus-bucket:/nexus-bucket -v /var/run/docker.sock:/var/run/docker.sock natoascode/cerberus0:latest sh -c "mkdir -p /root/nexus-bucket && cp /etc/rancher/k3s/k3s.yaml /root/nexus-bucket/k3s.yml && exec bash" && sleep 30 && sudo bash /root/nexus-bucket/underground-nexus/'Dagger CI'/Scripts/install-k3s.sh`

`sudo cp /etc/rancher/k3s/k3s.yaml /root/nexus-bucket/k3s.yml`
`sudo docker exec Cerberus-Manager bash -c "mkdir -p /root/.kube && cp /nexus-bucket/k3s.yml /root/.kube/config"`

`sudo docker exec -it Cerberus-Manager sh -c "`
  `VERSION=\$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt);`
  `wget https://github.com/kubevirt/kubevirt/releases/download/\$VERSION/virtctl-\$VERSION-linux-amd64;`
  `chmod +x virtctl-\$VERSION-linux-amd64;`
  `mv virtctl-\$VERSION-linux-amd64 /usr/local/bin/virtctl;`
  `"`

`sudo docker exec -it Cerberus-Manager bash`