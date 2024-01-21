terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
  }
}

provider "cloudflare" {
  api_token = var.api_token
}

resource "cloudflare_record" "hejsan" {
  zone_id = var.zone_id
  name    = var.domain
  type    = "A"
  value   = var.external_ip
  proxied = true
}

resource "cloudflare_record" "local" {
  for_each = {
    "*.local"         = "192.168.0.181"
    "media.local"     = "192.168.0.105"
    "proxmox.local"   = "192.168.0.100"
    "storage.local"   = "192.168.0.102"
    "ansible.local"   = "192.168.0.101"
    "*.staging.local" = "192.168.0.182"
  }
  zone_id = var.zone_id
  name    = each.key
  type    = "A"
  value   = each.value
  proxied = false
}

# Proxied CNAME Records
resource "cloudflare_record" "proxied_cnames" {
  for_each = toset(["api", "assistant", "budget", "dohi", "emby", "fest", "it-tools", "jellyfin", "ombi", "plex", "serble", "wireguard"])
  zone_id  = var.zone_id
  name     = each.key
  type     = "CNAME"
  value    = "hejsan.xyz"
  proxied  = true
}

# Non-Proxied CNAME Record
resource "cloudflare_record" "non_proxied_cname" {
  zone_id = var.zone_id
  name    = "wireguard"
  type    = "CNAME"
  value   = "hejsan.xyz"
  proxied = false
}
