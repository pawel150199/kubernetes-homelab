# Infrastructure for Kuberentes Homelab

The whole infrastructure needed for setting up a Kubernetes homelab is located in the Hetzner Cloud Provider (except S3 Storage where terraform state is stored).
I am using the terraform module for setting up the K3S cluster (module uses the k3s for setting up Kubernetes).
[Module reference](!https://github.com/pawel150199/hcloud-k8s-cluster).

## How to run this terraform code

### Prerequisites

Before running the terraform code, make sure you have the following installed:

- [Terraform](https://www.terraform.io/downloads)
- [AWS CLI](https://aws.amazon.com/cli/)

Then, you have to prepare some prerequisites, such as S3 bucket, Hetner API token, and any other necessary credentials.

- Configure AWS CLI with your credentials

    ```bash
    aws configure --profile private
    ```

- Confirm AWS CLI is configured correctly

    ```bash
    aws sts get-caller-identity --profile private
    ```

- Create S3 bucket in AWS for storing terraform state.

    ```bash
    aws configure --profile private
    aws s3api create-bucket \
        --bucket kubernetes-homelab \
        --region eu-central-1
    ```

- Obtain Hetzner API token and configure it as an environment variable (token has to have read and write permissions):

    ```bash
    export HCLOUD_TOKEN="your_hetzner_api_token"
    ```

### Run terraform code

1. Initialize the terraform configuration:

   ```bash
   terraform init
   ```

2. Review the terraform plan:

   ```bash
   terraform plan
   ```

3. Apply the terraform configuration:

   ```bash
   terraform apply
   ```

## Connect to Kubernetes Cluster

After applying the terraform configuration, you can connect to your Kubernetes cluster using `kubectl`. The K3S module should generate a kubeconfig file for you.

1. Export the KUBECONFIG from the master node:

    ```bash
    scp -i ~/.ssh/id_rsa cluster@<master_ip_address>:/etc/rancher/k3s/k3s.yaml ~/.kube/config
    ```

2. Config copied from master node probably has the wrong it (127.0.0.1) of kube-api so change it to the master node's IP address.
3. Verify the connection to the cluster:

    ```bash
    kubectl get nodes
    ```
