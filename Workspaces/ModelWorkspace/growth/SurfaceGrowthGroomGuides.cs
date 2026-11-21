using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class SurfaceGrowthGeometry
{
    private readonly ModelViewportPicking _picking = new();
    private static void Invalidate(GodotObject data) { data.Set("revision", data.Get("revision").AsInt64() + 1); data.Set("render_cache", default(Variant)); }
    private static string RootId(Settings root) => root["id"].AsInt64().ToString(System.Globalization.CultureInfo.InvariantCulture);
    private static Action<Settings, Settings?> GuideSetter(RefCounted session, string id)
    {
        var reference = GodotObject.WeakRef(session) ?? throw new InvalidOperationException("Cannot retain guide history owner.");
        return (guides, groom) =>
        {
            var current = reference.GetRef().As<RefCounted>(); if (current == null) return;
            var target = current.Get("document").As<Resource>().Call("component", id).As<Resource>(); if (target?.Get("growth").As<Resource>() is not Resource data) return;
            data.Set("guides", guides.Duplicate(true)); if (groom != null) data.Set("groom", groom.Duplicate(true)); Invalidate(data);
        };
    }
    public void create_guide(GodotObject tool, int rootIndex)
    {
        var component = item(tool); if (component?.Get("growth").As<Resource>() is not Resource data) return;
        var roots = data.Get("roots").AsGodotArray(); if (rootIndex < 0 || rootIndex >= roots.Count) return;
        var root = roots[rootIndex].AsGodotDictionary(); string guideId = Guid.NewGuid().ToString("N"); var before = Dict(data, "guides").Duplicate(true); var after = before.Duplicate(true);
        after[guideId] = new Settings { ["root"] = root["id"], ["points"] = curve(data, root, -1), ["influence"] = 1.0, ["locked"] = false, ["group"] = "" };
        var assignmentBefore = Dict(data, "groom").Duplicate(true); var assignmentAfter = assignmentBefore.Duplicate(true); float radius = tool.Get("radius").AsSingle(); Vector3 position = root["position"].AsVector3();
        foreach (int index in query(data, position, radius))
        {
            var candidate = roots[index].AsGodotDictionary(); string id = RootId(candidate); if (!assignmentAfter.ContainsKey(id)) assignmentAfter[id] = new Settings();
            var assignment = assignmentAfter[id].AsGodotDictionary(); var weights = Get(assignment, "guide_weights", new Settings()).AsGodotDictionary().Duplicate();
            weights[guideId] = Math.Max(.001f, 1 - candidate["position"].AsVector3().DistanceTo(position) / Math.Max(.001f, radius));
            while (weights.Count > 4)
            {
                Variant weakest = default; double smallest = double.PositiveInfinity;
                foreach (var pair in weights) if (pair.Value.AsDouble() < smallest) { weakest = pair.Key; smallest = pair.Value.AsDouble(); }
                weights.Remove(weakest);
            }
            assignment["guide_weights"] = weights; assignment["guide"] = guideId;
        }
        var canvas = tool.Get("canvas").As<Control>(); var session = canvas.Get("session").As<RefCounted>(); var apply = GuideSetter(session, component.Get("id").AsString());
        apply(after, assignmentAfter); session.Call("custom_action", "Create hair guide", Callable.From(() => apply(before, assignmentBefore)), Callable.From(() => apply(after, assignmentAfter)), assignmentAfter.Count * 4);
        tool.Set("selected_guide", guideId); tool.Set("selected_root", root["id"]);
    }
    public Transform3D guide_frame(GodotObject tool)
    {
        var component = item(tool)!; var data = component.Get("growth").As<Resource>(); var canvas = tool.Get("canvas").As<Control>(); var visual = Visual(canvas, component);
        var points = posed_points(data, visual?.Get("growth_skeleton").As<Skeleton3D>()); Transform3D world = visual != null ? visual.GlobalTransform : ComponentWorld(canvas, component);
        var guide = Get(Dict(data, "guides"), tool.Get("selected_guide"), new Settings()).AsGodotDictionary(); long id = Get(guide, "root", -1).AsInt64();
        foreach (var row in data.Get("roots").AsGodotArray()) { var root = row.AsGodotDictionary(); if (root["id"].AsInt64() == id) return world * point_frame(data, root, points); }
        return world;
    }
    public void draw_guide(GodotObject tool)
    {
        var data = item(tool)!.Get("growth").As<Resource>(); var guides = Dict(data, "guides"); if (!guides.TryGetValue(tool.Get("selected_guide"), out var value)) return;
        var canvas = tool.Get("canvas").As<Control>(); var camera = canvas.Get("camera").As<Camera3D>(); var overlay = canvas.Get("overlay").As<Control>(); var frame = guide_frame(tool); var points = value.AsGodotDictionary()["points"].AsVector3Array();
        for (int i = 0; i < points.Length; i++)
        {
            Vector3 point = frame * points[i]; if (camera.IsPositionBehind(point)) continue; Vector2 screen = _picking.project(canvas, point); overlay.DrawCircle(screen, 5, new Color("ffd078"));
            if (i > 0) overlay.DrawLine(_picking.project(canvas, frame * points[i - 1]), screen, new Color("ffd078"), 2, true);
        }
    }
    public bool guide_event(GodotObject tool, InputEvent input)
    {
        var component = item(tool)!; var data = component.Get("growth").As<Resource>(); var canvas = tool.Get("canvas").As<Control>(); var guides = Dict(data, "guides"); int guidePoint = tool.Get("guide_point").AsInt32();
        if (input is InputEventKey { Pressed: true, Keycode: Key.Escape } && guidePoint >= 0)
        { data.Set("guides", Dict(tool, "guide_before").Duplicate(true)); Invalidate(data); tool.Set("guide_point", -1); canvas.Call("request_sync"); return true; }
        if (input is InputEventMouseButton { ButtonIndex: MouseButton.Left } button)
        {
            if (button.Pressed)
            {
                if (guides.TryGetValue(tool.Get("selected_guide"), out var selectedGuide) && !Get(selectedGuide.AsGodotDictionary(), "locked", false).AsBool())
                {
                    var frame = guide_frame(tool); var points = selectedGuide.AsGodotDictionary()["points"].AsVector3Array(); float best = 10; int selected = -1;
                    for (int i = 1; i < points.Length; i++) { float distance = _picking.project(canvas, frame * points[i]).DistanceTo(button.Position); if (distance < best) { best = distance; selected = i; } }
                    if (selected >= 0) { tool.Set("guide_point", selected); tool.Set("guide_before", guides.Duplicate(true)); tool.Set("guide_plane", new Plane(canvas.Get("camera").As<Camera3D>().GlobalBasis.Z, frame * points[selected])); return true; }
                }
                float closest = 12; int chosen = -1; var visual = Visual(canvas, component); var world = visual != null ? visual.GlobalTransform : ComponentWorld(canvas, component); var posed = posed_points(data, visual?.Get("growth_skeleton").As<Skeleton3D>()); var roots = data.Get("roots").AsGodotArray(); var camera = canvas.Get("camera").As<Camera3D>();
                for (int i = 0; i < roots.Count; i++)
                {
                    Vector3 point = world * point_frame(data, roots[i].AsGodotDictionary(), posed).Origin; if (camera.IsPositionBehind(point)) continue; float distance = _picking.project(canvas, point).DistanceTo(button.Position); if (distance < closest) { closest = distance; chosen = i; }
                }
                if (chosen >= 0) { create_guide(tool, chosen); canvas.EmitSignal("gesture_finished"); } return true;
            }
            if (guidePoint >= 0)
            {
                var after = guides.Duplicate(true); var before = Dict(tool, "guide_before").Duplicate(true); tool.Set("guide_point", -1); var session = canvas.Get("session").As<RefCounted>(); var apply = GuideSetter(session, component.Get("id").AsString());
                session.Call("custom_action", "Move groom guide point", Callable.From(() => apply(before, null)), Callable.From(() => apply(after, null)), after.Count * 16); return true;
            }
            return true;
        }
        if (input is InputEventMouseMotion motion && guidePoint >= 0)
        {
            var ray = _picking.ray(canvas, motion.Position); Vector3? hit = tool.Get("guide_plane").AsPlane().IntersectsRay(ray["origin"].AsVector3(), ray["direction"].AsVector3());
            if (hit.HasValue)
            {
                var guide = guides[tool.Get("selected_guide")].AsGodotDictionary(); var points = guide["points"].AsVector3Array(); points[guidePoint] = guide_frame(tool).AffineInverse() * hit.Value; guide["points"] = points; Invalidate(data); Visual(canvas, component)?.Call("update_growth");
            }
            return true;
        }
        return false;
    }
}
