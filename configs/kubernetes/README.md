# Kubernetes configs - PaySecure (EKS, Istio, Kyverno)

| Path | Purpose | Used by |
|---|---|---|
| `base/namespaces.yaml` | `paysecure` (Istio injection on) and `paysecure-cde` (restricted pod security) | all |
| `base/region-config.yaml` | ConfigMap `region-config` read by services: Aurora endpoint, Kafka bootstrap, write readiness, fraud mode, rate-limit scale | RB-01, RB-04, RB-12 |
| `base/deployments.yaml` | Deployments and Services for payment-api, transaction-processor, settlement-engine and fraud-detection (requests/limits, probes, ConfigMap and Secret references, signed images) | RB-01, RB-10, RB-12 |
| `base/hpa.yaml`, `base/pdb.yaml` | Autoscaling (CPU 60% and TPS per pod) and disruption budgets | RB-10 |
| `base/topology-spread-patch.yaml` | Patch in the base kustomization: spread pods across the 3 AZs | RB-10 |
| `istio/peer-authentication.yaml` | Strict mTLS | security baseline |
| `istio/fraud-detection-virtualservice.yaml` | Baseline routing, timeout and retries for fraud-detection | RB-12 |
| `istio/fraud-detection-circuit-breaker.yaml` | Pre-staged circuit breaker, applied during RB-12 | **RB-12 step 10** |
| `policies/verify-signed-images.yaml` | Kyverno policy: only signed images from Indian registries run | **RB-11 step 19** |
| `policies/cde-network-policy.yaml` | Default-deny network policy for the PCI CDE namespace | PCI DSS segmentation |
| `overlays/dr` | Hyderabad overlay: lower replica floors, write not ready | RB-01 |

## Status - read before applying
- **Not applied to a cluster.** Files were parsed as YAML and checked for the runbook-required values only. Run `kubectl apply --dry-run=server` and `kustomize build` in a non-production cluster first.
- Replica counts, ports, registry names and the TPS-per-pod target are **assumptions** (marked `assumed`). Replace them with the real values from the running Mumbai cluster.
- Kyverno and Istio CRDs must already be installed. The circuit-breaker file is **not** part of `kustomization.yaml` on purpose: it is applied only during an incident or a drill.

## Apply
```
kubectl --context paysecure-primary apply -k configs/kubernetes/base
kubectl --context paysecure-primary apply -f configs/kubernetes/istio/peer-authentication.yaml -f configs/kubernetes/istio/fraud-detection-virtualservice.yaml
kubectl --context paysecure-primary apply -f configs/kubernetes/policies/
kubectl --context paysecure-dr apply -k configs/kubernetes/overlays/dr
```
