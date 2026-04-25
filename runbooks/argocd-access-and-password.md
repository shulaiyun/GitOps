# Runbook: Argo CD Password and LAN Access

## 中文先说结论

你现在同一路由器里的其他电脑访问不了 Argo CD，核心原因通常不是 Argo 坏了，而是这两件事：

1. 你之前打开 Argo CD 用的是 `127.0.0.1` 或 `localhost`
2. `kubectl port-forward` 默认只监听本机地址，不监听局域网地址

这两个条件叠在一起，就会导致：

- 在这台 Mac 上可以打开
- 在别的电脑上不行

因为别的电脑访问 `127.0.0.1`，访问到的是“它自己”，不是这台 Mac。

另外，当前 `argocd-server` 的 Kubernetes `Service`（服务）类型还是 `ClusterIP`，这也表示它默认只在集群内部可见，不会自己暴露给局域网。

## 当前真实状态

当前这套 Mac 实验集群里：

- `argocd-server` 是 `ClusterIP`
- 要从浏览器访问它，靠的是 `kubectl port-forward`
- `kubectl port-forward` 默认监听 `localhost`
- 当前本地学习环境已把 `argocd-server` 调成 `server.insecure=true`，所以浏览器访问走 HTTP，避免自签 HTTPS 证书拦截

所以这是一个“默认仅本机访问”的入口。

专业名词解释：

- `ClusterIP`：Kubernetes 里的内部服务地址，只能在集群内部直接访问。
- `port-forward`：临时把本机端口转发到集群里的某个服务。
- `server.insecure=true`：Argo CD 的本地学习模式，表示 UI 用 HTTP，不强制跳转自签 HTTPS。
- 自签 HTTPS 证书：不是公网 CA 签发的证书，浏览器会警告；本地实验可用 HTTP 绕开这个学习障碍。

## 怎么改 Argo 登录密码

Argo CD 官方支持两种思路：

- 已经能登录时，用 `argocd account update-password`
- 忘记了或想直接重置时，更新 `argocd-secret` 里的 `admin.password`

当前这台 Mac 没有安装本地 `argocd` CLI（命令行工具），所以仓库里提供的是第二种做法的脚本版：

```bash
cd "/Users/shulai/Library/Mobile Documents/com~apple~CloudDocs/Documents/New project/platform-control"
bash scripts/reset_argocd_admin_password.sh
```

执行后脚本会静默提示你输入两次新密码，不会把密码直接写进 shell 历史。

这个脚本会做三件事：

1. 在 `argocd-server` 容器里生成新的 `bcrypt`（密码哈希）
2. 更新 `argocd-secret`
3. 删除 `argocd-initial-admin-secret`，避免旧初始密码继续留着

改完后：

- 用户名还是 `admin`
- 密码就是你刚设置的新密码

## 为什么别的电脑访问不了

### 原因 1：你之前用的是 `127.0.0.1`

这个地址只代表“当前这台电脑自己”。

所以：

- 在 Mac 上访问 `https://127.0.0.1:19080`，能通
- 在别的电脑上访问 `https://127.0.0.1:19080`，访问到的是那台别的电脑自己

### 原因 2：`kubectl port-forward` 默认只绑到本机

Kubernetes 官方文档里，`kubectl port-forward` 的默认监听地址就是 `localhost`。

所以，即使你知道这台 Mac 的局域网 IP，例如 `192.168.16.110`，如果 `port-forward` 还是默认模式，别的电脑也连不上。

## 怎么让同一路由器的其他电脑访问

使用这个脚本：

```bash
cd "/Users/shulai/Library/Mobile Documents/com~apple~CloudDocs/Documents/New project/platform-control"
ARGOCD_BIND_ADDRESS=0.0.0.0 bash scripts/start_argocd_ui_port_forward.sh
```

它会把 `kubectl port-forward` 监听到所有网卡地址，而不是只监听 `127.0.0.1`。

然后，在同一路由器里的别的电脑上访问：

```text
http://192.168.16.110:19080
```

这里的 `192.168.16.110` 要换成这台 Mac 当前的局域网 IP。

## 如果还是打不开，通常看这 4 件事

1. 这个 `port-forward` 终端窗口是不是还开着  
   关了就断了。

2. 你是不是还在访问 `127.0.0.1`  
   局域网访问必须改成这台 Mac 的局域网 IP。

3. `macOS` 防火墙是不是挡住了  
   如果防火墙开着，可能需要允许终端或 `kubectl` 的入站连接。

4. 路由器或 Wi-Fi 有没有“客户端隔离”  
   有些路由器会禁止同一 Wi-Fi 下设备互相访问。

## 本机访问和局域网访问的区别

### 只想自己这台 Mac 打开

```bash
cd "/Users/shulai/Library/Mobile Documents/com~apple~CloudDocs/Documents/New project/platform-control"
bash scripts/start_argocd_ui_port_forward.sh
```

访问：

```text
http://127.0.0.1:19080
```

### 想让同一路由器里的其他电脑也打开

```bash
cd "/Users/shulai/Library/Mobile Documents/com~apple~CloudDocs/Documents/New project/platform-control"
ARGOCD_BIND_ADDRESS=0.0.0.0 bash scripts/start_argocd_ui_port_forward.sh
```

访问：

```text
http://这台Mac的局域网IP:19080
```

## 补一句边界

这套方式适合：

- 本地学习
- 局域网演示
- 临时从其他电脑看 Argo CD

它还不是正式长期发布入口。

如果以后你想让 Argo CD 稳定成为局域网或固定域名入口，更合适的是：

- 单独做 `Ingress` / `Gateway` 暴露
- 或者给它挂专门域名和反向代理
- 到正式环境再恢复 HTTPS 和可信证书

但对你现在这套 Mac 实验集群来说，`port-forward + 局域网地址` 已经够用了。
