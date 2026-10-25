```
module "dns_rg" {
  source = "./modules/resource_group"

  rg_name  = "dns"
  location = "uksouth"
  extra_tags = {
    "ExtraTest" = "Test"
  }
}
```