using Godot;

[Tool, GlobalClass]
public partial class ExpandableButtonControl : VBoxContainer
{
    public Button? _expandable_icon_button { get; set; }
    public TextureRect? _expandable_icon { get; set; }
    public TextureRect? _main_icon { get; set; }
    public Label? _label { get; set; }
    public VBoxContainer? _children_container { get; set; }
    public Panel? _panel { get; set; }
    public Button? _main_button { get; set; }
    public ColorRect? _cover_color_rect { get; set; }
    private readonly SharedControlOperations _operations = new();
    private bool _expanded;
    private Texture2D? _icon;
    private string _text = "";
    private LabelSettings? _labelSettings;
    private StyleBox? _panelStyle;
    private Color _coverColor = new(1, 1, 1, .05f);
    private bool _connected;
    [Export] public bool expanded { get => _expanded; set { _expanded = value; Refresh("expanded", true); } }
    [ExportGroup("icon")]
    [Export] public Texture2D? icon { get => _icon; set { _icon = value; Refresh("icon", true); } }
    [ExportGroup("Text")]
    [Export] public string text { get => _text; set { _text = value; Refresh("text", true); } }
    [Export] public LabelSettings? label_settings { get => _labelSettings; set { _labelSettings = value; Refresh("label_settings", true); } }
    [ExportGroup("style")]
    [Export] public StyleBox? panel_stylebox { get => _panelStyle; set { _panelStyle = value; Refresh("panel_stylebox", true); } }
    [Export] public Color cover_colorrect_color { get => _coverColor; set { _coverColor = value; Refresh("cover_colorrect_color", true); } }
    [Signal] public delegate void toggledEventHandler(bool on);
    private void Refresh(string property, bool notify)
    {
        if (IsNodeReady() && GodotObject.IsInstanceValid(_panel)) _operations.expandable_property(this, property, notify);
    }
    public override void _Ready()
    {
        _expandable_icon_button = GetNode<Button>("Panel/HBoxContainer/ExpandableIconButton");
        _expandable_icon = GetNode<TextureRect>("Panel/HBoxContainer/ExpandableIconButton/ExpandableIcon");
        _main_icon = GetNode<TextureRect>("Panel/HBoxContainer/MainIcon");
        _label = GetNode<Label>("Panel/HBoxContainer/Text");
        _children_container = GetNode<VBoxContainer>("HBoxContainer/ChildrenContainer");
        _panel = GetNode<Panel>("Panel"); _main_button = GetNode<Button>("Panel/MainButton");
        _cover_color_rect = GetNode<ColorRect>("Panel/CoverColorRect");
        if (!_connected) { _operations.expandable_ready(this); _connected = true; }
        foreach (string property in new[] { "icon", "text", "expanded", "label_settings", "panel_stylebox", "cover_colorrect_color" }) Refresh(property, false);
    }
    public ColorRect? get_cover_color_rect() => _cover_color_rect;
    public Button? get_main_button() => _main_button;
    public Button? get_expandable_icon_button() => _expandable_icon_button;
    public void add_child_in_expand(Node child) => _operations.add_child_in_expand(this, child);
}
