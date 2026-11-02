# Grafana dashboards

Custom Grafana dashboards, kept as plain `.json` files so they can be exported
from Grafana and committed without any YAML escaping.

`kustomization.yaml` wraps the listed JSON files into the `homelab-dashboards`
ConfigMap with the `grafana_dashboard: "1"` label. The Grafana sidecar from
`kube-prometheus-stack` (configured in
`../addons/values/kube-prometheus-stack.yaml`) watches for that label and
provisions the dashboards automatically - no Grafana restart needed.

ArgoCD syncs this directory through the `monitoring-dashboards` Application in
`../addons/monitoring-dashboards.yaml`, which the `addons` app-of-apps picks up
like any other addon.

## Adding a dashboard

1. Export it from Grafana: **Share -> Export -> Save to file**, or download the
   JSON from <https://grafana.com/grafana/dashboards/>.
2. Drop the file in this directory (`kubernetes-cluster.json`, ...).
3. Add the filename to the `files` list in `kustomization.yaml` (Kustomize does
   not expand globs).
4. Commit and push. ArgoCD syncs the ConfigMap; the sidecar imports it within
   ~30s.

Keep the dashboards' `uid` stable and avoid setting a numeric `id` - Grafana
uses the `uid` (or the title) to decide whether a dashboard is new or an update.

Data source UID: the chart provisions the default Prometheus data source with
UID `prometheus`, so panels should reference
`"datasource": {"type": "prometheus", "uid": "prometheus"}`.

## Folders

Folders are enabled in the values file:

```yaml
sidecar:
  dashboards:
    folderAnnotation: grafana_folder
    provider:
      foldersFromFilesStructure: true
```

Both settings are required: the sidecar reads the `grafana_folder` annotation from
each ConfigMap and places the file in a matching subdirectory, and the Grafana
file provider (`foldersFromFilesStructure`) turns that directory into a real
Grafana folder. Without the provider flag the annotation is ignored and every
dashboard lands in the default folder.

`kustomization.yaml` sets the annotation for the whole generated ConfigMap:

```yaml
generatorOptions:
  disableNameSuffixHash: true
  labels:
    grafana_dashboard: "1"
  annotations:
    grafana_folder: Homelab
```

so all dashboards in this directory go to **Homelab**.

The chart's own dashboards (Kubernetes / Compute Resources / …, node-exporter,
etc.) stay in the default folder: `kube-prometheus-stack` does not annotate them
with `folderAnnotation` — it only applies the static
`sidecar.dashboards.annotations` map to them. To group those too, set for
example:

```yaml
sidecar:
  dashboards:
    annotations:
      grafana_folder: Kubernetes
```

or add the annotation per dashboard. Without an annotation a dashboard is
provisioned at the provider's root folder.

To put a dashboard in a different folder, give it its own generator entry with
its own annotation instead of listing it in the shared one:

```yaml
configMapGenerator:
  - name: homelab-dashboards
    files:
      - homelab-overview.json
    options:
      annotations:
        grafana_folder: Homelab
  - name: apps-dashboards
    files:
      - my-app.json
    options:
      annotations:
        grafana_folder: Applications
```

Note: `generatorOptions.annotations` apply to every generator, so per-dashboard
folders need the per-entry `options.annotations` shown above (and no global
`annotations`).

## Notes

- All dashboards share one ConfigMap, so a malformed JSON file prevents every
  dashboard in it from importing. If that becomes a problem, add another
  `configMapGenerator` entry per dashboard.
- Deleting a `.json` file removes the key from the ConfigMap; the dashboard
  itself is left in Grafana until it is deleted there (the sidecar does not
  garbage-collect).
- `homelab-overview.json` is a starter dashboard using only node-exporter and
  kube-state-metrics series. Delete it once you have your own.
