# Project instructions

- Keep the domain layer independent from SwiftUI, Vision, EventKit, and persistence frameworks.
- Model regular and irregular course times through one `MeetingRule` with mutually exclusive timing modes.
- Never write calendar events directly from OCR output. OCR must produce a reviewable draft first.
- Calendar export must be idempotent and must preserve enough identifiers to update or remove only events created by this app.
- Use a Luna subagent for small, bounded tasks such as test matrices, fixture generation, string cleanup, and documentation checks when subagents are available. Keep architecture, persistence migrations, OCR parsing, and calendar synchronization in the primary agent.
- Do not claim iOS compilation passed unless an Xcode build or test run succeeded on macOS.
