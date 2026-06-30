import Foundation

/// Starter source handed to brand-new mini-apps.
///
/// The actual example source lives in standalone files under `Examples/` so it
/// is convenient to view and edit (`.html` for vanilla, `.jsx` for React),
/// instead of being buried in Swift string literals. They are bundled as
/// resources and loaded on demand here.
///
/// These are *fragments*, not full HTML documents: the host (`MiniAppDocument`)
/// wraps them in the standard scaffold — doctype, `<head>`, viewport meta, and
/// base CSS — so authors only write the interesting part. State persists via
/// the host's `HostStorage` bridge so it survives relaunch.
enum MiniAppTemplate {
    /// Plain HTML/CSS/JS To-do List. Just body markup, a `<style>` block, and a
    /// `<script>` — the document shell is added by the host.
    static var todoList: String { load("todo-list", "html") }

    /// React + JSX To-do List. Just an `App` component with inline style block.
    // The host wraps the source in a Babel script and auto-mounts
    /// `<App/>` (no `createRoot` boilerplate needed).
    static var reactTodoList: String { load("react-todo-list", "jsx") }

    /// React + JSX To-do List backed by the async `db` collection API instead of
    /// `HostStorage`. Shows the firebase-like flow: `await`ed list/create/update/
    /// remove calls that resolve once native has persisted each change.
    static var reactTodoDb: String { load("react-todo-db", "jsx") }

    /// Loads a bundled example file's contents. The examples ship with the app,
    /// so a miss is a packaging bug rather than a runtime condition.
    private static func load(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("Missing bundled example resource: \(name).\(ext)")
            return ""
        }
        return source
    }
}
