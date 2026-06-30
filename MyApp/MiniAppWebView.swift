import SwiftUI
import WebKit

#if os(macOS)
import AppKit
typealias PlatformViewRepresentable = NSViewRepresentable
#else
import UIKit
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

/// Renders a mini-app's HTML/CSS/JS in a WKWebView and bridges a small
/// `HostStorage` key-value API back to native persistence.
///
/// Mini-app JavaScript can call:
///   HostStorage.getItem(key)        -> any JSON value (object/array/number/string/bool) | null
///   HostStorage.setItem(key, value) -> persists any JSON value across launches
///   HostStorage.removeItem(key)
///   HostStorage.clear()
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
            controller.addUserScript(WKUserScript(source: consoleCaptureScript,
                                                   injectionTime: .atDocumentStart,
                                                   forMainFrameOnly: true))
            controller.add(context.coordinator, name: "log")
        }

        // React libraries first (UMD globals + Babel transpiler), then the
        // HostStorage bridge — all at document start, before the page's scripts.
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

        // Content-height reporting for inline (size-to-content) rendering.
        if sizeToContent {
            controller.addUserScript(WKUserScript(source: heightObserverScript,
                                                   injectionTime: .atDocumentEnd,
                                                   forMainFrameOnly: true))
            controller.add(context.coordinator, name: "hostHeight")
        }

        let config = WKWebViewConfiguration()
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
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

    /// JS injected before the page loads: seeds saved data and exposes `HostStorage`.
    private var bootstrapScript: String {
        let seed = initialData.isEmpty ? "{}" : initialData
        return """
        window.__INITIAL_DATA__ = \(seed);
        window.HostStorage = (function () {
            var data = window.__INITIAL_DATA__ || {};
            function send(msg) { window.webkit.messageHandlers.storage.postMessage(msg); }
            return {
                getItem: function (k) {
                    return Object.prototype.hasOwnProperty.call(data, k) ? data[k] : null;
                },
                setItem: function (k, v) { data[k] = v; send({ op: "set", key: k, value: v }); },
                removeItem: function (k) { delete data[k]; send({ op: "remove", key: k }); },
                clear: function () { data = {}; send({ op: "clear" }); }
            };
        })();
        """
    }

    /// JS injected at document start: routes `console.*`, uncaught errors, and
    /// unhandled promise rejections to the host so they can be shown in a console.
    private var consoleCaptureScript: String {
        """
        (function () {
            function post(level, args) {
                try {
                    var parts = Array.prototype.map.call(args, function (a) {
                        if (a instanceof Error) return (a.stack || (a.name + ": " + a.message));
                        if (typeof a === "object" && a !== null) {
                            try { return JSON.stringify(a); } catch (e) { return String(a); }
                        }
                        return String(a);
                    });
                    window.webkit.messageHandlers.log.postMessage({ level: level, message: parts.join(" ") });
                } catch (e) { /* never let logging break the app */ }
            }
            ["log", "info", "debug", "warn", "error"].forEach(function (name) {
                var original = console[name] ? console[name].bind(console) : null;
                console[name] = function () {
                    post(name === "warn" ? "warning" : name, arguments);
                    if (original) original.apply(console, arguments);
                };
            });
            window.addEventListener("error", function (e) {
                // Same-origin loads expose the real Error, including its stack.
                if (e.error && e.error.stack) { post("error", [e.error.stack]); return; }
                var where = e.filename ? (" (" + e.filename + ":" + e.lineno + ":" + e.colno + ")") : "";
                post("error", [(e.message || "Script error") + where]);
            });
            window.addEventListener("unhandledrejection", function (e) {
                var reason = e.reason && e.reason.message ? e.reason.message : e.reason;
                post("error", ["Unhandled promise rejection: " + reason]);
            });
        })();
        """
    }

    /// JS injected after the document loads: reports the body's content height
    /// to the host whenever it changes, so the native view can size to fit.
    private var heightObserverScript: String {
        """
        (function () {
            function report() {
                var h = Math.ceil(document.body ? document.body.scrollHeight
                                                : document.documentElement.scrollHeight);
                window.webkit.messageHandlers.hostHeight.postMessage(h);
            }
            window.addEventListener("load", report);
            if (document.body && window.ResizeObserver) {
                new ResizeObserver(report).observe(document.body);
            }
            report();
        })();
        """
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
        private var store: [String: Any]
        private let onPersist: (String) -> Void
        private let onHeightChange: ((CGFloat) -> Void)?
        private let onLog: ((MiniAppLogEntry) -> Void)?
        var lastHTML: String = ""

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
    }
}
