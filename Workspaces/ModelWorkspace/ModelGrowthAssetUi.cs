using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class ModelWorkspaceOperations
{
    public void growth_asset_actions(Control workspace, Node parent, Resource data)
    {
        var material = data.Get("appearance").As<Resource>(); var actions = new HFlowContainer(); parent.AddChild(actions); var session = Session(workspace);
        AddButton(actions, "Save material…", () => growth_save_material(workspace, data));
        foreach (bool link in new[] { false, true }) AddButton(actions, link ? "Link material…" : "Load material…", async () =>
        {
            string path = await GrowthPick(workspace, GrowthProperty(), link ? "Link shared growth material" : "Load growth material"); if (path.Length == 0 || path == "::empty-resource::" || !GrowthCurrent(workspace, session)) return;
            var loaded = ResourceLoader.Load(path); if (loaded == null || !GrowthScriptType(loaded, "growth_material")) { GrowthNotice(workspace, "Choose a Growth Material resource."); return; }
            Action(session, link ? "Link growth material" : "Load growth material", () => { if (link) { loaded.Set("linked_source", path); data.Set("appearance", loaded); } else data.Set("appearance", _growthMaterials.copy_material(loaded, true)); });
        });
        AddButton(actions, "Make unique", () => Action(session, "Make growth material unique", () => data.Set("appearance", _growthMaterials.copy_material(material, true))));
        AddButton(actions, "Duplicate", () => Action(session, "Duplicate growth material", () => { var copy = _growthMaterials.copy_material(material, true); copy.Set("title", copy.Get("title").AsString() + " copy"); data.Set("appearance", copy); }));
        string linkedSource = material.Get("linked_source").AsString();
        if (linkedSource.Length > 0)
        {
            Label(parent, "Shared material · " + linkedSource.GetFile());
            AddButton(parent, "Save linked material", () => { if (GrowthInside(ProjectSettings.GlobalizePath(linkedSource))) GrowthNotice(workspace, ResourceSaver.Save(material, linkedSource) == Error.Ok ? "Material saved." : "Could not save material."); });
        }
        if (material.Get("mode").AsInt32() == 2) AddButton(parent, "Load custom material…", async () =>
        {
            var property = GrowthProperty(new Settings { ["extensions"] = new GArray { "tres", "res" }, ["accepted_object_types"] = new GArray { "material", "shader_material", "natural_material" }, ["native_resource_types"] = new GArray { "Material" } }); property.Set("object_type", new StringName("material"));
            string path = await GrowthPick(workspace, property, "Custom growth material"); if (path.Length == 0 || !GrowthCurrent(workspace, session)) return;
            var resource = path == "::empty-resource::" ? null : ResourceLoader.Load(path); var loaded = _growthMaterials.from_asset(resource); if (resource != null && loaded == null) { GrowthNotice(workspace, "Choose a spatial material or Spatial ShaderMaterial."); return; }
            Action(session, "Custom growth material", () => { material.Set("custom", loaded != null ? Variant.From(loaded) : default); material.Set("custom_asset", resource != null && resource.HasMethod("get_value") ? Variant.From(resource) : default); });
        });
    }
}
