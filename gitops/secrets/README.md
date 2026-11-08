# Secret Management

For Secret management in homelab cluster the Bitwarden with External Secret Operator is used
It allow easly using the Bitwarden as a Secret Manager.

## Setup

> NOTE: To configure External Secret operator with Bitwarden you have to create manually
> bitwarden-access-token secret in Kubernetes with token value in the same namespace as External Secret operator

To create this secret you can use following command:
```bash
kubectl create secret generic bitwarden-access-token  --namespace <namespace> --from-literal=token=<token_value>
```

Next check whether the secret exists:
```bash
kubectl get secret bitwarden-access-token -n <namespace>
```
