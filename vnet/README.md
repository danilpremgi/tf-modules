# terraform-azurerm-vnet

Terraform module that creates one Azure VNet (Virtual Network) and its subnets. Optionally it
associates an NSG (Network Security Group) and a route table with each subnet. Use one module
block per VNet, for example one for a hub and one per spoke.

- **Provider:** AzureRM (Azure Resource Manager) `>= 4.77.0, < 5.0.0`
- **Terraform:** `>= 1.5.0`

## Usage

```hcl
module "vnet" {
  source = "./modules/vnet"

  name                = "vnet-app-prod-uks-001"
  resource_group_name = "rg-network-prod"
  location            = "uksouth"
  address_space       = ["10.51.0.0/16"]

  subnets = {
    "snet-web"  = { newbits = 8, netnum = 1 }                    # 10.51.1.0/24
    "snet-app"  = { newbits = 8, netnum = 2 }                    # 10.51.2.0/24
    "snet-data" = { address_prefixes = ["10.51.3.0/24"] }        # explicit CIDR also works
    "snet-ase"  = {
      newbits    = 8
      netnum     = 20
      delegation = { service = "Microsoft.Web/hostingEnvironments" }
    }
  }

  subnet_network_security_group_ids = {
    "snet-web" = azurerm_network_security_group.web.id
    "snet-app" = azurerm_network_security_group.app.id
  }
}
```

Reference subnets elsewhere by their key:

```hcl
subnet_id             = module.vnet.subnet_ids["snet-app"]
source_address_prefix = module.vnet.subnet_prefixes["snet-web"]
```

Examples:
- [`examples/basic`](examples/basic/main.tf): three-tier VNet.
- [`examples/complete`](examples/complete/main.tf): hub and spoke from two module blocks, with NSGs, a firewall route table and peering.

## Subnet sizing

From Microsoft's [VNet and subnet design guide](https://learn.microsoft.com/azure/networking/design-guide/vnets-subnets).
Azure reserves 5 addresses in every subnet, so a /24 has 251 usable.

| Service | Minimum size | Required subnet name |
|---|---|---|
| Azure Firewall | /26 | `AzureFirewallSubnet` |
| VPN Gateway | /27 (larger recommended) | `GatewaySubnet` |
| Azure Bastion | /26 | `AzureBastionSubnet` |
| Azure Route Server | /26 | `RouteServerSubnet` |
| Application Gateway v2 | /24 recommended | any |
| App Service Environment | /24 (/23 for maximum scale) | any, delegated to `Microsoft.Web/hostingEnvironments` |
| DNS Private Resolver | /28 per endpoint, separate inbound and outbound | any, delegated to `Microsoft.Network/dnsResolvers` |
| AKS (Azure Kubernetes Service) | depends on CNI (Container Networking Interface); small with CNI Overlay | any |

For the required names, set the map key (or `name`) to the exact name. The module doesn't add
prefixes or suffixes.

## Inputs

### Required

| Name | Description |
|---|---|
| `name` | VNet name |
| `resource_group_name`, `location` | Where to create everything |
| `address_space` | List of CIDR blocks. Subnets using `newbits`/`netnum` are carved from the first |

### Optional

| Name | Default | Description |
|---|---|---|
| `subnets` | `{}` | Map of subnets, see below |
| `subnet_network_security_group_ids` | `{}` | Map of subnet key => NSG ID |
| `subnet_route_table_ids` | `{}` | Map of subnet key => route table ID |
| `subnet_nat_gateway_ids` | `{}` | Map of subnet key => NAT gateway ID, for example from [`modules/nat_gateway`](../nat_gateway/README.md). Not allowed on `GatewaySubnet` |
| `dns_servers` | `[]` | Custom DNS (Domain Name System) servers |
| `tags` | `{}` | Applied to the VNet |

Each `subnets` entry:

| Field | Default | Description |
|---|---|---|
| `address_prefixes` | | Explicit CIDRs. Use this, or `newbits` + `netnum` |
| `newbits`, `netnum` | | Passed to `cidrsubnet(address_space[0], newbits, netnum)` |
| `name` | map key | Subnet name in Azure |
| `service_endpoints` | `[]` | For example `["Microsoft.Storage"]` |
| `private_endpoint_network_policies` | `Disabled` | `Disabled`, `Enabled`, `NetworkSecurityGroupEnabled`, `RouteTableEnabled` |
| `default_outbound_access_enabled` | `false` | Private subnet: VMs need a NAT gateway, firewall route or public IP to reach the internet. Ignored on delegated subnets |
| `delegation` | `null` | `{ service, actions? }` |

NSG, route table and NAT gateway maps are keyed by subnet key rather than set inside each subnet.
That keeps the plan working when they're created in the same run.

## Outbound connectivity

Subnets are private by default, matching Azure's default for VNets created after 31 March 2026.
Give each subnet that needs internet access one explicit outbound method:

- a NAT gateway via `subnet_nat_gateway_ids` (recommended for most subnets)
- a route table sending `0.0.0.0/0` to Azure Firewall or another appliance via `subnet_route_table_ids` (hub and spoke)
- a load balancer with outbound rules, or a public IP on the VM

Delegated subnets are left to the service, so the setting isn't applied to them.

## Outputs

| Name | Description |
|---|---|
| `id`, `name`, `address_space` | |
| `subnets` | Map of `{ id, name, address_prefixes }` keyed by subnet key |
| `subnet_ids` | Map of subnet key => ID |
| `subnet_prefixes` | Map of subnet key => first address prefix, for NSG rules and routes |

## Gotchas

- **Changing a subnet's CIDR or name replaces it**, along with anything deployed into it.
- **Keys in `subnet_network_security_group_ids` and `subnet_route_table_ids`** must exist in
  `subnets`, or the plan fails.
- **Don't attach NSGs or route tables to `GatewaySubnet` or `AzureFirewallSubnet`** unless the
  service supports it. `AzureBastionSubnet` NSGs need Bastion's specific rules.
- **Private endpoints** use IPs from an existing subnet. A dedicated `snet-private-endpoints`
  keeps that consumption predictable.
