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
- `scripts/start_argocd_ui_port_forward.sh` starts a local-only or LAN-reachable Argo CD UI port-forward on demand.
- The Mac learning lab uses Argo CD `server.insecure=true` for local HTTP UI access, so browser teaching does not get blocked by self-signed HTTPS certificate warnings.
- `scripts/reset_argocd_admin_password.sh` resets the Argo CD admin password by patching `argocd-secret`.
- `k8s/apps/kustomization.yaml` makes the root Argo CD application path syncable.
- `k8s/apps/learning-whoami/base` provides a zero-dependency learning app for the first Gateway API and rollout drill.
- `k8s/apps/sloth-cloud-api/lab` provides the first real lab overlay with ConfigMap and ExternalSecret separation.
- `k8s/apps/sloth-cloud-api/lab-dev-real-write` provides the first real-write development overlay that points at local development Paymenter, Convoy, Web, registry, and lab routes.
- `adr/0003-lab-first-k8s-migrations.md` records that business services must enter Kubernetes as isolated lab variants first.
- `scripts/render_root_application.sh` renders the root Argo CD application using either `PLATFORM_GIT_REPO` or the configured `origin` remote.
- `scripts/render_sloth_cloud_api_lab_application.sh` renders a dedicated Argo CD application for `sloth-cloud-api-lab` without enabling automatic sync.
- `scripts/check_sloth_cloud_api_lab_dependencies.rb` checks the first real app candidate's ConfigMap and ExternalSecret coverage before sync.
- `scripts/preflight_mac_lab.sh` checks whether this Mac is ready to host the local lab path.
- `runbooks/learning-whoami-gitops-drill.md` captures the first end-to-end GitOps sync and self-heal drill.
- `runbooks/argocd-access-and-password.md` explains how Argo CD login password changes work and why LAN access fails by default.
- `runbooks/sloth-cloud-api-k3s-migration.md` captures the first app migration path.
- `runbooks/sloth-cloud-api-lab-argocd-application.md` captures the manual-sync-only Argo CD application path for the first real business service.
- `runbooks/sloth-cloud-api-lab-dependency-matrix.md` records which lab API config values can be kept, replaced, disabled, or moved to secrets.
- `runbooks/sloth-cloud-api-lab-dev-real-write-policy.md` records that development business data may be mutated while project code and control files remain protected.
- `adr/0004-dev-real-write-lab-boundary.md` records the accepted boundary for real write lab operations.
- `scripts/import_sloth_cloud_api_lab_image.sh` imports the current Compose API image into the k3d cluster as `sloth-cloud-api-lab:dev`.
- `scripts/seed_sloth_cloud_api_lab_secret_from_api_env.sh` creates the manual Kubernetes Secret used by the lab API without committing secret values to Git.
- `k8s/apps/sloth-cloud-web/lab-dev-real-write` adds the first Web lab overlay that proxies `/api` to the Kubernetes `sloth-cloud-api-lab` Service.
- `scripts/import_sloth_cloud_web_lab_image.sh` imports the current Compose Web image into the k3d cluster as `sloth-cloud-web:dev`.
- `scripts/render_sloth_cloud_web_lab_application.sh` renders the manual-sync-only Argo CD application for the Web lab.
- `runbooks/sloth-cloud-web-lab-gitops.md` records the Web lab rollout, verification, and rollback path with Chinese term explanations.

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
- a dedicated Argo CD `Application` render path now exists so the lab API can appear in Argo UI without auto-syncing into the cluster
- the lab API ConfigMap and ExternalSecret dependencies are classified before any sync attempt
- the lab policy now allows real writes to development business state but still blocks mutation of source code, Git history, Compose definitions, Kubernetes control manifests, and traffic cutover
- the dev real-write overlay now replaces `replace-me` URLs with local development endpoints and keeps secrets out of Git
- the first manual `SYNC` of `sloth-cloud-api-lab` completed successfully in Argo CD
- the lab API is reachable through `http://sloth-cloud-api.lab.localhost:16080/api/v1/health`
- the next service-building step is `sloth-cloud-web-lab`, which keeps the existing Compose Web active while testing a Kubernetes Web -> API path
- the first manual `SYNC` of `sloth-cloud-web-lab` completed successfully in Argo CD
- the Web lab is reachable through `http://cloud.lab.localhost:16080/`
- `http://cloud.lab.localhost:16080/api/v1/health` reaches the API through the Web container proxy

## Next entry point

Use the running `sloth-cloud-api-lab` and `sloth-cloud-web-lab` path to learn real business integration safely:

1. Open the Web lab and inspect browser-side login/API behavior.
2. Inspect the Argo object chain from `Application -> Deployment -> ReplicaSet -> Pod -> Logs`.
3. Exercise low-risk authenticated API reads first.
4. Then test one accepted development write operation and record its rollback or cleanup path.
5. If the Compose API or Web image changes, re-run the matching image import script and restart/sync the lab Deployment.

## Open questions

- Which secret manager should back External Secrets in the first lab cluster?
- Should the next step use manual Kubernetes Secret only for learning, or should we introduce a real Secret manager before the first customer-facing lab?
