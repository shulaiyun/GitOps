#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="$repo_root/stacks/public-gateway/.env.local"

if [ ! -f "$env_file" ]; then
  "$repo_root/scripts/setup_public_gateway_auth.sh" >/dev/null
fi

printf "Paste Cloudflare API Token, then press Enter. Input is hidden:\n"
IFS= read -rs token
printf "\n"

if [ -z "$token" ]; then
  echo "Token is empty; nothing changed." >&2
  exit 1
fi

python3 - "$env_file" "$token" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
token = sys.argv[2]
lines = path.read_text().splitlines() if path.exists() else []

updated = False
new_lines = []
for line in lines:
    if line.startswith("CLOUDFLARE_API_TOKEN="):
        new_lines.append(f"CLOUDFLARE_API_TOKEN={token}")
        updated = True
    else:
        new_lines.append(line)

if not updated:
    if new_lines and new_lines[-1] != "":
        new_lines.append("")
    new_lines.append(f"CLOUDFLARE_API_TOKEN={token}")

path.write_text("\n".join(new_lines) + "\n")
PY

chmod 600 "$env_file"
echo "Saved Cloudflare API Token to ignored local file:"
echo "$env_file"
