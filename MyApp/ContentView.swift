import SwiftUI
import SwiftData

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
                createMiniApp(name: "React Counter", icon: "⚛️",
                              framework: .react, source: MiniAppTemplate.reactCounter)
            } label: {
                Label("React (JSX)", systemImage: "atom")
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
        .frame(height: frameHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
