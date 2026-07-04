import Foundation

/// Starter bundles handed to brand-new mini-apps.
/// The source files live under `Examples/`.
enum MiniAppTemplate {
    static var todosVanilla: MiniAppBundle { load("todos-vanilla", "html") }
    static var todosReact: MiniAppBundle { load("todos-react", "jsx") }
    static var todosReactSimple: MiniAppBundle { load("todos-react-simple", "jsx") }
    static var googleMapsHtml: MiniAppBundle { load("google-maps", "html") }
    static var googleMapsJsx: MiniAppBundle { load("google-maps", "jsx") }

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
