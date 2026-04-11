# Notion Dashboard Swift

Standalone SwiftUI application for iOS and macOS, extracted from the original `Notion-Extension` repository.

## What is included

- Dashboard view (KPI, blockers, data quality, todos)
- Stages view with Kanban + WIP limits
- Stage automation:
  - Open stage creates todo with deadline J+3
  - Applied/interview statuses can create follow-up todos
- Calendar view from external iCal URL
- Google OAuth (PKCE) + Google Calendar fetch
- Local notifications with reminder offsets and snooze actions
- Focus mode + URL blocker (in-app link blocking while focus is active)
- News + Markets widgets (Yahoo feeds)
- Pipeline import (LinkedIn/Welcome/JobTeaser) from URL/clipboard with parsing
- Settings view for all connections:
  - Notion token / DB IDs
  - Google OAuth client ID / redirect URI / scopes
  - API keys
  - iCal link
  - Pipeline toggle
  - Field/status mapping
- Notion robustness:
  - retry with backoff on transient failures/rate-limit
  - offline queue for pending write operations
  - diagnostics logs in Settings
- Import/Export of all connection parameters into a `.txt` file
- Notion client for fetch/upsert/status update

## Project layout

- `Sources/`: SwiftUI app, services, models, and shared views
- `Config/`: platform Info.plist files
- `project.yml`: XcodeGen project definition
- `packaging/`: DMG, notarization, and Sparkle release scripts
- `.github/workflows/dev-release.yml`: macOS release pipeline

## Generate and run

1. Install Xcode 15+.
2. Install XcodeGen:
   - `brew install xcodegen`
3. Generate the Xcode project:
   - `xcodegen generate`
4. Open the project:
   - `open NotionDashboardSwift.xcodeproj`
5. Run either target:
   - `NotionDashboard-iOS`
   - `NotionDashboard-macOS`

## Local packaging

Build an unsigned local DMG:

```bash
./build-dmg.sh
```

The generated DMG contains:

- `Dashboard.app`
- `Connections/connections-config.template.txt`
- `Applications` shortcut

## Google OAuth setup

1. In Google Cloud Console, create an OAuth client for installed apps.
2. Add the app callback used by the current client ID: `com.googleusercontent.apps.608348086080-dp8647muci5st4em00pdgvrba75jq3db:/oauth2redirect`.
3. In Settings tab, set:
   - `Google OAuth client ID`
   - `Google OAuth redirect URI`
   - scopes if needed
4. Click `Connect Google`.

## Security note

The exported `.txt` configuration contains sensitive data (tokens and API keys).
Store it securely.
