# Platform Control

`platform-control` is the long-lived control repository for the current Sloth runtime estate and its Kubernetes migration path. The chat thread can change, compress, or end; this repo is the memory.

## What lives here

- `inventory/`: current service inventory, compose project map, monitor targets
- `environments/`: environment contracts for the current compose estate and the target K3s lab
- `tenants/`: customer delivery templates and tenancy defaults
- `adr/`: architecture decisions that lock in important choices
- `phases/`: one file per phase with done criteria, current result, and the next handoff point
- `runbooks/`: deployment, rollback, recovery, and bootstrap procedures
- `runbooks/server-to-mac-migration.md`: Mac feasibility assessment and server-to-Mac migration flow
- `stacks/`: file-based compose stacks, including the new platform core stack
- `k8s/`: K3s bootstrap assets and first-pass app manifests
- `scripts/`: validation and inventory helpers

## Current implementation status

- Phase 0 is implemented as a real service inventory covering every currently running container.
- Phase 1 is implemented as a compose-based platform core stack for Traefik, Dockge, Homepage, Uptime Kuma, and Beszel.
- `Homepage`, `Dockge`, `Uptime Kuma`, `Beszel`, and `Traefik` can all be started from the same platform core stack.
- `Homepage` and `Beszel` are already running on this host at `http://127.0.0.1:15002` and `http://127.0.0.1:15004`.
- `scripts/setup_beszel_local_agent.sh` provisions the local Beszel agent, and `scripts/setup_uptime_kuma_targets.sh` bootstraps Uptime Kuma plus the initial monitors.
- Phase 2 is implemented as a bootstrapable K3s/Kubernetes skeleton with Argo CD, cert-manager, External Secrets, Traefik Gateway, Loki, and kube-prometheus-stack bootstrap scripts.
- `k8s/apps/kustomization.yaml` and `k8s/apps/sloth-cloud-api/lab` now provide the first real GitOps-syncable app path.
- The live machine still runs the business services on Compose. K3s is prepared but intentionally not installed by default on this host.
- GitOps means Git is the single source of truth for platform changes, and Argo CD is the controller that syncs those Git changes into Kubernetes.
- macOS can also host a local lab by using Colima plus k3d, which lets us rehearse the Kubernetes path without using the remote Linux server.

## Recommended workflow

1. Update `inventory/services.yaml` before deploying any new service.
2. Record one ADR whenever a major platform decision changes.
3. End each work slice by updating the matching `phases/phase-XX-*.md`.
4. Run `scripts/validate_platform_control.rb` before calling a phase complete.

## Quickstart

Validate the repo:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
ruby scripts/validate_platform_control.rb
ruby scripts/validate_k8s_manifests.rb
```

Preview the platform core stack:

```bash
docker compose -f stacks/platform-core/compose.yaml config
```

Bring up the platform core stack:

```bash
docker compose -f stacks/platform-core/compose.yaml up -d
```

Bootstrap the operational tools:

```bash
bash scripts/setup_beszel_local_agent.sh
bash scripts/setup_uptime_kuma_targets.sh
```

Prepare the K3s lab host:

```bash
bash scripts/preflight_k3s_lab.sh
bash k8s/bootstrap/scripts/install-k3s.sh
bash k8s/bootstrap/scripts/bootstrap-platform.sh
```

Prepare the macOS local lab:

```bash
bash scripts/preflight_mac_lab.sh
bash k8s/bootstrap/scripts/create-k3d-cluster.sh
bash k8s/bootstrap/scripts/bootstrap-platform.sh
```
