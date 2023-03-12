locals {
  subnet       = "192.168.0"

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
    storage             = "10G"
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
    cores       = 1
    storage     = "20G"
  })

  kubernetes_node = merge(local.base_machine, {
    description = "Kubernetes node"
    cores       = 1
    storage     = "20G"
  })

  machine_map = {
    machines = {
      master_1 = merge(local.kubernetes_master, {
        name       = "master_1"
        ip_address = "${local.subnet}.211"
      })
      master_2 = merge(local.kubernetes_master, {
        name       = "master_2"
        ip_address = "${local.subnet}.212"
      })
      master_3 = merge(local.kubernetes_master, {
        name       = "master_3"
        ip_address = "${local.subnet}.213"
      })
      node_1 = merge(local.kubernetes_node, {
        name       = "node_1"
        ip_address = "${local.subnet}.214"
      })
      node_2 = merge(local.kubernetes_node, {
        name       = "node_1"
        ip_address = "${local.subnet}.215"
      })
      node_3 = merge(local.kubernetes_node, {
        name       = "node_1"
        ip_address = "${local.subnet}.216"
      })
    }
  }

  machines = lookup(local.machine_map, "machines", {})
}
