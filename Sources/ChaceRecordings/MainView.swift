import SwiftUI
import AppKit

@MainActor struct MainView: View {
    @ObservedObject var model: Recorder
    @StateObject private var transcriber = Transcriber()
    @State private var settingsPresented = false
    @State private var transcriptionTarget: Recording?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "mic.circle.fill").font(.system(size: 26)).foregroundStyle(.indigo)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ChaceRecordings").font(.headline)
                    }
                    Spacer()
                    Button { settingsPresented = true } label: { Image(systemName: "gearshape") }
                        .help("Ajustes de Deepgram").disabled(transcriber.busy)
                }
                VStack(spacing: 10) {
                    Picker("Fuente de audio", selection: $model.source) {
                        ForEach(AudioSource.allCases) { source in Text(source == .both ? "Ambos" : source.rawValue).tag(source) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.busy)
                    if model.source.needsMicrophone {
                        HStack {
                            Picker("Micrófono", selection: $model.selectedMicrophoneID) {
                                Text("Predeterminado del Mac").tag("")
                                ForEach(model.microphones) { microphone in Text(microphone.name).tag(microphone.id) }
                            }
                            .disabled(model.busy)
                            Button { model.refreshMicrophones() } label: { Image(systemName: "arrow.clockwise") }
                                .help("Actualizar micrófonos").disabled(model.busy)
                        }
                        if model.microphones.isEmpty {
                            Text("No se detectaron micrófonos. Autoriza el acceso y actualiza la lista.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                    InputMonitors(monitor: model.monitor, source: model.source, paused: model.paused, recording: model.phase == .recording)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            recordingTime
                            Spacer(minLength: 8)
                            recordingButtons
                        }
                        VStack(spacing: 8) {
                            recordingTime
                            recordingButtons
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .modifier(GlassCard())
                HStack(spacing: 6) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(model.library.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        .help(model.library.path)
                    Spacer(minLength: 4)
                    Button("Cambiar carpeta") { model.chooseRecordingFolder() }
                        .disabled(model.busy || model.exporting || transcriber.busy)
                }
                .font(.caption)
                .padding(.horizontal, 4)
                HStack {
                    Text("Tus grabaciones").font(.headline)
                    Spacer()
                    if model.exporting { ProgressView().controlSize(.small); Text("Exportando MP3…").font(.caption) }
                }
                if model.recordings.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "waveform").font(.title3).foregroundStyle(.secondary)
                        Text("Tu primera grabación empieza aquí.").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 45)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(model.recordings) { recording in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Button { model.play(recording) } label: {
                                        Image(systemName: model.playingID == recording.id ? "stop.circle.fill" : "play.circle.fill").font(.title3)
                                    }.buttonStyle(.plain).disabled(model.busy)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(recording.name).font(.caption.bold()).lineLimit(1).help(recording.name)
                                        Text("\(clock(recording.duration)) · \(recording.tracks.count == 2 ? "Sistema + micrófono" : recording.tracks[0].deletingPathExtension().lastPathComponent.capitalized)")
                                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    .layoutPriority(1)
                                    Spacer()
                                    Button { model.rename(recording) } label: { Image(systemName: "pencil") }
                                        .help("Cambiar nombre de la grabación").disabled(model.busy || model.exporting || transcriber.busy)
                                    Button { model.reveal(recording) } label: { Image(systemName: "folder") }
                                        .help("Mostrar pistas originales en Finder")
                                    Button("MP3") { model.export(recording) }.disabled(model.exporting).help("Exportar grabación a MP3")
                                }
                                HStack(spacing: 6) {
                                    if transcriber.recordingID == recording.id {
                                        ProgressView().controlSize(.small)
                                        Text(transcriber.status).font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Button { transcriptionTarget = recording } label: {
                                            Label("Transcribir", systemImage: "text.bubble")
                                        }
                                        .controlSize(.small)
                                        .disabled(model.busy || model.exporting || transcriber.busy)
                                    }
                                    Spacer(minLength: 0)
                                    if let transcript = recording.transcriptURL {
                                        Button("Abrir TXT") { NSWorkspace.shared.open(transcript) }
                                            .controlSize(.small).help("Abrir la última transcripción guardada")
                                    }
                                }
                            }
                            .padding(8)
                            .modifier(GlassCard())
                        }
                    }
                    Text("En grabaciones combinadas, la reproducción y el MP3 incluyen sistema y micrófono.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
        }
        .background(GlassBackground().ignoresSafeArea())
        .scrollIndicators(.visible)
        .onChange(of: transcriber.busy) { busy in if !busy && !model.busy { model.reload() } }
        .onChange(of: scenePhase) { phase in if phase == .active && !model.busy { model.reload() } }
        .sheet(isPresented: $settingsPresented) {
            DeepgramSettingsView { transcriber.refreshKeyStatus() }
        }
        .sheet(item: $transcriptionTarget) { recording in
            TranscriptionOptionsView(recording: recording, hasKey: transcriber.hasKey) { language in
                transcriber.start(recording, language: language)
            }
        }
        .alert("ChaceRecordings", isPresented: Binding(get: { model.error != nil || transcriber.error != nil }, set: { if !$0 { model.error = nil; transcriber.error = nil } })) {
            Button("Aceptar") { model.error = nil; transcriber.error = nil }
        } message: { Text(model.error ?? transcriber.error ?? "") }
    }

    private var recordingTime: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(clock(model.elapsed))
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .monospacedDigit()
            HStack(spacing: 5) {
                Circle().fill(model.busy && !model.paused ? Color.red : Color.secondary).frame(width: 6, height: 6)
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var recordingButtons: some View {
        HStack(spacing: 6) {
            if model.phase == .recording {
                Button { model.togglePause() } label: {
                    Label(model.paused ? "Reanudar" : "Pausar", systemImage: model.paused ? "play.fill" : "pause.fill")
                }
                Button { model.stop() } label: { Label("Guardar", systemImage: "stop.fill") }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .help("Detener y guardar la grabación")
            } else {
                Button { model.start() } label: { Label("Grabar", systemImage: "record.circle") }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .disabled(model.busy)
            }
        }
        .controlSize(.regular)
        .fixedSize()
    }

    private var status: String {
        switch model.phase {
        case .idle: return "Listo para grabar"
        case .starting: return "Preparando captura…"
        case .recording: return model.paused ? "Grabación pausada" : "Grabando"
        case .stopping: return "Guardando grabación…"
        }
    }
}

struct FloatingControls: View {
    @ObservedObject var model: Recorder
    var body: some View {
        HStack(spacing: 16) {
            Circle().fill(model.paused ? Color.orange : .red).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.paused ? "En pausa" : "Grabando").font(.caption.bold())
                Text(clock(model.elapsed)).font(.system(.body, design: .monospaced)).monospacedDigit()
            }
            Spacer()
            Button { model.togglePause() } label: { Image(systemName: model.paused ? "play.fill" : "pause.fill") }
                .help(model.paused ? "Reanudar" : "Pausar")
            Button { model.stop() } label: { Image(systemName: "stop.fill").foregroundStyle(.red) }
                .help("Detener y guardar")
        }
        .buttonStyle(.borderless)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct InputMonitors: View {
    @ObservedObject var monitor: AudioMonitor
    let source: AudioSource
    let paused: Bool
    let recording: Bool

    var body: some View {
        VStack(spacing: 8) {
            WaveformView(title: "Sistema", values: monitor.system, enabled: source.needsSystem, receiving: monitor.systemReceiving, paused: paused, recording: recording, color: .indigo)
            WaveformView(title: "Micrófono", values: monitor.microphone, enabled: source.needsMicrophone, receiving: monitor.microphoneReceiving, paused: paused, recording: recording, color: .teal)
        }
    }
}

struct WaveformView: View {
    let title: String
    let values: [Float]
    let enabled: Bool
    let receiving: Bool
    let paused: Bool
    let recording: Bool
    let color: Color

    private var status: String {
        if !enabled { return "Desactivado" }
        if paused { return "En pausa" }
        if !recording { return "En espera" }
        if !receiving { return "Sin datos de audio" }
        return (values.suffix(8).max() ?? 0) > 0.08 ? "Audio detectado" : "Silencio / nivel bajo"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.caption.bold())
                Spacer()
                Text(status).font(.caption2).foregroundStyle(.secondary)
            }
            // A single canvas draws all 64 bars: no per-bar views or animation loops.
            Canvas { context, size in
                let step = size.width / CGFloat(values.count)
                let width = max(1, step * 0.55)
                var bars = Path()
                for index in values.indices {
                    let height = max(1, CGFloat(values[index]) * size.height)
                    let rect = CGRect(x: CGFloat(index) * step + (step - width) / 2,
                                      y: (size.height - height) / 2, width: width, height: height)
                    bars.addRoundedRect(in: rect, cornerSize: CGSize(width: width / 2, height: width / 2))
                }
                context.fill(bars, with: .color(enabled ? color : .gray.opacity(0.3)))
            }
            .frame(height: 34)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio de \(title): \(status)")
    }
}
