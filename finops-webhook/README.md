# Demo FinOps: Mutating + Validating Admission Webhooks en OpenShift

**Mensaje de la demo:** *"Si no sabemos a quién cobrarle un pod, ese pod no entra al cluster."*
Herramientas como OpenShift Cost Management u OpenCost reparten costos por **labels** y por **requests**.
Si faltan o están mal, el showback/chargeback no sirve. Esta demo pone dos guardrails:

| Webhook | Qué hace | failurePolicy |
|---|---|---|
| **Mutating** `/mutate` | Hereda `cost-center`, `team` y `environment` del Namespace al workload. Pone requests por defecto (100m / 128Mi) si faltan. Deja la anotación `finops.demo/mutated` y regresa *warnings* que el usuario ve en `oc`. | `Ignore` |
| **Validating** `/validate` | Rechaza si faltan labels FinOps, si el `cost-center` no está en el catálogo, si `environment` no es dev/qa/prod, o si un pod en **dev** pide más de 1 core. | `Fail` |

Solo aplica en namespaces con la label `finops.demo/enforce=true`, así que no afecta a `openshift-*`.
Aplica a Pods (CREATE) y Deployments (CREATE/UPDATE).

```
oc apply ──► Mutating (hereda labels, defaults) ──► Schema ──► Validating (¿cumple FinOps?) ──► etcd
```

---

## 1. Instalación (~3 min)

```bash
oc apply -f deploy/00-namespace.yaml

# Build dentro del cluster (sin registry externo)
oc -n finops-webhook new-build --name finops-webhook --binary --strategy docker
oc -n finops-webhook start-build finops-webhook --from-dir . --follow

oc apply -f deploy/
oc -n finops-webhook rollout status deploy/finops-webhook

# Verifica que OpenShift inyectó el caBundle
oc get mutatingwebhookconfiguration finops-mutating -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | head -c 40; echo
```

> TLS sin cert-manager: la anotación `serving-cert-secret-name` del Service genera el certificado, e `inject-cabundle` en las webhook configs pone la CA.

Pruebas locales sin cluster: `python3 tests/test_webhook.py`

---

## 2. Guion de la demo

En otra terminal deja corriendo los logs del webhook, porque se ve muy bien en vivo:
```bash
oc -n finops-webhook logs -f deploy/finops-webhook
```

### Paso 0: el escenario
```bash
oc apply -f demo/00-namespaces.yaml
oc get ns finops-payments finops-sandbox --show-labels
```
> "`finops-payments` tiene dueño y centro de costo. `finops-sandbox` es el típico namespace que nadie sabe de quién es."

### Paso 1: Mutating, el dev no tiene que saber de FinOps
```bash
oc -n finops-payments apply -f demo/01-app-sin-labels.yaml
```
Salida esperada (los warnings vienen del webhook):
```
Warning: [FinOps] labels heredadas del namespace: cost-center=CC-1001, environment=dev, team=payments
Warning: [FinOps] requests por defecto (100m CPU / 128Mi) en: app
deployment.apps/checkout created
```
```bash
oc -n finops-payments get pods --show-labels
oc -n finops-payments get deploy checkout -o jsonpath='{.metadata.annotations.finops\.demo/mutated}'; echo
oc -n finops-payments get deploy checkout -o jsonpath='{.spec.template.spec.containers[0].resources}'; echo
```
> "El YAML que mandé no tenía nada de esto. El cluster lo completó solo y ya se puede hacer chargeback."

### Paso 2: Validating, namespace huérfano
```bash
oc -n finops-sandbox apply -f demo/01-app-sin-labels.yaml
```
```
Error from server: admission webhook "validate.finops.demo" denied the request:
[FinOps] rechazado: faltan labels FinOps obligatorias: cost-center, team, environment ...
```
> "El mutating intentó ayudar, pero el namespace no tiene datos. El validating no deja entrar costo sin dueño."

### Paso 3: Catálogo de centros de costo
```bash
oc -n finops-payments apply -f demo/02-cost-center-invalido.yaml
```
> Rechazado: `CC-9999 no existe en el catálogo`. Ojo: el mutating **no** pisa labels que el usuario ya puso.

### Paso 4: Presupuesto en dev
```bash
oc -n finops-payments apply -f demo/03-dev-muy-caro.yaml
```
> Rechazado: `en dev cada pod puede pedir máximo 1000m de CPU; este pide 4000m`.

Cambia el catálogo en vivo, sin tocar código:
```bash
oc -n finops-webhook patch cm finops-policy -p '{"data":{"ALLOWED_COST_CENTERS":"CC-1001,CC-2002,CC-9999"}}'
oc -n finops-webhook rollout restart deploy/finops-webhook && oc -n finops-webhook rollout status deploy/finops-webhook
oc -n finops-payments apply -f demo/02-cost-center-invalido.yaml   # ahora sí entra
```

### Paso 5 (bonus): `--dry-run=server` para validar en CI
```bash
oc -n finops-sandbox apply -f demo/01-app-sin-labels.yaml --dry-run=server
```
> El webhook se ejecuta sin persistir nada (por eso `sideEffects: None`). Así puedes validar desde un pipeline antes de que ArgoCD sincronice.

### Paso 6 (momento wow): ¿qué pasa si el webhook se cae?
```bash
oc -n finops-webhook scale deploy/finops-webhook --replicas=0
oc -n finops-payments rollout restart deploy/checkout
oc -n finops-payments get events --sort-by=.lastTimestamp | tail -5
```
> Con el validating en `failurePolicy: Fail`, **ningún** pod nuevo entra en los namespaces enforced (el ReplicaSet muestra `failed calling webhook`). El mutating está en `Ignore` y no estorba.
> Lección de operación: alta disponibilidad (2+ réplicas y PDB), `timeoutSeconds` bajo y un `namespaceSelector` estricto. Nunca apliques un webhook `Fail` a todo el cluster.

```bash
oc -n finops-webhook scale deploy/finops-webhook --replicas=1
```

---

## 3. Puntos para la conversación

- **Orden:** todos los mutating corren antes que todos los validating. Por eso el validating ve el objeto ya completado.
- **Pods vs Deployments:** validar el Deployment da feedback inmediato en `oc apply`. Si solo validas Pods, el error queda escondido en los eventos del ReplicaSet.
- **Hoy sin webhook:** `ValidatingAdmissionPolicy` (CEL, GA) cubre las validaciones simples, como labels requeridas y allowlists, sin servidor ni TLS. La herencia desde el Namespace sí requiere leer otro objeto (con CEL se puede vía `paramRef`/`namespaceObject`, pero el webhook es más flexible). Buen cierre: *"¿cuándo webhook y cuándo CEL?"*
- **Siguiente paso real:** OpenShift Cost Management / OpenCost agrupando costos por `cost-center`.

## 4. Limpieza
```bash
oc delete -f deploy/05-webhooks.yaml        # primero los webhooks, para no bloquear nada
oc delete -f demo/00-namespaces.yaml
oc delete -f deploy/
oc delete clusterrole,clusterrolebinding finops-webhook-read-namespaces --ignore-not-found
```
