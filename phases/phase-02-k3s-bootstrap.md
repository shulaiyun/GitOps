# Phase 02: K3s Bootstrap and First App Migration

## Goal

Bootstrap a separate K3s lab that proves GitOps, Gateway API routing, metrics, logs, certs, and one real stateless app migration.
GitOps: use Git as the single source of truth for deployment changes.
Gateway API: the Kubernetes traffic routing model used here instead of ad hoc ingress rules.

## Implemented in this repo

- `k8s/bootstrap/scripts/install-k3s.sh` installs K3s with Traefik disabled.
- `k8s/bootstrap/scripts/bootstrap-platform.sh` bootstraps Argo CD, cert-manager, External Secrets, Traefik Gateway, kube-prometheus-stack, and Loki.
- `k8s/bootstrap/scripts/create-k3d-cluster.sh` creates a local macOS-friendly K3s lab by using k3d on top of Docker.
- `k8s/bootstrap/scripts/bootstrap-platform-mac-learning.sh` bootstraps the Mac lab in a lighter learning-first mode.
- `k8s/bootstrap/scripts/show-argocd-admin-password.sh` gives the local Argo CD admin password for first login.
- `k8s/apps/kustomization.yaml` makes the root Argo CD application path syncable.
- `k8s/apps/learning-whoami/base` provides a zero-dependency learning app for the first Gateway API and rollout drill.
- `k8s/apps/sloth-cloud-api/lab` provides the first real lab overlay with ConfigMap and ExternalSecret separation.
- `adr/0003-lab-first-k8s-migrations.md` records that business services must enter Kubernetes as isolated lab variants first.
- `scripts/render_root_application.sh` renders the root Argo CD application using either `PLATFORM_GIT_REPO` or the configured `origin` remote.
- `scripts/preflight_mac_lab.sh` checks whether this Mac is ready to host the local lab path.
- `runbooks/learning-whoami-gitops-drill.md` captures the first end-to-end GitOps sync and self-heal drill.
- `runbooks/sloth-cloud-api-k3s-migration.md` captures the first app migration path.

## Done definition

- `kubectl` works against a dedicated K3s lab cluster.
- Argo CD, cert-manager, External Secrets, Traefik Gateway, kube-prometheus-stack, and Loki are installed.
- At least one stateless app deployment is reachable through an HTTPRoute.
- The migration and rollback steps are captured in a runbook.
- The bootstrap path clearly distinguishes Linux lab hosts from macOS control workstations.
- The macOS path has a lighter first-day bootstrap so learning and experimentation can start before full observability and app sync are enabled.
- A no-risk demo app is reachable through `whoami.lab.localhost` before any real business service migration begins.
- The first GitOps lesson is durable in-repo and proves both automated sync and self-heal behavior.
- The first real business-service candidate is isolated as `sloth-cloud-api-lab` in `sloth-labs`, with a lab-only hostname and no default root sync inclusion.

## Verification

```bash
cd "/Users/shulai/Library/Mobile Documents/com~apple~CloudDocs/Documents/New project/platform-control"
bash scripts/preflight_k3s_lab.sh
bash k8s/bootstrap/scripts/install-k3s.sh
bash k8s/bootstrap/scripts/bootstrap-platform.sh
bash scripts/render_root_application.sh
ruby scripts/validate_k8s_manifests.rb
kubectl get pods -A
```

Live verification completed on the Mac lab:

- `learning-whoami` Argo CD `Application` is `Synced` and `Healthy`
- Git commit `d97cca9` changed the `Deployment` desired replicas from `1` to `2`
- Argo CD reconciled that Git change into the cluster
- a manual drift by `kubectl scale ... --replicas=1` was self-healed back to `2`

Safety hardening completed after the first learning phase:

- `sloth-cloud-api` Kubernetes resources were renamed to `sloth-cloud-api-lab`
- the dedicated namespace `sloth-labs` was added
- the lab route was made explicit as `sloth-cloud-api.lab.localhost`
- `k8s/apps/kustomization.yaml` was emptied by default so placeholder lab overlays are not pulled into root sync accidentally

## Next entry point

Use the configured Git remote to bootstrap a Linux K3s lab, then migrate `sloth-cloud-api` first.
For a quieter local path, bootstrap the macOS lab with k3d first, then migrate `sloth-cloud-api`.

## Open questions

- Which registry will host the Kubernetes-ready `sloth-cloud-api` and `sloth-cloud-web` images?
- Which secret manager should back External Secrets in the first lab cluster?
