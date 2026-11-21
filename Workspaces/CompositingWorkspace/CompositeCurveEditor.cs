using Godot;
using System.Collections.Generic;

public partial class CompositeCurveEditor : Control
{
    [Signal] public delegate void edit_startedEventHandler();
    [Signal] public delegate void points_changedEventHandler(Godot.Collections.Array points);
    [Signal] public delegate void edit_finishedEventHandler();
    private readonly List<Vector2> _points = new() { Vector2.Zero, Vector2.One };
    private int _active = -1;

    public override void _Ready()
    {
        CustomMinimumSize = new Vector2(260, 190); MouseFilter = MouseFilterEnum.Stop;
    }

    public void set_points(Godot.Collections.Array values)
    {
        _points.Clear();
        foreach (Variant point in values) if (point.VariantType == Variant.Type.Vector2) _points.Add(point.AsVector2());
        if (_points.Count < 2) { _points.Clear(); _points.Add(Vector2.Zero); _points.Add(Vector2.One); }
        SortAndClamp(); QueueRedraw();
    }

    public override void _Draw()
    {
        var rect = new Rect2(Vector2.Zero, Size); DrawRect(rect, new Color("111a24"));
        for (int division = 1; division < 4; division++)
        {
            float x = Size.X * division / 4, y = Size.Y * division / 4;
            DrawLine(new Vector2(x, 0), new Vector2(x, Size.Y), new Color("304252"));
            DrawLine(new Vector2(0, y), new Vector2(Size.X, y), new Color("304252"));
        }
        DrawRect(rect, new Color("71899b"), false);
        var curve = new Vector2[65];
        for (int step = 0; step <= 64; step++) { float x = step / 64f; curve[step] = CanvasPoint(new Vector2(x, Sample(x))); }
        DrawPolyline(curve, new Color("56dbc0"), 2, true);
        for (int i = 0; i < _points.Count; i++)
        {
            DrawCircle(CanvasPoint(_points[i]), 5, new Color(i == _active ? "ffe2a0" : "efffff"));
            DrawArc(CanvasPoint(_points[i]), 5, 0, Mathf.Tau, 20, new Color("183c43"), 2);
        }
    }

    public override void _GuiInput(InputEvent input)
    {
        if (input is InputEventMouseButton button)
        {
            if (button.ButtonIndex == MouseButton.Left && button.Pressed)
            {
                EmitSignal(SignalName.edit_started); _active = Nearest(button.Position);
                if (_active < 0) { _points.Add(Normalized(button.Position)); SortAndClamp(); _active = Nearest(button.Position); }
                MoveActive(button.Position); AcceptEvent();
            }
            else if (button.ButtonIndex == MouseButton.Left && !button.Pressed && _active >= 0)
            {
                _active = -1; QueueRedraw(); EmitSignal(SignalName.edit_finished); AcceptEvent();
            }
            else if (button.ButtonIndex == MouseButton.Right && button.Pressed)
            {
                int candidate = Nearest(button.Position);
                if (candidate > 0 && candidate < _points.Count - 1)
                {
                    EmitSignal(SignalName.edit_started); _points.RemoveAt(candidate); Publish();
                    EmitSignal(SignalName.edit_finished); AcceptEvent();
                }
            }
        }
        else if (input is InputEventMouseMotion motion && _active >= 0) { MoveActive(motion.Position); AcceptEvent(); }
    }

    private void MoveActive(Vector2 position)
    {
        if (_active < 0 || _active >= _points.Count) return;
        var point = Normalized(position);
        if (_active == 0) point.X = 0;
        else if (_active == _points.Count - 1) point.X = 1;
        else point.X = Mathf.Clamp(point.X, _points[_active - 1].X + .005f, _points[_active + 1].X - .005f);
        _points[_active] = point; Publish();
    }

    private void Publish()
    {
        SortAndClamp(); var values = new Godot.Collections.Array();
        foreach (var point in _points) values.Add(point);
        EmitSignal(SignalName.points_changed, values); QueueRedraw();
    }

    private void SortAndClamp()
    {
        for (int i = 0; i < _points.Count; i++) _points[i] = _points[i].Clamp(Vector2.Zero, Vector2.One);
        _points.Sort((a, b) => a.X.CompareTo(b.X));
        if (_points.Count >= 2) { _points[0] = new Vector2(0, _points[0].Y); _points[^1] = new Vector2(1, _points[^1].Y); }
    }

    private int Nearest(Vector2 position)
    {
        int best = -1; float distance = 14;
        for (int i = 0; i < _points.Count; i++)
        {
            float candidate = CanvasPoint(_points[i]).DistanceTo(position);
            if (candidate < distance) { best = i; distance = candidate; }
        }
        return best;
    }
    private Vector2 Normalized(Vector2 position) => new(Mathf.Clamp(position.X / Mathf.Max(1, Size.X), 0, 1), 1 - Mathf.Clamp(position.Y / Mathf.Max(1, Size.Y), 0, 1));
    private Vector2 CanvasPoint(Vector2 point) => new(point.X * Size.X, (1 - point.Y) * Size.Y);
    private float Sample(float value)
    {
        if (value <= _points[0].X) return _points[0].Y;
        for (int i = 1; i < _points.Count; i++)
            if (value <= _points[i].X) return Mathf.Lerp(_points[i - 1].Y, _points[i].Y, Mathf.InverseLerp(_points[i - 1].X, _points[i].X, value));
        return _points[^1].Y;
    }
}
