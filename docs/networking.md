# Networking guide

This template supports three network postures for the Azure AI Foundry
account it provisions, plus reuse of an existing account. Pick the one
that matches your environment.

| Mode | Public traffic | Best for |
| --- | --- | --- |
| `none` (default) | Account is publicly reachable from anywhere. | Local dev, demos, getting started fast. |
| `managed` | Microsoft-managed network isolation; no customer VNet. | You want Microsoft to handle isolation without managing your own VNet. |
| `byo-vnet` | Customer-supplied VNet with a delegated agent subnet and a private endpoint on the account. | Enterprise / hub-spoke topologies; you need traffic to stay inside your VNet. |

You can also point the template at an **existing Foundry account** (with
or without a VNet) and have it provision a new project on top.

All of these options are opt-in via environment variables. The default
flow (`azd init` -> `azd up`) gives you the public `none` mode, unchanged.

## How it works

The template's Bicep params are bound to environment variables in
`infra/main.parameters.json`. To opt into any of the modes below:

1. Run `azd init -t Azure-Samples/azd-ai-starter-basic` (or
   `azd ai agent init`).
2. Run one or more `azd env set NAME VALUE` commands listed in the recipe
   for your scenario.
3. Run `azd provision` (or `azd up`).

If you change network mode after a first deploy, run `azd provision`
again. Going from `none` -> `byo-vnet` adds a VNet, subnets, private
endpoint, and DNS zones; going the other way removes them.

## Recipe: Microsoft-managed network

One env var:

```bash
azd env set FOUNDRY_NETWORK_MODE managed
azd provision
```

The account is provisioned with `networkInjections.useMicrosoftManagedNetwork = true`.
No customer VNet is created. Microsoft handles isolation.

## Recipe: Bring your own VNet (new VNet, default subnets)

Two env vars: the mode, and your dev machine's public IP so the data
plane (e.g. `azd deploy`, `azd ai agent invoke`) keeps working from your
laptop.

Linux / macOS / WSL:

```bash
# 1. Fetch your public IP. Pick any reliable echo service.
MY_IP=$(curl -s https://api.ipify.org)

# 2. Set env vars.
azd env set FOUNDRY_NETWORK_MODE byo-vnet
azd env set FOUNDRY_CLIENT_IP_ALLOW_LIST "[\"$MY_IP\"]"

# 3. Provision.
azd provision
```

Windows PowerShell:

```powershell
$myIp = (Invoke-RestMethod https://api.ipify.org)
azd env set FOUNDRY_NETWORK_MODE byo-vnet
azd env set FOUNDRY_CLIENT_IP_ALLOW_LIST "[`"$myIp`"]"
azd provision
```

This creates a new VNet `vnet-<env-name>` in the deployment resource
group with two subnets:

* `agent-subnet` (192.168.0.0/24) -- delegated to
  `Microsoft.App/environments` for the hosted agent runtime.
* `pe-subnet` (192.168.1.0/24) -- holds the private endpoint for the
  Foundry account.

It also creates a private endpoint on the account and three private DNS
zones (`privatelink.services.ai.azure.com`,
`privatelink.openai.azure.com`, `privatelink.cognitiveservices.azure.com`)
linked to the VNet.

Public access stays Enabled with a Deny ACL + AzureServices bypass + your
IP allow-list, so the Foundry control plane (which lives outside the
VNet) and your laptop both keep working.

### Customizing the VNet and subnets

Override any of these only if the defaults collide with another network
you peer with:

```bash
azd env set FOUNDRY_VNET_NAME my-vnet
azd env set FOUNDRY_VNET_ADDRESS_PREFIX 10.20.0.0/16
azd env set FOUNDRY_AGENT_SUBNET_NAME agents
azd env set FOUNDRY_AGENT_SUBNET_PREFIX 10.20.0.0/24
azd env set FOUNDRY_PE_SUBNET_NAME private-endpoints
azd env set FOUNDRY_PE_SUBNET_PREFIX 10.20.1.0/24
```

### Fully private (no public path)

If your dev machine is inside the VNet (via VPN, ExpressRoute, or a
bastion VM), you can drop public access entirely:

```bash
azd env set FOUNDRY_DISABLE_PUBLIC_NETWORK_ACCESS true
azd provision
```

Do not set this from a laptop that only has internet access -- you will
lose the ability to reach the Foundry control plane from your dev
environment.

## Recipe: Bring your own VNet (existing VNet)

Three env vars: mode, VNet ARM ID, IP allow-list.

```bash
# Linux / macOS / WSL
azd env set FOUNDRY_NETWORK_MODE byo-vnet
azd env set FOUNDRY_VNET_RESOURCE_ID /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>
azd env set FOUNDRY_CLIENT_IP_ALLOW_LIST "[\"$(curl -s https://api.ipify.org)\"]"
azd provision
```

```powershell
# Windows PowerShell
azd env set FOUNDRY_NETWORK_MODE byo-vnet
azd env set FOUNDRY_VNET_RESOURCE_ID /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>
$myIp = (Invoke-RestMethod https://api.ipify.org)
azd env set FOUNDRY_CLIENT_IP_ALLOW_LIST "[`"$myIp`"]"
azd provision
```

Cross-RG and cross-subscription references work. The template does NOT
mutate the existing VNet -- it only reads it. The two subnets must
already exist on the VNet:

* The agent subnet must be **delegated to
  `Microsoft.App/environments`** (Bicep cannot retroactively add the
  delegation on a referenced subnet).
* The private endpoint subnet must allow private endpoints (no policies
  blocking them).

By default the template looks for subnets named `agent-subnet` and
`pe-subnet`. Override with `FOUNDRY_AGENT_SUBNET_NAME` /
`FOUNDRY_PE_SUBNET_NAME` if your subnets are named differently.

Region matters: the Foundry account is created in
`AZURE_AI_DEPLOYMENTS_LOCATION` (or `AZURE_LOCATION` if not set). If the
VNet lives in a different region, set `AZURE_AI_DEPLOYMENTS_LOCATION` to
match the VNet's region.

## Recipe: Allowlist your dev IP

If `azd ai agent invoke` or `azd deploy` starts failing with 403s or
hangs, your public IP probably rotated. Re-fetch and re-set:

```bash
# Linux / macOS / WSL
azd env set FOUNDRY_CLIENT_IP_ALLOW_LIST "[\"$(curl -s https://api.ipify.org)\"]"
azd provision
```

```powershell
# Windows PowerShell
$myIp = (Invoke-RestMethod https://api.ipify.org)
azd env set FOUNDRY_CLIENT_IP_ALLOW_LIST "[`"$myIp`"]"
azd provision
```

The JSON-array value supports multiple IPs and CIDR ranges:

```bash
azd env set FOUNDRY_CLIENT_IP_ALLOW_LIST '["203.0.113.45","203.0.113.0/24"]'
```

You can also update the account's network ACL out of band without
re-running `azd provision`:

```bash
az cognitiveservices account network-rule add \
    --name <foundry-account-name> \
    --resource-group <rg> \
    --ip-address <your-ip>
```

The change takes effect immediately. `azd provision` will reconcile back
to whatever `FOUNDRY_CLIENT_IP_ALLOW_LIST` contains the next time it
runs, so keep the env var in sync if you want the change to stick.

## Recipe: Reuse an existing Foundry account

Use this when you have a pre-existing Foundry account (created out of
band or by another team) and you want to provision a new project on top
of it.

```bash
azd env set USE_EXISTING_AI_ACCOUNT true
azd env set AZURE_EXISTING_AI_ACCOUNT_RESOURCE_ID /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<account>
azd provision
```

Constraints:

* The account must live in the **same resource group** as this
  deployment.
* The template creates a new project, the project's capability host, and
  any requested model deployments / connections on the existing account.
  It does NOT change the account's network configuration.
* If the existing account is in BYO VNet mode, also set
  `FOUNDRY_NETWORK_MODE=byo-vnet` and the matching VNet params so the
  new project's hosted agent runtime is wired to the same agent subnet.

This pairs naturally with all the network modes above.

## Recipe (advanced): Reuse existing private DNS zones (hub-spoke)

In hub-spoke topologies the private DNS zones for AI services typically
live in a hub subscription / resource group, not the spoke. Point the
template at them so it doesn't try to create duplicates.

The value is a JSON map from zone FQDN to the resource group that holds
the zone. Empty value for a zone means "create a new one in the spoke
RG" (the default).

```bash
azd env set FOUNDRY_EXISTING_DNS_ZONES '{"privatelink.services.ai.azure.com":"hub-dns-rg","privatelink.openai.azure.com":"hub-dns-rg","privatelink.cognitiveservices.azure.com":"hub-dns-rg"}'

# If the zones live in a different subscription:
azd env set FOUNDRY_DNS_ZONES_SUBSCRIPTION_ID <hub-sub-id>

azd provision
```

When you reuse existing zones, the template assumes the hub team has
already linked them to the spoke VNet (the typical hub-spoke pattern).
The template only creates VNet links for zones it creates itself.

## Verifying

After `azd provision`, check the env vars set by the template:

```bash
# Linux / macOS / WSL
azd env get-values | grep -E '^(FOUNDRY_NETWORK_MODE|AZURE_VNET|AZURE_AGENT_SUBNET|AZURE_PE_SUBNET)='
```

```powershell
# Windows PowerShell
azd env get-values | Select-String -Pattern '^(FOUNDRY_NETWORK_MODE|AZURE_VNET|AZURE_AGENT_SUBNET|AZURE_PE_SUBNET)='
```

You should see:

* `FOUNDRY_NETWORK_MODE` -- the mode you picked.
* `AZURE_VNET_ID` / `AZURE_VNET_NAME` -- the VNet (empty for `none` and
  `managed`).
* `AZURE_AGENT_SUBNET_ID` / `AZURE_PE_SUBNET_ID` -- the subnet ARM IDs
  (empty for `none` and `managed`).

Quick DNS sanity check from a peered or in-VNet host:

```bash
nslookup <account-name>.services.ai.azure.com
# Should resolve to a 10.x or 192.168.x address (the private endpoint),
# not a public IP.
```

## Troubleshooting

**Symptom: `azd ai agent invoke` returns 403 with "Client IP X.Y.Z.W is
not allowed".**

Your dev machine's public IP is not in
`FOUNDRY_CLIENT_IP_ALLOW_LIST`. See the allow-list recipe above to
refresh it.

**Symptom: `azd deploy` hangs or fails with TLS / connection timeout to
the account.**

The data plane is unreachable. Either your IP isn't allowlisted, OR
`FOUNDRY_DISABLE_PUBLIC_NETWORK_ACCESS` is `true` and you're outside the
VNet. Re-enable public access (`azd env set
FOUNDRY_DISABLE_PUBLIC_NETWORK_ACCESS false && azd provision`) or move
your dev session into the VNet.

**Symptom: `nslookup` on the privatelink hostname returns a public IP
from inside the VNet.**

The private DNS zone is not linked to your VNet. If you used the default
flow (template-created zones), the link is automatic. If you're reusing
existing zones via `FOUNDRY_EXISTING_DNS_ZONES`, the hub team must have
linked the zones to your spoke VNet.

**Symptom: `azd provision` fails with "subnet must be delegated to
Microsoft.App/environments".**

You pointed `FOUNDRY_VNET_RESOURCE_ID` at an existing VNet whose agent
subnet has no delegation. Add the delegation out of band, then re-run:

```bash
az network vnet subnet update \
    --vnet-name <vnet> --name <agent-subnet> --resource-group <rg> \
    --delegations Microsoft.App/environments
```

**Symptom: Capability host creation fails on a BYO VNet deploy.**

The capability host is created with `enablePublicHostingEnvironment =
false` for `byo-vnet` and `managed` modes. If the deploy fails here,
double-check that the agent subnet is delegated correctly and that the
Foundry account's `networkInjections.agent.subnetArmId` matches the
agent subnet's ARM ID (you can verify via the portal: Foundry account
-> Networking -> Network Injection).
