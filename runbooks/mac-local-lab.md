# Runbook: macOS Local Lab

## Purpose / 目的

Run the platform lab on this Mac without using the noisy Linux server.
This path is for local validation, GitOps rehearsal, and early migration drills.
It is not the recommended long-running customer production substrate.

中文解释：

这份手册对应的是“Mac 本地 Kubernetes 实验场”。
它适合学习、演练、验证，不适合直接当长期生产底座。

Key terms / 关键术语：
Colima: a lightweight Linux virtual machine on macOS that provides the Docker runtime.
k3d: a tool that runs K3s clusters inside Docker.
K3s: a lightweight Kubernetes distribution.
GitOps: use Git as the single source of truth for deployment changes.
Argo CD: the controller that watches Git and syncs the cluster.

中文解释：

- Colima：Mac 上提供 Linux 容器运行环境的小虚拟机
- k3d：在 Docker 里创建 K3s 集群的工具
- K3s：轻量版 Kubernetes 发行版
- GitOps：用 Git 管理集群期望状态
- Argo CD：自动读取 Git 并把集群同步过去的控制器

## What this local Kubernetes cluster is for

Use it to learn and validate:

- `kubectl`: inspect and operate Kubernetes resources directly
- `Deployment`: run stateless applications in a controlled way
- `Service`: give pods stable in-cluster network access
- `Gateway API`: define traffic entry and routing rules
- `Helm`: install packaged platform components such as Traefik and cert-manager
- `Argo CD`: learn GitOps by letting the cluster reconcile from Git
- `External Secrets`: separate secret delivery from app manifests

Use it less for:

- final customer production
- stateful databases that have not passed restore drills
- anything that must survive Mac sleep, laptop restarts, or travel

## When to use this path

- You want a quiet local platform lab on the Mac.
- You want to validate Argo CD, Helm, Gateway API, metrics, logs, and one app migration before touching a remote node.
- You do not want to move customer traffic onto this machine.

## Constraints

- macOS can sleep, reboot for updates, or change network state, so do not treat this as a stable always-on platform.
- Public domains and customer ingress should stay on a real Linux host or managed cluster later.
- Stateful databases should remain in Compose for now; the Mac lab is mainly for stateless app migration drills.

## Prerequisites

1. Make sure Colima is running:

```bash
colima status
```

2. Install the local control tools:

```bash
brew install kubectl helm k3d
```

3. Run the macOS preflight:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
bash scripts/preflight_mac_lab.sh
```

## Create the local cluster

Use dedicated ports so the Mac lab does not collide with the existing Compose platform stack:

- `16080`: local Kubernetes HTTP entry
- `16443`: local Kubernetes HTTPS entry

Create the cluster:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
bash k8s/bootstrap/scripts/create-k3d-cluster.sh
```

This creates:

- one K3s server node
- zero worker nodes by default, to keep the first learning cluster lighter and simpler
- bundled Traefik disabled, because this repo installs Traefik itself by Helm

If you want an extra worker node later:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
K3D_AGENTS=1 bash k8s/bootstrap/scripts/create-k3d-cluster.sh
```

## Bootstrap the platform layer

Point the bootstrap to the real Git remote:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
export PLATFORM_GIT_REPO="$(git remote get-url origin)"
export PLATFORM_GIT_REVISION=main
export GRAFANA_ADMIN_PASSWORD="change-me-now"
bash k8s/bootstrap/scripts/bootstrap-platform-mac-learning.sh
```

This learning-mode bootstrap installs the core platform first:

- Argo CD
- cert-manager
- External Secrets
- Traefik
- Gateway API

It also prepares the shared namespaces that later app routes use:

- `argocd`: GitOps control namespace
- `traefik`: edge gateway namespace
- `sloth-apps`: business and learning app namespace

It skips the heavier first-day items by default:

- Prometheus stack
- Loki
- root application auto-sync

When you want the full platform later:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
export PLATFORM_GIT_REPO="$(git remote get-url origin)"
export PLATFORM_GIT_REVISION=main
export GRAFANA_ADMIN_PASSWORD="change-me-now"
export BOOTSTRAP_OBSERVABILITY=1
export BOOTSTRAP_ROOT_APP=1
bash k8s/bootstrap/scripts/bootstrap-platform.sh
```

## Verification

```bash
kubectl config current-context
kubectl get nodes
kubectl get pods -A
kubectl get applications -n argocd
kubectl get gateways.gateway.networking.k8s.io -A
```

Expected result:

- current context is `k3d-sloth-lab`
- Argo CD, cert-manager, External Secrets, and Traefik are running
- the cluster is ready for later GitOps root-app enablement

## First commands to learn with

```bash
kubectl get ns
kubectl get pods -A
kubectl get svc -A
kubectl get gateway -A
kubectl describe pod -n argocd <pod-name>
kubectl logs -n argocd <pod-name>
```

That gives you the first useful Kubernetes loop:

1. see what exists
2. find what is unhealthy
3. describe the object
4. read the logs

## First useful demo

Deploy a tiny HTTP demo service:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
kubectl apply -k k8s/apps/learning-whoami/base
kubectl get pods -n sloth-apps
kubectl get httproute -n sloth-apps
```

Then open or test:

```bash
curl http://whoami.lab.localhost:16080
```

What this teaches:

- `Deployment`: how the pod is created and restarted
- `Service`: how traffic finds the pod without using a pod IP directly
- `HTTPRoute`: how the hostname is attached to the shared Traefik gateway
- `Namespace`: why the app can live in `sloth-apps` while the gateway lives in `traefik`

Scale it and watch the rollout:

```bash
kubectl scale deployment learning-whoami -n sloth-apps --replicas=2
kubectl rollout status deployment/learning-whoami -n sloth-apps
kubectl get pods -n sloth-apps -w
```

Delete the demo when you are done:

```bash
kubectl delete -k k8s/apps/learning-whoami/base
```

## Argo CD local access / Argo CD 本地访问

Get the first admin password:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
bash k8s/bootstrap/scripts/show-argocd-admin-password.sh
```

Expose the web UI locally:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
bash scripts/start_argocd_ui_port_forward.sh
```

Then open:

- `https://127.0.0.1:19080`
- username: `admin`
- password: output from `show-argocd-admin-password.sh`

Because this is a local lab endpoint, your browser will warn about the self-signed certificate.
That is expected for the first local login.

Keep that terminal open while you use the Argo CD page.

To stop it later:

```bash
Ctrl+C
```

What Argo CD is for in this lab:

- connect the cluster to Git
- compare desired state in Git with actual state in Kubernetes
- sync changes without manually re-running `kubectl apply`
- practice the later customer-ready GitOps workflow on a safe local cluster

如果你更想先看界面，再回来看命令：

```bash
cd "/Users/shulai/Documents/New project/platform-control"
cat runbooks/argocd-ui-learning-whoami-tour.md
```

## First migration drill

Once the lab platform is healthy, continue with:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
cat runbooks/sloth-cloud-api-k3s-migration.md
```

For the safest first GitOps exercise before a real business migration:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
cat runbooks/learning-whoami-gitops-drill.md
```

## Rollback and cleanup

Delete the local cluster:

```bash
k3d cluster delete sloth-lab
```

This removes the local Kubernetes lab without touching the Compose-based business services.
