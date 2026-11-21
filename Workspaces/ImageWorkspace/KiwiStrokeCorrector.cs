using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiStrokeCorrector : RefCounted
{
    public const int SUPPORT = 54, CORNER_SUPPORT = 12, TAIL = 76;
    public const double CONNECTION_RANGE = 16;
    public StrokeCorrectorKernel? _kernel { get; set; }
    public Settings _array_values { get; set; } = new();
    public Settings _array_revisions { get; set; } = new();
    public StrokeCorrectorKernel _native() => _kernel ??= new StrokeCorrectorKernel();
    public double strength { get => _native().get_state("strength").AsDouble(); set => _native().set_state("strength", value); }
    public double correction_scale { get => _native().get_state("correction_scale").AsDouble(); set => _native().set_state("correction_scale", value); }
    public double spacing { get => _native().get_state("spacing").AsDouble(); set => _native().set_state("spacing", value); }
    public Variant points { get => _array_view("points"); set => _native().set_state("points", value); }
    public Variant times { get => _array_view("times"); set => _native().set_state("times", value); }
    public Variant knots { get => _array_view("knots"); set => _native().set_state("knots", value); }
    public Variant corners { get => _array_view("corners"); set => _native().set_state("corners", value); }
    public Vector2 _tip { get => _native().get_state("_tip").AsVector2(); set => _native().set_state("_tip", value); }
    public Vector2 _last { get => _native().get_state("_last").AsVector2(); set => _native().set_state("_last", value); }
    public double _last_time { get => _native().get_state("_last_time").AsDouble(); set => _native().set_state("_last_time", value); }
    public double _tip_time { get => _native().get_state("_tip_time").AsDouble(); set => _native().set_state("_tip_time", value); }
    public double _carry { get => _native().get_state("_carry").AsDouble(); set => _native().set_state("_carry", value); }
    public int _sealed { get => _native().get_state("_sealed").AsInt32(); set => _native().set_state("_sealed", value); }
    public bool _dirty { get => _native().get_state("_dirty").AsBool(); set => _native().set_state("_dirty", value); }
    public Variant _left_corner { get => _array_view("_left_corner"); set => _native().set_state("_left_corner", value); }
    public Variant _right_corner { get => _array_view("_right_corner"); set => _native().set_state("_right_corner", value); }
    public Variant _turn_prefix { get => _array_view("_turn_prefix"); set => _native().set_state("_turn_prefix", value); }
    public Variant _fit_first { get => _array_view("_fit_first"); set => _native().set_state("_fit_first", value); }
    public Variant _fit_last { get => _array_view("_fit_last"); set => _native().set_state("_fit_last", value); }
    public Variant _fit_radius { get => _array_view("_fit_radius"); set => _native().set_state("_fit_radius", value); }
    public Variant _fit_edge { get => _array_view("_fit_edge"); set => _native().set_state("_fit_edge", value); }
    public Rect2 _raw_bounds { get => _native().get_state("_raw_bounds").AsRect2(); set => _native().set_state("_raw_bounds", value); }
    public bool _shape_rejected { get => _native().get_state("_shape_rejected").AsBool(); set => _native().set_state("_shape_rejected", value); }
    public bool _gap_closed { get => _native().get_state("_gap_closed").AsBool(); set => _native().set_state("_gap_closed", value); }
    public void begin(Vector2 point, double amount, double brushSize) => begin(point, amount, brushSize, 0, 1);
    public void begin(Vector2 point, double amount, double brushSize, double time) => begin(point, amount, brushSize, time, 1);
    public void begin(Vector2 point, double amount, double brushSize, double time, double scale) => _native().begin(point, amount, brushSize, time, scale);
    public void add(Vector2 point, double time) => _native().add(point, time);
    public Vector2 _raw(int index) => _native().raw(index);
    public double _time(int index) => _native().time(index);
    public bool _corner(int index, int count) => _native().corner(index, count);
    public Vector2 _fit(int index, int count) => _native().fit(index, count);
    public Vector2 _tangent(int index) => _native().tangent(index);
    public Vector2[] _path(int first, int last) => _native().path(first, last);
    public Vector2[] _close_gap(int count) => _native().close_gap(count);
    public Settings update() => _native().update();
    public Variant _array_view(string key)
    {
        long version = _native().view_version();
        if (!_array_revisions.TryGetValue(key, out var previous) || previous.AsInt64() != version)
        {
            _array_values[key] = _native().get_state(key);
            _array_revisions[key] = version;
        }
        return _array_values[key];
    }
}
