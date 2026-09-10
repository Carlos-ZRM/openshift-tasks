#!/usr/bin/env python3
"""
check-cve.py

Reads a list of CVE IDs from cve-in.txt, queries the Red Hat Security Data API
for each one, filters to CVEs that affect a product whose name contains
"OpenShift", and prints/saves the results ordered by threat_severity.

Usage:
    python3 check-cve.py
    python3 check-cve.py --input cve-in.txt --output cve-openshift.csv

Directory expected: /Users/creyesma/Documents/openshift-tasks/get-cve
"""

import argparse
import csv
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API_URL = "https://access.redhat.com/hydra/rest/securitydata/cve/{}.json"

# Red Hat threat_severity values, worst first, for sorting
SEVERITY_ORDER = {
    "Critical": 0,
    "Important": 1,
    "Moderate": 2,
    "Low": 3,
    "None": 4,
}


def load_cve_list(path: Path) -> list[str]:
    """Read CVE IDs from file, strip blanks, dedupe while preserving first-seen order."""
    seen = set()
    ordered = []
    with path.open() as f:
        for line in f:
            cve = line.strip()
            if not cve or cve in seen:
                continue
            seen.add(cve)
            ordered.append(cve)
    return ordered


def fetch_cve(cve_id: str, retries: int = 3, timeout: int = 15) -> dict | None:
    """Fetch CVE JSON from Red Hat API. Returns None on 404 or repeated failure."""
    url = API_URL.format(cve_id)
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(url, headers={"Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code == 404:
                print(f"  [{cve_id}] not found (404) - skipping", file=sys.stderr)
                return None
            print(f"  [{cve_id}] HTTP error {e.code} (attempt {attempt}/{retries})", file=sys.stderr)
        except (urllib.error.URLError, TimeoutError) as e:
            print(f"  [{cve_id}] network error: {e} (attempt {attempt}/{retries})", file=sys.stderr)
        time.sleep(1.5 * attempt)
    print(f"  [{cve_id}] giving up after {retries} attempts", file=sys.stderr)
    return None


def openshift_products(data: dict) -> list[str]:
    """Return the list of affected_release product_name values containing 'OpenShift'."""
    matches = []
    for rel in data.get("affected_release", []) or []:
        name = rel.get("product_name", "") or ""
        if "openshift" in name.lower():
            matches.append(name)
    # also check package_state (unfixed/affected without a release yet)
    for pkg in data.get("package_state", []) or []:
        name = pkg.get("product_name", "") or ""
        if "openshift" in name.lower():
            matches.append(f"{name} (package_state: {pkg.get('fix_state', '')})")
    return sorted(set(matches))


def main():
    parser = argparse.ArgumentParser(description="Filter CVEs affecting OpenShift, sorted by severity.")
    parser.add_argument("--input", default="cve-in.txt", help="Input file with one CVE ID per line")
    parser.add_argument("--output", default="cve-openshift.csv", help="Output CSV file")
    parser.add_argument("--delay", type=float, default=0.3, help="Seconds to sleep between API calls")
    args = parser.parse_args()

    base_dir = Path(__file__).resolve().parent
    input_path = Path(args.input)
    if not input_path.is_absolute():
        input_path = base_dir / input_path

    if not input_path.exists():
        print(f"Input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    cve_ids = load_cve_list(input_path)
    print(f"Loaded {len(cve_ids)} unique CVE ID(s) from {input_path}")

    results = []
    for i, cve_id in enumerate(cve_ids, 1):
        print(f"[{i}/{len(cve_ids)}] Checking {cve_id} ...")
        data = fetch_cve(cve_id)
        if data is None:
            continue

        products = openshift_products(data)
        if not products:
            continue

        results.append({
            "cve": cve_id,
            "threat_severity": data.get("threat_severity", "None"),
            "public_date": data.get("public_date", ""),
            "bugzilla": (data.get("bugzilla") or {}).get("url", ""),
            "products": "; ".join(products),
            "cvss3_score": (data.get("cvss3") or {}).get("cvss3_base_score", ""),
        })
        time.sleep(args.delay)

    # sort by severity (Critical first), then by CVE id
    results.sort(key=lambda r: (SEVERITY_ORDER.get(r["threat_severity"], 99), r["cve"]))

    output_path = base_dir / args.output
    fieldnames = ["cve", "threat_severity", "cvss3_score", "public_date", "products", "bugzilla"]
    with output_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)

    print(f"\n{len(results)} CVE(s) affect OpenShift. Results written to {output_path}\n")

    # pretty print to console too
    if results:
        col_widths = {
            "cve": 16,
            "threat_severity": 11,
            "cvss3_score": 6,
            "public_date": 12,
            "products": 60,
        }
        header = "".join(f"{h.upper():<{w}}" for h, w in col_widths.items())
        print(header)
        print("-" * len(header))
        for r in results:
            row = "".join(f"{str(r[h])[:w-1]:<{w}}" for h, w in col_widths.items())
            print(row)


if __name__ == "__main__":
    main()
