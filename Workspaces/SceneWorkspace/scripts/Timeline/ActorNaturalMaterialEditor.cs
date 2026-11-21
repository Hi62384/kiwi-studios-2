using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorNaturalMaterialEditor : VBoxContainer
{
    public Variant _reader { get; set; }
    public Variant _writer { get; set; }
    public Settings _settings { get; set; } = new();
    public Settings _original { get; set; } = new();
    public bool _pending { get; set; }
    public bool _syncing { get; set; }
    public Control? _browser { get; set; }
    public ColorRect _swatch { get; set; } = new();
    public Label _title { get; set; } = new();
    public OptionButton _mapping { get; set; } = new();
    public SpinBox _relief { get; set; } = new();
    public SpinBox _metallic { get; set; } = new();
    public CheckButton _automatic_metallic { get; set; } = new();
    public Timer _commit_timer { get; set; } = new();
    private readonly ActorNaturalMaterialEditorOperations _operations = new();
    public void setup(Variant reader, Variant writer) => setup(reader, writer, "local");
    public void setup(Variant reader, Variant writer, string editContext)
    {
        _reader = reader; _writer = writer; _operations.setup(this, editContext);
    }
    public void _number(VBoxContainer parent, string title, SpinBox input, double minimum, double maximum, double step)
        => _operations.number(parent, title, input, minimum, maximum, step);
    public void sync_from_source() => _operations.sync_from_source(this);
    public void _update_controls() => _operations.update_controls(this);
    public void _change(string key, Variant value) => _operations.change(this, key, value);
    public void _edit(Settings settings) => _operations.edit(this, settings);
    public void _finish_edit() => _operations.finish_edit(this);
    public override void _Input(InputEvent @event) => _operations.input(this, @event);
    public void _open_browser() => _operations.open_browser(this);
    public override void _ExitTree() => _operations.exit_tree(this);
    public bool _reader_valid() => EngineVariantDispatch.CallableValid(_reader);
    public bool _writer_valid() => EngineVariantDispatch.CallableValid(_writer);
    public Settings _read_native()
    {
        using var arguments = new Godot.Collections.Array();
        using var result = EngineVariantDispatch.InvokeCallable(_reader, arguments);
        return result.AsGodotDictionary();
    }
    public void _write_native(Settings settings, string mode, Settings original)
    {
        using var arguments = new Godot.Collections.Array { settings, mode, original };
        using var ignored = EngineVariantDispatch.InvokeCallable(_writer, arguments);
    }
}
