# Runbook: LAN service access and triage

## Purpose

This runbook explains how to check the services from another device on the same router/LAN.

LAN means local area network, here using the Mac IP `192.168.16.102`.

## Main entrypoints

Use these from another computer or phone on the same network:

- Homepage: `http://192.168.16.102:15002`
- Dockge: `http://192.168.16.102:15001`
- Uptime Kuma: `http://192.168.16.102:15003`
- Beszel: `http://192.168.16.102:15004`
- Traefik Dashboard: `http://192.168.16.102:15080/dashboard/`
- Sloth Cloud Web: `http://192.168.16.102:13000`
- Sloth Cloud API health: `http://192.168.16.102:14000/api/v1/health`
- Sloth Cloud Paymenter: `http://192.168.16.102:18080`
- Sloth Cloud Web Lab on K3s: `http://192.168.16.102:16080`
- Sloth Cloud API Lab health on K3s: `http://192.168.16.102:16080/api/v1/health`
- Xboard Web: `http://192.168.16.102:7001`

## Non-page services

These are real services, but not normal browser pages:

- Convoy on `18181`: current source tree has Caddy/PHP backend pieces but no `/public` browser UI, so treat it as a backend health target.
- Xboard WebSocket on `8076`: WebSocket means long-lived realtime connection. A browser GET returns `400 Bad Request`, which is expected.
- CLIProxy API: currently bound to `127.0.0.1`, so it is intentionally Mac-local only.

## Fast checks

```bash
for url in \
  http://192.168.16.102:15002/ \
  http://192.168.16.102:15080/dashboard/ \
  http://192.168.16.102:16080/ \
  http://192.168.16.102:16080/api/v1/health \
  http://192.168.16.102:7001/ \
  http://192.168.16.102:13000/ \
  http://192.168.16.102:14000/api/v1/health \
  http://192.168.16.102:18080/
do
  echo "---- $url"
  curl -i --max-time 8 "$url" | sed -n '1,10p'
done
```

Expected result: key browser pages return `200 OK`; Uptime Kuma may return `302 Found` to `/dashboard`.

## Error meaning

- `404 Not Found`: the port is reachable, but the path or hostname does not match a page.
- `502 Bad Gateway`: the proxy is reachable, but it cannot reach the backend container.
- `500 Internal Server Error`: the backend container is reachable, but the app itself failed.
- `ERR_CONNECTION_REFUSED`: nothing is listening on that IP/port, or the service/port-forward stopped.

## Xboard recovery note

On 2026-04-25, `sloth-xboard-web` was down because several bind-mounted files had become empty directories. The recovery used:

- backup the broken empty directories under `SlothVPN-source-clean/Xboard-master/.recovery/`
- restore PHP files from `ghcr.io/cedar2025/xboard:new`
- recreate local `.env` with a hidden generated `APP_KEY`
- copy SQLite state from `sloth-xboard-horizon`
- run database migrations
- set `REDIS_HOST=redis`

Do not publish the generated `.env`; it is local runtime state.

