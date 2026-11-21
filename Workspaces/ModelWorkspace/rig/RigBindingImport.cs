using Godot;
using System;
using System.Collections.Generic;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

public partial class RigBindingImport : RefCounted
{
    private readonly RigMath _math = new();
    private static Settings Failed(string message) => new() { ["message"] = message, ["bindings"] = new Settings() };
    public Mesh source(Resource item)
    {
        var binding = item.Get("binding").As<Resource>(); if (binding != null) return binding.Get("source_mesh").As<Mesh>();
        var skinMesh = item.Get("skin_mesh").As<Mesh>(); if (skinMesh != null) return skinMesh;
        var cached = item.Get("geometry_source").As<Mesh>(); var mesh = item.Get("mesh").As<Resource>();
        if (cached != null && item.Get("modifiers").AsGodotArray().Count == 0
            && item.Get("geometry_source_hash").AsInt64() == GD.Hash(new GArray { mesh.Get("vertices"), mesh.Get("faces"), mesh.Get("uv"), mesh.Get("materials") })) return cached;
        var evaluated = GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_modifiers.gd").Call("evaluate", item).As<Resource>();
        return evaluated.Call("render_mesh", item.Get("surface_materials")).As<Mesh>();
    }
    public Settings prepare_bind(Resource document, Resource? armature, GArray targets, int selectedBone, string method, int influences)
    {
        if (armature == null || armature.Get("bones").AsGodotArray().Count == 0) return Failed("Create bones first.");
        if (targets.Count == 0) return Failed("Select one or more meshes to bind.");
        var bones = armature.Get("bones").AsGodotArray(); var inverse = document.Call("world_transform", armature).AsTransform3D().AffineInverse(); var bindings = new Settings(); long totalVertices = 0;
        using var weighting = new RigWeighting(); Godot.Collections.Array<Transform3D>? rest = null;
        foreach (Variant target in targets)
        {
            var item = target.As<Resource>(); var original = source(item); var transform = inverse * document.Call("world_transform", item).AsTransform3D(); Resource data;
            if (method == "Rigid")
            {
                data = new KiwiRigBinding(); data.Set("source_mesh", original); data.Set("mesh_to_rig", transform);
                var ids = new string[bones.Count]; for (int i = 0; i < bones.Count; i++) ids[i] = bones[i].AsGodotDictionary()["id"].AsString(); data.Set("bone_ids", ids);
                data.Set("rigid_bone_id", ids[selectedBone]); rest ??= _math.globals(bones, false); data.Set("attachment_offset", rest[selectedBone].AffineInverse() * transform);
            }
            else
            {
                long vertices = 0;
                for (int surface = 0; surface < original.GetSurfaceCount(); surface++)
                {
                    if (original.Call("surface_get_primitive_type", surface).AsInt32() != (int)Mesh.PrimitiveType.Triangles) return Failed("Soft binding needs triangular mesh surfaces. Use Rigid for line or point components.");
                    vertices += original is ArrayMesh arrays ? arrays.SurfaceGetArrayLen(surface) : original.SurfaceGetArrays(surface)[(int)Mesh.ArrayType.Vertex].AsVector3Array().Length;
                }
                totalVertices += vertices;
                if (totalVertices > RigWeighting.MaxVertices || totalVertices * bones.Count > RigWeighting.MaxPairs) return Failed("Weighting limit: 100,000 source vertices / 3 million vertex-bone pairs. Bind smaller selections or use fewer bones.");
                var computed = weighting.compute(original, bones, transform, method, influences, 8, null);
                if (computed == null) return Failed("No eligible deforming bones. Enable at least one bone's deform metadata.");
                data = computed;
            }
            bindings[item.Get("id").AsString()] = data;
        }
        return new Settings { ["message"] = "", ["bindings"] = bindings };
    }
    public Settings prepare_tasks(Resource document, Resource armature, GArray targets)
    {
        var tasks = new Godot.Collections.Array<Settings>(); var bones = armature.Get("bones").AsGodotArray(); var inverse = document.Call("world_transform", armature).AsTransform3D().AffineInverse(); long budget = 0;
        foreach (Variant target in targets)
        {
            var item = target.As<Resource>(); var mesh = source(item); long count = 0;
            for (int surface = 0; surface < mesh.GetSurfaceCount(); surface++)
            {
                if (mesh.Call("surface_get_primitive_type", surface).AsInt32() != (int)Mesh.PrimitiveType.Triangles) return Failed("Soft binding needs triangular mesh surfaces. Use Rigid for line or point components.");
                count += mesh is ArrayMesh arrays ? arrays.SurfaceGetArrayLen(surface) : mesh.SurfaceGetArrays(surface)[(int)Mesh.ArrayType.Vertex].AsVector3Array().Length;
            }
            budget += count;
            if (budget > RigWeighting.MaxVertices || budget * bones.Count > RigWeighting.MaxPairs) return Failed("Weighting limit: 100,000 source vertices / 3 million vertex-bone pairs. Bind smaller selections or use fewer bones.");
            tasks.Add(new Settings { ["id"] = item.Get("id"), ["source"] = mesh, ["bones"] = bones.Duplicate(true), ["transform"] = inverse * document.Call("world_transform", item).AsTransform3D() });
        }
        return new Settings { ["message"] = "", ["tasks"] = tasks };
    }
    public Settings prepare_import(Resource document, Resource armature, GArray targets)
    {
        var bindings = new Settings(); var bones = armature.Get("bones").AsGodotArray(); var rest = _math.globals(bones, false);
        string rigId = armature.Get("id").AsString(); var rigInverse = document.Call("world_transform", armature).AsTransform3D().AffineInverse();
        foreach (Variant target in targets)
        {
            var item = target.As<Resource>();
            if (item.Get("skeleton_id").AsString() != rigId || item.Get("skin_mesh").As<Mesh>() == null || item.Get("binding").As<Resource>() != null) continue;
            var mesh = item.Get("skin_mesh").As<Mesh>(); var transform = rigInverse * document.Call("world_transform", item).AsTransform3D(); var skin = item.Get("skin").As<Skin>();
            if (skin == null || !transform.IsEqualApprox(Transform3D.Identity)) return Failed("Imported custom mesh-space binding retained. Rebind explicitly to make its weights editable.");
            var data = new KiwiRigBinding(); data.Set("source_mesh", mesh); data.Set("mesh_to_rig", transform);
            var boneIds = new string[bones.Count]; for (int i = 0; i < bones.Count; i++) boneIds[i] = bones[i].AsGodotDictionary()["id"].AsString(); data.Set("bone_ids", boneIds);
            var remap = new Dictionary<int, int>();
            for (int slot = 0; slot < skin.GetBindCount(); slot++)
            {
                int bone = skin.GetBindBone(slot);
                if (bone < 0) for (int i = 0; i < bones.Count; i++) if (bones[i].AsGodotDictionary()["name"].AsString() == skin.GetBindName(slot).ToString()) { bone = i; break; }
                if (bone < 0 || bone >= rest.Count) return Failed("Invalid imported skin binding. Original retained.");
                if (!skin.GetBindPose(slot).IsEqualApprox(rest[bone].AffineInverse())) return Failed("Custom imported bind matrices retained. Rebind explicitly to generate editable weights.");
                remap[slot] = bone;
            }
            var indices = new Godot.Collections.Array<int[]>(); var weights = new Godot.Collections.Array<float[]>();
            for (int surface = 0; surface < mesh.GetSurfaceCount(); surface++)
            {
                var arrays = mesh.SurfaceGetArrays(surface);
                if (arrays[(int)Mesh.ArrayType.Bones].VariantType == Variant.Type.Nil || arrays[(int)Mesh.ArrayType.Weights].VariantType == Variant.Type.Nil) return Failed("This surface has no editable skin weights.");
                int[] ids = arrays[(int)Mesh.ArrayType.Bones].AsInt32Array(); float[] amounts = arrays[(int)Mesh.ArrayType.Weights].AsFloat32Array(); int vertices = arrays[(int)Mesh.ArrayType.Vertex].AsVector3Array().Length;
                if (vertices == 0) return Failed("This surface has no editable skin weights.");
                data.Set("influence_count", ids.Length / vertices);
                for (int i = 0; i < ids.Length; i++) ids[i] = remap.GetValueOrDefault(ids[i]);
                indices.Add(ids); weights.Add(amounts);
            }
            data.Set("indices", indices); data.Set("weights", weights); bindings[item.Get("id").AsString()] = data;
        }
        return bindings.Count == 0 ? Failed("No imported skins selected.") : new Settings { ["message"] = "", ["bindings"] = bindings };
    }
}
