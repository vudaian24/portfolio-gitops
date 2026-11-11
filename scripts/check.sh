#!/usr/bin/env bash
# Lint, render and schema-check every chart, then schema-check the Argo CD
# manifests. Needs helm and kubeconform; no cluster, no AWS credentials.
# Used by .github/workflows/k8s-ci.yml and before every push.
set -euo pipefail

KUBE_VERSION="${KUBE_VERSION:-1.36.0}"

cd "$(dirname "$0")/.."

# Own Helm config and cache, so `repo add` and `dependency build` never touch
# the global Helm setup of the developer or the CI runner.
helm_home="$(mktemp -d)"
trap 'rm -rf "${helm_home}"' EXIT
export HELM_REPOSITORY_CONFIG="${helm_home}/repositories.yaml"
export HELM_REPOSITORY_CACHE="${helm_home}/cache"
export HELM_CACHE_HOME="${helm_home}/cache"
export HELM_CONFIG_HOME="${helm_home}/config"
export HELM_DATA_HOME="${helm_home}/data"

# Commit of github.com/datreeio/CRDs-catalog the CRD schemas are read from
# (2026-11-08). Pinned so a change in the catalog cannot change the result of
# a run; move it forward when a chart bump brings a kind the catalog lacks.
CRDS_CATALOG_REF="${CRDS_CATALOG_REF:-49729e49e8f062933e3716a26540d41b0cd0856c}"

# Built-in kinds from the default catalog; Argo CD, External Secrets, Prometheus
# and AWS CRDs from the datree CRDs catalog. No -ignore-missing-schemas: a
# resource without a schema fails the run.
# Narrow allow-list: no catalog publishes the schema of the
# CustomResourceDefinition kind itself, so CRD objects are skipped. Their
# content is checked by the Kubernetes API when Argo CD applies them.
KUBECONFORM=(kubeconform -strict -summary -output text
  -kubernetes-version "${KUBECONFORM_KUBE_VERSION:-$KUBE_VERSION}"
  -skip CustomResourceDefinition
  -schema-location default
  -schema-location "https://raw.githubusercontent.com/datreeio/CRDs-catalog/${CRDS_CATALOG_REF}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json")

# `helm dependency build` needs every chart repository registered first.
grep -h '^ *repository:' charts/*/Chart.yaml | awk '{print $2}' | sort -u |
  while read -r url; do
    helm repo add "$(echo "${url#https://}" | tr -c 'a-zA-Z0-9\n' '-')" "${url}" --force-update >/dev/null
  done

for chart in charts/*/; do
  chart="${chart%/}"
  name="$(basename "$chart")"
  echo "==> ${name}"

  values=()
  [[ -f "${chart}/values-prod.yaml" ]] && values+=(-f "${chart}/values-prod.yaml")
  [[ -f "${chart}/ci/test-values.yaml" ]] && values+=(-f "${chart}/ci/test-values.yaml")

  if grep -q '^dependencies:' "${chart}/Chart.yaml"; then
    helm dependency build "${chart}" >/dev/null
  fi
  helm lint "${chart}" "${values[@]}"
  # --include-crds: Argo CD renders the chart's crds/ directory too.
  helm template "${name}" "${chart}" --namespace "${name}" --include-crds \
    --kube-version "${KUBE_VERSION}" "${values[@]}" \
    | "${KUBECONFORM[@]}"
done

# portfolio-web again, with the image tag that is committed and that Argo CD
# will deploy. The render above takes the tag from ci/test-values.yaml, which
# overrides values-prod.yaml, so a bad tag written by the release pipeline got
# through. Only the registry is a placeholder here; the chart itself refuses a
# tag that is not a 40-character git SHA.
echo "==> portfolio-web (committed image tag)"
prod_values="charts/portfolio-web/values-prod.yaml"
if [[ "$(grep -c '^  tag: ' "${prod_values}")" != "1" ]] ||
   [[ "$(grep -c '^  tag: "[^"]*"$' "${prod_values}")" != "1" ]]; then
  echo "unexpected layout in ${prod_values}: want exactly one line of the form '  tag: \"<sha>\"'" >&2
  exit 1
fi
if grep -q '^  tag: ""$' "${prod_values}"; then
  # A new cluster before the bootstrap deploy of portfolio-web.
  echo "image.tag is empty (no deploy yet); nothing to render"
else
  helm template portfolio-web charts/portfolio-web --namespace portfolio-web \
    --kube-version "${KUBE_VERSION}" -f "${prod_values}" \
    --set-string image.registry=000000000000.dkr.ecr.ap-southeast-1.amazonaws.com \
    | "${KUBECONFORM[@]}"
fi

echo "==> appsets and bootstrap"
"${KUBECONFORM[@]}" appsets bootstrap
