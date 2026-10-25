# terraform-azurerm-storage-account

Terraform module that creates one Azure Storage Account with secure defaults, plus optional
blob containers, file shares, queues, tables, private endpoints, CMK (Customer-Managed Keys)
encryption and diagnostic settings.

- **Provider:** AzureRM (Azure Resource Manager) `>= 4.77.0, < 5.0.0`
- **Terraform:** `>= 1.5.0`

## Secure defaults

A bare call (name, resource group, location) gives you:

| Setting | Default | Why |
|---|---|---|
| Kind / tier / replication | `StorageV2` / `Standard` / `ZRS` (Zone-Redundant Storage) | Survives a zone outage |
| Public network access | **Off** | Reach it through private endpoints, or turn on and restrict with `network_rules` |
| Shared Key (account keys and SAS (Shared Access Signature)) | **Off** | Microsoft Entra ID only |
| Portal default auth | Microsoft Entra ID | |
| Anonymous blob access | Off | |
| HTTPS (HyperText Transfer Protocol Secure) only, TLS (Transport Layer Security) | On, TLS 1.2 minimum | |
| Cross-tenant replication, local users | Off | |
| Blob soft delete / container soft delete | 7 days / 7 days | |
| Blob versioning | On (off automatically when Hierarchical Namespace is on, as Azure doesn't support both) | |
| File share soft delete | 7 days | |
| Firewall (when public access is on) | Default deny, Azure services bypass | |

Containers, shares, queues and tables are all empty maps by default, so nothing beyond the
account is created unless you ask for it.

## Provider configuration you need

Because Shared Key is off by default, configure the provider like this:

```hcl
provider "azurerm" {
  features {
    storage {
      # The module never uses queue_properties or static_website, so skip the
      # data plane checks that fail when the account has no public endpoint.
      data_plane_available = false
    }
  }
  storage_use_azuread = true
}
```

Containers, shares, queues and tables are created with `storage_account_id`, which goes through
the Azure Resource Manager API rather than the storage data plane. That means `terraform apply`
works from a build agent that has no network line of sight to the account.

## Usage

### Minimal

```hcl
module "storage" {
  source = "./terraform-azurerm-storage-account"

  name                = "stappdev001"
  resource_group_name = "rg-app-dev"
  location            = "uksouth"
}
```

### With data services, private endpoints and diagnostics

```hcl
module "storage" {
  source = "./terraform-azurerm-storage-account"

  name                = "stappprod001"
  resource_group_name = "rg-app-prod"
  location            = "uksouth"

  containers  = { raw = {}, processed = {} }
  file_shares = { shared = { quota = 100 } }
  queues      = { ingest = {} }
  tables      = { auditlog = {} }

  private_endpoints = {
    blob = {
      subresource_name     = "blob"
      subnet_id            = azurerm_subnet.pe.id
      private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
    }
  }

  diagnostic_settings = {
    law = { log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id }
  }
}
```

See [`examples/complete`](examples/complete/main.tf) for CMK, a restricted public firewall and
private endpoints for all four services.

## Inputs

### Required

| Name | Type | Description |
|---|---|---|
| `name` | `string` | 3-24 lowercase letters and numbers, globally unique |
| `resource_group_name` | `string` | Resource group for the account |
| `location` | `string` | Azure region |

### Account

| Name | Default | Description |
|---|---|---|
| `account_kind` | `"StorageV2"` | `StorageV2`, `Storage`, `BlobStorage`, `BlockBlobStorage`, `FileStorage` |
| `account_tier` | `"Standard"` | `Standard` or `Premium` (Premium required for BlockBlobStorage and FileStorage) |
| `account_replication_type` | `"ZRS"` | `LRS`, `ZRS`, `GRS`, `RAGRS`, `GZRS`, `RAGZRS` |
| `access_tier` | `"Hot"` | `Hot`, `Cool`, `Cold`, `Premium` |
| `is_hns_enabled` | `false` | Hierarchical Namespace (Data Lake Storage Gen2). Forces replacement |
| `sftp_enabled` | `false` | SFTP (SSH File Transfer Protocol). Needs HNS and local users |
| `nfsv3_enabled` | `false` | NFS (Network File System) v3. Needs HNS. Forces replacement |
| `large_file_share_enabled` | `false` | Shares over 5 TiB on Standard accounts |
| `tags` | `{}` | Applied to the account and private endpoints |

### Security

| Name | Default | Description |
|---|---|---|
| `public_network_access_enabled` | `false` | Public endpoint on/off |
| `shared_access_key_enabled` | `false` | Shared Key and SAS authorisation |
| `default_to_oauth_authentication` | `true` | Portal uses Entra ID by default |
| `allow_nested_items_to_be_public` | `false` | Anonymous container/blob access |
| `cross_tenant_replication_enabled` | `false` | |
| `infrastructure_encryption_enabled` | `false` | Double encryption. Forces replacement |
| `local_user_enabled` | `false` | |
| `allowed_copy_scope` | `null` | `AAD`, `PrivateLink` or `All` |
| `sas_policy` | `null` | `{ expiration_period = "DD.HH:MM:SS", expiration_action = "Log" \| "Block" }` |
| `identity` | `null` | `{ type, identity_ids }` |
| `customer_managed_key` | `null` | `{ key_vault_key_id, user_assigned_identity_id }` |
| `network_rules` | deny + `AzureServices` bypass | `{ default_action, bypass, ip_rules, virtual_network_subnet_ids, private_link_access }` |
| `private_endpoints` | `{}` | Map of `{ subresource_name, subnet_id, private_dns_zone_ids, ... }` |

### Service properties

| Name | Default | Description |
|---|---|---|
| `blob_properties` | soft delete 7/7 days, versioning on | Set to `null` to omit. Also supports change feed, last-access tracking, point-in-time restore, CORS (Cross-Origin Resource Sharing) |
| `share_properties` | soft delete 7 days | Set to `null` to omit. Also supports SMB (Server Message Block) settings and CORS |

### Sub-resources

| Name | Default | Value shape |
|---|---|---|
| `containers` | `{}` | `{ name?, container_access_type? = "private", metadata? }` |
| `file_shares` | `{}` | `{ name?, quota, access_tier?, enabled_protocol? = "SMB", metadata? }` |
| `queues` | `{}` | `{ name?, metadata? }` |
| `tables` | `{}` | `{ name? }` |
| `diagnostic_settings` | `{}` | `{ log_analytics_workspace_id?, storage_account_id?, eventhub_authorization_rule_id?, services?, log_category_groups? = ["allLogs"], metric_categories? = ["Transaction"] }` |

Map keys are used as names unless `name` is set.

## Outputs

| Name | Description |
|---|---|
| `id`, `name` | Account ID and name |
| `primary_endpoints` | Map of blob, dfs, file, queue, table and web endpoints |
| `identity_principal_id` | System-assigned identity principal ID, or `null` |
| `containers`, `file_shares`, `queues`, `tables` | Maps of IDs, names, Resource Manager IDs and URLs (shares also include `rbac_scope_id` for role assignments) |
| `private_endpoints` | Map of IDs, names and private IP (Internet Protocol) addresses |
| `resource` | Full account resource (sensitive) |

No access keys or connection strings are output, since Shared Key is off by default. Grant access
with role assignments such as **Storage Blob Data Contributor** instead.

## Notes and gotchas

- **CMK:** the user-assigned identity must be in `identity.identity_ids` and hold
  **Key Vault Crypto Service Encryption User** on the key or vault before the account is
  created. Add `depends_on` on that role assignment, as the complete example does. The vault needs
  purge protection. Pass the key's `versionless_id` for automatic rotation.
- **Diagnostic settings:** the account itself only emits metrics, so the module creates one
  setting on the account plus one on each service (`blobServices/default` and so on) for logs.
  Services the account kind doesn't have are skipped.
- **Private endpoints and DNS:** for Data Lake (`dfs`) or static website (`web`) endpoints use the
  `privatelink.dfs.core.windows.net` and `privatelink.web.core.windows.net` zones.
- **Point-in-time restore** (`blob_properties.restore_days`) needs versioning and change feed on,
  and must be shorter than `delete_retention_days`.
- **Preconditions** stop the plan early for invalid combinations: Premium-only kinds on Standard,
  CMK without a matching user-assigned identity, SFTP/NFSv3 without HNS, or sub-resources the
  account kind can't hold.

## Upgrading to AzureRM 5.x

Only one argument changes for this module. In `main.tf`, replace

```hcl
public_network_access_enabled = var.public_network_access_enabled
```

with

```hcl
public_network_access = var.public_network_access_enabled ? "Enabled" : "Disabled"
```

then widen the version constraint in `versions.tf`. 5.x also offers `"SecuredByPerimeter"` if you
use Network Security Perimeter.
