import XCTest
@testable import ChaceRecordings

final class RecordingStoreTests: XCTestCase {
    func testLatestExistingTranscriptSurvivesRelaunchLookup() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertNil(RecordingStore.latestTranscript(in: folder))
        let old = folder.appendingPathComponent("Transcripcion-es.txt")
        let latest = folder.appendingPathComponent("Transcripcion-en.txt")
        try "Hola".write(to: old, atomically: true, encoding: .utf8)
        try "Hello".write(to: latest, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: latest.path)
        XCTAssertEqual(RecordingStore.latestTranscript(in: folder), latest)
    }
    func testRenameSurvivesReloadWithoutTouchingTrack() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let track = folder.appendingPathComponent("microfono.caf")
        let audio = Data([1, 2, 3, 4])
        try audio.write(to: track)
        try RecordingStore.rename(in: folder, to: "  Entrevista con José  ")
        XCTAssertEqual(RecordingStore.displayName(in: folder), "Entrevista con José")
        XCTAssertEqual(try Data(contentsOf: track), audio)
        try RecordingStore.rename(in: folder, to: "Segunda entrevista")
        XCTAssertEqual(RecordingStore.displayName(in: folder), "Segunda entrevista")
    }

    func testInvalidRenamePreservesPreviousName() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try RecordingStore.rename(in: folder, to: "Original")
        for name in ["", "../fuera", "nombre:otro", "dos\nlíneas", ".."] {
            XCTAssertThrowsError(try RecordingStore.rename(in: folder, to: name))
        }
        XCTAssertEqual(RecordingStore.displayName(in: folder), "Original")
    }

    func testWritableProbeLeavesNoFilesAndMissingFolderFails() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try RecordingStore.verifyWritable(folder))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try RecordingStore.verifyWritable(folder)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }
}
