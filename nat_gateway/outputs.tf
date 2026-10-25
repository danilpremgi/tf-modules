output "id" {
  description = "Resource ID of the NAT (Network Address Translation) gateway. Pass to the vnet module's subnet_nat_gateway_ids."
  value       = azurerm_nat_gateway.this.id
}

output "name" {
  description = "Name of the NAT gateway."
  value       = azurerm_nat_gateway.this.name
}

output "sku_name" {
  description = "Standard or StandardV2."
  value       = azurerm_nat_gateway.this.sku_name
}

output "public_ip_ids" {
  description = "IDs of the public IPs the module created, keyed 01, 02 and so on."
  value       = { for k, ip in azurerm_public_ip.this : k => ip.id }
}

output "public_ip_addresses" {
  description = "Outbound addresses of the public IPs the module created. Give these to third parties that allowlist your traffic."
  value       = [for ip in azurerm_public_ip.this : ip.ip_address]
}

output "public_ip_prefix" {
  description = "CIDR of the public IP prefix the module created, or null."
  value       = one(azurerm_public_ip_prefix.this[*].ip_prefix)
}

output "public_ip_prefix_id" {
  description = "ID of the public IP prefix the module created, or null."
  value       = one(azurerm_public_ip_prefix.this[*].id)
}
