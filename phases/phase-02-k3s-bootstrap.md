# Phase 02: K3s Bootstrap and First App Migration

## Goal

Bootstrap a separate K3s lab that proves GitOps, Gateway API routing, metrics, logs, certs, and one real stateless app migration.

## Implemented in this repo

- `k8s/bootstrap/scripts/install-k3s.sh` installs K3s with Traefik disabled.
- `k8s/bootstrap/scripts/bootstrap-platform.sh` bootstraps Argo CD, cert-manager, External Secrets, Traefik Gateway, kube-prometheus-stack, and Loki.
- `k8s/apps/sloth-cloud-api/base` and `k8s/apps/sloth-cloud-web/base` provide the first app deployment skeletons.

## Done definition

- `kubectl` works against a dedicated K3s lab cluster.
- Argo CD, cert-manager, External Secrets, Traefik Gateway, kube-prometheus-stack, and Loki are installed.
- At least one stateless app deployment is reachable through an HTTPRoute.
- The migration and rollback steps are captured in a runbook.

## Verification

```bash
cd "/Users/shulai/Documents/New project/platform-control"
bash k8s/bootstrap/scripts/install-k3s.sh
bash k8s/bootstrap/scripts/bootstrap-platform.sh
kubectl get pods -A
```

## Next entry point

Push this repo to a real Git remote, then wire Argo CD applications to that remote and migrate `sloth-cloud-api` first.

## Open questions

- Which registry will host the Kubernetes-ready `sloth-cloud-api` and `sloth-cloud-web` images?
- Which secret manager should back External Secrets in the first lab cluster?
