#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 DMG_PATH" >&2
  exit 1
fi

required_vars=(
  APPLE_NOTARY_KEY_ID
  APPLE_NOTARY_API_KEY_P8_BASE64
)

for name in "${required_vars[@]}"; do
  if [[ -z "${(P)name:-}" ]]; then
    echo "Missing required environment variable: ${name}" >&2
    exit 1
  fi
done

dmg_path="$1"
if [[ ! -f "${dmg_path}" ]]; then
  echo "DMG not found: ${dmg_path}" >&2
  exit 1
fi

runner_temp="${RUNNER_TEMP:-/tmp}"
api_key_path="${runner_temp}/AuthKey_${APPLE_NOTARY_KEY_ID}.p8"

cleanup() {
  rm -f "${api_key_path}"
}
trap cleanup EXIT

log() {
  printf '[notarize-dmg] %s\n' "$1" >&2
}

if ! printf '%s' "${APPLE_NOTARY_API_KEY_P8_BASE64}" | { base64 --decode 2>/dev/null || base64 -D; } > "${api_key_path}"; then
  echo "Unable to decode APPLE_NOTARY_API_KEY_P8_BASE64 into ${api_key_path}" >&2
  exit 1
fi
chmod 600 "${api_key_path}"

submit_command=(
  xcrun notarytool submit
  "${dmg_path}"
  --key "${api_key_path}"
  --key-id "${APPLE_NOTARY_KEY_ID}"
  --wait
)

if [[ -n "${APPLE_NOTARY_ISSUER_ID:-}" ]]; then
  submit_command+=(--issuer "${APPLE_NOTARY_ISSUER_ID}")
fi

log "submitting DMG for notarization"
"${submit_command[@]}"

log "stapling notarization ticket"
xcrun stapler staple "${dmg_path}"

log "validating stapled ticket"
xcrun stapler validate "${dmg_path}"
