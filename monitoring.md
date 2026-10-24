# Plan monitoringu dla homelabu (ArgoCD + Grafana, Logi/Metrics/Tracing)

Ten plan jest dopasowany pod aktualny stan repozytorium (`k3s` na Hetznerze, ArgoCD app-of-apps, Tailscale, `hcloud-ccm/csi`, brak ingressu). Bazuje na aktualnym podejściu Grafany ("LGTM" stack) czyli **Loki + Grafana + Tempo (+ Mimir/Prometheus)** z **Grafana Alloy** jako unified collector.

## 1) Obecny stan (quick assessment)

Na podstawie audytu klastra/repo:

| Element | Status | Komentarz |
| --- | --- | --- |
| ArgoCD | OK (v3.5.4) | Działa, root app-of-apps (`addons/`, `apps/`) skonfigurowany. ArgoCD serwer eksponowany przez Tailscale (`tailscale.com/expose: "true"`). |
| cert-manager | OK | Zainstalowany. |
| hcloud-ccm + hcloud-csi | OK | `hcloud` secret utworzony ręcznie (patrz `gitops/addons/README.md`). |
| metrics-server | `OutOfSync`/`Progressing`, pod `0/1` | Aplikacja istnieje, jednak nie startuje poprawnie. K3s ma swoje modyfikacje TLS - wymaga naprawy. |
| ingress controller | Brak | W K3s `traefik` wyłączony. Obecnie ruch wewnętrzny przez Tailscale/klipper. |
| monitoring | Pusty/zepsuty stub | `gitops/addons/monitoring.yaml` ma błędy (literówki, źle ustawiony `sources/valueFiles`, wskazuje na `metrics-server.yaml`). |
| Tailscale Operator | OK | Używany do eksponowania usług na tailnecie. |

## 2) Docelowe rozwiązanie (zgodne z rekomendacjami Grafany)

Grafana obecnie promuje podejście oparte o **OpenTelemetry** + **Grafana Alloy**. Dla self-hosted na małym klastrze (2x CX23) najlepszy balans prostoty/stabilności to:

| Obszar | Komponent | Uwagi |
| --- | --- | --- |
| **Metryki** | [`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) (Prometheus Operator + Prometheus + Alertmanager + Grafana) | Najszybszy start. Automatycznie zbiera metryki K8s, node-exporter, kube-state-metrics. Grafana już w środku. |
| **Logi** | [`loki`](https://grafana.github.io/helm-charts) (w trybie `single-binary` na start) | Lekki dla homelabu, indeksuje tylko labele, tanio w storage. |
| **Traces** | [`tempo`](https://grafana.github.io/helm-charts) | Wystarczający na start (monolityczny/distributed minimalny). Przyjmuje OTLP. |
| **Kolektor** | [`alloy`](https://grafana.github.io/helm-charts) (DaemonSet + opcjonalny Deployment) | Unified collector - zbiera logi z podów, metryki (scrape/remote_write), traces (OTLP), enrichuje o K8s metadata. Zastępuje promtail/otel-collector w nowym stacku Grafany. |
| **Dodatkowe** | `node-exporter`, `kube-state-metrics` | Zazwyczaj dostarczone przez kube-prometheus-stack/alloy. |

> Alternatywa: [`grafana/k8s-monitoring`](https://github.com/grafana/k8s-monitoring-helm) - bardzo wygodny, ale bardziej "opinionated". Dla nauki i kontroli nad wartościami wolę osobne Applicationy w ArgoCD.

## 3) Architektura przepływu danych

```text
[Pods/Nodes] 
  -> Grafana Alloy (DaemonSet) 
     - logi (pod logs via k8s API/file) -> Loki
     - metryki (kubelet/cadvisor/node/kube-state) -> Prometheus (kube-prometheus-stack)
     - traces (OTLP gRPC/HTTP) -> Tempo

Grafana (w kube-prometheus-stack) łączy datasource'y: Prometheus, Loki, Tempo
Korelacje: traceID <-> logi <-> metryki
```

## 4) Proponowana struktura w repozytorium

Trzymaj się obecnego wzoru (multi-source: chart + `$values` z tego repo). Dodać osobne pliki pod `gitops/addons/` oraz wartości pod `gitops/addons/values/monitoring/`.

```text
gitops/
├── addons/
│   ├── monitoring-namespace.yaml      # namespace monitoring (opcjonalne, można przez syncOptions)
│   ├── kube-prometheus-stack.yaml     # metryki + Grafana + Alertmanager
│   ├── loki.yaml                      # logi
│   ├── tempo.yaml                     # tracing
│   ├── alloy.yaml                     # collector (logi/metryki/trace)
│   └── values/
│       ├── monitoring/
│       │   ├── kube-prometheus-stack.yaml
│       │   ├── loki.yaml
│       │   ├── tempo.yaml
│       │   └── alloy.yaml
│       └── ... (istniejące)
└── root-app.yaml                      # bez zmian (addons/ już śledzony)
```

Dodatkowo napraw/usuń obecny `gitops/addons/monitoring.yaml` (jest uszkodzony). Lepiej mieć rozbite Applicationy niż jeden monolit.

## 5) Wersje chartów (aktualne na podstawie indeksu)

Na podstawie sprawdzenia repozytorium indeksów Helm:

| Chart | Repo | Sugerowana wersja (stabilna) | AppVersion | Komentarz |
| --- | --- | --- | --- | --- |
| `kube-prometheus-stack` | `https://prometheus-community.github.io/helm-charts` | `~76.x` lub najnowsza sprawdzona (np. 77.x) | Prometheus v3.x/Grafana 12.x | Najpopularniejszy, integruje się świetnie z ArgoCD. |
| `grafana` (opcjonalnie osobny) | `https://grafana.github.io/helm-charts` | zgodny | - | Niepotrzebny jeśli używasz Grafany z kube-prometheus-stack. |
| `loki` | `https://grafana.github.io/helm-charts` | `6.x` (single-binary) | 3.5.x+ | Dla homelabu `deploymentMode: SingleBinary` + `filesystem` lub PVC na `local-path`/`hcloud-volumes`. |
| `tempo` | `https://grafana.github.io/helm-charts` | `1.23.x` | 2.8.x+ | Monolityczny wystarczający. |
| `alloy` | `https://grafana.github.io/helm-charts` | `1.2.x+` | v1.9.x+ | Używaj najnowszej stabilnej z repo Grafany. |

Zawsze sprawdź przed wdrożeniem `helm search repo`/indeks, bo wersje się zmieniają.

## 6) Konfiguracja (minimalne, działające wartości)

> Poniższe to propozycja pod ten klaster. Dostosuj zasoby (requests/limits) do CX23 (4GB RAM/2vCPU). Na start lepiej mniej niż więcej.

### 6a) `gitops/addons/values/monitoring/kube-prometheus-stack.yaml`

```yaml
# Minimalne wartości pod homelab
grafana:
  enabled: true
  adminUser: admin
  # hasło lepiej trzymać w SealedSecret/ExternalSecret później
  adminPassword: "changeme-please"  # zmień po pierwszym logowaniu
  service:
    type: ClusterIP
  persistence:
    enabled: false  # na start, można włączyć PVC
  sidecar:
    dashboards:
      enabled: true
      searchNamespace: ALL
    datasources:
      enabled: true
      defaultDatasourceEnabled: true

prometheus:
  prometheusSpec:
    retention: 7d
    retentionSize: "10GB"
    resources:
      requests:
        memory: 512Mi
        cpu: 250m
      limits:
        memory: 1Gi
        cpu: 500m
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path  # lub hcloud-volumes
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 20Gi

alertmanager:
  enabled: true
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 2Gi

nodeExporter:
  enabled: true

kubeStateMetrics:
  enabled: true

# Dla K3s często niepotrzebne niektóre scrape'y, stack działa
defaultRules:
  create: true
```

### 6b) `gitops/addons/values/monitoring/loki.yaml` (single-binary)

```yaml
deploymentMode: SingleBinary

loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
  schemaConfig:
    configs:
      - from: "2024-04-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: loki_index_
          period: 24h
  rulerConfig:
    storage:
      type: local

singleBinary:
  replicas: 1
  persistence:
    enabled: true
    storageClass: local-path
    size: 20Gi
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 512Mi
      cpu: 250m

# Wyłącz komponenty niepotrzebne w single-binary
read:
  replicas: 0
write:
  replicas: 0
backend:
  replicas: 0

monitoring:
  selfMonitoring:
    enabled: false
  lokiCanary:
    enabled: false

test:
  enabled: false
```

### 6c) `gitops/addons/values/monitoring/tempo.yaml`

```yaml
tempo:
  metricsGenerator:
    enabled: true
    remoteWriteUrl: "http://kube-prometheus-stack-prometheus.monitoring:9090/api/v1/write"

  storage:
    trace:
      backend: local
      local:
        path: /var/tempo/traces
      wal:
        path: /var/tempo/wal

  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318
    jaeger:
      protocols:
        thrift_http:
          endpoint: 0.0.0.0:14268
    zipkin:
      endpoint: 0.0.0.0:9411

persistence:
  enabled: true
  storageClassName: local-path
  size: 10Gi

resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 250m

serviceMonitor:
  enabled: true
```

### 6d) `gitops/addons/values/monitoring/alloy.yaml`

```yaml
alloy:
  configMap:
    create: true
    content: |-
      // Discovery
      discovery.kubernetes "pods" {
        role = "pod"
      }

      discovery.kubernetes "nodes" {
        role = "node"
      }

      // Pod logs -> Loki
      discovery.relabel "pod_logs" {
        targets = discovery.kubernetes.pods.targets
        rule {
          source_labels = ["__meta_kubernetes_namespace"]
          action = "replace"
          target_label = "namespace"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_name"]
          action = "replace"
          target_label = "pod"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_container_name"]
          action = "replace"
          target_label = "container"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_node_name"]
          action = "replace"
          target_label = "node"
        }
        rule {
          source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_name"]
          action = "replace"
          target_label = "job"
          separator = "/"
          replacement = "$1"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_uid", "__meta_kubernetes_pod_container_name"]
          action = "replace"
          target_label = "__path__"
          separator = "/"
          replacement = "/var/log/pods/*$1/*.log"
        }
      }

      local.file_match "pod_logs" {
        path_targets = discovery.relabel.pod_logs.output
      }

      loki.source.file "pod_logs" {
        targets    = local.file_match.pod_logs.targets
        forward_to = [loki.write.loki.receiver]
      }

      loki.write "loki" {
        endpoint {
          url = "http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push"
        }
      }

      // OTLP for traces/metrics/logs from apps
      otelcol.receiver.otlp "default" {
        grpc { endpoint = "0.0.0.0:4317" }
        http { endpoint = "0.0.0.0:4318" }
        output {
          traces  = [otelcol.exporter.otlp.tempo.input]
          metrics = [otelcol.exporter.prometheus.default.input]
          logs    = [otelcol.exporter.loki.default.input]
        }
      }

      otelcol.exporter.otlp "tempo" {
        client {
          endpoint = "tempo.monitoring.svc.cluster.local:4317"
          tls {
            insecure = true
          }
        }
      }

      otelcol.exporter.prometheus "default" {
        forward_to = [prometheus.remote_write.prom.receiver]
      }

      otelcol.exporter.loki "default" {
        forward_to = [loki.write.loki.receiver]
      }

      prometheus.remote_write "prom" {
        endpoint {
          url = "http://kube-prometheus-stack-prometheus.monitoring:9090/api/v1/write"
        }
      }

  clustering:
    enabled: false

  resources:
    requests:
      memory: 128Mi
      cpu: 100m
    limits:
      memory: 256Mi
      cpu: 200m

controller:
  type: daemonset
  tolerations:
    - operator: Exists

serviceMonitor:
  enabled: true
```

> Uwaga: w zależności od wersji chartu Loki service może być `loki` lub `loki-gateway`. Sprawdź po wdrożeniu (`kubectl get svc -n monitoring`). W powyższym przyjęto `loki-gateway` który często występuje w nowszych wersjach chartu.

## 7) ArgoCD Application manifesty

Używaj wzoru multi-source jak w `cert-manager.yaml`/`metrics-server.yaml`.

### 7a) `gitops/addons/kube-prometheus-stack.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  sources:
    - repoURL: https://prometheus-community.github.io/helm-charts
      chart: kube-prometheus-stack
      targetRevision: 77.14.0  # sprawdź aktualną stabilną przed apply
      helm:
        releaseName: kube-prometheus-stack
        valueFiles:
          - $values/gitops/addons/values/monitoring/kube-prometheus-stack.yaml
    - repoURL: https://github.com/pawel150199/kubernetes-homelab.git
      targetRevision: master
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      enabled: true
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
  revisionHistoryLimit: 5
```

### 7b) `gitops/addons/loki.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: loki
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "6"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  sources:
    - repoURL: https://grafana.github.io/helm-charts
      chart: loki
      targetRevision: 6.46.0  # sprawdź aktualną
      helm:
        releaseName: loki
        valueFiles:
          - $values/gitops/addons/values/monitoring/loki.yaml
    - repoURL: https://github.com/pawel150199/kubernetes-homelab.git
      targetRevision: master
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      enabled: true
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
  revisionHistoryLimit: 5
```

### 7c) `gitops/addons/tempo.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tempo
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "6"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  sources:
    - repoURL: https://grafana.github.io/helm-charts
      chart: tempo
      targetRevision: 1.24.4  # sprawdź aktualną
      helm:
        releaseName: tempo
        valueFiles:
          - $values/gitops/addons/values/monitoring/tempo.yaml
    - repoURL: https://github.com/pawel150199/kubernetes-homelab.git
      targetRevision: master
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      enabled: true
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
  revisionHistoryLimit: 5
```

### 7d) `gitops/addons/alloy.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: alloy
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "7"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  sources:
    - repoURL: https://grafana.github.io/helm-charts
      chart: alloy
      targetRevision: 1.14.3  # sprawdź aktualną
      helm:
        releaseName: alloy
        valueFiles:
          - $values/gitops/addons/values/monitoring/alloy.yaml
    - repoURL: https://github.com/pawel150199/kubernetes-homelab.git
      targetRevision: master
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      enabled: true
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
  revisionHistoryLimit: 5
```

## 8) Dostęp do Grafany (na start przez Tailscale)

Masz już wzór z ArgoCD - wystarczy dodać adnotacje Tailscale do serwisu Grafany.

Opcja A - przez `values` w `kube-prometheus-stack.yaml`:

```yaml
grafana:
  service:
    type: ClusterIP
    annotations:
      tailscale.com/expose: "true"
      tailscale.com/hostname: "grafana"  # opcjonalne
```

Po syncu usługa pojawi się jako `grafana.<tailnet>.ts.net` (lub hostname z tailnetu). HTTPS/TLS obsłużony przez Tailscale.

Opcja B - osobny `Service`/`Ingress` przez Tailscale operator. Adnotacja na serwisie jest najprościej i zgodna z tym co już robisz (`argocd-server`).

## 9) Kolejność wdrożenia (krok po kroku)

Wykonuj kolejno, sprawdzając status w ArgoCD/UI lub `kubectl`.

| Krok | Akcja | Komentarz |
| --- | --- | --- |
| **0.** | **Napraw metrics-server** | Obecny stan nie działa. Sprawdź przyczynę: `kubectl -n kube-system logs deploy/metrics-server`. Często potrzeba dodatkowych args dla K3s (np. `--kubelet-insecure-tls`, `--kubelet-preferred-address-types=InternalIP,Hostname,InternalDNS,ExternalDNS`). Możesz poprawić `gitops/addons/values/metrics-server.yaml` i zsyncować ponownie. Metrics API przyda się do HPA/dashboardów. |
| **1.** | **Oczyść/usun stare monitoring** | Usuń zepsuty `gitops/addons/monitoring.yaml` (ma literówki i niepoprawną konfigurację). Nie commituj go w obecnej formie. |
| **2.** | **Stwórz strukturę** | Dodaj katalog `gitops/addons/values/monitoring/` i pliki wartości z pkt. 6. |
| **3.** | **Dodaj Applicationy** | Dodaj `kube-prometheus-stack.yaml`, `loki.yaml`, `tempo.yaml`, `alloy.yaml` do `gitops/addons/` (pkt. 7) z odpowiednimi `sync-wave`. |
| **4.** | **Commit + push** | ArgoCD (`addons` app-of-apps) wykryje nowe pliki i stworzy aplikacje. |
| **5.** | **Synchronicznie obserwuj** | Zacznij od `kube-prometheus-stack` (sync-wave 5). Potem Loki/Tempo (6), Alloy (7). W ArgoCD sprawdź sync/health. |
| **6.** | **Skonfiguruj dostęp do Grafany** | Ustal hasło admina (zmień `adminPassword` na silne, najlepiej przenieś do SealedSecret później). Dodaj adnotację Tailscale lub użyj port-forward na chwilę: `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80`. |
| **7.** | **Weryfikacja** | Grafana -> Connections/Datasources: powinny być Prometheus, Loki, Tempo (często auto-provisioned). Sprawdź Explore: metryki (up), logi (pod logs), traces (OTLP). |

## 10) Ważne uwagi dla tego środowiska

| Temat | Rekomendacja |
| --- | --- |
| **Storage** | Na start `local-path` wystarczający. Masz też `hcloud-volumes` (RWO) - lepiej na rzeczy krytyczne (dłuższe retencje) jeśli chcesz przetrwać utratę nod'a. Prometheus/Loki przy dużej retencji szybko zje miejsce. |
| **Zasoby** | CX23 ma ~4GB RAM. Ustal retencje: Prometheus 5-7 dni, Loki mniejsze (7 dni) na start. Obserwuj `kubectl top pods -n monitoring`. |
| **K3s specifics** | `metrics-server` zepsuty - napraw przed wdrożeniem dashboardów które mocno na nim polegają. Dodatkowo cAdvisor/kubelet są dostępne przez API. |
| **Tailscale only** | Nie musisz otwierać 80/443 na świat. Tailscale exposure wystarczające. Jeśli kiedyś dodasz publiczny ingress, pamiętaj o `80` zablokowanym obecnie w firewallu modułu. |
| **Sekrety** | `adminPassword` w plain YAML to na start OK, ale warto wdrożyć Sealed Secrets (w TODO wspomniane) i przechowywać w repo zaszyfrowane. |
| **CRDs** | `kube-prometheus-stack` instaluje sporo CRD (PrometheusRule, ServiceMonitor). Używaj `ServerSideApply=true` w syncOptions (dodałem wyżej) żeby uniknąć problemów z dużymi CRD. |
| **Alloy config** | Powyższa konfiguracja jest minimalna. Jeśli chcesz zbierać również logi systemowe/`/var/log/` bardziej szczegółowo, można rozbudować. Dla pod logów powyższe wystarczające. |
| **NetworkPolicy** | Brak - na homelab niekonieczne, ale warto rozważyć później. |

## 11) Szybki plan działania (checklist)

- [ ] **Naprawić `metrics-server`** - zbadać logi, poprawić args/values, doprowadzić do `Healthy/Synced`.
- [ ] **Usunąć zepsuty `gitops/addons/monitoring.yaml`**.
- [ ] **Stworzyć `gitops/addons/values/monitoring/`** z 4 plikami wartości.
- [ ] **Dodać 4 Applicationy ArgoCD** z sync waves 5-7.
- [ ] **Commit & push** - obserwować sync w ArgoCD.
- [ ] **Ustal dostęp do Grafany przez Tailscale** i zmienić hasło.
- [ ] **Zweryfikować datasources** (Prometheus/Loki/Tempo) i załadować podstawowe dashboardy.
- [ ] **Monitorować zasoby** przez pierwsze 24h (RAM/CPU/volumen).

## Podpowiedź przed startem

Zacznij **minimalnie**: tylko `kube-prometheus-stack` (metryki + Grafana). Gdy będzie stabilny, dodaj `loki` + `alloy`, na końcu `tempo`. Dzięki temu szybciej wyłapiesz problemy (CRD, zasoby, PVC) bez wdrożenia całego stosu naraz. 

To rozwiązanie jest zgodne z aktualnym kierunkiem Grafany (Alloy + LGTM) i idealnie wpisuje się w Twój model GitOps przez ArgoCD.
