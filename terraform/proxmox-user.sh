PASSWORD=$(date +%s | sha256sum | base64 | head -c 32 ; echo)

pveum role add TerraformProv -privs "Datastore.AllocateSpace Datastore.Audit Pool.Allocate Sys.Audit VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.PowerMgmt"
pveum user add terraform-prov@pve --password $PASSWORD
pveum aclmod / -user terraform-prov@pve -role TerraformProv
pveum user token add terraform-prov@pve terraform --privsep=0
