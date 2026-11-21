using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorData : Resource
{
    [Export] public string id { get; set; } = "";
    [Export] public StringName type_id { get; set; } = new("");
    [Export] public string display_name { get; set; } = "";
    [Export] public string parent_id { get; set; } = "";
    [Export] public string section_id { get; set; } = "default";
    [Export] public bool show_timeline_children { get; set; } = true;
    [Export] public bool link_timeline_children { get; set; }
    [Export] public int schema_version { get; set; } = 1;
    [Export] public Settings values { get; set; } = new();
    [Export] public Godot.Collections.Array<ActorAnimationTrack> animation_tracks { get; set; } = new();
    public double animation_time { get; set; } = double.NaN;
    public Settings animation_previews { get; set; } = new();
    private readonly ActorDataOperations _operations = new();
    public ActorAnimationTrack? animation_track(string[] path) => _operations.animation_track(this, path) as ActorAnimationTrack;
    public static string new_id() => new ActorDataOperations().new_id();
    public void set_value(StringName property_id, Variant value) => _operations.set_value(this, property_id, value);
    public Variant get_value(StringName property_id) => _operations.get_value(this, property_id, default);
    public Variant get_value(StringName property_id, Variant fallback) => _operations.get_value(this, property_id, fallback);
    public static Variant copy_value(Variant value) => new ActorDataOperations().copy_value(value);
    public ActorData copy_actor() => (ActorData)_operations.copy_actor(this);
}
