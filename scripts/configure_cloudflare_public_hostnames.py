#!/usr/bin/env python3
import argparse
import base64
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PUBLIC_HOSTNAMES = REPO_ROOT / "inventory" / "public-hostnames.yaml"
PUBLIC_GATEWAY_ENV = REPO_ROOT / "stacks" / "public-gateway" / ".env.local"


def load_env_file(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.exists():
        return data
    for line in path.read_text().splitlines():
        if not line or line.strip().startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = value.strip()
    return data


def load_public_hostnames() -> dict:
    raw = subprocess.check_output(
        [
            "ruby",
            "-ryaml",
            "-rjson",
            "-e",
            "puts JSON.generate(YAML.load_file(ARGV[0]))",
            str(PUBLIC_HOSTNAMES),
        ],
        text=True,
    )
    return json.loads(raw)


def cf_request(method: str, path: str, token: str, body: dict | None = None, query: dict | None = None) -> dict:
    url = "https://api.cloudflare.com/client/v4" + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    payload = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=payload, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        error_text = exc.read().decode()
        raise SystemExit(f"Cloudflare API {method} {path} failed: HTTP {exc.code}\n{error_text}") from exc
    if not data.get("success", False):
        raise SystemExit(f"Cloudflare API {method} {path} failed:\n{json.dumps(data, ensure_ascii=False, indent=2)}")
    return data


def decode_cloudflared_token_from_container(container_name: str) -> tuple[str | None, str | None]:
    try:
        raw = subprocess.check_output(
            ["docker", "inspect", "-f", "{{json .Args}}", container_name],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return None, None

    try:
        args = json.loads(raw)
    except json.JSONDecodeError:
        return None, None

    token = None
    for index, value in enumerate(args):
        if value == "--token" and index + 1 < len(args):
            token = args[index + 1]
            break
        if isinstance(value, str) and value.startswith("ey"):
            token = value

    if not token:
        return None, None

    candidates = [token]
    if "." in token:
        candidates.extend(part for part in token.split(".") if part)

    for candidate in candidates:
        padded = candidate + ("=" * (-len(candidate) % 4))
        try:
            decoded = base64.urlsafe_b64decode(padded.encode())
            obj = json.loads(decoded.decode())
        except Exception:
            continue
        account_id = obj.get("a") or obj.get("account_id") or obj.get("accountTag")
        tunnel_id = obj.get("t") or obj.get("tunnel_id") or obj.get("tunnelID")
        if account_id and tunnel_id:
            return account_id, tunnel_id
    return None, None


def get_zone_id(token: str, zone_name: str) -> str:
    result = cf_request("GET", "/zones", token, query={"name": zone_name})
    zones = result.get("result", [])
    if not zones:
        raise SystemExit(f"Cloudflare zone not found: {zone_name}")
    return zones[0]["id"]


def upsert_dns_record(token: str, zone_id: str, hostname: str, tunnel_id: str, dry_run: bool) -> None:
    target = f"{tunnel_id}.cfargotunnel.com"
    if dry_run:
        print(f"DRY-RUN DNS CNAME {hostname} -> {target} proxied=true")
        return

    existing = cf_request(
        "GET",
        f"/zones/{zone_id}/dns_records",
        token,
        query={"type": "CNAME", "name": hostname},
    ).get("result", [])

    body = {
        "type": "CNAME",
        "name": hostname,
        "content": target,
        "ttl": 1,
        "proxied": True,
        "comment": "Managed by GitOps-learning public gateway",
    }
    if existing:
        record_id = existing[0]["id"]
        cf_request("PATCH", f"/zones/{zone_id}/dns_records/{record_id}", token, body=body)
        print(f"Updated DNS CNAME: {hostname}")
    else:
        cf_request("POST", f"/zones/{zone_id}/dns_records", token, body=body)
        print(f"Created DNS CNAME: {hostname}")


def put_tunnel_configuration(
    token: str,
    account_id: str,
    tunnel_id: str,
    hostnames: list[str],
    origin_service: str,
    dry_run: bool,
) -> None:
    managed = set(hostnames)
    fallback = {"service": "http_status:404"}
    existing_ingress: list[dict] = []

    if token:
        try:
            current = cf_request("GET", f"/accounts/{account_id}/cfd_tunnel/{tunnel_id}/configurations", token)
            existing_ingress = current.get("result", {}).get("config", {}).get("ingress", []) or []
        except SystemExit as exc:
            print(f"Warning: could not read current tunnel configuration, will write managed rules only.\n{exc}", file=sys.stderr)

    preserved = []
    preserved_fallback = None
    for rule in existing_ingress:
        hostname = rule.get("hostname")
        service = rule.get("service", "")
        if hostname in managed:
            continue
        if not hostname and service.startswith("http_status:"):
            preserved_fallback = rule
            continue
        preserved.append(rule)

    managed_rules = [{"hostname": hostname, "service": origin_service} for hostname in hostnames]
    merged = preserved + managed_rules + [preserved_fallback or fallback]
    body = {"config": {"ingress": merged}}

    if dry_run:
        print("DRY-RUN tunnel ingress configuration:")
        print(json.dumps(body, ensure_ascii=False, indent=2))
        return

    cf_request("PUT", f"/accounts/{account_id}/cfd_tunnel/{tunnel_id}/configurations", token, body=body)
    print(f"Updated tunnel configuration: {len(managed_rules)} managed public hostnames")


def main() -> int:
    parser = argparse.ArgumentParser(description="Configure Cloudflare Tunnel public hostnames for the Sloth public gateway.")
    parser.add_argument("--dry-run", action="store_true", help="Print intended changes without calling write APIs.")
    parser.add_argument("--container", default=os.environ.get("CLOUDFLARED_CONTAINER", "sloth-cloud-local-tunnel"))
    parser.add_argument("--zone-name", default=os.environ.get("CLOUDFLARE_ZONE_NAME") or os.environ.get("OPERATOR_CLOUDFLARE_ZONE_NAME"))
    parser.add_argument("--account-id", default=os.environ.get("CLOUDFLARE_ACCOUNT_ID") or os.environ.get("OPERATOR_CLOUDFLARE_ACCOUNT_ID"))
    parser.add_argument("--tunnel-id", default=os.environ.get("CLOUDFLARE_TUNNEL_ID") or os.environ.get("OPERATOR_CLOUDFLARE_DEFAULT_TUNNEL_ID"))
    parser.add_argument("--skip-dns", action="store_true", help="Only update tunnel ingress; do not create or update DNS records.")
    args = parser.parse_args()

    token = os.environ.get("CLOUDFLARE_API_TOKEN") or os.environ.get("OPERATOR_CLOUDFLARE_API_TOKEN")
    if not token and not args.dry_run:
        raise SystemExit(
            "Missing CLOUDFLARE_API_TOKEN or OPERATOR_CLOUDFLARE_API_TOKEN.\n"
            "需要一个 Cloudflare API Token，至少包含 Zone:DNS Edit 和 Account:Cloudflare Tunnel Edit 权限。"
        )

    gateway_env = load_env_file(PUBLIC_GATEWAY_ENV)
    inventory = load_public_hostnames()
    base_domain = args.zone_name or gateway_env.get("PUBLIC_BASE_DOMAIN") or inventory.get("base_domain")
    origin_service = inventory.get("origin_service") or f"http://host.docker.internal:{gateway_env.get('PUBLIC_GATEWAY_PORT', '18088')}"
    hostnames = [entry["hostname"] for entry in inventory["hostnames"]]

    account_id = args.account_id
    tunnel_id = args.tunnel_id
    if not account_id or not tunnel_id:
        decoded_account, decoded_tunnel = decode_cloudflared_token_from_container(args.container)
        account_id = account_id or decoded_account
        tunnel_id = tunnel_id or decoded_tunnel

    if not account_id:
        raise SystemExit("Missing CLOUDFLARE_ACCOUNT_ID and could not derive it from the running cloudflared container.")
    if not tunnel_id:
        raise SystemExit("Missing CLOUDFLARE_TUNNEL_ID and could not derive it from the running cloudflared container.")

    print(f"Base domain: {base_domain}")
    print(f"Origin service: {origin_service}")
    print(f"Managed hostnames: {len(hostnames)}")

    put_tunnel_configuration(token or "", account_id, tunnel_id, hostnames, origin_service, args.dry_run)

    if not args.skip_dns:
        zone_id = "(dry-run)" if args.dry_run and not token else get_zone_id(token or "", base_domain)
        for hostname in hostnames:
            upsert_dns_record(token or "", zone_id, hostname, tunnel_id, args.dry_run)

    print("Cloudflare public hostname configuration complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
