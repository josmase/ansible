if [[ -z "${1}" || -z "${2}" ]]; then
    echo "Usage: $0 <user> <password>"
    exit 1
fi

PM_USER="${1}"
PM_PASS="${2}"
PM_ROLE="TerraformProv"

pveum role delete $PM_ROLE
pveum user delete $PM_USER

pveum role add $PM_ROLE -privs "Datastore.AllocateSpace Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.Monitor VM.PowerMgmt SDN.Use"
pveum user add $PM_USER --password $PM_PASS
pveum aclmod / -user $PM_USER -role $PM_ROLE
