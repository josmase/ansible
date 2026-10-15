#!/bin/bash

if [[ -z "${1}" || -z "${2}" || -z "${3}" || -z "${4}" ]]; then
    echo "Usage: $0 <id> <proxmox storage name> <template name> <disk size>"
    exit 1
fi

virtualMachineId=$1
volumeName=$2
templateName=$3
diskSize=$4
imageURL=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
unmodifiedImageName="noble-server-cloudimg-amd64-unmodified.img"
imageName="noble-server-cloudimg-amd64-$diskSize.img"
tmp_cores="2"
tmp_memory="2048"

# Check if the unmodified image file already exists
if [ ! -f "$unmodifiedImageName" ]; then
    echo "Downloading image from $imageURL..."
    wget -q "$imageURL" -O "$unmodifiedImageName" || { echo "Error downloading image"; exit 1; }
else
    echo "Unmodified image '$unmodifiedImageName' already exists. Skipping download."
fi

# Create a copy of the unmodified image for this run. This is needed as the commands below modify the image in place.
echo "Creating a copy of the unmodified image..."
cp "$unmodifiedImageName" "$imageName" || { echo "Error creating copy of image"; exit 1; }


echo "Destroying existing VM with ID $virtualMachineId (if exists)..."
qm destroy "$virtualMachineId"

# Increase root disk size
echo "Resizing root disk by $diskSize..."
qemu-img resize "$imageName" "+$diskSize" || { echo "Error resizing disk"; exit 1; }

echo "Installing required packages and resizing partitions..."
virt-customize -a "$imageName" --install cloud-guest-utils || { echo "Error installing cloud-guest-utils"; exit 1; }
resize_command="growpart /dev/sda 1 && resize2fs /dev/sda1"

echo "Running '$resize_command' on the image..."
if ! virt-customize -a "$imageName" --run-command "$resize_command"; then
    echo "Attempting additional troubleshooting steps:"
    
    # Check disk information
    echo "Checking disk information..."
    fdisk -l "$imageName" || { echo "Error checking disk information"; exit 1; }

    # Check available space
    echo "Checking available space..."
    df -h || { echo "Error checking available space"; exit 1; }

    # Check filesystem
    echo "Checking filesystem type..."
    virt-filesystems -a "$imageName" --all --long --filesystems || { echo "Error checking filesystem type"; exit 1; }

    # Exit with a more specific error message
    echo "Error resizing partition or filesystem"; exit 1;
fi

# Continue with normal install
echo "Updating package lists and upgrading existing packages..."
virt-customize -a "$imageName" --run-command "apt-get update && apt-get upgrade -y" || { echo "Error updating packages"; exit 1; }

echo "Installing qemu-guest-agent..."
if ! virt-customize -a "$imageName" --install qemu-guest-agent; then
    echo "Failed to install qemu-guest-agent normally. Attempting force installation..."
    virt-customize -a "$imageName" --run-command "apt-get download qemu-guest-agent && dpkg --force-all -i qemu-guest-agent*.deb && apt-get install -f -y" || { echo "Error force installing qemu-guest-agent"; exit 1; }
fi

echo "Creating VM with ID $virtualMachineId, name $templateName..."
qm create "$virtualMachineId" --name "$templateName" --memory "$tmp_memory" --cores "$tmp_cores" --net0 virtio,bridge=vmbr0 || { echo "Error creating VM"; exit 1; }

echo "Importing disk to VM..."
qm importdisk "$virtualMachineId" "$imageName" "$volumeName" || { echo "Error importing disk"; exit 1; }

echo "Configuring VM settings..."
qm set "$virtualMachineId" --scsihw virtio-scsi-pci --scsi0 "$volumeName:vm-$virtualMachineId-disk-0" || { echo "Error configuring VM"; exit 1; }
qm set "$virtualMachineId" --boot c --bootdisk scsi0 || { echo "Error setting boot options"; exit 1; }
qm set "$virtualMachineId" --ide2 "$volumeName:cloudinit" || { echo "Error configuring cloudinit"; exit 1; }
qm set "$virtualMachineId" --serial0 socket --vga serial0 || { echo "Error configuring serial and VGA"; exit 1; }

echo "Setting VM as template..."
qm template "$virtualMachineId" || { echo "Error setting VM as template"; exit 1; }

echo "Cleaning up modified image..."
rm "$imageName" || { echo "Error removing modified image"; exit 1; }

echo "VM creation and setup completed successfully!"
