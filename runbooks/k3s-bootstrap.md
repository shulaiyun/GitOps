# Runbook: Bootstrap the K3s lab

## Purpose

Stand up a separate K3s lab for platform validation without disturbing the compose-based live estate.
K3s: a lightweight Kubernetes distribution used here as the first lab platform, not the final production substrate.

## Prerequisites

- Use a separate machine or VM from the current compose production-like host.
- DNS can be local-only for the first lab, but it must be explicit.
- A real Git remote for this repo is available before Argo CD app syncing is enabled.
- If you are on macOS, treat this machine as a control workstation only. Run the install and bootstrap scripts on a Linux VM or Linux server.

## Install order

1. Install K3s:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
bash k8s/bootstrap/scripts/install-k3s.sh
```

2. Bootstrap the platform components:

```bash
bash k8s/bootstrap/scripts/bootstrap-platform.sh
```

Platform components:
Argo CD: GitOps controller for repo-to-cluster sync.
cert-manager: certificate automation controller.
External Secrets: syncs secret data from an external secret backend into Kubernetes.
Gateway API: modern Kubernetes traffic routing model.
Loki: log aggregation system.

3. Confirm the cluster health:

```bash
kubectl get nodes
kubectl get pods -A
kubectl get gateways.gateway.networking.k8s.io -A
```

4. Push `platform-control` to a real Git remote and set:

```bash
export PLATFORM_GIT_REPO="https://git.example.com/your-org/platform-control.git"
export PLATFORM_GIT_REVISION="main"
```

5. Re-run the bootstrap script to apply the root Argo CD application once the remote exists.

## Rollback

- Remove the K3s lab node if bootstrap fails before workloads are migrated.
- Do not repoint production traffic until the lab passes app deployment, routing, metrics, and log checks.
