# Phase 01: Platform Core on Compose

## Goal

Add one shared operational layer above the existing compose estate so services become discoverable, routable, and observable without changing the app runtime underneath.

## Implemented in this repo

- `stacks/platform-core/compose.yaml` defines Traefik, Dockge, Homepage, Uptime Kuma, Beszel hub, and the gated Beszel agent profile.
- Homepage config is preloaded with current business and platform endpoints.
- Traefik dynamic routes proxy current host-bound services under `*.localhost` hostnames.
- `inventory/uptime-targets.yaml` captures the intended Uptime Kuma monitor list.
- `Homepage` and `Beszel` are already live on the current host.

## Done definition

- Platform core stack parses successfully with `docker compose config`.
- Homepage renders the current runtime map.
- Dockge can manage new stacks under `platform-control/stacks`.
- Uptime Kuma and Beszel are reachable on their direct ports and through Traefik.

## Verification

```bash
cd "/Users/shulai/Documents/New project/platform-control"
docker compose -f stacks/platform-core/compose.yaml config
docker compose -f stacks/platform-core/compose.yaml up -d
```

Current live checks:

```bash
curl -I http://127.0.0.1:15002
curl -I http://127.0.0.1:15004
```

## Next entry point

Bring up Traefik, Dockge, and Uptime Kuma when the remaining images are pulled, add monitors from `inventory/uptime-targets.yaml`, then prepare the separate K3s lab host.

## Open questions

- Which hostnames should become permanent public or internal DNS names after the localhost phase?
- When should the Beszel agent be activated and keyed?
