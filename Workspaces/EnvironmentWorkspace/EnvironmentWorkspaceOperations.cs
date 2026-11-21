using Godot;
using System;
using System.Globalization;
using Settings=Godot.Collections.Dictionary;
using GArray=Godot.Collections.Array;

public partial class EnvironmentWorkspaceOperations : RefCounted
{
    private readonly EnvironmentDocumentOperations _documents=new();
    private readonly ModelDocumentOperations _models=new();
    private readonly TerrainDataOperations _terrain=new();
    private readonly EnvironmentRuntimeOperations _runtime=new();
    private static RefCounted Session(Control owner)=>owner.Get("session").As<RefCounted>();
    private static Resource Document(RefCounted session)=>session.Get("document").As<Resource>();
    private static GArray Jobs(Control owner)=>owner.Get("_generation_jobs").AsGodotArray();
    private static Settings State(Control owner,string field)=>owner.Get(field).AsGodotDictionary();
    private static Variant Get(Settings values,string key,Variant fallback=default)=>values.TryGetValue(key,out var value)?value:fallback;
    private static void Status(Control owner,string text)=>owner.Get("status").As<Label>().Text=text;
    public void regenerate_terrain(Control owner,string id,Settings settings,bool resetEdits,bool derivedOnly)
    {
        var session=Session(owner);var terrain=_documents.terrain(Document(session),id);if(terrain==null)return;if(Math.Max(terrain.Get("resolution").AsInt32(),Get(settings,"resolution",terrain.Get("resolution")).AsInt32())<129&&terrain.Get("erosion").AsGodotArray().Count==0&&terrain.Get("caves").AsGodotArray().Count==0&&terrain.Get("hydrology").As<Resource>()==null&&terrain.Get("biomes").As<Resource>()==null&&!settings.ContainsKey("biomes")&&!settings.ContainsKey("hydrology")&&!settings.ContainsKey("erosion")&&!settings.ContainsKey("caves")){session.Call("regenerate_terrain",id,settings,resetEdits);return;}cancel_generation(owner,false);State(owner,"_failed_volumes").Remove(id);var job=new EnvironmentGenerationJob();Jobs(owner).Add(new Settings {["job"]=job,["session"]=session,["id"]=id,["source"]=terrain,["signature"]=_terrain.signature(terrain),["derived_only"]=derivedOnly});job.start(terrain,settings,resetEdits);owner.Get("_generation_cancel").As<Button>().Show();Status(owner,"Generating terrain…");
    }
    public void cancel_generation(Control owner,bool suspendWorlds)
    {
        if(suspendWorlds)GD.Load<GDScript>("res://Workspaces/EnvironmentWorkspace/world/world_dependencies.gd").Call("suspend",owner);var session=Session(owner);session.Call("_invoke_pending_source_cancel");owner.Get("_terrain_bake").As<RefCounted>()?.Call("cancel");foreach(var value in Jobs(owner)){var entry=value.AsGodotDictionary();entry["job"].As<EnvironmentGenerationJob>().cancel();if(entry["session"].As<RefCounted>()==session)State(owner,"_failed_volumes")[entry["id"]]=entry["signature"];}var renderer=owner.Get("canvas").As<Control>().Get("renderer").As<Node3D>();_runtime.cancel_scatter_generation(renderer);owner.Get("_generation_cancel").As<Button>().Hide();
    }
    public void poll_generation(Control owner)
    {
        var jobs=Jobs(owner);for(int index=jobs.Count-1;index>=0;index--)
        {
            var entry=jobs[index].AsGodotDictionary();var job=entry["job"].As<EnvironmentGenerationJob>();if(!job.complete()){if(!job.cancelled())Status(owner,"Generating terrain · "+Math.Round(job.progress()*100,MidpointRounding.AwayFromZero).ToString(CultureInfo.InvariantCulture)+"%");continue;}job.collect();jobs.RemoveAt(index);if(job.cancelled())continue;var target=entry["session"].As<RefCounted>();if(job.error.Length>0){if(target==Session(owner))State(owner,"_failed_volumes")[entry["id"]]=entry["signature"];Status(owner,job.error);continue;}string id=entry["id"].AsString();var source=_documents.terrain(Document(target),id);if(target!=Session(owner)||source!=entry["source"].As<Resource>()||source==null||_terrain.signature(source)!=entry["signature"].AsInt64()){Status(owner,"Generation discarded because its terrain changed.");continue;}bool derived=Get(entry,"derived_only",false).AsBool();if(!derived)target.Call("begin");var document=Document(target);document.Get("component_settings").AsGodotDictionary()[id].AsGodotDictionary()["terrain"]=job.terrain!=null?Variant.From(job.terrain):default;_models.component(document,id)!.Set("mesh",job.mesh!=null?Variant.From(job.mesh):default);if(derived){target.Set("dirty",true);target.Set("revision",target.Get("revision").AsInt64()+1);target.EmitSignal("changed");}else target.Call("commit","Generate terrain");Status(owner,"Terrain generated in "+job.elapsed_ms.ToString("F1",CultureInfo.InvariantCulture)+" ms");
        }
        owner.Get("_generation_cancel").As<Button>().Visible=jobs.Count>0;
    }
    public void exit_tree(Control owner)
    {
        cancel_generation(owner,true);foreach(string name in new[]{"world_recipe_job","world_site_job"})if(owner.HasMeta(name)){var job=owner.GetMeta(name).As<RefCounted>();if(job!=null){job.Call("cancel");job.Call("collect");}}var jobs=Jobs(owner);foreach(var value in jobs)value.AsGodotDictionary()["job"].As<EnvironmentGenerationJob>().collect();jobs.Clear();
    }
}
