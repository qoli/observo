# Repository Guidelines

## Project Structure & Module Organization
- `observo/` contains the app source.
- `observo/observoApp.swift` is the app entry point (`@main`).
- `observo/ContentView.swift` holds the initial SwiftUI view; add new feature views alongside it or in subfolders like `observo/Features/<FeatureName>/`.
- `observo/Assets.xcassets/` stores app icons, colors, and image assets.
- `observo.xcodeproj/` contains Xcode project configuration, schemes, and build settings.
- There is currently no dedicated test target; add one (`observoTests/`) as features grow.

## Build, Test, and Development Commands
- `open observo.xcodeproj` — open the project in Xcode.
- `xcodebuild -project observo.xcodeproj -scheme observo -configuration Debug build` — CLI build for local verification/CI.
- `xcodebuild -project observo.xcodeproj -scheme observo -destination 'platform=iOS Simulator,name=iPhone 16' test` — run unit/UI tests once a test target exists.
- In Xcode, use the `observo` scheme and run on an iOS Simulator for interactive SwiftUI checks.

## Coding Style & Naming Conventions
- Use Swift 5+ conventions with 4-space indentation and no tabs.
- Types/protocols: `UpperCamelCase` (for example, `SettingsViewModel`).
- Variables/functions/properties: `lowerCamelCase` (for example, `loadSettings()`).
- Keep one primary type per file and name files after that type.
- Prefer small SwiftUI views composed from reusable subviews instead of one large body.
- Use Xcode’s formatter (`Editor > Structure > Re-Indent`) before committing.

## Testing Guidelines
- Preferred framework: XCTest (unit) and XCUITest (UI).
- Name test files as `<TypeName>Tests.swift`; test methods should follow `test_<Scenario>_<ExpectedResult>()`.
- Add regression tests for bug fixes and logic extracted from views (view models/helpers).
- Aim for meaningful coverage on business logic; avoid snapshot-only validation.

## Commit & Pull Request Guidelines
- No stable commit convention exists yet in this repository; use clear, imperative commits (recommended: Conventional Commits, e.g., `feat: add onboarding header`).
- Keep commits focused and atomic; avoid mixing refactors with behavior changes.
- PRs should include: brief summary, testing notes, linked issue (if any), and screenshots/video for UI changes.
- Ensure the project builds cleanly before requesting review.
