# AGENTS.md — portfolio-gitops

Kubernetes configuration for the portfolio, deployed by Argo CD to one EKS cluster in `ap-southeast-1`. Public repo: github.com/vudaian24/portfolio-gitops. Migration design and cross-repo rules live in the parent `../docs/`; this file covers this repo only.

## Current state

- Live: Argo CD runs on the EKS cluster and syncs every add-on and `portfolio-web` from `main`. `portfolio-web` serves production.
- `charts/portfolio-web/values-prod.yaml` holds the live image tag, written by `portfolio-web` CI. The chart refuses to render with an empty tag, so never empty it.
- ApplicationSets set `preserveResourcesOnDeletion: true` and add no finalizer to Applications, so deleting a file in `appsets/` removes the Application but leaves the workload running.
- `.github/workflows/notify-workspace.yml`: on push to `main`, sends `repository_dispatch` (`submodule-updated`) to the private workspace repo `portfolio`, which then bumps its submodule pointer. Uses a GitHub App token (repository variable `WORKSPACE_SYNC_APP_CLIENT_ID`, repository secret `WORKSPACE_SYNC_APP_PRIVATE_KEY`); skipped while the variable is unset.
- The design is in the parent `docs/`. Follow the parent docs when they conflict.

## Layout

- `bootstrap/`: the `in-cluster` Argo CD cluster secret (labels only) and the root Application. Applied by hand once; not managed by Argo CD.
- `appsets/portfolio-project.yaml`: the AppProject `portfolio` that every generated Application uses. The root Application applies it first (sync-wave -1).
- `scripts/check.sh`: the same checks CI runs.
- `appsets/platform/`: one ApplicationSet per add-on. `appsets/apps/`: the `portfolio-web` ApplicationSet. The root Application syncs `appsets/` recursively.
- `charts/<add-on>/`: wrapper chart with the upstream chart as its only dependency, plus our own templates. `charts/portfolio-web/`: the app chart.

## Conventions

- Wrapper charts: `apiVersion: v2`, one dependency with an exact version, `Chart.lock` committed. Downloaded archives (`charts/*/charts/`) are git-ignored.
- Exception: an add-on whose upstream chart cannot meet these rules gets our own chart with no dependency and top-level values. `cloudflared` will be the first, because Cloudflare's chart takes the tunnel token as a Helm value (parent `docs/adr/0010-cloudflared-chart-and-admin-ui-roles.md`); it is not written yet, so every chart in `charts/` today has one upstream dependency except the app chart.
- Values live in each chart's `values.yaml`, nested under the dependency name, with explicit CPU and memory requests and limits. Do not put Helm values in ApplicationSets; their only parameters come from cluster secret annotations.
- Own templates: one resource per file, kind in the file name (`cluster-secret-store.yaml`), helpers in `_helpers.tpl` prefixed with the chart name.
- Leave `replicas` out of the app Deployment; the HPA owns it.
- ApplicationSets: cluster generator matching only the `in-cluster` secret, `goTemplate: true` with `missingkey=error`, automated sync with prune and self-heal, retry with backoff, `CreateNamespace=true`.
- Every chart must render with `helm dependency build` and `helm template`, with no cluster and no Argo CD.
- Only `portfolio-web` CI writes to `charts/portfolio-web/values-prod.yaml`, and only the image tag.
- Commits: conventional commits with one of `feat`, `fix`, `chore`, `docs`, `perf`.

## Commands

- Check everything (same as CI): `./scripts/check.sh`. Needs `helm` and `kubeconform`.
- Render one chart: `helm dependency build charts/<name> && helm template <name> charts/<name>`. Add `-f charts/<name>/ci/test-values.yaml` only for charts that have one (`aws-load-balancer-controller` and `portfolio-web` today); `scripts/check.sh` applies the file when it exists.
- Bump an upstream chart: change the version in `Chart.yaml`, run `helm dependency update charts/<name>`, commit `Chart.yaml` and `Chart.lock`.

## Never do

- Never commit the AWS account ID, the ECR registry host, the VPC ID or any secret value. Secrets come from SSM Parameter Store through External Secrets.
- Never run `kubectl apply`, `helm install` or `argocd app sync` against the EKS cluster. A local kind or k3d cluster is fine.
- Deleting a file in `appsets/` removes that Application as soon as it is pushed. The workload keeps running unmanaged. Confirm with the user first and say so in the commit message.
- This repo is also checked out as a submodule of the `portfolio` workspace repo. Push changes here first; the workspace records the new commit afterwards.
- Commit on `main` and push it directly; there are no pull requests. Argo CD syncs every push, so render each changed chart with `helm template` before pushing.
