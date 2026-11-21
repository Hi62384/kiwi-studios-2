using Godot;

public partial class CompositeWorkspaceAnimation : RefCounted
{
    private readonly CompositingDocument _rules = new();

    public bool set_property(Resource document, string layerId, string property, double time, Variant value)
    {
        var layer = _rules.layer_resource(document, layerId);
        if (layer == null) return false;
        if (_rules.has_layer_track_resource(document, layerId, property))
            return _rules.set_layer_key_resource(document, layerId, property, time, value);
        layer.Set(property, value);
        return true;
    }

    public bool key_transform(Resource document, string layerId, double time)
    {
        var layer = _rules.layer_resource(document, layerId);
        if (layer == null) return false;
        foreach (string property in new[] { "position", "rotation", "scale", "opacity" })
        {
            Variant value = _rules.sample_layer_value_resource(document, layerId, property, time, layer.Get(property));
            _rules.set_layer_key_resource(document, layerId, property, time, value);
        }
        return true;
    }
}
