using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;

public partial class ModelWorkspaceOperations
{
    private readonly ModelImport _imports = new();
    private static bool ScriptType(GodotObject? value, string path)
    { if (value == null) return false; var script = value.GetScript().As<Script>(); while (script != null) { if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true; script = script.GetBaseScript(); } return false; }
    private static Variant Value(Settings state, string key, Variant fallback) => state.TryGetValue(key, out var value) ? value : fallback;
    public void open_source(Control workspace, Variant value, Settings state)
    {
        var buildings = GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/architecture/building_ui.gd"); buildings.Call("cancel", workspace); workspace.Get("rig_ui").As<RefCounted>()?.Call("cancel_job"); var session = Session(workspace); var canvas = workspace.Get("canvas").As<Control>(); var changed = new Callable(workspace, "_changed"); var sync = new Callable(canvas, "request_sync"); if (session.IsConnected("changed", changed)) session.Disconnect("changed", changed); if (session.IsConnected("changed", sync)) session.Disconnect("changed", sync);
        var retained = state.TryGetValue("session", out var stored) && stored.VariantType == Variant.Type.Object ? stored.AsGodotObject() as RefCounted : null;
        if (ScriptType(retained, "res://Workspaces/ModelWorkspace/model_session.gd")) session = retained!;
        else
        {
            session = GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_session.gd").New().As<RefCounted>(); var loaded = _imports.load_document(value); session.Set("document", loaded); session.Set("dirty", value.VariantType != Variant.Type.String); var linked = GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/architecture/module_links.gd").Call("resolve", loaded).AsGodotDictionary(); if (linked["document"].As<Resource>() is Resource resolved) session.Set("document", resolved); else Status(workspace, linked["error"].AsString() + " Saved instance geometry is retained.");
            var document = session.Get("document").As<Resource>(); var saved = document.Get("workspace_state").AsGodotDictionary(); var selected = session.Get("selected").AsGodotArray<string>(); selected.Clear(); if (saved.TryGetValue("selected", out var chosen)) foreach (Variant id in chosen.AsGodotArray()) selected.Add(id.AsString()); session.Set("mode", Value(saved, "mode", "Object").AsString()); session.Set("elements", Value(saved, "elements", Array.Empty<int>())); var items = document.Get("components").AsGodotArray(); if (selected.Count == 0 && items.Count > 0) selected.Add(items[0].As<Resource>().Get("id").AsString());
        }
        workspace.Set("session", session); canvas.Set("session", session); var rig = canvas.Get("rig_tool").As<RefCounted>(); var editor = rig.Get("editor").As<RefCounted>(); editor.Set("session", session); var workspaceState = session.Get("document").As<Resource>().Get("workspace_state").AsGodotDictionary(); var rigState = Value(state, "rig", Value(workspaceState, "rig", new Settings())).AsGodotDictionary(); editor.Set("enabled", Value(rigState, "enabled", false)); editor.Set("rig_id", Value(rigState, "id", "")); editor.Set("selected_bone", Value(rigState, "bone", 0)); editor.Set("mode", Value(rigState, "mode", "Edit")); rig.Get("geometry_cache").AsGodotDictionary().Clear(); rig.Get("heat_signature").AsGodotDictionary().Clear(); rig.Get("region").AsGodotDictionary().Clear(); rig.Set("chain", default(Variant));
        if (!session.IsConnected("changed", changed)) session.Connect("changed", changed); if (!session.IsConnected("changed", sync)) session.Connect("changed", sync); string nativePath = "", rejected = "";
        if (value.VariantType == Variant.Type.String && value.AsString().GetExtension() is "tres" or "res")
        {
            var candidate = ResourceLoader.Load(value.AsString()) as Resource; if (ScriptType(candidate, "res://Workspaces/ModelWorkspace/model_document.gd")) { string[] errors = _documents.validate(candidate!); if (errors.Length == 0) nativePath = value.AsString(); else rejected = errors[0]; }
        }
        workspace.Set("source", value); workspace.Set("path", Value(state, "path", nativePath).AsString()); if (value.VariantType == Variant.Type.String && nativePath.Length == 0 && session.Get("document").As<Resource>().Get("components").AsGodotArray().Count == 0) Status(workspace, "No editable geometry found. GLB/GLTF work at runtime; other formats need a Godot-imported resource. Original file unchanged."); if (rejected.Length > 0 && !state.ContainsKey("session")) { workspace.Set("path", ""); Status(workspace, "Model rejected: " + rejected + ". Original file unchanged; Save requires a new destination."); }
        canvas.Call("restore_state", Value(state, "view", Value(workspaceState, "view", new Settings()))); workspace.Call("_refresh"); canvas.Call("request_sync"); var panels = Value(state, "panels", Value(workspaceState, "panels", new Settings())); if (workspace.Get("_layout_ready").AsBool()) workspace.Call("_restore_panels", panels); else workspace.Set("_pending_panels", panels); buildings.Call("restore", workspace);
    }
    public Settings capture_state(Control workspace)
    {
        GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/architecture/building_ui.gd").Call("cancel", workspace);
        foreach (Node number in workspace.FindChildren("*", "SpinBox", true, false)) if (ScriptType(number, "res://Workspaces/SceneWorkspace/scripts/Timeline/drag_number.gd") && number.Get("_pressed").AsBool()) number.Call("cancel_drag"); var canvas = workspace.Get("canvas").As<Control>(); canvas.Call("cancel_all"); workspace.Set("_property_gesture", false);
        return new Settings { ["session"] = Session(workspace), ["path"] = workspace.Get("path"), ["view"] = canvas.Call("capture_state"), ["panels"] = workspace.Call("_capture_panels"), ["rig"] = workspace.Call("_rig_state") };
    }
    public Settings rig_state(Control workspace)
    { var rig = workspace.Get("canvas").As<Control>().Get("rig_tool").As<RefCounted>().Get("editor").As<RefCounted>(); return new Settings { ["enabled"] = rig.Get("enabled"), ["id"] = rig.Get("rig_id"), ["bone"] = rig.Get("selected_bone"), ["mode"] = rig.Get("mode") }; }
    public void exit_tree(Control workspace) => workspace.Get("rig_ui").As<RefCounted>()?.Call("cancel_job");
    public void key_input(Control workspace, InputEvent input)
    {
        if (!workspace.IsVisibleInTree() || input is not InputEventKey { Pressed: true, Echo: false } key) return; var focused = workspace.GetViewport().GuiGetFocusOwner(); if (focused == null || !workspace.IsAncestorOf(focused) || workspace.Get("_property_gesture").AsBool()) return;
        if (key.CtrlPressed && key.Keycode == Key.S) workspace.Call(key.ShiftPressed ? "save_as" : "save");
        else if (focused is not LineEdit && focused is not TextEdit) { var session = Session(workspace); if (key.CtrlPressed && key.Keycode == Key.Z) session.Call(key.ShiftPressed ? "redo" : "undo"); else if (key.CtrlPressed && key.Keycode == Key.Y) session.Call("redo"); else if (key.Keycode == Key.Delete || key.Keycode == Key.Backspace) Status(workspace, session.Call("delete_selected").AsString()); else return; }
        else return; workspace.GetViewport().SetInputAsHandled();
    }
}
