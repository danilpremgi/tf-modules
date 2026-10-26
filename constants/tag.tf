output "tags" {
  description = "Tags applied to every resource. Callers merge their own tags on top."
  value = {
    "ManagedWith" = "Terraform"
  }
}
