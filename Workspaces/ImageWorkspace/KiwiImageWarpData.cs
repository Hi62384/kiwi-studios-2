using Godot;
using System;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class KiwiImageWarpData : Resource
{
    [Export] public bool enabled { get; set; } = true;
    [Export] public Vector2I grid_size { get; set; } = new(65, 65);
    [Export] public Vector2[] displacement { get; set; } = Array.Empty<Vector2>();
    [Export] public float[] freeze { get; set; } = Array.Empty<float>();
    [Export] public int mesh_resolution { get; set; } = 4;
    [Export] public Vector2[] mesh_points { get; set; } = Array.Empty<Vector2>();
    [Export] public Godot.Collections.Array<Settings> pins { get; set; } = new();
    [Export] public float[] restriction { get; set; } = Array.Empty<float>();
    [Export] public Vector2[] baseline { get; set; } = Array.Empty<Vector2>();
    public long revision { get; set; }
    public long _cached_revision { get; set; } = -1;
    public Vector2[] _field { get; set; } = Array.Empty<Vector2>();
    public ImageTexture? _texture { get; set; }
    public bool _mesh_active { get; set; }
    public Vector2[] _pin_sources { get; set; } = Array.Empty<Vector2>();
    public Vector2[] _pin_deltas { get; set; } = Array.Empty<Vector2>();
    public float[] _pin_radii { get; set; } = Array.Empty<float>();
    public byte[] _pin_locked { get; set; } = Array.Empty<byte>();
    private ImageWarpKernel? _kernel;
    public ImageWarpKernel _native() => _kernel ??= new ImageWarpKernel();
    public void initialize(Vector2 extent) => _native().initialize(this, extent);
    public KiwiImageWarpData copy_warp() => (KiwiImageWarpData)_native().copy_warp(this);
    public void touch() => _native().touch(this);
    public void refine_for_brush(Vector2 extent, double diameter) => _native().refine_for_brush(this, extent, diameter);
    public static double sample_scalar(float[] values, Vector2I size, Vector2 uv) => ImageWarpOperations.SampleScalar(values, size, uv);
    public static Vector2 sample_grid(Vector2[] values, Vector2I size, Vector2 uv) => ImageWarpOperations.SampleGrid(values, size, uv);
    public Vector2 node_uv(int index) => _native().node_uv(this, index);
    public Vector2 mesh_origin(int index) => _native().mesh_origin(this, index);
    public void reset_mesh(int resolution) => _native().reset_mesh(this, resolution);
    public void change_resolution(int resolution) => _native().change_resolution(this, resolution);
    public Vector2 forward_controls(Vector2 uv) => _native().forward_controls(this, uv);
    public void rebuild() => _native().rebuild(this);
    public Texture2D? texture() => _native().texture(this);
    public Vector2 forward(Vector2 uv) => _native().forward(this, uv);
    public void capture_baseline() => _native().capture_baseline(this);
    public Vector2 inverse_offset(int index) => _native().inverse_offset(this, index);
    public void reset_all() => _native().reset_all(this);
}
