using Godot;
using System;
using System.Linq;
using Settings = Godot.Collections.Dictionary;

public partial class EnvironmentSessionOperations
{
    private readonly ModelImport _import = new();
    private static Resource Component() => new KiwiModelComponent();
    private static Settings LoadParts(string path) => GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd").Call("load_parts", path).AsGodotDictionary();
    public string place_asset(RefCounted session, string path, Vector3 point, Vector3 normal, bool align)
    {
        var source = LoadParts(path); string error = source["error"].AsString(); if (error.Length > 0) return error; Aabb bounds = new(); bool first = true;
        foreach (var value in source["parts"].AsGodotArray())
        {
            var part = value.AsGodotDictionary(); Aabb box = part["mesh"].As<Mesh>().GetAabb(); var transform = part["transform"].AsTransform3D();
            for (int corner = 0; corner < 8; corner++) { Vector3 p = transform * (box.Position + box.Size * new Vector3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1)); if (first) { bounds = new Aabb(p, Vector3.Zero); first = false; } else bounds = bounds.Expand(p); }
        }
        Action(session, "Place environment asset", () =>
        {
            var item = Component(); item.Set("id", Guid.NewGuid().ToString("N")); item.Set("title", path.GetFile().GetBaseName()); using var box = new BoxMesh { Size = bounds.Size.Max(Vector3.One * .01f) }; var mesh = _meshes.from_mesh(box); var vertices = mesh.Get("vertices").AsVector3Array(); Vector3 center = bounds.GetCenter(); for (int i = 0; i < vertices.Length; i++) vertices[i] += center; mesh.Set("vertices", vertices); item.Set("mesh", mesh);
            item.Set("transform", new Transform3D(align ? new Basis(new Quaternion(Vector3.Up, normal.Normalized())) : Basis.Identity, point)); var document = Doc(session); document.Get("components").AsGodotArray().Add(item); Dict(document, "component_settings")[item.Get("id")] = new Settings { ["kind"] = "asset", ["source"] = path, ["collision"] = false }; SelectOnly(session, item.Get("id").AsString());
        }); return "";
    }
    public string add_scatter(RefCounted session, string terrainId, string asset)
    {
        var terrain = Terrain(session, terrainId); if (terrain == null) return "Select a terrain first."; var source = LoadParts(asset); string error = source["error"].AsString(); if (error.Length > 0) return error;
        Action(session, "Add scatter layer", () =>
        {
            var document = Doc(session); var layer = document.Call("add_group", "Scatter · " + asset.GetFile().GetBaseName()).As<Resource>(); layer.Set("parent_id", terrainId); var settings = GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_scatter.gd").New().As<Resource>(); Vector2 dimensions = terrain.Get("dimensions").AsVector2();
            settings.Set("terrain_id", terrainId); settings.Get("palette").AsGodotArray().Add(new Settings { ["source"] = asset, ["weight"] = 1.0 }); settings.Set("region", new Rect2(-dimensions * .5f, dimensions)); settings.Set("density", .1);
            using var proxy = new BoxMesh { Size = new Vector3(dimensions.X, .1f, dimensions.Y) }; layer.Set("mesh", _meshes.from_mesh(proxy)); Dict(document, "component_settings")[layer.Get("id")] = new Settings { ["kind"] = "scatter", ["scatter"] = settings }; SelectOnly(session, layer.Get("id").AsString());
        }); return "";
    }
    public string promote_scatter(RefCounted session, string layerId, string identity, Settings placement)
    {
        var document = Doc(session); var layer = _documents.component(document, layerId); var scatter = Scatter(session, layerId); if (layer == null || scatter == null || placement.Count == 0) return "Choose a generated instance first.";
        int index = Get(placement, "palette", -1).AsInt32(); var palette = scatter.Get("palette").AsGodotArray(); if (index < 0 || index >= palette.Count) return "The instance source is no longer in the palette.";
        Variant asset = Get(palette[index].AsGodotDictionary(), "source", ""); var embedded = asset.VariantType == Variant.Type.Object ? asset.As<Resource>() : null; bool isDocument = embedded != null && ScriptType(embedded, "res://Workspaces/ModelWorkspace/model_document.gd"); var source = isDocument ? embedded : _import.load_document(asset.AsString());
        if (source == null || source.Get("components").AsGodotArray().Count == 0) return "The source model could not be opened.";
        Action(session, "Promote scatter instance", () =>
        {
            var parts = source.Get("components").AsGodotArray(); string title = isDocument ? parts[0].As<Resource>().Get("title").AsString() : asset.AsString().GetFile().GetBaseName(); var group = document.Call("add_group", "Editable · " + title).As<Resource>(); group.Set("transform", _documents.world_transform(document, layer) * placement["transform"].AsTransform3D()); var remap = new Settings();
            foreach (var value in parts) remap[value.As<Resource>().Get("id")] = Guid.NewGuid().ToString("N");
            foreach (var value in parts)
            {
                var part = value.As<Resource>(); var copy = _components.copy_component(part, false); copy.Set("id", remap[part.Get("id")]); copy.Set("parent_id", Get(remap, part.Get("parent_id"), group.Get("id"))); _remap.component(copy, remap); document.Get("components").AsGodotArray().Add(copy); Dict(document, "component_settings")[copy.Get("id")] = new Settings { ["kind"] = "asset", ["collision"] = scatter.Get("collisions") };
            }
            Dict(scatter, "overrides")[identity] = new Settings { ["deleted"] = true }; SelectOnly(session, group.Get("id").AsString());
        }); return "";
    }
}
