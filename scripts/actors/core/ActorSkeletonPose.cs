using Godot;
using Settings = Godot.Collections.Dictionary;

[GlobalClass]
public partial class ActorSkeletonPose : RefCounted
{
    public static string[] path(int bone, string channel) => new ActorSkeletonPoseOperations().path(bone, channel);
    public static Vector3 value(ActorData actor, int bone, string channel) => new ActorSkeletonPoseOperations().value(actor, bone, channel);
    public static Settings capture(ActorTimeline model, ActorData actor) => new ActorSkeletonPoseOperations().capture(model, actor);
    public static void restore(ActorTimeline model, Settings state) => new ActorSkeletonPoseOperations().restore(model, state);
    public static void preview(ActorTimeline model, ActorData actor, int bone, string channel, Vector3 next) => new ActorSkeletonPoseOperations().preview(model, actor, bone, channel, next);
    public static void commit(ActorTimeline model, Settings before, int bone, Settings changes, bool keyAll) => new ActorSkeletonPoseOperations().commit(model, before, bone, changes, keyAll);
    public static void key_pose(ActorTimeline model, ActorData actor, int bone) => new ActorSkeletonPoseOperations().key_pose(model, actor, bone);
}
