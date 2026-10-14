# Sizes follow the table in scenarios/2-nested-proxmox/README.md. The DC, the Docker host and
# Authentik are VMs, not LXC: no privileged containers, and no Docker inside an LXC.
#
# Not created here: pfSense, the Windows machines and the scanner. pfSense has no unattended
# installer (pfsense/README.md), Windows is a native VMware VM in scenario 2, and scenario 3
# builds the Windows machines by hand like every other platform does.
locals {
  linux_vms = {
    samba-dc01  = { vcpu = 2, ram_mb = 2048, disk_gb = 25, ip = "10.10.10.10", dns = "127.0.0.1" }
    docker01    = { vcpu = 2, ram_mb = 6144, disk_gb = 60, ip = "10.10.10.20", dns = "10.10.10.10" }
    authentik01 = { vcpu = 2, ram_mb = 2560, disk_gb = 25, ip = "10.10.10.30", dns = "10.10.10.10" }
  }
}

# Proxmox fetches the image itself, so there is no manual download step. The ".qcow2" name is
# required by the "import" content type; Ubuntu's .img file is a qcow2 image.
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "import"
  datastore_id = var.image_datastore
  node_name    = var.proxmox_node
  url          = var.ubuntu_cloud_image_url
  file_name    = "noble-server-cloudimg-amd64.qcow2"
}

resource "proxmox_virtual_environment_vm" "linux" {
  for_each  = local.linux_vms
  name      = each.key
  node_name = var.proxmox_node
  tags      = ["lab", "terraform"]

  cpu {
    cores = each.value.vcpu
  }

  memory {
    dedicated = each.value.ram_mb
  }

  disk {
    datastore_id = var.storage_pool
    interface    = "scsi0"
    import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    size         = each.value.disk_gb
    file_format  = "raw"
  }

  network_device {
    bridge = var.lan_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  # Native Proxmox cloud-init: no snippet file, so the API token is enough and no SSH access to
  # the Proxmox host is needed. The guest agent is off because the cloud image does not ship it
  # and the addresses are static anyway.
  agent {
    enabled = false
  }

  initialization {
    datastore_id = var.storage_pool

    user_account {
      username = "labadmin"
      keys     = [var.ssh_public_key]
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.lan_gateway
      }
    }

    dns {
      domain  = "lab.internal"
      servers = [each.value.dns]
    }
  }
}
