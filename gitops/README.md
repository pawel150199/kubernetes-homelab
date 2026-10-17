# GitOps definitions

This directory holds the manifests that [Argo CD](../bootstrap) reconciles inside
the cluster — the L2 (addons) and L3 (applications) layers. Terraform only
bootstraps Argo CD and the root Application; everything below is managed from
Git. Keeping in-cluster state (Helm releases, CRDs) out of `tfstate` gives a
single source of truth for the cluster.

Two directories exist:

- `addons/` — cluster addons managed by Argo CD. Current state: `Application` CR definitions
  for addons are placed here (see `root-app.yaml` below).
- `apps/` (or `applications/` historically) — your own workloads, one subdirectory per application.

A single root Application (`root-app.yaml`) bootstraps Argo CD to manage
applications from Git using the App-of-Apps pattern.

See also: [Tworzenie aplikacji w ArgoCD](../docs/argocd/tworzenie-aplikacji-w-argocd.md).

The planned addon set and the intended sync order (secrets → cert-manager →
ingress → observability) are described in [`../TODO.md`](../TODO.md).
