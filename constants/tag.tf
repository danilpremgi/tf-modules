resource "time_static" "rg_creation" {}

output "tags" {
  value = {
    "CreatedBy"   = "Terraform"
    "ManagedWith" = "Terraform"
    "CreatedOn"   = formatdate("DD-MM-YYYY", time_static.rg_creation.rfc3339)
  }
}
