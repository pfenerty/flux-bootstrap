#!/usr/bin/env bash
# Everything CI checks, runnable locally. Needs kustomize, kubeconform, helm
# and yq on PATH.
#
#   1. Every kustomization builds.
#   2. What they build validates against the Kubernetes and CRD schemas.
#   3. Every HelmRelease names a chart that exists at the version it asks
#      for, and its values render.
#
# Nothing here talks to a cluster.
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0
note() { printf '\n\033[1m%s\033[0m\n' "$*"; }
bad() { printf '  \033[31m%s\033[0m\n' "$*"; fail=1; }
ok() { printf '  %s\n' "$*"; }

# Kubernetes' own schemas do not cover custom resources, so CRD schemas come
# from the CRDs-catalog. A kind that is in neither is skipped rather than
# failed: -ignore-missing-schemas keeps a new CRD from breaking the build,
# at the cost of not checking it.
CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
KUBE_VERSION="${KUBE_VERSION:-1.34.0}"

# tuppr's two kinds are skipped rather than validated, for two reasons that
# both resolve on their own eventually.
#
# The catalog's copy of their schemas is well behind the chart version pinned
# in platform/infrastructure/tuppr - it has no prePull, waitForVolumeDetach,
# nodeSelector, hooks, maintenance or parallelism - so it rejects fields that
# are valid in the release actually installed. And the manifests carry
# `${talos_version}` placeholders that Flux substitutes at apply, which no
# version string pattern will ever match.
#
# What does validate them is the CRD in the cluster: kustomize-controller
# applies these through the API server, which rejects a bad field there.
SKIP_KINDS='TalosUpgrade,KubernetesUpgrade'

note "kustomize build"
builds=$(mktemp -d)
trap 'rm -rf "$builds"' EXIT

while IFS= read -r dir; do
  name=$(echo "${dir#./}" | tr '/' '_')
  if kustomize build "$dir" > "$builds/$name.yaml" 2> "$builds/$name.err"; then
    ok "$dir"
  else
    bad "$dir"
    sed 's/^/    /' "$builds/$name.err"
  fi
done < <(find . -name kustomization.yaml -not -path './.git/*' -printf '%h\n' | sort)

note "kubeconform"
for f in "$builds"/*.yaml; do
  [ -s "$f" ] || continue
  if kubeconform \
    -strict \
    -ignore-missing-schemas \
    -skip "$SKIP_KINDS" \
    -kubernetes-version "$KUBE_VERSION" \
    -schema-location default \
    -schema-location "$CRD_SCHEMAS" \
    -summary "$f" 2>&1 | sed 's/^/  /'
  then :; else bad "$(basename "$f")"; fi
done

# The cluster directories have no kustomization.yaml - kustomize-controller
# generates one from whatever yaml it finds - so they are validated as plain
# files rather than built.
note "kubeconform: clusters/"
if kubeconform \
  -strict \
  -ignore-missing-schemas \
  -kubernetes-version "$KUBE_VERSION" \
  -schema-location default \
  -schema-location "$CRD_SCHEMAS" \
  -summary clusters 2>&1 | sed 's/^/  /'
then :; else bad "clusters/"; fi

note "helm template"
./scripts/render-helmreleases.sh || fail=1

if [ "$fail" -ne 0 ]; then
  printf '\n\033[31mFAILED\033[0m\n'
  exit 1
fi
printf '\n\033[32mOK\033[0m\n'
