import Foundation
import FoundationModels

/// Generates and modifies a mini-app's source code with Apple's Foundation Models.
///
/// Two backends are offered and selectable per request:
///
///   * ``Backend/onDevice`` — the on-device `SystemLanguageModel`. Free, private,
///     and works offline, but it's a small model that's weaker at writing larger
///     programs.
///   * ``Backend/privateCloudCompute`` — `PrivateCloudComputeLanguageModel`, a
///     larger server-side model that runs on Apple's Private Cloud Compute with
///     the same privacy guarantees as on-device. Stronger at code, but it needs a
///     network connection (and a provisioned PCC entitlement to build against).
///
/// All output is a *fragment* in the same format the templates use: no `<html>`
/// or `<head>`, just body markup / a React `App` component, so it can be dropped
/// straight into the editor and wrapped by `MiniAppDocument`.
enum AICodeService {

    /// Which Foundation Models backend should run a request.
    enum Backend: String, CaseIterable, Identifiable {
        /// The on-device `SystemLanguageModel`.
        case onDevice
        /// The larger server-side model on Apple's Private Cloud Compute.
        case privateCloudCompute

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .onDevice: return "On-device"
            case .privateCloudCompute: return "Private Cloud Compute"
            }
        }
    }

    /// Whether a backend can be used right now, carrying a human-readable reason
    /// when it can't.
    enum Availability: Equatable {
        case available
        case unavailable(reason: String)

        var isAvailable: Bool { self == .available }
    }

    /// Reports whether the given backend is ready to generate code, so the UI can
    /// explain why a request can't run before the user waits for it.
    static func availability(for backend: Backend) -> Availability {
        switch backend {
        case .onDevice:
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable(reason: "This device doesn't support Apple Intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable(reason: "Turn on Apple Intelligence in Settings to use AI.")
            case .unavailable(.modelNotReady):
                return .unavailable(reason: "The on-device model isn't ready yet — it may still be downloading. Try again shortly.")
            case .unavailable:
                return .unavailable(reason: "The on-device model is currently unavailable.")
            }
        case .privateCloudCompute:
            // The Private Cloud Compute backend is only offered by Foundation Models
            // on iOS 27 and later; on iOS 26 only the on-device model exists.
            guard #available(iOS 27, *) else {
                return .unavailable(reason: "Private Cloud Compute requires iOS 27 or later. Use the on-device model instead.")
            }
            switch PrivateCloudComputeLanguageModel().availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable(reason: "This device doesn't support Apple Intelligence.")
            case .unavailable(.systemNotReady):
                return .unavailable(reason: "Apple Intelligence is still setting up. Try again later.")
            case .unavailable:
                return .unavailable(reason: "Private Cloud Compute is currently unavailable.")
            }
        }
    }

    /// Asks the chosen model to write or modify a mini-app's source so it satisfies
    /// `request`. `currentSource` is the code being edited (empty for a new app).
    ///
    /// Streams the source as it's generated: each element is the cumulative
    /// fragment so far (already sanitized), so the caller can write it straight
    /// into the editor for a live typing effect. The final element is the
    /// complete result.
    static func streamSource(request: String,
                             currentSource: String,
                             framework: MiniAppFramework,
                             backend: Backend) -> AsyncThrowingStream<String, Error> {
        let session = makeSession(backend: backend, framework: framework)
        let prompt = makePrompt(request: request, currentSource: currentSource)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await snapshot in session.streamResponse(to: prompt) {
                        continuation.yield(sanitize(snapshot.content))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Session & prompt construction

    /// Builds a single-turn session against the chosen backend, primed with
    /// instructions for the mini-app authoring format.
    private static func makeSession(backend: Backend, framework: MiniAppFramework) -> LanguageModelSession {
        let text = instructions(for: framework)
        switch backend {
        case .onDevice:
            return LanguageModelSession(instructions: text)
        case .privateCloudCompute:
            // Guarded so the app still builds and runs on iOS 26; callers gate on
            // `availability(for:)`, which reports PCC as unavailable there.
            if #available(iOS 27, *) {
                return LanguageModelSession(model: PrivateCloudComputeLanguageModel()) { text }
            } else {
                return LanguageModelSession(instructions: text)
            }
        }
    }

    /// System instructions describing the exact fragment format the host expects.
    /// Kept short and direct — the on-device model has a small context window.
    private static func instructions(for framework: MiniAppFramework) -> String {
        let common = """
        You write small, self-contained mini-apps that run in a web view. \
        Output ONLY the source code — no Markdown fences, no prose, no explanation of your changes. \
        Do NOT include <html>, <head>, or <body> tags; the host adds those for you. \
        Persist data with HostStorage.getItem(key) and HostStorage.setItem(key, value); values can be any JSON (objects, arrays, numbers, strings) — no JSON.parse/stringify needed.
        """
        switch framework {
        case .vanilla:
            return common + " " + """
            Write plain HTML body markup plus optional <style> and <script> blocks using vanilla JavaScript. \
            No frameworks or libraries are available.
            """
        case .react:
            return common + " " + """
            Write React with JSX. Define a component named App — it is mounted for you, so never call createRoot.
            NEVER use import or export statements: React and ReactDOM are already global.
            Read hooks off the global React, e.g. const { useState } = React.
            Use HostStorage with any key to load/save persistent data.
            Put any CSS in a <style> block. Follow this exact shape:

            const { useState } = React;
            const KEY = "items";

            function App() {
              const [items, setItems] = useState(HostStorage.getItem(KEY) || []);
              function save(next) { setItems(next); HostStorage.setItem(KEY, next); }
              return (
                <div>
                  {items.map((it, i) => <div key={i}>{it}</div>)}
                  <button onClick={() => save([...items, "new"])}>Add</button>
                </div>
              );
            }

            <style> button { padding: 8px 12px; } </style>
            """
        }
    }

    /// Wraps the user's request with the current source (when editing) so the model
    /// modifies in place rather than starting over.
    private static func makePrompt(request: String, currentSource: String) -> String {
        let trimmed = currentSource.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Create a mini-app. \(request)"
        }
        return """
        Here is the current mini-app source:

        \(currentSource)

        Modify it as follows: \(request)

        Return the complete updated source.
        """
    }

    /// Strips a surrounding Markdown ``` fence the model may add despite the
    /// instructions, leaving clean source to drop into the editor.
    private static func sanitize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```") else { return text }

        // Drop the opening fence line, which may carry a language hint (```jsx).
        if let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        }
        // Drop the closing fence, if present.
        if let closing = text.range(of: "```", options: .backwards) {
            text = String(text[..<closing.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
