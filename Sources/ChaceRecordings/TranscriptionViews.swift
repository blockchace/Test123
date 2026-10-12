import SwiftUI

struct DeepgramSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var message: String?
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Ajustes · Deepgram", systemImage: "gearshape").font(.headline)
            Text("API key").font(.caption.bold())
            SecureField("Pega tu clave de Deepgram", text: $key).textFieldStyle(.roundedBorder)
            Text("La clave se guarda en el Llavero de este Mac. No se incluye en el instalador ni en las grabaciones.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Modelo de transcripción: Nova 3").font(.caption)
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Eliminar clave", role: .destructive) {
                    do { try DeepgramKeychain.delete(); key = ""; message = nil; onChange() }
                    catch { message = error.localizedDescription }
                }
                Spacer()
                Button("Cerrar") { dismiss() }
                Button("Guardar") {
                    do { try DeepgramKeychain.save(key); onChange(); dismiss() }
                    catch { message = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20).frame(width: 380)
        .onAppear {
            do { key = try DeepgramKeychain.load() ?? "" }
            catch { message = error.localizedDescription }
        }
        .onDisappear { key = "" }
    }
}

struct TranscriptionOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var language = TranscriptionLanguage(rawValue: UserDefaults.standard.string(forKey: "deepgramLanguage") ?? "es") ?? .spanish
    let recording: Recording
    let hasKey: Bool
    let onStart: (TranscriptionLanguage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Transcribir grabación", systemImage: "text.bubble").font(.headline)
            Text(recording.name).font(.subheadline).lineLimit(2)
            Picker("Idioma", selection: $language) {
                ForEach(TranscriptionLanguage.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            Text("Modelo: Nova 3. Multilingüe permite alternar entre español e inglés.")
                .font(.caption).foregroundStyle(.secondary)
            Text("El audio se enviará a Deepgram y consumirá tus créditos. El TXT se guardará en la carpeta de esta grabación.")
                .font(.caption).foregroundStyle(.secondary)
            if !hasKey {
                Text("Añade tu API key con el botón Ajustes de la ventana principal.").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Transcribir") {
                    UserDefaults.standard.set(language.rawValue, forKey: "deepgramLanguage")
                    onStart(language)
                    dismiss()
                }
                .buttonStyle(.borderedProminent).disabled(!hasKey)
            }
        }.padding(20).frame(width: 380)
    }
}
