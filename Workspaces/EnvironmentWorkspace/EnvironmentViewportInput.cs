using Godot;
using System;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;

public partial class EnvironmentViewportRuntime
{
    public void dab(Control canvas, Vector2 point, bool subtract)
    {
        var session = environment_session(canvas)!; string mode = Mode(canvas); double radius = canvas.Get("brush_radius").AsDouble();
        if (ScatterMode(mode)) { session.Call("paint_scatter", point, radius, (mode == "Erase scatter") != subtract); canvas.Call("request_sync"); return; }
        int operation = Math.Max(0, Array.IndexOf(BrushTools, mode)); if (subtract && operation is 0 or 1) operation = 1 - operation;
        double strength = canvas.Get("brush_strength").AsDouble(); if (subtract && operation is 6 or 7 or 8 or 12) strength = -strength;
        var options = new Settings { ["target"] = canvas.Get("brush_target_height"), ["terrace_step"] = canvas.Get("brush_terrace_step"), ["square"] = canvas.Get("brush_square"), ["stamp"] = canvas.Get("stamp_image") };
        var points = new List<Vector2> { point }; if (canvas.Get("brush_symmetry_x").AsBool()) points.Add(new Vector2(-point.X, point.Y)); if (canvas.Get("brush_symmetry_z").AsBool()) { int count = points.Count; for (int i = 0; i < count; i++) points.Add(new Vector2(points[i].X, -points[i].Y)); }
        var seen = new HashSet<Vector2>(); foreach (Vector2 sample in points) if (seen.Add(sample)) session.Call("sculpt", sample, radius, strength, canvas.Get("brush_falloff"), operation, canvas.Get("_flatten_height"), options); canvas.Call("request_sync");
    }
    public void finish_brush(Control canvas, bool cancelled)
    { var session = environment_session(canvas); session?.Call("finish_terrain", cancelled); session?.Call("finish_scatter", cancelled); canvas.Set("_painting", false); }
    public void handle(Control canvas, InputEvent input)
    {
        foreach (string key in new[] { "road_tool", "biome_tool", "water_tool", "cave_tool" }) if (Tool(canvas, key).Call("input", input).AsBool()) { canvas.AcceptEvent(); return; }
        string mode = Mode(canvas); var session = environment_session(canvas)!;
        if (input is InputEventKey { Pressed: true } keyboard)
        {
            if (keyboard.Keycode == Key.Escape && canvas.Get("_painting").AsBool()) { finish_brush(canvas, true); canvas.Call("request_sync"); canvas.AcceptEvent(); return; }
            if (keyboard.Keycode is Key.Tab or Key.Key1 or Key.Key2 or Key.Key3 or Key.Key4) { canvas.AcceptEvent(); return; }
            if (keyboard.Keycode is Key.W or Key.E or Key.R or Key.G or Key.S && !canvas.Get("_navigating").AsBool() && !keyboard.CtrlPressed) { mode = "Select"; canvas.Set("environment_tool", mode); }
        }
        if (input is InputEventMouseButton { Pressed: true, ShiftPressed: true } wheel && wheel.ButtonIndex is MouseButton.WheelUp or MouseButton.WheelDown && mode != "Select")
        { canvas.Set("brush_radius", Math.Clamp(canvas.Get("brush_radius").AsDouble() * (wheel.ButtonIndex == MouseButton.WheelUp ? 1.15 : 1 / 1.15), .05, 1000)); canvas.EmitSignal("brush_settings_changed"); canvas.Get("overlay").As<Control>().QueueRedraw(); canvas.AcceptEvent(); return; }
        if ((Array.IndexOf(BrushTools, mode) >= 0 || mode is "Paint material" or "Paint scatter" or "Erase scatter") && !canvas.Get("_navigating").AsBool() && !canvas.Get("_panning").AsBool() && !canvas.Get("_orbiting").AsBool())
        {
            if (input is InputEventMouseMotion motion)
            {
                canvas.Set("_mouse", motion.Position); var hit = pick(canvas, motion.Position, true, Array.Empty<string>()); canvas.Set("_brush_hit", hit);
                if (canvas.Get("_painting").AsBool() && hit.Count > 0 && hit["id"].AsString() == canvas.Get("_painting_id").AsString())
                {
                    Vector3 local = hit["local"].AsVector3(); var current = new Vector2(local.X, local.Z); Vector2 previous = canvas.Get("_last_dab").AsVector2(); int count = Math.Clamp((int)Math.Ceiling(current.DistanceTo(previous) / Math.Max(.05, canvas.Get("brush_radius").AsDouble() * canvas.Get("brush_spacing").AsDouble())), 1, 64);
                    for (int i = 1; i <= count; i++) dab(canvas, previous.Lerp(current, (float)i / count), motion.CtrlPressed); canvas.Set("_last_dab", current);
                }
                canvas.Get("overlay").As<Control>().QueueRedraw(); canvas.AcceptEvent(); return;
            }
            if (input is InputEventMouseButton { ButtonIndex: MouseButton.Left } button)
            {
                canvas.GrabFocus();
                if (button.Pressed)
                {
                    var hit = pick(canvas, button.Position, true, Array.Empty<string>()); canvas.Set("_brush_hit", hit);
                    if (hit.Count > 0)
                    {
                        bool scatterMode = ScatterMode(mode), valid = false;
                        if (scatterMode)
                        {
                            var selected = session.Call("primary").As<Resource>(); var settings = selected != null ? Get(Dict(Document(canvas), "component_settings"), selected.Get("id"), new Settings()).AsGodotDictionary() : new Settings(); var scatter = Get(settings, "scatter").As<Resource>();
                            valid = scatter != null && scatter.Get("terrain_id").AsString() == hit["id"].AsString() && session.Call("begin_scatter", selected!.Get("id")).AsBool();
                        }
                        else valid = session.Call("begin_terrain", hit["id"].AsString(), mode == "Paint material").AsBool();
                        if (valid)
                        {
                            canvas.Set("_painting", true); canvas.Set("_painting_id", hit["id"]); if (!scatterMode) session.Call("select", hit["id"].AsString());
                            Vector3 local = hit["local"].AsVector3(); var point = new Vector2(local.X, local.Z); canvas.Set("_last_dab", point); canvas.Set("_flatten_height", local.Y); dab(canvas, point, button.CtrlPressed);
                        }
                    }
                }
                else if (canvas.Get("_painting").AsBool()) { finish_brush(canvas, false); canvas.EmitSignal("gesture_finished"); }
                canvas.AcceptEvent(); return;
            }
        }
        if (mode == "Place" && input is InputEventMouseButton { ButtonIndex: MouseButton.Left, Pressed: true } place)
        {
            var hit = pick(canvas, place.Position, true, Array.Empty<string>()); string asset = canvas.Get("placement_asset").AsString(); if (hit.Count > 0 && asset.Length > 0) canvas.EmitSignal("asset_placed", asset, placement_point(canvas, hit["point"].AsVector3(), hit["id"].AsString()), hit["normal"]); canvas.AcceptEvent(); return;
        }
        _input.handle(canvas, input);
    }
    public void cancel_all(Control canvas)
    {
        foreach (string name in new[] { "road_tool", "cave_tool", "water_tool", "biome_tool" }) { var tool = Tool(canvas, name); if (tool.Get("canvas").AsGodotObject() != null) tool.Call("cancel"); }
        if (canvas.Get("_painting").AsBool()) finish_brush(canvas, true); clear_preview(canvas); _state.cancel_all(canvas);
    }
}
