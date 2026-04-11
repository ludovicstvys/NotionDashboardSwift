#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 ENV_OUTPUT_PATH" >&2
  exit 1
fi

required_vars=(
  APPLE_TEAM_ID
  APPLE_DEVELOPER_ID_CERT_P12_BASE64
  APPLE_DEVELOPER_ID_CERT_PASSWORD
)

for name in "${required_vars[@]}"; do
  if [[ -z "${(P)name:-}" ]]; then
    echo "Missing required environment variable: ${name}" >&2
    exit 1
  fi
done

env_output_path="$1"
runner_temp="${RUNNER_TEMP:-/tmp}"
keychain_path="${runner_temp}/notion-dashboard-signing.keychain-db"
keychain_password="$(openssl rand -base64 24)"
certificate_path="${runner_temp}/developer-id-application.p12"
identity_filter="${APPLE_CODESIGN_IDENTITY:-Developer ID Application}"

log() {
  printf '[apple-signing] %s\n' "$1" >&2
}

decode_base64_to_file() {
  local output_path="$1"
  if ! printf '%s' "$2" | { base64 --decode 2>/dev/null || base64 -D; } > "${output_path}"; then
    echo "Unable to decode base64 payload into ${output_path}" >&2
    exit 1
  fi
}

cleanup_existing_keychain() {
  if security list-keychains -d user | grep -Fq "${keychain_path}"; then
    security delete-keychain "${keychain_path}" >/dev/null 2>&1 || true
  fi
  rm -f "${certificate_path}"
}

cleanup_existing_keychain

log "creating temporary keychain"
security create-keychain -p "${keychain_password}" "${keychain_path}"
security set-keychain-settings -lut 21600 "${keychain_path}"
security unlock-keychain -p "${keychain_password}" "${keychain_path}"

log "importing Developer ID certificate"
decode_base64_to_file "${certificate_path}" "${APPLE_DEVELOPER_ID_CERT_P12_BASE64}"
security import "${certificate_path}" \
  -k "${keychain_path}" \
  -P "${APPLE_DEVELOPER_ID_CERT_PASSWORD}" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -T /usr/bin/xcodebuild \
  -T /usr/bin/productbuild >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${keychain_password}" "${keychain_path}" >/dev/null
existing_keychains=("${(@f)$(security list-keychains -d user | tr -d '"')}")
security list-keychains -d user -s "${keychain_path}" "${existing_keychains[@]}"

resolved_identity="$(
  security find-identity -v -p codesigning "${keychain_path}" |
    sed -n 's/.*"\(.*\)"/\1/p' |
    grep -F "${identity_filter}" |
    head -n 1
)"

if [[ -z "${resolved_identity}" ]]; then
  echo "Unable to find a codesigning identity matching '${identity_filter}' in ${keychain_path}" >&2
  security find-identity -v -p codesigning "${keychain_path}" >&2 || true
  exit 1
fi

log "resolved signing identity: ${resolved_identity}"
mkdir -p "$(dirname "${env_output_path}")"
cat > "${env_output_path}" <<EOF
SIGNING_KEYCHAIN_PATH=${keychain_path}
SIGNING_KEYCHAIN_PASSWORD=${keychain_password}
APPLE_CODESIGN_IDENTITY_RESOLVED=${resolved_identity}
APPLE_TEAM_ID=${APPLE_TEAM_ID}
EOF
