#!/usr/bin/env bash
# Lint, render and schema-check every chart, then schema-check the Argo CD
# manifests. Needs helm and kubeconform; no cluster, no AWS credentials.
# Used by .github/workflows/k8s-ci.yml and before every push.
set -euo pipefail

KUBE_VERSION="${KUBE_VERSION:-1.36.0}"
# Built-in kinds from the default catalog; Argo CD, External Secrets and
# Prometheus CRDs from the datree CRDs catalog.
KUBECONFORM=(kubeconform -strict -summary -output text
  -kubernetes-version "${KUBECONFORM_KUBE_VERSION:-$KUBE_VERSION}"
  -schema-location default
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json')

cd "$(dirname "$0")/.."

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
  helm template "${name}" "${chart}" --namespace "${name}" \
    --kube-version "${KUBE_VERSION}" "${values[@]}" \
    | "${KUBECONFORM[@]}" -ignore-missing-schemas
done

echo "==> appsets and bootstrap"
"${KUBECONFORM[@]}" appsets bootstrap
