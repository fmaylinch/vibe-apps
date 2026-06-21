import SwiftUI

/// Runs a mini-app by rendering its source in a web view, wiring up the
/// persistent storage bridge, and offering an Edit shortcut.
struct MiniAppRunnerView: View {
    @Bindable var app: MiniApp
    @State private var showEditor = false

    var body: some View {
        MiniAppWebView(
            html: app.source,
            initialData: app.storageJSON,
            injectReact: app.framework == MiniAppFramework.react.rawValue,
            onPersist: { json in app.storageJSON = json }
        )
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(app.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showEditor = true } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                MiniAppEditorView(app: app)
            }
        }
    }
}
