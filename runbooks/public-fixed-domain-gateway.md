# Runbook: Public Fixed-Domain Gateway

## Purpose / 目的

这份手册把当前 Mac 上的服务统一暴露到固定域名。

核心思路：

- Public Gateway：公开入口网关。外部访问先进入这个网关，再转发到真正服务。
- Cloudflare Tunnel：Cloudflare 隧道。它让外网访问你的 Mac，但不需要你在路由器上做端口转发。
- Public Hostname：公开域名规则。例如 `argo.ops.shulaiyun.top` 指向哪个本地服务。
- Basic Auth：浏览器弹窗用户名密码。即使某个后台面板本身有登录页，也先加一层统一门禁。

## Local gateway / 本地网关

本地网关使用 Traefik。Traefik 是一个反向代理和入口网关，中文可以理解为“门口分流器”：它根据访问的域名把请求送到不同服务。

初始化账号密码并生成配置：

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
bash scripts/setup_public_gateway_auth.sh
```

启动网关：

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
bash scripts/start_public_gateway.sh
```

本地验证：

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
bash scripts/check_public_gateway.sh
```

## Public hostnames / 固定公开域名

默认域名后缀是 `shulaiyun.top`。如果要换域名，编辑这个本地文件：

```bash
/Users/shulai/Documents/New project/GitOps-learning/stacks/public-gateway/.env.local
```

然后重新生成并启动：

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
bash scripts/setup_public_gateway_auth.sh
bash scripts/start_public_gateway.sh
```

当前建议创建这些公开域名：

- `ops.shulaiyun.top` -> Homepage
- `argo-ops.shulaiyun.top` -> Argo CD, HTTPS-friendly preferred host
- `cloud-ops.shulaiyun.top` -> Sloth Cloud Web, HTTPS-friendly preferred host
- `api-ops.shulaiyun.top` -> Sloth Cloud API, HTTPS-friendly preferred host
- `argo.ops.shulaiyun.top` -> Argo CD
- `dockge.ops.shulaiyun.top` -> Dockge
- `uptime.ops.shulaiyun.top` -> Uptime Kuma
- `beszel.ops.shulaiyun.top` -> Beszel
- `traefik.ops.shulaiyun.top` -> Traefik Dashboard
- `cloud.ops.shulaiyun.top` -> Sloth Cloud Web
- `api.ops.shulaiyun.top` -> Sloth Cloud API
- `paymenter.ops.shulaiyun.top` -> Paymenter
- `xboard.ops.shulaiyun.top` -> Xboard
- `cloud-lab.ops.shulaiyun.top` -> K3s Sloth Cloud Web Lab
- `api-lab.ops.shulaiyun.top` -> K3s Sloth Cloud API Lab
- `convoy.ops.shulaiyun.top` -> Convoy component endpoint

Prefer the `*-ops.shulaiyun.top` names for browser sharing. They are one-label subdomains under `shulaiyun.top`, so Cloudflare's normal wildcard certificate is more likely to cover them immediately. The `*.ops.shulaiyun.top` names are still kept as aliases, but they may need extra DNS/certificate setup before HTTPS works.

每个 Cloudflare Public Hostname 的本地服务地址都填：

```text
http://host.docker.internal:18088
```

这里 `host.docker.internal` 的意思是：从 Docker 容器里访问这台 Mac 本机。

## Cloudflare setup / Cloudflare 配置

Cloudflare 这一侧必须有账号权限。现有的 `sloth-cloud-local-tunnel` token 只能让隧道连接 Cloudflare，不能新增域名规则。

当前这台 Mac 上的 tunnel container（隧道容器）建议使用 `http2` 协议连接 Cloudflare：

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
bash scripts/recreate_cloudflare_tunnel_http2.sh
```

这里的 `http2` 是 Cloudflare 隧道连接协议。默认的 `quic` 基于 UDP，中文可以理解为“走 UDP 的快速通道”，但在代理、校园网、公司网或部分路由器下更容易被拦；`http2` 走 TCP，通常更稳。

当前从 tunnel 日志已经确认远端还有旧规则，例如 wildcard hostname（通配域名）`*.shulaiyun.top` 可能还指向旧内网地址。所以固定域名要真正公网生效，必须在 Cloudflare 里把下方这些 Public Hostname 规则改到新的 public gateway。

你有两种办法：

1. 给本机配置 Cloudflare API Token，然后用脚本自动创建公开域名。
2. 在 Cloudflare Zero Trust 网页里，进入当前 Tunnel，手动新增 Public Hostnames。

自动配置命令：

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
bash scripts/save_cloudflare_api_token.sh
python3 scripts/configure_cloudflare_public_hostnames.py
```

API Token 是 Cloudflare 的接口密钥。这个脚本需要：

- Zone DNS Edit：允许创建或更新 DNS 记录。
- Account Cloudflare Tunnel Edit：允许更新 Tunnel 的 Public Hostname 配置。

脚本会做两件事：

- 更新 Tunnel ingress。Ingress 在这里指“外部域名进来后走哪条内部服务规则”。
- 创建或更新 DNS CNAME。CNAME 是“域名别名记录”，这里会把 `argo.ops.shulaiyun.top` 等域名指向 Cloudflare Tunnel。

脚本会保留 Tunnel 里不属于本项目的现有域名规则，只替换本文件列出的 `*.ops.shulaiyun.top` 规则。

手动新增时：

- Subdomain 填 `ops`、`argo.ops`、`dockge.ops` 等。
- Domain 选择 `shulaiyun.top`。
- Type 选择 `HTTP`。
- URL 填 `host.docker.internal:18088`。

## Security notes / 安全说明

- 不建议把 Dockge、Argo CD、Uptime Kuma、Beszel 裸露到公网。
- 当前网关已经加了 Basic Auth 作为第一层门禁。
- 真正面向长期公网使用时，建议再加 Cloudflare Access。Cloudflare Access 是 Cloudflare 的身份验证层，可以限制只有指定邮箱、GitHub 账号或一次性验证码用户能进入。
- `stacks/public-gateway/.env.local` 和 `stacks/public-gateway/data/` 是本地秘密和生成配置，不要提交到 Git。
- 参考 Cloudflare 官方文档：Tunnel configuration API 支持 `ingress` 规则；DNS API 支持创建 CNAME 记录并设置 `proxied`。

## Rollback / 回滚

停止公开入口：

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
docker compose --env-file stacks/public-gateway/.env.local -f stacks/public-gateway/compose.yaml down
```

如果已经在 Cloudflare 上创建了 Public Hostname，也要在 Cloudflare Zero Trust 里删除对应域名规则。

## References / 参考资料

- Cloudflare Tunnel DNS 说明：`https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/routing-to-tunnel/dns/`
- Cloudflare Tunnel ingress 配置说明：`https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/configuration-file/`
- Cloudflare DNS Records API：`https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/create/`
- Cloudflare Tunnel API：`https://developers.cloudflare.com/api/resources/zero_trust/subresources/tunnels/subresources/cloudflared/subresources/connections/methods/get/`
