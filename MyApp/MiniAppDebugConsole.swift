import SwiftUI

/// A single line captured from a running mini-app: a `console.*` call, an
/// uncaught error, or an unhandled promise rejection. Surfaced in
/// ``DebugConsoleView`` so authors can see why a mini-app misbehaves.
struct MiniAppLogEntry: Identifiable {
    enum Level: String {
        case log, info, debug, warning, error

        /// Maps a raw level string from JavaScript to a known level.
        init(rawLevel: String) {
            self = Level(rawValue: rawLevel) ?? .log
        }

        var symbol: String {
            switch self {
            case .log: return "text.alignleft"
            case .info: return "info.circle"
            case .debug: return "ant"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }

        var color: Color {
            switch self {
            case .log: return .gray
            case .info: return .blue
            case .debug: return .purple
            case .warning: return .orange
            case .error: return .red
            }
        }
    }

    let id = UUID()
    let level: Level
    let message: String
    let date: Date = .now
}

/// A collapsible console that lists the output and errors emitted by a running
/// mini-app, newest at the bottom. Shown beneath the web view in the runner.
struct DebugConsoleView: View {
    let logs: [MiniAppLogEntry]
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if logs.isEmpty {
                emptyState
            } else {
                logList
            }
        }
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Console", systemImage: "ladybug.fill")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if !logs.isEmpty {
                Text("\(logs.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Clear", action: onClear)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No output yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("console.log output and runtime errors from the mini-app appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(logs) { entry in
                        DebugLogRow(entry: entry)
                            .id(entry.id)
                        Divider().opacity(0.25)
                    }
                }
            }
            .onChange(of: logs.count) {
                guard let last = logs.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}

/// One row in the debug console: a level glyph plus the selectable message text.
private struct DebugLogRow: View {
    let entry: MiniAppLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.level.symbol)
                .foregroundStyle(entry.level.color)
                .font(.caption)
                .frame(width: 16)
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(entry.level == .error ? Color.red : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(entry.level == .error ? Color.red.opacity(0.08) : Color.clear)
    }
}
