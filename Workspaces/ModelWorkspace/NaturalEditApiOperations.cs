using Godot;
using Settings = Godot.Collections.Dictionary;
public partial class NaturalEditApiOperations : RefCounted
{
    public NaturalEditCoordinator? controller(Control workspace, bool create)
    {
        var controller = workspace.GetNodeOrNull<NaturalEditCoordinator>("_NaturalEditCoordinator");
        if (controller == null && create) { controller = new NaturalEditCoordinator { Name = "_NaturalEditCoordinator" }; workspace.AddChild(controller); controller.configure(workspace); }
        return controller;
    }
    public void request(Control workspace, string id, string key, Variant value, bool finished) => controller(workspace, true)!.request(id, key, value, finished);
    public void finish(Control workspace) { var current = controller(workspace, false); if (current != null) current.finish(); else workspace.Get("session").As<RefCounted>().Call("commit", "Change natural source"); }
    public void cancel(Control workspace) { var current = controller(workspace, false); if (current != null) current.cancel(); else workspace.Get("session").As<RefCounted>().Call("cancel"); }
    public Settings begin_flush(Control workspace)
    {
        if (workspace.GetMeta("natural_edit", new Settings()).AsGodotDictionary().Count == 0) return new Settings { ["done"] = true };
        var session = workspace.Get("session").As<RefCounted>(); finish(workspace); return new Settings { ["done"] = false, ["session"] = session };
    }
    public bool flush_done(Control workspace, Settings state) => state["done"].AsBool() || !GodotObject.IsInstanceValid(workspace) || !workspace.IsInsideTree() || workspace.Get("session").AsGodotObject() != state["session"].AsGodotObject() || workspace.GetMeta("natural_edit", new Settings()).AsGodotDictionary().Count == 0;
    public bool finish_flush(Control workspace, Settings state) => state["done"].AsBool() || (GodotObject.IsInstanceValid(workspace) && workspace.IsInsideTree() && workspace.Get("session").AsGodotObject() == state["session"].AsGodotObject());
}
