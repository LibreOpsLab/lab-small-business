# Small single-purpose services run as unprivileged LXC containers: a few hundred MB each
# instead of a whole VM. Anything that needs Docker or special privileges is a VM (vms.tf).

resource "proxmox_virtual_environment_download_file" "debian_lxc_template" {
  content_type = "vztmpl"
  datastore_id = var.image_datastore
  node_name    = var.proxmox_node
  url          = var.lxc_template_url
}

# Proxmox Backup Server. The container is created here; PBS itself is installed by
# ../guests/pbs-install.sh (see ../README.md), because Terraform creates machines, not the
# software inside them.
resource "proxmox_virtual_environment_container" "pbs" {
  node_name    = var.proxmox_node
  vm_id        = 150
  description  = "Proxmox Backup Server for the lab (managed by Terraform)"
  tags         = ["lab", "terraform"]
  unprivileged = true
  started      = true

  cpu {
    cores = 1
  }

  memory {
    dedicated = 1536
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.debian_lxc_template.id
    type             = "debian"
  }

  disk {
    datastore_id = var.storage_pool
    size         = 8
  }

  # The backup datastore is a separate volume, on a separate storage pool where the host has one.
  mount_point {
    volume = var.backup_storage_pool
    size   = "${var.pbs_datastore_gb}G"
    path   = "/mnt/datastore/lab"
  }

  network_interface {
    name   = "eth0"
    bridge = var.lan_bridge
  }

  initialization {
    hostname = "pbs01"

    dns {
      domain  = "lab.internal"
      servers = ["10.10.10.10"]
    }

    ip_config {
      ipv4 {
        address = "10.10.10.50/24"
        gateway = var.lan_gateway
      }
    }

    user_account {
      keys = [var.ssh_public_key]
    }
  }
}
