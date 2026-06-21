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
    /// JSON object string backing the `HostStorage` bridge (e.g. {"todos":"[...]"}).
    var storageJSON: String = "{}"
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(name: String,
         icon: String = "✨",
         source: String = "",
         framework: String = MiniAppFramework.vanilla.rawValue,
         storageJSON: String = "{}",
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.name = name
        self.icon = icon
        self.source = source
        self.framework = framework
        self.storageJSON = storageJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
