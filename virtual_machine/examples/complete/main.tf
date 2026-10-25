# One module, two operating systems: a Linux and a Windows VM (Virtual Machine)
# from the same module call using for_each, each with data disks, Azure Backup,
# the Azure Monitor Agent sending to Log Analytics, and Microsoft Entra ID login.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.77.0, < 5.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "vm_admins_group_object_id" {
  description = "Object ID of the Entra ID group allowed to sign in to the VMs as administrators."
  type        = string
}

variable "vm_users_group_object_id" {
  description = "Object ID of the Entra ID group allowed to sign in to the VMs as standard users."
  type        = string
}

data "azurerm_client_config" "current" {}

locals {
  location = "uksouth"

  vms = {
    linux = {
      os_type       = "Linux"
      name          = "vm-app-prod-lnx01"
      computer_name = null # defaults to name
      zone          = "1"
      data_disks    = { data = { lun = 0, disk_size_gb = 128 } }
    }
    windows = {
      os_type = "Windows"
      name    = "vm-app-prod-win01"
      # Windows hostnames are limited to 15 characters.
      computer_name = "appprodwin01"
      zone          = "2"
      data_disks = {
        data = { lun = 0, disk_size_gb = 256 }
        logs = { lun = 1, disk_size_gb = 64, caching = "None", storage_account_type = "StandardSSD_ZRS" }
      }
    }
  }
}

resource "azurerm_resource_group" "example" {
  name     = "rg-vm-complete-example"
  location = local.location
}

###############################################################################
# Network
###############################################################################

resource "azurerm_virtual_network" "example" {
  name                = "vnet-vm-complete-example"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  address_space       = ["10.40.0.0/16"]
}

resource "azurerm_subnet" "vms" {
  name                 = "snet-vms"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.40.1.0/24"]
}

###############################################################################
# Key Vault for generated credentials
###############################################################################

resource "azurerm_key_vault" "example" {
  name                       = "kv-vmcomplete-ex-001"
  location                   = azurerm_resource_group.example.location
  resource_group_name        = azurerm_resource_group.example.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
}

resource "azurerm_role_assignment" "deployer_secrets" {
  scope                = azurerm_key_vault.example.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

###############################################################################
# Monitoring: Log Analytics and one DCR (Data Collection Rule) for both OSes
###############################################################################

resource "azurerm_log_analytics_workspace" "example" {
  name                = "law-vm-example"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_data_collection_rule" "vms" {
  name                = "dcr-vm-baseline"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  destinations {
    log_analytics {
      name                  = "law"
      workspace_resource_id = azurerm_log_analytics_workspace.example.id
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Syslog", "Microsoft-Event"]
    destinations = ["law"]
  }

  data_sources {
    performance_counter {
      name                          = "perf"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Processor(_Total)\\% Processor Time",
        "\\Memory\\Available Bytes",
        "\\LogicalDisk(_Total)\\% Free Space",
      ]
    }

    syslog {
      name           = "syslog"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["auth", "authpriv", "daemon", "kern", "syslog"]
      log_levels     = ["Warning", "Error", "Critical", "Alert", "Emergency"]
    }

    windows_event_log {
      name    = "events"
      streams = ["Microsoft-Event"]
      x_path_queries = [
        "System!*[System[(Level=1 or Level=2 or Level=3)]]",
        "Application!*[System[(Level=1 or Level=2 or Level=3)]]",
      ]
    }
  }
}

###############################################################################
# Backup: Trusted Launch VMs need an Enhanced (V2) policy
###############################################################################

resource "azurerm_recovery_services_vault" "example" {
  name                = "rsv-vm-example"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  sku                 = "Standard"
  storage_mode_type   = "ZoneRedundant"
}

resource "azurerm_backup_policy_vm" "daily" {
  name                           = "vm-daily-30d"
  resource_group_name            = azurerm_resource_group.example.name
  recovery_vault_name            = azurerm_recovery_services_vault.example.name
  policy_type                    = "V2"
  timezone                       = "GMT Standard Time"
  instant_restore_retention_days = 7

  backup {
    frequency = "Daily"
    time      = "01:00"
  }

  retention_daily {
    count = 30
  }
}

###############################################################################
# The module, once per OS
###############################################################################

module "vm" {
  source   = "../.."
  for_each = local.vms

  os_type             = each.value.os_type
  name                = each.value.name
  computer_name       = each.value.computer_name
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  zone                = each.value.zone
  size                = "Standard_D4s_v5"
  subnet_id           = azurerm_subnet.vms.id

  admin_credentials_key_vault_id = azurerm_key_vault.example.id

  data_disks = each.value.data_disks

  backup = {
    recovery_vault_name                = azurerm_recovery_services_vault.example.name
    recovery_vault_resource_group_name = azurerm_resource_group.example.name
    backup_policy_id                   = azurerm_backup_policy_vm.daily.id
  }

  azure_monitor_agent = {
    data_collection_rule_ids = { baseline = azurerm_monitor_data_collection_rule.vms.id }
  }

  entra_id_login = {
    admin_principal_ids = { vm_admins = var.vm_admins_group_object_id }
    user_principal_ids  = { vm_users = var.vm_users_group_object_id }
  }

  tags = {
    environment = "prod"
  }

  depends_on = [azurerm_role_assignment.deployer_secrets]
}

output "vms" {
  value = {
    for k, vm in module.vm : k => {
      id                 = vm.id
      private_ip_address = vm.private_ip_address
      credential_secret  = vm.admin_credentials_secret_id
    }
  }
}
