variable "proxmox_api_url" {
  description = "Proxmox API endpoint, e.g. https://pve.lab.internal:8006/api2/json"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token in 'user@realm!token-id=secret' form. Created by ../host/create-terraform-user.sh"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Target Proxmox node name"
  type        = string
  default     = "pve"
}

variable "storage_pool" {
  description = "Datastore ID for VM and container disks"
  type        = string
  default     = "local-lvm"
}

variable "backup_storage_pool" {
  description = "Datastore ID for the PBS backup datastore. Point this at a separate virtual disk so a backup does not share a failure with the thing it protects"
  type        = string
  default     = "local-lvm"
}

variable "image_datastore" {
  description = "Datastore ID that holds the cloud image and the container template. Needs the 'import' and 'vztmpl' content types (../host/create-terraform-user.sh enables them)"
  type        = string
  default     = "local"
}

variable "lan_bridge" {
  description = "Linux bridge every lab guest attaches to (see hypervisor/networks/README.md)"
  type        = string
  default     = "vmbr-lan"
}

variable "lan_gateway" {
  description = "The LAN default gateway: pfSense"
  type        = string
  default     = "10.10.10.1"
}

variable "ssh_public_key" {
  description = "Public key installed for the labadmin user on every guest. Password login is disabled, matching the Ansible common role"
  type        = string
}

variable "ubuntu_cloud_image_url" {
  description = "Ubuntu 24.04 Server cloud image. Proxmox downloads it itself, over HTTPS with verification on"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "lxc_template_url" {
  description = "Debian container template for PBS. Versions change: list current ones on the Proxmox host with `pveam update && pveam available --section system`"
  type        = string
  default     = "http://download.proxmox.com/images/system/debian-12-standard_12.7-1_amd64.tar.zst"
}

variable "pbs_datastore_gb" {
  description = "Size of the PBS backup datastore disk"
  type        = number
  default     = 40
}
