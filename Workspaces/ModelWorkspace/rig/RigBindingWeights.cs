using Godot;
using System.Collections.Generic;
using System.Linq;
using Settings = Godot.Collections.Dictionary;

public partial class RigBindingWeights : RefCounted
{
    public string prepare_install(Resource document, Resource armature, Settings bindings)
    {
        if (bindings.Count == 0) return "No usable weights were generated. Nothing changed.";
        foreach (var pair in bindings)
        {
            var item = document.Call("component", pair.Key).As<Resource>(); var data = pair.Value.As<Resource>(); var old = item?.Get("binding").As<Resource>();
            if (item == null || old == null || old.Get("locked_bones").AsStringArray().Length == 0 || data.Get("rigid_bone_id").AsString().Length > 0) continue;
            string[] locked = old.Get("locked_bones").AsStringArray(); data.Set("locked_bones", locked); var context = new RigWeighting.BindingContext(data);
            if (context.Count is not (4 or 8)) return "Unsupported influence count";
            var available = new HashSet<string>(context.Ids); foreach (string id in locked) if (!available.Contains(id)) return "Locked influences do not exist on the chosen armature. Unlock them before rebinding to another rig.";
            if (old.Get("source_mesh").As<Mesh>()?.GetInstanceId() != data.Get("source_mesh").As<Mesh>()?.GetInstanceId()) return "Locked weights need the same source topology. Unlock or restore it first.";
            string[] oldIds = old.Get("bone_ids").AsStringArray(); var oldLookup = new Dictionary<string, int>(); for (int i = 0; i < oldIds.Length; i++) oldLookup.TryAdd(oldIds[i], i);
            var lockedIndices = new List<(int current, int previous)>();
            for (int i = 0; i < context.Ids.Length; i++) if (context.Locked.Contains(context.Ids[i])) lockedIndices.Add((i, oldLookup.GetValueOrDefault(context.Ids[i], -1)));
            var indices = data.Get("indices").AsGodotArray(); var weights = data.Get("weights").AsGodotArray(); var previousIndices = old.Get("indices").AsGodotArray(); var previousWeights = old.Get("weights").AsGodotArray(); int previousCount = old.Get("influence_count").AsInt32();
            for (int surface = 0; surface < indices.Count; surface++)
            {
                int[] ids = indices[surface].AsInt32Array(), oldIndices = previousIndices[surface].AsInt32Array(); float[] amounts = weights[surface].AsFloat32Array(), oldAmounts = previousWeights[surface].AsFloat32Array(); var changes = new Settings();
                for (int vertex = 0; vertex < amounts.Length / context.Count; vertex++)
                {
                    var values = RigWeighting.ReadVertex(ids, amounts, context.Count, vertex); var previous = RigWeighting.ReadVertex(oldIndices, oldAmounts, previousCount, vertex);
                    foreach (var influence in lockedIndices) values[influence.current] = previous.TryGetValue(influence.previous, out var amount) ? amount.AsDouble() : 0;
                    changes[vertex] = RigWeighting.Normalize(context, values, 0, 0);
                }
                assign_vertices(data, surface, changes);
            }
        }
        using var geometry = new RigBindingGeometry();
        foreach (var pair in bindings) { string[] errors = geometry.validate(pair.Value.As<Resource>(), armature); if (errors.Length > 0) return errors[0]; }
        return "";
    }
    public void install_bindings(Resource document, Resource armature, Settings bindings)
    {
        using var geometry = new RigBindingGeometry();
        foreach (var pair in bindings)
        {
            var item = document.Call("component", pair.Key).As<Resource>(); if (item == null) continue; var binding = pair.Value.As<Resource>();
            item.Set("binding", binding); item.Set("skeleton_id", armature.Get("id"));
            if (binding.Get("rigid_bone_id").AsString().Length == 0) { item.Set("skin", geometry.make_skin(binding, armature)); item.Set("skin_mesh", geometry.render_mesh(binding, -1)); }
            else { item.Set("skin", default(Variant)); item.Set("skin_mesh", default(Variant)); }
        }
    }
    public void refresh_bindings(Resource document, Resource armature, bool remapWeights, Settings fallback)
    {
        using var geometry = new RigBindingGeometry(); using var math = new RigMath();
        Godot.Collections.Array<Transform3D>? rest = null; var bones = armature.Get("bones").AsGodotArray(); string rigId = armature.Get("id").AsString();
        foreach (Variant value in document.Get("components").AsGodotArray())
        {
            var item = value.As<Resource>(); var binding = item.Get("binding").As<Resource>();
            if (item.Get("skeleton_id").AsString() != rigId || binding == null) continue;
            if (remapWeights) remap(binding, armature, fallback);
            string rigid = binding.Get("rigid_bone_id").AsString();
            if (rigid.Length == 0) { item.Set("skin", geometry.make_skin(binding, armature)); if (remapWeights) item.Set("skin_mesh", geometry.render_mesh(binding, -1)); }
            else for (int i = 0; i < bones.Count; i++)
                if (bones[i].AsGodotDictionary()["id"].AsString() == rigid)
                { rest ??= math.globals(bones, false); binding.Set("attachment_offset", rest[i].AffineInverse() * binding.Get("mesh_to_rig").AsTransform3D()); }
        }
    }
    public void apply_weight_patch(Variant target, Settings patch)
    {
        if (target.VariantType != Variant.Type.Object) return;
        GodotObject? owner = target.AsGodotObject(); if (owner is WeakRef) owner = owner.Call("get_ref").AsGodotObject();
        if (owner == null || !GodotObject.IsInstanceValid(owner)) return;
        var document = owner.Get("document").As<Resource>(); if (document == null) return;
        var touched = new Dictionary<string, Resource>(); var surfaces = new Dictionary<(string id, int surface), (Resource binding, Settings changes)>();
        foreach (var pair in patch)
        {
            var entry = pair.Value.AsGodotDictionary(); string id = entry["id"].AsString(); var item = document.Call("component", id).As<Resource>();
            var binding = item?.Get("binding").As<Resource>(); if (item == null || binding == null) continue;
            var key = (id, entry["surface"].AsInt32());
            if (!surfaces.TryGetValue(key, out var group)) { group = (binding, new Settings()); surfaces[key] = group; }
            group.changes[entry["vertex"].AsInt32()] = entry["values"]; touched[item.Get("id").AsString()] = item;
        }
        foreach (var pair in surfaces) assign_vertices(pair.Value.binding, pair.Key.surface, pair.Value.changes);
        using var geometry = new RigBindingGeometry();
        foreach (var item in touched.Values) item.Set("skin_mesh", geometry.render_mesh(item.Get("binding").As<Resource>(), -1));
        owner.EmitSignal("changed");
    }
    public Godot.Collections.Dictionary topology(Resource binding)
    {
        var cached = binding.Get("_topology").AsGodotDictionary();
        if (cached.Count > 0) return cached;
        using var geometry = new RigGeometry(); cached = geometry.geometry(binding.Get("source_mesh").As<Mesh>(), binding.Get("mesh_to_rig").AsTransform3D());
        var representatives = new Settings(); var mappings = cached["surfaces"].AsGodotArray();
        for (int surface = 0; surface < mappings.Count; surface++) { int[] mapping = mappings[surface].AsInt32Array(); for (int vertex = 0; vertex < mapping.Length; vertex++) representatives[mapping[vertex]] = new Vector2I(surface, vertex); }
        cached["representatives"] = representatives; binding.Set("_topology", cached); return cached;
    }
    public Resource copy_binding(Resource binding)
    {
        var copy = (Resource)binding.Duplicate(false); copy.Set("source_mesh", binding.Get("source_mesh"));
        var indices = new Godot.Collections.Array<int[]>(); foreach (Variant array in binding.Get("indices").AsGodotArray()) indices.Add(array.AsInt32Array());
        var weights = new Godot.Collections.Array<float[]>(); foreach (Variant array in binding.Get("weights").AsGodotArray()) weights.Add(array.AsFloat32Array());
        copy.Set("indices", indices); copy.Set("weights", weights); copy.Set("bone_ids", binding.Get("bone_ids").AsStringArray()); copy.Set("locked_bones", binding.Get("locked_bones").AsStringArray());
        copy.Set("revision", binding.Get("revision")); copy.Set("_topology", binding.Get("_topology")); return copy;
    }
    public long signature(Resource binding) => GD.Hash(new Godot.Collections.Array { binding.Get("source_mesh"), binding.Get("mesh_to_rig"), binding.Get("bone_ids"), binding.Get("indices"), binding.Get("weights"), binding.Get("locked_bones"), binding.Get("rigid_bone_id"), binding.Get("attachment_offset") });
    public void assign_vertices(Resource binding, int surface, Settings changes)
    {
        var indexSurfaces = binding.Get("indices").AsGodotArray(); var weightSurfaces = binding.Get("weights").AsGodotArray();
        int[] ids = indexSurfaces[surface].AsInt32Array(); float[] amounts = weightSurfaces[surface].AsFloat32Array(); int count = binding.Get("influence_count").AsInt32();
        foreach (var change in changes)
        {
            int vertex = change.Key.AsInt32(); var ordered = change.Value.AsGodotDictionary().OrderByDescending(pair => pair.Value.AsDouble()).ToArray();
            for (int k = 0; k < count; k++) { int offset = vertex * count + k; ids[offset] = k < ordered.Length ? ordered[k].Key.AsInt32() : 0; amounts[offset] = k < ordered.Length ? (float)ordered[k].Value.AsDouble() : 0; }
        }
        indexSurfaces[surface] = ids; weightSurfaces[surface] = amounts; binding.Set("indices", indexSurfaces); binding.Set("weights", weightSurfaces); binding.Set("revision", binding.Get("revision").AsInt64() + 1);
    }

    public void remap(Resource binding, Resource rig, Settings fallbackIds)
    {
        var bones = rig.Get("bones").AsGodotArray(); var nextIds = bones.Select(value => value.AsGodotDictionary()["id"].AsString()).ToArray();
        var lookup = new Dictionary<string, int>(); for (int i = 0; i < nextIds.Length; i++) lookup[nextIds[i]] = i;
        string Remapped(string id) => fallbackIds.TryGetValue(id, out var found) ? found.AsString() : id;
        string[] old = binding.Get("bone_ids").AsStringArray(); binding.Set("bone_ids", nextIds);
        var remappedLocks = new List<string>(); foreach (string id in binding.Get("locked_bones").AsStringArray()) { string mapped = Remapped(id); if (lookup.ContainsKey(mapped) && !remappedLocks.Contains(mapped)) remappedLocks.Add(mapped); }
        binding.Set("locked_bones", remappedLocks.ToArray()); int count = binding.Get("influence_count").AsInt32();
        var context = new RigWeighting.BindingContext(binding); var indices = binding.Get("indices").AsGodotArray(); var weights = binding.Get("weights").AsGodotArray();
        for (int surface = 0; surface < indices.Count; surface++)
        {
            var changes = new Settings(); int[] ids = indices[surface].AsInt32Array(); float[] amounts = weights[surface].AsFloat32Array();
            for (int vertex = 0; vertex < amounts.Length / count; vertex++)
            {
                var values = new Settings();
                for (int k = 0; k < count; k++)
                {
                    int offset = vertex * count + k, index = ids[offset]; if (index < 0 || index >= old.Length) continue;
                    if (lookup.TryGetValue(Remapped(old[index]), out int bone)) values[bone] = (values.TryGetValue(bone, out var previous) ? previous.AsDouble() : 0) + amounts[offset];
                }
                changes[vertex] = RigWeighting.Normalize(context, values, 0, 0);
            }
            assign_vertices(binding, surface, changes);
        }
    }
}
