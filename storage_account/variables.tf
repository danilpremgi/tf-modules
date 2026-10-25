###############################################################################
# Core
###############################################################################

variable "name" {
  description = "Name of the storage account. 3-24 characters, lowercase letters and numbers only, globally unique."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "name must be 3-24 characters long and contain only lowercase letters and numbers."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group the storage account is created in."
  type        = string
}

variable "location" {
  description = "Azure region for the storage account (and, by default, its private endpoints)."
  type        = string
}

variable "tags" {
  description = "Tags applied to the storage account and private endpoints."
  type        = map(string)
  default     = {}
}

###############################################################################
# Account SKU (Stock Keeping Unit) and kind
###############################################################################

variable "account_kind" {
  description = "Kind of account: StorageV2, Storage, BlobStorage, BlockBlobStorage or FileStorage."
  type        = string
  default     = "StorageV2"

  validation {
    condition     = contains(["StorageV2", "Storage", "BlobStorage", "BlockBlobStorage", "FileStorage"], var.account_kind)
    error_message = "account_kind must be one of StorageV2, Storage, BlobStorage, BlockBlobStorage, FileStorage."
  }
}

variable "account_tier" {
  description = "Performance tier: Standard or Premium. BlockBlobStorage and FileStorage require Premium."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "account_tier must be Standard or Premium."
  }
}

variable "account_replication_type" {
  description = "Replication: LRS (Locally Redundant), ZRS (Zone Redundant), GRS (Geo Redundant), RAGRS (Read-Access Geo Redundant), GZRS (Geo-Zone Redundant) or RAGZRS (Read-Access Geo-Zone Redundant)."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "access_tier" {
  description = "Default access tier for blob data: Hot, Cool, Cold or Premium. Ignored by Azure for kinds that don't support it."
  type        = string
  default     = "Hot"

  validation {
    condition     = contains(["Hot", "Cool", "Cold", "Premium"], var.access_tier)
    error_message = "access_tier must be one of Hot, Cool, Cold, Premium."
  }
}

variable "is_hns_enabled" {
  description = "Enable Hierarchical Namespace (Azure Data Lake Storage Gen2). Forces a new account when changed. Disables blob versioning by default."
  type        = bool
  default     = false
}

variable "sftp_enabled" {
  description = "Enable SFTP (SSH File Transfer Protocol). Requires is_hns_enabled = true and local_user_enabled = true."
  type        = bool
  default     = false
}

variable "nfsv3_enabled" {
  description = "Enable NFS (Network File System) v3 for blobs. Requires is_hns_enabled = true. Forces a new account when changed."
  type        = bool
  default     = false
}

variable "large_file_share_enabled" {
  description = "Allow file shares larger than 5 TiB (tebibytes) on Standard accounts."
  type        = bool
  default     = false
}

###############################################################################
# Security baseline (secure by default)
###############################################################################

variable "public_network_access_enabled" {
  description = "Allow access over the public endpoint. Off by default; use private endpoints, or turn on and restrict with network_rules."
  type        = bool
  default     = false
}

variable "shared_access_key_enabled" {
  description = "Allow Shared Key (account key and SAS (Shared Access Signature)) authorisation. Off by default so only Microsoft Entra ID works. If off, set storage_use_azuread = true in the provider block."
  type        = bool
  default     = false
}

variable "default_to_oauth_authentication" {
  description = "Make the Azure portal default to Microsoft Entra ID (OAuth) authorisation."
  type        = bool
  default     = true
}

variable "allow_nested_items_to_be_public" {
  description = "Allow containers and blobs to be set to anonymous public read access."
  type        = bool
  default     = false
}

variable "cross_tenant_replication_enabled" {
  description = "Allow object replication to accounts in other Microsoft Entra tenants."
  type        = bool
  default     = false
}

variable "infrastructure_encryption_enabled" {
  description = "Double encryption at the infrastructure layer. Forces a new account when changed; only StorageV2, or Premium BlockBlobStorage/FileStorage."
  type        = bool
  default     = false
}

variable "local_user_enabled" {
  description = "Allow local users (needed for SFTP)."
  type        = bool
  default     = false
}

variable "allowed_copy_scope" {
  description = "Restrict copy operations to accounts in the same tenant (AAD) or reachable via Private Link (PrivateLink). null means no restriction."
  type        = string
  default     = null

  validation {
    condition     = var.allowed_copy_scope == null || contains(["AAD", "PrivateLink", "All"], coalesce(var.allowed_copy_scope, "All"))
    error_message = "allowed_copy_scope must be null, AAD, PrivateLink or All."
  }
}

variable "sas_policy" {
  description = "Optional SAS (Shared Access Signature) expiry policy. expiration_period is DD.HH:MM:SS; expiration_action is Log or Block."
  type = object({
    expiration_period = string
    expiration_action = optional(string, "Log")
  })
  default = null
}

###############################################################################
# Identity and CMK (Customer-Managed Keys)
###############################################################################

variable "identity" {
  description = "Managed identity for the account. type is SystemAssigned, UserAssigned or \"SystemAssigned, UserAssigned\". identity_ids is required when UserAssigned is included."
  type = object({
    type         = string
    identity_ids = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.identity == null || contains(["SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], try(var.identity.type, ""))
    error_message = "identity.type must be SystemAssigned, UserAssigned or \"SystemAssigned, UserAssigned\"."
  }
}

variable "customer_managed_key" {
  description = <<-EOT
    Encrypt the account with a key from Azure Key Vault. The user-assigned identity must also be
    listed in identity.identity_ids and hold the "Key Vault Crypto Service Encryption User" role on
    the key (or vault). Use a version-less key_vault_key_id to get automatic key rotation.
  EOT
  type = object({
    key_vault_key_id          = string
    user_assigned_identity_id = string
  })
  default = null
}

###############################################################################
# Networking
###############################################################################

variable "network_rules" {
  description = <<-EOT
    Firewall rules for the public endpoint. Only take effect when public_network_access_enabled = true.
    ip_rules accepts public IPv4 (Internet Protocol version 4) addresses or CIDR (Classless Inter-Domain Routing)
    ranges up to /30; private (RFC 1918) ranges are not allowed.
  EOT
  type = object({
    default_action             = optional(string, "Deny")
    bypass                     = optional(set(string), ["AzureServices"])
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
    private_link_access = optional(list(object({
      endpoint_resource_id = string
      endpoint_tenant_id   = optional(string)
    })), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["Allow", "Deny"], var.network_rules.default_action)
    error_message = "network_rules.default_action must be Allow or Deny."
  }

  validation {
    condition     = alltrue([for b in var.network_rules.bypass : contains(["AzureServices", "Logging", "Metrics", "None"], b)])
    error_message = "network_rules.bypass values must be AzureServices, Logging, Metrics or None."
  }
}

variable "private_endpoints" {
  description = <<-EOT
    Private endpoints keyed by an arbitrary label. subresource_name is one of blob, file, queue, table,
    dfs (Data Lake) or web (static website). Pass private_dns_zone_ids (e.g. the
    privatelink.blob.core.windows.net zone) to register DNS (Domain Name System) records automatically.
  EOT
  type = map(object({
    subresource_name              = string
    subnet_id                     = string
    name                          = optional(string)
    location                      = optional(string)
    resource_group_name           = optional(string)
    private_dns_zone_ids          = optional(list(string), [])
    private_dns_zone_group_name   = optional(string, "default")
    custom_network_interface_name = optional(string)
    is_manual_connection          = optional(bool, false)
    request_message               = optional(string)
    tags                          = optional(map(string))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for pe in var.private_endpoints : contains(["blob", "file", "queue", "table", "dfs", "web"], pe.subresource_name)])
    error_message = "private_endpoints[*].subresource_name must be one of blob, file, queue, table, dfs, web."
  }
}

###############################################################################
# Service properties
###############################################################################

variable "blob_properties" {
  description = <<-EOT
    Blob service settings. Secure defaults: soft delete for blobs and containers (7 days) and versioning
    (on unless Hierarchical Namespace is enabled, where versioning isn't supported). Set to null to omit
    the block entirely. Ignored for FileStorage accounts.
  EOT
  type = object({
    versioning_enabled              = optional(bool) # null = on, unless is_hns_enabled
    change_feed_enabled             = optional(bool, false)
    change_feed_retention_in_days   = optional(number)
    last_access_time_enabled        = optional(bool, false)
    default_service_version         = optional(string)
    delete_retention_days           = optional(number, 7)
    permanent_delete_enabled        = optional(bool, false)
    container_delete_retention_days = optional(number, 7)
    restore_days                    = optional(number) # point-in-time restore; needs versioning + change feed
    cors_rules = optional(list(object({
      allowed_headers    = list(string)
      allowed_methods    = list(string)
      allowed_origins    = list(string)
      exposed_headers    = list(string)
      max_age_in_seconds = number
    })), [])
  })
  default = {}
}

variable "share_properties" {
  description = "File service settings. Defaults to 7-day share soft delete. Set to null to omit. Only applied to Standard Storage/StorageV2 or Premium FileStorage accounts."
  type = object({
    retention_days = optional(number, 7)
    smb = optional(object({
      versions                        = optional(set(string))
      authentication_types            = optional(set(string))
      kerberos_ticket_encryption_type = optional(set(string))
      channel_encryption_type         = optional(set(string))
      multichannel_enabled            = optional(bool)
    }))
    cors_rules = optional(list(object({
      allowed_headers    = list(string)
      allowed_methods    = list(string)
      allowed_origins    = list(string)
      exposed_headers    = list(string)
      max_age_in_seconds = number
    })), [])
  })
  default = {}
}

###############################################################################
# Sub-resources (all optional, empty by default)
###############################################################################

variable "containers" {
  description = "Blob containers keyed by name (or set name explicitly). container_access_type is private, blob or container."
  type = map(object({
    name                  = optional(string)
    container_access_type = optional(string, "private")
    metadata              = optional(map(string))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for c in var.containers : contains(["private", "blob", "container"], c.container_access_type)])
    error_message = "containers[*].container_access_type must be private, blob or container."
  }
}

variable "file_shares" {
  description = "Azure Files shares keyed by name (or set name explicitly). quota is in GiB (gibibytes)."
  type = map(object({
    name             = optional(string)
    quota            = number
    access_tier      = optional(string)
    enabled_protocol = optional(string, "SMB")
    metadata         = optional(map(string))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for s in var.file_shares : contains(["SMB", "NFS"], s.enabled_protocol)])
    error_message = "file_shares[*].enabled_protocol must be SMB (Server Message Block) or NFS (Network File System)."
  }
}

variable "queues" {
  description = "Storage queues keyed by name (or set name explicitly)."
  type = map(object({
    name     = optional(string)
    metadata = optional(map(string))
  }))
  default  = {}
  nullable = false
}

variable "tables" {
  description = "Storage tables keyed by name (or set name explicitly). Names are alphanumeric and start with a letter."
  type = map(object({
    name = optional(string)
  }))
  default  = {}
  nullable = false
}

###############################################################################
# Diagnostics
###############################################################################

variable "diagnostic_settings" {
  description = <<-EOT
    Diagnostic settings keyed by label. Each creates one setting on the account (metrics only) and one per
    selected service (blob, file, queue, table) with logs and metrics. Services the account kind doesn't
    support are skipped. At least one destination is required.
  EOT
  type = map(object({
    name                           = optional(string)
    log_analytics_workspace_id     = optional(string)
    log_analytics_destination_type = optional(string)
    storage_account_id             = optional(string)
    eventhub_authorization_rule_id = optional(string)
    eventhub_name                  = optional(string)
    services                       = optional(set(string), ["blob", "file", "queue", "table"])
    log_category_groups            = optional(set(string), ["allLogs"])
    log_categories                 = optional(set(string), [])
    metric_categories              = optional(set(string), ["Transaction"])
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for d in var.diagnostic_settings :
      d.log_analytics_workspace_id != null || d.storage_account_id != null || d.eventhub_authorization_rule_id != null
    ])
    error_message = "Each diagnostic setting needs at least one of log_analytics_workspace_id, storage_account_id or eventhub_authorization_rule_id."
  }

  validation {
    condition     = alltrue(flatten([for d in var.diagnostic_settings : [for s in d.services : contains(["blob", "file", "queue", "table"], s)]]))
    error_message = "diagnostic_settings[*].services values must be blob, file, queue or table."
  }
}
