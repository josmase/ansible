This repo contains code for setting up my own media server, network configuration and stuff.


# Adding a new drive

Find the drive, add it to the vm, format it.

## Finding drives


```sh
ls -la /dev/disk/by-id
qm set $VM_ID -scsi$DRIVE_NUMBER /dev/disks/by-id/$DRIVE_ID
```

## Use GPT with LUKS encrypted XFS partition

```sh
DRIVE="some drive name to use"
lsblk -o NAME,UUID,FSTYPE,SIZE --json
sudo sgdisk -n 1:0:0 /dev/$DRIVE
sudo cryptsetup luksFormat /dev/${DRIVE}1 --key-file ./keyfile
sudo cryptsetup luksOpen /dev/${DRIVE}1 ${DRIVE}1 --key-file ./keyfile
sudo mkfs.xfs /dev/mapper/${DRIVE}1
```

