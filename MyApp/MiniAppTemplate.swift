import Foundation

/// Starter bundles handed to brand-new mini-apps.
///
/// The actual example source lives in standalone files under `Examples/` so it
/// is convenient to view and edit (`.html` for vanilla, `.jsx` for React),
/// instead of being buried in Swift string literals. Each file uses the same
/// metadata and storage format accepted by Import App, and is decoded through
/// that path so starter metadata cannot drift from its source file.
enum MiniAppTemplate {
    /// Plain HTML/CSS/JS To-do List. Just body markup, a `<style>` block, and a
    /// `<script>` — the document shell is added by the host.
    static var todoList: MiniAppBundle { load("todo-list", "html") }

    /// React + JSX To-do List. Just an `App` component with inline style block.
    // The host wraps the source in a Babel script and auto-mounts
    /// `<App/>` (no `createRoot` boilerplate needed).
    static var reactTodoList: MiniAppBundle { load("react-todo-list", "jsx") }

    /// React + JSX To-do List backed by the async `db` collection API instead of
    /// `HostStorage`. Shows the firebase-like flow: `await`ed list/create/update/
    /// remove calls that resolve once native has persisted each change.
    static var reactTodoDb: MiniAppBundle { load("react-todo-db", "jsx") }

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
