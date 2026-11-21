using Godot;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class RigSkeletonRuntime : RefCounted
{
    public Skeleton3D create_skeleton(GArray bones)
    {
        var result=new Skeleton3D {Name="Skeleton"};
        foreach(Variant value in bones) result.AddBone(value.AsGodotDictionary()["name"].AsString());
        for(int i=0;i<bones.Count;i++)
        {
            var bone=bones[i].AsGodotDictionary(); result.SetBoneParent(i,bone["parent"].AsInt32()); result.SetBoneRest(i,bone["rest"].AsTransform3D());
            result.SetBonePosePosition(i,bone["position"].AsVector3()); result.SetBonePoseRotation(i,Quaternion.FromEuler(bone["rotation"].AsVector3()*(Mathf.Pi/180))); result.SetBonePoseScale(i,bone["scale"].AsVector3());
        }
        return result;
    }
    public void evaluate_pose(Skeleton3D skeleton,GArray bones,Settings poses)
    {
        for(int i=0;i<skeleton.GetBoneCount();i++)
        {
            var pose=poses.TryGetValue(i.ToString(),out var value)?value.AsGodotDictionary():i<bones.Count?bones[i].AsGodotDictionary():new Settings();
            if(pose.Count==0) continue;
            skeleton.SetBonePosePosition(i,pose["position"].AsVector3());
            skeleton.SetBonePoseRotation(i,Quaternion.FromEuler(pose["rotation"].AsVector3()*(Mathf.Pi/180)));
            skeleton.SetBonePoseScale(i,pose["scale"].AsVector3());
        }
    }
}
