using Godot;
using System;
using Settings = Godot.Collections.Dictionary;
using GArray = Godot.Collections.Array;

[GlobalClass]
public partial class KiwiRigBinding : Resource
{
    [Export] public Mesh? source_mesh { get; set; }
    [Export] public Transform3D mesh_to_rig { get; set; } = Transform3D.Identity;
    [Export] public string[] bone_ids { get; set; } = Array.Empty<string>();
    [Export] public Godot.Collections.Array<int[]> indices { get; set; } = new();
    [Export] public Godot.Collections.Array<float[]> weights { get; set; } = new();
    [Export] public int influence_count { get; set; } = 4;
    [Export] public string[] locked_bones { get; set; } = Array.Empty<string>();
    [Export] public string rigid_bone_id { get; set; } = "";
    [Export] public Transform3D attachment_offset { get; set; } = Transform3D.Identity;
    public long revision { get; set; }
    public Settings _topology { get; set; } = new();
    private readonly RigBindingWeights _weights = new();
    private readonly RigBindingGeometry _geometry = new();
    private readonly RigWeighting _weighting = new();
    public Settings topology() => _weights.topology(this);
    public KiwiRigBinding copy_binding() => (KiwiRigBinding)_weights.copy_binding(this);
    public long signature() => _weights.signature(this);
    public Settings vertex(int surface, int index)
    {
        var result = new Settings(); var bones = indices[surface]; var values = weights[surface];
        for (int k = 0; k < influence_count; k++)
        {
            int offset = index * influence_count + k; int bone = bones[offset]; float weight = values[offset];
            if (weight > 0) result[bone] = (result.TryGetValue(bone, out var prior) ? prior.AsDouble() : 0) + weight;
        }
        return result;
    }
    public void assign(int surface, int index, Settings values) => assign_vertices(surface, new Settings { [index] = values });
    public void assign_vertices(int surface, Settings changes) => _weights.assign_vertices(this, surface, changes);
    public Settings normalized(Settings values) => _weighting.normalized(this, values, 0, 0);
    public Settings normalized(Settings values, int fallback) => _weighting.normalized(this, values, fallback, 0);
    public Settings normalized(Settings values, int fallback, double cutoff) => _weighting.normalized(this, values, fallback, cutoff);
    public void remap(Resource rig) => _weights.remap(this, rig, new Settings());
    public void remap(Resource rig, Settings fallback_ids) => _weights.remap(this, rig, fallback_ids);
    public string[] validate(Resource rig) => _geometry.validate(this, rig);
    public Skin make_skin(Resource rig) => _geometry.make_skin(this, rig);
    public ArrayMesh render_mesh() => _geometry.render_mesh(this, -1);
    public ArrayMesh render_mesh(int heat_bone) => _geometry.render_mesh(this, heat_bone);
    public void _transform_arrays(GArray arrays, bool relative) => _geometry.transform_arrays(this, arrays, relative);
    public Vector3[] deformed_points(Resource rig, int surface) => _geometry.deformed_points(this, rig, surface);
}
