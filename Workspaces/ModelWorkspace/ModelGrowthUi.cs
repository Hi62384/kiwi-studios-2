using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class ModelWorkspaceOperations
{
    private readonly SurfaceGrowthGeometry _growth = new();
    private readonly SurfaceGrowthSettings _growthSettings = new();
    private readonly GrowthMaterialOperations _growthMaterials = new();
    private readonly Dictionary<string, Texture2D> _growthIcons = new();
    private static readonly Dictionary<string, string> GrowthPaths = new()
    {
        ["Hair"] = "M5 21C2 8 8 3 9 3M10 21C6 9 13 4 14 3M15 21C10 9 18 4 20 3",
        ["Fur"] = "M3 20L6 5 10 20 13 3 17 20 20 7 22 20",
        ["Feathers"] = "M4 21L17 4M7 18C-2 8 14 0 20 3 23 10 19 20 7 18M11 14L20 10M8 17L9 8",
        ["Comb"] = "M4 6H20M5 7V19M9 7V19M13 7V19M17 7V19M20 7V15",
        ["Brush"] = "M5 19L16 3 21 7 9 21ZM4 20L3 23",
        ["Cut"] = "M10 13L21 3M10 11L21 21M10 12L4 5M10 12L4 19M3 3a3 3 0 1 0 1 0M3 17a3 3 0 1 0 1 0",
        ["Grow"] = "M12 21V3M6 9L12 3 18 9M5 16H19",
        ["Curl"] = "M4 19C18 25 25 8 14 4 4 1 4 15 12 15 18 15 16 8 12 9",
        ["Clump"] = "M3 4Q11 6 12 20M8 3L12 20M21 4Q13 6 12 20M16 3L12 20",
        ["Density"] = "M4 4h1M10 4h1M16 4h1M22 4h1M4 10h1M10 10h1M16 10h1M4 16h1M10 16h1M4 22h1",
        ["Length"] = "M4 21V3M2 6L4 3 6 6M2 18L4 21 6 18M11 21V11M16 21V6M21 21V2",
        ["Smooth"] = "M2 14C7 3 17 23 22 10",
        ["Relax"] = "M3 5Q8 21 12 5M12 5L12 18M8 14L12 18 16 14",
        ["Part"] = "M12 2V22M10 7L3 12M14 7L21 12M10 13L3 18M14 13L21 18",
        ["Feather width"] = "M3 12H21M8 7L3 12 8 17M16 7L21 12 16 17",
        ["Spread"] = "M12 21L3 3M12 21V3M12 21L21 3",
        ["Protect"] = "M12 2L3 6V13Q5 19 12 22 19 19 21 13V6ZM8 12L11 15 17 8",
        ["Reset region"] = "M4 10A9 9 0 1 1 5 18M4 3V10H11",
        ["Guide"] = "M3 20C4 4 20 22 21 4M2 19h3v3H2ZM19 2h4v4H19Z",
        ["Color paint"] = "M4 20L16 3 21 8 9 22ZM3 15H8M14 17a4 4 0 1 0 8 0 4 4 0 1 0 -8 0",
        ["Select strands"] = "M3 2L6 19 10 13 17 12ZM14 3Q20 11 20 22M18 3Q24 11 24 22",
    };
    public Texture2D growth_icon(string title)
    {
        if (_growthIcons.TryGetValue(title, out var found)) return found;
        string path = GrowthPaths.GetValueOrDefault(title, GrowthPaths["Hair"]);
        using var image = new Image(); image.LoadSvgFromString("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\"><path d=\"" + path + "\" fill=\"none\" stroke=\"#8be4cc\" stroke-width=\"1.65\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/></svg>");
        var texture = ImageTexture.CreateFromImage(image); _growthIcons[title] = texture; return texture;
    }
    private static Settings GrowthDict(GodotObject owner, string name) => owner.Get(name).AsGodotDictionary();
    private static Variant GrowthValue(Settings values, Variant key, Variant fallback = default) => values.TryGetValue(key, out var value) ? value : fallback;
    private static Control GrowthCanvas(Control workspace) => workspace.Get("canvas").As<Control>();
    private static RefCounted GroomTool(Control workspace) => GrowthCanvas(workspace).Get("groom_tool").As<RefCounted>();
    private static void GrowthChanged(Resource data) { data.Set("revision", data.Get("revision").AsInt64() + 1); data.Set("render_cache", default(Variant)); }
    public void growth_add_menu(Control workspace)
    {
        var menu = new PopupMenu(); workspace.AddChild(menu);
        foreach (string title in new[] { "Hair", "Fur", "Feathers" }) menu.AddIconItem(growth_icon(title), "Generate " + title);
        menu.AddSeparator(); menu.AddIconItem(growth_icon("Fur"), "Generate layered fur coat", 3);
        menu.IdPressed += kind => { string error = kind == 3 ? _growth.add_layered_fur(Session(workspace)) : _growth.add(Session(workspace), (int)kind); if (error.Length > 0) GrowthCanvas(workspace).EmitSignal("notice", error); };
        menu.Position = (Vector2I)workspace.GetGlobalMousePosition(); menu.Popup(); menu.PopupHide += menu.QueueFree;
    }
    public void growth_choice(Control workspace, Node parent, Resource data, string key, string title, GArray choices)
    {
        Label(parent, title); var input = new OptionButton { FitToLongestItem = false }; parent.AddChild(input); foreach (var text in choices) input.AddItem(text.AsString());
        input.Select(Math.Clamp(GrowthValue(GrowthDict(data, "settings"), key, 0).AsInt32(), 0, choices.Count - 1)); var session = Session(workspace);
        input.ItemSelected += index => Action(session, "Growth " + title, () => { GrowthDict(data, "settings")[key] = index; GrowthChanged(data); });
    }
}
