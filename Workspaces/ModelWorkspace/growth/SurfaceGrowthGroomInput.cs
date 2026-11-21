using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class SurfaceGrowthGeometry
{
    public bool handle(GodotObject tool, InputEvent input)
    {
        if (!active(tool)) { if (tool.Get("drawing").AsBool()) finish(tool, true); return false; }
        string kind = tool.Get("tool").AsString(); var canvas = tool.Get("canvas").As<Control>(); var component = item(tool)!;
        if (kind == "Guide" && guide_event(tool, input)) return true;
        if (kind == "Select strands" && input is InputEventMouseButton { ButtonIndex: MouseButton.Left } select)
        {
            if (select.Pressed)
            {
                var data = component.Get("growth").As<Resource>(); var visual = Visual(canvas, component); Transform3D world = visual != null ? visual.GlobalTransform : ComponentWorld(canvas, component);
                var positions = posed_points(data, visual?.Get("growth_skeleton").As<Skeleton3D>()); float best = 12; tool.Set("selected_root", -1); var camera = canvas.Get("camera").As<Camera3D>();
                foreach (var row in data.Get("roots").AsGodotArray())
                {
                    var root = row.AsGodotDictionary(); Vector3 point = world * point_frame(data, root, positions).Origin; if (camera.IsPositionBehind(point)) continue;
                    float distance = _picking.project(canvas, point).DistanceTo(select.Position); if (distance < best) { best = distance; tool.Set("selected_root", root["id"]); }
                }
                canvas.EmitSignal("gesture_finished");
            }
            return true;
        }
        if (input is InputEventKey { Pressed: true, Keycode: Key.Escape }) { if (tool.Get("drawing").AsBool()) finish(tool, true); else tool.Set("enabled", false); return true; }
        if (input is InputEventMouseButton button)
        {
            if (button.Pressed && button.ShiftPressed && (button.ButtonIndex == MouseButton.WheelUp || button.ButtonIndex == MouseButton.WheelDown))
            { tool.Set("radius", Math.Clamp(tool.Get("radius").AsDouble() * (button.ButtonIndex == MouseButton.WheelUp ? 1.12 : 1 / 1.12), .005, 100)); canvas.EmitSignal("gesture_finished"); return true; }
            if (button.ButtonIndex == MouseButton.Left)
            {
                if (button.Pressed) { tool.Set("drawing", true); tool.Set("component_id", component.Get("id")); tool.Set("stroke_id", Guid.NewGuid().ToString("N")); tool.Set("last_world", new Vector3(float.PositiveInfinity, float.PositiveInfinity, float.PositiveInfinity)); tool.Set("touched", 0); stroke(tool, button.Position, button.CtrlPressed); }
                else finish(tool, false); return true;
            }
        }
        if (input is InputEventMouseMotion motion)
        { tool.Set("cursor", motion.Position); if (tool.Get("drawing").AsBool()) stroke(tool, motion.Position, motion.CtrlPressed); else tool.Set("last_hit", hit(tool, motion.Position)); return true; }
        return false;
    }
    public void draw(GodotObject tool)
    {
        if (!active(tool)) return;
        string kind = tool.Get("tool").AsString(); if (kind == "Guide") draw_guide(tool);
        var canvas = tool.Get("canvas").As<Control>(); var overlay = canvas.Get("overlay").As<Control>(); var camera = canvas.Get("camera").As<Camera3D>();
        if (kind == "Select strands" && tool.Get("selected_root").AsInt64() >= 0)
        {
            var component = item(tool)!; var data = component.Get("growth").As<Resource>(); var visual = Visual(canvas, component); Transform3D world = visual != null ? visual.GlobalTransform : ComponentWorld(canvas, component);
            var positions = posed_points(data, visual?.Get("growth_skeleton").As<Skeleton3D>());
            foreach (var row in data.Get("roots").AsGodotArray())
            {
                var root = row.AsGodotDictionary(); if (root["id"].AsInt64() != tool.Get("selected_root").AsInt64()) continue;
                var frame = world * point_frame(data, root, positions); var points = curve(data, root, -1);
                for (int i = 1; i < points.Length; i++) if (!camera.IsPositionBehind(frame * points[i])) overlay.DrawLine(_picking.project(canvas, frame * points[i - 1]), _picking.project(canvas, frame * points[i]), new Color("ffd078"), 3, true);
            }
        }
        var lastHit = Dict(tool, "last_hit"); if (lastHit.Count == 0) return;
        Vector3 hitPoint = lastHit["world"].AsVector3(); Vector2 center = _picking.project(canvas, hitPoint), edge = _picking.project(canvas, hitPoint + camera.GlobalBasis.X * tool.Get("radius").AsSingle());
        overlay.DrawArc(center, center.DistanceTo(edge), 0, Mathf.Tau, 64, new Color("77e1ce"), 1.5f, true);
        overlay.DrawString(ThemeDB.FallbackFont, new Vector2(14, 24), kind + " · Shift-wheel radius · Ctrl invert · Esc cancel", fontSize: 13, modulate: new Color("77e1ce"));
    }
}
