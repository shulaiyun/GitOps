# K3s Bootstrap

This directory prepares a separate K3s lab for the first Kubernetes wave.

## What is here

- `config/k3s-config.yaml`: K3s server flags, with bundled Traefik disabled
- `scripts/install-k3s.sh`: installs K3s and Helm
- `scripts/bootstrap-platform.sh`: installs Argo CD, cert-manager, External Secrets, Traefik Gateway, kube-prometheus-stack, and Loki
- `manifests/`: base namespaces and template manifests
- `values/`: Helm values used by the bootstrap script

## Important constraints

- Do not run this on the current compose production-like host unless you are intentionally testing there.
- Argo CD app sync requires a real Git remote. Export `PLATFORM_GIT_REPO` before enabling the root application.
