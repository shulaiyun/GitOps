# Runbook: Sloth Cloud API Lab Argo CD Application

## 中文先说结论

这一步做的不是“部署 `sloth-cloud-api-lab`”，而是“先把它作为一个独立的 Argo CD 应用对象挂进去”。

也就是说：

- 你会在 Argo CD 界面里看到 `sloth-cloud-api-lab`
- 但它默认不会自动同步
- 也不会自动创建 Pod
- 现有 Compose 里的 `sloth-cloud-api` 继续跑

这一步的价值是：

- 你先学会 Argo CD 里“一个真实业务应用对象长什么样”
- 你能看懂 `repo -> path -> namespace -> sync policy` 这些字段
- 但不会因为误点或根同步把实验版业务拉起来

## 准备好的资产

- Application 模板：`k8s/bootstrap/manifests/sloth-cloud-api-lab-application.template.yaml`
- 渲染脚本：`scripts/render_sloth_cloud_api_lab_application.sh`

这里的 `template`（模板）意思是：
先保留 `${PLATFORM_GIT_REPO}` 和 `${PLATFORM_GIT_REVISION}` 这样的占位符，渲染时再替换成当前 Git 仓库地址和分支。

## 关键设计

- Argo 应用名：`sloth-cloud-api-lab`
- Git 路径：`k8s/apps/sloth-cloud-api/lab`
- 目标命名空间：`sloth-labs`
- 同步模式：`manual sync only`

`manual sync only` 的意思是：

- Argo 只负责“看到它”
- 不会因为 Git 有内容就自动部署
- 必须你明确点击 `Sync`（同步）或者手动执行同步命令，它才会真的创建 Kubernetes 资源

## 如何渲染并挂进当前集群

```bash
cd "/Users/shulai/Library/Mobile Documents/com~apple~CloudDocs/Documents/New project/platform-control"
bash scripts/render_sloth_cloud_api_lab_application.sh /tmp/sloth-cloud-api-lab-application.yaml
kubectl apply -f /tmp/sloth-cloud-api-lab-application.yaml
kubectl get application -n argocd
kubectl describe application sloth-cloud-api-lab -n argocd
```

## 你会看到什么

第一次创建后，Argo CD 里通常会出现下面这种状态：

- `OutOfSync`：表示 Git 里定义了资源，但还没有同步到集群
- `Missing` 或 `Unknown`：表示业务资源还没真的创建

这不是错误，而是我们故意要的“安全等待态”。

## 为什么它现在依然安全

因为这一步只创建了 `Application`（应用对象），没有开启自动同步。

所以：

- 不会自动创建 `Deployment`
- 不会自动创建 `Service`
- 不会自动创建 `HTTPRoute`
- 不会影响现有 `14000` 的 Compose API

## 什么时候才进入下一步

只有在这三件事都准备好之后，才建议做手动同步：

1. `sloth-cloud-api-lab` 的真实镜像已经准备好
2. `External Secrets`（外部密钥）已经对到真实密钥来源
3. 你确认要测试 `sloth-cloud-api.lab.localhost`

## 回退

如果你只是想先把它从 Argo CD 界面移走：

```bash
kubectl delete application sloth-cloud-api-lab -n argocd
```

这一步只会删掉 Argo 的应用对象，不会影响现有 Compose API。
