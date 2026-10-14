# TODO — GitOps / cluster bootstrap (Terraform bootstrap + ArgoCD + addons + applications)

Notes from the project review and the plan for the next steps.
Goal: after `terraform apply` provisions the cloud + K3s cluster, a second Terraform
bootstrap installs ArgoCD, and ArgoCD deploys the cluster addons and applications.

---

## 0. Current state — findings

### What already exists
- `infrastructure/` — Terraform: K3s on Hetzner via the `hcloud-k8s-cluster` module
  (own module: `pawel150199/hcloud-k8s-cluster`, currently `0.1.19`).
- 1 master + 1 worker (`cx23`, `ubuntu-26.04`, `hel1`), placement group, private network.
- Tailscale on the nodes (`--ssh`), S3 state backend, CI on GitHub Actions.
- `bootstrap/` — Terraform that installs ArgoCD (the `argocd` namespace + the
  `argo-cd` Helm chart) and the Tailscale Kubernetes Operator (the `tailscale`
  namespace + the `tailscale-operator` chart, authenticated by a Tailscale OAuth
  client); the root Application and outputs are still TODO.
- `gitops/` — stub directories `addons/` and `applications/` for ArgoCD-managed manifests.
- CI: `pre-commit` → `deploy-infrastructure` (dry-run → manual approval → apply).

### Facts about the cluster (from the module — important for decisions)
- K3s starts with **`--disable traefik`** → **no ingress whatsoever**.
- The built-in **klipper ServiceLB is active** → `Service type=LoadBalancer` is served by
  node IP + hostPort, **not** by a Hetzner LB.
- Flannel VXLAN over the private network, Spegel registry mirror on :5001.
- **No** `hcloud-cloud-controller-manager` (CCM) and **no** CSI.
- Firewall: only `443` is open (+ `6443` to `kube_api_source_ips`, `22` to `ssh_source_ips`).
  **`80` is closed**, and so are NodePorts.
- The module **exposes no variable for custom K3s flags** — `K3S_EXEC` is hardcoded.
- The module outputs node IPs, the control-plane endpoint and the cluster token, but
  **no kubeconfig**.
- Public IPv4 enabled with inbound restricted to Tailscale (`100.64.0.0/10`);
  `use_public_ipv6 = false`. Outbound internet works for bootstrap (Tailscale
  install/join), but no inbound from public internet. Access goes over the tailnet
  (`master-node-0`, `worker-node-0`). The `*_public_ips` outputs will be non-empty.
- `infrastructure/main.tf` does **not** set `extra_tls_sans` yet. Without it a
  kubeconfig pointed at a `master-node-0.<tailnet>.ts.net` address fails TLS
  verification. Adding it changes cloud-init `user_data` and therefore
  recreates the servers.

### Conclusion
What is missing is (a) a decision on **how traffic enters the cluster**, and
(b) the GitOps layer itself. Those are the subjects of this file.

---

## 1. Separation of responsibilities

| Layer | Tool | Responsible for |
|---|---|---|
| L0 — Cloud + Kubernetes | Terraform (`infrastructure/`) | Hetzner servers, network, load balancer, DNS records and the K3s cluster runtime |
| L1 — Bootstrap | **Terraform (`bootstrap/`)** | **Installs ArgoCD and the root Application** |
| L2 — Addons | ArgoCD (`gitops/addons/`) | cert-manager, ingress, monitoring, secrets, storage… |
| L3 — Applications | ArgoCD (`gitops/applications/`) | Own workloads |

Rule: **Terraform = cloud + cluster provisioning and the ArgoCD bootstrap (L0–L1).
ArgoCD = everything that runs inside the cluster afterwards (L2–L3).**
This keeps in-cluster state (Helm releases, CRDs) out of tfstate and gives a single
source of truth for the cluster.

---

## 2. Repository structure (current)

```
kubernetes-homelab/
├── .github/
│   └── workflows/
│       ├── deploy-infrastructure.yml
│       └── pre-commit-check.yml
├── bootstrap/
│   └── README.md                # Terraform that bootstraps ArgoCD
├── gitops/
│   ├── README.md
│   ├── addons/                  # ArgoCD-managed cluster addons
│   └── applications/            # ArgoCD-managed applications
├── infrastructure/
│   ├── README.md
│   ├── main.tf
│   ├── outputs.tf
│   ├── variables.tf
│   └── versions.tf
├── .gitignore
├── .pre-commit-config.yaml
└── TODO.md
```

---

## 3. ArgoCD bootstrap via Terraform (L1)

The bootstrap is done **by Terraform**, not by hand with `kubectl`/`helm`:
- `bootstrap/` Terraform installs ArgoCD (recommended: the official `argo-cd` Helm chart
  via the `helm` provider) and then applies the **root Application** (`kubernetes`/
  `kubectl` provider) that points at `gitops/`.
- From that point ArgoCD **manages itself** and everything under `gitops/`.

Steps:
1. `infrastructure/` Terraform creates the cluster.
2. `bootstrap/` Terraform runs and installs ArgoCD + the Tailscale operator + the root app-of-apps.
3. ArgoCD reconciles `gitops/addons` and `gitops/applications`.

The Tailscale operator is configured with an **OAuth client**, distinct from the
`tailscale_auth_key` the nodes use to join the tailnet. Before applying
`bootstrap/`, export `TF_VAR_tailscale_oauth_client_id` and
`TF_VAR_tailscale_oauth_client_secret` (or set `tailscale_oauth_client_id` /
`tailscale_oauth_client_secret` in a `terraform.tfvars`). Both are required — the
`check` blocks in `bootstrap/main.tf` fail the plan when either is empty.

- [x] Decide how `bootstrap/` Terraform obtains cluster access: the kubeconfig is copied
      over Tailscale (`scp cluster@master-node-0:/etc/rancher/k3s/k3s.yaml`) into
      `bootstrap/kube-config/config` and read via `config_path`. Needs `extra_tls_sans`.
- [x] Choose the provider: `helm` for the ArgoCD release and `kubernetes` for the root app.
- [ ] Give `bootstrap/` its own state key in the S3 backend.
- [ ] Add the root Application (app-of-apps) pointing at `gitops/`.
- [ ] Define addon ordering via **sync waves**: `argocd.argoproj.io/sync-wave` (e.g. cert-manager before ingress).
- [ ] (optional, once there are many addons/apps) consider an `ApplicationSet` with a git directory
      generator instead of adding each app by hand.

### How the kubeconfig reaches CI (later)
- The GitHub runner is public, the cluster is private. Options:
  - [ ] join the runner to the tailnet (`tailscale/github-action` + ephemeral key), then run Terraform;
  - [ ] keep the kubeconfig in a GitHub Secret (generated after the infrastructure apply).
- For a start: run `bootstrap/` Terraform **locally from the laptop** (one-time). ArgoCD maintains itself afterwards.

---

## 4. K3s — decisions

- **Ingress**: Traefik is disabled in the module → install your own ingress controller
  (Traefik or nginx). Do not run two.
- **Storage**: the default `local-path` is enough to start; Longhorn if replication is needed;
  `hcloud-csi` (Hetzner Volumes) as a separate option (RWO).
- **ServiceLB**: klipper is already active — it can stay.
- **K3s/Tailscale secrets**: the auth key is rendered into cloud-init → treat the Terraform state as a secret.

---

## 5. Traffic entrypoint (decision)

Decision: **for now, most apps via Tailscale (no public exposure)**,
later **selected apps on a public domain**.

### Now: klipper + Tailscale Operator
- [ ] Ingress controller (Service `type=LoadBalancer`) → served by klipper (node IP:443).
- [ ] **Tailscale Kubernetes Operator** — expose ingresses/services directly on the tailnet,
      zero cost, no public inbound exposure. Fits the "private cluster" philosophy.
      (Currently installed directly by `bootstrap/` with the `tailscale-operator` chart
      and a Tailscale OAuth client — see [§3](#3-argocd-bootstrap-via-terraform-l1) —
      rather than by ArgoCD as an addon.)
- Caveat: klipper + a `LoadBalancer` Service on port 80 → **the firewall blocks 80**.
      Only 443 works (or add a rule for 80 in the module: `custom_*_firewall_rules`).

### Later: public domain for selected apps
Option A — **hcloud-cloud-controller-manager (CCM)** = Hetzner's official operator for LBs:
- implements `Service type=LoadBalancer` → actually creates a **Hetzner Cloud Load Balancer**
  (health checks, targets = node private IPs), plus node lifecycle.
- **It is not an ingress** — it only provisions the LB; HTTP routing is still done by the ingress controller.
- Cost: ~5–6 EUR/month for `lb11` + traffic (per LB).
- Requirements/conflicts (to handle at rollout):
  - [ ] disable klipper: `--disable servicelb`;
  - [ ] disable the built-in k3s CCM: `--disable-cloud-controller`;
  - [ ] **extend the module** (it exposes no variable for K3s flags) — best done by writing
        `/etc/rancher/k3s/config.yaml` with `disable: [servicelb, cloud-controller]` via cloud-init;
  - [ ] open NodePorts in the firewall (CCM routes LB → NodePort), preferably only from the LB range
        (module: `custom_master_firewall_rules` / `custom_worker_firewall_rules`);
  - [ ] the `HCLOUD_TOKEN` secret (with LB permission) must reach CCM inside the cluster.
- [ ] For a public domain: cert-manager + ClusterIssuer (Let's Encrypt, DNS-01 — Hetzner DNS / Cloudflare).

Option B — a manual Hetzner LB in Terraform (no in-cluster operator), static.

### Comparison of options

| Option | Cost | Public? | Notes |
|---|---|---|---|
| klipper ServiceLB (already there) | 0 | node IP:443 | simplest; 80 closed |
| Tailscale Operator | 0 | no (tailnet only) | best for now |
| hcloud CCM | ~5–6 EUR/month | under the LB domain | requires module changes |
| manual Hetzner LB (TF) | ~5–6 EUR/month | under the domain | no in-cluster operator |

---

## 6. Secrets

Decision: **defer for now**, but the direction is **option 1 = Sealed Secrets**.
- [ ] (later) Sealed Secrets: a `SealedSecret` is a plain YAML, encrypt with `kubeseal`, commit to git.
- Future alternatives: External Secrets Operator + 1Password/Bitwarden/Vault (cleaner, more config);
  SOPS + age (needs a CMP sidecar in ArgoCD — ksops/viaduct).

---

## 7. Addon set (with proposed sync waves)

- wave `-10`: `sealed-secrets` (or `external-secrets`)
- wave `-5`: `cert-manager` (+ ClusterIssuer, Let's Encrypt DNS-01)
- wave `0`: ingress (Traefik/nginx), `tailscale-operator`
- wave `5`: `kube-prometheus-stack` (Prometheus/Grafana/Alertmanager), `metrics-server` (K3s has it)
- wave `5`: `loki` + `alloy` (logs)
- wave `10`: `renovate` / ArgoCD Image Updater (updates)
- (once there is a public domain) `hcloud-ccm`, possibly `hcloud-csi`

Each of the above becomes a directory under `gitops/addons/<name>/`.

---

## 8. Rollout order (checklist)

- [ ] 1. Finalize the entrypoint (now: klipper + tailscale-operator; later CCM for domains).
- [ ] 2. Write the `bootstrap/` Terraform that installs ArgoCD (L1) + the root app-of-apps.
- [ ] 3. Populate `gitops/addons/` with the first addons: `tailscale-operator`, ingress, `cert-manager`.
- [ ] 4. Verify ArgoCD sync and self-management.
- [ ] 5. Add monitoring/logging addons.
- [ ] 6. Configure secrets (Sealed Secrets).
- [ ] 7. (optional, later) wire the bootstrap into CI (Tailscale join + kubeconfig).
- [ ] 8. Add applications under `gitops/applications/`.
- [ ] 9. (once there is a public domain) extend the module with `--disable servicelb`/`config.yaml` +
         NodePort firewall rules and roll out `hcloud-ccm`.

---

## 9. Open questions / decisions

- [x] Public IPv4 enabled with Tailscale-only inbound firewall — decided.
- [ ] Set `extra_tls_sans` in `main.tf` to the master's tailnet name so `kubectl`
      works over Tailscale (this recreates the servers).
- [ ] How `bootstrap/` Terraform gets cluster credentials (no kubeconfig in the module outputs).
- [ ] `helm` + `kubernetes` providers vs the `kubectl` provider for the ArgoCD install.
- [ ] Open `80` in the firewall (if ingress should accept HTTP / redirect to HTTPS).
- [ ] Whether and when to introduce a public domain + cert-manager DNS-01 (which DNS provider).
- [ ] ArgoCD version/tag and install method (Helm chart vs official manifests).
