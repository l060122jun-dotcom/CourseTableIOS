# CourseTable iOS

An iOS-first course schedule app inspired by the course-table workflow in vivo Calendar, with additional support for image recognition, irregular course times, and Apple Calendar reminders.

See [Docs/Architecture.md](Docs/Architecture.md) for dependency boundaries and synchronization rules.

## Architecture

- `CourseTableCore`: framework-independent domain models, validation, time resolution, fingerprints, and OCR draft types.
- `CourseTableApp`: SwiftUI application shell. Vision/VisionKit, PhotosUI, SwiftData, and EventKit adapters belong here.
- `CourseTableCoreTests`: domain tests that run on an iOS Simulator.
- `.github/workflows/ios-ci.yml`: generates the Xcode project and builds/tests it on a GitHub-hosted macOS runner.

## Timing modes

Every meeting rule uses one of two modes:

- `period`: references a configured start and end period.
- `custom`: stores an explicit start and end minute of day, independent of periods.

Course name, teacher, room, notes, weeks, weekday, color, and reminder policy are shared by both modes.

## Generate and test on macOS

```bash
brew install xcodegen
xcodegen generate
swift test
xcodebuild build \
  -project CourseTable.xcodeproj \
  -scheme CourseTable \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

The repository does not commit a generated `.xcodeproj`; GitHub Actions creates it from `project.yml`.
