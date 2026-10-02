# Workshop Shop - Platform Repository

This repository contains the Terraform infrastructure, Argo CD
configuration, and Kubernetes manifests for the workshop
*"Build a CI/CD Pipeline on Amazon EKS with Terraform, GitHub Actions, and Argo CD"*.

> The shopping application and its GitHub Actions workflow live in a
> separate repository: **`<APP_REPO_URL_PLACEHOLDER>`**
> (replace with your `shop-app` repository URL).

## Architecture

```
 Developer edits app code (price, banner, ...)
        │
        ▼
 git push → shop-app (main)
        │
        ▼
 GitHub Actions (in shop-app)
   1. Build Docker image
   2. Push image to Amazon ECR, tagged with the commit SHA
   3. Checkout shop-platform
   4. Update gitops/deployment.yaml with the new image
   5. Commit + push to shop-platform (main)
        │
        ▼
 Argo CD (running in EKS, watching shop-platform's gitops/ directory)
   - Detects the new commit
   - Syncs the Deployment + Service to the workshop-shop namespace
        │
        ▼
 Amazon EKS cluster
   - Workshop Shop pods updated, accessible via kubectl port-forward
```

**Division of responsibility**, which is the core idea of this workshop:

- **GitHub Actions** (in `shop-app`) handles **CI**: building the image
  and updating the deployment manifest. It is never given Kubernetes or
  EKS credentials.
- **Argo CD** (installed by this repository's Terraform, configured by
  `argocd/application.yaml`) handles **CD**: it watches this repository's
  `gitops/` directory and applies whatever it finds there to the cluster.
- **Terraform** (`terraform/infrastructure` and `terraform/argocd`, both
  in this repository) creates the AWS infrastructure once, before the
  workshop, and installs Argo CD.

## What is GitOps / Argo CD, in plain language

Instead of a CI pipeline running `kubectl apply` against your cluster
(which means CI needs cluster credentials), GitOps flips it around:

- Git holds the **desired state** of what should be running (here,
  `gitops/deployment.yaml` and `gitops/service.yaml`).
- **Argo CD runs inside the cluster** and continuously compares that
  desired state to what's actually running.
- If they differ - a new commit, or someone manually changing something
  with `kubectl` - Argo CD reconciles the cluster to match Git again.

This is what `automated: { prune: true, selfHeal: true }` in
`argocd/application.yaml` means: automatically apply new commits
(`prune` removes anything deleted from Git, `selfHeal` reverts manual
cluster changes). No component outside the cluster ever needs
`kubectl` access to deploy - only to *watch*.

## Project layout

```
terraform/
  infrastructure/   VPC, EKS cluster, node group, ECR, GitHub OIDC/IAM (creates AWS resources)
  argocd/           Installs Argo CD onto the existing cluster via Helm
argocd/
  application.yaml  The Argo CD Application - applied manually with kubectl, not Terraform
gitops/
  deployment.yaml   Workshop Shop Deployment (image updated automatically by CI)
  service.yaml      ClusterIP Service for Workshop Shop
```

`argocd/application.yaml` is deliberately **outside** `gitops/`, so Argo
CD (which only watches `gitops/`) never tries to manage itself.

## Reference documentation used for versions in this repository

- [terraform-aws-modules/vpc](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest)
- [terraform-aws-modules/eks](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)
- [Amazon EKS supported Kubernetes versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions-standard.html)
- [argo-helm (argo-cd chart) releases](https://github.com/argoproj/argo-helm/releases)
- [EKS access entries / cluster access policies](https://docs.aws.amazon.com/eks/latest/userguide/access-policies.html)

Terraform module and chart versions are pinned in each root's
`versions.tf` / `variables.tf` - check those files' comments before
upgrading.

## Local state (workshop only)

Both Terraform roots use **local state** (the default `terraform.tfstate`
file on disk) to keep the workshop simple - there is no backend
configuration. This means:

- State only exists on whoever's machine ran `apply`.
- Don't run `apply` from two different machines against the same state.

A real/production setup would use a **remote backend** (e.g. an S3
bucket + DynamoDB lock table, or Terraform Cloud) so state is shared,
locked, and durable. `terraform.tfstate*` and `*.tfvars` are gitignored;
provider lock files (`.terraform.lock.hcl`) **are** committed, so
everyone resolves the same provider versions.

## Cost note

Running the infrastructure in this repository costs real money for as
long as it exists - roughly, per hour, in `eu-west-2`:

- **EKS cluster**: a fixed hourly charge for the control plane.
- **EC2 nodes**: 2x `t3.medium` (the managed node group's desired size).
- **NAT gateway**: one, hourly charge plus data processing charges.
- **ECR**: storage cost only, based on image size - negligible for a demo image.

None of this is large for a 90-minute workshop, but it is **not free**,
and it keeps accruing until you destroy it (see Cleanup below). Avoid
leaving it running overnight or over a weekend by accident.

---

## Setup order

Run steps 1-8 **before** the live workshop. Steps 9-15 are the live
demo.

### 1. Create and push both public GitHub repositories

Create `shop-app` and `shop-platform` as public repositories on GitHub
and push each directory's contents to the matching repository.

### 2. Authenticate to AWS and verify the operator identity

```bash
aws sts get-caller-identity
```

Confirm this prints the IAM identity you intend to use as the workshop
operator (its ARN is `operator_principal_arn` in the next step).

### 3. Configure Terraform variables with the application repository identity

```bash
cd terraform/infrastructure
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: github_repository_owner, operator_principal_arn, admin_cidr, etc.
```

### 4. Apply terraform/infrastructure

```bash
terraform init
terraform fmt -check
terraform validate
terraform apply
```

**Verify:**

```bash
terraform output
```

### 5. Configure kubectl and verify nodes

```bash
aws eks update-kubeconfig --region eu-west-2 --name "$(terraform output -raw cluster_name)"
kubectl get nodes
```

### 6. Apply terraform/argocd

```bash
cd ../argocd
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: cluster_name must match terraform/infrastructure's output
terraform init
terraform fmt -check
terraform validate
terraform apply
```

**Verify:**

```bash
kubectl -n argocd get pods
```

### 7. Set application repository variables from Terraform outputs

In the `shop-app` repository, under **Settings -> Secrets and variables
-> Actions -> Variables**, create `AWS_REGION`, `AWS_ROLE_ARN`,
`ECR_REPOSITORY_URL`, and `GITOPS_REPOSITORY` using the values from:

```bash
cd ../infrastructure
terraform output
```

(`GITOPS_REPOSITORY` is not a Terraform output - it's your
`shop-platform` repository, in `owner/repository` format.)

### 8. Create the scoped GITOPS_TOKEN and save it as an Actions secret

Create a fine-grained GitHub personal access token restricted to the
`shop-platform` repository, with repository permission **Contents: Read
and write**. Save it as the `GITOPS_TOKEN` secret in the `shop-app`
repository (see that repository's README for details and organisation
approval notes).

---

### 9. Manually run the application workflow

In `shop-app`, go to **Actions -> Build and Update GitOps -> Run workflow**.

### 10. Verify that the image exists in ECR and the platform manifest has been updated

```bash
aws ecr list-images --repository-name workshop-shop
git -C shop-platform pull && cat shop-platform/gitops/deployment.yaml
```

Confirm the `image:` line next to `# workshop-shop-image` is no longer
the placeholder.

### 11. Update the repository URL in argocd/application.yaml

Replace `<PLATFORM_REPO_URL_PLACEHOLDER>` in
[`argocd/application.yaml`](argocd/application.yaml) with this
repository's public HTTPS URL, then commit and push.

### 12. Apply the Argo CD Application

```bash
kubectl apply -f argocd/application.yaml
```

**Verify:**

```bash
kubectl -n argocd get applications
```

### 13. Access Argo CD and Workshop Shop using port-forward

```bash
# Argo CD UI
kubectl -n argocd port-forward svc/argocd-server 8080:443
# then open https://localhost:8080

# Workshop Shop
kubectl -n workshop-shop port-forward svc/workshop-shop 3000:80
# then open http://localhost:3000
```

To log in to Argo CD (username `admin`), retrieve the initial password
**without** ever saving it in source code or Terraform state:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

### 14. Change a product price and banner in the application repository

Edit `app/products.json` and the `STORE_BANNER` constant in
`app/server.js` in `shop-app`, then commit and push to `main`.

### 15. Watch GitHub Actions update the platform repository and Argo CD deploy the change

Watch the `shop-app` Actions tab, then:

```bash
kubectl -n argocd get applications workshop-shop -w
```

Refresh the Workshop Shop tab in your browser once the sync completes.

---

## Verification commands reference

| Step | Command |
|---|---|
| Infrastructure applied | `terraform output` (in `terraform/infrastructure`) |
| Nodes ready | `kubectl get nodes` |
| Argo CD running | `kubectl -n argocd get pods` |
| Image pushed | `aws ecr list-images --repository-name workshop-shop` |
| Manifest updated | `cat gitops/deployment.yaml` |
| Application synced | `kubectl -n argocd get application workshop-shop` |
| Pods healthy | `kubectl -n workshop-shop get pods` |

## 90-minute workshop agenda

| Time | Activity |
|---|---|
| 0:00-0:10 | Welcome; walk through the architecture diagram above |
| 0:10-0:25 | Tour the Terraform code (`terraform/infrastructure`) - VPC, EKS, IAM/OIDC. Cluster is already provisioned - we read the code, not `apply` it live |
| 0:25-0:35 | Explain GitOps and Argo CD; tour `argocd/application.yaml` and `gitops/` |
| 0:35-0:40 | Verify the environment together: `kubectl get nodes`, open the Argo CD UI |
| 0:40-0:55 | Live demo: edit a product price and the banner in `shop-app`, push, watch GitHub Actions build the image and update the manifest |
| 0:55-1:05 | Watch Argo CD auto-sync; verify the change in the browser via port-forward |
| 1:05-1:20 | Hands-on: students make their own small change (different price/banner text), or intentionally break the image marker and practice the troubleshooting table below |
| 1:20-1:30 | Recap; walk through the cleanup steps; Q&A |

## Troubleshooting

### EKS

| Symptom | Likely cause |
|---|---|
| `kubectl` times out or `Unauthorized` | Re-run `aws eks update-kubeconfig`; confirm your IAM identity matches `operator_principal_arn` or the identity that ran `terraform apply` |
| Public API access denied from your IP | `admin_cidr` doesn't match your current public IP - check with `curl -s https://checkip.amazonaws.com` and update the Terraform variable |
| Nodes stuck `NotReady` | Check `kubectl describe node <name>`; usually a networking/add-on issue - confirm the `vpc-cni` addon is `ACTIVE` in the EKS console |

### Argo CD

| Symptom | Likely cause |
|---|---|
| `kubectl -n argocd get pods` shows pods not `Running` | Wait a minute after `terraform apply` for the Helm chart's pods to start; check `kubectl -n argocd describe pod <name>` if it persists |
| Application shows `Unknown` or won't sync | Confirm `argocd/application.yaml`'s `repoURL` is correct and the repository is public |
| Application `OutOfSync` forever | Check `gitops/deployment.yaml` for a YAML syntax error from a manual edit |
| Pods stuck `ImagePullBackOff` | The image placeholder was never replaced, or `ECR_REPOSITORY_URL` / IAM permissions are wrong - see step 10 above |
| Can't log in to Argo CD | Re-fetch the initial admin password (step 13) - it's only stored in the `argocd-initial-admin-secret` Kubernetes secret, never in Git or Terraform state |

---

## Cleanup

Clean up in this exact order - deleting Terraform-managed resources
*before* telling Argo CD to stop would just have Argo CD recreate them.

### 1. Disable Argo CD automatic sync for the application

```bash
kubectl -n argocd patch application workshop-shop \
  --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
```

This stops Argo CD from recreating resources as you delete them in the
next step.

### 2. Delete the Argo CD Application and the shopping application resources

```bash
kubectl delete -f argocd/application.yaml
kubectl delete namespace workshop-shop
```

### 3. Destroy terraform/argocd while the cluster still exists

```bash
cd terraform/argocd
terraform destroy
```

This must run **before** the cluster is destroyed - the Helm provider
needs a live cluster to uninstall Argo CD's resources from.

### 4. Destroy terraform/infrastructure

```bash
cd ../infrastructure
terraform destroy
```

### Handling a non-empty ECR repository

`aws_ecr_repository.shop` is configured with `force_delete = true`, so
`terraform destroy` removes the repository even if it still contains
images - there's no need to empty it manually first for this disposable
workshop repository. (In a real project you would usually leave
`force_delete` off, and either keep the repository or empty it
deliberately with `aws ecr batch-delete-image` before destroying.)
