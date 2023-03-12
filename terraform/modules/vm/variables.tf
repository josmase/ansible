variable "proxmox_host" {
    type=string
}

variable "proxmox_id" {
  description = "Token id for the proxmox user"
  type        = string
  sensitive = true
}

variable "proxmox_secret" {
  description = "Token secret for the proxmox user"
  type        = string
  sensitive = true
}

variable "virtual_machines" {
  type        = map
  default     = {}
  description = "Identifies the object of virtual machines."
}
