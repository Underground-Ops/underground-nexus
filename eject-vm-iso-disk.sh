#!/bin/bash
kubectl patch vm lubuntu-vm -n vm --type=json -p='[
  {"op": "remove", "path": "/spec/template/spec/domain/devices/disks/0"},
  {"op": "remove", "path": "/spec/template/spec/volumes/0"}
]'

#Add SR-IOV to the VM and restart vm

virtctl stop lubuntu-vm -n vm

kubectl patch vm lubuntu-vm -n vm --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/networks/-",
    "value": {
      "name": "vm-bridge-network",
      "multus": {
        "networkName": "vm/vm-bridge-network"
      }
    }
  }
]'




kubectl patch vm lubuntu-vm -n vm --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/domain/devices/interfaces/-",
    "value": {
      "name": "vm-bridge-network",
      "bridge": {}
    }
  }
]'

virtctl start lubuntu-vm -n vm