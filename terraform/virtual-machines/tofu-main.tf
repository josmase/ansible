resource "proxmox_download_file" "ubuntu_cloud_image" {
  node_name          = var.proxmox_node
  datastore_id       = var.image_storage
  content_type       = "import"
  file_name          = "noble-server-cloudimg-amd64.qcow2"
  url                = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  checksum           = var.ubuntu_image_sha256
  checksum_algorithm = "sha256"
  overwrite          = false
}

resource "proxmox_virtual_environment_vm" "worker" {
  for_each  = var.workers
  node_name = var.proxmox_node
  vm_id     = tonumber(each.key)
  name      = each.value.name
  memory { dedicated = each.value.memory }
  cpu {
    cores = each.value.cores
    type  = "host"
  }
  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["scsi0"]
  operating_system { type = "l26" }
  disk {
    interface    = "scsi0"
    datastore_id = var.storage
    import_from  = proxmox_download_file.ubuntu_cloud_image.id
    size         = 250
    file_format  = "raw"
    backup       = true
  }
  disk {
    interface    = "scsi1"
    datastore_id = var.storage
    size         = 750
    file_format  = "raw"
    backup       = true
    serial       = "linstor-data-${each.key}"
  }
  initialization {
    datastore_id = var.storage
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "192.168.1.1"
      }
    }
    dns { servers = ["1.1.1.1", "1.0.0.1", "192.168.1.1"] }
    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
  }
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }
  serial_device { device = "socket" }
  on_boot = false
  lifecycle { prevent_destroy = true }
}
