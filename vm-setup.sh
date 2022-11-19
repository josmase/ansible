export VM_NAME="master-1"
export CLOUD_VERSION="focal"
export CLOUD_IMAGE="${CLOUD_VERSION}-server-cloudimg-amd64-disk-kvm.img"
export BASE_IMAGE_NAME="ubuntu20.04"

export BASE_IMAGE_FILE="/var/lib/libvirt/images/base/${BASE_IMAGE_NAME}.qcow2"
export VM_IMAGE_FOLDER="/var/lib/libvirt/images/${VM_NAME}"
export VM_IMAGE_FILE="${VM_IMAGE_FOLDER}/${VM_NAME}.qcow2"
export VM_CLOUD_IMAGE_FILE="${VM_IMAGE_FOLDER}/${VM_NAME}-cidata.iso"

if [[ ! -f ./pubkey ]]
then
	echo "You must provide a public key in ./pubkey"
	exit 1
fi

export PUB_KEY=$(cat ./pubkey)

#Exit on any error
set -e


rm -f user-data
cat >user-data <<EOF
#cloud-config
users:
  - name: ubuntu
    ssh-authorized-keys:
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    groups: sudo
    shell: /bin/bash
runcmd:
  - echo "AllowUsers ubuntu" >> /etc/ssh/sshd_config
  - restart ssh
EOF

rm -f meta-data
echo "local-hostname: ${VM_NAME}" > meta-data



if [[ ! -f "$BASE_IMAGE_FILE" ]]
then
	echo "Base file does not exist. Downloading it now to ${CLOUD_IMAGE}"
	sudo mkdir -pv /var/lib/libvirt/images/base
	wget "https://cloud-images.ubuntu.com/${CLOUD_VERSION}/current/${CLOUD_IMAGE}"
	sudo mv -v "${CLOUD_IMAGE}" "${BASE_IMAGE_FILE}"
	sudo qemu-img info "${BASE_IMAGE_FILE}"
	echo "Base file download done"
fi

echo "Create vm image from base image"
sudo mkdir -pv "/var/lib/libvirt/images/${VM_NAME}"
sudo qemu-img create -f qcow2 -F qcow2 -o backing_file=$BASE_IMAGE_FILE $VM_IMAGE_FILE
sudo qemu-img resize $VM_IMAGE_FILE 5G

echo "Create cloud image data from config"
sudo genisoimage  -output $VM_CLOUD_IMAGE_FILE -volid cidata -joliet -rock user-data meta-data


echo "Start the machine"
virt-install --connect qemu:///system --virt-type kvm --name $VM_NAME --ram 2048 --vcpus=1 \
--os-variant $BASE_IMAGE_NAME --disk path=$VM_IMAGE_FILE,format=qcow2 --disk $VM_CLOUD_IMAGE_FILE,device=cdrom --import \
--network network=default --noautoconsole
