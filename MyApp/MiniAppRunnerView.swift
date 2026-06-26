import SwiftUI

/// Runs a mini-app by rendering its source in a web view, wiring up the
/// persistent storage bridge, and offering an Edit shortcut.
///
/// A debug console (capturing `console.*` output and runtime errors) is always
/// available via the toolbar. When `startWithConsole` is true — e.g. when the
/// view is presented from the "Run with Console" menu item — the console starts
/// open and a Done button is shown to dismiss the modally-presented runner.
struct MiniAppRunnerView: View {
    @Bindable var app: MiniApp
    /// Whether to open the debug console immediately and show a Done button.
    var startWithConsole: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false
    @State private var showConsole = false
    @State private var logs: [MiniAppLogEntry] = []
    /// Whether the console has already auto-opened for an error, so a noisy app
    /// doesn't keep reopening it after the user closes it.
    @State private var didAutoOpenForError = false

    /// How many captured entries are errors — used to flag the console button.
    private var errorCount: Int {
        logs.reduce(0) { $0 + ($1.level == .error ? 1 : 0) }
    }

    var body: some View {
        MiniAppWebView(
            source: app.source,
            initialData: app.storageJSON,
            injectReact: app.framework == MiniAppFramework.react.rawValue,
            onPersist: { json in app.storageJSON = json },
            onLog: { entry in append(entry) },
            useDevelopmentRuntime: startWithConsole
        )
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(app.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom) {
            if showConsole {
                DebugConsoleView(logs: logs, onClear: { logs.removeAll() })
                    .frame(height: 240)
                    .transition(.move(edge: .bottom))
            }
        }
        .toolbar {
            if startWithConsole {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation { showConsole.toggle() }
                } label: {
                    Label("Console", systemImage: showConsole ? "ladybug.fill" : "ladybug")
                }
                .tint(errorCount > 0 ? .red : nil)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showEditor = true } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
        .onAppear {
            if startWithConsole { showConsole = true }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                MiniAppEditorView(app: app)
            }
        }
    }

    /// Appends a captured log entry, keeping only the most recent 500 so a noisy
    /// mini-app can't grow the buffer without bound.
    private func append(_ entry: MiniAppLogEntry) {
        logs.append(entry)
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
        // Surface the console automatically the first time something fails, so a
        // broken mini-app explains itself without the user hunting for it.
        if entry.level == .error, !showConsole, !didAutoOpenForError {
            didAutoOpenForError = true
            withAnimation { showConsole = true }
        }
    }
}
