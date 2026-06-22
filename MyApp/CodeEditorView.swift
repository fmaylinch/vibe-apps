import SwiftUI
import Runestone
import TreeSitterJavaScriptRunestone

/// A SwiftUI wrapper around Runestone's `TextView`, configured for editing a
/// mini-app's JavaScript/JSX source with syntax highlighting and line numbers.
///
/// Runestone is a UIKit component, so this bridges it via `UIViewRepresentable`.
/// The JavaScript tree-sitter grammar also covers JSX, so React mini-apps are
/// highlighted correctly.
struct CodeEditorView: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> TextView {
        let textView = TextView()
        textView.editorDelegate = context.coordinator
        textView.backgroundColor = .secondarySystemBackground
        textView.showLineNumbers = true
        textView.lineSelectionDisplayType = .line
        textView.isLineWrappingEnabled = false
        textView.alwaysBounceVertical = true

        // Code editing should never autocorrect, autocapitalize or smart-substitute.
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.spellCheckingType = .no

        let state = TextViewState(text: text, theme: CodeEditorTheme(), language: .javaScript)
        textView.setState(state)
        return textView
    }

    func updateUIView(_ textView: TextView, context: Context) {
        // Only push external changes; typing already flows back via the delegate,
        // so this guard avoids clobbering the caret on every keystroke.
        if textView.text != text {
            textView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, TextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: TextView) {
            text.wrappedValue = textView.text
        }
    }
}

/// A syntax theme for the mini-app code editor, built on the system semantic
/// colors so it adapts to light and dark mode.
final class CodeEditorTheme: Runestone.Theme {
    let font: UIFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
    let textColor: UIColor = .label

    let gutterBackgroundColor: UIColor = .secondarySystemBackground
    let gutterHairlineColor: UIColor = .separator

    let lineNumberColor: UIColor = .tertiaryLabel
    let lineNumberFont: UIFont = .monospacedSystemFont(ofSize: 12, weight: .regular)

    let selectedLineBackgroundColor: UIColor = .tertiarySystemBackground
    let selectedLinesLineNumberColor: UIColor = .label
    let selectedLinesGutterBackgroundColor: UIColor = .tertiarySystemBackground

    let invisibleCharactersColor: UIColor = .quaternaryLabel

    let pageGuideHairlineColor: UIColor = .separator
    let pageGuideBackgroundColor: UIColor = .secondarySystemBackground

    let markedTextBackgroundColor: UIColor = .systemFill

    /// Maps tree-sitter highlight capture names to colors. Matching on the name
    /// prefix keeps this robust across grammar capture variations (e.g.
    /// `function.method`, `variable.builtin`).
    func textColor(for highlightName: String) -> UIColor? {
        func matches(_ prefixes: String...) -> Bool {
            prefixes.contains { highlightName.hasPrefix($0) }
        }

        if matches("comment") { return .systemGreen }
        if matches("keyword", "operator") { return .systemPink }
        if matches("string") { return .systemRed }
        if matches("number", "constant") { return .systemOrange }
        if matches("variable.builtin") { return .systemTeal }
        if matches("function") { return .systemBlue }
        if matches("type", "constructor") { return .systemPurple }
        if matches("property", "attribute") { return .systemIndigo }
        if matches("tag") { return .systemBlue }
        if matches("punctuation") { return .secondaryLabel }
        return nil
    }

    func fontTraits(for highlightName: String) -> FontTraits {
        highlightName.hasPrefix("keyword") ? .bold : []
    }
}
