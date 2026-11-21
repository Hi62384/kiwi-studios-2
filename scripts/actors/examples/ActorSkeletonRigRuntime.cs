using Godot;
using System.Collections.Generic;
using GArray = Godot.Collections.Array;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorSkeletonRigRuntime : PointActorRuntime
{
    public Skeleton3D? skeleton { get; set; }
    public RigSkeletonRuntime _pose_runtime { get; set; } = new();
    public static Skeleton3D create_skeleton(GArray bones) => new RigSkeletonRuntime().create_skeleton(bones);
    public override void _Ready()
    {
        base._Ready();
        var values = actor!.values;
        skeleton = create_skeleton(values.GetValueOrDefault(new StringName("rig_bones"), new GArray()).AsGodotArray());
        transform_node!.AddChild(skeleton); AddToGroup("actor_skeleton_rigs");
    }
    public override void evaluate_transform(Settings values)
    {
        base.evaluate_transform(values);
        _pose_runtime.evaluate_pose(skeleton!, actor!.values.GetValueOrDefault(new StringName("rig_bones"), new GArray()).AsGodotArray(), values.GetValueOrDefault(new StringName("bone_poses"), new Settings()).AsGodotDictionary());
    }
}
