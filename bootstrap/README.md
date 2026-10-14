# Bootstrap Argo CD and the Tailscale operator

Terraform that installs [Argo CD](https://argo-cd.readthedocs.io/) and the
[Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator)
into the Kubernetes homelab cluster. This is the L1 layer: `../infrastructure`
provisions the cloud + k3s cluster, and `bootstrap/` installs Argo CD, the
Tailscale operator and (once finished) the root Application that points at
[`../gitops`](../gitops). From then on Argo CD reconciles everything inside the
cluster from Git.

## What it does

- creates the `argocd` namespace and installs the official
  [`argo-cd`](https://github.com/argoproj/argo-helm) Helm chart (`10.10.2`) with
  the overrides in `values/argocd.yaml` (liveness probe, metrics, ServiceMonitor,
  server autoscaling);
- creates the `tailscale` namespace and installs the official
  [`tailscale-operator`](https://pkgs.tailscale.com/helmcharts/) Helm chart
  (`1.104.1`), configured with a **Tailscale OAuth client** so the operator can
  provision the proxy nodes and expose Services/Ingresses on the tailnet.

The root Application (app-of-apps) that hands Argo CD the contents of
`../gitops` is still marked `TODO` in `main.tf`/`outputs.tf`.

## Prerequisites

- The cluster from `../infrastructure` is up and reachable over the tailnet.
- A kubeconfig is available at `bootstrap/.kube/config` — both the `helm`
  and `kubernetes` providers read it through `config_path` in `versions.tf`.
- A Tailscale **OAuth client** for the Tailscale operator: its client ID and
  client secret are passed to `helm_release.tailscale`. Create it in the
  Tailscale admin console under **Settings → OAuth clients** with write access to
  the tailnet's devices and the tag its proxy nodes should carry. See the
  [Tailscale Kubernetes operator docs](https://tailscale.com/kb/1236/kubernetes-operator).
- AWS credentials for the S3 backend (key `terraform-bootstrap.tfstate`, bucket
  `kubernetes-homelab-tfstate`).

### Drop in the kubeconfig

The nodes have no public IP addresses, so the kubeconfig is copied over
Tailscale from the master and repointed at its tailnet name:

```bash
scp cluster@master-node-0:/etc/rancher/k3s/k3s.yaml bootstrap/kube-config/config
sed -i '' "s/127.0.0.1/master-node-0.<tailnet>.ts.net/" bootstrap/kube-config/config

kubectl --kubeconfig bootstrap/kube-config/config get nodes
```

> **The address must be on the API server certificate.** `extra_tls_sans` in
> `../infrastructure/main.tf` has to name the same address before the cluster is
> created, or `kubectl` (and therefore Terraform) fails the TLS handshake. See
> [Connect to the Kubernetes cluster](../infrastructure/README.md#connect-to-the-kubernetes-cluster).

> **`kube-config/` is not committed** — it contains cluster admin credentials and
> should live only on the machine that runs the bootstrap.

## How to run

### Environment variables

The Tailscale operator authenticates with an **OAuth client**, not with the
`tailscale_auth_key` the nodes use to join the tailnet. Pass the client
credentials through the environment (or as `tailscale_oauth_client_id` /
`tailscale_oauth_client_secret` in an ignored `terraform.tfvars`):

| Variable | Read by | Purpose |
| --- | --- | --- |
| `TF_VAR_tailscale_oauth_client_id` | `variables.tf` → `helm_release.tailscale` | Tailscale OAuth client ID |
| `TF_VAR_tailscale_oauth_client_secret` | `variables.tf` → `helm_release.tailscale` | Tailscale OAuth client secret |
| `AWS_ACCESS_KEY_ID` | the `s3` backend | AWS access key for the state bucket |
| `AWS_SECRET_ACCESS_KEY` | the `s3` backend | AWS secret access key |
| `AWS_REGION` | the `s3` backend | Region of the state bucket (`eu-central-1`) |

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

### Apply

```bash
terraform init
terraform plan
terraform apply
```

Access the Argo CD UI by port-forwarding (the cluster has no ingress yet):

```bash
kubectl --kubeconfig kube-config/config -n argocd port-forward svc/argocd-server 8080:443
```

The initial admin password is stored in the `argocd-initial-admin-secret`:

```bash
kubectl --kubeconfig kube-config/config -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```
