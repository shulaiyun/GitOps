# Phase 01: Platform Core on Compose

## Goal

Add one shared operational layer above the existing compose estate so services become discoverable, routable, and observable without changing the app runtime underneath.

## Implemented in this repo

- `stacks/platform-core/compose.yaml` defines Traefik, Dockge, Homepage, Uptime Kuma, Beszel hub, and the gated Beszel agent profile.
- Homepage config is preloaded as the public-first unified service portal. The canonical address is `https://ops.shulaiyun.top`, so visitors only need to remember one URL.
- Traefik dynamic routes proxy current host-bound services under `*.localhost` hostnames.
- `inventory/uptime-targets.yaml` captures the intended Uptime Kuma monitor list.
- `Homepage`, `Beszel`, `Traefik`, `Dockge`, and `Uptime Kuma` can all be brought up from the same stack.
- `scripts/setup_beszel_local_agent.sh` provisions the local Beszel agent without hand-editing tokens into tracked files.
- `scripts/setup_uptime_kuma_targets.sh` bootstraps Uptime Kuma, creates the first admin user, and imports the tracked monitors.
- `scripts/sync_uptime_kuma_targets_sqlite.sh` can re-sync the tracked monitor inventory into an already initialized Uptime Kuma database. Re-sync means "make the Uptime Kuma panel match the repository inventory again", 中文就是“把监控面板重新对齐仓库里的清单”。
- LAN-accessible service entrypoints are documented in `runbooks/lan-service-access.md`.
- `stacks/public-gateway/compose.yaml` adds a single fixed-domain public gateway for Cloudflare Tunnel.
- `runbooks/public-fixed-domain-gateway.md` documents the public-domain flow with Chinese explanations for Public Gateway, Cloudflare Tunnel, Public Hostname, and Basic Auth.
- `scripts/recreate_cloudflare_tunnel_http2.sh` recreates the existing cloudflared connector with `protocol=http2` so proxy-heavy local networks do not break the tunnel.
- Cloudflare Tunnel now has 27 managed Public Hostnames pointing to the local public gateway. Public Hostname means a Cloudflare rule that maps one external domain to one internal service, 中文就是“公网域名到内网服务的映射规则”。
- Xboard Web was recovered on the Mac and now opens at `http://192.168.16.102:7001`.
- Uptime Kuma was recreated from the current `GitOps-learning` compose file so its data mount now lives under this repo instead of the removed `platform-control` path.

## Done definition

- Platform core stack parses successfully with `docker compose config`.
- Homepage renders the current runtime map.
- Dockge can manage new stacks under the platform stack directory.
- Uptime Kuma and Beszel are reachable on their direct ports and through Traefik.
- The local Beszel agent is connected and container metrics are available.
- Uptime Kuma has 21 monitors imported from `inventory/uptime-targets.yaml`, including public gate checks for `ops`, `argo-ops`, `cloud-ops`, `api-ops`, `uptime-ops`, and `beszel-ops`. Monitor means a health check target, 中文就是“一个被监控的服务入口”。
- Public gateway starts on `http://127.0.0.1:18088`. Only the canonical homepage `ops.shulaiyun.top` requires the shared Basic Auth gate; downstream links use their own app login pages or public behavior.
- `ops.shulaiyun.top` returns `401 Unauthorized` without Basic Auth from the public internet, proving the shared gate is active. Basic Auth means browser username/password gate, 中文就是“浏览器弹出的统一用户名密码门禁”。
- Public app hostnames such as `argo-ops.shulaiyun.top` and `cloud-ops.shulaiyun.top` are not wrapped by the shared Basic Auth gate, so they do not ask for the same password again after entering from the homepage.

## Verification

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
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
bash scripts/sync_uptime_kuma_targets_sqlite.sh
bash scripts/start_public_gateway.sh
bash scripts/check_public_gateway.sh
bash scripts/recreate_cloudflare_tunnel_http2.sh
python3 scripts/configure_cloudflare_public_hostnames.py --skip-dns
```

Public fixed-domain checks:

```bash
curl --noproxy '*' -k -I https://ops.shulaiyun.top
curl --noproxy '*' -k -I https://argo-ops.shulaiyun.top
curl --noproxy '*' -k -I https://cloud-ops.shulaiyun.top
curl --noproxy '*' -k -I https://api-ops.shulaiyun.top/api/v1/health
curl --noproxy '*' -k -I https://uptime-ops.shulaiyun.top
curl --noproxy '*' -k -I https://beszel-ops.shulaiyun.top
```

LAN checks:

```bash
curl -I http://192.168.16.102:15002
curl -I http://192.168.16.102:15080/dashboard/
curl -I http://192.168.16.102:16080
curl -I http://192.168.16.102:7001
```

Uptime Kuma monitor verification:

```bash
sqlite3 stacks/platform-core/data/uptime-kuma/kuma.db \
  "select count(*) from monitor;"

sqlite3 -header -column stacks/platform-core/data/uptime-kuma/kuma.db \
  "select m.id, m.name, h.status, h.msg
   from monitor m
   left join heartbeat h on h.id = (
     select id from heartbeat h2
     where h2.monitor_id = m.id
     order by h2.time desc
     limit 1
   )
   order by m.id;"
```

## Next entry point

Keep the monitor inventory in sync with new services, then add alert channels for Uptime Kuma.

## Open questions

- Which public hostnames should stay exposed long-term after the learning/demo phase?
- Should Uptime Kuma stay socket-script managed, or should the monitor list later become a pure Git-rendered backup/import artifact?
- Should Convoy be restored as a browser UI, or kept as a backend-only component under monitoring?
