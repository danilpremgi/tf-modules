output "id" {
  description = "Resource ID of the VNet (Virtual Network)."
  value       = azurerm_virtual_network.this.id
}

output "name" {
  description = "Name of the VNet."
  value       = azurerm_virtual_network.this.name
}

output "address_space" {
  description = "Address space of the VNet."
  value       = azurerm_virtual_network.this.address_space
}

# Subnet outputs wait for the NSG, route table and NAT gateway associations, so
# consumers (NICs, private endpoints) don't race them for the subnet lock or
# start on a subnet that isn't secured yet.
output "subnets" {
  description = "Subnets keyed as in var.subnets, including any associated NSG (Network Security Group), route table and NAT (Network Address Translation) gateway IDs."
  value = {
    for k, s in azurerm_subnet.this : k => {
      id                        = s.id
      name                      = s.name
      resource_group_name       = s.resource_group_name
      virtual_network_name      = s.virtual_network_name
      address_prefix            = s.address_prefixes[0]
      address_prefixes          = s.address_prefixes
      network_security_group_id = lookup(var.subnet_network_security_group_ids, k, null)
      route_table_id            = lookup(var.subnet_route_table_ids, k, null)
      nat_gateway_id            = lookup(var.subnet_nat_gateway_ids, k, null)
    }
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.this,
    azurerm_subnet_route_table_association.this,
    azurerm_subnet_nat_gateway_association.this,
  ]
}

output "subnet_ids" {
  description = "Subnet IDs keyed as in var.subnets. Available once NSG, route table and NAT gateway associations are applied."
  value       = { for k, s in azurerm_subnet.this : k => s.id }

  depends_on = [
    azurerm_subnet_network_security_group_association.this,
    azurerm_subnet_route_table_association.this,
    azurerm_subnet_nat_gateway_association.this,
  ]
}

output "subnet_prefixes" {
  description = "First address prefix of each subnet, keyed as in var.subnets. Use in NSG rules and routes; for subnets with several prefixes use subnets[key].address_prefixes."
  value       = { for k, s in azurerm_subnet.this : k => s.address_prefixes[0] }
}
