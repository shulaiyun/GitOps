# Runbook: GitOps Remote Preparation

## Goal

Prepare `platform-control` so Argo CD can sync it from a real Git remote instead of relying on local-only files.
Argo CD: a GitOps controller that watches Git and reconciles the Kubernetes cluster to match the repo state.
GitOps: use Git as the single source of truth for deployment and configuration changes.

## Steps

1. Add a remote:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
git remote add origin https://github.com/shulaiyun/GitOps.git
git remote -v
```

2. Render the root Argo CD application manifest from the tracked template:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
bash scripts/render_root_application.sh
```

This manifest is the bootstrap entry for Argo CD.
Bootstrap: the first step that installs the controller and points it at the repo so later sync happens automatically.

3. After the remote exists and contains the current branch, export the repo URL before bootstrapping K3s:

```bash
export PLATFORM_GIT_REPO="$(git remote get-url origin)"
export PLATFORM_GIT_REVISION=main
```

4. Bootstrap the cluster:

```bash
bash k8s/bootstrap/scripts/bootstrap-platform.sh
```

K3s: a lightweight Kubernetes distribution suitable for a first lab cluster.

## Verification

```bash
cd "/Users/shulai/Documents/New project/platform-control"
bash scripts/render_root_application.sh >/tmp/platform-root-app.yaml
sed -n '1,80p' /tmp/platform-root-app.yaml
```

## Rollback

- Remove the remote if it was added incorrectly:

```bash
git remote remove origin
```

- Unset exported variables in the shell:

```bash
unset PLATFORM_GIT_REPO PLATFORM_GIT_REVISION
```
