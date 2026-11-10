"""Pruebas locales sin cluster: python -m pytest tests/  (o python tests/test_webhook.py)"""
import base64
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import app as webhook  # noqa: E402

NS_LABELS = {"cost-center": "CC-1001", "team": "payments", "environment": "dev"}
webhook.namespace_labels = lambda ns: NS_LABELS if ns == "finops-payments" else {}
client = webhook.app.test_client()


def deployment(labels=None, resources=None):
    return {
        "apiVersion": "apps/v1", "kind": "Deployment",
        "metadata": {"name": "web", "labels": {"app": "web"}},
        "spec": {"selector": {"matchLabels": {"app": "web"}},
                 "template": {"metadata": {"labels": {"app": "web", **(labels or {})}},
                              "spec": {"containers": [{"name": "app", "image": "nginx",
                                                       **({"resources": resources} if resources else {})}]}}},
    }


def call(path, obj, ns="finops-payments"):
    body = {"apiVersion": "admission.k8s.io/v1", "kind": "AdmissionReview",
            "request": {"uid": "1", "kind": {"kind": obj["kind"]}, "namespace": ns, "object": obj}}
    return client.post(path, json=body).get_json()["response"]


def apply_patch(obj, patch):
    """JSON Patch mínimo (solo 'add') para verificar el resultado."""
    obj = json.loads(json.dumps(obj))
    for op in patch:
        parts = [p.replace("~1", "/").replace("~0", "~") for p in op["path"].split("/")[1:]]
        cur = obj
        for p in parts[:-1]:
            cur = cur[int(p)] if isinstance(cur, list) else cur[p]
        cur[parts[-1]] = op["value"]
    return obj


def test_mutate_inherits_and_defaults_then_validates():
    obj = deployment()
    r = call("/mutate", obj)
    patched = apply_patch(obj, json.loads(base64.b64decode(r["patch"])))
    tl = patched["spec"]["template"]["metadata"]["labels"]
    assert tl["cost-center"] == "CC-1001" and tl["team"] == "payments"
    assert patched["spec"]["template"]["spec"]["containers"][0]["resources"]["requests"]["cpu"] == "100m"
    assert webhook.ANNOTATION in patched["metadata"]["annotations"]
    assert r["warnings"]
    assert call("/validate", patched)["allowed"] is True


def test_reject_orphan_namespace():
    obj = deployment()
    patched = apply_patch(obj, json.loads(base64.b64decode(call("/mutate", obj, ns="finops-sandbox")["patch"])))
    r = call("/validate", patched, ns="finops-sandbox")
    assert r["allowed"] is False and "faltan labels" in r["status"]["message"]


def test_reject_bad_cost_center():
    r = call("/validate", deployment({"cost-center": "CC-9999", "team": "x", "environment": "qa"}))
    assert r["allowed"] is False and "CC-9999" in r["status"]["message"]


def test_reject_dev_cpu_budget():
    obj = deployment(NS_LABELS, {"requests": {"cpu": "2", "memory": "1Gi"}})
    r = call("/validate", obj)
    assert r["allowed"] is False and "2000m" in r["status"]["message"]


def test_pod_without_labels_map():
    pod = {"kind": "Pod", "metadata": {"name": "p"}, "spec": {"containers": [{"name": "c", "image": "x"}]}}
    patched = apply_patch(pod, json.loads(base64.b64decode(call("/mutate", pod)["patch"])))
    assert patched["metadata"]["labels"]["team"] == "payments"
    assert call("/validate", patched)["allowed"] is True


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("OK", name)
