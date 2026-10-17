# Bootstrap Argo CD and the Tailscale operator

Terraform that installs [Argo CD](https://argo-cd.readthedocs.io/) and the
[Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator)
into the Kubernetes homelab cluster. The `../infrastructure`
provisions the cloud + k3s cluster, and `bootstrap/` installs Argo CD and 
Tailscale operator. In the `../gitops` directory. From then on Argo CD reconciles everything inside the
cluster from Git.

CI deployment is handled by `.github/workflows/deploy-bootstrap.yml` (uses
Tailscale OAuth for the runner, writes kubeconfig from `KUBE_CONFIG` secret,
and passes operator OAuth credentials via `TAILSCALE_OAUTH_CLIENT_ID` secret).

## What it does

- creates the `argocd` namespace and installs the official
  [`argo-cd`](https://github.com/argoproj/argo-helm) Helm chart (`10.10.2`) with
  the overrides in `values/argocd.yaml` (liveness probe, metrics, ServiceMonitor,
  server autoscaling);
- creates the `tailscale` namespace and installs the official
  [`tailscale-operator`](https://pkgs.tailscale.com/helmcharts/) Helm chart
  (`1.104.1`), configured with a **Tailscale OAuth client** so the operator can
  provision the proxy nodes and expose Services/Ingresses on the tailnet.

The argocd UI is available using the address in the tailscale network.
It have to be read from tailscale managment console. Then type correct address in browser (remember you have to be in tailscale network). Then you will have to autorise using credentials and managing your's app will be available.

### Kube Config

Copy the kubeconfig using tailscale network (accessing the nodes using public IP can be not possible due the narrow firewall configured).

```bash
scp cluster@master-node-0:/etc/rancher/k3s/k3s.yaml bootstrap/kube-config/config
sed -i '' "s/127.0.0.1/master-node-0.<tailnet>.ts.net/" bootstrap/kube-config/config

kubectl --kubeconfig bootstrap/kube-config/config get nodes
```

## How to run

### Environment variables

The Tailscale operator authenticates with an **OAuth client**, not with the
`tailscale_auth_key` the nodes use to join the tailnet. Pass the client
credentials through the environment (or as `tailscale_oauth_client_id` /
`tailscale_oauth_client_secret` in an ignored `terraform.tfvars`). Both
OAuth clients (one used by nodes/infra and one used by the operator/CI)
are described below:

| Variable | Read by | Purpose |
| --- | --- | --- |
| `TF_VAR_tailscale_oauth_client_id` | `variables.tf` → `helm_release.tailscale` | Tailscale OAuth client ID for the operator |
| `TF_VAR_tailscale_oauth_client_secret` | `variables.tf` → `helm_release.tailscale` | Tailscale OAuth client secret for the operator |
| `AWS_ACCESS_KEY_ID` | the `s3` backend | AWS access key for the state bucket |
| `AWS_SECRET_ACCESS_KEY` | the `s3` backend | AWS secret access key |
| `AWS_REGION` | the `s3` backend | Region of the state bucket (`eu-central-1`) |

**GitHub Actions secrets (used by CI):**

| Secret | Purpose |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | AWS credentials for Terraform S3 backend |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials for Terraform S3 backend |
| `HCLOUD_TOKEN` | Hetzner Cloud token (if needed by bootstrap) |
| `KUBE_CONFIG` | Base64-encoded kubeconfig for the cluster (written to `bootstrap/.kube/config` in CI) |
| `CI_TAILSCALE_OAUTH_CLIENT_ID` | Tailscale OAuth client ID for `tailscale/github-action` (CI runner access) |
| `CI_TAILSCALE_OAUTH_CLIENT_SECRET` | Tailscale OAuth client secret for `tailscale/github-action` (CI runner access) |
| `TAILSCALE_OAUTH_CLIENT_ID` | Same as `TF_VAR_tailscale_oauth_client_id` (operator) - passed to Terraform in CI |
| `TAILSCALE_OAUTH_CLIENT_SECRET` | Same as `TF_VAR_tailscale_oauth_client_secret` (operator) - passed to Terraform in CI |

```bash
export TF_VAR_tailscale_oauth_client_id="k1234CNTRL"
export TF_VAR_tailscale_oauth_client_secret="tskey-client-…"
export AWS_ACCESS_KEY_ID="AKIA…"
export AWS_SECRET_ACCESS_KEY="…"
export AWS_REGION="eu-central-1"
```

> **Both OAuth variables are required.** `main.tf` declares `check` blocks that
> fail the plan when either is empty, because the Helm release has no credentials
> to create the operator's proxy nodes. The client secret is rendered into the
> Helm release and therefore lands in the Terraform state in clear text — keep
> the state bucket private, like the `../infrastructure` state.

> **CI OAuth credentials:** GitHub Actions uses `CI_TAILSCALE_OAUTH_CLIENT_ID`
> and `CI_TAILSCALE_OAUTH_CLIENT_SECRET` (stored as repository secrets) together
> with the `tailscale/github-action` to connect the runner to the tailnet during
> bootstrap deployments (see `.github/workflows/deploy-bootstrap.yml` and
> `CI.md`). These are different from `TF_VAR_tailscale_oauth_client_id`/secret
> and from `TAILSCALE_AUTH_KEY` used by nodes.

### Apply

```bash
terraform init
terraform plan
terraform apply
```

Access the Argo CD UI is possible using the tailscale Magic DNS or private IP.
