#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This helper is for macOS only." >&2
  exit 1
fi

LOCAL_HOST_NAME="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
LOCAL_HOST_NAME="$(printf '%s' "${LOCAL_HOST_NAME}" | tr '[:upper:]' '[:lower:]')"

BYPASS_DOMAINS=(
  "localhost"
  "127.0.0.0/8"
  "::1"
  "*.local"
  ".local"
  "local"
  "${LOCAL_HOST_NAME}.local"
  "192.168.0.0/16"
  "10.0.0.0/8"
  "172.16.0.0/12"
)

echo "Applying macOS proxy bypass domains:"
printf '  %s\n' "${BYPASS_DOMAINS[@]}"
echo

networksetup -listallnetworkservices \
  | sed '1d' \
  | while IFS= read -r service_name; do
      [[ -z "${service_name}" ]] && continue
      service_name="${service_name#\*}"

      echo "--- ${service_name}"
      if networksetup -setproxybypassdomains "${service_name}" "${BYPASS_DOMAINS[@]}" >/dev/null 2>&1; then
        networksetup -getproxybypassdomains "${service_name}" || true
      else
        echo "Skipped: cannot update this network service."
      fi
    done

echo
echo "Current effective proxy configuration:"
scutil --proxy | sed -n '1,160p'

echo
echo "Expected local Argo URL:"
echo "  http://${LOCAL_HOST_NAME}.local:16080/"
