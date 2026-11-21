using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class EnvironmentViewportRuntime
{
    public bool can_drop_data(Control canvas, Vector2 point, Variant payload)
    {
        string[] paths = GD.Load<GDScript>("res://Workspaces/SceneWorkspace/scripts/Timeline/timeline_canvas.gd").Call("dropped_paths", payload).AsStringArray(); if (paths.Length != 1) return false;
        string path = paths[0], extension = path.GetExtension().ToLowerInvariant(); if (extension is not ("tres" or "res" or "mesh" or "obj" or "gltf" or "glb")) return false;
        var source = GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd").Call("load_parts", path).AsGodotDictionary(); if (source["error"].AsString().Length > 0) return false;
        var hit = pick(canvas, point, true, Array.Empty<string>()); if (hit.Count == 0) return false; var preview = canvas.Get("_drop_preview").As<Node3D>();
        if (preview == null || path != canvas.Get("_drop_path").AsString())
        {
            clear_preview(canvas); preview = new Node3D(); canvas.Set("_drop_preview", preview); canvas.Get("world").As<Node3D>().AddChild(preview); canvas.Set("_drop_path", path);
            foreach (var value in source["parts"].AsGodotArray()) { var part = value.AsGodotDictionary(); preview.AddChild(new MeshInstance3D { Mesh = part["mesh"].As<Mesh>(), Transform = part["transform"].AsTransform3D(), Transparency = .45f }); }
        }
        preview.Show(); preview.Position = placement_point(canvas, hit["point"].AsVector3(), hit["id"].AsString()); preview.Basis = canvas.Get("align_surface").AsBool() ? new Basis(new Quaternion(Vector3.Up, hit["normal"].AsVector3().Normalized())) : Basis.Identity; return true;
    }
    public void drop_data(Control canvas, Vector2 point, Variant payload)
    {
        if (!can_drop_data(canvas, point, payload)) return; var hit = pick(canvas, point, true, Array.Empty<string>()); string path = canvas.Get("_drop_path").AsString(); clear_preview(canvas); canvas.EmitSignal("asset_placed", path, placement_point(canvas, hit["point"].AsVector3(), hit["id"].AsString()), hit["normal"]);
    }
    public Vector3 placement_point(Control canvas, Vector3 point, string terrainId)
    {
        if (canvas.Get("snap").AsBool() != Input.IsPhysicalKeyPressed(Key.Ctrl))
        {
            float step = canvas.Get("grid_step").AsSingle(); point.X = Mathf.Snapped(point.X, step); point.Z = Mathf.Snapped(point.Z, step); var document = Document(canvas); var terrain = document.Call("terrain", terrainId).As<Resource>(); var item = _documents.component(document, terrainId);
            if (terrain != null && item != null)
            {
                var transform = _documents.world_transform(document, item); Vector3 local = transform.AffineInverse() * point; var surface = terrain.Call("sample", new Vector2(local.X, local.Z)).AsGodotDictionary(); if (surface.Count > 0) point = transform * new Vector3(local.X, surface["height"].AsSingle(), local.Z);
            }
        }
        return point;
    }
    public void clear_preview(Control canvas)
    {
        var preview = canvas.Get("_drop_preview").As<Node3D>(); if (preview != null && GodotObject.IsInstanceValid(preview)) preview.QueueFree(); canvas.Set("_drop_preview", default(Variant)); canvas.Set("_drop_path", "");
    }
}
