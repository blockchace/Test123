import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import SwiftUI
import UniformTypeIdentifiers

enum AudioSource: String, CaseIterable, Identifiable {
    case system = "Sistema"
    case microphone = "Micrófono"
    case both = "Sistema + micrófono"
    var id: String { rawValue }
    var needsSystem: Bool { self != .microphone }
    var needsMicrophone: Bool { self != .system }
}

struct Recording: Identifiable {
    let url: URL
    let date: Date
    let duration: Double
    let tracks: [URL]
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

final class Recorder: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    static let shared = Recorder()
    static let stateChanged = Notification.Name("AireAudioStateChanged")
    enum Phase { case idle, starting, recording, stopping }
    @Published var source: AudioSource = .system
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var paused = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var exporting = false
    @Published private(set) var playingID: String?
    @Published var error: String?
    var busy: Bool { phase != .idle }

    private let audioQueue = DispatchQueue(label: "AireAudio.disk-writer")
    private var accepting = false // Accessed only on audioQueue.
    private var files: [String: AVAudioFile] = [:]
    private var frames: [String: Int64] = [:]
    private var session: URL?
    private var writeFailed = false
    private var stream: SCStream?
    private var engine: AVAudioEngine?
    private var timer: Timer?
    private var player: AVAudioPlayer?
    private var playerTimer: Timer?
    private var resumeAfterSleep = false
    private var activity: NSObjectProtocol?
    private let library: URL

    override init() {
        library = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AireAudio/Grabaciones", isDirectory: true)
        super.init()
        do { try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true) }
        catch { self.error = error.localizedDescription }
        reload()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func announce() { NotificationCenter.default.post(name: Self.stateChanged, object: self) }

    func start() {
        guard phase == .idle else { return }
        stopPlayback()
        phase = .starting
        paused = false
        elapsed = 0
        error = nil
        announce()
        let selected = source
        Task { @MainActor in
            do {
                if selected.needsMicrophone {
                    let allowed = await AVCaptureDevice.requestAccess(for: .audio)
                    guard allowed else { throw AppError("Autoriza el micrófono en Ajustes del Sistema → Privacidad y seguridad → Micrófono.") }
                }
                var content: SCShareableContent?
                if selected.needsSystem {
                    do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
                    catch { throw AppError("No se pudo acceder al audio del sistema. Autoriza Aire Audio en Ajustes del Sistema → Privacidad y seguridad → Grabación de pantalla (o Pantalla y audio del sistema), y vuelve a abrir la app. Detalle: \(error.localizedDescription)") }
                    guard content?.displays.first != nil else { throw AppError("No se encontró una pantalla para la captura del sistema.") }
                }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
                let folder = library.appendingPathComponent("\(formatter.string(from: Date())) \(UUID().uuidString.prefix(6))", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                audioQueue.sync {
                    session = folder
                    files.removeAll()
                    frames.removeAll()
                    accepting = false
                    writeFailed = false
                }
                if selected.needsMicrophone {
                    let e = AVAudioEngine()
                    let input = e.inputNode
                    let format = input.outputFormat(forBus: 0)
                    guard format.sampleRate > 0, format.channelCount > 0 else { throw AppError("No hay un micrófono disponible.") }
                    input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                        // Copy: the engine reuses tap buffers after this callback returns.
                        guard let copy = Self.copy(buffer) else { return }
                        self?.audioQueue.async { self?.write(copy, track: "microfono") }
                    }
                    engine = e
                    try e.start()
                }
                if let display = content?.displays.first {
                    let config = SCStreamConfiguration()
                    config.capturesAudio = true
                    config.excludesCurrentProcessAudio = true
                    config.sampleRate = 48_000
                    config.channelCount = 2
                    config.width = 2
                    config.height = 2
                    config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                    config.queueDepth = 3
                    let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
                    stream = s
                    try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
                    try await s.startCapture()
                }
                audioQueue.sync { accepting = true }
                activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated], reason: "Grabación de audio en curso")
                phase = .recording
                timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.updateElapsed() }
                announce()
            } catch {
                await finishCapture()
                self.error = error.localizedDescription
            }
        }
    }

    func togglePause() {
        guard phase == .recording else { return }
        paused.toggle()
        audioQueue.sync { accepting = !paused }
        updateElapsed()
        announce()
    }

    func stop() {
        guard phase == .recording else { return }
        phase = .stopping
        audioQueue.sync { accepting = false }
        announce()
        Task { @MainActor in await finishCapture() }
    }

    @MainActor private func finishCapture() async {
        timer?.invalidate()
        timer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        audioQueue.sync { accepting = false }
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        if let s = stream {
            stream = nil
            do { try await s.stopCapture() }
            catch { self.error = "La captura se interrumpió: \(error.localizedDescription). Las pistas guardadas siguen en la biblioteca." }
        }
        audioQueue.sync {
            files.removeAll() // Close and finalize CAF headers.
            session = nil
        }
        phase = .idle
        paused = false
        resumeAfterSleep = false
        reload()
        announce()
    }

    private func updateElapsed() {
        elapsed = audioQueue.sync {
            files.map { key, file in Double(frames[key, default: 0]) / file.processingFormat.sampleRate }.max() ?? elapsed
        }
    }

    private static func copy(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let output = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return nil }
        output.frameLength = source.frameLength
        let src = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let dst = UnsafeMutableAudioBufferListPointer(output.mutableAudioBufferList)
        for index in 0..<src.count {
            guard let from = src[index].mData, let to = dst[index].mData else { return nil }
            memcpy(to, from, Int(src[index].mDataByteSize))
        }
        return output
    }

    private func write(_ buffer: AVAudioPCMBuffer, track: String) {
        guard accepting, !writeFailed, let session, buffer.frameLength > 0 else { return }
        do {
            if files[track] == nil {
                files[track] = try AVAudioFile(forWriting: session.appendingPathComponent("\(track).caf"), settings: buffer.format.settings, commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
            }
            try files[track]?.write(from: buffer)
            frames[track, default: 0] += Int64(buffer.frameLength)
        } catch {
            accepting = false
            writeFailed = true
            DispatchQueue.main.async {
                self.error = "No se pudo guardar audio: \(error.localizedDescription). Comprueba el espacio disponible."
                self.stop()
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, accepting, sampleBuffer.isValid,
              let description = sampleBuffer.formatDescription else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let count = CMSampleBufferGetNumSamples(sampleBuffer)
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return }
        buffer.frameLength = AVAudioFrameCount(count)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(count), into: buffer.mutableAudioBufferList)
        guard status == noErr else {
            DispatchQueue.main.async {
                self.error = "No se pudo convertir el audio del sistema (\(status))."
                self.stop()
            }
            return
        }
        write(buffer, track: "sistema")
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            guard self.phase == .recording else { return }
            self.error = "La captura se interrumpió: \(error.localizedDescription)"
            self.stop()
        }
    }

    @objc private func willSleep() {
        if phase == .recording && !paused { resumeAfterSleep = true; togglePause() }
    }
    @objc private func didWake() {
        if resumeAfterSleep && phase == .recording && paused { resumeAfterSleep = false; togglePause() }
    }

    func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: [.creationDateKey])) ?? []
        recordings = folders.compactMap { folder in
            let tracks = ["sistema.caf", "microfono.caf"].map { folder.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            let durations = tracks.compactMap { url -> Double? in
                guard let f = try? AVAudioFile(forReading: url), f.length > 0 else { return nil }
                return Double(f.length) / f.processingFormat.sampleRate
            }
            guard let duration = durations.max() else { return nil }
            return Recording(url: folder, date: (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date(), duration: duration, tracks: tracks)
        }.sorted { $0.date > $1.date }
    }

    func reveal(_ recording: Recording) { NSWorkspace.shared.activateFileViewerSelecting([recording.url]) }
    func play(_ recording: Recording) {
        if playingID == recording.id { stopPlayback(); return }
        stopPlayback()
        do {
            player = try AVAudioPlayer(contentsOf: recording.tracks[0])
            guard player?.play() == true else { throw AppError("No se pudo reproducir la pista.") }
            playingID = recording.id
            playerTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                if self?.player?.isPlaying != true { self?.stopPlayback() }
            }
        } catch { self.error = error.localizedDescription }
    }
    func stopPlayback() { player?.stop(); player = nil; playingID = nil; playerTimer?.invalidate(); playerTimer = nil }

    func export(_ recording: Recording) {
        guard !exporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mp3]
        panel.nameFieldStringValue = recording.name + ".mp3"
        panel.title = "Exportar grabación a MP3"
        guard panel.runModal() == .OK, let target = panel.url else { return }
        guard let encoder = Bundle.main.url(forResource: "ffmpeg", withExtension: nil, subdirectory: "bin") else {
            error = "Falta el codificador MP3. Genera la app con scripts/build-macos.sh."
            return
        }
        exporting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let temporary = target.deletingLastPathComponent().appendingPathComponent(".aire-\(UUID().uuidString).mp3")
            let log = FileManager.default.temporaryDirectory.appendingPathComponent("aire-export-\(UUID().uuidString).log")
            defer { try? FileManager.default.removeItem(at: temporary); try? FileManager.default.removeItem(at: log) }
            do {
                FileManager.default.createFile(atPath: log.path, contents: nil)
                let handle = try FileHandle(forWritingTo: log)
                defer { try? handle.close() }
                let process = Process()
                process.executableURL = encoder
                var args = ["-hide_banner", "-loglevel", "error", "-nostdin", "-y"]
                for track in recording.tracks { args += ["-i", track.path] }
                if recording.tracks.count == 2 {
                    args += ["-filter_complex", "[0:a][1:a]amix=inputs=2:duration=longest:dropout_transition=0:normalize=1[a]", "-map", "[a]"]
                }
                args += ["-vn", "-codec:a", "libmp3lame", "-b:a", "192k", temporary.path]
                process.arguments = args
                process.standardError = handle
                process.standardOutput = FileHandle.nullDevice
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let detail = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                    throw AppError("No se pudo exportar el MP3. \(detail.prefix(1500))")
                }
                if FileManager.default.fileExists(atPath: target.path) {
                    _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
                } else { try FileManager.default.moveItem(at: temporary, to: target) }
                DispatchQueue.main.async { self.exporting = false; NSWorkspace.shared.activateFileViewerSelecting([target]) }
            } catch { DispatchQueue.main.async { self.exporting = false; self.error = error.localizedDescription } }
        }
    }
}

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func clock(_ seconds: Double) -> String {
    let value = max(0, Int(seconds))
    return String(format: "%02d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
}
