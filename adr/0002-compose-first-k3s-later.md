# ADR 0002: Stabilize the compose estate before moving selected workloads to K3s

- Status: accepted
- Date: 2026-04-18

## Context

The current runtime is compose-based, with local bind mounts, cross-project networks, and core databases running directly on the host. K3s, Helm, and kubectl are not installed on the active machine yet.

## Decision

- Keep the live business estate on Compose for now.
- Add a shared operations stack on Compose first: Traefik, Dockge, Homepage, Uptime Kuma, Beszel.
- Prepare a separate K3s lab bootstrap path.
- Migrate only first-batch stateless workloads to K3s until storage, backup, and image packaging are proven.

## Consequences

- No surprise control-plane migration on the production-like host.
- K3s work can proceed in parallel with immediate operational cleanup.
- Stateful databases and cache services stay on Compose until restore drills pass.
