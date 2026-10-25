module "constants" {
  source = "../constants"
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.rg_name}-${module.constants.region_codes[var.location]}-${format("%03d", var.instance_number)}"
  location = var.location
  tags     = merge(module.constants.tags, var.extra_tags)
}
