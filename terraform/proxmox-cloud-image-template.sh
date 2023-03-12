#!/bin/bash

if [[ -z "${1}" || -z "${2}" ]]; then
    echo "Usage: $0 <proxmox storage name> <template name>"
    exit 1
fi

volumeName=$1
templateName=$2
imageURL=https://cloud-images.ubuntu.com/lunar/current/lunar-server-cloudimg-amd64.img
imageName="lunar-server-cloudimg-amd64.img"
virtualMachineId="9000"
tmp_cores="2"
tmp_memory="2048"


rm $imagename
wget -O $imageName $imageURL
qm destroy $virtualMachineId
virt-customize -a $imageName --install qemu-guest-agent
qm create $virtualMachineId --name $templateName --memory $tmp_memory --cores $tmp_cores --net0 virtio,bridge=vmbr0
qm importdisk $virtualMachineId $imageName $volumeName
qm set $virtualMachineId --scsihw virtio-scsi-pci --scsi0 $volumeName:vm-$virtualMachineId-disk-0
qm set $virtualMachineId --boot c --bootdisk scsi0
qm set $virtualMachineId --ide2 $volumeName:cloudinit
qm set $virtualMachineId --serial0 socket --vga serial0
qm template $virtualMachineId