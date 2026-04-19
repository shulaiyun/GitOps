# Phase 00: Inventory and Standardization

## Goal

Turn the current runtime into explicit assets that can be handed off, reviewed, and migrated without relying on memory.

## Implemented in this repo

- `inventory/services.yaml` covers every currently running container.
- `inventory/compose-projects.yaml` maps all discovered compose projects.
- `inventory/uptime-targets.yaml` defines the desired monitor set.
- Naming, owner, migration class, and customer visibility are captured for every known service.

## Done definition

- Every `docker ps` container appears in `inventory/services.yaml`.
- Every discovered compose project appears in `inventory/compose-projects.yaml`.
- Every service has `owner`, `data_class`, and `migration_class`.
- New services must be registered before deployment.

## Verification

```bash
cd "/Users/shulai/Documents/New project/platform-control"
ruby scripts/check_inventory_coverage.rb
```

## Next entry point

Start Phase 01 by deploying the platform core stack from `stacks/platform-core/compose.yaml`.

## Open questions

- Which services need formal backup restore drills first?
- Which source-mounted services should be repackaged into immutable images before Kubernetes migration?
