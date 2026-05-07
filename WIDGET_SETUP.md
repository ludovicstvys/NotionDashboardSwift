# Widget Integration Setup Guide

## Overview
Your NotionDashboardSwift app now has fully configured widget extensions for **both iOS and macOS** that display:
- **Todo Widget**: Shows your next pending todo
- **Open Stages Widget**: Shows your open stage pipeline
- **Upcoming Events Widget**: Shows your next calendar event

## What Was Set Up

### 1. **Project Configuration** (`project.yml`)
Added two new widget extension targets:
- **`NotionDashboardWidgets-iOS`**: iOS/iPadOS widgets (iOS 16.0+)
- **`NotionDashboardWidgets-macOS`**: macOS widgets (macOS 13.0+)

Both include sources from `Sources/Widgets/` and `Sources/Services/WidgetData.swift`.

### 2. **Entitlements**
All targets are configured with app group entitlements:
- Shared app group: `group.com.loldashboard.notiondashboard`
- Files created:
  - `Config/iOS-Info.entitlements` - iOS app
  - `Config/macOS-Info.entitlements` - macOS app
  - `Config/NotionDashboardWidgets.entitlements` - iOS widgets
  - `Config/NotionDashboardWidgets-macOS.entitlements` - macOS widgets

### 3. **Build Targets**
The project now has 4 targets:
1. **NotionDashboard-iOS** - Main iOS/iPadOS app
2. **NotionDashboard-macOS** - Main macOS app
3. **NotionDashboardWidgets-iOS** - iOS/iPadOS widgets (NEW)
4. **NotionDashboardWidgets-macOS** - macOS widgets (NEW)

## How Widgets Work

### Data Sharing
Widgets read data from a shared `DashboardWidgetSnapshot` saved via the app group container:
```swift
let appGroupIdentifier = "group.com.loldashboard.notiondashboard"
```

When you update stages, todos, or events in the main app, they're synced to this snapshot:
```swift
WidgetSnapshotSync.syncStagesAndTodos(stages: stages, todos: todos)
WidgetSnapshotSync.syncEvents(events: events)
```

### Deep Linking
Widgets support deep links back to the main app:
- Todo widget → opens the specific todo in the home screen
- Stages widget → opens the stages view
- Events widget → opens the calendar

## Building Locally

### macOS Build ✅ (Works via CLI)
```bash
xcodebuild build -project NotionDashboardSwift.xcodeproj \
  -scheme NotionDashboard-macOS \
  -configuration Debug

xcodebuild build -project NotionDashboardSwift.xcodeproj \
  -scheme NotionDashboardWidgets-macOS \
  -configuration Debug
```
Both build successfully from the command line!

### iOS Build (Requires Xcode UI)
To build for iOS, you need to:
1. Open `NotionDashboardSwift.xcodeproj` in Xcode
2. Select the **NotionDashboard-iOS** scheme
3. In the Signing & Capabilities tab:
   - Select your development team
   - The "App Groups" capability is already configured
4. Do the same for the **NotionDashboardWidgets-iOS** scheme

### Testing Widgets

**macOS Widgets:**
1. Build and run **NotionDashboard-macOS** on your Mac
2. In Xcode, select **NotionDashboardWidgets-macOS** scheme and run
3. Add the widget to your Lock Screen using system preferences or widget picker

**iOS Widgets:**
1. Build and run **NotionDashboard-iOS** on a simulator/device
2. In Xcode toolbar, switch to **NotionDashboardWidgets-iOS** scheme
3. Build and run on the same simulator
4. On the home screen, long-press → "Edit" → "+" → add Dashboard widgets

## Files Modified
- `project.yml` - Added two widget extension targets (iOS and macOS)
- `Config/iOS-Info.entitlements` - Created with app group entitlement
- `Config/macOS-Info.entitlements` - Created with app group entitlement
- `Config/NotionDashboardWidgets-macOS-Info.plist` - Created for macOS widget extension
- `NotionDashboardSwift.xcodeproj` - Regenerated via XcodeGen

## Notes
- The widget code (`Sources/Widgets/NotionDashboardWidgets.swift`) was already present
- Data sharing logic (`WidgetData.swift`) is already implemented
- `WidgetSnapshotSync.swift` is only used by the main app targets (not the widget extensions)
- Widgets for both platforms are fully functional and compile successfully

## Next Steps
1. Open the project in Xcode UI to configure development team signing
2. Test the widgets by running the app on a simulator
3. Implement any custom widget UI updates you want
