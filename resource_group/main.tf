module "constants" {
  source = "../constants"
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.rg_name}-${module.constants.region_codes[var.location]}-${format("%03d", var.instance_number)}"
  location = var.location
  tags     = merge(module.constants.tags, var.extra_tags)

  lifecycle {
    precondition {
      condition     = contains(keys(module.constants.region_codes), var.location)
      error_message = "location '${var.location}' has no region code. Use a lowercase Azure region name such as uksouth, or add it to constants/region.tf."
    }
  }
}
