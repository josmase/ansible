#!/bin/bash

if [[  -z "${1}" || -z "${2}" || -z "${3}" || -z "${4}" ]]; then
    echo "Usage: $0 <id> <proxmox storage name> <template name> <disk size>"
    exit 1
fi

virtualMachineId=$1
volumeName=$2
templateName=$3
diskSize=$4
imageURL=https://cloud-images.ubuntu.com/lunar/current/lunar-server-cloudimg-amd64.img
imageName="lunar-server-cloudimg-amd64-$diskSize.img"
tmp_cores="2"
tmp_memory="2048"

#Cleanup
rm $imagename
wget $imageURL -O $imageName
qm destroy $virtualMachineId

#Increase root disk size
qemu-img resize $imageName "+$diskSize"
virt-customize -a $imagename --install cloud-guest-utils
virt-customize -a $imagename --run-command growpart /dev/vda 1

#Continue with normal install
virt-customize -a $imageName --install qemu-guest-agent
qm create $virtualMachineId --name $templateName --memory $tmp_memory --cores $tmp_cores --net0 virtio,bridge=vmbr0
qm importdisk $virtualMachineId $imageName $volumeName
qm set $virtualMachineId --scsihw virtio-scsi-pci --scsi0 $volumeName:vm-$virtualMachineId-disk-0
qm set $virtualMachineId --boot c --bootdisk scsi0
qm set $virtualMachineId --ide2 $volumeName:cloudinit
qm set $virtualMachineId --serial0 socket --vga serial0
qm template $virtualMachineId