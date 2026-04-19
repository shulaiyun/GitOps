# ADR 0001: Use a dedicated platform control repository

- Status: accepted
- Date: 2026-04-18

## Context

The live estate already spans multiple compose projects, multiple product lines, and mixed stateful/stateless services. Chat history is not reliable enough to act as the long-term memory for this system.

## Decision

Create and maintain a dedicated `platform-control` repository as the single source of truth for:

- current runtime inventory
- environment contracts
- tenant templates
- platform stack definitions
- migration runbooks
- phase handoff notes

## Consequences

- New services must be registered in `inventory/services.yaml` before deployment.
- Each phase must end with inventory, ADR, runbook, and phase-file updates.
- Future Kubernetes work starts from repo state, not from previous chats.
