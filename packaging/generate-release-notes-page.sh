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
  UPDATE_PUBLISHED_AT
  UPDATE_DOWNLOAD_URL
  UPDATE_RELEASE_URL
)

for name in "${required_vars[@]}"; do
  if [[ -z "${(P)name:-}" ]]; then
    echo "Missing required environment variable: ${name}" >&2
    exit 1
  fi
done

output_path="$1"
mkdir -p "$(dirname "$output_path")"

release_notes_url="${UPDATE_RELEASE_NOTES_URL:-${UPDATE_RELEASE_URL}}"
commit_sha="${UPDATE_COMMIT_SHA:-unknown}"
commit_message="${UPDATE_COMMIT_MESSAGE:-No commit summary provided.}"
minimum_system_version="${UPDATE_MINIMUM_SYSTEM_VERSION:-13.0}"

html_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\\&amp;/g' \
    -e 's/</\\&lt;/g' \
    -e 's/>/\\&gt;/g' \
    -e 's/\"/\\&quot;/g' \
    -e "s/'/\\&#39;/g"
}

escaped_commit_sha="$(html_escape "${commit_sha}")"
escaped_commit_message="$(html_escape "${commit_message}")"
escaped_published_at="$(html_escape "${UPDATE_PUBLISHED_AT}")"
escaped_minimum_system_version="$(html_escape "${minimum_system_version}")"

cat > "$output_path" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Dashboard ${UPDATE_VERSION} (${UPDATE_BUILD})</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #09131a;
      --panel: rgba(13, 32, 42, 0.88);
      --stroke: rgba(163, 206, 222, 0.16);
      --text: #f4f7f8;
      --muted: rgba(244, 247, 248, 0.7);
      --teal: #59c1b2;
      --orange: #ff9d5c;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
      background:
        radial-gradient(circle at top left, rgba(89, 193, 178, 0.22), transparent 30%),
        radial-gradient(circle at top right, rgba(255, 157, 92, 0.22), transparent 28%),
        linear-gradient(180deg, #0d1b22, var(--bg));
      color: var(--text);
      padding: 48px 20px;
    }
    main {
      width: min(880px, 100%);
      margin: 0 auto;
      padding: 28px;
      border-radius: 28px;
      background: var(--panel);
      border: 1px solid var(--stroke);
      backdrop-filter: blur(18px);
      box-shadow: 0 24px 80px rgba(0, 0, 0, 0.32);
    }
    .eyebrow {
      letter-spacing: 0.24em;
      text-transform: uppercase;
      font-size: 12px;
      color: var(--muted);
      margin-bottom: 12px;
    }
    h1 {
      margin: 0 0 10px;
      font-family: "Iowan Old Style", "Palatino", serif;
      font-size: clamp(2.2rem, 6vw, 3.4rem);
      line-height: 1.04;
    }
    p { color: var(--muted); line-height: 1.6; }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 12px;
      margin: 28px 0;
    }
    .card {
      padding: 16px;
      border-radius: 18px;
      background: rgba(255,255,255,0.05);
      border: 1px solid rgba(255,255,255,0.06);
    }
    .card strong {
      display: block;
      font-size: 13px;
      color: var(--muted);
      margin-bottom: 8px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }
    .value {
      font-size: 1.4rem;
      font-weight: 700;
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      margin-top: 24px;
    }
    a.button {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-height: 46px;
      padding: 0 18px;
      border-radius: 999px;
      text-decoration: none;
      font-weight: 600;
      color: #041014;
      background: var(--teal);
    }
    a.button.secondary {
      color: var(--text);
      background: transparent;
      border: 1px solid rgba(255,255,255,0.14);
    }
    pre {
      margin-top: 24px;
      padding: 16px;
      border-radius: 18px;
      background: rgba(0,0,0,0.22);
      border: 1px solid rgba(255,255,255,0.08);
      color: var(--text);
      white-space: pre-wrap;
      line-height: 1.5;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    }
  </style>
</head>
<body>
  <main>
    <div class="eyebrow">Dashboard · ${UPDATE_CHANNEL} channel</div>
    <h1>Dev build ${UPDATE_VERSION} (${UPDATE_BUILD})</h1>
    <p>This page is the signed release note entry used by Sparkle. The app can now install this build in place, while the direct DMG remains available as a fallback.</p>

    <section class="grid">
      <div class="card">
        <strong>Published</strong>
        <div class="value">${escaped_published_at}</div>
      </div>
      <div class="card">
        <strong>Minimum macOS</strong>
        <div class="value">${escaped_minimum_system_version}</div>
      </div>
      <div class="card">
        <strong>Commit</strong>
        <div class="value">${escaped_commit_sha}</div>
      </div>
    </section>

    <pre>${escaped_commit_message}</pre>

    <div class="actions">
      <a class="button" href="${UPDATE_DOWNLOAD_URL}">Download DMG</a>
      <a class="button secondary" href="${UPDATE_RELEASE_URL}">Open GitHub Release</a>
      <a class="button secondary" href="${release_notes_url}">Canonical release notes URL</a>
    </div>
  </main>
</body>
</html>
HTML
