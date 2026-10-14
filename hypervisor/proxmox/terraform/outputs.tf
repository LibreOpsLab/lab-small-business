output "linux_vm_addresses" {
  description = "Static address of each Linux VM"
  value       = { for name, vm in local.linux_vms : name => vm.ip }
}

output "pbs_address" {
  description = "Where the PBS web interface will answer (port 8007) once ../guests/pbs-install.sh has run"
  value       = "https://10.10.10.50:8007"
}
