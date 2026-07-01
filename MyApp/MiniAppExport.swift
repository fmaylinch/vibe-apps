import SwiftUI
import UniformTypeIdentifiers

// MARK: - JSONValue

/// A fully `Codable` stand-in for arbitrary JSON, used to parse and serialize
/// a mini-app's runtime storage.
nonisolated enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// Parses a JSON string (such as an exported storage blob) into a `JSONValue`.
    /// Returns `nil` when the string isn't valid JSON.
    static func parse(_ string: String) -> JSONValue? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Serializes back to a compact JSON string (an exported storage blob).
    func compactString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Export models

/// Discriminates the two export file shapes so each importer can reject the
/// wrong file with a clear message.
enum MiniAppExportKind: String {
    /// Full bundle (code + data) — importing creates a new mini-app.
    case app
    /// Storage only — importing replaces an existing mini-app's data.
    case data
}

/// The full export of a mini-app: everything needed to recreate it.
nonisolated struct MiniAppBundle {
    var name: String
    var icon: String
    var framework: String
    var source: String
    /// The storage blob as a nested JSON object when parseable; otherwise the
    /// raw string is preserved in `storageRaw`. Its `__collections` map seeds the
    /// new app's `db` documents via `MiniApp.adoptCollections(from:in:)`.
    var storage: JSONValue?
    var storageRaw: String?
    var isInline: Bool
    var inlineMaxHeight: Double?

    /// The compact storage blob (`const STORAGE = …`) to seed the app's `db`
    /// documents from after it is inserted.
    var resolvedStorageJSON: String {
        if let storage, let string = storage.compactString() {
            return string
        }
        if let storageRaw { return storageRaw }
        return "{}"
    }

    /// Builds a new (uninserted) `MiniApp` from this bundle. `createdAt` /
    /// `updatedAt` default to now, so the import sorts to the top of the list.
    /// The caller must insert it, then seed `db` documents with
    /// `adoptCollections(from: resolvedStorageJSON, in:)`.
    func makeMiniApp() -> MiniApp {
        MiniApp(
            name: name,
            icon: icon.isEmpty ? "✨" : icon,
            source: source,
            framework: MiniAppFramework(rawValue: framework)?.rawValue
                ?? MiniAppFramework.vanilla.rawValue,
            isInline: isInline,
            inlineMaxHeight: inlineMaxHeight
        )
    }
}

/// The data-only export: just a mini-app's `db` storage blob.
nonisolated struct MiniAppDataExport {
    var storage: JSONValue?
    var storageRaw: String?

    /// The compact storage blob to reseed an app's `db` documents from.
    var resolvedStorageJSON: String {
        if let storage, let string = storage.compactString() {
            return string
        }
        if let storageRaw { return storageRaw }
        return "{}"
    }
}

// MARK: - Errors

enum MiniAppImportError: LocalizedError {
    case unreadable
    case missingMetadata
    case missingStorage
    case invalidStorage
    case wrongKind(expected: MiniAppExportKind, found: MiniAppExportKind)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "This file couldn’t be read."
        case .missingMetadata:
            return "This code file is missing its Mini App metadata. Add @name and @type to the comment at the beginning."
        case .missingStorage:
            return "This file doesn’t contain a const STORAGE value."
        case .invalidStorage:
            return "The const STORAGE value isn’t valid JSON."
        case .wrongKind(let expected, let found):
            switch (expected, found) {
            case (.app, .data):
                return "This is a Mini App data file. Use “Import Data into this App” from a mini-app’s menu instead."
            case (.data, .app):
                return "This is a full Mini App file. Use “Import App” to add it as a new app."
            default:
                return "This file is the wrong type for this action."
            }
        }
    }
}

// MARK: - Code-file encoding / decoding

enum MiniAppExportCoder {
    private static let storageMarker = "@miniapp-storage"

    /// Encodes a complete app as an editable HTML or JSX source file.
    static func encodeBundle(_ app: MiniApp) throws -> Data {
        let framework = MiniAppFramework(rawValue: app.framework) ?? .vanilla
        let storage = serializedStorage(app.storageJSONForExport())
        let metadata = metadataLines(
            for: app, framework: framework, storageIsRaw: storage.isRaw
        )
        let text: String

        switch framework {
        case .react:
            let header = metadata.map { "// \($0)" }.joined(separator: "\n")
            text = """
            \(header)

            // Globals: React, db
            // Define an App component; it will be automatically mounted.
            // @miniapp-source

            \(app.source.trimmingCharacters(in: .newlines))

            // \(storageMarker)
            const STORAGE = \(storage.text);
            """
        case .vanilla:
            let header = metadata.joined(separator: "\n")
            text = """
            <!--
            \(header)

            Globals: db
            -->

            \(app.source.trimmingCharacters(in: .newlines))

            <script data-miniapp-storage>
              // \(storageMarker)
              const STORAGE = \(storage.text);
            </script>
            """
        }
        return Data((text + "\n").utf8)
    }

    /// Encodes storage by itself as a small JavaScript file.
    static func encodeDataExport(_ app: MiniApp) throws -> Data {
        let storage = serializedStorage(app.storageJSONForExport())
        let rawMetadata = storage.isRaw ? "\n// @storage-encoding raw" : ""
        let text = """
        // @name \(singleLine(app.name))
        // @kind data\(rawMetadata)

        // \(storageMarker)
        const STORAGE = \(storage.text);
        """
        return Data((text + "\n").utf8)
    }

    /// Decodes a complete code-file export.
    static func decodeBundle(_ data: Data) throws -> MiniAppBundle {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MiniAppImportError.unreadable
        }
        let parsed = try parseCodeFile(text)
        guard parsed.kind == .app else {
            throw MiniAppImportError.wrongKind(expected: .app, found: parsed.kind)
        }
        guard let name = parsed.metadata["name"],
              let type = parsed.metadata["type"],
              let framework = MiniAppFramework(rawValue: type) else {
            throw MiniAppImportError.missingMetadata
        }

        return MiniAppBundle(
            name: name,
            icon: parsed.metadata["icon"] ?? "✨",
            framework: framework.rawValue,
            source: parsed.source,
            storage: parsed.storageRaw == nil ? parsed.storage : nil,
            storageRaw: parsed.storageRaw,
            isInline: parsed.metadata["inline"].flatMap(Bool.init) ?? false,
            inlineMaxHeight: parsed.metadata["inline-max-height"].flatMap(Double.init)
        )
    }

    /// Decodes a storage-only code file.
    static func decodeDataExport(_ data: Data) throws -> MiniAppDataExport {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MiniAppImportError.unreadable
        }
        let parsed = try parseCodeFile(text)
        guard parsed.kind == .data else {
            throw MiniAppImportError.wrongKind(expected: .data, found: parsed.kind)
        }
        return MiniAppDataExport(
            storage: parsed.storageRaw == nil ? parsed.storage : nil,
            storageRaw: parsed.storageRaw
        )
    }

    private struct ParsedCodeFile {
        var kind: MiniAppExportKind
        var metadata: [String: String]
        var source: String
        var storage: JSONValue
        var storageRaw: String?
    }

    private static func parseCodeFile(_ text: String) throws -> ParsedCodeFile {
        let text = text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
        let isHTML = text.drop(while: { $0.isWhitespace }).hasPrefix("<!--")
        let header = isHTML ? htmlHeader(in: text) : lineCommentHeader(in: text)
        let metadata = parseMetadata(header.text)
        let kind: MiniAppExportKind
        if metadata["kind"] == "data" {
            kind = .data
        } else if metadata["type"] != nil || metadata["name"] != nil {
            kind = .app
        } else {
            // A bare `const STORAGE = ...` file is a convenient valid
            // data-only import even without a metadata header.
            kind = .data
        }

        let body = String(text[header.bodyStart...])
        let extraction: (source: String, storage: JSONValue)
        do {
            extraction = try isHTML
                ? extractHTMLStorage(from: body)
                : extractJavaScriptStorage(from: body)
        } catch MiniAppImportError.missingStorage {
            // Storage is optional for hand-authored files and bundled examples.
            // Preserve the entire source when no declaration needs stripping.
            extraction = (body, .object([:]))
        }
        let storageRaw: String?
        if metadata["storage-encoding"] == "raw",
           case .string(let raw) = extraction.storage {
            storageRaw = raw
        } else {
            storageRaw = nil
        }
        return ParsedCodeFile(
            kind: kind,
            metadata: metadata,
            source: extraction.source.trimmingCharacters(in: .whitespacesAndNewlines),
            storage: extraction.storage,
            storageRaw: storageRaw
        )
    }

    private static func metadataLines(
        for app: MiniApp, framework: MiniAppFramework, storageIsRaw: Bool
    ) -> [String] {
        var lines = [
            "@name \(singleLine(app.name))",
            "@type \(framework.rawValue)",
            "@icon \(singleLine(app.icon))"
        ]
        if app.isInline { lines.append("@inline true") }
        if let height = app.inlineMaxHeight {
            lines.append("@inline-max-height \(height.formatted(.number.grouping(.never)))")
        }
        if storageIsRaw { lines.append("@storage-encoding raw") }
        return lines
    }

    private static func singleLine(_ value: String) -> String {
        value.components(separatedBy: .newlines).joined(separator: " ")
    }

    private static func serializedStorage(
        _ blob: String
    ) -> (text: String, isRaw: Bool) {
        guard let data = blob.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
              ),
              let string = String(data: pretty, encoding: .utf8) else {
            // An unparseable blob is preserved verbatim as a JSON string.
            let encoded = try? JSONEncoder().encode(blob)
            let string = encoded.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
            return (string, true)
        }
        return (string, false)
    }

    private static func parseMetadata(_ header: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in header.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("//") {
                line.removeFirst(2)
                line = line.trimmingCharacters(in: .whitespaces)
            }
            guard line.hasPrefix("@") else { continue }
            line.removeFirst()
            let pieces = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard pieces.count == 2 else { continue }
            result[String(pieces[0]).lowercased()] =
                String(pieces[1]).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func lineCommentHeader(
        in text: String
    ) -> (text: String, bodyStart: String.Index) {
        var cursor = text.startIndex
        var end = cursor
        var sawComment = false
        while cursor < text.endIndex {
            let lineEnd = text[cursor...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[cursor..<lineEnd].trimmingCharacters(in: .whitespaces)
            if line == "// @miniapp-source" {
                let bodyStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
                return (String(text[..<cursor]), bodyStart)
            }
            if line.hasPrefix("//") {
                sawComment = true
                end = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
            } else if line.isEmpty, sawComment {
                end = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
            } else {
                break
            }
            cursor = lineEnd < text.endIndex ? text.index(after: lineEnd) : lineEnd
        }
        return (String(text[..<end]), end)
    }

    private static func htmlHeader(
        in text: String
    ) -> (text: String, bodyStart: String.Index) {
        let start = text.range(of: "<!--")!
        guard let close = text.range(of: "-->", range: start.upperBound..<text.endIndex) else {
            return ("", text.startIndex)
        }
        var bodyStart = close.upperBound
        while bodyStart < text.endIndex, text[bodyStart].isWhitespace {
            bodyStart = text.index(after: bodyStart)
        }
        return (String(text[start.upperBound..<close.lowerBound]), bodyStart)
    }

    private static func extractHTMLStorage(
        from body: String
    ) throws -> (source: String, storage: JSONValue) {
        // Prefer the marked storage script emitted by this app.
        if let marker = body.range(of: "data-miniapp-storage", options: .backwards),
           let open = body[..<marker.lowerBound].range(of: "<script", options: .backwards),
           let openEnd = body[marker.upperBound...].firstIndex(of: ">"),
           let close = body.range(
                of: "</script>", options: [.caseInsensitive],
                range: openEnd..<body.endIndex
           ) {
            let script = String(body[body.index(after: openEnd)..<close.lowerBound])
            let storage = try parseStorageDeclaration(in: script).storage
            var source = body
            source.removeSubrange(open.lowerBound..<close.upperBound)
            return (source, storage)
        }

        // Also accept the simpler documented form: a separate script whose
        // contents include `const STORAGE = ...`.
        var searchEnd = body.endIndex
        while let close = body.range(
            of: "</script>", options: [.backwards, .caseInsensitive],
            range: body.startIndex..<searchEnd
        ), let open = body.range(
            of: "<script", options: [.backwards, .caseInsensitive],
            range: body.startIndex..<close.lowerBound
        ), let openEnd = body[open.lowerBound..<close.lowerBound].firstIndex(of: ">") {
            let script = String(body[body.index(after: openEnd)..<close.lowerBound])
            if let declaration = try? parseStorageDeclaration(in: script) {
                var source = body
                source.removeSubrange(open.lowerBound..<close.upperBound)
                return (source, declaration.storage)
            }
            searchEnd = open.lowerBound
        }
        throw MiniAppImportError.missingStorage
    }

    private static func extractJavaScriptStorage(
        from body: String
    ) throws -> (source: String, storage: JSONValue) {
        let declaration = try parseStorageDeclaration(in: body)
        var source = body
        source.removeSubrange(declaration.range)

        // Remove our marker when present. It deliberately sits immediately
        // before the declaration and is not part of the mini-app source.
        if let marker = source.range(of: "// \(storageMarker)", options: .backwards) {
            source.removeSubrange(marker)
        }
        return (source, declaration.storage)
    }

    private static func parseStorageDeclaration(
        in text: String
    ) throws -> (storage: JSONValue, range: Range<String.Index>) {
        guard let nameRange = lastRegexRange(
            #"const\s+STORAGE\s*="#, in: text
        ) else {
            throw MiniAppImportError.missingStorage
        }

        var valueStart = nameRange.upperBound
        while valueStart < text.endIndex, text[valueStart].isWhitespace {
            valueStart = text.index(after: valueStart)
        }
        guard let valueEnd = jsonValueEnd(in: text, from: valueStart) else {
            throw MiniAppImportError.invalidStorage
        }
        let json = String(text[valueStart..<valueEnd])
        guard let storage = JSONValue.parse(json) else {
            throw MiniAppImportError.invalidStorage
        }
        var declarationEnd = valueEnd
        while declarationEnd < text.endIndex, text[declarationEnd].isWhitespace {
            declarationEnd = text.index(after: declarationEnd)
        }
        if declarationEnd < text.endIndex, text[declarationEnd] == ";" {
            declarationEnd = text.index(after: declarationEnd)
        }
        return (storage, nameRange.lowerBound..<declarationEnd)
    }

    private static func lastRegexRange(
        _ pattern: String, in text: String
    ) -> Range<String.Index>? {
        var searchStart = text.startIndex
        var lastMatch: Range<String.Index>?
        while searchStart < text.endIndex,
              let match = text.range(
                of: pattern,
                options: .regularExpression,
                range: searchStart..<text.endIndex
              ) {
            lastMatch = match
            searchStart = match.upperBound
        }
        return lastMatch
    }

    /// Finds the end of a JSON value without treating braces inside strings as
    /// delimiters. Exported storage is normally an object, but fragments are
    /// supported so malformed legacy blobs can still round-trip as strings.
    private static func jsonValueEnd(
        in text: String, from start: String.Index
    ) -> String.Index? {
        guard start < text.endIndex else { return nil }
        let first = text[start]
        if first == "\"" {
            var index = text.index(after: start)
            var escaped = false
            while index < text.endIndex {
                let character = text[index]
                if character == "\"", !escaped { return text.index(after: index) }
                if character == "\\", !escaped {
                    escaped = true
                } else {
                    escaped = false
                }
                index = text.index(after: index)
            }
            return nil
        }
        if first == "{" || first == "[" {
            var index = start
            var stack: [Character] = []
            var inString = false
            var escaped = false
            while index < text.endIndex {
                let character = text[index]
                if inString {
                    if character == "\"", !escaped { inString = false }
                    if character == "\\", !escaped { escaped = true } else { escaped = false }
                } else if character == "\"" {
                    inString = true
                } else if character == "{" || character == "[" {
                    stack.append(character)
                } else if character == "}" || character == "]" {
                    guard let opening = stack.popLast(),
                          (opening == "{" && character == "}") ||
                          (opening == "[" && character == "]") else { return nil }
                    if stack.isEmpty { return text.index(after: index) }
                }
                index = text.index(after: index)
            }
            return nil
        }

        var end = start
        while end < text.endIndex, text[end] != ";", text[end] != "\n",
              text[end] != "<" {
            end = text.index(after: end)
        }
        while end > start, text[text.index(before: end)].isWhitespace {
            end = text.index(before: end)
        }
        return end > start ? end : nil
    }

}

// MARK: - Transferable file for ShareLink

/// A `Transferable` wrapper so a mini-app export can be shared with a sensible
/// code-file name (e.g. "todos-react.jsx").
struct MiniAppExportFile: Transferable {
    let data: Data
    /// The full filename, e.g. "todos-react.jsx".
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(file.filename)
            try file.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
        .suggestedFileName { $0.filename }

        // Text targets (Copy, Messages, Notes) get the editable source.
        ProxyRepresentation { file in
            String(decoding: file.data, as: UTF8.self)
        }
    }

    /// Sanitizes a mini-app name into a filesystem-safe base, defaulting to "MiniApp".
    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -_"))
        let scalars = name.unicodeScalars.filter { allowed.contains($0) }
        let base = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "")
        return base.isEmpty ? "MiniApp" : base
    }

    /// A full app bundle (code + data) for `app`.
    static func appBundle(for app: MiniApp) throws -> MiniAppExportFile {
        let framework = MiniAppFramework(rawValue: app.framework) ?? .vanilla
        let data = try MiniAppExportCoder.encodeBundle(app)
        let fileExtension = framework == .react ? "jsx" : "html"
        return MiniAppExportFile(data: data, filename: "\(sanitize(app.name)).\(fileExtension)")
    }

    /// A data-only export (storage blob) for `app`.
    static func dataExport(for app: MiniApp) throws -> MiniAppExportFile {
        let data = try MiniAppExportCoder.encodeDataExport(app)
        return MiniAppExportFile(data: data, filename: "\(sanitize(app.name)).data.js")
    }
}
