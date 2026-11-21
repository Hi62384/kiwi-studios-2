using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class SurfaceGrowthGeometry
{
    public Resource? item(GodotObject tool) => tool.Get("canvas").As<Control>()?.Get("session").As<RefCounted>()?.Call("primary").As<Resource>();
    public bool active(GodotObject tool)
    {
        if (!tool.Get("enabled").AsBool()) return false;
        return item(tool)?.Get("growth").As<Resource>() is Resource data && data.Get("source_valid").AsBool();
    }
    private static Node3D? Visual(Control canvas, Resource component) => Get(Dict(canvas, "visuals"), component.Get("id")).As<Node3D>();
    private Transform3D ComponentWorld(Control canvas, Resource component) => _documents.world_transform(canvas.Get("session").As<RefCounted>().Get("document").As<Resource>(), component);
    public Settings hit(GodotObject tool, Vector2 position)
    {
        var component = item(tool); if (component?.Get("growth").As<Resource>() is not Resource data) return new Settings();
        var canvas = tool.Get("canvas").As<Control>(); var visual = Visual(canvas, component); var skeleton = visual?.Get("growth_skeleton").As<Skeleton3D>(); var points = posed_points(data, skeleton);
        Transform3D world = skeleton != null ? skeleton.GlobalTransform : ComponentWorld(canvas, component); long key = Hash(new GArray { data.Get("topology"), points });
        var triangleMesh = tool.Get("triangle_mesh").As<TriangleMesh>();
        if (triangleMesh == null || key != tool.Get("hit_key").AsInt64())
        {
            triangleMesh = new TriangleMesh(); var triangles = data.Get("surface_triangles").AsGodotArray(); var faces = new Vector3[triangles.Count * 3];
            for (int i = 0; i < triangles.Count; i++) { Vector3I ids = triangles[i].AsGodotDictionary()["indices"].AsVector3I(); for (int axis = 0; axis < 3; axis++) faces[i * 3 + axis] = points[ids[axis]]; }
            triangleMesh.CreateFromFaces(faces); tool.Set("triangle_mesh", triangleMesh); tool.Set("hit_key", key);
        }
        var ray = canvas.Call("ray", position).AsGodotDictionary(); var inverse = world.AffineInverse();
        var result = triangleMesh.IntersectRay(inverse * ray["origin"].AsVector3(), (inverse.Basis * ray["direction"].AsVector3()).Normalized());
        if (result.Count == 0) return result;
        result["world"] = world * result["position"].AsVector3(); result["transform"] = world; result["points"] = points; return result;
    }
    public void stroke(GodotObject tool, Vector2 position, bool invert)
    {
        var lastHit = hit(tool, position); tool.Set("last_hit", lastHit); if (lastHit.Count == 0) return;
        Vector3 lastWorld = tool.Get("last_world").AsVector3(); float radius = tool.Get("radius").AsSingle(), spacing = tool.Get("spacing").AsSingle();
        if (lastWorld.IsFinite() && lastWorld.DistanceTo(lastHit["world"].AsVector3()) < radius * spacing) return;
        var component = item(tool)!; var data = component.Get("growth").As<Resource>(); var points = lastHit["points"].AsVector3Array(); Vector3 local = lastHit["position"].AsVector3(), normal = lastHit["normal"].AsVector3();
        int face = Get(lastHit, "face_index", -1).AsInt32(); var triangles = data.Get("surface_triangles").AsGodotArray();
        if (face >= 0 && face < triangles.Count)
        {
            var triangle = triangles[face].AsGodotDictionary(); Vector3I ids = triangle["indices"].AsVector3I(); Vector3 a = points[ids.X], u = points[ids.Y] - a, v = points[ids.Z] - a, p = local - a;
            double denominator = (double)u.Dot(u) * v.Dot(v) - (double)u.Dot(v) * u.Dot(v);
            if (Math.Abs(denominator) > .0000001)
            {
                float y = (float)(((double)v.Dot(v) * p.Dot(u) - (double)u.Dot(v) * p.Dot(v)) / denominator), z = (float)(((double)u.Dot(u) * p.Dot(v) - (double)u.Dot(v) * p.Dot(u)) / denominator);
                var source = data.Get("source_points").AsVector3Array(); local = source[ids.X] * (1 - y - z) + source[ids.Y] * y + source[ids.Z] * z; normal = triangle["normal"].AsVector3();
            }
        }
        Vector3 movement = lastWorld.IsFinite() ? local - tool.Get("previous").AsVector3() : Vector3.Zero; tool.Set("previous", local); tool.Set("last_world", lastHit["world"]);
        var transform = lastHit["transform"].AsTransform3D(); Vector3 scale = transform.Basis.Scale.Abs(); float worldScale = Math.Max(.0001f, Math.Min(scale.X, Math.Min(scale.Y, scale.Z))), localRadius = radius / worldScale;
        tool.Set("radius", localRadius); tool.Set("distance_metric", transform.Basis.Scaled(Vector3.One / worldScale));
        try
        {
            int steps = Math.Clamp((int)Math.Ceiling(movement.Length() / Math.Max(.001f, localRadius * spacing)), 1, 24);
            for (int i = 0; i < steps; i++) apply_at(tool, data, local - movement * (1 - (float)(i + 1) / steps), movement / steps, normal, invert);
            int symmetry = tool.Get("symmetry").AsInt32();
            if (symmetry >= 0)
            {
                local[symmetry] = -local[symmetry]; movement[symmetry] = -movement[symmetry]; normal[symmetry] = -normal[symmetry];
                for (int i = 0; i < steps; i++) apply_at(tool, data, local - movement * (1 - (float)(i + 1) / steps), movement / steps, normal, invert);
            }
        }
        finally { tool.Set("radius", radius); tool.Set("distance_metric", Basis.Identity); }
        var canvas = tool.Get("canvas").As<Control>(); Visual(canvas, component)?.Call("update_growth"); canvas.Get("overlay").As<Control>().QueueRedraw();
    }
    public void finish(GodotObject tool, bool cancel)
    {
        if (!tool.Get("drawing").AsBool()) return; tool.Set("drawing", false); var canvas = tool.Get("canvas").As<Control>(); var session = canvas.Get("session").As<RefCounted>();
        string componentId = tool.Get("component_id").AsString(); var component = session.Get("document").As<Resource>().Call("component", componentId).As<Resource>();
        if (component?.Get("growth").As<Resource>() is not Resource data) return;
        var changes = Dict(data, "pending").Duplicate(true); Dict(data, "pending").Clear(); data.Set("revision", data.Get("revision").AsInt64() + 1); data.Set("render_cache", default(Variant));
        if (!cancel && changes.Count > 0)
        {
            var layers = data.Get("groom_layers").AsGodotArray(); int entries = changes.Count; foreach (var row in layers) entries += row.AsGodotDictionary()["changes"].AsGodotDictionary().Count;
            if (entries > 65536 || layers.Count >= 128) { canvas.EmitSignal("notice", "Groom history budget reached. Apply groom layers before adding more strokes."); session.EmitSignal("changed"); return; }
            var layer = new Settings { ["id"] = tool.Get("stroke_id"), ["tool"] = tool.Get("tool"), ["enabled"] = true, ["changes"] = changes }; var reference = GodotObject.WeakRef(session) ?? throw new InvalidOperationException("Cannot retain groom history owner.");
            void Apply(bool add)
            {
                var current = reference.GetRef().As<RefCounted>(); if (current == null) return;
                var target = current.Get("document").As<Resource>().Call("component", componentId).As<Resource>(); if (target?.Get("growth").As<Resource>() is not Resource growth) return;
                var history = growth.Get("groom_layers").AsGodotArray();
                for (int i = history.Count - 1; i >= 0; i--) if (history[i].AsGodotDictionary()["id"].AsString() == layer["id"].AsString()) history.RemoveAt(i);
                if (add) history.Add(layer.Duplicate(true)); growth.Set("revision", growth.Get("revision").AsInt64() + 1); growth.Set("render_cache", default(Variant));
            }
            Apply(true); session.Call("custom_action", "Groom · " + tool.Get("tool").AsString(), Callable.From(() => Apply(false)), Callable.From(() => Apply(true)), changes.Count * 8);
        }
        else session.EmitSignal("changed"); canvas.EmitSignal("gesture_finished");
    }
}
