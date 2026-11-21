using Godot;
using System;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class ModelSourceLink : RefCounted
{
    public sealed class CacheState
    {
        public Settings Resources=new(),Instances=new(),Revisions=new(),Resolved=new();
        public readonly object Sync=new();
        public void Clear(){lock(Sync){Resources.Clear();Instances.Clear();Revisions.Clear();Resolved.Clear();}}
    }
    private readonly CacheState _state;
    public ModelSourceLink():this(new CacheState()){}
    public ModelSourceLink(CacheState state)=>_state=state;
    public Settings _resources {get=>_state.Resources;set=>_state.Resources=value;}
    public Settings _instances {get=>_state.Instances;set=>_state.Instances=value;}
    public Settings _revisions {get=>_state.Revisions;set=>_state.Revisions=value;}
    public Settings _resolved {get=>_state.Resolved;set=>_state.Resolved=value;}
    private readonly ModelDocumentOperations _documents=new();
    private static Variant Value(Settings settings,Variant key,Variant fallback)=>settings.TryGetValue(key,out var value)?value:fallback;
    private static Variant ActorValue(Resource actor,string key,Variant fallback)=>Value(actor.Get("values").AsGodotDictionary(),new StringName(key),fallback);
    private static bool ScriptType(GodotObject value,string path)
    {var script=value.GetScript().As<Script>();while(script!=null){if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true;script=script.GetBaseScript();}return false;}
    private static GDScript Bridge()=>GD.Load<GDScript>("res://Workspaces/ModelWorkspace/model_source_link.gd");
    public string _path(string path)
    {if(path.StartsWith("uid://",StringComparison.Ordinal)){long id=ResourceUid.TextToId(path);if(ResourceUid.HasId(id))path=ResourceUid.GetIdPath(id);}return ProjectSettings.GlobalizePath(path).Replace('\\','/').SimplifyPath();}
    public void invalidate(string path) {lock(_state.Sync){invalidate_locked(path);}}
    private void invalidate_locked(string path)
    {path=_path(path);_resources.Remove(path);_revisions[path]=Value(_revisions,path,0).AsInt64()+1;}
    public Resource? load_resource(string path) {lock(_state.Sync){return load_resource_locked(path);}}
    private Resource? load_resource_locked(string path)
    {
        if(path.Length==0)return null;path=_path(path);if(path.Length==0||!ResourceLoader.Exists(path))return null;
        using var file=Godot.FileAccess.Open(path,Godot.FileAccess.ModeFlags.Read);long key=GD.Hash(new GArray{Godot.FileAccess.GetModifiedTime(path),file?.GetLength()??0,Value(_revisions,path,0),Bridge().Call("_asset_revision",path)});
        if(_resources.TryGetValue(path,out var cached)&&cached.AsGodotDictionary()["key"].AsInt64()==key)return cached.AsGodotDictionary()["resource"].As<Resource>();
        var resource=ResourceLoader.Load(path,"",ResourceLoader.CacheMode.Ignore);if(_resources.Count>=16)_resources.Remove(_resources.Keys.First());_resources[path]=new Settings{["key"]=key,["resource"]=resource==null?default(Variant):Variant.From(resource)};return resource;
    }
    public Resource? resolved_resource(string path) {lock(_state.Sync){return resolved_resource_locked(path);}}
    private Resource? resolved_resource_locked(string path)
    {
        var resource=load_resource(path);if(resource==null||!ScriptType(resource,"res://Workspaces/ModelWorkspace/model_document.gd")||ScriptType(resource,"res://Workspaces/EnvironmentWorkspace/environment_document.gd"))return resource;
        path=_path(path);long key=GD.Hash(new GArray{resource.GetInstanceId(),Bridge().Call("_asset_generation")});
        if(_resolved.TryGetValue(path,out var cached)&&cached.AsGodotDictionary()["key"].AsInt64()==key)return cached.AsGodotDictionary()["resource"].As<Resource>();
        var result=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/architecture/module_links.gd").Call("resolve",resource).AsGodotDictionary();var resolved=result["document"].As<Resource>()??resource;
        if(_resolved.Count>=16)_resolved.Remove(_resolved.Keys.First());_resolved[path]=new Settings{["key"]=key,["resource"]=resolved};return resolved;
    }
    public bool register_actor(Resource? actor,Node? runtime) {lock(_state.Sync){return register_actor_locked(actor,runtime);}}
    private bool register_actor_locked(Resource? actor,Node? runtime)
    {
        if(actor==null||ActorValue(actor,"model_component_bind_transform",default).VariantType!=Variant.Type.Transform3D||ActorValue(actor,"model_component_source","").AsString().Length==0)return false;
        string instance=ActorValue(actor,"model_component_instance_id","").AsString(),component=ActorValue(actor,"model_component_id","").AsString();if(instance.Length==0||component.Length==0)return false;
        if(!_instances.ContainsKey(instance))
        {
            if(_instances.Count>=64)foreach(Variant id in _instances.Keys.ToArray())if(!_instances[id].AsGodotDictionary().Any(pair=>_actor(pair.Value.AsGodotDictionary())!=null))_instances.Remove(id);
            _instances[instance]=new Settings();
        }
        var entries=_instances[instance].AsGodotDictionary();var previous=Value(entries,component,new Settings()).AsGodotDictionary();
        var actorRef=GodotObject.WeakRef(actor)??throw new InvalidOperationException("The actor is no longer available.");Variant runtimeRef=runtime!=null?Variant.From(GodotObject.WeakRef(runtime)!):Value(previous,"runtime",default);
        entries[component]=new Settings{["actor"]=actorRef,["runtime"]=runtimeRef};return true;
    }
    public Resource? _actor(Settings entry)
    {
        var runtimeRef=Value(entry,"runtime",default).As<WeakRef>();if(runtimeRef!=null){var runtime=runtimeRef.GetRef().As<Node>();if(runtime==null||runtime.IsQueuedForDeletion())return null;}
        var actor=entry["actor"].As<WeakRef>().GetRef().As<Resource>();return actor!=null&&ScriptType(actor,"res://scripts/actors/core/actor_data.gd")?actor:null;
    }
    public bool refresh(Resource? actor,string path) {lock(_state.Sync){return refresh_locked(actor,path);}}
    private bool refresh_locked(Resource? actor,string path)
    {
        if(actor==null||_path(ActorValue(actor,"model_component_source","").AsString())!=_path(path)||!register_actor(actor,null))return false;
        var values=actor.Get("values").AsGodotDictionary();if(actor.Get("type_id").AsString()=="skeleton_rig"||values.ContainsKey(new StringName("model_rig_bind_signature")))return false;
        var source=resolved_resource(path);if(source==null||!ScriptType(source,"res://Workspaces/ModelWorkspace/model_document.gd"))return false;
        var item=_documents.component(source,ActorValue(actor,"model_component_id","").AsString());if(item==null||item.Get("parent_id").AsString()!=ActorValue(actor,"model_component_bind_parent",item.Get("parent_id")).AsString())return false;
        var previous=_documents.transform_values(ActorValue(actor,"model_component_bind_transform",default).AsTransform3D());var desired=_documents.transform_values(item.Get("transform").AsTransform3D());bool changed=false;
        foreach(var pair in desired)
        {Variant current=Value(values,pair.Key,previous[pair.Key]);var value=_reconcile(actor,previous[pair.Key],pair.Value,current,new[]{pair.Key.AsString()});if(!_same(value,current)){values[pair.Key]=value;changed=true;}}
        var mapping=new Settings();var instance=_instances[ActorValue(actor,"model_component_instance_id","").AsString()].AsGodotDictionary();foreach(Variant id in instance.Keys.ToArray()){var linked=_actor(instance[id].AsGodotDictionary());if(linked==null)instance.Remove(id);else mapping[id]=linked.Get("id");}
        var oldStructure=_mapped_structure(ActorValue(actor,"model_component_bind_structure",new Settings()).AsGodotDictionary(),mapping);var nextStructure=_mapped_structure(item.Get("structural").AsGodotDictionary(),mapping);
        foreach(var pair in nextStructure)
        {Variant previousValue=Value(oldStructure,pair.Key,default),current=Value(values,pair.Key,previousValue),value=_reconcile(actor,previousValue,pair.Value,current,new[]{pair.Key.AsString()});if(!_same(value,current)){values[pair.Key]=value;changed=true;}}
        values[new StringName("model_component_bind_transform")]=item.Get("transform");values[new StringName("model_component_bind_structure")]=item.Get("structural").AsGodotDictionary().Duplicate(true);return changed;
    }
    public Settings _mapped_structure(Settings settings,Settings mapping)
    {
        var result=settings.Duplicate(true);var connections=Value(result,new StringName("structure_connections"),new Settings()).AsGodotDictionary();
        foreach(var pair in connections){var link=pair.Value.AsGodotDictionary();link["target"]=Value(mapping,Value(link,"target","").AsString(),"");}
        var assembly=new StringName("structure_assembly");if(result.TryGetValue(assembly,out var id))result[assembly]=Value(mapping,id.AsString(),"");return result;
    }
    public Variant _reconcile(Resource actor,Variant old,Variant next,Variant current,string[] path)
    {
        foreach(Variant trackValue in actor.Get("animation_tracks").AsGodotArray())
        {string[] track=trackValue.As<Resource>().Get("path").AsStringArray();if(track.Length>path.Length)continue;bool matches=true;for(int index=0;index<track.Length;index++)matches&=track[index]==path[index];if(matches)return current;}
        if(old.VariantType==Variant.Type.Dictionary&&next.VariantType==Variant.Type.Dictionary&&current.VariantType==Variant.Type.Dictionary)
        {
            var original=old.AsGodotDictionary();var nextValues=next.AsGodotDictionary();var present=current.AsGodotDictionary();var result=present.Duplicate(true);
            foreach(var pair in nextValues)
            {if(!original.ContainsKey(pair.Key)&&!present.ContainsKey(pair.Key)){result[pair.Key]=Copy(pair.Value);continue;}if(!present.ContainsKey(pair.Key))continue;result[pair.Key]=_reconcile(actor,Value(original,pair.Key,default),pair.Value,present[pair.Key],path.Append(pair.Key.AsString()).ToArray());}return result;
        }
        return _same(old,current)?Copy(next):current;
    }
    private static Variant Copy(Variant value)=>ActorData.copy_value(value);
    public bool _same(Variant one,Variant two)
    {
        if(one.VariantType!=two.VariantType)return false;
        return one.VariantType switch
        {
            Variant.Type.Vector3=>one.AsVector3().IsEqualApprox(two.AsVector3()),Variant.Type.Basis=>one.AsBasis().IsEqualApprox(two.AsBasis()),Variant.Type.Transform3D=>one.AsTransform3D().IsEqualApprox(two.AsTransform3D()),Variant.Type.Float=>Mathf.IsEqualApprox(one.AsDouble(),two.AsDouble()),
            Variant.Type.Dictionary=>one.AsGodotDictionary().RecursiveEqual(two.AsGodotDictionary()),Variant.Type.Array=>one.AsGodotArray().RecursiveEqual(two.AsGodotArray()),_=>one.Equals(two)
        };
    }
}
