using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;

public partial class EnvironmentViewportRuntime : RefCounted
{
    private readonly ModelViewportState _state = new();
    private readonly ModelViewportNavigation _navigation = new();
    private readonly ModelViewportSync _sync = new();
    private readonly ModelViewportPicking _picking = new();
    private readonly ModelViewportInput _input = new();
    private readonly ModelViewportOverlay _overlay = new();
    private readonly ModelDocumentOperations _documents = new();
    private readonly ModelMeshOperations _meshes = new();
    private static readonly string[] BrushTools = { "Raise", "Lower", "Smooth", "Flatten", "Level to height", "Terrace", "Noise", "Ridge", "Valley", "Pinch / sharpen", "Relax", "Erode brush", "Stamp" };
    private static Settings Dict(GodotObject value, string key) => value.Get(key).AsGodotDictionary();
    private static Variant Get(Settings values, Variant key, Variant fallback = default) => values.TryGetValue(key, out var value) ? value : fallback;
    private static RefCounted Tool(Control canvas, string key) => canvas.Get(key).As<RefCounted>();
    private static Node3D Renderer(Control canvas) => canvas.Get("renderer").As<Node3D>();
    private static Resource Document(Control canvas) => canvas.Get("session").As<RefCounted>().Get("document").As<Resource>();
    private static string Mode(Control canvas) => canvas.Get("environment_tool").AsString();
    private static bool BiomeMode(string mode) => mode is "Paint biome" or "Erase biome";
    private static bool ScatterMode(string mode) => mode is "Paint scatter" or "Erase scatter";
    public RefCounted? environment_session(Control canvas)
    {
        var session = canvas.Get("session").As<RefCounted>(); if (session == null) return null; var script = session.GetScript().As<Script>();
        while (script != null) { if (script.ResourcePath == "res://Workspaces/EnvironmentWorkspace/environment_session.gd") return session; script = script.GetBaseScript(); } return null;
    }
    public void setup(Control canvas)
    {
        foreach (string key in new[] { "road_tool", "cave_tool", "water_tool", "biome_tool" }) Tool(canvas, key).Set("canvas", canvas);
        _state.setup(canvas); var renderer = Renderer(canvas); renderer.Set("progressive", true); renderer.Set("animate_preview", true); renderer.Set("priority_camera", canvas.Get("camera")); canvas.Get("world").As<Node3D>().AddChild(renderer); canvas.Get("grid").As<Node3D>().Hide(); canvas.Set("show_edges", false); canvas.Call("request_sync");
    }
    public Settings capture(Control canvas)
    {
        var state = _state.capture(canvas); var water = Tool(canvas, "water_tool"); state["water_handle"] = new Settings { ["path"] = water.Get("river_index"), ["point"] = water.Get("point_index") }; state["biome_id"] = Tool(canvas, "biome_tool").Get("biome_id"); return state;
    }
    public void restore(Control canvas, Settings state)
    {
        var settings = state.Duplicate(); settings["grid_visible"] = Get(settings, "grid_visible", false).AsBool(); _state.restore(canvas, settings);
        var water = Get(state, "water_handle", new Settings()).AsGodotDictionary(); Tool(canvas, "water_tool").Set("river_index", Get(water, "path", 0).AsInt32()); Tool(canvas, "water_tool").Set("point_index", Get(water, "point", 0).AsInt32()); Tool(canvas, "biome_tool").Set("biome_id", Get(state, "biome_id", "").AsString());
    }
    public void frame(Control canvas, bool all)
    { _navigation.frame(canvas, all); canvas.Set("distance", canvas.Get("distance").AsDouble() * .65); canvas.Get("camera").As<Camera3D>().Size *= .7f; _navigation.update_camera(canvas); }
    public void sync(Control canvas)
    {
        var session = environment_session(canvas); if (session == null) return;
        var document = session.Call("environment").As<Resource>(); Renderer(canvas).Call("configure", document); var evaluated = Dict(canvas, "evaluated"); evaluated.Clear(); sync_lighting(canvas);
        foreach (var value in document.Get("components").AsGodotArray()) { var item = value.As<Resource>(); evaluated[item.Get("id")] = item.Get("mesh"); }
        canvas.Set("_pending_sync", false); canvas.Get("overlay").As<Control>().QueueRedraw();
    }
    public void sync_lighting(Control canvas)
    {
        var session = environment_session(canvas); if (session == null) return; var document = session.Call("environment").As<Resource>(); var world = canvas.Get("world").As<Node3D>(); var camera = canvas.Get("camera").As<Camera3D>(); var renderer = Renderer(canvas);
        var lights = world.FindChildren("*", "DirectionalLight3D", false, false); var climate = document.Get("climate").As<Resource>(); var state = new Settings();
        if (climate != null && climate.HasMethod("evaluate")) state = climate.Call("evaluate", camera.GlobalPosition, renderer.Get("preview_time")).AsGodotDictionary();
        var sunlight = Dict(document, "sunlight");
        if (lights.Count > 0)
        {
            var sun = (DirectionalLight3D)lights[0];
            if (state.Count == 0) { sun.Visible = Get(sunlight, "enabled", true).AsBool(); sun.RotationDegrees = Get(sunlight, "rotation", new Vector3(-45, -30, 0)).AsVector3(); sun.LightColor = Get(sunlight, "color", Colors.White).AsColor(); sun.LightEnergy = Get(sunlight, "energy", 1.5).AsSingle(); }
            else
            {
                Vector3 direction = state["sun_direction"].AsVector3(); double elevation = state["sun_elevation"].AsDouble(); sun.Visible = Get(sunlight, "enabled", true).AsBool() && elevation > Mathf.DegToRad(-10); sun.Basis = Basis.LookingAt(-direction.Normalized(), Vector3.Up);
                sun.LightColor = Get(sunlight, "color", Colors.White).AsColor().Lerp(new Color(1, .55f, .3f), (float)(Math.Clamp(1 - Math.Abs(elevation) / .25, 0, 1) * .55)); sun.LightEnergy = Get(sunlight, "energy", 1.5).AsSingle() * state["sunlight_energy"].AsSingle();
            }
        }
        if (lights.Count > 1) ((DirectionalLight3D)lights[1]).Visible = false;
        var assets = GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd"); long key = assets.Call("world_stamp", document).AsInt64();
        if (key != canvas.Get("_environment_key").AsInt64())
        {
            canvas.Set("_environment_key", key); var environment = assets.Call("world_environment", document).As<Godot.Environment>();
            if (climate != null && climate.HasMethod("make_environment")) environment = environment != null ? (Godot.Environment)environment.Duplicate(true) : climate.Call("make_environment", renderer.Get("preview_time")).As<Godot.Environment>();
            foreach (Node child in world.GetChildren()) if (child is WorldEnvironment target)
            {
                var preview = canvas.Get("_preview_environment").As<Godot.Environment>(); if (preview == null) { preview = target.Environment; canvas.Set("_preview_environment", preview); } target.Environment = environment ?? preview;
            }
        }
        foreach (Node child in world.GetChildren()) if (child is WorldEnvironment target && climate != null && climate.HasMethod("apply_environment"))
        { state = climate.Call("apply_environment", target.Environment, renderer.Get("preview_time"), camera.GlobalPosition).AsGodotDictionary(); renderer.Call("update_weather_particles", state, camera); }
    }
    public Settings geometry(Control canvas) => Mode(canvas) == "Select" ? _picking.geometry(canvas) : new Settings();
    public void process(Control canvas, double delta)
    {
        var biome = Tool(canvas, "biome_tool"); string mode = Mode(canvas); if (!BiomeMode(mode) && Dict(biome, "_stroke").Count > 0) biome.Call("cancel"); _sync.process(canvas, delta); sync_lighting(canvas);
        var info = BiomeMode(mode) ? biome.Call("target").AsGodotDictionary() : new Settings(); string selected = Get(info, "id", "").AsString(), id = info.Count > 0 ? biome.Get("biome_id").AsString() : ""; var renderer = Renderer(canvas);
        if (selected != renderer.Get("biome_preview_terrain").AsString() || id != renderer.Get("biome_preview_id").AsString()) { renderer.Set("biome_preview_terrain", selected); renderer.Set("biome_preview_id", id); canvas.Call("request_sync"); }
        var preview = canvas.Get("_drop_preview").As<Node3D>(); if (preview != null && GodotObject.IsInstanceValid(preview) && !new Rect2(Vector2.Zero, canvas.Size).HasPoint(canvas.GetLocalMousePosition())) preview.Hide();
    }
}
