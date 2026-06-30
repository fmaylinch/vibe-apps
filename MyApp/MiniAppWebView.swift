import SwiftUI
import WebKit

#if os(macOS)
import AppKit
typealias PlatformViewRepresentable = NSViewRepresentable
#else
import UIKit
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

/// Renders a mini-app's HTML/CSS/JS in a WKWebView and bridges two storage APIs
/// back to native persistence. The bridge JavaScript lives in standalone files
/// under `WebBridge/` (loaded via `bridgeScript(_:)`) rather than inline strings,
/// so it's easy to read and edit.
///
/// `HostStorage` — a synchronous, fire-and-forget key-value store:
///   HostStorage.getItem(key)        -> any JSON value (object/array/number/string/bool) | null
///   HostStorage.setItem(key, value) -> persists any JSON value across launches
///   HostStorage.removeItem(key)
///   HostStorage.clear()
///
/// `db` — a firebase-like document/collection API whose methods return Promises
/// that resolve only after native has performed and persisted the operation:
///   db.collection(name)        -> a named collection (db itself is the "default" one)
///   await coll.list()           -> [{ id, ... }, ...]
///   await coll.get(id)          -> { id, ... } | null
///   await coll.create(doc)      -> created doc (with a generated id)
///   await coll.update(id, patch)-> updated doc (rejects if id is missing)
///   await coll.remove(id)       -> null (idempotent)
/// Collections persist inside the same `storageJSON` blob under a reserved
/// `"__collections"` key.
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
    let source: String
    let initialData: String
    let injectReact: Bool
    let onPersist: (String) -> Void
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
        Coordinator(initialData: initialData,
                    onPersist: onPersist,
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
        // storage bridges — all at document start, before the page's scripts.
        if injectReact {
            for source in Self.reactRuntimeScripts(development: useDevelopmentRuntime) {
                controller.addUserScript(WKUserScript(source: source,
                                                       injectionTime: .atDocumentStart,
                                                       forMainFrameOnly: true))
            }
        }
        controller.addUserScript(WKUserScript(source: bootstrapScript,
                                               injectionTime: .atDocumentStart,
                                               forMainFrameOnly: true))
        controller.add(context.coordinator, name: "storage")
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

    /// JS injected before the page loads: seeds saved data, then exposes the
    /// `HostStorage` and `db` bridges. The seed is a tiny generated line so the
    /// bridge files themselves (`WebBridge/*.js`) stay static; `host-storage.js`
    /// reads `window.__INITIAL_DATA__` set here.
    private var bootstrapScript: String {
        let seed = initialData.isEmpty ? "{}" : initialData
        return """
        window.__INITIAL_DATA__ = \(seed);
        \(Self.bridgeScript("host-storage"))
        \(Self.bridgeScript("db"))
        """
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
        /// Reserved `store` key under which `db` collections live, kept separate
        /// from the mini-app's own `HostStorage` keys.
        private static let collectionsKey = "__collections"

        private var store: [String: Any]
        private let onPersist: (String) -> Void
        private let onHeightChange: ((CGFloat) -> Void)?
        private let onLog: ((MiniAppLogEntry) -> Void)?
        var lastHTML: String = ""
        /// The web view this coordinator backs, used to settle `db` Promises by
        /// calling `window.__settleDb` via `evaluateJavaScript`. Weak to avoid a
        /// retain cycle (the web view owns the content controller, which retains
        /// this coordinator as a message handler).
        weak var webView: WKWebView?

        init(initialData: String,
             onPersist: @escaping (String) -> Void,
             onHeightChange: ((CGFloat) -> Void)?,
             onLog: ((MiniAppLogEntry) -> Void)?) {
            self.onPersist = onPersist
            self.onHeightChange = onHeightChange
            self.onLog = onLog
            if let data = initialData.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.store = parsed
            } else {
                self.store = [:]
            }
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

            guard let body = message.body as? [String: Any],
                  let op = body["op"] as? String else { return }
            switch op {
            case "set":
                // Value may be any JSON type (object/array/number/string/bool/null);
                // a missing value (e.g. setItem(k, undefined)) is stored as null.
                if let key = body["key"] as? String {
                    store[key] = body["value"] ?? NSNull()
                }
            case "remove":
                if let key = body["key"] as? String { store.removeValue(forKey: key) }
            case "clear":
                store.removeAll()
            default:
                break
            }
            persist()
        }

        private func persist() {
            guard let data = try? JSONSerialization.data(withJSONObject: store),
                  let json = String(data: data, encoding: .utf8) else { return }
            onPersist(json)
        }

        // MARK: - db collection bridge

        /// Performs a `db` operation on a collection, persists the result, and
        /// settles the JS Promise identified by `reqId`. Messages have the shape
        /// `{ reqId, collection, op, payload }`.
        private func handleDB(_ rawBody: Any) {
            guard let body = rawBody as? [String: Any],
                  let reqId = body["reqId"] as? String,
                  let name = body["collection"] as? String,
                  let op = body["op"] as? String else { return }
            let payload = body["payload"] as? [String: Any] ?? [:]

            var docs = collection(name)
            switch op {
            case "list":
                settle(reqId, ok: true, result: docs)

            case "get":
                let id = payload["id"] as? String
                settle(reqId, ok: true, result: docs.first { $0["id"] as? String == id } ?? NSNull())

            case "create":
                var doc = payload["doc"] as? [String: Any] ?? [:]
                doc["id"] = UUID().uuidString
                docs.append(doc)
                setCollection(name, docs)
                persist()
                settle(reqId, ok: true, result: doc)

            case "update":
                guard let id = payload["id"] as? String,
                      let index = docs.firstIndex(where: { $0["id"] as? String == id }) else {
                    settle(reqId, ok: false, result: "No document with id \(payload["id"] ?? "nil") in \"\(name)\"")
                    return
                }
                let patch = payload["patch"] as? [String: Any] ?? [:]
                docs[index].merge(patch) { _, new in new }
                setCollection(name, docs)
                persist()
                settle(reqId, ok: true, result: docs[index])

            case "remove":
                // Idempotent: removing a missing id still resolves.
                let id = payload["id"] as? String
                docs.removeAll { $0["id"] as? String == id }
                setCollection(name, docs)
                persist()
                settle(reqId, ok: true, result: NSNull())

            default:
                settle(reqId, ok: false, result: "Unknown db op \"\(op)\"")
            }
        }

        /// Reads a collection's documents from the store (empty if absent).
        /// JSON-decoded arrays come back as `[Any]`, so fall back to mapping.
        private func collection(_ name: String) -> [[String: Any]] {
            let cols = store[Self.collectionsKey] as? [String: Any] ?? [:]
            if let docs = cols[name] as? [[String: Any]] { return docs }
            return (cols[name] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        }

        private func setCollection(_ name: String, _ docs: [[String: Any]]) {
            var cols = store[Self.collectionsKey] as? [String: Any] ?? [:]
            cols[name] = docs
            store[Self.collectionsKey] = cols
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
