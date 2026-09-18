#!/usr/bin/env bash
# Renders every HelmRelease in the repository against the chart it names.
#
# This is the check that catches what kustomize cannot see: a chart version
# that was yanked, a repository that moved, a value the chart's own
# values.schema.json rejects, and a template that does not survive the values
# it was given.
#
# Values from `valuesFrom` are not resolved - they live in Kubernetes secrets
# that only exist on a cluster. Where a chart cannot render without one, a
# placeholder is supplied below.
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Repository name -> url and type, read out of the repository rather than
# repeated here.
declare -A repo_url repo_type
while read -r name url type; do
  [ -n "$name" ] || continue
  repo_url["$name"]="$url"
  repo_type["$name"]="$type"
done < <(yq -N \
  'select(.kind == "HelmRepository")
   | .metadata.name + " " + .spec.url + " " + (.spec.type // "default")' \
  platform/sources/helm-repositories.yaml)

# Two things a chart can see on a cluster and not here.
#
# `--api-versions` stands in for the CRDs another release installs: several
# charts gate a ServiceMonitor on the CRD being registered, which is true by
# the time Flux installs them and false in front of an empty API surface.
#
# The stubs stand in for `valuesFrom`, which reads secrets that only exist on
# a cluster. Only charts that refuse to render without a value need one.
api_versions=(--api-versions monitoring.coreos.com/v1)

declare -A stub=(
  [karpenter]="--set settings.clusterName=example --set settings.clusterEndpoint=https://example.invalid:6443"
  [talos-upgrades]="--set talosVersion=v0.0.0 --set kubernetesVersion=v0.0.0"
)

for name in "${!repo_url[@]}"; do
  [ "${repo_type[$name]}" = "oci" ] && continue
  helm repo add --force-update "$name" "${repo_url[$name]}" >/dev/null
done
helm repo update >/dev/null

while IFS= read -r file; do
  yq 'select(.kind == "HelmRelease")' "$file" > "$tmp/hr.yaml"
  [ -s "$tmp/hr.yaml" ] || continue

  release=$(yq '.metadata.name' "$tmp/hr.yaml")
  chart=$(yq '.spec.chart.spec.chart' "$tmp/hr.yaml")
  version=$(yq '.spec.chart.spec.version // ""' "$tmp/hr.yaml")
  source_kind=$(yq '.spec.chart.spec.sourceRef.kind' "$tmp/hr.yaml")
  source_name=$(yq '.spec.chart.spec.sourceRef.name' "$tmp/hr.yaml")
  namespace=$(yq '.spec.targetNamespace // "flux-system"' "$tmp/hr.yaml")

  yq '.spec.values // {}' "$tmp/hr.yaml" > "$tmp/values.yaml"

  args=(template "$release" --namespace "$namespace" --values "$tmp/values.yaml"
        "${api_versions[@]}")
  # shellcheck disable=SC2206  # deliberate word splitting: these are flags
  [ -n "${stub[$release]:-}" ] && args+=(${stub[$release]})

  if [ "$source_kind" = "GitRepository" ]; then
    # A chart in this repository. Its real values come from a secret, so
    # they are stubbed; the point is that the templates render.
    args+=("${chart#./}"
           --set amiID=ami-00000000000000000
           --set instanceProfile=example-worker
           --set discoveryTag=example
           --set userData='version: v1alpha1')
  elif [ "${repo_type[$source_name]:-default}" = "oci" ]; then
    args+=("${repo_url[$source_name]}/$chart" --version "$version")
  else
    args+=("$source_name/$chart" --version "$version")
  fi

  if helm "${args[@]}" > "$tmp/out.yaml" 2> "$tmp/err"; then
    printf '  %s (%s %s)\n' "$release" "$chart" "$version"
  else
    printf '  \033[31m%s (%s %s)\033[0m\n' "$release" "$chart" "$version"
    sed 's/^/    /' "$tmp/err"
    fail=1
  fi
done < <(grep -rl 'kind: HelmRelease' platform --include='*.yaml' | sort)

exit "$fail"
