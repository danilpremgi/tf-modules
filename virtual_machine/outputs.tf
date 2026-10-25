output "id" {
  description = "Resource ID of the VM (Virtual Machine)."
  value       = local.vm_id
}

output "name" {
  description = "Name of the VM."
  value       = var.name
}

output "os_type" {
  description = "Linux or Windows."
  value       = var.os_type
}

output "computer_name" {
  description = "Hostname inside the OS (Operating System)."
  value       = local.computer_name
}

output "private_ip_address" {
  description = "Private IP (Internet Protocol) address of the primary NIC (Network Interface Card)."
  value       = azurerm_network_interface.this.private_ip_address
}

output "network_interface_id" {
  description = "ID of the NIC."
  value       = azurerm_network_interface.this.id
}

output "identity_principal_id" {
  description = "Principal ID of the system-assigned identity, or null. Use it to grant the VM access to other resources."
  value = one(concat(
    [for vm in azurerm_linux_virtual_machine.this : try(vm.identity[0].principal_id, null)],
    [for vm in azurerm_windows_virtual_machine.this : try(vm.identity[0].principal_id, null)],
  ))
}

output "admin_username" {
  description = "Local administrator username."
  value       = var.admin_username
}

output "admin_credentials_secret_id" {
  description = "Version-less Key Vault secret ID holding the SSH (Secure Shell) private key (Linux) or password (Windows)."
  value       = azurerm_key_vault_secret.admin.versionless_id
}

output "ssh_public_key" {
  description = "Linux only: the generated SSH public key in OpenSSH format. null for Windows."
  value       = local.is_linux ? tls_private_key.admin[0].public_key_openssh : null
}

output "data_disks" {
  description = "Data disks keyed as in var.data_disks."
  value = {
    for k, d in azurerm_managed_disk.data : k => {
      id  = d.id
      lun = var.data_disks[k].lun
    }
  }
}
