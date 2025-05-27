#!/bin/bash

#Get ISO
mkdir -p /nexus-bucket/virtual-machines
wget -nc -O /nexus-bucket/virtual-machines/lubuntu-25.04-desktop-amd64.iso https://cdimage.ubuntu.com/lubuntu/releases/25.04/release/lubuntu-25.04-desktop-amd64.iso

# Create storage-class.yaml
cat <<EOF > /nexus-bucket/virtual-machines/storage-class.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: custom-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: Immediate
EOF

# Create iso-pv.yaml
cat <<EOF > /nexus-bucket/virtual-machines/iso-pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: iso-pv
spec:
  capacity:
    storage: 5Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
  storageClassName: custom-storage
  hostPath:
    path: /data/iso
  claimRef:
    name: my-iso-dv
    namespace: vm
EOF

# Create install-pv.yaml
cat <<EOF > /nexus-bucket/virtual-machines/install-pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: install-pv
spec:
  capacity:
    storage: 50Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
  storageClassName: custom-storage
  hostPath:
    path: /data/install
  claimRef:
    name: my-install-disk
    namespace: vm
EOF

# Create pvc.yaml
cat <<EOF > /nexus-bucket/virtual-machines/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-install-disk
spec:
  accessModes:
  - ReadWriteOnce
  volumeMode: Filesystem
  resources:
    requests:
      storage: 50Gi
  storageClassName: custom-storage
EOF

# Create dv.yaml
cat <<EOF > /nexus-bucket/virtual-machines/dv.yaml
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: my-iso-dv
spec:
  source:
    upload: {}
  pvc:
    accessModes:
    - ReadWriteOnce
    volumeMode: Filesystem
    resources:
      requests:
        storage: 5Gi
    storageClassName: custom-storage
EOF

# Create vm.yaml
cat <<EOF > /nexus-bucket/virtual-machines/vm.yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: lubuntu-vm
spec:
  running: false
  template:
    metadata:
      labels:
        kubevirt.io/domain: lubuntu-vm
    spec:
      domain:
        cpu:
          sockets: 1
          cores: 2
          threads: 1
        resources:
          requests:
            memory: 8Gi
        devices:
          disks:
          - name: cdromiso
            bootOrder: 1
            cdrom:
              bus: sata
              readonly: true
          - name: instdisk
            bootOrder: 2
            disk:
              bus: virtio
      volumes:
      - name: cdromiso
        dataVolume:
          name: my-iso-dv
      - name: instdisk
        persistentVolumeClaim:
          claimName: my-install-disk
      terminationGracePeriodSeconds: 0
EOF

# Apply the StorageClass, PVs, PVCs, and DataVolume
kubectl apply -f /nexus-bucket/virtual-machines/storage-class.yaml -n vm
kubectl apply -f /nexus-bucket/virtual-machines/iso-pv.yaml -n vm
kubectl apply -f /nexus-bucket/virtual-machines/install-pv.yaml -n vm
kubectl apply -f /nexus-bucket/virtual-machines/pvc.yaml -n vm
kubectl apply -f /nexus-bucket/virtual-machines/dv.yaml -n vm

# Set permissions and volumes
sudo mkdir -p /data
sudo mkdir -p /data/iso
sudo chown -R 107:107 /data/iso
sudo chmod -R 770 /data/iso

sudo mkdir -p /data/install
sudo chown -R 107:107 /data/install
sudo chmod -R 770 /data/install

docker exec k3d-KuberNexus-server-0 chown -R 107:107 /data/iso
docker exec k3d-KuberNexus-server-0 chmod -R 0755 /data/iso

# Port-forward the CDI Upload Proxy service
kubectl port-forward -n cdi svc/cdi-uploadproxy 8443:443 &
sleep 5

# Upload the ISO to the DataVolume
virtctl -n vm image-upload \
  --pvc-name=my-iso-dv \
  --image-path=/nexus-bucket/virtual-machines/lubuntu-25.04-desktop-amd64.iso \
  --access-mode=ReadWriteOnce \
  --insecure \
  --force-bind \
  --uploadproxy-url=https://127.0.0.1:8443

# Apply the VM
kubectl apply -f /nexus-bucket/virtual-machines/vm.yaml -n vm