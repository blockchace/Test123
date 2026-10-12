import AppKit
import Combine

private final class DeepgramTransport: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never redirect an authenticated audio upload.
    }
}

@MainActor final class Transcriber: ObservableObject {
    @Published private(set) var recordingID: String?
    @Published private(set) var status = ""
    @Published private(set) var hasKey = false
    @Published var error: String?
    var busy: Bool { recordingID != nil }

    init() { refreshKeyStatus() }

    func refreshKeyStatus() {
        do { hasKey = try DeepgramKeychain.isConfigured() }
        catch { hasKey = false; self.error = error.localizedDescription }
    }

    func start(_ recording: Recording, language: TranscriptionLanguage) {
        guard !busy else { return }
        recordingID = recording.id
        Recorder.shared.transcriptionActive = true
        status = "Preparando audio…"
        error = nil
        Task {
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("chace-transcribe-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: temporary); recordingID = nil; status = ""; Recorder.shared.transcriptionActive = false }
            do {
                guard let key = try DeepgramKeychain.load(), !key.isEmpty else {
                    throw AppError("Añade tu API key de Deepgram en Ajustes antes de transcribir.")
                }
                try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                // Check destination access before consuming API credits.
                try RecordingStore.verifyWritable(recording.url)
                guard let encoder = Bundle.main.url(forResource: "ffmpeg", withExtension: nil, subdirectory: "bin") else {
                    throw AppError("Falta FFmpeg en la app. Compílala con scripts/build-macos.sh.")
                }
                let upload = temporary.appendingPathComponent("audio.mp3")
                try await Self.prepare(recording.tracks, encoder: encoder, output: upload, log: temporary.appendingPathComponent("encoding.log"))
                status = "Enviando audio y transcribiendo…"
                var request = URLRequest(url: DeepgramTranscript.endpoint(language: language))
                request.httpMethod = "POST"
                request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
                request.setValue("audio/mpeg", forHTTPHeaderField: "Content-Type")
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 600
                config.timeoutIntervalForResource = 7200
                let session = URLSession(configuration: config, delegate: DeepgramTransport(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                // Stream the upload from disk; do not load the full recording into RAM.
                let (data, response) = try await session.upload(for: request, fromFile: upload)
                guard let http = response as? HTTPURLResponse else { throw AppError("No se recibió una respuesta válida de Deepgram.") }
                try DeepgramTranscript.validate(status: http.statusCode)
                let text = try DeepgramTranscript.text(from: data, name: recording.name, language: language)
                let date = DateFormatter()
                date.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let output = recording.url.appendingPathComponent("Transcripcion-\(language.rawValue)-\(date.string(from: Date()))-\(UUID().uuidString.prefix(6)).txt")
                try text.write(to: output, atomically: true, encoding: .utf8)
                NSWorkspace.shared.activateFileViewerSelecting([output])
                NSWorkspace.shared.open(output)
            } catch {
                self.error = "No se completó la transcripción. \(error.localizedDescription) La grabación original se conserva."
            }
        }
    }

    private static func prepare(_ tracks: [URL], encoder: URL, output: URL, log: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .utility).async {
                do {
                    FileManager.default.createFile(atPath: log.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: log)
                    defer { try? handle.close() }
                    let process = Process()
                    process.executableURL = encoder
                    var args = ["-hide_banner", "-loglevel", "error", "-nostdin", "-y"]
                    for track in tracks { args += ["-i", track.path] }
                    if tracks.count == 2 {
                        args += ["-filter_complex", "[0:a][1:a]amix=inputs=2:duration=longest:dropout_transition=0:normalize=1[a]", "-map", "[a]"]
                    }
                    args += ["-vn", "-ac", "1", "-ar", "16000", "-codec:a", "libmp3lame", "-b:a", "64k", output.path]
                    process.arguments = args
                    process.standardError = handle
                    process.standardOutput = FileHandle.nullDevice
                    try process.run()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else { throw AppError("No se pudo preparar el audio para Deepgram.") }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
