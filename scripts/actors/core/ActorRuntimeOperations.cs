using Godot;
using System;
using Settings=Godot.Collections.Dictionary;
public partial class ActorRuntimeOperations:RefCounted
{
    private readonly ActorDataOperations _data=new();private readonly ActorAnimationOperations _animation=new();
    public Resource create_clip(Resource actor,double start,double length)=>ActorClip.create(actor,start,length);
    public bool contains_time(Resource clip,double time){double start=clip.Get("start_time").AsDouble();return time>=start&&time<start+clip.Get("duration").AsDouble();}
    public double local_time(Resource clip,double time)=>clip.Get("source_offset").AsDouble()+(time-clip.Get("start_time").AsDouble())*clip.Get("playback_speed").AsDouble();
    public void bind(Node3D owner,Resource actor)=>owner.Set("actor",actor);
    public void set_active(Node3D owner,bool active)=>owner.Set("active",active);
    public void evaluate_clip(Node3D owner,Resource clip,double timelineTime,Settings overrides)
    {
        var actor=owner.Get("actor").As<Resource>();if(actor==null||clip.Get("actor_id").AsString()!=actor.Get("id").AsString()){owner.Call("set_active",false);return;}double time=local_time(clip,timelineTime);actor.Set("animation_time",time);var evaluated=_animation.sampled_values(actor,time);evaluated.Merge(overrides,true);owner.Call("evaluate_transform",evaluated);owner.Call("set_active",contains_time(clip,timelineTime));if(!owner.Get("active").AsBool())return;owner.Call("evaluate",time,evaluated);owner.Call("set_timeline_time",timelineTime);
    }
}
