FROM docker:dind

EXPOSE 22 53 80 443 1000 2375 2376 2377 9010 9443 18443

VOLUME ["/var/run", "/var/lib/docker/volumes", "/nexus-bucket"]

RUN apk update
RUN apk upgrade

RUN apk add bash
RUN apk add nano
RUN apk add curl
RUN apk add wget
RUN apk add git

#-------------------------------
#Configure kubectl, helm and k3d
RUN curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash || true
#kubectl: arch-detected. (Previously this downloaded the amd64 kubectl and then
#unconditionally downloaded the arm64 kubectl over the same path, so even amd64
#images shipped the wrong-arch binary. One line now serves amd64/arm64/armv7.)
RUN KARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/' -e 's/armv7l/arm/') && curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${KARCH}/kubectl" && chmod +x ./kubectl && mv ./kubectl /usr/local/bin/kubectl || true
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash && helm repo add stable https://charts.helm.sh/stable && helm repo add gitlab https://charts.gitlab.io/ || true
#RUN wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list && apk update && apk add terraform; exit 0
WORKDIR "/usr/local"
RUN curl -L https://dl.dagger.io/dagger/install.sh | sh
WORKDIR "/"
#-------------------------------

#Pull the Olympiad's lightweight deployment activation script artifact first
RUN wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Production%20Artifacts/olympiad-deploy-light.sh

#Build the FULL Olympiad deployment activation script
RUN echo "#!/bin/sh" > deploy-olympiad.sh

# =============================================================================
# OLYMPIAD PREFLIGHT + CAULK HELPERS  (added - reliability upgrade)
# -----------------------------------------------------------------------------
# These lines APPEND to deploy-olympiad.sh exactly like every other line in this
# file - the same proven echo-chain the Nexus has shipped for years. The ONLY
# difference: helper-definition lines use SINGLE-quoted
#     RUN echo '...' >> deploy-olympiad.sh
# because they contain shell metacharacters ( $ { } ; until [ ] "..." ) that
# must land in the script LITERALLY instead of being expanded here at image
# BUILD time. Every original deployment line keeps its double-quoted echo.
# To edit a helper, change the text inside the single quotes; to add a deploy
# step, keep using the double-quoted echo style used throughout this file.
#
# Why (Infrastructure Caulk law: caulk is a draft until dry-run; caulk never
# claims success it did not verify; the script stays tolerant - NO `set -e` -
# so it still surfaces host constraints as a chaos test yet keeps going):
#   wait_docker            block until the inner dockerd socket answers
#   wait_container NAME     block until NAME is in the running state (liveness)
#   wait_exec NAME          block until we can actually exec inside NAME
#                           (a webtop is "running" long before its s6 init is
#                            ready - liveness is not readiness; this is what the
#                            failed log's "No such container" cascade needed)
#   retry CMD...            run CMD up to 5x with backoff (idempotent ops only)
#   ensure_net_bridge/overlay  inspect-or-create a network, retried
#   ensure_repo             clone/pull the Nexus repo into /nexus-bucket so the
#                            /nexus-bucket/underground-nexus/... paths resolve
#                            even after SEC-rebuild wipes the bucket volume
# OLYMPIAD_CLEAN=0 skips the stale-inner-container sweep (default 1 = clean).
#
# SUBSTRATE AGNOSTIC (pass 3) - the promoted artifact runs unchanged inside the
# SEC dind container, on a bare-metal Forge OS host, on a Pi, and on M-series:
#   pkg_add          apk -> apt-get -> dnf, tolerant (no Alpine assumption)
#   ensure_compose   replaces the old bare "apk add docker-compose"
#   ensure_swarm     joins an existing swarm instead of erroring; falls back to
#                    --advertise-addr on multi-NIC metal hosts
#   detect_substrate sets DOCKER_BIN (docker CLI lives at /usr/bin on Ubuntu,
#                    /usr/local/bin on Alpine) and arbitrates the four host
#                    ports a real host already owns:
#                      P_SSH 22->2223  P_DNS 53->5353  P_DHCP 67->6767
#                      P_S3  9000->19000
#                    In a container every value stays canonical, so the SEC
#                    path is byte-identical to what has always been tested.
#                    Any of them can be pinned from the environment.
# NOTE: lines carrying ${VAR} use SINGLE-quoted echo so the variable reaches
# the script literally and resolves at RUN time, not at build time.
# =============================================================================
RUN echo 'log() { echo "[olympiad] $*"; }' >> deploy-olympiad.sh \
 && echo 'wait_docker() { i=0; until docker info >/dev/null 2>&1; do i=$((i+1)); [ "$i" -ge 180 ] && { log "dockerd not ready after 180s - continuing best-effort"; return 1; }; [ $((i % 5)) -eq 0 ] && log "waiting for docker daemon... ($i)"; sleep 1; done; log "docker daemon ready"; }' >> deploy-olympiad.sh \
 && echo 'wait_container() { n="$1"; i=0; until [ "$(docker inspect -f "{{.State.Running}}" "$n" 2>/dev/null)" = "true" ]; do i=$((i+1)); [ "$i" -ge 120 ] && { log "$n not running after 120s - continuing"; return 1; }; sleep 1; done; log "$n running"; }' >> deploy-olympiad.sh \
 && echo 'wait_exec() { n="$1"; wait_container "$n" || true; i=0; until docker exec "$n" true >/dev/null 2>&1; do i=$((i+1)); [ "$i" -ge 120 ] && { log "$n not exec-ready after 240s - continuing"; return 1; }; sleep 2; done; log "$n exec-ready"; }' >> deploy-olympiad.sh \
 && echo 'retry() { n=0; until "$@"; do n=$((n+1)); [ "$n" -ge 5 ] && { log "failed after 5 tries: $*"; return 1; }; log "retry $n/5: $*"; sleep 3; done; }' >> deploy-olympiad.sh \
 && echo 'ensure_net_bridge() { docker network inspect "$1" >/dev/null 2>&1 && { log "net $1 exists"; return 0; }; M=$(net_mtu); if [ -n "$M" ]; then log "net $1 creating with mtu=$M"; retry docker network create -d bridge --opt com.docker.network.driver.mtu="$M" --subnet="$2" --gateway="$3" "$1"; else retry docker network create -d bridge --subnet="$2" --gateway="$3" "$1"; fi; }' >> deploy-olympiad.sh \
 && echo 'ensure_net_overlay() { docker network inspect "$1" >/dev/null 2>&1 && { log "net $1 exists"; return 0; }; retry docker network create -d overlay --subnet="$2" "$1"; }' >> deploy-olympiad.sh \
 && echo 'net_mtu() { case "${NEXUS_NET_MTU:-}" in "") : ;; auto) I=$(ip -4 route show default 2>/dev/null | awk "{print \$5; exit}"); [ -z "$I" ] && I=$(ls /sys/class/net 2>/dev/null | grep -v "^lo$" | head -1); [ -n "$I" ] && cat /sys/class/net/"$I"/mtu 2>/dev/null ;; *) echo "${NEXUS_NET_MTU}" ;; esac; }' >> deploy-olympiad.sh \
 && echo 'net_report() { R=$(docker network inspect "$1" --format "driver={{.Driver}} subnet={{range .IPAM.Config}}{{.Subnet}}{{end}} gw={{range .IPAM.Config}}{{.Gateway}}{{end}} mtu={{index .Options \"com.docker.network.driver.mtu\"}}" 2>/dev/null | sed "s/mtu=<no value>/mtu=default/"); log "net $1 $R"; }' >> deploy-olympiad.sh \
 && echo 'ensure_repo() { if [ -d /nexus-bucket/underground-nexus/.git ]; then git -C /nexus-bucket/underground-nexus pull --rebase >/dev/null 2>&1 || true; else mkdir -p /nexus-bucket; retry git clone https://github.com/Underground-Ops/underground-nexus.git /nexus-bucket/underground-nexus || true; fi; }' >> deploy-olympiad.sh \
 && echo 'pkg_add() { command -v "$1" >/dev/null 2>&1 && return 0; apk add --no-cache "$2" >/dev/null 2>&1 || { apt-get update >/dev/null 2>&1 && apt-get install -y "$2" >/dev/null 2>&1; } || dnf install -y "$2" >/dev/null 2>&1 || true; command -v "$1" >/dev/null 2>&1; }' >> deploy-olympiad.sh \
 && echo 'ensure_compose() { pkg_add docker-compose docker-compose || log "docker-compose not installable here - compose steps degrade"; }' >> deploy-olympiad.sh
RUN echo 'ensure_swarm() { docker node ls >/dev/null 2>&1 && { log "swarm already active - joining existing"; return 0; }; docker swarm init >/dev/null 2>&1 && { log "swarm init ok"; return 0; }; A=$(ip -4 route get 1.1.1.1 2>/dev/null | awk "{print \$7; exit}"); [ -z "$A" ] && A=$(hostname -i 2>/dev/null | awk "{print \$1}"); [ -n "$A" ] && docker swarm init --advertise-addr "$A" >/dev/null 2>&1 && { log "swarm init ok (advertise $A)"; return 0; }; log "swarm init failed - overlay nets may degrade to bridge"; return 1; }' >> deploy-olympiad.sh \
 && echo 'detect_substrate() { if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then NEXUS_METAL=0; else NEXUS_METAL=1; fi; DOCKER_BIN=$(command -v docker 2>/dev/null || echo /usr/local/bin/docker); NEXUS_ARCH=$(uname -m); if [ "$NEXUS_METAL" = "1" ]; then P_SSH="${P_SSH:-2223}"; P_DNS="${P_DNS:-5353}"; P_DHCP="${P_DHCP:-6767}"; P_S3="${P_S3:-19000}"; log "substrate: bare metal ($NEXUS_ARCH) - host publishes shifted ssh=$P_SSH dns=$P_DNS dhcp=$P_DHCP s3=$P_S3"; else P_SSH="${P_SSH:-22}"; P_DNS="${P_DNS:-53}"; P_DHCP="${P_DHCP:-67}"; P_S3="${P_S3:-9000}"; log "substrate: container ($NEXUS_ARCH) - canonical host publishes"; fi; log "docker cli at $DOCKER_BIN"; }' >> deploy-olympiad.sh \
 && echo '' >> deploy-olympiad.sh \
 && echo '# ---- preflight (added): wait for dockerd, ensure repo, clean slate ----' >> deploy-olympiad.sh \
 && echo 'wait_docker' >> deploy-olympiad.sh \
 && echo 'detect_substrate' >> deploy-olympiad.sh \
 && echo 'pkg_add git git || log "git unavailable - repo sync may skip"' >> deploy-olympiad.sh \
 && echo 'ensure_repo' >> deploy-olympiad.sh \
 && echo '[ "${OLYMPIAD_CLEAN:-1}" = "1" ] && for c in Inner-DNS-Control Olympiad0 Athena0 Security-Operation-Center workbench torpedo code-server Nexus-Secret-Vault; do docker rm -f "$c" >/dev/null 2>&1 || true; done' >> deploy-olympiad.sh

#Build Inner-Athena engine
RUN echo 'ensure_swarm || true' >> deploy-olympiad.sh \
 && echo 'ensure_compose' >> deploy-olympiad.sh

RUN echo 'ensure_net_bridge Inner-Athena 10.20.0.0/24 10.20.0.1' >> deploy-olympiad.sh \
 && echo 'net_report Inner-Athena' >> deploy-olympiad.sh \
 && echo 'docker run -itd -p ${P_DNS}:53/tcp -p ${P_DNS}:53/udp -p ${P_DHCP}:67 -p 800:80 -h Inner-DNS-Control --name=Inner-DNS-Control --net=Inner-Athena --ip=10.20.0.20 --restart=always -v pihole_DNS_data:/etc/dnsmasq.d/ -v pihole_config:/etc/pihole/ pihole/pihole:latest || true' >> deploy-olympiad.sh \
 && echo 'wait_container Inner-DNS-Control' >> deploy-olympiad.sh

#Build Olympiad0 Portainer node
RUN echo "docker volume create portainer_data" >> deploy-olympiad.sh \
 && echo "docker run -d -p 8000:8000 -p 9443:9443 --name=Olympiad0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest || true" >> deploy-olympiad.sh

#Deploy Athena0 Gateway and Security Operation Center
RUN echo 'docker run -itd --init --privileged -p ${P_SSH}:22 --name=Athena0 -h Athena0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v athena0:/home/ -v /nexus-bucket:/nexus-bucket -v /etc/docker:/etc/docker -v ${DOCKER_BIN}:/usr/local/bin/docker -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/docker/volumes/:/var/lib/docker/volumes/ natoascode/athena0:latest || true' >> deploy-olympiad.sh \
 && echo "docker run -itd --name=Security-Operation-Center -h Security-Operation-Center -e PUID=2000 -e PGID=2000 -e TZ=America/Colorado -p 2000:3001 --dns=10.20.0.20 --net=Inner-Athena --ip=10.20.0.30 --restart=always -v security-operation-center:/config -v /nexus-bucket:/config/Desktop/nexus-bucket linuxserver/webtop:ubuntu-i3 || true" >> deploy-olympiad.sh \
 && echo 'wait_exec Security-Operation-Center' >> deploy-olympiad.sh \
 && echo "docker exec Security-Operation-Center apt update || true" >> deploy-olympiad.sh \
 && echo "docker exec Security-Operation-Center apt install rofi -y || true" >> deploy-olympiad.sh \
 && echo "docker exec Security-Operation-Center apt install terminator -y || true" >> deploy-olympiad.sh \
 && echo "docker exec Security-Operation-Center apt install firefox -y || true" >> deploy-olympiad.sh \
 && echo "docker exec Security-Operation-Center su - abc -c 'DISPLAY=:1 firefox &' || true" >> deploy-olympiad.sh \
 && echo "docker exec Security-Operation-Center su - abc -c 'DISPLAY=:1 terminator &' || true" >> deploy-olympiad.sh

#Build workbench admin MATE desktop environment
RUN echo "echo "FROM natoascode/workbench0:ubuntu" >> /nexus-bucket/workbench.dockerfile" >> deploy-olympiad.sh \
 && echo "echo "RUN bash workbench.sh" >> /nexus-bucket/workbench.dockerfile" >> deploy-olympiad.sh \
 && echo "docker build -f /nexus-bucket/workbench.dockerfile -t workbench:latest /nexus-bucket" >> deploy-olympiad.sh \
 && echo "docker run -itd  --privileged --name=workbench -h workbench -e PUID=1000 -e PGID=1000 -e TZ=America/Colorado -p 1000:3000 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /dev:/dev -v workbench0:/config -v /nexus-bucket:/config/Desktop/nexus-bucket -v /var/run/docker.sock:/var/run/docker.sock natoascode/workbench0:ubuntu || true" >> deploy-olympiad.sh \
 && echo 'wait_exec workbench' >> deploy-olympiad.sh \
 && echo "docker exec workbench bash /workbench.sh || true" >> deploy-olympiad.sh \
 && echo "docker exec workbench sudo apt install firefox -y || true" >> deploy-olympiad.sh \
 && echo "docker run -itd  --privileged --name=workbench -h workbench -e PUID=1000 -e PGID=1000 -e TZ=America/Colorado -p 1000:3000 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /dev:/dev -v workbench0:/config -v /nexus-bucket:/config/Desktop/nexus-bucket -v /var/run/docker.sock:/var/run/docker.sock workbench:latest || true" >> deploy-olympiad.sh || true
#RUN echo "docker run -itd  --privileged --name=workbench -h workbench -e PUID=1000 -e PGID=1000 -e TZ=America/Colorado -p 1000:3000 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v workbench0:/config -v /nexus-bucket:/config/Desktop/nexus-bucket -v /var/run/docker.sock:/var/run/docker.sock linuxserver/webtop:ubuntu-mate" >> deploy-olympiad.sh

#Build workbench stack
#RUN echo "docker exec workbench echo "docker exec workbench echo "#!/bin/sh"" > /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt -y update" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench sudo apt install -y wget" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec Security-Operation-Center sudo apk update" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec Security-Operation-Center sudo apk add wget" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec Security-Operation-Center sudo apk add dpkg" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec Security-Operation-Center sudo apk upgrade" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#Visual Studio Code installs
#RUN echo "docker exec workbench echo "docker exec workbench sudo wget -O vscode-amd64.deb  https://go.microsoft.com/fwlink/?LinkID=760868" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo dpkg -i vscode-amd64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#ARM64 Visual Studio Code deploy
#RUN echo "docker exec workbench echo "docker exec workbench sudo wget https://aka.ms/linux-arm64-deb -O vscode-arm64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo dpkg -i vscode-arm64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#Install Git
RUN echo "docker exec workbench echo "docker exec workbench sudo apt install -y git" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench sudo apt install -y iputils-ping" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#GitHub Desktop
RUN echo "docker exec workbench echo "docker exec workbench sudo wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/github-desktop.sh" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench sudo bash github-desktop.sh" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench sudo apt install -y apt-transport-https curl" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#Chrome RDP and GitKraken
RUN echo "docker exec workbench echo "docker exec workbench wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench sudo dpkg -i chrome-remote-desktop_current_amd64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench wget https://release.gitkraken.com/linux/gitkraken-amd64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench sudo dpkg -i gitkraken-amd64.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#Install Discord
RUN echo "docker exec workbench echo "docker exec workbench wget -O discord.deb https://discordapp.com/api/download?platform=linux&format=deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo dpkg -i discord.deb" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#Virtual Machine Engineering Suite
RUN echo "docker exec workbench echo "docker exec workbench sudo apt install -y qemu" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils qemu-system qemu-system-x86 qemu-system-arm" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench sudo apt install -y virt-manager" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench sudo apt install -y synaptic" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench sudo apt install -y terminator" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#Deploy KuberNexus ETCD Kubernetes Cluster from Athena0
RUN echo "docker exec workbench echo "docker exec Athena0 wget https://raw.githubusercontent.com/rancher/k3d/main/install.sh" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec Athena0 bash /install.sh" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec Athena0 k3d cluster create KuberNexus --network Inner-Athena --api-port 10.20.0.1:6443 -p 18080:8080@loadbalancer -p 8443:8443@loadbalancer -p 2222:22@loadbalancer -p 179:179@loadbalancer -p 2375:2376@loadbalancer -p 2378:2379@loadbalancer -p 2381:2380@loadbalancer -p 8472:8472@loadbalancer -p 8843:443@loadbalancer -p 4789:4789@loadbalancer -p 9099:9099@loadbalancer -p 9100:9100@loadbalancer -p 7443:9443@loadbalancer -p 9796:9796@loadbalancer -p 6783:6783@loadbalancer -p 10250:10250@loadbalancer -p 10254:10254@loadbalancer -p 31896:31896@loadbalancer -v /nexus-bucket:/nexus-bucket -v /dev:/dev --servers 1 --registry-create KuberNexus-registry --kubeconfig-update-default" >> /nexus-bucket/build-kubernexus.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec Athena0 export KUBECONFIG=/root/.k3d/kubeconfig-KuberNexus.yaml" >> /nexus-bucket/build-kubernexus.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec Athena0 #cp /root/.k3d/kubeconfig-KuberNexus.yaml /nexus-bucket/" >> /nexus-bucket/build-kubernexus.sh" >> deploy-olympiad.sh || true
RUN echo "docker exec workbench echo "docker exec Athena0 k3d kubeconfig merge KuberNexus --kubeconfig-merge-default" >> /nexus-bucket/build-kubernexus.sh" >> deploy-olympiad.sh || true \
 && echo "docker exec workbench echo "docker exec Athena0 sh /nexus-bucket/build-kubernexus.sh" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec Athena0 sh /enable-weekly-updates.sh" >> /nexus-bucket/enable-weekly-updates.sh" >> deploy-olympiad.sh

#Terraform
RUN echo "docker exec workbench echo "docker exec workbench sudo wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Terraform%20Master/terraform-workbench-install.sh" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench sudo sh terraform-workbench-install.sh" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench sudo mv /terraform-workbench-install.sh /config/Desktop/nexus-bucket" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo mv terraform usr/local/bin" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo touch ~/.bashrc" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo terraform -install-autocomplete" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#Alternate Terraform deploy
#RUN echo "docker exec workbench echo "docker exec workbench sudo curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench sudo apt-get update && sudo apt-get install -y terraform" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench terraform -v" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench which terraform" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench touch ~/.bashrc" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#RUN echo "docker exec workbench echo "docker exec workbench terraform -install-autocomplete" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
RUN echo "docker exec workbench echo "docker exec workbench sudo apt -y update --fix-missing" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench sudo apt --fix-broken install -y" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench sudo apt -y upgrade" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench sudo apt install -y virt-manager firefox" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#------------------------------------
#Change MATE Default Desktop
RUN echo "docker exec workbench echo "docker exec workbench sudo rm /usr/share/backgrounds/ubuntu-mate-jammy/Jammy-Jellyfish_WP_4096x2304_Green.png" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench echo "docker exec workbench sudo wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Wallpapers/underground-nexus-scifi-space-jelly.png -O /usr/share/backgrounds/ubuntu-mate-jammy/Jammy-Jellyfish_WP_4096x2304_Green.png" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh
#------------------------------------

#Build Athena0 stack
RUN echo 'wait_exec Athena0' >> deploy-olympiad.sh \
 && echo "docker exec Athena0 apt -y update" >> deploy-olympiad.sh \
 && echo "docker exec Athena0 apt install -y iputils-ping" >> deploy-olympiad.sh \
 && echo "docker exec Athena0 git clone https://github.com/radareorg/radare2" >> deploy-olympiad.sh \
 && echo "docker exec Athena0 sh radare2/sys/install.sh" >> deploy-olympiad.sh \
 && echo "docker exec Athena0 apt-get install -y metasploit-framework" >> deploy-olympiad.sh
#RUN echo "docker exec Athena0 wget -O terraform-amd64.zip https://releases.hashicorp.com/terraform/1.1.7/terraform_1.1.7_linux_amd64.zip" >> deploy-olympiad.sh
#RUN echo "docker exec Athena0 unzip terraform-amd64.zip" >> deploy-olympiad.sh
#RUN echo "docker exec Athena0 mv terraform usr/local/bin" >> deploy-olympiad.sh
#RUN echo "docker exec Athena0 touch ~/.bashrc" >> deploy-olympiad.sh
#RUN echo "docker exec Athena0 terraform -install-autocomplete" >> deploy-olympiad.sh
RUN echo "docker exec Athena0 apt -y update" >> deploy-olympiad.sh \
 && echo "docker exec Athena0 apt -y upgrade" >> deploy-olympiad.sh

#Build Cyber Life Torpedo - default username is "minioadmin" and default password is also "minioadmin" (please change, especially before shipping off to Dockerhub or other public cloud repositories!)
RUN echo 'docker run -itd --privileged -p ${P_S3}:9000 -p 9010:9001 --name=torpedo -h torpedo --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /nexus-bucket:/nexus-bucket -v /nexus-bucket/s3-torpedo:/data pgsty/minio:latest server /data --console-address ":9001" || true' >> deploy-olympiad.sh

#Deploy OPEN Visual Studio Code Container
RUN echo 'docker run -d --name=code-server -e PUID=1050 -e PGID=1050 -p 18443:3000 --dns=10.20.0.20 --net=Inner-Athena -v /nexus-bucket:/nexus-bucket -v /nexus-bucket/visual-studio-code:/config -v /etc/docker:/etc/docker -v ${DOCKER_BIN}:/usr/local/bin/docker -v /var/run/docker.sock:/var/run/docker.sock --restart unless-stopped lscr.io/linuxserver/openvscode-server || true' >> deploy-olympiad.sh

#Build Development Vault
RUN echo "docker run -itd -p 8200:1234 --name=Nexus-Secret-Vault -h Nexus-Secret-Vault --dns=10.20.0.20 --net=Inner-Athena --restart=always --cap-add=IPC_LOCK -e 'VAULT_DEV_ROOT_TOKEN_ID=myroot' -e 'VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:1234' hashicorp/vault:1.13.3 || true" >> deploy-olympiad.sh


#Deploy Dagger CI Cyber Life Building Beaver and Update Scheduling Manager Update script
RUN echo "docker exec Athena0 sh /old-underground-nexus-dagger-ci.sh" >> deploy-olympiad.sh \
 && echo "docker exec Athena0 sh /nexus-bucket/underground-nexus/'Dagger CI'/Scripts/enable-weekly-updates.sh" >> deploy-olympiad.sh

#Visual Studio Code for workbench desktop
RUN echo "docker exec workbench echo "docker exec workbench bash /config/Desktop/nexus-bucket/underground-nexus/visual-studio-code.sh" >> /nexus-bucket/workbench.sh" >> deploy-olympiad.sh

#Build workbench script
RUN echo "docker exec Athena0 sh /nexus-bucket/workbench.sh" >> deploy-olympiad.sh

#Restart DNS before building loadbalancing resources
RUN echo "docker restart Inner-DNS-Control" >> deploy-olympiad.sh

#Install KuberNexus ETCD Kubernetes Cluster Backup Process if first KuberNexus deployment fails
RUN echo "curl -s https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash" >> deploy-olympiad.sh \
 && echo "#k3d cluster create KuberNexus -p 8080:8080@loadbalancer -p 8443:8443@loadbalancer -p 2222:22@loadbalancer -p 179:179@loadbalancer -p 2375:2376@loadbalancer -p 2378:2379@loadbalancer -p 2381:2380@loadbalancer -p 8472:8472@loadbalancer -p 8843:443@loadbalancer -p 4789:4789@loadbalancer -p 9099:9099@loadbalancer -p 9100:9100@loadbalancer -p 7443:9443@loadbalancer -p 9796:9796@loadbalancer -p 6783:6783@loadbalancer -p 10250:10250@loadbalancer -p 10254:10254@loadbalancer -p 31896:31896@loadbalancer -v /nexus-bucket:/nexus-bucket --servers 3 --registry-create KuberNexus-registry --kubeconfig-update-default" >> deploy-olympiad.sh
#kubectl refresh inside the running Nexus: the arch is baked at image-build time
#(under buildx --platform the build arch IS the target arch), matching the
#:amd64/:arm64 per-arch image model. This was hardcoded amd64 with a commented
#arm64 twin - on amd64 hosts it was silently repairing the build-time arm64
#overwrite bug fixed above; both ends are now arch-correct everywhere.
RUN KARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/' -e 's/armv7l/arm/') && echo "curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${KARCH}/kubectl" && chmod +x ./kubectl && mv ./kubectl /usr/local/bin/kubectl" >> deploy-olympiad.sh || true
RUN echo "k3d kubeconfig merge KuberNexus --kubeconfig-merge-default" >> deploy-olympiad.sh || true \
 && echo "docker exec Athena0 bash /nexus-bucket/underground-nexus/'Dagger CI'/Scripts/virtual-machine-engine.sh" >> deploy-olympiad.sh

#Deploy Traefik loadbalancer, GitLab for Git-BIOS alongside the collaborator-workbench service - build "underground-ops.me" domain proxy gateway
RUN echo 'ensure_net_overlay underground-wordpress_internal 172.16.32.0/24' >> deploy-olympiad.sh \
 && echo "curl https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Dagger%20CI/Scripts/gitlab-collaborator-stack.sh | sh" >> deploy-olympiad.sh

#Configure firefox browser defaults
RUN echo "wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Production%20Artifacts/firefox-homepage.sh" >> deploy-olympiad.sh \
 && echo "sh firefox-homepage.sh" >> deploy-olympiad.sh

RUN echo "docker exec workbench bash /config/Desktop/nexus-bucket/terraform-workbench-install.sh && docker exec workbench terraform -v && docker exec workbench apt install terminator -y && docker exec workbench chown -R abc /config" >> deploy-olympiad.sh

#Fix workbench apt (if broken) and set up rofi-based desktop menu
RUN echo "docker exec workbench bash /config/Desktop/nexus-bucket/underground-nexus/'Dagger CI'/Scripts/Maintenance/workbench-apt-update-repair.sh" >> deploy-olympiad.sh \
 && echo "docker exec workbench apt install rofi -y" >> deploy-olympiad.sh \
 && echo "docker exec workbench bash /config/Desktop/nexus-bucket/underground-nexus/'Dagger CI'/Scripts/configure-desktop-menu.sh" >> deploy-olympiad.sh
#Install Git-BIOS Control Panel
RUN echo "docker exec workbench bash /config/Desktop/nexus-bucket/underground-nexus/Jelly-Apps/Git-BIOS-Control-Panel/install-git-bios-control-panel.sh || true" >> deploy-olympiad.sh

RUN echo "docker exec Athena0 curl https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/underground-nexus-update.sh | bash" >> deploy-olympiad.sh

RUN echo "docker restart Inner-DNS-Control" >> deploy-olympiad.sh \
 && echo "docker restart workbench" >> deploy-olympiad.sh \
 && echo "docker restart Athena0" >> deploy-olympiad.sh

# =============================================================================
# LIGHT FLAVOR - deploy-olympiad-light.sh  (8GB Raspberry Pi minimum viable HW)
# -----------------------------------------------------------------------------
# The Olympiad was born on Raspberry Pi 4 (HypriotOS, whitepaper 2018-2020);
# this chain restores that origin as a first-class flavor. It is derived line-
# by-line from the promoted artifact 'Production Artifacts/olympiad-deploy-
# light.sh' (the pristine artifact is still wget'd above, untouched, as the
# comparison baseline), with the same caulk helpers + waits as the full chain,
# '|| true' chaos-test tolerance on every step, and three deliberate deltas:
#   - dpkg filename fixed to the GitHubDesktop 3.1.1 actually wget'd (the
#     artifact dpkg'd a 2.9.6 file that never existed)
#   - torpedo image: quay.io/minio/minio -> pgsty/minio:latest (minio/minio
#     archived Feb 2026; pgsty is the declared arm64-wave standard and ships
#     latest-arm64 / latest-amd64)
#   - the artifact's bare 'network create' becomes ensure_net_bridge with
#     gateway 10.20.0.1 - docker's default for 10.20.0.0/24, so the effective
#     network is identical
# The artifact's commented-out SOC/k3d sections are not carried; they remain
# visible in the pristine artifact copy. Run with:
#   docker exec Underground-Nexus bash deploy-olympiad-light.sh   (or SEC-light)
# =============================================================================
RUN echo "#!/bin/sh" > deploy-olympiad-light.sh \
 && echo 'log() { echo "[olympiad] $*"; }' >> deploy-olympiad-light.sh \
 && echo 'wait_docker() { i=0; until docker info >/dev/null 2>&1; do i=$((i+1)); [ "$i" -ge 180 ] && { log "dockerd not ready after 180s - continuing best-effort"; return 1; }; [ $((i % 5)) -eq 0 ] && log "waiting for docker daemon... ($i)"; sleep 1; done; log "docker daemon ready"; }' >> deploy-olympiad-light.sh \
 && echo 'wait_container() { n="$1"; i=0; until [ "$(docker inspect -f "{{.State.Running}}" "$n" 2>/dev/null)" = "true" ]; do i=$((i+1)); [ "$i" -ge 120 ] && { log "$n not running after 120s - continuing"; return 1; }; sleep 1; done; log "$n running"; }' >> deploy-olympiad-light.sh \
 && echo 'wait_exec() { n="$1"; wait_container "$n" || true; i=0; until docker exec "$n" true >/dev/null 2>&1; do i=$((i+1)); [ "$i" -ge 120 ] && { log "$n not exec-ready after 240s - continuing"; return 1; }; sleep 2; done; log "$n exec-ready"; }' >> deploy-olympiad-light.sh \
 && echo 'retry() { n=0; until "$@"; do n=$((n+1)); [ "$n" -ge 5 ] && { log "failed after 5 tries: $*"; return 1; }; log "retry $n/5: $*"; sleep 3; done; }' >> deploy-olympiad-light.sh \
 && echo 'ensure_net_bridge() { docker network inspect "$1" >/dev/null 2>&1 && { log "net $1 exists"; return 0; }; M=$(net_mtu); if [ -n "$M" ]; then log "net $1 creating with mtu=$M"; retry docker network create -d bridge --opt com.docker.network.driver.mtu="$M" --subnet="$2" --gateway="$3" "$1"; else retry docker network create -d bridge --subnet="$2" --gateway="$3" "$1"; fi; }' >> deploy-olympiad-light.sh \
 && echo 'ensure_net_overlay() { docker network inspect "$1" >/dev/null 2>&1 && { log "net $1 exists"; return 0; }; retry docker network create -d overlay --subnet="$2" "$1"; }' >> deploy-olympiad-light.sh \
 && echo 'net_mtu() { case "${NEXUS_NET_MTU:-}" in "") : ;; auto) I=$(ip -4 route show default 2>/dev/null | awk "{print \$5; exit}"); [ -z "$I" ] && I=$(ls /sys/class/net 2>/dev/null | grep -v "^lo$" | head -1); [ -n "$I" ] && cat /sys/class/net/"$I"/mtu 2>/dev/null ;; *) echo "${NEXUS_NET_MTU}" ;; esac; }' >> deploy-olympiad-light.sh \
 && echo 'net_report() { R=$(docker network inspect "$1" --format "driver={{.Driver}} subnet={{range .IPAM.Config}}{{.Subnet}}{{end}} gw={{range .IPAM.Config}}{{.Gateway}}{{end}} mtu={{index .Options \"com.docker.network.driver.mtu\"}}" 2>/dev/null | sed "s/mtu=<no value>/mtu=default/"); log "net $1 $R"; }' >> deploy-olympiad-light.sh \
 && echo 'ensure_repo() { if [ -d /nexus-bucket/underground-nexus/.git ]; then git -C /nexus-bucket/underground-nexus pull --rebase >/dev/null 2>&1 || true; else mkdir -p /nexus-bucket; retry git clone https://github.com/Underground-Ops/underground-nexus.git /nexus-bucket/underground-nexus || true; fi; }' >> deploy-olympiad-light.sh \
 && echo 'pkg_add() { command -v "$1" >/dev/null 2>&1 && return 0; apk add --no-cache "$2" >/dev/null 2>&1 || { apt-get update >/dev/null 2>&1 && apt-get install -y "$2" >/dev/null 2>&1; } || dnf install -y "$2" >/dev/null 2>&1 || true; command -v "$1" >/dev/null 2>&1; }' >> deploy-olympiad-light.sh
RUN echo 'ensure_compose() { pkg_add docker-compose docker-compose || log "docker-compose not installable here - compose steps degrade"; }' >> deploy-olympiad-light.sh \
 && echo 'ensure_swarm() { docker node ls >/dev/null 2>&1 && { log "swarm already active - joining existing"; return 0; }; docker swarm init >/dev/null 2>&1 && { log "swarm init ok"; return 0; }; A=$(ip -4 route get 1.1.1.1 2>/dev/null | awk "{print \$7; exit}"); [ -z "$A" ] && A=$(hostname -i 2>/dev/null | awk "{print \$1}"); [ -n "$A" ] && docker swarm init --advertise-addr "$A" >/dev/null 2>&1 && { log "swarm init ok (advertise $A)"; return 0; }; log "swarm init failed - overlay nets may degrade to bridge"; return 1; }' >> deploy-olympiad-light.sh \
 && echo 'detect_substrate() { if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then NEXUS_METAL=0; else NEXUS_METAL=1; fi; DOCKER_BIN=$(command -v docker 2>/dev/null || echo /usr/local/bin/docker); NEXUS_ARCH=$(uname -m); if [ "$NEXUS_METAL" = "1" ]; then P_SSH="${P_SSH:-2223}"; P_DNS="${P_DNS:-5353}"; P_DHCP="${P_DHCP:-6767}"; P_S3="${P_S3:-19000}"; log "substrate: bare metal ($NEXUS_ARCH) - host publishes shifted ssh=$P_SSH dns=$P_DNS dhcp=$P_DHCP s3=$P_S3"; else P_SSH="${P_SSH:-22}"; P_DNS="${P_DNS:-53}"; P_DHCP="${P_DHCP:-67}"; P_S3="${P_S3:-9000}"; log "substrate: container ($NEXUS_ARCH) - canonical host publishes"; fi; log "docker cli at $DOCKER_BIN"; }' >> deploy-olympiad-light.sh \
 && echo '' >> deploy-olympiad-light.sh \
 && echo '# ---- preflight: wait for dockerd, ensure repo, clean slate ----' >> deploy-olympiad-light.sh \
 && echo 'wait_docker' >> deploy-olympiad-light.sh \
 && echo 'detect_substrate' >> deploy-olympiad-light.sh \
 && echo 'pkg_add git git || log "git unavailable - repo sync may skip"' >> deploy-olympiad-light.sh \
 && echo 'ensure_repo' >> deploy-olympiad-light.sh \
 && echo '[ "${OLYMPIAD_CLEAN:-1}" = "1" ] && for c in Inner-DNS-Control Olympiad0 workbench Athena0 torpedo; do docker rm -f "$c" >/dev/null 2>&1 || true; done' >> deploy-olympiad-light.sh
RUN echo 'ensure_swarm || true' >> deploy-olympiad-light.sh \
 && echo 'ensure_compose' >> deploy-olympiad-light.sh \
 && echo 'ensure_net_bridge Inner-Athena 10.20.0.0/24 10.20.0.1' >> deploy-olympiad-light.sh \
 && echo 'net_report Inner-Athena' >> deploy-olympiad-light.sh \
 && echo "docker run -itd -p 800:80 -h Inner-DNS-Control --name=Inner-DNS-Control --net=Inner-Athena --ip=10.20.0.20 --restart=always -v pihole_DNS_data:/etc/dnsmasq.d/ -v pihole_config:/etc/pihole/ pihole/pihole:latest || true" >> deploy-olympiad-light.sh \
 && echo 'wait_container Inner-DNS-Control' >> deploy-olympiad-light.sh \
 && echo "docker volume create portainer_data || true" >> deploy-olympiad-light.sh \
 && echo "docker run -d -p 8000:8000 -p 9443:9443 --name=Olympiad0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest || true" >> deploy-olympiad-light.sh \
 && echo "docker run -itd --name=workbench -h workbench --privileged -e PUID=1000 -e PGID=1000 -e TZ=America/Colorado -p 1000:3000 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v workbench0:/config -v /nexus-bucket:/config/Desktop/nexus-bucket -v /var/run/docker.sock:/var/run/docker.sock linuxserver/webtop:ubuntu-mate || true" >> deploy-olympiad-light.sh \
 && echo 'wait_exec workbench' >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo apt -y update >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh
RUN echo "docker exec workbench echo docker exec workbench sudo apt install -y wget >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo apt install -y git >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo apt install -y iputils-ping >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo wget https://github.com/shiftkey/desktop/releases/download/release-3.1.1-linux1/GitHubDesktop-linux-3.1.1-linux1.deb >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo dpkg -i GitHubDesktop-linux-3.1.1-linux1.deb >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo apt install -y apt-transport-https curl >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench wget https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo dpkg -i chrome-remote-desktop_current_amd64.deb >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench wget https://release.gitkraken.com/linux/gitkraken-amd64.deb >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo dpkg -i gitkraken-amd64.deb >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh
RUN echo "docker exec workbench echo docker exec workbench sudo dpkg -i discord.deb >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo apt install -y qemu >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils qemu-system qemu-system-x86 qemu-system-arm >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo apt install -y virt-manager >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo apt install -y synaptic >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec Athena0 sh /enable-weekly-updates.sh >> /nexus-bucket/enable-weekly-updates.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Terraform%20Master/terraform-workbench-install.sh >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo sh terraform-workbench-install.sh >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo mv /terraform-workbench-install.sh /config/Desktop/nexus-bucket >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo apt -y update --fix-missing >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh
RUN echo "docker exec workbench echo docker exec workbench sudo apt --fix-broken install -y >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo apt -y upgrade >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo apt install -y virt-manager >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo rm /usr/share/backgrounds/ubuntu-mate-jammy/Jammy-Jellyfish_WP_4096x2304_Green.png >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench sudo wget https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/Wallpapers/underground-nexus-scifi-space-jelly.png -O /usr/share/backgrounds/ubuntu-mate-jammy/Jammy-Jellyfish_WP_4096x2304_Green.png >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo 'docker run -itd --init --name=Athena0 -h Athena0 --dns=10.20.0.20 --net=Inner-Athena --restart=always -v athena0:/home/ -v /nexus-bucket:/nexus-bucket -v /etc/docker:/etc/docker -v ${DOCKER_BIN}:/usr/local/bin/docker -v /var/run/docker.sock:/var/run/docker.sock -v /var/lib/docker/volumes/:/var/lib/docker/volumes/ natoascode/athena0:latest || true' >> deploy-olympiad-light.sh \
 && echo 'wait_exec Athena0' >> deploy-olympiad-light.sh \
 && echo "docker exec Athena0 apt -y update || true" >> deploy-olympiad-light.sh \
 && echo "docker exec Athena0 apt install -y iputils-ping || true" >> deploy-olympiad-light.sh \
 && echo "docker exec Athena0 git clone https://github.com/radareorg/radare2 || true" >> deploy-olympiad-light.sh
RUN echo "docker exec Athena0 sh radare2/sys/install.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec Athena0 apt-get install -y metasploit-framework || true" >> deploy-olympiad-light.sh \
 && echo "docker exec Athena0 apt -y update || true" >> deploy-olympiad-light.sh \
 && echo "docker exec Athena0 apt -y upgrade || true" >> deploy-olympiad-light.sh \
 && echo 'docker run -itd --privileged -p ${P_S3}:9000 -p 9010:9001 --name=torpedo -h torpedo --dns=10.20.0.20 --net=Inner-Athena --restart=always -v /nexus-bucket:/nexus-bucket -v /nexus-bucket/s3-torpedo:/data pgsty/minio:latest server /data --console-address :9001 || true' >> deploy-olympiad-light.sh \
 && echo "docker exec Athena0 sh /old-underground-nexus-dagger-ci.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec Athena0 sh /nexus-bucket/underground-nexus/'Dagger CI'/Scripts/enable-weekly-updates.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench echo docker exec workbench bash /config/Desktop/nexus-bucket/underground-nexus/visual-studio-code.sh >> /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec Athena0 sh /nexus-bucket/workbench.sh || true" >> deploy-olympiad-light.sh \
 && echo "docker exec workbench bash /config/Desktop/nexus-bucket/terraform-workbench-install.sh && docker exec workbench terraform -v || true" >> deploy-olympiad-light.sh
RUN echo "docker exec Athena0 curl https://raw.githubusercontent.com/Underground-Ops/underground-nexus/main/underground-nexus-update.sh | bash || true" >> deploy-olympiad-light.sh \
 && echo "docker restart Inner-DNS-Control || true" >> deploy-olympiad-light.sh

RUN apk upgrade