resource "azurerm_virtual_network" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  dns_servers         = var.dns_servers
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                 = coalesce(each.value.name, each.key)
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes = coalesce(
    each.value.address_prefixes,
    [cidrsubnet(var.address_space[0], coalesce(each.value.newbits, 0), coalesce(each.value.netnum, 0))],
  )

  service_endpoints                 = each.value.service_endpoints
  private_endpoint_network_policies = each.value.private_endpoint_network_policies

  # Private by default: VMs need a NAT gateway, firewall route or public IP for
  # internet egress. Delegated subnets leave outbound to the service.
  default_outbound_access_enabled = each.value.delegation == null ? each.value.default_outbound_access_enabled : null

  dynamic "delegation" {
    for_each = each.value.delegation == null ? [] : [each.value.delegation]
    content {
      name = "delegation"
      service_delegation {
        name    = delegation.value.service
        actions = delegation.value.actions
      }
    }
  }
}

# Keyed by subnet key rather than filtered on null IDs, so the plan works when
# an NSG or route table is created in the same run.
resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = var.subnet_network_security_group_ids

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = each.value
}

resource "azurerm_subnet_route_table_association" "this" {
  for_each = var.subnet_route_table_ids

  subnet_id      = azurerm_subnet.this[each.key].id
  route_table_id = each.value
}

resource "azurerm_subnet_nat_gateway_association" "this" {
  for_each = var.subnet_nat_gateway_ids

  subnet_id      = azurerm_subnet.this[each.key].id
  nat_gateway_id = each.value

  lifecycle {
    precondition {
      condition     = azurerm_subnet.this[each.key].name != "GatewaySubnet"
      error_message = "NAT gateways can't be associated with GatewaySubnet."
    }
  }
}

# Resource addresses from before the module was made reusable.
moved {
  from = azurerm_virtual_network.my_vnet
  to   = azurerm_virtual_network.this
}

moved {
  from = azurerm_subnet.dynamic_subnets
  to   = azurerm_subnet.this
}
