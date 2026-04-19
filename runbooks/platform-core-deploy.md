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

## Usage notes

### Homepage

- Homepage is the curated service catalog, not the service manager itself.
- The cards under `Business Services` are the routed business entrypoints.
- The cards under `Platform` intentionally use direct local ports for the operational tools, so they still open even if Traefik is unhealthy.
- UI language can be pinned in `stacks/platform-core/config/homepage/settings.yaml` with `language: zh-Hans` or `language: en`.
- Homepage supports translated UI chrome, but it does not expose a built-in runtime language toggle for end users.

### Beszel

- Beszel is the metrics hub, but it stays empty until at least one agent is connected.
- For this host, use the local agent helper to mint a universal token and start the socket-based agent:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
bash scripts/setup_beszel_local_agent.sh
```

- Once the local agent is online, the system and container tables will populate automatically.

## Post-deploy tasks

1. Bootstrap Uptime Kuma and import the tracked monitors:

```bash
bash scripts/setup_uptime_kuma_targets.sh
```

The generated login is stored at:

`stacks/platform-core/data/uptime-kuma/credentials.env`

2. In Beszel, connect the local agent:

```bash
bash scripts/setup_beszel_local_agent.sh
```

3. In Dockge, treat `platform-control/stacks` as the managed compose root.

## Rollback

```bash
cd "/Users/shulai/Documents/New project/platform-control"
docker compose -f stacks/platform-core/compose.yaml down
```

Rollback trigger: any conflict with existing business services, unexpected port collision, or elevated resource pressure on the host.
