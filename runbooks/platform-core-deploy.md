# Runbook: Deploy the platform core compose stack

## Prerequisites

- Docker and Compose available on the host
- Current working directory contains `/Users/shulai/Documents/New project/platform-control`
- Ports intended for the platform core stack are free:
  - `15080` for Traefik HTTP
  - `15443` for Traefik HTTPS
  - `15001` for Dockge
  - `15002` for Homepage
  - `15003` for Uptime Kuma
  - `15004` for Beszel

## Deployment

```bash
cd "/Users/shulai/Documents/New project/platform-control"
docker compose -f stacks/platform-core/compose.yaml config
docker compose -f stacks/platform-core/compose.yaml up -d
```

## Direct URLs

- Dockge: `http://127.0.0.1:15001`
- Homepage: `http://127.0.0.1:15002`
- Uptime Kuma: `http://127.0.0.1:15003`
- Beszel: `http://127.0.0.1:15004`
- Traefik edge: `http://127.0.0.1:15080`

## Traefik hostnames

- `http://home.localhost:15080`
- `http://dockge.localhost:15080`
- `http://uptime.localhost:15080`
- `http://beszel.localhost:15080`
- `http://cloud.localhost:15080`
- `http://cloud-api.localhost:15080`
- `http://paymenter.localhost:15080`
- `http://convoy.localhost:15080`
- `http://xboard.localhost:15080`
- `http://cliproxy.localhost:15080`

## Post-deploy tasks

1. In Uptime Kuma, create monitors from `inventory/uptime-targets.yaml`.
2. In Beszel, generate a token and public key, then enable the `agent` profile:

```bash
docker compose -f stacks/platform-core/compose.yaml --profile agent up -d
```

3. In Dockge, treat `platform-control/stacks` as the managed compose root.

## Rollback

```bash
cd "/Users/shulai/Documents/New project/platform-control"
docker compose -f stacks/platform-core/compose.yaml down
```

Rollback trigger: any conflict with existing business services, unexpected port collision, or elevated resource pressure on the host.
