using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorRuntime : Node3D
{
    public ActorData? actor { get; set; }
    public bool active;
    private readonly ActorRuntimeOperations _runtimeOperations = new();
    public override Variant _Get(StringName property) => property == "active" ? Variant.From(active) : default;
    public override bool _Set(StringName property, Variant value)
    {
        if (property != "active") return false; active = value.AsBool(); return true;
    }
    public virtual void bind(ActorData data) => _runtimeOperations.bind(this, data);
    public virtual Node parenting_node() => this;
    public void evaluate_clip(ActorClip clip, double timelineTime) => evaluate_clip(clip, timelineTime, new Settings());
    public virtual void evaluate_clip(ActorClip clip, double timelineTime, Settings overrides) => _runtimeOperations.evaluate_clip(this, clip, timelineTime, overrides);
    public virtual void set_active(bool value) => _runtimeOperations.set_active(this, value);
    public virtual void evaluate_transform(Settings values) { }
    public virtual void evaluate(double localTime, Settings values) { }
    public virtual void set_timeline_time(double timelineTime) { }
    public virtual bool supports_remote_transform() => false;
    public virtual Transform3D remote_transform() => Transform3D.Identity;
    public virtual void apply_remote_transform(Transform3D source, bool position, bool rotation, bool scale) { }
}
