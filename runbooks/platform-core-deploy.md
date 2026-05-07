# Runbook: Deploy the platform core compose stack

## Prerequisites

- Docker and Compose available on the host
- Current working directory contains `/Users/shulai/Documents/New project/GitOps-learning`
- Ports intended for the platform core stack are free:
  - `15080` for Traefik HTTP
  - `15443` for Traefik HTTPS
  - `15001` for Dockge
  - `15002` for Homepage
  - `15003` for Uptime Kuma
  - `15004` for Beszel

## Deployment

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
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
- Beszel Hub means the web panel that stores and displays metrics, 中文就是“监控管理端”。
- Beszel Agent means the collector running beside Docker, 中文就是“采集 CPU、内存、磁盘和容器状态的小组件”。
- For this Mac/Colima lab, the local agent listens on `/beszel_socket/beszel.sock`. Unix socket means two local containers talk through one shared local communication file, 中文就是“两个容器通过同一个本地通信文件连接”，and this avoids the dashboard going empty when the Hub-to-Agent TCP polling path becomes stale.
- For this host, use the local agent helper to write the agent environment file and recreate the agent container:

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
bash scripts/setup_beszel_local_agent.sh
```

- Once the local agent is online, the system and container tables will populate automatically.
- If Beszel opens but shows no systems, verify the stored system points to the socket path:

```bash
sqlite3 stacks/platform-core/data/beszel/data.db \
  "select id, name, host, port, status, updated from systems;"
```

Expected local result:

```text
colima|/beszel_socket/beszel.sock||up
```

- If the timestamp is stale, rerun the helper. It recreates the Agent, points the stored system at the socket path, and restarts the Hub in the safe order:

```bash
bash scripts/setup_beszel_local_agent.sh
```

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

3. In Dockge, treat `GitOps-learning/stacks` as the managed compose root.

## Rollback

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
docker compose -f stacks/platform-core/compose.yaml down
```

Rollback trigger: any conflict with existing business services, unexpected port collision, or elevated resource pressure on the host.
