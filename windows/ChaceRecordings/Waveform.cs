using System;
using System.Windows;
using System.Windows.Media;

namespace ChaceRecordings;
public sealed class Waveform : FrameworkElement
{
    private readonly float[] values = new float[64];
    public Brush Color { get; set; } = Brushes.MediumPurple;
    public void Push(float peak)
    {
        Array.Copy(values, 1, values, 0, values.Length - 1);
        values[^1] = float.IsFinite(peak) && peak >= .0001f ? Math.Min(1, MathF.Sqrt(Math.Max(0, peak)) * 1.4f) : 0;
        InvalidateVisual();
    }
    public void Clear() { Array.Clear(values); InvalidateVisual(); }
    protected override void OnRender(DrawingContext drawing)
    {
        double step = ActualWidth / values.Length;
        for (int i = 0; i < values.Length; i++)
        {
            double height = Math.Max(1, values[i] * ActualHeight);
            drawing.DrawRoundedRectangle(Color, null, new Rect(i * step, (ActualHeight - height) / 2, Math.Max(1, step * .5), height), 1, 1);
        }
    }
}
