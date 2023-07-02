variable "proxmox_host" {
  type = string
}

variable "proxmox_id" {
  description = "Token id for the proxmox user"
  type        = string
  sensitive   = true
}

variable "proxmox_secret" {
  description = "Token secret for the proxmox user"
  type        = string
  sensitive   = true
}

variable "virtual_machines" {
  type = map(object({
    id                  = string
    name                = string
    qemu_os             = string
    description         = string
    target_node         = string
    os_type             = string
    full_clone          = string
    template            = string
    memory              = number
    socket              = number
    cores               = number
    ssh_user            = string
    public_ssh_key      = string
    ssh_user            = string
    ip_address          = string
    gateway             = string
    cloud_init_pass     = string
    automatic_reboot    = bool
    dns_servers         = string
    storage_dev         = string
    disk_type           = string
    storage             = string
    network_bridge_type = string
    network_model       = string
    network_firewall    = bool

  }))
  default     = {}
  description = "Identifies the object of virtual machines."
}
