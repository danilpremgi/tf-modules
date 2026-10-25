# Minimal call: a locked-down StorageV2 account with no containers, shares,
# queues or tables. Public access and Shared Key are off, so reach it through a
# private endpoint (see ../complete) or turn public access on with network_rules.

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
      # The module doesn't use queue_properties or static_website, so skip the
      # data plane checks that would otherwise fail on a private account.
      data_plane_available = false
    }
  }
  # Shared Key is disabled, so authenticate to storage with Microsoft Entra ID.
  storage_use_azuread = true
}

resource "azurerm_resource_group" "example" {
  name     = "rg-storage-basic-example"
  location = "uksouth"
}

module "storage" {
  source = "../.."

  name                = "stbasicexample001"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location

  tags = {
    environment = "dev"
  }
}

output "storage_account_id" {
  value = module.storage.id
}
