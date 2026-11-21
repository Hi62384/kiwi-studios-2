using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class ShaderDocumentationOperations : RefCounted
{
    private static readonly Color Accent = new("62e6c7"), AccentSoft = new("203f42"), Text = new("e8f0f5"), Muted = new("91a6b5"), Border = new("2c4252");
    private static T Field<T>(PopupPanel owner, string name) where T : GodotObject => (T)owner.Get(name).AsGodotObject();
    private static GArray Topics => GD.Load<GDScript>("res://Workspaces/SceneWorkspace/scripts/ShaderEditor/shader_documentation_popup.gd").GetScriptConstantMap()["TOPICS"].AsGodotArray();
    private static GArray Indices(PopupPanel owner) => owner.Get("_filtered_indices").AsGodotArray();
    private static void Clear(Node parent) { foreach (Node child in parent.GetChildren()) { parent.RemoveChild(child); child.QueueFree(); } }
    private static Label Label(string text, int size, Color color, bool wrap = false)
    {
        var label = new Label { Text = text, AutowrapMode = wrap ? TextServer.AutowrapMode.WordSmart : TextServer.AutowrapMode.Off }; label.AddThemeFontSizeOverride("font_size", size); label.AddThemeColorOverride("font_color", color); return label;
    }
    public StyleBoxFlat style(Color bg, Color border, int width, int radius, int padding)
    {
        var result = new StyleBoxFlat { BgColor = bg, BorderColor = border }; result.SetBorderWidthAll(width); result.SetCornerRadiusAll(radius); result.ContentMarginLeft = result.ContentMarginTop = result.ContentMarginRight = result.ContentMarginBottom = padding; return result;
    }
    public void style_button(Button button, Color normal, Color border, Color hover)
    {
        button.AddThemeStyleboxOverride("normal", style(normal, border, 1, 7, 7)); button.AddThemeStyleboxOverride("hover", style(hover, Accent, 1, 7, 7)); button.AddThemeStyleboxOverride("pressed", style(new Color("173d3b"), Accent, 1, 7, 7)); button.AddThemeStyleboxOverride("focus", style(normal, Accent, 1, 7, 7));
    }
    public void style_topic_button(Button button, bool selected)
    {
        Color normal = selected ? AccentSoft : Colors.Transparent, border = selected ? new Color("3e746e") : Colors.Transparent;
        button.AddThemeStyleboxOverride("normal", style(normal, border, selected ? 1 : 0, 6, 8)); button.AddThemeStyleboxOverride("pressed", style(AccentSoft, new Color("3e746e"), 1, 6, 8)); button.AddThemeStyleboxOverride("hover", style(new Color("1b2d39"), new Color("314a59"), 1, 6, 8)); button.AddThemeStyleboxOverride("focus", style(normal, Accent, 1, 6, 8));
        button.AddThemeColorOverride("font_color", selected ? Accent : new Color("b3c3cd")); button.AddThemeColorOverride("font_pressed_color", Accent); button.AddThemeColorOverride("font_hover_color", Text);
    }
    public void ready(PopupPanel owner)
    {
        owner.Name = "ShaderDocumentation"; owner.Size = new Vector2I(980, 700); owner.MinSize = new Vector2I(720, 500); owner.TransparentBg = false; owner.Borderless = false; owner.Title = "Shader Documentation, Samples & Templates"; owner.AddThemeStyleboxOverride("panel", style(new Color("111923"), Border, 1, 12, 0));
        var margin = new MarginContainer(); margin.AddThemeConstantOverride("margin_left", 18); margin.AddThemeConstantOverride("margin_top", 16); margin.AddThemeConstantOverride("margin_right", 18); margin.AddThemeConstantOverride("margin_bottom", 18); owner.AddChild(margin); margin.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        var root = new VBoxContainer(); owner.Set("_page_root", root); root.AddThemeConstantOverride("separation", 14); margin.AddChild(root); root.AddChild(build_header(owner));
        var sections = Field<TabBar>(owner, "sections"); sections.AddTab("Documentation"); sections.AddTab("Shader Samples"); sections.AddTab("Shader Templates"); sections.Connect("tab_changed", new Callable(owner, "_section_changed")); root.AddChild(sections);
        var body = build_body(owner); owner.Set("documentation_body", body); root.AddChild(body); Field<LineEdit>(owner, "search").Connect("text_changed", new Callable(owner, "_filter_topics")); filter_topics(owner, "");
        if (Indices(owner).Count > 0) owner.Call("_select_topic", Indices(owner)[0]);
    }
    public void open(PopupPanel owner) { owner.PopupCenteredClamped(new Vector2I(1300, 850), .94f); Field<LineEdit>(owner, "search").GrabFocus(); }
    public void open_samples(PopupPanel owner, bool templates) { open(owner); Field<TabBar>(owner, "sections").CurrentTab = templates ? 2 : 1; }
    public void section_changed(PopupPanel owner, int index)
    {
        Field<Control>(owner, "documentation_body").Visible = index == 0;
        var browser = owner.Get("sample_browser").As<Control>();
        if (index > 0 && browser == null)
        {
            browser = GD.Load<GDScript>("res://Workspaces/ShaderWorkspace/shader_sample_browser.gd").New().As<Control>(); browser.Set("templates_only", index == 2);
            browser.Connect("open_requested", new Callable(owner, "_sample_open_requested")); owner.Set("sample_browser", browser); Field<VBoxContainer>(owner, "_page_root").AddChild(browser);
        }
        if (browser != null) { browser.Visible = index > 0; if (index > 0) browser.Call("set_templates", index == 2); }
    }
    public Control build_header(PopupPanel owner)
    {
        var hero = new PanelContainer(); hero.AddThemeStyleboxOverride("panel", style(new Color("162a35"), new Color("366172"), 1, 12, 16)); var row = new HBoxContainer(); row.AddThemeConstantOverride("separation", 16); hero.AddChild(row); row.AddChild(Label("◇", 34, Accent));
        var words = new VBoxContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }; words.AddThemeConstantOverride("separation", 2); row.AddChild(words); words.AddChild(Label("SHADER FIELD GUIDE", 20, Text)); words.AddChild(Label("Concepts, built-ins, and production-ready patterns—without leaving the editor.", 12, Muted));
        var close = new Button { Text = "Close  ×", CustomMinimumSize = new Vector2(92, 34) }; style_button(close, new Color("233441"), new Color("36505f"), new Color("2d4350")); close.Connect("pressed", new Callable(owner, "hide")); row.AddChild(close); return hero;
    }
    public Control build_body(PopupPanel owner)
    {
        var split = new HSplitContainer { SizeFlagsVertical = Control.SizeFlags.ExpandFill, SplitOffsets = new[] { 245 } };
        var sidebar = new PanelContainer { CustomMinimumSize = new Vector2(225, 0) }; sidebar.AddThemeStyleboxOverride("panel", style(new Color("131e29"), Border, 1, 10, 12)); split.AddChild(sidebar); var side = new VBoxContainer(); side.AddThemeConstantOverride("separation", 9); sidebar.AddChild(side);
        var search = Field<LineEdit>(owner, "search"); search.Name = "DocumentationSearch"; search.PlaceholderText = "Search shader docs…"; search.ClearButtonEnabled = true; search.CustomMinimumSize = new Vector2(0, 38); search.AddThemeColorOverride("font_color", Text); search.AddThemeColorOverride("font_placeholder_color", Muted); search.AddThemeStyleboxOverride("normal", style(new Color("0d151e"), Border, 1, 7, 9)); search.AddThemeStyleboxOverride("focus", style(new Color("0d171f"), Accent, 1, 7, 9)); side.AddChild(search);
        var count = Field<Label>(owner, "result_count"); count.AddThemeFontSizeOverride("font_size", 10); count.AddThemeColorOverride("font_color", Muted); side.AddChild(count);
        var navigation = new ScrollContainer { SizeFlagsVertical = Control.SizeFlags.ExpandFill, HorizontalScrollMode = ScrollContainer.ScrollMode.Disabled }; side.AddChild(navigation); var topics = Field<VBoxContainer>(owner, "topic_list"); topics.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill; topics.AddThemeConstantOverride("separation", 4); navigation.AddChild(topics);
        var panel = new PanelContainer(); panel.AddThemeStyleboxOverride("panel", style(new Color("0e161f"), Border, 1, 10, 16)); split.AddChild(panel); var scroll = Field<ScrollContainer>(owner, "scroll"); scroll.SizeFlagsHorizontal = scroll.SizeFlagsVertical = Control.SizeFlags.ExpandFill; scroll.HorizontalScrollMode = ScrollContainer.ScrollMode.Disabled; panel.AddChild(scroll);
        var content = Field<VBoxContainer>(owner, "content"); content.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill; content.AddThemeConstantOverride("separation", 14); scroll.AddChild(content); return split;
    }
    public void filter_topics(PopupPanel owner, string query)
    {
        var indices = Indices(owner); indices.Clear(); string needle = query.Trim().ToLowerInvariant(); var topics = Topics;
        for (int i = 0; i < topics.Count; i++) { var topic = topics[i].AsGodotDictionary(); string haystack = string.Join(' ', new[] { "category", "title", "summary", "body" }.Select(key => topic[key].AsString())); if (needle == "" || haystack.ToLowerInvariant().Contains(needle)) indices.Add(i); }
        Field<Label>(owner, "result_count").Text = indices.Count + " TOPICS"; rebuild_navigation(owner);
        if (indices.Count == 0) show_empty_state(owner, needle); else if (!indices.Contains(owner.Get("_selected_index"))) owner.Call("_select_topic", indices[0]); else update_navigation_selection(owner);
    }
    public void rebuild_navigation(PopupPanel owner)
    {
        var list = Field<VBoxContainer>(owner, "topic_list"); Clear(list); string previous = ""; var topics = Topics;
        foreach (var value in Indices(owner))
        {
            int index = value.AsInt32(); var topic = topics[index].AsGodotDictionary(); string category = topic["category"].AsString();
            if (category != previous) { var label = Label(category, 9, new Color("668395")); label.AddThemeConstantOverride("outline_size", 1); list.AddChild(label); previous = category; }
            var button = new Button { Name = "DocumentationTopic_" + index, Text = topic["title"].AsString(), Alignment = HorizontalAlignment.Left, CustomMinimumSize = new Vector2(0, 36), ToggleMode = true, ButtonPressed = index == owner.Get("_selected_index").AsInt32() }; style_topic_button(button, button.ButtonPressed);
            button.Pressed += () => { if (GodotObject.IsInstanceValid(owner)) owner.Call("_select_topic", index); }; list.AddChild(button);
        }
    }
    public void update_navigation_selection(PopupPanel owner)
    {
        foreach (Node child in Field<VBoxContainer>(owner, "topic_list").GetChildren())
        {
            if (child is Button button && button.Name.ToString().StartsWith("DocumentationTopic_", StringComparison.Ordinal) && int.TryParse(button.Name.ToString()[19..], out int index)) { bool selected = index == owner.Get("_selected_index").AsInt32(); button.SetPressedNoSignal(selected); style_topic_button(button, selected); }
        }
    }
    public bool select_topic(PopupPanel owner, int index)
    {
        var topics = Topics; if (index < 0 || index >= topics.Count) return false;
        owner.Set("_selected_index", index); update_navigation_selection(owner); var content = Field<VBoxContainer>(owner, "content"); Clear(content); var topic = topics[index].AsGodotDictionary();
        content.AddChild(Label(topic["category"].AsString() + "   /   " + topic["tag"].AsString(), 10, Accent)); content.AddChild(Label(topic["title"].AsString(), 28, Text)); content.AddChild(Label(topic["summary"].AsString(), 15, new Color("b9cad5"), true));
        var divider = new HSeparator(); divider.AddThemeConstantOverride("separation", 10); content.AddChild(divider); var body = Label(topic["body"].AsString(), 13, Muted, true); body.CustomMinimumSize = new Vector2(0, 52); content.AddChild(body); content.AddChild(build_code_card(owner, topic["code"].AsString(), topic["title"].AsString()));
        var tip = new PanelContainer(); tip.AddThemeStyleboxOverride("panel", style(new Color("152529"), new Color("29484b"), 1, 8, 10)); tip.AddChild(Label("TIP  •  Copy the sample, then adjust its uniforms in the Properties panel.", 11, new Color("86cbbb"), true)); content.AddChild(tip); return true;
    }
    public void reset_scroll(PopupPanel owner) { var scroll = Field<ScrollContainer>(owner, "scroll"); if (GodotObject.IsInstanceValid(scroll)) scroll.ScrollVertical = 0; }
    public Control build_code_card(PopupPanel owner, string source, string title)
    {
        var card = new PanelContainer { Name = "DocumentationCodeCard" }; card.AddThemeStyleboxOverride("panel", style(new Color("0a1119"), new Color("2b4555"), 1, 9, 0)); var box = new VBoxContainer(); box.AddThemeConstantOverride("separation", 0); card.AddChild(box); var bar = new PanelContainer(); bar.AddThemeStyleboxOverride("panel", style(new Color("172633"), Colors.Transparent, 0, 9, 10)); box.AddChild(bar); var row = new HBoxContainer(); bar.AddChild(row); var language = Label("GODOT SHADER", 9, new Color("7896aa")); language.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill; row.AddChild(language);
        var copy = new Button { Name = "CopyShaderSample", Text = "Copy code", TooltipText = "Copy this sample to the clipboard", CustomMinimumSize = new Vector2(100, 30) }; style_button(copy, AccentSoft, new Color("39716c"), new Color("2b5a57")); copy.AddThemeColorOverride("font_color", Accent); copy.Pressed += () => { if (GodotObject.IsInstanceValid(owner)) owner.Call("_copy_code", source, copy, title); }; row.AddChild(copy);
        var sample = new CodeEdit { Name = "DocumentationCodeSample", Text = source, Editable = false, GuttersDrawLineNumbers = true, HighlightCurrentLine = false, ScrollFitContentHeight = true, CustomMinimumSize = new Vector2(0, Math.Clamp((source.Count(c => c == '\n') + 1) * 22 + 18, 130, 390)), SyntaxHighlighter = make_highlighter() }; sample.AddThemeFontSizeOverride("font_size", 13); sample.AddThemeColorOverride("font_color", new Color("d9e6ee")); sample.AddThemeColorOverride("background_color", new Color("0a1119")); box.AddChild(sample); return card;
    }
    public long copy_code(PopupPanel owner, string source, Button button)
    {
        DisplayServer.ClipboardSet(source); long revision = owner.Get("_copy_revision").AsInt64() + 1; owner.Set("_copy_revision", revision); button.Text = "Copied  ✓"; button.AddThemeColorOverride("font_color", new Color("b7ffe9")); return revision;
    }
    public void finish_copy(PopupPanel owner, long revision, Variant value)
    {
        if (revision != owner.Get("_copy_revision").AsInt64() || value.VariantType != Variant.Type.Object || value.AsGodotObject() is not Button button || !GodotObject.IsInstanceValid(button)) return; button.Text = "Copy code"; button.AddThemeColorOverride("font_color", Accent);
    }
    public void show_empty_state(PopupPanel owner, string query)
    {
        var content = Field<VBoxContainer>(owner, "content"); Clear(content); content.AddChild(new Control { CustomMinimumSize = new Vector2(0, 100) });
        foreach (var label in new[] { Label("⌕", 40, new Color("4b6879")), Label("No shader topics found", 20, Text), Label("Try a broader search than " + query + ".", 14, Muted) }) { label.HorizontalAlignment = HorizontalAlignment.Center; content.AddChild(label); }
    }
    public CodeHighlighter make_highlighter()
    {
        var result = new CodeHighlighter { NumberColor = new Color("b5cea8"), SymbolColor = new Color("d4d4d4"), FunctionColor = new Color("dcdcaa"), MemberVariableColor = new Color("9cdcfe") };
        foreach (string keyword in new[] { "shader_type", "render_mode", "uniform", "varying", "const", "void", "if", "else", "for", "while", "return", "discard" }) result.AddKeywordColor(keyword, new Color("c792ea"));
        foreach (string type in new[] { "float", "int", "uint", "bool", "vec2", "vec3", "vec4", "mat2", "mat3", "mat4", "sampler2D", "samplerCube" }) result.AddKeywordColor(type, new Color("62d6ca")); result.AddColorRegion("//", "", new Color("6a9955"), true); return result;
    }
}
