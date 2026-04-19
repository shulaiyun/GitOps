# Runbook: Refresh the runtime inventory

## Purpose

Keep `inventory/services.yaml` accurate enough to survive handoffs, context loss, and later migration work.

## Steps

1. Capture the current runtime:

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}'
docker compose ls
```

2. Validate inventory coverage:

```bash
cd "/Users/shulai/Documents/New project/platform-control"
ruby scripts/check_inventory_coverage.rb
```

3. For every new or changed service, update:

- `inventory/services.yaml`
- `inventory/compose-projects.yaml` when a new compose project appears
- `inventory/uptime-targets.yaml` when the service needs uptime monitoring

4. Update the matching phase file with:

- current result
- blockers
- next phase entry point

## Acceptance

- No running container is missing from `inventory/services.yaml`.
- Every new service has owner, migration class, and customer visibility recorded.
