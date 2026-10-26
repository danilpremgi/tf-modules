# Writing a Terraform Module

A walkthrough of how to write a Terraform module, built around a new **network security group (NSG)** module for this repo. Each section explains why each piece of code is there, not just what it does.

The `nat_gateway` module in this repo already follows these practices. The `resource_group` module is used for contrast.

---

## 1. What a module actually is

**Any folder of `.tf` files is a module.** Terraform reads every `.tf` file in a folder and treats them as one unit, so the file names don't matter to Terraform. They're for people.

- **Root module:** the folder you run `terraform plan` in. In this repo, that's the repo root, with `main.tf` and `01-providers.tf`.
- **Child module:** a folder that another module calls with a `module "x" { source = ... }` block, like `modules/nat_gateway`.

A module works a lot like a **function**:

| Function concept | Terraform equivalent | File by convention |
|---|---|---|
| Parameters | `variable` blocks | `variables.tf` |
| Body | `resource`, `data`, `locals` | `main.tf` |
| Return values | `output` blocks | `outputs.tf` |
| Dependencies / runtime | `terraform { required_providers }` | `versions.tf` |

Everything below builds on that comparison.

## 2. Folder layout

```
modules/network_security_group/
├── versions.tf     # what Terraform/provider versions this works with
├── variables.tf    # the inputs (the module's public API)
├── main.tf         # the resources
├── outputs.tf      # what callers get back
├── README.md       # how to use it
└── examples/
    ├── basic/main.tf      # smallest working call
    └── complete/main.tf   # every option exercised
```

**Why split files?** Terraform doesn't care. Splitting them lets a reader open `variables.tf` and see the module's whole interface without reading the implementation, the same way you'd read a function signature.

---

## 3. `versions.tf`: declare requirements, don't configure them

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0.0, < 5.0.0"
    }
  }
}
```

**Why each part:**

- `required_version`: the oldest Terraform that supports the features you use. This module uses `optional()` in object types (Terraform 1.3+), so `>= 1.5.0` is safe.
- `required_providers`: says *which* provider and *which versions* the module was written against. `source` matters because without it Terraform assumes `hashicorp/<name>`, which is wrong for third-party providers.
- **A range, not a pin.** Modules use a minimum and a maximum (`>= 4.0.0, < 5.0.0`). The root module, in `01-providers.tf`, picks the exact version. If every module pinned an exact version, two modules could never sit in the same root. The comment in `nat_gateway/versions.tf`, "Same range as the other modules", already captures this.

**What's deliberately missing: a `provider "azurerm" {}` block.** Child modules should **never** configure providers (credentials, `features {}`, `use_oidc`). They inherit the provider from the caller. There are three reasons:

1. The caller decides the subscription and authentication, not the module.
2. A module that contains a provider block can't be used with `count` or `for_each`.
3. You can't cleanly delete a module that contains a provider block, because Terraform needs that provider to destroy the module's resources.

> The `resource_group` module has no `versions.tf`. It still works because it inherits from the root, but adding one documents the module's requirements and protects it if someone calls it from a root that uses a different version.

---

## 4. `variables.tf`: the public API

This is the most important file. Good inputs make a module pleasant to use; bad ones make it a leaky wrapper.

```hcl
###############################################################################
# Core
###############################################################################

variable "name" {
  description = "Name of the network security group."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,78}[A-Za-z0-9_]$", var.name))
    error_message = "name must be 2-80 characters: letters, numbers, '.', '_' or '-', starting with a letter or number and ending with a letter, number or '_'."
  }
}

variable "resource_group_name" {
  description = "Resource group for the NSG."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource the module creates."
  type        = map(string)
  default     = {}
}

###############################################################################
# Rules
###############################################################################

variable "rules" {
  description = "Security rules, keyed by rule name."
  type = map(object({
    priority                = number
    direction               = string
    access                  = optional(string, "Allow")
    protocol                = optional(string, "Tcp")
    source_address_prefix   = optional(string, "*")
    destination_port_ranges = optional(list(string), ["*"])
    description             = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for r in var.rules : r.priority >= 100 && r.priority <= 4096])
    error_message = "Every rule priority must be between 100 and 4096."
  }

  validation {
    condition     = alltrue([for r in var.rules : contains(["Inbound", "Outbound"], r.direction)])
    error_message = "direction must be Inbound or Outbound."
  }
}

###############################################################################
# Associations
###############################################################################

variable "subnet_ids" {
  description = "Subnets to attach the NSG to, keyed by a label you choose (e.g. the subnet's short name)."
  type        = map(string)
  default     = {}
}
```

**Why each component:**

- **`description`**: shows up in docs generators and in editor hover. Write it for someone who has never opened `main.tf`.
- **`type`**: catches mistakes at plan time ("expected string, got list") instead of halfway through an apply against Azure. Always set it.
- **`default`**: a variable with no default is **required**, and one with a default is **optional**. Make `name`, `location` and `resource_group_name` required, because the module can't guess them. Give everything else a sensible default so the basic call stays short.
- **`validation`**: fails fast with *your* error message, not a cryptic Azure API error 40 seconds into an apply. Put Azure's rules (name formats, value ranges, allowed values) here.
- **`map(object({...}))` with `optional()`**: callers pass rich structured data, but only the fields they care about. `optional(string, "Allow")` means "if omitted, use `Allow`". Without `optional()`, every caller would have to spell out every field of every rule.
- **Why a `map`, not a `list`, for `rules` and `subnet_ids`?** It comes down to `for_each` keys, which section 5 explains. The NAT module's `existing_public_ip_ids` is a map for the same reason.

**Design rule:** expose what callers *need to vary*, and hard-code what they shouldn't. For example, there's no `source_port_range` variable, because it's almost always `*` and exposing it is noise.

---

## 5. `main.tf`: the implementation

```hcl
resource "azurerm_network_security_group" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

###############################################################################
# Rules
###############################################################################

resource "azurerm_network_security_rule" "this" {
  for_each = var.rules

  name                        = each.key
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.this.name

  priority                   = each.value.priority
  direction                  = each.value.direction
  access                     = each.value.access
  protocol                   = each.value.protocol
  source_port_range          = "*"
  source_address_prefix      = each.value.source_address_prefix
  destination_port_ranges    = each.value.destination_port_ranges
  destination_address_prefix = "*"
  description                = each.value.description
}

###############################################################################
# Subnet associations
###############################################################################

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = var.subnet_ids

  subnet_id                 = each.value
  network_security_group_id = azurerm_network_security_group.this.id
}
```

**Why each component:**

- **The name `"this"`**: when a module has one main resource of a type, calling it `this` is the common convention, and `azurerm_network_security_group.this` reads naturally. The newer modules in this repo do this; `resource_group` uses `"rg"`, which works but repeats information the type already gives.
- **References create the dependency graph.** `azurerm_network_security_group.this.name` inside the rule tells Terraform "create the NSG first". You almost never need `depends_on`, because references already set the order.
- **`for_each` over a map** creates one resource per key, addressed like `azurerm_network_security_rule.this["allow-https"]`.
  - **Why not `count`?** `count` addresses resources by position (`[0]`, `[1]`, `[2]`). Delete the first item in a list and everything after it shifts, so Terraform destroys and recreates resources that didn't change. Map keys are stable, so removing `"allow-ssh"` touches only that rule.
  - **Use `count` only for on/off switches**, like the NAT module's `count = var.public_ip_prefix_length == null ? 0 : 1`.
  - **Keys must be known at plan time.** That's why `subnet_ids` is keyed by a label you choose and not by the subnet ID itself: the IDs don't exist until after apply. Values can be unknown; keys can't.
- **`each.key` / `each.value`**: the current map key and its object.
- **Separate rule resources vs. inline `security_rule {}` blocks:** the NSG resource also accepts inline rules, often generated with a `dynamic "security_rule"` block. Pick one style and **never mix them**: inline rules make Terraform own the whole rule set, so the two styles fight and each plan reverts the other's changes. Separate resources let other modules add rules to the same NSG later.
- **`locals`** (not needed here, but see `nat_gateway/main.tf`): named intermediate values. Use them when an expression is used more than once or needs a name to be understood, like `local.is_v2`.
- **`lifecycle { precondition }`** (also in the NAT module): checks that involve *several* variables at once, which a single variable's `validation` can't easily do.

---

## 6. `outputs.tf`: what callers get back

```hcl
output "id" {
  description = "Resource ID of the NSG."
  value       = azurerm_network_security_group.this.id
}

output "name" {
  description = "Name of the NSG. Pass to other modules that add their own rules."
  value       = azurerm_network_security_group.this.name
}

output "rule_ids" {
  description = "IDs of the rules the module created, keyed by rule name."
  value       = { for k, r in azurerm_network_security_rule.this : k => r.id }
}
```

**Why each component:**

- **A module's resources are private.** The caller *cannot* write `module.web_nsg.azurerm_network_security_group.this.id`; outputs are the only way out. If you don't output it, it's inaccessible.
- **Output IDs and names generously.** IDs are what other resources consume. The `resource_group` module outputs only `rg_name`, so anything that needs the resource group's ID (role assignments, policy) is stuck. Adding an `id` output would fix that.
- **Return maps with the same keys as the input**, so callers can look things up: `module.web_nsg.rule_ids["allow-https"]`.
- **`for` expressions** reshape resource objects into clean data, which hides the module's internals from the caller.

---

## 7. Calling the module from the root `main.tf`

```hcl
module "web_nsg" {
  source = "./modules/network_security_group"

  name                = "nsg-web-${local.network_suffix}"
  resource_group_name = module.vm_rg.rg_name
  location            = local.network_location
  tags                = module.constants.tags

  rules = {
    "allow-https-inbound" = {
      priority                = 100
      direction               = "Inbound"
      destination_port_ranges = ["443"]
      source_address_prefix   = "Internet"
    }
  }

  subnet_ids = {
    "snet-web" = module.vm_network.subnet_ids["snet-web"] # whatever the vnet module outputs
  }
}
```

**Why each part:**

- **`source`** says where the module code lives. A local path (`./...`) is read straight from disk. Git sources (`git::https://github.com/you/repo.git//modules/x?ref=v1.0.0`) and registry sources (`Azure/avm-res-.../azurerm`) are downloaded during `terraform init`.
- **Chaining outputs to inputs** (`module.vm_rg.rg_name`) is how modules compose, and it also builds the dependency graph between modules.
- **Shared tags are applied here, in the root.** The child modules don't call `constants` themselves, so each one stays standalone and can be copied or published on its own. Pass `module.constants.tags` to every module, merging in your own with `merge(module.constants.tags, { role = "web" })`. azurerm has no provider-level `default_tags`, so this is the one place that keeps `ManagedWith` consistent.
- Notice how little you had to type for that rule. That's what the `optional()` defaults buy you.

> ⚠️ **`?ref=` only works with git sources.** A local path like `"./modules/virtual_machine?ref=modules/vm/v1.0.0"` makes Terraform look for a folder literally named `virtual_machine?ref=modules/vm/v1.0.0`, so `init` fails. Use `"./modules/virtual_machine"`, or a full `git::https://github.com/...//modules/virtual_machine?ref=modules/vm/v1.0.0` URL if you want version pinning.

---

## 8. Examples, README, and testing

- **`examples/basic`** shows the minimum required inputs, and **`examples/complete`** shows every feature. They're documentation that `terraform validate` can check, so they can't silently go stale the way a README snippet can.
- **README**: what the module does, an example call, and the inputs and outputs table. [`terraform-docs`](https://terraform-docs.io) can generate that table from your `description` fields, which is another reason to write good ones.
- **Workflow while developing:**

  ```bash
  terraform fmt -recursive   # canonical formatting (CI already does this)
  terraform init             # fetch providers/modules
  terraform validate         # types, references, syntax
  terraform plan             # see what it *would* do
  ```

- **`terraform test`** (Terraform 1.6+): put `*.tftest.hcl` files in a `tests/` folder to assert things like "an invalid priority is rejected" or "two rules produce two resources", usually with `command = plan` so nothing gets deployed.

---

## 9. Design checklist

1. **One purpose per module.** An NSG module manages NSGs; it doesn't also create the VNet.
2. **Required inputs = only what the module can't guess.** Everything else gets a sensible default.
3. **Every variable and output has a `description` and a `type`.**
4. **Validate early** with `validation` and `precondition`, so errors are yours and not Azure's.
5. **Use `for_each` with maps** for collections, and `count` only as a 0/1 toggle.
6. **No provider blocks** in child modules; use version *ranges* in `versions.tf`.
7. **Output IDs and names** of anything a caller might need to reference.
8. **Don't wrap a single resource with no added value.** A module earns its place by encoding decisions, like a naming convention, tags, or the NAT gateway's zone logic. A module that just passes every argument straight through to one resource adds indirection with no benefit.
