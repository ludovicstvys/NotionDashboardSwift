#!/bin/zsh

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 OUTPUT_PATH ARCHIVES_DIR" >&2
  exit 1
fi

required_vars=(
  SPARKLE_PRIVATE_ED_KEY
  UPDATE_DOWNLOAD_URL_PREFIX
  UPDATE_RELEASE_NOTES_URL_PREFIX
)

for name in "${required_vars[@]}"; do
  if [[ -z "${(P)name:-}" ]]; then
    echo "Missing required environment variable: ${name}" >&2
    exit 1
  fi
done

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_path="$1"
archives_dir="$2"
sparkle_version="${SPARKLE_VERSION:-2.9.1}"
tools_dir="${root_dir}/.tools"
sparkle_repo_dir="${tools_dir}/Sparkle-${sparkle_version}"
sparkle_bin_dir="${tools_dir}/bin"
sparkle_bin_path="${sparkle_bin_dir}/generate_appcast-${sparkle_version}"
sparkle_derived_data="${SPARKLE_DERIVED_DATA:-/tmp/SparkleToolsDerivedData}"
host_arch="$(uname -m)"

log() {
  printf '[sparkle-appcast] %s\n' "$1" >&2
}

ensure_sparkle_source() {
  if [[ -d "${sparkle_repo_dir}/.git" ]]; then
    return
  fi

  mkdir -p "${tools_dir}"
  log "cloning Sparkle ${sparkle_version}"
  git clone --depth 1 --branch "${sparkle_version}" https://github.com/sparkle-project/Sparkle "${sparkle_repo_dir}" >/dev/null
}

ensure_generate_appcast() {
  if [[ -x "${sparkle_bin_path}" ]]; then
    printf '%s\n' "${sparkle_bin_path}"
    return
  fi

  ensure_sparkle_source
  mkdir -p "${sparkle_bin_dir}"

  log "building generate_appcast"
  xcodebuild \
    -project "${sparkle_repo_dir}/Sparkle.xcodeproj" \
    -scheme generate_appcast \
    -configuration Release \
    -destination "platform=macOS,arch=${host_arch}" \
    -derivedDataPath "${sparkle_derived_data}" \
    build >/dev/null

  local built_binary="${sparkle_derived_data}/Build/Products/Release/generate_appcast"
  if [[ ! -x "${built_binary}" ]]; then
    echo "Unable to locate generate_appcast binary: ${built_binary}" >&2
    exit 1
  fi

  cp "${built_binary}" "${sparkle_bin_path}"
  chmod +x "${sparkle_bin_path}"
  printf '%s\n' "${sparkle_bin_path}"
}

if [[ ! -d "${archives_dir}" ]]; then
  echo "Archives directory does not exist: ${archives_dir}" >&2
  exit 1
fi

mkdir -p "$(dirname "${output_path}")"
generate_appcast_bin="$(ensure_generate_appcast)"

command=(
  "${generate_appcast_bin}"
  --ed-key-file -
  --download-url-prefix "${UPDATE_DOWNLOAD_URL_PREFIX}"
  --release-notes-url-prefix "${UPDATE_RELEASE_NOTES_URL_PREFIX}"
  --maximum-deltas 0
  -o "${output_path}"
)

if [[ -n "${UPDATE_CHANNEL:-}" ]] && [[ "${UPDATE_CHANNEL}" != "stable" ]] && [[ "${UPDATE_CHANNEL}" != "default" ]]; then
  command+=(--channel "${UPDATE_CHANNEL}")
fi

if [[ -n "${UPDATE_RELEASE_URL:-}" ]]; then
  command+=(--link "${UPDATE_RELEASE_URL}")
fi

command+=("${archives_dir}")

log "generating signed Sparkle appcast"
printf '%s' "${SPARKLE_PRIVATE_ED_KEY}" | "${command[@]}"
