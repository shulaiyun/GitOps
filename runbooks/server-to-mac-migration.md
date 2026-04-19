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

Interpretation:
- The Mac can carry the current Compose business stack.
- The Mac can also carry a local K3s lab, but only if we treat it as a local validation platform, not as a long-running customer production server.
- If Compose business services and a full observability-heavy K3s lab run together, the current Colima `8 GiB` memory limit is too tight.

### Server `192.168.16.115`

- The host is a `PVE` virtualization server, not the direct Docker business host.
- Host resources:
  - CPU threads reported: `32`
  - Memory: about `15 GiB`
  - Root disk: `94 GiB`, free about `75 GiB`
  - `local-lvm` thin storage free: about `338 GiB`

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
- Based on the verified inspection, this PVE host does not appear to contain the currently active Docker business estate that is represented in `platform-control`.
- That means a full "server to Mac" migration cannot yet be defined as a literal lift from this PVE host, because the real source of the current business stack has not been identified here.

## Decision

### Can the Mac host everything?

Yes, but only in a limited sense:

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

Before any real migration starts, identify the real source host of the business stack.

What is still missing:
- the actual machine or VM that currently runs:
  - `slothcloud`
  - `sloth-convoy`
  - `sloth-xboard`
  - `cliproxyapi-main`
- direct in-guest measurement of:
  - database size
  - bind mount size
  - upload/assets size
  - Redis persistence size
  - cron jobs
  - reverse proxy config

Without that source host, the safest thing we can define now is the Mac-side target preparation and the application-level migration flow.

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

1. treat the Mac as the new quiet single-host Compose platform first
2. do not move the full Kubernetes production idea onto the Mac at the same time
3. keep the local `k3d` lab only for GitOps and first stateless migration drills
4. identify the true source host of the business data before attempting any server migration

This keeps the migration shape realistic:
- business runtime can move to the Mac
- Kubernetes can still be rehearsed locally
- customer production does not get tied to a laptop
