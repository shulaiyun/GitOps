# ADR 0004: Dev Real-Write Lab Boundary

## Status

Accepted.

## Context

`sloth-cloud-api-lab` is intended to teach Kubernetes and validate the real Sloth Cloud business surface. A purely fake or read-only integration is not enough for learning because it hides the real behavior of payment, provisioning, VPS control, DNS, webhooks, deployment, and database-backed workflows.

The current environment is treated as a development environment owned by the operator. Destructive changes to development business data are acceptable if they are caused by deliberate lab actions.

## Decision

Use a `dev_real_write` profile for `sloth-cloud-api-lab`.

Allowed in this profile:

- payment and refund actions against development-owned payment data
- service provisioning and deletion against development-owned services
- VPS reinstall, shutdown, reboot, and related power actions against development-owned VPS resources
- DNS changes for development-owned zones or accepted test records
- real webhook sends to development-owned receivers
- real deployment runs into lab-scoped targets
- development database writes caused by business APIs

Still protected:

- source code
- Git history
- Compose definitions
- Kubernetes control manifests
- production route cutover
- non-development remote services unless explicitly accepted

## Consequences

The safety model is no longer "read-only business." It is "real write for development business state, no mutation of the project itself."

Before any `SYNC`, the dependency checker must still block placeholder images, `replace-me` URLs, and placeholder secret stores. The checker may allow live-like integrations once they point at accepted development targets and required secrets exist.

## Rollback

If the lab writes unwanted development business data, revert the data through the owning application or restore from development backups. Do not revert project files or Git history unless the project files themselves were changed.
