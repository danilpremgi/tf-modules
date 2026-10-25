locals {
  is_v2 = var.sku_name == "StandardV2"

  # StandardV2 gateways reject zones; their public IPs default to all three.
  nat_gateway_zones = local.is_v2 ? null : var.zones
  public_ip_zones   = local.is_v2 ? coalesce(var.zones, ["1", "2", "3"]) : var.zones

  public_ip_keys = [for i in range(var.public_ip_count) : format("%02d", i + 1)]

  # A NAT gateway supports at most 16 IPv4 addresses across IPs and prefixes.
  created_prefix_size = var.public_ip_prefix_length == null ? 0 : pow(2, 32 - var.public_ip_prefix_length)
  created_ip_total    = var.public_ip_count + local.created_prefix_size
}

resource "azurerm_nat_gateway" "this" {
  name                    = var.name
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = var.sku_name
  zones                   = local.nat_gateway_zones
  idle_timeout_in_minutes = var.idle_timeout_in_minutes
  tags                    = var.tags

  lifecycle {
    precondition {
      condition     = local.is_v2 || var.zones == null || length(coalesce(var.zones, [])) <= 1
      error_message = "A Standard NAT gateway is zonal: set zones to null or a single zone. Use StandardV2 for zone redundancy."
    }

    precondition {
      condition     = local.created_ip_total + length(var.existing_public_ip_ids) + length(var.existing_public_ip_prefix_ids) > 0
      error_message = "The NAT gateway needs at least one outbound IP: set public_ip_count, public_ip_prefix_length or an existing IP or prefix."
    }

    precondition {
      condition     = local.created_ip_total <= 16
      error_message = "public_ip_count plus the addresses in public_ip_prefix_length must not exceed 16."
    }
  }
}

###############################################################################
# Outbound IPs
###############################################################################

resource "azurerm_public_ip" "this" {
  for_each = toset(local.public_ip_keys)

  name                = "pip-${var.name}-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku_name
  allocation_method   = "Static"
  zones               = local.public_ip_zones
  tags                = var.tags
}

resource "azurerm_public_ip_prefix" "this" {
  count = var.public_ip_prefix_length == null ? 0 : 1

  name                = "ippre-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku_name
  prefix_length       = var.public_ip_prefix_length
  zones               = local.public_ip_zones
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "created" {
  for_each = azurerm_public_ip.this

  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = each.value.id
}

resource "azurerm_nat_gateway_public_ip_association" "existing" {
  for_each = var.existing_public_ip_ids

  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = each.value
}

resource "azurerm_nat_gateway_public_ip_prefix_association" "created" {
  count = length(azurerm_public_ip_prefix.this)

  nat_gateway_id      = azurerm_nat_gateway.this.id
  public_ip_prefix_id = azurerm_public_ip_prefix.this[0].id
}

resource "azurerm_nat_gateway_public_ip_prefix_association" "existing" {
  for_each = var.existing_public_ip_prefix_ids

  nat_gateway_id      = azurerm_nat_gateway.this.id
  public_ip_prefix_id = each.value
}
