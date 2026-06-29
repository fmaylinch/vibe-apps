import SwiftUI
import UniformTypeIdentifiers

// MARK: - JSONValue

/// A fully `Codable` stand-in for arbitrary JSON. Used so a mini-app's
/// `storageJSON` blob can be embedded in an export file as a readable nested
/// object instead of an escaped string.
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

    /// Parses a JSON string (such as `MiniApp.storageJSON`) into a `JSONValue`.
    /// Returns `nil` when the string isn't valid JSON.
    static func parse(_ string: String) -> JSONValue? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Serializes back to a compact JSON string suitable for `storageJSON`.
    func compactString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Export file shapes

/// Discriminates the two export file shapes so each importer can reject the
/// wrong file with a clear message.
enum MiniAppExportKind: String, Codable {
    /// Full bundle (code + data) — importing creates a new mini-app.
    case app
    /// Storage only — importing replaces an existing mini-app's data.
    case data
}

/// Current on-disk format version. Bump when the shape changes incompatibly.
nonisolated enum MiniAppExportFormat {
    static let currentVersion = 1
}

/// The full export of a mini-app: everything needed to recreate it.
nonisolated struct MiniAppBundle: Codable {
    var formatVersion: Int = MiniAppExportFormat.currentVersion
    var kind: MiniAppExportKind = .app

    var name: String
    var icon: String
    var framework: String
    var source: String
    /// The storage blob as a nested JSON object when parseable; otherwise the
    /// raw string is preserved in `storageRaw`.
    var storage: JSONValue?
    var storageRaw: String?
    var isInline: Bool
    var inlineMaxHeight: Double?

    init(from app: MiniApp) {
        name = app.name
        icon = app.icon
        framework = app.framework
        source = app.source
        isInline = app.isInline
        inlineMaxHeight = app.inlineMaxHeight
        if let parsed = JSONValue.parse(app.storageJSON) {
            storage = parsed
            storageRaw = nil
        } else {
            storage = nil
            storageRaw = app.storageJSON
        }
    }

    /// The compact `storageJSON` string to give a reconstructed `MiniApp`.
    var resolvedStorageJSON: String {
        if let storage, let string = storage.compactString() { return string }
        if let storageRaw { return storageRaw }
        return "{}"
    }

    /// Builds a new (uninserted) `MiniApp` from this bundle. `createdAt` /
    /// `updatedAt` default to now, so the import sorts to the top of the list.
    func makeMiniApp() -> MiniApp {
        MiniApp(
            name: name,
            icon: icon.isEmpty ? "✨" : icon,
            source: source,
            framework: MiniAppFramework(rawValue: framework)?.rawValue
                ?? MiniAppFramework.vanilla.rawValue,
            storageJSON: resolvedStorageJSON,
            isInline: isInline,
            inlineMaxHeight: inlineMaxHeight
        )
    }
}

/// The data-only export: just a mini-app's runtime storage blob.
nonisolated struct MiniAppDataExport: Codable {
    var formatVersion: Int = MiniAppExportFormat.currentVersion
    var kind: MiniAppExportKind = .data

    var storage: JSONValue?
    var storageRaw: String?

    init(storageJSON: String) {
        if let parsed = JSONValue.parse(storageJSON) {
            storage = parsed
            storageRaw = nil
        } else {
            storage = nil
            storageRaw = storageJSON
        }
    }

    /// The compact `storageJSON` string to assign back to a mini-app.
    var resolvedStorageJSON: String {
        if let storage, let string = storage.compactString() { return string }
        if let storageRaw { return storageRaw }
        return "{}"
    }
}

// MARK: - Errors

enum MiniAppImportError: LocalizedError {
    case unreadable
    case notMiniAppJSON
    case wrongKind(expected: MiniAppExportKind, found: MiniAppExportKind)
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "This file couldn’t be read."
        case .notMiniAppJSON:
            return "This isn’t a Mini App export file."
        case .wrongKind(let expected, let found):
            switch (expected, found) {
            case (.app, .data):
                return "This is a Mini App data file. Use “Import Data into this App” from a mini-app’s menu instead."
            case (.data, .app):
                return "This is a full Mini App file. Use “Import App” to add it as a new app."
            default:
                return "This file is the wrong type for this action."
            }
        case .unsupportedVersion(let version):
            return "This file uses a newer format (version \(version)) than this app understands. Update the app and try again."
        }
    }
}

// MARK: - Encoding / decoding

enum MiniAppExportCoder {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    /// Decodes a full app bundle, validating kind and version.
    static func decodeBundle(_ data: Data) throws -> MiniAppBundle {
        try decode(data, expecting: .app)
    }

    /// Decodes a data-only export, validating kind and version.
    static func decodeDataExport(_ data: Data) throws -> MiniAppDataExport {
        try decode(data, expecting: .data)
    }

    /// Minimal header used to validate a file before fully decoding it.
    private struct Envelope: Decodable {
        var formatVersion: Int?
        var kind: MiniAppExportKind?
    }

    private static func decode<T: Decodable>(
        _ data: Data, expecting kind: MiniAppExportKind
    ) throws -> T {
        // Peek at the envelope first for precise wrong-kind / version errors.
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let foundKind = envelope.kind else {
            throw MiniAppImportError.notMiniAppJSON
        }
        guard foundKind == kind else {
            throw MiniAppImportError.wrongKind(expected: kind, found: foundKind)
        }
        if let version = envelope.formatVersion, version > MiniAppExportFormat.currentVersion {
            throw MiniAppImportError.unsupportedVersion(version)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MiniAppImportError.notMiniAppJSON
        }
    }
}

// MARK: - Transferable file for ShareLink

/// A `Transferable` wrapper so a mini-app export can be shared as a JSON file
/// with a sensible filename (e.g. "TodoList.miniapp.json").
struct MiniAppExportFile: Transferable {
    let data: Data
    /// The full filename, e.g. "TodoList.miniapp.json".
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        // File targets (Save to Files, AirDrop, Mail) get a named .json file.
        FileRepresentation(exportedContentType: .json) { file in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(file.filename)
            try file.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
        .suggestedFileName { $0.filename }

        // Text targets (Copy, Messages, Notes) get the raw JSON as plain text.
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
        let data = try MiniAppExportCoder.encode(MiniAppBundle(from: app))
        return MiniAppExportFile(data: data, filename: "\(sanitize(app.name)).miniapp.json")
    }

    /// A data-only export (storage blob) for `app`.
    static func dataExport(for app: MiniApp) throws -> MiniAppExportFile {
        let data = try MiniAppExportCoder.encode(MiniAppDataExport(storageJSON: app.storageJSON))
        return MiniAppExportFile(data: data, filename: "\(sanitize(app.name)).miniappdata.json")
    }
}
