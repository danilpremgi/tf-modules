terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Same range as the storage account and VM modules, so all can sit in one root module.
      version = ">= 4.77.0, < 5.0.0"
    }
  }
}
