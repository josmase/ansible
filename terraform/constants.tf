locals {
  subnet = "192.168.0"

  base_machine = {
    target_node         = var.proxmox_node
    qemu_os             = "other"
    os_type             = "cloud-init"
    agent               = 1
    full_clone          = true
    template            = var.ubuntu_template
    cores               = 2
    socket              = 1
    memory              = 2048
    storage             = "20G"
    gateway             = "${local.subnet}.1"
    ssh_user            = "ubuntu"
    public_ssh_key      = var.public_ssh_key
    disk_type           = "virtio"
    storage_dev         = var.proxmox_storage
    network_bridge_type = "vmbr0"
    network_model       = "virtio"
    cloud_init_pass     = "somepassword"
    automatic_reboot    = true
    network_firewall    = false
    dns_servers         = "1.1.1.1 1.0.0.1 192.168.0.1 127.0.0.1"
  }

  kubernetes_master = merge(local.base_machine, {
    description = "Kubernetes master"
    cores       = 2
  })

  kubernetes_node = merge(local.base_machine, {
    description = "Kubernetes node"
    cores       = 2
  })

  machine_map = {
    machines = merge(
      { for machine_id in [201, 202, 203] : machine_id => merge(local.kubernetes_master, {
        id         = machine_id
        name       = "master-${machine_id}"
        ip_address = "${local.subnet}.${machine_id}"
      }) },
      { for machine_id in [204, 205, 206] : machine_id => merge(local.kubernetes_node, {
        id         = machine_id
        name       = "node-${machine_id}"
        ip_address = "${local.subnet}.${machine_id}"
      }) }
    )
  }

  machines = lookup(local.machine_map, "machines", {})
}
