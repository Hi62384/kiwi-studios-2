using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class TimelineMaterialLink : RefCounted
{
    private sealed record Prepared(Shader Shader, string Uniform, string[] Uniforms, int Bytes);
    private static readonly Dictionary<string, Prepared> PreparedShaders = new(StringComparer.Ordinal);
    private static readonly LinkedList<string> Order = new();
    private static readonly object CacheLock = new();
    private static int _bytes;
    // Obtain a raw engine Variant from WeakRef without creating a managed
    // material wrapper. Release each temporary strong engine reference promptly.
    private static Variant WeakInvoke(Variant reference, string method, params Variant[] args)
    {
        if (reference.VariantType != Variant.Type.Object || reference.AsGodotObject() is not WeakRef weak)
            return method == "_alive" ? Variant.From(false) : default;
        Variant target = weak.GetRef();
        if (method == "_identity") return target;
        try
        {
            if (method == "_alive") return target.VariantType == Variant.Type.Object;
            if (target.VariantType != Variant.Type.Object) return default;
            using var arguments = new GArray(args);
            return EngineVariantDispatch.Call(target, method, arguments);
        }
        finally { target.Dispose(); }
    }
    private static Variant Invoke(Settings state, string slot, string method, params Variant[] args)
        => WeakInvoke(state[slot], method, args);
    internal static void Listen(Variant reference, long identity, bool enabled)
    {
        if (!WeakInvoke(reference, "_alive").AsBool()) return;
        var owner = GodotObject.InstanceFromId(unchecked((ulong)identity));
        if (!GodotObject.IsInstanceValid(owner)) return;
        var callback = new Callable(owner!, nameof(TimelineMaterialBinding._changed));
        bool connected = WeakInvoke(reference, "is_connected", "changed", callback).AsBool();
        if (connected != enabled) WeakInvoke(reference, enabled ? "connect" : "disconnect", "changed", callback);
    }
    private static ShaderMaterial? Source(Settings state) => Invoke(state, "source", "_identity").As<ShaderMaterial>();
    public bool active(Settings state) => Invoke(state, "source", "_alive").AsBool() && Invoke(state, "target", "_alive").AsBool();
    public bool active_for(Settings state, long identity) => active(state) && Invoke(state, "target", "get_instance_id").AsInt64() == identity;
    public ShaderMaterial? authoring_source(Settings state) => Source(state);
    public void setup(Settings state)
    {
        var source = Source(state); if (source == null) return;
        Listen(state["source"],state["owner"].AsInt64(),true);
        _changed(state);
    }
    public void _changed(Settings state)
    {
        if (state["busy"].AsBool() || !active(state)) return; state["busy"] = true;
        try
        {
            var source = Source(state)!;
            var previous = state["shader"].As<WeakRef>()?.GetRef().As<Shader>();
            if (previous != source.Shader)
            {
                if (previous != null) Listen(state["shader"],state["owner"].AsInt64(),false);
                state["shader"] = source.Shader != null ? Variant.From(GodotObject.WeakRef(source.Shader)!) : default;
                if (source.Shader != null) Listen(state["shader"],state["owner"].AsInt64(),true);
                state["compiled"] = false;
            }
            if (source.Shader == null)
            {
                Invoke(state,"target","set","shader",default); Invoke(state,"target","set_meta","kiwi_time_uniform", ""); state["uniforms"] = Array.Empty<string>(); return;
            }
            if (!state["compiled"].AsBool() || state["code"].AsString() != source.Shader.Code)
            {
                state["compiled"] = true; state["code"] = source.Shader.Code;
                var prepared = Prepare(source.Shader); Invoke(state,"target","set","shader",prepared.Shader);
                string uniform = prepared.Uniform; state["uniforms"] = prepared.Uniforms;
                if (uniform.Length == 0) { string existing = source.GetMeta("kiwi_time_uniform", "").AsString(); if (Array.IndexOf(prepared.Uniforms, existing) >= 0) uniform = existing; }
                Invoke(state,"target","set_meta","kiwi_time_uniform",uniform);
                if (uniform.Length > 0) Invoke(state,"target","set_shader_parameter",uniform,Invoke(state,"target","get_meta","kiwi_last_time",0.0));
            }
        }
        finally { state["busy"] = false; }
        synchronize_parameters(state);
    }
    private static Prepared Prepare(Shader source)
    {
        string code = source.Code;
        lock (CacheLock)
        {
            if (PreparedShaders.TryGetValue(code, out var cached)) { Order.Remove(code); Order.AddLast(code); return cached; }
            var transformed = new ActorShaderTimeOperations().prepare(code); string controlled = transformed["code"].AsString();
            var result = new Prepared(new Shader { Code = controlled }, transformed["uniform"].AsString(), source.GetShaderUniformList().Select(value => value.AsGodotDictionary()["name"].AsString()).ToArray(), checked(code.Length * 2 + controlled.Length * 2));
            if (result.Bytes <= 4 * 1024 * 1024)
            {
                while (Order.Count > 0 && (Order.Count >= 32 || _bytes + result.Bytes > 4 * 1024 * 1024)) { string oldest = Order.First!.Value; Order.RemoveFirst(); _bytes -= PreparedShaders[oldest].Bytes; PreparedShaders.Remove(oldest); }
                PreparedShaders[code] = result; Order.AddLast(code); _bytes += result.Bytes;
            }
            return result;
        }
    }
    public Settings prepared_shader(Shader source)
    { var value = Prepare(source); return new Settings { ["shader"] = value.Shader, ["uniform"] = value.Uniform, ["uniforms"] = value.Uniforms, ["bytes"] = value.Bytes }; }
    internal static void ClearCache() { lock (CacheLock) { PreparedShaders.Clear(); Order.Clear(); _bytes = 0; } }
    private static bool Same(Variant a, Variant b)
    {
        if (a.VariantType == b.VariantType)
        {
            switch (a.VariantType)
            {
                case Variant.Type.Nil: return true;
                case Variant.Type.Bool: return a.AsBool() == b.AsBool();
                case Variant.Type.Int: return a.AsInt64() == b.AsInt64();
                case Variant.Type.Float: return a.AsDouble() == b.AsDouble();
                case Variant.Type.String: case Variant.Type.StringName: return a.AsString() == b.AsString();
                case Variant.Type.Object: return a.AsGodotObject() == b.AsGodotObject();
                case Variant.Type.Color: return a.AsColor() == b.AsColor();
                case Variant.Type.Vector2: return a.AsVector2() == b.AsVector2();
                case Variant.Type.Vector3: return a.AsVector3() == b.AsVector3();
                case Variant.Type.Vector4: return a.AsVector4() == b.AsVector4();
            }
        }
        using var left = new GArray { a }; using var right = new GArray { b }; return left.RecursiveEqual(right);
    }
    public void synchronize_parameters(Settings state)
    {
        if (state["busy"].AsBool() || !active(state)) return;
        var source = Source(state)!;
        if (source.Shader != state["shader"].As<WeakRef>()?.GetRef().As<Shader>()) { _changed(state); return; }
        if (Invoke(state,"target","get","shader").VariantType == Variant.Type.Nil) return;
        string manual = Invoke(state,"target","get_meta","kiwi_time_uniform", "").AsString();
        foreach (string name in state["uniforms"].AsStringArray())
        {
            if (name == manual) continue;
            Variant value = source.GetShaderParameter(name);
            if (!Same(Invoke(state,"target","get_shader_parameter",name), value)) Invoke(state,"target","set_shader_parameter",name,value);
        }
    }
}
