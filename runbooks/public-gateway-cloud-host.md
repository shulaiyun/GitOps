# Runbook: Move Public Gateway Connector to a Cloud Host

## What this solves / 解决什么问题

`ops.shulaiyun.top` 有时能打开、有时变成 Cloudflare `502/530`，主要不是 Homepage 坏了，而是当前 Mac 上的 `cloudflared` connector 到 Cloudflare edge 的长连接不稳定。

- `cloudflared`：Cloudflare Tunnel 客户端，中文可以理解为“主动连出去的公网入口连接器”。
- connector：连接器，指这台机器上负责和 Cloudflare 保持连接的进程或容器。
- edge：Cloudflare 边缘节点，中文可以理解为“离访问者最近的 Cloudflare 网关”。
- origin：真实后端服务，中文就是“最终被访问的服务”。

把公网入口连接器放到一台稳定云主机上，可以让 `Cloudflare -> connector` 这一段更稳定。注意：如果真实服务仍然跑在 Mac 上，云主机还必须能访问 Mac。否则公网入口到了云主机以后，仍然找不到 Mac 上的 Homepage、Argo、Dockge 等服务。

## Recommended size / 云服务器规格

只运行 `cloudflared + Traefik public gateway`：

- 最低：`1 vCPU / 1 GiB RAM / 10 GiB disk`
- 推荐：`1 vCPU / 2 GiB RAM / 20 GiB disk`
- 系统：Ubuntu 22.04 LTS 或 Ubuntu 24.04 LTS
- 带宽：10 Mbps 起步可以用，100 Mbps 更舒服

如果还要把 Homepage、Uptime Kuma、Beszel、业务服务也搬到云主机：

- 起步：`2 vCPU / 4 GiB RAM / 40 GiB disk`
- 更稳：`4 vCPU / 8 GiB RAM / 80 GiB disk`

当前阶段建议先买最小规格做 connector，不要和远端生产 Xboard 放在同一台机器上。生产机是业务资产，公网入口实验会带来不必要的变更风险。

## Target architecture / 目标架构

```text
Visitor browser
  -> Cloudflare
  -> cloudflared on small cloud host
  -> public-gateway Traefik on cloud host
  -> Mac private address, usually through Tailscale/WireGuard
  -> Mac services: Homepage, Argo CD, Dockge, Uptime Kuma, Sloth Cloud lab
```

- Tailscale：一类私有组网工具，中文可以理解为“给两台机器拉一条安全内网”。
- WireGuard：VPN 组网协议，中文可以理解为“轻量、安全的机器到机器加密通道”。

最省心路线是 Tailscale：Mac 和云主机都装 Tailscale，云主机用 Mac 的 Tailscale IP 访问 `15002/16080/15001/15003/...` 这些端口。

## Step 1: Prepare the cloud host / 准备云主机

在云主机上安装 Docker：

```bash
apt-get update
apt-get install -y ca-certificates curl git
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

## Step 2: Connect cloud host to Mac / 让云主机能访问 Mac

推荐装 Tailscale：

```bash
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up
```

Mac 也安装并登录 Tailscale 后，在 Mac 上查看自己的 Tailscale IP：

```bash
tailscale ip -4
```

假设得到：

```text
100.64.12.34
```

那云主机上的 `PUBLIC_ORIGIN_HOST` 就填这个 IP。

## Step 3: Deploy gateway files / 部署公网入口文件

```bash
git clone https://github.com/shulaiyun/GitOps.git /opt/sloth-gitops
cd /opt/sloth-gitops
```

创建本地配置：

```bash
mkdir -p stacks/public-gateway
cat > stacks/public-gateway/.env.local <<'EOF'
PUBLIC_BASE_DOMAIN=shulaiyun.top
PUBLIC_GATEWAY_PORT=18088
PUBLIC_GATEWAY_USER=sloth
PUBLIC_GATEWAY_PASSWORD=replace-with-a-strong-password
PUBLIC_ORIGIN_HOST=100.64.12.34
EOF
```

`PUBLIC_ORIGIN_HOST` 是云主机访问 Mac 的地址。如果用 Tailscale，就填 Mac 的 Tailscale IP。

生成并启动公网入口网关：

```bash
bash scripts/setup_public_gateway_auth.sh
bash scripts/start_public_gateway.sh
```

## Step 4: Move the Cloudflare Tunnel connector / 迁移 Cloudflare 连接器

在 Cloudflare Zero Trust 的 Tunnel 页面里，把同一个 tunnel token 用到云主机上。云主机上运行：

```bash
docker run -d \
  --name sloth-cloud-local-tunnel \
  --restart unless-stopped \
  cloudflare/cloudflared:latest \
  tunnel --no-autoupdate --protocol http2 run --token "PASTE_TUNNEL_TOKEN_HERE"
```

然后停掉 Mac 上旧的 tunnel 容器：

```bash
docker stop sloth-cloud-local-tunnel
```

不要同时长期运行两个相同 tunnel 的 connector，除非你明确要做高可用。学习阶段先保留一个连接器，排障会简单很多。

## Step 5: Verify / 验证

在云主机上验证 public gateway 本地能分流：

```bash
curl -I http://127.0.0.1:18088/ -H 'Host: ops.shulaiyun.top'
curl -I http://127.0.0.1:18088/ -H 'Host: cloud-ops.shulaiyun.top'
curl -I http://127.0.0.1:18088/api/v1/health -H 'Host: api-ops.shulaiyun.top'
```

从任意公网网络验证：

```bash
curl -I https://ops.shulaiyun.top
curl -I https://cloud-ops.shulaiyun.top
curl -I https://api-ops.shulaiyun.top/api/v1/health
```

## Failure meanings / 常见故障含义

- `502/530`：Cloudflare 到 connector 或 connector 到 origin 不通。先看云主机 `docker logs sloth-cloud-local-tunnel`。
- `401` on `ops.shulaiyun.top`：正常，说明统一首页 Basic Auth 门禁生效。
- `404` on `convoy-ops.shulaiyun.top`：当前 Convoy 组件没有普通网页首页；Uptime Kuma 用这个状态确认“路由能到组件”，不是确认有用户页面。
- `connection refused`：端口没开、服务没启动，或 `PUBLIC_ORIGIN_HOST` 指错了。

## Current recommendation / 当前建议

先不要把业务迁上云主机，只迁“公网入口连接器 + public-gateway”。这样学习成本低、回滚也简单。等入口稳定后，再决定 Homepage/Uptime Kuma 是否也要常驻云端。
