# Runbook: LAN service access and triage

## Purpose / 目的

这份手册用来说明：如何从同一个路由器下的其他电脑或手机访问这些服务，以及出错时怎么判断原因。

LAN 是 Local Area Network，中文就是“局域网”。这里的 Mac 局域网 IP 是 `192.168.16.102`。

## Main entrypoints / 主要入口

在同一个 Wi-Fi 或路由器下，其他设备可以直接打开这些地址：

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

## Non-page services / 不是网页的服务

下面这些也是正常运行的服务，但它们不是普通浏览器网页：

- Convoy on `18181`: current source tree has Caddy/PHP backend pieces but no `/public` browser UI, so treat it as a backend health target.
- Xboard WebSocket on `8076`: WebSocket 是“长连接实时通信”。浏览器直接打开会返回 `400 Bad Request`，这是预期现象。
- CLIProxy API: currently bound to `127.0.0.1`, so it is intentionally Mac-local only.

## Uptime Kuma monitoring / 统一健康监控

Uptime Kuma 是“黑盒监控”页面。Black-box monitoring 的意思是：从外部像用户一样检查服务，例如打开一个 HTTP 地址，或者检查一个 TCP 端口能不能连上。

监控清单在这里：

```bash
/Users/shulai/Documents/New project/GitOps-learning/inventory/uptime-targets.yaml
```

首次导入或重新导入监控项：

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
bash scripts/setup_uptime_kuma_targets.sh
```

如果 Uptime Kuma 已经有管理员，只是想把仓库里的监控清单同步进去：

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
bash scripts/sync_uptime_kuma_targets_sqlite.sh
```

本机登录凭据文件在这里：

```bash
/Users/shulai/Documents/New project/GitOps-learning/stacks/platform-core/data/uptime-kuma/credentials.env
```

不要提交或公开这个文件。

当前应该有 `14` 个监控项。

数据库里的状态值含义：

- `1`: Up, normal.
- `0`: Down, failed.
- `2`: Pending, not checked yet.

## Fast checks / 快速检查

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

预期结果：主要网页返回 `200 OK`；Uptime Kuma 如果跳转到 `/dashboard`，可能会返回 `302 Found`，这也是正常的。

## Error meaning / 常见错误含义

- `404 Not Found`: the port is reachable, but the path or hostname does not match a page.
- `502 Bad Gateway`: the proxy is reachable, but it cannot reach the backend container.
- `500 Internal Server Error`: the backend container is reachable, but the app itself failed.
- `ERR_CONNECTION_REFUSED`: nothing is listening on that IP/port, or the service/port-forward stopped.

## Xboard recovery note / Xboard 恢复记录

On 2026-04-25, `sloth-xboard-web` was down because several bind-mounted files had become empty directories. The recovery used:

- backup the broken empty directories under `SlothVPN-source-clean/Xboard-master/.recovery/`
- restore PHP files from `ghcr.io/cedar2025/xboard:new`
- recreate local `.env` with a hidden generated `APP_KEY`
- copy SQLite state from `sloth-xboard-horizon`
- run database migrations
- set `REDIS_HOST=redis`

Do not publish the generated `.env`; it is local runtime state.
