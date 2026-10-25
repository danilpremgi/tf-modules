###############################################################################
# Core
###############################################################################

variable "os_type" {
  description = "Operating system: Linux or Windows. Changing this replaces the VM (Virtual Machine)."
  type        = string

  validation {
    condition     = contains(["Linux", "Windows"], var.os_type)
    error_message = "os_type must be Linux or Windows."
  }
}

variable "name" {
  description = "Name of the VM. Also used to name the NIC (Network Interface Card), disks and Key Vault secret."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,62}[A-Za-z0-9_]$", var.name))
    error_message = "name must be 2-64 characters: letters, numbers, '.', '_' or '-', not starting with '.', '_' or '-' and not ending with '.' or '-'."
  }
}

variable "computer_name" {
  description = "Hostname inside the OS (Operating System). Defaults to name. Windows hostnames are limited to 15 characters."
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "Resource group for the VM, NIC and disks."
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
# Size, placement and image
###############################################################################

variable "size" {
  description = "VM size (SKU (Stock Keeping Unit)). Must support Trusted Launch while secure_boot_enabled or vtpm_enabled are on."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "zone" {
  description = "Availability zone (\"1\", \"2\" or \"3\"). Data disks are placed in the same zone. null for no zone."
  type        = string
  default     = null

  validation {
    condition     = var.zone == null || contains(["1", "2", "3"], coalesce(var.zone, "1"))
    error_message = "zone must be null, \"1\", \"2\" or \"3\"."
  }
}

variable "availability_set_id" {
  description = "Availability set ID. Can't be combined with zone."
  type        = string
  default     = null
}

variable "proximity_placement_group_id" {
  description = "Proximity placement group ID."
  type        = string
  default     = null
}

variable "source_image_reference" {
  description = <<-EOT
    Marketplace image. Defaults to Ubuntu 24.04 LTS (Long-Term Support) for Linux and
    Windows Server 2025 Datacenter Azure Edition for Windows, both Generation 2 images that
    support Trusted Launch. Ignored when source_image_id is set.
  EOT
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = optional(string, "latest")
  })
  default = null
}

variable "source_image_id" {
  description = "ID of a custom image or Azure Compute Gallery image version. Takes priority over source_image_reference."
  type        = string
  default     = null
}

variable "license_type" {
  description = "Azure Hybrid Benefit. Windows: None, Windows_Client or Windows_Server. Linux: RHEL_BYOS, SLES_BYOS and similar."
  type        = string
  default     = null
}

###############################################################################
# OS disk and security
###############################################################################

variable "os_disk" {
  description = "OS disk settings. storage_account_type is Standard_LRS, StandardSSD_LRS, Premium_LRS, StandardSSD_ZRS or Premium_ZRS."
  type = object({
    name                   = optional(string)
    caching                = optional(string, "ReadWrite")
    storage_account_type   = optional(string, "Premium_LRS")
    disk_size_gb           = optional(number)
    disk_encryption_set_id = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["None", "ReadOnly", "ReadWrite"], var.os_disk.caching)
    error_message = "os_disk.caching must be None, ReadOnly or ReadWrite."
  }
}

variable "secure_boot_enabled" {
  description = "Trusted Launch Secure Boot. Needs a Generation 2 image and supported size. Forces replacement."
  type        = bool
  default     = true
}

variable "vtpm_enabled" {
  description = "Trusted Launch vTPM (virtual Trusted Platform Module). Forces replacement."
  type        = bool
  default     = true
}

variable "encryption_at_host_enabled" {
  description = "Encrypt temp disk and caches at the host. Needs the EncryptionAtHost feature registered on the subscription."
  type        = bool
  default     = false
}

###############################################################################
# Patching
###############################################################################

variable "patch_mode" {
  description = "Guest patching. Linux: ImageDefault or AutomaticByPlatform. Windows: Manual, AutomaticByOS or AutomaticByPlatform."
  type        = string
  default     = "AutomaticByPlatform"

  validation {
    condition     = contains(["ImageDefault", "Manual", "AutomaticByOS", "AutomaticByPlatform"], var.patch_mode)
    error_message = "patch_mode must be ImageDefault, Manual, AutomaticByOS or AutomaticByPlatform."
  }
}

variable "patch_assessment_mode" {
  description = "Periodic patch assessment: ImageDefault or AutomaticByPlatform."
  type        = string
  default     = "AutomaticByPlatform"

  validation {
    condition     = contains(["ImageDefault", "AutomaticByPlatform"], var.patch_assessment_mode)
    error_message = "patch_assessment_mode must be ImageDefault or AutomaticByPlatform."
  }
}

variable "reboot_setting" {
  description = "Reboot behaviour for platform patching: Always, IfRequired or Never. Only with patch_mode = AutomaticByPlatform."
  type        = string
  default     = null
}

variable "bypass_platform_safety_checks_on_user_schedule_enabled" {
  description = "Set true when patching is driven by an Azure Update Manager maintenance configuration."
  type        = bool
  default     = false
}

variable "hotpatching_enabled" {
  description = "Windows only. Hotpatching for Azure Edition images; needs patch_mode = AutomaticByPlatform."
  type        = bool
  default     = false
}

variable "timezone" {
  description = "Windows only. Time zone ID, e.g. \"GMT Standard Time\"."
  type        = string
  default     = null
}

###############################################################################
# Admin account and credentials
###############################################################################

variable "admin_username" {
  description = "Local administrator username."
  type        = string
  default     = "azureadmin"

  validation {
    condition = !contains(
      ["admin", "administrator", "root", "guest", "user", "user1", "test", "test1", "sa", "owner", "adm", "sys"],
      lower(var.admin_username)
    )
    error_message = "admin_username can't be a reserved name such as admin, administrator or root."
  }
}

variable "admin_credentials_key_vault_id" {
  description = <<-EOT
    Key Vault the generated credential is written to: an SSH (Secure Shell) private key for Linux,
    a random password for Windows. Whoever runs Terraform needs Key Vault Secrets Officer (or an
    access policy with secret Set) on it.
  EOT
  type        = string
}

variable "admin_credentials_secret_name" {
  description = "Secret name. Defaults to <name>-admin-ssh-key (Linux) or <name>-admin-password (Windows)."
  type        = string
  default     = null
}

variable "admin_credentials_secret_expiration_date" {
  description = "Optional secret expiry as an RFC 3339 timestamp, e.g. 2027-12-31T23:59:59Z. Some Azure Policy baselines require one."
  type        = string
  default     = null
}

###############################################################################
# Networking (private only)
###############################################################################

variable "subnet_id" {
  description = "Subnet for the NIC. The module never creates a public IP (Internet Protocol) address."
  type        = string
}

variable "private_ip_address" {
  description = "Static private IP address. null for dynamic allocation."
  type        = string
  default     = null
}

variable "accelerated_networking_enabled" {
  description = "Accelerated networking on the NIC. The size must support it."
  type        = bool
  default     = false
}

variable "dns_servers" {
  description = "Custom DNS (Domain Name System) servers for the NIC. Empty to inherit from the virtual network."
  type        = list(string)
  default     = []
}

###############################################################################
# Identity
###############################################################################

variable "system_assigned_identity_enabled" {
  description = "Give the VM a system-assigned managed identity. Required for Entra ID login."
  type        = bool
  default     = true
}

variable "user_assigned_identity_ids" {
  description = "User-assigned managed identity IDs to attach."
  type        = list(string)
  default     = []
}

###############################################################################
# Misc
###############################################################################

variable "boot_diagnostics_storage_account_uri" {
  description = "Blob endpoint for boot diagnostics. null uses a Microsoft-managed storage account."
  type        = string
  default     = null
}

variable "custom_data" {
  description = "Base64-encoded custom data (cloud-init on Linux). Forces replacement when changed."
  type        = string
  default     = null
  sensitive   = true
}

variable "user_data" {
  description = "Base64-encoded user data, readable from the Instance Metadata Service. Can change without replacement."
  type        = string
  default     = null
}

###############################################################################
# Optional features
###############################################################################

variable "data_disks" {
  description = <<-EOT
    Managed data disks keyed by label. lun is 0-63 and must be unique. Disks are created with
    network access denied (no disk export/import over the network) and in the VM's zone
    (except ZRS (Zone-Redundant Storage) types, which span zones).
  EOT
  type = map(object({
    lun                       = number
    disk_size_gb              = number
    name                      = optional(string)
    storage_account_type      = optional(string, "Premium_LRS")
    caching                   = optional(string, "ReadOnly")
    disk_encryption_set_id    = optional(string)
    write_accelerator_enabled = optional(bool, false)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = length(distinct([for d in var.data_disks : d.lun])) == length(var.data_disks)
    error_message = "data_disks[*].lun values must be unique."
  }

  validation {
    condition     = alltrue([for d in var.data_disks : d.lun >= 0 && d.lun <= 63])
    error_message = "data_disks[*].lun must be between 0 and 63."
  }

  validation {
    condition     = alltrue([for d in var.data_disks : contains(["None", "ReadOnly", "ReadWrite"], d.caching)])
    error_message = "data_disks[*].caching must be None, ReadOnly or ReadWrite."
  }
}

variable "backup" {
  description = "Protect the VM with an existing Recovery Services vault and backup policy. null to skip."
  type = object({
    recovery_vault_name                = string
    recovery_vault_resource_group_name = string
    backup_policy_id                   = string
  })
  default = null
}

variable "azure_monitor_agent" {
  description = <<-EOT
    Install the Azure Monitor Agent and associate DCRs (Data Collection Rules). data_collection_rule_ids
    is a map of label => DCR ID. Set user_assigned_identity_id to authenticate the agent with a
    user-assigned identity (it must also be in user_assigned_identity_ids); otherwise the
    system-assigned identity is used. null to skip.
  EOT
  type = object({
    data_collection_rule_ids  = optional(map(string), {})
    user_assigned_identity_id = optional(string)
    type_handler_version      = optional(string, "1.0")
  })
  default = null
}

variable "entra_id_login" {
  description = <<-EOT
    Sign in with Microsoft Entra ID instead of the local account. Installs AADSSHLoginForLinux or
    AADLoginForWindows and grants the Virtual Machine Administrator Login / User Login roles on the VM.
    Principal maps are label => object ID. Windows needs Windows Server 2022 or later with Desktop
    Experience. null to skip.
  EOT
  type = object({
    admin_principal_ids  = optional(map(string), {})
    user_principal_ids   = optional(map(string), {})
    type_handler_version = optional(string, "1.0")
  })
  default = null
}
