using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class WorldSessionOperations
{
    public Settings update(RefCounted session,string id,Resource authored,string label,Settings prepared)
    {
        var document=Document(session);var root=Component(document,id);if(root==null)return Failure("The world no longer exists.");var desired=_sources.copy(authored);desired.Set("world_id",id);var current=source(root);preserve_reservations(current,desired);long signature=_sources.signature(desired);
        if(current!=null&&_sources.signature(current)==signature&&!prepared.ContainsKey("terrain_result"))return new Settings {["errors"]=Array.Empty<string>(),["warnings"]=Array.Empty<string>()};
        if(current!=null){if(current.Get("terrain_id").AsString()!=desired.Get("terrain_id").AsString()&&Items(current,"roads").Any(road=>Get(road,"mode","Ground").AsString()=="Tunnel"))return Failure("Change tunnel roads to Ground before switching their terrain reference.");string conflict=locked_conflict(current,desired);if(conflict.Length>0)return Failure(conflict);}
        var output=prepared.ContainsKey("signature")&&prepared["signature"].AsInt64()==signature?prepared:new RoadNetworkOperations().Generate(desired,()=>false);var generatedDocument=Get(output,"document").As<Resource>();if(generatedDocument==null||output["errors"].AsStringArray().Length>0)return output;var terrainPlan=new WorldTerrainOperations().tunnels_plan(session,id,desired);string terrainError=Get(terrainPlan,"error","").AsString();if(terrainError.Length>0)return Failure(terrainError);if(terrainPlan.ContainsKey("settings")&&!output.ContainsKey("terrain_result"))return Failure("Tunnel changes require the background world editor so terrain and road geometry can commit together.");
        var parts=generatedDocument.Get("components").AsGodotArray().Duplicate();parts.Clear();var replacement=new Settings();var removed=new Settings();var poses=new Settings();var existing=new Settings();var mapping=new Settings();var hierarchy=generatedDocument.Call("hierarchy_state").AsGodotDictionary();var generatedPoses=hierarchy["poses"].AsGodotDictionary();var generatedRoot=generatedPoses[id].AsTransform3D();var generatedInverse=Math.Abs(generatedRoot.Basis.Determinant())>1e-10?generatedRoot.AffineInverse():Transform3D.Identity;var stamp=new WorldBuildingMassing();var architecture=new BuildingSessionOperations();bool reused=Get(output,"development_reused",false).AsBool();
        foreach(var value in document.Get("components").AsGodotArray()){var item=value.As<Resource>();if(Generated(item,id))existing[Get(Parameters(item),"world_key",TrimOwner(item.Get("id").AsString(),id)).AsString()]=item;}
        foreach(var value in generatedDocument.Get("components").AsGodotArray())
        {
            var part=value.As<Resource>();string generatedId=part.Get("id").AsString();if(generatedId==id)continue;var parameters=Parameters(part);parameters["world_mesh_key"]=stamp.stamp(part.Get("mesh").As<Resource>(),2);parameters["world_mesh_version"]=2;var old=Lookup(existing,parameters["world_key"].AsString());
            if(old!=null&&reused){var previous=Parameters(old);if(previous.ContainsKey("world_global_pose"))parameters["world_global_pose"]=previous["world_global_pose"];else parameters.Remove("world_global_pose");}else parameters["world_global_pose"]=generatedInverse*generatedPoses[generatedId].AsTransform3D();
            if(old!=null){string error=PreservePart(part,old,reused,stamp,architecture);if(error.Length>0)return Failure(error);}parts.Add(part);replacement[part.Get("id")]=true;mapping[generatedId]=part.Get("id");
        }
        mapping[id]=id;foreach(var value in document.Get("components").AsGodotArray()){var itemId=value.As<Resource>().Get("id");if(!mapping.ContainsKey(itemId))mapping[itemId]=itemId;}var remap=new ModelReferenceRemap();
        foreach(var value in parts)
        {
            var part=value.As<Resource>();var parent=part.Get("parent_id");part.Set("parent_id",mapping.TryGetValue(parent,out var mapped)?mapped:parent);remap.component(part,mapping);string expected=part.Get("parent_id").AsString();var parameters=Parameters(part);var old=Lookup(existing,parameters["world_key"].AsString());if(old!=null&&reused)expected=Get(Parameters(old),"world_parent",expected).AsString();parameters["world_parent"]=expected;
            if(old!=null&&(Get(Parameters(old),"world_manual_parent",false).AsBool()||old.Get("parent_id").AsString()!=Get(Parameters(old),"world_parent",expected).AsString())){part.Set("parent_id",old.Get("parent_id"));part.Set("transform",old.Get("transform"));parameters["world_manual_parent"]=true;parameters["world_manual_pose"]=true;}
        }
        string removedConflict=RemovedConflict(document,existing,replacement,stamp,architecture);if(removedConflict.Length>0)return Failure(removedConflict);var generatedSettings=new Settings();foreach(var pair in Get(output,"settings",new Settings()).AsGodotDictionary())generatedSettings[mapping.TryGetValue(pair.Key,out var mapped)?mapped:pair.Key]=pair.Value;
        foreach(var value in document.Get("components").AsGodotArray()){var item=value.As<Resource>();if(Generated(item,id))removed[item.Get("id")]=true;}
        foreach(var value in parts)
        {
            var part=value.As<Resource>();var parent=part.Get("parent_id");if(!removed.ContainsKey(parent)||replacement.ContainsKey(parent))continue;var old=Component(document,part.Get("id").AsString());if(old!=null)part.Set("transform",document.Call("world_transform",root).AsTransform3D().AffineInverse()*document.Call("world_transform",old).AsTransform3D());part.Set("parent_id",id);Parameters(part)["world_manual_parent"]=true;Parameters(part)["world_manual_pose"]=true;
        }
        string hierarchyError=new WorldPlacementOperations().hierarchy_plan(document,id,removed,replacement,parts,poses);if(hierarchyError.Length>0)return Failure(hierarchyError);
        CommitWorld(session,root,desired,label,output,generatedDocument,parts,removed,replacement,poses,existing,generatedSettings);return output;
    }
    private static bool IsScatter(Resource? resource)
    {if(resource==null)return false;var script=resource.GetScript().As<Script>();while(script!=null){if(script.ResourcePath=="res://Workspaces/EnvironmentWorkspace/environment_scatter.gd")return true;script=script.GetBaseScript();}return false;}
    private void CommitWorld(RefCounted session,Resource root,Resource desired,string label,Settings output,Resource generatedDocument,GArray parts,Settings removed,Settings replacement,Settings poses,Settings existing,Settings generatedSettings)
    {
        var document=Document(session);string id=root.Get("id").AsString();session.Call("begin");root.Set("parameters",Parameters(Component(generatedDocument,id)!));Parameters(root)["editor_proxy"]=true;var dimensions=desired.Get("dimensions").AsVector2();root.Set("mesh",ModelPrimitives.Box(new Vector3(dimensions.X,.05f,dimensions.Y)).Build());var retained=document.Get("components").AsGodotArray().Duplicate();retained.Clear();var environment=session.Call("environment").As<Resource>();var componentSettings=environment.Get("component_settings").AsGodotDictionary();
        if(output.TryGetValue("terrain_result",out var terrainValue)){var generated=terrainValue.AsGodotDictionary();componentSettings[generated["id"]].AsGodotDictionary()["terrain"]=generated["terrain"];Component(document,generated["id"].AsString())!.Set("mesh",generated["mesh"]);}
        foreach(var value in document.Get("components").AsGodotArray()){var item=value.As<Resource>();var itemId=item.Get("id");if(!removed.ContainsKey(itemId))retained.Add(item);else if(!replacement.ContainsKey(itemId))componentSettings.Remove(itemId);}
        var forests=new WorldForestOperations();foreach(var value in parts)
        {
            var part=value.As<Resource>();string partId=part.Get("id").AsString();var parameters=Parameters(part);var settings=Get(generatedSettings,partId,new Settings {["kind"]=Get(parameters,"world_lazy_building",false).AsBool()?"building":"asset",["collision"]=true}).AsGodotDictionary();var oldSettings=Get(componentSettings,partId,new Settings()).AsGodotDictionary();var oldRules=Get(oldSettings,"scatter").As<Resource>();var newRules=Get(settings,"scatter").As<Resource>();
            if(IsScatter(oldRules)&&IsScatter(newRules)){var old=Lookup(existing,parameters["world_key"].AsString());if(old!=null)forests.preserve(oldRules!,newRules!,Get(Parameters(old),"world_scatter_defaults",new Settings()).AsGodotDictionary());}retained.Add(part);componentSettings[partId]=settings;
        }
        document.Set("components",retained);var inverse=document.Call("world_transform",root).AsTransform3D().AffineInverse();foreach(var pair in poses){var child=Component(document,pair.Key.AsString())!;child.Set("parent_id",id);child.Set("transform",inverse*pair.Value.AsTransform3D());}
        var selected=session.Get("selected").AsGodotArray();var ids=selected.ToArray();selected.Clear();foreach(var identity in ids)if(Component(document,identity.AsString())!=null)selected.Add(identity);session.Call("commit",label);
    }
}
