# Addons

ArgoCD `Application` manifests for cluster addons (cert-manager, ingress,
monitoring, storage, …) live here.

This directory is the source of the `addons` Application defined in
`../root-app.yaml`. Keep this file (or any other tracked file) here so the
directory exists in Git — ArgoCD fails with `app path does not exist` when the
path is missing from the repository.

One `Application` per file, e.g. `cert-manager.yaml`.

## hcloud addons — required Secret (manual step)

`hcloud-cloud-controller-manager.yaml` and `hcloud-csi.yaml` read the Hetzner
API token from the `hcloud` Secret in the `kube-system` namespace (key `token`).
ArgoCD does not create it — create it once by hand, before the first sync:

```bash
kubectl -n kube-system create secret generic hcloud \
  --from-literal=token=<HCLOUD_TOKEN>
```

> **TODO:** add a Secret Operator (Sealed Secrets — the direction chosen in
> `../../TODO.md` §6) so this Secret (and others) can live in Git in an
> encrypted form instead of being created by hand on every new cluster.
