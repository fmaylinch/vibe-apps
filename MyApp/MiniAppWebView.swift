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
///   HostStorage.getItem(key)        -> String | null
///   HostStorage.setItem(key, value) -> persists across launches
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

    /// The full HTML document that actually loads, composed from `source`.
    private var document: String {
        MiniAppDocument.html(for: source, react: injectReact)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(initialData: initialData, onPersist: onPersist, onHeightChange: onHeightChange)
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

        // React libraries first (UMD globals + Babel transpiler), then the
        // HostStorage bridge — all at document start, before the page's scripts.
        if injectReact {
            for source in Self.reactRuntimeScripts() {
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
        webView.loadHTMLString(document, baseURL: nil)
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
        webView.loadHTMLString(document, baseURL: nil)
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
                setItem: function (k, v) { data[k] = String(v); send({ op: "set", key: k, value: String(v) }); },
                removeItem: function (k) { delete data[k]; send({ op: "remove", key: k }); },
                clear: function () { data = {}; send({ op: "clear" }); }
            };
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
    /// JS source strings, in load order. Missing files are skipped silently.
    private static func reactRuntimeScripts() -> [String] {
        let resources = [
            "react.production.min",
            "react-dom.production.min",
            "babel.min"
        ]
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
        private var store: [String: String]
        private let onPersist: (String) -> Void
        private let onHeightChange: ((CGFloat) -> Void)?
        var lastHTML: String = ""

        init(initialData: String,
             onPersist: @escaping (String) -> Void,
             onHeightChange: ((CGFloat) -> Void)?) {
            self.onPersist = onPersist
            self.onHeightChange = onHeightChange
            if let data = initialData.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
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

            guard let body = message.body as? [String: Any],
                  let op = body["op"] as? String else { return }
            switch op {
            case "set":
                if let key = body["key"] as? String, let value = body["value"] as? String {
                    store[key] = value
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
