#!/bin/bash

# =============================================================================
# nexus-devsecops-appinator.sh — Underground Nexus DEV / SEC / OPS commands
# -----------------------------------------------------------------------------
# ARCH-AGNOSTIC (amd64 / arm64): the Underground Nexus image tag is detected at
# install time from this host's architecture (the host that installs these
# commands is the host that runs them). Override with the NEXUS_IMAGE env var
# before running this script if you need a specific image or tag:
#     NEXUS_IMAGE=natoascode/underground-nexus:latest bash nexus-devsecops-appinator.sh
#
# PORT REMAP (host side only — every dind/container-side port is unchanged, so
# nothing inside the Nexus moves; only where you reach it from the host moves):
#     -p 22        ->  -p 2222:22    SSH to Athena0. 2222:22 is the ORIGINAL
#                                    Inner-Athena mapping from the 2018-2020
#                                    Olympiad whitepaper (and it is now
#                                    deterministic instead of a random port).
#     -p 80:80     ->  -p 8090:80    was colliding with host webservers /
#     -p 443:443   ->  -p 4443:443   Cerberus edge-router (Traefik on 80/443)
#     -p 8080:8080 ->  -p 8180:8080
# These were the exact conflicts that forced the SEC-exoskeleton workaround
# (see its original comment); standard SEC no longer collides. The
# SEC-exoskeleton commands are kept unchanged for compatibility.
#
# NEW: SEC-light — deploys the same Underground Nexus container but activates
# deploy-olympiad-light.sh, the 8GB-Raspberry-Pi-minimum flavor (no SOC, no
# KuberNexus, no code-server/vault). Publishes only what light runs:
# pihole admin (800), workbench (1000), MinIO console (9010), Portainer (9050).
# =============================================================================

# ---- Architecture detection (install-time) ----
NEXUS_ARCH=$(uname -m)
case "${NEXUS_ARCH}" in
    x86_64)          NEXUS_TAG=amd64 ;;
    aarch64|arm64)   NEXUS_TAG=arm64 ;;
    *)               NEXUS_TAG=amd64 ;;
esac
NEXUS_IMAGE="${NEXUS_IMAGE:-natoascode/underground-nexus:${NEXUS_TAG}}"
echo "Underground Nexus image for this host (${NEXUS_ARCH}): ${NEXUS_IMAGE}"

# ---- Standard DevSecOps Commands ---- (standard DEV, SEC and OPS deployments)

# Create the DEV command script
echo 'docker run -itd --name=nexus-creator-vault -h nexus-creator-vault --privileged -p 1050:3000 -e PUID=1050 -e PGID=1050 -e TZ=America/Colorado --restart unless-stopped -v /dev:/dev -v creator-vault0:/config -v /var/run/docker.sock:/var/run/docker.sock natoascode/zero-trust-cockpit:creator-vault' > /usr/local/bin/DEV
chmod +x /usr/local/bin/DEV

# Create the SEC command script
echo "docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 2222:22 -p 8090:80 -p 8180:8080 -p 4443:443 -p 1000:1000 -p 2000:2000 -p 2375:2375 -p 2376:2376 -p 2377:2377 -p 9010:9010 -p 9050:9443 -p 18080:18080 -p 18443:18443 -v /dev:/dev -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket ${NEXUS_IMAGE} && docker exec Underground-Nexus bash deploy-olympiad.sh" > /usr/local/bin/SEC
chmod +x /usr/local/bin/SEC

# Create the SEC-light command script (8GB Raspberry Pi minimum viable hardware)
echo "docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 800:800 -p 1000:1000 -p 9010:9010 -p 9050:9443 -v /dev:/dev -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket ${NEXUS_IMAGE} && docker exec Underground-Nexus bash deploy-olympiad-light.sh" > /usr/local/bin/SEC-light
chmod +x /usr/local/bin/SEC-light

# Create the OPS command script
echo "docker run -itd --name=Underground-Ops -h Underground-Ops --privileged --init -p 1060:1050 -v /dev:/dev -v underground-ops-docker-socket:/var/run ${NEXUS_IMAGE}" > /usr/local/bin/OPS
chmod +x /usr/local/bin/OPS

echo "Commands have been added to /usr/local/bin and are now executable."

# ---- Cerberus Manager SEC-exoskeleton Command ---- (kept for compatibility: it
# predates the port remap above, which resolves the port 80, 443 and 23**
# conflicts that originally required this variant)

# Create the SEC-exoskeleton command script
echo "docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 1000:1000 -p 2000:2000 -p 9010:9010 -p 9050:9443 -p 18080:18080 -v /dev:/dev -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket ${NEXUS_IMAGE} && docker exec Underground-Nexus bash deploy-olympiad.sh" > /usr/local/bin/SEC-exoskeleton
chmod +x /usr/local/bin/SEC-exoskeleton

echo "Command has been added to /usr/local/bin and is now executable."

# ---- Rebuild Commands ---- (completely deletes all resources and rebuilds DEV, SEC or OPS)

# Create the DEV-rebuild command script
echo 'docker container stop nexus-creator-vault && docker container rm nexus-creator-vault && docker volume rm creator-vault0 && docker pull natoascode/zero-trust-cockpit:creator-vault && docker run -itd --name=nexus-creator-vault -h nexus-creator-vault --privileged -p 1050:3000 -e PUID=1050 -e PGID=1050 -e TZ=America/Colorado --restart unless-stopped -v /dev:/dev -v creator-vault0:/config -v /var/run/docker.sock:/var/run/docker.sock natoascode/zero-trust-cockpit:creator-vault' > /usr/local/bin/DEV-rebuild
chmod +x /usr/local/bin/DEV-rebuild

# Create the SEC-rebuild command script
echo "docker container stop Underground-Nexus && docker container rm Underground-Nexus && docker volume rm underground-nexus-docker-socket underground-nexus-data nexus-bucket && docker pull ${NEXUS_IMAGE} && docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 2222:22 -p 8090:80 -p 8180:8080 -p 4443:443 -p 1000:1000 -p 2000:2000 -p 2375:2375 -p 2376:2376 -p 2377:2377 -p 9010:9010 -p 9050:9443 -p 18080:18080 -p 18443:18443 -v /dev:/dev -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket ${NEXUS_IMAGE} && docker exec Underground-Nexus bash deploy-olympiad.sh" > /usr/local/bin/SEC-rebuild
chmod +x /usr/local/bin/SEC-rebuild

# Create the SEC-light-rebuild command script
echo "docker container stop Underground-Nexus && docker container rm Underground-Nexus && docker volume rm underground-nexus-docker-socket underground-nexus-data nexus-bucket && docker pull ${NEXUS_IMAGE} && docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 800:800 -p 1000:1000 -p 9010:9010 -p 9050:9443 -v /dev:/dev -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket ${NEXUS_IMAGE} && docker exec Underground-Nexus bash deploy-olympiad-light.sh" > /usr/local/bin/SEC-light-rebuild
chmod +x /usr/local/bin/SEC-light-rebuild

# Create the SEC-exoskeleton-rebuild command script
echo "docker container stop Underground-Nexus && docker container rm Underground-Nexus && docker volume rm underground-nexus-docker-socket underground-nexus-data nexus-bucket && docker pull ${NEXUS_IMAGE} && docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 1000:1000 -p 2000:2000 -p 9010:9010 -p 9050:9443 -p 18080:18080 -v /dev:/dev -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket ${NEXUS_IMAGE} && docker exec Underground-Nexus bash deploy-olympiad.sh" > /usr/local/bin/SEC-exoskeleton-rebuild
chmod +x /usr/local/bin/SEC-exoskeleton-rebuild

# Create the OPS-rebuild command script
echo "docker container stop Underground-Ops && docker container rm Underground-Ops && docker volume rm underground-ops-docker-socket nexus-bucket && docker pull ${NEXUS_IMAGE} && docker run -itd --name=Underground-Ops -h Underground-Ops --privileged --init -p 1060:1050 -v /dev:/dev -v underground-ops-docker-socket:/var/run ${NEXUS_IMAGE}" > /usr/local/bin/OPS-rebuild
chmod +x /usr/local/bin/OPS-rebuild

# ---- Restore Commands ---- (deletes container without deleting images and rebuilds DEV, SEC or OPS environments with volumes intact)

# Create the DEV-restore command script
echo 'docker container stop nexus-creator-vault && docker container rm nexus-creator-vault && docker pull natoascode/zero-trust-cockpit:creator-vault && docker run -itd --name=nexus-creator-vault -h nexus-creator-vault --privileged -p 1050:3000 -e PUID=1050 -e PGID=1050 -e TZ=America/Colorado --restart unless-stopped -v /dev:/dev -v creator-vault0:/config -v /var/run/docker.sock:/var/run/docker.sock natoascode/zero-trust-cockpit:creator-vault' > /usr/local/bin/DEV-restore
chmod +x /usr/local/bin/DEV-restore

# Create the SEC-restore command script
echo "docker container stop Underground-Nexus && docker container rm Underground-Nexus && docker volume rm underground-nexus-docker-socket && docker pull ${NEXUS_IMAGE} && docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 2222:22 -p 8090:80 -p 8180:8080 -p 4443:443 -p 1000:1000 -p 2000:2000 -p 2375:2375 -p 2376:2376 -p 2377:2377 -p 9010:9010 -p 9050:9443 -p 18080:18080 -p 18443:18443 -v /dev:/dev -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket ${NEXUS_IMAGE} && docker exec Underground-Nexus bash deploy-olympiad.sh" > /usr/local/bin/SEC-restore
chmod +x /usr/local/bin/SEC-restore

# Create the SEC-light-restore command script
echo "docker container stop Underground-Nexus && docker container rm Underground-Nexus && docker volume rm underground-nexus-docker-socket && docker pull ${NEXUS_IMAGE} && docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 800:800 -p 1000:1000 -p 9010:9010 -p 9050:9443 -v /dev:/dev -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket ${NEXUS_IMAGE} && docker exec Underground-Nexus bash deploy-olympiad-light.sh" > /usr/local/bin/SEC-light-restore
chmod +x /usr/local/bin/SEC-light-restore

# Create the SEC-exoskeleton-restore command script
echo "docker container stop Underground-Nexus && docker container rm Underground-Nexus && docker volume rm underground-nexus-docker-socket && docker pull ${NEXUS_IMAGE} && docker run -itd --name=Underground-Nexus -h Underground-Nexus --privileged --init -p 1000:1000 -p 2000:2000 -p 9010:9010 -p 9050:9443 -p 18080:18080 -v /dev:/dev -v underground-nexus-docker-socket:/var/run -v underground-nexus-data:/var/lib/docker/volumes -v nexus-bucket:/nexus-bucket ${NEXUS_IMAGE} && docker exec Underground-Nexus bash deploy-olympiad.sh" > /usr/local/bin/SEC-exoskeleton-restore
chmod +x /usr/local/bin/SEC-exoskeleton-restore

# Create the OPS-restore command script
echo "docker container stop Underground-Ops && docker container rm Underground-Ops && docker pull ${NEXUS_IMAGE} && docker run -itd --name=Underground-Ops -h Underground-Ops --privileged --init -p 1060:1050 -v /dev:/dev -v underground-ops-docker-socket:/var/run ${NEXUS_IMAGE}" > /usr/local/bin/OPS-restore
chmod +x /usr/local/bin/OPS-restore