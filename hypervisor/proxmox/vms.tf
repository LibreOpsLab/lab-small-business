# name -> vcpu/ram/disk/ip/dns — mirrors the VM table in
# hypervisor/vmware-linux/scripts/create-vms.sh, minus win-client01 (not automated on Proxmox —
# see hypervisor/README.md and hypervisor/vms/windows-client.md for why) and minus
# pfsense01/linux-client01 (built by hand on every platform, not just this one).
locals {
  linux_vms = {
    samba-dc01  = { vcpu = 2, ram_mb = 4096, disk_gb = 40, ip = "10.10.10.10", dns = "127.0.0.1" }
    docker01    = { vcpu = 4, ram_mb = 8192, disk_gb = 80, ip = "10.10.10.20", dns = "10.10.10.10" }
    authentik01 = { vcpu = 2, ram_mb = 4096, disk_gb = 40, ip = "10.10.10.30", dns = "10.10.10.10" }
  }
}

# Imported once, then cloned into each VM's disk below via import_from. Download the image
# yourself first (see proxmox/README.md) — Terraform only imports the local file, it doesn't
# fetch it from the internet.
resource "proxmox_virtual_environment_file" "ubuntu_cloud_image" {
  content_type = "import"
  datastore_id = var.image_datastore
  node_name    = var.proxmox_node

  source_file {
    path = var.cloud_image_path
  }
}

# Each VM's cloud-init user-data, uploaded as a snippet. Built from
# hypervisor/vms/seeds/<name>/proxmox-user-data (the real, gitignored, filled-in copy of
# proxmox-user-data.example) — Terraform only uploads the file, it doesn't fill in placeholders;
# fill them in by hand before running `terraform apply` (proxmox/README.md covers this).
resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  for_each     = local.linux_vms
  content_type = "snippets"
  datastore_id = var.image_datastore
  node_name    = var.proxmox_node

  source_file {
    path = "${path.module}/../vms/seeds/${each.key}/proxmox-user-data"
  }
}

resource "proxmox_virtual_environment_vm" "linux" {
  for_each  = local.linux_vms
  name      = each.key
  node_name = var.proxmox_node

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.vcpu
  }

  memory {
    dedicated = each.value.ram_mb
  }

  disk {
    datastore_id = var.storage_pool
    interface    = "scsi0"
    import_from  = proxmox_virtual_environment_file.ubuntu_cloud_image.id
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

  initialization {
    datastore_id      = var.storage_pool
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data[each.key].id

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "10.10.10.1"
      }
    }

    dns {
      servers = [each.value.dns]
    }
  }
}
