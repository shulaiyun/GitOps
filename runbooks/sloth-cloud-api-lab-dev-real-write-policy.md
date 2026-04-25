# Runbook: Sloth Cloud API Lab Dev Real-Write Policy

## 中文先说结论

我们现在把 `sloth-cloud-api-lab` 的边界改清楚：

开发环境里的业务数据可以真实写，可以被实验影响。

包括：

- 付款
- 退款
- 开通服务
- 删除服务
- 重装系统
- 关机或重启开发 VPS
- 改开发 DNS
- 发真实 webhook
- 跑真实部署
- 写开发数据库

真正不能被破坏的是项目本体：

- 项目源代码
- Git 历史
- Compose 文件
- Kubernetes 控制清单
- 现有入口和流量切换规则
- 不属于当前开发环境的远端生产系统

## 为什么这样更适合学习

只读环境很安全，但不够真实。

如果 `sloth-cloud-api-lab` 永远不触发真实业务动作，你很难理解 Kubernetes 接入真实业务后会遇到什么问题，比如：

- 密钥是否完整
- 外部系统是否可达
- webhook 是否真的触发
- VPS 操作是否真的返回结果
- 部署任务是否真的创建资源
- 数据库写入是否真的改变业务状态

所以我们采用 `dev_real_write`：

```text
真实写开发业务状态
不破坏项目代码和平台控制文件
```

## 什么可以被实验影响

可以被实验影响的是“开发业务状态”。

例如：

| 类型 | 可以接受的影响 |
| --- | --- |
| 账单 | 测试订单、测试付款、测试退款记录变化 |
| 客户状态 | 开发环境里的测试客户状态变化 |
| 服务状态 | 测试服务被开通、暂停、删除 |
| VPS 状态 | 测试 VPS 被重启、关机、重装 |
| DNS | 开发域名或测试记录被修改 |
| Webhook | 开发 webhook 被真实触发 |
| 部署 | lab namespace 里产生真实部署资源 |
| 数据库 | 开发数据库被业务 API 写入 |

## 什么不能被实验影响

不能被实验影响的是“项目本体”。

例如：

| 类型 | 禁止影响 |
| --- | --- |
| 源码 | API 运行时不能改项目源码 |
| Git | API 运行时不能 push、reset、rewrite history |
| Compose | API 运行时不能改现有 Compose 文件 |
| K8s 控制清单 | API 运行时不能改 `platform-control` 里的清单 |
| 现有入口 | API lab 不能接管 `14000` 或正式域名 |
| 非开发远端 | 不能误操作远端生产 `xboard` 或其他未接受目标 |

## 同步前仍然要满足的条件

虽然开发业务数据可以被写，但这些阻塞项仍然必须解决：

1. 镜像不能再是 `ghcr.io/replace-me/...`
2. ConfigMap 里不能再有 `replace-me-*`
3. 必要密钥必须接上
5. 入口仍然只走 `sloth-cloud-api.lab.localhost`
6. 不能把 API 容器挂载到项目源码目录
7. 不能给 API 容器写 Git 仓库或控制仓库的权限

## 当前采用的启动方式

现在新增了 `lab-dev-real-write` overlay。

专业名词解释：

- `overlay`：覆盖配置层。它复用 base 基础清单，只替换实验环境需要变的镜像、地址和密钥引用。
- `ConfigMap`：Kubernetes 里的普通配置，不适合放密码。
- `Secret`：Kubernetes 里的敏感配置，用来放 token、API key、cookie secret。
- `host.docker.internal`：Mac Docker 提供的特殊主机名。Kubernetes 容器通过它访问 Mac 上已经暴露出来的本机开发服务。
- `k3d image import`：把 Mac Docker 里的镜像导入 k3d 集群内部，这样 Pod 不需要从公网镜像仓库拉取。

当前 `lab-dev-real-write` 做了三件事：

1. 把 API 镜像改成 `sloth-cloud-api-lab:dev`
2. 把 Paymenter、Convoy、Web 等地址改成本机开发服务地址
3. 改成手动创建 `sloth-cloud-api-lab-secrets`，不把密钥写进 Git

## 检查命令

```bash
cd "/Users/shulai/Library/Mobile Documents/com~apple~CloudDocs/Documents/New project/platform-control"
ruby scripts/check_sloth_cloud_api_lab_dependencies.rb --profile=dev_real_write
```

准备真正同步前：

```bash
ruby scripts/check_sloth_cloud_api_lab_dependencies.rb --profile=dev_real_write --strict --check-cluster-secret
```

严格模式会拦住占位符、缺失镜像替换和缺失的 Kubernetes Secret key。

## 当前阶段

当前阶段已经完成第一次手动 `SYNC`。

但仍然不要随手点 `DELETE`。

已经完成：

1. 导入本地 API 镜像
2. 从本机开发 env 种入 Kubernetes Secret
3. 运行严格检查
4. 手动点 `SYNC`
5. 确认 `Application` 为 `Synced / Healthy`
6. 确认 `/api/v1/health` 从 lab route 可访问

后续操作原则：

- 可以继续用这个 lab 练习真实开发业务写入。
- 不要点 `DELETE`，除非本轮目标就是撤销实验资源。
- 不要把 `sloth-cloud-api.lab.localhost` 改成正式业务入口。
- 不要给 API 容器挂载项目源码目录或 Git 仓库。
