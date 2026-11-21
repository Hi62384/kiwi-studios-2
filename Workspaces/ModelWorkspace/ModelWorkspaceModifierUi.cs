using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;

public partial class ModelWorkspaceOperations
{
    private readonly ModelModifiers _modifierEngine = new();
    private static Button AddButton(Node parent, string text, Action action)
    { var button = new Button { Text = text, CustomMinimumSize = new Vector2(0, 28) }; parent.AddChild(button); button.Pressed += action; return button; }
    private static Resource? Item(Control workspace, string id) => Session(workspace).Get("document").As<Resource>().Call("component", id).As<Resource>();
    public void build_modifiers(Control workspace, Resource item)
    {
        var parent = workspace.Get("_modifiers").As<Node>(); if (item.Get("mesh").As<Resource>() == null) { workspace.Call("_label", parent, "Select a mesh component"); return; }
        if (item.Get("skin_mesh").As<Mesh>() != null || item.Get("binding").As<Resource>() != null) { workspace.Call("_label", parent, "Rigged geometry is preserved.\nDetach before changing modifiers."); return; } string id = item.Get("id").AsString();
        void Edit(string label, int index, Action<Resource, Godot.Collections.Array<Settings>> write)
        { var session = Session(workspace); var current = Item(workspace, id); if (current == null) return; var list = current.Get("modifiers").AsGodotArray<Settings>(); if (index >= list.Count) return; Action(session, label, () => write(current, list)); }
        AddButton(parent, "＋ Add modifier", () => Choice(workspace, "MODIFIERS", Choices(workspace.Call("_command_choices").AsGodotDictionary(), "modifiers"), kind => Edit("Add " + kind, -1, (_, list) => list.Add(new Settings { ["type"] = kind, ["enabled"] = true, ["amount"] = new[] { "Bevel", "Solidify", "Smooth" }.Contains(kind) ? .1 : 1.0, ["axis"] = 0, ["count"] = 3 }))));
        var modifiers = item.Get("modifiers").AsGodotArray<Settings>();
        for (int i = 0; i < modifiers.Count; i++)
        {
            int index = i; var settings = modifiers[i]; string type = settings["type"].AsString(); var row = new HBoxContainer(); parent.AddChild(row); var toggle = new CheckButton { Text = type, ButtonPressed = !settings.TryGetValue("enabled", out var enabled) || enabled.AsBool(), SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }; row.AddChild(toggle); toggle.Toggled += next => Edit("Enable modifier", index, (_, list) => list[index]["enabled"] = next);
            AddButton(row, "↑", () => { if (index > 0) Edit("Reorder modifiers", index, (_, list) => { var entry = list[index]; list.RemoveAt(index); list.Insert(index - 1, entry); }); }); AddButton(row, "×", () => Edit("Remove modifier", index, (_, list) => list.RemoveAt(index)));
            if (new[] { "Mirror", "Linear array", "Radial array", "Twist", "Taper" }.Contains(type)) { var axis = new OptionButton(); foreach (string name in new[] { "X axis", "Y axis", "Z axis" }) axis.AddItem(name); axis.Select(settings.TryGetValue("axis", out var selected) ? selected.AsInt32() : 0); parent.AddChild(axis); axis.ItemSelected += next => Edit("Modifier axis", index, (_, list) => list[index]["axis"] = next); }
            if (type == "Mirror") { var bisect = new CheckButton { Text = "Keep half + mirror", ButtonPressed = !settings.TryGetValue("bisect", out var half) || half.AsBool(), TooltipText = "Edit the retained half; Apply the modifier to edit the full result." }; parent.AddChild(bisect); bisect.Toggled += next => Edit("Mirror bisection", index, (_, list) => list[index]["bisect"] = next); }
            if (type != "Mirror" && type != "Subdivision") Number(workspace, parent, type == "Bevel" ? "Width" : "Amount", settings.TryGetValue("amount", out var amount) ? amount.AsDouble() : 1, type == "Bevel" || type == "Smooth" ? .0001 : -360, type == "Smooth" ? 1 : 360, .01, next => { var current = Item(workspace, id); if (current == null) return; var list = current.Get("modifiers").AsGodotArray<Settings>(); if (index < list.Count) list[index]["amount"] = next; });
            if (new[] { "Linear array", "Radial array", "Subdivision", "Smooth" }.Contains(type)) Number(workspace, parent, "Count", settings.TryGetValue("count", out var count) ? count.AsInt32() : 3, 1, type == "Subdivision" ? 3 : type == "Smooth" ? 8 : 64, 1, next => { var current = Item(workspace, id); if (current == null) return; var list = current.Get("modifiers").AsGodotArray<Settings>(); if (index < list.Count) list[index]["count"] = (int)next; });
            AddButton(parent, "Apply through here", () => Edit("Apply modifier", index, (current, list) => { for (int j = 0; j <= index; j++) if (!list[j].TryGetValue("enabled", out var active) || active.AsBool()) current.Set("mesh", _modifierEngine.apply(current.Get("mesh").As<Resource>(), list[j])); for (int j = 0; j <= index; j++) list.RemoveAt(0); current.Set("generator", ""); }));
        }
    }
    public void build_surfaces(Control workspace, Resource item)
    {
        var mesh = item.Get("mesh").As<Resource>(); if (mesh == null) return; var parent = workspace.Get("_surfaces").As<Node>(); string id = item.Get("id").AsString();
        void Edit(string label, Action<Resource> write) { var current = Item(workspace, id); if (current != null) Action(Session(workspace), label, () => write(current)); }
        var shading = new CheckButton { Text = "Smooth normals", ButtonPressed = mesh.Get("smooth").AsBool() }; parent.AddChild(shading); shading.Toggled += next => Edit("Shading", current => current.Get("mesh").As<Resource>().Set("smooth", next));
        AddButton(parent, "＋ Material", () => Edit("Add material", current => current.Get("surface_materials").AsGodotArray<Material>().Add(new StandardMaterial3D { AlbedoColor = new Color("91bfc8"), Roughness = .55f })));
        var materials = item.Get("surface_materials").AsGodotArray<Material>();
        for (int i = 0; i < materials.Count; i++)
        {
            int slot = i; var row = new HBoxContainer(); parent.AddChild(row); workspace.Call("_label", row, "Material " + (i + 1)); var material = materials[i] as BaseMaterial3D; var color = new ColorPickerButton { CustomMinimumSize = new Vector2(50, 26), Color = material?.AlbedoColor ?? Colors.White, Disabled = material == null, TooltipText = material != null ? "Albedo tint" : "Shader material — edit its shader parameters in the shader workspace" }; row.AddChild(color); var session = Session(workspace); bool began = false, closed = false;
            bool Current() => !closed && GodotObject.IsInstanceValid(workspace) && workspace.IsInsideTree() && Session(workspace) == session;
            color.Pressed += () => { if (!Current()) return; session.Call("begin"); began = true; workspace.Set("_property_gesture", true); };
            color.PopupClosed += () => { if (!Current()) return; began = false; workspace.Set("_property_gesture", false); session.Call("commit", "Material color"); };
            color.ColorChanged += next => { if (!Current()) return; var current = Item(workspace, id); if (current == null) return; var slots = current.Get("surface_materials").AsGodotArray<Material>(); if (slot >= slots.Count || slots[slot]?.Duplicate() is not BaseMaterial3D copy) return; copy.AlbedoColor = next; slots[slot] = copy; session.EmitSignal("changed"); };
            color.TreeExiting += () => { if (began) { session.Call("cancel"); if (Current()) workspace.Set("_property_gesture", false); } closed = true; };
            AddButton(row, "Assign", () => Edit("Assign material", current => { var source = current.Get("mesh").As<Resource>(); int[] slots = source.Get("materials").AsInt32Array(); var selected = new HashSet<int>(Session(workspace).Get("elements").AsInt32Array()); bool faces = Session(workspace).Get("mode").AsString() == "Face"; for (int f = 0; f < slots.Length; f++) if (!faces || selected.Contains(f)) slots[f] = slot; source.Set("materials", slots); }));
        }
        AddButton(parent, "Load Material…", () => workspace.Call("_load_material"));
    }
}
