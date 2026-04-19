# Managed Compose Stacks

New compose workloads should land under this directory so Dockge can manage them without scanning unrelated source trees.

Recommended shape:

```text
managed/
  my-service/
    compose.yaml
    .env
```
