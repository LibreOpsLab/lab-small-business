variable "proxmox_api_url" {
  description = "Proxmox API endpoint, e.g. https://pve.lab.internal:8006/api2/json"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token in 'user@realm!token-id=uuid' form"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Target Proxmox node name"
  type        = string
  default     = "pve"
}

variable "storage_pool" {
  description = "Datastore ID for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "image_datastore" {
  description = "Datastore ID for the imported Ubuntu cloud image and cloud-init snippet files (must have both the 'Disk image' and 'Snippets' content types enabled — see proxmox/README.md)"
  type        = string
  default     = "local"
}

variable "lan_bridge" {
  description = "Linux bridge every automatable lab VM's NIC attaches to (see hypervisor/networks/README.md)"
  type        = string
  default     = "vmbr-lan"
}

variable "cloud_image_path" {
  description = "Local path to the downloaded Ubuntu 24.04 Server cloud image (see proxmox/README.md's prerequisites)"
  type        = string
  default     = "~/isos/noble-server-cloudimg-amd64.img"
}
