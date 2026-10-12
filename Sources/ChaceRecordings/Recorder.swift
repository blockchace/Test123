import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import SwiftUI
import UniformTypeIdentifiers
import Darwin

enum AudioSource: String, CaseIterable, Identifiable {
    case system = "Sistema"
    case microphone = "Micrófono"
    case both = "Sistema + micrófono"
    var id: String { rawValue }
    var needsSystem: Bool { self != .microphone }
    var needsMicrophone: Bool { self != .system }
}

struct Microphone: Identifiable {
    let id: String
    let name: String
}

struct Recording: Identifiable {
    let url: URL
    let name: String
    let date: Date
    let duration: Double
    let tracks: [URL]
    var id: String { url.path }
}

final class Recorder: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let shared = Recorder()
    static let stateChanged = Notification.Name("ChaceRecordingsStateChanged")
    enum Phase { case idle, starting, recording, stopping }
    @Published var source: AudioSource = .both
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var paused = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var exporting = false
    @Published private(set) var playingID: String?
    @Published var error: String?
    @Published private(set) var microphones: [Microphone] = []
    @Published var selectedMicrophoneID = "" {
        didSet { UserDefaults.standard.set(selectedMicrophoneID, forKey: "selectedMicrophoneID") }
    }
    let monitor = AudioMonitor()
    @Published private(set) var library: URL
    var busy: Bool { phase != .idle }
    var transcriptionActive = false

    private let audioQueue = DispatchQueue(label: "ChaceRecordings.disk-writer")
    private let captureQueue = DispatchQueue(label: "ChaceRecordings.microphone-lifecycle")
    private var accepting = false // Accessed only on audioQueue.
    private var files: [String: AVAudioFile] = [:]
    private var frames: [String: Int64] = [:]
    private var session: URL?
    private var writeFailed = false
    private var stream: SCStream?
    private var microphoneSession: AVCaptureSession?
    private var microphoneRuntimeObserver: NSObjectProtocol?
    private var waveforms: [String: WaveformHistory] = [:]
    private var pendingPeaks: [String: Float] = [:]
    private var lastAudio: [String: TimeInterval] = [:]
    private var timer: Timer?
    private var playbackEngine: AVAudioEngine?
    private var playbackNodes: [AVAudioPlayerNode] = []
    private var playbackFiles: [AVAudioFile] = []
    private var playbackToken = UUID()
    private var pendingPlaybackTracks = 0
    private var resumeAfterSleep = false
    private var activity: NSObjectProtocol?

    override init() {
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AireAudio/Grabaciones", isDirectory: true)
        library = UserDefaults.standard.string(forKey: "recordingDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? legacy
        super.init()
        selectedMicrophoneID = UserDefaults.standard.string(forKey: "selectedMicrophoneID") ?? ""
        do { try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true) }
        catch { self.error = error.localizedDescription }
        registerLibrary(library)
        reload()
        refreshMicrophones()
        NotificationCenter.default.addObserver(self, selector: #selector(devicesChanged), name: AVCaptureDevice.wasConnectedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(devicesChanged), name: AVCaptureDevice.wasDisconnectedNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func refreshMicrophones() {
        let devices = AVCaptureDevice.devices(for: .audio)
        microphones = devices.map { Microphone(id: $0.uniqueID, name: $0.localizedName) }
        if !selectedMicrophoneID.isEmpty && !devices.contains(where: { $0.uniqueID == selectedMicrophoneID }) {
            if busy {
                error = "El micrófono seleccionado se desconectó. Se guardará lo grabado hasta ahora."
                stop()
            } else { selectedMicrophoneID = "" }
        }
    }

    @objc private func devicesChanged() {
        DispatchQueue.main.async { self.refreshMicrophones() }
    }

    private func configureMicrophone() throws {
        let device: AVCaptureDevice?
        if selectedMicrophoneID.isEmpty { device = AVCaptureDevice.default(for: .audio) }
        else { device = AVCaptureDevice.devices(for: .audio).first { $0.uniqueID == selectedMicrophoneID } }
        guard let device else { throw AppError("No se encontró el micrófono seleccionado. Actualiza la lista y elige otra entrada.") }
        let capture = AVCaptureSession()
        capture.beginConfiguration()
        defer { capture.commitConfiguration() }
        let input = try AVCaptureDeviceInput(device: device)
        guard capture.canAddInput(input) else { throw AppError("No se pudo abrir el micrófono \(device.localizedName).") }
        capture.addInput(input)
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false]
        output.setSampleBufferDelegate(self, queue: audioQueue)
        guard capture.canAddOutput(output) else { throw AppError("No se pudo configurar la salida del micrófono.") }
        capture.addOutput(output)
        microphoneSession = capture
        microphoneRuntimeObserver = NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: capture, queue: .main) { [weak self] notification in
            let detail = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription ?? "Error del dispositivo"
            self?.error = "La captura del micrófono falló: \(detail)"
            self?.stop()
        }
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
                    catch { throw AppError("No se pudo acceder al audio del sistema. Autoriza ChaceRecordings en Ajustes del Sistema → Privacidad y seguridad → Grabación de pantalla (o Pantalla y audio del sistema), y vuelve a abrir la app. Detalle: \(error.localizedDescription)") }
                    guard content?.displays.first != nil else { throw AppError("No se encontró una pantalla para la captura del sistema.") }
                }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
                let folder = library.appendingPathComponent("\(formatter.string(from: Date())) \(UUID().uuidString.prefix(6))", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try RecordingStore.rename(in: folder, to: "Grabación \(formatter.string(from: Date()))")
                audioQueue.sync {
                    session = folder
                    files.removeAll()
                    frames.removeAll()
                    accepting = false
                    writeFailed = false
                    waveforms.removeAll()
                    pendingPeaks.removeAll()
                    lastAudio.removeAll()
                }
                if selected.needsMicrophone {
                    try configureMicrophone()
                    if let capture = microphoneSession {
                        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                            captureQueue.async { capture.startRunning(); continuation.resume() }
                        }
                        guard capture.isRunning else { throw AppError("El micrófono no inició la captura. Comprueba los permisos y el dispositivo seleccionado.") }
                    }
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
                startMeterTimer()
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
        if paused {
            updateElapsed()
            timer?.invalidate()
            timer = nil
            audioQueue.sync { waveforms.removeAll(); pendingPeaks.removeAll() }
            monitor.clear()
        } else { startMeterTimer() }
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
        if let observer = microphoneRuntimeObserver { NotificationCenter.default.removeObserver(observer) }
        microphoneRuntimeObserver = nil
        if let capture = microphoneSession {
            microphoneSession = nil
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                captureQueue.async { capture.stopRunning(); continuation.resume() }
            }
        }
        monitor.clear()
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

    private func startMeterTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.updateElapsed() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateElapsed() {
        let snapshot = audioQueue.sync { () -> (Double, [Float], [Float], Bool, Bool) in
            let now = ProcessInfo.processInfo.systemUptime
            let systemLive = accepting && now - lastAudio["sistema", default: 0] < 0.3
            let micLive = accepting && now - lastAudio["microfono", default: 0] < 0.3
            for key in ["sistema", "microfono"] {
                var history = waveforms[key] ?? WaveformHistory()
                history.append(peak: accepting ? pendingPeaks[key, default: 0] : 0)
                waveforms[key] = history
                pendingPeaks[key] = 0
            }
            return (files.map { key, file in Double(frames[key, default: 0]) / file.processingFormat.sampleRate }.max() ?? elapsed,
                    waveforms["sistema"]!.values, waveforms["microfono"]!.values, systemLive, micLive)
        }
        // The library and controls refresh once per second, not on every meter frame.
        if Int(elapsed) != Int(snapshot.0) { elapsed = snapshot.0 }
        monitor.update(system: snapshot.1, microphone: snapshot.2, systemReceiving: snapshot.3, microphoneReceiving: snapshot.4)
    }

    private func write(_ buffer: AVAudioPCMBuffer, track: String) {
        guard accepting, !writeFailed, let session, buffer.frameLength > 0 else { return }
        do {
            if files[track] == nil {
                files[track] = try AVAudioFile(forWriting: session.appendingPathComponent("\(track).caf"), settings: buffer.format.settings, commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
            }
            try files[track]?.write(from: buffer)
            frames[track, default: 0] += Int64(buffer.frameLength)
            let now = ProcessInfo.processInfo.systemUptime
            lastAudio[track] = now
            pendingPeaks[track] = max(pendingPeaks[track, default: 0], AudioLevels.peak(buffer))
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
        guard type == .audio else { return }
        consume(sampleBuffer, track: "sistema")
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        consume(sampleBuffer, track: "microfono")
    }

    private func consume(_ sampleBuffer: CMSampleBuffer, track: String) {
        guard accepting, sampleBuffer.isValid,
              let description = sampleBuffer.formatDescription else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let count = CMSampleBufferGetNumSamples(sampleBuffer)
        guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return }
        buffer.frameLength = AVAudioFrameCount(count)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(count), into: buffer.mutableAudioBufferList)
        guard status == noErr else {
            DispatchQueue.main.async {
                self.error = "No se pudo convertir el audio de \(track) (\(status))."
                self.stop()
            }
            return
        }
        write(buffer, track: track)
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

    private func registerLibrary(_ root: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: "recordingDirectories") ?? []
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AireAudio/Grabaciones").path
        for path in [legacy, root.standardizedFileURL.path] where !paths.contains(path) { paths.append(path) }
        UserDefaults.standard.set(paths, forKey: "recordingDirectories")
    }

    func chooseRecordingFolder() {
        guard !busy, !exporting else { return }
        let panel = NSOpenPanel()
        panel.title = "Carpeta para guardar las grabaciones"
        panel.prompt = "Elegir carpeta"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = library
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            try RecordingStore.verifyWritable(folder)
            stopPlayback()
            library = folder.standardizedFileURL
            UserDefaults.standard.set(library.path, forKey: "recordingDirectory")
            registerLibrary(library)
            reload()
        } catch { self.error = "No se puede guardar en esa carpeta: \(error.localizedDescription)" }
    }

    func rename(_ recording: Recording) {
        guard !busy, !exporting else { return }
        let alert = NSAlert()
        alert.messageText = "Nombre de la grabación"
        alert.informativeText = "El nombre también se utilizará al exportar a MP3."
        let field = NSTextField(string: recording.name)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Guardar nombre")
        alert.addButton(withTitle: "Cancelar")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try RecordingStore.rename(in: recording.url, to: field.stringValue); reload() }
        catch { self.error = error.localizedDescription }
    }

    func reload() {
        let roots = UserDefaults.standard.stringArray(forKey: "recordingDirectories") ?? [library.path]
        let folders = Array(Set(roots)).flatMap { path in
            (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.creationDateKey])) ?? []
        }
        recordings = folders.compactMap { folder in
            let tracks = ["sistema.caf", "microfono.caf"].map { folder.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            let durations = tracks.compactMap { url -> Double? in
                guard let f = try? AVAudioFile(forReading: url), f.length > 0 else { return nil }
                return Double(f.length) / f.processingFormat.sampleRate
            }
            guard let duration = durations.max() else { return nil }
            return Recording(url: folder, name: RecordingStore.displayName(in: folder), date: (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date(), duration: duration, tracks: tracks)
        }.sorted { $0.date > $1.date }
    }

    func reveal(_ recording: Recording) { NSWorkspace.shared.activateFileViewerSelecting([recording.url]) }
    func play(_ recording: Recording) {
        if playingID == recording.id { stopPlayback(); return }
        stopPlayback()
        let token = UUID()
        playbackToken = token
        do {
            let engine = AVAudioEngine()
            playbackEngine = engine
            playbackFiles = try recording.tracks.map { try AVAudioFile(forReading: $0) }
            pendingPlaybackTracks = playbackFiles.count
            engine.mainMixerNode.outputVolume = playbackFiles.count > 1 ? 0.5 : 1
            for file in playbackFiles {
                let node = AVAudioPlayerNode()
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
                playbackNodes.append(node)
                node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self, self.playbackToken == token else { return }
                        self.pendingPlaybackTracks -= 1
                        if self.pendingPlaybackTracks == 0 { self.stopPlayback() }
                    }
                }
            }
            engine.prepare()
            try engine.start()
            let start = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.1))
            for node in playbackNodes { node.play(at: start) }
            playingID = recording.id
        } catch {
            stopPlayback()
            self.error = error.localizedDescription
        }
    }
    func stopPlayback() {
        playbackToken = UUID()
        for node in playbackNodes { node.stop() }
        playbackEngine?.stop()
        playbackNodes.removeAll()
        playbackFiles.removeAll()
        playbackEngine = nil
        pendingPlaybackTracks = 0
        playingID = nil
    }

    func export(_ recording: Recording) {
        guard !exporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mp3]
        panel.nameFieldStringValue = recording.name + ".mp3"
        panel.directoryURL = recording.url.deletingLastPathComponent()
        panel.title = "Exportar grabación a MP3"
        guard panel.runModal() == .OK, let target = panel.url else { return }
        guard let encoder = Bundle.main.url(forResource: "ffmpeg", withExtension: nil, subdirectory: "bin") else {
            error = "Falta el codificador MP3. Genera la app con scripts/build-macos.sh."
            return
        }
        exporting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let temporary = target.deletingLastPathComponent().appendingPathComponent(".chace-\(UUID().uuidString).mp3")
            let log = FileManager.default.temporaryDirectory.appendingPathComponent("chace-export-\(UUID().uuidString).log")
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
