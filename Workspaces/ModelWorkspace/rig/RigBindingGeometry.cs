using Godot;
using System.Collections.Generic;
using GArray = Godot.Collections.Array;

public partial class RigBindingGeometry : RefCounted
{
    private readonly RigMath _math = new();
    public ArrayMesh render_mesh(Resource binding, int heatBone)
    {
        var source = binding.Get("source_mesh").As<Mesh>(); var result = new ArrayMesh(); var originalMesh = source as ArrayMesh;
        if (originalMesh != null)
        { result.BlendShapeMode = originalMesh.BlendShapeMode; for (int i = 0; i < originalMesh.GetBlendShapeCount(); i++) result.AddBlendShape(originalMesh.GetBlendShapeName(i)); }
        int count = binding.Get("influence_count").AsInt32(); var indexSurfaces = binding.Get("indices").AsGodotArray(); var weightSurfaces = binding.Get("weights").AsGodotArray();
        for (int surface = 0; surface < source.GetSurfaceCount(); surface++)
        {
            var arrays = source.SurfaceGetArrays(surface).Duplicate(true); transform_arrays(binding, arrays, false);
            int[] ids = indexSurfaces[surface].AsInt32Array(); float[] weights = weightSurfaces[surface].AsFloat32Array();
            arrays[(int)Mesh.ArrayType.Bones] = ids; arrays[(int)Mesh.ArrayType.Weights] = weights;
            if (heatBone >= 0)
            {
                var colors = new Color[weights.Length / count];
                for (int vertex = 0; vertex < colors.Length; vertex++)
                { double amount = 0; for (int k = 0; k < count; k++) if (ids[vertex * count + k] == heatBone) amount += weights[vertex * count + k]; colors[vertex] = Color.FromHsv((float)((1 - amount) * .66), 1, 1); }
                arrays[(int)Mesh.ArrayType.Color] = colors;
            }
            var shapes = new Godot.Collections.Array<GArray>(); Mesh.ArrayFormat flags = count == 8 ? Mesh.ArrayFormat.FlagUse8BoneWeights : 0;
            if (originalMesh != null)
            {
                foreach (var original in originalMesh.SurfaceGetBlendShapeArrays(surface))
                { var shape = original.Duplicate(true); transform_arrays(binding, shape, originalMesh.BlendShapeMode == Mesh.BlendShapeMode.Relative); shapes.Add(shape); }
                flags |= originalMesh.SurfaceGetFormat(surface) & ~(Mesh.ArrayFormat.FlagUse8BoneWeights | Mesh.ArrayFormat.FormatBones | Mesh.ArrayFormat.FormatWeights);
            }
            result.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arrays, shapes, new Godot.Collections.Dictionary(), flags);
            result.SurfaceSetMaterial(surface, source.SurfaceGetMaterial(surface)); if (originalMesh != null) result.SurfaceSetName(surface, originalMesh.SurfaceGetName(surface));
        }
        return result;
    }
    public string[] validate(Resource binding, Resource rig)
    {
        var errors = new List<string>(); var source = binding.Get("source_mesh").As<Mesh>();
        if (source == null) return new[] { "Missing binding source mesh" };
        var transform = binding.Get("mesh_to_rig").AsTransform3D();
        if (!transform.IsFinite() || System.Math.Abs(transform.Basis.Determinant()) < .0000001) errors.Add("Invalid binding transform");
        int count = binding.Get("influence_count").AsInt32();
        if (count is not (4 or 8)) { errors.Add("Unsupported influence count"); return errors.ToArray(); }
        var available = new HashSet<string>(); foreach (Variant value in rig.Get("bones").AsGodotArray()) available.Add(value.AsGodotDictionary()["id"].AsString());
        string[] boneIds = binding.Get("bone_ids").AsStringArray(); string rigid = binding.Get("rigid_bone_id").AsString();
        if (rigid.Length > 0)
        { if (System.Array.IndexOf(boneIds, rigid) < 0 || !available.Contains(rigid)) errors.Add("Missing rigid attachment bone"); return errors.ToArray(); }
        var indices = binding.Get("indices").AsGodotArray(); var weights = binding.Get("weights").AsGodotArray();
        if (indices.Count != source.GetSurfaceCount() || weights.Count != indices.Count) { errors.Add("Missing weight surfaces"); return errors.ToArray(); }
        foreach (string id in boneIds) if (!available.Contains(id)) errors.Add("Stale bone influence identity");
        for (int surface = 0; surface < indices.Count; surface++)
        {
            var points = source.SurfaceGetArrays(surface)[(int)Mesh.ArrayType.Vertex].AsVector3Array(); int[] ids = indices[surface].AsInt32Array(); float[] amounts = weights[surface].AsFloat32Array();
            if (ids.Length != points.Length * count || amounts.Length != ids.Length) { errors.Add("Invalid weight array size"); continue; }
            for (int vertex = 0; vertex < points.Length; vertex++)
            {
                double sum = 0;
                for (int k = 0; k < count; k++)
                {
                    int offset = vertex * count + k;
                    if (ids[offset] < 0 || ids[offset] >= boneIds.Length) { errors.Add("Invalid bone index"); break; }
                    if (amounts[offset] < 0 || !float.IsFinite(amounts[offset])) { errors.Add("Invalid influence weight"); break; }
                    sum += amounts[offset];
                }
                if (System.Math.Abs(sum - 1) > .001) { errors.Add("Unweighted or non-normalized vertex"); break; }
            }
        }
        return errors.ToArray();
    }
    public Skin make_skin(Resource binding, Resource rig)
    {
        var bones = rig.Get("bones").AsGodotArray(); var rest = _math.globals(bones, false); var lookup = new Dictionary<string, int>();
        for (int i = 0; i < bones.Count; i++) lookup[bones[i].AsGodotDictionary()["id"].AsString()] = i;
        var result = new Skin(); foreach (string id in binding.Get("bone_ids").AsStringArray()) { int index = lookup.GetValueOrDefault(id); result.AddBind(index, rest[index].AffineInverse()); }
        return result;
    }
    public void transform_arrays(Resource binding, GArray arrays, bool relative)
    {
        if (arrays.Count != (int)Mesh.ArrayType.Max) return;
        Transform3D transform = binding.Get("mesh_to_rig").AsTransform3D(); var normalBasis = transform.Basis.Inverse().Transposed();
        if (arrays[(int)Mesh.ArrayType.Vertex].VariantType != Variant.Type.Nil)
        {
            var points = arrays[(int)Mesh.ArrayType.Vertex].AsVector3Array();
            for (int i = 0; i < points.Length; i++) points[i] = relative ? transform.Basis * points[i] : transform * points[i];
            arrays[(int)Mesh.ArrayType.Vertex] = points;
        }
        if (arrays[(int)Mesh.ArrayType.Normal].VariantType != Variant.Type.Nil)
        {
            var normals = arrays[(int)Mesh.ArrayType.Normal].AsVector3Array();
            for (int i = 0; i < normals.Length; i++) normals[i] = relative ? normalBasis * normals[i] : (normalBasis * normals[i]).Normalized();
            arrays[(int)Mesh.ArrayType.Normal] = normals;
        }
        if (arrays[(int)Mesh.ArrayType.Tangent].VariantType != Variant.Type.Nil)
        {
            var tangents = arrays[(int)Mesh.ArrayType.Tangent].AsFloat32Array();
            for (int i = 0; i < tangents.Length / 4; i++)
            {
                Vector3 next = (transform.Basis * new Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])).Normalized();
                tangents[i * 4] = next.X; tangents[i * 4 + 1] = next.Y; tangents[i * 4 + 2] = next.Z;
            }
            arrays[(int)Mesh.ArrayType.Tangent] = tangents;
        }
    }

    public Vector3[] deformed_points(Resource binding, Resource rig, int surface)
    {
        var bones = rig.Get("bones").AsGodotArray(); var rest = _math.globals(bones, false); var pose = _math.globals(bones, true);
        var lookup = new Dictionary<string, int>(); for (int i = 0; i < bones.Count; i++) lookup[bones[i].AsGodotDictionary()["id"].AsString()] = i;
        string[] boneIds = binding.Get("bone_ids").AsStringArray(); var transforms = new Transform3D[boneIds.Length];
        for (int index = 0; index < boneIds.Length; index++) { int bone = lookup.GetValueOrDefault(boneIds[index]); transforms[index] = pose[bone] * rest[bone].AffineInverse(); }
        var points = binding.Get("source_mesh").As<Mesh>().SurfaceGetArrays(surface)[(int)Mesh.ArrayType.Vertex].AsVector3Array();
        int[] ids = binding.Get("indices").AsGodotArray()[surface].AsInt32Array(); float[] weights = binding.Get("weights").AsGodotArray()[surface].AsFloat32Array();
        int count = binding.Get("influence_count").AsInt32(); var transform = binding.Get("mesh_to_rig").AsTransform3D(); var result = new Vector3[points.Length];
        for (int vertex = 0; vertex < points.Length; vertex++)
        {
            Vector3 point = transform * points[vertex], value = Vector3.Zero;
            for (int k = 0; k < count; k++) { int offset = vertex * count + k; value += transforms[ids[offset]] * point * weights[offset]; }
            result[vertex] = value;
        }
        return result;
    }
}
