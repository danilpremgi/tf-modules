terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 4.77.0 is the first 4.x release where containers, shares, queues AND
      # tables all accept `storage_account_id` (Azure Resource Manager API).
      # Capped below 5.0 because 5.x replaces `public_network_access_enabled`
      # with the string argument `public_network_access`.
      version = ">= 4.77.0, < 5.0.0"
    }
  }
}
