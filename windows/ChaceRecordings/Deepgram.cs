using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace ChaceRecordings;

public static class Deepgram
{
    public static async Task<string> TranscribeAsync(Recording recording, string language, IProgress<string> progress, CancellationToken cancellation)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(TimeSpan.FromHours(2));
        cancellation = timeout.Token;
        string key = SecretStore.Read() ?? throw new InvalidOperationException("Añade tu API key en Ajustes.");
        string probe = Path.Combine(recording.Folder, ".write-" + Guid.NewGuid().ToString("N"));
        File.WriteAllText(probe, ""); File.Delete(probe);
        string audio = Path.Combine(Path.GetTempPath(), "chace-" + Guid.NewGuid().ToString("N") + ".mp3");
        try
        {
            progress.Report("Preparando audio…");
            await Task.Run(() => RecordingAudio.ExportMp3(recording, audio), cancellation);
            cancellation.ThrowIfCancellationRequested();
            progress.Report("Enviando y transcribiendo…");
            using var handler = new HttpClientHandler { AllowAutoRedirect = false };
            using var client = new HttpClient(handler) { Timeout = TimeSpan.FromHours(2) };
            using var request = new HttpRequestMessage(HttpMethod.Post, DeepgramProtocol.Endpoint(language));
            request.Headers.Authorization = new AuthenticationHeaderValue("Token", key);
            await using var stream = File.OpenRead(audio);
            request.Content = new StreamContent(stream);
            request.Content.Headers.ContentType = new MediaTypeHeaderValue("audio/mpeg");
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellation);
            if (!response.IsSuccessStatusCode)
            {
                string detail = (int)response.StatusCode switch
                {
                    401 or 403 => "Clave inválida o sin permisos. Revisa Ajustes.",
                    402 => "No hay saldo disponible en Deepgram.",
                    413 => "El audio supera el tamaño admitido por Deepgram.",
                    429 => "Deepgram indica un límite de uso. Inténtalo más tarde.",
                    _ => $"Deepgram rechazó la petición (HTTP {(int)response.StatusCode})."
                };
                throw new InvalidOperationException(detail);
            }
            string json = await response.Content.ReadAsStringAsync(cancellation);
            string text = DeepgramProtocol.Parse(json, recording.Name, language);
            string path = Path.Combine(recording.Folder, $"Transcripcion-{language}-{DateTime.Now:yyyy-MM-dd_HH-mm-ss}-{Guid.NewGuid().ToString("N")[..6]}.txt");
            AtomicFile.Write(path, text);
            return path;
        }
        finally { if (File.Exists(audio)) File.Delete(audio); }
    }
}
