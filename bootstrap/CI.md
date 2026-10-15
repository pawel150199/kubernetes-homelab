# CI secrets for bootstrap deployment

The GitHub Actions workflow `.github/workflows/deploy-bootstrap.yml` uses the following repository/environment secrets (environment `homelab`):

| Secret | Used by | Purpose |
| --- | --- | --- |
| `AWS_ACCESS_KEY_ID` | `aws-actions/configure-aws-credentials` | AWS credentials for S3 Terraform backend (`kubernetes-homelab-tfstate`, key `terraform-bootstrap.tfstate`) |
| `AWS_SECRET_ACCESS_KEY` | `aws-actions/configure-aws-credentials` | AWS secret key |
| `HCLOUD_TOKEN` | Terraform (passed as env var) | Hetzner Cloud API token (if referenced) |
| `KUBE_CONFIG` | Workflow step "Setup kube config" | Cluster kubeconfig (written to `bootstrap/.kube/config`). Must point to the Tailscale-reachable API server endpoint (not localhost) whose cert includes the address. |
| `CI_TAILSCALE_OAUTH_CLIENT_ID` | `tailscale/github-action@v4` | Tailscale OAuth client ID for CI runner to join tailnet |
| `CI_TAILSCALE_OAUTH_CLIENT_SECRET` | `tailscale/github-action@v4` | Tailscale OAuth client secret for CI runner |
| `TAILSCALE_OAUTH_CLIENT_ID` | Terraform via `TF_VAR_tailscale_oauth_client_id` | Tailscale OAuth client ID for the Tailscale operator (passed to Helm chart) |
| `TAILSCALE_OAUTH_CLIENT_SECRET` | Terraform via `TF_VAR_tailscale_oauth_client_secret` | Tailscale OAuth client secret for the Tailscale operator |

Notes:
- The operator OAuth client is different from the CI OAuth client and from the node `TAILSCALE_AUTH_KEY`.
- The kubeconfig in CI must be the one that works over Tailscale (replace `127.0.0.1` with e.g. `master-node-0.<tailnet>.ts.net` as documented in README).
- Secrets are stored in GitHub repository secrets for the `homelab` environment; never commit them.
