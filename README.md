This repo contains code for setting up my own media server, network configuration and stuff.


# Finding drives

`lsblk |awk 'NR==1{print $0" DEVICE-ID(S)"}NR>1{dev=$1;printf $0" ";system("find /dev/disk/by-id -lname \"*"dev"\" -printf \" %p\"");print "";}'|grep -v -E 'part|lvm'`

# Adding drive to VM

Edit the VM using `virsh edit VMNAME` and add the below XML

```xml
    <disk type='block' device='disk'>
        <driver name='qemu' type='raw'/>
        <source dev='/dev/disk/by-id/DISK_ID'/>
        <target dev='vdc' bus='virtio'/>
    </disk>
```

Apply the change `virsh define /etc/libvirt/qemu/VMNAME.xml`

