using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class ModelWorkspaceOperations
{
    private static readonly string[] GrowthTools = { "Brush", "Comb", "Cut", "Grow", "Curl", "Clump", "Density", "Length", "Smooth", "Relax", "Part", "Feather width", "Spread", "Protect", "Reset region", "Guide", "Color paint", "Select strands" };
    private void GrowthChoice(Control workspace, Node parent, Resource data, string key, string title, params string[] choices) => growth_choice(workspace, parent, data, key, title, new GArray(choices.Select(text => Variant.From(text))));
    public void growth_build(Control workspace, Resource item, VBoxContainer parent)
    {
        var data = item.Get("growth").As<Resource>(); var settings = GrowthDict(data, "settings"); var session = Session(workspace); var tool = GroomTool(workspace);
        Label(parent, "SURFACE GROWTH · " + new[] { "Hair", "Fur", "Feathers" }[GrowthValue(settings, "type", 0).AsInt32()]);
        var source = new OptionButton { FitToLongestItem = false, Name = "GrowthSource" }; parent.AddChild(source);
        foreach (var value in session.Get("document").As<Resource>().Get("components").AsGodotArray())
        {
            var candidate = value.As<Resource>(); if (candidate.Get("mesh").As<Resource>() == null || candidate.Get("growth").As<Resource>() != null) continue;
            source.AddItem(candidate.Get("title").AsString()); source.SetItemMetadata(source.ItemCount - 1, candidate.Get("id")); if (candidate.Get("id").AsString() == data.Get("source_id").AsString()) source.Select(source.ItemCount - 1);
        }
        source.ItemSelected += index => Action(session, "Change growth source", () => { data.Set("source_id", source.GetItemMetadata((int)index).AsString()); item.Set("parent_id", data.Get("source_id")); item.Set("transform", Transform3D.Identity); data.Set("topology", 0); data.Set("generation_key", 0); GrowthDict(data, "groom").Clear(); data.Get("groom_layers").AsGodotArray().Clear(); GrowthDict(data, "guides").Clear(); });
        var groom = new CheckButton { Name = "GrowthGroomMode", Text = "Groom in viewport", ButtonPressed = tool.Get("enabled").AsBool() }; parent.AddChild(groom);
        groom.Toggled += next => { tool.Set("enabled", next); GrowthCanvas(workspace).Get("rig_tool").As<RefCounted>().Get("editor").As<RefCounted>().Set("enabled", false); workspace.Set("_refresh_pending", true); };
        if (tool.Get("enabled").AsBool())
        {
            var choose = new OptionButton { Name = "GroomTool", FitToLongestItem = false }; parent.AddChild(choose); foreach (string title in GrowthTools) choose.AddIconItem(growth_icon(title), title);
            choose.Select(Array.IndexOf(GrowthTools, tool.Get("tool").AsString())); choose.ItemSelected += index => { tool.Set("tool", GrowthTools[index]); workspace.Set("_refresh_pending", true); };
            growth_build_presets(workspace, parent, data); string kind = tool.Get("tool").AsString(); if (kind == "Select strands") growth_build_individual(workspace, parent, data);
            void Brush(string field, string title, double minimum, double maximum, double step) => Number(workspace, parent, title, tool.Get(field).AsDouble(), minimum, maximum, step, next => tool.Set(field, next));
            Brush("radius", "Radius (world)", .005, 100, .01); Brush("strength", "Strength", 0, 1, .01); Brush("falloff", "Falloff", 0, 1, .01);
            if (new[] { "Cut", "Grow", "Length", "Density", "Clump", "Feather width", "Curl" }.Contains(kind)) Brush("value", "Target / amount", 0, 10, .01);
            if (kind == "Curl") Brush("frequency", "Curl frequency", .1, 20, .1);
            if (kind == "Clump") { Brush("clump_start", "Clump starts along strand", 0, .99, .01); Brush("clump_end", "Full clump along strand", .01, 1, .01); Brush("clump_variation", "Clump variation", 0, 1, .01); }
            if (kind == "Cut") AddButton(parent, "Cut at local height", () => Action(session, "Cut groom with plane", () => _growth.cut_plane(data, new Plane(Vector3.Up, tool.Get("value").AsSingle()))));
            if (kind == "Guide") growth_build_guides(workspace, parent, data);
            if (kind == "Color paint") { var paint = new ColorPickerButton { Color = tool.Get("paint_color").AsColor(), CustomMinimumSize = new Vector2(0, 24) }; parent.AddChild(paint); paint.ColorChanged += next => tool.Set("paint_color", next); }
            var symmetry = new OptionButton(); parent.AddChild(symmetry); foreach (string title in new[] { "No symmetry", "Mirror X", "Mirror Y", "Mirror Z" }) symmetry.AddItem(title); symmetry.Select(tool.Get("symmetry").AsInt32() + 1); symmetry.ItemSelected += index => tool.Set("symmetry", index - 1);
            var through = new CheckButton { Text = "Through surface", ButtonPressed = tool.Get("through").AsBool() }; parent.AddChild(through); through.Toggled += next => tool.Set("through", next);
            if (kind is "Density" or "Length" or "Cut") { string key = kind == "Cut" ? "target_cut" : "replace"; var replace = new CheckButton { Text = "Set target", ButtonPressed = tool.Get(key).AsBool() }; parent.AddChild(replace); replace.Toggled += next => tool.Set(key, next); }
        }
        else
        {
            foreach (var (key, title, minimum, maximum, step) in new[] { ("density", "Density / surface unit²", 0.0, 10000.0, .1), ("length", "Length", .001, 100.0, .01), ("thickness", "Thickness", .0001, 2.0, .001), ("seed", "Seed", 0.0, 1000000.0, 1.0), ("curvature", "Bend", -3.0, 3.0, .01), ("taper", "Taper", 0.0, 1.0, .01), ("variation", "Length variation", 0.0, 1.0, .01), ("orientation_variation", "Direction variation", 0.0, 1.0, .01), ("spacing", "Minimum root spacing", 0.0, 5.0, .01) })
                Number(workspace, parent, title, GrowthValue(settings, key, 0).AsDouble(), minimum, maximum, step, next => { settings[key] = key == "seed" ? Variant.From((long)next) : Variant.From(next); GrowthChanged(data); });
            GrowthChoice(workspace, parent, data, "quality", "Detail", "Fast", "Balanced", "Detailed", "Final Render");
            growth_styles(workspace, parent, data);
            GrowthChoice(workspace, parent, data, "direction_mode", "Direction", "Surface normal", "World direction", "Object-local direction", "Surface tangent");
            if (GrowthValue(settings, "direction_mode", 0).AsInt32() > 0)
            {
                for (int axis = 0; axis < 3; axis++) { int at = axis; Number(workspace, parent, "Direction " + "XYZ"[at], settings["direction"].AsVector3()[at], -1, 1, .01, next => { Vector3 direction = settings["direction"].AsVector3(); direction[at] = (float)next; settings["direction"] = direction; GrowthChanged(data); }); }
                Number(workspace, parent, "Direction blend", GrowthValue(settings, "direction_blend", .4).AsDouble(), 0, 1, .01, next => { settings["direction_blend"] = next; GrowthChanged(data); });
            }
            if (GrowthValue(settings, "type", 0).AsInt32() == 2)
            {
                GrowthChoice(workspace, parent, data, "feather_type", "Feathers", "Down", "Contour", "Flight"); GrowthChoice(workspace, parent, data, "arrangement", "Arrangement", "Area-random", "Ordered surface rows");
                Number(workspace, parent, "Vane width", GrowthValue(settings, "width", .14).AsDouble(), .001, 10, .01, next => { settings["width"] = next; GrowthChanged(data); });
                Number(workspace, parent, "Rows", GrowthValue(settings, "rows", 4).AsDouble(), 1, 32, 1, next => settings["rows"] = (long)next);
                Number(workspace, parent, "Overlap", GrowthValue(settings, "overlap", .3).AsDouble(), 0, .95, .01, next => { settings["overlap"] = next; GrowthChanged(data); });
            }
            else GrowthChoice(workspace, parent, data, "shape", "Strands", "Straight", "Curved", "Wavy", "Curly");
        }
        var actions = new HFlowContainer(); parent.AddChild(actions);
        AddButton(actions, "Regenerate", () => Action(session, "Regenerate growth", () => { if (!data.Get("source_valid").AsBool()) { data.Set("topology", 0); data.Set("faces", Array.Empty<int>()); GrowthDict(data, "groom").Clear(); data.Get("groom_layers").AsGodotArray().Clear(); GrowthDict(data, "guides").Clear(); } data.Set("generation_key", 0); GrowthChanged(data); }));
        AddButton(actions, "Clear face mask", () => Action(session, "Clear growth face mask", () => { data.Set("faces", Array.Empty<int>()); data.Set("generation_key", 0); }));
        AddButton(actions, "Convert to mesh", () => Action(session, "Make growth editable", () => { item.Set("mesh", new ModelMeshOperations().from_mesh(_growth.render(data, Array.Empty<Vector3>()))); item.Set("growth", default(Variant)); item.Set("skeleton_id", ""); }));
        growth_appearance(workspace, parent, data); growth_regions(workspace, parent, data);
        Label(parent, data.Get("roots").AsGodotArray().Count + " roots reserved · " + data.Get("faces").AsInt32Array().Length + " selected faces"); if (data.Get("error").AsString().Length > 0) Label(parent, data.Get("error").AsString());
        var enabled = new CheckButton { Text = "Groom adjustments", ButtonPressed = data.Get("groom_enabled").AsBool() }; parent.AddChild(enabled); enabled.Toggled += next => Action(session, "Toggle grooming", () => { data.Set("groom_enabled", next); GrowthChanged(data); });
        AddButton(parent, "Reset groom", () => Action(session, "Reset groom", () => { GrowthDict(data, "groom").Clear(); data.Get("groom_layers").AsGodotArray().Clear(); GrowthDict(data, "guides").Clear(); GrowthChanged(data); }));
        AddButton(parent, "Apply groom layers", () => Action(session, "Apply groom layers", () => { var roots = data.Get("roots").AsGodotArray(); if (roots.Count > 0) _growth.style(data, roots[0].AsGodotDictionary()); data.Set("groom", GrowthDict(data, "effective").Duplicate(true)); data.Get("groom_layers").AsGodotArray().Clear(); GrowthChanged(data); }));
        var layers = data.Get("groom_layers").AsGodotArray();
        for (int index = 0; index < layers.Count; index++)
        {
            int at = index; var layer = layers[at].AsGodotDictionary(); var row = new HBoxContainer(); parent.AddChild(row); var check = new CheckBox { Text = layer["tool"].AsString() + " · " + layer["changes"].AsGodotDictionary().Count, ButtonPressed = GrowthValue(layer, "enabled", true).AsBool(), SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }; row.AddChild(check); check.Toggled += next => Action(session, "Toggle grooming layer", () => { layers[at].AsGodotDictionary()["enabled"] = next; GrowthChanged(data); });
            foreach (int direction in new[] { -1, 1 }) { var move = AddButton(row, direction < 0 ? "↑" : "↓", () => Action(session, "Reorder groom", () => { var copy = layers[at]; layers.RemoveAt(at); layers.Insert(at + direction, copy); GrowthChanged(data); })); move.Disabled = at + direction < 0 || at + direction >= layers.Count; }
            AddButton(row, "×", () => Action(session, "Remove grooming layer", () => { layers.RemoveAt(at); GrowthChanged(data); }));
        }
        foreach (Node child in parent.GetChildren()) if (child is Label label) { label.AutowrapMode = TextServer.AutowrapMode.WordSmart; label.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill; }
    }
}
