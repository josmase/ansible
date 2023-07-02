resource "proxmox_vm_qemu" "virtual_machines" {
  for_each         = var.virtual_machines
  vmid             = each.value.id
  name             = each.value.name
  qemu_os          = each.value.qemu_os
  desc             = each.value.description
  target_node      = each.value.target_node
  os_type          = each.value.os_type
  full_clone       = each.value.full_clone
  clone            = each.value.template
  memory           = each.value.memory
  sockets          = each.value.socket
  cores            = each.value.cores
  ssh_user         = each.value.ssh_user
  sshkeys          = each.value.public_ssh_key
  ciuser           = each.value.ssh_user
  ipconfig0        = "ip=${each.value.ip_address}/24,gw=${each.value.gateway}"
  cipassword       = each.value.cloud_init_pass
  automatic_reboot = each.value.automatic_reboot
  nameserver       = each.value.dns_servers
  scsihw           = "virtio-scsi-pci"

  network {
    bridge   = each.value.network_bridge_type
    model    = each.value.network_model
    mtu      = 0
    queues   = 0
    rate     = 0
    firewall = each.value.network_firewall
  }

  lifecycle {
    ignore_changes = [
      network,
    ]
  }
}
