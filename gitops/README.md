# GitOps definitions

This directory holds the manifests that Argo CD reconciles inside
the cluster — everything below is managed from Git. Keeping in-cluster state (Helm releases, CRDs) out of `tfstate` gives a single source of truth for the cluster.

## Structure

- `root-app.yaml` — root Applications (App-of-Apps) pointing Argo CD to `addons/` and `apps/`. Argo CD will sync all `Application` CRs placed in `addons/` and `apps/`.
- `addons/` — `Application` CR definitions for cluster addons (one per file).
- `apps/` — `Application` CR definitions for your own workloads.