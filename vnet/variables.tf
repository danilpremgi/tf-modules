###############################################################################
# Core
###############################################################################

variable "name" {
  description = "Name of the VNet (Virtual Network)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,62}[A-Za-z0-9_]$", var.name))
    error_message = "name must be 2-64 characters: letters, numbers, '.', '_' or '-', starting with a letter or number and ending with a letter, number or '_'."
  }
}

variable "resource_group_name" {
  description = "Resource group for the VNet and its subnets."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tags" {
  description = "Tags applied to the VNet. Subnets don't support tags."
  type        = map(string)
  default     = {}
}

###############################################################################
# Address space and DNS
###############################################################################

variable "address_space" {
  description = "VNet address space. Pick ranges that don't overlap on-premises, other VNets, AWS VPCs or Google Cloud VPCs. Subnets using newbits/netnum are carved from the first entry."
  type        = list(string)

  validation {
    condition     = length(var.address_space) > 0 && alltrue([for cidr in var.address_space : can(cidrhost(cidr, 0))])
    error_message = "address_space must contain at least one valid CIDR block."
  }
}

variable "dns_servers" {
  description = "Custom DNS (Domain Name System) servers. Empty for Azure-provided DNS."
  type        = list(string)
  default     = []
}

###############################################################################
# Subnets
###############################################################################

variable "subnets" {
  description = <<-EOT
    Subnets keyed by a label you choose. The key is used as the subnet name unless name is set.
    Give each subnet either address_prefixes, or newbits and netnum (passed to cidrsubnet() against
    the first address_space entry).
  EOT
  type = map(object({
    name             = optional(string)
    address_prefixes = optional(list(string))
    newbits          = optional(number)
    netnum           = optional(number)

    service_endpoints                 = optional(list(string), [])
    private_endpoint_network_policies = optional(string, "Disabled")
    default_outbound_access_enabled   = optional(bool, false)

    delegation = optional(object({
      service = string
      actions = optional(list(string))
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for s in values(var.subnets) :
      (s.address_prefixes != null) != (s.newbits != null && s.netnum != null)
    ])
    error_message = "Each subnet needs either address_prefixes, or both newbits and netnum, but not both."
  }

  validation {
    condition = alltrue([
      for s in values(var.subnets) :
      contains(["Disabled", "Enabled", "NetworkSecurityGroupEnabled", "RouteTableEnabled"], s.private_endpoint_network_policies)
    ])
    error_message = "private_endpoint_network_policies must be Disabled, Enabled, NetworkSecurityGroupEnabled or RouteTableEnabled."
  }
}

variable "subnet_network_security_group_ids" {
  description = "NSG (Network Security Group) IDs to associate, keyed by subnet key. Keys must exist in subnets."
  type        = map(string)
  default     = {}
}

variable "subnet_route_table_ids" {
  description = "Route table IDs to associate, keyed by subnet key. Keys must exist in subnets."
  type        = map(string)
  default     = {}
}

variable "subnet_nat_gateway_ids" {
  description = "NAT (Network Address Translation) gateway IDs to associate, keyed by subnet key. Keys must exist in subnets. Not supported on GatewaySubnet."
  type        = map(string)
  default     = {}
}
