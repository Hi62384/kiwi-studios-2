using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorProperty : Resource
{
    public enum FileResourceMode { NONE, UNEDITABLE, EDITABLE }
    [Export] public StringName id { get; set; } = new("");
    [Export] public string label { get; set; } = "";
    [Export] public int value_type { get; set; } = (int)Variant.Type.Nil;
    [Export] public bool animatable { get; set; }
    [Export] public StringName object_type { get; set; } = new("");
    [Export] public Settings options { get; set; } = new();
    private readonly ActorPropertyOperations _operations = new();
    public bool can_keyframe() => _operations.can_keyframe(this);
    public FileResourceMode file_resource_mode() => (FileResourceMode)_operations.file_resource_mode(this);
    public static Settings file_resource_modes() => new() { ["NONE"] = 0, ["UNEDITABLE"] = 1, ["EDITABLE"] = 2 };
    public static ActorProperty create(StringName key, string display_label, Variant value) => create(key, display_label, value, false);
    public static ActorProperty create(StringName key, string display_label, Variant value, bool can_animate) => new() { id = key, label = display_label, value_type = (int)value.VariantType, animatable = can_animate, options = new Settings { ["default"] = value } };
    public bool accepts(Variant value) => _operations.accepts(this, value);
    public Variant create_default() => _operations.create_default(this);
    public Variant create_default_for_actor(ActorData actor) => _operations.create_default_for_actor(this, actor);
    public static Vector3 image_ratio_scale(Variant source) => new ActorPropertyOperations().image_ratio_scale(source);
}
