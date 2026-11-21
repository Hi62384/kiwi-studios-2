using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

public partial class FileOperationsNative
{
    private static GDScript Bridge => GD.Load<GDScript>("res://scripts/Globals/file_operations.gd");
    private static Texture2D Icon(string name) => GD.Load<Texture2D>("res://resources/Images/ActorIcons/" + name + ".svg");
    private static Texture2D DefaultIcon => GD.Load<Texture2D>("uid://mwmlqweqemfk");
    public Godot.Collections.Array file_type_to_extension(int type)
    {
        var map = Bridge.GetScriptConstantMap()["_FILE_TYPE_TO_EXTENSION"].AsGodotDictionary();
        return map.TryGetValue(type, out var value) ? value.AsGodotArray() : new Godot.Collections.Array();
    }
    public int get_type_of_file(string path)
    {
        string extension = path.GetExtension().ToLowerInvariant();
        if (extension == "") return 0;
        if (extension is "tres" or "res")
        {
            var resource = ResourceLoader.Load(path);
            if (ActorDataOperations.ScriptIs(resource, "res://scripts/actors/core/actor_scene_data.gd")) return 10;
            if (ActorDataOperations.ScriptIs(resource, "res://scripts/actors/core/actor_object_data.gd"))
            {
                string type = resource!.Get("type_id").AsString();
                if (type == "environment") return 7;
                if (type is "image" or "noise_image") return 1;
            }
            return resource switch { Godot.Environment => 7, Mesh => 4, PackedScene => 3, AudioStream => 2, Texture2D => 1, StandardMaterial3D => 8, _ => 0 };
        }
        var map = Bridge.GetScriptConstantMap()["_FILE_TYPE_TO_EXTENSION"].AsGodotDictionary();
        foreach (var key in map.Keys) if (map[key].AsGodotArray().Contains(extension)) return key.AsInt32();
        return 0;
    }
    private static bool Is(Resource? resource, string path) => ActorDataOperations.ScriptIs(resource, path);
    private static Settings Texture(Texture2D? texture) => new() { ["texture"] = texture == null ? default(Variant) : Variant.From(texture) };
    private static Settings Render(string kind, Resource resource) => new() { ["render"] = kind, ["resource"] = resource };
    private static bool RendererAvailable
    {
        get
        {
            var value = GD.Load<GDScript>("res://scripts/Extra/thumbnail_renderer.gd").Get("_instance");
            return value.VariantType == Variant.Type.Object && GodotObject.IsInstanceValid(value.AsGodotObject());
        }
    }
    private static Texture2D ImageDocumentThumbnail(Texture2D preview)
    {
        using var result = Image.CreateEmpty(192, 144, false, Image.Format.Rgba8);
        result.Fill(Colors.Transparent);
        result.FillRect(new Rect2I(16, 4, 170, 126), new Color("385b62"));
        result.FillRect(new Rect2I(8, 10, 170, 126), new Color("508f89"));
        result.FillRect(new Rect2I(0, 18, 170, 126), new Color("152735"));
        using var image = (Image)preview.GetImage().Duplicate();
        if (image.IsEmpty()) return ImageTexture.CreateFromImage(result);
        float factor = Math.Min(158f / image.GetWidth(), 100f / image.GetHeight());
        image.Resize(Math.Max(1, Mathf.RoundToInt(image.GetWidth() * factor)), Math.Max(1, Mathf.RoundToInt(image.GetHeight() * factor)), Image.Interpolation.Lanczos);
        result.BlendRect(image, new Rect2I(Vector2I.Zero, image.GetSize()), new Vector2I(6 + (158 - image.GetWidth()) / 2, 24 + (100 - image.GetHeight()) / 2));
        for (int line = 0; line < 3; line++) result.FillRect(new Rect2I(10 + line * 5, 128 + line * 3, 18, 2), new Color("75e2c4"));
        return ImageTexture.CreateFromImage(result);
    }
    private static Texture2D EnvironmentDocumentThumbnail(Texture2D preview)
    {
        using var result = Image.CreateEmpty(192, 144, false, Image.Format.Rgba8);
        result.Fill(new Color("23594b"));
        using var image = (Image)preview.GetImage().Duplicate();
        if (!image.IsEmpty())
        {
            image.Convert(Image.Format.Rgba8); image.Resize(180, 116, Image.Interpolation.Lanczos);
            result.BlendRect(image, new Rect2I(Vector2I.Zero, image.GetSize()), new Vector2I(6, 6));
        }
        result.FillRect(new Rect2I(6, 128, 54, 4), new Color("7fe4c3"));
        result.FillRect(new Rect2I(66, 128, 24, 4), new Color("a8d5e5"));
        return ImageTexture.CreateFromImage(result);
    }
    private static Variant Value(Resource resource, string key, Variant fallback = default) => resource.Call("get_value", new StringName(key), fallback);
    private readonly ActorImageGeneratorOperations _images = new();
    private StandardMaterial3D PreviewMaterial(Resource resource)
    {
        var tint = Value(resource, "tint", Colors.White).AsColor();
        tint.A *= Value(resource, "opacity", 1.0).AsSingle();
        var result = new StandardMaterial3D
        {
            AlbedoColor = tint, Roughness = Value(resource, "roughness", 1.0).AsSingle(),
            Metallic = Value(resource, "metallic", 0.0).AsSingle(), MetallicSpecular = Value(resource, "specular", 0.5).AsSingle(),
            EmissionEnabled = Value(resource, "emission_enabled", false).AsBool(), Emission = Value(resource, "emission_color", Colors.Black).AsColor(),
            EmissionEnergyMultiplier = Value(resource, "emission_energy", 1.0).AsSingle()
        };
        var reference = Value(resource, "albedo_map");
        if (reference.VariantType == Variant.Type.Object && reference.AsGodotObject() is Resource slot)
        {
            Resource? image = null;
            if (slot.Get("source").AsInt32() == 1)
            {
                string path = slot.Get("asset_id").AsString();
                if (path != "") image = ResourceLoader.Load(path, "", ResourceLoader.CacheMode.Ignore);
            }
            else if (slot.Get("embedded").VariantType == Variant.Type.Object) image = slot.Get("embedded").As<Resource>();
            if (!ActorDataOperations.ScriptIs(image,"res://scripts/actors/core/actor_object_data.gd") || image!.Get("type_id").AsString() != slot.Get("object_type").AsString()) image = null;
            result.AlbedoTexture = _images.texture_for_object(image);
        }
        return result;
    }
    public Settings thumbnail_plan(string path)
    {
        if (!path_exists(path)) return Texture(null);
        string extension = path.GetExtension().ToLowerInvariant();
        if (extension == "gdshader") return Texture(Icon("Shader"));
        if (extension is "tres" or "res")
        {
            var resource = ResourceLoader.Load(path, "", ResourceLoader.CacheMode.Ignore);
            if (Is(resource, "res://Workspaces/ModelWorkspace/growth/growth_style.gd") || Is(resource, "res://Workspaces/ModelWorkspace/growth/growth_material.gd")) return Texture(resource!.Call("thumbnail").As<Texture2D>());
            if (Is(resource, "res://Workspaces/TransformationWorkspace/transformation_document.gd")) return Texture(resource!.Call("thumbnail").As<Texture2D>() ?? Icon("Transformation2D"));
            if (Is(resource, "res://Workspaces/EnvironmentWorkspace/environment_document.gd"))
            {
                var preview = resource!.Call("thumbnail").As<Texture2D>();
                return Texture(preview == null ? Icon("WorldEnvironment") : EnvironmentDocumentThumbnail(preview));
            }
            if (Is(resource, "res://Workspaces/ModelWorkspace/model_document.gd")) return Texture(resource!.Call("thumbnail").As<Texture2D>() ?? Icon("BasicMesh"));
            if (resource is RigPreset || Is(resource, "res://Workspaces/ModelWorkspace/rig/rig_preset.gd")) return Texture(Icon("SkeletonRig"));
            if (Is(resource, "res://Workspaces/ImageWorkspace/image_pattern_preset.gd")) return Texture(resource!.Get("texture").As<Texture2D>() ?? DefaultIcon);
            if (Is(resource, "res://Workspaces/ImageWorkspace/image_document.gd"))
            {
                var preview = resource!.Get("preview").As<Texture2D>();
                return Texture(preview == null ? Icon("Image2D") : ImageDocumentThumbnail(preview));
            }
            if (Is(resource, "res://scripts/actors/core/actor_scene_data.gd")) return Texture(Icon("Scene"));
            if (Is(resource, "res://scripts/actors/core/actor_object_data.gd"))
            {
                string type = resource!.Get("type_id").AsString();
                if (type == "text_settings") return RendererAvailable ? Render("text_settings", resource) : Texture(Icon("TextSettings"));
                if (type == "environment") return RendererAvailable ? Render("actor_environment", resource) : Texture(DefaultIcon);
                if (type is "image" or "noise_image") return Texture(_images.texture_for_object(resource));
                if (type == "material" && RendererAvailable) return Render("material", PreviewMaterial(resource));
            }
            if (resource is Godot.Environment) return RendererAvailable ? Render("environment", resource) : Texture(DefaultIcon);
            if (resource is Texture2D texture) return Texture(texture);
        }
        if (DirAccess.DirExistsAbsolute(path)) return Texture(GD.Load<Texture2D>("uid://h5xgw3ns54ys"));
        switch (get_type_of_file(path))
        {
            case 1: return Texture(load_image(path));
            case 2: return Texture(GD.Load<Texture2D>("uid://dcqki3r6v5dxo"));
            case 9: return new Settings { ["video"] = path };
            case 3: case 4: return Texture(GD.Load<Texture2D>("uid://bw47linn7yref"));
            case 7: case 8:
                if (RendererAvailable) return Render(get_type_of_file(path) == 7 ? "environment" : "material", ResourceLoader.Load(path));
                break;
        }
        return Texture(DefaultIcon);
    }
}
