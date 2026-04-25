# Runbook: Sloth Cloud API Lab Dependency Matrix

## 中文先说结论

这一步不是部署，而是给 `sloth-cloud-api-lab` 做“同步前体检表”。

现在 `sloth-cloud-api-lab` 在 Argo CD 里是：

- `OutOfSync`：Git 里有配置，但集群里还没同步
- `Missing`：集群里还没有这些资源

这个状态是安全的。我们暂时不点 `SYNC`，先把它依赖的配置分清楚。

## 四类配置

`A. lab 可以直接用`

实验环境可以暂时保留，不阻塞第一次同步。

`B. 必须替换成本地或实验地址`

这些配置里有 `replace-me`，或者明确指向还不存在的服务。第一次同步前必须改掉。

`C. 开发环境真实写入，需要明确边界`

这些配置会触发现实业务动作，例如调用真实支付、真实服务器管理、真实构建部署或真实 AI 额度。

在 `dev_real_write` profile 下，这类动作允许影响开发环境业务数据。它们不再要求必须关闭，但必须确认目标是开发环境，且不能破坏项目代码、Git、Compose 或 K8s 控制文件。

`D. 必须进 Secret / ExternalSecret`

这些是密钥、Token、API Key，不能放进 ConfigMap。

## A. lab 可以直接用

这些配置目前不阻塞实验部署：

| 配置 | 中文说明 |
| --- | --- |
| `PORT` | API 容器内部监听端口，当前是 `4000` |
| `PLATFORM_ENV` | 环境标识，当前是 `lab` |
| `SESSION_COOKIE_SECURE` | 本地实验可先为 `false`，生产再收紧 |
| `RUNTIME_READ_CACHE_TTL_MS` | 运行状态缓存时间 |
| `CONVOY_TIMEOUT_MS` | Convoy 请求超时时间 |
| `CONVOY_APPLICATION_PREFIX` | Convoy API 路径前缀 |
| `CONVOY_SERVER_REF_KEYS` | 服务器引用字段名列表 |
| `MANAGED_APP_*` 资源和构建调优项 | 在 managed app 功能关闭前，这些只是配置 |
| `ASSISTANT_*` 配额和会话参数 | 在 assistant 功能关闭或密钥准备好后可用 |

## B. 必须替换成本地或实验地址

这些当前还是占位符：

| 配置 | 当前问题 | 第一次同步前动作 |
| --- | --- | --- |
| `PAYMENTER_API_URL` | `replace-me-paymenter` | 指向 lab Paymenter，或关闭 Paymenter 路径 |
| `CONVOY_BASE_URL` | `replace-me-convoy` | 指向 lab Convoy |
| `MANAGED_APP_IMAGE_REGISTRY` | `replace-me-registry` | 指向真实 lab 镜像仓库 |
| `MANAGED_APP_DEFAULT_DOMAIN_SUFFIX` | `replace-me.example` | 换成 lab 域名后缀 |
| `OPERATOR_PREVIEW_BASE_URL` | `replace-me-api` | 指向 lab API 或 preview 服务 |
| `OPERATOR_ARTIFACT_BASE_URL` | `replace-me-api` | 指向 lab artifact 服务 |
| `OPERATOR_WEB_BASE_URL` | `replace-me-web` | 指向 lab Web |
| `OPERATOR_CLOUDFLARE_ZONE_NAME` | `replace-me-zone` | 换成 lab zone 或关闭 Cloudflare 路径 |
| `OPERATOR_CLOUDFLARE_TUNNEL_SERVICE` | `replace-me-web` | 指向 lab tunnel target 或关闭 |
| `OPERATOR_MONITORING_WEBHOOK_BASE_URL` | `replace-me-api` | 指向 lab webhook 或关闭 |

## C. 开发环境真实写入，需要明确边界

这些配置不是“错”，它们正是让 lab 接触真实业务的地方。当前接受开发环境业务数据被实验改动，但仍然保护项目本体。

| 配置 | 会影响什么 | 当前策略 |
| --- | --- | --- |
| `PAYMENTER_MODE=live` | 开发订单、付款、退款状态 | 允许，但必须是开发环境 Paymenter |
| `CONVOY_ENABLED=true` | 开发 VPS 的开通、删除、重装、电源状态 | 允许，但必须是开发环境 Convoy |
| `CONVOY_MODE=live` | 真实调用 Convoy API | 允许连接开发 Convoy |
| `MANAGED_APP_ENABLED=true` | 创建真实构建和部署资源 | 允许，但只进 lab namespace / lab registry |
| `MANAGED_APP_DRIVER=in-cluster` | 使用当前 K8s 做部署执行环境 | 允许，但不能挂载或改项目源码 |
| `MANAGED_APP_BUILD_NAMESPACE` | 创建构建 Pod 和临时资源 | 允许，但需要 namespace、RBAC 和 quota |
| `MANAGED_APP_IMAGE_REGISTRY_INSECURE=true` | 使用非 HTTPS registry | 只允许本地/开发 registry |
| `ASSISTANT_ENABLED=true` | 消耗开发环境 AI provider 额度 | 允许，但密钥和额度 cookie secret 必须存在 |

## Dev real-write 边界

我们现在采用 `dev_real_write`：

```text
允许真实写开发业务状态
禁止破坏项目本体
```

允许被实验影响：

- 测试付款、退款、订单
- 测试客户状态
- 测试服务开通和删除
- 开发 VPS 重启、关机、重装
- 开发 DNS 记录
- 开发 webhook
- lab 部署资源
- 开发数据库业务写入

仍然禁止：

- API 运行时改源码
- API 运行时 push / reset / rewrite Git
- API 运行时改 Compose 文件
- API 运行时改 `platform-control` 控制清单
- lab 接管 `14000` 或正式域名入口
- 误操作不属于当前开发环境的远端生产系统

## D. 必须进 Secret / ExternalSecret

这些都应该通过 `ExternalSecret` 进入 `sloth-cloud-api-lab-secrets`：

| Secret key | 中文说明 |
| --- | --- |
| `CONVOY_APPLICATION_KEY` | Convoy 应用密钥 |
| `MANAGED_APP_INTERNAL_API_TOKEN` | managed app 内部 API token |
| `ASSISTANT_OPENAI_API_KEY` | OpenAI API Key |
| `ASSISTANT_GEMINI_API_KEY` | Gemini API Key |
| `ASSISTANT_CLAUDE_API_KEY` | Claude API Key |
| `ASSISTANT_QUOTA_COOKIE_SECRET` | AI 配额 cookie 签名密钥 |
| `OPERATOR_CLOUDFLARE_API_TOKEN` | Cloudflare API token |
| `OPERATOR_MONITORING_WEBHOOK_SECRET` | 监控 webhook 密钥 |

另外，`ExternalSecret` 里的 `secretStoreRef.name` 现在还是：

```yaml
replace-me-secret-store
```

第一次同步前必须替换成真实的 `ClusterSecretStore`。

## 同步前检查命令

```bash
cd "/Users/shulai/Library/Mobile Documents/com~apple~CloudDocs/Documents/New project/platform-control"
ruby scripts/check_sloth_cloud_api_lab_dependencies.rb
```

这个命令会检查：

- Deployment 里容器镜像是否还是 `replace-me`
- ConfigMap 里所有 key 是否都在分级表登记
- ExternalSecret 里所有 secretKey 是否都在分级表登记
- 是否还有 `replace-me`
- secret store 是否还是占位符

如果只是学习和盘点，可以直接看输出。

如果准备真正点 `SYNC`，用严格模式：

```bash
ruby scripts/check_sloth_cloud_api_lab_dependencies.rb --strict
```

严格模式下，只要还有同步阻塞项，就会失败。

## 当前结论

`sloth-cloud-api-lab` 现在不应该同步。

原因不是 Kubernetes 结构有问题，而是运行材料还没准备好：

- 镜像还是占位符
- 上游 URL 还有 `replace-me`
- secret store 还是占位符
- live 集成已经允许用于开发环境真实写入，但还没有真实开发地址和密钥

下一步应该先做“dev_real_write 可启动 profile”：

1. 替换必要 URL
2. 接上必要密钥
3. 确认 API 容器不能修改项目代码和控制仓库
4. 再考虑手动 `SYNC`
