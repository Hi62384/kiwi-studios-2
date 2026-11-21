using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class NaturalMaterialCatalog : RefCounted
{
    public const int Version = 2;
    [ThreadStatic] private static Settings? _categories;
    [ThreadStatic] private static Settings? _structure;
    public static int version() => Version;
    public static Settings categories() => _categories ??= BuildCategories();
    public static Settings structure() => _structure ??= BuildStructure();
    private static Settings BuildCategories()
    {
        var result = new Settings();
        {
            var values = new GArray { "Brushed Steel", "Stainless Steel", "Polished Metal", "Rough Iron", "Cast Iron", "Aluminum", "Copper", "Bronze", "Gold", "Silver", "Galvanized Steel", "Rusted Metal", "Scratched Metal", "Hammered Metal", "Diamond Plate Metal" };
            values.MakeReadOnly();
            result["Metal"] = values;
        }
        {
            var values = new GArray { "Oak", "Pine", "Walnut", "Mahogany", "Birch", "Bamboo", "Plywood", "Tree Bark", "Weathered Wood", "Painted Wood", "Wood Planks", "Knotty Wood", "Rough Timber", "Dark Aged Wood" };
            values.MakeReadOnly();
            result["Wood"] = values;
        }
        {
            var values = new GArray { "Cotton", "Denim", "Linen", "Wool", "Silk", "Velvet", "Leather", "Suede", "Burlap", "Knitted Fabric", "Woven Fabric", "Canvas Fabric", "Corduroy", "Fleece", "Mesh Fabric" };
            values.MakeReadOnly();
            result["Fabric"] = values;
        }
        {
            var values = new GArray { "Granite", "Marble", "Limestone", "Sandstone", "Slate", "Concrete", "Rough Concrete", "Brick", "Stone Bricks", "Cobblestone", "Asphalt", "Cracked Stone", "Polished Stone", "Pebbled Stone", "Ceramic Tiles" };
            values.MakeReadOnly();
            result["Stone"] = values;
        }
        {
            var values = new GArray { "Grass", "Moss", "Dirt", "Mud", "Cracked Mud", "Sand", "Gravel", "Pebbles", "Snow", "Ice", "Rock Ground", "Forest Floor", "Dry Earth", "Wet Soil", "Fallen Leaves", "Organic Debris" };
            values.MakeReadOnly();
            result["Ground"] = values;
        }
        {
            var values = new GArray { "Skin Pores", "Reptile Scales", "Fish Scales", "Fur", "Feather Pattern", "Leaf Surface", "Leaf Veins", "Tree Bark", "Bone", "Shell", "Organic Membrane" };
            values.MakeReadOnly();
            result["Organic"] = values;
        }
        {
            var values = new GArray { "Rust", "Dust", "Dirt Buildup", "Scratches", "Cracks", "Peeling Paint", "Paint Chips", "Water Stains", "Oil Stains", "Grime", "Corrosion", "Surface Erosion", "Burn Marks", "Mold", "Surface Pitting" };
            values.MakeReadOnly();
            result["Weathering"] = values;
        }
        {
            var values = new GArray { "Comic Halftone", "Dots", "Stippling", "Crosshatching", "Hatching", "Pencil Grain", "Ink Grain", "Scribble Texture", "Hand-Drawn Shading", "Paper Grain", "Cartoon Speckles", "Watercolor Granulation", "Chalk Texture", "Marker Texture" };
            values.MakeReadOnly();
            result["Illustration"] = values;
        }
        {
            var values = new GArray { "Stripes", "Checkerboard", "Dots", "Grid", "Hexagons", "Triangles", "Diamonds", "Waves", "Zigzags", "Repeating Circles", "Brick Pattern", "Tiles", "Honeycomb", "Cross Pattern" };
            values.MakeReadOnly();
            result["Geometry"] = values;
        }
        {
            var values = new GArray { "White Noise", "Value Noise", "Smooth Noise", "Perlin Noise", "Simplex Noise", "Cellular Noise", "Voronoi Noise", "Fractal Brownian Motion", "Ridged Noise", "Billow Noise", "Turbulence", "Domain Warped Noise", "Worley Distance Noise", "Multiscale Grain" };
            values.MakeReadOnly();
            result["Noise"] = values;
        }
        result.MakeReadOnly();
        return result;
    }
    private static Settings BuildStructure()
    {
        var result = new Settings();
        {
            var values = new GArray { "density", "roughness", "distortion", "detail" };
            values.MakeReadOnly();
            result["Metal"] = values;
        }
        {
            var values = new GArray { "density", "knots", "distortion", "detail" };
            values.MakeReadOnly();
            result["Wood"] = values;
        }
        {
            var values = new GArray { "density", "thickness", "distortion", "detail" };
            values.MakeReadOnly();
            result["Fabric"] = values;
        }
        {
            var values = new GArray { "density", "thickness", "distortion", "detail" };
            values.MakeReadOnly();
            result["Stone"] = values;
        }
        {
            var values = new GArray { "density", "roughness", "distortion", "detail" };
            values.MakeReadOnly();
            result["Ground"] = values;
        }
        {
            var values = new GArray { "density", "thickness", "distortion", "detail" };
            values.MakeReadOnly();
            result["Organic"] = values;
        }
        {
            var values = new GArray { "density", "thickness", "distortion", "detail" };
            values.MakeReadOnly();
            result["Weathering"] = values;
        }
        {
            var values = new GArray { "density", "thickness", "distortion", "detail" };
            values.MakeReadOnly();
            result["Illustration"] = values;
        }
        {
            var values = new GArray { "density", "thickness", "distortion", "detail" };
            values.MakeReadOnly();
            result["Geometry"] = values;
        }
        {
            var values = new GArray { "frequency", "octaves", "gain", "lacunarity" };
            values.MakeReadOnly();
            result["Noise"] = values;
        }
        result.MakeReadOnly();
        return result;
    }
    public static string slug(string value) => new NaturalMaterialDefinitionOperations().slug(value);
    public static GArray controls(string id) => new NaturalMaterialDefinitionOperations().controls(id);
    public static string control_label(string id, string key) => new NaturalMaterialDefinitionOperations().control_label(id, key);
    public static Godot.Collections.Array<Settings> schema(string id)
    {
        var result = new Godot.Collections.Array<Settings>();
        foreach (var value in new NaturalMaterialDefinitionOperations().schema(id)) result.Add(value.AsGodotDictionary());
        return result;
    }
    public static Settings definition(string id) => new NaturalMaterialDefinitionOperations().definition(id);
    public static Godot.Collections.Array<string> ids()
    {
        var result = new Godot.Collections.Array<string>();
        foreach (var value in new NaturalMaterialDefinitionOperations().ids()) result.Add(value.AsString());
        return result;
    }
    public static string category(string id) => new NaturalMaterialDefinitionOperations().category(id);
    public static int variant(string id) => new NaturalMaterialDefinitionOperations().variant(id);
    public static KiwiTextureMaterial create(string id) => (KiwiTextureMaterial)new NaturalMaterialDefinitionOperations().create(id);
}
