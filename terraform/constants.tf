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
    machines = {
      master-211 = merge(local.kubernetes_master, {
        name       = "master-211"
        ip_address = "${local.subnet}.211"
      })
      master-212 = merge(local.kubernetes_master, {
        name       = "master-212"
        ip_address = "${local.subnet}.212"
      })
      master-213 = merge(local.kubernetes_master, {
        name       = "master-213"
        ip_address = "${local.subnet}.213"
      })
      node-214 = merge(local.kubernetes_node, {
        name       = "node-214"
        ip_address = "${local.subnet}.214"
      })
      node-215 = merge(local.kubernetes_node, {
        name       = "node-215"
        ip_address = "${local.subnet}.215"
      })
      node-216 = merge(local.kubernetes_node, {
        name       = "node-216"
        ip_address = "${local.subnet}.216"
      })
    }
  }

  machines = lookup(local.machine_map, "machines", {})
}
