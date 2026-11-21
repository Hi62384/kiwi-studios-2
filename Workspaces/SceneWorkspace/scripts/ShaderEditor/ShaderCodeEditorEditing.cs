using Godot;
using System;
using System.Linq;
using System.Text.RegularExpressions;
using Settings = Godot.Collections.Dictionary;

public partial class ShaderCodeEditorOperations
{
    public void workspace_selected(Control owner, int index)
    {
        Field<OptionButton>(owner, "workspace_picker").Select(index);
        Field<Control>(owner, "scene_tree").Visible = index == 0;
        Field<Control>(owner, "shader_workspace").Visible = index == 1;
        if (index == 1) Code(owner).GrabFocus();
    }
    public void connect_filesystem(Control owner)
    {
        if (owner.GetTree().GetFirstNodeInGroup("actor_scene_tabs") != null) return;
        var filesystem = owner.GetParent().GetNodeOrNull("FileSystem");
        if (filesystem?.HasSignal("shader_file_opened") == true) filesystem.Connect("shader_file_opened", new Callable(owner, "open_shader"));
    }
    public void connect_timeline(Control owner)
    {
        var timeline = owner.GetTree().GetFirstNodeInGroup("actor_timeline_editors");
        if (timeline != null) Field<Control>(owner, "scene_tree").Call("setup", timeline.Get("model"), timeline.Get("registry"));
    }
    public void open_shader(Control owner, Variant source)
    {
        workspace_selected(owner, 1);
        var timer = Field<Timer>(owner, "save_timer");
        if (!timer.IsStopped()) save(owner);
        timer.Stop(); owner.Set("_loading", true);
        try
        {
            if (source.VariantType == Variant.Type.Object && source.AsGodotObject() is Shader shader)
            {
                owner.Set("current_shader", shader); owner.Set("current_path", ""); Code(owner).Text = shader.Code;
                Field<Label>(owner, "title").Text = shader.ResourceName == "" ? "Embedded Shader" : shader.ResourceName;
            }
            else
            {
                string path = source.ToString();
                if (path.GetExtension().ToLowerInvariant() != "gdshader" || !FileAccess.FileExists(path)) return;
                using var file = FileAccess.Open(path, FileAccess.ModeFlags.Read);
                if (file == null) return;
                owner.Set("current_path", path); owner.Set("current_shader", default);
                Code(owner).Text = file.GetAsText(); Field<Label>(owner, "title").Text = path.GetFile();
            }
        }
        finally { owner.Set("_loading", false); }
        validate_syntax(owner); Code(owner).GrabFocus();
    }
    public void save(Control owner)
    {
        var current = owner.Get("current_shader").As<Shader>();
        if (current != null)
        {
            current.Code = Code(owner).Text; current.EmitChanged(); notify_shader_changed(owner, current); return;
        }
        string path = owner.Get("current_path").AsString();
        if (path == "") return;
        using (var file = FileAccess.Open(path, FileAccess.ModeFlags.Write))
        {
            if (file == null) return;
            file.StoreString(Code(owner).Text); file.Flush(); file.Close();
        }
        ResourceLoader.Load(path, "", ResourceLoader.CacheMode.Replace);
        notify_shader_changed(owner, path);
    }
    public void notify_shader_changed(Control owner, Variant source)
    {
        owner.EmitSignal("shader_changed", source);
        owner.GetTree().CallGroup("actor_timeline_editors", "refresh_saved_shader", source);
        owner.GetTree().CallGroup("actor_shader_runtimes", "refresh_saved_shader", source);
    }
    public void text_changed(Control owner)
    {
        if (owner.Get("_loading").AsBool() || (owner.Get("current_path").AsString() == "" && owner.Get("current_shader").As<Shader>() == null)) return;
        Code(owner).RequestCodeCompletion(true); validate_syntax(owner);
        if (owner.Get("auto_save_enabled").AsBool()) Field<Timer>(owner, "save_timer").Start();
    }
    public void code_input(Control owner, InputEvent input)
    {
        if (input is InputEventMouseButton { Pressed: true }) { ClearFocus(); Code(owner).GrabFocus(); }
        if (input is InputEventKey { Pressed: true, CtrlPressed: true, Keycode: Key.S } key)
        {
            if (owner.Get("dedicated_mode").AsBool()) owner.EmitSignal("save_shortcut_requested", key.ShiftPressed); else save(owner);
            owner.GetViewport().SetInputAsHandled();
        }
    }
    public void input(Control owner, InputEvent input)
    {
        if (input is InputEventMouseButton { Pressed: true } mouse && owner.GetGlobalRect().HasPoint(mouse.Position)) ClearFocus();
    }
    private static string[] Completions => GD.Load<GDScript>("res://Workspaces/SceneWorkspace/scripts/ShaderEditor/shader_code_editor.gd").GetScriptConstantMap()["COMPLETIONS"].AsGodotArray().Select(value => value.AsString()).ToArray();
    public void complete_code(Control owner)
    {
        var code = Code(owner);
        foreach (string completion in Completions) code.AddCodeCompletionOption(CodeEdit.CodeCompletionKind.Class, completion, completion);
        foreach (Match uniform in Regex.Matches(code.Text, @"uniform\s+\w+\s+(\w+)")) code.AddCodeCompletionOption(CodeEdit.CodeCompletionKind.Class, uniform.Groups[1].Value, uniform.Groups[1].Value);
        code.UpdateCodeCompletionOptions(true);
    }
    public CodeHighlighter make_highlighter()
    {
        var highlighter = new CodeHighlighter { NumberColor = new Color("b5cea8"), SymbolColor = new Color("d4d4d4"), FunctionColor = new Color("dcdcaa"), MemberVariableColor = new Color("9cdcfe") };
        foreach (string keyword in Completions)
        {
            string token = keyword.Split(' ')[0].TrimEnd(';');
            if (token.EndsWith("()", StringComparison.Ordinal)) token = token[..^2];
            if (Regex.IsMatch(token, @"^[A-Za-z_][A-Za-z0-9_]*$")) highlighter.AddKeywordColor(token, new Color("c586c0"));
        }
        foreach (string type in new[] { "float", "int", "bool", "vec2", "vec3", "vec4", "mat2", "mat3", "mat4", "sampler2D", "samplerCube", "void" }) highlighter.AddKeywordColor(type, new Color("4ec9b0"));
        highlighter.AddColorRegion("//", "", new Color("6a9955"), true); highlighter.AddColorRegion("/*", "*/", new Color("6a9955"), false);
        return highlighter;
    }
    public void open_library_sample(Control owner, Settings entry)
    {
        var shader = new Shader { ResourceName = (entry.TryGetValue("name", out var name) ? name.AsString() : "Shader Sample") + " Copy", Code = entry.TryGetValue("source", out var source) ? source.AsString() : "" };
        var tabs = owner.GetTree().GetFirstNodeInGroup("actor_scene_tabs");
        if (tabs?.HasMethod("open_shader") == true && tabs.Call("open_shader", shader).AsBool())
        {
            Field<Window>(owner, "documentation").Hide();
            var workspace = tabs.Get("shader_workspace").As<Control>();
            if (workspace != null) { workspace.Set("requires_path", true); workspace.Get("load_shader_button").As<Button>().Show(); }
            return;
        }
        var confirm = new ConfirmationDialog { Title = "Open shader sample copy", DialogText = "This standalone editor has no document tabs. Save the current shader and open a separate embedded copy of '" + (entry.TryGetValue("name", out var label) ? label.AsString() : "sample") + "'?" };
        confirm.Confirmed += () =>
        {
            if (GodotObject.IsInstanceValid(owner))
            {
                if (owner.Get("current_path").AsString() != "" || owner.Get("current_shader").As<Shader>() != null) save(owner);
                open_shader(owner, shader); Field<Window>(owner, "documentation").Hide();
            }
            confirm.QueueFree();
        };
        confirm.Canceled += confirm.QueueFree; owner.AddChild(confirm); confirm.PopupCentered();
    }
}
