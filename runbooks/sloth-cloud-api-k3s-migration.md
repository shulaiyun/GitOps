# Runbook: Sloth Cloud API First K3s Migration

## Goal

Move `sloth-cloud-api` first because it is stateless, already exposes `/api/v1/health`, and gives the quickest proof that GitOps plus Gateway API works before touching stateful services.

## Prepared assets

- Base manifests: `k8s/apps/sloth-cloud-api/base`
- Lab overlay: `k8s/apps/sloth-cloud-api/lab`
- Root sync entry: `k8s/apps/kustomization.yaml`

## Required decisions before rollout

1. Publish a Kubernetes-usable image for `sloth-cloud-api`.
2. Choose the upstream URLs that replace the compose-only service names in `configmap.yaml`.
3. Bind `sloth-cloud-api-secrets` to a real `ClusterSecretStore`.

## Suggested rollout order

1. Update the overlay with a real image reference and reachable upstream URLs.
2. Create the backing secret store for External Secrets.
3. Render and apply the root Argo CD application.
4. Wait for `sloth-cloud-api` to become Ready.
5. Test the route:

```bash
curl -H 'Host: api.lab.localhost' http://<traefik-gateway-address>/api/v1/health
```

## Rollback

If the lab API is unhealthy or its upstream dependencies are not reachable:

1. Remove `sloth-cloud-api/lab` from `k8s/apps/kustomization.yaml`.
2. Re-sync the root application.
3. Keep the Compose-hosted API as the active control plane endpoint.

## Verification

```bash
cd "/Users/shulai/Documents/New project/platform-control"
ruby scripts/validate_k8s_manifests.rb
```
