# portfolio-gitops

Kubernetes configuration for [portfolio-web](https://github.com/vudaian24/portfolio-web), deployed by Argo CD to one Amazon EKS cluster in `ap-southeast-1`.

**Status:** layout only. The directories are empty placeholders.

This repository holds config, not source code, following the [Argo CD best practice](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/) of keeping manifests in their own repository. The app code and its image build live in `portfolio-web`. AWS and Cloudflare resources live in `portfolio-infra` (Terraform). Design records live in the private workspace repo.

## Layout

```text
bootstrap/                  Applied by hand once per cluster. Not managed by Argo CD.
                            The in-cluster Argo CD cluster secret (labels only) and the root Application.
appsets/
  platform/                 One ApplicationSet per add-on: Argo CD, AWS Load Balancer Controller,
                            External Secrets, kube-prometheus-stack.
  apps/                     ApplicationSet for portfolio-web.
charts/                     One chart per add-on, plus the app chart.
  argocd/                   Wrapper chart: upstream argo-cd.
  aws-load-balancer-controller/
                            Wrapper chart: upstream aws-load-balancer-controller.
  external-secrets/         Wrapper chart: upstream external-secrets, plus the ClusterSecretStore.
  kube-prometheus-stack/    Wrapper chart: upstream kube-prometheus-stack, plus Grafana dashboards.
  portfolio-web/            App chart: Deployment, Service, Ingress, HPA, ExternalSecret.
                            values-prod.yaml holds the image tag that portfolio-web CI updates.
```

## How it fits together

1. `portfolio-web` CI builds a `linux/arm64` image, pushes it to ECR with the git SHA as tag, and commits the tag to `charts/portfolio-web/values-prod.yaml` here.
2. Argo CD polls this repository and syncs the change.
3. Values that come from Terraform and identify the AWS account (ECR registry host, VPC ID) are never committed. They are annotations on the `in-cluster` Argo CD cluster secret, and the ApplicationSets pass them to the charts as Helm parameters.

## Requirements

- `helm` and `kubectl`
- `kubeconform` (optional, for schema checks)
- A local kind or k3d cluster for testing without AWS
