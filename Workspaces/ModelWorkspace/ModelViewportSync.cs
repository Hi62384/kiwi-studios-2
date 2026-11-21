using Godot;
using System.Collections.Generic;
using System.Linq;
using Settings = Godot.Collections.Dictionary;

public partial class ModelViewportSync : RefCounted
{
    private readonly ModelDocumentOperations _documents = new();
    private readonly ModelModifiers _modifiers = new();
    private readonly ModelComponentOperations _components = new();
    private readonly ModelNaturalRender _natural = new();
    public void sync(Control canvas)
    {
        var session = canvas.Get("session").As<RefCounted>(); var document = session.Get("document").As<Resource>(); document.Call("prepare_growth");
        var items = document.Get("components").AsGodotArray(); var state = _documents.hierarchy_state(document, new()); var poses = state["poses"].AsGodotDictionary(); var visible = state["visible"].AsGodotDictionary();
        var visuals = canvas.Get("visuals").AsGodotDictionary(); var evaluated = canvas.Get("evaluated").AsGodotDictionary(); var signatures = canvas.Get("signatures").AsGodotDictionary(); var hidden = canvas.Get("preview_hidden").AsGodotDictionary(); var scope = canvas.Get("_material_scope").AsGodotDictionary();
        var live = new HashSet<string>(); var liveMaterials = new HashSet<ulong>(); ulong started = Time.GetTicksUsec(); bool uploaded = false, deferred = false, budgeted = items.Count > 64;
        foreach (Variant value in items)
        {
            var item = value.As<Resource>(); string id = item.Get("id").AsString(); live.Add(id); bool growth = item.Get("growth").As<Resource>() != null;
            if (!visuals.TryGetValue(id, out var found)) { MeshInstance3D node = growth ? GD.Load<GDScript>("res://Workspaces/ModelWorkspace/growth/surface_growth_instance.gd").New().As<MeshInstance3D>() : new MeshInstance3D(); canvas.Get("world").As<Node3D>().AddChild(node); visuals[id] = node; found = node; }
            var visual = found.As<MeshInstance3D>(); visual.Transform = poses[id].AsTransform3D(); visual.Visible = visible[id].AsBool() && !hidden.ContainsKey(id);
            foreach (Variant material in item.Get("surface_materials").AsGodotArray()) if (material.As<Material>() is ShaderMaterial shader) liveMaterials.Add(shader.GetInstanceId());
            if (growth) { if (visual.HasMethod("configure")) visual.Call("configure", item, false); continue; }
            var mesh = item.Get("mesh").As<Resource>(); if (mesh == null) { visual.Mesh = null; continue; } var binding = item.Get("binding").As<Resource>();
            long signature = GD.Hash(new Godot.Collections.Array { mesh.Get("vertices"), mesh.Get("faces"), mesh.Get("uv"), mesh.Get("materials"), mesh.Get("smooth"), item.Get("modifiers"), item.Get("surface_materials"), item.Get("skin_mesh"), binding?.Get("revision") ?? Variant.From(0) });
            if (!signatures.TryGetValue(id, out var previous) || previous.AsInt64() != signature)
            {
                if (budgeted && uploaded && Time.GetTicksUsec() - started >= canvas.Get("upload_budget_usec").AsUInt64()) { deferred = true; continue; }
                evaluated[id] = _modifiers.evaluate(item); visual.Mesh = item.Get("skin_mesh").As<Mesh>() ?? (binding != null ? binding.Get("source_mesh").As<Mesh>() : _components.render_mesh(item, scope)); signatures[id] = signature; uploaded = true;
            }
            visual.Transparency = canvas.Get("wireframe").AsBool() ? 1 : canvas.Get("xray").AsBool() ? .65f : 0;
        }
        foreach (Variant key in visuals.Keys.ToArray()) if (!live.Contains(key.AsString())) { visuals[key].As<Node>().QueueFree(); visuals.Remove(key); evaluated.Remove(key); signatures.Remove(key); }
        foreach (Variant key in scope.Keys.ToArray()) if (!liveMaterials.Contains(key.AsUInt64())) scope.Remove(key);
        var rig = canvas.Get("rig_tool").As<RefCounted>(); if (rig != null) { rig.Get("editor").As<RefCounted>().Set("session", session); rig.Call("sync"); }
        canvas.Set("_pending_sync", deferred); canvas.Get("overlay").As<Control>().QueueRedraw();
    }
    public void process(Control canvas, double delta)
    {
        if (!canvas.IsVisibleInTree()) return; if (canvas.Get("_pending_sync").AsBool()) canvas.Call("sync");
        double time = canvas.Get("_natural_preview_time").AsDouble() + delta; canvas.Set("_natural_preview_time", time); var visited = new Settings();
        foreach (Variant value in canvas.Get("visuals").AsGodotDictionary().Values) _natural.time(value.As<Node>(), time, visited);
        if (canvas.Get("_navigating").AsBool()) canvas.Get("_navigation_native").As<ModelViewportNavigation>().fly(canvas, delta);
    }
}
