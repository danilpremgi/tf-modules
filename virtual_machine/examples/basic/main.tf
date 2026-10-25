# Minimal call: a private Ubuntu 24.04 VM (Virtual Machine) with Trusted Launch
# and platform patching. The generated SSH (Secure Shell) private key is written
# to Key Vault. Switch os_type to "Windows" for a Windows Server 2025 VM with a
# generated password instead.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.77.0, < 5.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "example" {
  name     = "rg-vm-basic-example"
  location = "uksouth"
}

resource "azurerm_virtual_network" "example" {
  name                = "vnet-vm-basic-example"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  address_space       = ["10.30.0.0/16"]
}

resource "azurerm_subnet" "vms" {
  name                 = "snet-vms"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.30.1.0/24"]
}

resource "azurerm_key_vault" "example" {
  name                       = "kv-vmbasic-example-001"
  location                   = azurerm_resource_group.example.location
  resource_group_name        = azurerm_resource_group.example.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
}

# Lets whoever runs Terraform write the generated credential.
resource "azurerm_role_assignment" "deployer_secrets" {
  scope                = azurerm_key_vault.example.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

module "vm" {
  source = "../.."

  os_type             = "Linux"
  name                = "vm-app-dev-01"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  zone                = "1"
  subnet_id           = azurerm_subnet.vms.id

  admin_credentials_key_vault_id = azurerm_key_vault.example.id

  depends_on = [azurerm_role_assignment.deployer_secrets]
}

output "vm" {
  value = {
    id                 = module.vm.id
    private_ip_address = module.vm.private_ip_address
    credential_secret  = module.vm.admin_credentials_secret_id
  }
}
