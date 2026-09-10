#!/usr/bin/env bash
set -euo pipefail

excluded_ns=$(oc get ns -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -E '^(kube|openshift)')

oc get route -A -o json | jq -r --arg excluded "$(echo "$excluded_ns" | tr '\n' '|')" '
  ($excluded | rtrimstr("|") | split("|")) as $exclist |
  .items[]
  | select(.metadata.namespace as $ns | $exclist | index($ns) | not)
  | [
      .metadata.namespace,
      .metadata.name,
      (.spec.tls.termination // "none"),
      (.spec.tls.insecureEdgeTerminationPolicy // "empty")
    ] | @tsv
' > /tmp/routes_raw.tsv

http_routes=()
https_allow_empty=()
https_redirect_deny=()

while IFS=$'\t' read -r ns name termination policy; do
  if [ "$termination" == "none" ]; then
    http_routes+=("$ns/$name")
  else
    if [ "$policy" == "Allow" ] || [ "$policy" == "empty" ]; then
      https_allow_empty+=("$ns/$name (termination=$termination, policy=$policy)")
    elif [ "$policy" == "Redirect" ] || [ "$policy" == "None" ]; then
      https_redirect_deny+=("$ns/$name (termination=$termination, policy=$policy)")
    fi
  fi
done < /tmp/routes_raw.tsv

rm -f /tmp/routes_raw.tsv

echo "=================================================="
echo " Routes with HTTP termination (no TLS) (${#http_routes[@]})"
echo "=================================================="
printf '  %s\n' "${http_routes[@]:-(none)}"

echo ""
echo "=================================================="
echo " Routes with HTTPS/TLS - policy Allow or empty (${#https_allow_empty[@]})"
echo "=================================================="
printf '  %s\n' "${https_allow_empty[@]:-(none)}"

echo ""
echo "=================================================="
echo " Routes with HTTPS/TLS - policy Redirect or Deny/None (${#https_redirect_deny[@]})"
echo "=================================================="
printf '  %s\n' "${https_redirect_deny[@]:-(none)}"
