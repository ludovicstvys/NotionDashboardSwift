#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 OUTPUT_PATH" >&2
  exit 1
fi

required_vars=(
  UPDATE_CHANNEL
  UPDATE_VERSION
  UPDATE_BUILD
  UPDATE_MINIMUM_SYSTEM_VERSION
  UPDATE_PUBLISHED_AT
  UPDATE_DOWNLOAD_URL
  UPDATE_RELEASE_NOTES_URL
)

for name in "${required_vars[@]}"; do
  if [[ -z "${(P)name:-}" ]]; then
    echo "Missing required environment variable: ${name}" >&2
    exit 1
  fi
done

output_path="$1"
mkdir -p "$(dirname "$output_path")"

cat > "$output_path" <<JSON
{
  "channel": "${UPDATE_CHANNEL}",
  "version": "${UPDATE_VERSION}",
  "build": ${UPDATE_BUILD},
  "minimumSystemVersion": "${UPDATE_MINIMUM_SYSTEM_VERSION}",
  "publishedAt": "${UPDATE_PUBLISHED_AT}",
  "downloadURL": "${UPDATE_DOWNLOAD_URL}",
  "releaseNotesURL": "${UPDATE_RELEASE_NOTES_URL}"
}
JSON
