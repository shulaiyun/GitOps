# Runbook: Learning Whoami GitOps Drill

## Purpose

Use `learning-whoami` as the safest first GitOps drill on the Mac lab.

This drill teaches the full chain:

- `Git`: the desired state source
- `Argo CD Application`: the Git watcher and reconciler
- `Deployment`: the app replica controller
- `ReplicaSet`: the rollout snapshot created by the Deployment
- `Pod`: the running container instance

Key terms:

- GitOps: use Git as the single source of truth for cluster changes.
- Argo CD: the controller that watches Git and syncs Kubernetes to match it.
- sync: Argo CD has applied the desired state from Git.
- self-heal: Argo CD notices live drift and puts the cluster back to the Git state.
- drift: someone changed the live cluster directly, so it no longer matches Git.

## Why this drill is safe

- `learning-whoami` is stateless.
- It has no database and no customer traffic.
- It is already connected to `Argo CD` and healthy.

## Baseline check

```bash
cd "/Users/shulai/Documents/New project/platform-control"
kubectl get application learning-whoami -n argocd
kubectl get deployment learning-whoami -n sloth-apps
kubectl get pods -n sloth-apps -l app.kubernetes.io/name=learning-whoami
curl http://whoami.lab.localhost:16080 | sed -n '1,6p'
```

Expected result:

- `Application` shows `Synced` and `Healthy`
- `Deployment` shows `1/1`
- one `Pod` is running

## Drill Part 1: change Git and let Argo CD sync it

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

## Drill Part 2: create drift and let Argo CD self-heal it

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

## Useful inspection commands

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

## Optional rollback

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

## Done definition

- You changed desired state in Git
- Argo CD synced that change into the cluster
- You created live drift
- Argo CD self-healed the cluster back to the Git state

## Live verification snapshot

Verified on the Mac lab:

- Git commit `d97cca9` changed `replicas` from `1` to `2`
- Argo CD moved through `OutOfSync -> Synced/Progressing -> Synced/Healthy`
- a manual `kubectl scale ... --replicas=1` created drift
- Argo CD self-healed the Deployment back to `2 desired / 2 ready`
