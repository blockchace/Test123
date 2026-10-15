using ChaceRecordings;
using NAudio.Wave;
using Xunit;

public sealed class CoreTests
{
    [Theory]
    [InlineData("es")]
    [InlineData("en")]
    [InlineData("multi")]
    public void RequestsUseNova3AndChosenLanguage(string language)
    {
        var url = DeepgramProtocol.Endpoint(language);
        Assert.Equal("https", url.Scheme);
        Assert.Equal("api.deepgram.com", url.Host);
        Assert.Contains("model=nova-3", url.Query);
        Assert.Contains("language=" + language, url.Query);
        Assert.DoesNotContain("key", url.Query);
    }
    [Fact]
    public void TranscriptIncludesSpeakersAndUnicode()
    {
        string result = DeepgramProtocol.Parse("""{"results":{"utterances":[{"start":4,"speaker":0,"transcript":"Hola, ¿cómo estás?"},{"start":9,"speaker":1,"transcript":"Very well."}]}}""", "Conversación", "multi");
        Assert.Contains("Hablante 1", result); Assert.Contains("00:00:04", result); Assert.Contains("¿cómo estás?", result); Assert.Contains("Very well.", result);
    }
    [Fact]
    public void MissingSpeechAndInvalidLanguageFail()
    {
        Assert.Throws<ArgumentException>(() => DeepgramProtocol.Endpoint("invalid"));
        Assert.Throws<InvalidOperationException>(() => DeepgramProtocol.Parse("{}", "Test", "es"));
        Assert.Throws<InvalidOperationException>(() => DeepgramProtocol.Parse("""{"results":{"channels":[{"alternatives":[{"transcript":""}]}]}}""", "Test", "en"));
    }
    [Fact]
    public void ExistingTranscriptIsFoundAfterReloadWithoutNetwork()
    {
        string root = Temporary();
        string folder = Directory.CreateDirectory(Path.Combine(root, "session")).FullName;
        try
        {
            var record = new Recording { Folder = folder, Name = "Entrevista", Duration = 4 };
            record.Save(); Assert.Null(record.Transcript);
            string text = Path.Combine(folder, "Transcripcion-es.txt"); File.WriteAllText(text, "Hola");
            Assert.Equal(text, record.Transcript);
            var preferences = new Preferences { Folder = root };
            var restored = Recording.LoadLibraries(preferences).Single(r => r.Folder == folder);
            Assert.Equal("Entrevista", restored.Name); Assert.Equal(text, restored.Transcript);
        }
        finally { Directory.Delete(root, true); }
    }
    [Fact]
    public void WavSegmentsRotateAndSilencePaddingKeepsDuration()
    {
        string folder = Temporary();
        try
        {
            var record = new Recording { Folder = folder };
            // A small segment cap exercises the same rollover used before WAV's size limit.
            using (var writer = new SegmentWriter(record, new WaveFormatExtensible(48000, 32, 2), false, 1024))
            {
                writer.PadTo(300); writer.Flush();
            }
            Assert.Equal(3, record.SystemParts.Count);
            long frames = 0;
            foreach (string part in record.SystemParts)
            {
                using var reader = new WaveFileReader(Path.Combine(folder, part));
                Assert.Equal(WaveFormatEncoding.IeeeFloat, reader.WaveFormat.Encoding);
                frames += reader.Length / reader.WaveFormat.BlockAlign;
                Assert.InRange(reader.Length, 1L, 1024L);
            }
            Assert.Equal(300, frames);
        }
        finally { Directory.Delete(folder, true); }
    }
    [Fact]
    public void SegmentedStereoAndMicrophoneMixAsOneContinuousRecording()
    {
        string folder = Temporary();
        try
        {
            var record = new Recording { Folder = folder };
            MakeWave(folder, "system-0.wav", 48000, 2, .25f, 2400);
            MakeWave(folder, "system-1.wav", 48000, 2, .25f, 2400);
            MakeWave(folder, "mic-0.wav", 48000, 1, .5f, 4800);
            record.SystemParts.AddRange(new[] { "system-0.wav", "system-1.wav" }); record.MicrophoneParts.Add("mic-0.wav");
            using var audio = new RecordingAudio(record);
            var buffer = new float[1024]; int total = 0, read;
            while ((read = audio.Read(buffer, 0, buffer.Length)) > 0)
            {
                for (int i = 0; i < read; i++) Assert.InRange(buffer[i], .374f, .376f);
                total += read;
            }
            Assert.Equal(9600, total);
        }
        finally { Directory.Delete(folder, true); }
    }
    private static void MakeWave(string folder, string name, int rate, int channels, float value, int frames)
    {
        using var writer = new WaveFileWriter(Path.Combine(folder, name), WaveFormat.CreateIeeeFloatWaveFormat(rate, channels));
        var data = Enumerable.Repeat(value, frames * channels).ToArray(); writer.WriteSamples(data, 0, data.Length);
    }
    private static string Temporary() { string p = Path.Combine(Path.GetTempPath(), "chace-test-" + Guid.NewGuid()); Directory.CreateDirectory(p); return p; }
}
