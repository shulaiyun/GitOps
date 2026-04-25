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

## Rollback

```bash
kubectl -n argocd delete application sloth-cloud-web-lab
kubectl -n sloth-labs delete deploy,svc,httproute -l app.kubernetes.io/name=sloth-cloud-web
```

The existing Compose web service remains separate and is not affected.
