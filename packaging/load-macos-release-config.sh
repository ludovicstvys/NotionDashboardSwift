#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 ENV_OUTPUT_PATH" >&2
  exit 1
fi

if [[ -z "${MACOS_RELEASE_CONFIG_BASE64:-}" ]] && [[ -z "${MACOS_RELEASE_CONFIG_PATH:-}" ]]; then
  echo "Set either MACOS_RELEASE_CONFIG_BASE64 or MACOS_RELEASE_CONFIG_PATH." >&2
  exit 1
fi

env_output_path="$1"
runner_temp="${RUNNER_TEMP:-/tmp}"
config_path="${MACOS_RELEASE_CONFIG_PATH:-${runner_temp}/macos-release-config.json}"
using_temp_config=0

decode_base64_to_file() {
  local output_path="$1"
  local encoded_payload="$2"
  if ! printf '%s' "${encoded_payload}" | { base64 --decode 2>/dev/null || base64 -D; } > "${output_path}"; then
    echo "Unable to decode MACOS_RELEASE_CONFIG_BASE64 into ${output_path}" >&2
    exit 1
  fi
}

extract_required() {
  local key="$1"
  local value
  value="$(
    ruby -rjson -e '
      data = JSON.parse(File.read(ARGV[0]))
      value = data[ARGV[1]]
      exit 1 if value.nil? || value.to_s.empty?
      print value
    ' "${config_path}" "${key}" 2>/dev/null || true
  )"
  if [[ -z "${value}" ]]; then
    echo "Missing required release config key: ${key}" >&2
    exit 1
  fi
  printf '%s' "${value}"
}

extract_optional() {
  local key="$1"
  ruby -rjson -e '
    data = JSON.parse(File.read(ARGV[0]))
    value = data[ARGV[1]]
    print value if value
  ' "${config_path}" "${key}" 2>/dev/null || true
}

cleanup() {
  if [[ "${using_temp_config}" == "1" ]]; then
    rm -f "${config_path}"
  fi
}
trap cleanup EXIT

if [[ -n "${MACOS_RELEASE_CONFIG_BASE64:-}" ]]; then
  using_temp_config=1
  decode_base64_to_file "${config_path}" "${MACOS_RELEASE_CONFIG_BASE64}"
fi

ruby -rjson -e 'JSON.parse(File.read(ARGV[0]))' "${config_path}" >/dev/null

apple_team_id="$(extract_required appleTeamId)"
developer_id_cert_p12_base64="$(extract_required developerIdCertificateP12Base64)"
developer_id_cert_password="$(extract_required developerIdCertificatePassword)"
apple_notary_key_id="$(extract_required appleNotaryKeyId)"
apple_notary_api_key_p8_base64="$(extract_required appleNotaryApiKeyP8Base64)"
sparkle_public_ed_key="$(extract_required sparklePublicEdKey)"
sparkle_private_ed_key="$(extract_required sparklePrivateEdKey)"

apple_codesign_identity="$(extract_optional appleCodesignIdentity)"
apple_notary_issuer_id="$(extract_optional appleNotaryIssuerId)"

mkdir -p "$(dirname "${env_output_path}")"
cat > "${env_output_path}" <<EOF
APPLE_TEAM_ID=${apple_team_id}
APPLE_DEVELOPER_ID_CERT_P12_BASE64=${developer_id_cert_p12_base64}
APPLE_DEVELOPER_ID_CERT_PASSWORD=${developer_id_cert_password}
APPLE_NOTARY_KEY_ID=${apple_notary_key_id}
APPLE_NOTARY_API_KEY_P8_BASE64=${apple_notary_api_key_p8_base64}
SPARKLE_PUBLIC_ED_KEY=${sparkle_public_ed_key}
SPARKLE_PRIVATE_ED_KEY=${sparkle_private_ed_key}
EOF

if [[ -n "${apple_codesign_identity}" ]]; then
  printf 'APPLE_CODESIGN_IDENTITY=%s\n' "${apple_codesign_identity}" >> "${env_output_path}"
fi

if [[ -n "${apple_notary_issuer_id}" ]]; then
  printf 'APPLE_NOTARY_ISSUER_ID=%s\n' "${apple_notary_issuer_id}" >> "${env_output_path}"
fi
