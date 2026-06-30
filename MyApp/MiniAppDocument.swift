import Foundation

/// Builds the full HTML document that actually runs in the web view from a
/// mini-app's source.
///
/// Authors no longer have to write the repetitive scaffold (doctype, `<head>`,
/// viewport meta, base CSS) or — for React — the `#root` element and the
/// `ReactDOM.createRoot(...).render(<App/>)` mount line. They write just the
/// interesting part and the host wraps it:
///
///   * **Vanilla** — write body markup, `<style>`, and `<script>` directly.
///   * **React** — write a component named `App`, with any `<style>` element
///     inside its returned JSX. The host auto-mounts `<App/>` unless the source
///     calls `createRoot` itself.
///
/// A source that is already a complete HTML document (it contains `<!doctype`
/// or `<html`) is passed through untouched, so full control is still possible.
enum MiniAppDocument {
    /// Base CSS shared by every wrapped fragment. Authors can override any of
    /// it with their own `<style>` block.
    private static let baseCSS = """
      :root { color-scheme: light dark; }
      body { font-family: -apple-system, system-ui, sans-serif; margin: 0; padding: 16px; }
      h1 { font-size: 1.4rem; margin: 0 0 12px; }
    """

    /// Returns a complete HTML document for `source`, wrapping it in the
    /// standard scaffold when it isn't already a full document.
    static func html(for source: String, react: Bool) -> String {
        guard !isFullDocument(source) else { return source }
        return react ? wrapReact(source) : wrapVanilla(source)
    }

    /// True when the source already provides its own document shell.
    private static func isFullDocument(_ source: String) -> Bool {
        let lower = source.lowercased()
        return lower.contains("<!doctype") || lower.contains("<html")
    }

    /// The shared `<head>` contents: charset, viewport, and base CSS.
    private static let head = """
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <style>
    \(baseCSS)
    </style>
    """

    /// Wraps a plain HTML/CSS/JS fragment as the document body.
    private static func wrapVanilla(_ fragment: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        \(head)
        </head>
        <body>
        \(fragment)
        </body>
        </html>
        """
    }

    /// Wraps a React fragment in a script and auto-mounts `<App/>` unless the
    /// author already calls `createRoot`.
    ///
    /// Rather than letting Babel auto-run a `type="text/babel"` script (whose
    /// failures surface only as an opaque "Script error."), the JSX is held in an
    /// inert `text/plain` block and transpiled + executed inside a `try/catch`, so
    /// Babel syntax errors and initial render errors are reported to the console
    /// with their full message and stack.
    private static func wrapReact(_ fragment: String) -> String {
        let mount = fragment.contains("createRoot")
            ? ""
            : "\n\nReactDOM.createRoot(document.getElementById(\"root\")).render(<App />);"
        return """
        <!doctype html>
        <html>
        <head>
        \(head)
        </head>
        <body>
        <div id="root"></div>
        <script type="text/plain" id="__miniapp_source__">
        \(fragment)\(mount)
        </script>
        <script>
        (function () {
            try {
                var src = document.getElementById("__miniapp_source__").textContent;
                var compiled = Babel.transform(src, { presets: ["react"] }).code;
                (0, eval)(compiled);
            } catch (err) {
                console.error(err && err.stack ? err.stack : String(err));
            }
        })();
        </script>
        </body>
        </html>
        """
    }
}
