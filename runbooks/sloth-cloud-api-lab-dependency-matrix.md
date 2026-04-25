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

## B. 已替换成本地或实验地址

这些之前是占位符，现在在 `lab-dev-real-write` overlay 里已经替换：

| 配置 | 当前问题 | 第一次同步前动作 |
| --- | --- | --- |
| `PAYMENTER_API_URL` | 本机开发 Paymenter | 通过 `host.docker.internal:18080` 访问 |
| `CONVOY_BASE_URL` | 本机开发 Convoy | 通过 `host.docker.internal:18181` 访问 |
| `MANAGED_APP_IMAGE_REGISTRY` | 开发镜像仓库 | 当前使用 `192.168.16.220:30500` |
| `MANAGED_APP_DEFAULT_DOMAIN_SUFFIX` | 开发域名后缀 | 当前使用 `shulaiyun.top` |
| `OPERATOR_PREVIEW_BASE_URL` | lab API 入口 | 当前使用 `sloth-cloud-api.lab.localhost:16080` |
| `OPERATOR_ARTIFACT_BASE_URL` | lab API 入口 | 当前使用 `sloth-cloud-api.lab.localhost:16080` |
| `OPERATOR_WEB_BASE_URL` | 本机开发 Web | 当前使用 `localhost:13000` |
| `OPERATOR_CLOUDFLARE_ZONE_NAME` | 开发 zone | 当前使用 `shulaiyun.top` |
| `OPERATOR_CLOUDFLARE_TUNNEL_SERVICE` | 本机开发 Web | 通过 `host.docker.internal:13000` 访问 |
| `OPERATOR_MONITORING_WEBHOOK_BASE_URL` | lab API 入口 | 当前使用 `sloth-cloud-api.lab.localhost:16080` |

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

这些都应该进入 `sloth-cloud-api-lab-secrets`。

当前学习环境先用手动 Kubernetes Secret，不使用 `ExternalSecret`。

专业名词解释：

- `ExternalSecret`：把外部密钥系统里的密钥同步进 Kubernetes Secret 的工具。
- `ClusterSecretStore`：External Secrets 用来连接外部密钥系统的集群级配置。
- 手动 Kubernetes Secret：先用脚本从本机开发 env 创建 Secret。它适合学习和本机实验，后面再换成 ExternalSecret。

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

种入命令：

```bash
bash scripts/seed_sloth_cloud_api_lab_secret_from_api_env.sh
```

## 同步前检查命令

```bash
cd "/Users/shulai/Library/Mobile Documents/com~apple~CloudDocs/Documents/New project/platform-control"
ruby scripts/check_sloth_cloud_api_lab_dependencies.rb
```

这个命令会检查：

- Deployment 里容器镜像是否还是 `replace-me`
- ConfigMap 里所有 key 是否都在分级表登记
- Deployment 是否引用了 `sloth-cloud-api-lab-secrets`
- 是否还有 `replace-me`

如果只是学习和盘点，可以直接看输出。

如果准备真正点 `SYNC`，用严格模式：

```bash
ruby scripts/check_sloth_cloud_api_lab_dependencies.rb --strict --check-cluster-secret
```

严格模式下，只要还有同步阻塞项，就会失败。

## 当前结论

`sloth-cloud-api-lab` 已经从“占位配置”推进到“dev_real_write 可启动配置”。

现在还差运行前动作：

- 把本机 Compose API 镜像导入 k3d
- 把本机开发 env 里的密钥种入 Kubernetes Secret
- 用严格模式确认 Secret key 齐全

然后才手动 `SYNC`。

注意：这仍然不会接管现有 Compose 的 `14000` 入口。
