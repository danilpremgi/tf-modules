# Hub and spoke built from the same module:
# - hub VNet (Virtual Network) with the platform subnets Azure requires by name
# - spoke VNet with tier subnets, an NSG (Network Security Group) per subnet,
#   and a route table forcing internet egress through the hub firewall
# - peering between the two
# Subnet sizes follow https://learn.microsoft.com/azure/networking/design-guide/vnets-subnets

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
  name     = "rg-vnet-complete-example"
  location = "uksouth"
}

###############################################################################
# Hub
###############################################################################

module "hub" {
  source = "../.."

  name                = "vnet-hub-prod-uks-001"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  address_space       = ["10.50.0.0/22"]
  tags                = { role = "hub" }

  subnets = {
    "AzureFirewallSubnet" = { address_prefixes = ["10.50.0.0/26"] }   # /26 minimum
    "AzureBastionSubnet"  = { address_prefixes = ["10.50.0.64/26"] }  # /26 minimum
    "RouteServerSubnet"   = { address_prefixes = ["10.50.0.128/26"] } # /26 minimum
    "GatewaySubnet"       = { address_prefixes = ["10.50.0.192/27"] } # /27 minimum
    "snet-management"     = { address_prefixes = ["10.50.1.0/24"] }

    "snet-dns-inbound" = {
      address_prefixes = ["10.50.2.0/28"]
      delegation       = { service = "Microsoft.Network/dnsResolvers" }
    }
    "snet-dns-outbound" = {
      address_prefixes = ["10.50.2.16/28"]
      delegation       = { service = "Microsoft.Network/dnsResolvers" }
    }
  }
}

###############################################################################
# Spoke
###############################################################################

locals {
  spoke_tiers = ["snet-web", "snet-app", "snet-data"]

  # Firewall private IP is the first usable address in AzureFirewallSubnet.
  firewall_private_ip = cidrhost(module.hub.subnet_prefixes["AzureFirewallSubnet"], 4)
}

resource "azurerm_network_security_group" "spoke" {
  for_each = toset(local.spoke_tiers)

  name                = "nsg-${each.key}-prod-uks-001"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_route_table" "spoke" {
  name                          = "rt-spoke-prod-uks-001"
  location                      = azurerm_resource_group.example.location
  resource_group_name           = azurerm_resource_group.example.name
  bgp_route_propagation_enabled = false

  route {
    name                   = "default-via-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.firewall_private_ip
  }
}

module "spoke" {
  source = "../.."

  name                = "vnet-app-prod-uks-001"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  address_space       = ["10.51.0.0/16"]
  tags                = { role = "spoke" }

  subnets = {
    "snet-web"  = { newbits = 8, netnum = 1 }                                            # 10.51.1.0/24
    "snet-app"  = { newbits = 8, netnum = 2 }                                            # 10.51.2.0/24
    "snet-data" = { newbits = 8, netnum = 3, service_endpoints = ["Microsoft.Storage"] } # 10.51.3.0/24

    "snet-private-endpoints" = {
      newbits                           = 8
      netnum                            = 4 # 10.51.4.0/24
      private_endpoint_network_policies = "Enabled"
    }

    "snet-appgw" = { newbits = 8, netnum = 252 } # 10.51.252.0/24 - /24 recommended for autoscaling
  }

  subnet_network_security_group_ids = { for tier in local.spoke_tiers : tier => azurerm_network_security_group.spoke[tier].id }
  subnet_route_table_ids            = { for tier in local.spoke_tiers : tier => azurerm_route_table.spoke.id }
}

# App tier only accepts traffic from the web tier.
resource "azurerm_network_security_rule" "app_from_web" {
  name                        = "allow-web-to-app"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = module.spoke.subnet_prefixes["snet-web"]
  destination_address_prefix  = module.spoke.subnet_prefixes["snet-app"]
  resource_group_name         = azurerm_resource_group.example.name
  network_security_group_name = azurerm_network_security_group.spoke["snet-app"].name
}

###############################################################################
# Peering
###############################################################################

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-hub-to-spoke"
  resource_group_name       = azurerm_resource_group.example.name
  virtual_network_name      = module.hub.name
  remote_virtual_network_id = module.spoke.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-spoke-to-hub"
  resource_group_name       = azurerm_resource_group.example.name
  virtual_network_name      = module.spoke.name
  remote_virtual_network_id = module.hub.id
  allow_forwarded_traffic   = true
}

output "hub_subnet_ids" {
  value = module.hub.subnet_ids
}

output "spoke_subnets" {
  value = module.spoke.subnets
}
