output "id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "resource" {
  description = "The full storage account resource, for anything not exposed as a dedicated output. Contains sensitive attributes."
  value       = azurerm_storage_account.this
  sensitive   = true
}

output "primary_endpoints" {
  description = "Primary service endpoints."
  value = {
    blob  = azurerm_storage_account.this.primary_blob_endpoint
    dfs   = azurerm_storage_account.this.primary_dfs_endpoint
    file  = azurerm_storage_account.this.primary_file_endpoint
    queue = azurerm_storage_account.this.primary_queue_endpoint
    table = azurerm_storage_account.this.primary_table_endpoint
    web   = azurerm_storage_account.this.primary_web_endpoint
  }
}

output "identity_principal_id" {
  description = "Principal ID of the system-assigned identity, or null."
  value       = try(azurerm_storage_account.this.identity[0].principal_id, null)
}

output "containers" {
  description = "Created containers, keyed as in var.containers."
  value = {
    for k, c in azurerm_storage_container.this : k => {
      id                  = c.id
      name                = c.name
      resource_manager_id = c.resource_manager_id
      url                 = c.url
    }
  }
}

output "file_shares" {
  description = "Created file shares, keyed as in var.file_shares. Use rbac_scope_id as the scope for role assignments."
  value = {
    for k, s in azurerm_storage_share.this : k => {
      id                  = s.id
      name                = s.name
      resource_manager_id = s.resource_manager_id
      rbac_scope_id       = s.rbac_scope_id
      url                 = s.url
    }
  }
}

output "queues" {
  description = "Created queues, keyed as in var.queues."
  value = {
    for k, q in azurerm_storage_queue.this : k => {
      id                  = q.id
      name                = q.name
      resource_manager_id = q.resource_manager_id
      url                 = q.url
    }
  }
}

output "tables" {
  description = "Created tables, keyed as in var.tables."
  value = {
    for k, t in azurerm_storage_table.this : k => {
      id                  = t.id
      name                = t.name
      resource_manager_id = t.resource_manager_id
    }
  }
}

output "private_endpoints" {
  description = "Created private endpoints with their private IP (Internet Protocol) addresses."
  value = {
    for k, pe in azurerm_private_endpoint.this : k => {
      id                 = pe.id
      name               = pe.name
      private_ip_address = try(pe.private_service_connection[0].private_ip_address, null)
    }
  }
}
