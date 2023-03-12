module "virtual_machine" {
  source = "./modules/vm"
  virtual_machines = local.machines
  proxmox_host = var.proxmox_host
  proxmox_id = var.proxmox_id
  proxmox_secret = var.proxmox_secret
}