# Runbook: Sloth Cloud API Lab-First K3s Migration

## 中文先说结论

这份方案现在是“实验版隔离迁移”，不是“现网切换迁移”。

也就是说：

- 现有 Compose 里的 `sloth-cloud-api` 继续跑
- Kubernetes 里如果要跑，只会先跑一个 `lab` 版本
- `lab` 版本使用新的名字、新的命名空间、新的入口
- 在你明确确认前，不会接管现有 `14000` 的 API 入口

## Goal

Move `sloth-cloud-api` first as a lab variant because it is stateless, already exposes `/api/v1/health`, and gives the quickest proof that GitOps plus Gateway API works before touching stateful services.

中文解释：

先迁它，不是因为现在就要替换现网，而是因为它最适合做第一个实验对象。
它是无状态服务，健康检查路径明确，比数据库类服务更适合先做 K8s 验证。

## Prepared assets

- Base manifests: `k8s/apps/sloth-cloud-api/base`
- Lab overlay: `k8s/apps/sloth-cloud-api/lab`
- Dev real-write overlay: `k8s/apps/sloth-cloud-api/lab-dev-real-write`
- Dedicated Argo CD application template: `k8s/bootstrap/manifests/sloth-cloud-api-lab-application.template.yaml`
- Dedicated Argo CD application render script: `scripts/render_sloth_cloud_api_lab_application.sh`
- Dependency classification: `inventory/sloth-cloud-api-lab-dependencies.yaml`
- Dependency runbook: `runbooks/sloth-cloud-api-lab-dependency-matrix.md`
- Dev real-write policy: `runbooks/sloth-cloud-api-lab-dev-real-write-policy.md`
- Image import helper: `scripts/import_sloth_cloud_api_lab_image.sh`
- Secret seed helper: `scripts/seed_sloth_cloud_api_lab_secret_from_api_env.sh`

当前隔离设计：

- Kubernetes 资源名：`sloth-cloud-api-lab`
- Kubernetes 命名空间：`sloth-labs`
- 实验入口域名：`sloth-cloud-api.lab.localhost`
- 默认不放进 `k8s/apps/kustomization.yaml`

这意味着：

- 它不会因为根应用同步被默认拉起
- 它不会和现有 Compose API 的名字混在一起
- 它不会占用现有 `14000` 入口
- 它还可以先以“单独的 Argo CD 应用对象”形式被挂进界面，但保持手动同步

## Required decisions before rollout

1. Publish a Kubernetes-usable image for `sloth-cloud-api-lab`.
2. Import the local Compose API image into k3d as `sloth-cloud-api-lab:dev`.
3. Seed `sloth-cloud-api-lab-secrets` from the local development API env.
4. Run the dependency matrix check and resolve all strict blockers.
5. Explicitly decide when to manually sync the dedicated Argo CD app.

## Suggested rollout order

1. Render and apply the dedicated Argo CD application object first, but keep it on manual sync.
2. Use the `lab-dev-real-write` overlay for the first real business connection.
3. Import the local image and seed the manual Kubernetes Secret.
4. Run strict dependency checks.
5. Keep using the dedicated app path until the lab is stable.
6. Manually sync `sloth-cloud-api-lab` only after the image and secrets are real.
7. Wait for `sloth-cloud-api-lab` to become Ready.
8. Test the route:

```bash
curl -H 'Host: sloth-cloud-api.lab.localhost' http://<traefik-gateway-address>/api/v1/health
```

中文理解：

先让它在实验入口里活起来，再谈后面的切换。
只要还在 `sloth-cloud-api.lab.localhost` 这个入口，它就不是现网切换。

## Dev real-write boundary

This lab may write development business data.

中文解释：

你已经确认开发环境里的业务数据、账单、客户状态、服务器状态、DNS、webhook、部署记录和数据库写入都可以被实验影响。

但项目本体仍然要保护：

- 不改项目源码
- 不改 Git 历史
- 不改现有 Compose 文件
- 不改 `platform-control` 控制清单
- 不接管现有 `14000` 或正式域名入口

## Rollback

If the lab API is unhealthy or its upstream dependencies are not reachable:

1. Remove `sloth-cloud-api/lab` from `k8s/apps/kustomization.yaml`.
2. Re-sync the root application.
3. Keep the Compose-hosted API as the active control plane endpoint.

中文理解：

最坏情况也只是把实验版撤掉。
现有 Compose API 继续跑，不受影响。

## Verification

```bash
cd "/Users/shulai/Library/Mobile Documents/com~apple~CloudDocs/Documents/New project/platform-control"
ruby scripts/validate_k8s_manifests.rb
bash scripts/render_sloth_cloud_api_lab_application.sh
ruby scripts/check_sloth_cloud_api_lab_dependencies.rb --profile=dev_real_write
bash scripts/import_sloth_cloud_api_lab_image.sh
bash scripts/seed_sloth_cloud_api_lab_secret_from_api_env.sh
ruby scripts/check_sloth_cloud_api_lab_dependencies.rb --profile=dev_real_write --strict --check-cluster-secret
```

## First manual sync result

Completed on 2026-04-25 in the Mac `k3d` lab.

专业名词解释：

- `SYNC`：让 Kubernetes 集群里的实际资源变成 Git 里写的期望资源。
- `Deployment`：声明应用副本数、镜像、环境变量、健康检查和资源限制。
- `ReplicaSet`：Deployment 创建出来的副本控制器，负责维持指定数量的 Pod。
- `Pod`：真正运行容器的最小 Kubernetes 单元。
- `Service`：给一组 Pod 一个稳定的集群内访问入口。
- `HTTPRoute`：Gateway API 的 HTTP 路由规则，把域名请求转给 Service。
- `Endpoint`：Service 当前实际指向的 Pod IP 和端口。

Verified state:

```text
Application: Synced / Healthy
Operation: Succeeded
Revision: f36d3847e57d49136da5033a514431153741667b
Deployment: sloth-cloud-api-lab 1/1 available
Pod: sloth-cloud-api-lab-* Running, 0 restarts
Service endpoint: Pod port 4000 behind Service port 80
Route: http://sloth-cloud-api.lab.localhost:16080/api/v1/health
Health: ok=true, sourceMode=live
```

Traffic path:

```text
Mac browser or curl
-> localhost:16080
-> k3d load balancer
-> Traefik Gateway
-> HTTPRoute sloth-cloud-api-lab
-> Service sloth-cloud-api-lab:80
-> Pod sloth-cloud-api-lab:4000
```

The existing Compose API on `localhost:14000` remains active and was not cut over.
