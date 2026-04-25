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

`C. 暂时关闭或隔离`

这些配置会触发现实业务动作，例如调用真实支付、真实服务器管理、真实构建部署或真实 AI 额度。第一次同步前要么关掉，要么明确指向 lab 环境。

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

## C. 暂时关闭或隔离

这些配置不是“错”，但第一次同步前风险比较高：

| 配置 | 风险 | 建议 |
| --- | --- | --- |
| `PAYMENTER_MODE=live` | 可能调用真实客户/支付系统 | 第一次同步前关闭或指向 lab |
| `CONVOY_ENABLED=true` | 可能操作真实服务器管理系统 | 第一次同步前关闭或指向 lab Convoy |
| `CONVOY_MODE=live` | 明确是 live 模式 | 使用 lab-safe 模式或关闭 |
| `MANAGED_APP_ENABLED=true` | 可能在集群里创建构建/部署资源 | 先关闭，等 registry/RBAC/quota 好了再开 |
| `MANAGED_APP_DRIVER=in-cluster` | 会把当前 K8s 当执行环境 | 先隔离 namespace、权限和资源配额 |
| `MANAGED_APP_BUILD_NAMESPACE` | 构建命名空间需要治理 | 先创建 quota/RBAC，再启用 |
| `MANAGED_APP_IMAGE_REGISTRY_INSECURE=true` | 非安全 registry 访问 | 只允许本地 lab registry 使用 |
| `ASSISTANT_ENABLED=true` | 需要真实 AI provider 密钥和额度控制 | 密钥没准备好前先关闭 |

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
- live 集成还没决定是否关闭或隔离

下一步应该先做“最小可启动 profile”：

1. 关闭高风险 live 集成
2. 替换必要 URL
3. 接上最少密钥
4. 再考虑手动 `SYNC`
