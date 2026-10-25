# Full-featured call: CMK (Customer-Managed Keys) encryption, private endpoints
# with private DNS (Domain Name System) zones, a restricted public firewall,
# containers, shares, queues, tables and diagnostic settings.

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
  features {
    storage {
      data_plane_available = false
    }
  }
  storage_use_azuread = true
}

data "azurerm_client_config" "current" {}

locals {
  location = "uksouth"
  # One private endpoint (and DNS zone) per storage service.
  storage_services = ["blob", "file", "queue", "table"]
}

resource "azurerm_resource_group" "example" {
  name     = "rg-storage-complete-example"
  location = local.location
}

###############################################################################
# Networking: VNet (Virtual Network), subnet and private DNS zones
###############################################################################

resource "azurerm_virtual_network" "example" {
  name                = "vnet-storage-example"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  address_space       = ["10.20.0.0/16"]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_private_dns_zone" "storage" {
  for_each = toset(local.storage_services)

  name                = "privatelink.${each.key}.core.windows.net"
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage" {
  for_each = azurerm_private_dns_zone.storage

  name                  = "link-${each.key}"
  resource_group_name   = azurerm_resource_group.example.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.example.id
}

###############################################################################
# CMK: user-assigned identity, Key Vault and key
###############################################################################

resource "azurerm_user_assigned_identity" "storage" {
  name                = "id-storage-cmk"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_key_vault" "example" {
  name                       = "kv-stcmk-example-001"
  location                   = azurerm_resource_group.example.location
  resource_group_name        = azurerm_resource_group.example.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true # required for storage CMK
  soft_delete_retention_days = 7
}

# Lets whoever runs Terraform create the key.
resource "azurerm_role_assignment" "deployer_crypto_officer" {
  scope                = azurerm_key_vault.example.id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Lets the storage account's identity wrap and unwrap with the key.
resource "azurerm_role_assignment" "storage_crypto_user" {
  scope                = azurerm_key_vault.example.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.storage.principal_id
}

resource "azurerm_key_vault_key" "storage" {
  name         = "storage-cmk"
  key_vault_id = azurerm_key_vault.example.id
  key_type     = "RSA"
  key_size     = 3072
  key_opts     = ["wrapKey", "unwrapKey"]

  depends_on = [azurerm_role_assignment.deployer_crypto_officer]
}

###############################################################################
# Monitoring
###############################################################################

resource "azurerm_log_analytics_workspace" "example" {
  name                = "law-storage-example"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

###############################################################################
# The module
###############################################################################

module "storage" {
  source = "../.."

  name                     = "stcompleteexample001"
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_replication_type = "GZRS"

  # Public endpoint on, but locked to one office range plus Azure services.
  public_network_access_enabled = true
  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices", "Logging", "Metrics"]
    ip_rules       = ["203.0.113.0/24"] # replace with your public range
  }

  identity = {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.storage.id]
  }

  customer_managed_key = {
    # Version-less ID means Azure picks up new key versions automatically.
    key_vault_key_id          = azurerm_key_vault_key.storage.versionless_id
    user_assigned_identity_id = azurerm_user_assigned_identity.storage.id
  }

  blob_properties = {
    delete_retention_days           = 14
    container_delete_retention_days = 14
    change_feed_enabled             = true
    change_feed_retention_in_days   = 30
    restore_days                    = 13 # must be less than delete_retention_days
  }

  containers = {
    raw       = {}
    processed = { metadata = { owner = "data-team" } }
  }

  file_shares = {
    shared = { quota = 100, access_tier = "Hot" }
  }

  queues = {
    ingest = {}
  }

  tables = {
    auditlog = {}
  }

  private_endpoints = {
    for svc in local.storage_services : svc => {
      subresource_name     = svc
      subnet_id            = azurerm_subnet.private_endpoints.id
      private_dns_zone_ids = [azurerm_private_dns_zone.storage[svc].id]
    }
  }

  diagnostic_settings = {
    law = {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.example.id
    }
  }

  tags = {
    environment = "prod"
  }

  # The identity must be able to use the key before the account is encrypted with it.
  depends_on = [azurerm_role_assignment.storage_crypto_user]
}

output "storage" {
  value = {
    id                = module.storage.id
    endpoints         = module.storage.primary_endpoints
    containers        = module.storage.containers
    private_endpoints = module.storage.private_endpoints
  }
}
