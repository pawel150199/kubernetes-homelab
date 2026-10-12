# Infrastructure for Kubernetes Homelab

Everything the Kubernetes homelab runs on lives in Hetzner Cloud and is
provisioned by Terraform. The cluster is built by the
[`hcloud-k8s-cluster`](https://github.com/pawel150199/hcloud-k8s-cluster) module
(pinned to `0.1.20`), which installs **k3s** on the nodes through cloud-init.
Only the Terraform state lives elsewhere — in an AWS S3 bucket, because Hetzner
has no native state backend.

## What this creates

| Resource | Value |
| --- | --- |
| Control plane | 1 × `cx23`, `ubuntu-26.04`, `hel1` |
| Workers | 1 × `cx23`, `ubuntu-26.04`, `hel1` |
| Networking | private network `10.0.0.0/16`, subnet `10.0.1.0/24` |
| Placement group | on — spreads nodes over separate physical hosts |
| Kubernetes | k3s `v1.36.4+k3s1` (Traefik disabled, klipper ServiceLB active) |
| Public IPs | IPv4 enabled but inbound firewalled to Tailscale (`use_public_ipv4 = true`, `use_public_ipv6 = false`, `ssh_source_ips`/`kube_api_source_ips` limited to `100.64.0.0/10`) |
| Remote access | **Tailscale** on every node (`use_tailscale = true`) |
| SSH keys | the existing Hetzner project key `ppolski` (`ssh_keys`) |

> **Public IPs are enabled for outbound access only.** The Hetzner firewalls are
> restricted to the Tailscale CGNAT range (`100.64.0.0/10`), so no inbound
> connections from the public internet are allowed. The nodes are reachable only
> over the tailnet (`master-node-0`, `worker-node-0`). Every `ssh` / `scp` /
> `kubectl` step below goes through Tailscale. See
> [Connect to the Kubernetes cluster](#connect-to-the-kubernetes-cluster).

## How to run this terraform code

### Prerequisites

Install:

- [Terraform](https://developer.hashicorp.com/terraform) ≥ 1.15.0
- [AWS CLI](https://aws.amazon.com/cli/) — for the S3 state bucket
- [Tailscale](https://tailscale.com/download) and `kubectl` — to reach the
  cluster once it is up

Prepare:

- An AWS S3 bucket for the Terraform state (created below).
- A Hetzner Cloud API token with **read & write** permissions.
- A Tailscale **auth key** — the nodes use it to join your tailnet. Generate an
  *ephemeral, pre-approved* key with a short expiry in the Tailscale admin
  console (**Settings → Keys**).
- The SSH key **`ppolski`** already present in the Hetzner project. That is the
  `ssh_keys` entry in `main.tf`; see the module's
  [SSH key model](https://github.com/pawel150199/hcloud-k8s-cluster/blob/master/docs/02-architecture.md#25-ssh-key-model).

### Create the S3 state bucket

Hetzner has no state backend of its own, so the state is kept in AWS S3. The
bucket name is globally unique and its region must match the backend block in
`versions.tf` (`eu-central-1`), which is why `LocationConstraint` is passed
explicitly for anything outside `us-east-1`. Versioning keeps a recoverable copy
of every state revision:

```bash
export AWS_REGION="eu-central-1"

aws s3api create-bucket \
  --bucket kubernetes-homelab-tfstate \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"

aws s3api put-bucket-versioning \
  --bucket kubernetes-homelab-tfstate \
  --versioning-configuration Status=Enabled
```

`versions.tf` uses `use_lockfile = true`, so locking is done with a lock object
in the same bucket — no DynamoDB table to manage (needs Terraform ≥ 1.10).

> **The state is a secret.** It holds `tailscale_auth_key`, the generated worker
> private key and the k3s join token in clear text. Keep the bucket private,
> keep versioning on, and restrict who can read it.

### Environment variables

Secrets are conventionally passed to Terraform through the environment rather
than committed to a `.tfvars` file:

| Variable | Read by | Purpose |
| --- | --- | --- |
| `HCLOUD_TOKEN` | the `hcloud` provider | Hetzner Cloud API token |
| `TF_VAR_tailscale_auth_key` | `variables.tf` → module | Tailscale auth key; required because `use_tailscale = true` |
| `AWS_ACCESS_KEY_ID` | the `s3` backend | AWS access key for the state bucket |
| `AWS_SECRET_ACCESS_KEY` | the `s3` backend | AWS secret access key |
| `AWS_REGION` | the `s3` backend | Region of the state bucket (`eu-central-1`) |

```bash
export HCLOUD_TOKEN="your_hetzner_api_token"
export TF_VAR_tailscale_auth_key="tskey-auth-…"
export AWS_ACCESS_KEY_ID="AKIA…"
export AWS_SECRET_ACCESS_KEY="…"
export AWS_REGION="eu-central-1"
```

Alternatively, configure the AWS CLI with a named profile and export
`AWS_PROFILE=private` instead of the two access-key variables.

> **`TF_VAR_*` and child modules.** Terraform's `TF_VAR_` variables set inputs on
> the **root** module only. `TF_VAR_tailscale_auth_key` reaches
> `hcloud-k8s-cluster` because `infrastructure/variables.tf` declares
> `tailscale_auth_key` and `main.tf` passes it down. The variable is `sensitive`,
> so Terraform keeps it out of the plan output.

### Run the terraform code

1. Initialize the terraform configuration:

   ```bash
   terraform init
   ```

2. Review the terraform plan:

   ```bash
   terraform plan
   ```

3. Apply the terraform configuration:

   ```bash
   terraform apply
   ```

`apply` returns once the servers exist, but **k3s keeps bootstrapping in the
background** via cloud-init — allow a few minutes before the API server and the
worker are Ready. Track progress from the master:

```bash
ssh cluster@master-node-0
sudo journalctl -u k3s -f
sudo kubectl get nodes -o wide
```

## Connect to the Kubernetes cluster

The nodes have no public IP addresses, so `terraform output` for the node IPs
comes back empty:

```bash
terraform output master_nodes_public_ips
# tolist([ "" ])
```

Read the node addresses from the tailnet instead, and log in as the `cluster`
user (passwordless `sudo`; `root` and password logins are refused by the
module's SSH hardening):

```bash
tailscale status | grep -E 'master-node|worker-node'
ssh cluster@master-node-0            # Tailscale SSH
```

Copy the kubeconfig off the master and repoint it at the node's tailnet name:

```bash
scp cluster@master-node-0:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# The kubeconfig points at 127.0.0.1 — repoint it at the node's tailnet address:
sed -i '' "s/127.0.0.1/master-node-0.<tailnet>.ts.net/" ~/.kube/config   # macOS sed

kubectl get nodes
```

> **The address must be on the API server certificate.** The masters' private
> IPs are added automatically, but a Tailscale address is not — it has to be
> listed in `extra_tls_sans` **before** the apply, otherwise `kubectl` fails the
> TLS handshake on a name mismatch:
>
> ```hcl
> extra_tls_sans = ["master-node-0.<tailnet>.ts.net"]
> ```
>
> Changing `extra_tls_sans` alters cloud-init `user_data`, which **recreates the
> servers**. Add the SAN before the first apply, or plan for a rebuild.
>
> **TODO:** `main.tf` does not set `extra_tls_sans` yet. Until it does, a
> kubeconfig pointed at the tailnet name will not pass TLS verification.

## Automatic GitHub Actions Integration

### Prerequisites for GitHub Actions Integration

To integrate GitHub Actions you have to add secrets in your repository
(**Settings → Secrets and variables → Actions**):

- `AWS_ACCESS_KEY_ID` - Your AWS access key ID
- `AWS_SECRET_ACCESS_KEY` - Your AWS secret access key
- `HCLOUD_TOKEN` - Your Hetzner API token
- `TAILSCALE_AUTH_KEY` - Your Tailscale auth key (exported as
  `TF_VAR_tailscale_auth_key` in the pipeline)

You also have to create the S3 bucket in AWS for storing terraform state, as
described in the manual steps above.

## GitHub Actions Integration

The GitHub Actions integration has been set up to automatically apply the
terraform configuration whenever changes are pushed to the repository.
There is also the possibility to manually trigger runs from the GitHub Actions
tab.

Automatic runs are triggered on every push to the master branch in the path
`infrastructure/`.

This automatic pipeline has 3 jobs defined: `dry-run-deploy`,
`wait-for-approval`, and `deploy`.

> **Note:** The `wait-for-approval` job requires manual approval before the
> `deploy` job is executed.

> **Note:** Concurrency in the GitHub Actions pipeline is managed to ensure that
> only one deployment runs at a time.

Both the `dry-run-deploy` and `deploy` jobs export `HCLOUD_TOKEN` and
`TF_VAR_tailscale_auth_key` from the repository secrets.
