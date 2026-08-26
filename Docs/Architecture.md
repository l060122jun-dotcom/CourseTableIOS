# Architecture

## Dependency direction

```text
SwiftUI features
  |-- OCR adapters (Vision, VisionKit, PhotosUI)
  |-- persistence adapters (SwiftData)
  |-- calendar adapter (EventKit)
  `-- CourseTableCore

CourseTableCore
  |-- domain models
  |-- validation and time resolution
  |-- OCR review drafts
  `-- calendar occurrence planning and fingerprints
```

`CourseTableCore` must not import SwiftUI, SwiftData, Vision, PhotosUI, or EventKit. This keeps parsing and scheduling logic independently testable.

## Course time representation

`Course` stores information shared by every occurrence: name, teacher, room, notes, color, and owning table.

`MeetingRule` stores weekday, semester week set, reminder override, and one mutually exclusive timing mode:

- `period`: `startPeriod` and `endPeriod` refer to the table's configured periods.
- `custom`: `customStartMinute` and `customEndMinute` store explicit local times.

Minutes are measured from local midnight. A custom start is in `0...1439`; an end is in `1...1440`; start must be earlier than end. Cross-day classes are intentionally excluded from the first version.

The same course may have several meeting rules and may mix regular and custom time rules.

## OCR boundary

OCR output is always stored as `OCRImportDraft`. It contains source-image identity, raw text, positioned blocks, field inference, proposed courses, proposed rules, and warnings.

The app must show a review screen before converting a draft into persisted course data. Calendar export is a second, explicit action after course confirmation.

## Calendar boundary

`CalendarOccurrenceFactory` expands each meeting rule into semester-relative occurrences. Each occurrence has a stable fingerprint containing the course, rule, week, weekday, timing mode, start time, and end time.

The EventKit adapter will:

1. Resolve each semester week into an absolute date.
2. Create or update an `EKEvent` in an app-owned calendar.
3. Add `EKAlarm` from the rule or table reminder policy.
4. Persist the fingerprint and EventKit identifier.
5. On re-export, update or skip matching records instead of creating duplicates.
6. Delete only records previously created by this app when the user requests calendar cleanup.

## Persistence boundary

SwiftData models will mirror the domain types but remain adapter-owned. Mapping functions convert between SwiftData records and immutable domain values. This separation allows future schema migrations without coupling validation to storage.

## CI

GitHub Actions runs on `macos-15`:

1. Select Xcode 16.4.
2. Install XcodeGen and generate `CourseTable.xcodeproj` from `project.yml`.
3. Run `swift test` for the framework-independent domain package.
4. Build the SwiftUI app for a generic iOS Simulator destination with code signing disabled.

An iOS build is considered verified only after this workflow succeeds.
