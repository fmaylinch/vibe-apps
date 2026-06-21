import SwiftUI
import SwiftData

/// Edit a mini-app's metadata, runtime, and its HTML/CSS/JavaScript source.
///
/// When `isNew` is `true` the mini-app has not yet been inserted into the model
/// context — it only becomes persisted when the user taps **Save**, so tapping
/// **Cancel** discards it entirely.
struct MiniAppEditorView: View {
    @Bindable var app: MiniApp
    /// Whether `app` is a brand-new draft awaiting its first save.
    var isNew: Bool = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Binds the model's string-backed framework to the typed enum for the Picker.
    private var frameworkSelection: Binding<MiniAppFramework> {
        Binding(
            get: { MiniAppFramework(rawValue: app.framework) ?? .vanilla },
            set: { app.framework = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Details") {
                TextField("Name", text: $app.name)
                TextField("Icon (emoji)", text: $app.icon)
                Picker("Runtime", selection: frameworkSelection) {
                    ForEach(MiniAppFramework.allCases) { framework in
                        Text(framework.displayName).tag(framework)
                    }
                }
            }
            Section("Source") {
                TextEditor(text: $app.source)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 280)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            Section {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(isNew ? "New Mini App" : "Edit Mini App")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if isNew {
                        context.insert(app)
                    }
                    app.updatedAt = .now
                    dismiss()
                }
            }
        }
    }

    private var footnote: String {
        let storage = "Persist data with HostStorage.getItem(key) / HostStorage.setItem(key, value)."
        switch MiniAppFramework(rawValue: app.framework) ?? .vanilla {
        case .vanilla:
            return storage
        case .react:
            return storage + " React, ReactDOM and Babel are available — write JSX inside a <script type=\"text/babel\"> tag."
        }
    }
}
