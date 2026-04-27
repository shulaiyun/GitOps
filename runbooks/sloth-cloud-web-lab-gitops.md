# Runbook: Sloth Cloud Web Lab GitOps Deployment

## 中文先说结论

这个 Web lab 是 Sloth Cloud 前端在 Kubernetes 里的实验入口，不接管现有 Compose 前端。

- Kubernetes 入口：`http://cloud.lab.localhost:16080`
- Kubernetes 命名空间：`sloth-labs`
- Argo CD 应用：`sloth-cloud-web-lab`
- API 上游：`sloth-cloud-api-lab` 的 Kubernetes Service
- 同步方式：手动 `SYNC`

## Key Terms

- Web: 前端页面服务，浏览器打开的 Sloth Cloud 界面。
- API: 后端接口服务，处理登录、服务、账单、部署等请求。
- Proxy: 代理。这里 Web 容器收到 `/api` 请求后，会转发给 API Service。
- Service: Kubernetes 内部稳定访问入口，避免直接依赖会变化的 Pod IP。
- HTTPRoute: Gateway API 路由规则，把域名请求送到对应 Service。
- Argo CD Application: Argo CD 管理的一组 GitOps 资源。

## Prepared Assets

- Base manifests: `k8s/apps/sloth-cloud-web/base`
- Lab overlay: `k8s/apps/sloth-cloud-web/lab-dev-real-write`
- Application template: `k8s/bootstrap/manifests/sloth-cloud-web-lab-application.template.yaml`
- Render helper: `scripts/render_sloth_cloud_web_lab_application.sh`
- Image import helper: `scripts/import_sloth_cloud_web_lab_image.sh`

## Rollout

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
ruby scripts/validate_k8s_manifests.rb
bash scripts/import_sloth_cloud_web_lab_image.sh
bash scripts/render_sloth_cloud_web_lab_application.sh | kubectl apply -f -
```

Then sync `sloth-cloud-web-lab` in Argo CD, or trigger a one-time sync from the CLI.

## Verification

```bash
kubectl -n argocd get application sloth-cloud-web-lab
kubectl -n sloth-labs get deploy,svc,httproute,pod -l app.kubernetes.io/name=sloth-cloud-web
curl -i http://cloud.lab.localhost:16080/
curl -i http://cloud.lab.localhost:16080/api/v1/health
```

Expected result:

- `Application` is `Synced` and `Healthy`
- `Deployment` is `1/1`
- `/` returns the Web app HTML
- `/api/v1/health` returns API health through the Web proxy

## First Sync Result

Completed on 2026-04-25 in the Mac `k3d` lab.

Verified state:

```text
Application: sloth-cloud-web-lab Synced / Healthy
Deployment: sloth-cloud-web 1/1 available
Pod: sloth-cloud-web-* Running, 0 restarts
Route: http://cloud.lab.localhost:16080/
Web root: HTTP 200 HTML
API through Web proxy: http://cloud.lab.localhost:16080/api/v1/health -> ok=true
```

Traffic path:

```text
Mac browser or curl
-> cloud.lab.localhost:16080
-> k3d load balancer
-> Traefik Gateway
-> HTTPRoute sloth-cloud-web
-> Service sloth-cloud-web:80
-> Pod sloth-cloud-web:80
-> Web container proxy for /api
-> Service sloth-cloud-api-lab:80
-> Pod sloth-cloud-api-lab:4000
```

## Health Probe Tuning Drill

中文先说结论：2026-04-27 发现 `sloth-cloud-web` Pod 曾多次重启，但业务日志只显示 `sloth-web listening on :80`，没有应用崩溃栈。`kubectl top pod` 显示内存只有约 `16Mi`，远低于 `256Mi` 限制，所以这次更像是本地 Mac/k3d 环境里健康检查太敏感导致的误重启。

专业名词解释：

- Pod: Kubernetes 里运行容器的最小单位，可以理解成“一个被调度运行的服务实例”。
- Probe: 探针，Kubernetes 周期性访问容器，用来判断服务是否正常。
- Readiness Probe: 就绪探针。失败时，Kubernetes 不再把新流量转给这个 Pod，但不一定重启它。
- Liveness Probe: 存活探针。失败到阈值后，Kubernetes 会重启容器。
- Exit Code 137: 容器被 `SIGKILL` 结束。常见原因包括内存超限或被 kubelet 强制重启；这次结合内存和日志，更接近探针误判。
- GitOps: 以 Git 仓库里的配置作为“期望状态”，Argo CD 负责把集群同步到这个状态。
- Rolling Update: 滚动更新。Kubernetes 用新模板创建新 Pod，确认可用后再替换旧 Pod。

本次变更：

```yaml
readinessProbe:
  timeoutSeconds: 3
  failureThreshold: 6
livenessProbe:
  timeoutSeconds: 5
  failureThreshold: 6
```

含义：

- `timeoutSeconds`: 每次探测最多等几秒。本地实验集群偶发慢响应时，`1` 秒默认值容易误判。
- `failureThreshold`: 连续失败多少次才认为失败。调高后可以减少偶发抖动带来的误重启。

排查命令：

```bash
kubectl -n sloth-labs describe pod -l app.kubernetes.io/name=sloth-cloud-web
kubectl -n sloth-labs logs deploy/sloth-cloud-web --previous --tail=100
kubectl -n sloth-labs top pod -l app.kubernetes.io/name=sloth-cloud-web
```

GitOps 操作流程：

```bash
cd "/Users/shulai/Documents/New project/GitOps-learning"
kubectl kustomize k8s/apps/sloth-cloud-web/lab-dev-real-write
kubectl apply --dry-run=server -k k8s/apps/sloth-cloud-web/lab-dev-real-write
git add k8s/apps/sloth-cloud-web/base/deployment.yaml
git commit -m "Relax sloth cloud web health probes"
git push
kubectl -n argocd annotate application sloth-cloud-web-lab argocd.argoproj.io/refresh=hard --overwrite
kubectl -n argocd patch application sloth-cloud-web-lab --type merge -p '{"operation":{"sync":{"revision":"main","syncOptions":["CreateNamespace=true"]}}}'
kubectl -n sloth-labs rollout status deploy/sloth-cloud-web --timeout=180s
```

验收结果：

```text
Argo CD Application: Synced / Healthy
New ReplicaSet: sloth-cloud-web-75cf5c8f6
New Pod: sloth-cloud-web-75cf5c8f6-vqdnh Running, 0 restarts
Route: http://cloud.lab.localhost:16080/ -> HTTP 200
```

## Rollback

```bash
kubectl -n argocd delete application sloth-cloud-web-lab
kubectl -n sloth-labs delete deploy,svc,httproute -l app.kubernetes.io/name=sloth-cloud-web
```

The existing Compose web service remains separate and is not affected.
