using Godot;
using Settings = Godot.Collections.Dictionary;

public partial class ModelViewportState : RefCounted
{
    public void setup(Control canvas)
    {
        canvas.Connect(Node.SignalName.TreeExiting, Callable.From(() => { var rig = canvas.Get("rig_tool").As<RefCounted>(); rig?.Get("_native").As<RigViewport>()?.release(); }));
        canvas.Get("groom_tool").As<RefCounted>().Set("canvas", canvas);
        var session = canvas.Get("session").As<RefCounted>(); var rig = GD.Load<GDScript>("res://Workspaces/ModelWorkspace/rig/rig_viewport.gd").New().As<RefCounted>();
        rig.Set("canvas", canvas); rig.Set("editor", GD.Load<GDScript>("res://Workspaces/ModelWorkspace/rig/rig_editor.gd").New(session)); canvas.Set("rig_tool", rig);
        canvas.FocusMode = Control.FocusModeEnum.All; canvas.ClipContents = true; canvas.CustomMinimumSize = new Vector2(220, 200);
        var viewport = canvas.Get("viewport").As<SubViewport>(); var world = canvas.Get("world").As<Node3D>(); var camera = canvas.Get("camera").As<Camera3D>();
        viewport.OwnWorld3D = true; viewport.RenderTargetUpdateMode = SubViewport.UpdateMode.Always; viewport.Msaa3D = Viewport.Msaa.Msaa2X;
        canvas.AddChild(viewport); viewport.AddChild(world); world.AddChild(camera); camera.Current = true; camera.Near = .02f; camera.Far = 2000;
        var display = canvas.Get("display").As<TextureRect>(); display.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); display.MouseFilter = Control.MouseFilterEnum.Ignore; display.ExpandMode = TextureRect.ExpandModeEnum.IgnoreSize; display.Texture = viewport.GetTexture(); canvas.AddChild(display);
        var overlay = canvas.Get("overlay").As<Control>(); overlay.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); overlay.MouseFilter = Control.MouseFilterEnum.Ignore; canvas.AddChild(overlay); overlay.Connect(CanvasItem.SignalName.Draw, new Callable(canvas, "_draw_overlay"));
        var environment = new WorldEnvironment { Environment = new Godot.Environment { BackgroundMode = Godot.Environment.BGMode.Color, BackgroundColor = new Color("18232e"), AmbientLightSource = Godot.Environment.AmbientSource.Color, AmbientLightColor = new Color("c7dbed"), AmbientLightEnergy = .55f } }; world.AddChild(environment);
        for (int i = 0; i < 2; i++) world.AddChild(new DirectionalLight3D { RotationDegrees = new Vector3(-45, i == 0 ? -35 : 130, 0), LightEnergy = i == 0 ? 1.1f : .45f });
        world.AddChild(canvas.Get("grid").As<Node3D>()); canvas.Call("rebuild_grid"); canvas.Connect(Control.SignalName.Resized, new Callable(canvas, "_resize")); canvas.Call("_resize"); canvas.Call("update_camera");
        session?.Connect("changed", new Callable(canvas, "request_sync"));
    }
    private static readonly string[] Direct = { "target", "distance", "yaw", "pitch", "grid_step", "snap", "xray", "show_edges", "tool", "local_axes", "wireframe", "snap_kind", "align_surface", "proportional", "radius", "strength", "sculpt", "push_pull", "fly_speed" };
    public Settings capture(Control canvas)
    {
        var result = new Settings(); foreach (string field in Direct) result[field] = canvas.Get(field);
        var camera = canvas.Get("camera").As<Camera3D>(); result["orthographic"] = camera.Projection == Camera3D.ProjectionType.Orthogonal; result["camera_size"] = camera.Size; result["normals"] = canvas.Get("show_normals"); result["grid_visible"] = canvas.Get("grid").As<Node3D>().Visible; return result;
    }
    public void restore(Control canvas, Settings state)
    {
        var defaults = new Settings { ["target"] = Vector3.Zero, ["distance"] = 7f, ["yaw"] = .65f, ["pitch"] = -.4f, ["grid_step"] = .25f, ["snap"] = false, ["xray"] = false, ["show_edges"] = true, ["tool"] = "Move", ["local_axes"] = false, ["wireframe"] = false, ["snap_kind"] = "Grid", ["align_surface"] = false, ["proportional"] = false, ["radius"] = 1.5f, ["strength"] = .3f, ["sculpt"] = "", ["push_pull"] = false, ["fly_speed"] = 4f };
        foreach (string field in Direct) canvas.Set(field, state.TryGetValue(field, out var value) ? value : defaults[field]);
        var camera = canvas.Get("camera").As<Camera3D>(); camera.Projection = state.TryGetValue("orthographic", out var orthographic) && orthographic.AsBool() ? Camera3D.ProjectionType.Orthogonal : Camera3D.ProjectionType.Perspective; camera.Size = state.TryGetValue("camera_size", out var size) ? size.AsSingle() : 6;
        canvas.Set("show_normals", state.TryGetValue("normals", out var normals) && normals.AsBool()); canvas.Get("grid").As<Node3D>().Visible = !state.TryGetValue("grid_visible", out var grid) || grid.AsBool();
        canvas.Call("rebuild_grid"); canvas.Call("update_camera"); canvas.Call("request_sync");
    }
    public void cancel_all(Control canvas)
    {
        var rig = canvas.Get("rig_tool").As<RefCounted>(); if (rig != null) { rig.Call("finish", true); rig.Set("chain", default(Variant)); rig.Set("placing", false); }
        var transforms = canvas.Get("_transforms_native").As<ModelViewportTransforms>(); transforms.finish_transform(canvas, true); transforms.finish_extrusion(canvas, true);
        var session = canvas.Get("session").As<RefCounted>(); if (session.Get("_gesture").AsGodotDictionary().Count > 0) session.Call("cancel");
        foreach (string flag in new[] { "_pressed", "_box", "_navigating", "_panning", "_orbiting" }) canvas.Set(flag, false); canvas.Set("_create", ""); canvas.Set("_create_phase", 0);
    }
}
