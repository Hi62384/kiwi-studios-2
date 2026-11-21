using Godot;

public partial class ShaderCodeEditorOperations
{
    private static StyleBoxFlat Panel(string background, string border, int radius)
    {
        var panel = new StyleBoxFlat { BgColor = new Color(background), BorderColor = new Color(border) };
        panel.SetBorderWidthAll(1); panel.SetCornerRadiusAll(radius); return panel;
    }
    public StyleBoxFlat workspace_switcher_panel()
    {
        var panel = Panel("121d27", "344c60", 9);
        panel.ContentMarginLeft = 9; panel.ContentMarginRight = 7; panel.ContentMarginTop = panel.ContentMarginBottom = 6;
        return panel;
    }
    public void style_workspace_picker(Control owner)
    {
        var picker = Field<OptionButton>(owner, "workspace_picker");
        var normal = Panel("192a37", "3d5b70", 7); normal.ContentMarginLeft = normal.ContentMarginRight = 12;
        var hover = (StyleBoxFlat)normal.Duplicate(); hover.BgColor = new Color("223c48"); hover.BorderColor = new Color("5aa58f");
        var pressed = (StyleBoxFlat)normal.Duplicate(); pressed.BgColor = new Color("244c4b"); pressed.BorderColor = new Color("70d8bd");
        picker.AddThemeStyleboxOverride("normal", normal); picker.AddThemeStyleboxOverride("hover", hover); picker.AddThemeStyleboxOverride("pressed", pressed); picker.AddThemeStyleboxOverride("focus", pressed);
        picker.AddThemeColorOverride("font_color", new Color("e0edf3")); picker.AddThemeColorOverride("font_hover_color", Colors.White); picker.AddThemeColorOverride("font_pressed_color", Colors.White); picker.AddThemeFontSizeOverride("font_size", 13);
        var popup = picker.GetPopup(); popup.MinSize = new Vector2I(225, 0);
        var panel = Panel("111b25", "456176", 9); panel.ShadowColor = new Color(0, 0, 0, .45f); panel.ShadowSize = 9;
        panel.ContentMarginLeft = panel.ContentMarginRight = panel.ContentMarginTop = panel.ContentMarginBottom = 7;
        popup.AddThemeStyleboxOverride("panel", panel); popup.AddThemeStyleboxOverride("hover", Panel("28534f", "67cdb4", 6));
        popup.AddThemeColorOverride("font_color", new Color("cbdbe5")); popup.AddThemeColorOverride("font_hover_color", Colors.White);
        popup.AddThemeConstantOverride("item_start_padding", 13); popup.AddThemeConstantOverride("item_end_padding", 16); popup.AddThemeConstantOverride("v_separation", 7); popup.AddThemeFontSizeOverride("font_size", 13);
    }
    public void ready(Control owner)
    {
        owner.CustomMinimumSize = new Vector2(210, 120);
        var root = new VBoxContainer(); root.AddThemeConstantOverride("separation", 4); owner.AddChild(root);
        var bar = new PanelContainer { Name = "WorkspaceSwitcher" }; bar.AddThemeStyleboxOverride("panel", workspace_switcher_panel()); root.AddChild(bar);
        var row = new HBoxContainer(); row.AddThemeConstantOverride("separation", 8); bar.AddChild(row);
        var mark = new Label { Text = "WORKSPACE", TooltipText = "Editor workspace", VerticalAlignment = VerticalAlignment.Center };
        mark.AddThemeColorOverride("font_color", new Color("65d6bb")); mark.AddThemeFontSizeOverride("font_size", 9); row.AddChild(mark);
        var picker = Field<OptionButton>(owner, "workspace_picker"); picker.Name = "EditorWorkspacePicker";
        picker.AddItem("Scene Tree", 0); picker.AddItem("Shader Editor", 1); picker.Select(0);
        picker.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill; picker.CustomMinimumSize = new Vector2(150, 34); picker.TooltipText = "Choose the editor shown above the Project Filesystem";
        row.AddChild(picker); style_workspace_picker(owner); picker.Connect("item_selected", new Callable(owner, "_workspace_selected"));
        var sceneTree = Field<Control>(owner, "scene_tree"); sceneTree.Name = "ActorSceneTree"; root.AddChild(sceneTree);
        var workspace = Field<VBoxContainer>(owner, "shader_workspace"); workspace.Name = "ShaderWorkspace"; workspace.AddThemeConstantOverride("separation", 4); workspace.SizeFlagsVertical = Control.SizeFlags.ExpandFill; workspace.Visible = false; root.AddChild(workspace);
        var header = new HBoxContainer(); workspace.AddChild(header);
        var title = Field<Label>(owner, "title"); title.Text = "SHADER EDITOR"; title.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill; title.ClipText = true; title.AddThemeFontSizeOverride("font_size", 13); header.AddChild(title);
        var docs = Field<Button>(owner, "documentation_button"); docs.Name = "ShaderDocumentationButton"; docs.Text = "Shader docs & library"; docs.CustomMinimumSize = new Vector2(138, 32); docs.TooltipText = "Documentation, rendered samples, and shader templates"; docs.AddThemeColorOverride("font_color", new Color("9ce8d5"));
        var normal = Panel("172b35", "365766", 7); normal.ContentMarginLeft = normal.ContentMarginRight = 10;
        var hover = (StyleBoxFlat)normal.Duplicate(); hover.BgColor = new Color("20413f"); hover.BorderColor = new Color("62e6c7");
        docs.AddThemeStyleboxOverride("normal", normal); docs.AddThemeStyleboxOverride("hover", hover); docs.AddThemeStyleboxOverride("pressed", hover); header.AddChild(docs);
        var documentation = GD.Load<GDScript>("res://Workspaces/SceneWorkspace/scripts/ShaderEditor/shader_documentation_popup.gd").New().As<PopupPanel>(); owner.Set("documentation", documentation); owner.AddChild(documentation);
        docs.Connect("pressed", new Callable(documentation, "open")); documentation.Connect("sample_open_requested", new Callable(owner, "_open_library_sample"));
        var code = Code(owner); code.SizeFlagsVertical = code.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill; code.GuttersDrawLineNumbers = true; code.HighlightCurrentLine = true; code.AutoBraceCompletionEnabled = true; code.IndentAutomatic = true; code.IndentSize = 4; code.CodeCompletionEnabled = true; code.PlaceholderText = "Double-click a .gdshader file in the Project Filesystem.";
        code.Connect("text_changed", new Callable(owner, "_text_changed")); code.Connect("code_completion_requested", new Callable(owner, "_complete_code")); code.Connect("gui_input", new Callable(owner, "_code_input")); code.FocusEntered += ClearFocus; code.SyntaxHighlighter = make_highlighter(); workspace.AddChild(code);
        var diagnostics = Field<Label>(owner, "diagnostics"); diagnostics.Visible = false; diagnostics.AutowrapMode = TextServer.AutowrapMode.WordSmart; diagnostics.AddThemeFontSizeOverride("font_size", 11); diagnostics.AddThemeColorOverride("font_color", new Color("ff8f88")); workspace.AddChild(diagnostics);
        var timer = Field<Timer>(owner, "save_timer"); timer.OneShot = true; timer.WaitTime = .25; timer.Connect("timeout", new Callable(owner, "save")); owner.AddChild(timer);
        owner.AddToGroup("shader_code_editor"); owner.CallDeferred("_connect_filesystem");
        if (owner.Get("dedicated_mode").AsBool()) { bar.Visible = false; picker.Visible = false; sceneTree.Visible = false; workspace.Visible = true; }
        else owner.CallDeferred("_connect_timeline");
    }
}
