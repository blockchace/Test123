using System;
using System.Text;
using System.Text.Json;

namespace ChaceRecordings;
public static class DeepgramProtocol
{
    public static Uri Endpoint(string language)
    {
        if (language is not ("es" or "en" or "multi")) throw new ArgumentException("Idioma no admitido.");
        return new Uri($"https://api.deepgram.com/v1/listen?model=nova-3&language={language}&smart_format=true&punctuate=true&diarize=true&utterances=true");
    }
    public static string Parse(string json, string name, string language)
    {
        using var document = JsonDocument.Parse(json);
        if (!document.RootElement.TryGetProperty("results", out var results)) throw new InvalidOperationException("Respuesta de Deepgram sin resultados.");
        var text = new StringBuilder();
        text.AppendLine(name).AppendLine($"Modelo: Nova 3 · Idioma: {language}").AppendLine();
        bool found = false;
        if (results.TryGetProperty("utterances", out var utterances) && utterances.ValueKind == JsonValueKind.Array)
        {
            foreach (var utterance in utterances.EnumerateArray())
            {
                string? phrase = utterance.GetProperty("transcript").GetString();
                if (string.IsNullOrWhiteSpace(phrase)) continue;
                double start = utterance.TryGetProperty("start", out var s) ? s.GetDouble() : 0;
                int seconds = Math.Max(0, (int)start);
                string speaker = utterance.TryGetProperty("speaker", out var p) && p.ValueKind == JsonValueKind.Number ? $" · Hablante {p.GetInt32() + 1}" : "";
                text.AppendLine($"[{seconds / 3600:D2}:{seconds / 60 % 60:D2}:{seconds % 60:D2}{speaker}]").AppendLine(phrase).AppendLine();
                found = true;
            }
        }
        if (!found && results.TryGetProperty("channels", out var channels) && channels.GetArrayLength() > 0)
        {
            var alternatives = channels[0].GetProperty("alternatives");
            string? phrase = alternatives.GetArrayLength() > 0 ? alternatives[0].GetProperty("transcript").GetString() : null;
            if (!string.IsNullOrWhiteSpace(phrase)) { text.AppendLine(phrase); found = true; }
        }
        if (!found) throw new InvalidOperationException("No se reconoció voz. Comprueba el audio y el idioma.");
        return text.ToString();
    }

}
