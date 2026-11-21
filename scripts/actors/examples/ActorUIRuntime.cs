using Godot;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class ActorUIRuntime : ActorRuntime
{
    public CanvasLayer? canvas_layer { get; set; }
    public Node2D anchor { get; set; } = new();
    public ActorUIVisual visual { get; set; } = new();
    public Label label { get; set; } = new();
    public Settings _values { get; set; } = new();
    public double _time { get; set; }
    public string _image_signature { get; set; } = "";
    public string _video_path { get; set; } = "";
    public long _text_signature { get; set; } = -1;
    public GpuParticles2D? particles_2d { get; set; }
    public ParticleProcessMaterial? particle_material_2d { get; set; }
    public bool _particles_emitting { get; set; } = true;
    public long _particle_settings_hash { get; set; } = -1;
    public ShaderMaterial? canvas_shader_material { get; set; }
    public string _canvas_shader_key { get; set; } = "";
    private readonly UiActorOperations _operations = new();
    public override void _Ready()
    {
        _operations.ready(this);
    }
    public Rect2 bounds()
    {
        return _operations.bounds(this);
    }
    public override void evaluate_transform(Settings values)
    {
        _operations.evaluate_transform(this,values);
    }
    public override void set_active(bool value)
    {
        base.set_active(value);
        _operations.set_active(this,value);
    }
    public override void evaluate(double time, Settings values)
    {
        _operations.evaluate(this,time,values);
    }
    public void _apply_canvas_material(Variant value)
    {
        _operations.apply_canvas_material(this,value);
    }
    public bool _is_canvas_shader(string code)
    {
        return _operations.is_canvas_shader(code);
    }
    public ActorObjectData? _load_object_resource(string path)
    {
        return _operations.load_object_resource(path) as ActorObjectData;
    }
    public string _resource_path(string path)
    {
        return _operations.resource_path(path);
    }
    public Texture2D? _texture_for_value(Variant value)
    {
        return _operations.texture_for_value(value);
    }
    public void refresh_saved_image(Variant _source)
    {
        _operations.refresh_saved_image(this,_source);
    }
    public void _apply_particles_2d(Settings values)
    {
        _operations.apply_particles_2d(this,values);
    }
    public override void _Process(double _delta)
    {
        _operations.process(this,_delta);
    }
    public override void set_timeline_time(double timeline_time)
    {
        _operations.set_timeline_time(this,timeline_time);
    }
    public void refresh_saved_shader(Variant _source)
    {
        _operations.refresh_saved_shader(this,_source);
    }
}
