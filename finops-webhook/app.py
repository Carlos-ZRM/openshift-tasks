"""
FinOps Admission Webhook (demo)

/mutate   -> Hereda labels FinOps (cost-center, team, environment) del Namespace
             y pone requests por defecto a contenedores que no los tienen.
/validate -> Rechaza workloads sin labels FinOps, con cost-center fuera de catálogo,
             environment inválido, o que piden demasiado CPU en dev.

Aplica a Pods (CREATE) y Deployments (CREATE/UPDATE).
"""
import base64
import json
import logging
import os

import requests
from flask import Flask, jsonify, request

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("finops-webhook")

FINOPS_LABELS = ["cost-center", "team", "environment"]
ALLOWED_COST_CENTERS = {
    c.strip() for c in os.getenv("ALLOWED_COST_CENTERS", "CC-1001,CC-2002").split(",") if c.strip()
}
ALLOWED_ENVIRONMENTS = {"dev", "qa", "prod"}
DEFAULT_CPU = os.getenv("DEFAULT_CPU_REQUEST", "100m")
DEFAULT_MEMORY = os.getenv("DEFAULT_MEMORY_REQUEST", "128Mi")
DEV_MAX_CPU_MILLI = int(os.getenv("DEV_MAX_CPU_MILLICORES", "1000"))
ANNOTATION = "finops.demo/mutated"

SA_DIR = "/var/run/secrets/kubernetes.io/serviceaccount"
API_SERVER = "https://kubernetes.default.svc"


# ---------------------------------------------------------------- helpers
def namespace_labels(ns: str) -> dict:
    """Lee las labels del Namespace usando el token del ServiceAccount."""
    with open(f"{SA_DIR}/token") as f:
        token = f.read().strip()
    r = requests.get(
        f"{API_SERVER}/api/v1/namespaces/{ns}",
        headers={"Authorization": f"Bearer {token}"},
        verify=f"{SA_DIR}/ca.crt",
        timeout=3,
    )
    r.raise_for_status()
    return r.json().get("metadata", {}).get("labels") or {}


def esc(key: str) -> str:
    """Escapa una key para JSON Patch (RFC 6901)."""
    return key.replace("~", "~0").replace("/", "~1")


def pod_template(kind: str, obj: dict):
    """Devuelve (labels_path, labels, containers_path, containers) del pod o del template."""
    if kind == "Pod":
        return ("/metadata/labels", obj.get("metadata", {}).get("labels"),
                "/spec/containers", obj.get("spec", {}).get("containers", []))
    tmpl = obj["spec"]["template"]
    return ("/spec/template/metadata/labels", tmpl.get("metadata", {}).get("labels"),
            "/spec/template/spec/containers", tmpl.get("spec", {}).get("containers", []))


def cpu_to_milli(value) -> int:
    if value is None:
        return 0
    s = str(value)
    return int(s[:-1]) if s.endswith("m") else int(float(s) * 1000)


def review(uid, allowed=True, patch=None, message=None, warnings=None):
    resp = {"uid": uid, "allowed": allowed}
    if patch:
        resp["patchType"] = "JSONPatch"
        resp["patch"] = base64.b64encode(json.dumps(patch).encode()).decode()
    if message:
        resp["status"] = {"code": 403, "message": message}
    if warnings:
        resp["warnings"] = warnings
    return jsonify({"apiVersion": "admission.k8s.io/v1", "kind": "AdmissionReview", "response": resp})


# ---------------------------------------------------------------- mutate
def build_patch(kind: str, obj: dict, ns_labels: dict):
    patch, warnings, notes = [], [], []

    # 1) Heredar labels FinOps del namespace
    label_targets = []
    if kind == "Deployment":
        label_targets.append(("/metadata/labels", obj.get("metadata", {}).get("labels")))
    lpath, labels, cpath, containers = pod_template(kind, obj)
    label_targets.append((lpath, labels))

    inherited = set()
    for path, current in label_targets:
        to_add = {k: ns_labels[k] for k in FINOPS_LABELS
                  if k in ns_labels and k not in (current or {})}
        if not to_add:
            continue
        if current is None:
            patch.append({"op": "add", "path": path, "value": to_add})
        else:
            for k, v in to_add.items():
                patch.append({"op": "add", "path": f"{path}/{esc(k)}", "value": v})
        inherited.update(f"{k}={v}" for k, v in to_add.items())

    if inherited:
        msg = "labels heredadas del namespace: " + ", ".join(sorted(inherited))
        warnings.append(f"[FinOps] {msg}")
        notes.append(msg)

    # 2) Requests por defecto (sin requests no hay asignación de costos)
    defaulted = []
    for i, c in enumerate(containers):
        res = c.get("resources") or {}
        reqs = res.get("requests") or {}
        missing = {k: v for k, v in (("cpu", DEFAULT_CPU), ("memory", DEFAULT_MEMORY)) if k not in reqs}
        if not missing:
            continue
        base = f"{cpath}/{i}/resources"
        if not res:
            patch.append({"op": "add", "path": base, "value": {"requests": missing}})
        elif not reqs:
            patch.append({"op": "add", "path": f"{base}/requests", "value": missing})
        else:
            for k, v in missing.items():
                patch.append({"op": "add", "path": f"{base}/requests/{k}", "value": v})
        defaulted.append(c.get("name", str(i)))

    if defaulted:
        msg = f"requests por defecto ({DEFAULT_CPU} CPU / {DEFAULT_MEMORY}) en: " + ", ".join(defaulted)
        warnings.append(f"[FinOps] {msg}")
        notes.append(msg)

    # 3) Anotación de trazabilidad
    if notes:
        if obj.get("metadata", {}).get("annotations") is None:
            patch.append({"op": "add", "path": "/metadata/annotations", "value": {ANNOTATION: "; ".join(notes)}})
        else:
            patch.append({"op": "add", "path": f"/metadata/annotations/{esc(ANNOTATION)}", "value": "; ".join(notes)})

    return patch, warnings


@app.post("/mutate")
def mutate():
    req = request.get_json()["request"]
    kind, ns = req["kind"]["kind"], req.get("namespace")
    try:
        ns_labels = namespace_labels(ns)
    except Exception as e:  # sin labels del ns igual ponemos requests
        log.warning("no pude leer namespace %s: %s", ns, e)
        ns_labels = {}
    patch, warnings = build_patch(kind, req["object"], ns_labels)
    log.info("MUTATE %s %s/%s -> %d ops", kind, ns, req["object"].get("metadata", {}).get("name"), len(patch))
    return review(req["uid"], patch=patch, warnings=warnings)


# ---------------------------------------------------------------- validate
def check(kind: str, obj: dict):
    _, labels, _, containers = pod_template(kind, obj)
    labels = labels or {}
    errors = []

    missing = [k for k in FINOPS_LABELS if not labels.get(k)]
    if missing:
        errors.append(f"faltan labels FinOps obligatorias: {', '.join(missing)} "
                      f"(ponlas en el workload o en el namespace)")

    cc = labels.get("cost-center")
    if cc and cc not in ALLOWED_COST_CENTERS:
        errors.append(f"cost-center '{cc}' no existe en el catálogo. "
                      f"Válidos: {', '.join(sorted(ALLOWED_COST_CENTERS))}")

    env = labels.get("environment")
    if env and env not in ALLOWED_ENVIRONMENTS:
        errors.append(f"environment '{env}' inválido. Válidos: {', '.join(sorted(ALLOWED_ENVIRONMENTS))}")

    if env == "dev":
        total = sum(cpu_to_milli(((c.get("resources") or {}).get("requests") or {}).get("cpu"))
                    for c in containers)
        if total > DEV_MAX_CPU_MILLI:
            errors.append(f"en dev cada pod puede pedir máximo {DEV_MAX_CPU_MILLI}m de CPU; "
                          f"este pide {total}m (presupuesto excedido)")
    return errors


@app.post("/validate")
def validate():
    req = request.get_json()["request"]
    kind = req["kind"]["kind"]
    name = req["object"].get("metadata", {}).get("name") or req["object"].get("metadata", {}).get("generateName")
    errors = check(kind, req["object"])
    if errors:
        msg = "[FinOps] rechazado: " + " | ".join(errors)
        log.info("DENY %s %s/%s: %s", kind, req.get("namespace"), name, msg)
        return review(req["uid"], allowed=False, message=msg)
    log.info("ALLOW %s %s/%s", kind, req.get("namespace"), name)
    return review(req["uid"])


@app.get("/healthz")
def healthz():
    return "ok"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8443,
            ssl_context=(os.getenv("TLS_CERT", "/certs/tls.crt"), os.getenv("TLS_KEY", "/certs/tls.key")))
