variable "proxmox_endpoint" { type = string }
variable "proxmox_username" {
  type      = string
  sensitive = true
}
variable "proxmox_password" {
  type      = string
  sensitive = true
}
variable "ubuntu_image_sha256" { type = string }
variable "proxmox_node" {
  type    = string
  default = "server"
}
variable "storage" {
  type    = string
  default = "Kubernetes"
}
variable "image_storage" {
  type    = string
  default = "local"
}
variable "ssh_public_key" { type = string }

variable "workers" {
  type = map(object({ ip = string, name = string, memory = number, cores = number, started = bool, expansion_disk_gib = number }))
  default = {
    "204" = { ip = "192.168.1.204", name = "kubernetes-node-204", memory = 3072, cores = 6, started = false, expansion_disk_gib = 1 }
    "205" = { ip = "192.168.1.205", name = "kubernetes-node-205", memory = 3072, cores = 6, started = false, expansion_disk_gib = 96 }
    "206" = { ip = "192.168.1.206", name = "kubernetes-node-206", memory = 3072, cores = 6, started = false, expansion_disk_gib = 160 }
  }
  validation {
    condition = (
      contains(keys(var.workers), "204") && contains(keys(var.workers), "205") && contains(keys(var.workers), "206") &&
      var.workers["204"].expansion_disk_gib == 1 &&
      var.workers["205"].expansion_disk_gib == 96 &&
      var.workers["206"].expansion_disk_gib == 160
    )
    error_message = "Keep the attached LINSTOR expansion disks at their declared sizes; do not remove or shrink them."
  }
}

variable "masters" {
  type = map(object({ ip = string, name = string, memory = number, cores = number, started = bool }))
  default = {
    "201" = { ip = "192.168.1.201", name = "kubernetes-master-201", memory = 19456, cores = 6, started = true }
    "202" = { ip = "192.168.1.202", name = "kubernetes-master-202", memory = 19456, cores = 6, started = true }
    "203" = { ip = "192.168.1.203", name = "kubernetes-master-203", memory = 19456, cores = 6, started = true }
  }
}

variable "media_vm" {
  type    = object({ ip = string, name = string, memory = number, cores = number })
  default = { ip = "192.168.1.105", name = "media", memory = 4096, cores = 5 }
}
