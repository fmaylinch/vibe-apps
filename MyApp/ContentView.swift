import SwiftUI
import SwiftData

@main struct MyApp: App {
    let container: ModelContainer

    init() {
        container = MyApp.makeContainer()
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

/// The home screen: a grid of the user's mini-apps with full CRUD.
/// Tap a mini-app to run it; long-press (context menu) to edit or delete.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MiniApp.updatedAt, order: .reverse) private var miniApps: [MiniApp]

    @State private var editingApp: MiniApp?

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if miniApps.isEmpty {
                    emptyState
                } else {
                    grid
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

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(miniApps) { app in
                    NavigationLink(value: app) {
                        MiniAppCard(app: app)
                    }
                    .buttonStyle(.plain)
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
            .padding()
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

    private func createMiniApp(name: String, icon: String,
                               framework: MiniAppFramework, source: String) {
        let app = MiniApp(name: name, icon: icon, source: source, framework: framework.rawValue)
        context.insert(app)
        editingApp = app
    }

    private func delete(_ app: MiniApp) {
        context.delete(app)
    }
}

/// A single mini-app tile shown in the home grid.
struct MiniAppCard: View {
    let app: MiniApp

    var body: some View {
        VStack(spacing: 10) {
            Text(app.icon)
                .font(.system(size: 44))
                .frame(width: 80, height: 80)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
            Text(app.name)
                .font(.subheadline)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}
