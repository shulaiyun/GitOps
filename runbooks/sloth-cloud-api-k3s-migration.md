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

当前隔离设计：

- Kubernetes 资源名：`sloth-cloud-api-lab`
- Kubernetes 命名空间：`sloth-labs`
- 实验入口域名：`sloth-cloud-api.lab.localhost`
- 默认不放进 `k8s/apps/kustomization.yaml`

这意味着：

- 它不会因为根应用同步被默认拉起
- 它不会和现有 Compose API 的名字混在一起
- 它不会占用现有 `14000` 入口

## Required decisions before rollout

1. Publish a Kubernetes-usable image for `sloth-cloud-api-lab`.
2. Choose the upstream URLs that replace the compose-only service names in `configmap.yaml`.
3. Bind `sloth-cloud-api-lab-secrets` to a real `ClusterSecretStore`.
4. Explicitly decide when to add the lab overlay into the root sync path.

## Suggested rollout order

1. Update the overlay with a real image reference and reachable upstream URLs.
2. Create the backing secret store for External Secrets.
3. Add `sloth-cloud-api/lab` into `k8s/apps/kustomization.yaml` only when you are ready to test it.
4. Render and apply the root Argo CD application.
5. Wait for `sloth-cloud-api-lab` to become Ready.
6. Test the route:

```bash
curl -H 'Host: sloth-cloud-api.lab.localhost' http://<traefik-gateway-address>/api/v1/health
```

中文理解：

先让它在实验入口里活起来，再谈后面的切换。
只要还在 `sloth-cloud-api.lab.localhost` 这个入口，它就不是现网切换。

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
```
