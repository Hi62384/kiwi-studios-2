using Godot;
using System.Collections.Generic;

public partial class InteractionHints : RefCounted
{
    [Signal] public delegate void changedEventHandler(string text);
    private readonly List<(ulong owner, string text)> _contexts = new();
    private string _idle = "";
    public void set_idle(string text) { _idle = text; Publish(); }
    public void begin(GodotObject owner, string text)
    {
        ulong id = owner.GetInstanceId(); _contexts.RemoveAll(entry => entry.owner == id); _contexts.Add((id, text)); Publish();
    }
    public void end(GodotObject owner) { ulong id = owner.GetInstanceId(); _contexts.RemoveAll(entry => entry.owner == id); Publish(); }
    private void Publish() => EmitSignal(SignalName.changed, _contexts.Count == 0 ? _idle : _contexts[^1].text);
}
