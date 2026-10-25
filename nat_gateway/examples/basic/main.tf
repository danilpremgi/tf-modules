# Minimal call: a zone-redundant StandardV2 NAT (Network Address Translation)
# gateway with one public IP, giving a private subnet internet egress.

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
  name     = "rg-nat-basic-example"
  location = "uksouth"
}

module "nat" {
  source = "../.."

  name                = "ng-app-dev-uks-001"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
}

module "vnet" {
  source = "../../../vnet"

  name                = "vnet-app-dev-uks-001"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  address_space       = ["10.60.0.0/16"]

  subnets = {
    "snet-app" = { newbits = 8, netnum = 1 } # 10.60.1.0/24, private by default
  }

  subnet_nat_gateway_ids = {
    "snet-app" = module.nat.id
  }
}

output "outbound_ips" {
  value = module.nat.public_ip_addresses
}
