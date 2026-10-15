using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using System.Threading;
using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace ChaceRecordings;

public sealed class AudioRecorder
{
    private readonly object gate = new();
    private readonly Stopwatch clock = new();
    private readonly List<(WasapiCapture Capture, TaskCompletionSource Completion)> captures = new();
    private readonly List<SegmentWriter> writers = new();
    private bool accepting;
    private bool paused;
    private float systemPeak, microphonePeak;
    private Timer? checkpoint;
    private Exception? captureError;
    public Recording? Current { get; private set; }
    public bool IsRecording { get; private set; }
    public bool IsPaused => paused;
    public double Elapsed => clock.Elapsed.TotalSeconds;
    public event Action<Exception>? Failed;

    public void Start(string folder, bool system, bool microphone, MMDevice? output, MMDevice? input)
    {
        if (IsRecording) return;
        if ((!system && !microphone) || (system && output == null) || (microphone && input == null))
            throw new InvalidOperationException("Selecciona una entrada de audio disponible.");
        Directory.CreateDirectory(folder);
        string session = Path.Combine(folder, DateTime.Now.ToString("yyyy-MM-dd HH.mm.ss") + "-" + Guid.NewGuid().ToString("N")[..6]);
        Directory.CreateDirectory(session);
        Current = new Recording { Folder = session, Name = "Grabación " + DateTime.Now.ToString("yyyy-MM-dd HH.mm.ss") };
        Current.Save();
        paused = false;
        captureError = null;
        systemPeak = microphonePeak = 0;
        clock.Reset();
        try
        {
            if (system) AddCapture(new WasapiLoopbackCapture(output!), false);
            if (microphone) AddCapture(new WasapiCapture(input!), true);
            IsRecording = true;
            clock.Start();
            lock (gate) accepting = true;
            foreach (var capture in captures) capture.Capture.StartRecording();
            checkpoint = new Timer(_ => Checkpoint(), null, 1000, 1000);
        }
        catch
        {
            lock (gate) accepting = false;
            clock.Stop();
            foreach (var capture in captures) { try { capture.Capture.StopRecording(); } catch { } capture.Capture.Dispose(); }
            foreach (var writer in writers) writer.Dispose();
            captures.Clear(); writers.Clear(); IsRecording = false;
            throw;
        }
    }

    private void AddCapture(WasapiCapture capture, bool microphone)
    {
        var writer = new SegmentWriter(Current!, capture.WaveFormat, microphone);
        writers.Add(writer);
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        captures.Add((capture, completion));
        capture.DataAvailable += (_, e) =>
        {
            try
            {
                lock (gate)
                {
                    if (!accepting || paused) return;
                    long end = (long)(clock.Elapsed.TotalSeconds * capture.WaveFormat.SampleRate);
                    long frames = e.BytesRecorded / capture.WaveFormat.BlockAlign;
                    // Fill WASAPI loopback silence and align independently clocked inputs.
                    writer.PadTo(Math.Max(0, end - frames));
                    writer.Write(e.Buffer, 0, e.BytesRecorded);
                    float peak = Peak(e.Buffer, e.BytesRecorded, capture.WaveFormat);
                    if (microphone) microphonePeak = Math.Max(microphonePeak, peak); else systemPeak = Math.Max(systemPeak, peak);
                }
            }
            catch (Exception error)
            {
                lock (gate) { accepting = false; captureError ??= error; }
                Failed?.Invoke(error);
            }
        };
        capture.RecordingStopped += (_, e) =>
        {
            if (e.Exception != null) { lock (gate) captureError ??= e.Exception; }
            completion.TrySetResult();
            if (e.Exception != null) Failed?.Invoke(e.Exception);
        };
    }

    public void TogglePause()
    {
        lock (gate)
        {
            if (!IsRecording) return;
            paused = !paused;
            if (paused) { clock.Stop(); foreach (var writer in writers) writer.PadTo((long)(clock.Elapsed.TotalSeconds * writer.Format.SampleRate)); }
            else clock.Start();
            systemPeak = microphonePeak = 0;
        }
    }

    public (float System, float Microphone) TakePeaks()
    {
        lock (gate) { var result = (systemPeak, microphonePeak); systemPeak = microphonePeak = 0; return result; }
    }

    private void Checkpoint()
    {
        try
        {
            lock (gate)
            {
                if (!accepting || paused || Current == null) return;
                double seconds = clock.Elapsed.TotalSeconds;
                foreach (var writer in writers)
                {
                    // A quarter-second cushion leaves room for queued capture packets.
                    writer.PadTo((long)(Math.Max(0, seconds - .25) * writer.Format.SampleRate));
                    writer.Flush();
                }
                Current.Duration = seconds; Current.Save();
            }
        }
        catch (Exception error) { lock (gate) { accepting = false; captureError ??= error; } Failed?.Invoke(error); }
    }

    public async Task StopAsync()
    {
        if (!IsRecording) return;
        checkpoint?.Dispose(); checkpoint = null;
        lock (gate) { accepting = false; clock.Stop(); }
        Exception? failure = null;
        try
        {
            foreach (var capture in captures)
            {
                try { capture.Capture.StopRecording(); }
                catch (Exception error) { failure ??= error; capture.Completion.TrySetResult(); }
            }
            await Task.WhenAll(captures.ConvertAll(c => c.Completion.Task)).WaitAsync(TimeSpan.FromSeconds(10));
        }
        catch (Exception error) { failure ??= error; }
        finally
        {
            lock (gate)
            {
                failure ??= captureError;
                foreach (var capture in captures) { try { capture.Capture.Dispose(); } catch (Exception error) { failure ??= error; } }
                foreach (var writer in writers)
                {
                    try { writer.PadTo((long)(clock.Elapsed.TotalSeconds * writer.Format.SampleRate)); }
                    catch (Exception error) { failure ??= error; }
                    finally { try { writer.Dispose(); } catch (Exception error) { failure ??= error; } }
                }
                try { if (Current != null) { Current.Duration = clock.Elapsed.TotalSeconds; Current.Save(); } }
                catch (Exception error) { failure ??= error; }
                captures.Clear(); writers.Clear(); IsRecording = false; paused = false;
            }
        }
        if (failure != null) throw new IOException("La captura terminó con un error: " + failure.Message, failure);
    }

    private static float Peak(byte[] buffer, int length, WaveFormat format)
    {
        float peak = 0;
        bool floating = format.Encoding == WaveFormatEncoding.IeeeFloat || format is WaveFormatExtensible extended && extended.SubFormat == new Guid("00000003-0000-0010-8000-00aa00389b71");
        int bytes = format.BitsPerSample / 8;
        for (int i = 0; i + bytes <= length; i += Math.Max(1, bytes))
        {
            float value = floating && bytes == 4 ? BitConverter.ToSingle(buffer, i)
                : bytes == 2 ? BitConverter.ToInt16(buffer, i) / 32768f
                : bytes == 4 ? BitConverter.ToInt32(buffer, i) / 2147483648f
                : bytes == 3 ? ((buffer[i] | buffer[i + 1] << 8 | buffer[i + 2] << 16) << 8 >> 8) / 8388608f : 0;
            if (float.IsFinite(value)) peak = Math.Max(peak, Math.Abs(value));
        }
        return Math.Min(1, peak);
    }
}

internal sealed class SegmentWriter : IDisposable
{
    private readonly Recording recording;
    private readonly bool microphone;
    private WaveFileWriter? writer;
    private readonly byte[] zeros = new byte[65536];
    private long frames;
    private long partBytes;
    private readonly long segmentLimit;
    public WaveFormat Format { get; }
    public SegmentWriter(Recording recording, WaveFormat format, bool microphone, long segmentLimit = 256L * 1024 * 1024)
    {
        this.recording = recording; this.microphone = microphone;
        if (format is WaveFormatExtensible extended)
        {
            var encoding = extended.SubFormat == new Guid("00000003-0000-0010-8000-00aa00389b71") ? WaveFormatEncoding.IeeeFloat
                : extended.SubFormat == new Guid("00000001-0000-0010-8000-00aa00389b71") ? WaveFormatEncoding.Pcm
                : throw new InvalidOperationException("Formato WASAPI no compatible.");
            Format = WaveFormat.CreateCustomFormat(encoding, format.SampleRate, format.Channels, format.AverageBytesPerSecond, format.BlockAlign, format.BitsPerSample);
        }
        else Format = format;
        if (format.BlockAlign <= 0 || format.BlockAlign > zeros.Length) throw new InvalidOperationException("Formato de entrada no admitido.");
        if (segmentLimit < format.BlockAlign) throw new ArgumentOutOfRangeException(nameof(segmentLimit));
        this.segmentLimit = segmentLimit - segmentLimit % format.BlockAlign;
    }
    public void PadTo(long target)
    {
        while (frames < target)
        {
            int count = (int)Math.Min(zeros.Length / Format.BlockAlign, target - frames) * Format.BlockAlign;
            Write(zeros, 0, count);
        }
    }
    public void Write(byte[] bytes, int offset, int count)
    {
        count -= count % Format.BlockAlign;
        while (count > 0)
        {
            if (writer == null || partBytes >= segmentLimit)
            {
                writer?.Dispose();
                var parts = microphone ? recording.MicrophoneParts : recording.SystemParts;
                string name = $"{(microphone ? "microfono" : "sistema")}-{parts.Count:D5}.wav";
                writer = new WaveFileWriter(Path.Combine(recording.Folder, name), Format);
                parts.Add(name); partBytes = 0; recording.Save();
            }
            int available = (int)(segmentLimit - partBytes);
            available -= available % Format.BlockAlign;
            int length = Math.Min(count, available);
            writer.Write(bytes, offset, length);
            offset += length; count -= length; partBytes += length; frames += length / Format.BlockAlign;
        }
    }
    public void Dispose() { writer?.Dispose(); writer = null; }
    public void Flush() => writer?.Flush();
}
