# Azure Resource Group Terraform Module

This module standardizes the provisioning of Azure Resource Groups across the organization. It programmatically enforces enterprise naming conventions (incorporating region short-codes and zero-padded sequence sizing) and merges standard global corporate tags with module-specific custom tags.

## Features

*   **Standardized Naming Structure:** Automatically builds compliant resource group names following a strict pattern.
*   **Dynamic Tag Merging:** Combines centralized organizational constants with localized custom mappings.
*   **Flexible Enforcement:** Provides clear rules on which tags take precedence in case of duplicate keys.

---

## Naming Convention

The resource group name is dynamically assembled using the following standard template:
```hcl
"rg-${var.rg_name}-${module.constants.region_codes[var.location]}-${format("%03d", var.instance_number)}"