locals {
  subnet = "192.168.0"

  base_machine = {
    target_node      = var.proxmox_node
    qemu_os          = "other"
    os_type          = "cloud-init"
    full_clone       = true
    template         = var.ubuntu_template_20G
    cores            = 2
    socket           = 1
    memory           = 2048
    gateway          = "${local.subnet}.1"
    ssh_user         = "ubuntu"
    public_ssh_key   = var.public_ssh_key
    cloud_init_pass  = var.cloud_init_pass
    automatic_reboot = true

    network_model       = "virtio"
    network_bridge_type = "vmbr0"
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
    memory      = 4096
    template    = var.ubuntu_template_300G

  })

  machine_map = {
    machines = merge(
      { for machine_id in [201, 202, 203] : machine_id => merge(local.kubernetes_master, {
        id         = machine_id
        name       = "kubernetes-master-${machine_id}"
        ip_address = "${local.subnet}.${machine_id}"
      }) },
      { for machine_id in [204, 205, 206] : machine_id => merge(local.kubernetes_node, {
        id         = machine_id
        name       = "kubernetes-node-${machine_id}"
        ip_address = "${local.subnet}.${machine_id}"
      }) },
      { 105 = merge(local.base_machine, {
        id          = "105"
        name        = "media-server"
        cores       = 10
        template    = var.ubuntu_template_300G
        memory      = 9216
        description = "Main media server for stuff that is not yet running in kubernetes"
        ip_address  = "${local.subnet}.105"
      }) },
      { 110 = merge(local.base_machine, {
        id          = "110"
        name        = "utils"
        description = "For running utils that should always be running, for example vpn. So that all other VMs can safely be restarted without risk of being locked out."
        ip_address  = "${local.subnet}.110"
      }) }
    )
  }

  machines = lookup(local.machine_map, "machines", {})
}
