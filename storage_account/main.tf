locals {
  # Which data services each account kind actually has.
  services_by_kind = {
    StorageV2        = ["blob", "file", "queue", "table"]
    Storage          = ["blob", "file", "queue", "table"]
    BlobStorage      = ["blob"]
    BlockBlobStorage = ["blob"]
    FileStorage      = ["file"]
  }
  supported_services = local.services_by_kind[var.account_kind]

  blob_properties_supported = var.account_kind != "FileStorage"
  # Versioning, change feed, last-access tracking and restore aren't available on legacy Storage (v1).
  blob_advanced_supported = local.blob_properties_supported && var.account_kind != "Storage"

  share_properties_supported = (
    (var.account_tier == "Standard" && contains(["Storage", "StorageV2"], var.account_kind)) ||
    (var.account_tier == "Premium" && var.account_kind == "FileStorage")
  )

  # Versioning defaults to on, except with Hierarchical Namespace where Azure doesn't support it.
  blob_versioning_enabled = (
    var.blob_properties == null ? false :
    coalesce(var.blob_properties.versioning_enabled, !var.is_hns_enabled)
  )

  identity_type_has_user_assigned = var.identity == null ? false : strcontains(var.identity.type, "UserAssigned")

  # One diagnostic setting on the account itself (metrics only), plus one per supported service.
  diagnostic_targets = merge([
    for dk, d in var.diagnostic_settings : merge(
      {
        "${dk}/account" = {
          setting           = d
          target_id         = azurerm_storage_account.this.id
          name              = coalesce(d.name, "diag-${var.name}-${dk}")
          is_service        = false
          metric_categories = d.metric_categories
        }
      },
      {
        for svc in setintersection(d.services, toset(local.supported_services)) :
        "${dk}/${svc}" => {
          setting           = d
          target_id         = "${azurerm_storage_account.this.id}/${svc}Services/default"
          name              = coalesce(d.name, "diag-${var.name}-${dk}")
          is_service        = true
          metric_categories = d.metric_categories
        }
      }
    )
  ]...)
}

###############################################################################
# Storage account
###############################################################################

resource "azurerm_storage_account" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  account_kind             = var.account_kind
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type
  access_tier              = var.access_tier

  is_hns_enabled           = var.is_hns_enabled
  sftp_enabled             = var.sftp_enabled
  nfsv3_enabled            = var.nfsv3_enabled
  large_file_share_enabled = var.large_file_share_enabled

  # Security baseline
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  public_network_access_enabled     = var.public_network_access_enabled
  shared_access_key_enabled         = var.shared_access_key_enabled
  default_to_oauth_authentication   = var.default_to_oauth_authentication
  allow_nested_items_to_be_public   = var.allow_nested_items_to_be_public
  cross_tenant_replication_enabled  = var.cross_tenant_replication_enabled
  infrastructure_encryption_enabled = var.infrastructure_encryption_enabled
  local_user_enabled                = var.local_user_enabled
  allowed_copy_scope                = var.allowed_copy_scope

  dynamic "sas_policy" {
    for_each = var.sas_policy == null ? [] : [var.sas_policy]
    content {
      expiration_period = sas_policy.value.expiration_period
      expiration_action = sas_policy.value.expiration_action
    }
  }

  dynamic "identity" {
    for_each = var.identity == null ? [] : [var.identity]
    content {
      type         = identity.value.type
      identity_ids = local.identity_type_has_user_assigned ? identity.value.identity_ids : null
    }
  }

  dynamic "customer_managed_key" {
    for_each = var.customer_managed_key == null ? [] : [var.customer_managed_key]
    content {
      key_vault_key_id          = customer_managed_key.value.key_vault_key_id
      user_assigned_identity_id = customer_managed_key.value.user_assigned_identity_id
    }
  }

  network_rules {
    default_action             = var.network_rules.default_action
    bypass                     = var.network_rules.bypass
    ip_rules                   = var.network_rules.ip_rules
    virtual_network_subnet_ids = var.network_rules.virtual_network_subnet_ids

    dynamic "private_link_access" {
      for_each = var.network_rules.private_link_access
      content {
        endpoint_resource_id = private_link_access.value.endpoint_resource_id
        endpoint_tenant_id   = private_link_access.value.endpoint_tenant_id
      }
    }
  }

  dynamic "blob_properties" {
    for_each = var.blob_properties != null && local.blob_properties_supported ? [var.blob_properties] : []
    content {
      versioning_enabled            = local.blob_advanced_supported ? local.blob_versioning_enabled : null
      change_feed_enabled           = local.blob_advanced_supported ? blob_properties.value.change_feed_enabled : null
      change_feed_retention_in_days = local.blob_advanced_supported ? blob_properties.value.change_feed_retention_in_days : null
      last_access_time_enabled      = local.blob_advanced_supported ? blob_properties.value.last_access_time_enabled : null
      default_service_version       = blob_properties.value.default_service_version

      dynamic "delete_retention_policy" {
        for_each = blob_properties.value.delete_retention_days == null ? [] : [1]
        content {
          days                     = blob_properties.value.delete_retention_days
          permanent_delete_enabled = blob_properties.value.permanent_delete_enabled
        }
      }

      dynamic "container_delete_retention_policy" {
        for_each = blob_properties.value.container_delete_retention_days == null ? [] : [1]
        content {
          days = blob_properties.value.container_delete_retention_days
        }
      }

      dynamic "restore_policy" {
        for_each = blob_properties.value.restore_days != null && local.blob_advanced_supported ? [1] : []
        content {
          days = blob_properties.value.restore_days
        }
      }

      dynamic "cors_rule" {
        for_each = blob_properties.value.cors_rules
        content {
          allowed_headers    = cors_rule.value.allowed_headers
          allowed_methods    = cors_rule.value.allowed_methods
          allowed_origins    = cors_rule.value.allowed_origins
          exposed_headers    = cors_rule.value.exposed_headers
          max_age_in_seconds = cors_rule.value.max_age_in_seconds
        }
      }
    }
  }

  dynamic "share_properties" {
    for_each = var.share_properties != null && local.share_properties_supported ? [var.share_properties] : []
    content {
      dynamic "retention_policy" {
        for_each = share_properties.value.retention_days == null ? [] : [1]
        content {
          days = share_properties.value.retention_days
        }
      }

      dynamic "smb" {
        for_each = share_properties.value.smb == null ? [] : [share_properties.value.smb]
        content {
          versions                        = smb.value.versions
          authentication_types            = smb.value.authentication_types
          kerberos_ticket_encryption_type = smb.value.kerberos_ticket_encryption_type
          channel_encryption_type         = smb.value.channel_encryption_type
          multichannel_enabled            = smb.value.multichannel_enabled
        }
      }

      dynamic "cors_rule" {
        for_each = share_properties.value.cors_rules
        content {
          allowed_headers    = cors_rule.value.allowed_headers
          allowed_methods    = cors_rule.value.allowed_methods
          allowed_origins    = cors_rule.value.allowed_origins
          exposed_headers    = cors_rule.value.exposed_headers
          max_age_in_seconds = cors_rule.value.max_age_in_seconds
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = !contains(["BlockBlobStorage", "FileStorage"], var.account_kind) || var.account_tier == "Premium"
      error_message = "BlockBlobStorage and FileStorage accounts require account_tier = \"Premium\"."
    }

    precondition {
      condition = var.customer_managed_key == null || (
        local.identity_type_has_user_assigned &&
        contains(try(var.identity.identity_ids, []), try(var.customer_managed_key.user_assigned_identity_id, ""))
      )
      error_message = "customer_managed_key needs identity.type to include UserAssigned, with customer_managed_key.user_assigned_identity_id listed in identity.identity_ids."
    }

    precondition {
      condition     = var.customer_managed_key == null || var.account_kind == "StorageV2" || var.account_tier == "Premium"
      error_message = "customer_managed_key requires account_kind = \"StorageV2\" or account_tier = \"Premium\"."
    }

    precondition {
      condition     = !local.identity_type_has_user_assigned || length(try(var.identity.identity_ids, [])) > 0
      error_message = "identity.identity_ids must be set when identity.type includes UserAssigned."
    }

    precondition {
      condition     = !var.sftp_enabled || (var.is_hns_enabled && var.local_user_enabled)
      error_message = "sftp_enabled requires is_hns_enabled = true and local_user_enabled = true."
    }

    precondition {
      condition     = !var.nfsv3_enabled || var.is_hns_enabled
      error_message = "nfsv3_enabled requires is_hns_enabled = true."
    }

    precondition {
      condition     = length(var.containers) == 0 || contains(local.supported_services, "blob")
      error_message = "containers can't be created on a ${var.account_kind} account."
    }

    precondition {
      condition     = length(var.file_shares) == 0 || contains(local.supported_services, "file")
      error_message = "file_shares can't be created on a ${var.account_kind} account."
    }

    precondition {
      condition     = (length(var.queues) == 0 && length(var.tables) == 0) || contains(local.supported_services, "queue")
      error_message = "queues and tables can only be created on Storage or StorageV2 accounts."
    }
  }
}

###############################################################################
# Data services (created through Azure Resource Manager via storage_account_id,
# so they work with Shared Key disabled and the public endpoint closed)
###############################################################################

resource "azurerm_storage_container" "this" {
  for_each = var.containers

  name                  = coalesce(each.value.name, each.key)
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = each.value.container_access_type
  metadata              = each.value.metadata
}

resource "azurerm_storage_share" "this" {
  for_each = var.file_shares

  name               = coalesce(each.value.name, each.key)
  storage_account_id = azurerm_storage_account.this.id
  quota              = each.value.quota
  access_tier        = each.value.access_tier
  enabled_protocol   = each.value.enabled_protocol
  metadata           = each.value.metadata
}

resource "azurerm_storage_queue" "this" {
  for_each = var.queues

  name               = coalesce(each.value.name, each.key)
  storage_account_id = azurerm_storage_account.this.id
  metadata           = each.value.metadata
}

resource "azurerm_storage_table" "this" {
  for_each = var.tables

  name               = coalesce(each.value.name, each.key)
  storage_account_id = azurerm_storage_account.this.id
}

###############################################################################
# Private endpoints
###############################################################################

resource "azurerm_private_endpoint" "this" {
  for_each = var.private_endpoints

  name                          = coalesce(each.value.name, "pe-${var.name}-${each.key}")
  location                      = coalesce(each.value.location, var.location)
  resource_group_name           = coalesce(each.value.resource_group_name, var.resource_group_name)
  subnet_id                     = each.value.subnet_id
  custom_network_interface_name = each.value.custom_network_interface_name
  tags                          = coalesce(each.value.tags, var.tags)

  private_service_connection {
    name                           = "psc-${var.name}-${each.key}"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = [each.value.subresource_name]
    is_manual_connection           = each.value.is_manual_connection
    request_message                = each.value.is_manual_connection ? each.value.request_message : null
  }

  dynamic "private_dns_zone_group" {
    for_each = length(each.value.private_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = each.value.private_dns_zone_group_name
      private_dns_zone_ids = each.value.private_dns_zone_ids
    }
  }
}

###############################################################################
# Diagnostic settings
###############################################################################

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = local.diagnostic_targets

  name                           = each.value.name
  target_resource_id             = each.value.target_id
  log_analytics_workspace_id     = each.value.setting.log_analytics_workspace_id
  log_analytics_destination_type = each.value.setting.log_analytics_destination_type
  storage_account_id             = each.value.setting.storage_account_id
  eventhub_authorization_rule_id = each.value.setting.eventhub_authorization_rule_id
  eventhub_name                  = each.value.setting.eventhub_name

  # The account resource only emits metrics; logs live on each service.
  dynamic "enabled_log" {
    for_each = each.value.is_service ? each.value.setting.log_category_groups : []
    content {
      category_group = enabled_log.value
    }
  }

  dynamic "enabled_log" {
    for_each = each.value.is_service ? each.value.setting.log_categories : []
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = each.value.metric_categories
    content {
      category = enabled_metric.value
    }
  }
}
