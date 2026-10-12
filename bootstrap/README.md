# Bootstrap Argo CD

Terraform that installs [Argo CD](https://argo-cd.readthedocs.io/) into the
Kubernetes homelab cluster. This is the L1 layer: `../infrastructure` provisions
the cloud + k3s cluster, and `bootstrap/` installs Argo CD and (once finished)
the root Application that points at [`../gitops`](../gitops). From then on Argo
CD reconciles everything inside the cluster from Git.

## What it does

- creates the `argocd` namespace;
- installs the official [`argo-cd`](https://github.com/argoproj/argo-helm) Helm
  chart (`10.10.2`) with the overrides in `values/argocd.yaml` (liveness probe,
  metrics, ServiceMonitor, server autoscaling).

The root Application (app-of-apps) that hands Argo CD the contents of
`../gitops` is still marked `TODO` in `main.tf`/`outputs.tf`.

## Prerequisites

- The cluster from `../infrastructure` is up and reachable over the tailnet.
- A kubeconfig is available at `bootstrap/kube-config/config` — both the `helm`
  and `kubernetes` providers read it through `config_path` in `versions.tf`.
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

```bash
export AWS_ACCESS_KEY_ID="AKIA…"
export AWS_SECRET_ACCESS_KEY="…"
export AWS_REGION="eu-central-1"

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
