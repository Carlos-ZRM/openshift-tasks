#!/usr/bin/env bash
#
# check-cve.sh
#
# Reads CVE IDs from cve-in.txt, queries the Red Hat Security Data API for
# each one, filters to CVEs that affect a product whose name contains
# "OpenShift", and prints the results ordered by threat_severity.
#
# Requires: curl, jq  (macOS: brew install jq)
#
# Usage:
#   ./check-cve.sh
#   ./check-cve.sh -i cve-in.txt -o cve-openshift.csv
#
# Directory expected: /Users/creyesma/Documents/openshift-tasks/get-cve

set -euo pipefail

INPUT="cve-in.txt"
OUTPUT="cve-openshift.csv"
DELAY="0.3"
API_URL="https://access.redhat.com/hydra/rest/securitydata/cve"

while getopts "i:o:d:h" opt; do
  case "$opt" in
    i) INPUT="$OPTARG" ;;
    o) OUTPUT="$OPTARG" ;;
    d) DELAY="$OPTARG" ;;
    h)
      echo "Usage: $0 [-i input_file] [-o output_csv] [-d delay_seconds]"
      exit 0
      ;;
    *) exit 1 ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed. Install with: brew install jq" >&2
  exit 1
fi

if [[ ! -f "$INPUT" ]]; then
  echo "Error: input file not found: $INPUT" >&2
  exit 1
fi

# dedupe while preserving order
mapfile -t CVE_LIST < <(awk '!seen[$0]++ && NF' "$INPUT")
echo "Loaded ${#CVE_LIST[@]} unique CVE ID(s) from $INPUT"

TMP_RESULTS=$(mktemp)
trap 'rm -f "$TMP_RESULTS"' EXIT

i=0
total=${#CVE_LIST[@]}
for cve in "${CVE_LIST[@]}"; do
  i=$((i + 1))
  echo "[$i/$total] Checking $cve ..." >&2

  http_code=$(curl -s -o /tmp/cve_response.json -w "%{http_code}" "$API_URL/${cve}.json" || echo "000")

  if [[ "$http_code" != "200" ]]; then
    echo "  [$cve] HTTP $http_code - skipping" >&2
    continue
  fi

  # Extract OpenShift-related product names from affected_release + package_state
  products=$(jq -r '
    ([.affected_release[]?.product_name // empty] +
     [.package_state[]?.product_name // empty])
    | map(select(test("openshift"; "i")))
    | unique
    | join("; ")
  ' /tmp/cve_response.json)

  if [[ -z "$products" ]]; then
    continue
  fi

  severity=$(jq -r '.threat_severity // "None"' /tmp/cve_response.json)
  cvss3=$(jq -r '.cvss3.cvss3_base_score // ""' /tmp/cve_response.json)
  public_date=$(jq -r '.public_date // ""' /tmp/cve_response.json)
  bugzilla=$(jq -r '.bugzilla.url // ""' /tmp/cve_response.json)

  # write pipe-delimited row: severity_rank|cve|severity|cvss3|public_date|products|bugzilla
  case "$severity" in
    Critical) rank=0 ;;
    Important) rank=1 ;;
    Moderate) rank=2 ;;
    Low) rank=3 ;;
    *) rank=4 ;;
  esac

  printf '%s|%s|%s|%s|%s|%s|%s\n' "$rank" "$cve" "$severity" "$cvss3" "$public_date" "$products" "$bugzilla" >> "$TMP_RESULTS"

  sleep "$DELAY"
done

rm -f /tmp/cve_response.json

# sort by severity rank, then CVE id
sort -t'|' -k1,1n -k2,2 "$TMP_RESULTS" > "${TMP_RESULTS}.sorted"

# write CSV
{
  echo "cve,threat_severity,cvss3_score,public_date,products,bugzilla"
  while IFS='|' read -r rank cve severity cvss3 public_date products bugzilla; do
    # basic CSV-safe quoting
    printf '"%s","%s","%s","%s","%s","%s"\n' "$cve" "$severity" "$cvss3" "$public_date" "$products" "$bugzilla"
  done < "${TMP_RESULTS}.sorted"
} > "$OUTPUT"

count=$(wc -l < "${TMP_RESULTS}.sorted" | tr -d ' ')
echo ""
echo "$count CVE(s) affect OpenShift. Results written to $OUTPUT"
echo ""

# pretty print table
printf '%-16s %-11s %-6s %-12s %s\n' "CVE" "SEVERITY" "CVSS3" "DATE" "PRODUCTS"
printf '%s\n' "--------------------------------------------------------------------------------"
while IFS='|' read -r rank cve severity cvss3 public_date products bugzilla; do
  printf '%-16s %-11s %-6s %-12s %s\n' "$cve" "$severity" "$cvss3" "${public_date:0:10}" "$products"
done < "${TMP_RESULTS}.sorted"

rm -f "${TMP_RESULTS}.sorted"

