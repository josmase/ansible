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

resource "cloudflare_record" "local" {
  for_each = {
    "*.local"         = "192.168.1.181"
    "media.local"     = "192.168.1.105"
    "proxmox.local"   = "192.168.1.100"
    "storage.local"   = "192.168.1.102"
    "ansible.local"   = "192.168.1.101"
    "*.staging.local" = "192.168.1.182"
  }
  zone_id = var.zone_id
  name    = each.key
  type    = "A"
  value   = each.value
  proxied = false
}

# Proxied CNAME Records
resource "cloudflare_record" "proxied_cnames" {
  for_each = toset(["assistant", "it-tools", "jellyfin", "headscale", "new-new-boplats"])
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
