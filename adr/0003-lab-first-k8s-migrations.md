# ADR 0003: Run first Kubernetes business migrations as isolated lab variants

- Status: accepted
- Date: 2026-04-23

## Context

The repository already contained a first-pass `sloth-cloud-api` K3s overlay, but it still used the production-like service name and namespace shape, and `k8s/apps/kustomization.yaml` pointed at that overlay by default. That created an avoidable future risk: if the root Argo CD application was enabled before image, secret, and rollback preparation were complete, the placeholder lab API could be pulled into the cluster automatically and look too close to the real Compose-hosted API.

The user explicitly wanted to avoid harming the currently deployed `sloth-cloud-api` business runtime and needed the separation to be obvious.

## Decision

- Keep the live Compose-hosted `sloth-cloud-api` as the active business API.
- Treat the Kubernetes path as a lab-first migration only.
- Rename Kubernetes resources to `sloth-cloud-api-lab`.
- Move the Kubernetes lab API into the dedicated `sloth-labs` namespace.
- Use the explicit lab hostname `sloth-cloud-api.lab.localhost`.
- Remove lab overlays from the default `k8s/apps/kustomization.yaml` root sync path until an explicit rollout decision is made.

## Consequences

- The Kubernetes lab API is visually and operationally distinct from the Compose-hosted API.
- Enabling the root Argo CD application no longer deploys placeholder business lab overlays by accident.
- Future migration work becomes an explicit opt-in step: add the lab overlay to root sync, validate it, then decide whether to keep it as a lab path or plan a real cutover.
