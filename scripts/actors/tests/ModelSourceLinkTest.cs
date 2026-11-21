using Godot;
using System;
using Settings=Godot.Collections.Dictionary;

public partial class ModelSourceLinkTest : Node
{
    public override void _Ready()
    {
        try
        {
            using var link=new ModelSourceLink();using var actor=new ActorData();
            var values=actor.Get("values").AsGodotDictionary();values[new StringName("model_component_bind_transform")]=Transform3D.Identity;values[new StringName("model_component_source")]="res://source.tres";values[new StringName("model_component_instance_id")]="instance";values[new StringName("model_component_id")]="part";
            using var track=new ActorAnimationTrack();track.Set("path",new[]{"structure_connections","support","strength"});actor.Get("animation_tracks").AsGodotArray().Add(track);
            var old=new Settings{["support"]=new Settings{["strength"]=1.0,["target_pivot"]=Vector3.One},["deleted"]=4};
            var next=new Settings{["support"]=new Settings{["strength"] = .7,["target_pivot"]=Vector3.One*2},["deleted"]=5,["new_field"]=new Godot.Collections.Array{1,2}};
            var current=new Settings{["support"]=new Settings{["strength"]=1.0,["target_pivot"]=Vector3.One}};
            var result=link._reconcile(actor,old,next,current,new[]{"structure_connections"}).AsGodotDictionary();var support=result["support"].AsGodotDictionary();
            if(support["strength"].AsDouble()!=1||support["target_pivot"].AsVector3()!=Vector3.One*2||result.ContainsKey("deleted")||!result.ContainsKey("new_field"))throw new Exception("Source reconciliation lost animation protection, default updates, or deleted/new fields.");
            result["new_field"].AsGodotArray()[0]=99;if(next["new_field"].AsGodotArray()[0].AsInt32()!=1)throw new Exception("A copied source value aliases the source array.");
            GD.Print("PASS linked-source reconciliation preserves nested animation and deleted fields while copying new defaults independently");
            actor.Get("animation_tracks").AsGodotArray().Clear();current["support"].AsGodotDictionary()["strength"] = .3;support=link._reconcile(actor,old,next,current,new[]{"structure_connections"}).AsGodotDictionary()["support"].AsGodotDictionary();
            if(support["strength"].AsDouble()!=.3||support["target_pivot"].AsVector3()!=Vector3.One*2)throw new Exception("Local nested overrides were overwritten by the source.");
            GD.Print("PASS linked-source reconciliation retains local overrides while updating untouched siblings");
            var runtime=new Node();AddChild(runtime);if(!link.register_actor(actor,runtime))throw new Exception("Valid linked actor registration failed.");var entry=link._instances["instance"].AsGodotDictionary()["part"].AsGodotDictionary();if(link._actor(entry)!=actor)throw new Exception("Registered live actor could not be resolved.");runtime.QueueFree();if(link._actor(entry)!=null)throw new Exception("Queued-for-deletion runtime remained eligible for source updates.");
            GD.Print("PASS linked-source weak runtime registry excludes queued-for-deletion instances");GetTree().Quit();
        }
        catch(Exception error){GD.PushError(error.ToString());GetTree().Quit(1);}
    }
}
