using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentActorOperations : RefCounted
{
    private readonly EnvironmentRuntimeOperations _runtime=new();
    private readonly EnvironmentDocumentOperations _documents=new();
    private readonly ModelDocumentOperations _models=new();
    private readonly ModuleLinkOperations _links=new();
    private readonly EnvironmentBuildingStreamOperations _buildings=new();
    private static Variant Get(Settings values,Variant key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static Node3D? Content(Node3D owner)=>owner.Get("content").As<Node3D>();
    private static Resource? Document(Node3D owner)=>owner.Get("source_document").As<Resource>();
    private static GArray Jobs(Node3D owner)=>owner.Get("_source_jobs").AsGodotArray();
    private static GDScript Assets()=>GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_assets.gd");
    private static bool Type(Resource value,string path)
    {var script=value.GetScript().As<Script>();while(script!=null){if(script.ResourcePath==path||script.ResourcePath==LegacyResourceLoader.NativeScriptPath(path))return true;script=script.GetBaseScript();}return false;}
    public void attach_world(Node3D owner)=>EnvironmentWorldOverride.Attach(owner);
    public void ready(Node3D owner)
    {
        var content=GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/environment_runtime.gd").New().As<Node3D>();owner.Set("content",content);owner.AddChild(content);owner.AddToGroup("environment_asset_actors");owner.AddToGroup("actor_shader_runtimes");EnvironmentWorldOverride.Attach(owner);var actor=owner.Get("actor").As<Resource>();if(actor!=null){var path=actor.Call("get_value",new StringName("environment_path"), "");if(path.VariantType==Variant.Type.String)load_source(owner,path.AsString());}
    }
    public bool physics_geometry_ready(Node3D owner,bool needPhysics)=>Content(owner)!=null&&Jobs(owner).Count==0&&_runtime.geometry_ready(Content(owner)!,needPhysics);
    public string physics_geometry_error(Node3D owner)
    {string error=owner.Get("error").AsString();if(error.Length>0)return error;var content=Content(owner);return content!=null?_buildings.failure(content.Get("building_stream").As<RefCounted>()):"Environment runtime is unavailable.";}
    public Resource? environment_for_physics(Node3D owner)=>Jobs(owner).Count==0&&owner.Get("error").AsString().Length==0?Document(owner):null;
    public Settings environment_at(Node3D owner,Vector3 worldPosition,double time,Settings overrides)
    {var document=Document(owner);var climate=document?.Get("climate").As<Resource>();if(climate==null)return new Settings();var content=Content(owner);var position=content!=null?content.GlobalTransform.AffineInverse()*worldPosition:worldPosition;return climate.Call("evaluate",position,time,double.NaN,overrides.Count>0?overrides:owner.Get("climate_overrides").AsGodotDictionary()).AsGodotDictionary();}
    public void process(Node3D owner)
    {
        bool changed=false;var jobs=Jobs(owner);for(int index=jobs.Count-1;index>=0;index--){var entry=jobs[index].AsGodotDictionary();var job=entry["job"].As<EnvironmentGenerationJob>();if(!job.complete())continue;job.collect();jobs.RemoveAt(index);if(entry["generation"].AsInt64()!=owner.Get("_source_generation").AsInt64())continue;if(job.cancelled()){owner.Set("error","Environment preparation canceled.");continue;}if(job.error.Length>0){owner.Set("error",job.error);continue;}var document=Document(owner)!;document.Get("component_settings").AsGodotDictionary()[entry["id"]].AsGodotDictionary()["terrain"]=job.terrain!=null?Variant.From(job.terrain):default;_models.component(document,entry["id"].AsString())!.Set("mesh",job.mesh!=null?Variant.From(job.mesh):default);changed=true;}string error=owner.Get("error").AsString();if(jobs.Count==0&&error=="Preparing environment terrain…"){owner.Set("error", "");configure_source(owner);}else if(changed&&jobs.Count==0&&error.Length==0)configure_source(owner);
    }
    public void cancel_source_jobs(Node3D owner)
    {owner.Set("_source_generation",owner.Get("_source_generation").AsInt64()+1);var jobs=Jobs(owner);foreach(var value in jobs){var job=value.AsGodotDictionary()["job"].As<EnvironmentGenerationJob>();job.cancel();job.collect();}jobs.Clear();}
    public void evaluate_transform(Node3D owner,Settings values)
    {owner.Position=Get(values,new StringName("position"),Vector3.Zero).AsVector3();owner.RotationDegrees=Get(values,new StringName("rotation"),Vector3.Zero).AsVector3();owner.Scale=Get(values,new StringName("scale"),Vector3.One).AsVector3();}
    public void set_active(Node3D owner,bool active){owner.Set("active",active);if(Content(owner) is Node3D content)content.Visible=active;}
    public Settings water_at(Node3D owner,Vector3 point)=>owner.Get("active").AsBool()&&Document(owner)!=null?_documents.water_at(Document(owner)!,point,owner.GlobalTransform):new Settings();
    public void apply_remote_transform(Node3D owner,Transform3D source,bool move,bool rotate,bool resize)
    {var next=owner.GlobalTransform;if(move)next.Origin=source.Origin;var orientation=rotate?source.Basis.Orthonormalized():next.Basis.Orthonormalized();next.Basis=orientation*Basis.FromScale(resize?source.Basis.Scale:next.Basis.Scale);owner.GlobalTransform=next;}
    public void evaluate(Node3D owner,Settings values)
    {
        owner.Set("climate_overrides",new Settings {["climate_time"]=Get(values,new StringName("climate_time"),-1.0).AsDouble(),["climate_weather"]=Get(values,new StringName("climate_weather"),0).AsInt32(),["climate_intensity"]=Get(values,new StringName("climate_intensity"),-1.0).AsDouble(),["climate_clouds"]=Get(values,new StringName("climate_clouds"),-1.0).AsDouble(),["climate_temperature_offset"]=Get(values,new StringName("climate_temperature_offset"),0.0).AsDouble(),["climate_wind_add"]=Get(values,new StringName("climate_wind_add"),Vector3.Zero)});var content=Content(owner)!;bool lighting=Get(values,new StringName("include_lighting"),true).AsBool(),atmosphere=Get(values,new StringName("include_atmosphere"),false).AsBool(),changed=content.Get("include_lighting").AsBool()!=lighting||content.Get("include_atmosphere").AsBool()!=atmosphere;content.Set("include_lighting",lighting);content.Set("include_atmosphere",atmosphere);var value=Get(values,new StringName("environment_path"));string path=value.VariantType==Variant.Type.String?value.AsString():"";if(path!=owner.Get("source_path").AsString()||Document(owner)==null)load_source(owner,path);else if(changed)_runtime.sync_lighting(content);content.Visible=owner.Get("active").AsBool();
    }
}
