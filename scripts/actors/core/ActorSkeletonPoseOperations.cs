using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
public partial class ActorSkeletonPoseOperations:RefCounted
{
    private readonly ActorDataOperations _data=new();private readonly ActorAnimationOperations _animation=new();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    public string[] path(int bone,string channel)=>new[]{"bone_poses",bone.ToString(System.Globalization.CultureInfo.InvariantCulture),channel};
    public Vector3 value(Resource actor,int bone,string channel){var address=path(bone,channel);var fallback=_animation.value_at_path(actor,address);double time=actor.Get("animation_time").AsDouble();return _animation.sampled_value(actor,address,double.IsNaN(time)?0:time,fallback).AsVector3();}
    public Settings capture(RefCounted model,Resource actor)=>new Settings{["actor"]=actor,["poses"]=_data.copy_value(Get(actor.Get("values").AsGodotDictionary(),"bone_poses",new Settings())),["tracks"]=model.Call("animation_snapshot",actor)};
    public void restore(RefCounted model,Settings state){var actor=state["actor"].As<Resource>();actor.Get("values").AsGodotDictionary()[new StringName("bone_poses")]=_data.copy_value(state["poses"]);actor.Get("animation_previews").AsGodotDictionary().Clear();model.Call("restore_animation",actor,state["tracks"]);}
    public void preview(RefCounted model,Resource actor,int bone,string channel,Vector3 next)=>model.Call("preview_animation_value",actor,path(bone,channel),next);
    public void commit(RefCounted model,Settings before,int bone,Settings changes,bool keyAll)
    {
        var actor=before["actor"].As<Resource>();actor.Get("animation_previews").AsGodotDictionary().Clear();bool modified=keyAll;foreach(var entry in changes){var address=path(bone,entry.Key.AsString());var original=_animation.sampled_value(actor,address,actor.Get("animation_time").AsDouble(),_animation.value_at_path(actor,address)).AsVector3();if(!original.IsEqualApprox(entry.Value.AsVector3()))modified=true;}if(!modified){restore(model,before);return;}bool previous=model.Get("property_batch_active").AsBool();model.Set("property_batch_active",true);try{var bones=Get(actor.Get("values").AsGodotDictionary(),"rig_bones",new Godot.Collections.Array()).AsGodotArray();foreach(var entry in changes){string channel=entry.Key.AsString();var address=path(bone,channel);if(keyAll||_data.animation_track(actor,address)!=null)model.Call("add_keyframe",actor,address,"Bones / "+bones[bone].AsGodotDictionary()["name"].AsString()+" / "+channel.Capitalize(),entry.Value);else actor.Get("values").AsGodotDictionary()[new StringName("bone_poses")].AsGodotDictionary()[bone.ToString(System.Globalization.CultureInfo.InvariantCulture)].AsGodotDictionary()[channel]=entry.Value;}}finally{model.Set("property_batch_active",previous);}var after=capture(model,actor);var history=model.Get("history").As<UndoRedo>();var action=new ActorSkeletonPoseHistoryAction(model,before,after);history.CreateAction(keyAll?"Key Bone Pose":"Transform Bone");history.AddDoMethod(new Callable(action,nameof(ActorSkeletonPoseHistoryAction.restore_after)));history.AddUndoMethod(new Callable(action,nameof(ActorSkeletonPoseHistoryAction.restore_before)));history.AddDoReference(action);history.CommitAction();
    }
    public void key_pose(RefCounted model,Resource actor,int bone){var changes=new Settings();foreach(string channel in new[]{"position","rotation","scale"})changes[channel]=value(actor,bone,channel);commit(model,capture(model,actor),bone,changes,true);}
}
