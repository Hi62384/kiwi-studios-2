using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class ModelViewportInput : RefCounted
{
    private readonly ModelPrimitives _primitives = new();
    private static ModelViewportTransforms Transforms(Control c) => c.Get("_transforms_native").As<ModelViewportTransforms>();
    private static ModelViewportPicking Picking(Control c) => c.Get("_picking_native").As<ModelViewportPicking>();
    private static ModelViewportNavigation Navigation(Control c) => c.Get("_navigation_native").As<ModelViewportNavigation>();
    private static bool Flag(Control c, string name) => c.Get(name).AsBool();
    private static string Text(Control c, string name) => c.Get(name).AsString();
    public void start_creation(Control canvas, string kind) { canvas.Set("_create", kind); canvas.Set("_create_phase", 0); canvas.Set("sculpt", ""); canvas.GrabFocus(); }
    public bool creation_input(Control canvas, InputEvent input)
    {
        string kind = Text(canvas, "_create"); if (kind.Length == 0) return false;
        var session = canvas.Get("session").As<RefCounted>(); int phase = canvas.Get("_create_phase").AsInt32();
        if (input is InputEventKey { Pressed: true, Keycode: Key.Escape })
        { if (phase > 0) session.Call("cancel"); canvas.Set("_create", ""); canvas.Set("_create_phase", 0); canvas.EmitSignal("gesture_finished"); return true; }
        if (input is InputEventMouseButton mouse && mouse.ButtonIndex == MouseButton.Left)
        {
            if (mouse.Pressed && phase == 0)
            {
                session.Call("begin"); canvas.Set("_start", mouse.Position); canvas.Set("_create_origin", Transforms(canvas).screen_plane(canvas, mouse.Position, Vector3.Zero, Vector3.Up));
                var item = new KiwiModelComponent(); string id = Guid.NewGuid().ToString("N"); item.Set("id", id); item.Set("title", kind); item.Set("generator", kind); item.Set("mesh", _primitives.create(kind, new())); canvas.Set("_create_component", item);
                session.Get("document").As<Resource>().Get("components").AsGodotArray().Add(item); var selected = session.Get("selected").AsGodotArray<string>(); selected.Clear(); selected.Add(id); canvas.Set("_create_phase", 1);
            }
            else if (!mouse.Pressed && phase == 1) { canvas.Set("_create_phase", 2); canvas.Set("_start", mouse.Position); }
            else if (mouse.Pressed && phase == 2) { session.Call("commit", "Draw " + kind); canvas.Set("_create", ""); canvas.Set("_create_phase", 0); canvas.EmitSignal("gesture_finished"); }
            return true;
        }
        if (input is InputEventMouseMotion motion && phase > 0)
        {
            var item = canvas.Get("_create_component").As<Resource>(); var parameters = item.Get("parameters").AsGodotDictionary().Duplicate(); float height = Mathf.Max(.05f, Mathf.Abs((canvas.Get("_start").AsVector2().Y - motion.Position.Y) * .02f)); Transform3D transform = item.Get("transform").AsTransform3D();
            if (phase == 1) { Vector3 end = Transforms(canvas).screen_plane(canvas, motion.Position, Vector3.Zero, Vector3.Up), origin = canvas.Get("_create_origin").AsVector3(), size = (end - origin).Abs().Max(new Vector3(.05f, .05f, .05f)); size.Y = 1; parameters = new Settings { ["size"] = size, ["radius"] = Mathf.Max(size.X, size.Z) * .5f, ["height"] = 1f }; transform.Origin = (origin + end) * .5f + Vector3.Up * .5f; }
            else { parameters["height"] = height; Vector3 dimensions = parameters.TryGetValue("size", out var found) ? found.AsVector3() : Vector3.One; dimensions.Y = height; parameters["size"] = dimensions; transform.Origin.Y = height * .5f; }
            item.Set("transform", transform); item.Set("parameters", parameters); item.Set("mesh", _primitives.create(kind, parameters)); session.EmitSignal("changed");
        }
        return true;
    }
    public void handle(Control canvas, InputEvent input)
    {
        var overlay = canvas.Get("overlay").As<Control>(); var session = canvas.Get("session").As<RefCounted>(); var camera = canvas.Get("camera").As<Camera3D>(); var transforms = Transforms(canvas); var picking = Picking(canvas); var navigation = Navigation(canvas);
        bool navigating = Flag(canvas, "_navigating"), panning = Flag(canvas, "_panning"), orbiting = Flag(canvas, "_orbiting");
        if (!navigating && !panning && !orbiting && canvas.Get("groom_tool").As<RefCounted>().Call("handle", input).AsBool()) { overlay.QueueRedraw(); canvas.AcceptEvent(); return; }
        var rig = canvas.Get("rig_tool").As<RefCounted>(); if (rig != null && !navigating && !panning && !orbiting && rig.Call("handle_event", input).AsBool()) { overlay.QueueRedraw(); canvas.AcceptEvent(); return; }
        if (input is InputEventMouseMotion motion)
        {
            Vector2 previous = canvas.Get("_mouse").AsVector2(); canvas.Set("_mouse", motion.Position);
            if (navigating || orbiting) { canvas.Set("yaw", canvas.Get("yaw").AsSingle() - motion.Relative.X * .006f); canvas.Set("pitch", Mathf.Clamp(canvas.Get("pitch").AsSingle() - motion.Relative.Y * .006f, -Mathf.Pi * .495f, Mathf.Pi * .495f)); navigation.update_camera(canvas); }
            else if (panning) { canvas.Set("target", canvas.Get("target").AsVector3() + (-camera.Basis.X * motion.Relative.X + camera.Basis.Y * motion.Relative.Y) * canvas.Get("distance").AsSingle() * .0015f); navigation.update_camera(canvas); }
            else if (creation_input(canvas, input)) { }
            else if (Flag(canvas, "_extruding")) transforms.update_extrusion(canvas, motion.Position, motion.CtrlPressed);
            else if (Flag(canvas, "_drag")) transforms.update_transform(canvas, motion.Position, motion.CtrlPressed);
            else if (Flag(canvas, "_pressed") && Text(canvas, "sculpt").Length > 0) transforms.sculpt_at(canvas, motion.Position, previous, motion.CtrlPressed);
            else if (Flag(canvas, "_pressed") && motion.Position.DistanceTo(canvas.Get("_start").AsVector2()) > 5) canvas.Set("_box", true);
            overlay.QueueRedraw(); canvas.AcceptEvent(); return;
        }
        if (input is InputEventMouseButton mouse)
        {
            canvas.GrabFocus();
            if (mouse.ButtonIndex == MouseButton.Right) { if (Flag(canvas, "_extruding")) transforms.finish_extrusion(canvas, true); else if (Flag(canvas, "_drag")) transforms.finish_transform(canvas, true); else canvas.Set("_navigating", mouse.Pressed); canvas.AcceptEvent(); return; }
            if (mouse.ButtonIndex == MouseButton.Middle) { canvas.Set("_panning", mouse.Pressed && mouse.ShiftPressed); canvas.Set("_orbiting", mouse.Pressed && !mouse.ShiftPressed); canvas.AcceptEvent(); return; }
            if ((mouse.ButtonIndex == MouseButton.WheelUp || mouse.ButtonIndex == MouseButton.WheelDown) && mouse.Pressed)
            {
                float factor = mouse.ButtonIndex == MouseButton.WheelDown ? 1.12f : 1 / 1.12f;
                if (navigating) canvas.Set("fly_speed", Mathf.Clamp(canvas.Get("fly_speed").AsSingle() / factor, .1f, 100));
                else if (mouse.ShiftPressed && (Text(canvas, "sculpt").Length > 0 || Flag(canvas, "proportional"))) canvas.Set("radius", Mathf.Clamp(canvas.Get("radius").AsSingle() / factor, .02f, 100));
                else { canvas.Set("distance", Mathf.Clamp(canvas.Get("distance").AsSingle() * factor, .1f, 1000)); camera.Size = Mathf.Clamp(camera.Size * factor, .05f, 1000); navigation.update_camera(canvas); }
                canvas.AcceptEvent(); return;
            }
            if (creation_input(canvas, input)) { canvas.AcceptEvent(); return; } if (mouse.ButtonIndex != MouseButton.Left) return;
            if (mouse.Pressed)
            {
                Vector2 compass = new(canvas.Size.X - 42, 38); var directions = new[] { Vector3.Right, Vector3.Up, Vector3.Back };
                for (int i = 0; i < 3; i++) { Vector3 direction = camera.Basis.Inverse() * directions[i]; if (mouse.Position.DistanceTo(compass + new Vector2(direction.X, -direction.Y) * 22) < 9) { navigation.set_view(canvas, (mouse.ShiftPressed ? new[] { "Left", "Bottom", "Back" } : new[] { "Right", "Top", "Front" })[i]); canvas.AcceptEvent(); return; } }
                if (Flag(canvas, "_modal")) { transforms.finish_transform(canvas, false); canvas.AcceptEvent(); return; }
                canvas.Set("_start", mouse.Position); canvas.Set("_mouse", mouse.Position);
                if ((Flag(canvas, "push_pull") || mouse.AltPressed) && session.Get("mode").AsString() == "Face") transforms.begin_extrusion(canvas, mouse.Position);
                else if (Text(canvas, "sculpt").Length > 0) { session.Call("begin"); canvas.Set("_pressed", true); transforms.sculpt_at(canvas, mouse.Position, mouse.Position, mouse.CtrlPressed); }
                else { int handle = !mouse.ShiftPressed && !mouse.CtrlPressed ? picking.handle_at(canvas, mouse.Position, canvas.Call("geometry").AsGodotDictionary()) : -2; if (handle != -2) transforms.begin_transform(canvas, handle, mouse.Position, false); else canvas.Set("_pressed", true); }
            }
            else
            {
                if (Flag(canvas, "_extruding")) transforms.finish_extrusion(canvas, false);
                else if (Flag(canvas, "_drag")) transforms.finish_transform(canvas, false);
                else if (Flag(canvas, "_pressed") && Text(canvas, "sculpt").Length > 0) { session.Call("commit", Text(canvas, "sculpt") + " deformation"); canvas.EmitSignal("gesture_finished"); }
                else if (Flag(canvas, "_box")) picking.box_select(canvas, new Rect2(canvas.Get("_start").AsVector2(), mouse.Position - canvas.Get("_start").AsVector2()).Abs(), mouse.ShiftPressed || mouse.CtrlPressed);
                else if (Flag(canvas, "_pressed")) picking.select_at(canvas, mouse.Position, mouse.ShiftPressed || mouse.CtrlPressed);
                canvas.Set("_pressed", false); canvas.Set("_box", false);
            }
            canvas.AcceptEvent(); return;
        }
        if (input is not InputEventKey key || !key.Pressed || key.Echo || navigating) return;
        if (creation_input(canvas, input)) { canvas.AcceptEvent(); return; }
        if (Flag(canvas, "_extruding") || Flag(canvas, "_drag"))
        {
            bool extrusion = Flag(canvas, "_extruding"); string field = extrusion ? "_extrude_numeric" : "_numeric";
            if (key.Keycode == Key.Escape) { if (extrusion) transforms.finish_extrusion(canvas, true); else transforms.finish_transform(canvas, true); }
            else if (key.Keycode == Key.Enter) { if (extrusion) transforms.finish_extrusion(canvas, false); else transforms.finish_transform(canvas, false); }
            else if (!extrusion && (key.Keycode == Key.X || key.Keycode == Key.Y || key.Keycode == Key.Z)) { canvas.Set("_axis", key.Keycode == Key.X ? 0 : key.Keycode == Key.Y ? 1 : 2); canvas.Set("_plane", key.ShiftPressed); }
            else if (key.Keycode == Key.Backspace) { string value = Text(canvas, field); canvas.Set(field, value.Length > 0 ? value[..^1] : ""); }
            else if (key.Unicode >= 32 && key.Unicode <= 127 && "0123456789.-".Contains((char)key.Unicode)) canvas.Set(field, Text(canvas, field) + (char)key.Unicode);
            if (extrusion) { if (Flag(canvas, "_extruding")) transforms.update_extrusion(canvas, canvas.Get("_mouse").AsVector2(), key.CtrlPressed); } else transforms.update_transform(canvas, canvas.Get("_mouse").AsVector2(), key.CtrlPressed);
            canvas.AcceptEvent(); return;
        }
        if (key.CtrlPressed)
        {
            if (key.Keycode == Key.Z) session.Call(key.ShiftPressed ? "redo" : "undo"); else if (key.Keycode == Key.Y) session.Call("redo");
            else if (key.Keycode == Key.D) { session.Call("duplicate_selected", true); canvas.Set("tool", "Move"); if (!transforms.begin_transform(canvas, -1, canvas.Get("_mouse").AsVector2(), true)) session.Call("cancel"); }
            else if (key.Keycode == Key.A) canvas.EmitSignal("command_requested", "Select all"); else if (key.Keycode == Key.I) canvas.EmitSignal("command_requested", "Invert selection"); else return;
        }
        else if (key.Keycode >= Key.Key1 && key.Keycode <= Key.Key4) { session.Set("mode", new[] { "Object", "Vertex", "Edge", "Face" }[(int)(key.Keycode - Key.Key1)]); session.Set("elements", Array.Empty<int>()); session.EmitSignal("changed"); }
        else if (key.Keycode == Key.W || key.Keycode == Key.E || key.Keycode == Key.R) { canvas.Set("tool", key.Keycode == Key.W ? "Move" : key.Keycode == Key.E ? "Rotate" : "Scale"); canvas.Set("sculpt", ""); overlay.QueueRedraw(); canvas.EmitSignal("gesture_finished"); }
        else if (key.Keycode == Key.G || key.Keycode == Key.S) { canvas.Set("tool", key.Keycode == Key.G ? "Move" : "Scale"); transforms.begin_transform(canvas, -1, canvas.Get("_mouse").AsVector2(), true); }
        else if (key.Keycode == Key.F) canvas.Call("frame", key.ShiftPressed);
        else if (key.Keycode == Key.Tab) { session.Set("mode", session.Get("mode").AsString() == "Object" ? "Face" : "Object"); session.Set("elements", Array.Empty<int>()); session.EmitSignal("changed"); }
        else if (key.Keycode == Key.Delete || key.Keycode == Key.Backspace) canvas.EmitSignal("notice", session.Call("delete_selected"));
        else if (key.Keycode == Key.Space) canvas.EmitSignal("command_requested", "Search");
        else if (key.Keycode == Key.Escape) { canvas.Set("sculpt", ""); session.Call("cancel"); overlay.QueueRedraw(); }
        else return;
        canvas.AcceptEvent();
    }
}
