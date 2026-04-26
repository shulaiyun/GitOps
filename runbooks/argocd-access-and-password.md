# Runbook: Argo CD Password and LAN Access

## 中文先说结论

你现在同一路由器里的其他电脑访问不了 Argo CD，核心原因通常不是 Argo 坏了，而是这几件事之一：

1. 你之前打开 Argo CD 用的是 `127.0.0.1` 或 `localhost`
2. `kubectl port-forward` 默认只监听本机地址，不监听局域网地址
3. 浏览器开了系统代理，`.local` 局域网名字被送进代理后解析失败

这两个条件叠在一起，就会导致：

- 在这台 Mac 上可以打开
- 在别的电脑上不行

因为别的电脑访问 `127.0.0.1`，访问到的是“它自己”，不是这台 Mac。

另外，当前 `argocd-server` 的 Kubernetes `Service`（服务）类型还是 `ClusterIP`，这表示它默认只在集群内部可见，不会自己暴露给局域网。现在我们给它补了一个更稳定的局域网入口：通过 K3s/k3d 里的 Traefik Gateway 转发到 `argocd-server`。

## 当前真实状态

当前这套 Mac 实验集群里：

- `argocd-server` 是 `ClusterIP`
- 旧方式是靠 `kubectl port-forward` 临时打开
- Mac 本机可用 `HTTPRoute` 固定挂到 `http://<这台Mac名字>.local:16080/`
- 同一路由器里的其他设备，推荐用独立局域网端口：`http://<这台Mac局域网IP>:19082/`
- 当前本地学习环境已把 `argocd-server` 调成 `server.insecure=true`，所以浏览器访问走 HTTP，避免自签 HTTPS 证书拦截

所以现在不需要长期挂着一个 port-forward 终端窗口。

专业名词解释：

- `ClusterIP`：Kubernetes 里的内部服务地址，只能在集群内部直接访问。
- `port-forward`：临时把本机端口转发到集群里的某个服务。
- `HTTPRoute`：Gateway API 的 HTTP 路由规则，用域名把请求转给 Kubernetes Service。
- `Gateway`：Kubernetes 里的统一入口。这里是 Traefik 提供的本地网关。
- `.local`：局域网本机发现域名，通常由 macOS/Bonjour/mDNS 提供，不依赖公网 DNS。
- `server.insecure=true`：Argo CD 的本地学习模式，表示 UI 用 HTTP，不强制跳转自签 HTTPS。
- 自签 HTTPS 证书：不是公网 CA 签发的证书，浏览器会警告；本地实验可用 HTTP 绕开这个学习障碍。
- `LAN port-forward`：局域网端口转发。这里把这台 Mac 的 `19082` 端口转发到 Kubernetes 里的 `argocd-server`。

## 推荐给其他设备用：独立局域网端口

先安装后台任务：

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
bash scripts/install_argocd_lan_port_forward_agent.sh
```

它会创建一个 macOS `LaunchAgent`，长期维持这个转发：

```text
http://192.168.16.102:19082/
```

这条入口的好处是：

- 不依赖 `.local` 名字解析
- 不会跟 `16080` 上的 Sloth Cloud / Gateway API 路由混在一起
- 不需要你手动开一个终端窗口挂着

专业名词解释：

- `kubectl port-forward`：把本机端口转发到 Kubernetes 集群里的服务。
- `--address 0.0.0.0`：监听所有网卡，别的设备才能通过局域网 IP 访问。
- `KeepAlive`：macOS 后台任务保持运行；如果进程异常退出，会自动拉起来。

验证：

```bash
launchctl print gui/$(id -u)/com.sloth.argocd-lan-port-forward | sed -n '1,90p'
curl -I --max-time 8 http://192.168.16.102:19082/
```

看到 `state = running`，并且 `curl` 返回 `HTTP/1.1 200 OK`，就说明其他设备应该也能打开。

## Mac 本机也可用：固定 HTTPRoute 入口

先执行一次：

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
bash scripts/apply_argocd_lan_route.sh
```

脚本会自动读取这台 Mac 的 `LocalHostName`，转成小写，然后创建 Argo CD 的 `HTTPRoute`。

当前这台 Mac 的入口通常是：

```text
http://jianxingjiandemacbook-air.local:16080/
```

这里的 `16080` 是本地 K3s/k3d 集群的 HTTP 入口端口。请求路径是：

```text
浏览器
-> jianxingjiandemacbook-air.local:16080
-> k3d-sloth-lab-serverlb
-> Traefik Gateway
-> HTTPRoute argocd-lan
-> Service argocd-server
-> Argo CD Pod
```

如果打开后是 Argo CD 登录页，说明入口正常。

## v2rayN/系统代理导致 502 怎么办

如果浏览器开着代理时访问：

```text
http://jianxingjiandemacbook-air.local:16080/
```

出现 `HTTP ERROR 502`，但关掉代理后能打开，这通常不是 Argo CD 坏了。

原因是：

- `.local` 依赖 macOS 的本地发现能力
- 请求进入代理后，代理程序不一定能按 macOS 的方式解析 `.local`
- 所以局域网地址应该绕过代理，直接访问

手动修复一次可以执行：

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
bash scripts/fix_macos_local_proxy_bypass.sh
```

它会把这些地址加入 macOS 代理绕过列表：

- `*.local`
- 当前 Mac 的 `.local` 名字
- `192.168.0.0/16`
- `10.0.0.0/8`
- `172.16.0.0/12`
- `localhost` / `127.0.0.0/8`

专业名词解释：

- `proxy bypass`：代理绕过。匹配到这些地址时，浏览器不走代理，直接连接。
- `mDNS`：局域网名字发现机制，macOS 的 `.local` 主机名通常靠它工作。
- `502 Bad Gateway`：代理或网关能收到请求，但它后面找不到或连不上真实服务。

如果发现 v2rayN 或系统代理过一会儿又把规则重置掉，安装自动修复任务：

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
bash scripts/install_macos_local_proxy_bypass_agent.sh
```

这个脚本会安装一个 macOS `LaunchAgent`，它会在登录时和每 5 分钟自动补齐代理绕过规则。

专业名词解释：

- `LaunchAgent`：macOS 的用户级后台任务，适合做“登录后自动执行”和“定时执行”的小任务。
- `StartInterval`：定时执行间隔。这里是 `300` 秒，也就是每 5 分钟。
- `Application Support`：macOS 给应用和脚本放运行配置的位置。后台任务直接执行 `Documents` 目录里的脚本可能被系统隐私权限拦住，所以安装脚本会复制一个可执行副本到这里。

验证它有没有装好：

```bash
launchctl print gui/$(id -u)/com.sloth.local-proxy-bypass | sed -n '1,80p'
scutil --proxy | sed -n '1,80p'
curl -I --max-time 8 http://jianxingjiandemacbook-air.local:16080/
```

看到 `last exit code = 0`、`ExceptionsList` 里有 `*.local` 和 `jianxingjiandemacbook-air.local`，并且 `curl` 返回 `HTTP/1.1 200 OK`，就说明正常。

## 怎么改 Argo 登录密码

Argo CD 官方支持两种思路：

- 已经能登录时，用 `argocd account update-password`
- 忘记了或想直接重置时，更新 `argocd-secret` 里的 `admin.password`

当前这台 Mac 没有安装本地 `argocd` CLI（命令行工具），所以仓库里提供的是第二种做法的脚本版：

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
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
cd "/Users/shulai/Documents/New project/GitOps-learning"
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
cd "/Users/shulai/Documents/New project/GitOps-learning"
bash scripts/start_argocd_ui_port_forward.sh
```

访问：

```text
http://127.0.0.1:19080
```

### 想让同一路由器里的其他电脑也打开

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
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
