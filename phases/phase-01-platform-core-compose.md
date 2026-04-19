# Phase 01: Platform Core on Compose

## Goal

Add one shared operational layer above the existing compose estate so services become discoverable, routable, and observable without changing the app runtime underneath.

## Implemented in this repo

- `stacks/platform-core/compose.yaml` defines Traefik, Dockge, Homepage, Uptime Kuma, Beszel hub, and the gated Beszel agent profile.
- Homepage config is preloaded with current business and platform endpoints.
- Traefik dynamic routes proxy current host-bound services under `*.localhost` hostnames.
- `inventory/uptime-targets.yaml` captures the intended Uptime Kuma monitor list.
- `Homepage`, `Beszel`, `Traefik`, `Dockge`, and `Uptime Kuma` can all be brought up from the same stack.
- `scripts/setup_beszel_local_agent.sh` provisions the local Beszel agent without hand-editing tokens into tracked files.
- `scripts/setup_uptime_kuma_targets.sh` bootstraps Uptime Kuma, creates the first admin user, and imports the tracked monitors.

## Done definition

- Platform core stack parses successfully with `docker compose config`.
- Homepage renders the current runtime map.
- Dockge can manage new stacks under `platform-control/stacks`.
- Uptime Kuma and Beszel are reachable on their direct ports and through Traefik.
- The local Beszel agent is connected and container metrics are available.
- Uptime Kuma has the initial monitor set imported from inventory.

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
curl -I http://127.0.0.1:15003
curl -I http://home.localhost:15080
bash scripts/setup_beszel_local_agent.sh
bash scripts/setup_uptime_kuma_targets.sh
```

## Next entry point

Keep the monitor inventory in sync with new services, then prepare the separate K3s lab host.

## Open questions

- Which hostnames should become permanent public or internal DNS names after the localhost phase?
- Should Uptime Kuma stay socket-script managed, or should the monitor list later become a pure Git-rendered backup/import artifact?
