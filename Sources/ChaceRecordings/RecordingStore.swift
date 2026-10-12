import Foundation

enum RecordingStore {
    struct Metadata: Codable { let name: String }

    static func displayName(in folder: URL) -> String {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("recording.json")),
              let metadata = try? JSONDecoder().decode(Metadata.self, from: data) else { return folder.lastPathComponent }
        return metadata.name
    }

    static func rename(in folder: URL, to proposed: String) throws {
        let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120,
              name.rangeOfCharacter(from: CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:"))) == nil,
              name != ".", name != ".." else {
            throw AppError("Usa un nombre de 1 a 120 caracteres, sin barras, dos puntos ni saltos de línea.")
        }
        let data = try JSONEncoder().encode(Metadata(name: name))
        try data.write(to: folder.appendingPathComponent("recording.json"), options: .atomic)
    }

    static func verifyWritable(_ folder: URL) throws {
        let probe = folder.appendingPathComponent(".chace-write-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: probe) }
        try Data("ChaceRecordings".utf8).write(to: probe, options: .withoutOverwriting)
    }
}
