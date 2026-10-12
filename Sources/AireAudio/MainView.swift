import SwiftUI

struct MainView: View {
    @ObservedObject var model: Recorder

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Image(systemName: "mic.circle.fill").font(.system(size: 36)).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Aire Audio").font(.title2.bold())
                    Text("Tu sonido, sin prisa.").foregroundStyle(.secondary)
                }
                Spacer()
                Text("SIN LÍMITE DE TIEMPO").font(.caption2.bold()).foregroundStyle(.secondary)
            }
            VStack(spacing: 20) {
                Picker("Fuente de audio", selection: $model.source) {
                    ForEach(AudioSource.allCases) { source in Text(source.rawValue).tag(source) }
                }
                .pickerStyle(.segmented)
                .disabled(model.busy)
                if model.source.needsMicrophone {
                    HStack {
                        Picker("Micrófono", selection: $model.selectedMicrophoneID) {
                            Text("Entrada predeterminada del Mac").tag("")
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
                VStack(spacing: 12) {
                    SpectrumView(title: "Sistema", values: model.systemSpectrum, enabled: model.source.needsSystem, receiving: model.systemReceiving, paused: model.paused, recording: model.phase == .recording, color: .indigo)
                    SpectrumView(title: "Micrófono", values: model.microphoneSpectrum, enabled: model.source.needsMicrophone, receiving: model.microphoneReceiving, paused: model.paused, recording: model.phase == .recording, color: .teal)
                }
                Text(clock(model.elapsed))
                    .font(.system(size: 54, weight: .light, design: .monospaced))
                    .monospacedDigit()
                HStack(spacing: 8) {
                    Circle().fill(model.busy && !model.paused ? Color.red : Color.secondary).frame(width: 8, height: 8)
                    Text(status).foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    if model.phase == .recording {
                        Button { model.togglePause() } label: {
                            Label(model.paused ? "Reanudar" : "Pausar", systemImage: model.paused ? "play.fill" : "pause.fill")
                                .frame(width: 115)
                        }
                        Button { model.stop() } label: { Label("Detener y guardar", systemImage: "stop.fill") }
                            .buttonStyle(.borderedProminent).tint(.red)
                    } else {
                        Button { model.start() } label: { Label("Grabar", systemImage: "record.circle").frame(width: 145) }
                            .buttonStyle(.borderedProminent).tint(.red)
                            .disabled(model.busy)
                    }
                }
                .controlSize(.large)
                Text("Se guarda en tu Mac. Las pausas se omiten del audio final.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))
            HStack {
                Text("Tus grabaciones").font(.headline)
                Spacer()
                if model.exporting { ProgressView().controlSize(.small); Text("Exportando MP3…").font(.caption) }
            }
            if model.recordings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform").font(.title).foregroundStyle(.secondary)
                    Text("Tu primera grabación empieza aquí.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 75)
            } else {
                    LazyVStack(spacing: 10) {
                        ForEach(model.recordings) { recording in
                            HStack(spacing: 12) {
                                Button { model.play(recording) } label: {
                                    Image(systemName: model.playingID == recording.id ? "stop.circle.fill" : "play.circle.fill").font(.title)
                                }.buttonStyle(.plain).disabled(model.busy)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recording.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.bold())
                                    Text("\(clock(recording.duration)) · \(recording.tracks.count == 2 ? "Sistema + micrófono" : recording.tracks[0].deletingPathExtension().lastPathComponent.capitalized)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { model.reveal(recording) } label: { Image(systemName: "folder") }
                                    .help("Mostrar pistas originales en Finder")
                                Button("Exportar MP3") { model.export(recording) }.disabled(model.exporting)
                            }
                            .padding(12)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                Text("En grabaciones combinadas, la reproducción y el MP3 incluyen sistema y micrófono.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.visible)
        .alert("Aire Audio", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("Aceptar") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var status: String {
        switch model.phase {
        case .idle: return "Listo para grabar"
        case .starting: return "Preparando captura…"
        case .recording: return model.paused ? "Grabación pausada" : "Grabando · \(model.source.rawValue)"
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

struct SpectrumView: View {
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
        if !recording { return "Se activa al grabar" }
        if !receiving { return "Sin datos de audio" }
        return (values.max() ?? 0) > 0.08 ? "Audio detectado" : "Silencio / nivel muy bajo"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption.bold())
                Spacer()
                Text(status).font(.caption2).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(values.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(enabled ? color : .gray.opacity(0.3))
                            .frame(width: max(1, (geometry.size.width - CGFloat(values.count - 1) * 3) / CGFloat(values.count)), height: max(2, CGFloat(values[index]) * geometry.size.height))
                    }
                }.frame(height: geometry.size.height, alignment: .bottom)
            }.frame(height: 42)
            HStack { Text("40 Hz"); Spacer(); Text("20 kHz") }
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Espectro de \(title): \(status)")
    }
}
