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

    /// The natural-language request the user types for the AI assistant.
    @State private var aiPrompt = ""
    /// Which Foundation Models backend handles the request.
    @State private var aiBackend: AICodeService.Backend = .onDevice
    /// True while a generation request is in flight.
    @State private var isGenerating = false
    /// A user-facing error from the last generation attempt, shown in an alert.
    @State private var aiError: String?

    /// Binds the model's string-backed framework to the typed enum for the Picker.
    private var frameworkSelection: Binding<MiniAppFramework> {
        Binding(
            get: { MiniAppFramework(rawValue: app.framework) ?? .vanilla },
            set: { app.framework = $0.rawValue }
        )
    }

    /// Binds the optional inline max-height to an editable text field. An empty
    /// or non-positive value clears the cap (`nil` — grow to fit).
    private var maxHeightText: Binding<String> {
        Binding(
            get: { app.inlineMaxHeight.map { String(Int($0)) } ?? "" },
            set: { app.inlineMaxHeight = Double($0).flatMap { $0 > 0 ? $0 : nil } }
        )
    }

    /// Whether the Generate button can run — non-empty request and not already busy.
    private var canGenerate: Bool {
        !isGenerating && !aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                Toggle("Show inline in list", isOn: $app.isInline)
                if app.isInline {
                    TextField("Max height (points, optional)", text: maxHeightText)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
            }
            aiSection
            Section("Source") {
                CodeEditorView(text: $app.source)
                    .frame(minHeight: 280)
                    .listRowInsets(EdgeInsets())
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
        .alert("Couldn’t Generate Code",
               isPresented: Binding(get: { aiError != nil }, set: { if !$0 { aiError = nil } }),
               presenting: aiError) { _ in
            Button("OK", role: .cancel) { aiError = nil }
        } message: { message in
            Text(message)
        }
    }

    /// The AI assistant: describe what to build or change, pick a model, and let
    /// Foundation Models write the source. The result replaces the editor's source.
    @ViewBuilder
    private var aiSection: some View {
        Section {
            TextField("Describe the app to build, or the change to make…",
                      text: $aiPrompt, axis: .vertical)
                .lineLimit(2...5)
                .disabled(isGenerating)

            Picker("Model", selection: $aiBackend) {
                ForEach(AICodeService.Backend.allCases) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }
            .disabled(isGenerating)

            Button {
                Task { await generate() }
            } label: {
                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Generating…")
                    }
                } else {
                    Label("Generate Code", systemImage: "sparkles")
                }
            }
            .disabled(!canGenerate)
        } header: {
            Text("AI Assistant")
        } footer: {
            Text(aiBackend == .privateCloudCompute
                 ? "Runs a larger model on Apple's Private Cloud Compute. Requires a network connection and Apple Intelligence."
                 : "Runs Apple's on-device model. Private and works offline.")
        }
    }

    /// Sends the request to the selected model and, on success, replaces the
    /// source with the generated code.
    @MainActor
    private func generate() async {
        let request = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }

        if case .unavailable(let reason) = AICodeService.availability(for: aiBackend) {
            aiError = reason
            return
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            var latest = ""
            // Each element is the cumulative source so far — write it straight
            // into the editor so the code appears as the model types it.
            for try await partial in AICodeService.streamSource(
                request: request,
                currentSource: app.source,
                framework: MiniAppFramework(rawValue: app.framework) ?? .vanilla,
                backend: aiBackend) {
                latest = partial
                app.source = partial
            }

            guard !latest.isEmpty else {
                aiError = "The model didn't return any code. Try rephrasing your request."
                return
            }
            aiPrompt = ""
        } catch {
            aiError = error.localizedDescription
        }
    }

    private var footnote: String {
        let storage = "Persist data with HostStorage.getItem(key) / HostStorage.setItem(key, value) — values can be any JSON (objects, arrays, numbers)."
        switch MiniAppFramework(rawValue: app.framework) ?? .vanilla {
        case .vanilla:
            return storage + " No need for <html> or <head> — just write body markup, <style>, and <script>. (A full HTML document still works if you write one.)"
        case .react:
            return storage + " Just write an App component (and optional <style> blocks) — React is loaded and <App/> is mounted for you. No <html>, #root, or createRoot needed."
        }
    }
}
