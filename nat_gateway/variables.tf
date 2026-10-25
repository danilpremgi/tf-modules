###############################################################################
# Core
###############################################################################

variable "name" {
  description = "Name of the NAT (Network Address Translation) gateway. Also used to name the public IPs and prefix it creates."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,78}[A-Za-z0-9_]$", var.name))
    error_message = "name must be 2-80 characters: letters, numbers, '.', '_' or '-', starting with a letter or number and ending with a letter, number or '_'."
  }
}

variable "resource_group_name" {
  description = "Resource group for the NAT gateway and its public IPs."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource the module creates."
  type        = map(string)
  default     = {}
}

###############################################################################
# SKU and zones
###############################################################################

variable "sku_name" {
  description = "Standard (zonal or no-zone) or StandardV2 (zone-redundant, same price). Changing this replaces the NAT gateway and its public IPs."
  type        = string
  default     = "StandardV2"

  validation {
    condition     = contains(["Standard", "StandardV2"], var.sku_name)
    error_message = "sku_name must be Standard or StandardV2."
  }
}

variable "zones" {
  description = <<-EOT
    Standard: null for no zone, or one zone such as ["1"]. Applied to the NAT gateway and its public IPs.
    StandardV2: zones of the public IPs only (the gateway is always zone-redundant). null means ["1", "2", "3"];
    use [] in regions without availability zones.
  EOT
  type        = list(string)
  default     = null

  validation {
    condition     = var.zones == null || alltrue([for z in coalesce(var.zones, []) : contains(["1", "2", "3"], z)])
    error_message = "zones may only contain \"1\", \"2\" or \"3\"."
  }
}

variable "idle_timeout_in_minutes" {
  description = "TCP idle timeout in minutes, 4-120. UDP is fixed at 4."
  type        = number
  default     = 4

  validation {
    condition     = var.idle_timeout_in_minutes >= 4 && var.idle_timeout_in_minutes <= 120
    error_message = "idle_timeout_in_minutes must be between 4 and 120."
  }
}

###############################################################################
# Outbound IPs
###############################################################################

variable "public_ip_count" {
  description = "Number of public IPs to create, named pip-<name>-01, -02 and so on. Each adds 64,512 SNAT (Source NAT) ports."
  type        = number
  default     = 1

  validation {
    condition     = var.public_ip_count >= 0 && var.public_ip_count <= 16 && floor(var.public_ip_count) == var.public_ip_count
    error_message = "public_ip_count must be a whole number from 0 to 16."
  }
}

variable "public_ip_prefix_length" {
  description = "Create a public IP prefix of this length (28-31) for a contiguous outbound range you can allowlist. null for none."
  type        = number
  default     = null

  validation {
    condition     = var.public_ip_prefix_length == null || contains([28, 29, 30, 31], coalesce(var.public_ip_prefix_length, 31))
    error_message = "public_ip_prefix_length must be null or 28-31."
  }
}

variable "existing_public_ip_ids" {
  description = "Public IPs created elsewhere to attach, keyed by a label you choose. SKU must match sku_name."
  type        = map(string)
  default     = {}
}

variable "existing_public_ip_prefix_ids" {
  description = "Public IP prefixes created elsewhere to attach, keyed by a label you choose. SKU must match sku_name."
  type        = map(string)
  default     = {}
}
