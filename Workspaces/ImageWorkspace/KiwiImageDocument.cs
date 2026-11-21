using Godot;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;
using LayerArray = Godot.Collections.Array<KiwiImageLayer>;

[GlobalClass]
public partial class KiwiImageDocument : Resource
{
    [Export] public int version { get; set; } = 1;
    [Export] public Vector2I canvas_size { get; set; } = new(1280, 720);
    [Export] public LayerArray layers { get; set; } = new();
    [Export] public string output_path { get; set; } = "";
    [Export] public Texture2D? preview { get; set; }
    [Export] public Settings workspace_state { get; set; } = new();
    [Export] public Settings selections { get; set; } = new();
    [Export] public Settings selection_masks { get; set; } = new();
    [Export] public string active_selection_mask { get; set; } = "";
    [Export] public Texture2D? pixel_selection { get; set; }
    [Export] public string pixel_selection_owner { get; set; } = "";
    [Export] public KiwiImageLayer? pixel_selection_reference { get; set; }
    [Export] public Transform2D pixel_selection_reference_world { get; set; } = Transform2D.Identity;
    [Export] public Godot.Collections.Array<KiwiLiveMaterialTemplate> live_materials { get; set; } = new();
    [Export] public string active_live_material_id { get; set; } = "";
    [Export] public bool live_edit_enabled { get; set; }
    private readonly ImageDocumentOperations _operations = new();
    private static LayerArray Typed(GArray values)
    {
        var result = new LayerArray();
        foreach (var value in values) result.Add((KiwiImageLayer)value.As<Resource>());
        return result;
    }
    public KiwiImageLayer? layer_for_id(string id) => _operations.layer_for_id(this, id) as KiwiImageLayer;
    public LayerArray children() => children("");
    public LayerArray children(string parent) => Typed(_operations.children(this, parent));
    public bool is_descendant(string id, string ancestor) => _operations.is_descendant(this, id, ancestor);
    public Transform2D world_transform(KiwiImageLayer layer) => _operations.world_transform(this, layer);
    public bool can_edit(KiwiImageLayer layer) => _operations.can_edit(this, layer);
    public bool isolation_allows(KiwiImageLayer layer) => _operations.isolation_allows(this, layer);
    public LayerArray selected_roots(Godot.Collections.Array<string> ids)
    {
        var raw = new GArray(); foreach (string id in ids) raw.Add(id);
        return Typed(_operations.selected_roots(this, raw));
    }
    public KiwiImageDocument snapshot() => (KiwiImageDocument)_operations.snapshot(this);
    public void resize_layer(KiwiImageLayer layer, Vector2 dimensions) => _operations.resize_layer(this, layer, dimensions);
    public KiwiLiveMaterialTemplate create_live_material(KiwiTextureMaterial material) => create_live_material(material, "");
    public KiwiLiveMaterialTemplate create_live_material(KiwiTextureMaterial material, string label) => (KiwiLiveMaterialTemplate)_operations.create_live_material(this, material, label);
    public KiwiLiveMaterialTemplate? live_material_for_id(string template_id) => _operations.live_material_for_id(this, template_id) as KiwiLiveMaterialTemplate;
    public bool set_live_material(string template_id, KiwiTextureMaterial material) => _operations.set_live_material(this, template_id, material);
    public bool live_material_has_artwork(string template_id) => _operations.live_material_has_artwork(this, template_id);
    public KiwiLivePaintRegion? add_live_region(KiwiImageLayer layer, string template_id) => add_live_region(layer, template_id, null, Transform2D.Identity);
    public KiwiLivePaintRegion? add_live_region(KiwiImageLayer layer, string template_id, Texture2D? coverage) => add_live_region(layer, template_id, coverage, Transform2D.Identity);
    public KiwiLivePaintRegion? add_live_region(KiwiImageLayer layer, string template_id, Texture2D? coverage, Transform2D mapping) => _operations.add_live_region(this, layer, template_id, coverage, mapping) as KiwiLivePaintRegion;
    public bool delete_live_material(string template_id) => _operations.delete_live_material(this, template_id);
    public void pack_live_material_textures() => _operations.pack_live_material_textures(this);
}
