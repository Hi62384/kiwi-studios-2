using Godot;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class EnvironmentActorRuntime : ActorRuntime
{
    public Node3D? content { get; set; }
    public string source_path { get; set; } = "";
    public KiwiEnvironmentDocument? source_document { get; set; }
    public string error { get; set; } = "";
    public string linked_source_warning { get; set; } = "";
    public double shader_time { get; set; }
    public Settings climate_overrides { get; set; } = new();
    public Godot.Collections.Array<Settings> _source_jobs { get; set; } = new();
    public long _source_generation { get; set; }
    private readonly EnvironmentActorOperations _operations = new();
    public override void bind(ActorData data)
    {
        base.bind(data);
        if (IsNodeReady()) _operations.load_source(this, data.get_value("environment_path", "").AsString());
    }
    public override void _Ready()
    {
        _operations.ready(this);
    }
    public bool physics_geometry_ready(bool need_physics)
    {
        return _operations.physics_geometry_ready(this,need_physics);
    }
    public bool physics_geometry_ready() => physics_geometry_ready(true);
    public string physics_geometry_error()
    {
        return _operations.physics_geometry_error(this);
    }
    public bool render_geometry_ready()
    {
        return content != null && _source_jobs.Count == 0 && content.Call("geometry_ready", false).AsBool();
    }
    public string render_geometry_error()
    {
        return physics_geometry_error();
    }
    public KiwiEnvironmentDocument? environment_for_physics()
    {
        return _operations.environment_for_physics(this) as KiwiEnvironmentDocument;
    }
    public Settings environment_at(Vector3 world_position, double time, Settings overrides)
    {
        return _operations.environment_at(this,world_position,time,overrides);
    }
    public Settings environment_at(Vector3 world_position, double time) => environment_at(world_position, time, new Settings());
    public override void _Process(double _delta)
    {
        _operations.process(this);
    }
    public void _cancel_source_jobs()
    {
        _operations.cancel_source_jobs(this);
    }
    public override void _ExitTree()
    {
        _operations.cancel_source_jobs(this);
    }
    public override void evaluate_transform(Settings values)
    {
        _operations.evaluate_transform(this,values);
    }
    public override void set_active(bool value)
    {
        _operations.set_active(this,value);
    }
    public override bool supports_remote_transform()
    {
        return true;
    }
    public Settings water_at(Vector3 world_point)
    {
        return _operations.water_at(this,world_point);
    }
    public override Transform3D remote_transform()
    {
        return GlobalTransform;
    }
    public override void apply_remote_transform(Transform3D source, bool move, bool rotate, bool resize)
    {
        _operations.apply_remote_transform(this,source,move,rotate,resize);
    }
    public override void evaluate(double _time, Settings values)
    {
        _operations.evaluate(this,values);
    }
    public void _load_source(string path)
    {
        _operations.load_source(this,path);
    }
    public void _prepare_source()
    {
        _operations.prepare_source(this);
    }
    public void _configure_source()
    {
        _operations.configure_source(this);
    }
    public void _clear_source()
    {
        _operations.clear_source(this);
    }
    public void reload_environment(string path)
    {
        _operations.reload_environment(this,path);
    }
    public void refresh_saved_model(string path)
    {
        _operations.refresh_saved_model(this,path);
    }
    public void refresh_saved_image(Variant source)
    {
        _operations.refresh_saved_image(this,source);
    }
    public override void set_timeline_time(double time)
    {
        _operations.set_timeline_time(this,time);
    }
}
