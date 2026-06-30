import SwiftUI
import SwiftData
import WebKit

#if os(macOS)
import AppKit
typealias PlatformViewRepresentable = NSViewRepresentable
#else
import UIKit
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

/// Renders a mini-app's HTML/CSS/JS in a WKWebView and bridges its `db` storage
/// API back to native persistence. The bridge JavaScript lives in standalone
/// files under `WebBridge/` (loaded via `bridgeScript(_:)`) rather than inline
/// strings, so it's easy to read and edit.
///
/// `db` — a firebase-like document/collection API whose methods return Promises
/// that resolve only after native has performed and persisted the operation:
///   db.collection(name)        -> a named collection (db itself is the "default" one)
///   await coll.list(options?)   -> [{ id, ... }, ...]  (filtered/sorted/paged)
///   await coll.count(options?)  -> number of matching documents
///   await coll.get(id)          -> { id, ... } | null
///   await coll.create(doc)      -> created doc (with a generated id)
///   await coll.update(id, patch)-> updated doc (rejects if id is missing)
///   await coll.remove(id)       -> null (idempotent)
/// `list`/`count` accept `{ where, orderBy, desc, limit, offset }`: `where`
/// filters on top-level fields (equality, or operators `>` `<` `>=` `<=` `==`
/// `!=` `contains`, AND-combined); `orderBy`/`desc` sort by a field; `limit`/
/// `offset` paginate. Each document is a `MiniAppDoc` row scoped by the app's
/// `appID`, so a single write touches one row (not the whole storage blob).
///
/// When `injectReact` is true, React + ReactDOM + Babel (bundled under
/// WebRuntime/) are injected before the page loads, so the source can use
/// JSX inside `<script type="text/babel">` with no build step.
///
/// `source` may be a bare fragment — `MiniAppDocument` wraps it in the standard
/// HTML scaffold (and, for React, auto-mounts `<App/>`) before it loads.
///
/// When `sizeToContent` is true the web view disables its own scrolling and
/// reports its document height via `onHeightChange`, so a host can size the
/// view to fit its content exactly (used for inline mini-apps in a list).
///
/// `console.*` output and uncaught errors are forwarded to `onLog` (when set)
/// so a host can surface them in a debug console.
struct MiniAppWebView: PlatformViewRepresentable {
    /// The mini-app being rendered. Backs the `db` bridge: documents are
    /// `MiniAppDoc` rows fetched/written through `app.modelContext`.
    let app: MiniApp
    let source: String
    let injectReact: Bool
    /// When true, the web view lays out at its full content height and reports
    /// that height through `onHeightChange` instead of scrolling internally.
    var sizeToContent: Bool = false
    /// Called with the document's measured height whenever it changes.
    var onHeightChange: ((CGFloat) -> Void)? = nil
    /// Whether the web view scrolls its own content. Inline views set this only
    /// when their content is clamped to a max height; otherwise the host (list)
    /// scrolls and the web view is sized to fit.
    var scrollEnabled: Bool = true
    /// Called for every captured `console.*` call, uncaught error, or unhandled
    /// promise rejection from the running mini-app.
    var onLog: ((MiniAppLogEntry) -> Void)? = nil
    /// When true, inject the *development* React/ReactDOM builds instead of the
    /// minified production ones. The dev builds emit full, readable warnings and
    /// runtime error messages (the production builds replace them with coded
    /// links), at the cost of size — used by the debug runner.
    var useDevelopmentRuntime: Bool = false

    /// The full HTML document that actually loads, composed from `source`.
    private var document: String {
        MiniAppDocument.html(for: source, react: injectReact)
    }

    /// A real (non-nil) origin for the loaded HTML. Loading with a `nil` baseURL
    /// gives the page an opaque origin, which makes the browser sanitize all
    /// script errors down to a bare "Script error." with no detail. A concrete
    /// https origin keeps the mini-app's own scripts same-origin so uncaught
    /// errors keep their real message and stack. Nothing is fetched from it.
    private static let baseURL = URL(string: "https://miniapp.local/")

    func makeCoordinator() -> Coordinator {
        Coordinator(app: app,
                    onHeightChange: onHeightChange,
                    onLog: onLog)
    }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ webView: WKWebView, context: Context) { reloadIfNeeded(webView, context: context) }
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ webView: WKWebView, context: Context) { reloadIfNeeded(webView, context: context) }
    #endif

    private func makeWebView(context: Context) -> WKWebView {
        let controller = WKUserContentController()

        // Console + error capture must run before any page or runtime script so
        // it can catch React/Babel failures too. Only wire it up when a host
        // actually wants the logs.
        if onLog != nil {
            controller.addUserScript(WKUserScript(source: Self.bridgeScript("console-capture"),
                                                   injectionTime: .atDocumentStart,
                                                   forMainFrameOnly: true))
            controller.add(context.coordinator, name: "log")
        }

        // React libraries first (UMD globals + Babel transpiler), then the
        // `db` bridge — all at document start, before the page's scripts.
        if injectReact {
            for source in Self.reactRuntimeScripts(development: useDevelopmentRuntime) {
                controller.addUserScript(WKUserScript(source: source,
                                                       injectionTime: .atDocumentStart,
                                                       forMainFrameOnly: true))
            }
        }
        controller.addUserScript(WKUserScript(source: Self.bridgeScript("db"),
                                               injectionTime: .atDocumentStart,
                                               forMainFrameOnly: true))
        controller.add(context.coordinator, name: "db")

        // Content-height reporting for inline (size-to-content) rendering.
        if sizeToContent {
            controller.addUserScript(WKUserScript(source: Self.bridgeScript("height-observer"),
                                                   injectionTime: .atDocumentEnd,
                                                   forMainFrameOnly: true))
            controller.add(context.coordinator, name: "hostHeight")
        }

        let config = WKWebViewConfiguration()
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        // The coordinator needs the web view to settle `db` Promises (it calls
        // back into the page via evaluateJavaScript). Held weakly there.
        context.coordinator.webView = webView
        if sizeToContent {
            webView.isOpaque = false
            webView.backgroundColor = .clear
        }
        #if os(iOS)
        webView.scrollView.isScrollEnabled = scrollEnabled
        #endif
        let document = self.document
        webView.loadHTMLString(document, baseURL: Self.baseURL)
        context.coordinator.lastHTML = document
        return webView
    }

    private func reloadIfNeeded(_ webView: WKWebView, context: Context) {
        #if os(iOS)
        // Capping can toggle as the content height crosses the max, so keep
        // the scroll setting in sync on every update.
        webView.scrollView.isScrollEnabled = scrollEnabled
        #endif
        let document = self.document
        guard context.coordinator.lastHTML != document else { return }
        context.coordinator.lastHTML = document
        webView.loadHTMLString(document, baseURL: Self.baseURL)
    }

    /// Loads a bundled bridge script (`WebBridge/<name>.js`) as a source string.
    /// The scripts ship with the app, so a miss is a packaging bug.
    static func bridgeScript(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("Missing bundled bridge script: \(name).js")
            return ""
        }
        return source
    }

    /// Loads the bundled React runtime files (UMD React, ReactDOM, Babel) as
    /// JS source strings, in load order. When `development` is true, the readable
    /// development React builds are used instead of the minified production ones.
    /// Missing files are skipped silently.
    private static func reactRuntimeScripts(development: Bool) -> [String] {
        let resources = development
            ? ["react.development", "react-dom.development", "babel.min"]
            : ["react.production.min", "react-dom.production.min", "babel.min"]
        return resources.compactMap { name in
            guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
                  let source = try? String(contentsOf: url, encoding: .utf8) else {
                assertionFailure("Missing bundled web runtime resource: \(name).js")
                return nil
            }
            return source
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        /// The mini-app whose `db` documents this coordinator reads and writes,
        /// via `app.modelContext`. Held strongly (the view hierarchy owns it too).
        private let app: MiniApp
        private let onHeightChange: ((CGFloat) -> Void)?
        private let onLog: ((MiniAppLogEntry) -> Void)?
        var lastHTML: String = ""
        /// The web view this coordinator backs, used to settle `db` Promises by
        /// calling `window.__settleDb` via `evaluateJavaScript`. Weak to avoid a
        /// retain cycle (the web view owns the content controller, which retains
        /// this coordinator as a message handler).
        weak var webView: WKWebView?

        init(app: MiniApp,
             onHeightChange: ((CGFloat) -> Void)?,
             onLog: ((MiniAppLogEntry) -> Void)?) {
            self.app = app
            self.onHeightChange = onHeightChange
            self.onLog = onLog
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "hostHeight" {
                if let height = message.body as? NSNumber {
                    onHeightChange?(CGFloat(height.doubleValue))
                }
                return
            }

            if message.name == "log" {
                guard let body = message.body as? [String: Any],
                      let level = body["level"] as? String,
                      let text = body["message"] as? String else { return }
                onLog?(MiniAppLogEntry(level: MiniAppLogEntry.Level(rawLevel: level), message: text))
                return
            }

            if message.name == "db" {
                handleDB(message.body)
                return
            }
        }

        // MARK: - db collection bridge (SwiftData-backed)

        /// Performs a `db` operation on a collection — each document is a
        /// `MiniAppDoc` row scoped to `app.appID` — then settles the JS Promise
        /// identified by `reqId`. Messages have the shape
        /// `{ reqId, collection, op, payload }`. Writes save a single row, so a
        /// change never rewrites the whole storage blob.
        private func handleDB(_ rawBody: Any) {
            guard let body = rawBody as? [String: Any],
                  let reqId = body["reqId"] as? String,
                  let name = body["collection"] as? String,
                  let op = body["op"] as? String else { return }
            let payload = body["payload"] as? [String: Any] ?? [:]

            switch op {
            case "list":
                settle(reqId, ok: true, result: query(name, options: payload))

            case "count":
                settle(reqId, ok: true, result: query(name, options: payload).count)

            case "get":
                let doc = fetchDoc(name, id: payload["id"] as? String)
                settle(reqId, ok: true, result: doc.map { Self.wire($0) } ?? NSNull())

            case "create":
                var fields = payload["doc"] as? [String: Any] ?? [:]
                fields.removeValue(forKey: "id")   // native owns the id
                let doc = MiniAppDoc(collection: name, appID: app.appID,
                                     body: Self.encodeBody(fields))
                doc.app = app
                app.modelContext?.insert(doc)
                save()
                settle(reqId, ok: true, result: Self.wire(doc))

            case "update":
                guard let id = payload["id"] as? String,
                      let doc = fetchDoc(name, id: id) else {
                    settle(reqId, ok: false, result: "No document with id \(payload["id"] ?? "nil") in \"\(name)\"")
                    return
                }
                var fields = doc.decodedBody()
                let patch = payload["patch"] as? [String: Any] ?? [:]
                for (key, value) in patch where key != "id" { fields[key] = value }
                doc.body = Self.encodeBody(fields)
                save()
                settle(reqId, ok: true, result: Self.wire(doc))

            case "remove":
                // Idempotent: removing a missing id still resolves.
                if let id = payload["id"] as? String, let doc = fetchDoc(name, id: id) {
                    app.modelContext?.delete(doc)
                    save()
                }
                settle(reqId, ok: true, result: NSNull())

            default:
                settle(reqId, ok: false, result: "Unknown db op \"\(op)\"")
            }
        }

        /// All documents in `collection` for this app, in insertion order.
        private func docs(in collection: String) -> [MiniAppDoc] {
            guard let context = app.modelContext else { return [] }
            let appID = app.appID
            let descriptor = FetchDescriptor<MiniAppDoc>(
                predicate: #Predicate { $0.appID == appID && $0.collection == collection },
                sortBy: [SortDescriptor(\.createdAt)]
            )
            return (try? context.fetch(descriptor)) ?? []
        }

        /// The single document with `id` in `collection`, or nil.
        private func fetchDoc(_ collection: String, id: String?) -> MiniAppDoc? {
            guard let id, let context = app.modelContext else { return nil }
            let appID = app.appID
            var descriptor = FetchDescriptor<MiniAppDoc>(
                predicate: #Predicate {
                    $0.appID == appID && $0.collection == collection && $0.id == id
                }
            )
            descriptor.fetchLimit = 1
            return try? context.fetch(descriptor).first
        }

        /// Runs a `list`/`count` query: fetch the collection (insertion order),
        /// then apply `where` filtering, `orderBy`/`desc` sorting, and
        /// `offset`/`limit` paging over the decoded document dictionaries.
        private func query(_ collection: String, options: [String: Any]) -> [[String: Any]] {
            var rows = docs(in: collection).map { Self.wire($0) }

            if let clause = options["where"] as? [String: Any], !clause.isEmpty {
                rows = rows.filter { Self.matches($0, clause) }
            }
            if let field = options["orderBy"] as? String {
                let descending = (options["desc"] as? NSNumber)?.boolValue ?? false
                rows.sort {
                    let order = Self.jsonCompare($0[field], $1[field])
                    return descending ? order > 0 : order < 0
                }
            }
            if let offset = (options["offset"] as? NSNumber)?.intValue, offset > 0 {
                rows = offset < rows.count ? Array(rows[offset...]) : []
            }
            if let limit = (options["limit"] as? NSNumber)?.intValue, limit >= 0 {
                rows = Array(rows.prefix(limit))
            }
            return rows
        }

        /// Saves the model context so the settled Promise reflects persisted state.
        private func save() { try? app.modelContext?.save() }

        // MARK: - db query helpers

        /// A document's wire form: its decoded fields plus its `id`.
        private static func wire(_ doc: MiniAppDoc) -> [String: Any] {
            var dict = doc.decodedBody()
            dict["id"] = doc.id
            return dict
        }

        /// Encodes a document's fields to a JSON object string for `body`.
        private static func encodeBody(_ fields: [String: Any]) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: fields),
                  let string = String(data: data, encoding: .utf8) else { return "{}" }
            return string
        }

        /// `where` operators usable as `{ field: { ">=": 2 } }`.
        private static let queryOperators: Set<String> =
            [">", "<", ">=", "<=", "==", "!=", "contains"]

        /// Whether `doc` satisfies every condition in `clause` (AND-combined). A
        /// condition is an operator object when it's a dictionary whose keys are
        /// all known operators; otherwise it's an equality match.
        private static func matches(_ doc: [String: Any], _ clause: [String: Any]) -> Bool {
            for (field, condition) in clause {
                let value = doc[field]
                if let ops = condition as? [String: Any], !ops.isEmpty,
                   ops.keys.allSatisfy({ queryOperators.contains($0) }) {
                    for (op, operand) in ops where !satisfies(value, op, operand) {
                        return false
                    }
                } else if !jsonEqual(value, condition) {
                    return false
                }
            }
            return true
        }

        private static func satisfies(_ value: Any?, _ op: String, _ operand: Any) -> Bool {
            switch op {
            case "==": return jsonEqual(value, operand)
            case "!=": return !jsonEqual(value, operand)
            case ">":  return jsonCompare(value, operand) > 0
            case "<":  return jsonCompare(value, operand) < 0
            case ">=": return jsonCompare(value, operand) >= 0
            case "<=": return jsonCompare(value, operand) <= 0
            case "contains":
                if let string = value as? String, let needle = operand as? String {
                    return string.contains(needle)
                }
                if let array = value as? [Any] {
                    return array.contains { jsonEqual($0, operand) }
                }
                return false
            default: return false
            }
        }

        /// Deep equality for decoded JSON values (numbers, strings, bools, null,
        /// arrays, objects). Missing (`nil`) and JSON `null` compare equal.
        private static func jsonEqual(_ a: Any?, _ b: Any?) -> Bool {
            let lhs = (a is NSNull) ? nil : a
            let rhs = (b is NSNull) ? nil : b
            if lhs == nil && rhs == nil { return true }
            guard let lhs, let rhs else { return false }
            if let l = lhs as? NSNumber, let r = rhs as? NSNumber { return l == r }
            if let l = lhs as? String, let r = rhs as? String { return l == r }
            if let l = lhs as? [Any], let r = rhs as? [Any] {
                return l.count == r.count && zip(l, r).allSatisfy { jsonEqual($0, $1) }
            }
            if let l = lhs as? [String: Any], let r = rhs as? [String: Any] {
                return l.count == r.count && l.allSatisfy { jsonEqual($0.value, r[$0.key]) }
            }
            return false
        }

        /// Orders two decoded JSON values for `orderBy`. Numbers and strings sort
        /// naturally; missing/`null` sorts first; mismatched types are treated as
        /// equal (left where they are).
        private static func jsonCompare(_ a: Any?, _ b: Any?) -> Int {
            let lhs = (a is NSNull) ? nil : a
            let rhs = (b is NSNull) ? nil : b
            if lhs == nil && rhs == nil { return 0 }
            guard let lhs else { return -1 }
            guard let rhs else { return 1 }
            if let l = lhs as? NSNumber, let r = rhs as? NSNumber {
                let x = l.doubleValue, y = r.doubleValue
                return x < y ? -1 : (x > y ? 1 : 0)
            }
            if let l = lhs as? String, let r = rhs as? String {
                return l < r ? -1 : (l > r ? 1 : 0)
            }
            return 0
        }

        /// Settles the pending JS Promise for `reqId` by calling `window.__settleDb`.
        /// On success `result` is the JSON value to resolve with; on failure it is
        /// the error message string. Runs on the main thread (message callbacks do).
        private func settle(_ reqId: String, ok: Bool, result: Any?) {
            let resultJSON = jsonLiteral(result ?? NSNull())
            let js = "window.__settleDb(\(jsonLiteral(reqId)), \(ok), \(resultJSON));"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        /// Encodes any JSON value (including bare strings/null) to a JS literal.
        private func jsonLiteral(_ value: Any) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: value,
                                                          options: [.fragmentsAllowed]),
                  let string = String(data: data, encoding: .utf8) else {
                return "null"
            }
            return string
        }
    }
}
