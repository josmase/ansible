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
  type = map(object({ ip = string, name = string, memory = number, cores = number }))
  default = {
    "204" = { ip = "192.168.1.204", name = "kubernetes-node-204", memory = 15360, cores = 6 }
    "205" = { ip = "192.168.1.205", name = "kubernetes-node-205", memory = 15360, cores = 6 }
    "206" = { ip = "192.168.1.206", name = "kubernetes-node-206", memory = 15360, cores = 6 }
  }
}
