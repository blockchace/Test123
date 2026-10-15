using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using NAudio.CoreAudioApi;
using NAudio.Wave;
using Forms = System.Windows.Forms;

namespace ChaceRecordings;

public partial class MainWindow : Window
{
    private readonly Preferences preferences = Preferences.Load();
    private readonly AudioRecorder recorder = new();
    private readonly MMDeviceEnumerator devices = new();
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1.0 / 30) };
    private readonly Forms.NotifyIcon tray = new();
    private List<MMDevice> microphones = new(), outputs = new();
    private WaveOutEvent? playback;
    private RecordingAudio? playbackAudio;
    private Recording? playing;
    private Window? floating;
    private Button? floatingPause;
    private TextBlock? floatingText;
    private bool working, stopping, resumeAfterSleep;

    public MainWindow()
    {
        InitializeComponent();
        MicWave.Color = Brushes.Turquoise;
        FolderText.Text = preferences.Folder; FolderText.ToolTip = preferences.Folder;
        try { Directory.CreateDirectory(preferences.Folder); preferences.Save(); RefreshDevices(); Reload(); }
        catch (Exception error) { Error(error); }
        timer.Tick += (_, _) => Tick();
        recorder.Failed += error => Dispatcher.BeginInvoke(async () => { if (recorder.IsRecording && !stopping) { Error(error); await StopRecording(); } });
        tray.Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? System.Drawing.SystemIcons.Application;
        tray.Text = "ChaceRecordings"; tray.Visible = true;
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Mostrar", null, (_, _) => Dispatcher.Invoke(ShowMain));
        menu.Items.Add("Pausar / reanudar", null, (_, _) => Dispatcher.Invoke(TogglePause));
        menu.Items.Add("Detener y guardar", null, (_, _) => Dispatcher.InvokeAsync(async () => await StopRecording()));
        menu.Items.Add("Salir", null, (_, _) => Dispatcher.Invoke(Close));
        tray.ContextMenuStrip = menu;
        tray.DoubleClick += (_, _) => Dispatcher.Invoke(ShowMain);
        SourceInitialized += (_, _) => ApplyMica();
        Microsoft.Win32.SystemEvents.PowerModeChanged += PowerChanged;
    }

    private void ApplyMica()
    {
        int backdrop = 2;
        var handle = new WindowInteropHelper(this).Handle;
        int dark = 1;
        DwmSetWindowAttribute(handle, 20, ref dark, sizeof(int));
        if (DwmSetWindowAttribute(handle, 38, ref backdrop, sizeof(int)) == 0)
        {
            var margins = new Margins { Left = -1, Right = -1, Top = -1, Bottom = -1 };
            DwmExtendFrameIntoClientArea(handle, ref margins);
            Background = Brushes.Transparent;
        }
    }
    [StructLayout(LayoutKind.Sequential)] private struct Margins { public int Left, Right, Top, Bottom; }
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);
    [DllImport("dwmapi.dll")] private static extern int DwmExtendFrameIntoClientArea(IntPtr window, ref Margins margins);
    [DllImport("kernel32.dll")] private static extern uint SetThreadExecutionState(uint flags);

    private void RefreshDevices()
    {
        if (recorder.IsRecording) return;
        foreach (var device in microphones.Concat(outputs)) device.Dispose();
        microphones = devices.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active).ToList();
        outputs = devices.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active).ToList();
        MicrophoneBox.ItemsSource = microphones; OutputBox.ItemsSource = outputs;
        string? defaultMicrophone = null, defaultOutput = null;
        try { using var d = devices.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Multimedia); defaultMicrophone = d.ID; } catch { }
        try { using var d = devices.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia); defaultOutput = d.ID; } catch { }
        MicrophoneBox.SelectedItem = microphones.FirstOrDefault(d => d.ID == preferences.Microphone) ?? microphones.FirstOrDefault(d => d.ID == defaultMicrophone) ?? microphones.FirstOrDefault();
        OutputBox.SelectedItem = outputs.FirstOrDefault(d => d.ID == preferences.Output) ?? outputs.FirstOrDefault(d => d.ID == defaultOutput) ?? outputs.FirstOrDefault();
    }
    private void RefreshDevicesClick(object sender, RoutedEventArgs e) { try { RefreshDevices(); } catch (Exception error) { Error(error); } }
    private void Reload() { if (!recorder.IsRecording) RecordingList.ItemsSource = Recording.LoadLibraries(preferences); }
    private void WindowActivated(object? sender, EventArgs e) { if (IsInitialized && !working && !recorder.IsRecording) Reload(); }
    private void ShowMain() { Show(); WindowState = WindowState.Normal; Activate(); }
    private void Error(Exception error) => MessageBox.Show(this, error.Message + "\nLos audios originales se conservan.", "ChaceRecordings", MessageBoxButton.OK, MessageBoxImage.Information);
    private static void Open(string path) => Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
    private static Recording Row(object sender) => (Recording)((Button)sender).Tag;

    private void RecordClick(object sender, RoutedEventArgs e)
    {
        if (working || recorder.IsRecording) return;
        try
        {
            StopPlayback();
            preferences.Microphone = (MicrophoneBox.SelectedItem as MMDevice)?.ID;
            preferences.Output = (OutputBox.SelectedItem as MMDevice)?.ID; preferences.Save();
            recorder.Start(preferences.Folder, SourceBox.SelectedIndex != 2, SourceBox.SelectedIndex != 1, OutputBox.SelectedItem as MMDevice, MicrophoneBox.SelectedItem as MMDevice);
            SourceBox.IsEnabled = MicrophoneBox.IsEnabled = OutputBox.IsEnabled = RecordButton.IsEnabled = false;
            PauseButton.IsEnabled = StopButton.IsEnabled = true;
            StateText.Text = "Grabando"; tray.Text = "ChaceRecordings · REC";
            SetThreadExecutionState(0x80000001); // Prevent idle system sleep; allow the display to turn off.
            ShowFloating(); timer.Start();
        }
        catch (Exception error) { Error(error); }
    }
    private void Tick()
    {
        int seconds = (int)recorder.Elapsed;
        string clock = $"{seconds / 3600:D2}:{seconds / 60 % 60:D2}:{seconds % 60:D2}";
        ClockText.Text = clock;
        if (floatingText != null) floatingText.Text = (recorder.IsPaused ? "En pausa · " : "● REC · ") + clock;
        var peaks = recorder.TakePeaks(); SystemWave.Push(peaks.System); MicWave.Push(peaks.Microphone);
    }
    private void PauseClick(object sender, RoutedEventArgs e) => TogglePause();
    private void TogglePause()
    {
        if (!recorder.IsRecording || stopping) return;
        try
        {
            recorder.TogglePause(); PauseButton.Content = recorder.IsPaused ? "Reanudar" : "Pausar";
            if (floatingPause != null) floatingPause.Content = PauseButton.Content;
            StateText.Text = recorder.IsPaused ? "En pausa" : "Grabando";
            SetThreadExecutionState(recorder.IsPaused ? 0x80000000u : 0x80000001u);
            tray.Text = "ChaceRecordings · " + StateText.Text;
            if (recorder.IsPaused) { Tick(); timer.Stop(); SystemWave.Clear(); MicWave.Clear(); } else timer.Start();
        }
        catch (Exception error) { Error(error); }
    }
    private async void StopClick(object sender, RoutedEventArgs e) => await StopRecording();
    private async Task StopRecording()
    {
        if (!recorder.IsRecording || stopping) return;
        stopping = true; StopButton.IsEnabled = PauseButton.IsEnabled = false; timer.Stop();
        try { await recorder.StopAsync(); StateText.Text = "Guardado"; }
        catch (Exception error) { Error(error); }
        finally
        {
            stopping = false; floating?.Close(); floating = null; floatingText = null; floatingPause = null;
            SetThreadExecutionState(0x80000000);
            RecordButton.IsEnabled = SourceBox.IsEnabled = MicrophoneBox.IsEnabled = OutputBox.IsEnabled = true;
            PauseButton.Content = "Pausar"; tray.Text = "ChaceRecordings";
            SystemWave.Clear(); MicWave.Clear(); resumeAfterSleep = false; Reload();
        }
    }
    private void ShowFloating()
    {
        floatingText = new TextBlock { Foreground = Brushes.White, VerticalAlignment = VerticalAlignment.Center, Text = "● REC" };
        floatingPause = new Button { Content = "Pausar" }; floatingPause.Click += (_, _) => TogglePause();
        var stop = new Button { Content = "■" }; stop.Click += async (_, _) => await StopRecording();
        var layout = new DockPanel(); DockPanel.SetDock(stop, Dock.Right); layout.Children.Add(stop); DockPanel.SetDock(floatingPause, Dock.Right); layout.Children.Add(floatingPause); layout.Children.Add(floatingText);
        floating = new Window { Width = 330, Height = 64, WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize, AllowsTransparency = true, Background = Brushes.Transparent, Topmost = true, ShowInTaskbar = false, ShowActivated = false, Left = SystemParameters.WorkArea.Right - 350, Top = SystemParameters.WorkArea.Top + 24,
            Content = new Border { Background = new SolidColorBrush(Color.FromArgb(245, 35, 39, 56)), CornerRadius = new CornerRadius(12), Padding = new Thickness(12), Child = layout } };
        floatingText.MouseLeftButtonDown += (_, _) => floating?.DragMove(); floating.Show();
    }
    private void FolderClick(object sender, RoutedEventArgs e)
    {
        if (working || recorder.IsRecording) return;
        using var dialog = new Forms.FolderBrowserDialog { SelectedPath = preferences.Folder, Description = "Guardar nuevas grabaciones en…", UseDescriptionForTitle = true };
        if (dialog.ShowDialog() != Forms.DialogResult.OK) return;
        try
        {
            string probe = Path.Combine(dialog.SelectedPath, ".chace-" + Guid.NewGuid().ToString("N")); File.WriteAllText(probe, ""); File.Delete(probe);
            preferences.Folder = dialog.SelectedPath; preferences.Save(); FolderText.Text = preferences.Folder; FolderText.ToolTip = preferences.Folder; Reload();
        }
        catch (Exception error) { Error(error); }
    }
    private void SettingsClick(object sender, RoutedEventArgs e) { if (!working) { try { Dialogs.Settings(this); } catch (Exception error) { Error(error); } } }
    private void RenameClick(object sender, RoutedEventArgs e)
    {
        if (working || recorder.IsRecording) return;
        var item = Row(sender); string? name = Dialogs.Text(this, "Nombre de la grabación", item.Name);
        if (name == null) return;
        try { Recording.ValidateName(name); item.Name = name; item.Save(); Reload(); } catch (Exception error) { Error(error); }
    }
    private void RevealClick(object sender, RoutedEventArgs e) { try { Open(Row(sender).Folder); } catch (Exception error) { Error(error); } }
    private void OpenTranscriptClick(object sender, RoutedEventArgs e)
    {
        try { string path = Row(sender).Transcript ?? throw new InvalidOperationException("Esta grabación aún no tiene un TXT."); Open(path); }
        catch (Exception error) { Error(error); }
    }
    private void PlayClick(object sender, RoutedEventArgs e)
    {
        if (recorder.IsRecording) return;
        var item = Row(sender); bool same = playing == item; StopPlayback(); if (same) return;
        try
        {
            playing = item; playbackAudio = new RecordingAudio(item); playback = new WaveOutEvent();
            playback.PlaybackStopped += (source, args) => Dispatcher.BeginInvoke(() =>
            {
                if (ReferenceEquals(playback, source)) { StopPlayback(); if (args.Exception != null) Error(args.Exception); }
            });
            playback.Init(playbackAudio.ToWaveProvider()); playback.Play();
        }
        catch (Exception error) { StopPlayback(); Error(error); }
    }
    private void StopPlayback() { playback?.Stop(); playback?.Dispose(); playback = null; playbackAudio?.Dispose(); playbackAudio = null; playing = null; }
    private async void ExportClick(object sender, RoutedEventArgs e)
    {
        if (working || recorder.IsRecording) return;
        var item = Row(sender); var dialog = new Microsoft.Win32.SaveFileDialog { Filter = "Audio MP3|*.mp3", FileName = item.Name + ".mp3", InitialDirectory = item.Folder };
        if (dialog.ShowDialog(this) != true) return;
        working = true; JobText.Text = "Exportando MP3…";
        string temp = Path.Combine(Path.GetDirectoryName(dialog.FileName)!, ".chace-" + Guid.NewGuid().ToString("N") + ".mp3");
        try { await Task.Run(() => RecordingAudio.ExportMp3(item, temp)); File.Move(temp, dialog.FileName, true); Open(Path.GetDirectoryName(dialog.FileName)!); }
        catch (Exception error) { Error(error); }
        finally { if (File.Exists(temp)) File.Delete(temp); working = false; JobText.Text = ""; }
    }
    private async void TranscribeClick(object sender, RoutedEventArgs e)
    {
        if (working || recorder.IsRecording) return;
        try
        {
            if (string.IsNullOrEmpty(SecretStore.Read())) { Dialogs.Settings(this); if (string.IsNullOrEmpty(SecretStore.Read())) return; }
            var item = Row(sender); string? language = Dialogs.Language(this, preferences.Language); if (language == null) return;
            preferences.Language = language; preferences.Save(); working = true;
            string path = await Deepgram.TranscribeAsync(item, language, new Progress<string>(text => JobText.Text = text), CancellationToken.None);
            Open(path);
        }
        catch (Exception error) { Error(error); }
        finally { working = false; JobText.Text = ""; Reload(); }
    }
    private void PowerChanged(object sender, Microsoft.Win32.PowerModeChangedEventArgs e)
    {
        Dispatcher.Invoke(() =>
        {
            if (!recorder.IsRecording) return;
            if (e.Mode == Microsoft.Win32.PowerModes.Suspend && !recorder.IsPaused) { resumeAfterSleep = true; TogglePause(); }
            if (e.Mode == Microsoft.Win32.PowerModes.Resume && resumeAfterSleep && recorder.IsPaused) { resumeAfterSleep = false; TogglePause(); }
        });
    }
    private void WindowClosing(object? sender, CancelEventArgs e)
    {
        if (recorder.IsRecording || working) { e.Cancel = true; if (recorder.IsRecording) Hide(); else MessageBox.Show(this, "Espera a que termine la exportación o transcripción."); return; }
        timer.Stop(); StopPlayback(); tray.Visible = false; tray.Dispose();
        Microsoft.Win32.SystemEvents.PowerModeChanged -= PowerChanged;
        foreach (var device in microphones.Concat(outputs)) device.Dispose(); devices.Dispose();
        Application.Current.Shutdown();
    }
}
