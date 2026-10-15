using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace ChaceRecordings;

public sealed class RecordingAudio : ISampleProvider, IDisposable
{
    private readonly List<TrackSequence> tracks;
    private readonly MixingSampleProvider mixer;
    public WaveFormat WaveFormat => mixer.WaveFormat;
    public RecordingAudio(Recording recording)
    {
        tracks = new[] { recording.SystemParts, recording.MicrophoneParts }.Where(p => p.Count > 0).Select(p => new TrackSequence(recording.Folder, p)).ToList();
        if (tracks.Count == 0) throw new InvalidOperationException("La grabación no tiene pistas disponibles.");
        mixer = new MixingSampleProvider(tracks) { ReadFully = false };
    }
    public int Read(float[] buffer, int offset, int count)
    {
        int read = mixer.Read(buffer, offset, count);
        if (tracks.Count > 1) for (int i = offset; i < offset + read; i++) buffer[i] /= tracks.Count;
        return read;
    }
    public void Dispose() { foreach (var track in tracks) track.Dispose(); }
    public static void ExportMp3(Recording recording, string output)
    {
        NAudio.MediaFoundation.MediaFoundationApi.Startup();
        using var audio = new RecordingAudio(recording);
        MediaFoundationEncoder.EncodeToMp3(audio.ToWaveProvider16(), output, 192000);
    }
}

internal sealed class TrackSequence : ISampleProvider, IDisposable
{
    private readonly string folder;
    private readonly Queue<string> parts;
    private WaveFileReader? reader;
    private ISampleProvider? current;
    public WaveFormat WaveFormat { get; } = WaveFormat.CreateIeeeFloatWaveFormat(48000, 2);
    public TrackSequence(string folder, IEnumerable<string> parts) { this.folder = folder; this.parts = new Queue<string>(parts); }
    private bool Next()
    {
        reader?.Dispose(); reader = null; current = null;
        if (parts.Count == 0) return false;
        string name = parts.Dequeue();
        if (Path.GetFileName(name) != name) throw new InvalidOperationException("Ruta de pista inválida.");
        reader = new WaveFileReader(Path.Combine(folder, name));
        ISampleProvider sample = reader.ToSampleProvider();
        if (sample.WaveFormat.Channels == 1) sample = new MonoToStereoSampleProvider(sample);
        else if (sample.WaveFormat.Channels != 2) sample = new MultiplexingSampleProvider(new[] { sample }, 2);
        if (sample.WaveFormat.SampleRate != 48000) sample = new WdlResamplingSampleProvider(sample, 48000);
        current = sample; return true;
    }
    public int Read(float[] buffer, int offset, int count)
    {
        int total = 0;
        while (total < count)
        {
            if (current == null && !Next()) break;
            int read = current!.Read(buffer, offset + total, count - total);
            total += read;
            if (read == 0 && !Next()) break;
        }
        return total;
    }
    public void Dispose() { reader?.Dispose(); reader = null; }
}
