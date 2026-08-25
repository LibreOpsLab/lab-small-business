terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

# TLS is verified against a real CA — insecure is never set to true. Issue Proxmox's web
# certificate from the lab's own PKI (see docs/PKI.md) and install that CA in the trust store of
# whatever machine runs `terraform apply`, or trust Proxmox's self-signed cert the same way;
# either way, the default (insecure = false) then just works without disabling verification.
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = var.proxmox_api_token
  insecure  = false
}
