#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER_TEMP_DIR="${RUNNER_TEMP:-/tmp}"
RELEASE_CONFIG_ENV_PATH="${RELEASE_CONFIG_ENV_PATH:-${RUNNER_TEMP_DIR}/macos-release.env}"
SIGNING_ENV_PATH="${SIGNING_ENV_PATH:-${RUNNER_TEMP_DIR}/apple-signing.env}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/NotionDashboardDerivedData}"
RELEASE_ASSETS_DIR="${RELEASE_ASSETS_DIR:-${ROOT_DIR}/build/release-assets}"
UPDATE_SITE_DIR="${UPDATE_SITE_DIR:-${ROOT_DIR}/build/update-site}"
METADATA_ENV_PATH="${METADATA_ENV_PATH:-${ROOT_DIR}/build/release-metadata.env}"
APP_PRODUCT_NAME="${APP_PRODUCT_NAME:-Dashboard}"
APP_NAME="${APP_PRODUCT_NAME}.app"
DMG_PATH="${ROOT_DIR}/NotionDashboard.dmg"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/${APP_NAME}"

log() {
  printf '[release-macos-update] %s\n' "$1" >&2
}

source_env_file() {
  local env_path="$1"
  set -a
  source "${env_path}"
  set +a
}

resolve_repository_context() {
  if [[ -n "${REPOSITORY:-}" ]]; then
    REPO_OWNER="${REPO_OWNER:-${REPOSITORY%%/*}}"
    REPO_NAME="${REPO_NAME:-${REPOSITORY##*/}}"
    return
  fi

  local remote_url
  remote_url="$(git -C "${ROOT_DIR}" remote get-url origin 2>/dev/null || true)"
  if [[ -z "${remote_url}" ]]; then
    echo "Unable to infer GitHub repository. Set REPOSITORY, REPO_OWNER, and REPO_NAME." >&2
    exit 1
  fi

  if [[ "${remote_url}" == git@github.com:* ]]; then
    REPOSITORY="${remote_url#git@github.com:}"
  elif [[ "${remote_url}" == https://github.com/* ]]; then
    REPOSITORY="${remote_url#https://github.com/}"
  else
    echo "Unsupported remote origin URL: ${remote_url}" >&2
    exit 1
  fi

  REPOSITORY="${REPOSITORY%.git}"
  REPO_OWNER="${REPOSITORY%%/*}"
  REPO_NAME="${REPOSITORY##*/}"
}

cleanup() {
  if [[ -n "${SIGNING_KEYCHAIN_PATH:-}" ]]; then
    security delete-keychain "${SIGNING_KEYCHAIN_PATH}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

log "loading release configuration bundle"
"${ROOT_DIR}/packaging/load-macos-release-config.sh" "${RELEASE_CONFIG_ENV_PATH}"
source_env_file "${RELEASE_CONFIG_ENV_PATH}"

log "importing Apple signing assets"
"${ROOT_DIR}/packaging/import-apple-signing-assets.sh" "${SIGNING_ENV_PATH}"
source_env_file "${SIGNING_ENV_PATH}"

resolve_repository_context

log "building signed macOS DMG"
ENABLE_CODE_SIGNING=1 \
APPLE_TEAM_ID="${APPLE_TEAM_ID}" \
APPLE_CODESIGN_IDENTITY="${APPLE_CODESIGN_IDENTITY_RESOLVED}" \
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY}" \
DERIVED_DATA_PATH="${DERIVED_DATA_PATH}" \
APP_PRODUCT_NAME="${APP_PRODUCT_NAME}" \
CURRENT_PROJECT_VERSION_OVERRIDE="${CURRENT_PROJECT_VERSION_OVERRIDE:-}" \
MARKETING_VERSION_OVERRIDE="${MARKETING_VERSION_OVERRIDE:-}" \
PRESERVE_BUILD_LOG="${PRESERVE_BUILD_LOG:-1}" \
"${ROOT_DIR}/build-dmg.sh"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Built app not found after release build: ${APP_PATH}" >&2
  exit 1
fi

log "verifying signed app bundle"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
codesign --display --verbose=4 "${APP_PATH}" >/dev/null

log "notarizing DMG"
APPLE_NOTARY_KEY_ID="${APPLE_NOTARY_KEY_ID}" \
APPLE_NOTARY_ISSUER_ID="${APPLE_NOTARY_ISSUER_ID:-}" \
APPLE_NOTARY_API_KEY_P8_BASE64="${APPLE_NOTARY_API_KEY_P8_BASE64}" \
"${ROOT_DIR}/packaging/notarize-dmg.sh" "${DMG_PATH}"

log "verifying notarized DMG"
spctl -a -vvv -t open --context context:primary-signature "${DMG_PATH}"

log "collecting release metadata"
APP_PLIST="${APP_PATH}/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PLIST}")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP_PLIST}")"
MIN_SYSTEM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${APP_PLIST}")"
TAG="v${VERSION}-dev.${BUILD}"
ASSET_NAME="${APP_PRODUCT_NAME}-${VERSION}-${BUILD}.dmg"
PAGES_BASE_URL="https://${REPO_OWNER}.github.io/${REPO_NAME}"
RELEASE_NOTES_FILENAME="${APP_PRODUCT_NAME}-${VERSION}-${BUILD}.html"
RELEASE_NOTES_PATH="releases/${RELEASE_NOTES_FILENAME}"
RELEASE_NOTES_URL="${PAGES_BASE_URL}/${RELEASE_NOTES_PATH}"
DOWNLOAD_URL_PREFIX="https://github.com/${REPOSITORY}/releases/download/${TAG}/"
DOWNLOAD_URL="${DOWNLOAD_URL_PREFIX}${ASSET_NAME}"
PUBLISHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
COMMIT_SHA="$(git -C "${ROOT_DIR}" rev-parse --short HEAD)"
COMMIT_MESSAGE="$(git -C "${ROOT_DIR}" log -1 --pretty=%s)"

log "staging release asset and update site"
mkdir -p "${RELEASE_ASSETS_DIR}" "${UPDATE_SITE_DIR}/releases" "${UPDATE_SITE_DIR}/appcast-input" "$(dirname "${METADATA_ENV_PATH}")"
cp "${DMG_PATH}" "${RELEASE_ASSETS_DIR}/${ASSET_NAME}"
cp "${RELEASE_ASSETS_DIR}/${ASSET_NAME}" "${UPDATE_SITE_DIR}/appcast-input/${ASSET_NAME}"

UPDATE_CHANNEL=dev \
UPDATE_VERSION="${VERSION}" \
UPDATE_BUILD="${BUILD}" \
UPDATE_MINIMUM_SYSTEM_VERSION="${MIN_SYSTEM}" \
UPDATE_PUBLISHED_AT="${PUBLISHED_AT}" \
UPDATE_DOWNLOAD_URL="${DOWNLOAD_URL}" \
UPDATE_RELEASE_URL="https://github.com/${REPOSITORY}/releases/tag/${TAG}" \
UPDATE_COMMIT_SHA="${COMMIT_SHA}" \
UPDATE_COMMIT_MESSAGE="${COMMIT_MESSAGE}" \
"${ROOT_DIR}/packaging/generate-release-notes-page.sh" "${UPDATE_SITE_DIR}/appcast-input/${RELEASE_NOTES_FILENAME}"

UPDATE_CHANNEL=dev \
UPDATE_DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX}" \
UPDATE_RELEASE_NOTES_URL_PREFIX="${PAGES_BASE_URL}/releases/" \
UPDATE_RELEASE_URL="https://github.com/${REPOSITORY}/releases/tag/${TAG}" \
SPARKLE_PRIVATE_ED_KEY="${SPARKLE_PRIVATE_ED_KEY}" \
"${ROOT_DIR}/packaging/generate-sparkle-appcast.sh" "${UPDATE_SITE_DIR}/appcast.xml" "${UPDATE_SITE_DIR}/appcast-input"

cp "${UPDATE_SITE_DIR}/appcast-input/${RELEASE_NOTES_FILENAME}" "${UPDATE_SITE_DIR}/${RELEASE_NOTES_PATH}"
rm -rf "${UPDATE_SITE_DIR}/appcast-input"
touch "${UPDATE_SITE_DIR}/.nojekyll"

cat > "${METADATA_ENV_PATH}" <<EOF
version=${VERSION}
build=${BUILD}
minimum_system_version=${MIN_SYSTEM}
tag=${TAG}
asset_name=${ASSET_NAME}
pages_base_url=${PAGES_BASE_URL}
release_notes_filename=${RELEASE_NOTES_FILENAME}
release_notes_path=${RELEASE_NOTES_PATH}
release_notes_url=${RELEASE_NOTES_URL}
release_notes_url_prefix=${PAGES_BASE_URL}/releases/
download_url_prefix=${DOWNLOAD_URL_PREFIX}
download_url=${DOWNLOAD_URL}
published_at=${PUBLISHED_AT}
commit_sha=${COMMIT_SHA}
commit_message=${COMMIT_MESSAGE}
repository=${REPOSITORY}
repo_owner=${REPO_OWNER}
repo_name=${REPO_NAME}
release_assets_dir=${RELEASE_ASSETS_DIR}
update_site_dir=${UPDATE_SITE_DIR}
EOF

log "release bundle ready"
log "metadata: ${METADATA_ENV_PATH}"
