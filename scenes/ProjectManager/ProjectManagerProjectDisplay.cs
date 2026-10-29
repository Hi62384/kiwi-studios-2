using Godot;

public partial class ProjectManagerProjectDisplay : Panel
{
    // Keep the existing script-facing names while the project manager is ported.
    [Export] public TextureRect texture_rect { get; set; } = null!;
    [Export] public Label project_name { get; set; } = null!;
    [Export] public Label project_path { get; set; } = null!;
    [Export] public Button button { get; set; } = null!;
    [Export] public ColorRect selected_cover { get; set; } = null!;
    [Export] public ColorRect error_cover { get; set; } = null!;

    public override void _Ready()
    {
        texture_rect = GetNode<TextureRect>("HBoxContainer/TextureRect");
        project_name = GetNode<Label>("HBoxContainer/VBoxContainer/ProjectName");
        project_path = GetNode<Label>("HBoxContainer/VBoxContainer/ProjectPath");
        button = GetNode<Button>("Button");
        selected_cover = GetNode<ColorRect>("SelectedCover");
        error_cover = GetNode<ColorRect>("ErrorCover");
    }
}
