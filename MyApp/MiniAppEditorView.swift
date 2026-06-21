import SwiftUI
import SwiftData

/// Edit a mini-app's metadata, runtime, and its HTML/CSS/JavaScript source.
struct MiniAppEditorView: View {
    @Bindable var app: MiniApp
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
        .navigationTitle("Edit Mini App")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
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
