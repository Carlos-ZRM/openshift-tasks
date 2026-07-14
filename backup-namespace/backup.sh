#!/bin/bash
set -euo pipefail

# Base directory where all namespace dumps will be stored
BASE_DIR="./oc-inspect-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BASE_DIR"

echo "Fetching namespaces..."
namespaces=$(oc get ns -o jsonpath='{.items[*].metadata.name}')

for ns in $namespaces; do
    ns_dir="${BASE_DIR}/${ns}"
    mkdir -p "$ns_dir"
    echo "Inspecting namespace: $ns -> $ns_dir"
    oc adm inspect "ns/${ns}" --dest-dir="$ns_dir" || echo "WARNING: inspect failed for $ns"
done

echo "Done. All inspect dumps saved under: $BASE_DIR"
