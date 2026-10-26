output "region_codes" {
  description = "Short code for each Azure region, keyed by region name (e.g. uksouth => uks). Used in resource names."
  value = {
    # United Kingdom
    "ukwest"  = "ukw"
    "uksouth" = "uks"

    # Europe
    "westeurope"         = "weu"
    "northeurope"        = "neu"
    "francecentral"      = "frc"
    "germanywestcentral" = "gwc"
    "norwayeast"         = "nwe"
    "swedencentral"      = "sdc"
    "switzerlandnorth"   = "szn"

    # North America
    "eastus"         = "eus"
    "eastus2"        = "eus2"
    "westus"         = "wus"
    "westus2"        = "wus2"
    "westus3"        = "wus3"
    "centralus"      = "cus"
    "northcentralus" = "ncus"
    "southcentralus" = "scus"
    "westcentralus"  = "wcus"
    "canadacentral"  = "cac"
    "canadaeast"     = "cae"

    # Asia Pacific
    "australiaeast"      = "aue"
    "australiasoutheast" = "ause"
    "centralindia"       = "cin"
    "southindia"         = "sin"
    "japaneast"          = "jpe"
    "japanwest"          = "jpw"
    "southeastasia"      = "sea"
    "eastasia"           = "eas"
  }
}
