using ChaceRecordings;
using NAudio.Wave;
using System.Security.Cryptography;
using Xunit;

public sealed class WindowsFactAttribute : FactAttribute
{
    public WindowsFactAttribute() { if (!OperatingSystem.IsWindows()) Skip = "Necesita Windows real y Media Foundation/DPAPI."; }
}
public sealed class WindowsTests
{
    [WindowsFact]
    public void NativeEncoderProducesPlayableMp3()
    {
        string folder = Path.Combine(Path.GetTempPath(), "chace-mp3-" + Guid.NewGuid()); Directory.CreateDirectory(folder);
        try
        {
            string wav = Path.Combine(folder, "microfono.wav");
            using (var writer = new WaveFileWriter(wav, WaveFormat.CreateIeeeFloatWaveFormat(48000, 1)))
            {
                var samples = Enumerable.Range(0, 48000).Select(i => (float)(.2 * Math.Sin(2 * Math.PI * 440 * i / 48000))).ToArray();
                writer.WriteSamples(samples, 0, samples.Length);
            }
            var record = new Recording { Folder = folder }; record.MicrophoneParts.Add("microfono.wav");
            string mp3 = Path.Combine(folder, "output.mp3"); RecordingAudio.ExportMp3(record, mp3);
            Assert.True(new FileInfo(mp3).Length > 1000);
            using var reader = new MediaFoundationReader(mp3);
            Assert.InRange(reader.TotalTime.TotalSeconds, .9, 1.2);
            Assert.True(reader.Read(new byte[4096], 0, 4096) > 0);
        }
        finally { Directory.Delete(folder, true); }
    }
    [WindowsFact]
    public void WindowsUserProtectionRoundTripsWithoutWritingARealKey()
    {
        if (!OperatingSystem.IsWindows()) return;
        byte[] sample = System.Text.Encoding.UTF8.GetBytes("test-data-not-a-key");
        byte[] encrypted = ProtectedData.Protect(sample, null, DataProtectionScope.CurrentUser);
        Assert.NotEqual(sample, encrypted);
        Assert.Equal(sample, ProtectedData.Unprotect(encrypted, null, DataProtectionScope.CurrentUser));
    }
}
