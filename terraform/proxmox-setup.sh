#!/bin/bash
source .env.sh
source .env.secrets.sh

ssh root@$TF_VAR_proxmox_host 'bash -s' < proxmox-user.sh $PM_USER $PM_PASS
ssh root@$TF_VAR_proxmox_host 'bash -s' < proxmox-cloud-image-template.sh $TF_VAR_proxmox_storage $TF_VAR_ubuntu_template