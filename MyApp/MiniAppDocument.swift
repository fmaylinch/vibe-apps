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
///   * **React** — write a component named `App` (plus optional `<style>`
///     blocks). The host hoists the styles into `<head>` and auto-mounts
///     `<App/>` unless the source calls `createRoot` itself.
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

    /// Wraps a React fragment: hoists any `<style>` blocks into `<head>`, drops
    /// the remaining JSX into a Babel script, and auto-mounts `<App/>` unless
    /// the author already calls `createRoot`.
    private static func wrapReact(_ fragment: String) -> String {
        let (styles, code) = extractStyles(fragment)
        let mount = code.contains("createRoot")
            ? ""
            : "\n\nReactDOM.createRoot(document.getElementById(\"root\")).render(<App />);"
        return """
        <!doctype html>
        <html>
        <head>
        \(head)
        \(styles)
        </head>
        <body>
        <div id="root"></div>
        <script type="text/babel">
        \(code)\(mount)
        </script>
        </body>
        </html>
        """
    }

    /// Splits `<style>...</style>` blocks out of a fragment so they can live in
    /// `<head>` rather than inside a script. Returns the joined style tags and
    /// the fragment with those tags removed.
    private static func extractStyles(_ source: String) -> (styles: String, code: String) {
        guard let regex = try? NSRegularExpression(
            pattern: "<style[^>]*>.*?</style>",
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return ("", source)
        }
        let range = NSRange(source.startIndex..., in: source)
        let matches = regex.matches(in: source, range: range)
        guard !matches.isEmpty else { return ("", source) }

        let styles = matches.compactMap { Range($0.range, in: source).map { String(source[$0]) } }
        let code = regex.stringByReplacingMatches(in: source, range: range, withTemplate: "")
        return (styles.joined(separator: "\n"),
                code.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
