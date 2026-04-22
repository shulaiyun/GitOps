# Runbook: Learning Whoami GitOps Drill

## Purpose / 目的

Use `learning-whoami` as the safest first GitOps drill on the Mac lab.

中文解释：

把 `learning-whoami` 当作第一套最安全的 GitOps 演练对象。
它没有数据库、没有客户流量、没有复杂依赖，所以最适合用来理解 GitOps 到底是怎么工作的。

如果你更想先从界面理解，再回来看命令，请先看：

```bash
cd "/Users/shulai/Documents/New project/platform-control"
cat runbooks/argocd-ui-learning-whoami-tour.md
```

This drill teaches the full chain:

- `Git`: the desired state source
- `Argo CD Application`: the Git watcher and reconciler
- `Deployment`: the app replica controller
- `ReplicaSet`: the rollout snapshot created by the Deployment
- `Pod`: the running container instance

Key terms / 关键术语：

- GitOps: use Git as the single source of truth for cluster changes.
- Argo CD: the controller that watches Git and syncs Kubernetes to match it.
- sync: Argo CD has applied the desired state from Git.
- self-heal: Argo CD notices live drift and puts the cluster back to the Git state.
- drift: someone changed the live cluster directly, so it no longer matches Git.

中文解释：

- GitOps：把 Git 作为部署配置的唯一事实源
- Argo CD：盯着 Git 并把集群状态拉到 Git 所定义状态的控制器
- sync：同步完成，说明 Git 和集群已经一致
- self-heal：自愈，说明集群被手动改歪后，Argo CD 会按 Git 改回来
- drift：漂移，说明集群当前状态和 Git 里的定义不一致

## Why this drill is safe

- `learning-whoami` is stateless.
- It has no database and no customer traffic.
- It is already connected to `Argo CD` and healthy.

## Baseline check / 基线检查

```bash
cd "/Users/shulai/Documents/New project/platform-control"
kubectl get application learning-whoami -n argocd
kubectl get deployment learning-whoami -n sloth-apps
kubectl get pods -n sloth-apps -l app.kubernetes.io/name=learning-whoami
curl http://whoami.lab.localhost:16080 | sed -n '1,6p'
```

Expected result / 你应该看到的结果：

- `Application` shows `Synced` and `Healthy`
- `Deployment` shows `1/1`
- one `Pod` is running

## Drill Part 1: change Git and let Argo CD sync it / 第 1 部分：改 Git，让 Argo CD 自动同步

Edit the desired replica count in Git:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
sed -n '1,40p' k8s/apps/learning-whoami/base/deployment.yaml
```

Change:

- `replicas: 1`

to:

- `replicas: 2`

Then commit and push:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
git add k8s/apps/learning-whoami/base/deployment.yaml
git commit -m "Scale learning-whoami to 2 replicas"
git push origin main
```

Watch Argo CD and the Deployment converge:

```bash
kubectl get application learning-whoami -n argocd -w
```

In another terminal:

```bash
kubectl rollout status deployment/learning-whoami -n sloth-apps
kubectl get pods -n sloth-apps -l app.kubernetes.io/name=learning-whoami -w
```

Expected result:

- Argo CD briefly reconciles the new Git revision
- `Deployment` moves from `1` replica to `2`
- a second `Pod` appears

Note:

- Argo CD may take a short polling interval before it notices the new Git revision.
- If you do not want to wait for the next poll, trigger a refresh check:

```bash
kubectl annotate application learning-whoami -n argocd argocd.argoproj.io/refresh=normal --overwrite
```

That does not apply the manifests by itself.
It only tells Argo CD to re-check Git now.

## Drill Part 2: create drift and let Argo CD self-heal it / 第 2 部分：故意制造漂移，再看 Argo CD 自动修复

Directly change the live cluster to the wrong value:

```bash
kubectl scale deployment learning-whoami -n sloth-apps --replicas=1
kubectl get deployment learning-whoami -n sloth-apps
```

That command changes Kubernetes live state only.
It does not change Git.

Now watch recovery:

```bash
kubectl get application learning-whoami -n argocd -w
```

In another terminal:

```bash
kubectl get deployment learning-whoami -n sloth-apps -w
kubectl get pods -n sloth-apps -l app.kubernetes.io/name=learning-whoami -w
```

Expected result:

- Argo CD notices drift
- the app returns to `Synced`
- `Deployment` goes back to `2` replicas because Git still says `2`

This is the core GitOps lesson:

- `kubectl scale` can change the live cluster
- but Git remains the truth
- so Argo CD pulls the cluster back to the Git state

## Useful inspection commands / 实用查看命令

See the Argo CD source and policy:

```bash
kubectl describe application learning-whoami -n argocd | sed -n '1,220p'
```

Look for:

- `Repo URL`
- `Path`
- `Target Revision`
- `Sync Policy`
- `Prune`
- `Self Heal`

See how the Deployment is tracked by Argo CD:

```bash
kubectl describe deployment learning-whoami -n sloth-apps | sed -n '1,120p'
```

Look for:

- `argocd.argoproj.io/tracking-id`

That annotation shows Argo CD is tracking this Deployment as part of the Application.

## Optional rollback / 可选回滚

If you want the lab back to one replica, change Git again:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
python3 - <<'PY'
from pathlib import Path
path = Path("k8s/apps/learning-whoami/base/deployment.yaml")
path.write_text(path.read_text().replace("replicas: 2", "replicas: 1"))
PY
git add k8s/apps/learning-whoami/base/deployment.yaml
git commit -m "Scale learning-whoami back to 1 replica"
git push origin main
```

## Done definition / 完成标准

- You changed desired state in Git
- Argo CD synced that change into the cluster
- You created live drift
- Argo CD self-healed the cluster back to the Git state

## Live verification snapshot / 本次实跑验证记录

Verified on the Mac lab:

- Git commit `d97cca9` changed `replicas` from `1` to `2`
- Argo CD moved through `OutOfSync -> Synced/Progressing -> Synced/Healthy`
- a manual `kubectl scale ... --replicas=1` created drift
- Argo CD self-healed the Deployment back to `2 desired / 2 ready`
