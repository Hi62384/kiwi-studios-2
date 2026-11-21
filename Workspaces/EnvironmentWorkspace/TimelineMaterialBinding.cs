using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class TimelineMaterialBinding : Resource
{
    public const int SHADER_CACHE_LIMIT = 32;
    public const int SHADER_CODE_BUDGET = 4 * 1024 * 1024;
    public Settings _state { get; set; } = new()
    {
        ["source"] = default, ["target"] = default, ["shader"] = default,
        ["code"] = "", ["compiled"] = false, ["uniforms"] = Array.Empty<string>(), ["busy"] = false
    };
    private readonly TimelineMaterialLink _operations = new();
    public bool active() => _operations.active(_state);
    public bool active_for(Variant material)
    {
        if (material.VariantType != Variant.Type.Object) return false;
        using var arguments = new GArray();
        return active_for_id(EngineVariantDispatch.Call(material, "get_instance_id", arguments).AsInt64());
    }
    public bool active_for_id(long identity) => _operations.active_for(_state, identity);
    public ShaderMaterial? authoring_source() => _operations.authoring_source(_state);
    // Keep source and target as Variants; converting the temporary target to a
    // managed ShaderMaterial wrapper would extend its lifetime until collection.
    public void setup(Variant source, Variant target)
    {
        setup_weak(EngineVariantDispatch.Weak(source).As<WeakRef>(), EngineVariantDispatch.Weak(target).As<WeakRef>());
    }
    // The scene adapter supplies WeakRefs before crossing the CLR boundary, so
    // even argument conversion cannot retain a disposable preview material.
    public void setup_weak(WeakRef source, WeakRef target)
    {
        long identity = unchecked((long)GetInstanceId());
        TimelineMaterialLink.Listen(_state["source"], identity, false);
        TimelineMaterialLink.Listen(_state["shader"], identity, false);
        _state["source"] = source; _state["target"] = target;
        _state["shader"] = default; _state["compiled"] = false; _state["code"] = "";
        _state["owner"] = identity;
        _operations.setup(_state);
    }
    public void _changed() => _operations._changed(_state);
    public void synchronize_parameters() => _operations.synchronize_parameters(_state);
    public static Settings _prepared_shader(Shader source) => new TimelineMaterialLink().prepared_shader(source);
}
