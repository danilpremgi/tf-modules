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

output "subnets" {
  description = "Subnets keyed as in var.subnets."
  value = {
    for k, s in azurerm_subnet.this : k => {
      id               = s.id
      name             = s.name
      address_prefixes = s.address_prefixes
    }
  }
}

output "subnet_ids" {
  description = "Subnet IDs keyed as in var.subnets."
  value       = { for k, s in azurerm_subnet.this : k => s.id }
}

output "subnet_prefixes" {
  description = "First address prefix of each subnet, keyed as in var.subnets. Use in NSG (Network Security Group) rules."
  value       = { for k, s in azurerm_subnet.this : k => s.address_prefixes[0] }
}
