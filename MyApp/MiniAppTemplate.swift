import Foundation

/// Starter bundles handed to brand-new mini-apps.
///
/// The actual example source lives in standalone files under `Examples/` so it
/// is convenient to view and edit (`.html` for vanilla, `.jsx` for React),
/// instead of being buried in Swift string literals. Each file uses the same
/// metadata and storage format accepted by Import App, and is decoded through
/// that path so starter metadata cannot drift from its source file.
enum MiniAppTemplate {
    /// Plain HTML/CSS/JS To-do List backed by the async `db` API. Just body
    /// markup, a `<style>` block, and a `<script>` — the document shell is added
    /// by the host.
    static var todosVanilla: MiniAppBundle { load("todos-vanilla", "html") }

    /// React + JSX To-do List backed by the `db` collection API. Shows the
    /// firebase-like flow — `await`ed list/create/update/remove plus filtering,
    /// sorting, pagination, and `count()` — in an auto-mounted `App` component.
    static var todosReact: MiniAppBundle { load("todos-react", "jsx") }

    /// Loads and imports a bundled example. A missing or malformed example is a
    /// packaging bug rather than a recoverable runtime condition.
    private static func load(_ name: String, _ ext: String) -> MiniAppBundle {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let data = try? Data(contentsOf: url),
              let bundle = try? MiniAppExportCoder.decodeBundle(data) else {
            preconditionFailure("Missing or invalid bundled example resource: \(name).\(ext)")
        }
        return bundle
    }
}
