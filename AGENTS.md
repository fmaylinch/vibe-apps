# AGENTS.md

VibeApps is an iOS app for creating, running, and sharing user-authored
"mini-apps" — small self-contained HTML/CSS/JS programs (vanilla or React/JSX)
that the host renders inside a `WKWebView`. Each mini-app persists its own data
through a JS↔native `db` bridge, and apps and/or their data can be exported and
imported as editable source files.

## Build & run

- Open `VibeApps.xcodeproj` in Xcode. The app target/scheme is **MyApp**
  (the product name; the project is `VibeApps`).
- Build from the CLI:
  `xcodebuild -project VibeApps.xcodeproj -scheme MyApp -destination 'generic/platform=iOS' build`
- **Requires Xcode 27 / the iOS 27 SDK to compile**: `AICodeService.swift`
  references `PrivateCloudComputeLanguageModel`, which only exists in that SDK
  (the older iOS 26 SDK fails with "cannot find … in scope"). If your default
  `xcode-select` is an older Xcode, prefix the build with
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.
- Deployment target is iOS 26 (some features, e.g. Private Cloud Compute AI,
  require iOS 27 and are gated at runtime with `#available`). Universal
  (iPhone + iPad).
- There is no test target.

### Dependencies (Swift Package Manager, resolved in-project)

- **Runestone** (0.5.2) + **TreeSitterLanguages** — the code editor with JS/JSX
  syntax highlighting (`CodeEditorView.swift`).
- React, ReactDOM, and Babel are **not** packages — they ship as bundled JS
  files under `MyApp/WebRuntime/` and are injected into the web view at runtime.

## Architecture

SwiftUI + SwiftData app. The persistent model is `MiniApp` (`MiniApp.swift`),
synced via CloudKit when available (falls back to local-only — see
`ContentView.swift`'s `makeContainer()`; every model property has a default so
the schema stays CloudKit-compatible).

Key source files (all under `MyApp/`):

| File | Responsibility |
| --- | --- |
| `ContentView.swift` | `@main` app entry, `HomeView` list, CRUD, import/export wiring |
| `MiniApp.swift` | SwiftData models (`MiniApp` + `MiniAppDoc` db rows) + `MiniAppFramework` enum |
| `MiniAppEditorView.swift` | Edit metadata/source; AI code generation UI |
| `MiniAppRunnerView.swift` | Runs a mini-app full-screen with a debug console |
| `MiniAppWebView.swift` | **Core**: `WKWebView` representable + native side of the storage/`db`/log bridges |
| `MiniAppDocument.swift` | Wraps a source fragment into a full HTML document (auto-mounts `<App/>` for React) |
| `MiniAppExport.swift` | Export/import as editable source files; `JSONValue` codec; `MiniAppExportCoder` |
| `MiniAppTemplate.swift` | Starter bundles, loaded from `Examples/` via the import path |
| `AICodeService.swift` | Code generation via Apple Foundation Models (on-device + Private Cloud Compute) |
| `MiniAppDebugConsole.swift` | `MiniAppLogEntry` + console UI for captured `console.*`/errors |
| `CodeEditorView.swift` | Runestone-based source editor |

### The web bridge (most important subsystem)

`MyApp/WebBridge/` holds the JS injected into every mini-app's web view as
standalone files (not inline Swift strings), loaded via
`MiniAppWebView.bridgeScript(_:)`:

- **`db.js`** — `db`: a firebase-like document/collection API, the sole
  persistence for a mini-app. Every call returns a Promise that resolves only
  after native has persisted the operation. Native settles the matching Promise
  via `window.__settleDb`. Each document is its own SwiftData `MiniAppDoc` row
  (scoped by the app's `appID`), so a single create/update/remove writes one row,
  and CloudKit syncs documents individually. `list`/`count` take an optional
  query — `{ where, orderBy, desc, limit, offset }`, with `where` operators `>`
  `<` `>=` `<=` `==` `!=` `contains` — evaluated natively so only the requested
  page crosses the bridge.
- **`console-capture.js`** — forwards `console.*` and uncaught errors to native
  (the debug console). Injected at document start, before runtime/page scripts.
- **`height-observer.js`** — reports document height so inline mini-apps in the
  list can size to their content.

The native side of the message handlers lives in `MiniAppWebView.Coordinator`.
A mini-app's data is its `db` documents (`MiniAppDoc` rows). For export those
rows are folded into a `"__collections"` map inside the `const STORAGE = …` blob
(`MiniApp.storageJSONForExport()`); on import the blob is read back into rows
(`adoptCollections(from:in:)`), so the portable file format is self-contained.

### Authoring model

Authors write only the interesting part — `MiniAppDocument` adds the document
shell. Vanilla = body markup + `<style>` + `<script>`. React = a component named
`App` (host auto-mounts it; no `createRoot`/imports/`#root`). Source that is
already a full HTML document is passed through untouched. Example starters live
in `MyApp/Examples/` (`*.html`, `*.jsx`).

### Export / import

Apps and data export as **editable source files** (`.jsx`/`.html`/`.data.js`),
not opaque JSON — metadata rides in leading comments (`@name`, `@type`, `@icon`,
…) and storage in a trailing `const STORAGE = …`. `MiniAppExportCoder` is the
single encode/decode path; starters are decoded through it too, so their
metadata can't drift. Import works from a file or from the pasteboard (via
`PasteButton`, whose tap is the privacy consent for clipboard access).

## Conventions

- Match the surrounding style: thorough doc comments (`///`) explaining *why*,
  not just what. Keep them when editing.
- Bridge JS belongs in `WebBridge/*.js` files, not inline Swift strings.
- A mini-app's data is its `db` documents (`MiniAppDoc` rows) — there is no
  other storage and no storage-format migration; the schema is the current
  shape only.
- Multiplatform shims exist (`PlatformViewRepresentable`, `#if os(...)`), but
  iOS is the only shipped platform.
- Commit messages: short imperative subject (see `git log`).
