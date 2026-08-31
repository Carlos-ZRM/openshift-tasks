#!/usr/bin/env bash
set -euo pipefail

all_ns=$(oc get ns -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -vE '^(kube|openshift)' | sort)

deny_all_ns=$(oc get networkpolicy -A -o json | jq -r '
  .items[] | select(
    (.spec.podSelector == {}) and
    (.spec.ingress == null) and
    (.spec.egress == null)
  ) | .metadata.namespace
' | sort -u)

with_policy=()
without_policy=()

while IFS= read -r ns; do
  if echo "$deny_all_ns" | grep -qx "$ns"; then
    with_policy+=("$ns")
  else
    without_policy+=("$ns")
  fi
done <<< "$all_ns"

echo "=================================================="
echo " Namespaces WITH deny-all NetworkPolicy (${#with_policy[@]})"
echo "=================================================="
printf '  %s\n' "${with_policy[@]}"

echo ""
echo "=================================================="
echo " Namespaces WITHOUT deny-all NetworkPolicy (${#without_policy[@]})"
echo "=================================================="
printf '  %s\n' "${without_policy[@]}"
