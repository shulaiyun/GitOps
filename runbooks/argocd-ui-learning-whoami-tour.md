# Runbook: Argo CD 界面查看指南

## 这份手册是干什么的

这是一份专门给你看 `Argo CD`（GitOps 控制器）界面的中文说明。

目标不是让你背概念，而是让你打开界面以后，马上知道：

- 先点哪里
- 每个字段是什么意思
- 哪些地方最值得看
- 怎么判断这次 `learning-whoami` 的 GitOps 演练是不是成功了

## 先准备本地访问

### 1. 取管理员密码

```bash
cd "/Users/shulai/Documents/New project/platform-control"
bash k8s/bootstrap/scripts/show-argocd-admin-password.sh
```

这条命令会打印 `Argo CD` 的初始管理员密码。

### 2. 打开本地端口转发

```bash
cd "/Users/shulai/Documents/New project/platform-control"
bash scripts/start_argocd_ui_port_forward.sh
```

中文解释：

- 这条脚本会在本机启动一个临时访问入口
- 默认用 `19080` 端口，避免和现有业务端口冲突
- 脚本底层本质上仍然是在执行 `kubectl port-forward`
- 这个命令要一直开着，所以请保留这个终端窗口不要关闭

为什么不用以前的 `18080`：

- 因为你的本机 `18080` 已经被现有业务占用了
- 再用 `https://127.0.0.1:18080` 打开时，就可能看到 `ERR_SSL_PROTOCOL_ERROR`
- 不是 Argo 坏了，而是浏览器连到了另一个不是 Argo 的服务

### 3. 浏览器打开

- 地址：`https://127.0.0.1:19080`
- 用户名：`admin`
- 密码：上一步脚本打印出来的值

注意：

- 第一次会提示证书不受信任，这在本地实验环境是正常的
- 继续访问即可
- 这个入口是临时的，Mac 睡眠、终端退出、Kubernetes 连接断开后，可能需要重新运行一次脚本
- 不用的时候，在运行脚本的终端里按 `Ctrl+C` 即可关闭

## 登录后先看哪里

登录后，先看左侧或首页里的 `Applications`（应用列表）。

你现在应该能看到：

- `learning-whoami`

这个对象不是容器本身。
它是 `Argo CD Application`，也就是：

- 一条 GitOps 管理记录
- 告诉 Argo CD 去哪个 Git 仓库
- 看哪个目录
- 把资源部署到哪个命名空间

你可以把它理解成：

- “这套应用应该长什么样”
- “应该从哪里拿配置”
- “应该部署到哪里”

## 点进 `learning-whoami` 以后重点看什么

点进 `learning-whoami` 之后，优先看这几块。

### 1. `Sync Status`

常见值：

- `Synced`：集群实际状态已经和 Git 中的期望状态一致
- `OutOfSync`：集群状态和 Git 不一致

这次演练里你已经见过：

- 改 Git 后，先出现 `OutOfSync`
- 然后回到 `Synced`

中文理解：

- `Synced` 不是“程序一定没问题”
- 它表示“Argo CD 看到的资源定义，和 Git 对上了”

### 2. `Health Status`

常见值：

- `Healthy`：应用健康
- `Progressing`：还在变更中，还没完全稳定
- `Degraded`：有异常，没达到期望状态

这次你应该看到：

- 正常稳定时是 `Healthy`
- 扩容或回滚过程中可能短暂变成 `Progressing`

中文理解：

- `Health` 更偏“运行状态”
- `Sync` 更偏“Git 和集群是不是一致”

### 3. `Repository / Repo URL`

这里表示这条 `Application` 盯着哪个 Git 仓库。

你这里应该是：

- `https://github.com/shulaiyun/GitOps.git`

中文理解：

- 这是 Argo CD 的“说明书来源”
- 它不是看你本地文件夹
- 它看的是远端 Git 仓库里的内容

### 4. `Path`

这里表示它在 Git 仓库里盯的是哪个目录。

你这里应该是：

- `k8s/apps/learning-whoami/base`

中文理解：

- 同一个 Git 仓库里可以放很多应用
- `Path` 表示这条 Application 只看其中一个子目录

### 5. `Target Revision`

这里表示它跟踪哪个分支或版本。

你这里应该是：

- `main`

中文理解：

- 如果你往 `main` 推送新提交
- Argo CD 就会拿新的 Git 内容来对比和同步

### 6. `Destination`

这里表示部署目标。

重点看两个字段：

- `Server`
- `Namespace`

你这里一般会看到：

- `Server: https://kubernetes.default.svc`
- `Namespace: sloth-apps`

中文理解：

- `Server`：目标集群，就是当前这套 Kubernetes 集群
- `Namespace`：部署到 `sloth-apps` 这个命名空间

### 7. `Sync Policy`

这里非常关键。

你这次演练最重要的是这两个能力：

- `Automated`
- `Self Heal`

中文解释：

- `Automated`：Git 一变，Argo CD 自动同步，不用你手动点部署
- `Self Heal`：如果你手动把集群改歪了，它会按 Git 再改回来

这正是刚才演练里：

- 你改 Git，副本数从 `1` 变 `2`
- 你手动 `kubectl scale` 改回 `1`
- 最后 Argo CD 又把它拉回 `2`

### 8. `History`

这里能看到历史同步记录。

重点看：

- `Revision`：对应哪次 Git 提交
- `Deployed At`：什么时候同步的
- `Initiated By`：谁触发的

中文理解：

- 这里像“部署历史记录”
- 你可以拿它对照 Git commit
- 看哪次提交已经真正进集群了

## 中间资源图怎么看

点进应用后，页面里通常会看到资源关系图。

你这次 `learning-whoami` 最值得看的是这三个资源：

- `Deployment`
- `Service`
- `HTTPRoute`

中文理解：

- `Deployment`：负责管副本数，决定要几个 Pod
- `Service`：给 Pod 一个稳定的集群内访问入口
- `HTTPRoute`：把域名流量交给这个 Service

你可以把它脑补成这条链路：

`Git -> Argo CD -> Deployment -> Pod`

以及对外访问链路：

`浏览器 -> Traefik -> HTTPRoute -> Service -> Pod`

## 这次演练里你应该在界面里确认什么

最关键的不是把每个按钮都点一遍，而是确认下面 5 件事：

1. `Application` 名字是 `learning-whoami`
2. `Sync Status` 是 `Synced`
3. `Health Status` 是 `Healthy`
4. `Path` 是 `k8s/apps/learning-whoami/base`
5. `History` 里能看到新提交已经同步

如果这 5 个都对，说明这次 GitOps 演练已经成立。

## 用一句话理解这整个界面

`Argo CD` 界面本质上是在回答三个问题：

1. Git 里希望它变成什么样
2. 集群里现在实际上是什么样
3. 两者现在是一致、正在收敛，还是已经偏了

## 你接下来最适合怎么学

第一次不要追求把整个界面全看懂。
只盯这 4 个地方就够了：

1. `Sync Status`
2. `Health Status`
3. `Path`
4. `History`

把这 4 个先看懂，后面迁真实业务服务时就不会慌。
