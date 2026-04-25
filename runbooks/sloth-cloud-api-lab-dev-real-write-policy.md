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
3. `ExternalSecret` 不能再指向 `replace-me-secret-store`
4. 必要密钥必须接上
5. 入口仍然只走 `sloth-cloud-api.lab.localhost`
6. 不能把 API 容器挂载到项目源码目录
7. 不能给 API 容器写 Git 仓库或控制仓库的权限

## 检查命令

```bash
cd "/Users/shulai/Library/Mobile Documents/com~apple~CloudDocs/Documents/New project/platform-control"
ruby scripts/check_sloth_cloud_api_lab_dependencies.rb --profile=dev_real_write
```

准备真正同步前：

```bash
ruby scripts/check_sloth_cloud_api_lab_dependencies.rb --profile=dev_real_write --strict
```

严格模式仍然会拦住占位符和缺失的 secret store。

## 当前阶段

当前阶段还是不能点 `SYNC`。

不是因为真实写入不允许，而是因为：

- 镜像还没替换
- 业务依赖 URL 还是占位符
- secret store 还是占位符

下一步应该把这些占位符换成真实开发环境地址和密钥。
