# portfolio-gitops

Kubernetes configuration for [portfolio-web](https://github.com/vudaian24/portfolio-web), deployed by Argo CD to one Amazon EKS cluster in `ap-southeast-1`.

**Status:** Phase 1. Charts, ApplicationSets and bootstrap manifests are written and tested on a local kind cluster. The EKS cluster does not exist yet, and `charts/portfolio-web/values-prod.yaml` has no image tag until the first image is pushed to ECR.

| Chart | Upstream chart | Version |
| --- | --- | --- |
| `argocd` | `argo-cd` (Argo CD v3.5.5) | 10.10.5 |
| `aws-load-balancer-controller` | `aws-load-balancer-controller` | 3.6.1 |
| `external-secrets` | `external-secrets` | 2.13.0 |
| `kube-prometheus-stack` | `kube-prometheus-stack` | 92.11.0 |
| `portfolio-web` | none (app chart) | 0.1.0 |

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

## Check before pushing

Argo CD syncs every push to `main`, and nothing reviews it first. Run the same checks as CI:

```sh
./scripts/check.sh
```

It runs `helm dependency build`, `helm lint`, and `helm template --include-crds` piped into `kubeconform` (Kubernetes 1.36) for every chart, with placeholder values from `charts/<name>/ci/test-values.yaml`, then schema-checks `appsets/` and `bootstrap/`. Helm uses its own config and cache in a temporary directory. A resource without a schema fails the run. The only exception is the CustomResourceDefinition kind, which no schema catalog publishes, so CRD objects are skipped.

## Requirements

- `helm` 4 (v4.3.1 in CI) and `kubectl`
- `kubeconform`
- A local kind cluster (`kindest/node:v1.36.x`) for testing without AWS
