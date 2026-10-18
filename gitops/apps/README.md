# Applications (L3)

ArgoCD `Application` manifests for your own workloads live here.

This directory is the source of the `apps` Application defined in
`../root-app.yaml`. Keep this file (or any other tracked file) here so the
directory exists in Git — ArgoCD fails with `app path does not exist` when the
path is missing from the repository.

One `Application` per file, e.g. `my-app.yaml`.
