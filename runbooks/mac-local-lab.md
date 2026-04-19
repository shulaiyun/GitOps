# Runbook: macOS Local Lab

## Purpose

Run the platform lab on this Mac without using the noisy Linux server.
This path is for local validation, GitOps rehearsal, and early migration drills.
It is not the recommended long-running customer production substrate.

Key terms:
Colima: a lightweight Linux virtual machine on macOS that provides the Docker runtime.
k3d: a tool that runs K3s clusters inside Docker.
K3s: a lightweight Kubernetes distribution.
GitOps: use Git as the single source of truth for deployment changes.
Argo CD: the controller that watches Git and syncs the cluster.

## When to use this path

- You want a quiet local platform lab on the Mac.
- You want to validate Argo CD, Helm, Gateway API, metrics, logs, and one app migration before touching a remote node.
- You do not want to move customer traffic onto this machine.

## Constraints

- macOS can sleep, reboot for updates, or change network state, so do not treat this as a stable always-on platform.
- Public domains and customer ingress should stay on a real Linux host or managed cluster later.
- Stateful databases should remain in Compose for now; the Mac lab is mainly for stateless app migration drills.

## Prerequisites

1. Make sure Colima is running:

```bash
colima status
```

2. Install the local control tools:

```bash
brew install kubectl helm k3d
```

3. Run the macOS preflight:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
bash scripts/preflight_mac_lab.sh
```

## Create the local cluster

Use dedicated ports so the Mac lab does not collide with the existing Compose platform stack:

- `16080`: local Kubernetes HTTP entry
- `16443`: local Kubernetes HTTPS entry

Create the cluster:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
bash k8s/bootstrap/scripts/create-k3d-cluster.sh
```

This creates:

- one K3s server node
- one worker node
- bundled Traefik disabled, because this repo installs Traefik itself by Helm

## Bootstrap the platform layer

Point the bootstrap to the real Git remote:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
export PLATFORM_GIT_REPO="$(git remote get-url origin)"
export PLATFORM_GIT_REVISION=main
export GRAFANA_ADMIN_PASSWORD="change-me-now"
bash k8s/bootstrap/scripts/bootstrap-platform.sh
```

## Verification

```bash
kubectl config current-context
kubectl get nodes
kubectl get pods -A
kubectl get applications -n argocd
kubectl get gateways.gateway.networking.k8s.io -A
```

Expected result:

- current context is `k3d-sloth-lab`
- Argo CD, cert-manager, External Secrets, Traefik, Prometheus stack, and Loki are running
- the root application points to `https://github.com/shulaiyun/GitOps.git`

## First migration drill

Once the lab platform is healthy, continue with:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
cat runbooks/sloth-cloud-api-k3s-migration.md
```

## Rollback and cleanup

Delete the local cluster:

```bash
k3d cluster delete sloth-lab
```

This removes the local Kubernetes lab without touching the Compose-based business services.
