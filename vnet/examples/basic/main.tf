# Minimal call: a VNet (Virtual Network) for a three-tier app, one /24 subnet
# per tier, carved from the address space with cidrsubnet().

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

resource "azurerm_resource_group" "example" {
  name     = "rg-vnet-basic-example"
  location = "uksouth"
}

module "vnet" {
  source = "../.."

  name                = "vnet-app-dev-uks-001"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  address_space       = ["10.40.0.0/16"]

  subnets = {
    "snet-web"  = { newbits = 8, netnum = 1 } # 10.40.1.0/24
    "snet-app"  = { newbits = 8, netnum = 2 } # 10.40.2.0/24
    "snet-data" = { newbits = 8, netnum = 3 } # 10.40.3.0/24
  }
}

output "subnet_ids" {
  value = module.vnet.subnet_ids
}
