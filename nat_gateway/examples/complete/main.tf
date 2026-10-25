# Two NAT (Network Address Translation) gateways from the same module:
# - StandardV2 with a /30 prefix (4 contiguous IPs to allowlist) plus one extra
#   public IP, shared by two subnets
# - zonal Standard gateway pinned to zone 1 for a zonal workload, with a
#   longer idle timeout

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
  name     = "rg-nat-complete-example"
  location = "uksouth"
}

module "nat_shared" {
  source = "../.."

  name                    = "ng-app-prod-uks-001"
  resource_group_name     = azurerm_resource_group.example.name
  location                = azurerm_resource_group.example.location
  sku_name                = "StandardV2"
  public_ip_count         = 1
  public_ip_prefix_length = 30
  tags                    = { workload = "app" }
}

module "nat_zonal" {
  source = "../.."

  name                    = "ng-batch-prod-uks-001"
  resource_group_name     = azurerm_resource_group.example.name
  location                = azurerm_resource_group.example.location
  sku_name                = "Standard"
  zones                   = ["1"]
  idle_timeout_in_minutes = 30
  tags                    = { workload = "batch" }
}

module "vnet" {
  source = "../../../vnet"

  name                = "vnet-app-prod-uks-001"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  address_space       = ["10.61.0.0/16"]

  subnets = {
    "snet-web"   = { newbits = 8, netnum = 1 } # 10.61.1.0/24
    "snet-app"   = { newbits = 8, netnum = 2 } # 10.61.2.0/24
    "snet-batch" = { newbits = 8, netnum = 3 } # 10.61.3.0/24
  }

  subnet_nat_gateway_ids = {
    "snet-web"   = module.nat_shared.id
    "snet-app"   = module.nat_shared.id
    "snet-batch" = module.nat_zonal.id
  }
}

output "allowlist" {
  value = {
    prefix = module.nat_shared.public_ip_prefix
    ips    = module.nat_shared.public_ip_addresses
  }
}
