# Runbook: Server to Mac Migration Assessment

## Purpose

Assess whether the current service estate can move onto the local Mac, and define a practical migration flow.

Key terms:
PVE (Proxmox VE): the virtualization host that runs virtual machines.
VM (Virtual Machine): a full guest operating system running on the PVE host.
Compose: Docker Compose, the file-based multi-container runtime already used by the current business stack.
GitOps: use Git as the single source of truth for deployment changes.
k3d: a tool that runs K3s clusters inside Docker.
K3s: a lightweight Kubernetes distribution.

## Topology correction as of 2026-04-19

The service estate is split across three different runtime surfaces:

- Local Mac:
  - `slothcloud`
  - `sloth-convoy`
  - local `sloth-xboard`
  - local `cliproxyapi-main`
  - `platform-core`
  - host-level `openclaw-gateway`
- Physical server `192.168.16.115`:
  - the `PVE` hypervisor that backs the VPS business substrate
  - not the same thing as the local Docker application runtime
- Remote host `38.80.189.137:19575`:
  - production `xboard`
  - remote `cliproxyapi-main`
  - host-level `nginx`, `mysqld`, `php-fpm`, `V2bX`, and `sloth-gateway`

Because of that, a full "move everything to the Mac" effort is not a single lift-and-shift job. It is really two different decisions:

1. whether the application runtimes should move to the Mac
2. whether the `PVE` virtualization substrate should move to the Mac

The first is feasible for self-use and internal validation.
The second is not a good long-term move.

## Verified findings as of 2026-04-19

### Local Mac

- Hardware:
  - CPU: `10` cores
  - Memory: `16 GiB`
  - Root disk free space: about `226 GiB`
- Current Colima runtime:
  - CPU: `4`
  - Memory: `8 GiB`
  - Disk: `100 GiB`
- Current Docker footprint on the Mac:
  - Active containers memory use at the sampling point: about `2793 MiB`
  - Docker images: about `35.65 GiB`
  - Build cache: about `32.57 GiB`
- Current local application data footprint:
  - `sloth-cloud` MariaDB: about `172M`
  - `sloth-cloud` Redis: about `49M`
  - `Paymenter` storage: about `26M`
  - `sloth-convoy` MySQL volume: about `293.9M`
  - `sloth-convoy` Redis volume: about `64M`
  - local `CLIProxy` auths and logs: under `200K`
  - local `OpenClaw` state directory: about `69M`
- Additional host-level services:
  - `openclaw-gateway` on `127.0.0.1:18789` and `127.0.0.1:18791`
  - `ollama` on `127.0.0.1:11434`

Interpretation:
- The Mac can carry the current Compose business stack.
- The Mac can also carry a local K3s lab, but only if we treat it as a local validation platform, not as a long-running customer production server.
- If Compose business services and a full observability-heavy K3s lab run together, the current Colima `8 GiB` memory limit is too tight.
- The currently measured local application data footprint is still comfortably below `1 GiB`, so disk space is not the immediate blocker.

### Server `192.168.16.115`

- The host is a `PVE` virtualization server.
- For the Sloth Cloud business, this machine matters because it is the VPS substrate, even though it is not the same thing as the local application Docker host.
- Host resources:
  - CPU threads reported: `32`
  - Memory: about `15 GiB`
  - Root disk: `94 GiB`, free about `75 GiB`
  - `local-lvm` thin storage free: about `338 GiB`
- Host services observed:
  - `pveproxy` on `8006`
  - `spiceproxy` on `3128`
  - `ssh` on `22`
  - `pvedaemon` on `127.0.0.1:85`

### VM inspection results

- Running VM `100455008`:
  - Name: `shu`
  - Config: `2` cores, `2 GiB` memory, `40 GiB` disk
  - IP: `192.168.16.235`
  - In-guest result:
    - Ubuntu `22.04`
    - Root filesystem used: about `2.3 GiB`
    - No Docker installed
    - Port `80` serves the default `nginx` welcome page
  - Thin disk actual use from the PVE layer: about `4.36 GiB`

- Stopped VM `416634378`:
  - Name: `shu`
  - Config: `4` cores, `6 GiB` memory, `80 GiB` disk
  - IP plan: `192.168.16.220`, `192.168.16.221`, `192.168.16.222`
  - Thin disk actual use from the PVE layer: about `8.40 GiB`
  - Read-only filesystem inspection from the PVE host:
    - Linux root partition exists and mounts correctly
    - `/var/lib/docker` is only `212 KiB`
    - No `docker-compose.yml`, `compose.yaml`, or current business project traces were found in the first-pass search

Interpretation:
- The PVE host is part of the business platform, but in the role of virtualization substrate, not local application Docker runtime.
- Migrating this host to the Mac would mean replacing the VPS substrate itself, which is not equivalent to migrating a few Compose applications.

### Remote `xboard` production host `38.80.189.137:19575`

- Host resources:
  - Memory: about `1.9 GiB`
  - Root disk: `40 GiB`, used about `28 GiB`, free about `11 GiB`
- Docker projects:
  - `v2board`
  - `cliproxyapi-main`
- Docker containers:
  - `v2board-xboard-1`
  - `v2board-redis-1`
  - `cli-proxy-api`
- Host-level services:
  - `nginx` on `80`, `443`, `887`, `888`
  - `mysqld` on `3306`
  - `php` on `7001`
  - `V2bX` on `8443`
  - `sloth-gateway` on `8787`
  - `ssh` on `19575`
- Data paths:
  - `/root/v2board` about `212M`
  - `/opt/shulai-VPN/CLIProxyAPI-main` about `8.7M`
  - `/www/server/data` about `295M`
  - `/usr/local/V2bX` about `118M`
  - `/opt/shulai-VPN/sloth-gateway` about `41M`

Interpretation:
- Remote production `xboard` is a hybrid host.
- It depends on both Docker and host-level services.
- Migrating it to the Mac is possible for self-use or internal validation, but it is not a trivial "copy two containers" move.

## Decision

### Can the Mac host everything?

Yes, but only in a limited sense.

What can move:
- the local application Compose estate that already runs on the Mac
- the remote `xboard` application layer and remote `cliproxy` layer

What should not be collapsed into the Mac as the final steady state:
- the `PVE` virtualization substrate used for VPS delivery

- Suitable:
  - self-use
  - local validation
  - development
  - internal staging
  - rehearsing GitOps and first migrations

- Not suitable as the final shape:
  - customer-facing long-running production
  - public edge routing that must survive sleep and reboots
  - all business services plus a heavy Kubernetes observability stack on a `16 GiB` laptop with no operational compromise

### Recommended Mac profiles

#### Profile A: Mac as Compose business host

Use this when the goal is to consolidate the current business services locally and keep Kubernetes separate.

Recommended Colima target:
- CPU: `6`
- Memory: `10 GiB`
- Disk: `160 GiB`

Notes:
- This is the most realistic path if you want the Mac to carry business services.
- Databases can live here for self-use, but only with disciplined backups and explicit downtime acceptance.
- This profile can also absorb the remote `xboard` production host workload if you accept that the result is local-only and not customer-grade production.

#### Profile B: Mac as Compose business host plus local K3d lab

Use this when you want business Compose plus a Kubernetes rehearsal environment on the same Mac.

Recommended Colima target:
- CPU: `6`
- Memory: `12 GiB`
- Disk: `180 GiB`

Notes:
- Keep `Prometheus` retention short.
- Keep `Loki` retention short.
- Do not treat this as customer production.

#### Profile C: Mac as final all-in-one production host

Not recommended.

Reason:
- sleep
- reboot
- laptop thermal and battery behavior
- no stable always-on operations boundary
- poor blast-radius control when both your workstation and your production runtime are the same machine

## Migration prerequisite

Before any real migration starts, confirm the exact source data paths on each source host.

What is still missing:
- exact application data sizes for the local `slothcloud` and `sloth-convoy` stacks
- exact MySQL data size and host-level config size on the remote `xboard` production host
- explicit decision on whether the `PVE` substrate is staying remote, or only the application layer is moving

Without those size measurements, the safest thing we can define now is the Mac-side target preparation and the application-layer migration flow.

## Migration flow

### Phase 1: Freeze and inventory

1. Confirm the source host.
2. Freeze deploys and config changes during the migration window.
3. Record the final source-of-truth list:
   - Compose files
   - `.env` files
   - image tags
   - port bindings
   - volume paths
   - DNS and reverse proxy rules
4. Record rollback criteria before touching data.

Rollback criteria:
- source host stays untouched until Mac validation passes
- DNS is not switched until health checks pass
- original database files or dumps are retained until cutover completes

### Phase 2: Prepare the Mac target

1. Resize Colima for the target profile:

```bash
colima stop
colima start --cpu 6 --memory 10 --disk 160
```

For the K3d lab profile:

```bash
colima stop
colima start --cpu 6 --memory 12 --disk 180
```

2. Verify Docker, Compose, `kubectl`, `helm`, and `k3d`.
3. Reserve ports so they do not collide with the existing local stack.
4. Clean reclaimable Docker cache if needed:

```bash
docker system df
docker builder prune -af
```

### Phase 3: Export from the source host

Use application-level export, not whole-VM lift-and-shift, unless there is a hard reason to preserve the entire OS image.

Important split:
- local `slothcloud` and `sloth-convoy` already live on the Mac, so there is no server-to-Mac copy step for them
- remote `xboard` production does have a real host-to-Mac copy step
- the `PVE` VPS substrate should stay out of this migration unless you are intentionally replacing the whole virtualization layer

Export checklist:
- Compose files and `.env`
- database dump:
  - `mysqldump` or `mariadb-dump`
- Redis persistence:
  - `dump.rdb` or `appendonly.aof`
- bind mounts and upload directories:
  - `tar`
- custom `nginx` or `Traefik` config
- scheduled tasks:
  - `crontab -l`

Typical commands:

```bash
docker compose ls
docker compose config > source-stack.rendered.yaml
mysqldump --single-transaction --routines --triggers -u root -p DB_NAME > db.sql
tar -czf app-data.tar.gz /path/to/bind-mount
```

### Phase 4: Restore onto the Mac

Restore order:

1. databases
2. Redis
3. API and worker services
4. frontend services
5. reverse proxy and edge routing
6. monitoring

Suggested restore actions:

```bash
docker compose up -d db redis
docker compose exec -T db mysql -u root -p DB_NAME < db.sql
tar -xzf app-data.tar.gz -C /
docker compose up -d
```

### Phase 5: Validate before cutover

Validate:
- containers are healthy
- databases accept reads and writes
- uploads and mounted assets are visible
- public and internal URLs respond
- background workers consume jobs
- payment or callback webhooks are disabled or safely pointed during rehearsal

Suggested checks:

```bash
docker ps
docker compose ls
curl -I http://127.0.0.1:13000
curl http://127.0.0.1:14000/api/v1/health
```

### Phase 6: Cutover

1. Enter maintenance mode on the source side if needed.
2. Take the final database delta dump.
3. Import the final delta onto the Mac.
4. Update DNS, proxy, or local routing.
5. Watch logs and metrics for the first hour.

### Phase 7: Rollback

Rollback triggers:
- repeated API health failures
- missing uploads or broken storage paths
- database import mismatch
- background jobs failing
- external callbacks failing

Rollback actions:
1. point DNS and proxy back to the source host
2. stop the Mac stack
3. keep the imported Mac data for forensic comparison
4. resume the source host as primary

## Practical recommendation

Right now, the best next move is:

1. treat the Mac as the quiet single-host application platform first
2. do not move the full Kubernetes production idea onto the Mac at the same time
3. keep the local `k3d` lab only for GitOps and first stateless migration drills
4. move remote `xboard` only after its host MySQL, nginx, php, `V2bX`, and `cliproxy` dependencies are exported explicitly
5. keep the `PVE` VPS substrate on dedicated Linux infrastructure instead of collapsing it onto the laptop

This keeps the migration shape realistic:
- business runtime can move to the Mac
- Kubernetes can still be rehearsed locally
- customer production and VPS substrate do not get tied to a laptop
