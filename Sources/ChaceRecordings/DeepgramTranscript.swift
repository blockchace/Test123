import Foundation

enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case spanish = "es", english = "en", multilingual = "multi"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spanish: return "Español"
        case .english: return "Inglés"
        case .multilingual: return "Multilingüe"
        }
    }
}

enum DeepgramTranscript {
    static func endpoint(language: TranscriptionLanguage) -> URL {
        var url = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        url.queryItems = [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "language", value: language.rawValue),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "diarize", value: "true"),
            URLQueryItem(name: "utterances", value: "true")
        ]
        return url.url!
    }

    private struct Response: Decodable {
        let results: Results?
        struct Results: Decodable {
            let channels: [Channel]?
            let utterances: [Utterance]?
        }
        struct Channel: Decodable { let alternatives: [Alternative] }
        struct Alternative: Decodable { let transcript: String }
        struct Utterance: Decodable { let start: Double; let speaker: Int?; let transcript: String }
    }

    static func text(from data: Data, name: String, language: TranscriptionLanguage) throws -> String {
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw AppError("Deepgram devolvió una respuesta que no se pudo interpretar. No se guardó un TXT incompleto.") }
        let paragraphs = (response.results?.utterances ?? []).compactMap { utterance -> String? in
            guard !utterance.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let speaker = utterance.speaker.map { " · Hablante \($0 + 1)" } ?? ""
            return "[\(clock(utterance.start))\(speaker)]\n\(utterance.transcript)"
        }
        let body = paragraphs.isEmpty
            ? response.results?.channels?.first?.alternatives.first?.transcript ?? ""
            : paragraphs.joined(separator: "\n\n")
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError("Deepgram no reconoció voz en esta grabación. Comprueba el audio y el idioma elegido.")
        }
        return "\(name)\nModelo: Nova 3 · Idioma: \(language.title)\n\n\(body)\n"
    }

    static func validate(status: Int) throws {
        switch status {
        case 200..<300: return
        case 401, 403: throw AppError("Deepgram rechazó la clave o sus permisos. Compruébala en Ajustes y en tu proyecto de Deepgram.")
        case 402: throw AppError("Deepgram indica que no hay saldo disponible. Revisa los créditos de tu cuenta.")
        case 413: throw AppError("El audio supera el tamaño admitido por Deepgram. La grabación original se conserva.")
        case 429: throw AppError("Deepgram alcanzó un límite de uso o solicitudes. Revisa tu cuenta y vuelve a intentarlo más tarde.")
        case 500..<600: throw AppError("Deepgram no está disponible en este momento. Inténtalo más tarde.")
        default: throw AppError("Deepgram rechazó la petición (HTTP \(status)). Revisa la disponibilidad de Nova 3 y el idioma en tu cuenta.")
        }
    }
}
