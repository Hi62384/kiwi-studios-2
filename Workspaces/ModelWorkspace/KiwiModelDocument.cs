using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiModelDocument : Resource
{
    [Export] public int version { get; set; } = 1;
    [Export] public Godot.Collections.Array<KiwiModelComponent> components { get; set; } = new();
    [Export] public Settings workspace_state { get; set; } = new();
    [Export] public Texture2D? preview { get; set; }
    [Export] public byte[] preview_png { get; set; } = Array.Empty<byte>();
    public Texture2D? _thumbnail { get; set; }
    private readonly ModelDocumentOperations _operations = new();
    public Texture2D? thumbnail() => _operations.thumbnail(this);
    public virtual string[] validate() => _operations.validate(this);
    public virtual string[] _component_geometry_errors(KiwiModelComponent item) => item.mesh?.validate() ?? Array.Empty<string>();
    public KiwiModelComponent? component(string id) => _operations.component(this, id) as KiwiModelComponent;
    public virtual KiwiModelDocument snapshot() => (KiwiModelDocument)_operations.snapshot(this);
    public Transform3D world_transform(KiwiModelComponent item) => _operations.world_transform(this, item);
    public Settings hierarchy_state() => _operations.hierarchy_state(this, new Godot.Collections.Array<string>());
    public Settings hierarchy_state(Godot.Collections.Array<string> chosen) => _operations.hierarchy_state(this, chosen);
    public bool is_descendant(string id, string ancestor_id) => _operations.is_descendant(this, id, ancestor_id);
    public bool visible_component(KiwiModelComponent item) => _operations.visible_component(this, item);
    public bool editable_component(KiwiModelComponent item) => _operations.editable_component(this, item);
    public Node3D instantiate_model() => _operations.instantiate_model(this);
    public static Settings transform_values(Transform3D transform) => new ModelDocumentOperations().transform_values(transform);
    public ActorSceneData actor_scene(RefCounted registry, string source_path) => (ActorSceneData)_operations.actor_scene(this, registry, source_path);
    public void prepare_growth() => _operations.prepare_growth(this);
}
