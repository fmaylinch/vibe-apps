import Foundation
import SwiftData

/// A user-authored mini-app: a self-contained HTML/CSS/JS document that the host
/// renders in a web view. Each mini-app also carries its own persisted key-value
/// storage blob so it can remember state between launches.
///
/// Every stored property has a default value so the schema stays compatible with
/// CloudKit sync (CloudKit requires attributes to be optional or have a default).
@Model
final class MiniApp {
    var name: String = ""
    var icon: String = "✨"
    var source: String = ""
    /// Which JS runtime to inject before the mini-app runs. See `MiniAppFramework`.
    var framework: String = MiniAppFramework.vanilla.rawValue
    /// JSON object string backing the `HostStorage` bridge. Values are native
    /// JSON (e.g. {"todos":[...]}), so a mini-app reads/writes structured data
    /// without JSON.parse/stringify.
    var storageJSON: String = "{}"
    /// Format version of `storageJSON`. `0` is the legacy double-encoded form
    /// (values were escaped JSON strings); `1` stores native JSON values. See
    /// `migrateStorageIfNeeded()`. Defaults to `0` so SwiftData flags existing
    /// rows for migration; new instances start at the current version.
    var storageFormatVersion: Int = 0
    /// When `true`, the mini-app renders directly in the main list instead of
    /// requiring a tap to open it in its own screen.
    var isInline: Bool = false
    /// Optional cap (in points) on the height an inline mini-app occupies in the
    /// list. `nil` means no cap — the row grows to fit the content. When the
    /// content exceeds the cap, the inline view scrolls within this height.
    var inlineMaxHeight: Double?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(name: String,
         icon: String = "✨",
         source: String = "",
         framework: String = MiniAppFramework.vanilla.rawValue,
         storageJSON: String = "{}",
         storageFormatVersion: Int = MiniApp.currentStorageFormatVersion,
         isInline: Bool = false,
         inlineMaxHeight: Double? = nil,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.name = name
        self.icon = icon
        self.source = source
        self.framework = framework
        self.storageJSON = storageJSON
        self.storageFormatVersion = storageFormatVersion
        self.isInline = isInline
        self.inlineMaxHeight = inlineMaxHeight
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The current `storageJSON` format: `1` stores native JSON values.
    static let currentStorageFormatVersion = 1

    /// Upgrades legacy double-encoded storage (where each value was an escaped
    /// JSON string, e.g. {"todos":"[...]"}) to native JSON ({"todos":[...]}) so
    /// the `HostStorage` bridge hands mini-apps real objects. Runs at most once
    /// per app, gated by `storageFormatVersion`, so values that are genuinely
    /// strings aren't re-expanded. Does NOT touch `updatedAt`.
    func migrateStorageIfNeeded() {
        guard storageFormatVersion < Self.currentStorageFormatVersion else { return }
        if let parsed = JSONValue.parse(storageJSON) {
            storageJSON = parsed.expandingStorageValues().compactString() ?? storageJSON
        }
        storageFormatVersion = Self.currentStorageFormatVersion
    }
}

/// The runtime a mini-app is authored against.
enum MiniAppFramework: String, CaseIterable, Identifiable {
    /// Plain HTML / CSS / JavaScript — no libraries injected.
    case vanilla
    /// React + ReactDOM + Babel injected so the source can use JSX directly.
    case react

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vanilla: return "HTML / JavaScript"
        case .react: return "React (JSX)"
        }
    }
}
