# Phase 02: K3s Bootstrap and First App Migration

## Goal

Bootstrap a separate K3s lab that proves GitOps, Gateway API routing, metrics, logs, certs, and one real stateless app migration.
GitOps: use Git as the single source of truth for deployment changes.
Gateway API: the Kubernetes traffic routing model used here instead of ad hoc ingress rules.

## Implemented in this repo

- `k8s/bootstrap/scripts/install-k3s.sh` installs K3s with Traefik disabled.
- `k8s/bootstrap/scripts/bootstrap-platform.sh` bootstraps Argo CD, cert-manager, External Secrets, Traefik Gateway, kube-prometheus-stack, and Loki.
- `k8s/apps/kustomization.yaml` makes the root Argo CD application path syncable.
- `k8s/apps/sloth-cloud-api/lab` provides the first real lab overlay with ConfigMap and ExternalSecret separation.
- `scripts/render_root_application.sh` renders the root Argo CD application using either `PLATFORM_GIT_REPO` or the configured `origin` remote.
- `runbooks/sloth-cloud-api-k3s-migration.md` captures the first app migration path.

## Done definition

- `kubectl` works against a dedicated K3s lab cluster.
- Argo CD, cert-manager, External Secrets, Traefik Gateway, kube-prometheus-stack, and Loki are installed.
- At least one stateless app deployment is reachable through an HTTPRoute.
- The migration and rollback steps are captured in a runbook.
- The bootstrap path clearly distinguishes Linux lab hosts from macOS control workstations.

## Verification

```bash
cd "/Users/shulai/Documents/New project/platform-control"
bash scripts/preflight_k3s_lab.sh
bash k8s/bootstrap/scripts/install-k3s.sh
bash k8s/bootstrap/scripts/bootstrap-platform.sh
bash scripts/render_root_application.sh
ruby scripts/validate_k8s_manifests.rb
kubectl get pods -A
```

## Next entry point

Use the configured Git remote to bootstrap a Linux K3s lab, then migrate `sloth-cloud-api` first.

## Open questions

- Which registry will host the Kubernetes-ready `sloth-cloud-api` and `sloth-cloud-web` images?
- Which secret manager should back External Secrets in the first lab cluster?
