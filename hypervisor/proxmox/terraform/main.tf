terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

# TLS is verified against a real CA: insecure is never set to true. Give Proxmox a certificate
# from the lab's own PKI (see ../README.md, "Trusting the Proxmox certificate"), or trust
# Proxmox's own CA on the machine that runs `terraform apply`. Either way the default
# (insecure = false) then just works without disabling verification.
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = var.proxmox_api_token
  insecure  = false
}
