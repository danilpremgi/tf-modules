# terraform-azurerm-nat-gateway

Terraform module that creates one Azure NAT (Network Address Translation) gateway and its outbound
public IPs and/or public IP prefix. Attach it to subnets with the vnet module's
`subnet_nat_gateway_ids`.

- **Provider:** AzureRM (Azure Resource Manager) `>= 4.77.0, < 5.0.0`
- **Terraform:** `>= 1.5.0`

## Why you need one

For API versions released after 31 March 2026, subnets in new VNets (Virtual Networks) are
private: VMs (Virtual Machines) get no default outbound internet access. The vnet module also makes
subnets private by default. Without an explicit outbound method, VMs can't reach the internet,
Windows Update or Windows activation.

NAT Gateway is Microsoft's recommended outbound method for most subnets. In a hub-and-spoke
network where spokes route `0.0.0.0/0` to Azure Firewall, the spokes don't need one. You can put a
NAT gateway on `AzureFirewallSubnet` instead, for more SNAT (Source NAT) ports.

## Usage

```hcl
module "nat" {
  source = "./modules/nat_gateway"

  name                = "ng-app-prod-uks-001"
  resource_group_name = "rg-network-prod"
  location            = "uksouth"
}

module "vnet" {
  source = "./modules/vnet"
  # ...
  subnet_nat_gateway_ids = {
    "snet-app" = module.nat.id
  }
}
```

Examples:
- [`examples/basic`](examples/basic/main.tf): StandardV2 gateway with one public IP on a private subnet.
- [`examples/complete`](examples/complete/main.tf): a StandardV2 gateway with a prefix shared by two subnets, and a zonal Standard gateway.

## SKUs

| | `StandardV2` (default) | `Standard` |
|---|---|---|
| Zones | Zone-redundant, always | One zone or no zone |
| Public IPs and prefixes | Must be `StandardV2` | Must be `Standard` |
| Throughput | 100 Gbps | 50 Gbps |
| IPv6, flow logs | Yes | No |
| Price | Same | Same |

The module sets the public IP and prefix SKU from `sku_name`. You can't upgrade Standard to
StandardV2 in place: changing `sku_name` replaces the gateway and its IPs, so your outbound
addresses change.

StandardV2 isn't available in Canada East, India South Central, Sweden South or West India. Use
`Standard` there.

## Inputs

### Required

| Name | Description |
|---|---|
| `name` | NAT gateway name. Public IPs are named `pip-<name>-01`, `-02` and so on; the prefix `ippre-<name>` |
| `resource_group_name`, `location` | Where to create everything |

### Optional

| Name | Default | Description |
|---|---|---|
| `sku_name` | `StandardV2` | `Standard` or `StandardV2` |
| `zones` | `null` | Standard: `null` or one zone. StandardV2: public IP zones, `null` means `["1", "2", "3"]`; use `[]` in regions without zones |
| `idle_timeout_in_minutes` | `4` | TCP idle timeout, 4-120 |
| `public_ip_count` | `1` | Public IPs to create, 0-16. Each adds 64,512 SNAT ports |
| `public_ip_prefix_length` | `null` | Create a prefix of /28-/31 for a contiguous range to allowlist |
| `existing_public_ip_ids` | `{}` | Map of label => public IP ID created elsewhere |
| `existing_public_ip_prefix_ids` | `{}` | Map of label => public IP prefix ID created elsewhere |
| `tags` | `{}` | Applied to every resource |

## Outputs

| Name | Description |
|---|---|
| `id`, `name`, `sku_name` | |
| `public_ip_ids` | Map of created public IP IDs, keyed `01`, `02` and so on |
| `public_ip_addresses` | Created outbound addresses, for allowlisting |
| `public_ip_prefix`, `public_ip_prefix_id` | Created prefix CIDR and ID, or `null` |

## Gotchas

- **One NAT gateway per subnet**, and one VNet per NAT gateway. Many subnets in the same VNet can
  share one.
- **Not supported on `GatewaySubnet`** or subnets with SQL Managed Instance. The vnet module stops
  the plan for `GatewaySubnet`.
- **NAT Gateway beats other outbound methods** (load balancer outbound rules, VM public IPs,
  Azure Firewall without a route). A route table sending `0.0.0.0/0` to a firewall or VPN gateway
  overrides it.
- **16 IPv4 addresses maximum** across created IPs and the created prefix; the module checks this.
- **Basic SKU resources** (Basic load balancer or public IP) in the subnet aren't compatible.
- **Existing VMs** must be stopped and deallocated before a subnet's private setting takes effect
  on their NICs (Network Interface Cards).
