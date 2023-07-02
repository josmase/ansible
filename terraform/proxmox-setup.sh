#!/bin/bash
source .env.sh
source .env.secrets.sh

ssh-copy-id -i ~/.ssh/id_rsa.pub root@$TF_VAR_proxmox_host

ssh root@$TF_VAR_proxmox_host 'bash -s' < proxmox-user.sh $PM_USER $PM_PASS
ssh root@$TF_VAR_proxmox_host 'bash -s' < proxmox-cloud-image-template.sh 9000 $TF_VAR_proxmox_storage $TF_VAR_ubuntu_template_20G "20G"
ssh root@$TF_VAR_proxmox_host 'bash -s' < proxmox-cloud-image-template.sh 9001 $TF_VAR_proxmox_storage $TF_VAR_ubuntu_template_300G "300G"