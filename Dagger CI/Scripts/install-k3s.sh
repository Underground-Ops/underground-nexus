#!/bin/bash
# install_k3s.sh
#
# This script installs k3s (Lightweight Kubernetes) onto your system.
# It will check for root privileges, verify prerequisites, and install k3s.
#
# Usage:
#   sudo ./install_k3s.sh
#
# To install a specific version of k3s, run:
#   INSTALL_K3S_VERSION=v1.25.0+k3s1 sudo ./install_k3s.sh
#
# Note: This script uses the upstream installer at https://get.k3s.io

set -euo pipefail

#------------------------------------------------#
#        Preliminary Checks and Setup            #
#------------------------------------------------#

# Ensure the script is executed as root.
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Exiting." >&2
  exit 1
fi

# Check if curl exists.
if ! command -v curl >/dev/null; then
  echo "curl is required but was not found. Please install curl and try again." >&2
  exit 1
fi

# Verify k3s is not already installed.
if command -v k3s || command -v k3s-server >/dev/null; then
  echo "k3s appears to be already installed. Exiting." >&2
  exit 0
fi

# Determine the desired k3s version.
# Set INSTALL_K3S_VERSION in your environment to override the default ("latest").
K3S_VERSION="${INSTALL_K3S_VERSION:-latest}"

echo "Starting installation of k3s version: ${K3S_VERSION}"

#------------------------------------------------#
#         k3s Installation Process               #
#------------------------------------------------#

# Download and run the k3s installer.
if [ "${K3S_VERSION}" = "latest" ]; then
    curl -sfL https://get.k3s.io | sh -
else
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" sh -
fi

#------------------------------------------------#
#          Post Install Verification             #
#------------------------------------------------#

if [ $? -eq 0 ]; then
  echo "k3s installation completed successfully!"
  echo "Verifying k3s version:"
  # k3s installation typically puts the binary in /usr/local/bin.
  if command -v k3s-server >/dev/null; then
     k3s-server --version || true
  elif command -v k3s >/dev/null; then
     k3s --version || true
  else
     echo "k3s installed, but the version check command was not found."
  fi
else
  echo "k3s installation failed." >&2
  exit 1
fi