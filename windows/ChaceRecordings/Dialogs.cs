using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace ChaceRecordings;
public static class Dialogs
{
    private static Window Create(Window owner, string title, StackPanel content) => new()
    { Owner = owner, Title = title, Width = 420, SizeToContent = SizeToContent.Height, ResizeMode = ResizeMode.NoResize, WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = new SolidColorBrush(Color.FromRgb(32,37,53)), Content = content };
    public static string? Text(Window owner, string title, string initial)
    {
        var panel = new StackPanel { Margin = new Thickness(18) };
        var field = new TextBox { Text = initial, Margin = new Thickness(0,10,0,10) };
        panel.Children.Add(field);
        var window = Create(owner, title, panel);
        var save = new Button { Content = "Guardar", IsDefault = true };
        save.Click += (_, _) => window.DialogResult = true;
        panel.Children.Add(save);
        field.SelectAll(); window.Loaded += (_, _) => field.Focus();
        return window.ShowDialog() == true ? field.Text.Trim() : null;
    }
    public static string? Language(Window owner, string current)
    {
        var panel = new StackPanel { Margin = new Thickness(18) };
        panel.Children.Add(new TextBlock { Text = "Modelo: Nova 3", FontWeight = FontWeights.SemiBold });
        var combo = new ComboBox { ItemsSource = new[] { "Español", "Inglés", "Multilingüe (español + inglés)" }, SelectedIndex = current == "en" ? 1 : current == "multi" ? 2 : 0 };
        panel.Children.Add(combo);
        panel.Children.Add(new TextBlock { Text = "El audio se enviará a Deepgram y consumirá tus créditos. El TXT se guardará junto a las pistas de esta grabación.", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0,10,0,10) });
        var window = Create(owner, "Transcribir", panel);
        var button = new Button { Content = "Transcribir", IsDefault = true };
        button.Click += (_, _) => window.DialogResult = true;
        panel.Children.Add(button);
        return window.ShowDialog() == true ? new[] { "es", "en", "multi" }[combo.SelectedIndex] : null;
    }
    public static void Settings(Window owner)
    {
        var panel = new StackPanel { Margin = new Thickness(18) };
        panel.Children.Add(new TextBlock { Text = "API key de Deepgram · Nova 3" });
        var field = new PasswordBox { Password = SecretStore.Read() ?? "", Margin = new Thickness(0,10,0,10) };
        panel.Children.Add(field);
        panel.Children.Add(new TextBlock { Text = "Se guarda cifrada para tu usuario de Windows. No se incluye en el instalador.", TextWrapping = TextWrapping.Wrap });
        var window = Create(owner, "Ajustes", panel);
        var save = new Button { Content = "Guardar" };
        save.Click += (_, _) => { try { SecretStore.Save(field.Password); window.Close(); } catch (Exception e) { MessageBox.Show(window, e.Message); } };
        var delete = new Button { Content = "Eliminar clave" };
        delete.Click += (_, _) => { try { SecretStore.Delete(); field.Clear(); } catch (Exception e) { MessageBox.Show(window, e.Message); } };
        panel.Children.Add(save); panel.Children.Add(delete);
        window.ShowDialog(); field.Clear();
    }
}
