#!/bin/bash
source .env
ssh root@$TF_VAR_PROXMOX_HOST 'bash -s' < proxmox-user.sh
ssh root@$TF_VAR_PROXMOX_HOST 'bash -s' < proxmox-cloud-image-template.sh $TF_VAR_PROXMOX_STORAGE $TF_VAR_UBUNTU_TEMPLATE