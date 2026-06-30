import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main struct VibeAppsApp: App {
    let container: ModelContainer

    init() {
        container = VibeAppsApp.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(container)
    }

    /// Builds the model container with iCloud (CloudKit) sync enabled, falling
    /// back to local-only storage when CloudKit isn't available — e.g. no signed-in
    /// iCloud account, a missing/unprovisioned entitlement, or an unsigned build.
    /// The fallback guarantees the app always launches.
    private static func makeContainer() -> ModelContainer {
        let cloudConfiguration = ModelConfiguration(cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: MiniApp.self, configurations: cloudConfiguration) {
            return container
        }

        let localConfiguration = ModelConfiguration(cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: MiniApp.self, configurations: localConfiguration)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}

/// The home screen: a vertical list of the user's mini-apps with full CRUD.
/// Tap a mini-app to run it; mini-apps marked inline render directly in the
/// list. Long-press (context menu) to edit or delete.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MiniApp.updatedAt, order: .reverse) private var miniApps: [MiniApp]

    /// An existing mini-app being edited.
    @State private var editingApp: MiniApp?
    /// A brand-new draft awaiting its first save. It isn't inserted into the
    /// model context until the user taps Save in the editor.
    @State private var newApp: MiniApp?
    /// A mini-app to run modally with the debug console open.
    @State private var debugApp: MiniApp?
    /// Controls the "Import App" file importer (toolbar action → new app).
    @State private var isImportingApp = false
    /// The mini-app an "Import Data" action targets. Non-nil both records the
    /// target and presents the data file importer.
    @State private var dataImportTarget: MiniApp?
    /// A user-facing import failure message, shown in an alert.
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Group {
                if miniApps.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Mini Apps")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    newMiniAppMenu {
                        Label("New Mini App", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { isImportingApp = true } label: {
                            Label("Import from File…", systemImage: "folder")
                        }
                        // PasteButton reads the pasteboard with the user's tap as
                        // consent, avoiding the silent-nil privacy gate that a
                        // plain button hitting UIPasteboard.general would hit.
                        PasteButton(payloadType: String.self) { strings in
                            importApp(fromPasted: strings)
                        }
                    } label: {
                        Label("Import App", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(isPresented: $isImportingApp,
                          allowedContentTypes: [.item]) { result in
                handleImportApp(result)
            }
            .fileImporter(isPresented: Binding(
                            get: { dataImportTarget != nil },
                            set: { if !$0 { dataImportTarget = nil } }),
                          allowedContentTypes: [.item]) { [target = dataImportTarget] result in
                handleImportData(result, into: target)
            }
            .alert("Import Failed",
                   isPresented: Binding(get: { importError != nil },
                                        set: { if !$0 { importError = nil } }),
                   presenting: importError) { _ in
                Button("OK", role: .cancel) { importError = nil }
            } message: { message in
                Text(message)
            }
            // Upgrade any legacy double-encoded storage to the native-JSON
            // format before a mini-app's web view seeds from it. Re-runs as
            // CloudKit-synced rows arrive; each app migrates at most once.
            .task(id: miniApps.map(\.persistentModelID)) {
                for app in miniApps { app.migrateStorageIfNeeded() }
            }
            .navigationDestination(for: MiniApp.self) { app in
                MiniAppRunnerView(app: app)
            }
            .sheet(item: $editingApp) { app in
                NavigationStack {
                    MiniAppEditorView(app: app)
                }
            }
            .sheet(item: $newApp) { app in
                NavigationStack {
                    MiniAppEditorView(app: app, isNew: true)
                }
            }
            .sheet(item: $debugApp) { app in
                NavigationStack {
                    MiniAppRunnerView(app: app, startWithConsole: true)
                }
            }
        }
    }

    /// A menu offering one starter per supported framework.
    private func newMiniAppMenu<TriggerLabel: View>(@ViewBuilder label: () -> TriggerLabel) -> some View {
        Menu {
            Button {
                createMiniApp(name: "Todo List", icon: "✅",
                              framework: .vanilla, source: MiniAppTemplate.todoList)
            } label: {
                Label("HTML / JavaScript", systemImage: "curlybraces")
            }
            Button {
                createMiniApp(name: "React Todo List", icon: "⚛️",
                              framework: .react, source: MiniAppTemplate.reactTodoList)
            } label: {
                Label("React (JSX)", systemImage: "atom")
            }
            Button {
                createMiniApp(name: "React Todo (db)", icon: "🗄️",
                              framework: .react, source: MiniAppTemplate.reactTodoDb)
            } label: {
                Label("React (JSX) + db", systemImage: "tray.full")
            }
        } label: {
            label()
        }
    }

    private var list: some View {
        List {
            ForEach(miniApps) { app in
                row(for: app)
                    .contextMenu {
                        Button { editingApp = app } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button { debugApp = app } label: {
                            Label("Run with Console", systemImage: "ladybug")
                        }

                        Divider()

                        if let file = try? MiniAppExportFile.appBundle(for: app) {
                            ShareLink(item: file, preview: SharePreview(file.filename)) {
                                Label("Export App", systemImage: "square.and.arrow.up")
                            }
                        }
                        if let file = try? MiniAppExportFile.dataExport(for: app) {
                            ShareLink(item: file, preview: SharePreview(file.filename)) {
                                Label("Export Data", systemImage: "square.and.arrow.up.on.square")
                            }
                        }
                        Menu {
                            Button { dataImportTarget = app } label: {
                                Label("From File…", systemImage: "folder")
                            }
                            // Must be a PasteButton, not a plain Button reading
                            // UIPasteboard: the user's tap is the pasteboard
                            // access consent, so it avoids the privacy gate that
                            // makes a programmatic read silently return nil.
                            PasteButton(payloadType: String.self) { strings in
                                importData(fromPasted: strings, into: app)
                            }
                        } label: {
                            Label("Import Data into this App", systemImage: "square.and.arrow.down")
                        }

                        Divider()

                        Button(role: .destructive) { delete(app) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }

    /// A single list entry. Inline mini-apps render their UI directly beneath a
    /// non-interactive header; the rest are a plain row that opens the runner on tap.
    @ViewBuilder
    private func row(for app: MiniApp) -> some View {
        if app.isInline {
            VStack(alignment: .leading, spacing: 10) {
                MiniAppRow(app: app)
                InlineMiniAppView(app: app)
            }
            .padding(.vertical, 4)
        } else {
            NavigationLink(value: app) {
                MiniAppRow(app: app)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Mini Apps", systemImage: "square.grid.2x2")
        } description: {
            Text("Create your first mini-app — a small HTML/JavaScript or React program you write and run right here.")
        } actions: {
            newMiniAppMenu {
                Text("Create Mini App")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Builds a draft mini-app and presents the editor. The draft is *not*
    /// inserted into the model context here — that happens only when the user
    /// taps Save, so dismissing the editor discards it.
    private func createMiniApp(name: String, icon: String,
                               framework: MiniAppFramework, source: String) {
        newApp = MiniApp(name: name, icon: icon, source: source, framework: framework.rawValue)
    }

    private func delete(_ app: MiniApp) {
        context.delete(app)
    }

    /// Imports a full app bundle as a brand-new mini-app.
    private func handleImportApp(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            reportImportFailure(error)
        case .success(let url):
            do {
                let data = try readSecurityScoped(url)
                let bundle = try MiniAppExportCoder.decodeBundle(data)
                context.insert(bundle.makeMiniApp())
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    /// Imports a data-only export, replacing `target`'s storage.
    private func handleImportData(_ result: Result<URL, Error>, into target: MiniApp?) {
        guard let target else { return }
        switch result {
        case .failure(let error):
            reportImportFailure(error)
        case .success(let url):
            do {
                let data = try readSecurityScoped(url)
                let export = try MiniAppExportCoder.decodeDataExport(data)
                target.storageJSON = export.resolvedStorageJSON
                target.storageFormatVersion = MiniApp.currentStorageFormatVersion
                target.updatedAt = .now
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    /// Imports a full app bundle pasted via a `PasteButton`.
    private func importApp(fromPasted strings: [String]) {
        guard let data = pastedExportData(strings) else { return }
        do {
            let bundle = try MiniAppExportCoder.decodeBundle(data)
            context.insert(bundle.makeMiniApp())
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Imports a data-only export pasted via a `PasteButton`,
    /// replacing `target`'s storage.
    private func importData(fromPasted strings: [String], into target: MiniApp) {
        guard let data = pastedExportData(strings) else { return }
        do {
            let export = try MiniAppExportCoder.decodeDataExport(data)
            target.storageJSON = export.resolvedStorageJSON
            target.storageFormatVersion = MiniApp.currentStorageFormatVersion
            target.updatedAt = .now
        } catch {
            importError = error.localizedDescription
        }
    }

    /// The first non-empty pasted string as UTF-8 data, or `nil` (surfacing an
    /// error) when the pasteboard yielded nothing usable.
    private func pastedExportData(_ strings: [String]) -> Data? {
        guard let text = strings.first(where: { !$0.isEmpty }),
              let data = text.data(using: .utf8) else {
            importError = "The clipboard doesn’t contain a Mini App to import. Copy an exported app or its data first."
            return nil
        }
        return data
    }

    /// Surfaces an importer error, but stays silent when the user just cancelled.
    private func reportImportFailure(_ error: Error) {
        if (error as NSError).code != NSUserCancelledError {
            importError = error.localizedDescription
        }
    }

    /// Reads a file handed to us by `.fileImporter`, honoring security-scoped
    /// access required for files outside the app sandbox.
    private func readSecurityScoped(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw MiniAppImportError.unreadable
        }
    }
}

/// A single mini-app entry shown in the home list: emoji icon plus name.
struct MiniAppRow: View {
    let app: MiniApp

    var body: some View {
        HStack(spacing: 14) {
            Text(app.icon)
                .font(.system(size: 25))
                .frame(width: 40, height: 40)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            Text(app.name)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}

/// Renders an inline mini-app sized to its content height so it occupies only
/// as much vertical space as the mini-app actually needs.
private struct InlineMiniAppView: View {
    @Bindable var app: MiniApp
    /// The mini-app's measured content height, reported by the web view.
    @State private var contentHeight: CGFloat = 1

    /// The author-specified height cap, if any (positive values only).
    private var maxHeight: CGFloat? {
        guard let cap = app.inlineMaxHeight, cap > 0 else { return nil }
        return CGFloat(cap)
    }

    /// True when the content is taller than the cap, so the view scrolls within it.
    private var isCapped: Bool {
        guard let maxHeight else { return false }
        return contentHeight > maxHeight
    }

    /// The height the row actually occupies: the content height, clamped to the cap.
    private var frameHeight: CGFloat {
        guard let maxHeight else { return contentHeight }
        return min(contentHeight, maxHeight)
    }

    var body: some View {
        MiniAppWebView(
            source: app.source,
            initialData: app.storageJSON,
            injectReact: app.framework == MiniAppFramework.react.rawValue,
            onPersist: { json in app.storageJSON = json },
            sizeToContent: true,
            onHeightChange: { newHeight in
                if abs(newHeight - contentHeight) > 0.5 { contentHeight = newHeight }
            },
            scrollEnabled: isCapped
        )
        // The web view seeds its storage once at creation, so an external data
        // change (import, or an edit in the editor) wouldn't otherwise show up
        // in a live inline mini-app until the view is rebuilt. Keying on
        // `updatedAt` rebuilds it then — but NOT on the web view's own
        // `setItem` persistence, which updates `storageJSON` without touching
        // `updatedAt`, so ordinary interaction keeps its state.
        .id(app.updatedAt)
        .frame(height: frameHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
