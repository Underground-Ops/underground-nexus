# Create the NetworkAttachmentDefinition YAML file at root
cat <<EOF > /vm-bridge-network.yml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: vm-bridge-network
  namespace: vm
  annotations:
    k8s.v1.cni.cncf.io/resourceName: intel.com/intel_sriov_netdevice
spec:
  config: '{
    "type": "sriov",
    "cniVersion": "0.3.1",
    "name": "vm-bridge-network",
    "plugins": [
      {
        "type": "bridge",
        "bridge": "br0",
        "ipam": {
          "type": "host-local",
          "subnet": "10.10.0.0/16",
          "rangeStart": "10.10.0.10",
          "rangeEnd": "10.10.0.100",
          "routes": [
            {"dst": "0.0.0.0/0"}
          ],
          "gateway": "10.10.0.1"
        }
      }
    ]
  }'
EOF

#---------------------
# Example of vm-bridge-network.yml
#---------------------
# apiVersion: k8s.cni.cncf.io/v1
# kind: NetworkAttachmentDefinition
# metadata:
#   name: vm-bridge-network
#   namespace: vm
# spec:
#   config: '{
#     "cniVersion": "0.3.1",
#     "name": "vm-bridge-network",
#     "plugins": [
#       {
#         "type": "bridge",
#         "bridge": "br0",
#         "ipam": {
#           "type": "host-local",
#           "subnet": "10.10.0.0/16",
#           "rangeStart": "10.10.0.10",
#           "rangeEnd": "10.10.0.100",
#           "routes": [
#             {"dst": "0.0.0.0/0"}
#           ],
#           "gateway": "10.10.0.1"
#         }
#       }
#     ]
#   }'
#-------------------
# IF k3s is needed then uncomment this
#curl -sfL https://get.k3s.io | sh -
#sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
#sudo chown $(id -u):$(id -g) $HOME/.kube/config
# Run this next to crete a Kubernetes network:
kubectl create namespace vm
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml
kubectl apply -f vm-bridge-network.yml
#Install KubeVirt
export VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
echo $VERSION
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-operator.yaml
kubectl create -f https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-cr.yaml
kubectl get all -n kubevirt
# Kubevirt-Manager
kubectl apply -f https://raw.githubusercontent.com/kubevirt-manager/kubevirt-manager/main/kubernetes/bundled.yaml
# List services to see ports and networking
kubectl get svc -A

#---------------------
# Install virtctl to manage VM’s from command line:

# Get the current KubeVirt version
VERSION=$(kubectl get kubevirt.kubevirt.io/kubevirt -n kubevirt -o=jsonpath="{.status.observedKubeVirtVersion}")

# Determine system architecture
ARCH="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m | sed 's/x86_64/amd64/')"

# Download virtctl
curl -L -o virtctl "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/virtctl-${VERSION}-${ARCH}"

# Make it executable
chmod +x virtctl

# Move it to a directory in your PATH
sudo install virtctl /usr/local/bin/
#---------------------

# Install CDIs:
kubectl apply -f https://github.com/kubevirt/containerized-data-importer/releases/latest/download/cdi-operator.yaml
kubectl apply -f https://github.com/kubevirt/containerized-data-importer/releases/latest/download/cdi-cr.yaml

# To edit manually with vim enter menu to change type to "LoadBalancer"
#kubectl edit svc kubevirt-manager -n kubevirt-manager
# Save type as "LoadBalancer"

# Set the service type of kubevirt-manager to LoadBalancer
echo "Patching kubevirt-manager service to type LoadBalancer..."
kubectl patch svc kubevirt-manager -n kubevirt-manager -p '{"spec": {"type": "LoadBalancer"}}'

# Optional: Confirm the change
echo "Verifying service type..."
kubectl get svc kubevirt-manager -n kubevirt-manager

#---------------------------