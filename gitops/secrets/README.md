# Secret Management

For Secret management in homelab cluster the Bitwarden with External Secret Operator is used
It allow easly using the Bitwarden as a Secret Manager.

How to configure Bitwarden Secret manager check [Bitwarden documentation](https://bitwarden.com/help/secrets-manager-kubernetes-operator/).

## Setup

> NOTE: Before configuring the External Secrets Operator with Bitwarden, create the
> `bitwarden-access-token` secret manually in Kubernetes. The secret must contain the
> Bitwarden token and be created in the same namespace as the External Secrets Operator.

To create this secret you can use following command:
```bash
kubectl create secret generic bitwarden-access-token  --namespace <namespace> --from-literal=token=<token_value>
```

Next check whether the secret exists:
```bash
kubectl get secret bitwarden-access-token -n <namespace>
```

After creation Secret Store you can create ExternalSecret for specific secret stored in bitwarden

Simple Example

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: example
spec:
  refreshInterval: 1h0m0s
  secretStoreRef:
    name: secretstore-sample
    kind: SecretStore
  target:
    name: secret-to-be-created
    creationPolicy: Owner
  data:
  - secretKey: secret-key-to-be-managed
    remoteRef:
      key: provider-key
      version: provider-key-versionś
      property: provider-key-property
  dataFrom:
  - extract:
      key: remote-key-in-the-provider
```
