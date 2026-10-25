locals {
  is_linux   = var.os_type == "Linux"
  is_windows = var.os_type == "Windows"

  default_images = {
    Linux = {
      publisher = "Canonical"
      offer     = "ubuntu-24_04-lts"
      sku       = "server"
      version   = "latest"
    }
    Windows = {
      publisher = "MicrosoftWindowsServer"
      offer     = "WindowsServer"
      sku       = "2025-datacenter-azure-edition"
      version   = "latest"
    }
  }
  image_reference = var.source_image_id != null ? null : coalesce(var.source_image_reference, local.default_images[var.os_type])

  computer_name = coalesce(var.computer_name, var.name)

  identity_type = join(", ", compact([
    var.system_assigned_identity_enabled ? "SystemAssigned" : "",
    length(var.user_assigned_identity_ids) > 0 ? "UserAssigned" : "",
  ]))

  # Key Vault secret names allow only letters, numbers and hyphens.
  safe_name   = replace(var.name, "/[^0-9A-Za-z-]/", "-")
  secret_name = coalesce(var.admin_credentials_secret_name, local.is_linux ? "${local.safe_name}-admin-ssh-key" : "${local.safe_name}-admin-password")

  # The two VM resources have different attribute sets, so a conditional can't
  # return either object; one() over the splat lists picks whichever exists.
  vm_id = one(concat(azurerm_linux_virtual_machine.this[*].id, azurerm_windows_virtual_machine.this[*].id))

  ama_enabled   = var.azure_monitor_agent != null
  entra_enabled = var.entra_id_login != null

  entra_role_assignments = local.entra_enabled ? merge(
    { for k, id in var.entra_id_login.admin_principal_ids : "admin-${k}" => { principal_id = id, role = "Virtual Machine Administrator Login" } },
    { for k, id in var.entra_id_login.user_principal_ids : "user-${k}" => { principal_id = id, role = "Virtual Machine User Login" } },
  ) : {}
}

###############################################################################
# Admin credential: generated, then stored in Key Vault
###############################################################################

resource "tls_private_key" "admin" {
  count = local.is_linux ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "random_password" "admin" {
  count = local.is_windows ? 1 : 0

  length      = 24
  min_lower   = 2
  min_upper   = 2
  min_numeric = 2
  min_special = 2
  # Avoids characters that cause escaping trouble in RDP (Remote Desktop Protocol) clients and scripts.
  override_special = "!#%*()-_=+[]{}:?"
}

resource "azurerm_key_vault_secret" "admin" {
  name            = local.secret_name
  key_vault_id    = var.admin_credentials_key_vault_id
  value           = local.is_linux ? tls_private_key.admin[0].private_key_openssh : random_password.admin[0].result
  content_type    = local.is_linux ? "ssh-private-key (user: ${var.admin_username})" : "password (user: ${var.admin_username})"
  expiration_date = var.admin_credentials_secret_expiration_date
  tags            = var.tags
}

###############################################################################
# Network interface (private only)
###############################################################################

resource "azurerm_network_interface" "this" {
  name                           = "nic-${var.name}"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  accelerated_networking_enabled = var.accelerated_networking_enabled
  ip_forwarding_enabled          = false
  dns_servers                    = var.dns_servers
  tags                           = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = var.private_ip_address == null ? "Dynamic" : "Static"
    private_ip_address            = var.private_ip_address
    primary                       = true
  }

  # Cross-variable checks live here because the NIC is always created and is
  # planned before the VM, so mistakes surface before anything else is built.
  lifecycle {
    precondition {
      condition     = local.is_linux ? contains(["ImageDefault", "AutomaticByPlatform"], var.patch_mode) : contains(["Manual", "AutomaticByOS", "AutomaticByPlatform"], var.patch_mode)
      error_message = local.is_linux ? "Linux patch_mode must be ImageDefault or AutomaticByPlatform." : "Windows patch_mode must be Manual, AutomaticByOS or AutomaticByPlatform."
    }

    precondition {
      condition     = var.reboot_setting == null || var.patch_mode == "AutomaticByPlatform"
      error_message = "reboot_setting can only be set when patch_mode = \"AutomaticByPlatform\"."
    }

    precondition {
      condition     = !var.bypass_platform_safety_checks_on_user_schedule_enabled || var.patch_mode == "AutomaticByPlatform"
      error_message = "bypass_platform_safety_checks_on_user_schedule_enabled needs patch_mode = \"AutomaticByPlatform\"."
    }

    precondition {
      condition     = !var.hotpatching_enabled || (local.is_windows && var.patch_mode == "AutomaticByPlatform")
      error_message = "hotpatching_enabled is Windows only and needs patch_mode = \"AutomaticByPlatform\"."
    }

    precondition {
      condition     = local.is_linux || can(regex("^[A-Za-z0-9-]{1,15}$", local.computer_name))
      error_message = "Windows computer names are limited to 15 letters, numbers or hyphens. Set computer_name, or use a shorter name."
    }

    precondition {
      condition     = local.is_windows || can(regex("^[A-Za-z0-9][A-Za-z0-9.-]{0,63}$", local.computer_name))
      error_message = "Linux hostnames may only contain letters, numbers, '.' and '-'. Set computer_name if name contains '_'."
    }

    precondition {
      condition     = !(var.zone != null && var.availability_set_id != null)
      error_message = "Set either zone or availability_set_id, not both."
    }

    precondition {
      condition     = !local.entra_enabled || var.system_assigned_identity_enabled
      error_message = "entra_id_login needs system_assigned_identity_enabled = true."
    }

    precondition {
      condition = !local.ama_enabled || (
        try(var.azure_monitor_agent.user_assigned_identity_id, null) == null
        ? var.system_assigned_identity_enabled
        : contains(var.user_assigned_identity_ids, var.azure_monitor_agent.user_assigned_identity_id)
      )
      error_message = "azure_monitor_agent needs the system-assigned identity, or its user_assigned_identity_id listed in user_assigned_identity_ids."
    }
  }
}

###############################################################################
# Virtual machine (exactly one of these is created)
###############################################################################

resource "azurerm_linux_virtual_machine" "this" {
  count = local.is_linux ? 1 : 0

  name                         = var.name
  computer_name                = local.computer_name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  size                         = var.size
  zone                         = var.zone
  availability_set_id          = var.availability_set_id
  proximity_placement_group_id = var.proximity_placement_group_id
  network_interface_ids        = [azurerm_network_interface.this.id]
  license_type                 = var.license_type
  tags                         = var.tags

  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.admin[0].public_key_openssh
  }

  source_image_id = var.source_image_id

  dynamic "source_image_reference" {
    for_each = local.image_reference == null ? [] : [local.image_reference]
    content {
      publisher = source_image_reference.value.publisher
      offer     = source_image_reference.value.offer
      sku       = source_image_reference.value.sku
      version   = source_image_reference.value.version
    }
  }

  os_disk {
    name                   = coalesce(var.os_disk.name, "osdisk-${var.name}")
    caching                = var.os_disk.caching
    storage_account_type   = var.os_disk.storage_account_type
    disk_size_gb           = var.os_disk.disk_size_gb
    disk_encryption_set_id = var.os_disk.disk_encryption_set_id
  }

  secure_boot_enabled        = var.secure_boot_enabled
  vtpm_enabled               = var.vtpm_enabled
  encryption_at_host_enabled = var.encryption_at_host_enabled

  provision_vm_agent                                     = true
  allow_extension_operations                             = true
  patch_mode                                             = var.patch_mode
  patch_assessment_mode                                  = var.patch_assessment_mode
  reboot_setting                                         = var.reboot_setting
  bypass_platform_safety_checks_on_user_schedule_enabled = var.bypass_platform_safety_checks_on_user_schedule_enabled

  custom_data = var.custom_data
  user_data   = var.user_data

  dynamic "identity" {
    for_each = local.identity_type == "" ? [] : [1]
    content {
      type         = local.identity_type
      identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
    }
  }

  boot_diagnostics {
    storage_account_uri = var.boot_diagnostics_storage_account_uri
  }
}

resource "azurerm_windows_virtual_machine" "this" {
  count = local.is_windows ? 1 : 0

  name                         = var.name
  computer_name                = local.computer_name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  size                         = var.size
  zone                         = var.zone
  availability_set_id          = var.availability_set_id
  proximity_placement_group_id = var.proximity_placement_group_id
  network_interface_ids        = [azurerm_network_interface.this.id]
  license_type                 = var.license_type
  timezone                     = var.timezone
  tags                         = var.tags

  admin_username = var.admin_username
  admin_password = random_password.admin[0].result

  source_image_id = var.source_image_id

  dynamic "source_image_reference" {
    for_each = local.image_reference == null ? [] : [local.image_reference]
    content {
      publisher = source_image_reference.value.publisher
      offer     = source_image_reference.value.offer
      sku       = source_image_reference.value.sku
      version   = source_image_reference.value.version
    }
  }

  os_disk {
    name                   = coalesce(var.os_disk.name, "osdisk-${var.name}")
    caching                = var.os_disk.caching
    storage_account_type   = var.os_disk.storage_account_type
    disk_size_gb           = var.os_disk.disk_size_gb
    disk_encryption_set_id = var.os_disk.disk_encryption_set_id
  }

  secure_boot_enabled        = var.secure_boot_enabled
  vtpm_enabled               = var.vtpm_enabled
  encryption_at_host_enabled = var.encryption_at_host_enabled

  provision_vm_agent                                     = true
  allow_extension_operations                             = true
  automatic_updates_enabled                              = true
  hotpatching_enabled                                    = var.hotpatching_enabled
  patch_mode                                             = var.patch_mode
  patch_assessment_mode                                  = var.patch_assessment_mode
  reboot_setting                                         = var.reboot_setting
  bypass_platform_safety_checks_on_user_schedule_enabled = var.bypass_platform_safety_checks_on_user_schedule_enabled

  custom_data = var.custom_data
  user_data   = var.user_data

  dynamic "identity" {
    for_each = local.identity_type == "" ? [] : [1]
    content {
      type         = local.identity_type
      identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
    }
  }

  boot_diagnostics {
    storage_account_uri = var.boot_diagnostics_storage_account_uri
  }
}

###############################################################################
# Data disks
###############################################################################

resource "azurerm_managed_disk" "data" {
  for_each = var.data_disks

  name                = coalesce(each.value.name, "disk-${var.name}-lun${each.value.lun}")
  location            = var.location
  resource_group_name = var.resource_group_name
  # ZRS disks span zones and reject a zone value; a zonal VM can still attach them.
  zone                          = endswith(each.value.storage_account_type, "_ZRS") ? null : var.zone
  storage_account_type          = each.value.storage_account_type
  create_option                 = "Empty"
  disk_size_gb                  = each.value.disk_size_gb
  disk_encryption_set_id        = each.value.disk_encryption_set_id
  network_access_policy         = "DenyAll"
  public_network_access_enabled = false
  tags                          = var.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  for_each = var.data_disks

  managed_disk_id           = azurerm_managed_disk.data[each.key].id
  virtual_machine_id        = local.vm_id
  lun                       = each.value.lun
  caching                   = each.value.caching
  write_accelerator_enabled = each.value.write_accelerator_enabled
}

###############################################################################
# Microsoft Entra ID login
###############################################################################

resource "azurerm_virtual_machine_extension" "entra_login" {
  count = local.entra_enabled ? 1 : 0

  name                       = local.is_linux ? "AADSSHLoginForLinux" : "AADLoginForWindows"
  virtual_machine_id         = local.vm_id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = local.is_linux ? "AADSSHLoginForLinux" : "AADLoginForWindows"
  type_handler_version       = var.entra_id_login.type_handler_version
  auto_upgrade_minor_version = true
  tags                       = var.tags

  # Let data disks attach first so the extension doesn't race a disk operation.
  depends_on = [azurerm_virtual_machine_data_disk_attachment.data]
}

resource "azurerm_role_assignment" "entra_login" {
  for_each = local.entra_role_assignments

  scope                = local.vm_id
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
}

###############################################################################
# Azure Monitor Agent and DCR (Data Collection Rule) associations
###############################################################################

resource "azurerm_virtual_machine_extension" "azure_monitor_agent" {
  count = local.ama_enabled ? 1 : 0

  name                       = local.is_linux ? "AzureMonitorLinuxAgent" : "AzureMonitorWindowsAgent"
  virtual_machine_id         = local.vm_id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = local.is_linux ? "AzureMonitorLinuxAgent" : "AzureMonitorWindowsAgent"
  type_handler_version       = var.azure_monitor_agent.type_handler_version
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = var.tags

  settings = var.azure_monitor_agent.user_assigned_identity_id == null ? null : jsonencode({
    authentication = {
      managedIdentity = {
        "identifier-name"  = "mi_res_id"
        "identifier-value" = var.azure_monitor_agent.user_assigned_identity_id
      }
    }
  })

  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.data,
    azurerm_virtual_machine_extension.entra_login,
  ]
}

resource "azurerm_monitor_data_collection_rule_association" "this" {
  for_each = local.ama_enabled ? var.azure_monitor_agent.data_collection_rule_ids : {}

  name                    = "dcra-${var.name}-${each.key}"
  target_resource_id      = local.vm_id
  data_collection_rule_id = each.value

  depends_on = [azurerm_virtual_machine_extension.azure_monitor_agent]
}

###############################################################################
# Azure Backup
###############################################################################

resource "azurerm_backup_protected_vm" "this" {
  count = var.backup == null ? 0 : 1

  resource_group_name = var.backup.recovery_vault_resource_group_name
  recovery_vault_name = var.backup.recovery_vault_name
  source_vm_id        = local.vm_id
  backup_policy_id    = var.backup.backup_policy_id

  # Back up the data disks too.
  depends_on = [azurerm_virtual_machine_data_disk_attachment.data]
}
