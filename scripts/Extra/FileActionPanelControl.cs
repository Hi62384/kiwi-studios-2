using Godot;

[Tool, GlobalClass]
public partial class FileActionPanelControl : Button
{
    public TextureRect? icon_texture_rect { get; set; }
    public Label? text_label { get; set; }
    public Button? more_options_button { get; set; }
    public Label? key_shortcut { get; set; }
    private readonly SharedControlOperations _operations = new();
    private Texture2D? _panelIcon;
    private string _panelText = "", _shortcut = "";
    private bool _hasMore;
    [Export] public Texture2D? panel_icon { get => _panelIcon; set { _panelIcon = value; Refresh("panel_icon"); } }
    [Export] public string panel_text { get => _panelText; set { _panelText = value; Refresh("panel_text"); } }
    [Export] public string key_shortcut_text { get => _shortcut; set { _shortcut = value; Refresh("key_shortcut_text"); } }
    [Export] public bool has_more_options { get => _hasMore; set { _hasMore = value; Refresh("has_more_options"); } }
    private void Refresh(string property)
    {
        if (IsNodeReady() && GodotObject.IsInstanceValid(text_label)) _operations.action_panel_property(this, property);
    }
    public override void _Ready()
    {
        icon_texture_rect = GetNode<TextureRect>("HBoxContainer/TextureRect");
        text_label = GetNode<Label>("HBoxContainer/Label");
        more_options_button = GetNode<Button>("HBoxContainer/Button"); key_shortcut = GetNode<Label>("key_shortcut");
        foreach (string property in new[] { "panel_icon", "panel_text", "key_shortcut_text", "has_more_options" }) Refresh(property);
    }
}
