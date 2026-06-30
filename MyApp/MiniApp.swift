import Foundation
import SwiftData

/// A user-authored mini-app: a self-contained HTML/CSS/JS document that the host
/// renders in a web view. Each mini-app persists its own data as `db` documents
/// (`MiniAppDoc` rows) so it can remember state between launches.
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
    /// Stable identifier used to scope this app's `db` documents (`MiniAppDoc`
    /// rows carry a matching `appID`, so a collection can be fetched with a
    /// simple predicate instead of walking the relationship). Generated once.
    var appID: String = UUID().uuidString
    /// This app's `db` documents, one SwiftData row per document — the sole
    /// persistence for a mini-app. A single create/update/remove writes one row,
    /// and CloudKit syncs documents individually. Cascade-deleted with the app.
    @Relationship(deleteRule: .cascade, inverse: \MiniAppDoc.app)
    var documents: [MiniAppDoc] = []
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
         isInline: Bool = false,
         inlineMaxHeight: Double? = nil,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.name = name
        self.icon = icon
        self.source = source
        self.framework = framework
        self.isInline = isInline
        self.inlineMaxHeight = inlineMaxHeight
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Reserved key under which `db` collections are nested inside an exported
    /// storage blob: `{ "__collections": { name: [docs] } }`. This is purely the
    /// portable file shape — live data lives in `documents` rows.
    static let collectionsKey = "__collections"

    /// Creates `MiniAppDoc` rows for this app from an exported storage `blob`
    /// (the `const STORAGE = …` value, whose `__collections` map holds the
    /// documents). Used on import. Existing documents are left in place — callers
    /// replacing an app's data should delete them first.
    func adoptCollections(from blob: String, in context: ModelContext) {
        guard let data = blob.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let collections = object[Self.collectionsKey] as? [String: Any] else { return }

        // Preserve each collection's order by spacing createdAt timestamps, so a
        // default (insertion-order) `list()` reproduces the exported sequence.
        let base = Date.now
        var index = 0
        for (name, value) in collections {
            let docs = (value as? [[String: Any]])
                ?? (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
            for var fields in docs {
                let id = fields["id"] as? String ?? UUID().uuidString
                fields.removeValue(forKey: "id")
                let body = (try? JSONSerialization.data(withJSONObject: fields))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                let doc = MiniAppDoc(id: id, collection: name, appID: appID,
                                     createdAt: base.addingTimeInterval(Double(index) * 0.001),
                                     body: body)
                doc.app = self
                context.insert(doc)
                index += 1
            }
        }
    }

    /// Builds the exportable storage blob: a `__collections` map reconstructed
    /// from this app's `documents`. The inverse of `adoptCollections(from:in:)`,
    /// so an exported file re-imports cleanly. Empty (`{}`) when there are none.
    func storageJSONForExport() -> String {
        var collections: [String: [[String: Any]]] = [:]
        for doc in documents.sorted(by: { $0.createdAt < $1.createdAt }) {
            var fields = doc.decodedBody()
            fields["id"] = doc.id
            collections[doc.collection, default: []].append(fields)
        }
        guard !collections.isEmpty else { return "{}" }

        let object: [String: Any] = [Self.collectionsKey: collections]
        guard let merged = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: merged, encoding: .utf8) else { return "{}" }
        return json
    }
}

/// One `db` document: a single record in a named collection belonging to a
/// `MiniApp`. The user's fields live in `body` (a JSON object string); `id` is
/// the document's logical id (returned to the mini-app), distinct from
/// SwiftData's own `persistentModelID`. Storing each document as its own row is
/// what makes `db` writes cheap (one row per change) and CloudKit-syncable at
/// document granularity.
///
/// Every stored property has a default so the schema stays CloudKit-compatible.
@Model
final class MiniAppDoc {
    /// The document's logical id, generated on create and handed back to the
    /// mini-app. Not SwiftData's `persistentModelID`.
    var id: String = ""
    /// The collection this document belongs to (e.g. "todos").
    var collection: String = ""
    /// Mirrors the owning app's `appID`, so a collection is fetchable with a
    /// predicate without traversing the relationship.
    var appID: String = ""
    /// Insertion timestamp; the default order for `list()`.
    var createdAt: Date = Date.now
    /// The document's fields as a JSON object string (excludes `id`).
    var body: String = "{}"
    /// The owning app (nil only transiently before assignment). Cascade target.
    var app: MiniApp?

    init(id: String = UUID().uuidString,
         collection: String = "",
         appID: String = "",
         createdAt: Date = .now,
         body: String = "{}") {
        self.id = id
        self.collection = collection
        self.appID = appID
        self.createdAt = createdAt
        self.body = body
    }

    /// The `body` decoded to a JSON object (empty if it can't be parsed).
    func decodedBody() -> [String: Any] {
        guard let data = body.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [:] }
        return object
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
