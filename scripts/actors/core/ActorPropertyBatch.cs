using Godot;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorPropertyBatch : RefCounted
{
    public ActorTimeline? model { get; set; }
    public ActorRegistry? registry { get; set; }
    public Godot.Collections.Array<Settings> _before { get; set; } = new();
    public StringName _key { get; set; } = new("");
    public Variant _primary_original { get; set; }
    private readonly ActorPropertyBatchOperations _operations = new();
    public Godot.Collections.Array<ActorData> targets(ActorData primary, StringName key, Variant value)
        => new(_operations.targets(this, primary, key, value));
    public Godot.Collections.Array<Settings> capture(Godot.Collections.Array<ActorData> actors, StringName key)
    {
        using var value = Variant.From(actors); return _operations.capture(this, value.AsGodotArray(), key);
    }
    public void restore(Godot.Collections.Array<Settings> states)
    {
        using var value = Variant.From(states); _operations.restore(this, value.AsGodotArray());
    }
    public void edit(ActorData primary, StringName key, Variant value) => _operations.edit(this, primary, key, value);
    public void preview(ActorData primary, StringName key, Variant value) => _operations.preview(this, primary, key, value);
    public void finish(ActorData primary, StringName key, Variant original, Variant value) => _operations.finish(this, primary, key, original, value);
    public void commit(Godot.Collections.Array<Settings> before, Godot.Collections.Array<Settings> after, StringName key)
    {
        using var original = Variant.From(before); using var updated = Variant.From(after);
        _operations.commit(this, original.AsGodotArray(), updated.AsGodotArray(), key);
    }
}
