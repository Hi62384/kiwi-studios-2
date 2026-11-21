using Godot;

public partial class RigModelRuntime : Node3D
{
    public Godot.Collections.Array<Godot.Collections.Dictionary> attachments { get; set; } = new();
    public override void _Ready() => update_attachments();
    public override void _Process(double delta) => update_attachments();
    public void update_attachments()
    {
        foreach (var entry in attachments)
        {
            if (!entry.TryGetValue("target", out var targetValue) || !entry.TryGetValue("skeleton", out var skeletonValue)) continue;
            if (targetValue.AsGodotObject() is not Node3D target || skeletonValue.AsGodotObject() is not Skeleton3D skeleton
                || !GodotObject.IsInstanceValid(target) || !GodotObject.IsInstanceValid(skeleton) || !target.IsInsideTree()) continue;
            if (!entry.TryGetValue("bone", out var boneValue) || !entry.TryGetValue("offset", out var offset)) continue;
            int bone = boneValue.AsInt32(); if (bone < 0 || bone >= skeleton.GetBoneCount()) continue;
            target.GlobalTransform = skeleton.GlobalTransform * skeleton.GetBoneGlobalPose(bone) * offset.AsTransform3D();
        }
    }
}
