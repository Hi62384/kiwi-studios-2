using Godot;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class BasicActorRuntime : ActorRuntime
{
    public Node? content { get; set; }
    public Node3D? parenting_anchor { get; set; }
    public StandardMaterial3D? material { get; set; }
    public ShaderMaterial? shader_material { get; set; }
    public ShaderMaterial? natural_material { get; set; }
    public Settings _natural_settings { get; set; } = new();
    public string loaded_shader_path { get; set; } = "";
    public string loaded_image_path { get; set; } = "";
    public string loaded_model_path { get; set; } = "";
    public Settings texture_cache { get; set; } = new();
    public Settings noise_texture_cache { get; set; } = new();
    public Shader? _watched_shader { get; set; }
    public long _shape_kind { get; set; } = -1;
    public long _light_kind { get; set; } = -1;
    public Environment? _world_environment_resource { get; set; }
    public Environment? _previous_environment { get; set; }
    public bool _previous_environment_captured { get; set; }
    public Label3D? text_shadow { get; set; }
    public ParticleProcessMaterial? particle_material { get; set; }
    public bool _particle_emitting { get; set; } = true;
    public long _particle_settings_hash { get; set; } = -1;
    public FogMaterial? fog_material { get; set; }
    public ShaderMaterial? fog_shader_material { get; set; }
    public string fog_shader_key { get; set; } = "";
    public ShaderMaterial? camera_shader_material { get; set; }
    public string camera_shader_key { get; set; } = "";
    public CanvasLayer? camera_canvas { get; set; }
    public ColorRect? camera_overlay { get; set; }
    private readonly BasicActorOperations _operations = new();
    public override void _ExitTree()
    {
        var callback = new Callable(this, "_source_shader_changed");
        if (GodotObject.IsInstanceValid(_watched_shader) && _watched_shader!.IsConnected("changed", callback)) _watched_shader.Disconnect("changed", callback);
        _operations.restore_environment(this);
    }
    public override void _Ready()
    {
        _operations.ready(this);
    }
    public void _add_camera_guide(Camera3D camera)
    {
        _operations.add_camera_guide(camera);
    }
    public override Node parenting_node()
    {
        return _operations.parenting_node(this);
    }
    public override bool supports_remote_transform()
    {
        return _operations.supports_remote_transform(this);
    }
    public override Transform3D remote_transform()
    {
        return _operations.remote_transform(this);
    }
    public override void apply_remote_transform(Transform3D source, bool use_position, bool use_rotation, bool use_scale)
    {
        _operations.apply_remote_transform(this,source,use_position,use_rotation,use_scale);
    }
    public override void set_active(bool value)
    {
        base.set_active(value);
        _operations.set_active(this,value);
    }
    public override void evaluate_transform(Settings values)
    {
        _operations.evaluate_transform(this,values);
    }
    public override void evaluate(double _time, Settings values)
    {
        _operations.evaluate(this,_time,values);
    }
    public void _apply_decal(Settings values)
    {
        _operations.apply_decal(this,values);
    }
    public void _apply_particles(Settings values)
    {
        _operations.apply_particles(this,values);
    }
    public void _apply_fog(Settings values)
    {
        _operations.apply_fog(this,values);
    }
    public void _apply_camera_shader(Variant value)
    {
        _operations.apply_camera_shader(this,value);
    }
    public void update_camera_overlay()
    {
        _operations.update_camera_overlay(this);
    }
    public Shader? _shader_from_value(Variant value)
    {
        return _operations.shader_from_value(this,value);
    }
    public string _shader_source_key(Variant value)
    {
        return _operations.shader_source_key(this,value);
    }
    public ShaderMaterial? _runtime_shader_material(Shader source, string kind, bool screen_input)
    {
        return _operations.runtime_shader_material(source,kind,screen_input);
    }
    public ShaderMaterial? _runtime_shader_material(Shader source, string kind) => _runtime_shader_material(source, kind, false);
    public void _apply_shader_uniforms(ShaderMaterial target, ActorObjectData @object)
    {
        _operations.apply_shader_uniforms(this,target,@object);
    }
    public void _apply_reflection_probe(Settings values)
    {
        _operations.apply_reflection_probe(this,values);
    }
    public MeshInstance3D? _new_mesh_instance()
    {
        return _operations.new_mesh_instance();
    }
    public StandardMaterial3D? _new_standard_material()
    {
        return _operations.new_standard_material();
    }
    public void _update_shape(int kind)
    {
        _operations.update_shape(this,kind);
    }
    public void _apply_shape_properties(PrimitiveMesh mesh, Settings values)
    {
        _operations.apply_shape_properties(mesh,values);
    }
    public void _update_model(Variant source)
    {
        _operations.update_model(this,source);
    }
    public void _bind_model_skin()
    {
        _operations.bind_model_skin(this);
    }
    public void apply_rig_attachment()
    {
        _operations.apply_rig_attachment(this);
    }
    public void refresh_saved_model(string path)
    {
        _operations.refresh_saved_model(this,path);
    }
    public void refresh_model_binding(string path)
    {
        _operations.refresh_model_binding(this,path);
    }
    public Light3D? _new_light(int kind)
    {
        return _operations.new_light(kind);
    }
    public void _ensure_light(int kind)
    {
        _operations.ensure_light(this,kind);
    }
    public void _apply_light(Settings values)
    {
        _operations.apply_light(this,values);
    }
    public void _apply_directional_light(Settings values)
    {
        _operations.apply_directional_light(this,values);
    }
    public void _apply_environment(Variant value)
    {
        _operations.apply_environment(this,value);
    }
    public void _configure_environment(Environment environment, ActorObjectData @object)
    {
        _operations.configure_environment(this,environment,@object);
    }
    public void _apply_environment_background(Environment environment, ActorObjectData @object)
    {
        _operations.apply_environment_background(this,environment,@object);
    }
    public void _restore_environment()
    {
        _operations.restore_environment(this);
    }
    public void _apply_material_reference(Variant value, Texture2D albedo_texture, bool preserve_null)
    {
        _operations.apply_material_reference(this,value,albedo_texture,preserve_null);
    }
    public void _apply_natural_material(ActorObjectData @object)
    {
        _operations.apply_natural_material(this,@object);
    }
    public void _ensure_standard_material()
    {
        _operations.ensure_standard_material(this);
    }
    public void _reset_standard_material(Texture2D albedo_texture)
    {
        _operations.reset_standard_material(this,albedo_texture);
    }
    public void _apply_standard_material(ActorObjectData @object)
    {
        _operations.apply_standard_material(this,@object);
    }
    public virtual void _assign_material_override(Material value)
    {
        _operations.assign_material_override(this,value);
    }
    public void _apply_shader_material(ActorObjectData @object)
    {
        _operations.apply_shader_material(this,@object);
    }
    public ShaderMaterial? _create_shader_material(ActorObjectData @object)
    {
        return _operations.create_shader_material(this,@object);
    }
    public override void set_timeline_time(double timeline_time)
    {
        _operations.set_timeline_time(this,timeline_time);
    }
    public void _watch_shader(Shader source)
    {
        _operations.watch_shader(this,source);
    }
    public void _source_shader_changed()
    {
        _operations.source_shader_changed(this);
    }
    public ActorObjectData? _current_material_object()
    {
        return _operations.current_material_object(this) as ActorObjectData;
    }
    public void _reload_actor_shader()
    {
        _operations.reload_actor_shader(this);
    }
    public void refresh_saved_shader(Variant _source)
    {
        _operations.refresh_saved_shader(this,_source);
    }
    public void refresh_saved_image(Variant source)
    {
        _operations.refresh_saved_image(this,source);
    }
    public Texture2D? _load_external_texture(string path)
    {
        return _operations.load_external_texture(path);
    }
    public Texture2D? _texture_for_path(string path)
    {
        return _operations.texture_for_path(this,path);
    }
    public Texture2D? _texture_for_value(Variant value)
    {
        return _operations.texture_for_value(this,value);
    }
    public string _resource_identity(Variant value)
    {
        return _operations.resource_identity(value);
    }
    public ActorObjectData? _load_object_resource(string path)
    {
        return _operations.load_object_resource(path) as ActorObjectData;
    }
    public string _godot_resource_path(string path)
    {
        return _operations.godot_resource_path(path);
    }
    public World3D? _runtime_world(bool create_if_missing)
    {
        return _operations.runtime_world(this,create_if_missing);
    }
    public World3D? _runtime_world() => _runtime_world(true);
}
