using Godot;

public partial class ImageOperationRow : PanelContainer
{
    [Signal] public delegate void reorder_requestedEventHandler(int from, int to);
    public int index { get; set; }
    public override Variant _GetDragData(Vector2 atPosition)
    {
        SetDragPreview(new Label { Text = "Move operation" });
        return new Godot.Collections.Dictionary { ["value_operation"] = index, ["owner"] = GetParent().GetInstanceId() };
    }
    public override bool _CanDropData(Vector2 atPosition, Variant data)
    {
        if (data.VariantType != Variant.Type.Dictionary || GetParent() == null) return false;
        var payload = data.AsGodotDictionary();
        return payload.TryGetValue("owner", out var owner) && owner.AsUInt64() == GetParent().GetInstanceId()
            && payload.TryGetValue("value_operation", out var from) && from.VariantType == Variant.Type.Int && from.AsInt32() >= 0;
    }
    public override void _DropData(Vector2 atPosition, Variant data)
    {
        if (!_CanDropData(atPosition, data)) return;
        EmitSignal(SignalName.reorder_requested, data.AsGodotDictionary()["value_operation"].AsInt32(), index);
    }
}
