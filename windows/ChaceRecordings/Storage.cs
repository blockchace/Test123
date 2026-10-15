using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Runtime.Versioning;

namespace ChaceRecordings;

public sealed class Preferences
{
    public string Folder { get; set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "ChaceRecordings");
    public List<string> Libraries { get; set; } = new();
    public string Language { get; set; } = "es";
    public string? Microphone { get; set; }
    public string? Output { get; set; }
    public static string ConfigDirectory => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ChaceRecordings");
    public static Preferences Load()
    {
        try { return JsonSerializer.Deserialize<Preferences>(File.ReadAllText(Path.Combine(ConfigDirectory, "settings.json"))) ?? new(); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return new(); }
    }
    public void Save()
    {
        Directory.CreateDirectory(ConfigDirectory);
        if (!Libraries.Contains(Folder, StringComparer.OrdinalIgnoreCase)) Libraries.Add(Folder);
        AtomicFile.Write(Path.Combine(ConfigDirectory, "settings.json"), JsonSerializer.Serialize(this));
    }
}

public static class AtomicFile
{
    public static void Write(string path, string text)
    {
        string temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { File.WriteAllText(temp, text, new UTF8Encoding(false)); File.Move(temp, path, true); }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
}

[SupportedOSPlatform("windows")]
public static class SecretStore
{
    private static string PathName => Path.Combine(Preferences.ConfigDirectory, "deepgram.key");
    public static string? Read()
    {
        if (!File.Exists(PathName)) return null;
        return Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(PathName), null, DataProtectionScope.CurrentUser));
    }
    public static void Save(string value)
    {
        string key = value.Trim();
        if (key.Length == 0 || key.Any(char.IsWhiteSpace)) throw new InvalidOperationException("Pega solo la clave de Deepgram, sin espacios ni el prefijo Token.");
        Directory.CreateDirectory(Preferences.ConfigDirectory);
        byte[] encrypted = ProtectedData.Protect(Encoding.UTF8.GetBytes(key), null, DataProtectionScope.CurrentUser);
        string temp = PathName + ".tmp";
        try { File.WriteAllBytes(temp, encrypted); File.Move(temp, PathName, true); }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }
    public static void Delete() { if (File.Exists(PathName)) File.Delete(PathName); }
}

public sealed class Recording
{
    public string Name { get; set; } = "Grabación";
    public DateTime Created { get; set; } = DateTime.Now;
    public double Duration { get; set; }
    public List<string> SystemParts { get; set; } = new();
    public List<string> MicrophoneParts { get; set; } = new();
    [System.Text.Json.Serialization.JsonIgnore] public string Folder { get; set; } = "";
    [System.Text.Json.Serialization.JsonIgnore] public string Details => $"{(long)Duration / 3600:D2}:{(long)Duration / 60 % 60:D2}:{(long)Duration % 60:D2} · {Created:g}";
    [System.Text.Json.Serialization.JsonIgnore] public string? Transcript => Directory.Exists(Folder) ? Directory.EnumerateFiles(Folder, "*.txt").OrderByDescending(File.GetLastWriteTimeUtc).FirstOrDefault() : null;
    public void Save() => AtomicFile.Write(Path.Combine(Folder, "recording.json"), JsonSerializer.Serialize(this));
    public static void ValidateName(string name)
    {
        if (string.IsNullOrWhiteSpace(name) || name.Length > 120 || name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
            throw new InvalidOperationException("Usa un nombre de 1 a 120 caracteres, sin caracteres especiales de rutas.");
    }
    public static List<Recording> LoadLibraries(Preferences preferences)
    {
        var result = new List<Recording>();
        foreach (var library in preferences.Libraries.Append(preferences.Folder).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (!Directory.Exists(library)) continue;
            try
            {
                foreach (string folder in Directory.EnumerateDirectories(library))
                {
                    try
                    {
                        var item = JsonSerializer.Deserialize<Recording>(File.ReadAllText(Path.Combine(folder, "recording.json")));
                        if (item != null && item.Duration > 0) { item.Folder = folder; result.Add(item); }
                    }
                    catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { }
                }
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
        return result.OrderByDescending(r => r.Created).ToList();
    }
}
