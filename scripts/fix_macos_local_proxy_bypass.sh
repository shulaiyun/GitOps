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

contains_entry() {
  local needle="$1"
  shift

  local entry
  for entry in "$@"; do
    [[ "${entry}" == "${needle}" ]] && return 0
  done

  return 1
}

is_networksetup_message() {
  local line="$1"

  [[ -z "${line}" ]] && return 0
  [[ "${line}" == "There aren't any bypass domains set on "* ]] && return 0
  [[ "${line}" == "Bypass domains aren't set on "* ]] && return 0
  [[ "${line}" == *"is not a recognized network service."* ]] && return 0
  [[ "${line}" == "An asterisk (*) denotes that a network service is disabled." ]] && return 0

  return 1
}

echo "Required macOS proxy bypass domains:"
printf '  %s\n' "${BYPASS_DOMAINS[@]}"
echo

networksetup -listallnetworkservices \
  | sed '1d' \
  | while IFS= read -r service_name; do
      [[ -z "${service_name}" ]] && continue
      service_name="${service_name#\*}"

      echo "--- ${service_name}"
      MERGED_DOMAINS=("${BYPASS_DOMAINS[@]}")
      current_output="$(networksetup -getproxybypassdomains "${service_name}" 2>/dev/null || true)"

      while IFS= read -r current_domain; do
        current_domain="${current_domain%$'\r'}"
        is_networksetup_message "${current_domain}" && continue

        if ! contains_entry "${current_domain}" "${MERGED_DOMAINS[@]}"; then
          MERGED_DOMAINS+=("${current_domain}")
        fi
      done <<< "${current_output}"

      if networksetup -setproxybypassdomains "${service_name}" "${MERGED_DOMAINS[@]}" >/dev/null 2>&1; then
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
