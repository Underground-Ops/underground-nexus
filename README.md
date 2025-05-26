# __Cerberus0 Cloud Native Cloud Package Manager and CICD Pipeline - *Agnostic Cloud CICD*__ (NEW updates on the way!)

------------------------------------------------------------------------------  

Manage virtual machines alongside containers seemlessly with complete infrastructure lifecycle management, this resource is an alternative to VSPhere for cloud native engineering.

This is the master package manager and installer for the Underground Nexus software hypervisor and DevSecOps platform.

This package management pipeline includes Zarf to provide powerful package management for DevSecOps pipelines and airgapping capabilities.

Learn more about Zarf here: https://docs.zarf.dev/

This package manager does more than package management, CICD can be deployed with Dagger and Kubectl is installed by default for managing Kubernetes clusters.

**Tools and Package Management Resources Include:**
*- zarf*
*- git*
*- kubevit hypervisor*
*- helm package manager*
*- homebrew package manager*
*- soft serve git management server*
*- dagger for cicd*
*- nmap network scanner*
*- cron scheduler*
*- wishlist ssh management*

Wishlist is preconfigured to allow this package manager to be used as an ssh server, the startup script at `/usr/local/bin/start_services.sh` can be edited to modify startup services.

Use this command to modify the startup services:
`nano /usr/local/bin/start_services.sh`

To save type `ctrl+x`, next `y` and `enter`

------------------------------------------------------------------------------  

# _INSTALL HYPERVISOR AND DEVSECOPS PACKAGE MANAGER - *Run the following commands to set up the Underground Nexus Package Manager called the Cerberus Manager*_

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

# Once installed then you can enter the Cerberus-Manager shell to get started using: 

`docker exec -it Cerberus-Manager bash`

